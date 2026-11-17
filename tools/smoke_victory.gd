extends SceneTree
## Проверка экрана итогов в главной сцене.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	main.map_size = "DUEL"
	main.fixed_seed = 17
	root.add_child(main)
	var game: Game = main.game
	game.state.settings["turn_limit"] = 1
	main.act({"type": "end_turn", "force": true})
	var hud: Hud = main.hud
	if game.state.result.get("kind") != "score" or not hud.is_modal_open() \
			or hud.get("_research_kind") != "victory":
		printerr("Экран итогов не открылся после завершения партии")
		quit(1)
		return
	hud.close_research()
	main._end_turn()
	if not hud.is_modal_open() or game.state.turn != 1:
		printerr("Итоги нельзя открыть повторно")
		quit(1)
		return
	main.queue_free()
	var second: Node = load("res://view/main.tscn").instantiate()
	second.map_size = "DUEL"
	second.fixed_seed = 18
	root.add_child(second)
	var religious_game: Game = second.game
	var home := CityRules.found_city(religious_game, 0, religious_game.state.start_positions[0])
	var rival := CityRules.found_city(religious_game, 1, religious_game.state.start_positions[1])
	religious_game.state.player(0).religion_id = "TEST_FAITH"
	religious_game.state.religions["TEST_FAITH"] = {"name": "Путь звёзд", "founder": 0,
		"holy_city": home.id, "follower_belief": "SCHOLARLY", "founder_belief": "TITHE",
		"cult_belief": "", "enhancer_belief": "", "inquisition_started": false}
	home.religion_pressure["TEST_FAITH"] = 400.0
	var missionary := religious_game.state.add_unit(0, "MISSIONARY", rival.tile)
	missionary.charges = 1
	missionary.moves_left = 2.0
	second.act({"type": "spread_religion", "unit": missionary.id})
	var religious_hud: Hud = second.hud
	if religious_game.state.result.get("kind") != "religion" or not religious_hud.is_modal_open() \
			or religious_hud.get("_research_kind") != "victory":
		printerr("Экран религиозной победы не открылся")
		quit(1)
		return
	var shown := false
	for label in religious_hud.get("_research_box").find_children("*", "Label", true, false):
		if label.text.contains("Распространение религии Путь звёзд"):
			shown = true
	if not shown:
		printerr("На экране итогов нет названия победившей религии")
		quit(1)
		return
	second.queue_free()
	var third: Node = load("res://view/main.tscn").instantiate()
	third.map_size = "DUEL"
	third.fixed_seed = 19
	root.add_child(third)
	var scientific_game: Game = third.game
	scientific_game.state.science_data["0"] = {"completed": {"EARTH_SATELLITE": true,
		"MOON_LANDING": true, "MARS_COLONY": true, "EXOPLANET_EXPEDITION": true},
		"launched": true, "distance": 49, "speed": 1, "lasers": 0}
	scientific_game.state.settings["turn_limit"] = 1
	third.act({"type": "end_turn", "force": true})
	var scientific_hud: Hud = third.hud
	if scientific_game.state.result.get("kind") != "science" or not scientific_hud.is_modal_open() \
			or scientific_hud.get("_research_kind") != "victory":
		printerr("Экран научной победы не открылся")
		quit(1)
		return
	shown = false
	for label in scientific_hud.get("_research_box").find_children("*", "Label", true, false):
		if label.text.contains("Экспедиция достигла экзопланеты"):
			shown = true
	if not shown:
		printerr("На экране итогов нет причины научной победы")
		quit(1)
		return
	print("Экраны очковой, религиозной и научной победы открываются автоматически")
	quit()
