#!/usr/bin/env bash
set -euo pipefail
mode=${1:?case required}
case "$mode" in validation|failure|release|recovery) ;; *) exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$here/fixture/." "$work/"
mkdir -p "$work/packages" "$work/cache" report
dotnet=mcr.microsoft.com/dotnet/sdk@sha256:ddbaedfc8b774389d91a511af08b77296f2c7a8d15d86f6214d2a87166933625
node=docker.io/library/node@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee
run_image() {
    local image=$1
    shift
    docker pull "$image" >/dev/null
    docker run --rm --pull never --network none --cap-drop ALL --security-opt no-new-privileges \
      --user "$(id -u):$(id -g)" -e HOME=/work/cache -e DOTNET_CLI_HOME=/work/cache \
      -e DOTNET_CLI_TELEMETRY_OPTOUT=1 --mount "type=bind,src=$work,dst=/work" "$image" "$@"
}
case "$mode" in
    validation)
        run_image "$dotnet" sh -ec 'cd /work/dotnet; dotnet build -o /work/output; test "$(dotnet /work/output/PilotFixture.dll)" = fixture-ok'
        ;;
    failure)
        printf '%s\n' '#error SCALED_PILOT_INTENTIONAL_FAILURE' >> "$work/dotnet/Program.cs"
        set +e
        run_image "$dotnet" sh -ec 'cd /work/dotnet; dotnet build' > "$work/expected-failure.log" 2>&1
        result=$?
        set -e
        test "$result" -ne 0
        grep 'error CS1029:.*SCALED_PILOT_INTENTIONAL_FAILURE' "$work/expected-failure.log"
        ;;
    release|recovery)
        run_image "$dotnet" sh -ec 'cd /work/dotnet; dotnet pack --output /work/packages'
        run_image "$node" sh -ec 'cd /work/npm; test "$(node -p "require(\"./index.js\")()")" = 4; npm pack --pack-destination /work/packages'
        ;;
esac
python3 "$here/report.py" "$mode" "$work" report/result.json
test "$mode" != failure || exit 17
