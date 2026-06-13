//%attributes = {}
// Starts the OpenAI-compatible Copilot chat server.
// $settings: {port: Integer (default 8044); cliPath; workingDirectory; gitHubToken;
//             model; approveAll: Boolean (allow tool execution, default False);
//             tools: Collection of fixed server-side tool declarations/handlers}
// Returns the server base URL.
#DECLARE($settings : Object) : Text
$settings:=$settings || {}

If (Not:C34(OB Is defined:C1231($settings; "cliPath")))
	$settings.cliPath:=(Is macOS:C1572) ? "/opt/homebrew/bin/copilot" : "copilot"
End if

CALL WORKER:C1389("CopilotChat"; "_copilotChatWorker"; {type: "configure"; options: $settings})

var $webServer : 4D:C1709.WebServer:=WEB Server:C1674
If (Not:C34($webServer.isRunning))
	var $port : Integer:=(Num:C11($settings.port)>0) ? Num:C11($settings.port) : 8044
	$webServer.start({HTTPPort: $port})
End if

var $url : Text:="http://127.0.0.1:"+String:C10($webServer.HTTPPort)
LOG EVENT:C667(Into system standard outputs:K38:9; "Copilot chat server: "+$url+"/chat"+Char:C90(Line feed:K15:40))
return $url
