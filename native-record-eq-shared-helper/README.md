# Compiled `==` on records uses one helper for every record type

In a natively compiled program, every record type shares a single equality helper, `__march_eq_Ptr`, generated for whichever record type's `==` is emitted first. Any other record type compared with `==` or `!=` runs that helper against its own layout. Depending on the two layouts, the result is a wrong answer, a read past the end of the record, or a SIGSEGV in `march_string_eq`. The interpreter is correct in every case here. No library module is needed. `eq()` on a flat record with `derive Eq` is correct, because the derived impl compares fields one at a time, but `eq()` reaches the helper when a record is nested in another record or in a `List`, since those compare the inner record with `==`.

This extends the repository's own todo, `specs/todos/2026-11-05-compiled-record-eq-helper-collision.md`, which records the SIGSEGV. The silent cases below are not in it.

## Expected

Compiled output matches the interpreter, which matches the documented meaning of `derive Eq` ("structural equality, comparing all fields/constructors", `docs/interfaces.md`).

| Program | Expected |
|---|---|
| `wrong_answer.march` | `true false true` |
| `segfault.march` | `true true` |
| `overread.march` | `true true` |
| `eq_nested.march` | `true false false` |

## Actual

Output of `./run.sh` on main at b7c963d74, macOS arm64. Release v0.7.0 prints the same.

```
control_one_type   interp: false true
control_one_type   native: false true (exit 0)
control_eq         interp: true false
control_eq         native: true false (exit 0)
wrong_answer       interp: true false true
wrong_answer       native: true true false (exit 0)
segfault           interp: true true
segfault           native: true (exit 139)
overread           interp: true true
overread           native: true false (exit 0)
eq_nested          interp: true false false
eq_nested          native: true true true (exit 0)
wrong natively: wrong_answer segfault overread eq_nested
REPRODUCED
```

The `segfault` binary also prints this to stderr:

```
march: fatal SIGSEGV si_code=2 addr=0x11 pc=0x10465e55c sched=9 pid=0 status=1 fault outside its stack
```

lldb puts the fault in `march_string_eq`, with `march_main` as the next frame.

## The programs

- `wrong_answer.march`: `Pair` is compared first, so the helper reads two fields. `Triple` values that differ only in their third field compare equal, and `!=` says they are not different.
- `segfault.march`: a record of two Strings is compared first, so the helper calls `march_string_eq`. Comparing a record of two Ints then passes Int fields to it as string pointers.
- `overread.march`: `Triple` is compared first, so the helper reads three fields. Comparing two equal `Pair` values loads offset 32 from a 32-byte allocation (`march_alloc(i64 32)` in the IR). The answer depends on what is in memory after the record. It printed `false` on every run here, but `run.sh` does not require that for REPRODUCED.
- `eq_nested.march`: `eq()` on a record with a record field, and on a `List` of records, gives `true` for values that differ.
- `control_one_type.march`: `wrong_answer.march` with no `Pair` comparison. Correct, so the first comparison is what causes the failure.
- `control_eq.march`: `wrong_answer.march` with `eq()` in place of `==`. Correct, and its IR contains no `__march_eq_Ptr`.

The two values in each comparison are separate variables on purpose: `x == x` on a single variable is folded away, and does not generate a helper.

## Cause

`mangle_ty_for_eq` (`lib/tir/llvm_eq.ml:27`) has no case for `Tir.TRecord`, so records fall through to `| _ -> "Ptr"` at line 39. `ensure_adt_eq_fn` builds the helper name from that at line 534 and at line 535 returns any helper already registered under the name, so the second record type gets the first type's body. The `TTuple` case just above it includes the component types in the name, so tuples with different component types get different names.

`eq()` reaches the helper through `==`: `derive Eq` compares each field with `==` (`lib/desugar/desugar_derive.ml:281`), and `impl Eq(List(a))` compares elements with `x == y` (`stdlib/list.march:1259`).

## Run

```
./run.sh
MARCH_BIN=path/to/march/bin ./run.sh
```

`MARCH_BIN` is the directory holding the `march` binary. It defaults to `~/.march/versions/main-b7c963d74/bin`. The last line is `REPRODUCED` when the interpreter and both controls are correct and `wrong_answer` and `segfault` fail natively, otherwise `NOT REPRODUCED`.
