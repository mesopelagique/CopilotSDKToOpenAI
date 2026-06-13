# ToolPermissions

Tool permission policy for Copilot sessions.

Decides whether an incoming Copilot tool / permission request is approved or rejected — the way Claude's `settings.json` or the Copilot CLI allow-lists work. A policy is a set of **allow**, **deny** and **ask** rules; each rule is a `Target(pattern)` string matched against the request. `CopilotChatService` builds one of these from its `permissions` / `permissionsFile` / `approveAll` options and calls `decide()` for every `onPermissionRequest`.

## Properties

| Property          | Type       | Default                | Description |
|-------------------|------------|------------------------|-------------|
| `allow`           | Collection | `[]`                   | Parsed allow rules |
| `deny`            | Collection | `[]`                   | Parsed deny rules (always win) |
| `ask`             | Collection | `[]`                   | Parsed ask rules |
| `approveAll`      | Boolean    | `False`                | Approve everything not explicitly denied |
| `approveReadOnly` | Boolean    | `False`                | Auto-approve read-only requests (read kind, read-only shell/MCP) |
| `defaultDecision` | Text       | `"reject"`             | Decision when no rule matches |
| `approveDecision` | Text       | `"approve-once"`       | Decision used when an `allow` rule matches |
| `askDecision`     | Text       | `"reject"`             | Decision used when an `ask` rule matches (no human on a headless server) |
| `rejectFeedback`  | Text       | *(generic message)*    | Feedback text returned with `reject` decisions |

## Rule syntax

A rule is `Target` or `Target(pattern)`.

**Targets** map to Copilot permission kinds (see the SDK `PermissionRequest` events):

| Target                     | Kind          | Matched against |
|----------------------------|---------------|-----------------|
| `Shell` · `Bash` · `Sh` · `Command` · `Exec` · `Run` | `shell` | `fullCommandText` and each command identifier |
| `Read` · `View` · `Cat`    | `read`        | `path` |
| `Write` · `Edit` · `Create`| `write`       | `fileName` |
| `Url` · `Web` · `Fetch`    | `url`         | `url` |
| `Mcp`                      | `mcp`         | `toolName`, `serverName`, `serverName/toolName` |
| `Tool` · `Function`        | `custom-tool` | `toolName` |
| `Memory`                   | `memory`      | `fact` |
| `Extension`                | extension management / access | — |
| `*` · `any` · `all`        | any kind      | the request's subjects |
| *(any other word)*         | a literal MCP/custom tool name | `toolName` / `serverName` |

**Pattern** is a glob: `*` (any run), `?` (one char). Claude's `:*` suffix is accepted and treated as `*` (so `Shell(npm run test:*)` ≡ `Shell(npm run test*)`). A target with no parentheses matches every request of that kind. Matching is anchored and case-sensitive.

## Decision order

1. **deny** matches → `reject` (always wins)
2. `approveAll` → `approve-once`
3. **allow** matches → `approveDecision`
4. `approveReadOnly` and the request is read-only → `approve-once`
5. **ask** matches → `askDecision`
6. otherwise → `defaultDecision`

A decision string resolves to a Copilot result object: `approve`/`approve-once` → `{kind: "approve-once"}`, `approve-for-session` → `{kind: "approve-for-session"}`, `pending` → `{kind: "no-result"}` (left pending), `user-not-available` → `{kind: "user-not-available"}`, anything else → `{kind: "reject"; feedback}`.

## Constructor

```4d
var $perms : cs.ToolPermissions:=cs.ToolPermissions.new($options)
```

`$options` accepts the keys above, optionally wrapped in a `{permissions: {…}}` object (so a Claude-style `settings.json` can be passed straight through).

## Functions

### `configure($options)` → `cs.ToolPermissions`

Merges an options object into the policy. Returns `This` for chaining.

### `loadFile($path)` → `cs.ToolPermissions`

Loads a JSON policy file (same shape as `$options`). `$path` is a POSIX path `Text` or a `4D.File`. Throws if the file is missing or is not a JSON object. Returns `This`.

### `allowRules($rules)` · `denyRules($rules)` · `askRules($rules)` → `cs.ToolPermissions`

Append one rule (`Text`) or several (`Collection` of `Text`) to the matching list. Returns `This`.

### `decide($request)` → Object

Main entry point. Takes a raw Copilot `PermissionRequest` object and returns the decision object described above.

### `handler()` → `4D.Function`

Returns a `Formula` bound to this instance, ready to assign to `session.onPermissionRequest` (called as `($permissionRequest; {sessionId})`).

```4d
$config.onPermissionRequest:=$perms.handler()
```

### `toObject()` → Object

Plain-object snapshot of the policy (rules rendered back to their raw `Target(pattern)` strings), handy for logging.

## Example

```4d
var $perms : cs.ToolPermissions:=cs.ToolPermissions.new({\
	defaultDecision: "reject"; \
	approveReadOnly: True; \
	allow: ["Read"; "Shell(git status)"; "Shell(npm run test:*)"]; \
	deny: ["Shell(rm:*)"; "Shell(curl:*)"; "Read(**/.env)"]; \
	ask: ["Shell(git push:*)"]})

$perms.loadFile("/path/to/tool-permissions.json")  // optional, merges in

$perms.decide({kind: "shell"; fullCommandText: "git status"; \
	commands: [{identifier: "git"; readOnly: True}]})  // → {kind: "approve-once"}
$perms.decide({kind: "shell"; fullCommandText: "rm -rf /"; \
	commands: [{identifier: "rm"; readOnly: False}]})  // → {kind: "reject"; feedback: …}
```

See [`Resources/tool-permissions.example.json`](../../Resources/tool-permissions.example.json) for a ready-to-edit policy file and [`test_tool_permissions`](../../Project/Sources/Methods/test_tool_permissions.4dm) for executable examples.
