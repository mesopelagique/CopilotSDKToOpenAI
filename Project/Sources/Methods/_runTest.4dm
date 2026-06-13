//%attributes = {"invisible":true}
// Temporary CLI runner for the copilot SDK integration test
ON ERR CALL:C155("_onTestErrors"; ek global:K92:2)
_onTestErrors(True:C214)

Try
	test_chat_service
	test_aikit
End try

var $errors : Collection:=Last errors:C1799 || ((Storage:C1525.errors.last#Null:C1517) ? Storage:C1525.errors.last.copy() : Null:C1517)

If ($errors=Null:C1517)
	LOG EVENT:C667(Into system standard outputs:K38:9; "PASS test_copilot_sdk"+Char:C90(Line feed:K15:40))
Else 
	LOG EVENT:C667(Into system standard outputs:K38:9; "FAIL test_copilot_sdk "+JSON Stringify:C1217($errors)+Char:C90(Line feed:K15:40))
End if 

QUIT 4D:C291
