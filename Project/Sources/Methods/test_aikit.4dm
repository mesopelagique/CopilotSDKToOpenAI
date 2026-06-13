//%attributes = {}

var $providers:=cs:C1710.AIKit.OpenAIProviders.new()

var $client:=cs:C1710.AIKit.OpenAI.new($providers.get("CopilotSDK"))

var $models:=$client.models.list().models
ASSERT:C1129($models.length>0; "no model?")
