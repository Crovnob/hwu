#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"

if [ -f "$HOME/.hermes/.env" ]; then
  set -a
  . "$HOME/.hermes/.env"
  set +a
fi

if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
  export GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
  export GOOGLE_API_KEY="${GOOGLE_API_KEY:-${GEMINI_API_KEY:-}}"
fi

if command -v hermes >/dev/null 2>&1; then
  hermes config set model.provider gemini >/dev/null 2>&1 || true
  hermes config set model.default gemini-2.5-flash >/dev/null 2>&1 || true
  hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta >/dev/null 2>&1 || true
fi

if [ -f /workspaces/hwu/scripts/setup-hermes-webui.sh ]; then
  chmod +x /workspaces/hwu/scripts/setup-hermes-webui.sh
  /workspaces/hwu/scripts/setup-hermes-webui.sh >/tmp/hermes-webui-boot.log 2>&1 || true
fi
