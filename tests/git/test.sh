#!/usr/bin/env bash
# Sanity tests for the git images (default and -dev variants).
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

echo "Checking git version ($STREAM)..."
OUT="$(run --version)"
[[ "$OUT" == "git version $STREAM."* ]] || fail "unexpected version: $OUT"

echo "Checking init, commit and clone as an arbitrary UID..."
OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -e HOME=/tmp -w /tmp "$IMAGE" \
  -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main \
  init -q repo 2>&1)" || fail "git init failed: $OUT"

cat > "$WORKDIR/script" <<'SH'
set -e
git init -q -b main /tmp/a
cd /tmp/a
echo hi > f && git add f
git -c user.name=t -c user.email=t@example.invalid commit -qm init
git clone -q /tmp/a /tmp/b
cat /tmp/b/f
SH
chmod -R a+rX "$WORKDIR"
if [ "$VARIANT" = dev ]; then
  OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -e HOME=/tmp -v "$WORKDIR:/w:ro,z" --entrypoint /bin/sh "$IMAGE" /w/script)"
  [ "$OUT" = hi ] || fail "commit/clone failed: $OUT"
fi

echo "Checking the ssh client for SSH remotes..."
succeeds /usr/bin/ssh -V || fail "no ssh client"

echo "All git tests passed for $IMAGE ($TAG)."
