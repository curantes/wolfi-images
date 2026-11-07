#!/usr/bin/env bash
# Print the upstream version of a build from its lock (e.g. 3.12.16) and check
# that it belongs to the stream. The same version must be locked on every
# architecture.
# Usage: scripts/version.sh <lock.json> <package> <stream>
set -euo pipefail
LOCK="${1:?lock}" PACKAGE="${2:?package}" STREAM="${3:?stream}"

mapfile -t VERSIONS < <(jq -r --arg p "$PACKAGE" \
  '[.contents.packages[] | select(.name == $p) | .version] | unique | .[]' "$LOCK")
if [ "${#VERSIONS[@]}" -ne 1 ]; then
  echo "Expected one locked version of $PACKAGE in $LOCK, got: ${VERSIONS[*]:-none}" >&2
  exit 1
fi
# Wolfi versions look like 3.12.16_git20261030-r0
VERSION="${VERSIONS[0]%-r*}"
VERSION="${VERSION%%_*}"
if [ "$VERSION" != "$STREAM" ] && [[ "$VERSION" != "$STREAM."* ]]; then
  echo "Locked $PACKAGE $VERSION does not belong to stream $STREAM" >&2
  exit 1
fi
echo "$VERSION"
