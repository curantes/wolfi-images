#!/usr/bin/env bash
# Sanity tests for the HAProxy images (default and -dev variants).
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

echo "Checking HAProxy version ($STREAM)..."
OUT="$(run -v)"
grep -q "HAProxy version $STREAM\." <<< "$OUT" || fail "unexpected version: $OUT"

cat > "$WORKDIR/haproxy.cfg" <<'CFG'
global
  log stdout format raw local0
defaults
  mode http
  timeout connect 5s
  timeout client 30s
  timeout server 30s
frontend web
  bind :8080
  http-request return status 200 content-type text/plain string "ok"
CFG
chmod -R a+rX "$WORKDIR"

echo "Checking it serves a mounted configuration as an arbitrary UID..."
CID="$(start_server --user "$ARBITRARY_USER" -p 127.0.0.1::8080 \
  -v "$WORKDIR/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro,z" "$IMAGE")"
PORT="$("$ENGINE" port "$CID" 8080/tcp | head -n1 | sed 's/.*://')"
for _ in $(seq 1 20); do OUT="$(curl -fsS "http://127.0.0.1:$PORT/" 2>/dev/null)" && break; sleep 1; done
[ "${OUT:-}" = ok ] || { "$ENGINE" logs "$CID" >&2; fail "haproxy did not answer"; }

echo "All haproxy tests passed for $IMAGE ($TAG)."
