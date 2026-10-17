#!/usr/bin/env bash
# Isolated tests: embedding-only doctor may omit VLM, but all other failures must block startup.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export TEST_SYSTEMCTL_LOG="$tmp/systemctl.log"
export TEST_DOCTOR_FILE="$tmp/doctor-output"
mkdir -p "$HOME/.openviking" "$HOME/.local/bin" "$HOME/.config/systemd/user" "$tmp/bin"
printf '%s\n' '{"embedding":{"dense":{"provider":"local"}}}' > "$HOME/.openviking/ov.conf"
: > "$HOME/.config/systemd/user/openviking-service.service"
cat > "$HOME/.local/bin/openviking-service-launcher" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "doctor" ]; then
    cat "$TEST_DOCTOR_FILE"
    if grep -q "FAIL" "$TEST_DOCTOR_FILE"; then exit 1; fi
    exit 0
fi
exit 9
LAUNCHER
cat > "$tmp/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
exit 0
SYSTEMCTL
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
exit 0
CURL
chmod +x "$HOME/.local/bin/openviking-service-launcher" "$tmp/bin/systemctl" "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

cat > "$TEST_DOCTOR_FILE" <<'DOCTOR'
OpenViking Doctor
  Config: PASS config
  Python: PASS 3.13
  Native Engine: PASS loaded
  AGFS: PASS loaded
  Authentication: PASS development
  Embedding: PASS local
  VLM: FAIL No VLM provider configured
  Ollama: PASS unused
  VikingBot: WARN not configured
  Disk: PASS enough
  1 check(s) failed. See above for fix suggestions.
DOCTOR
bash "$root/scripts/activate.sh" > "$tmp/positive-output" 2>&1
grep -Fq 'Embedding-only configuration accepted' "$tmp/positive-output"
grep -Fq 'READY: http://127.0.0.1:1933/mcp' "$tmp/positive-output"
grep -Fq -- '--user restart openviking-service.service' "$TEST_SYSTEMCTL_LOG"
printf '%s\n' 'PASS: intentionally absent VLM allows embedding-only startup'

: > "$TEST_SYSTEMCTL_LOG"
sed -i 's/Embedding: PASS local/Embedding: FAIL local embedding broken/;s/1 check(s) failed/2 check(s) failed/' "$TEST_DOCTOR_FILE"
if bash "$root/scripts/activate.sh" > "$tmp/negative-output" 2>&1; then
    echo "FAIL: broken embedding was incorrectly allowed" >&2
    exit 1
fi
if grep -Fq -- '--user restart openviking-service.service' "$TEST_SYSTEMCTL_LOG"; then
    echo "FAIL: service was restarted after an unexpected diagnostic failure" >&2
    exit 1
fi
printf '%s\n' 'PASS: additional doctor failures block activation'
