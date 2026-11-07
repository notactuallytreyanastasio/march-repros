# Docs vs compiler: monotonic clock reads under `cap pure`/`cap deterministic`, and `Js.Dom` from a no-`needs` module

`docs/capabilities.md` and the compiler disagree in two places, and a third case is a question about how far a documented exclusion reaches. Some or all of this may be a docs fix rather than a compiler fix.

## Cases

1. `cap pure` and `cap deterministic` accept `sys_uptime_ms()` and `System.monotonic_time()`. Docs lines 894 and 915 say the clock and monotonic-clock reads are banned, and line 188 puts monotonic time under `IO.Clock`. The source keeps this builtin ambient for `needs` on purpose (`lib/typecheck/typecheck_builtins.ml:868`). That comment does not mention these two caps. `needs ()` on the function does not reject the reads either.
2. `cap pure` and `cap deterministic` accept `File.read` and `DateTime.now()` once the module declares the matching `needs`. Line 894 speaks of builtins, so this may be intended. Lines 95 and 96 are broader.
3. With `--target js`, a module with no `needs` calls `Js.Dom` and `Js.Canvas`. Line 492 excludes `IO.Foreign` from the ceiling, and these stdlib modules declare it, so this is a question about whether the exclusion is meant to cover them. Line 669 says stdlib-mediated calls are caught. `--target js` is Tier 3 in `docs/platforms.md`, where nothing is promised.

Calls through user-defined modules are not reported here. Line 669 says "the compiler cannot force you to declare a capability that never appears in a signature and is never transitively required by an import", and the comment at `lib/typecheck/typecheck.ml:11277` says a user callee owns its own caps. `cap no_extern` is not reported either, because line 880 defines it per module.

## Controls

| Program | Shows |
|---|---|
| `control_pure_wallclock`, `control_deterministic_wallclock` | `unix_time_ms` in the same module is rejected |
| `control_pure_direct_builtin` | `file_read` in the same module as case 2 is rejected |
| `control_file_no_needs` | Case 3 shape with `File.read`, built with `--target js`, is rejected with `[cap_ceiling]` |
| `control_js_dom_fn_bound` | Case 3 under `needs ()` is rejected with `[cap_bound]` |
| `control_js_dom_narrow_grant` | Case 3 with `main` granted only `Cap(IO.Console)` is rejected with `[cap_grant_exceeded]` |

## Output

Main at b7c963d74:

```
$ ./run.sh
accepted          pure_monotonic
  direct, wrapped before the loop: 0 0; after: 214 214
rejected (ok)     control_pure_wallclock [pure_violation]
accepted          deterministic_monotonic
  direct, wrapped before the loop: 0 0; after: 232 232
rejected (ok)     control_deterministic_wallclock [deterministic_violation]
accepted          monotonic_fn_bound
  direct, wrapped before the loop: 0 0; after: 211 211
accepted          wrapper_with_needs
  File.read bytes, DateTime.now: 611 1794030757
  size of the file read: 611
rejected (ok)     control_pure_direct_builtin [pure_violation]
accepted          js_dom_no_needs (--target js; output has DOM and canvas call sites)
rejected (ok)     control_file_no_needs [cap_ceiling]
rejected (ok)     control_js_dom_fn_bound [cap_bound]
rejected (ok)     control_js_dom_narrow_grant [cap_grant_exceeded]
REPRODUCED
```

v0.7.0, where the two `needs ()` cases are skipped because that release has no per-function bounds:

```
$ MARCH_BIN=$HOME/.march/versions/v0.7.0/bin ./run.sh
accepted          pure_monotonic
  direct, wrapped before the loop: 0 0; after: 248 248
rejected (ok)     control_pure_wallclock [pure_violation]
accepted          deterministic_monotonic
  direct, wrapped before the loop: 0 0; after: 258 258
rejected (ok)     control_deterministic_wallclock [deterministic_violation]
skipped           monotonic_fn_bound (this compiler has no per-function bounds)
accepted          wrapper_with_needs
  File.read bytes, DateTime.now: 611 1794030776
  size of the file read: 611
rejected (ok)     control_pure_direct_builtin [pure_violation]
accepted          js_dom_no_needs (--target js; output has DOM and canvas call sites)
rejected (ok)     control_file_no_needs [cap_ceiling]
skipped           control_js_dom_fn_bound (this compiler has no per-function bounds)
rejected (ok)     control_js_dom_narrow_grant [cap_grant_exceeded]
REPRODUCED
```

## Source

Read at commit b7c963d74:

- `lib/typecheck/typecheck_modcaps.ml:359` and `:439`: `pure_banned` and `deterministic_banned` are derived from `builtin_cap_table`, which has no `sys_uptime_ms` row. `lib/tir/purity.ml:30` lists it as impure.
- `lib/typecheck/typecheck_modcaps.ml:376` and `:449`: `check_pure_module` and `check_deterministic_module` scan the module's own bodies for direct calls to banned names.
- `lib/caps/cap_ceiling.ml:12` and `:28`, and `lib/typecheck/typecheck.ml:11272` and `:11402`: `IO.Foreign` is filtered out of the ceiling. That this filter explains case 3 is inferred from the `File.read` contrast and the source. The compiler was not rebuilt without it.

## Run

```
./run.sh
MARCH_BIN=/path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding `march`, and may be relative. The default is `~/.march/versions/main-b7c963d74/bin`, then the `march` on `PATH`. Tested on macOS arm64.

The `--target js` programs are compiled and their output is searched for the call sites, but they are not run. The `needs ()` control is reported only with `--target js`: `march --check control_js_dom_fn_bound.march` exits 0, and `march --check --target js control_js_dom_fn_bound.march` exits 1.
