#!/usr/bin/env bash
# Usage: ./run.sh                     (pinned main toolchain if present, else march on PATH)
#        MARCH_BIN=path/to/bin ./run.sh    (directory holding march; may be relative)
# The last line is REPRODUCED or NOT REPRODUCED.

# Resolve MARCH_BIN to an absolute path before any cd below.
if [ -z "$MARCH_BIN" ]; then
  MARCH_BIN="$HOME/.march/versions/main-b7c963d74/bin"
  [ -x "$MARCH_BIN/march" ] || MARCH_BIN=$(dirname "$(command -v march || echo .)")
fi
if ! MARCH_BIN=$(CDPATH= cd -- "$MARCH_BIN" 2>/dev/null && pwd); then
  echo "MARCH_BIN is not a directory"
  echo "NOT REPRODUCED"
  exit 1
fi
MARCH="$MARCH_BIN/march"

cd "$(dirname "$0")" || exit 1
LIMIT=20

if [ ! -x "$MARCH" ] || ! command -v node >/dev/null || ! command -v perl >/dev/null; then
  echo "need $MARCH, node and perl on PATH"
  echo "NOT REPRODUCED"
  exit 1
fi

rm -rf build
mkdir -p build/js
cp ./*.march build/
cd build || exit 1

# Run a command under a time limit (perl: macOS has no timeout(1)).
limited() { perl -e 'alarm shift; exec @ARGV or exit 127' "$LIMIT" "$@"; }

run_interp() { limited "$MARCH" "$1.march" 2>&1; }
run_native() {
  "$MARCH" --compile "$1.march" -o "$1.bin" >/dev/null 2>&1 || { echo "native compile failed"; return 1; }
  limited "./$1.bin" 2>&1
}
run_js() {
  "$MARCH" --target js -o "js/$1.mjs" "$1.march" >/dev/null 2>&1 || { echo "js compile failed"; return 1; }
  limited node "js/$1.mjs" 2>&1
}
oneline() { printf '%s' "$1" | tr '\n' '|'; }

# Prints the three outputs. Sets RI, RN, RJ to the outputs.
three() {
  RI=$(run_interp "$1"); RN=$(run_native "$1"); RJ=$(run_js "$1")
  echo "$1"
  echo "  interp: $(oneline "$RI")"
  echo "  native: $(oneline "$RN")"
  echo "  js:     $(oneline "$RJ")"
}

expected_str=$'called\na!\ncalled\nb!'
expected_int=$'called\n15\ncalled\n15'
expected_not=$'called\ntrue\ncalled\ntrue'

three repro
bug_explicit=no
[ "$RI" = "$expected_str" ] && [ "$RN" = "$expected_str" ] && [ "$RJ" != "$expected_str" ] && bug_explicit=yes

three prefix_minus
bug_prefix=no
[ "$RI" = "$expected_int" ] && [ "$RN" = "$expected_int" ] && [ "$RJ" != "$expected_int" ] && bug_prefix=yes

three not
bug_not=no
[ "$RI" = "$expected_not" ] && [ "$RN" = "$expected_not" ] && [ "$RJ" != "$expected_not" ] && bug_not=yes

controls_ok=yes
for c in control_renamed control_nested; do
  three "$c"
  { [ "$RI" = "$expected_str" ] && [ "$RN" = "$expected_str" ] && [ "$RJ" = "$expected_str" ]; } || controls_ok=no
done

# For information; these do not decide the result.
echo "reported (--check)"
out=$("$MARCH" --check reported.march 2>&1); rc=$?
echo "  exit $rc: $(printf '%s\n' "$out" | grep -o '\[non_tail_recursion\]' | head -1)"

echo "tail_minus"
out=$("$MARCH" --check tail_minus.march 2>&1); rc=$?
echo "  --check: exit $rc, $(printf '%s' "$out" | wc -c | tr -d ' ') bytes of diagnostics"
out=$(run_interp tail_minus); rc=$?
echo "  interp: exit $rc: $(printf '%s\n' "$out" | head -1)"
out=$(run_native tail_minus); rc=$?
echo "  native: exit $rc after at most ${LIMIT}s (142 = killed by the limit)"
out=$(run_js tail_minus); rc=$?
echo "  js:     exit $rc: $out"

cd .. && rm -rf build

echo "explicit call dropped on JS: $bug_explicit; prefix minus dropped on JS: $bug_prefix; not dropped on JS: $bug_not; controls correct: $controls_ok"
if [ "$bug_explicit" = yes ] && [ "$bug_prefix" = yes ] && [ "$bug_not" = yes ] && [ "$controls_ok" = yes ]; then
  echo "REPRODUCED"
else
  echo "NOT REPRODUCED"
fi
