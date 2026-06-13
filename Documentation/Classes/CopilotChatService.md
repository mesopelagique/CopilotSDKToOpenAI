# CopilotChatService

OpenAI-compatible chat service backed by Copilot sessions.

Lives as a **process singleton** inside the `CopilotChat` worker. Because `cs.copilot.Client` owns a `SystemWorker` and closures, it cannot be shared with web processes. HTTP handlers send tasks here via `CALL WORKER` and wait on a signal.

## Properties

| Property   | Type                  | Description |
|------------|-----------------------|-------------|
| `options`  | Object                | Current configuration options (set via `configure`) |
| `client`   | cs.copilot.Client     | Lazily created Copilot CLI client |
| `sessions` | Object                | Map of session key → `cs.copilot.Session` |

## Public functions

### `handle($task)`

```
Function handle($task : Object)
```

Main entry point called by the `_copilotChatWorker` method. Dispatches the task to the appropriate handler based on `$task.type`.

| `type`        | Action |
|---------------|--------|
| `"configure"` | Calls `configure($task.options)` |
| `"models"`    | Returns available models |
| `"chat"`      | Runs a chat turn |
| *(unknown)*   | Returns `404` error |

Errors are caught and returned as `500` responses. The result is stored as a JSON string in `$task.signal.result` and the signal is triggered.

---

### `configure($options)`

```
Function configure($options : Object)
```

Resets all current state (disconnects sessions, stops the client) and stores new options. Supported options:

| Option               | Type       | Description |
|----------------------|------------|-------------|
| `cliPath`            | Text       | Path to the Copilot CLI binary |
| `cliArgs`            | Collection | Extra arguments passed to the CLI |
| `workingDirectory`   | Text       | Working directory for the CLI |
| `baseDirectory`      | Text       | Base directory used by the CLI |
| `env`                | Object     | Additional environment variables |
| `gitHubToken`        | Text       | GitHub token (overrides the logged-in user) |
| `useLoggedInUser`    | Boolean    | Use the currently logged-in GitHub account |
| `logLevel`           | Text       | CLI log level |
| `model`              | Text       | Default model |
| `approveAll`         | Boolean    | Auto-approve tool permission requests (default: `false`) |
| `tools`              | Collection | Server-side tool declarations and handlers |

## Private functions

### `_resetState()`

```
Function _resetState()
```

Disconnects all active Copilot sessions and stops the client. Called by `configure` before applying new options.

---

### `_ensureClient()`

```
Function _ensureClient() : cs.copilot.Client
```

Returns the active `cs.copilot.Client`, creating and starting it if it does not yet exist. Forwards the relevant keys from `options` to the client constructor.

---

### `_models()`

```
Function _models() : Object
```

Lists available models via the Copilot client and returns them formatted as an OpenAI `"list"` response.

Each entry has the shape:

```json
{
  "id": "<model-id>",
  "object": "model",
  "created": <unix-epoch>,
  "owned_by": "github-copilot"
}
```

---

### `_chat($task)`

```
Function _chat($task : Object) : Object
```

Executes one chat turn:

1. Extracts the last user message from `$task.body.messages`.
2. Resolves (or creates) a `cs.copilot.Session` via `_sessionFor`.
3. Sends the prompt with `session.sendAndWait`.
4. Returns an OpenAI `chat.completion` object (or SSE stream if `$task.body.stream` is `true`).

Returns `400` if no user message is found.

---

### `_sessionFor($sessionKey, $body, $messages)`

```
Function _sessionFor($sessionKey : Text; $body : Object; $messages : Collection) : cs.copilot.Session
```

Returns the existing Copilot session for `$sessionKey`, or creates a new one. On creation:

- Sets the model from `$body.model` (if provided and not `"github-copilot"`).
- Sets the system message from the first `"system"` role message.
- Attaches configured server-side tools.
- Registers `_decidePermission` as the `onPermissionRequest` callback.

New sessions are cached in `This.sessions[$sessionKey]`.

---

### `_configuredTools()`

```
Function _configuredTools() : Collection
```

Validates and normalises the `tools` array from `options`. Each tool must have a `name`. Optional fields: `description`, `parameters`, `handler`, `skipPermission`, `overridesBuiltInTool`.

---

### `_decidePermission($permissionRequest)`

```
Function _decidePermission($permissionRequest : Object) : Object
```

Permission callback for Copilot tool requests.

- If `options.approveAll` is `true` → returns `{kind: "approve-once"}`.
- Otherwise → returns `{kind: "reject"}` with an explanatory feedback message.

---

### `_contentText($content)`

```
Function _contentText($content : Variant) : Text
```

Converts an OpenAI message `content` value to plain text:

- If already a text string → returned as-is.
- If a collection of parts → concatenates all parts where `type = "text"`, joined by newlines.
- Otherwise → returns `""`.

---

### `_json($status, $payload)`

```
Function _json($status : Integer; $payload : Object) : Object
```

Helper that returns `{status; contentType: "application/json"; body: <JSON string>}`.

---

### `_epoch()`

```
Function _epoch() : Integer
```

Returns the current time as a Unix epoch integer (seconds since 1970-01-01).

## See also

- [CopilotChatHTTPHandler](CopilotChatHTTPHandler.md) — the HTTP layer that dispatches tasks to this service.
