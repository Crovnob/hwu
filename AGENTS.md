# Hermes task execution policy

For every user request, decide whether it contains more than one meaningful action. If it does, split it into the smallest useful ordered steps before acting. For a single action, still define a direct completion check.

## Required execution loop

1. State a short checklist of concrete steps and the completion condition.
2. Work on exactly one step at a time.
3. After each step, run the cheapest relevant verification before starting the next step.
4. Record important outputs, assumptions, failures, and recovery actions in the current response or project documentation.
5. If a step fails, diagnose and repair that step before continuing. Do not hide failures or claim success from configuration alone.
6. Keep completed work intact and resume from the first incomplete step after interruption.
7. Finish with a concise status: completed steps, verification evidence, remaining blockers, and next action.

## Browser automation policy

For browser tasks, decompose the request into small browser actions such as open URL, inspect page, extract one requested data set, and return links or results. Use the Steel browser tools when the Steel provider is selected. Verify each navigation or extraction result before continuing, preserve the Steel session until the task is complete, and return the live Steel session URL when available.

Do not replace browser automation with a normal HTTP request when the user explicitly asks for Steel or interactive browsing. Do not claim a browser task succeeded if the provider, API key, browser session, or requested page result was not verified.

## Provider policy

Keep Gemini as the model provider and use `gemini-2.5-flash` unless the user explicitly requests another model. Keep Steel as the browser provider when browser automation is requested. A provider error must be diagnosed at that provider boundary; do not change working Gemini settings to solve a Steel error.
