@tool
class_name LuxoddDevTokenDialog
extends ConfirmationDialog

signal token_saved(token: String)

const CONFIG_PATH := "res://addons/luxodd/config/luxodd_config.tres"

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

	# Load existing token
	if ResourceLoader.exists(CONFIG_PATH):
		var config: LuxoddConfig = load(CONFIG_PATH)
		if config:
			_line_edit.text = config.developer_debug_token

	vbox.add_child(_line_edit)
	add_child(vbox)

	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)


func _on_confirmed() -> void:
	var token := _line_edit.text.strip_edges()

	var config: LuxoddConfig
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
	else:
		config = LuxoddConfig.new()

	config.developer_debug_token = token
	ResourceSaver.save(config, CONFIG_PATH)
	token_saved.emit(token)
	queue_free()
