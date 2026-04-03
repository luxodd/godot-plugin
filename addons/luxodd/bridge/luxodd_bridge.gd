class_name LuxoddBridge
extends Node

## Handles postMessage communication between the game (running in an iframe)
## and the Luxodd host page. Only active on HTML5 builds — all methods are
## no-ops on desktop/editor to allow seamless local testing.

signal jwt_received(token: String)
signal action_received(action: String)

var _jwt_callback: JavaScriptObject
var _action_callback: JavaScriptObject
var _is_web: bool = false


func initialize() -> void:
	_is_web = OS.has_feature("web")
	if not _is_web:
		return

	# Create GDScript callbacks that JavaScript can invoke
	_jwt_callback = JavaScriptBridge.create_callback(_on_jwt_from_host)
	_action_callback = JavaScriptBridge.create_callback(_on_action_from_host)

	# Expose callbacks on the window object so our injected JS can reach them
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.set("_luxodd_jwt_cb", _jwt_callback)
	window.set("_luxodd_action_cb", _action_callback)

	# Inject a message listener that routes host messages to our callbacks
	JavaScriptBridge.eval("""
		(function() {
			if (window._luxodd_listener_added) return;
			window._luxodd_listener_added = true;
			window.addEventListener('message', function(e) {
				var d = e.data;
				if (!d || typeof d !== 'object') return;
				if (typeof d.jwt === 'string' && window._luxodd_jwt_cb) {
					window._luxodd_jwt_cb(d.jwt);
				}
				if (typeof d.action === 'string' && window._luxodd_action_cb) {
					window._luxodd_action_cb(d.action);
				}
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


func get_ws_host_from_url() -> String:
	## Read the wsHost query param set by the Luxodd embed page.
	if not _is_web:
		return ""
	var result: Variant = JavaScriptBridge.eval("""
		(function() {
			var params = new URLSearchParams(window.location.search);
			var wsHost = params.get('wsHost') || '';
			if (wsHost) return 'wss://' + wsHost;
			return '';
		})();
	""", true)
	return str(result) if result != null else ""


func post_game_ready() -> void:
	if not _is_web:
		return
	JavaScriptBridge.eval("window.parent.postMessage({type:'gameReady'}, '*');", true)


func post_session_end() -> void:
	if not _is_web:
		return
	JavaScriptBridge.eval("window.parent.postMessage({type:'session_end'}, '*');", true)


func post_session_option(action: String) -> void:
	if not _is_web:
		return
	JavaScriptBridge.eval(
		"window.parent.postMessage({type:'session_options',action:'%s'}, '*');" % action, true
	)


func _on_jwt_from_host(args: Array) -> void:
	if args.size() > 0 and args[0] is String:
		jwt_received.emit(args[0])


func _on_action_from_host(args: Array) -> void:
	if args.size() > 0 and args[0] is String:
		action_received.emit(args[0])
