#!/usr/bin/env bash
# Sanity tests for the Go toolchain image (-dev only).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

check_common

echo "Checking Go version ($STREAM)..."
OUT="$(run version)"
[[ "$OUT" == "go version go$STREAM"* ]] || fail "unexpected version: $OUT"

cat > "$WORKDIR/main.go" <<'GO'
package main

/*
int answer(void) { return 42; }
*/
import "C"
import "fmt"

func main() { fmt.Println("cgo", C.answer()) }
GO
printf 'module hello\n\ngo %s\n' "$STREAM" > "$WORKDIR/go.mod"
chmod -R a+rX "$WORKDIR"

echo "Checking a cgo build as an arbitrary UID..."
OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -e HOME=/tmp -e GOCACHE=/tmp/cache -e GOPATH=/tmp/go \
  -v "$WORKDIR:/src:ro,z" --entrypoint /bin/sh "$IMAGE" -c \
  'cp -r /src /tmp/app && cd /tmp/app && CGO_ENABLED=1 go build -o /tmp/hello . && /tmp/hello')"
[ "$OUT" = "cgo 42" ] || fail "cgo build failed: $OUT"

echo "Checking git is available..."
succeeds /usr/bin/git --version || fail "git missing"

echo "All go tests passed for $IMAGE ($TAG)."
