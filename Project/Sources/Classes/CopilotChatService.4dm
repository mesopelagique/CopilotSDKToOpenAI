// OpenAI-compatible chat service backed by Copilot sessions.
// Lives as a process singleton inside the "CopilotChat" worker (see _copilotChatWorker):
// cs.Client owns a SystemWorker and formulas, so it cannot be shared with the
// web processes. HTTP handlers send tasks here via CALL WORKER and wait on a signal.

property options : Object
property client : cs:C1710.copilot.Client
property sessions : Object
property permissions : cs:C1710.ToolPermissions
property store : Object  // {conversations: [{id; title; model; createdAt; updatedAt; messages: [{role; content; ts}]}]}, lazily loaded from disk

singleton Class constructor()
	This:C1470.options:={}
	This:C1470.client:=Null:C1517
	This:C1470.sessions:={}
	This:C1470.permissions:=Null:C1517
	This:C1470.store:=Null:C1517
	
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
			: (String:C10($task.type)="sessions")
				$response:=This:C1470._sessions()
			: (String:C10($task.type)="messages")
				$response:=This:C1470._messages($task)
			: (String:C10($task.type)="deleteSession")
				$response:=This:C1470._deleteSession($task)
			: (String:C10($task.type)="renameSession")
				$response:=This:C1470._renameSession($task)
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
	
	var $session : cs:C1710.copilot.Session:=This:C1470._resolveSession(String:C10($task.sessionKey); $body; $messages)
	var $conversationId : Text:=$session.sessionId
	
	var $timeout : Real:=(Num:C11($body.timeout)>0) ? Num:C11($body.timeout) : 180
	var $message : Object:=$session.sendAndWait($prompt; $timeout)
	var $content : Text:=($message#Null:C1517) ? String:C10($message.data.content) : ""
	
	// Keep our own display transcript in the JSON store (the runtime session keeps the model context)
	This:C1470._recordTurn($conversationId; $prompt; $content; $body)
	
	var $id : Text:="chatcmpl-"+Generate UUID:C1066
	var $created : Integer:=This:C1470._epoch()
	var $model : Text:=(Length:C16(String:C10($body.model))>0) ? String:C10($body.model) : "github-copilot"
	
	var $response : Object
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
		$response:={status: 200; contentType: "text/event-stream"; body: $sse}
	Else 
		$response:=This:C1470._json(200; {\
			id: $id; \
			object: "chat.completion"; \
			created: $created; \
			model: $model; \
			choices: [{index: 0; message: {role: "assistant"; content: $content}; finish_reason: "stop"}]; \
			usage: {prompt_tokens: 0; completion_tokens: 0; total_tokens: 0}})
	End if 
	
	// The HTTP handler echoes this back as the X-Copilot-Session-Id response header
	$response.sessionId:=$conversationId
	return $response
	
	// Resolves the Copilot session for a request key, reusing a live one, resuming a persisted
	// conversation from disk, or creating a fresh one. The runtime sessionId (session.sessionId)
	// is the durable conversation id used by the store and handed back to the client.
	// $sessionKey is "" / "new" for a brand-new conversation, or a known runtime id to continue.
Function _resolveSession($sessionKey : Text; $body : Object; $messages : Collection) : cs:C1710.copilot.Session
	If ($sessionKey="new")
		$sessionKey:=""
	End if 
	
	If (Length:C16($sessionKey)>0)
		var $live : cs:C1710.copilot.Session:=This:C1470.sessions[$sessionKey]
		If ($live#Null:C1517)
			return $live
		End if 
	End if 
	
	var $config : Object:=This:C1470._buildSessionConfig($body; $messages)
	
	// A key we have on record is a persisted runtime session: bring it back with its context
	If ((Length:C16($sessionKey)>0) && (This:C1470._storeEntry($sessionKey)#Null:C1517))
		Try
			var $resumed : cs:C1710.copilot.Session:=This:C1470._ensureClient().resumeSession($sessionKey; $config)
			This:C1470.sessions[$sessionKey]:=$resumed
			This:C1470.sessions[$resumed.sessionId]:=$resumed
			return $resumed
		End try
		// resume failed (deleted on disk): fall through and start a new conversation
	End if 
	
	var $session : cs:C1710.copilot.Session:=This:C1470._ensureClient().createSession($config)
	If (Length:C16($sessionKey)>0)
		This:C1470.sessions[$sessionKey]:=$session
	End if 
	This:C1470.sessions[$session.sessionId]:=$session
	return $session
	
	// Builds the session config (model, system message, server-side tools, permission callback)
	// shared by createSession and resumeSession
Function _buildSessionConfig($body : Object; $messages : Collection) : Object
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
	return $config
	
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
	
	// === Conversation store & list endpoints =========================================
	// Conversations are persisted as JSON in the data folder. The store holds the display
	// transcript (the runtime keeps the real model context, reloaded via resumeSession).
	
	// GET /sessions: the conversation list for the sidebar, most recently updated first
Function _sessions() : Object
	var $store : Object:=This:C1470._loadStore()
	var $data : Collection:=[]
	var $conversation : Object
	For each ($conversation; $store.conversations)
		$data.push({\
			id: String:C10($conversation.id); \
			title: String:C10($conversation.title); \
			model: String:C10($conversation.model); \
			created: Num:C11($conversation.createdAt); \
			updated: Num:C11($conversation.updatedAt); \
			messageCount: (Value type:C1509($conversation.messages)=Is collection:K8:32) ? $conversation.messages.length : 0})
	End for each 
	// The store keeps conversations most-recently-updated first (see _recordTurn), no extra sort needed
	return This:C1470._json(200; {object: "list"; data: $data})
	
	// GET /sessions/{id}/messages: the stored transcript of one conversation
Function _messages($task : Object) : Object
	var $conversation : Object:=This:C1470._storeEntry(String:C10($task.sessionKey))
	If ($conversation=Null:C1517)
		return This:C1470._json(404; {error: {message: "Conversation not found"; type: "invalid_request_error"}})
	End if 
	var $messages : Collection:=(Value type:C1509($conversation.messages)=Is collection:K8:32) ? $conversation.messages : []
	return This:C1470._json(200; {\
		id: String:C10($conversation.id); \
		title: String:C10($conversation.title); \
		model: String:C10($conversation.model); \
		messages: $messages})
	
	// DELETE /sessions/{id}: drop the conversation from the store, memory and Copilot disk
Function _deleteSession($task : Object) : Object
	var $id : Text:=String:C10($task.sessionKey)
	var $store : Object:=This:C1470._loadStore()
	var $index : Integer
	var $removed : Boolean:=False:C215
	For ($index; $store.conversations.length-1; 0; -1)
		If (String:C10($store.conversations[$index].id)=$id)
			$store.conversations.remove($index)
			$removed:=True:C214
		End if 
	End for 
	If ($removed)
		This:C1470._saveStore()
	End if 
	
	var $session : cs:C1710.copilot.Session:=This:C1470.sessions[$id]
	If ($session#Null:C1517)
		Try
			$session.disconnect()
		End try
		OB REMOVE:C1226(This:C1470.sessions; $id)
	End if 
	
	If (This:C1470.client#Null:C1517)
		Try
			This:C1470.client.deleteSession($id)
		End try
	End if 
	return This:C1470._json(200; {ok: True:C214})
	
	// PATCH /sessions/{id} {title}: rename a conversation
Function _renameSession($task : Object) : Object
	var $conversation : Object:=This:C1470._storeEntry(String:C10($task.sessionKey))
	If ($conversation=Null:C1517)
		return This:C1470._json(404; {error: {message: "Conversation not found"; type: "invalid_request_error"}})
	End if 
	$conversation.title:=String:C10($task.title)
	This:C1470._saveStore()
	return This:C1470._json(200; {ok: True:C214; id: $conversation.id; title: $conversation.title})
	
	// Appends one user+assistant exchange to the conversation (creating it on first use) and
	// moves it to the front, so the store stays ordered most-recently-updated first. Array
	// position is the ordering key: it is deterministic even for turns within the same second
	// and is preserved on disk across restarts.
Function _recordTurn($id : Text; $userText : Text; $assistantText : Text; $body : Object)
	If (Length:C16($id)=0)
		return 
	End if 
	var $store : Object:=This:C1470._loadStore()
	var $now : Integer:=This:C1470._epoch()
	var $conversation : Object:=This:C1470._storeEntry($id)
	If ($conversation=Null:C1517)
		$conversation:={id: $id; title: ""; model: ""; createdAt: $now; updatedAt: $now; messages: []}
	End if 
	If (Length:C16(String:C10($conversation.title))=0)
		$conversation.title:=This:C1470._titleFromText($userText)
	End if 
	If (Length:C16(String:C10($body.model))>0)
		$conversation.model:=String:C10($body.model)
	End if 
	$conversation.messages.push({role: "user"; content: $userText; ts: $now})
	$conversation.messages.push({role: "assistant"; content: $assistantText; ts: This:C1470._epoch()})
	$conversation.updatedAt:=This:C1470._epoch()
	
	// Re-insert at the front (drop any previous position first)
	var $index : Integer
	For ($index; $store.conversations.length-1; 0; -1)
		If (String:C10($store.conversations[$index].id)=$id)
			$store.conversations.remove($index)
		End if 
	End for 
	$store.conversations.unshift($conversation)
	This:C1470._saveStore()
	
	// Returns the conversation object for a runtime session id, or Null
Function _storeEntry($id : Text) : Object
	If (Length:C16($id)=0)
		return Null:C1517
	End if 
	var $store : Object:=This:C1470._loadStore()
	var $matches : Collection:=$store.conversations.query("id = :1"; $id)
	return ($matches.length>0) ? $matches[0] : Null:C1517
	
	// Lazily loads the conversation store from disk (defaulting to an empty store)
Function _loadStore() : Object
	If (This:C1470.store#Null:C1517)
		return This:C1470.store
	End if 
	var $file : 4D:C1709.File:=This:C1470._storeFile()
	var $store : Object:=Null:C1517
	If (($file#Null:C1517) && ($file.exists))
		$store:=Try(JSON Parse:C1218($file.getText()))
	End if 
	If ((Value type:C1509($store)#Is object:K8:27) || (Value type:C1509($store.conversations)#Is collection:K8:32))
		$store:={conversations: []}
	End if 
	This:C1470.store:=$store
	return This:C1470.store
	
	// Persists the in-memory store to disk. Persistence must never break a chat turn, so a
	// missing data folder (e.g. a dataless runtime) is a silent no-op and disk errors are swallowed.
Function _saveStore()
	If (This:C1470.store=Null:C1517)
		return 
	End if 
	var $file : 4D:C1709.File:=This:C1470._storeFile()
	If ($file=Null:C1517)
		return 
	End if 
	Try
		If (Not:C34($file.parent.exists))
			$file.parent.create()
		End if 
		$file.setText(JSON Stringify:C1217(This:C1470.store))
	Catch
	End try
	
	// The store lives in the data folder (gitignored). Returns Null when no data folder is
	// available (e.g. a dataless runtime), which makes persistence a silent no-op.
Function _storeFile() : 4D:C1709.File
	var $folder : 4D:C1709.Folder:=Try(Folder:C1567(fk data folder:K87:12; *))
	return ($folder#Null:C1517) ? $folder.file("copilot-conversations.json") : Null:C1517
	
	// First line of the prompt, trimmed to a sidebar-friendly length
Function _titleFromText($text : Text) : Text
	var $title : Text:=Replace string:C233(Replace string:C233(String:C10($text); Char:C90(Carriage return:K15:38); " "); Char:C90(Line feed:K15:40); " ")
	While (Position:C15("  "; $title)>0)
		$title:=Replace string:C233($title; "  "; " ")
	End while 
	$title:=This:C1470._trim($title)
	If (Length:C16($title)>60)
		$title:=Substring:C12($title; 1; 60)+"…"
	End if 
	return (Length:C16($title)>0) ? $title : "New conversation"
	
Function _trim($text : Text) : Text
	var $result : Text:=String:C10($text)
	While ((Length:C16($result)>0) && (Substring:C12($result; 1; 1)=" "))
		$result:=Substring:C12($result; 2)
	End while 
	While ((Length:C16($result)>0) && (Substring:C12($result; Length:C16($result); 1)=" "))
		$result:=Substring:C12($result; 1; Length:C16($result)-1)
	End while 
	return $result
	
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
	