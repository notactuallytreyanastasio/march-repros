# string_to_float accepts different inputs on the JS target

On `--target js`, `string_to_float` (and `String.to_float`, which wraps it) uses JavaScript's `Number()`, so it accepts different inputs from the interpreter and native builds. `"inf"`, `"-inf"` and `"nan"` give `None`, although `float_to_string` on that target prints those strings. Blank strings give `Some(0.)`.

This reaches the stdlib: `Toml` gets `inf` and `nan` from `string_to_float`, with `0.0` as the `None` fallback, so `x = inf` silently reads as `x = 0.` on JS.

`--target js` is Tier 3 in `docs/platforms.md`: "it may work partly or not at all, nothing is promised, and nothing about it holds back a release."

## Expected

`"inf"`, `"-inf"` and `"nan"` parse on JS, because `float_to_string` there emits them and `stdlib/toml.march` relies on them, and blank strings give `None`. No document defines the rest of the grammar, so whether the other rows below should match is a question for the maintainers.

## Actual

macOS arm64, node v26.13.0. Reproduced on main at b7c963d74 and on v0.7.0, with identical output. Columns are interpreter | native | js. This is the output of `./run.sh`.

```
== repro.march (interpreter | native | js)
[inf] -> Some(inf)|[inf] -> Some(inf)|[inf] -> None
[-inf] -> Some(-inf)|[-inf] -> Some(-inf)|[-inf] -> None
[infinity] -> Some(inf)|[infinity] -> Some(inf)|[infinity] -> None
[INF] -> Some(inf)|[INF] -> Some(inf)|[INF] -> None
[nan] -> Some(nan)|[nan] -> Some(nan)|[nan] -> None
[NaN] -> Some(nan)|[NaN] -> Some(nan)|[NaN] -> None
[] -> None|[] -> None|[] -> Some(0.)
[ ] -> None|[ ] -> None|[ ] -> Some(0.)
[tab] -> None|[tab] -> None|[tab] -> Some(0.)
[1.5 ] -> None|[1.5 ] -> None|[1.5 ] -> Some(1.5)
[0b11] -> None|[0b11] -> None|[0b11] -> Some(3.)
[0o17] -> None|[0o17] -> None|[0o17] -> Some(15.)
[0x1p3] -> Some(8.)|[0x1p3] -> Some(8.)|[0x1p3] -> None
[1_000] -> Some(1000.)|[1_000] -> None|[1_000] -> None
toml: { x = inf, y = nan }|toml: { x = inf, y = nan }|toml: { x = 0., y = 0. }
== control.march (interpreter | native | js)
[1.5] -> Some(1.5)|[1.5] -> Some(1.5)|[1.5] -> Some(1.5)
[-42.5] -> Some(-42.5)|[-42.5] -> Some(-42.5)|[-42.5] -> Some(-42.5)
[1e3] -> Some(1000.)|[1e3] -> Some(1000.)|[1e3] -> Some(1000.)
[.5] -> Some(0.5)|[.5] -> Some(0.5)|[.5] -> Some(0.5)
[5.] -> Some(5.)|[5.] -> Some(5.)|[5.] -> Some(5.)
[0x10] -> Some(16.)|[0x10] -> Some(16.)|[0x10] -> Some(16.)
[abc] -> None|[abc] -> None|[abc] -> None
[Infinity] -> Some(inf)|[Infinity] -> Some(inf)|[Infinity] -> Some(inf)
[-Infinity] -> Some(-inf)|[-Infinity] -> Some(-inf)|[-Infinity] -> Some(-inf)
toml: { x = 1.5 }|toml: { x = 1.5 }|toml: { x = 1.5 }
REPRODUCED
```

Inputs in `control.march` agree on all three targets: `1.5`, `-42.5`, `1e3`, `.5`, `5.`, `0x10`, `abc`, `Infinity`, `-Infinity`, and a TOML document with `x = 1.5`.

`"1_000"` is a smaller, separate difference: only the interpreter accepts it, so interpreter and native differ there too.

## Cause

Each target uses its host's parser:

- JS: `runtime/march_runtime.mjs:195`, `Number(s)` with `isNaN(n)` mapped to `None`. A genuine `"nan"` cannot be told apart from a failed parse. `Number` only spells infinity `Infinity`, reads an empty or blank string as 0, trims whitespace, accepts `0b`/`0o` prefixes and rejects hex floats.
- Interpreter: `lib/eval/eval_builtins.ml:1138`, OCaml `float_of_string`, which also allows `_` separators.
- Native: `runtime/march_runtime.c:11508`, `strtod`, requiring the whole string to be consumed.

The Toml fallback is at `stdlib/toml.march:490-510`.

I found no document that defines the accepted grammar. `specs/progress_through_july_2026.md:1277-1278` describes the builtin as `strtod` (native) / `float_of_string` (interpreter) backed and does not mention JS, so a host-defined grammar may be intended. In that case the fix may belong in `Toml`, although `float_infinity` and `float_nan` currently fail to compile on `--target js`. `docs/cookbook/dom.md:255-257` uses `string_to_float` on JS.

## Workaround

Callers can work around this, but `Toml` cannot be fixed from outside because its `string_to_float` calls are inside `stdlib/toml.march`. Before calling `string_to_float` on JS:

- Reject blank strings, not only `""`.
- Rewrite `inf` and `-inf` to `Infinity` and `-Infinity`, which parse on all three targets. This does not cover spellings such as `infinity` and `INF` unless they are rewritten too.
- No string parses to NaN on JS, because NaN is mapped to `None`. Special-case `nan` and compute it, for example `Infinity` minus `Infinity`.
- The other rows above (`0b11`, `0o17`, `0x1p3`, trailing whitespace) need the caller to validate the input's shape first.

## Run

Needs `node` on `PATH`. `MARCH_BIN` is the directory holding the `march` binary.

```
MARCH_BIN=/path/to/march/bin ./run.sh
```

The last line is `REPRODUCED` or `NOT REPRODUCED`.
