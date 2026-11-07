#!/usr/bin/env bash
# REPRODUCED means: the interpreter gives +0 for 0.0 +. -0.0 and -0.0 +. 0.0 as
# IEEE 754 requires, while a native or JS build gives -0 for either.
# MARCH_BIN is the toolchain's bin directory. Without it: the pinned main build
# if present, otherwise `march` from PATH.
set -u
if [ -n "${MARCH_BIN:-}" ]; then
  BIN=$MARCH_BIN
else
  BIN=$HOME/.march/versions/main-b7c963d74/bin
  [ -x "$BIN/march" ] || BIN=$(dirname "$(command -v march || echo /nonexistent/march)")
fi
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
MARCH="$BIN/march"
cd "$(dirname "$0")" || { echo NOT REPRODUCED; exit 1; }
ROOT=$PWD
rm -rf build; mkdir -p build; trap 'rm -rf "$ROOT/build"' EXIT
cp repro.march build/; cd build
echo "== interpreter"; i=$("$MARCH" repro.march 2>&1); echo "$i"
echo "== native"; n=$("$MARCH" --compile repro.march -o ./repro.bin >/dev/null 2>&1 && ./repro.bin 2>&1); echo "$n"
echo "== js (opt.fold disabled)"; j=$("$MARCH" --target js --disable-pass opt.fold -o repro.mjs repro.march >/dev/null 2>&1 && node repro.mjs 2>&1); echo "$j"
bad() { printf '%s' "$1" | grep -q -- '0.0: -0 (IEEE'; }
if ! bad "$i" && printf '%s' "$i" | grep -q 'm: -0' && { bad "$n" || bad "$j"; }; then echo REPRODUCED; else echo NOT REPRODUCED; fi
