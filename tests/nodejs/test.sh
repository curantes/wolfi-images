#!/usr/bin/env bash
# Sanity tests for the Node.js images (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

check_common

echo "Checking Node.js version ($STREAM)..."
OUT="$(run --version)"
[[ "$OUT" == "v$STREAM."* ]] || fail "unexpected version: $OUT"

echo "Checking crypto, zlib, ICU and the CA store as an arbitrary UID..."
OUT="$(run_arbitrary -e '
const crypto = require("crypto"), zlib = require("zlib"), tls = require("tls");
if (!crypto.createHash("sha256").update("x").digest("hex")) throw 1;
if (zlib.gunzipSync(zlib.gzipSync("ok")).toString() !== "ok") throw 2;
if (new Intl.NumberFormat("sv-SE").format(1234.5) !== "1 234,5") throw 3;
if (tls.rootCertificates.length === 0) throw 4;
console.log("ok")')"
[ "$OUT" = ok ] || fail "runtime check failed: $OUT"

case "$VARIANT" in
  dev)
    echo "Checking npm..."
    "$ENGINE" run --rm --entrypoint /bin/sh "$IMAGE" -c 'cd /tmp && npm init -y > /dev/null && npm --version' > /dev/null \
      || fail "npm does not work"
    ;;
  "")
    ! succeeds /usr/bin/npm --version || fail "default variant ships npm"
    ;;
esac

echo "All nodejs tests passed for $IMAGE ($TAG)."
