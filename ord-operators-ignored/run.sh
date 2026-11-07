#!/usr/bin/env bash
# Runs the repro and control programs on the interpreter, native and JS backends.
# REPRODUCED means: every control is correct on all three backends, the
# interpreter is correct on repro.march and generic.march, and a native or JS
# build of either one succeeds and prints the wrong answer.
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
# The compiler writes .ll files and a .march cache beside its input, so build in a copy.
rm -rf build; mkdir -p build
trap 'rm -rf "$ROOT/build"' EXIT
cp ./*.march expected.txt build/
cd build

interp() { "$MARCH" "$1.march" 2>&1; }
native() {
  if "$MARCH" --compile "$1.march" -o "./$1.bin" >"$1.log" 2>&1; then "./$1.bin" 2>&1
  else echo "BUILD FAILED"; grep -m1 'error:' "$1.log"; fi
}
js() {
  if "$MARCH" --target js -o "$1.mjs" "$1.march" >"$1.jslog" 2>&1; then node "$1.mjs" 2>&1
  else echo "BUILD FAILED"; grep -m1 'error' "$1.jslog"; fi
}
# A build failure is not the bug under test, so it never counts as a wrong answer.
wrong() { [ "$1" != "$2" ] && [ "${1%%$'\n'*}" != "BUILD FAILED" ]; }

want_repro=$(cat expected.txt)
want_control=$(grep -v '^p < q' expected.txt)
want_generic='lt(Red, Green)  true'

control_ok=1
check_control() {
  for backend in interp native js; do
    got=$($backend "$1")
    if [ "$got" = "$2" ]; then echo "$1 $backend: ok"
    else echo "$1 $backend: WRONG"; echo "$got"; control_ok=0; fi
  done
}
check_control control "$want_control"
check_control generic_control "$want_generic"

interp_ok=1
compiled_wrong=0
check_repro() {
  i=$(interp "$1"); n=$(native "$1"); j=$(js "$1")
  echo "--- $1: interpreter"; echo "$i"
  echo "--- $1: native";      echo "$n"
  echo "--- $1: js";          echo "$j"
  [ "$i" = "$2" ] || interp_ok=0
  if wrong "$n" "$2" || wrong "$j" "$2"; then compiled_wrong=1; fi
}
check_repro repro "$want_repro"
check_repro generic "$want_generic"

# Two related native symptoms. Each is checked and reported on its own line, but
# neither decides the verdict, which is about the operators ignoring the impl.
ni=$(interp newtype); nn=$(native newtype)
echo "--- newtype: interpreter"; echo "$ni"
echo "--- newtype: native";      echo "$nn"
if [ "$(echo "$ni" | tail -1)" = "Wrap(1) < Wrap(2) false" ] &&
   [ "$(echo "$nn" | tail -1)" = "Wrap(1) < Wrap(2) true" ]; then
  echo "related symptom newtype: present"
else
  echo "related symptom newtype: absent"
fi
ui=$(interp unboxed); un=$(native unboxed)
echo "--- unboxed: interpreter"; echo "$ui"
echo "--- unboxed: native";      echo "$un"
if [ "${un%%$'\n'*}" = "BUILD FAILED" ]; then
  echo "related symptom unboxed: present"
else
  echo "related symptom unboxed: absent"
fi

if [ "$control_ok" = 1 ] && [ "$interp_ok" = 1 ] && [ "$compiled_wrong" = 1 ]; then
  echo REPRODUCED
else
  echo NOT REPRODUCED
fi
