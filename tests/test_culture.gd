extends TestCase


func _world() -> Dictionary:
	var game := blank_game(26, 14, 2)
	var city := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	var rival := CityRules.found_city(game, 1, game.state.map.grid.index_of(17, 6))
	var tile := game.state.map.grid.neighbors(city.tile)[0]
	city.districts.append({"type": "THEATER_SQUARE", "tile": tile, "tier": 2,
		"buildings": [], "complete": true, "cost": 200.0})
	game.state.map.district[tile] = "THEATER_SQUARE"
	game.state.player(0).met[1] = true
	game.state.player(1).met[0] = true
	return {"game": game, "city": city, "rival": rival, "tile": tile}


func test_commission_requires_theater_and_fills_slots() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["city"]
	var item := {"kind": "cultural_project", "id": "GREAT_WORK"}
	check(CityRules.build_error(game, city, item).contains("Гуманизм"))
	game.state.player(0).known_civics["HUMANISM"] = true
	game.state.map.pillaged[world["tile"]] = 1
	check(CityRules.build_error(game, city, item).contains("работающей"))
	var pillaged_culture := float(CityRules.city_yields(game, city)["culture"])
	game.state.map.pillaged[world["tile"]] = 0
	var culture_before := float(CityRules.city_yields(game, city)["culture"])
	check_eq(game.apply_action({"type": "purchase", "city": city.id,
		"kind": "cultural_project", "id": "GREAT_WORK"})[0]["type"], "error")
	for count in range(1, 4):
		var started := game.apply_action({"type": "set_production", "city": city.id,
			"kind": "cultural_project", "id": "GREAT_WORK"})
		check_eq(started[0]["type"], "city_updated")
		var events: Array = []
		CityRules.process_production(game, city, CityRules.item_cost(game, city, item) + 1.0, events)
		check(events.any(func(event): return event["type"] == "great_work_created"))
		check_eq(city.great_works, count)
	check(CityRules.build_error(game, city, item).contains("свободная ячейка"))
	check_near(CultureRules.tourism_per_turn(game, 0), 12.0)
	check_near(float(CityRules.city_yields(game, city)["culture"]), culture_before + 6.0)
	game.state.map.pillaged[world["tile"]] = 1
	check_near(CultureRules.tourism_per_turn(game, 0), 0.0)
	check_near(float(CityRules.city_yields(game, city)["culture"]), pillaged_culture)
	game.state.map.pillaged[world["tile"]] = 0
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.city(city.id).great_works, 3)


func test_holy_city_and_walls_are_tourism_sources() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["city"]
	game.state.religions["TEST"] = {"founder": 0, "holy_city": city.id}
	check_near(CultureRules.tourism_per_turn(game, 0), 8.0)
	city.buildings.append("ANCIENT_WALLS")
	city.buildings.append("MEDIEVAL_WALLS")
	game.state.player(0).known_civics["CONSERVATION"] = true
	check_near(CultureRules.tourism_per_turn(game, 0), 10.0)
	city.owner = 1
	check_near(CultureRules.tourism_per_turn(game, 0), 0.0)
	check_near(CultureRules.tourism_per_turn(game, 1), 8.0)


func test_pair_modifiers_and_culture_save() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["city"]
	city.great_works = 2
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.0)
	var trader := game.state.add_unit(0, "TRADER", city.tile)
	trader.trade_route = {"origin": city.id, "destination": world["rival"].id}
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.25)
	game.state.treaty_data["active"]["passage:0:1"] = {"until": game.state.turn + 5}
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.5)
	game.state.player(0).known_techs["COMPUTERS"] = true
	game.state.player(0).known_civics["SOCIAL_MEDIA"] = true
	check_near(CultureRules.pair_multiplier(game, 0, 1), 2.0)
	game.state.player(0).government = "DEMOCRACY"
	game.state.player(1).government = "COMMUNISM"
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.75)
	city.religion_pressure["FAITH_A"] = 200.0
	var rival: City = world["rival"]
	rival.religion_pressure["FAITH_B"] = 200.0
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.25)
	game.state.player(0).known_civics["THE_ENLIGHTENMENT"] = true
	check_near(CultureRules.pair_multiplier(game, 0, 1), 1.75)
	game.state.player(0).government = ""
	game.state.player(1).government = ""
	EmpireRules.add_research(game, 0, "civic", 125.0, [])
	check_near(game.state.player(0).culture_total, 125.0)
	CultureRules.process_round(game)
	check_near(float(game.state.player(0).tourism_points["1"]), 16.0)
	trader.trade_route = {}
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_near(restored.player(0).culture_total, 125.0)
	check_near(float(restored.player(0).tourism_points["1"]), 16.0)
	var old := game.state.to_dict()
	old["version"] = 13
	old["players"][0].erase("culture_total")
	old["players"][0].erase("tourism_points")
	old["cities"][0].erase("great_works")
	check_near(GameState.from_dict(old, game.data).player(0).culture_total, 0.0)


func test_culture_victory_precedes_score() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["city"]
	city.great_works = 1
	game.state.player(1).culture_total = 100.0
	game.state.player(0).tourism_points["1"] = 796.0
	game.state.player(1).is_ai = false
	game.state.settings["turn_limit"] = 1
	game.apply_action({"type": "end_turn", "force": true})
	var ending := game.apply_action({"type": "end_turn", "force": true})
	check(ending.any(func(event): return event["type"] == "game_finished"))
	check_eq(game.state.result["kind"], "culture")
	check_eq(game.state.result["winners"], [0])
