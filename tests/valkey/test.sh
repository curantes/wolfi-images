#!/usr/bin/env bash
# Sanity tests for the Valkey images (default and -dev variants).
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

echo "Checking Valkey version ($STREAM)..."
OUT="$(run --version)"
grep -qE "v=$STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"

echo "Checking the server as an arbitrary UID with valkey-cli..."
CID="$(start_server --user "$ARBITRARY_USER" --tmpfs /data:uid=1000700000,gid=0 "$IMAGE")"
wait_for_log "$CID" 'Ready to accept connections' 30 || fail "valkey did not start"
CLI=("$ENGINE" run --rm --network "container:$CID" --entrypoint /usr/bin/valkey-cli "$IMAGE")
"${CLI[@]}" SET greeting ok > /dev/null || fail "SET failed"
OUT="$("${CLI[@]}" GET greeting)"
[ "$OUT" = ok ] || fail "GET returned '$OUT'"

echo "All valkey tests passed for $IMAGE ($TAG)."
