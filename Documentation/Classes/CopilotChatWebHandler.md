# CopilotChatWebHandler

HTTP request handlers for the **Copilot chat web interface**: the bundled chat page and the
conversation management endpoints used by its sidebar.

Declared in `Project/Sources/HTTPHandlers.json`. Implemented as a **shared singleton** that
`extends` `CopilotChatHTTPHandlerBase` for the worker-dispatch plumbing.

The OpenAI-compatible API lives in a separate handler,
[CopilotChatHTTPHandler](CopilotChatHTTPHandler.md).

## Routes

| Method | Path | Handler |
|--------|------|---------|
| `GET`    | `/chat`                  | `chatPage` |
| `GET`    | `/sessions`              | `sessions` |
| `GET`    | `/sessions/{id}/messages`| `session`  |
| `DELETE` | `/sessions/{id}`         | `session`  |
| `PATCH`  | `/sessions/{id}`         | `session`  |

The `/sessions/{id}` routes share one handler method (`session`), which branches on the HTTP verb.
All verbs for that URL must be declared on a single handler, because the web server rejects a
request whose verb is not allowed by the first handler matching the URL.

## Public functions

### `chatPage($request)`

```
Function chatPage($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `GET /chat`. Serves `copilot-chat.html` from the web root folder. Returns `404` if the file is not found.

---

### `sessions($request)`

```
Function sessions($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles `GET /sessions`. Dispatches a `"sessions"` task and returns the conversation list (id, title, model, timestamps, message count) for the sidebar, most recently updated first.

---

### `session($request)`

```
Function session($request : 4D.IncomingMessage) : 4D.OutgoingMessage
```

Handles the per-conversation routes under `/sessions/{id}`. The id is read from `$request.urlPath`
(the path segment after `sessions`), and the action is chosen from `$request.verb`:

- `GET` → dispatches `"messages"` (the stored transcript), whether or not the path ends with `/messages`.
- `DELETE` → dispatches `"deleteSession"`.
- `PATCH` → dispatches `"renameSession"` with the `title` from the JSON body.

Returns `400` if no id is present in the URL.

## Shared base

`_dispatch($task; $timeout)` and `_error($status; $message)` are inherited from
`CopilotChatHTTPHandlerBase` — see [CopilotChatHTTPHandler](CopilotChatHTTPHandler.md#shared-base).

## See also

- [CopilotChatHTTPHandler](CopilotChatHTTPHandler.md) — the OpenAI-compatible API handlers.
- [CopilotChatService](CopilotChatService.md) — the worker singleton that executes the tasks.
