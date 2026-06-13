// HTTP request handlers for the OpenAI-compatible API (declared in Project/Sources/HTTPHandlers.json):
//   POST /v1/chat/completions   GET /v1/models
// Conversation affinity: the X-Copilot-Session header, or the 4D web Session.id, maps to one
// persistent Copilot session (see CopilotChatService). Work is delegated to the "CopilotChat"
// worker via the shared _dispatch (see CopilotChatHTTPHandlerBase). The chat web interface is
// served by a separate handler (see CopilotChatWebHandler).
Class extends CopilotChatHTTPHandlerBase

shared singleton Class constructor()
	Super:C1706()

Function chatCompletions($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	var $body : Variant:=Try(JSON Parse:C1218($request.getText()))
	If (Value type:C1509($body)#Is object:K8:27)
		return This:C1470._error(400; "Request body must be a JSON object")
	End if

	var $timeout : Real:=(Num:C11($body.timeout)>0) ? Num:C11($body.timeout)+10 : 190
	return This:C1470._dispatch({type: "chat"; sessionKey: This:C1470._sessionKey($request); body: $body}; $timeout)

Function models($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	return This:C1470._dispatch({type: "models"}; 60)

Function _sessionKey($request : 4D:C1709.IncomingMessage) : Text
	var $key : Text:=String:C10($request.getHeader("x-copilot-session"))
	If (Length:C16($key)>0)
		return $key
	End if
	If (Session:C1714#Null:C1517)
		return String:C10(Session:C1714.id)
	End if
	return "default"
