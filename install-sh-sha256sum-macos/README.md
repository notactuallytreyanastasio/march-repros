# install.sh fails checksum verification on macOS when Apple's sha256sum is first on PATH

`install.sh` prefers `sha256sum` when it is on `PATH`, then pipes the checklist to `sha256sum -c --ignore-missing` with no file operand. GNU coreutils reads stdin in that case. Apple's `/sbin/sha256sum` (a hard link to `/sbin/md5`, from `text_cmds`) does not: in its GNU-compatible mode, `-c` needs at least one file operand, so it prints its usage line and exits 1. `/sbin` is in the default macOS `PATH` through `/etc/paths`, so `install.sh` picks this binary over `shasum`, and the install fails with `checksum verification failed` even though the download is intact. `--ignore-missing` is not the cause: Apple's `sha256sum` accepts it, and plain `sha256sum -c` on stdin fails the same way. The failure is safe, because nothing gets installed, but the documented `curl | sh` install does not work on such a machine.

Tested on macOS 27.2 arm64, `/sbin/sha256sum` from `text_cmds-201`. Which earlier macOS releases ship this binary was not tested.

## Expected

The checksum step passes for an intact download, as it does with GNU `sha256sum` and with `shasum`, and the install continues.

## Actual

From `./run.sh`, using a file whose checksum is correct:

```
$ grep " march-v0.0.0-darwin-arm64.tar.gz\$" checksums.txt | sha256sum -c --ignore-missing
usage: sha256sum [-bctwz] [files ...]
[exit 1]

$ grep " march-v0.0.0-darwin-arm64.tar.gz\$" checksums.txt | sha256sum -c
usage: sha256sum [-bctwz] [files ...]
[exit 1]

$ sha256sum -c --ignore-missing checksums.txt
march-v0.0.0-darwin-arm64.tar.gz: OK
[exit 0]

$ grep " march-v0.0.0-darwin-arm64.tar.gz\$" checksums.txt | sha256sum -c --ignore-missing -
march-v0.0.0-darwin-arm64.tar.gz: OK
[exit 0]

$ grep " march-v0.0.0-darwin-arm64.tar.gz\$" checksums.txt | shasum -a 256 -c --ignore-missing
march-v0.0.0-darwin-arm64.tar.gz: OK
[exit 0]
```

The real `install.sh` from commit b7c963d74, fetched and run unmodified, with `curl` stubbed to serve a local fixture:

```
Platform: darwin-arm64
Release: v0.0.0
Downloading march-v0.0.0-darwin-arm64.tar.gz ...
Verifying checksum ...
usage: sha256sum [-bctwz] [files ...]
error: checksum verification failed for march-v0.0.0-darwin-arm64.tar.gz
[exit 1]
```

`install.sh` at tag v0.7.0 prints the same output in the same harness. With only `-` added to the `sha256sum` command on line 28, the b7c963d74 script finishes with `March v0.0.0 installed.`, and the `-` form still rejects a tampered file (`march-v0.0.0-darwin-arm64.tar.gz: FAILED`, exit 1).

## Against the real v0.7.0 release

`run.sh` does not download a release. These commands do, about 14 MB per install. `MARCH_HOME` keeps each install in `./march-home`, so an existing `~/.march` is not touched. They cover the stock script, the workaround below, and the one-line fix, in that order.

```sh
URL=https://raw.githubusercontent.com/march-language/march/b7c963d746dd5e326e04e5acf661a34e4f6b7b2c/install.sh
curl -fsSL "$URL" | MARCH_HOME=./march-home MARCH_VERSION=v0.7.0 sh
echo "[exit $?]"
curl -fsSL "$URL" | MARCH_HOME=./march-home MARCH_VERSION=v0.7.0 PATH=/usr/bin:/bin sh
echo "[exit $?]"
./march-home/bin/march --version
rm -rf march-home
curl -fsSL "$URL" | sed 's/SHACHECK="sha256sum -c --ignore-missing"/SHACHECK="sha256sum -c --ignore-missing -"/' | MARCH_HOME=./march-home MARCH_VERSION=v0.7.0 sh
echo "[exit $?]"
./march-home/bin/march --version
```

Output:

```
Platform: darwin-arm64
Release: v0.7.0
Downloading march-v0.7.0-darwin-arm64.tar.gz ...
Verifying checksum ...
usage: sha256sum [-bctwz] [files ...]
error: checksum verification failed for march-v0.7.0-darwin-arm64.tar.gz
[exit 1]
Platform: darwin-arm64
Release: v0.7.0
Downloading march-v0.7.0-darwin-arm64.tar.gz ...
Verifying checksum ...
Installing to ./march-home/versions/v0.7.0 ...

March v0.7.0 installed.
Add March to your PATH:

    export PATH="./march-home/bin:$PATH"

(append that line to your ~/.zshrc or ~/.bashrc to make it permanent)
[exit 0]
march 0.7.0
Platform: darwin-arm64
Release: v0.7.0
Downloading march-v0.7.0-darwin-arm64.tar.gz ...
Verifying checksum ...
Installing to ./march-home/versions/v0.7.0 ...

March v0.7.0 installed.
Add March to your PATH:

    export PATH="./march-home/bin:$PATH"

(append that line to your ~/.zshrc or ~/.bashrc to make it permanent)
[exit 0]
march 0.7.0
```

## Cause

- `install.sh` lines 27-28 choose `sha256sum -c --ignore-missing`, and line 94 feeds it from a pipe with no operand. `install.sh` at v0.7.0 has the same lines, and differs from b7c963d74 only in one header comment.
- Apple's `md5/md5.c` (read at tag `text_cmds-199`, the newest published; the installed binary is 201) has `if (argc < 1) usage(...)` at lines 601-602, inside `if (cflag && mode != mode_bsd)`. `gnu_check()` does handle `"-"` as stdin (line 330), which is why the explicit operand works.

Adding `-` also works with GNU `sha256sum` 9.12 and with `shasum`. Preferring `shasum` on Darwin would work too. The README already says "use shasum on macOS, sha256sum on Linux" for manual verification.

## Workaround

Keep `/sbin` out of `PATH` for the installer so that it falls back to `shasum`. This was confirmed against the real v0.7.0 release, the latest at the time of writing: with `MARCH_HOME` set to a local directory, the command below exited 0 and the installed binary reported `march 0.7.0`.

```sh
curl -fsSL https://raw.githubusercontent.com/march-language/march/main/install.sh | PATH=/usr/bin:/bin sh
```

## Running it

```sh
./run.sh
```

It needs network access to `raw.githubusercontent.com` and no March toolchain. It fetches `install.sh` from commit b7c963d74 (main) and from the commit tagged v0.7.0, and checks each against a pinned SHA-256. If a fetch fails, it says so and prints `NOT REPRODUCED`, which then says nothing about the bug.

It works in `./build`, removes it on exit, and prints `REPRODUCED` or `NOT REPRODUCED` as the last line. On a machine with GNU `sha256sum` first on `PATH`, or with no `sha256sum` on `PATH`, it prints `NOT REPRODUCED`. Both were checked.

`MARCH_BIN` is ignored, because nothing runs the march binary. The v0.7.0 result comes from the script fetched at that tag, not from `MARCH_BIN`.

`stub-curl.sh` stands in for `curl` during the installer runs, so `run.sh` does not download a release.

`install.sh` is not included here. The March README says MIT, but the repository has no LICENSE file, so this repro fetches the script rather than redistributing it.
