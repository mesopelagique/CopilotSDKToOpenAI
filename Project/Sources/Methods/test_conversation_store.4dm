//%attributes = {}
// Unit tests for the conversation store in cs.CopilotChatService — pure, no Copilot connection.

SET ASSERT ENABLED:C1131(True:C214)

var $svc : cs:C1710.CopilotChatService:=cs:C1710.CopilotChatService.me
// Isolate from any running state: clean in-memory store, no live sessions/client
$svc.store:={conversations: []}
$svc.sessions:={}

// --- a first turn creates the conversation with a title derived from the user message
$svc._recordTurn("sess-1"; "Hello there world"; "Hi back"; {model: "gpt-test"})
var $c1 : Object:=$svc._storeEntry("sess-1")
ASSERT:C1129($c1#Null:C1517; "recordTurn should create the conversation")
ASSERT:C1129($c1.title="Hello there world"; "title should come from the first user message, got "+String:C10($c1.title))
ASSERT:C1129($c1.model="gpt-test"; "model should be recorded")
ASSERT:C1129($c1.messages.length=2; "a turn should store user+assistant, got "+String:C10($c1.messages.length))
ASSERT:C1129($c1.messages[0].role="user"; "first stored message should be the user")
ASSERT:C1129($c1.messages[0].content="Hello there world"; "user content should be stored")
ASSERT:C1129($c1.messages[1].role="assistant"; "second stored message should be the assistant")
ASSERT:C1129($c1.messages[1].content="Hi back"; "assistant content should be stored")

// --- a second turn on the same id appends and keeps the title
$svc._recordTurn("sess-1"; "Follow up"; "Sure"; {})
$c1:=$svc._storeEntry("sess-1")
ASSERT:C1129($c1.messages.length=4; "second turn should append, got "+String:C10($c1.messages.length))
ASSERT:C1129($c1.title="Hello there world"; "title should not change on later turns")

// --- a turn on another id makes a second conversation
$svc._recordTurn("sess-2"; "Another chat"; "Ok"; {})
ASSERT:C1129($svc.store.conversations.length=2; "there should be two conversations")

// --- list endpoint, most-recently-updated first
var $list : Object:=$svc._sessions()
ASSERT:C1129($list.status=200; "list should be 200")
var $listBody : Object:=JSON Parse:C1218($list.body)
ASSERT:C1129($listBody.data.length=2; "list should hold two conversations")
ASSERT:C1129($listBody.data[0].id="sess-2"; "the most recently updated conversation should be first")
ASSERT:C1129($listBody.data[0].messageCount=2; "messageCount should be reported")

// --- messages endpoint
var $msgs : Object:=$svc._messages({sessionKey: "sess-1"})
ASSERT:C1129($msgs.status=200; "messages should be 200")
var $msgsBody : Object:=JSON Parse:C1218($msgs.body)
ASSERT:C1129($msgsBody.messages.length=4; "messages should return the full transcript")

var $missing : Object:=$svc._messages({sessionKey: "nope"})
ASSERT:C1129($missing.status=404; "messages for an unknown id should be 404")

// --- rename endpoint
var $renamed : Object:=$svc._renameSession({sessionKey: "sess-1"; title: "Renamed"})
ASSERT:C1129($renamed.status=200; "rename should be 200")
ASSERT:C1129($svc._storeEntry("sess-1").title="Renamed"; "rename should update the title")

// --- delete endpoint (no live session/client here, so only the store is touched)
var $deleted : Object:=$svc._deleteSession({sessionKey: "sess-1"})
ASSERT:C1129($deleted.status=200; "delete should be 200")
ASSERT:C1129($svc._storeEntry("sess-1")=Null:C1517; "delete should remove the conversation")
ASSERT:C1129($svc.store.conversations.length=1; "one conversation should remain after delete")

// --- title trimming and truncation
var $long : Text:=""
var $i : Integer
For ($i; 1; 90)
	$long:=$long+"a"
End for
ASSERT:C1129(Length:C16($svc._titleFromText($long))=61; "long titles should be truncated to 60 chars plus an ellipsis")
ASSERT:C1129($svc._titleFromText("   ")="New conversation"; "blank titles should fall back to a default")

// cleanup
$svc.store:={conversations: []}
$svc.sessions:={}
