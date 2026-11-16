extends SceneTree
## Проверка меню с отдельными временными настройками и слотом сохранения.

const MENU := preload("res://view/start_menu.tscn")

var _slot := "start_menu_test_%d" % Time.get_ticks_usec()
var _settings := "user://%s.cfg" % _slot


func _initialize() -> void:
	call_deferred("_run")


func _menu() -> Node:
	var scene := MENU.instantiate()
	scene.save_slot = _slot
	scene.settings_path = _settings
	change_scene_to_node(scene)
	return scene


func _button(scene: Node, name: String) -> Button:
	return scene.find_child(name, true, false) as Button


func _choose(scene: Node, name: String, value: String) -> void:
	var options := scene.find_child(name, true, false) as OptionButton
	for i in options.item_count:
		if options.get_item_metadata(i) == value:
			options.select(i)
			options.item_selected.emit(i)
			return


func _run() -> void:
	var menu := _menu()
	await scene_changed
	if not _button(menu, "LoadGame").disabled or _button(menu, "Exit") == null:
		_finish("Пустое меню должно показывать выход и отключать загрузку")
		return
	_button(menu, "Settings").pressed.emit()
	var fullscreen := menu.find_child("Fullscreen", true, false) as CheckButton
	fullscreen.button_pressed = true
	var volume := menu.find_child("Volume", true, false) as HSlider
	volume.value = 37
	_button(menu, "ApplySettings").pressed.emit()
	var config := ConfigFile.new()
	if config.load(_settings) != OK or int(config.get_value("audio", "volume", -1)) != 37 \
			or not config.get_value("display", "fullscreen", false):
		_finish("Настройки не были записаны")
		return
	_button(menu, "NewGame").pressed.emit()
	_choose(menu, "MapSize", "DUEL")
	_choose(menu, "MapType", "PANGAEA")
	_choose(menu, "GameSpeed", "QUICK")
	_button(menu, "StartGame").pressed.emit()
	await scene_changed
	var game: Game = current_scene.game
	if game.state.settings["map_size"] != "DUEL" or game.state.settings["map_type"] != "PANGAEA" \
			or game.state.settings["speed"] != "QUICK":
		_finish("Карта не получила параметры из меню")
		return
	game.apply_action({"type": "end_turn", "force": true})
	var turn := game.state.turn
	var seed_value: String = game.state.settings["seed"]
	if SaveLoad.save(game, _slot) != "":
		_finish("Не удалось создать тестовое сохранение")
		return
	menu = _menu()
	await scene_changed
	if _button(menu, "LoadGame").disabled:
		_finish("Кнопка загрузки недоступна при наличии сохранения")
		return
	if not is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.37)):
		_finish("Настройки не применились после повторного открытия меню")
		return
	_button(menu, "LoadGame").pressed.emit()
	await scene_changed
	var restored: Game = current_scene.game
	if restored.state.turn != turn or restored.state.settings["seed"] != seed_value:
		_finish("Загрузка не восстановила ход и карту")
		return
	var scene := current_scene
	scene.hud.menu_pressed.emit()
	var confirmation := scene.get("_menu_confirmation") as ConfirmationDialog
	if confirmation == null or not confirmation.visible or current_scene != scene:
		_finish("Возврат из партии не запросил подтверждение")
		return
	confirmation.confirmed.emit()
	await scene_changed
	if _button(current_scene, "NewGame") == null:
		_finish("Подтверждение не открыло стартовое меню")
		return
	var broken := FileAccess.open(SaveLoad.path_for(_slot), FileAccess.WRITE)
	broken.store_buffer(var_to_bytes({"version": GameState.SAVE_VERSION}))
	broken.close()
	menu = _menu()
	await scene_changed
	_button(menu, "LoadGame").pressed.emit()
	for _i in 4:
		await process_frame
	if current_scene != menu or _button(current_scene, "NewGame") == null:
		_finish("Повреждённое сохранение должно оставить игрока в меню")
		return
	print("Стартовое меню: настройки, новая игра, загрузка и возврат работают")
	_finish("")


func _finish(error: String) -> void:
	for path in [_settings, SaveLoad.path_for(_slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not error.is_empty():
		printerr(error)
	quit(0 if error.is_empty() else 1)
