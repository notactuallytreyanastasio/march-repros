# `<`, `<=`, `>`, `>=` ignore the `Ord` impl on the native and JS backends

On the user types in `repro.march` (an enum, a record, a multi-constructor payload type, and a type with a hand-written `impl Ord`), the operators `<`, `<=`, `>` and `>=` typecheck and the interpreter answers correctly, but compiled code never calls the impl. Native sends the operands to `march_poly_compare`, which returns 0 for two heap values, and JS emits a bare `a < b` on objects. So strict comparisons are `false` and `<=`/`>=` are `true` whatever the values are, with no diagnostic about the comparison. `compare(a, b)` is correct on the same enum, payload and hand-written values. The impl being derived is not the cause: a hand-written `impl Ord` is ignored as well.

The generic path is also wrong: `lt(Red, Green)` with `fn lt(a, b) when Ord(a) do a < b end` is `false` on native and JS and `true` on the interpreter (`generic.march`), and multi-constructor payload types behave the same (`Ci(1) < Sq(1)` in `repro.march`).

`--target js` is listed as Tier 3 in `docs/platforms.md` (nothing promised); the JS results are included for completeness.

## Expected

Every backend agrees with `compare(a, b) <op> 0`, which is what the interpreter prints (`expected.txt`):

```
Red < Green     true
Green > Red     true
Green <= Red    false
Red >= Green    false
p < q           true
Small < Large   true
Ci(1) < Sq(1)   true
Ci(1) >= Sq(1)  false
```

## Actual

Native and JS, on main `b7c963d74` and on v0.7.0 (macOS arm64, node v26.13.0):

```
Red < Green     false
Green > Red     false
Green <= Red    true
Red >= Green    true
p < q           false
Small < Large   false
Ci(1) < Sq(1)   false
Ci(1) >= Sq(1)  true
```

`control.march` and `generic_control.march` ask the same questions through `compare(a, b) <op> 0` and are correct on all three backends. That is also the workaround, with one limit: `Point` is left out of `control.march` because `compare` on a derived record with `Int` fields does not build on JS.

Two related native symptoms. `run.sh` checks each and reports it on its own `related symptom` line, but neither decides the verdict:

- `newtype.march`: a single-constructor, single-field type has no heap cell, so `march_poly_compare` compares the raw payload. `Wrap(1) < Wrap(2)` is `true` natively, `false` on the interpreter, and `compare` is 0 on both.
- `unboxed.march`: `Pair(1, 1) < Pair(1, 2)` on `type Pair = Pair(Int, Int)` fails the native build. This is the full error on main; the pid in the file name varies, and on v0.7.0 the line number is 635:

  ```
  unboxed.68075.tmp.ll:647:24: error: '%ld5' defined with type '%ub.Pair = type { i64, i64 }' but expected 'i64'
    647 |   %cmp7 = icmp slt i64 %ld5, %ld6
        |                        ^
  1 error generated.
  march: clang failed (exit 1)
  ```

## Why this looks like a bug and not a limitation

- `docs/refinement-types.md:5231`, in the termination section, says "`<`, `<=`, `>`, `>=`, `compare` run `Ord`".
- `docs/types.md:699` lists `<` `>` `<=` `>=` for "any `Ord`". Its parenthetical names only `Int`, `Float` and `String`, but the typechecker accepts these operators on user types: without an impl, `Rood < Bloo` on `type Hue = Rood | Bloo` is rejected with "`Hue` does not implement interface `Ord`"

## Not a bug: derived `Ord` ignores variant payloads

`compare(Wrap(1), Wrap(2))` being 0, and the interpreter's `Wrap(1) < Wrap(2)` being `false`, follow from `specs/lang/surface-syntax.md`, "Derived `Ord`/`Hash` ignore constructor payloads", which calls this intentional. This repro does not report that. `Ci(1) < Sq(1)` is unaffected by that rule, because the constructors differ.

## Where it happens

Read from the source at `b7c963d74`, and checked against `--dump-tir`, `--emit-llvm` and the emitted JS:

- `lib/tir/mono.ml:826`: `<` and friends are rerouted through `compare` for tuples only. The comment above it describes the same failure for tuples: "every tuple `<` was false".
- `lib/tir/llvm_emit_arith.ml:252`: other pointer operands call `march_poly_compare`.
- `runtime/march_runtime.c:1718`: `return 0;  /* structural order needs static type info unavailable here */`
- `lib/tir/js_emit.ml:307`: `<` maps straight to the JS operator.
- `lib/eval/eval_runtime.ml:828`: the interpreter looks up the `Ord` impl, which is why it is right.

The `Pair` build failure has no root cause assigned here.

## Run

```
./run.sh
```

`MARCH_BIN` selects a toolchain's `bin` directory. Without it, `run.sh` uses `~/.march/versions/main-b7c963d74/bin` if present and otherwise `march` from `PATH`. `node` must be on `PATH`. The last line is `REPRODUCED` or `NOT REPRODUCED`: `REPRODUCED` means every control is correct on all three backends, the interpreter is correct on `repro.march` and `generic.march`, and a native or JS build of either one succeeds and prints the wrong answer.

Output on main `b7c963d74`. On v0.7.0 only the `unboxed` error line differs, in its pid and line number (635):

```
control interp: ok
control native: ok
control js: ok
generic_control interp: ok
generic_control native: ok
generic_control js: ok
--- repro: interpreter
Red < Green     true
Green > Red     true
Green <= Red    false
Red >= Green    false
p < q           true
Small < Large   true
Ci(1) < Sq(1)   true
Ci(1) >= Sq(1)  false
--- repro: native
Red < Green     false
Green > Red     false
Green <= Red    true
Red >= Green    true
p < q           false
Small < Large   false
Ci(1) < Sq(1)   false
Ci(1) >= Sq(1)  true
--- repro: js
Red < Green     false
Green > Red     false
Green <= Red    true
Red >= Green    true
p < q           false
Small < Large   false
Ci(1) < Sq(1)   false
Ci(1) >= Sq(1)  true
--- generic: interpreter
lt(Red, Green)  true
--- generic: native
lt(Red, Green)  false
--- generic: js
lt(Red, Green)  false
--- newtype: interpreter
compare         0
Wrap(1) < Wrap(2) false
--- newtype: native
compare         0
Wrap(1) < Wrap(2) true
related symptom newtype: present
--- unboxed: interpreter
false
--- unboxed: native
BUILD FAILED
unboxed.57420.tmp.ll:647:24: error: '%ld5' defined with type '%ub.Pair = type { i64, i64 }' but expected 'i64'
related symptom unboxed: present
REPRODUCED
```
