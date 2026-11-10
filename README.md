# March bug repros

Minimal, self-contained reproductions of bugs in the [March language](https://github.com/march-language/march), found while porting a game to it. Each directory has the smallest program that shows the problem, a working control where one makes sense, and a `run.sh` whose last line is `REPRODUCED` or `NOT REPRODUCED`.

Tested on March main at `b7c963d74` and on v0.7.0, on macOS arm64 with node v26.13.0.

## Running one

```sh
cd js-float-literal-truncation
MARCH_BIN=/path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding the `march` binary. `march --version` prints 0.7.0 for both builds tested, so it can't tell them apart. `install-sh-sha256sum-macos` ignores `MARCH_BIN` and needs network access.

## Repros

| Repro | Problem | Issue |
|---|---|---|
| [`capability-ceiling-misses-foreign`](capability-ceiling-misses-foreign/) | Docs vs compiler: `cap pure`/`cap deterministic` accept monotonic clock reads; `Js.Dom` passes a no-`needs` module | [march#1180](https://github.com/march-language/march/issues/1180) |
| [`forge-format-deletes-code`](forge-format-deletes-code/) | forge format / march fmt overwrite valid code with a literal "..." | [march#1174](https://github.com/march-language/march/issues/1174) |
| [`forge-format-drops-parens`](forge-format-drops-parens/) | forge format drops parens around if/match/pipe operands, breaking or changing code | [march#1175](https://github.com/march-language/march/issues/1175) |
| [`install-sh-sha256sum-macos`](install-sh-sha256sum-macos/) | install.sh fails checksum verification on macOS when Apple's /sbin/sha256sum is first on PATH | [march#1182](https://github.com/march-language/march/issues/1182) |
| [`js-float-literal-truncation`](js-float-literal-truncation/) | --target js emits Float literals with 12 significant digits | [march#1169](https://github.com/march-language/march/issues/1169) |
| [`js-module-let-closure`](js-module-let-closure/) | --target js: module-level let outside the entry module reads as a closure object | [march#1170](https://github.com/march-language/march/issues/1170) |
| [`js-test-blocks-run-zero`](js-test-blocks-run-zero/) | march --target js --test compiles test blocks but never runs them, exits 0 | [march#1176](https://github.com/march-language/march/issues/1176) |
| [`missing-output-dir-ice`](missing-output-dir-ice/) | march --target js reports an unwritable -o path as an internal compiler error | [march#1181](https://github.com/march-language/march/issues/1181) |
| [`native-none-float-field-segfault`](native-none-float-field-segfault/) | Native: let-bound None used as Option(Float) segfaults at address 0x8 | [march#1173](https://github.com/march-language/march/issues/1173) |
| [`native-record-eq-shared-helper`](native-record-eq-shared-helper/) | Compiled == on records shares one __march_eq_Ptr across all record types | [march#1171](https://github.com/march-language/march/issues/1171) |
| [`negate-shadow-recursion`](negate-shadow-recursion/) | JS backend ignores a user fn named negate or not, unless it gets inlined | [march#1177](https://github.com/march-language/march/issues/1177) |
| [`ord-operators-ignored`](ord-operators-ignored/) | `<`, `<=`, `>`, `>=` ignore the Ord impl on native and JS backends | [march#1172](https://github.com/march-language/march/issues/1172) |
| [`record-literal-paren-application`](record-literal-paren-application/) | A `(` line after `}`, `do ... end` or an interpolated string still parses as a call | [march#1179](https://github.com/march-language/march/issues/1179) |
| [`target-float-divergence`](target-float-divergence/) | string_to_float accepts a different grammar on --target js (inf, nan, "") | [march#1178](https://github.com/march-language/march/issues/1178) |
| [`lib-path-type-name-loads-module`](lib-path-type-name-loads-module/) | A shared type name loads unreferenced modules from `MARCH_LIB_PATH` | [march#1183](https://github.com/march-language/march/issues/1183) |
| [`float-add-zero-keeps-negative-zero`](float-add-zero-keeps-negative-zero/) | Compiled `x +. 0.0` keeps a negative zero on native and JS | [march#1185](https://github.com/march-language/march/issues/1185) |
| [`json-control-escape`](json-control-escape/) | Json.to_string leaves U+0000-U+001F (except \b\t\n\f\r) unescaped | [march#1193](https://github.com/march-language/march/issues/1193) |
| [`type-name-captured-across-modules`](type-name-captured-across-modules/) | A local type named like another module's type is substituted into that module's record fields (and can hang the build) | [march#1199](https://github.com/march-language/march/issues/1199) |
| [`float-to-int-out-of-range`](float-to-int-out-of-range/) | float_to_int, float_floor and friends return garbage for NaN, infinities and values outside Int's range | [march#1230](https://github.com/march-language/march/issues/1230) |
