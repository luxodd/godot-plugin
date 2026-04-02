class_name LuxoddWebSocket
extends Node

## WebSocket transport layer with reconnection and command queuing.
## Wraps Godot's WebSocketPeer and handles the connection lifecycle.

signal ws_connected()
signal ws_disconnected(code: int)
signal ws_message_received(message: String)
signal ws_error(error: String)
signal reconnect_attempt(attempt: int, max_attempts: int)
signal reconnect_failed()

var _peer: WebSocketPeer = WebSocketPeer.new()
var _url: String = ""
var _is_connected: bool = false
var _was_connected: bool = false
var _pending_queue: Array[String] = []

# Reconnection state
var _reconnect_attempts: int = 0
var _max_reconnect_attempts: int = 3
var _reconnect_delay: float = 0.5
var _is_reconnecting: bool = false


func configure(max_attempts: int, delay: float) -> void:
	_max_reconnect_attempts = max_attempts
	_reconnect_delay = delay


func connect_to(url: String) -> void:
	_url = url
	_reconnect_attempts = 0
	_is_reconnecting = false
	var err := _peer.connect_to_url(url)
	if err != OK:
		ws_error.emit("Failed to initiate WebSocket connection: %d" % err)


func disconnect_ws() -> void:
	_was_connected = false
	_is_reconnecting = false
	if _is_connected:
		_peer.close(1000, "Client disconnect")
	_is_connected = false


func send_text(message: String) -> void:
	if _is_connected:
		_peer.send_text(message)
	else:
		_pending_queue.append(message)


func is_socket_connected() -> bool:
	return _is_connected


func poll() -> void:
	_peer.poll()

	var state := _peer.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_is_connected = true
				_was_connected = true
				_reconnect_attempts = 0
				_is_reconnecting = false
				ws_connected.emit()
				_flush_queue()

			while _peer.get_available_packet_count() > 0:
				var packet := _peer.get_packet()
				var text := packet.get_string_from_utf8()
				ws_message_received.emit(text)

		WebSocketPeer.STATE_CLOSED:
			var code := _peer.get_close_code()
			if _is_connected:
				_is_connected = false
				ws_disconnected.emit(code)

			if _was_connected and not _is_reconnecting:
				_try_reconnect()

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CONNECTING:
			pass


func _flush_queue() -> void:
	var queue := _pending_queue.duplicate()
	_pending_queue.clear()
	for msg in queue:
		_peer.send_text(msg)


func _try_reconnect() -> void:
	if _reconnect_attempts >= _max_reconnect_attempts:
		_was_connected = false
		reconnect_failed.emit()
		return

	_is_reconnecting = true
	_reconnect_attempts += 1
	reconnect_attempt.emit(_reconnect_attempts, _max_reconnect_attempts)

	await get_tree().create_timer(_reconnect_delay).timeout

	# Create a fresh peer for the new connection attempt
	_peer = WebSocketPeer.new()
	var err := _peer.connect_to_url(_url)
	if err != OK:
		_is_reconnecting = false
		_try_reconnect()
