# Native: let-bound `None` crashes when its Option payload is Float, Unit or a nested Option

A well-typed program that binds `None` with an unannotated `let` and then uses it as `Option(Float)` crashes natively with SIGSEGV at address 0x8. The interpreter and the JS backend run it correctly. `Option(())` and `Option(Option(Int))` crash the same way. Niche-safe payloads such as `Int` and `String` do not. The `None` does not need to be inside a record: a record field only moves the crash to the point where the record is dropped, after correct output (`repro_record.march`). Any later `match` on the value also crashes (`repro.march`). Annotating the `let`, or not using a `let`, avoids it.

```march
mod Repro do
  needs IO.Console

  fn start() : Option(Float) do
    let x = None
    x
  end

  fn main(_c : Cap(IO.Console)) : () do
    match start() do
    | None -> println("none")
    | Some(_) -> println("some")
    end
  end
end
```

## Expected

`repro.march` prints `none` and exits 0, as it does in the interpreter and under `--target js`.

## Actual

`march --compile -o repro repro.march && ./repro`, on main at b7c963d74, macOS arm64:

```
march: fatal SIGSEGV si_code=2 addr=0x8 pc=0x100403ac4 sched=2 pid=0 status=1 fault outside its stack
```

Exit status 139. Full `run.sh` output:

```
== bug programs
repro: native exit=139, interpreter said: none
    march: fatal SIGSEGV si_code=2 addr=0x8 pc=0x100403ac4 sched=2 pid=0 status=1 fault outside its stack
repro_unit: native exit=139, interpreter said: none
    march: fatal SIGSEGV si_code=2 addr=0x8 pc=0x104313a38 sched=1 pid=0 status=1 fault outside its stack
repro_nested: native exit=139, interpreter said: none
    march: fatal SIGSEGV si_code=2 addr=0x8 pc=0x104117a38 sched=2 pid=0 status=1 fault outside its stack
repro_record: native exit=139, interpreter said: 3
    3
    march: fatal SIGSEGV si_code=2 addr=0x8 pc=0x102663e48 sched=2 pid=0 status=1 fault outside its stack
== controls
control_annotated: native exit=0, output: none
control_direct: native exit=0, output: none
control_int_payload: native exit=0, output: none
control_record_annotated: native exit=0, output: 3
== JS backend (informational)
repro: js output: none
repro_record: js output: 3
REPRODUCED
```

The same crash occurs on v0.7.0, at `--opt` 0 to 3, and with `--no-opt`.

## How to run

```
MARCH_BIN=/path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding the `march` binary. It defaults to `~/.march/versions/main-b7c963d74/bin`. The last line is `REPRODUCED` or `NOT REPRODUCED`. `REPRODUCED` means all four bug programs hit SIGSEGV natively, the interpreter gave the right output for them, and all four controls passed. The JS lines are informational.

## Files

| File | Result |
| --- | --- |
| `repro.march` | Crash: `Option(Float)` |
| `repro_unit.march` | Crash: `Option(())` |
| `repro_nested.march` | Crash: `Option(Option(Int))` |
| `repro_record.march` | Crash at drop, after correct output (the shape first reported) |
| `control_annotated.march` | Works: `let x : Option(Float) = None` |
| `control_direct.march` | Works: `None` with no `let` |
| `control_int_payload.march` | Works: same code at `Option(Int)` |
| `control_record_annotated.march` | Works: `let blank : A = ...` |

## Cause

Source references are to b7c963d74. Each step below was confirmed from `--dump-tir`, `--emit-llvm` and the source.

1. `let x = None` is generalized, because the `let` binds a simple variable (`lib/typecheck/typecheck.ml:5365`). This is documented: March has no value restriction (`specs/lang/core-march-types.md`, section 4, finding 1). The allocation reaches codegen with an unresolved payload type. `--dump-tir` shows `let x_i1 : Option('_55612) = alloc Option.None('_55612)()` flowing into `$t45517 : Option(Float)`.
2. A `TVar` payload is encoded as niche, so `None` becomes a raw null (`lib/tir/llvm_emit_alloc.ml:205-213`).
3. `Option(Float)`, `Option(())` and `Option(Option(_))` are not niche-safe (`niche_payload_ok`, `lib/tir/kind.ml:382`), so they use the Boxed representation. `match` and the drop glue at that type load the tag from `ptr + 8`, which is the fault at `0x8`. The `.ll` for `repro_record.march` shows `%tgp35 = getelementptr i8, ptr %ld33, i64 8` on the null value.

With an annotation or no `let`, the allocation is typed `Option(Float)`, so `None` is emitted as a boxed tag-0 cell and both sides agree.

The niche encoding for `Option(TVar)` is deliberate (see the comment at `lib/tir/llvm_emit.ml:951`). The defect is that a value encoded under that convention reaches code that decodes it at a concrete Boxed type, with no conversion between them.

`let x = None` used at two types in one function shows the same thing: `x` is one null value. With optimization on, inlining makes the `match` scrutinee `Option('_)`, which decodes as niche, so it happens to work. With `--no-opt` it crashes at the `Option(Float)` use.
