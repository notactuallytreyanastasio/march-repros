#!/bin/sh
# Compiles the repros for --target js, runs them under node, and compares the
# results with the interpreter. Needs node. Prints REPRODUCED or NOT REPRODUCED last.
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
if ! MARCH_BIN=$(CDPATH= cd -- "$MARCH_BIN" 2>/dev/null && pwd); then
  echo "MARCH_BIN is not a directory"
  echo NOT REPRODUCED
  exit 1
fi
MARCH="$MARCH_BIN/march"
cd "$(dirname "$0")" || exit 1
HERE=$(pwd)
rm -rf build
mkdir build || exit 1
trap 'rm -rf "$HERE/build"' EXIT
cd build || exit 1   # march writes its cache to the cwd, so keep that in build/

js() { # js <name> <out> [march flags]: compile to JS, run under node
  name=$1; out=$2; shift 2
  "$MARCH" --target js "$@" -o "$out.mjs" "../$name.march" >/dev/null 2>"$out.compile.err" || return 1
  node "$out.mjs" >"$out.out" 2>"$out.err"
}

# march --version prints 0.7.0 on main too, so also name the toolchain directory.
echo "toolchain: $(basename "$(dirname "$MARCH_BIN")")"
"$MARCH" --version
ok=1

"$MARCH" ../repro.march >interp.out 2>&1
echo "--- interpreter (reference)"; cat interp.out
[ "$(grep -c ': exact$' interp.out)" = 4 ] || { echo "reference run is not all exact"; ok=0; }

js repro js
echo "--- --target js"; cat js.out
[ "$(grep -c ': WRONG$' js.out)" = 4 ] || ok=0
# 1.22e-16 is sin() of the correct double; a truncated pi gives about -2.07e-13.
grep -q '^sin(pi): -2\.0682310711e-13$' js.out || ok=0
grep -q 'check("Math.pi", 3\.14159265359,' js.mjs || ok=0

js repro nofold --disable-pass opt.fold
echo "--- --target js --disable-pass opt.fold"; cat nofold.out
# Only the folded value recovers: its division now happens at run time.
grep -q '^folded 1.0 /. 240.0: exact$' nofold.out || ok=0
grep -q '^Math.pi: WRONG$' nofold.out || ok=0

js control control
echo "--- control, --target js"; cat control.out
[ "$(grep -c ': exact$' control.out)" = 2 ] || ok=0
grep -q 'WRONG' control.out && ok=0

overflow() { # overflow <name> <printed value> <emitted literal>
  name=$1; want=$2; lit=$3
  "$MARCH" "../$name.march" >"$name.interp" 2>&1
  js "$name" "$name.nofold" --disable-pass opt.fold
  js "$name" "$name"
  echo "--- $name"
  echo "interpreter: $(cat "$name.interp")"
  echo "--target js --disable-pass opt.fold: $(cat "$name.nofold.out")"
  echo "--target js:"
  cat "$name.out"
  sed -n '/^ *const/,/^SyntaxError/p' "$name.err"   # the line above these has a local path
  # The reference results must agree, or this would not be an emitter problem.
  [ "$(cat "$name.interp")" = "$want" ] || { echo "reference run did not print $want"; ok=0; }
  [ "$(cat "$name.nofold.out")" = "$want" ] || ok=0
  grep -qF "march_float_to_string($lit)" "$name.mjs" || ok=0
  grep -q '^SyntaxError' "$name.err" || ok=0
}
overflow overflow_inf inf inf.0
overflow overflow_neg_inf -inf -inf.0
overflow overflow_nan nan nan.0

if [ "$ok" = 1 ]; then echo REPRODUCED; else echo NOT REPRODUCED; fi
