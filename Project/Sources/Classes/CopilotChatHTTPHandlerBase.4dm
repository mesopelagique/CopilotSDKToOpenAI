// Shared plumbing for the Copilot HTTP handlers. Forwards a task to the "CopilotChat" worker,
// waits on a signal, and builds the OutgoingMessage. Subclassed by:
//   - CopilotChatHTTPHandler  (OpenAI-compatible API)
//   - CopilotChatWebHandler   (chat web interface)
// Not registered in HTTPHandlers.json itself; it only carries the common helpers.
// Declared "shared" so the shared-singleton subclasses are allowed to extend it.
shared Class constructor()

	// Sends the task to the CopilotChat worker and waits for {status; contentType; body}.
	// A "sessionId" field on the result is echoed back as the X-Copilot-Session-Id header.
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
	If (Length:C16(String:C10($result.sessionId))>0)
		// Lets the chat page learn the durable conversation id created/resumed for this request
		$response.setHeader("X-Copilot-Session-Id"; String:C10($result.sessionId))
	End if
	return $response

Function _error($status : Integer; $message : Text) : 4D:C1709.OutgoingMessage
	var $response : 4D:C1709.OutgoingMessage:=4D:C1709.OutgoingMessage.new()
	$response.setStatus($status)
	$response.setBody(JSON Stringify:C1217({error: {message: $message; type: ($status>=500) ? "server_error" : "invalid_request_error"}}))
	$response.setHeader("Content-Type"; "application/json")
	return $response
