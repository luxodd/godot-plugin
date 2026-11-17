@tool
class_name LuxoddExportPlugin
extends EditorExportPlugin

const CONFIG_PATH := "res://addons/luxodd/config/luxodd_config.tres"
const PRODUCTION_CONFIG_PATH := "res://luxodd_config.tres"
const DEV_CONFIG_PATH := "res://luxodd_dev_config.tres"


func _get_name() -> String:
	return "LuxoddExportPlugin"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("web"):
		push_warning("[Luxodd] This plugin is designed for HTML5 (Web) exports. "
			+ "The host bridge will not function on other platforms.")
	else:
		# Godot's web export renders through WebGL 2 with the Compatibility renderer.
		var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method.web", "gl_compatibility"))
		if method != "gl_compatibility":
			push_warning("[Luxodd] Web exports need the Compatibility renderer "
				+ "(rendering/renderer/rendering_method.web = gl_compatibility); it is '%s'." % method)

	for path in [CONFIG_PATH, PRODUCTION_CONFIG_PATH]:
		if not ResourceLoader.exists(path):
			continue
		var config: LuxoddConfig = load(path)
		if config == null:
			continue
		if path == CONFIG_PATH and config.server_address.is_empty():
			push_error("[Luxodd] Server address is not configured. "
				+ "Edit addons/luxodd/config/luxodd_config.tres before exporting.")
		if not config.developer_debug_token.is_empty():
			# The game API key would ship inside the build (integration check SEC-6).
			push_error("[Luxodd] %s contains a developer token, which would ship inside this build. " % path
				+ "Use Project > Tools > Set Luxodd Dev Token, which keeps it in luxodd_dev_config.tres.")
		if config.logs_enabled:
			push_warning("[Luxodd] Plugin logs are on in %s. Turn them off for a submission build." % path)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Editor and desktop testing only; it holds the developer token.
	if path == DEV_CONFIG_PATH:
		skip()
