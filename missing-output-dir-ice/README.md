# `march --target js` reports an unwritable `-o` path as an internal compiler error

When `march --target js -o <path>` cannot open the output file, for example because the parent directory does not exist, the compiler prints `internal compiler error: Sys_error(...)`, an OCaml backtrace and "This is a compiler bug, not a problem with your program", and exits 3. The program compiled fine; the failure is an ordinary filesystem error in the user's environment. The command in the JavaScript Backend section of `docs/tooling.md` (`march --target js -o dist/app.mjs src/app.march`) hits this in any project that has no `dist/` yet. Whether `march` should create the directory is a design choice; the bug is the classification as a compiler crash. The native path does not have this problem: `--compile -o out/x` fails with a linker error and exit 1, which is not an ICE, though the message comes from `ld` and blames clang.

## Expected

Either `dist/` is created and the build succeeds, or a plain error naming the path, with a non-ICE exit code, for example:

```
march: cannot write dist/x.mjs: No such file or directory
```

## Actual

Main at b7c963d74 (macOS arm64):

```
$ march --target js -o dist/x.mjs hello.march
march: internal compiler error: Sys_error("dist/x.mjs: No such file or directory")
Raised by primitive operation at Stdlib.open_out_gen in file "stdlib.ml", line 331, characters 29-55
Called from Stdlib.open_out in file "stdlib.ml" (inlined), line 336, characters 2-74
Called from Dune__exe__Main.compile in file "bin/main.ml", line 5898, characters 19-35
This is a compiler bug, not a problem with your program. Please file an issue with a minimal reproduction.
exit code: 3
```

v0.7.0 gives the same output, with the raise at `bin/main.ml` line 5219.

Control, the same command with the directory present:

```
$ mkdir ok_dist && march --target js -o ok_dist/x.mjs hello.march
compiled ok_dist/x.mjs
exit code: 0
$ node ok_dist/x.mjs
hello
```

Native, with the directory missing (clang's `-Woverride-module` warning removed):

```
$ march --compile -o out/x hello.march
ld: open() failed, errno=2 (No such file or directory) for 'out/x'
clang: error: linker command failed with exit code 1 (use -v to see invocation)
march: clang failed (exit 1)
exit code: 1
```

Other unwritable `-o` paths give the same ICE on the JS target:

```
march: internal compiler error: Sys_error("adir: Is a directory")
march: internal compiler error: Sys_error("afile/x.mjs: Not a directory")
march: internal compiler error: Sys_error("ro/x.mjs: Permission denied")
```

## Cause

In `bin/main.ml` at b7c963d74, the JS branch of `compile` writes the output with an unguarded `open_out out_bin` (line 5898). The `Sys_error` reaches the catch-all `| exn ->` handler of the compile pipeline (lines 7087-7108), which treats every exception that reaches it as a compiler bug and exits with `internal_compiler_error_exit_code` (3). The source map write just above it (line 5892) is wrapped in `try ... with Sys_error _ -> ()`, so that failure is dropped and the first visible failure is the `.mjs` write.

## Run

```sh
./run.sh                                             # main build under ~/.march/versions
MARCH_BIN=/path/to/march/bin ./run.sh                # any other toolchain
```

`run.sh` needs `node` for the control. It builds in `_work/`, removes it, and prints `REPRODUCED` or `NOT REPRODUCED` as its last line. `REPRODUCED` means the missing-directory build exited 3 with the ICE text and the control built and printed `hello`.
