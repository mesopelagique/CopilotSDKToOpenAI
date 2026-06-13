//%attributes = {"invisible":true}
// Entry point of the "CopilotChat" worker: routes tasks from the HTTP handlers
// to the per-process CopilotChatService singleton (which owns the Client)
#DECLARE($task : Object)
cs:C1710.CopilotChatService.me.handle($task)
