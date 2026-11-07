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

| Repro | Problem |
|---|---|
| [`capability-ceiling-misses-foreign`](capability-ceiling-misses-foreign/) | Docs vs compiler: `cap pure`/`cap deterministic` accept monotonic clock reads; `Js.Dom` passes a no-`needs` module |
| [`forge-format-deletes-code`](forge-format-deletes-code/) | forge format / march fmt overwrite valid code with a literal "..." |
| [`forge-format-drops-parens`](forge-format-drops-parens/) | forge format drops parens around if/match/pipe operands, breaking or changing code |
| [`install-sh-sha256sum-macos`](install-sh-sha256sum-macos/) | install.sh fails checksum verification on macOS when Apple's /sbin/sha256sum is first on PATH |
| [`js-float-literal-truncation`](js-float-literal-truncation/) | --target js emits Float literals with 12 significant digits |
| [`js-module-let-closure`](js-module-let-closure/) | --target js: module-level let outside the entry module reads as a closure object |
| [`js-test-blocks-run-zero`](js-test-blocks-run-zero/) | march --target js --test compiles test blocks but never runs them, exits 0 |
| [`missing-output-dir-ice`](missing-output-dir-ice/) | march --target js reports an unwritable -o path as an internal compiler error |
| [`native-none-float-field-segfault`](native-none-float-field-segfault/) | Native: let-bound None used as Option(Float) segfaults at address 0x8 |
| [`native-record-eq-shared-helper`](native-record-eq-shared-helper/) | Compiled == on records shares one __march_eq_Ptr across all record types |
| [`negate-shadow-recursion`](negate-shadow-recursion/) | JS backend ignores a user fn named negate or not, unless it gets inlined |
| [`ord-operators-ignored`](ord-operators-ignored/) | `<`, `<=`, `>`, `>=` ignore the Ord impl on native and JS backends |
| [`record-literal-paren-application`](record-literal-paren-application/) | A `(` line after `}`, `do ... end` or an interpolated string still parses as a call |
| [`target-float-divergence`](target-float-divergence/) | string_to_float accepts a different grammar on --target js (inf, nan, "") |
