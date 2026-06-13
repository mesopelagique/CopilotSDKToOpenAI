//%attributes = {}
var $copilotCliPath : Text:="/opt/homebrew/bin/copilot"
var $runtimeEnv : Object:={PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"; HOME: "/Users/phimage"}

// --- chat service with fixed server-side tools
var $chatService : cs:C1710.CopilotChatService:=cs:C1710.CopilotChatService.me
var $chatSessionKey : Text:="chat_service_tools"
$chatService.configure({\
cliPath: $copilotCliPath; \
workingDirectory: Folder:C1567(fk database folder:K87:14; *); \
env: $runtimeEnv; \
approveAll: True:C214; \
tools: [{\
name: "get_service_secret"; \
description: "Returns the chat service secret word"; \
parameters: {type: "object"; properties: {}}; \
handler: Formula:C1597("kumquat")}]})

var $chatResponse : Object:=$chatService._chat({sessionKey: $chatSessionKey; body: {messages: [{role: "user"; content: "Call the get_service_secret tool and reply with only the secret word it returns."}]}})
ASSERT:C1129($chatResponse.status=200; "Chat service should return 200, got "+JSON Stringify:C1217($chatResponse))

var $chatPayload : Object:=JSON Parse:C1218(String:C10($chatResponse.body); Is object:K8:27)
var $chatContent : Text:=String:C10($chatPayload.choices[0].message.content)
ASSERT:C1129(Position:C15("kumquat"; $chatContent)>0; "Chat service should reply with the tool result")

var $chatSession : cs:C1710.copilot.Session:=$chatService.sessions[$chatSessionKey]
ASSERT:C1129($chatSession#Null:C1517; "Chat service should cache the created session")
ASSERT:C1129($chatSession.events.query("type = :1"; "external_tool.requested").length>0; "Chat service session should invoke the configured tool")

var $chatSessionId : Text:=$chatSession.sessionId
$chatResponse:=$chatService._chat({sessionKey: $chatSessionKey; body: {messages: [{role: "user"; content: "Reply with only the secret word from earlier in this conversation."}]}})
ASSERT:C1129($chatResponse.status=200; "Chat service follow-up should return 200, got "+JSON Stringify:C1217($chatResponse))

$chatPayload:=JSON Parse:C1218(String:C10($chatResponse.body); Is object:K8:27)
$chatContent:=String:C10($chatPayload.choices[0].message.content)
ASSERT:C1129(Position:C15("kumquat"; $chatContent)>0; "Cached chat session should remember the previous tool result")
ASSERT:C1129($chatService.sessions[$chatSessionKey].sessionId=$chatSessionId; "Chat service should reuse the cached session for the same key")

$chatService.configure({})
