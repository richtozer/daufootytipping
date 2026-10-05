#!/usr/bin/env bash
# Runs a command inside an OPERATING-SYSTEM boundary:
#   * no outbound network except loopback (127.0.0.0/8 / ::1) and unix sockets, for EVERY process the
#     command starts: Node, Bash, native executables, Dart, Java (the emulators);
#   * the usual credential stores are unreadable (Firebase CLI login, gcloud, ssh, aws, azure,
#     kube, docker, gh, netrc, the macOS keychain);
#   * an explicit minimal environment (env -i): no credential variables, no proxy settings, and an
#     EMPTY XDG_CONFIG_HOME so the Firebase CLI sees no stored login.
#
# Implemented with macOS `sandbox-exec`. If no boundary is available this FAILS CLOSED: it refuses to
# run rather than running unprotected. On Linux CI run the tests inside a container started with no
# network (`--network none`) and no credentials, then set OS_BOUNDARY=1 yourself; the canary tests in
# os_boundary.test.mjs verify the boundary is really there and fail if it is not.
#
# Usage: support/isolated.sh <command> [args...]
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: isolated.sh <command> [args...]" >&2
  exit 64
fi

if [ "$(uname -s)" != "Darwin" ] || [ ! -x /usr/bin/sandbox-exec ]; then
  echo "isolated.sh: no operating-system network boundary is available on this machine." >&2
  echo "Refusing to run unprotected. Run these tests inside a container with --network none and no" >&2
  echo "credentials mounted, and set OS_BOUNDARY=1 there (os_boundary.test.mjs will verify it)." >&2
  exit 78
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/isolated.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config"

home="${HOME:?HOME must be set (the Firebase emulator cache lives under it)}"

cat > "$work/profile.sb" <<PROFILE
(version 1)
(allow default)
(deny network*)
(allow network-outbound (remote ip "localhost:*"))
(allow network-outbound (remote unix-socket))
(allow network-bind (local ip "localhost:*"))
(allow network-inbound (local ip "localhost:*"))
(allow network* (local unix-socket))
(deny file-read* (subpath "$home/.config/configstore"))
(deny file-read* (subpath "$home/.config/gcloud"))
(deny file-read* (subpath "$home/.config/gh"))
(deny file-read* (subpath "$home/.ssh"))
(deny file-read* (subpath "$home/.aws"))
(deny file-read* (subpath "$home/.azure"))
(deny file-read* (subpath "$home/.kube"))
(deny file-read* (subpath "$home/.docker"))
(deny file-read* (literal "$home/.netrc"))
(deny file-read* (subpath "$home/Library/Keychains"))
PROFILE

# Pass through only what the tools need to run; nothing that carries a credential or a proxy.
# (No `exec`: the EXIT trap must run to remove the temporary profile.)
/usr/bin/sandbox-exec -f "$work/profile.sb" \
  /usr/bin/env -i \
    HOME="$home" \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$work/config" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LANG=C \
    LC_ALL=C \
    OS_BOUNDARY=1 \
    "$@"
