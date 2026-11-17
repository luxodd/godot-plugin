class_name LuxoddBridge
extends Node

## Handles postMessage communication between the game (running in an iframe)
## and the Luxodd host page. Only active on HTML5 builds — all methods are
## no-ops on desktop/editor to allow seamless local testing.
##
## Host messages posted here match the Unity plugin's .jslib files exactly:
## gameReady, session_options, restart_ready, session_end, prize_won.

signal jwt_received(token: String)
signal action_received(action: String)
## The host's 'luxodd:session' event: {token, wsUrl, runtime?}. Values are validated strings;
## runtime is {} when the host named no platform.
signal session_received(token: String, ws_url: String, runtime: Dictionary)
## The host asks the game to get ready for a Fast Restart (restartPreparationVersion 1).
signal restart_prepare_received(request_id: String)

var _jwt_callback: JavaScriptObject
var _action_callback: JavaScriptObject
var _session_callback: JavaScriptObject
var _restart_prepare_callback: JavaScriptObject
var _is_web: bool = false


func initialize() -> void:
	_is_web = OS.has_feature("web")
	if not _is_web:
		return

	# Create GDScript callbacks that JavaScript can invoke
	_jwt_callback = JavaScriptBridge.create_callback(_on_jwt_from_host)
	_action_callback = JavaScriptBridge.create_callback(_on_action_from_host)
	_session_callback = JavaScriptBridge.create_callback(_on_session_from_host)
	_restart_prepare_callback = JavaScriptBridge.create_callback(_on_restart_prepare_from_host)

	# Expose callbacks on the window object so our injected JS can reach them
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.set("_luxodd_jwt_cb", _jwt_callback)
	window.set("_luxodd_action_cb", _action_callback)
	window.set("_luxodd_session_cb", _session_callback)
	window.set("_luxodd_restart_prepare_cb", _restart_prepare_callback)

	# Inject a message listener that routes host messages to our callbacks.
	# Values cross into GDScript as strings only (the session event as JSON).
	JavaScriptBridge.eval("""
		(function() {
			if (window._luxodd_listener_added) return;
			window._luxodd_listener_added = true;
			window.addEventListener('message', function(e) {
				var d = e.data;
				if (!d || typeof d !== 'object') return;
				if (d.type === 'restart_prepare') {
					if (typeof d.requestId === 'string' && d.requestId.trim().length > 0 &&
						window._luxodd_restart_prepare_cb) {
						window._luxodd_restart_prepare_cb(d.requestId);
					}
					return;
				}
				if (typeof d.jwt === 'string' && window._luxodd_jwt_cb) {
					window._luxodd_jwt_cb(d.jwt);
				}
				if (typeof d.action === 'string' && window._luxodd_action_cb) {
					window._luxodd_action_cb(d.action);
				}
			});
			// The arcade page hands the current session to same-origin games with this event,
			// on boot and on a Fast Restart (ext-game-server-frontend gameSessionHandshake.ts).
			window.addEventListener('luxodd:session', function(e) {
				var d = e && e.detail;
				if (!d || typeof d !== 'object' || !window._luxodd_session_cb) return;
				var runtime = (d.runtime && typeof d.runtime === 'object' && !Array.isArray(d.runtime))
					? d.runtime : null;
				window._luxodd_session_cb(JSON.stringify({
					token: typeof d.token === 'string' ? d.token : '',
					wsUrl: typeof d.wsUrl === 'string' ? d.wsUrl : '',
					runtime: runtime ? {
						platform: typeof runtime.platform === 'string' ? runtime.platform.slice(0, 64) : '',
						arcadeLayout: typeof runtime.arcadeLayout === 'string' ? runtime.arcadeLayout.slice(0, 64) : ''
					} : null
				}));
			});
		})();
	""", true)


func get_token_from_url() -> String:
	if not _is_web:
		return ""
	var result: Variant = JavaScriptBridge.eval("""
		(function() {
			var params = new URLSearchParams(window.location.search);
			return params.get('token') || '';
		})();
	""", true)
	return str(result) if result != null else ""


## The WebSocket endpoint from the page URL, without the token:
## the `ws` parameter if present (a full ws:// or wss:// URL, as the Unity plugin reads it),
## else <scheme>://<wsHost>/ws, where the scheme follows the page (wss on https, ws on http).
## Returns "" when neither is usable. 1.0.0 always used wss, so a page served over http
## (a local sbx mission) could not connect.
func get_ws_endpoint_from_url() -> String:
	if not _is_web:
		return ""
	var result: Variant = JavaScriptBridge.eval("""
		(function() {
			var params = new URLSearchParams(window.location.search);
			var ws = params.get('ws') || '';
			if (/^wss?:\\/\\/[^\\s?#]+$/.test(ws)) return ws.replace(/\\/+$/, '');
			var wsHost = params.get('wsHost') || '';
			if (!wsHost || /[\\/?#\\s]/.test(wsHost)) return '';
			var scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
			return scheme + '://' + wsHost + '/ws';
		})();
	""", true)
	return str(result) if result != null else ""


## Kept for games that called it on 1.0.0. Returns the server without the /ws path,
## with the scheme following the page.
func get_ws_host_from_url() -> String:
	var endpoint := get_ws_endpoint_from_url()
	return endpoint.trim_suffix("/ws")


func post_game_ready() -> void:
	_post({"type": "gameReady"})


func post_session_end() -> void:
	_post({"type": "session_end"})


func post_session_option(action: String) -> void:
	if action.is_empty():
		return
	_post({"type": "session_options", "action": action})


## Fast Restart (Unity 1.2.0 wire format): the host keeps the game loaded on Restart and hands it
## the replacement session. include_continue shows Continue as well; prepared adds
## restartPreparationVersion 1, so the host sends restart_prepare before charging.
func post_fast_restart_session_option(include_continue: bool, prepared: bool) -> void:
	var message := {
		"type": "session_options",
		"action": "both" if include_continue else "restart",
		"keepGameLoaded": true,
	}
	if prepared:
		message["restartPreparationVersion"] = 1
	_post(message)


func post_restart_ready(request_id: String) -> void:
	if request_id.strip_edges().is_empty():
		return
	_post({"type": "restart_ready", "requestId": request_id})


func post_prize_won(tickets: Array) -> void:
	if tickets.is_empty():
		return
	_post({"type": "prize_won", "tickets": tickets})


func _post(message: Dictionary) -> void:
	if not _is_web:
		return
	# JSON is a valid JS object literal, so no value is ever spliced into code as raw text.
	JavaScriptBridge.eval("window.parent.postMessage(%s, '*');" % JSON.stringify(message), true)


func _on_jwt_from_host(args: Array) -> void:
	if args.size() > 0 and args[0] is String:
		jwt_received.emit(args[0])


func _on_action_from_host(args: Array) -> void:
	if args.size() > 0 and args[0] is String:
		action_received.emit(args[0])


func _on_restart_prepare_from_host(args: Array) -> void:
	if args.size() > 0 and args[0] is String:
		restart_prepare_received.emit(args[0])


func _on_session_from_host(args: Array) -> void:
	if args.size() == 0 or not args[0] is String:
		return
	var parsed: Variant = JSON.parse_string(args[0])
	if not parsed is Dictionary:
		return
	var token := str(parsed.get("token", "")).strip_edges()
	var ws_url := str(parsed.get("wsUrl", ""))
	if not (ws_url.begins_with("ws://") or ws_url.begins_with("wss://")):
		ws_url = ""
	var runtime: Dictionary = {}
	if parsed.get("runtime") is Dictionary:
		runtime = parsed["runtime"]
	session_received.emit(token, ws_url, runtime)
