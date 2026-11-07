#!/bin/sh
# Runs repro.march on the interpreter and feeds the output to node's JSON.parse.
# Needs node on PATH. Set MARCH_BIN to the directory holding the march binary.
# The last line of output is REPRODUCED or NOT REPRODUCED.
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
cd "$(dirname "$0")" || { echo "NOT REPRODUCED"; exit 1; }
OUT="$("$MARCH_BIN/march" repro.march)" || { echo "march failed"; echo "NOT REPRODUCED"; exit 1; }
printf '%s\n' "$OUT" | od -c | head -2
if printf '%s' "$OUT" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/tmp/jp.$$; then
  echo "JSON.parse accepted it"; echo "NOT REPRODUCED"
else
  grep -m1 SyntaxError /tmp/jp.$$; rm -f /tmp/jp.$$; echo "REPRODUCED"
fi
