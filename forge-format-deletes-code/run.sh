#!/usr/bin/env bash
# Runs `forge format` over a throwaway project holding copies of cases/ and
# control/. The checked-in sources are never formatted in place.
#
# REPRODUCED requires, for every file in cases/: valid before formatting,
# forge format exits 0, the file now contains the literal "...", and it no
# longer parses. Every file in control/ must stay valid with no "...".
set -u
cd "$(dirname "$0")"

MARCH_BIN="${MARCH_BIN:-$HOME/.march/versions/main-b7c963d74/bin}"
# forge format runs `march fmt` through PATH, so march must be on it.
export PATH="$MARCH_BIN:$PATH"

WORK=.work
rm -rf "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/lib"
printf '[package]\nname = "repro"\nversion = "0.1.0"\n' > "$WORK/forge.toml"

fail=0
note() { echo "  FAIL: $*"; fail=1; }

for f in cases/*.march control/*.march; do
  march check "$f" >/dev/null 2>&1 || note "$f does not check before formatting"
  cp "$f" "$WORK/lib/$(basename "$f")"
done

echo "== forge format"
(cd "$WORK" && forge format >/dev/null 2>&1)
rc=$?
echo "exit code: $rc"
[ "$rc" -eq 0 ] || note "forge format exited $rc"

echo "== cases (should be damaged if the bug is present)"
for f in cases/*.march; do
  out="$WORK/lib/$(basename "$f")"
  if grep -qF '...' "$out"; then dots=yes; else dots=no; fi
  if march check "$out" >/dev/null 2>&1; then parses=yes; else parses=no; fi
  printf '%-28s placeholder=%-3s checks_after=%s\n' "$(basename "$f" .march)" "$dots" "$parses"
  grep -F '...' "$out" | sed 's/^/    /'
  [ "$dots" = yes ] || note "$f has no placeholder"
  [ "$parses" = no ] || note "$f still checks after formatting"
done

echo "== controls (should survive)"
for f in control/*.march; do
  out="$WORK/lib/$(basename "$f")"
  if grep -qF '...' "$out"; then dots=yes; else dots=no; fi
  if march check "$out" >/dev/null 2>&1; then parses=yes; else parses=no; fi
  printf '%-28s placeholder=%-3s checks_after=%s\n' "$(basename "$f" .march)" "$dots" "$parses"
  [ "$dots" = no ] || note "$f has a placeholder"
  [ "$parses" = yes ] || note "$f no longer checks"
done

if [ "$fail" -eq 0 ]; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
