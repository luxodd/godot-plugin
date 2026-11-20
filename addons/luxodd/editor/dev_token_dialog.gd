@tool
class_name LuxoddDevTokenDialog
extends ConfirmationDialog

signal token_saved(token: String)

# Editor and desktop only: the plugin never reads this file in a web build, and the export
# plugin leaves it out of every export. 1.0.0 wrote the token into the addon's own config,
# which ships inside the web build (integration check SEC-6). Add this file to .gitignore.
const CONFIG_PATH := "res://luxodd_dev_config.tres"
const LEGACY_CONFIG_PATH := "res://addons/luxodd/config/luxodd_config.tres"

var _line_edit: LineEdit


func _init() -> void:
	title = "Luxodd — Set Developer Token"
	min_size = Vector2i(450, 120)

	var vbox := VBoxContainer.new()

	var label := Label.new()
	label.text = "Enter your Luxodd developer debug token:"
	vbox.add_child(label)

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Paste token here..."
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Load existing token (never shown in the console)
	_line_edit.secret = true
	for path in [CONFIG_PATH, LEGACY_CONFIG_PATH]:
		if ResourceLoader.exists(path):
			var config: LuxoddConfig = load(path)
			if config and not config.developer_debug_token.is_empty():
				_line_edit.text = config.developer_debug_token
				break

	vbox.add_child(_line_edit)
	add_child(vbox)

	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)


func _on_confirmed() -> void:
	var token := _line_edit.text.strip_edges()

	var config: LuxoddConfig
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
	elif ResourceLoader.exists(LEGACY_CONFIG_PATH):
		# Start from the project's settings, without carrying the token along in the addon file.
		config = (load(LEGACY_CONFIG_PATH) as LuxoddConfig).duplicate()
	else:
		config = LuxoddConfig.new()

	config.developer_debug_token = token
	ResourceSaver.save(config, CONFIG_PATH)

	# Move a token saved by 1.0.0 out of the exported addon config.
	if ResourceLoader.exists(LEGACY_CONFIG_PATH):
		var legacy: LuxoddConfig = load(LEGACY_CONFIG_PATH)
		if legacy and not legacy.developer_debug_token.is_empty():
			legacy.developer_debug_token = ""
			ResourceSaver.save(legacy, LEGACY_CONFIG_PATH)
	token_saved.emit(token)
	queue_free()
