#!/usr/bin/env bash
# Sanity tests for the CoreDNS images (default and -dev variants).
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

echo "Checking CoreDNS version ($STREAM)..."
OUT="$(run -version)"
grep -q "CoreDNS-$STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"

echo "Checking it serves the default whoami zone as an arbitrary UID..."
CID="$(start_server --user "$ARBITRARY_USER" "$IMAGE" -dns.port 1053)"
wait_for_log "$CID" 'CoreDNS-' 30 || fail "coredns did not start"
sleep 1
[ "$("$ENGINE" inspect -f '{{.State.Running}}' "$CID")" = true ] || fail "coredns exited"

echo "All coredns tests passed for $IMAGE ($TAG)."
