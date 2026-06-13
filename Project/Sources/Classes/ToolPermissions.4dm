// Tool permission policy for Copilot sessions.
//
// Decides whether a Copilot tool/permission request is approved or rejected,
// the way Claude's settings.json or the Copilot CLI allow-lists work: a set of
// allow / deny / ask rules, each a "Target(pattern)" string, matched against the
// incoming permission request. Deny always wins; then approveAll; then allow;
// then read-only auto-approve; then ask; then the default decision.
//
// Targets map to Copilot permission kinds (see Session events PermissionRequest):
//   Shell|Bash  -> kind "shell"  matched on fullCommandText + command identifiers
//   Read|View   -> kind "read"   matched on path
//   Write|Edit  -> kind "write"  matched on fileName
//   Url|Fetch   -> kind "url"    matched on url
//   Mcp         -> kind "mcp"    matched on toolName / serverName / serverName/toolName
//   Tool        -> kind "custom-tool" matched on toolName
//   Memory      -> kind "memory" matched on fact
//   *|any|all   -> any kind
//   <name>      -> a literal MCP/custom tool name (matched on toolName/serverName)
//
// Pattern is glob (* and ?). Claude's ":*" suffix is accepted as "*".
// An empty pattern (target with no parentheses) matches every request of that kind.
//
// Usage:
//   var $perms : cs.ToolPermissions:=cs.ToolPermissions.new({\
//     allow: ["Read"; "Shell(git status)"; "Shell(npm run test:*)"]; \
//     deny: ["Shell(rm:*)"; "Shell(curl:*)"; "Read(**/.env)"]; \
//     defaultDecision: "reject"})
//   $perms.loadFile("/path/to/tool-permissions.json")  // optional, same shape
//   $config.onPermissionRequest:=$perms.handler()      // wire into a session
//   var $decision : Object:=$perms.decide($permissionRequest)  // {kind; feedback}

property allow : Collection
property deny : Collection
property ask : Collection
property approveAll : Boolean
property approveReadOnly : Boolean
property defaultDecision : Text
property approveDecision : Text
property askDecision : Text
property rejectFeedback : Text

Class constructor($options : Object)
	This:C1470.allow:=[]
	This:C1470.deny:=[]
	This:C1470.ask:=[]
	This:C1470.approveAll:=False:C215
	This:C1470.approveReadOnly:=False:C215
	This:C1470.defaultDecision:="reject"
	This:C1470.approveDecision:="approve-once"
	This:C1470.askDecision:="reject"  // no human is watching a headless server
	This:C1470.rejectFeedback:="Tool execution is not allowed by the server tool policy"
	If (Value type:C1509($options)=Is object:K8:27)
		This:C1470.configure($options)
	End if

	// Merge an options object. Accepts a Claude-style {permissions: {...}} wrapper or
	// the keys directly: allow, deny, ask (Text or Collection of "Target(pattern)"),
	// approveAll, approveReadOnly, defaultDecision, approveDecision, askDecision, rejectFeedback.
Function configure($options : Object) : cs:C1710.ToolPermissions
	If (Value type:C1509($options)#Is object:K8:27)
		return This:C1470
	End if
	var $cfg : Object:=(Value type:C1509($options.permissions)=Is object:K8:27) ? $options.permissions : $options

	If (OB Is defined:C1231($cfg; "approveAll"))
		This:C1470.approveAll:=Bool:C1537($cfg.approveAll)
	End if
	If (OB Is defined:C1231($cfg; "approveReadOnly"))
		This:C1470.approveReadOnly:=Bool:C1537($cfg.approveReadOnly)
	End if
	If (Length:C16(String:C10($cfg.defaultDecision))>0)
		This:C1470.defaultDecision:=String:C10($cfg.defaultDecision)
	End if
	If (Length:C16(String:C10($cfg.approveDecision))>0)
		This:C1470.approveDecision:=String:C10($cfg.approveDecision)
	End if
	If (Length:C16(String:C10($cfg.askDecision))>0)
		This:C1470.askDecision:=String:C10($cfg.askDecision)
	End if
	If (Length:C16(String:C10($cfg.rejectFeedback))>0)
		This:C1470.rejectFeedback:=String:C10($cfg.rejectFeedback)
	End if

	This:C1470.allowRules($cfg.allow)
	This:C1470.denyRules($cfg.deny)
	This:C1470.askRules($cfg.ask)
	return This:C1470

	// Load a JSON policy file (Text path, 4D.File, or 4D.Folder is not accepted).
	// The file has the same shape as configure()'s $options. Throws if missing/invalid.
Function loadFile($path : Variant) : cs:C1710.ToolPermissions
	var $file : 4D:C1709.File:=This:C1470._fileFrom($path)
	If (($file=Null:C1517) || (Not:C34($file.exists)))
		throw:C1805({componentSignature: "TPRM"; message: "Tool permissions file not found: "+String:C10($path)})
	End if
	var $parsed : Variant:=JSON Parse:C1218($file.getText())
	If (Value type:C1509($parsed)#Is object:K8:27)
		throw:C1805({componentSignature: "TPRM"; message: "Tool permissions file must contain a JSON object"})
	End if
	return This:C1470.configure($parsed)

Function allowRules($rules : Variant) : cs:C1710.ToolPermissions
	This:C1470._append(This:C1470.allow; $rules)
	return This:C1470

Function denyRules($rules : Variant) : cs:C1710.ToolPermissions
	This:C1470._append(This:C1470.deny; $rules)
	return This:C1470

Function askRules($rules : Variant) : cs:C1710.ToolPermissions
	This:C1470._append(This:C1470.ask; $rules)
	return This:C1470

	// Main entry point: returns a decision object for onPermissionRequest, one of
	// {kind: "approve-once"}, {kind: "approve-for-session"}, {kind: "reject"; feedback},
	// {kind: "user-not-available"} or {kind: "no-result"} (leave pending).
Function decide($request : Object) : Object
	If (Value type:C1509($request)#Is object:K8:27)
		return This:C1470._decision(This:C1470.defaultDecision; "")
	End if
	var $n : Object:=This:C1470._normalize($request)

	Case of
		: (This:C1470._listMatches(This:C1470.deny; $n))  // deny always wins
			return This:C1470._decision("reject"; $n.label)
		: (This:C1470.approveAll)
			return This:C1470._decision("approve-once"; $n.label)
		: (This:C1470._listMatches(This:C1470.allow; $n))
			return This:C1470._decision(This:C1470.approveDecision; $n.label)
		: (This:C1470.approveReadOnly && $n.readOnly)
			return This:C1470._decision("approve-once"; $n.label)
		: (This:C1470._listMatches(This:C1470.ask; $n))
			return This:C1470._decision(This:C1470.askDecision; $n.label)
		Else
			return This:C1470._decision(This:C1470.defaultDecision; $n.label)
	End case

	// A Formula bound to this instance, ready for session.onPermissionRequest.
	// It is called as ($permissionRequest; {sessionId}); only $1 is used.
Function handler() : 4D:C1709.Function
	var $self : cs:C1710.ToolPermissions:=This:C1470
	return Formula:C1597($self.decide($1))

	// Plain-object snapshot of the policy (for logging / serialization).
Function toObject() : Object
	return {\
		approveAll: This:C1470.approveAll; \
		approveReadOnly: This:C1470.approveReadOnly; \
		defaultDecision: This:C1470.defaultDecision; \
		approveDecision: This:C1470.approveDecision; \
		askDecision: This:C1470.askDecision; \
		allow: This:C1470._rawRules(This:C1470.allow); \
		deny: This:C1470._rawRules(This:C1470.deny); \
		ask: This:C1470._rawRules(This:C1470.ask)}

	// --- internals -------------------------------------------------------------

Function _decision($which : Text; $label : Text) : Object
	Case of
		: (($which="approve") || ($which="approve-once") || ($which="allow"))
			return {kind: "approve-once"}
		: (($which="approve-for-session") || ($which="session"))
			return {kind: "approve-for-session"}
		: (($which="pending") || ($which="no-result"))
			return {kind: "no-result"}
		: (($which="user-not-available") || ($which="unavailable"))
			return {kind: "user-not-available"}
		Else   // "reject" / "deny" / anything unrecognized
			return {kind: "reject"; feedback: This:C1470._feedbackFor($label)}
	End case

Function _feedbackFor($label : Text) : Text
	If (Length:C16($label)>0)
		return This:C1470.rejectFeedback+" ["+$label+"]"
	End if
	return This:C1470.rejectFeedback

	// Reduce a raw PermissionRequest to {kind; subjects; toolName; serverName; readOnly; label}
Function _normalize($req : Object) : Object
	var $kind : Text:=Lowercase:C14(String:C10($req.kind))
	var $n : Object:={kind: $kind; subjects: []; toolName: ""; serverName: ""; readOnly: False:C215; label: $kind}

	Case of
		: ($kind="shell")
			$n.subjects.push(String:C10($req.fullCommandText))
			var $allReadOnly : Boolean:=True:C214
			var $hasCommands : Boolean:=False:C215
			If (Value type:C1509($req.commands)=Is collection:K8:32)
				var $cmd : Object
				For each ($cmd; $req.commands)
					$hasCommands:=True:C214
					$n.subjects.push(String:C10($cmd.identifier))
					$allReadOnly:=$allReadOnly && Bool:C1537($cmd.readOnly)
				End for each
			End if
			$n.readOnly:=$hasCommands && $allReadOnly && Not:C34(Bool:C1537($req.hasWriteFileRedirection))
			$n.label:=String:C10($req.fullCommandText)
		: ($kind="write")
			$n.subjects.push(String:C10($req.fileName))
			$n.label:="write "+String:C10($req.fileName)
		: ($kind="read")
			$n.subjects.push(String:C10($req.path))
			$n.readOnly:=True:C214
			$n.label:="read "+String:C10($req.path)
		: ($kind="url")
			$n.subjects.push(String:C10($req.url))
			$n.label:="fetch "+String:C10($req.url)
		: ($kind="mcp")
			$n.toolName:=String:C10($req.toolName)
			$n.serverName:=String:C10($req.serverName)
			$n.subjects.push($n.toolName)
			$n.subjects.push($n.serverName)
			$n.subjects.push($n.serverName+"/"+$n.toolName)
			$n.readOnly:=Bool:C1537($req.readOnly)
			$n.label:="mcp "+$n.serverName+"/"+$n.toolName
		: ($kind="custom-tool")
			$n.toolName:=String:C10($req.toolName)
			$n.subjects.push($n.toolName)
			$n.label:="tool "+$n.toolName
		: ($kind="memory")
			$n.subjects.push(String:C10($req.fact))
			$n.label:="memory"
	End case
	return $n

Function _listMatches($list : Collection; $n : Object) : Boolean
	If (Value type:C1509($list)#Is collection:K8:32)
		return False:C215
	End if
	var $rule : Object
	For each ($rule; $list)
		If (This:C1470._ruleMatches($rule; $n))
			return True:C214
		End if
	End for each
	return False:C215

Function _ruleMatches($rule : Object; $n : Object) : Boolean
	var $kinds : Collection:=This:C1470._kindsForTarget($rule.target)
	If ($kinds.length>0)
		If (($kinds.indexOf("*")<0) && ($kinds.indexOf($n.kind)<0))
			return False:C215
		End if
	Else   // literal MCP/custom tool name target
		If (Not:C34(This:C1470._glob($rule.target; $n.toolName) || This:C1470._glob($rule.target; $n.serverName)))
			return False:C215
		End if
	End if

	If ($rule.pattern="")
		return True:C214
	End if
	return This:C1470._globAny($rule.pattern; $n.subjects)

Function _kindsForTarget($target : Text) : Collection
	var $t : Text:=Lowercase:C14(This:C1470._trim($target))
	Case of
		: (["*"; "any"; "all"].indexOf($t)>=0)
			return ["*"]
		: (["shell"; "bash"; "sh"; "command"; "exec"; "run"].indexOf($t)>=0)
			return ["shell"]
		: (["write"; "edit"; "create"].indexOf($t)>=0)
			return ["write"]
		: (["read"; "view"; "cat"].indexOf($t)>=0)
			return ["read"]
		: (["url"; "web"; "webfetch"; "fetch"].indexOf($t)>=0)
			return ["url"]
		: ($t="mcp")
			return ["mcp"]
		: ($t="memory")
			return ["memory"]
		: (["tool"; "customtool"; "custom-tool"; "function"].indexOf($t)>=0)
			return ["custom-tool"]
		: ($t="hook")
			return ["hook"]
		: (["extension"; "extensions"].indexOf($t)>=0)
			return ["extension-management"; "extension-permission-access"]
	End case
	return []  // not a known target: treat as a literal tool/server name

	// Parse "Target(pattern)" or "Target" into {target; pattern; raw}
Function _parseRule($text : Text) : Object
	var $t : Text:=This:C1470._trim($text)
	var $open : Integer:=Position:C15("("; $t)
	If (($open>0) && (Substring:C12($t; Length:C16($t); 1)=")"))
		var $target : Text:=This:C1470._trim(Substring:C12($t; 1; $open-1))
		var $pattern : Text:=Substring:C12($t; $open+1; Length:C16($t)-$open-1)
		$pattern:=Replace string:C233($pattern; ":*"; "*")  // Claude compatibility
		return {target: $target; pattern: This:C1470._trim($pattern); raw: $t}
	End if
	return {target: $t; pattern: ""; raw: $t}

Function _append($list : Collection; $rules : Variant)
	Case of
		: (Value type:C1509($rules)=Is text:K8:3)
			If (Length:C16($rules)>0)
				$list.push(This:C1470._parseRule($rules))
			End if
		: (Value type:C1509($rules)=Is collection:K8:32)
			var $r : Variant
			For each ($r; $rules)
				If (Value type:C1509($r)=Is text:K8:3) && (Length:C16($r)>0)
					$list.push(This:C1470._parseRule($r))
				End if
			End for each
	End case

Function _rawRules($list : Collection) : Collection
	var $out : Collection:=[]
	var $rule : Object
	For each ($rule; $list)
		$out.push(String:C10($rule.raw))
	End for each
	return $out

	// Glob (* ?) match, anchored, case-sensitive. Returns False on invalid pattern.
Function _glob($pattern : Text; $text : Text) : Boolean
	var $matched : Boolean:=False:C215
	Try
		$matched:=Match regex:C1019(This:C1470._globToRegex($pattern); $text)
	End try
	return $matched

Function _globAny($pattern : Text; $subjects : Collection) : Boolean
	var $subject : Text
	For each ($subject; $subjects)
		If (This:C1470._glob($pattern; $subject))
			return True:C214
		End if
	End for each
	return False:C215

Function _globToRegex($glob : Text) : Text
	var $special : Collection:=["\\"; "."; "+"; "("; ")"; "["; "]"; "{"; "}"; "^"; "$"; "|"]
	var $out : Text:=$glob
	var $ch : Text
	For each ($ch; $special)
		$out:=Replace string:C233($out; $ch; "\\"+$ch)
	End for each
	$out:=Replace string:C233($out; "*"; ".*")
	$out:=Replace string:C233($out; "?"; ".")
	return "^"+$out+"$"

Function _trim($s : Text) : Text
	var $t : Text:=String:C10($s)
	While ((Length:C16($t)>0) && ((Substring:C12($t; 1; 1)=" ") || (Substring:C12($t; 1; 1)=Char:C90(9))))
		$t:=Substring:C12($t; 2)
	End while
	While ((Length:C16($t)>0) && ((Substring:C12($t; Length:C16($t); 1)=" ") || (Substring:C12($t; Length:C16($t); 1)=Char:C90(9))))
		$t:=Substring:C12($t; 1; Length:C16($t)-1)
	End while
	return $t

Function _fileFrom($path : Variant) : 4D:C1709.File
	Case of
		: (Value type:C1509($path)=Is object:K8:27)
			return $path  // assume a 4D.File
		: (Value type:C1509($path)=Is text:K8:3)
			If (Length:C16($path)=0)
				return Null:C1517
			End if
			return File:C1566($path; fk posix path:K87:1)
	End case
	return Null:C1517
