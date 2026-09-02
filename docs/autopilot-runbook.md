# Hermes WebUI + Gemini startup runbook for future autopilot launches

This document is the canonical handoff for the Hermes WebUI setup in this Codespace. It records the real failures we hit, the exact causes, the verified fixes, and the commands that must be used on the next launch so that future automation does not repeat the same mistakes.

## 1. Summary of the actual problem

The app was successfully installed, but it did not work correctly until we explicitly forced Gemini configuration. The real issue was not the Gemini API key itself; the root cause was that Hermes kept defaulting to a non-Gemini provider and base URL. In practice, the app tried OpenRouter defaults and then failed with a missing-authentication error.

The final working configuration is:

- provider: gemini
- model: gemini-2.5-flash
- base_url: https://generativelanguage.googleapis.com/v1beta
- key env: GEMINI_API_KEY and GOOGLE_API_KEY must both be present
- bind host: 0.0.0.0
- port: 8787

The WebUI controller specifically reads `HERMES_WEBUI_HOST` and `HERMES_WEBUI_PORT`. The setup script sets those values and also passes `--host 0.0.0.0 8787` to `ctl.sh`; setting only generic `HOST` and `PORT` is insufficient.
The post-start hook also reapplies public visibility with GitHub CLI when running inside Codespaces. Always use the current `browseUrl` from `gh codespace ports`, because an old forwarded URL may show 404 even while the service is healthy.

When Gemini quota is exhausted, a Hermes chat may fail before selecting any browser tool. This is a Gemini provider limit, not evidence that Steel is broken. Validate Steel independently with a short create-session, navigate, inspect, extract, and release check, then retry the full Hermes workflow after Gemini quota is available.

This is the configuration the app must keep on every fresh Codespace startup.

Steel cloud browser automation is also enabled through the official `browser-steel` Hermes plugin. It is installed by the project setup script and selected with `browser.cloud_provider=steel`. A real Steel API key is required for live cloud sessions.

The agent also uses a persistent incremental-task policy. Multi-action requests must be split into small ordered tasks, verified one task at a time, and resumed from the first incomplete task after interruption. Browser requests must separately verify navigation, page inspection, extraction, and final links while preserving the Steel session.

## 2. Issues we encountered and how we fixed them

### Issue A: Hermes defaulted to OpenRouter instead of Gemini

Symptoms:
- WebUI loads but chat requests fail
- Error message mentions `claude-opus-4.6` or OpenRouter defaults
- Hermes returns an authentication error

Root cause:
- Hermes config retained a default provider/base URL that was not Gemini-related
- The app was never explicitly told to use Gemini
- `GEMINI_API_KEY` was valid, but the runtime still used the wrong provider and web endpoint

Fix:
```bash
export GEMINI_API_KEY="..."
export GOOGLE_API_KEY="$GEMINI_API_KEY"
hermes config set model.provider gemini
hermes config set model.default gemini-2.5-flash
hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta
```

Important rule:
- Never trust the default provider selection
- Always set Gemini explicitly before launching the WebUI or sending a chat request

### Issue B: PATH broke after installation

Symptoms:
- `hermes` command is not found
- system commands such as `mkdir` or `ls` fail in the shell after updating PATH
- shell started with a malformed export line

Root cause:
- PATH was overwritten incorrectly and lost essential system directories
- there was an invalid variable expansion pattern in the shell configuration

Fix:
```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"
[ -f "$HOME/.bashrc" ] && [[ $- == *i* ]] && . "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && [[ $- == *i* ]] && . "$HOME/.profile"
```

Important rule:
- Preserve `/usr/local/bin`, `/usr/bin`, `/bin`, and the rest of the OS path before app-specific directories

### Issue C: Python venv support missing on Ubuntu Codespace image

Symptoms:
- `python3 -m venv` fails
- app cannot create virtual environment
- dependencies cannot install

Root cause:
- Ubuntu image had Python but not the `venv` module installed

Fix:
```bash
if ! python3 -m venv --help >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y python3-venv
fi
```

### Issue D: Orphaned port listeners blocking startup

Symptoms:
- app fails to bind to 8787
- startup reports port conflict
- health probe never becomes ready

Root cause:
- another stale process was still bound to the required port

Fix:
```bash
lsof -ti:8787,1111,8080 | xargs -r kill -9 || true
```

### Issue E: server bound to localhost instead of 0.0.0.0

Symptoms:
- app runs locally but is not reachable from forwarded Codespace port

Root cause:
- service was bound to localhost only, which works on the local machine but not through Codespace port forwarding

Fix:
```bash
nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
```

Important rule:
- In Codespaces, always bind to `0.0.0.0`, never `localhost`

### Issue F: missing or incomplete .env config

Symptoms:
- app launches without credentials
- WebUI starts but backend requests fail
- gateway token is missing or not recognized

Root cause:
- required environment variables were absent or inconsistent between Hermes home and WebUI repo

Fix:
```bash
mkdir -p "$HOME/.hermes"
cat >> "$HOME/.hermes/.env" <<'EOF'
GEMINI_API_KEY=...
GOOGLE_API_KEY=...
GATEWAY_TOKEN=hermes-codespace-pass
HOST=0.0.0.0
PORT=8787
EOF

cat >> "$HOME/hermes-webui/.env" <<'EOF'
GEMINI_API_KEY=...
GOOGLE_API_KEY=...
GATEWAY_TOKEN=hermes-codespace-pass
HOST=0.0.0.0
PORT=8787
EOF
chmod 600 "$HOME/.hermes/.env" "$HOME/hermes-webui/.env"
```

### Issue G: no health verification after launch

Symptoms:
- app appears to be running, but there is no proof it is ready

Root cause:
- the service started in background mode without a live check

Fix:
```bash
curl -fsS http://127.0.0.1:8787/health || curl -fsS http://127.0.0.1:8787/
```

This must be done before declaring the app ready.

### Issue H: Steel plugin name and authentication

The requested repository installs under the Hermes plugin key `browser-steel`, not `steel`. Future automation must check `hermes plugins show browser-steel`; checking only `steel` causes unnecessary reinstall attempts on every startup.

The plugin, SDK, Playwright package, and Chromium runtime can be installed without exposing a secret. Live Steel cloud browsing cannot be verified without a real key:

```bash
grep -q '^STEEL_API_KEY=.' "$HOME/.hermes/.env"
hermes plugins show browser-steel
hermes plugins doctor browser-steel
hermes config get browser.cloud_provider
```

Never commit either `.env` file or print the API key. If the key is missing, report Steel as installed but authentication-pending; do not claim that a cloud browser session has been tested.

If the Steel session API returns HTTP 403, the integration is installed but the current key/account is not authorized. Replace `STEEL_API_KEY` from the Steel dashboard and retry; do not alter the working Gemini provider to fix a Steel authentication response.

### Issue I: Large requests were executed as one opaque turn

Symptoms:
- a complex request could fail late without identifying which action failed
- a browser task could report a result without separately verifying navigation or extraction

Root cause:
- no persistent instruction required decomposition, per-step verification, or resumable progress

Fix:
- add `AGENTS.md` to the workspace
- append a managed policy to `~/.hermes/SOUL.md` without overwriting the existing personality
- enable `compression.checkpoint_required=true`

Required behavior:
- plan small ordered tasks
- execute one task at a time
- verify every task
- repair failures at the failing boundary
- report completed steps, evidence, blockers, and the next action

## 3. Required startup sequence for future launches

Use this sequence whenever a fresh Codespace is started or the app needs to be relaunched.

### Step 1: restore the necessary environment
```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"
[ -f "$HOME/.bashrc" ] && [[ $- == *i* ]] && . "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && [[ $- == *i* ]] && . "$HOME/.profile"
```

### Step 2: load environment keys and ensure Gemini is set
```bash
if [ -f "$HOME/.hermes/.env" ]; then
  set -a
  . "$HOME/.hermes/.env"
  set +a
fi

if [ -n "${GEMINI_API_KEY:-}" ]; then
  export GOOGLE_API_KEY="${GEMINI_API_KEY}"
fi

if [ -n "${GOOGLE_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  export GEMINI_API_KEY="${GOOGLE_API_KEY}"
fi
```

### Step 3: force Hermes to use Gemini
```bash
hermes config set model.provider gemini
hermes config set model.default gemini-2.5-flash
hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta
hermes config set browser.cloud_provider steel --force
```

### Step 4: ensure Steel dependencies and plugin

The canonical setup script performs these idempotently. The equivalent commands are:

```bash
source "$HOME/hermes-webui/.venv/bin/activate"
pip install --no-input steel-sdk playwright
python -m playwright install chromium
hermes plugins show browser-steel >/dev/null 2>&1 || hermes plugins install steel-dev/hermes-steel --enable
```

### Step 5: start or restart the app cleanly
```bash
lsof -ti:8787,1111,8080 | xargs -r kill -9 || true
cd "$HOME/hermes-webui"
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi

if [ -f ./ctl.sh ]; then
  chmod +x ./ctl.sh ./start.sh
  ./ctl.sh start
else
  nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
fi
```

### Step 6: verify health, model, and Steel registration
```bash
curl -fsS http://127.0.0.1:8787/health || curl -fsS http://127.0.0.1:8787/
hermes config get model.provider
hermes config get model.default
hermes config get model.base_url
hermes config get browser.cloud_provider
hermes plugins doctor browser-steel
hermes chat --provider gemini --model gemini-2.5-flash --oneshot -q "Say hello in one short sentence using Gemini." -Q
```

## 4. Verified working state

This is the final configuration we confirmed to work successfully:

```text
provider = gemini
model = gemini-2.5-flash
base_url = https://generativelanguage.googleapis.com/v1beta
WebUI health = OK
Test prompt result = "Hello, I am Gemini."
Steel plugin = browser-steel, enabled, runtime doctor passed
```

The Steel API key is intentionally not included in this repository. Put the real key in `~/.hermes/.env` as `STEEL_API_KEY=...` before testing cloud browsing. Use this WebUI prompt only after the key is present:

```text
Using Steel browser, navigate to news.ycombinator.com, extract the top 3 headlines, and provide the live Steel session link.
```

This should be treated as the canonical target state for future launches.

## 5. Anti-patterns to avoid

- Do not trust the default Hermes provider selection
- Do not leave the server bound to localhost in Codespaces
- Do not rely only on generic `HOST` and `PORT`; use the controller-specific `HERMES_WEBUI_HOST` and `HERMES_WEBUI_PORT`
- Do not skip the health check after starting the app
- Do not rely on OpenRouter without a valid key if Gemini is the intended backend
- Do not forget to set both `GEMINI_API_KEY` and `GOOGLE_API_KEY`
- Do not run a GUI/browser assumption in a headless container
- Do not skip `python3-venv` installation in minimal Ubuntu images
- Do not ignore stale processes before port reuse

## 6. What the next autopilot should do

On the next launch, the future agent should:

1. Re-source PATH and environment
2. Load `~/.hermes/.env`
3. Ensure `GEMINI_API_KEY` and `GOOGLE_API_KEY` exist
4. Force Hermes to `gemini` with `gemini-2.5-flash`
5. Bind to `0.0.0.0:8787`
6. Kill stale listeners
7. Start the app
8. Call the health endpoint
9. Run one live prompt through Gemini to verify runtime behavior
10. Verify `browser-steel` is enabled and its plugin doctor passes
11. If `STEEL_API_KEY` is absent, report Steel authentication as pending
12. Only then consider the deployment successful

For a multi-step user request, apply the task execution loop before performing the work. The startup policy is not a substitute for live verification.

## 7. Files that contain the actual runtime fix

- [scripts/setup-hermes-webui.sh](../scripts/setup-hermes-webui.sh)
- [.devcontainer/post-start.sh](../.devcontainer/post-start.sh)
- [.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json)

These files are the source of truth for the final working configuration and should be used as the default automation path on future launches.
