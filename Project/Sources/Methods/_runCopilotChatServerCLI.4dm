//%attributes = {"invisible":true}
// Headless runner: starts the OpenAI-compatible Copilot chat server and keeps running.
// Usage: tool4d --project=... --startup-method=_runCopilotChatServerCLI --dataless
var $url : Text:=_startCopilotChat({port: 8044})

Repeat
	DELAY PROCESS:C323(Current process:C322; 60)
Until (False:C215)
