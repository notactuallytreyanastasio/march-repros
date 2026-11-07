#!/bin/sh
# Prints REPRODUCED if every "accepted" case below builds (and, natively, runs
# as described) and every control is rejected with its expected diagnostic.
# MARCH_BIN: directory holding the march binary. Default: the pinned toolchain
# under ~/.march if present, otherwise the march on PATH.
if [ -z "$MARCH_BIN" ]; then
  if [ -x "$HOME/.march/versions/main-b7c963d74/bin/march" ]; then
    MARCH_BIN="$HOME/.march/versions/main-b7c963d74/bin"
  elif command -v march >/dev/null 2>&1; then
    MARCH_BIN=$(dirname "$(command -v march)")
  fi
fi
BIN_ABS=$(cd "${MARCH_BIN:-/nonexistent}" 2>/dev/null && pwd)
MARCH="$BIN_ABS/march"
cd "$(dirname "$0")" || { echo "NOT REPRODUCED"; exit 2; }
if [ -z "$BIN_ABS" ] || [ ! -x "$MARCH" ]; then
  echo "march not found in '${MARCH_BIN:-}'"
  echo "NOT REPRODUCED"
  exit 1
fi
OUT=out
cleanup() { rm -rf "$OUT" .march ./*.ll; }
cleanup
trap cleanup EXIT
mkdir -p "$OUT"
fail=0

# Per-function bounds do not exist in v0.7.0. Probe for the syntax once, so a
# syntax error in a control is still a failure on a compiler that has them.
cat >"$OUT/probe.march" <<'PROBE'
mod Main do
  fn f() : Int needs () do
    1
  end
  fn main() : () do
    f()
    ()
  end
end
PROBE
if "$MARCH" --check "$OUT/probe.march" 2>&1 | grep -q '\[syntax_error\]'; then
  has_bounds=no
else
  has_bounds=yes
fi

# clock NAME: must compile, and both reads must advance across the busy loop.
clock() {
  if "$MARCH" --compile -o "$OUT/$1" "$1.march" >"$OUT/$1.log" 2>&1 && [ -x "$OUT/$1" ]; then
    r=$("$OUT/$1")
    echo "accepted          $1"
    set -- $r
    echo "  direct, wrapped before the loop: ${1:-?} ${2:-?}; after: ${3:-?} ${4:-?}"
    if [ "$#" -ne 5 ] || [ "$3" -le "$1" ] || [ "$4" -le "$2" ]; then fail=1; fi
  else
    echo "rejected          $1"; sed -n 1,6p "$OUT/$1.log"; fail=1
  fi
}

# rejected NAME SLUG [js]: must fail with [SLUG].
rejected() {
  if [ "$2" = cap_bound ] && [ "$has_bounds" = no ]; then
    echo "skipped           $1 (this compiler has no per-function bounds)"
    return
  fi
  if [ "$3" = js ]; then
    "$MARCH" --target js -o "$OUT/$1.mjs" "$1.march" >"$OUT/$1.log" 2>&1
  else
    "$MARCH" --compile -o "$OUT/$1" "$1.march" >"$OUT/$1.log" 2>&1
  fi
  rc=$?
  if [ "$rc" -ne 0 ] && grep -q "\[$2\]" "$OUT/$1.log"; then
    echo "rejected (ok)     $1 [$2]"
  else
    echo "UNEXPECTED        $1 (exit $rc)"; sed -n 1,6p "$OUT/$1.log"; fail=1
  fi
}

# 1. Monotonic clock reads under `cap pure` and `cap deterministic`.
clock pure_monotonic
rejected control_pure_wallclock pure_violation
clock deterministic_monotonic
rejected control_deterministic_wallclock deterministic_violation
if [ "$has_bounds" = yes ]; then
  clock monotonic_fn_bound
else
  echo "skipped           monotonic_fn_bound (this compiler has no per-function bounds)"
fi

# 2. Stdlib wrappers under `cap pure` / `cap deterministic`, with `needs` declared.
if "$MARCH" --compile -o "$OUT/wrapper_with_needs" wrapper_with_needs.march >"$OUT/w.log" 2>&1 \
   && [ -x "$OUT/wrapper_with_needs" ]; then
  r=$("$OUT/wrapper_with_needs")
  size=$(wc -c <wrapper_with_needs.march | tr -d ' ')
  echo "accepted          wrapper_with_needs"
  echo "  File.read bytes, DateTime.now:" $r
  echo "  size of the file read: $size"
  set -- $r
  [ "${1:-0}" = "$size" ] && [ "${2:-0}" -gt 0 ] || fail=1
else
  echo "rejected          wrapper_with_needs"; sed -n 1,6p "$OUT/w.log"; fail=1
fi
rejected control_pure_direct_builtin pure_violation

# 3. --target js: a no-`needs` module reaches Js.Dom and Js.Canvas. Grep for the
# call sites, not just the imports. The output is not executed.
if "$MARCH" --target js -o "$OUT/js_dom_no_needs.mjs" js_dom_no_needs.march >"$OUT/js.log" 2>&1 \
   && grep -qF 'dom_set_text$clo._0(' "$OUT/js_dom_no_needs.mjs" \
   && grep -qF 'canvas_save$clo._0(' "$OUT/js_dom_no_needs.mjs"; then
  echo "accepted          js_dom_no_needs (--target js; output has DOM and canvas call sites)"
else
  echo "rejected          js_dom_no_needs"; sed -n 1,6p "$OUT/js.log"; fail=1
fi
rejected control_file_no_needs cap_ceiling js
rejected control_js_dom_fn_bound cap_bound js
rejected control_js_dom_narrow_grant cap_grant_exceeded js

if [ "$fail" -eq 0 ]; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
