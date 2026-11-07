#!/usr/bin/env bash
# Sanity tests for the curl images (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
CID=""
trap '[ -z "$CID" ] || "$ENGINE" rm -f "$CID" > /dev/null; rm -rf "$WORKDIR"' EXIT

check_common

echo "Checking curl version ($STREAM) and features..."
OUT="$(run --version)"
grep -q "^curl $STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"
for feature in HTTP2 SSL; do grep -q "$feature" <<< "$OUT" || fail "missing feature $feature"; done
grep -qE '^Protocols:.* https( |$)' <<< "$OUT" || fail "no https support"

echo "Checking it loads the CA bundle as an arbitrary UID..."
"$ENGINE" run --rm --user "$ARBITRARY_USER" --network none "$IMAGE" -sS --max-time 2 https://example.invalid 2>&1 \
  | grep -qiE 'resolve|could not|failed' || fail "unexpected curl behaviour"
[ -n "$(image_file /etc/ssl/certs/ca-certificates.crt | head -c 100)" ] || fail "empty CA bundle"

echo "All curl tests passed for $IMAGE ($TAG)."
