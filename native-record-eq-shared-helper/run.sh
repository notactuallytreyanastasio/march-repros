#!/bin/bash
# Checks that compiled record == disagrees with the interpreter, and that the controls agree.
# MARCH_BIN: directory holding the march binary.
cd "$(dirname "$0")" || exit 1
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
MARCH="$MARCH_BIN/march"
BUILD=build
# .march is the compiler's build cache, created in the working directory.
rm -rf "$BUILD" .march
mkdir -p "$BUILD"
trap 'rm -rf "$BUILD" .march' EXIT

fail=0   # a precondition failed: interpreter or control is not correct
hits=""  # bug shapes that showed up natively

# oneline <text>: newlines to spaces, trimmed
oneline() { printf '%s' "$1" | tr '\n' ' ' | sed 's/ *$//'; }

# Sets OUT and RC for the native build of $1. The source is copied first because
# the compiler writes <name>.ll next to its input.
native() {
  cp "$1.march" "$BUILD/$1.march"
  if ! "$MARCH" --compile -o "$BUILD/$1" "$BUILD/$1.march" >"$BUILD/$1.log" 2>&1; then
    OUT="(compile failed)"; RC=255; fail=1; cat "$BUILD/$1.log"; return
  fi
  OUT=$("$BUILD/$1" 2>/dev/null); RC=$?
  OUT=$(oneline "$OUT")
}

# interp_ok <name> <correct output>: the interpreter must print the correct output.
interp_ok() {
  local got; got=$(oneline "$("$MARCH" "$1.march" 2>&1)")
  printf '%-18s interp: %s\n' "$1" "$got"
  [ "$got" = "$2" ] || { echo "  interpreter did not print: $2"; fail=1; }
}

control() {
  interp_ok "$1" "$2"
  native "$1"
  printf '%-18s native: %s (exit %s)\n' "$1" "$OUT" "$RC"
  { [ "$OUT" = "$2" ] && [ "$RC" = 0 ]; } || { echo "  control is wrong natively, expected: $2"; fail=1; }
}

bug() {
  interp_ok "$1" "$2"
  native "$1"
  printf '%-18s native: %s (exit %s)\n' "$1" "$OUT" "$RC"
  [ "$RC" = 255 ] && return
  if [ "$OUT" != "$2" ] || [ "$RC" != 0 ]; then hits="$hits $1"; fi
}

control control_one_type "false true"
control control_eq       "true false"
bug wrong_answer "true false true"
bug segfault     "true true"
bug overread     "true true"
bug eq_nested    "true false false"

echo "wrong natively:${hits:- none}"
case "$hits" in
  *wrong_answer*segfault*) [ "$fail" = 0 ] && { echo REPRODUCED; exit 0; } ;;
esac
echo "NOT REPRODUCED"
