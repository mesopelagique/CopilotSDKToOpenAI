# CopilotSDKToOpenAI

A 4D project that wraps [GitHub Copilot](https://github.com/mesopelagique/CopilotSDK) behind an OpenAI-compatible HTTP API, so any OpenAI client can talk to Copilot without modification.

![Chat web page demo](Screenshot.png)

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/v1/models` | Lists available Copilot models in OpenAI format |
| `POST` | `/v1/chat/completions` | Chat completions (JSON and SSE streaming supported) |
| `GET`  | `/chat` | Bundled web chat page (`copilot-chat.html` in the web root) |

## Dependencies

- [mesopelagique/CopilotSDK](https://github.com/mesopelagique/CopilotSDK) — Copilot client SDK
- [4d/4D-AIKit](https://github.com/4d/4D-AIKit) — loaded automatically

## Session affinity

Each HTTP session maps to one persistent Copilot session (conversation state is kept server-side). The session key is resolved in order:

1. `X-Copilot-Session` request header
2. 4D web `Session.id`
3. Falls back to `"default"`

## Configuration

Send a `configure` task to the `CopilotChatService` singleton (inside the `CopilotChat` worker) with any of the following options:

| Option | Type | Description |
|--------|------|-------------|
| `cliPath` | Text | Path to the Copilot CLI binary |
| `workingDirectory` | Text | Working directory for the CLI |
| `gitHubToken` | Text | GitHub token (overrides logged-in user) |
| `useLoggedInUser` | Boolean | Use the currently logged-in GitHub account |
| `model` | Text | Default model to use |
| `approveAll` | Boolean | Auto-approve tool permission requests (default: `false`) |
| `tools` | Collection | Server-side tool declarations and handlers |

## Class reference

| Class | Description |
|-------|-------------|
| [`CopilotChatHTTPHandler`](Documentation/Classes/CopilotChatHTTPHandler.md) | HTTP request handlers — routes incoming requests and returns responses |
| [`CopilotChatService`](Documentation/Classes/CopilotChatService.md) | Worker singleton — manages Copilot client and per-session state |
