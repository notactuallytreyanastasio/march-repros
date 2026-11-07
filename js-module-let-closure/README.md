# `--target js`: a module-level `let` outside the entry module reads as a closure object

On `--target js`, a module-level `let` in any module other than the entry module (a nested `mod` or a `MARCH_LIB_PATH`/stdlib module) evaluates to the closure-protocol wrapper object instead of its value, with no compile error. `let n = 7` printed through `int_to_string` gives `[object Object]`. The interpreter and `--compile` give the right value, and so does the same `let` in the entry module. The same happens to references inside the defining module, which is how `Bytes.encode_base64` fails on this target.

## Program

```march
mod Main do
  needs IO.Console

  mod Cst do
    let n = 7
  end

  fn main(_c : Cap(IO.Console)) : () do
    println(int_to_string(Cst.n))
  end
end
```

## Expected

```
7
```

## Actual

Main at b7c963d74 and v0.7.0, node v26.13.0, macOS arm64:

```
$ march --target js -o out/repro.mjs repro.march && node out/repro.mjs
[object Object]
```

The emitted JS (`repro.mjs`) refers to the wrapper and never calls `Cst$n`:

```js
function Cst$n() {
  return 7;
}
const Cst$n$clo = { _0: ($_) => Cst$n() };
...
    const $t45517 = String(Cst$n$clo);
```

Other programs here, interpreter then `--target js`:

| Program | Interpreter | `--target js` |
|---|---|---|
| `control.march` (`let` in the entry module) | `7` | `7` |
| `repro_lib.march`, `Cst.n` from a `MARCH_LIB_PATH` module | `7` | `[object Object]` |
| `repro_lib.march`, `fn via_let() do n end` inside that module | `7` | `[object Object]` |
| `repro_lib.march`, `fn via_literal() do 7 end` | `7` | `7` |
| `repro_stdlib.march`, `Bytes.encode_base64` on `"hi!"` | `aGkh` | `TypeError: s.slice is not a function` |

## Cause

Confirmed by reading the source at b7c963d74:

- A `let` in a non-entry module is lowered to a zero-parameter function (`lib/tir/lower.ml:910`, `lib/tir/lower_decls.ml:403`). A `let` in the entry module is collected in `top_lets` (`lib/tir/lower.ml:827`) and injected as a local binding into `main` and each function that uses it (`lib/tir/lower.ml:1175`), which is why the control works.
- `emit_atom` in `lib/tir/js_emit.ml:263` and `:275` emits `<name>$clo` for any name in `fn_names`, and `fn_names` holds every top-level function (`:1693`).
- The native backend handles this case: `zero_arg_fns` (`lib/tir/llvm_ctx.ml:103`) and the fallback in `lib/tir/llvm_emit.ml:776` call the function to get the value. `js_emit.ml` has no equivalent.

## Run

```
./run.sh
MARCH_BIN=/path/to/march/bin ./run.sh
```

Needs `node`. `MARCH_BIN` defaults to `~/.march/versions/main-b7c963d74/bin`. The last line is `REPRODUCED` or `NOT REPRODUCED`.
