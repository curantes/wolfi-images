#!/usr/bin/env bash
# Sanity tests for the nginx images (default and -dev variants).
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

echo "Checking nginx version ($STREAM)..."
OUT="$(run -v 2>&1)"
grep -q "nginx/$STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"

echo "Checking the configuration and the default page on 8080 as an arbitrary UID..."
run -t > /dev/null 2>&1 || fail "nginx -t failed"
CID="$(start_server --user "$ARBITRARY_USER" -p 127.0.0.1::8080 "$IMAGE")"
PORT="$("$ENGINE" port "$CID" 8080/tcp | head -n1 | sed 's/.*://')"
for _ in $(seq 1 20); do CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)"; [ "$CODE" = 200 ] && break; sleep 1; done
[ "${CODE:-}" = 200 ] || { "$ENGINE" logs "$CID" >&2; fail "nginx answered ${CODE:-nothing}"; }

echo "All nginx tests passed for $IMAGE ($TAG)."
