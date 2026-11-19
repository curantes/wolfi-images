#!/usr/bin/env bash
# Sanity tests for the PHP images (CLI default, -fpm and -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

check_common

EXTENSIONS="bcmath ctype curl dom fileinfo iconv intl mbstring mysqlnd openssl pdo_mysql pdo_pgsql pdo_sqlite posix simplexml sodium xml xmlreader xmlwriter zip"

case "$VARIANT" in
  fpm)
    echo "Checking PHP-FPM version ($STREAM) and configuration..."
    OUT="$(run -v)"
    [[ "$OUT" == "PHP $STREAM."* ]] || fail "unexpected version: $OUT"
    run -t > /dev/null 2>&1 || fail "php-fpm -t failed"
    MODULES="$(run -m)"

    echo "Checking PHP-FPM serves on port 9000 as an arbitrary UID..."
    CID="$("$ENGINE" run -d --user "$ARBITRARY_USER" "$IMAGE")"
    for _ in $(seq 1 20); do
      "$ENGINE" logs "$CID" 2>&1 | grep -q 'ready to handle connections' && break
      sleep 1
    done
    LOGS="$("$ENGINE" logs "$CID" 2>&1)"
    "$ENGINE" rm -f "$CID" > /dev/null
    grep -q 'ready to handle connections' <<< "$LOGS" || fail "php-fpm did not start: $LOGS"
    ;;
  *)
    echo "Checking PHP version ($STREAM)..."
    OUT="$(run -v)"
    [[ "$OUT" == "PHP $STREAM."* ]] || fail "unexpected version: $OUT"
    MODULES="$(run -m)"

    echo "Checking a script as an arbitrary UID..."
    OUT="$(run_arbitrary -r '
      $db = new PDO("sqlite::memory:");
      $db->exec("CREATE TABLE t (v TEXT)");
      $db->exec("INSERT INTO t VALUES (\"ok\")");
      echo $db->query("SELECT v FROM t")->fetchColumn(),
        strlen(sodium_crypto_secretbox_keygen()) === 32 ? "" : " sodium",
        mb_strtoupper("å") === "Å" ? "" : " mbstring";')"
    [ "$OUT" = ok ] || fail "script failed: $OUT"
    ;;
esac

echo "Checking extensions..."
for ext in $EXTENSIONS; do
  grep -qix "$ext" <<< "$MODULES" || fail "missing extension $ext"
done
grep -qi 'opcache' <<< "$MODULES" || fail "missing opcache"

if [ "$VARIANT" = dev ]; then
  echo "Checking Composer..."
  succeeds /usr/bin/composer --version || fail "composer missing"
else
  ! succeeds /usr/bin/composer --version || fail "variant '${VARIANT:-default}' ships composer"
fi

echo "All php tests passed for $IMAGE ($TAG)."
