extends SceneTree
## Проверка доступности основания религии и покупки миссионера из игрового окна.


func _initialize() -> void:
	call_deferred("_run")


func _button(box: Control, prefix: String) -> Button:
	for node in box.find_children("*", "Button", true, false):
		if node.text.begins_with(prefix):
			return node
	return null


func _run() -> void:
	var main: Node3D = load("res://view/main.tscn").instantiate()
	main.map_size = "DUEL"
	main.fixed_seed = 71
	root.add_child(main)
	var game: Game = main.game
	var city := CityRules.found_city(game, 0, game.state.start_positions[0])
	var site_tile := -1
	for tile in game.state.map.grid.neighbors(city.tile):
		if game.state.map.is_land(tile) and not game.state.map.is_mountain(tile):
			site_tile = tile
			break
	if site_tile < 0:
		printerr("Нет клетки для Священного места в проверочной партии")
		quit(1)
		return
	city.districts.append({"type": "HOLY_SITE", "tile": site_tile, "tier": 1,
		"buildings": [], "complete": true, "cost": 1.0})
	game.state.map.district[site_tile] = "HOLY_SITE"
	game.state.player(0).prophet_points = 20.0
	main.hud.open_religion()
	var box: VBoxContainer = main.hud.get("_research_box")
	var recruit := _button(box, "Нанять Великого пророка")
	if recruit == null:
		printerr("Кнопка найма пророка не появилась")
		quit(1)
		return
	recruit.pressed.emit()
	var found := _button(box, "Основать религию")
	if found == null:
		printerr("Кнопка основания религии не появилась")
		quit(1)
		return
	found.pressed.emit()
	if game.state.player(0).religion_id == "":
		printerr("Религия не основана из интерфейса")
		quit(1)
		return
	game.state.player(0).faith = 75.0
	main.hud.open_religion()
	var missionary := _button(box, "Купить миссионера")
	if missionary == null:
		printerr("Кнопка покупки миссионера не появилась")
		quit(1)
		return
	missionary.pressed.emit()
	var exists := false
	for unit in game.state.units_of(0):
		if unit.type == "MISSIONARY":
			exists = true
	if not exists or game.state.player(0).faith != 0.0:
		printerr("Миссионер не создан или вера не списана")
		quit(1)
		return
	print("Религия основана, миссионер куплен через игровой экран")
	quit()
