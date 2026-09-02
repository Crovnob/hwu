#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"

load_env_file() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
  fi
}

load_env_file "$HOME/hermes-webui/.env"
load_env_file "$HOME/.hermes/.env"

if [ -f "$HOME/.bashrc" ] && [[ $- == *i* ]]; then
  . "$HOME/.bashrc"
fi

if [ -f "$HOME/.profile" ] && [[ $- == *i* ]]; then
  . "$HOME/.profile"
fi

ensure_env_value() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$env_file"; then
    if [ -n "$value" ] && grep -q "^${key}=$" "$env_file"; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    fi
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

install_task_policy() {
  local soul_file="$HOME/.hermes/SOUL.md"
  mkdir -p "$HOME/.hermes"
  if ! grep -q '^## Managed task execution policy$' "$soul_file" 2>/dev/null; then
    cat >> "$soul_file" <<'EOF'

## Managed task execution policy

For requests with multiple meaningful actions, split the work into the smallest useful ordered steps before acting. State a short checklist and completion condition, execute one step at a time, and run the cheapest relevant verification after each step. If a step fails, diagnose and repair that step before continuing; never claim success from configuration alone. Preserve completed work and resume from the first incomplete step after interruption. Finish with completed steps, verification evidence, blockers, and the next action.

For browser tasks, use the selected Steel browser tools and decompose the request into small actions such as opening the URL, inspecting the page, extracting one requested data set, and returning links or results. Verify each navigation or extraction result, preserve the session until the task is complete, and return the live Steel session URL when available. Do not replace an explicitly requested browser action with a normal HTTP request or claim success without provider, session, and result verification.

Keep Gemini as the model provider with gemini-2.5-flash unless the user requests another model. Keep Steel as the browser provider for browser automation. Diagnose provider errors at their own boundary and do not change working Gemini settings to fix a Steel error.
EOF
  fi
}

install_task_policy

PACKAGES=(git curl wget build-essential xz-utils tar python3 python3-pip python3-venv lsof)
for pkg in "${PACKAGES[@]}"; do
  if ! command -v "$pkg" >/dev/null 2>&1 && [ "$pkg" != "python3" ] && [ "$pkg" != "python3-pip" ] && [ "$pkg" != "python3-venv" ]; then
    echo "Installing missing package: $pkg"
    sudo apt-get update
    sudo apt-get install -y "$pkg"
  fi
done

if ! python3 --version >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y python3 python3-pip python3-venv
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "Installing python3-venv for virtual environment support"
  sudo apt-get update
  sudo apt-get install -y python3-venv
fi

if ! command -v hermes >/dev/null 2>&1; then
  echo "Installing Hermes Agent CLI"
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
fi

[ -f "$HOME/.bashrc" ] && grep -q "export PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$HOME/.local/bin:\$HOME/.hermes/bin\"" "$HOME/.bashrc" || echo 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"' >> "$HOME/.bashrc"
[ -f "$HOME/.profile" ] && grep -q "export PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$HOME/.local/bin:\$HOME/.hermes/bin\"" "$HOME/.profile" || echo 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"' >> "$HOME/.profile"

if [ -f "$HOME/.bashrc" ] && [[ $- == *i* ]]; then
  . "$HOME/.bashrc" 2>/dev/null || true
fi
if [ -f "$HOME/.profile" ] && [[ $- == *i* ]]; then
  . "$HOME/.profile" 2>/dev/null || true
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"

mkdir -p "$HOME/.hermes"
if command -v hermes >/dev/null 2>&1; then
  hermes --version || which hermes || true
fi

if [ -n "${GEMINI_API_KEY:-}" ]; then
  export GOOGLE_API_KEY="${GEMINI_API_KEY}"
fi

if [ -n "${GOOGLE_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  export GEMINI_API_KEY="${GOOGLE_API_KEY}"
fi

if command -v hermes >/dev/null 2>&1; then
  export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
  if [ -n "${GEMINI_API_KEY:-}" ]; then
    hermes config set model.provider gemini >/dev/null 2>&1 || true
    hermes config set model.default gemini-2.5-flash >/dev/null 2>&1 || true
    hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta >/dev/null 2>&1 || true
    export GOOGLE_API_KEY="${GEMINI_API_KEY}"
    export GEMINI_API_KEY="${GEMINI_API_KEY}"
  fi

  if ! hermes plugins show browser-steel >/dev/null 2>&1; then
    echo "Installing Hermes Steel browser plugin"
    hermes plugins install steel-dev/hermes-steel --enable
  fi
  hermes config set browser.cloud_provider steel --force >/dev/null 2>&1 || true
  hermes config set compression.checkpoint_required true >/dev/null 2>&1 || true
fi

WEBUI_DIR="$HOME/hermes-webui"
if [ ! -d "$WEBUI_DIR" ]; then
  git clone https://github.com/nesquena/hermes-webui.git "$WEBUI_DIR"
fi

cd "$WEBUI_DIR"
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi
pip install --no-input steel-sdk playwright
python -m playwright install chromium

mkdir -p "$HOME/.hermes"
ENV_FILE="$HOME/.hermes/.env"
if [ ! -f "$ENV_FILE" ]; then
  touch "$ENV_FILE"
fi

if ! grep -q '^GEMINI_API_KEY=' "$ENV_FILE"; then
  printf '\nGEMINI_API_KEY=%s\n' "${GEMINI_API_KEY:-}" >> "$ENV_FILE"
fi
if ! grep -q '^GOOGLE_API_KEY=' "$ENV_FILE"; then
  printf 'GOOGLE_API_KEY=%s\n' "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" >> "$ENV_FILE"
fi
if ! grep -q '^GATEWAY_TOKEN=' "$ENV_FILE"; then
  printf 'GATEWAY_TOKEN=%s\n' "${GATEWAY_TOKEN:-hermes-codespace-pass}" >> "$ENV_FILE"
fi
if ! grep -q '^HOST=' "$ENV_FILE"; then
  printf 'HOST=0.0.0.0\n' >> "$ENV_FILE"
fi
if ! grep -q '^PORT=' "$ENV_FILE"; then
  printf 'PORT=8787\n' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

ensure_env_value "$ENV_FILE" "STEEL_API_KEY" "${STEEL_API_KEY:-}"
ensure_env_value "$ENV_FILE" "BROWSER_PROVIDER" "steel"
ensure_env_value "$ENV_FILE" "BROWSER_HEADLESS" "true"
ensure_env_value "$ENV_FILE" "HERMES_WEBUI_HOST" "0.0.0.0"
ensure_env_value "$ENV_FILE" "HERMES_WEBUI_PORT" "8787"
chmod 600 "$ENV_FILE"

WEBUI_ENV_FILE="$WEBUI_DIR/.env"
if [ ! -f "$WEBUI_ENV_FILE" ]; then
  touch "$WEBUI_ENV_FILE"
fi

for item in "GEMINI_API_KEY=${GEMINI_API_KEY:-}" "GOOGLE_API_KEY=${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" "GATEWAY_TOKEN=${GATEWAY_TOKEN:-hermes-codespace-pass}" "HOST=0.0.0.0" "PORT=8787"; do
  key="${item%%=*}"
  value="${item#*=}"
  if ! grep -q "^${key}=" "$WEBUI_ENV_FILE"; then
    printf '%s=%s\n' "$key" "$value" >> "$WEBUI_ENV_FILE"
  fi
done
ensure_env_value "$WEBUI_ENV_FILE" "STEEL_API_KEY" "${STEEL_API_KEY:-}"
ensure_env_value "$WEBUI_ENV_FILE" "BROWSER_PROVIDER" "steel"
ensure_env_value "$WEBUI_ENV_FILE" "BROWSER_HEADLESS" "true"
ensure_env_value "$WEBUI_ENV_FILE" "HERMES_WEBUI_HOST" "0.0.0.0"
ensure_env_value "$WEBUI_ENV_FILE" "HERMES_WEBUI_PORT" "8787"
chmod 600 "$WEBUI_ENV_FILE"

lsof -ti:8787,1111,8080 | xargs -r kill -9 || true

if [ -f "$WEBUI_DIR/ctl.sh" ]; then
  chmod +x "$WEBUI_DIR/ctl.sh" "$WEBUI_DIR/start.sh"
  (cd "$WEBUI_DIR" && ./ctl.sh start --host 0.0.0.0 8787)
else
  nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
fi

for attempt in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8787/health >/dev/null 2>&1 || curl -fsS http://127.0.0.1:8787/ >/dev/null 2>&1; then
    echo "Hermes WebUI is running on http://127.0.0.1:8787"
    break
  fi
  sleep 2
done

echo "--------------------------------------------------"
echo "WebUI URL: http://127.0.0.1:8787"
echo "Codespace forwarded URL: use the 'Ports' tab and open the public URL for port 8787"
echo "Gateway token: ${GATEWAY_TOKEN:-hermes-codespace-pass}"
echo "Gemini API config: ${GEMINI_API_KEY:+present}"
if command -v gh >/dev/null 2>&1 && [ -n "${CODESPACE_NAME:-}" ]; then
  gh codespace ports visibility 8787:public -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
fi
echo "--------------------------------------------------"
