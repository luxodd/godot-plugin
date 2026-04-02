class_name LuxoddProtocol
extends Node

## Handles JSON command serialization and response deserialization/routing.
## Replaces the 16 individual command handler classes from the Unity plugin
## with a single generic send/receive mechanism.

signal response_received(command_type: String, status_code: int, payload: Variant)

var _websocket: LuxoddWebSocket


func setup(websocket: LuxoddWebSocket) -> void:
	_websocket = websocket
	_websocket.ws_message_received.connect(_on_message)


func send_command(type: String, payload: Dictionary = {}, version: String = "1.0") -> void:
	var request := {
		"type": type,
		"version": version,
	}
	if payload.is_empty():
		request["payload"] = {}
	else:
		request["payload"] = payload

	var json_string := JSON.stringify(request)
	_websocket.send_text(json_string)


func _on_message(raw_json: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed == null or not parsed is Dictionary:
		push_warning("[LuxoddProtocol] Failed to parse server message: %s" % raw_json)
		return

	var response: Dictionary = parsed
	var response_type: String = response.get("type", "")
	var status_code: int = response.get("status", 0)
	var payload: Variant = response.get("payload", {})

	# Map the response type back to the originating request type
	var request_type: String = _resolve_request_type(response_type)
	if request_type.is_empty():
		push_warning("[LuxoddProtocol] Unknown response type: %s" % response_type)
		return

	response_received.emit(request_type, status_code, payload)


func _resolve_request_type(response_type: String) -> String:
	# Direct lookup first
	if LuxoddCommandTypes.RESPONSE_TO_REQUEST.has(response_type):
		return LuxoddCommandTypes.RESPONSE_TO_REQUEST[response_type]

	# Try converting snake_case response to PascalCase for lookup
	var pascal := _to_pascal_case(response_type)
	if LuxoddCommandTypes.RESPONSE_TO_REQUEST.has(pascal):
		return LuxoddCommandTypes.RESPONSE_TO_REQUEST[pascal]

	return ""


static func _to_pascal_case(snake: String) -> String:
	var parts := snake.split("_")
	var result := ""
	for part in parts:
		if part.length() > 0:
			result += part[0].to_upper() + part.substr(1)
	return result
