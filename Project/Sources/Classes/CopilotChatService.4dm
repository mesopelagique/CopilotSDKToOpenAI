// OpenAI-compatible chat service backed by Copilot sessions.
// Lives as a process singleton inside the "CopilotChat" worker (see _copilotChatWorker):
// cs.Client owns a SystemWorker and formulas, so it cannot be shared with the
// web processes. HTTP handlers send tasks here via CALL WORKER and wait on a signal.

property options : Object
property client : cs:C1710.copilot.Client
property sessions : Object
property permissions : cs:C1710.ToolPermissions

singleton Class constructor()
	This:C1470.options:={}
	This:C1470.client:=Null:C1517
	This:C1470.sessions:={}
	This:C1470.permissions:=Null:C1517
	
	// $task: {type: "configure"|"models"|"chat"; signal: 4D.Signal; ...}
	// The response {status; contentType; body} is stored as JSON text in signal.result
Function handle($task : Object)
	var $response : Object
	Try
		Case of 
			: (String:C10($task.type)="configure")
				This:C1470.configure($task.options)
				$response:=This:C1470._json(200; {ok: True:C214})
			: (String:C10($task.type)="models")
				$response:=This:C1470._models()
			: (String:C10($task.type)="chat")
				$response:=This:C1470._chat($task)
			Else 
				$response:=This:C1470._json(404; {error: {message: "Unknown task type "+String:C10($task.type); type: "invalid_request_error"}})
		End case 
	Catch
		$response:=This:C1470._json(500; {error: {message: String:C10(Last errors:C1799[0].message); type: "server_error"}})
	End try
	
	If ($task.signal#Null:C1517)
		Use ($task.signal)
			$task.signal.result:=JSON Stringify:C1217($response)
		End use 
		$task.signal.trigger()
	End if 
	
	// Options: cliPath, workingDirectory (text), gitHubToken, model (default),
	// approveAll (Boolean, default False: tool permission requests are rejected),
	// permissions (Object: allow/deny/ask rule policy, see cs.ToolPermissions),
	// permissionsFile (Text: path to a JSON policy file with the same shape),
	// tools (Collection of fixed server-side tool declarations/handlers)
Function configure($options : Object)
	This:C1470._resetState()
	This:C1470.options:=$options || {}
	This:C1470.permissions:=This:C1470._buildPermissions()

	// Builds the tool permission policy from options.permissions / options.permissionsFile,
	// with options.approveAll as a blanket override kept for backward compatibility.
Function _buildPermissions() : cs:C1710.ToolPermissions
	var $permissions : cs:C1710.ToolPermissions:=cs:C1710.ToolPermissions.new(This:C1470.options.permissions)
	If (Bool:C1537(This:C1470.options.approveAll))
		$permissions.approveAll:=True:C214
	End if
	If (Length:C16(String:C10(This:C1470.options.permissionsFile))>0)
		$permissions.loadFile(String:C10(This:C1470.options.permissionsFile))
	End if
	return $permissions

Function _resetState()
	var $sessionKey : Text
	For each ($sessionKey; This:C1470.sessions)
		var $session : cs:C1710.copilot.Session:=This:C1470.sessions[$sessionKey]
		If ($session#Null:C1517)
			Try
				$session.disconnect()
			End try
		End if 
	End for each 
	
	If (This:C1470.client#Null:C1517)
		Try
			This:C1470.client.stop()
		End try
	End if 
	
	This:C1470.client:=Null:C1517
	This:C1470.sessions:={}
	
Function _ensureClient() : cs:C1710.copilot.Client
	If (This:C1470.client=Null:C1517)
		var $clientOptions : Object:={requestTimeout: 30; workingDirectory: Folder:C1567(Folder:C1567(fk database folder:K87:14; *).platformPath; fk platform path:K87:2)}
		var $key : Text
		For each ($key; ["cliPath"; "cliArgs"; "workingDirectory"; "baseDirectory"; "env"; "gitHubToken"; "useLoggedInUser"; "logLevel"])
			If (OB Is defined:C1231(This:C1470.options; $key))
				$clientOptions[$key]:=This:C1470.options[$key]
			End if 
		End for each 
		This:C1470.client:=cs:C1710.copilot.Client.new($clientOptions).start()
	End if 
	return This:C1470.client
	
Function _models() : Object
	var $models : Collection:=This:C1470._ensureClient().listModels()
	var $data : Collection:=[]
	var $model : Object
	For each ($model; $models)
		$data.push({\
			id: String:C10($model.id || $model.name); \
			object: "model"; \
			created: This:C1470._epoch(); \
			owned_by: "github-copilot"})
	End for each 
	return This:C1470._json(200; {object: "list"; data: $data})
	
Function _chat($task : Object) : Object
	var $body : Object:=$task.body || {}
	var $messages : Collection:=(Value type:C1509($body.messages)=Is collection:K8:32) ? $body.messages : []
	
	var $userMessages : Collection:=$messages.query("role = :1"; "user")
	If ($userMessages.length=0)
		return This:C1470._json(400; {error: {message: "No user message found in 'messages'"; type: "invalid_request_error"}})
	End if 
	var $prompt : Text:=This:C1470._contentText($userMessages[$userMessages.length-1].content)
	
	var $session : cs:C1710.copilot.Session:=This:C1470._sessionFor(String:C10($task.sessionKey); $body; $messages)
	
	var $timeout : Real:=(Num:C11($body.timeout)>0) ? Num:C11($body.timeout) : 180
	var $message : Object:=$session.sendAndWait($prompt; $timeout)
	var $content : Text:=($message#Null:C1517) ? String:C10($message.data.content) : ""
	
	var $id : Text:="chatcmpl-"+Generate UUID:C1066
	var $created : Integer:=This:C1470._epoch()
	var $model : Text:=(Length:C16(String:C10($body.model))>0) ? String:C10($body.model) : "github-copilot"
	
	If (Bool:C1537($body.stream))
		// Server-sent events; the whole stream is delivered in one response body
		var $chunk : Object:={id: $id; object: "chat.completion.chunk"; created: $created; model: $model; \
			choices: [{index: 0; delta: {role: "assistant"}; finish_reason: Null:C1517}]}
		var $sse : Text:="data: "+JSON Stringify:C1217($chunk)+"\n\n"
		$chunk.choices[0].delta:={content: $content}
		$sse+="data: "+JSON Stringify:C1217($chunk)+"\n\n"
		$chunk.choices[0].delta:={}
		$chunk.choices[0].finish_reason:="stop"
		$sse+="data: "+JSON Stringify:C1217($chunk)+"\n\n"
		$sse+="data: [DONE]\n\n"
		return {status: 200; contentType: "text/event-stream"; body: $sse}
	End if 
	
	return This:C1470._json(200; {\
		id: $id; \
		object: "chat.completion"; \
		created: $created; \
		model: $model; \
		choices: [{index: 0; message: {role: "assistant"; content: $content}; finish_reason: "stop"}]; \
		usage: {prompt_tokens: 0; completion_tokens: 0; total_tokens: 0}})
	
	// Reuses the Copilot session mapped to the HTTP session key, creating it on first use.
	// The Copilot session keeps the conversation state: only the latest user message is sent
Function _sessionFor($sessionKey : Text; $body : Object; $messages : Collection) : cs:C1710.copilot.Session
	If (Length:C16($sessionKey)=0)
		$sessionKey:="default"
	End if 
	
	var $session : cs:C1710.copilot.Session:=This:C1470.sessions[$sessionKey]
	If ($session#Null:C1517)
		return $session
	End if 
	
	var $config : Object:={}
	If ((Length:C16(String:C10($body.model))>0) && (String:C10($body.model)#"github-copilot"))
		$config.model:=String:C10($body.model)
	End if 
	
	var $systemMessages : Collection:=$messages.query("role = :1"; "system")
	If ($systemMessages.length>0)
		$config.systemMessage:={content: This:C1470._contentText($systemMessages[0].content)}
	End if 
	
	var $tools : Collection:=This:C1470._configuredTools()
	If ($tools.length>0)
		$config.tools:=$tools
	End if 
	
	var $self : cs:C1710.CopilotChatService:=This:C1470
	$config.onPermissionRequest:=Formula:C1597($self._decidePermission($1))
	
	$session:=This:C1470._ensureClient().createSession($config)
	This:C1470.sessions[$sessionKey]:=$session
	return $session
	
Function _configuredTools() : Collection
	var $configured : Collection:=(Value type:C1509(This:C1470.options.tools)=Is collection:K8:32) ? This:C1470.options.tools : []
	var $tools : Collection:=[]
	var $tool : Object
	For each ($tool; $configured)
		If (Value type:C1509($tool)=Is object:K8:27)
			var $name : Text:=String:C10($tool.name)
			If (Length:C16($name)>0)
				var $copy : Object:={name: $name}
				If (OB Is defined:C1231($tool; "description"))
					$copy.description:=$tool.description
				End if 
				If (OB Is defined:C1231($tool; "parameters"))
					$copy.parameters:=$tool.parameters
				End if 
				If ($tool.handler#Null:C1517)
					$copy.handler:=$tool.handler
				End if 
				If (OB Is defined:C1231($tool; "skipPermission"))
					$copy.skipPermission:=Bool:C1537($tool.skipPermission)
				End if 
				If (OB Is defined:C1231($tool; "overridesBuiltInTool"))
					$copy.overridesBuiltInTool:=Bool:C1537($tool.overridesBuiltInTool)
				End if 
				$tools.push($copy)
			End if 
		End if 
	End for each 
	return $tools
	
Function _decidePermission($permissionRequest : Object) : Object
	If (This:C1470.permissions#Null:C1517)
		return This:C1470.permissions.decide($permissionRequest)
	End if
	// configure() was never called: keep the safe default (reject everything)
	If (Bool:C1537(This:C1470.options.approveAll))
		return {kind: "approve-once"}
	End if
	return {kind: "reject"; feedback: "Tool execution is not allowed from the chat web server"}
	
	// OpenAI message content is either a text or a collection of parts ({type: "text"; text: ...})
Function _contentText($content : Variant) : Text
	If (Value type:C1509($content)=Is text:K8:3)
		return $content
	End if 
	If (Value type:C1509($content)=Is collection:K8:32)
		var $texts : Collection:=[]
		var $part : Object
		For each ($part; $content)
			If (String:C10($part.type)="text")
				$texts.push(String:C10($part.text))
			End if 
		End for each 
		return $texts.join("\n")
	End if 
	return ""
	
Function _json($status : Integer; $payload : Object) : Object
	return {status: $status; contentType: "application/json"; body: JSON Stringify:C1217($payload)}
	
Function _epoch() : Integer
	return ((Current date:C33-!1970-01-01!)*86400)+(Current time:C178+0)
	