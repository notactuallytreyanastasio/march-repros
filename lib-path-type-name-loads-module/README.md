# A shared type name loads an unrelated module from MARCH_LIB_PATH

`main.march` calls only `Alpha.one()`. `lib/zeta.march` is never referenced and calls a module that doesn't exist. Zeta is still loaded and checked, and its error fails the build, but only when Zeta defines a type with the same name as a type in Alpha (`Tally`). Rename Zeta's type (`control/`) and the program checks and prints `1`.

So a bare type name seems to pull in every module on the lib path that defines that name, not just the one in scope.

```
$ MARCH_LIB_PATH=lib march --check main.march
-- NAMING -------------------------------- lib/zeta.march
Unknown module `Gamma`. [unknown_qualified_name]
exit 1
```

The interpreter (`march main.march`) fails the same way.

## Why it matters

In a project where each test suite is meant to compile only what it reaches, two unrelated `type Tally` records tied every suite to every other suite. A syntax error in one piece of the project then broke the build of all the others, and compile times went up. The results stayed correct, because the two types were never mixed.

## Expected

Modules that aren't referenced are never loaded, whatever type names they define. Or, if loading every file on the lib path is intended, the renamed control should fail too.

Run `./run.sh`; the last line is `REPRODUCED` or `NOT REPRODUCED`.
