# hwu

Hermes WebUI deployment for Gemini and Steel cloud browser automation in GitHub Codespaces.

## Documentation

- [Final project handoff](docs/final-project-handoff.md)
- [Autopilot runbook](docs/autopilot-runbook.md)
- [Issue log](docs/issue-log.md)
- [Master setup prompt](docs/master-prompt.md)

## Start

```bash
bash scripts/setup-hermes-webui.sh
```

The setup keeps Gemini as the default model provider, enables Steel for browser automation, binds the WebUI to `0.0.0.0:8787`, and verifies the service. Runtime secrets remain outside Git in the Hermes environment files.