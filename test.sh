test "$(id -u)" -ne 0
test ! -S /var/run/docker.sock
test -z "${BUILDKITE_AGENT_ACCESS_TOKEN:-}"
test -z "${SSH_AUTH_SOCK:-}"
test ! -e /src/.git
test -r /src/README.md
printf "%s\\n" "public fixture passed"
