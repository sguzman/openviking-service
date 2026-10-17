#!/usr/bin/env bash
# Install packaged OpenViking and systemd user unit, never auto-start.
# Supports uv's default tool bin directory and custom UV_TOOL_BIN_DIR.
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || fail "Run as the desktop user, not root."
[ -n "$HOME" ] || fail "HOME not set."
for bin in uv systemctl install realpath mktemp; do
    command -v "$bin" >/dev/null || fail "Missing $bin. On EndeavourOS: yay -S --needed uv"
done

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(cat "$root/OPENVIKING_VERSION")"
[ -n "$version" ] || fail "OPENVIKING_VERSION is empty."
printf 'Installing OpenViking %s with Python 3.13 via uv...\n' "$version"
uv tool install --upgrade --python 3.13 "openviking==$version"

# Use uv's effective bin directory, not ~/.local/bin, for the upstream executable.
# UV_TOOL_BIN_DIR is allowed and may contain whitespace.
bin_dir="$(uv tool dir --bin)"
[ -n "$bin_dir" ] || fail "uv tool dir --bin returned an empty directory."
bin_dir="$(realpath -m -- "$bin_dir")"
server="$bin_dir/openviking-server"
[ -x "$server" ] || fail "Cannot execute $server; inspect: uv tool dir --bin"

mkdir -p "$HOME/.openviking" "$HOME/.config/systemd/user" "$HOME/.local/bin"
chmod 700 "$HOME/.openviking"

# The unit launches a stable user-local wrapper, which executes the exact
# uv-managed binary discovered during bootstrap.
launcher="$HOME/.local/bin/openviking-service-launcher"
temporary="$(mktemp "$HOME/.local/bin/.openviking-service-launcher.XXXXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
{
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'server=%q\n' "$server"
    cat <<'LAUNCHER'
if [ "$#" -gt 0 ]; then
    exec "$server" "$@"
fi
exec "$server" --config "$HOME/.openviking/ov.conf" --host 127.0.0.1 --port 1933
LAUNCHER
} > "$temporary"
chmod 700 "$temporary"

if [ -f "$launcher" ] && ! cmp -s "$launcher" "$temporary"; then
    backup="$launcher.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p -- "$launcher" "$backup"
    printf 'Preserved previous launcher: %s\n' "$backup"
fi
install -m 0700 "$temporary" "$launcher"

unit="$HOME/.config/systemd/user/openviking-service.service"
template="$root/systemd/openviking-service.service"
if [ -f "$unit" ] && ! cmp -s "$unit" "$template"; then
    backup="$unit.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p -- "$unit" "$backup"
    printf 'Preserved previous unit backup: %s\n' "$backup"
fi
install -m 0644 "$template" "$unit"
systemctl --user daemon-reload

printf 'Upstream server: %s\n' "$server"
printf 'Installed stable launcher: %s\n' "$launcher"
printf 'Installed user unit: %s\n' "$unit"
if [ -f "$HOME/.openviking/ov.conf" ]; then
    printf 'Existing OpenViking configuration preserved.\n'
else
    printf 'Provider/model configuration still needed.\n'
fi
printf 'NEXT: bash %s/scripts/activate.sh\n' "$root"
