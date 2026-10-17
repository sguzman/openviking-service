#!/usr/bin/env bash
# Configure models interactively once, validate, then enable/start the service.
set -euo pipefail
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || fail "Run as your desktop user."
server="$HOME/.local/bin/openviking-service-launcher"
config="$HOME/.openviking/ov.conf"
unit="$HOME/.config/systemd/user/openviking-service.service"
[ -x "$server" ] || fail "First run scripts/bootstrap.sh."
[ -f "$unit" ] || fail "Missing user unit. First run scripts/bootstrap.sh."
command -v curl >/dev/null || fail "curl is needed for readiness checks."
mkdir -p "$HOME/.openviking"
chmod 700 "$HOME/.openviking"

if [ ! -f "$config" ]; then
    # Do not enter the known-broken upstream pip installation branch.
    # Bootstrap provisions local CPU embedding into uv's isolated tool env.
    command -v uv >/dev/null || fail "uv missing; install uv and rerun bootstrap."
    tool_python="$(uv tool dir)/openviking/bin/python"
    if [ ! -x "$tool_python" ] || ! "$tool_python" -c 'from llama_cpp import Llama' >/dev/null 2>&1; then
        fail "Local CPU embedding dependency missing. Run bash scripts/bootstrap.sh once before using the wizard."
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        fail "Provider/model setup needs an interactive terminal. Run bash scripts/activate.sh directly in a terminal (not a background job)."
    fi
    printf 'Select your real embedding + VLM providers/models in upstream setup.\n'
    printf 'Keep API keys in your local configuration, never in Git or chat.\n'
    ( cd "$HOME/.openviking" && "$server" init )
fi
[ -f "$config" ] || fail "Wizard did not create ~/.openviking/ov.conf."
chmod 600 "$config"
printf 'Validating upstream config and model access ...\n'
doctor_log="$(mktemp)"
trap 'rm -f -- "$doctor_log"' EXIT
if ( cd "$HOME/.openviking" && "$server" doctor ) 2>&1 | tee "$doctor_log"; then
    :
else
    # Upstream doctor 0.5.0 fails for a deliberately skipped VLM, despite the
    # official wizard offering embedding-only mode. Permit *only* this exact
    # diagnostic failure; never ignore broken embedding or storage checks.
    failures="$(grep -Ec ':[[:space:]]+FAIL([[:space:]]|$)' "$doctor_log" || true)"
    if [ "$failures" -eq 1 ] &&
       grep -Eq '^[[:space:]]*VLM:[[:space:]]+FAIL[[:space:]]+No VLM provider configured' "$doctor_log" &&
       grep -Fq '1 check(s) failed.' "$doctor_log"; then
        printf 'Embedding-only configuration accepted: VLM-dependent features remain unavailable.\n'
    else
        fail "OpenViking doctor failed. Resolve all diagnostics except an intentionally absent VLM."
    fi
fi

printf 'Enabling and restarting openviking-service.service ...\n'
systemctl --user enable openviking-service.service
systemctl --user restart openviking-service.service

for i in $(seq 1 15); do
    if systemctl --user is-active --quiet openviking-service.service && curl --fail --silent --output /dev/null --max-time 2 http://127.0.0.1:1933/ready; then
        printf '\nREADY: http://127.0.0.1:1933/mcp\n'
        printf 'Studio: http://127.0.0.1:1933/studio\n'
        exit 0
    fi
    sleep 2
done
printf 'Service did not become ready. Recent journal entries:\n' >&2
journalctl --user -u openviking-service.service -n 35 --no-pager >&2 || true
fail "Readiness failed; fix provider and service configuration."
