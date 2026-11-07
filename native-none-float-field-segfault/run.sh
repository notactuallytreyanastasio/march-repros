#!/bin/sh
# Usage: MARCH_BIN=<dir containing march> ./run.sh
# Prints REPRODUCED or NOT REPRODUCED as its last line.
cd "$(dirname "$0")" || exit 2
MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
case "$MARCH_BIN" in /*) ;; *) MARCH_BIN="$PWD/$MARCH_BIN" ;; esac
MARCH="$MARCH_BIN/march"
# Build in a scratch copy: the compiler writes .ll files and a .march dir beside
# the source and into the working directory.
rm -rf build
mkdir -p build
cp ./*.march build/
cd build || exit 2
ok=1

native() { # name -> sets out, rc
  if ! "$MARCH" --compile -o "$1" "$1.march" >"$1.log" 2>&1; then
    echo "$1: COMPILE FAILED"; cat "$1.log"; ok=0; out=""; rc=-1; return
  fi
  out=$("./$1" 2>&1); rc=$?
}

# Crashes natively, while the interpreter prints the expected text.
expect_crash() { # name expected-stdout
  native "$1"
  interp=$("$MARCH" "$1.march" 2>&1)
  echo "$1: native exit=$rc, interpreter said: $interp"
  echo "$out" | sed 's/^/    /'
  [ "$interp" = "$2" ] || { echo "  interpreter output was not '$2'"; ok=0; }
  case "$out" in
    *SIGSEGV*) [ "$rc" -ne 0 ] || ok=0 ;;
    *) echo "  no SIGSEGV"; ok=0 ;;
  esac
}

# Correct natively.
expect_ok() { # name expected-stdout
  native "$1"
  echo "$1: native exit=$rc, output: $out"
  { [ "$rc" -eq 0 ] && [ "$out" = "$2" ]; } || { echo "  control failed"; ok=0; }
}

echo "== bug programs"
expect_crash repro none
expect_crash repro_unit none
expect_crash repro_nested none
expect_crash repro_record 3
echo "== controls"
expect_ok control_annotated none
expect_ok control_direct none
expect_ok control_int_payload none
expect_ok control_record_annotated 3

# Informational only: the JS backend does not decide the verdict.
if command -v node >/dev/null 2>&1; then
  echo "== JS backend (informational)"
  for p in repro repro_record; do
    if "$MARCH" --target js -o "$p.mjs" "$p.march" >"$p.js.log" 2>&1; then
      echo "$p: js output: $(node "$p.mjs" 2>&1)"
    else
      echo "$p: js compile failed"
    fi
  done
fi

cd .. && rm -rf build
if [ "$ok" -eq 1 ]; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
