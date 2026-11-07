#!/usr/bin/env bash
# Shows that `march --target js --test` compiles test blocks but never runs
# them, using a test that must fail. Needs node and clang.
set -u
cd "$(dirname "$0")"

BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
MARCH="$BIN/march"
OUT=build

clean() { rm -rf "$OUT" .march failing.ll; }
clean
trap clean EXIT
mkdir -p "$OUT"

"$MARCH" --version 2>/dev/null | head -1

# Control: the same failing test on the native target must fail.
echo "== control: native --compile --test failing.march"
"$MARCH" --compile --test -o "$OUT/native" failing.march >"$OUT/native.compile" 2>&1
native_compile=$?
"./$OUT/native" >"$OUT/native.out" 2>&1
native_run=$?
cat "$OUT/native.out"
echo "compile exit=$native_compile, run exit=$native_run"
control_ok=no
if [ "$native_compile" -eq 0 ] && [ "$native_run" -ne 0 ] &&
   grep -q 'FAIL: "must fail"' "$OUT/native.out"; then
  control_ok=yes
fi

# Compiles $1 for JS, runs it, and sets false_green=yes when both steps exit 0
# and the run prints nothing, so the failing test was not reported.
js_case() {
  local src=$1 mjs="$OUT/${1%.march}.mjs" log="$OUT/${1%.march}.log"
  echo "== bug: --target js --test $src"
  "$MARCH" --target js --test -o "$mjs" "$src" >"$log.compile" 2>&1
  local compile=$?
  local run=skipped
  : >"$log"
  if [ -f "$mjs" ]; then
    node "$mjs" >"$log" 2>&1
    run=$?
  fi
  echo "compile exit=$compile, node exit=$run, node output bytes=$(wc -c <"$log" | tr -d ' ')"
  false_green=no
  if [ "$compile" -eq 0 ] && [ "$run" = 0 ] && [ ! -s "$log" ]; then
    false_green=yes
  fi
}

js_case failing.march
no_main=$false_green
js_case failing_with_main.march
with_main=$false_green

# Related, reported but not part of the verdict: --test alone turns a program
# that builds for JS into one that does not.
echo "== related: --target js prints.march (no --test)"
"$MARCH" --target js -o "$OUT/prints.mjs" prints.march 2>&1
node "$OUT/prints.mjs"
echo "== related: --target js --test prints.march"
"$MARCH" --target js --test -o "$OUT/prints_test.mjs" prints.march 2>&1
echo "compile exit=$?"

echo "control_ok=$control_ok no_main_false_green=$no_main with_main_false_green=$with_main"
if [ "$control_ok" = yes ] && [ "$no_main" = yes ] && [ "$with_main" = yes ]; then
  echo REPRODUCED
else
  echo NOT REPRODUCED
fi
