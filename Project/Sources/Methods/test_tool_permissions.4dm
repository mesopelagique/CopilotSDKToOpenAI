//%attributes = {}
// Unit tests for cs.ToolPermissions — pure, no Copilot connection required.

SET ASSERT ENABLED:C1131(True:C214)

var $perms : cs:C1710.ToolPermissions:=cs:C1710.ToolPermissions.new({\
	defaultDecision: "reject"; \
	approveReadOnly: True:C214; \
	allow: ["Read"; "Shell(git status)"; "Shell(npm run test:*)"]; \
	ask: ["Shell(git push:*)"]; \
	deny: ["Shell(rm:*)"; "Shell(curl:*)"; "Read(**/.env)"]})

// --- helpers building synthetic PermissionRequest objects (see Session events)
var $shell : Object
var $decision : Object

// Allowed exact command
$shell:={kind: "shell"; fullCommandText: "git status"; commands: [{identifier: "git"; readOnly: True:C214}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="approve-once"; "git status should be approved, got "+JSON Stringify:C1217($decision))

// Allowed by glob (Claude ":*" form)
$shell:={kind: "shell"; fullCommandText: "npm run test:unit"; commands: [{identifier: "npm"; readOnly: False:C215}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="approve-once"; "npm run test:unit should be approved, got "+JSON Stringify:C1217($decision))

// Denied wins even though it would otherwise be unknown
$shell:={kind: "shell"; fullCommandText: "rm -rf /"; commands: [{identifier: "rm"; readOnly: False:C215}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="reject"; "rm should be rejected, got "+JSON Stringify:C1217($decision))

// Not in any list -> default decision (reject)
$shell:={kind: "shell"; fullCommandText: "make deploy"; commands: [{identifier: "make"; readOnly: False:C215}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="reject"; "make deploy should fall to default reject, got "+JSON Stringify:C1217($decision))

// approveReadOnly: a read-only shell command auto-approves even without an allow rule
$shell:={kind: "shell"; fullCommandText: "cat README.md"; commands: [{identifier: "cat"; readOnly: True:C214}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="approve-once"; "read-only cat should auto-approve, got "+JSON Stringify:C1217($decision))

// A write redirection cancels the read-only auto-approval
$shell:={kind: "shell"; fullCommandText: "cat x > y"; hasWriteFileRedirection: True:C214; commands: [{identifier: "cat"; readOnly: True:C214}]}
$decision:=$perms.decide($shell)
ASSERT:C1129($decision.kind="reject"; "redirecting cat should not auto-approve, got "+JSON Stringify:C1217($decision))

// Read kind allowed by "Read" rule
$decision:=$perms.decide({kind: "read"; path: "/project/src/main.4dm"})
ASSERT:C1129($decision.kind="approve-once"; "read should be approved, got "+JSON Stringify:C1217($decision))

// ...but a denied path wins over the broad Read allow
$decision:=$perms.decide({kind: "read"; path: "/project/.env"})
ASSERT:C1129($decision.kind="reject"; "reading .env should be rejected, got "+JSON Stringify:C1217($decision))

// ask rule -> askDecision (default "reject" for a headless server)
$decision:=$perms.decide({kind: "shell"; fullCommandText: "git push origin main"; commands: [{identifier: "git"; readOnly: False:C215}]})
ASSERT:C1129($decision.kind="reject"; "git push should map to askDecision, got "+JSON Stringify:C1217($decision))

// Custom tool: allowed by literal name target
$perms.allowRules("get_service_secret")
$decision:=$perms.decide({kind: "custom-tool"; toolName: "get_service_secret"; toolDescription: "secret"})
ASSERT:C1129($decision.kind="approve-once"; "named custom tool should be approved, got "+JSON Stringify:C1217($decision))

// MCP tool matched on server/tool name
$perms.allowRules("Mcp(github/*)")
$decision:=$perms.decide({kind: "mcp"; serverName: "github"; toolName: "list_issues"; readOnly: True:C214})
ASSERT:C1129($decision.kind="approve-once"; "github/* MCP tool should be approved, got "+JSON Stringify:C1217($decision))

// approveAll override (deny still wins)
var $loose : cs:C1710.ToolPermissions:=cs:C1710.ToolPermissions.new({approveAll: True:C214; deny: ["Shell(rm:*)"]})
ASSERT:C1129($loose.decide({kind: "url"; url: "https://example.com"}).kind="approve-once"; "approveAll should approve url")
ASSERT:C1129($loose.decide({kind: "shell"; fullCommandText: "rm x"; commands: [{identifier: "rm"; readOnly: False:C215}]}).kind="reject"; "deny should beat approveAll")

// Loading a policy from the bundled example file
var $file : 4D:C1709.File:=Folder:C1567(fk resources folder:K87:11).file("tool-permissions.example.json")
If (Asserted:C1132($file.exists; "example policy file should exist"))
	// loadFile accepts a 4D.File directly…
	var $fromFile : cs:C1710.ToolPermissions:=cs:C1710.ToolPermissions.new()
	$fromFile.loadFile($file)
	// …or a POSIX path string
	var $fromPath : cs:C1710.ToolPermissions:=cs:C1710.ToolPermissions.new()
	$fromPath.loadFile($file.path)
	ASSERT:C1129($fromPath.decide({kind: "url"; url: "https://x"}).kind="reject"; "policy from path string should deny url")
	ASSERT:C1129($fromFile.decide({kind: "shell"; fullCommandText: "git status"; commands: [{identifier: "git"; readOnly: True:C214}]}).kind="approve-once"; "file policy should allow git status")
	ASSERT:C1129($fromFile.decide({kind: "url"; url: "https://x"}).kind="reject"; "file policy should deny url")
End if

// All assertions passed if execution reaches here.
LOG EVENT:C667(Into system standard outputs:K38:9; "test_tool_permissions: PASSED"+Char:C90(10))
