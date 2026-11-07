#!/usr/bin/env bash
# Write or refresh the apko lock of every generated config (or the given ones).
# Usage: scripts/lock.sh [generated/<name>/<tag>.apko.yaml ...]
#   APKO=/path/to/apko to use a specific binary.
set -euo pipefail
cd "$(dirname "$0")/.."
APKO="${APKO:-apko}"

if [ "$#" -eq 0 ]; then
  mapfile -t CONFIGS < <(jq -r '.builds[].config' generated/catalog.json)
else
  CONFIGS=("$@")
fi

for config in "${CONFIGS[@]}"; do
  lock="${config%.apko.yaml}.lock.json"
  echo "Locking $config"
  "$APKO" lock "$config" --output "$lock" --log-level warn
done
