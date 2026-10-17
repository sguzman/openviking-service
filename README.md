# OpenViking Service

A small, **standalone deployment repository** for one central, locally hosted [OpenViking](https://github.com/volcengine/OpenViking) context database. The upstream OpenViking package is installed externally; this repository does **not** fork its implementation and does **not** integrate any app or agent.

**Scope:** native Streamable HTTP MCP endpoint, persistent local storage, user-level systemd lifecycle, and diagnostics. **Out of scope:** Chatarium, Codex, client configuration, memory namespace policy, shared-memory permissions, automatic capture, and agent instructions.

## Runtime

- OS: EndeavourOS / Arch Linux (systemd user manager)
- Upstream package: [OpenViking](https://pypi.org/project/openviking/), pinned to the release in [OPENVIKING_VERSION](OPENVIKING_VERSION)
- Python: 3.13, managed by uv
- Server/REST API: http://127.0.0.1:1933
- MCP (Streamable HTTP): **http://127.0.0.1:1933/mcp**
- Health: http://127.0.0.1:1933/health
- Readiness: http://127.0.0.1:1933/ready
- Studio: http://127.0.0.1:1933/studio

The MCP endpoint is part of the official server, **not** a separate MCP process. This repository deliberately does not install VikingBot or the OpenViking Gateway.

## First-time setup

Prerequisite: uv installed and a working user-level systemd manager. Install uv with your normal package manager if missing, e.g. on EndeavourOS:

~~~sh
yay -S --needed uv
~~~

From an existing checkout, install the packaged runtime and systemd user unit:

~~~sh
git pull --ff-only
bash scripts/bootstrap.sh
~~~

If you haven't cloned yet, clone this repository to your preferred projects directory first. For the primary developer's workstation the checkout is `~/Code/Service/openviking-service`; do **not** create a duplicate clone in `~/openviking-service`.

The installer resolves `uv tool dir --bin` after package installation. It **supports custom `UV_TOOL_BIN_DIR`**, including paths containing spaces. It installs a stable launcher at `~/.local/bin/openviking-service-launcher`; systemd calls that launcher, which executes the actual uv-managed OpenViking binary. This does **not** overwrite or relocate uv's executable.

Bootstrap installs the pinned upstream package **with its local CPU embedding extra** and uses the upstream llama-cpp-python prebuilt Linux CPU wheel index. It verifies `from llama_cpp import Llama` inside the isolated uv tool environment *before* installing the unit. This bypasses an upstream interactive setup issue: its `pip install "openviking[local-embed]"` branch cannot run because normal uv tool environments do not include pip. The bootstrap deliberately disallows a source build for `llama-cpp-python`, so missing wheels fail explicitly instead of spending an unpredictable amount of time compiling.

Run bootstrap in a normal terminal: large package downloads may take much longer than a Jobflick job timeout. The operation is repeatable, preserves the existing `~/.openviking/ov.conf`, and does **not** start a server until the model configuration is valid. Changed preexisting unit files are backed up before replacement.

**One-time model setup is interactive.** Run the next command in a normal terminal with standard input/output (not Jobflick's non-interactive background command runner):

~~~sh
bash scripts/activate.sh
~~~

If ~/.openviking/ov.conf does not exist, this verifies the local CPU embedding dependency is installed, then invokes upstream's official setup wizard. It configures your choice of **both an embedding model and a VLM**, runs `openviking-server doctor`, and only enables/starts the service after validation. If the configuration already exists, the wizard is skipped and your provider choices are preserved.

Do not guess provider/model names or put credentials in this repository. The upstream wizard supports cloud providers, Codex authentication for the VLM, and Ollama; using Codex for VLM does **not** automatically supply embeddings. Remote providers can have separate costs/quotas, and ChatGPT plan usage is not automatically shared with OpenViking. If you already have an OpenViking configuration, check the resolved storage workspace before starting this systemd unit, especially when it uses a relative path.

The wizard and systemd unit both run with ~/.openviking as the working directory. Thus upstream's default `storage.workspace="./data"` resolves to **~/.openviking/data** consistently across restarts. An explicit absolute storage.workspace in your existing configuration is honored.

### Check status

~~~sh
bash scripts/check.sh
systemctl --user status openviking-service.service
journalctl --user -u openviking-service.service -n 100 --no-pager
~~~

The diagnostic script checks HTTP /health and /ready. A successful /health alone does **not** prove that indexing or model dependencies work; readiness and actual MCP tool discovery are stronger checks. This repo deliberately does not write test memories into your database. Once a client is integrated, separately verify MCP tools/list and a permitted read.

### Control lifecycle

~~~sh
systemctl --user stop openviking-service.service
systemctl --user start openviking-service.service
systemctl --user restart openviking-service.service
systemctl --user disable --now openviking-service.service
~~~

Enabled user services launch when the user systemd manager starts (normally at desktop login). **No lingering** or system-wide root daemon is configured; running before login requires a separate, explicit decision.

## Persistence and secrets

| Path | Purpose |
| --- | --- |
| ~/.openviking/ov.conf | Server configuration and private provider credentials |
| ~/.openviking/data | Default durable index/resources/memories if storage.workspace is relative |
| ~/.config/systemd/user/openviking-service.service | Installed user unit |
| `$(uv tool dir --bin)/openviking-server` | Upstream uv-managed executable (path can be customized) |
| ~/.local/bin/openviking-service-launcher | Stable locally generated wrapper used by systemd and setup |
| This Git repository | Only operations scripts, documentation and version pin |

Do not commit the configuration, memory data, backups, or secrets. Back up the **configured storage.workspace** and your private config separately; Git does not back up live memories.

**Default binding is localhost only.** Without a root key OpenViking can run in local development mode without authentication. That is suitable only when you trust local processes on the machine. It is **not** a multi-tenant isolation or authentication boundary. The server must not be opened on the LAN/internet by changing the host to 0.0.0.0 without first configuring proper API-key/OAuth access and understanding client credentials. A server shared by several future apps does not automatically create isolated per-chat memory banks; that is a later client/identity-policy decision.

## Maintenance and updates

The OpenViking version is intentionally pinned instead of implicitly tracking new upstream releases. To upgrade later, review upstream changes, update OPENVIKING_VERSION, and run:

~~~sh
bash scripts/bootstrap.sh
bash scripts/activate.sh
~~~

Activation re-runs `doctor` and restarts the service. Always back up the data/config before upgrading the version. To review current diagnostics without changing state, use `bash scripts/check.sh`.

### Troubleshooting

- **Package cannot install:** ensure uv is available and can download a Python 3.13 interpreter/prebuilt OpenViking wheel. Do not install a source toolchain as the first response.
- **Custom `UV_TOOL_BIN_DIR`:** supported by design. Re-run `bash scripts/bootstrap.sh` to regenerate the stable launcher after changing uv's tool bin directory. Verify the upstream executable with `uv tool dir --bin`.
- **Wizard/model setup fails:** choose the actual supported embedding/VLM providers, confirm credentials privately, and rerun `bash scripts/activate.sh`. Existing ov.conf is preserved. If you saw `No module named pip` at the lightweight CPU embedding step, exit the wizard, pull the updated repository and rerun bootstrap; the installer provisions the CPU wheel beforehand.
- **Port 1933 busy:** stop the other service occupying that port; do not start two writers on the same embedded workspace.
- **Service runs but /ready fails:** run `openviking-server doctor` (from ~/.openviking), then inspect the user journal.
- **No server until login:** this is a systemd user service, not a system service.
- **Other computers cannot connect:** intentional. The service listens on 127.0.0.1; secure remote access is a later deployment phase.

## Upstream references

- [Server setup](https://docs.openviking.ai/en/getting-started/04-setup-for-agent)
- [Systemd and deployment](https://docs.openviking.ai/en/guides/03-deployment)
- [Configuration](https://docs.openviking.ai/en/guides/01-configuration)
- [MCP tools and protocol](https://docs.openviking.ai/en/guides/06-mcp-integration)
- [Authentication](https://docs.openviking.ai/en/guides/02-authentication)

Upstream code is AGPL-3.0; this repository contains independent deployment files under its own LICENSE. Review upstream obligations if distributing a modified upstream service.
