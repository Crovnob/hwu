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

load_env_file "$HOME/.hermes/.env"
load_env_file "$HOME/hermes-webui/.env"

if [ -f "$HOME/.bashrc" ] && [[ $- == *i* ]]; then
  . "$HOME/.bashrc"
fi

if [ -f "$HOME/.profile" ] && [[ $- == *i* ]]; then
  . "$HOME/.profile"
fi

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
chmod 600 "$WEBUI_ENV_FILE"

lsof -ti:8787,1111,8080 | xargs -r kill -9 || true

if [ -f "$WEBUI_DIR/ctl.sh" ]; then
  chmod +x "$WEBUI_DIR/ctl.sh" "$WEBUI_DIR/start.sh"
  (cd "$WEBUI_DIR" && ./ctl.sh start)
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
echo "--------------------------------------------------"
