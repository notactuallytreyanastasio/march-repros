#!/usr/bin/env bash
# forge format drops the parentheses around a non-infix operand.
# MARCH_BIN selects the toolchain's bin directory. The last line of output is
# REPRODUCED or NOT REPRODUCED, and depends only on repro.march and
# control.march; the related/ cases are reported above it.
set -u
cd "$(dirname "$0")"
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
MARCH="$MARCH_BIN/march"
FORGE="$MARCH_BIN/forge"
OUT=.out
rm -rf "$OUT" .march
mkdir -p "$OUT"
trap 'rm -rf "$OUT" .march' EXIT

if [ ! -x "$MARCH" ] || [ ! -x "$FORGE" ]; then
  echo "no march and forge in MARCH_BIN=$MARCH_BIN" >&2
  echo "NOT REPRODUCED"
  exit 1
fi

parses() { "$MARCH" --check "$1" >"$OUT/check.txt" 2>&1; }
format_to() { "$FORGE" format --stdin <"$1" >"$2"; }

echo "--- repro.march"
ok=1
if parses repro.march; then
  echo "input: passes march --check"
else
  echo "input: FAILS march --check, so the repro is invalid"
  ok=0
fi
format_to repro.march "$OUT/repro.march"
echo "forge format --stdin exit code: $?"
grep -n '1 + ' "$OUT/repro.march"
if parses "$OUT/repro.march"; then
  echo "formatted: passes march --check"
  ok=0
else
  grep -q 'syntax_error' "$OUT/check.txt" || ok=0
  sed -e '/^$/d' "$OUT/check.txt"
fi

echo "--- control.march"
format_to control.march "$OUT/control.march"
grep -n -E 'let y|2 \* ' "$OUT/control.march"
if parses control.march && parses "$OUT/control.march" &&
   grep -q '2 \* (y + 1)' "$OUT/control.march"; then
  echo "formatted: passes march --check, parentheses kept"
else
  echo "formatted: control failed"
  ok=0
fi

echo "--- related/pipe.march (output changes)"
format_to related/pipe.march "$OUT/pipe.march"
grep -n 'println' "$OUT/pipe.march"
echo "before: $("$MARCH" related/pipe.march 2>&1 | tail -1)  after: $("$MARCH" "$OUT/pipe.march" 2>&1 | tail -1)"

echo "--- related/callee.march (output changes)"
format_to related/callee.march "$OUT/callee.march"
grep -n 'add1 else' "$OUT/callee.march"
echo "before: $("$MARCH" related/callee.march 2>&1 | tail -1)  after: $("$MARCH" "$OUT/callee.march" 2>&1 | tail -1)"

echo "--- related/match_operand.march (forge format in a project, in place)"
mkdir -p "$OUT/proj/lib"
printf '[package]\nname = "p"\nversion = "0.1.0"\n' >"$OUT/proj/forge.toml"
cp related/match_operand.march "$OUT/proj/lib/m.march"
# forge format shells out to `march fmt` found on PATH.
(cd "$OUT/proj" && PATH="$MARCH_BIN:$PATH" "$FORGE" format >/dev/null)
echo "forge format exit code: $?"
sed -e '/^$/d' "$OUT/proj/lib/m.march"

echo "---"
if [ "$ok" = 1 ]; then
  echo "REPRODUCED"
else
  echo "NOT REPRODUCED"
fi
