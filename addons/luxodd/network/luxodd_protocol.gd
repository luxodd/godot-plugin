class_name LuxoddProtocol
extends Node

## Handles JSON command serialization and response deserialization/routing.
## Replaces the individual command handler classes from the Unity plugin
## with a single generic send/receive mechanism.

## `envelope` is the whole parsed response, for commands whose result sits beside the payload
## (merchant prize info's is_active, tournament info's request_id and msgver).
signal response_received(command_type: String, status_code: int, payload: Variant, envelope: Dictionary)

var _websocket: LuxoddWebSocket


func setup(websocket: LuxoddWebSocket) -> void:
	_websocket = websocket
	_websocket.ws_message_received.connect(_on_message)


## The 1.0.0 envelope: {"type", "version", "payload"}. Kept byte-for-byte for every command
## that existed in 1.0.0, so servers see what they always saw.
func send_command(type: String, payload: Dictionary = {}, version: String = "1.0") -> void:
	var request := {
		"type": type,
		"version": version,
	}
	request["payload"] = payload
	_send(request)


## The envelope used by commands added in 1.1.0, matching the Unity plugin's CommandRequestJson:
## "msgver" and "version" are left out when empty, and the payload may be null.
func send_request(type: String, payload: Variant, version: String = "", msgver: String = "") -> void:
	var request := {"type": type}
	if not msgver.is_empty():
		request["msgver"] = msgver
	if not version.is_empty():
		request["version"] = version
	request["payload"] = payload
	_send(request)


func _send(request: Dictionary) -> void:
	var json_string := JSON.stringify(request)
	LuxoddLog.info("send %s, %d chars" % [request.get("type", "?"), json_string.length()])
	_websocket.send_text(json_string)


func _on_message(raw_json: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed == null or not parsed is Dictionary:
		# Never the body: it can carry the player's email, name and saved data.
		LuxoddLog.warn("Ignoring a server message that is not a JSON object (%d chars)." % raw_json.length())
		return

	var response: Dictionary = parsed
	var response_type: String = str(response.get("type", ""))
	var status_code: int = int(response.get("status", 0))
	var payload: Variant = response.get("payload", {})

	# Map the response type back to the originating request type
	var request_type: String = _resolve_request_type(response_type)
	if request_type.is_empty():
		LuxoddLog.warn("Unknown response type: %s" % response_type)
		return

	LuxoddLog.info("recv %s, status %d, %d chars" % [response_type, status_code, raw_json.length()])
	response_received.emit(request_type, status_code, payload, response)


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
