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

# A real HTTPS request is the only way to exercise the default CA bundle:
# curl loads it during the TLS handshake, after name resolution.
echo "Checking an HTTPS request with the default CA bundle as an arbitrary UID..."
for attempt in 1 2 3; do
  CODE="$(run_arbitrary -sS --max-time 20 -o /dev/null -w '%{http_code}' https://github.com 2>&1)" && break
  echo "attempt $attempt: $CODE"
  sleep $((attempt * 5))
done
[[ "$CODE" =~ ^(200|301|302)$ ]] || fail "HTTPS request failed: $CODE"

echo "All curl tests passed for $IMAGE ($TAG)."
