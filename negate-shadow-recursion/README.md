# JS backend ignores a user `fn negate` or `fn not`

On the JS target, a call to an entry-module top-level `fn negate` compiles to the builtin negation instead of the user's function, so the function never runs. This covers both an explicit `negate(x)` and prefix `-x`, which the parser lowers to a call of `negate`. With a non-literal argument, a user `fn not` is ignored the same way, through `not(x)` and prefix `!x` (`not.march`). The program compiles without a diagnostic and silently computes something else; in these cases the interpreter and native binaries call the user's function. For `negate`, and for `not` with a non-literal argument, it only shows when the call survives to the emitter: if the optimizer inlines the function the result is correct, which is why the programs here have a `println` in the body and two call sites. Separately, `not <bool literal>` is folded by name before codegen with no user-function check (`lib/tir/fold.ml:53`, `lib/tir/simplify.ml:102`), so native ignores a user `fn not` for a literal argument too, while the interpreter calls it.

`--target js` is Tier 3 in `docs/platforms.md`, where nothing is promised.

This repro started from a report that "a user `fn negate` recurses forever, on native and JS". That report is only partly right; see [The original report](#the-original-report).

## Expected

All three backends agree. For `repro.march`:

```
called
a!
called
b!
```

For `prefix_minus.march`:

```
called
15
called
15
```

For `not.march`:

```
called
true
called
true
```

## Actual

Output of `./run.sh`, with lines joined by `|`. Identical on main (b7c963d74) and v0.7.0, macOS arm64, node v26.13.0.

```
repro
  interp: called|a!|called|b!
  native: called|a!|called|b!
  js:     NaN|NaN
prefix_minus
  interp: called|15|called|15
  native: called|15|called|15
  js:     -5|-5
not
  interp: called|true|called|true
  native: called|true|called|true
  js:     false|false
control_renamed
  interp: called|a!|called|b!
  native: called|a!|called|b!
  js:     called|a!|called|b!
control_nested
  interp: called|a!|called|b!
  native: called|a!|called|b!
  js:     called|a!|called|b!
reported (--check)
  exit 1: [non_tail_recursion]
tail_minus
  --check: exit 0, 0 bytes of diagnostics
  interp: exit 2: Fatal error: exception Stack overflow
  native: exit 142 after at most 20s (142 = killed by the limit)
  js:     exit 0: -2
explicit call dropped on JS: yes; prefix minus dropped on JS: yes; not dropped on JS: yes; controls correct: yes
REPRODUCED
```

`control_renamed.march` is `repro.march` with the function renamed. `control_nested.march` keeps the name `negate` in a nested module, where it has a qualified name. Both controls cover `negate`.

## Cause

`lib/tir/js_emit.ml:662-667`, in `emit_val_impl`, matches the callee's bare name (`"negate"`, `"not"` and others) and emits the operator, without asking whether a user function owns that name. For `repro.march` the generated code on main is `const $t45517 = (-"a");` (v0.7.0 emits the same line with the temp `$t44773`), and the calls in `main` do not use the emitted `function negate(s)`.

The native backend had the same bug and fixed it with an arm placed ahead of the builtin name arms. `lib/tir/llvm_emit.ml:1345-1372` (`shadows_dispatched_builtin`) says:

> Shadowing a builtin name with an entry-module top-level `fn` is a supported, regression-tested feature

## The original report

- `reported.march`, the program as reported, does not run anywhere. It is rejected with a `non_tail_recursion` error pointing at `-1.0`.
- The capture itself is by design: prefix minus resolves to whichever `negate` is in scope. `lib/refinecheck/refine_check.ml:9632-9634` says a user `fn negate` captures `-2` "in program code and in a predicate alike", and `test/test_refine_unfold.ml:935` pins it.
- So `tail_minus.march`, where `fn negate` is written as `-x`, is plain self-recursion. It passes `--check` silently because the tail self-call is accepted, as `fn f(x) do f(x) end` is. Native loops forever and the interpreter overflows its stack.
- JS does not recurse. It prints `-2`, which looks right only because of the bug above.

## Run

```
./run.sh
MARCH_BIN=path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding `march`; it may be relative. Without it, `run.sh` uses the pinned main toolchain if present, otherwise `march` on `PATH`.

Needs `node` and `perl`. The last line is `REPRODUCED` or `NOT REPRODUCED`. It takes under a minute, most of it `tail_minus` running until a 20-second limit.

To see the bug without `run.sh`, in any directory holding `repro.march`:

```
march repro.march
march --target js -o repro.mjs repro.march && node repro.mjs
```

The `-o` path must be in an existing directory.
