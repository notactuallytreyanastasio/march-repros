#!/bin/sh
# Repro: install.sh's checksum step fails on macOS because /sbin/sha256sum will
# not read a checklist from stdin unless given an explicit "-" operand.
#
# MARCH_BIN is accepted for consistency with the other repros, but nothing here
# runs the march binary: the bug is in install.sh and the host's sha256sum.
#
# Needs network access to raw.githubusercontent.com: install.sh is not included
# here, so it is fetched from pinned commits and checked against pinned hashes.
# After that the installer only ever sees stub-curl.sh, so no release is
# downloaded. Nothing is installed outside ./build.
set -u
if [ -n "${MARCH_BIN:-}" ]; then
  MARCH_BIN="$(cd "$MARCH_BIN" 2>/dev/null && pwd)" || MARCH_BIN=""
fi
cd "$(dirname "$0")"
ROOT="$PWD"
RAW=https://raw.githubusercontent.com/march-language/march
MAIN_COMMIT=b7c963d746dd5e326e04e5acf661a34e4f6b7b2c   # main
MAIN_SHA256=5ed5ea5c6e15a47cf51a876062ca90b0463acd4e6fe9725fb79532199a14dd6b
V070_COMMIT=f6aeb5a833bece07701bb23cd6c61cd7e71655db   # tag v0.7.0
V070_SHA256=ac684457af7738aa846579b67aee5597a2a9f2c8636f1d2e19bce5f8f73d95d9
B="$ROOT/build"
rm -rf "$B"
mkdir -p "$B/work" "$B/fixture/march-v0.0.0/bin" "$B/stub" "$B/fetched"
trap 'rm -rf "$B"' EXIT

fetch() {  # fetch <commit> <sha256> <dest>; a failure here says nothing about the bug
  if ! curl -fsSL -o "$3" "$RAW/$1/install.sh"; then
    echo "could not fetch $RAW/$1/install.sh (this repro needs network access)"
    echo "NOT REPRODUCED"; exit 1
  fi
  if [ "$(shasum -a 256 "$3" | cut -d' ' -f1)" != "$2" ]; then
    echo "unexpected content at $RAW/$1/install.sh"
    echo "NOT REPRODUCED"; exit 1
  fi
}
MAIN_SH="$B/fetched/install-main.sh"
V070_SH="$B/fetched/install-v0.7.0.sh"
fetch "$MAIN_COMMIT" "$MAIN_SHA256" "$MAIN_SH"
fetch "$V070_COMMIT" "$V070_SHA256" "$V070_SH"

if command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum: $(command -v sha256sum) ($(sha256sum --version 2>&1 | head -1))"
else
  echo "sha256sum: none"
fi
echo

# --- part 1: the exact command, against a file whose checksum is correct ------
cd "$B/work"
NAME=march-v0.0.0-darwin-arm64.tar.gz
printf 'hello\n' > "$NAME"
shasum -a 256 "$NAME" > checksums.txt
cat checksums.txt

try() {  # try <label> <shell command>; sets RC and OUT
  OUT="$(sh -c "$2" 2>&1)"; RC=$?
  printf '\n$ %s\n%s\n[exit %s]\n' "$2" "$OUT" "$RC"
}

try bug "grep \" $NAME\\\$\" checksums.txt | sha256sum -c --ignore-missing"
rc_bug=$RC; out_bug=$OUT
try noflag "grep \" $NAME\\\$\" checksums.txt | sha256sum -c"
rc_noflag=$RC
try fileoperand "sha256sum -c --ignore-missing checksums.txt"
rc_file=$RC
try dash "grep \" $NAME\\\$\" checksums.txt | sha256sum -c --ignore-missing -"
rc_dash=$RC
try shasum "grep \" $NAME\\\$\" checksums.txt | shasum -a 256 -c --ignore-missing"
rc_shasum=$RC

# The "-" form must still reject a bad file, or it would not be a fix.
printf 'tampered\n' > "$NAME"
try tampered "grep \" $NAME\\\$\" checksums.txt | sha256sum -c --ignore-missing -"
rc_tampered=$RC

# --- part 2: the real install.sh end to end, with curl stubbed out -------------
# curl is stubbed only for the installer runs, so the fetches above were real.
cd "$B/fixture"
printf '#!/bin/sh\necho stub\n' > march-v0.0.0/bin/march
chmod +x march-v0.0.0/bin/march
tar czf march.tar.gz march-v0.0.0
h="$(shasum -a 256 march.tar.gz | cut -d' ' -f1)"
for p in darwin-arm64 linux-x86_64 linux-aarch64; do
  printf '%s  march-v0.0.0-%s.tar.gz\n' "$h" "$p"
done > checksums.txt
cp "$ROOT/stub-curl.sh" "$B/stub/curl"
chmod +x "$B/stub/curl"
cd "$B"

run_installer() {  # run_installer <script> <march_home>
  env -u GITHUB_TOKEN PATH="$B/stub:$PATH" FIXTURE="$B/fixture" \
    MARCH_VERSION=v0.0.0 MARCH_HOME="$2" sh "$1" 2>&1
}

echo
echo "--- install.sh at b7c963d74, unmodified ---"
inst_out="$(run_installer "$MAIN_SH" "$B/home-stock")"; inst_rc=$?
printf '%s\n[exit %s]\n' "$inst_out" "$inst_rc"

echo
echo "--- install.sh at v0.7.0, unmodified ---"
v070_out="$(run_installer "$V070_SH" "$B/home-v070")"; v070_rc=$?
printf '%s\n[exit %s]\n' "$v070_out" "$v070_rc"

# Control: the same script with only the operand added to line 28.
sed 's/SHACHECK="sha256sum -c --ignore-missing"/SHACHECK="sha256sum -c --ignore-missing -"/' \
  "$MAIN_SH" > "$B/install.patched.sh"
echo
echo "--- same script, with \"-\" added to the sha256sum command ---"
patched_out="$(run_installer "$B/install.patched.sh" "$B/home-patched")"; patched_rc=$?
printf '%s\n[exit %s]\n' "$patched_out" "$patched_rc"
echo

# --- verdict -------------------------------------------------------------------
ok=1
check() { if [ "$2" = yes ]; then echo "ok:   $1"; else echo "FAIL: $1"; ok=0; fi; }
yn() { if eval "$1"; then echo yes; else echo no; fi; }

check "stdin form exits nonzero on a correct file"      "$(yn '[ $rc_bug -ne 0 ]')"
check "stdin form prints usage, not a hash mismatch"    "$(yn 'printf "%s" "$out_bug" | grep -q "^usage: sha256sum"')"
check "same failure without --ignore-missing"           "$(yn '[ $rc_noflag -ne 0 ]')"
check "--ignore-missing accepted with a file operand"   "$(yn '[ $rc_file -eq 0 ]')"
check "--ignore-missing accepted with \"-\" operand"    "$(yn '[ $rc_dash -eq 0 ]')"
check "shasum accepts the stdin form"                   "$(yn '[ $rc_shasum -eq 0 ]')"
check "\"-\" form still rejects a tampered file"        "$(yn '[ $rc_tampered -ne 0 ]')"
check "stock install.sh dies at checksum verification"  "$(yn '[ $inst_rc -ne 0 ] && printf "%s" "$inst_out" | grep -q "checksum verification failed"')"
check "stock install.sh installed nothing"              "$(yn '[ ! -e "$B/home-stock/current" ]')"
check "v0.7.0 install.sh dies at checksum verification" "$(yn '[ $v070_rc -ne 0 ] && printf "%s" "$v070_out" | grep -q "checksum verification failed"')"
check "v0.7.0 install.sh installed nothing"             "$(yn '[ ! -e "$B/home-v070/current" ]')"
check "patched install.sh completes"                    "$(yn '[ $patched_rc -eq 0 ] && [ -x "$B/home-patched/current/bin/march" ]')"

echo
if [ "$ok" = 1 ]; then echo REPRODUCED; else echo "NOT REPRODUCED"; fi
