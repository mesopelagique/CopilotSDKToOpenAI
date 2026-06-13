// HTTP request handlers for the Copilot chat web interface (declared in Project/Sources/HTTPHandlers.json):
//   GET /chat                    the bundled chat page (copilot-chat.html)
//   GET /sessions                conversation list for the sidebar
//   GET /sessions/{id}/messages  stored transcript of one conversation
//   DELETE /sessions/{id}        delete a conversation
//   PATCH /sessions/{id}         rename a conversation (JSON body {title})
// Work is delegated to the "CopilotChat" worker via the shared _dispatch (see CopilotChatHTTPHandlerBase).
// The OpenAI-compatible API is served by a separate handler (see CopilotChatHTTPHandler).
Class extends CopilotChatHTTPHandlerBase

shared singleton Class constructor()
	Super:C1706()

Function chatPage($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	var $response : 4D:C1709.OutgoingMessage:=4D:C1709.OutgoingMessage.new()
	var $file : 4D:C1709.File:=Folder:C1567(fk web root folder:K87:15).file("copilot-chat.html")
	If ($file.exists)
		$response.setBody($file.getText())
		$response.setHeader("Content-Type"; "text/html; charset=utf-8")
	Else
		$response.setStatus(404)
		$response.setBody("copilot-chat.html not found in the web root folder")
		$response.setHeader("Content-Type"; "text/plain")
	End if
	return $response

	// GET /sessions — the conversation list for the sidebar
Function sessions($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	return This:C1470._dispatch({type: "sessions"}; 30)

	// /sessions/{id}            GET (alias of messages) · DELETE · PATCH {title}
	// /sessions/{id}/messages   GET — the stored transcript
Function session($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	var $segments : Collection:=$request.urlPath || []
	var $idIndex : Integer:=$segments.indexOf("sessions")+1
	var $id : Text:=(($idIndex>0) && ($idIndex<$segments.length)) ? String:C10($segments[$idIndex]) : ""
	If (Length:C16($id)=0)
		return This:C1470._error(400; "Missing conversation id in the URL")
	End if

	var $verb : Text:=Uppercase:C13(String:C10($request.verb))
	Case of
		: ($verb="DELETE")
			return This:C1470._dispatch({type: "deleteSession"; sessionKey: $id}; 30)
		: ($verb="PATCH")
			var $body : Variant:=Try(JSON Parse:C1218($request.getText()))
			var $title : Text:=(Value type:C1509($body)=Is object:K8:27) ? String:C10($body.title) : ""
			return This:C1470._dispatch({type: "renameSession"; sessionKey: $id; title: $title}; 30)
		Else
			// GET, whether or not the path ends with /messages
			return This:C1470._dispatch({type: "messages"; sessionKey: $id}; 30)
	End case
