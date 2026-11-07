#!/bin/sh
# Compiles repro.march with lib/ on MARCH_LIB_PATH. The last line is REPRODUCED or NOT REPRODUCED.
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
cd "$(dirname "$0")" || { echo "NOT REPRODUCED"; exit 1; }
OUT="$(MARCH_LIB_PATH=lib "$MARCH_BIN/march" repro.march 2>&1)"
printf '%s\n' "$OUT" | head -12
if printf '%s' "$OUT" | grep -q 'expected `{ table : Table }` but got `{ table : Table }`'; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
