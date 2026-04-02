@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Luxodd"
const AUTOLOAD_PATH := "res://addons/luxodd/luxodd.gd"
const CONFIG_PATH := "res://addons/luxodd/config/luxodd_config.tres"

var _export_plugin: LuxoddExportPlugin


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	add_tool_menu_item("Set Luxodd Dev Token", _open_dev_token_dialog)

	_export_plugin = LuxoddExportPlugin.new()
	add_export_plugin(_export_plugin)

	# Prompt for dev token on first activation if empty
	if _is_token_empty():
		call_deferred("_open_dev_token_dialog")


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	remove_tool_menu_item("Set Luxodd Dev Token")

	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _open_dev_token_dialog() -> void:
	var dialog := LuxoddDevTokenDialog.new()
	dialog.token_saved.connect(func(_t: String): print("[Luxodd] Dev token saved."))
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _is_token_empty() -> bool:
	if not ResourceLoader.exists(CONFIG_PATH):
		return true
	var config: LuxoddConfig = load(CONFIG_PATH)
	return config == null or config.developer_debug_token.is_empty()
