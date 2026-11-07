#!/bin/sh
# Compares string_to_float on the interpreter, native and JS targets.
# Needs node on PATH. Set MARCH_BIN to the directory holding the march binary.
# The last line of output is REPRODUCED or NOT REPRODUCED.
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
if ! MARCH_BIN="$(CDPATH= cd -- "$MARCH_BIN" 2>/dev/null && pwd)"; then
  echo "MARCH_BIN is not a directory"
  echo "NOT REPRODUCED"
  exit 1
fi
MARCH="$MARCH_BIN/march"
cd "$(dirname "$0")" || { echo "NOT REPRODUCED"; exit 1; }
OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/js_repro" "$OUT/js_control"

# run <name>: writes $OUT/<name>.{interp,native,js}
run() {
  "$MARCH" "$1.march" > "$OUT/$1.interp" 2> "$OUT/$1.interp.err"
  "$MARCH" --compile "$1.march" -o "$OUT/$1.bin" > "$OUT/$1.native.log" 2>&1
  "./$OUT/$1.bin" > "$OUT/$1.native" 2>&1
  "$MARCH" --target js "$1.march" -o "$OUT/js_$1/$1.mjs" > "$OUT/$1.js.log" 2>&1
  node "$OUT/js_$1/$1.mjs" > "$OUT/$1.js" 2>&1
}

run repro
run control

for f in repro control; do
  echo "== $f.march (interpreter | native | js)"
  paste -d'|' "$OUT/$f.interp" "$OUT/$f.native" "$OUT/$f.js"
done

has() { grep -qxF -- "$2" "$OUT/$1"; }

result=REPRODUCED
# Controls must agree and be non-empty, or the comparison proves nothing.
[ -s "$OUT/control.interp" ] || result="NOT REPRODUCED"
cmp -s "$OUT/control.interp" "$OUT/control.native" || result="NOT REPRODUCED"
cmp -s "$OUT/control.interp" "$OUT/control.js" || result="NOT REPRODUCED"
# Interpreter and native agree on the JS-divergent inputs.
for f in repro.interp repro.native; do
  has "$f" '[inf] -> Some(inf)'      || result="NOT REPRODUCED"
  has "$f" '[infinity] -> Some(inf)' || result="NOT REPRODUCED"
  has "$f" '[INF] -> Some(inf)'      || result="NOT REPRODUCED"
  has "$f" '[nan] -> Some(nan)'      || result="NOT REPRODUCED"
  has "$f" '[NaN] -> Some(nan)'      || result="NOT REPRODUCED"
  has "$f" '[] -> None'              || result="NOT REPRODUCED"
  has "$f" '[tab] -> None'           || result="NOT REPRODUCED"
  has "$f" '[0o17] -> None'          || result="NOT REPRODUCED"
  has "$f" '[0x1p3] -> Some(8.)'     || result="NOT REPRODUCED"
  has "$f" 'toml: { x = inf, y = nan }' || result="NOT REPRODUCED"
done
# JS differs on each of them.
has repro.js '[inf] -> None'       || result="NOT REPRODUCED"
has repro.js '[infinity] -> None'  || result="NOT REPRODUCED"
has repro.js '[INF] -> None'       || result="NOT REPRODUCED"
has repro.js '[nan] -> None'       || result="NOT REPRODUCED"
has repro.js '[NaN] -> None'       || result="NOT REPRODUCED"
has repro.js '[] -> Some(0.)'      || result="NOT REPRODUCED"
has repro.js '[tab] -> Some(0.)'   || result="NOT REPRODUCED"
has repro.js '[0o17] -> Some(15.)' || result="NOT REPRODUCED"
has repro.js '[0x1p3] -> None'     || result="NOT REPRODUCED"
has repro.js 'toml: { x = 0., y = 0. }' || result="NOT REPRODUCED"

rm -rf "$OUT" .march repro.ll control.ll
echo "$result"
