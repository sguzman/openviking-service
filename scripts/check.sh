#!/usr/bin/env bash
# Read-only service diagnostics. Does not read or modify stored memories.
set -euo pipefail
printf '%s\n' 'systemd:'
systemctl --user --no-pager --full status openviking-service.service || true
printf '\nLiveness (/health):\n'
curl --fail --show-error --silent --max-time 5 http://127.0.0.1:1933/health
printf '\nReadiness (/ready):\n'
curl --fail --show-error --silent --max-time 5 http://127.0.0.1:1933/ready
printf '\nMCP: http://127.0.0.1:1933/mcp (verify tools/list with an MCP client)\n'
