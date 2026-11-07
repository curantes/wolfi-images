# Shared checks for every image. Source from tests/<name>/test.sh after
# setting IMAGE and TAG.
#
#   check_common   user 65532, no setuid/setgid files, and the variant
#                  contract: the base image has no shell and no apk, -dev
#                  has both

ENGINE="${CONTAINER_ENGINE:-docker}"
STREAM="${TAG%%-*}"
VARIANT="${TAG#"$STREAM"}"
VARIANT="${VARIANT#-}"
# OpenShift-style arbitrary UID with GID 0
ARBITRARY_USER="1000700000:0"

fail() { echo "FAIL: $*" >&2; exit 1; }
# Runs the image's entrypoint with the given arguments.
run() { "$ENGINE" run --rm "$IMAGE" "$@"; }
# Same, as an arbitrary non-root UID.
run_arbitrary() { "$ENGINE" run --rm --user "$ARBITRARY_USER" "$IMAGE" "$@"; }
succeeds() { "$ENGINE" run --rm --entrypoint "$1" "$IMAGE" "${@:2}" > /dev/null 2>&1; }

check_common() {
  echo "Checking user (65532)..."
  local user
  user="$("$ENGINE" inspect --format='{{.Config.User}}' "$IMAGE")"
  [ "$user" = "65532" ] || fail "User is '$user', expected 65532"

  echo "Checking for setuid/setgid files..."
  local cid special
  cid="$("$ENGINE" create "$IMAGE")"
  special="$("$ENGINE" export "$cid" | tar -tvf - | awk '$1 ~ /^-.*[sS]/ {print $NF}')"
  "$ENGINE" rm "$cid" > /dev/null
  [ -z "$special" ] || fail "setuid/setgid files: $special"

  echo "Checking variant contract ('${VARIANT:-default}')..."
  case "$VARIANT" in
    dev)
      succeeds /bin/sh -c true || fail "-dev must ship /bin/sh"
      succeeds /sbin/apk --version || fail "-dev must ship apk"
      ;;
    "")
      ! succeeds /bin/sh -c true || fail "default variant ships /bin/sh"
      ! succeeds /bin/busybox true || fail "default variant ships busybox"
      ! succeeds /sbin/apk --version || fail "default variant ships apk"
      ;;
    *) fail "unknown variant '$VARIANT'" ;;
  esac
}
