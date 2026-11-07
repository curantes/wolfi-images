#!/usr/bin/env bash
# Tests policy/verify-wolfi-images.yaml with the Kyverno CLI against the live
# registry and Rekor (no cluster needed).
#
# 1. Provenance and VSA: a published image passes; an unknown digest fails.
# 2. EOL rules for IMAGE (default python:3.12): "now" is pinned to dates
#    relative to the image's EOL label to exercise supported, deprecated
#    (warn only) and frozen (blocked).
#
# Usage: policy/test.sh [image]   (needs kyverno, curl, jq, python3 with PyYAML)
set -euo pipefail
cd "$(dirname "$0")"
KYVERNO="${KYVERNO:-kyverno}"
IMAGE="${1:-ghcr.io/curantes/wolfi-images/python:3.12}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# result <policy> <pod> <rule>: Pass/Fail/Error for one rule
result() {
  # kyverno exits non-zero when any rule fails; the table is what we check.
  { "$KYVERNO" apply "$1" --resource "$WORK/pods.yaml" --registry -t 2>/dev/null || true; } \
    | awk -F'│' -v pod="default/Pod/$2" -v rule="$3" \
        '{gsub(/ +/, "", $4); gsub(/ +/, "", $5); gsub(/ +/, "", $6)} $4 == rule && $5 == pod {print $6; exit}'
}

REPO="${IMAGE%:*}"
cat > "$WORK/pods.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: published, namespace: default}
spec:
  containers:
    - {name: app, image: "$IMAGE"}
---
apiVersion: v1
kind: Pod
metadata: {name: unknown-digest, namespace: default}
spec:
  containers:
    - {name: app, image: "$REPO@sha256:$(printf '0%.0s' {1..64})"}
EOF

echo "Provenance and VSA..."
[ "$(result verify-wolfi-images.yaml published verify-provenance-and-approval)" = Pass ] \
  || fail "published image $IMAGE did not verify"
[ "$(result verify-wolfi-images.yaml unknown-digest verify-provenance-and-approval)" = Fail ] \
  || fail "unknown digest was not rejected"

# EOL label of the image, read the way the policy reads it
NAME_TAG="${IMAGE#ghcr.io/}"
TOKEN="$(curl -fsS "https://ghcr.io/token?scope=repository:${NAME_TAG%:*}:pull" | jq -r .token)"
API="https://ghcr.io/v2/${NAME_TAG%:*}"
MANIFEST="$(curl -fsS -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/vnd.oci.image.index.v1+json' "$API/manifests/${NAME_TAG##*:}" | jq -r '.manifests[0].digest')"
CONFIG="$(curl -fsS -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' "$API/manifests/$MANIFEST" | jq -r .config.digest)"
EOL="$(curl -fsSL -H "Authorization: Bearer $TOKEN" "$API/blobs/$CONFIG" \
  | jq -r '.config.Labels["io.github.curantes.wolfi-images.eol"] // empty')"
[ -n "$EOL" ] || fail "$IMAGE has no EOL label"

check_at() { # check_at <label> <now> <expected warn> <expected block>
  python3 -I - "$2" "$WORK/t.yaml" <<'EOF'
import json, sys, yaml
policy = yaml.safe_load(open("verify-wolfi-images.yaml"))
policy["spec"]["rules"] = [r for r in policy["spec"]["rules"] if "validate" in r]
text = json.dumps(policy).replace("time_now_utc()", "'%s'" % sys.argv[1])
yaml.safe_dump(json.loads(text), open(sys.argv[2], "w"))
EOF
  local warn block
  warn="$(result "$WORK/t.yaml" published warn-deprecated-streams)"
  block="$(result "$WORK/t.yaml" published block-frozen-streams)"
  echo "  $1 ($2): warn=$warn block=$block"
  [ "$warn" = "$3" ] && [ "$block" = "$4" ] || fail "expected warn=$3 block=$4"
}

echo "EOL rules (EOL $EOL)..."
day() { date -u -d "$EOL $1 days" +%Y-%m-%dT00:00:00Z; }
check_at supported "$(day -1)" Pass Pass
check_at deprecated "$(day +10)" Fail Pass
check_at frozen "$(day +31)" Fail Fail

echo "All policy tests passed."
