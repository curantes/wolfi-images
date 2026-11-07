#!/usr/bin/env bash
# Sanity tests for the glibc-dynamic base image (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

check_common

FILES="$(image_files)"
echo "Checking CA bundle and tzdata..."
grep -qx 'etc/ssl/certs/ca-certificates.crt' <<< "$FILES" || fail "no CA bundle"
grep -qx 'usr/share/zoneinfo/UTC' <<< "$FILES" || fail "no tzdata"

# Built on the runner (glibc 2.39), so it only needs symbols any newer glibc has.
echo "Checking dynamically linked C and C++ programs run as an arbitrary UID..."
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
printf '#include <stdio.h>\nint main(void){puts("c ok");return 0;}\n' > "$WORKDIR/hello.c"
printf '#include <iostream>\n#include <stdexcept>\nint main(){try{throw std::runtime_error("x");}catch(...){std::cout<<"cxx ok\\n";}}\n' > "$WORKDIR/hello.cc"
gcc -O2 -o "$WORKDIR/hello-c" "$WORKDIR/hello.c"
g++ -O2 -o "$WORKDIR/hello-cxx" "$WORKDIR/hello.cc"
chmod -R a+rX "$WORKDIR"
for bin in hello-c hello-cxx; do
  OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -v "$WORKDIR:/w:ro,z" --entrypoint "/w/$bin" "$IMAGE")"
  [[ "$OUT" == *" ok" ]] || fail "$bin failed: $OUT"
done

echo "All glibc-dynamic tests passed for $IMAGE ($TAG)."
