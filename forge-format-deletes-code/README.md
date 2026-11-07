# forge format replaces code with a literal `...`

`forge format` (and `march fmt`) overwrite valid source with the placeholder text `...` for several ordinary expression shapes: every `match do` (the cond form), and any multi-statement lambda, `if` branch block or `match` that is printed through the single-line renderer, such as inside a list literal, as a non-last call argument, or as an `if` bound by `let` or used as a match arm. The original code is gone from the file. The command exits 0 and prints `formatted <file>`, and the file no longer parses, so without version control the deleted code cannot be recovered.

## Expected

Formatting keeps the program. The output still parses and contains the original `match do` arms and lambda or block bodies.

## Actual

Input (`cases/cond_body.march`):

```
mod X do
  fn f(x : Int) : Int do
    match do
      x > 0 -> 1
      true -> 2
    end
  end
end
```

The same file after `forge format`, which exits 0:

```
mod X do

  fn f(x : Int) : Int do
    match do ... end
  end

end
```

`march check` on the result:

```
I got stuck here: [syntax_error]

4 |     match do ... end
                 ^
```

Output of `./run.sh`. Each indented line is what replaced the code in that file:

```
== forge format
exit code: 0
== cases (should be damaged if the bug is present)
cond_body                    placeholder=yes checks_after=no
        match do ... end
if_block_in_let              placeholder=yes checks_after=no
        let r = if x > 0 do ... else 2 end
if_block_in_match_arm        placeholder=yes checks_after=no
        0 -> if x > 0 do ... else 2 end
lambda_call_in_list          placeholder=yes checks_after=no
        [List.map(xs, fn x -> ...)]
lambda_not_last_arg          placeholder=yes checks_after=no
        h(fn x -> ..., n)
match_in_list                placeholder=yes checks_after=no
        [match ...]
== controls (should survive)
if_block_as_statement        placeholder=no  checks_after=yes
lambda_call_no_list          placeholder=no  checks_after=yes
match_in_let                 placeholder=no  checks_after=yes
match_with_subject           placeholder=no  checks_after=yes
REPRODUCED
```

Every file in `cases/` and `control/` passes `march check` before formatting. Reproduced on main at b7c963d74 and on v0.7.0, macOS arm64.

The controls are the nearest variants that survive: the same lambda call outside the list, the same `if` as a statement, a `match` with a subject, and a `match` bound by `let`.

## Cause

Line numbers are for `lib/format/format.ml` at b7c963d74.

- `expr_inline` returns summary strings instead of source for several nodes: `EBlock` at line 466, `EMatch` at line 474, `ECond` at line 518. `ELetFn`, `ELetQ` and `ELetStar` at lines 506-511 have the same kind of summary.
- `is_multiline` (line 538) decides whether an expression avoids `expr_inline`. It has no `ECond` case and does not look inside `EIf`, tuples, records, list elements, or call arguments other than the last, so these shapes take the inline path, for example at lines 578, 641 and 757.
- `emit_stmt` has no `ECond` case, so `match do` always reaches the fallback at line 641.
- `march fmt` writes the result without re-parsing it (`bin/main.ml`, `fmt_file` and `run_fmt`).

The trailing-lambda shape was fixed on 2026-07-13. `specs/progress_through_july_2026.md` calls the `EBlock` string "a stub meant only for terse `EMatch`/`ELetFn`/etc. summaries used in *other* diagnostic contexts, never meant to reach formatter output". The regression helper in `test/test_fmt.ml` only searches for `-> ...`, so it would not catch `match do ... end`, `do ... else`, or `[match ...]`.

## Run

```sh
./run.sh                                        # main toolchain by default
MARCH_BIN=~/.march/versions/v0.7.0/bin ./run.sh # any bin dir holding forge and march
```

`run.sh` formats copies in a temporary `.work/` project and removes it afterwards, so the files in `cases/` are not changed. The last line is `REPRODUCED` or `NOT REPRODUCED`.

Do not run `forge format` or `march fmt` directly on `cases/`: it will destroy them.
