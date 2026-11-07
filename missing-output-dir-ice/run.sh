#!/usr/bin/env bash
# Repro: `march --target js -o <path>` with an unwritable output path reports an
# internal compiler error. Prints REPRODUCED or NOT REPRODUCED as its last line.
set -u
cd "$(dirname "$0")"

MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
MARCH="$MARCH_BIN/march"
if [ ! -x "$MARCH" ]; then
  echo "no march binary at $MARCH"
  echo "NOT REPRODUCED"
  exit 1
fi
case "$MARCH" in /*) ;; *) MARCH="$PWD/$MARCH" ;; esac

ROOT=$PWD
WORK=_work
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'cd "$ROOT" && rm -rf "$WORK"' EXIT
cp hello.march "$WORK/"
cd "$WORK"

show() { sed -e '/Woverride-module/d' -e '/warning generated/d' "$1"; }

echo "== march version: $("$MARCH" --version 2>&1 | head -1)"

echo "== 1. bug: --target js, dist/ does not exist"
"$MARCH" --target js -o dist/x.mjs hello.march > js_missing.log 2>&1
js_missing_rc=$?
show js_missing.log
echo "exit code: $js_missing_rc"

echo "== 2. control: same command, dist/ exists"
mkdir ok_dist
"$MARCH" --target js -o ok_dist/x.mjs hello.march > js_ok.log 2>&1
js_ok_rc=$?
show js_ok.log
echo "exit code: $js_ok_rc"
js_ok_out=""
if command -v node > /dev/null 2>&1 && [ -f ok_dist/x.mjs ]; then
  js_ok_out=$(node ok_dist/x.mjs 2>&1)
  echo "node ok_dist/x.mjs: $js_ok_out"
else
  echo "node or ok_dist/x.mjs missing"
fi

echo "== 3. comparison: --compile (native), out/ does not exist"
"$MARCH" --compile -o out/x hello.march > native_missing.log 2>&1
native_missing_rc=$?
show native_missing.log
echo "exit code: $native_missing_rc"

echo "== 4. same fault, another path: --target js, -o names an existing directory"
mkdir adir
"$MARCH" --target js -o adir hello.march > js_isdir.log 2>&1
js_isdir_rc=$?
show js_isdir.log
echo "exit code: $js_isdir_rc"

echo
if [ "$js_missing_rc" -eq 3 ] \
   && grep -q 'internal compiler error: Sys_error' js_missing.log \
   && grep -q 'This is a compiler bug' js_missing.log \
   && [ "$js_ok_rc" -eq 0 ] \
   && [ "$js_ok_out" = "hello" ]; then
  echo "REPRODUCED"
else
  echo "NOT REPRODUCED"
fi
