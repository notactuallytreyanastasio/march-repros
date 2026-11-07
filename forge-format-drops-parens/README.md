# forge format drops parentheses around non-infix operands

`forge format` (and `march fmt`) removes the parentheses around an `if` used as an operand. The formatter only adds parentheses when an operand is itself an infix operator of lower precedence, so `1 + (if x > 0 do 1 else 0 end)` is printed as `1 + if x > 0 do 1 else 0 end`. The grammar does not accept that: `specs/lang/grammar.md` says `if`/`match`/`with` "must be parenthesized to appear as an operand". The formatter exits 0 and, when run on a project, overwrites the file with source that no longer parses.

## Expected

The parentheses are kept, and the formatted file still passes `march --check`.

## Actual

`repro.march` passes `march --check` before formatting. After formatting (main at b7c963d74):

```
4:    1 + if x > 0 do 1 else 0 end
-- SYNTAX ------------------------------ .out/repro.march
I got stuck here: [syntax_error]
4 |     1 + if x > 0 do 1 else 0 end
            ^^
```

`forge format --stdin` exits 0. v0.7.0 gives the same result.

`control.march` formats correctly: an `if` bound by `let`, and an infix operand, `2 * (y + 1)`, which keeps its parentheses.

## Related cases, same cause

The same missing check affects other operands. These are in `related/`, and `run.sh` prints them.

Formatted code that still compiles but gives a different result:

| File | Before | After | Output before | Output after |
| --- | --- | --- | --- | --- |
| `related/pipe.march` | `1 + (3 \|> double)` | `1 + 3 \|> double` | 7 | 8 |
| `related/callee.march` | `(if x > 0 do add1 else add1 end)(5)` | `if x > 0 do add1 else add1 end(5)` | 6 | 5 |

Source lost from the file: `related/match_operand.march` has a `match` operand. The inline printer has no real rendering for `match`, so `forge format` exits 0 and writes this over the file, with both arms gone:

```
mod Repro do

  fn pick(x : Int) : Int do
    1 + match ...
  end

end
```

A multi-statement `if` branch is lost the same way (`1 + if x > 0 do ... else 0 end`). The `match ...` loss is not limited to operands: `h(1, match x do ... end)` becomes `h(1, match ...)`, and tuple and list elements do too.

Other forms seen with the same drop: `(if ...) + 1`, `-(if ...)`, `!(if ...)`, `(a == b) == c`, `(fn y -> y)(1)`.

## Cause

In `lib/format/format.ml`, the infix case of `expr_inline` (lines 440-447) decides on parentheses with `expr_infix_prec`, which returns `None` for anything that is not a binary infix application, so `EIf`, `EMatch`, `ELam` and `EPipe` operands are never wrapped. The `negate` and `not` cases (448-455) use `is_infix_app` and have the same gap, and the call case (456) prints the callee with no parentheses. `(a == b) == c` loses its parentheses because `la` uses `pa < p`, while `expr_cmp` is non-associative. The parser keeps no parenthesis node, so the formatter has to work out where they are needed.

The lost source comes from the placeholders at lines 466 (`EBlock _ -> "..."`) and 474 (`EMatch _ -> "match ..."`), which are reached because `is_multiline` (line 538) follows only trailing lambdas in a call, so it does not see a `match` inside an infix application or a call argument.

## Run

```sh
./run.sh
MARCH_BIN=/path/to/march/bin ./run.sh
```

`MARCH_BIN` defaults to `~/.march/versions/main-b7c963d74/bin`. The last line is `REPRODUCED` or `NOT REPRODUCED`, decided from `repro.march` and `control.march` only.
