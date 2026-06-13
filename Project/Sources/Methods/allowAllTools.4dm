//%attributes = {}
var $isRunning:=WEB Is server running:C1313
If ($isRunning)
	WEB STOP SERVER:C618
	defer:C1860(WEB START SERVER:C617)
End if 


cs:C1710.CopilotChatService.me.options.approveAll:=True:C214
cs:C1710.CopilotChatService.me.client:=Null:C1517  // a new client will be created with options
