# CopilotChatHTTPHandler

HTTP request handlers exposing the **OpenAI-compatible API** backed by Copilot sessions.

Declared in `Project/Sources/HTTPHandlers.json`. Implemented as a **shared singleton** that
`extends` [`CopilotChatHTTPHandlerBase`](#shared-base) for the worker-dispatch plumbing.

The chat web interface (the `/chat` page and `/sessions` endpoints) lives in a separate handler,
[CopilotChatWebHandler](CopilotChatWebHandler.md).

Work is delegated to the `CopilotChat` worker (via `CopilotChatService`); each handler sends a
task and waits on a signal for the result.

## Routes

| Method | Path | Handler |
|--------|------|---------|
| `POST` | `/v1/chat/completions` | `chatCompletions` |
| `GET`  | `/v1/models`           | `models`          |

## Public functions

### `chatCompletions($request)`

```
Function chatCompletions($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `POST /v1/chat/completions`. Parses the JSON body, resolves the session key, and dispatches a `"chat"` task to the worker.

- The `timeout` field in the request body extends the worker wait time by 10 seconds (default: 190 s).
- Returns a standard OpenAI chat-completion response (JSON or SSE streaming).
- The resolved durable conversation id is returned in the `X-Copilot-Session-Id` response header.

---

### `models($request)`

```
Function models($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `GET /v1/models`. Dispatches a `"models"` task to the worker and returns the list of available Copilot models in OpenAI format.

## Private functions

### `_sessionKey($request)`

```
Function _sessionKey($request : 4D.IncomingMessage) : Text
```

Resolves the session key used to identify the Copilot conversation, in priority order:

1. `X-Copilot-Session` request header
2. `Session.id` (4D web session)
3. `"default"` as fallback

## Shared base

`_dispatch($task; $timeout)` and `_error($status; $message)` are inherited from
**`CopilotChatHTTPHandlerBase`** (a `shared` class):

- `_dispatch` sends a task object to the `CopilotChat` worker and blocks until the signal is
  triggered or `$timeout` seconds elapse. Returns `504 Gateway Timeout` on timeout, and copies a
  `sessionId` field from the result into the `X-Copilot-Session-Id` header.
- `_error` builds an OpenAI-shaped JSON error response (`"server_error"` for `5xx`,
  `"invalid_request_error"` otherwise).

## See also

- [CopilotChatWebHandler](CopilotChatWebHandler.md) — the chat web interface handlers.
- [CopilotChatService](CopilotChatService.md) — the worker singleton that executes the tasks.
