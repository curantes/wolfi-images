#!/usr/bin/env bash
# Sanity tests for the OpenJDK images (JRE default and JDK -dev variants).
# Usage: test.sh <image-ref> <tag>   (set CONTAINER_ENGINE=podman to run locally)
set -euo pipefail

IMAGE="${1:?usage: $0 <image-ref> <tag>}"
TAG="${2:?usage: $0 <image-ref> <tag>}"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

check_common

# Java 8 reports itself as 1.8.0_x
[ "$STREAM" = 8 ] && WANT='"1.8.0' || WANT="\"$STREAM"

echo "Checking Java version ($STREAM)..."
OUT="$(run -version 2>&1)"
[[ "$OUT" == *"version $WANT"* ]] || fail "unexpected version: $OUT"

echo "Checking the JVM starts as an arbitrary UID with the CA trust store..."
OUT="$(run_arbitrary -XshowSettings:properties -version 2>&1)"
[[ "$OUT" == *"java.home = /usr/lib/jvm/"* ]] || fail "unexpected java.home: $OUT"
image_files | grep -qE '^usr/lib/jvm/[^/]+/(jre/)?lib/security/cacerts$|^etc/ssl/certs/java/cacerts$' \
  || fail "no Java CA trust store"

cat > "$WORKDIR/Hello.java" <<'JAVA'
import java.security.KeyStore;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

public class Hello {
  public static void main(String[] args) throws Exception {
    TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
    tmf.init((KeyStore) null);
    X509TrustManager tm = (X509TrustManager) tmf.getTrustManagers()[0];
    System.out.println(tm.getAcceptedIssuers().length > 0 ? "ok" : "empty trust store");
  }
}
JAVA
chmod -R a+rX "$WORKDIR"

case "$VARIANT" in
  dev)
    echo "Checking javac as an arbitrary UID..."
    OUT="$("$ENGINE" run --rm --user "$ARBITRARY_USER" -v "$WORKDIR:/src:ro,z" --entrypoint /bin/sh "$IMAGE" -c \
      'javac -d /tmp/out /src/Hello.java && java -cp /tmp/out Hello')"
    [ "$OUT" = ok ] || fail "javac/java failed: $OUT"
    ;;
  "")
    ! succeeds /usr/lib/jvm/default-jvm/bin/javac -version || fail "JRE variant ships javac"
    ;;
esac

echo "All openjdk tests passed for $IMAGE ($TAG)."
