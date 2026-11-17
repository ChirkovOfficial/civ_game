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
	third.queue_free()
	var fourth: Node = load("res://view/main.tscn").instantiate()
	fourth.map_size = "DUEL"
	fourth.fixed_seed = 20
	root.add_child(fourth)
	var culture_game: Game = fourth.game
	var culture_city := CityRules.found_city(culture_game, 0, culture_game.state.start_positions[0])
	CityRules.found_city(culture_game, 1, culture_game.state.start_positions[1])
	var theater_tile := culture_game.state.map.grid.neighbors(culture_city.tile)[0]
	culture_city.districts.append({"type": "THEATER_SQUARE", "tile": theater_tile,
		"tier": 2, "buildings": [], "complete": true, "cost": 200.0})
	culture_game.state.map.district[theater_tile] = "THEATER_SQUARE"
	culture_city.great_works = 1
	culture_game.state.player(0).met[1] = true
	culture_game.state.player(1).met[0] = true
	culture_game.state.player(0).tourism_points["1"] = 796.0
	culture_game.state.player(1).culture_total = 100.0
	culture_game.state.settings["turn_limit"] = 1
	fourth.act({"type": "end_turn", "force": true})
	var culture_hud: Hud = fourth.hud
	if culture_game.state.result.get("kind") != "culture" or not culture_hud.is_modal_open() \
			or culture_hud.get("_research_kind") != "victory":
		printerr("Экран культурной победы не открылся")
		quit(1)
		return
	shown = false
	for label in culture_hud.get("_research_box").find_children("*", "Label", true, false):
		if label.text.contains("Приезжих туристов больше"):
			shown = true
	if not shown:
		printerr("На экране итогов нет причины культурной победы")
		quit(1)
		return
	fourth.queue_free()
	var fifth: Node = load("res://view/main.tscn").instantiate()
	fifth.map_size = "DUEL"
	fifth.fixed_seed = 21
	root.add_child(fifth)
	var finance_game: Game = fifth.game
	var finance_city := CityRules.found_city(finance_game, 0, finance_game.state.start_positions[0])
	CityRules.found_city(finance_game, 1, finance_game.state.start_positions[1])
	finance_game.data.buildings["SMOKE_MINT"] = {"yields": {"gold": 700}, "maintenance": 0}
	finance_city.buildings.append("SMOKE_MINT")
	finance_game.state.player(1).known_techs["BANKING"] = true
	finance_game.state.finance_data["unlocked"] = true
	finance_game.state.finance_data["streaks"]["0"] = FinanceRules.required_turns(finance_game) - 1
	finance_game.state.settings["turn_limit"] = 3
	var finance_hud: Hud = fifth.hud
	finance_hud.open_finance()
	if not finance_hud.is_modal_open() or finance_hud.get("_research_kind") != "finance":
		printerr("Окно Мировой биржи не открылось")
		quit(1)
		return
	finance_hud.close_research()
	fifth.act({"type": "end_turn", "force": true})
	if finance_game.state.result.get("kind") != "finance" or not finance_hud.is_modal_open() \
			or finance_hud.get("_research_kind") != "victory":
		printerr("Экран финансовой победы не открылся")
		quit(1)
		return
	shown = false
	for label in finance_hud.get("_research_box").find_children("*", "Label", true, false):
		if label.text.contains("Устойчивая финансовая гегемония"):
			shown = true
	if not shown:
		printerr("На экране итогов нет причины финансовой победы")
		quit(1)
		return
	print("Окно Мировой биржи и экраны пяти видов побед открываются")
	quit()
