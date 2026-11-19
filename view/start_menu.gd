extends Control
## Стартовое меню. Карта появляется после выбора партии.

const GAME_SCENE := preload("res://view/main.tscn")
const UiSkin := preload("res://view/ui_skin.gd")
const TEXT := Color("#eae3d2")
const MUTED := Color("#b6b5ae")
const ACCENT := Color("#d4b57e")

var _data: GameData
var settings_path := "user://settings.cfg"
var save_slot := SaveLoad.QUICKSAVE
var _panel: VBoxContainer
var _screen := "home"
var _busy := false
var _fullscreen := false
var _volume := 80
var _new_game_options := {"map_size": "SMALL", "map_type": "CONTINENTS", "speed": "STANDARD"}


func _ready() -> void:
	theme = UiSkin.theme()
	_data = GameData.get_default()
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		_fullscreen = bool(config.get_value("display", "fullscreen", false))
		_volume = clampi(int(config.get_value("audio", "volume", 80)), 0, 100)
	_apply_settings()
	_build_layout()
	_home()


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color("#151d22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margins := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 20)
	center.add_child(margins)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 410
	var frame := UiSkin.panel()
	card.add_theme_stylebox_override("panel", frame)
	margins.add_child(card)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	card.add_child(_panel)


func _show(screen: String, title: String) -> void:
	_screen = screen
	for child in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	var label := _label(title, 29, ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var line := HSeparator.new()
	_panel.add_child(line)


func _label(value: String, size: int = 16, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_panel.add_child(label)
	return label


func _button(id: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	_panel.add_child(button)
	return button


func _home(message: String = "") -> void:
	_show("home", "Civ Game")
	_button("NewGame", "Новая игра", _setup_game).grab_focus()
	var load_button := _button("LoadGame", "Загрузить игру", _load_game)
	load_button.disabled = not SaveLoad.exists(save_slot)
	_button("Settings", "Настройки", _show_settings)
	_button("Exit", "Выход", func(): get_tree().quit())
	if not message.is_empty():
		_label(message, 14, MUTED)
	elif load_button.disabled:
		_label("Быстрого сохранения пока нет.", 14, MUTED)


func _setup_game() -> void:
	_show("setup", "Новая игра")
	var sizes := _choices("MapSize", "Размер карты", "map_sizes", "map_size")
	_choices("MapType", "Тип карты", "map_types", "map_type")
	_choices("GameSpeed", "Скорость игры", "game_speeds", "speed")
	_button("StartGame", "Начать партию", _new_game)
	_button("Back", "Назад", _home)
	sizes.grab_focus()


func _choices(id: String, caption: String, group: String, setting: String) -> OptionButton:
	_label(caption)
	var select := OptionButton.new()
	select.name = id
	select.custom_minimum_size.y = 37
	_panel.add_child(select)
	for entry in _data.setup[group]:
		select.add_item(entry["name"])
		var index := select.item_count - 1
		select.set_item_metadata(index, entry["id"])
		if entry["id"] == _new_game_options[setting]:
			select.select(index)
	select.item_selected.connect(func(index: int): _new_game_options[setting] = select.get_item_metadata(index))
	return select


func _show_settings() -> void:
	_show("settings", "Настройки")
	var mode := CheckButton.new()
	mode.name = "Fullscreen"
	mode.text = "Полноэкранный режим"
	mode.button_pressed = _fullscreen
	_panel.add_child(mode)
	var volume_label := _label("Общая громкость · %d%%" % _volume)
	var volume := HSlider.new()
	volume.name = "Volume"
	volume.custom_minimum_size.y = 26
	volume.max_value = 100
	volume.step = 1
	volume.value = _volume
	volume.value_changed.connect(func(value: float): volume_label.text = "Общая громкость · %d%%" % int(value))
	_panel.add_child(volume)
	var message := _label("", 14, MUTED)
	message.hide()
	_button("ApplySettings", "Применить", func():
		var config := ConfigFile.new()
		config.set_value("display", "fullscreen", mode.button_pressed)
		config.set_value("audio", "volume", int(volume.value))
		if config.save(settings_path) != OK:
			message.text = "Не удалось сохранить настройки."
			message.show()
			return
		_fullscreen = mode.button_pressed
		_volume = int(volume.value)
		_apply_settings()
		_home("Настройки сохранены."))
	_button("Back", "Назад", _home)
	mode.grab_focus()


func _apply_settings() -> void:
	if DisplayServer.get_name() != "headless":
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, _volume == 0)
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(0.001, _volume / 100.0)))


func _new_game() -> void:
	if _busy:
		return
	await _loading("Генерация карты…")
	var scene := GAME_SCENE.instantiate()
	scene.map_size = _new_game_options["map_size"]
	scene.map_type = _new_game_options["map_type"]
	scene.game_speed = _new_game_options["speed"]
	_enter_game(scene)


func _load_game() -> void:
	if _busy:
		return
	await _loading("Загрузка сохранения…")
	var game := SaveLoad.load_game(_data, save_slot)
	if game == null:
		_busy = false
		_home("Не удалось загрузить быстрое сохранение.")
		return
	var scene := GAME_SCENE.instantiate()
	scene.initial_game = game
	_enter_game(scene)


func _loading(message: String) -> void:
	_busy = true
	_show("loading", message)
	# Показать сообщение до синхронной генерации или чтения карты.
	await get_tree().process_frame
	await get_tree().process_frame


func _enter_game(scene: Node) -> void:
	if get_tree().change_scene_to_node(scene) != OK:
		scene.free()
		_busy = false
		_home("Не удалось открыть игровую сцену.")


func _unhandled_key_input(event: InputEvent) -> void:
	if not _busy and event.is_action_pressed("ui_cancel") and _screen != "home":
		_home()
		get_viewport().set_input_as_handled()
