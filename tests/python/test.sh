#!/usr/bin/env bash
# Sanity tests for the Python images (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

check_common

echo "Checking Python version ($STREAM)..."
OUT="$(run --version)"
[[ "$OUT" == "Python $STREAM."* ]] || fail "unexpected version: $OUT"

echo "Checking stdlib modules and the CA trust store as an arbitrary UID..."
OUT="$(run_arbitrary -c '
import bz2, ctypes, decimal, hashlib, lzma, sqlite3, ssl, uuid, zlib
ctx = ssl.create_default_context()
print(len(ctx.get_ca_certs()) > 0 or bool(open("/etc/ssl/certs/ca-certificates.crt").read().count("BEGIN CERTIFICATE")))')"
[ "$OUT" = "True" ] || fail "stdlib or CA trust store check failed: $OUT"

echo "Checking venv..."
case "$VARIANT" in
  dev)
    # pip ships only in -dev; --version needs no network.
    run -c '
import subprocess, venv
venv.create("/tmp/venv", with_pip=True)
subprocess.run(["/tmp/venv/bin/python", "-m", "pip", "--version"], check=True)' > /dev/null
    "$ENGINE" run --rm --entrypoint /bin/sh "$IMAGE" -c 'command -v gcc && python3 -c "import sysconfig; print(sysconfig.get_paths()[\"include\"])"' > /dev/null \
      || fail "-dev must ship gcc and Python headers"
    ;;
  "")
    run -c 'import venv; venv.create("/tmp/venv", with_pip=False)' > /dev/null
    ! succeeds /usr/bin/pip --version || fail "default variant ships pip"
    ;;
esac

echo "All python tests passed for $IMAGE ($TAG)."
