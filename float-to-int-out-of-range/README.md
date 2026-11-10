# Float to Int conversions return garbage outside Int's range

`float_to_int`, `float_truncate`, `float_floor`, `float_ceil` and `float_round` have no range check. For a Float outside Int's range [-2^62, 2^62), and for NaN and the infinities, every target returns a value and exits 0:

- The interpreter and native code print the same wrong numbers: `-1` for `1e20` and `+inf`, `0` for `-1e20`, `-inf` and NaN, and `-4611686018427387904` for `2^62`. The C runtime's `(int64_t)f` is undefined behaviour for these values. On arm64 it saturates to the int64 limits, and narrowing those to March's 63-bit Int gives `-1` and `0`. OCaml's `Float.to_int` does the same on this machine.
- `--target js` returns the JS number unchanged, so the "Int" can be `100000000000000000000`, `NaN` or `Infinity`.

Values inside the range agree on all three targets (`control.march`).

## Actual

macOS arm64, node v26.13.0. This is the output of `./run.sh`. It is identical on main at `7cd864dda`, on main at `b7c963d74` and on v0.7.0.

```
== repro.march on interp
1e20  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-1e20  to_int=0 truncate=0 floor=0 ceil=0 round=0
2^62  to_int=-4611686018427387904 truncate=-4611686018427387904 floor=-4611686018427387904 ceil=-4611686018427387904 round=-4611686018427387904
2^63  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-2^63  to_int=0 truncate=0 floor=0 ceil=0 round=0
nan  to_int=0 truncate=0 floor=0 ceil=0 round=0
inf  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-inf  to_int=0 truncate=0 floor=0 ceil=0 round=0
exit 0
== repro.march on native
1e20  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-1e20  to_int=0 truncate=0 floor=0 ceil=0 round=0
2^62  to_int=-4611686018427387904 truncate=-4611686018427387904 floor=-4611686018427387904 ceil=-4611686018427387904 round=-4611686018427387904
2^63  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-2^63  to_int=0 truncate=0 floor=0 ceil=0 round=0
nan  to_int=0 truncate=0 floor=0 ceil=0 round=0
inf  to_int=-1 truncate=-1 floor=-1 ceil=-1 round=-1
-inf  to_int=0 truncate=0 floor=0 ceil=0 round=0
exit 0
== repro.march on js
1e20  to_int=100000000000000000000 truncate=100000000000000000000 floor=100000000000000000000 ceil=100000000000000000000 round=100000000000000000000
-1e20  to_int=-100000000000000000000 truncate=-100000000000000000000 floor=-100000000000000000000 ceil=-100000000000000000000 round=-100000000000000000000
2^62  to_int=4611686018427388000 truncate=4611686018427388000 floor=4611686018427388000 ceil=4611686018427388000 round=4611686018427388000
2^63  to_int=9223372036854776000 truncate=9223372036854776000 floor=9223372036854776000 ceil=9223372036854776000 round=9223372036854776000
-2^63  to_int=-9223372036854776000 truncate=-9223372036854776000 floor=-9223372036854776000 ceil=-9223372036854776000 round=-9223372036854776000
nan  to_int=NaN truncate=NaN floor=NaN ceil=NaN round=NaN
inf  to_int=Infinity truncate=Infinity floor=Infinity ceil=Infinity round=Infinity
-inf  to_int=-Infinity truncate=-Infinity floor=-Infinity ceil=-Infinity round=-Infinity
exit 0
== control.march on interp
2.5  to_int=2 truncate=2 floor=2 ceil=3 round=3
-2.5  to_int=-2 truncate=-2 floor=-3 ceil=-2 round=-3
0.0  to_int=0 truncate=0 floor=0 ceil=0 round=0
1e15  to_int=1000000000000000 truncate=1000000000000000 floor=1000000000000000 ceil=1000000000000000 round=1000000000000000
2^53  to_int=9007199254740992 truncate=9007199254740992 floor=9007199254740992 ceil=9007199254740992 round=9007199254740992
-2^53  to_int=-9007199254740992 truncate=-9007199254740992 floor=-9007199254740992 ceil=-9007199254740992 round=-9007199254740992
exit 0
== control.march on native
2.5  to_int=2 truncate=2 floor=2 ceil=3 round=3
-2.5  to_int=-2 truncate=-2 floor=-3 ceil=-2 round=-3
0.0  to_int=0 truncate=0 floor=0 ceil=0 round=0
1e15  to_int=1000000000000000 truncate=1000000000000000 floor=1000000000000000 ceil=1000000000000000 round=1000000000000000
2^53  to_int=9007199254740992 truncate=9007199254740992 floor=9007199254740992 ceil=9007199254740992 round=9007199254740992
-2^53  to_int=-9007199254740992 truncate=-9007199254740992 floor=-9007199254740992 ceil=-9007199254740992 round=-9007199254740992
exit 0
== control.march on js
2.5  to_int=2 truncate=2 floor=2 ceil=3 round=3
-2.5  to_int=-2 truncate=-2 floor=-3 ceil=-2 round=-3
0.0  to_int=0 truncate=0 floor=0 ceil=0 round=0
1e15  to_int=1000000000000000 truncate=1000000000000000 floor=1000000000000000 ceil=1000000000000000 round=1000000000000000
2^53  to_int=9007199254740992 truncate=9007199254740992 floor=9007199254740992 ceil=9007199254740992 round=9007199254740992
-2^53  to_int=-9007199254740992 truncate=-9007199254740992 floor=-9007199254740992 ceil=-9007199254740992 round=-9007199254740992
exit 0
REPRODUCED
```

## Cause

- Native: `runtime/march_runtime.c`, `march_float_ceil`/`floor`/`round`/`truncate` (around line 10723) and `march_float_to_int` (around line 11164) are a bare `(int64_t)` cast.
- wasm: `runtime/march_runtime_wasm.c` (around line 515), the same cast.
- Interpreter: `lib/eval/eval_builtins.ml` around line 1210. `float_floor`/`ceil`/`round` call `int_of_float`/`Float.to_int` directly. `float_truncate` and `float_to_int` go through `int_of_float_checked` (`lib/eval/eval_runtime.ml`), which only checks on a narrow (browser REPL) host.
- JS: `lib/tir/js_emit.ml` emits `Math.trunc`/`Math.floor`/`Math.ceil` inline, and `march_float_round` in `runtime/march_runtime.mjs` has no check either.

`opt.fold` already refuses to fold these conversions for a literal outside ±4.6e18 (`lib/tir/fold.ml` around line 125). The inputs here are parsed at run time anyway.

## Run

Needs `node` on `PATH`. `MARCH_BIN` is the directory holding the `march` binary.

```
MARCH_BIN=/path/to/march/bin ./run.sh
```

The last line is `REPRODUCED` or `NOT REPRODUCED`.
