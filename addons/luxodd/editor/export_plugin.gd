@tool
class_name LuxoddExportPlugin
extends EditorExportPlugin

const CONFIG_PATH := "res://addons/luxodd/config/luxodd_config.tres"


func _get_name() -> String:
	return "LuxoddExportPlugin"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not features.has("web"):
		push_warning("[Luxodd] This plugin is designed for HTML5 (Web) exports. "
			+ "The host bridge will not function on other platforms.")

	if ResourceLoader.exists(CONFIG_PATH):
		var config: LuxoddConfig = load(CONFIG_PATH)
		if config and config.server_address.is_empty():
			push_error("[Luxodd] Server address is not configured. "
				+ "Edit addons/luxodd/config/luxodd_config.tres before exporting.")
