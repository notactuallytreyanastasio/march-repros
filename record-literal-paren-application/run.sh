#!/usr/bin/env bash
# Usage: ./run.sh    (MARCH_BIN selects the toolchain's bin dir; default is the
# main-b7c963d74 install if present, otherwise the march on PATH)
set -u
if [ -z "${MARCH_BIN:-}" ]; then
  MARCH_BIN="$HOME/.march/versions/main-b7c963d74/bin"
  [ -x "$MARCH_BIN/march" ] || MARCH_BIN="$(dirname "$(command -v march || echo /nonexistent/march)")"
fi
if ! MARCH_BIN="$(cd "$MARCH_BIN" 2>/dev/null && pwd)" || [ ! -x "$MARCH_BIN/march" ]; then
  echo "no march binary found; set MARCH_BIN to its bin dir"
  echo "NOT REPRODUCED"
  exit 1
fi
MARCH="$MARCH_BIN/march"
cd "$(dirname "$0")"
OUT=.out
clean() { rm -rf "$OUT" .march control_do_block.ll do_block_silent.ll; }
clean; mkdir -p "$OUT"
trap clean EXIT

fail=0
run() { "$MARCH" "$1" >"$OUT/$1.log" 2>&1; }
ok()  { echo "as predicted      $1"; }
bad() { echo "NOT as predicted  $1"; sed 's/^/    /' "$OUT/$2.log"; fail=1; }

exact() { # label, file, exact expected output
  run "$2"
  if [ "$(cat "$OUT/$2.log")" = "$3" ]; then ok "$1"; else bad "$1" "$2"; fi
}
has() { # label, file, text that must appear in the output
  run "$2"
  if grep -qF -- "$3" "$OUT/$2.log"; then ok "$1"; else bad "$1" "$2"; fi
}
compiled() { # label, file, exact expected output of the native binary
  if "$MARCH" --compile "$2" -o "$OUT/$2.bin" >"$OUT/$2.log" 2>&1 \
     && "$OUT/$2.bin" >"$OUT/$2.log" 2>&1 \
     && [ "$(cat "$OUT/$2.log")" = "$3" ]; then ok "$1"; else bad "$1" "$2"; fi
}

# Controls: `)` ends the previous line, so the `(` line is its own statement.
exact    "control: record, then ( line"                control_record_literal.march      2
exact    "control: record update, then ( line"         control_record_update.march       3
exact    "control: interpolated string, then ( line"   control_interpolated_string.march 2
exact    "control: do block, then ( line"              control_do_block.march            end
compiled "control: do block, then ( line (--compile)"  control_do_block.march            end
# Control: an int, identifier, `]`, plain string, `if ... end`, `match ... end`.
exact    "control: other line endings, then ( line"    control_other_endings.march \
  "-10
7
2
3
4
5"

# Bug: `}`, the end of an interpolated string, or `end` ends the previous line.
has      "record literal, then ( line"       record_literal.march      '[not_a_function]'
has      "record update, then ( line"        record_update.march       '[not_a_function]'
has      "interpolated string, then ( line"  interpolated_string.march '[not_a_function]'
exact    "do block, then ( line: silently called" do_block_silent.march \
  "g called with: discarded
end"
compiled "do block, then ( line: silently called (--compile)" do_block_silent.march \
  "g called with: discarded
end"

# Function-level `needs` bounds do not exist in v0.7.0; skip this one there.
run cap_bound.march
if grep -qF 'I only noticed at `needs`' "$OUT/cap_bound.march.log"; then
  echo "skipped           needs () bound: this toolchain has no function-level bounds"
else
  has "needs () bound: cap_bound error" cap_bound.march 'invokes a function value'
fi

if [ "$fail" -eq 0 ]; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
