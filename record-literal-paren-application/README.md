# A `(` line after `}`, `do ... end` or an interpolated string is parsed as a call

After #129 and #132, a line starting with `(` is a new statement when the previous line ends in an identifier, `)`, `]` or a literal: `token_filter.ml` retags that `(` as `LPAREN_STMT`, which the call rule does not accept. The retag is decided by a token list that omits `RBRACE`, `END` and `INTERP_END`, so after a record literal, a record update, a `do ... end` expression or an interpolated string, the next `(` line becomes an argument list.

- Records: `not_a_function` on the previous line, then `unbound_variable` for the binding if it is used afterwards. In a function with a `needs` bound there is also a `cap_bound` error about an untraceable function value.
- Interpolated strings: `not_a_function` on the previous line. In `interpolated_string.march` `s` is never used, so there is no `unbound_variable`.
- A `do ... end` block that evaluates to a function: no error. The function is called, in the interpreter and in a compiled binary.

This may already be known. See "Docs and history".

## Expected

Each `(` line is its own statement, as it is after `)`, `]`, an identifier or a literal.

- `record_literal.march`, `record_update.march`, `cap_bound.march`, `interpolated_string.march`: compile and print `2` or `3`.
- `do_block_silent.march`: prints only `end`.

## Actual

`march record_literal.march`, exit 1:

```
-- TYPE MISMATCH ------------------- record_literal.march

expected `Int` but got `()`. [type_mismatch]

5 |     let r = { x: 1 }
        ^^^^^^^^^^^^^^^^

    This is the declared return type of `f`.

    the expected type comes from here:

4 |   fn f() : Int do
      ^^^^^^^^^^^^^^^
    run `march --explain type_mismatch`


-- TYPE MISMATCH ------------------- record_literal.march

This is not a function — it has type `{ x : Int }`. [not_a_function]
I cannot apply it to arguments.

5 |     let r = { x: 1 }
                ^^^^^^^^



-- NAMING -------------------------- record_literal.march

I cannot find `r`. [unbound_variable]

6 |     (r.x + 1)
         ^



-- TYPE MISMATCH ------------------- record_literal.march

I cannot access field `x` because `r` has type `<error>`, which is not a record. [field_access_non_record]

6 |     (r.x + 1)
         ^^^
```

`march record_update.march` fails the same way, on a single-line `{ r with x: 2 }`.

`march interpolated_string.march`, exit 1:

```
-- TYPE MISMATCH -------------- interpolated_string.march

expected `Int` but got `()`. [type_mismatch]

5 |     let n = 1
        ^^^^^^^^^

    This is the declared return type of `f`.

    the expected type comes from here:

4 |   fn f() : Int do
      ^^^^^^^^^^^^^^^
    run `march --explain type_mismatch`


-- TYPE MISMATCH -------------- interpolated_string.march

This is not a function — it has type `String`. [not_a_function]
I cannot apply it to arguments.

6 |     let s = "n=${n}"
                ^^^^^^^^
```

`march cap_bound.march` on current main (b7c963d74), exit 1. This is the first of five errors; the other four are the same as for `record_literal.march`. `f` calls nothing:

```
-- CAPABILITY --------------------------- cap_bound.march

`f` is bounded by `needs ()`, but its body invokes a function value whose origin the capability analysis cannot trace (one taken from a record field, a list or a ref), so nothing can be charged for what that call does and the bound cannot be certified. [cap_bound]
help: pass the function in as a parameter or call it by name, or bound `f` by `needs IO`.

5 |   fn f() : Int needs () do
                   ^^^^^^^^
```

`march do_block_silent.march`, exit 0. A binary built with `march --compile do_block_silent.march -o do_block_silent` prints the same:

```
g called with: discarded
end
```

## Controls

The first four differ from the failing programs only in that the previous line ends in `)`.

| File | Prints |
|---|---|
| `control_record_literal.march` | `2` |
| `control_record_update.march` | `3` |
| `control_interpolated_string.march` | `2` |
| `control_do_block.march` | `end`, also when compiled |
| `control_other_endings.march` | `-10`, `7`, `2`, `3`, `4`, `5` |

`control_other_endings.march` has a `(` line after an int, an identifier, `]`, a plain string, `if ... end` and `match ... end`. The first two are the `(` examples from `specs/lang/surface-syntax.md`, with `identity` and `negate` defined in the file.

## Docs and history

- `specs/lang/surface-syntax.md:1251-1295` ("Newline-glom") documents this as a trap: "a `(...)` line is parsed as a call on the preceding expression". It gives the same workaround as below: "parenthesize/terminate the prior expression so the next line can't attach". So the remaining cases may be considered known.
- That passage dates from 6fa344e2a (2026-07-05), before #129. Its two `(` examples no longer glue. `specs/lang/grammar.md` §3.3 still says every newline outside a match body is swallowed and does not mention `LPAREN_STMT`. I only checked the `(` part of the passage, not its `-` and infix examples.
- 8efcc991a (#129, 2026-07-30), "a `(`-led statement no longer glues onto the previous line", enforces "the newline-separates-statements rule" for `(` after "a value-ending token" (identifiers, `)`, `]`).
- 3ff8c48e2 (#132, 2026-07-30) adds literals, because "the call rule takes an `expr_field`, which a bare literal also reduces to". Records, `do ... end` and interpolated strings also reduce to `expr_field`.
- `specs/2026-09-23-tree-sitter-grammar-sync-design.md:241` describes the rule as "`(` at the start of a line, after a complete expression".

This reads as an inconsistency in the #129 and #132 fixes. I found nothing that says whether these tokens were left out on purpose.

## Where

- `lib/parser/token_filter.ml:229` `is_value_ending` and `:245` `ends_expression`: neither lists `RBRACE`, `END` or `INTERP_END`.
- `lib/parser/token_filter.ml:662-669`: the `(` is only retagged when `ends_expression` holds for the previous token.
- `lib/parser/parser.mly:1994`: the call rule takes any `expr_field`, which includes records, `do ... end` and interpolated strings through `expr_atom`.

`if ... end` and `match ... end` are not `expr_atom`s, which is why they are not affected.

## Run

```
./run.sh
MARCH_BIN=path/to/march/bin ./run.sh
```

The last line is `REPRODUCED` or `NOT REPRODUCED`. Without `MARCH_BIN`, `run.sh` uses the `march` on `PATH` if the main-b7c963d74 install is absent. It checks the interpreter for every program, and `--compile` for `do_block_silent.march` and `control_do_block.march`.

Reproduced on current main (b7c963d74) and on v0.7.0 (macOS arm64). `march --version` prints 0.7.0 on both. v0.7.0 has no function-level `needs` bounds, so `cap_bound.march` is skipped there.
