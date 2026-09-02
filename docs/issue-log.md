# Hermes WebUI setup issue log

This document captures the issues discovered during the Hermes WebUI deployment process, the root cause, the approach used to solve them, and the final fixes we should reuse to avoid repeated mistakes.

## 1. Localhost binding in a headless Codespace

### Issue
The app was not reachable from the forwarded port because the server was launched on `localhost` instead of `0.0.0.0`.

### Root cause
GitHub Codespaces exposes services via a forwarded port, but a process bound only to local loopback is not reachable from the public port mapping.

### Solution
Use the host binding `0.0.0.0` and expose port `8787` in the Codespace Ports tab.

### Final pattern
```bash
nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
```

---

## 2. Missing PATH exports after CLI install

### Issue
The Hermes CLI was installed successfully, but the shell could not find `hermes` immediately after installation.

### Root cause
The installation script placed binaries under `$HOME/.local/bin` or `$HOME/.hermes/bin`, but the shell environment had been polluted by a literal `$PATH` entry in the exported PATH, which broke command resolution for standard tools such as `mkdir`.

### Solution
Use a clean, explicit PATH value that preserves the system bin directories before app-specific bins, avoid escaping `$PATH` incorrectly inside the exported assignment, and source shell profiles only in interactive sessions.

### Final pattern
```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"
[ -f "$HOME/.bashrc" ] && [[ $- == *i* ]] && . "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && [[ $- == *i* ]] && . "$HOME/.profile"
```

---

## 3. Port conflicts on 8787 / 1111 / 8080

### Issue
A stale process from a previous run or another service was holding the required port and prevented a clean restart.

### Root cause
Port reuse without checking for orphaned processes caused startup errors and failed health probes.

### Solution
Check for active listeners before launching the app and kill stale processes when needed.

### Final pattern
```bash
lsof -ti:8787,1111,8080 | xargs -r kill -9 || true
```

---

## 4. Missing API credentials for LLM access

### Issue
The app started, but it did not have a functioning LLM backend connection.

### Root cause
No valid API key was configured in the environment or `.env` file, so the app could not access the model provider.

### Solution
Create `.env` values for the required keys and ensure Gemini-compatible variables are present.

### Final pattern
```bash
GEMINI_API_KEY=${GEMINI_API_KEY:-}
GOOGLE_API_KEY=${GEMINI_API_KEY:-}
GATEWAY_TOKEN=${GATEWAY_TOKEN:-hermes-codespace-pass}
HOST=0.0.0.0
PORT=8787
```

---

## 5. Incorrect authentication configuration for WebUI

### Issue
The app was running but the user did not know the required login token.

### Root cause
The gateway token was either missing or not surfaced to the user after deployment.

### Solution
Create a stable token in `.env` and print it clearly in the startup output.

### Final pattern
```bash
GATEWAY_TOKEN=${GATEWAY_TOKEN:-hermes-codespace-pass}
```

---

## 6. Using the app without a GUI browser in a headless environment

### Issue
Attempts to open a browser window in the container are invalid in Codespaces and may fail or hang.

### Root cause
The environment is headless and only exposes port forwarding.

### Solution
Start the app in daemon mode and rely on the forwarded port URL instead of a local browser launch.

### Final pattern
```bash
nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
```

---

## 7. Missing Python venv support in Ubuntu Codespaces images

### Issue
The Hermes WebUI virtual environment could not be created because the system was missing the `python3-venv` package.

### Root cause
The container had `python3` installed, but not the `venv` module required for `python3 -m venv`.

### Solution
Install `python3-venv` explicitly before creating the app environment, and keep this validation in the deployment script so the same failure does not recur.

### Final pattern
```bash
if ! python3 -m venv --help >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y python3-venv
fi
```

---

## 8. Hermes defaulted to OpenRouter instead of Gemini

### Issue
The app was using `provider: auto` with the default OpenRouter URL and the model selector defaulted to `claude-opus-4.6`, causing a `HTTP 401: Missing Authentication header` error.

### Root cause
The Hermes config file still pointed to `https://openrouter.ai/api/v1`, and there was no explicit Gemini override in the active config. Since the OpenRouter key was absent, the model request failed before any Gemini call was made.

### Solution
Force Hermes to use the Gemini provider directly and set the base URL to the Google AI Studio endpoint. Keep the key in both `GEMINI_API_KEY` and `GOOGLE_API_KEY` so runtime detection succeeds.

### Final pattern
```bash
export GEMINI_API_KEY="..."
export GOOGLE_API_KEY="$GEMINI_API_KEY"
hermes config set model.provider gemini
hermes config set model.default gemini-2.5-flash
hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta
```

---

## 9. Missing health-check validation after launch

### Issue
The app was started in the background, but there was no proof that it was live and ready to serve requests.

### Root cause
A background process can exist while the app is still booting or failing silently.

### Solution
Poll the health endpoint and fail loudly if the app does not respond.

### Final pattern
```bash
curl -s -f http://127.0.0.1:8787/health || curl -s -f http://127.0.0.1:8787/
```

---

## 9. No reusable automation for the deployment process

### Issue
Every deployment required manually redoing the same installation and configuration steps.

### Root cause
There was no repeatable script to standardize environment setup and startup.

### Solution
Use a single setup script that installs dependencies, creates `.env`, configures paths, and starts the service.

### Reusable approach
Store automation in the repository under `scripts/` and include a documented prompt in `docs/`.

---

## 10. Steel cloud browser integration

### Requirement
Hermes WebUI needs cloud browser automation through Steel while retaining Gemini, existing configuration, and conversation state.

### Checks performed before implementation
- Confirmed the Hermes CLI supports Git-based plugin installation.
- Confirmed `https://github.com/steel-dev/hermes-steel.git` exists.
- Confirmed `steel-sdk` and `playwright` are available from the Python package index.
- Confirmed the installed plugin key is `browser-steel`, not `steel`.

### Implementation
The setup script now:
- installs and enables `steel-dev/hermes-steel` only when `browser-steel` is not already installed
- sets `browser.cloud_provider=steel`
- installs `steel-sdk` and `playwright` in `~/hermes-webui/.venv`
- installs the Playwright Chromium runtime
- appends `STEEL_API_KEY`, `BROWSER_PROVIDER=steel`, and `BROWSER_HEADLESS=true` only when absent
- never overwrites Gemini keys, the gateway token, or session data

### Important authentication boundary
The plugin can be installed and validated without printing or committing a secret, but live Steel cloud browsing requires a real `STEEL_API_KEY` in `~/.hermes/.env`. An empty or placeholder key must not be reported as working browser automation.

If the Steel session API returns HTTP 403, treat that as an invalid, revoked, or unauthorized Steel key/account. Do not change Gemini configuration to address it; replace the Steel key from the Steel dashboard and retry the session test.

### Verification
The following checks passed after installation:
```bash
hermes plugins show browser-steel
hermes plugins doctor browser-steel
hermes config get browser.cloud_provider
curl -fsS http://127.0.0.1:8787/health
```

The plugin doctor reported successful runtime discovery, manifest parsing, import, and registration of its tools. It also reported manifest metadata warnings for declared hooks/tools; these are non-fatal because runtime registration passed.

---

## Lessons learned
- Always bind the server to `0.0.0.0` in Codespaces.
- Hermes WebUI `ctl.sh` reads `HERMES_WEBUI_HOST` and `HERMES_WEBUI_PORT`; generic `HOST` and `PORT` alone do not change its binding.
- Codespaces public visibility can reset or leave an old browser URL stale; reapply `gh codespace ports visibility 8787:public` during startup and verify the current `browseUrl`.
- A multi-step Hermes/Gemini browser prompt can be blocked before tool execution by Gemini free-tier `429` quota; test Steel’s browser path independently before changing browser code.
- Always reload PATH after package installs.
- Always check port occupancy before starting services.
- Always create `.env` values with secure defaults.
- Always validate with an HTTP health check.
- Always keep a Gemini-compatible API key in the runtime environment.
- Use the actual Steel plugin key `browser-steel` when checking installation state.
- Require a real `STEEL_API_KEY` before claiming cloud browser automation is live.
- Always document fixes as they are discovered so that the same mistakes are not repeated.
