#!/usr/bin/env bash
# Isolated, dependency-free smoke test for installer behavior.
# Mocks uv and systemctl; never touches the developer's actual HOME.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/fake-bin"
cat > "$tmp/fake-bin/uv" <<'UV'
#!/usr/bin/env bash
set -euo pipefail
case "$1/$2" in
    tool/install)
        mkdir -p "$MOCK_UV_BIN" "$MOCK_UV_TOOL_DIR/openviking/bin"
        cat > "$MOCK_UV_TOOL_DIR/openviking/bin/python" <<'PYTHON'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "-c" ] && [ "$2" = "from llama_cpp import Llama" ] || exit 12
PYTHON
        chmod +x "$MOCK_UV_TOOL_DIR/openviking/bin/python"
        cat > "$MOCK_UV_BIN/openviking-server" <<'SERVER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$TEST_SERVER_ARGS"
SERVER
        chmod +x "$MOCK_UV_BIN/openviking-server"
        ;;
    tool/dir)
        if [ "${3:-}" = "--bin" ]; then
            printf '%s\n' "$MOCK_UV_BIN"
        elif [ "$#" -eq 2 ]; then
            printf '%s\n' "$MOCK_UV_TOOL_DIR"
        else
            exit 4
        fi
        ;;
    *) echo "Unexpected uv invocation: $*" >&2; exit 5 ;;
esac
UV
cat > "$tmp/fake-bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
SYSTEMCTL
chmod +x "$tmp/fake-bin/uv" "$tmp/fake-bin/systemctl"
export PATH="$tmp/fake-bin:$PATH"

run_case() {
    local name="$1"
    local bin="$2"
    export HOME="$tmp/$name/home"
    export TEST_SYSTEMCTL_LOG="$tmp/$name/systemctl.log"
    export TEST_SERVER_ARGS="$tmp/$name/server-args"
    export MOCK_UV_BIN="$bin"
    export MOCK_UV_TOOL_DIR="$tmp/$name/uv tools"
    mkdir -p "$HOME"
    bash "$root/scripts/bootstrap.sh" > "$tmp/$name-bootstrap.log"
    launcher="$HOME/.local/bin/openviking-service-launcher"
    unit="$HOME/.config/systemd/user/openviking-service.service"
    [ -x "$launcher" ] && [ -f "$unit" ]
    [ -x "$MOCK_UV_BIN/openviking-server" ]
    grep -Fq 'ExecStart=%h/.local/bin/openviking-service-launcher' "$unit"
    grep -Fxq -- '--user daemon-reload' "$TEST_SYSTEMCTL_LOG"
    [ "$(wc -l < "$TEST_SYSTEMCTL_LOG")" -eq 1 ]
    [ ! -f "$HOME/.openviking/ov.conf" ]
    "$launcher" --help
    grep -Fxq -- '--help' "$TEST_SERVER_ARGS"
    "$launcher"
    printf '%s\n' --config "$HOME/.openviking/ov.conf" --host 127.0.0.1 --port 1933 > "$tmp/expected-args"
    cmp -s "$tmp/expected-args" "$TEST_SERVER_ARGS"
    # A second bootstrap must keep existing provider config and avoid starting.
    printf '%s\n' '{"already":"configured"}' > "$HOME/.openviking/ov.conf"
    bash "$root/scripts/bootstrap.sh" > "$tmp/$name-bootstrap-again.log"
    grep -Fq '"configured"' "$HOME/.openviking/ov.conf"
    [ "$(wc -l < "$TEST_SYSTEMCTL_LOG")" -eq 2 ]
    printf 'PASS: %s\n' "$name"
}

# Customized uv path with whitespace.
run_case custom "$tmp/custom bins/openviking"
# Default uv tool bin path.
run_case default "$tmp/default/home/.local/bin"
