#!/usr/bin/env bash
# Install packaged OpenViking and the systemd user unit, never auto-start.
set -euo pipefail
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || fail "Run as the desktop user, not root."
[ -n "$HOME" ] || fail "HOME not set."
for bin in uv systemctl install; do
    command -v "$bin" >/dev/null || fail "Missing $bin. On EndeavourOS: yay -S --needed uv"
done
[ -z "$(printenv UV_TOOL_BIN_DIR || true)" ] || fail "Custom UV_TOOL_BIN_DIR requires editing the unit's executable path."
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(cat "$root/OPENVIKING_VERSION")"
[ -n "$version" ] || fail "OPENVIKING_VERSION is empty."
printf 'Installing OpenViking %s with Python 3.13 via uv...\n' "$version"
uv tool install --python 3.13 "openviking==$version"
[ -x "$HOME/.local/bin/openviking-server" ] || fail "Expected ~/.local/bin/openviking-server; inspect uv tool dir --bin."

mkdir -p "$HOME/.openviking" "$HOME/.config/systemd/user"
chmod 700 "$HOME/.openviking"
unit="$HOME/.config/systemd/user/openviking-service.service"
template="$root/systemd/openviking-service.service"
if [ -f "$unit" ] && ! cmp -s "$unit" "$template"; then
    backup="$unit.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p -- "$unit" "$backup"
    printf 'Preserved previous unit backup: %s\n' "$backup"
fi
install -m 0644 "$template" "$unit"
systemctl --user daemon-reload
printf 'Installed user unit: %s\n' "$unit"
if [ -f "$HOME/.openviking/ov.conf" ]; then
    printf 'Existing OpenViking config preserved (not rewritten).\n'
else
    printf 'Provider/model configuration still needed.\n'
fi
printf 'NEXT: bash %s/scripts/activate.sh\n' "$root"
