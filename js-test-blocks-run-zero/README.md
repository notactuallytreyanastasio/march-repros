# `march --target js --test` runs no tests and exits 0

`march --target js --test` accepts test blocks and writes a `.mjs` file, but the JS backend never calls the tests. A test that must fail compiles with exit 0, and `node` then prints nothing and exits 0, so a CI step using this command stays green whatever the tests do. The same test on the native target (`--compile --test`) reports the failure and exits 1. With a `main` in the file, the `.mjs` runs `main` and the test functions are removed from the output, so this is also silent. Separately, `--test` makes any program that prints fail to build for JS with ``builtin `cap_dict` has no JavaScript-target implementation``, although the same file builds and runs without `--test`.

`failing.march` is the whole bug:

```
mod Failing do
  test "must fail" do
    assert (1 + 1 == 3)
  end
end
```

`failing_with_main.march` adds an empty `main`. `prints.march` has no tests and only shows the `cap_dict` error.

## Expected

Either the `.mjs` runs the tests, reports the failure and exits non-zero, as the native test runner does, or the compiler rejects `--test` with `--target js`. The `--test` help says "use with --compile", and `--target js` implies `--compile`.

## Actual

Output from main at b7c963d74. The binary reports `march 0.7.0`.

```
march 0.7.0
== control: native --compile --test failing.march
F

1 failure(s):

FAIL: "must fail"
  -- TEST FAILURE --------------------------- failing.march

  The two sides of this `==` are not equal. [assert_failed]

  3 |     assert (1 + 1 == 3)
                  ^^^^^^^^^^

      left `1 + 1`
          2
          ^
      right
          3
          ^

Finished: 1 test, 1 failure
compile exit=0, run exit=1
== bug: --target js --test failing.march
compile exit=0, node exit=0, node output bytes=0
== bug: --target js --test failing_with_main.march
compile exit=0, node exit=0, node output bytes=0
== related: --target js prints.march (no --test)
compiled build/prints.mjs
ran main
== related: --target js --test prints.march
error: builtin `cap_dict` has no JavaScript-target implementation (called from main (prints.march:4)).
The compiled call would throw ReferenceError at runtime. Add a
mapping in lib/tir/js_emit.ml (+ runtime/march_runtime.mjs if it
needs a helper), or build a native/wasm target.
compile exit=1
control_ok=yes no_main_false_green=yes with_main_false_green=yes
REPRODUCED
```

Release v0.7.0 gives the same result: `REPRODUCED`, with the same JS lines. Only the native failure text differs (`assertion failed`).

## Cause

- `lib/tir/llvm_toplevel.ml:2179` builds the test-runner entry point from `tm_tests`. That is the only place that turns `tm_tests` into calls. `lib/tir/js_emit.ml` never reads `tm_tests`.
- `lib/tir/js_emit.ml:1820` emits a call to `main` only when one exists, so with no `main` the module has no entry call. `__march_test_0__` is defined in the `.mjs` but nothing calls it. Calling it by hand throws the expected test failure.
- With a `main`, `bin/main.ml:5861` prunes to what `main` reaches, so the test functions are dropped from the output.
- The `cap_dict` error comes from capability mocking, which `--test` turns on (`cap_mocking` in `bin/flags.ml`). `MARCH_CAP_DISPATCH=1` without `--test` gives the same error. `lib/tir/js_emit.ml` has no `cap_dict` mapping.

## Documentation

`--test` with `--target js` is neither documented as supported nor as unsupported. `docs/platforms.md` lists the JS target as experimental. `forge test` has no `--target` option, so this applies to calling `march` directly.

## Run

```
./run.sh
MARCH_BIN=/path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding the `march` binary. The default is `~/.march/versions/main-b7c963d74/bin`. It needs `node` and `clang`, and it removes its own build output. The last line is `REPRODUCED` or `NOT REPRODUCED`.
