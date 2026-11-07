#!/bin/sh
# Compiles each program for the interpreter and for --target js, compares.
# Usage: ./run.sh    (MARCH_BIN = directory holding the march binary)
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
MARCH="$MARCH_BIN/march"
cd "$(dirname "$0")" || exit 1
OUT=out
rm -rf "$OUT" .march
mkdir -p "$OUT"
trap 'rm -rf "$OUT" .march' EXIT

"$MARCH" --version

# Each prints the program output (stdout and stderr).
interp() { MARCH_LIB_PATH=lib "$MARCH" "$1.march" 2>&1; }
js() {
  MARCH_LIB_PATH=lib "$MARCH" --target js -o "$OUT/$1.mjs" "$1.march" >"$OUT/$1.log" 2>&1 \
    || { echo "COMPILE FAILED"; cat "$OUT/$1.log"; return; }
  node "$OUT/$1.mjs" 2>&1
}

for p in control repro repro_lib repro_stdlib; do
  i=$(interp "$p")
  j=$(js "$p")
  echo "--- $p (interpreter)"; echo "$i"
  echo "--- $p (--target js)"; echo "$j" | head -6
  if [ "$i" = "$j" ]; then r=same; else r=differ; fi
  eval "r_$p=$r"
done

i_ok=$(interp repro)
j_out=$(js repro)
echo "---"
echo "control: $r_control, repro: $r_repro, repro_lib: $r_repro_lib, repro_stdlib: $r_repro_stdlib"
if [ "$i_ok" = "7" ] && [ "$j_out" = "[object Object]" ] \
   && [ "$r_control" = same ] && [ "$r_repro_lib" = differ ]; then
  echo "REPRODUCED"
else
  echo "NOT REPRODUCED"
fi
