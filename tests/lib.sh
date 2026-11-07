# Shared checks for every image. Source from tests/<name>/test.sh after
# setting IMAGE and TAG.
#
#   check_common   user 65532, no setuid/setgid files, and the variant
#                  contract: -dev has a shell and apk, every other variant
#                  has neither (ALLOW_SHELL=1 allows a shell)

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
  cid="$("$ENGINE" create --entrypoint /nonexistent "$IMAGE")"
  special="$("$ENGINE" export "$cid" | tar -tvf - | awk '$1 ~ /^-.*[sS]/ {print $NF}')"
  "$ENGINE" rm "$cid" > /dev/null
  [ -z "$special" ] || fail "setuid/setgid files: $special"

  echo "Checking variant contract ('${VARIANT:-default}')..."
  case "$VARIANT" in
    dev)
      succeeds /bin/sh -c true || fail "-dev must ship /bin/sh"
      succeeds /sbin/apk --version || fail "-dev must ship apk"
      ;;
    *)
      # Every other variant (default, fpm, ...) is distroless. An image that
      # must ship a shell sets ALLOW_SHELL=1 and tests it explicitly.
      if [ "${ALLOW_SHELL:-0}" != 1 ]; then
        ! succeeds /bin/sh -c true || fail "variant '${VARIANT:-default}' ships /bin/sh"
        ! succeeds /bin/busybox true || fail "variant '${VARIANT:-default}' ships busybox"
      fi
      ! succeeds /sbin/apk --version || fail "variant '${VARIANT:-default}' ships apk"
      ;;
  esac
}

# image_files: list every path in the image (no leading slash), for checks on
# images without a shell.
image_files() {
  local cid
  cid="$("$ENGINE" create --entrypoint /nonexistent "$IMAGE")"
  "$ENGINE" export "$cid" | tar -tf - | sed 's|^\./||'
  "$ENGINE" rm "$cid" > /dev/null
}

# image_file PATH: print one file from the image.
image_file() {
  local cid
  cid="$("$ENGINE" create --entrypoint /nonexistent "$IMAGE")"
  "$ENGINE" cp "$cid:$1" - | tar -xOf -
  "$ENGINE" rm "$cid" > /dev/null
}
