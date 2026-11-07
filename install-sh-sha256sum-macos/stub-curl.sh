#!/bin/sh
# Stand-in for curl, installed as `curl` on PATH by run.sh, so install.sh
# runs unmodified against a local fixture instead of GitHub. FIXTURE is set by run.sh.
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *)  url="$1"; shift ;;
  esac
done
case "$url" in
  */releases/tags/*)
    for p in darwin-arm64 linux-x86_64 linux-aarch64; do
      printf '"browser_download_url": "https://example.invalid/march-v0.0.0-%s.tar.gz"\n' "$p"
    done
    printf '"browser_download_url": "https://example.invalid/march-v0.0.0-checksums.txt"\n'
    ;;
  *.tar.gz)        cp "$FIXTURE/march.tar.gz" "$out" ;;
  *checksums.txt)  cat "$FIXTURE/checksums.txt" ;;
  *)               echo "stub curl: unexpected url $url" >&2; exit 22 ;;
esac
