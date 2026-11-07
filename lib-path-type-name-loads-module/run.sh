#!/usr/bin/env bash
# main.march uses only Alpha. lib/zeta.march is never referenced and has an
# error, but it defines a type with the same name as one in Alpha.
# REPRODUCED means: the control (Zeta's type renamed) checks and runs cleanly,
# while the repro reports Zeta's error, so Zeta was loaded because of the name.
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
rm -rf build; mkdir -p build
trap 'rm -rf "$ROOT/build"' EXIT
cp -R main.march lib control build/
cd build

echo "== control: zeta's type renamed"
c_out=$(cd control && MARCH_LIB_PATH=lib "$MARCH" main.march 2>&1); c_rc=$?
echo "$c_out"; echo "exit $c_rc"
echo "== repro: zeta's type is also named Tally"
r_out=$(MARCH_LIB_PATH=lib "$MARCH" --check main.march 2>&1); r_rc=$?
echo "$r_out"; echo "exit $r_rc"

if [ "$c_rc" -eq 0 ] && [ "$c_out" = "1" ] && [ "$r_rc" -ne 0 ] && printf '%s' "$r_out" | grep -q 'lib/zeta.march'; then
  echo REPRODUCED
else
  echo NOT REPRODUCED
fi
