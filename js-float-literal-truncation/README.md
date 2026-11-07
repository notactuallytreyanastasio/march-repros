# Float literals lose precision on `--target js`

With `--target js`, any `Float` value that reaches the emitter as a literal is printed with 12 significant digits, so the JS program runs with a different double than the one in the source. This covers source literals with more than 12 significant digits, `Math.pi()`, `Math.tau()`, and anything `opt.fold` computes at compile time, such as `1.0 /. 240.0`. Nothing warns about it, and the interpreter and native builds are correct. Values that fit in 12 digits, and values computed at run time, are unaffected. `float_to_string` also prints 12 digits, so printing a value usually hides the error; `repro.march` compares against `string_to_float` instead.

## Expected

The same result as the interpreter and `--compile`:

```
source literal: exact
Math.pi: exact
Math.tau: exact
folded 1.0 /. 240.0: exact
sin(pi): 1.22464679915e-16
```

## Actual

`march --target js`, run under node, on main b7c963d74 and on v0.7.0:

```
source literal: WRONG
Math.pi: WRONG
Math.tau: WRONG
folded 1.0 /. 240.0: WRONG
sin(pi): -2.0682310711e-13
```

The emitted JS:

```js
  check("source literal", 3.14159265359, "3.141592653589793");
  check("Math.pi", 3.14159265359, "3.141592653589793");
  check("Math.tau", 6.28318530718, "6.283185307179586");
  check("folded 1.0 /. 240.0", 0.00416666666667, "0.004166666666666667");
```

With `--disable-pass opt.fold`, only the folded value recovers, because the division moves to run time:

```
source literal: WRONG
Math.pi: WRONG
Math.tau: WRONG
folded 1.0 /. 240.0: exact
sin(pi): -2.0682310711e-13
```

`control.march` uses a short literal and a run-time division, and is correct on JS:

```
short literal: exact
runtime 1.0 /. 240.0: exact
```

## Non-finite literals, same line

The same line also breaks non-finite values that `opt.fold` computes. These programs use overflow, not division by zero: `x` is a literal of 1 followed by 308 zeros, multiplied by `10.0` (the lexer has no exponent form).

| File | Printed expression | Interpreter, `--compile`, `--target js --disable-pass opt.fold` | `--target js` emits |
|---|---|---|---|
| `overflow_inf.march` | `x` | `inf` | `inf.0` |
| `overflow_neg_inf.march` | `0.0 -. x` | `-inf` | `-inf.0` |
| `overflow_nan.march` | `x -. x` | `nan` | `nan.0` |

With folding on, none of the three modules load under node. Output from `run.sh` on main; the first line of node's error, a local file path, is left out, and the `$t` names differ on v0.7.0:

```
--- overflow_inf
interpreter: inf
--target js --disable-pass opt.fold: inf
--target js:
    const $t45517 = march_float_to_string(inf.0);
                                          ^^^

SyntaxError: missing ) after argument list
--- overflow_neg_inf
interpreter: -inf
--target js --disable-pass opt.fold: -inf
--target js:
    const $t45518 = march_float_to_string(-inf.0);
                                           ^^^

SyntaxError: missing ) after argument list
--- overflow_nan
interpreter: nan
--target js --disable-pass opt.fold: nan
--target js:
    const $t45518 = march_float_to_string(nan.0);
                                          ^^^

SyntaxError: missing ) after argument list
```

`--compile` needs clang, so `run.sh` does not run it. Run by hand, it printed `inf`, `-inf` and `nan` on both toolchains.

## Cause

`lib/tir/js_emit.ml:182`, in `emit_literal`, formats `LitFloat` with `string_of_float`, which OCaml defines as `valid_float_lexem (format_float "%.12g" f)`. For infinity and NaN it returns `inf` and `nan`; the emitter then appends `.0` because they contain neither `.` nor `e`.

Float patterns in the same file already use `%.17g` (`literal_tag_js`, line 356), with a comment explaining that it round-trips a double exactly. The LLVM backend emits the raw 64 bits (`lib/tir/llvm_emit.ml:424`). `%.17g` alone would still give `inf`, `-inf` and `nan`, so non-finite values need separate handling.

## Related: `1.0 /. 0.0`

This is a separate problem, noted here because changing `emit_literal` does not address it. `1.0 /. 0.0` is specified to stop with "division by zero" (`specs/lang/core-march.md:1049`). `fold_float_op` folds `/.` with no zero check (`lib/tir/fold.ml:29`), while `fold_int_op` returns `None` for a zero divisor (line 20). `div_zero.march` shows the effect, on main and v0.7.0:

| Build | Result |
|---|---|
| interpreter | stops with "division by zero" |
| `--compile --disable-pass opt.fold` | `march: runtime error: division by zero`, exit 1 |
| `--compile` | prints `inf`, exit 0 |
| `--target js --disable-pass opt.fold` | prints `inf`, exit 0 |
| `--target js` | emits `inf.0`, same SyntaxError |

`run.sh` does not cover this file.

## Run

```
./run.sh
MARCH_BIN=/path/to/march/bin ./run.sh
```

Needs `node`. `MARCH_BIN` defaults to `~/.march/versions/main-b7c963d74/bin`. The script uses the interpreter as the reference and prints `REPRODUCED` or `NOT REPRODUCED` on its last line. `march --version` prints 0.7.0 on main too, so the first line of the output names the toolchain directory.
