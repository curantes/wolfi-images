#!/usr/bin/env bash
# Sanity tests for the static base image.
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

check_common

FILES="$(image_files)"
echo "Checking CA bundle, tzdata and nonroot user..."
grep -qx 'etc/ssl/certs/ca-certificates.crt' <<< "$FILES" || fail "no CA bundle"
grep -qx 'usr/share/zoneinfo/UTC' <<< "$FILES" || fail "no tzdata"
image_file /etc/passwd | grep -q '^nonroot:x:65532:65532:' || fail "no nonroot user in /etc/passwd"

echo "Checking there is no libc..."
! grep -qE '(^|/)(ld-linux[^/]*\.so[^/]*|libc\.so[^/]*)$' <<< "$FILES" || fail "static image ships a libc"

echo "Checking a static binary runs as an arbitrary UID and reads the CA bundle..."
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cat > "$WORKDIR/hello.c" <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char line[128];
  FILE *f = fopen("/etc/ssl/certs/ca-certificates.crt", "r");
  if (!f) return 1;
  while (fgets(line, sizeof line, f))
    if (strstr(line, "BEGIN CERTIFICATE")) { puts("ok"); return 0; }
  return 2;
}
C
gcc -static -O2 -o "$WORKDIR/hello" "$WORKDIR/hello.c"
chmod -R a+rX "$WORKDIR"
OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -v "$WORKDIR:/w:ro,z" --entrypoint /w/hello "$IMAGE")"
[ "$OUT" = ok ] || fail "static binary failed: $OUT"

echo "All static tests passed for $IMAGE ($TAG)."
