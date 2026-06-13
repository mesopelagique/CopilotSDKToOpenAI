// HTTP request handlers (declared in Project/Sources/HTTPHandlers.json) exposing an
// OpenAI-compatible API backed by Copilot sessions:
//   POST /v1/chat/completions   GET /v1/models   GET /chat (bundled web page)
// Conversation affinity: the X-Copilot-Session header, or the 4D web Session.id,
// maps to one persistent Copilot session (see CopilotChatService).
// Work is delegated to the "CopilotChat" worker; the handler waits on a signal.

shared singleton Class constructor()
	
Function chatCompletions($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	var $body : Variant:=Try(JSON Parse:C1218($request.getText()))
	If (Value type:C1509($body)#Is object:K8:27)
		return This:C1470._error(400; "Request body must be a JSON object")
	End if 
	
	var $timeout : Real:=(Num:C11($body.timeout)>0) ? Num:C11($body.timeout)+10 : 190
	return This:C1470._dispatch({type: "chat"; sessionKey: This:C1470._sessionKey($request); body: $body}; $timeout)
	
Function models($request : 4D:C1709.IncomingMessage) : 4D:C1709.OutgoingMessage
	return This:C1470._dispatch({type: "models"}; 60)
	
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
	
	// Sends the task to the CopilotChat worker and waits for {status; contentType; body}
Function _dispatch($task : Object; $timeout : Real) : 4D:C1709.OutgoingMessage
	$task.signal:=New signal:C1641("copilot-chat")
	CALL WORKER:C1389("CopilotChat"; "_copilotChatWorker"; $task)
	
	If (Not:C34($task.signal.wait($timeout)))
		return This:C1470._error(504; "Timed out waiting for the Copilot worker")
	End if 
	
	var $result : Object:=JSON Parse:C1218(String:C10($task.signal.result); Is object:K8:27)
	
	var $response : 4D:C1709.OutgoingMessage:=4D:C1709.OutgoingMessage.new()
	$response.setStatus(Num:C11($result.status))
	$response.setBody(String:C10($result.body))
	$response.setHeader("Content-Type"; String:C10($result.contentType))
	return $response
	
Function _sessionKey($request : 4D:C1709.IncomingMessage) : Text
	var $key : Text:=String:C10($request.getHeader("x-copilot-session"))
	If (Length:C16($key)>0)
		return $key
	End if 
	If (Session:C1714#Null:C1517)
		return String:C10(Session:C1714.id)
	End if 
	return "default"
	
Function _error($status : Integer; $message : Text) : 4D:C1709.OutgoingMessage
	var $response : 4D:C1709.OutgoingMessage:=4D:C1709.OutgoingMessage.new()
	$response.setStatus($status)
	$response.setBody(JSON Stringify:C1217({error: {message: $message; type: ($status>=500) ? "server_error" : "invalid_request_error"}}))
	$response.setHeader("Content-Type"; "application/json")
	return $response
	