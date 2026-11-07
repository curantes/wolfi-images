#!/usr/bin/env bash
# Sanity tests for the RabbitMQ images (default and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
CID=""
trap '[ -z "$CID" ] || "$ENGINE" rm -f "$CID" > /dev/null; rm -rf "$WORKDIR"' EXIT

# The server and CLI are shell scripts: the default variant ships busybox sh.
ALLOW_SHELL=1 check_common
succeeds /bin/sh -c true || fail "rabbitmq needs /bin/sh"

echo "Checking the broker starts as non-root and answers rabbitmqctl..."
CID="$(start_server --hostname rabbit "$IMAGE")"
wait_for_log "$CID" 'Server startup complete' 120 || fail "rabbitmq did not start"
OUT="$("$ENGINE" exec "$CID" rabbitmqctl status 2>&1)"
grep -q "RabbitMQ version: $STREAM\." <<< "$OUT" || fail "unexpected status: $OUT"
"$ENGINE" exec "$CID" rabbitmq-diagnostics -q check_port_connectivity > /dev/null \
  || fail "AMQP port check failed"

echo "All rabbitmq tests passed for $IMAGE ($TAG)."
