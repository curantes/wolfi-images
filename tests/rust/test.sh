#!/usr/bin/env bash
# Sanity tests for the Rust toolchain image (-dev only).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

check_common

echo "Checking Rust version ($STREAM)..."
OUT="$("$ENGINE" run --rm --entrypoint /usr/bin/rustc "$IMAGE" --version)"
[[ "$OUT" == "rustc $STREAM."* ]] || fail "unexpected version: $OUT"

echo "Checking a cargo build as an arbitrary UID..."
OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -e HOME=/tmp -e CARGO_HOME=/tmp/cargo \
  --entrypoint /bin/sh "$IMAGE" -c \
  'cd /tmp && cargo new --quiet --vcs none hello && cd hello && cargo build --quiet --offline && ./target/debug/hello')"
[ "$OUT" = "Hello, world!" ] || fail "cargo build failed: $OUT"

echo "Checking clippy and rustfmt..."
succeeds /usr/bin/cargo-clippy --version || fail "clippy missing"
succeeds /usr/bin/rustfmt --version || fail "rustfmt missing"

echo "All rust tests passed for $IMAGE ($TAG)."
