# CopilotChatHTTPHandler

HTTP request handlers exposing an OpenAI-compatible API backed by Copilot sessions.

Declared in `Project/Sources/HTTPHandlers.json`. Implemented as a **shared singleton**.

Work is delegated to the `CopilotChat` worker (via `CopilotChatService`); each handler sends a task and waits on a signal for the result.

## Routes

| Method | Path | Handler |
|--------|------|---------|
| `POST` | `/v1/chat/completions` | `chatCompletions` |
| `GET`  | `/v1/models`           | `models`          |
| `GET`  | `/chat`                | `chatPage`        |

## Public functions

### `chatCompletions($request)`

```
Function chatCompletions($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `POST /v1/chat/completions`. Parses the JSON body, resolves the session key, and dispatches a `"chat"` task to the worker.

- The `timeout` field in the request body extends the worker wait time by 10 seconds (default: 190 s).
- Returns a standard OpenAI chat-completion response (JSON or SSE streaming).

---

### `models($request)`

```
Function models($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `GET /v1/models`. Dispatches a `"models"` task to the worker and returns the list of available Copilot models in OpenAI format.

---

### `chatPage($request)`

```
Function chatPage($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `GET /chat`. Serves `copilot-chat.html` from the web root folder. Returns `404` if the file is not found.

## Private functions

### `_dispatch($task, $timeout)`

```
Function _dispatch($task : Object; $timeout : Real) : 4D.OutgoingMessage
```

Sends a task object to the `CopilotChat` worker and blocks until the signal is triggered or `$timeout` seconds elapse.

- Returns `504 Gateway Timeout` if the worker does not respond in time.
- The worker stores its result as a JSON string in `signal.result` with the shape `{status; contentType; body}`.

---

### `_sessionKey($request)`

```
Function _sessionKey($request : 4D.IncomingMessage) : Text
```

Resolves the session key used to identify the Copilot conversation, in priority order:

1. `X-Copilot-Session` request header
2. `Session.id` (4D web session)
3. `"default"` as fallback

---

### `_error($status, $message)`

```
Function _error($status : Integer; $message : Text) : 4D.OutgoingMessage
```

Builds an OpenAI-shaped JSON error response with the given HTTP status code and message.

- Uses `"server_error"` type for `5xx` codes and `"invalid_request_error"` for all others.

## See also

- [CopilotChatService](CopilotChatService.md) — the worker singleton that executes the tasks.
