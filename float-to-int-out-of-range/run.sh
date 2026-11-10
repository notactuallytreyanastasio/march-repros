#!/bin/sh
# Runs float_to_int, float_truncate, float_floor, float_ceil and float_round on
# out-of-range Floats, NaN and the infinities, on the interpreter, native and JS.
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
HERE=$(pwd)
rm -rf build
mkdir -p build/js || { echo "NOT REPRODUCED"; exit 1; }
trap 'rm -rf "$HERE/build"' EXIT
cd build || exit 1   # march writes its cache to the cwd, so keep that in build/

# run <name>: writes <name>.{interp,native,js}, each followed by an exit line
run() {
  cp "../$1.march" . || return 1   # --compile writes <name>.ll next to the source
  "$MARCH" "$1.march" > "$1.interp" 2>&1
  echo "exit $?" >> "$1.interp"
  "$MARCH" --compile "$1.march" -o "$1.bin" > "$1.native.log" 2>&1
  "./$1.bin" > "$1.native" 2>&1
  echo "exit $?" >> "$1.native"
  "$MARCH" --target js "$1.march" -o "js/$1.mjs" > "$1.js.log" 2>&1
  node "js/$1.mjs" > "$1.js" 2>&1
  echo "exit $?" >> "$1.js"
}

run repro
run control

for f in repro control; do
  for t in interp native js; do
    echo "== $f.march on $t"
    cat "$f.$t"
  done
done

has() { grep -qF -- "$2" "$1"; }

result=REPRODUCED
# Controls must agree and be non-empty, or the comparison proves nothing.
has control.interp "2.5  to_int=2" || result="NOT REPRODUCED"
cmp -s control.interp control.native || result="NOT REPRODUCED"
cmp -s control.interp control.js || result="NOT REPRODUCED"
# No target refuses an out-of-range conversion: every one exits 0.
for t in interp native js; do
  has "repro.$t" "exit 0" || result="NOT REPRODUCED"
done
# The interpreter and native print wrapped values; JS prints values that are not Ints.
for t in interp native; do
  has "repro.$t" "1e20  to_int=-1 " || result="NOT REPRODUCED"
  has "repro.$t" "2^62  to_int=-4611686018427387904 " || result="NOT REPRODUCED"
  has "repro.$t" "nan  to_int=0 " || result="NOT REPRODUCED"
done
has repro.js "1e20  to_int=100000000000000000000 " || result="NOT REPRODUCED"
has repro.js "nan  to_int=NaN " || result="NOT REPRODUCED"
has repro.js "inf  to_int=Infinity " || result="NOT REPRODUCED"

echo "$result"
