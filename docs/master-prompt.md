# Hermes WebUI + Gemini API master prompt

Copy this into GitHub Copilot / Cursor / Claude Code / any AI coding agent in GitHub Codespaces.

---

You are an expert DevOps engineer and AI Systems Administrator. Your objective is to fully deploy and configure Hermes Agent (by Nous Research) along with Hermes WebUI (by nesquena) in this GitHub Codespaces environment autonomously without manual intervention.

Execute this setup in a rigorous, phased sequence. Do not skip any phase, verify every step, and handle all non-interactive Linux/headless edge cases.

You must use a Gemini-compatible API configuration to validate the app works with full functionality. If `GEMINI_API_KEY` is available, configure the app to use it. If the project requires a generic API key field, copy the Gemini key into the equivalent environment variable.

### Mandatory task execution policy
For every request containing multiple meaningful actions, use incremental execution:
1. Split the request into the smallest useful ordered tasks and state the completion condition.
2. Execute one task at a time.
3. Verify each task with the cheapest relevant check before continuing.
4. If a task fails, diagnose and repair that task before moving on; never claim success from configuration alone.
5. Preserve completed work and resume from the first incomplete task after interruption.
6. For browser requests, use Steel browser tools, verify navigation and extraction separately, preserve the session until completion, and return the live Steel session URL when available.

This policy is also installed in the Hermes workspace instructions and global `SOUL.md` by the startup script. Do not replace an explicitly requested browser action with a normal HTTP request.

---

### Phase 1: Environment & System Prerequisites Verification
1. Verify system environment:
   - Detect OS architecture (`uname -a`) and confirm Linux/Debian/Ubuntu environment.
   - Check available package managers and ensure standard build utilities (`git`, `curl`, `wget`, `build-essential`, `xz-utils`, `tar`, `python3`, `python3-pip`, `python3-venv`, `lsof`) are installed. If missing, install them non-interactively using `sudo apt-get update && sudo apt-get install -y <package>`.
2. Ensure Python 3.10+ or Python 3.11+ is available.
3. Check and kill any existing orphaned processes occupying ports 8787, 1111, or 8080.

---

### Phase 2: Install Hermes Agent Core (Nous Research)
1. Install the official Hermes Agent core CLI:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
   ```
2. Export all environment paths to the current shell session:
   - Source `~/.bashrc`, `~/.profile`, and ensure `$HOME/.local/bin` and `$HOME/.hermes/bin` are appended to `$PATH`.
3. Verify that the hermes CLI binary is installed and executable:
   ```bash
   hermes --version || which hermes
   ```
4. Create the required runtime directory if it does not already exist:
   ```bash
   mkdir -p ~/.hermes
   ```

---

### Phase 3: Clone and Prepare Hermes WebUI
1. Clone the Hermes WebUI repository to the workspace root or home directory (`~/hermes-webui`):
   ```bash
   if [ ! -d "$HOME/hermes-webui" ]; then
     git clone https://github.com/nesquena/hermes-webui.git "$HOME/hermes-webui"
   fi
   cd "$HOME/hermes-webui"
   ```
2. Set up an isolated Python virtual environment for WebUI:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install --upgrade pip
   if [ -f "requirements.txt" ]; then
     pip install -r requirements.txt
   fi
   ```

---

### Phase 4: Configuration & Environment Secrets
1. Check for existing environment API keys (e.g., `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GROQ_API_KEY`).
2. Create or update `~/.hermes/.env` and `$HOME/hermes-webui/.env` with fallback environment variables if not already present:
   - Configure a secure `GATEWAY_TOKEN` (or use a default like `hermes-codespace-pass`).
   - Set `HOST=0.0.0.0` and `PORT=8787` to ensure the server binds across all network interfaces for GitHub Codespace port forwarding.
   - Set `GEMINI_API_KEY` or `GOOGLE_API_KEY` from the environment. If the app expects another generic field, mirror the value there too.
   - Force Hermes to use Gemini directly by setting `model.provider=gemini`, `model.default=gemini-2.5-flash`, and `model.base_url=https://generativelanguage.googleapis.com/v1beta`.
3. Ensure proper file permissions on configuration files:
   ```bash
   chmod 600 ~/.hermes/.env
   chmod 600 "$HOME/hermes-webui/.env"
   ```

---

### Phase 5: Headless Server Startup & Port Forwarding
1. Recognize that GitHub Codespaces is a headless cloud environment:
   - Do NOT run commands that attempt to launch a local GUI web browser window.
2. Launch the Hermes WebUI server in background/daemon mode:
   ```bash
   cd "$HOME/hermes-webui"
   source .venv/bin/activate
   if [ -f "./ctl.sh" ]; then
     chmod +x ./ctl.sh ./start.sh
     ./ctl.sh start
   else
     nohup python3 server.py --host 0.0.0.0 --port 8787 > webui.log 2>&1 &
   fi
   ```
3. Wait 5 seconds and poll the health endpoint until the server is ready:
   ```bash
   curl -s -f http://127.0.0.1:8787/health || curl -s -f http://127.0.0.1:8787/
   ```

---

### Phase 6: Automated Verification & Report
1. Verify and output:
   - PID and process status of the running server.
   - Bound host and port (8787).
   - Active LLM configuration status.
   - Active skills and memory initialization status in `~/.hermes`.
2. Instruct the user clearly:
   - Provide the local port 8787 URL.
   - Remind the user to check the "Ports" tab in VS Code / Codespaces and set port 8787 to Public (or open in browser) to access the UI.
   - Display the active `GATEWAY_TOKEN` needed for initial login.
3. Validate Gemini integration by confirming the environment contains a valid `GEMINI_API_KEY` and the application loads without errors.

---

### Required behavior for the agent
- Be explicit about every command run.
- Do not hide failures; if a command fails, explain the cause and fix it.
- Preserve logs in `~/.hermes` and the WebUI repo.
- Use the correct headless approach for Codespaces.
- Always prefer secure, non-interactive shell operations.
- Use `0.0.0.0` for host binding, not `localhost`.

---

### How to run this in GitHub Codespaces
1. Open your GitHub Codespace.
2. Open your AI coding agent chat panel.
3. Paste the prompt above and hit Enter.
4. Once the agent finishes:
   - Go to the Ports tab.
   - Find port `8787`.
   - Click the Globe icon or copy the forwarded URL.
   - Log in using the configured `GATEWAY_TOKEN`.

---

### Minimum Gemini API requirements
The environment should contain at least one of these values before deployment completes:
- `GEMINI_API_KEY`
- `GOOGLE_API_KEY`

If neither is set, the agent must stop and explain that the app cannot be validated with live Gemini functionality until a valid key is provided.
