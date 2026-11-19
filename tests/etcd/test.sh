#!/usr/bin/env bash
# Sanity tests for the etcd images (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
CID=""
trap '[ -z "$CID" ] || "$ENGINE" rm -f "$CID" > /dev/null; rm -rf "$WORKDIR"' EXIT

ALLOW_SHELL=0 check_common

echo "Checking etcd version ($STREAM)..."
OUT="$(run --version)"
grep -q "etcd Version: $STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"

echo "Checking a single-member cluster as an arbitrary UID with etcdctl..."
CID="$(start_server --user "$ARBITRARY_USER" --tmpfs /var/lib/etcd:uid=1000700000,gid=0 "$IMAGE")"
wait_for_log "$CID" 'ready to serve client requests' 60 || fail "etcd did not start"
CTL=("$ENGINE" run --rm --network "container:$CID" --entrypoint /usr/bin/etcdctl "$IMAGE")
"${CTL[@]}" put greeting ok > /dev/null || fail "etcdctl put failed"
OUT="$("${CTL[@]}" get --print-value-only greeting)"
[ "$OUT" = ok ] || fail "etcdctl get returned '$OUT'"

echo "All etcd tests passed for $IMAGE ($TAG)."
