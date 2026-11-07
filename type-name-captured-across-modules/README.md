# A local type named like another module's type captures that module's field types

`Main` defines `type Table`, and so does `Shapes`. `Shapes.Holder`'s field `table : Table` means `Shapes.Table`, but in `Main` it is read as `Main.Table`. That gives the impossible error:

    expected `{ table : Table }` but got `{ table : Table }`. [type_mismatch]

In a larger program (a record holding a type that reaches the other `Table` through several modules), `forge check` passed, but then `march --target js` and `march --compile` never finished: they ran over 5 minutes with memory past 19 GB and printed nothing. Renaming the local type fixes both.

Run: `./run.sh` (march main b7c963d74). Expected: it compiles and prints `2.0`. Actual: the error above, `REPRODUCED`.

Related to march#1183 (shared type names on `MARCH_LIB_PATH`).
