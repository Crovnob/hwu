# Hermes WebUI project handoff

## Current status

This repository contains the Codespaces automation and operating instructions for Hermes Agent with Hermes WebUI, Google Gemini, Steel cloud browser automation, and incremental task execution.

The project is ready to push after local verification. Runtime secrets are intentionally kept outside Git in `~/.hermes/.env` and `~/hermes-webui/.env`.

## Working capabilities

- Hermes Agent installs through the official installer.
- Hermes WebUI runs as a background service on port `8787`.
- The service binds to `0.0.0.0`, allowing Codespaces forwarding.
- Codespaces port `8787` is automatically requested as public when GitHub CLI access is available.
- Gemini is explicitly selected as the model provider.
- The default model is `gemini-2.5-flash`.
- The Google Generative Language API base URL is configured explicitly.
- The official `browser-steel` Hermes plugin is installed and enabled.
- Steel is selected as the cloud browser provider.
- Steel SDK, Playwright, and Chromium are installed in the WebUI virtual environment.
- Steel live session viewer URLs are propagated by the plugin to the agent.
- Existing Gemini keys, gateway credentials, and Hermes session data are preserved.
- Multi-action requests are split into small ordered tasks with verification after each task.
- Browser actions preserve the Steel session until completion and return the live viewer link when available.
- Startup is idempotent and can be repeated without reinstalling the plugin or replacing non-empty credentials.

## Runtime source of truth

- [AGENTS.md](../AGENTS.md): repository task-execution and browser policy.
- [scripts/setup-hermes-webui.sh](../scripts/setup-hermes-webui.sh): installation, configuration, dependency setup, restart, health check, and public port request.
- [.devcontainer/post-start.sh](../.devcontainer/post-start.sh): fresh-Codespace startup enforcement.
- [.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json): lifecycle hook registration.
- [docs/autopilot-runbook.md](autopilot-runbook.md): detailed future-agent procedure.
- [docs/issue-log.md](issue-log.md): issue-by-issue history.
- [docs/master-prompt.md](master-prompt.md): reusable Autopilot prompt.

## Problems found and fixes

### 1. Hermes selected the wrong provider

Hermes initially retained OpenRouter defaults and selected a Claude model. Requests failed with missing OpenRouter authentication even though the Gemini key was valid.

Fix:

```bash
hermes config set model.provider gemini
hermes config set model.default gemini-2.5-flash
hermes config set model.base_url https://generativelanguage.googleapis.com/v1beta
```

Lesson: a valid Gemini key is not enough; the provider, model, and base URL must be explicitly forced.

### 2. PATH was corrupted

An invalid PATH export removed normal system directories and caused basic commands to fail after installation.

Fix: restore the system directories first, then append Hermes locations:

```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.hermes/bin"
```

Lesson: never replace the operating system PATH with only application directories.

### 3. Python virtual environments were unavailable

The Ubuntu Codespace image had Python but did not have the `venv` module.

Fix: detect `python3 -m venv` support and install `python3-venv` when needed.

### 4. Stale processes held required ports

Previous WebUI processes could block `8787`, `1111`, or `8080`.

Fix: remove stale listeners before startup and verify the new process afterward.

### 5. WebUI listened only on localhost

The application worked locally but could not be reached through Codespaces forwarding.

Root cause: Hermes WebUI `ctl.sh` uses `HERMES_WEBUI_HOST` and `HERMES_WEBUI_PORT`; generic `HOST` and `PORT` were insufficient.

Fix: persist both controller variables and pass explicit startup arguments:

```bash
./ctl.sh start --host 0.0.0.0 8787
```

### 6. The forwarded URL became stale or private

The browser showed `404` or an invalid response while the local app was healthy.

Fix: bind to all interfaces, reapply public visibility with:

```bash
gh codespace ports visibility 8787:public -c "$CODESPACE_NAME"
```

and always obtain the current URL from:

```bash
gh codespace ports -c "$CODESPACE_NAME" --json sourcePort,visibility,browseUrl
```

### 7. Steel was not initially integrated

Steel was absent from the original Hermes installation.

Fix: install the official Git plugin and use its actual Hermes key:

```bash
hermes plugins install steel-dev/hermes-steel --enable
hermes config set browser.cloud_provider steel --force
```

The installed plugin name is `browser-steel`, not `steel`.

### 8. Steel credentials could be overwritten by an empty WebUI entry

The Hermes environment contained a valid key while the WebUI environment could contain an empty key. Environment loading order could make the empty value win.

Fix: load the WebUI environment first, load Hermes environment second, and fill only empty entries. Existing non-empty credentials are never overwritten.

### 9. Steel API authentication appeared inconsistent

One test returned `403`, but a later direct request with the same configured key returned `201` and created a live session. The successful session was released with `200`.

Lesson: test the current endpoint and key directly before changing integration code. A transient `403` must not be misdiagnosed as a Gemini failure.

### 10. Large requests lacked resumable execution rules

A complex task could fail late without identifying the failed action.

Fix: add repository instructions and a managed Hermes `SOUL.md` policy requiring small ordered tasks, per-step verification, failure repair, and resumable progress. Checkpoint mode is enabled with:

```bash
hermes config set compression.checkpoint_required true
```

## Verification evidence

The following checks passed during this project:

```text
Hermes provider: gemini
Hermes model: gemini-2.5-flash
Browser provider: steel
Steel plugin: browser-steel v1.0.0, enabled
Steel plugin doctor: runtime discovery, import, and registration passed
WebUI listener: 0.0.0.0:8787
WebUI health: status ok
Codespaces visibility: public
Forwarded WebUI response: HTTP 200
```

A live Steel browser session also passed these actions:

```text
session_created=yes
viewer_url_present=yes
task_1_open_search_engine=ok
task_2_search_exact_phrase=ok
task_3_inspect_results=ok
task_4_summary=...
release_status=200
```

The full Hermes/Gemini browser prompt was attempted, but Gemini's free-tier request quota returned HTTP `429` before tool selection. This is a Google API quota limitation, not a Steel or WebUI failure. After quota resets or billing is enabled, rerun the Hermes browser prompt.

## Recommended smoke test after push

Use the current forwarded URL and send this in the WebUI:

```text
Use Steel browser. Open https://news.ycombinator.com, inspect the page, and return the live Steel session viewer link before extracting the first three headlines. Verify each step and keep the session active while working.
```

The expected result includes the headlines and a URL shaped like:

```text
https://app.steel.dev/sessions/<session-id>
```

## Operator experience and lessons

The most important lesson was to distinguish configuration, application health, provider authentication, and external service limits. A green WebUI health check proves only that the server is serving HTTP; it does not prove Gemini or Steel can complete a task. Conversely, a Gemini quota error does not justify changing working browser code.

The reliable workflow is: inspect the controlling layer, make one small change, verify it immediately, then continue. For this project that means checking the listener and forwarded URL separately, checking Gemini separately, checking Steel session creation separately, and only then testing the combined Hermes workflow.

## Push safety

Before pushing:

1. Run `git diff --check`.
2. Run `bash -n scripts/setup-hermes-webui.sh .devcontainer/post-start.sh`.
3. Confirm `.env` files and API keys are not tracked.
4. Confirm the WebUI health endpoint.
5. Confirm Gemini and Steel configuration values without printing secrets.
6. Commit all repository changes and push `main`.
