extends TestCase


func _world() -> Dictionary:
	var game := blank_game(26, 14, 2)
	var city := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	var tile := game.state.map.grid.neighbors(city.tile)[0]
	city.districts.append({"type": "SPACEPORT", "tile": tile, "tier": 1,
		"buildings": [], "complete": true, "cost": 1800.0})
	game.state.map.district[tile] = "SPACEPORT"
	return {"game": game, "city": city, "tile": tile}


func _finish_project(game: Game, city: City, id: String) -> Array:
	game.state.current_player = city.owner
	var started := game.apply_action({"type": "set_production", "city": city.id, "kind": "project", "id": id})
	check_eq(started[0]["type"], "city_updated")
	var events: Array = []
	CityRules.process_production(game, city, CityRules.item_cost(game, city, {"kind": "project", "id": id}) + 1.0, events)
	check(events.any(func(event): return event["type"] == "science_project_completed" and event["project"] == id),
		"проект %s завершается через очередь города" % id)
	return events


func test_science_projects_require_spaceport_technology_and_order() -> void:
	var state := _world()
	var game: Game = state["game"]
	var city: City = state["city"]
	var player := game.state.player(0)
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "EARTH_SATELLITE"}).begins_with("Нужна технология"), true)
	player.known_techs["ROCKETRY"] = true
	game.state.map.pillaged[state["tile"]] = 1
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "EARTH_SATELLITE"}), "Нужен работающий Космопорт в этом городе")
	game.state.map.pillaged[state["tile"]] = 0
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "MOON_LANDING"}).begins_with("Нужна технология"), true)
	check_eq(game.apply_action({"type": "purchase", "city": city.id, "kind": "project", "id": "EARTH_SATELLITE"})[0]["type"], "error")
	_finish_project(game, city, "EARTH_SATELLITE")
	check_eq(player.revealed.count(Player.FOG_UNEXPLORED), 0)
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "EARTH_SATELLITE"}), "Этот проект уже завершён державой")
	player.known_techs["SATELLITES"] = true
	player.known_techs["NANOTECHNOLOGY"] = true
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "MARS_COLONY"}), "Сначала завершите предыдущий космический проект")
	var expected_culture := float(EmpireRules.summary(game, 0)["yields"].get("science", 0.0)) * 10.0
	var culture_before := float(player.civic_progress.get("_overflow", 0.0))
	var moon_events := _finish_project(game, city, "MOON_LANDING")
	var moon_event: Dictionary = moon_events.filter(func(event): return event["type"] == "science_project_completed")[0]
	check_near(float(moon_event["culture"]), expected_culture)
	check(float(player.civic_progress.get("_overflow", 0.0)) >= culture_before)
	_finish_project(game, city, "MARS_COLONY")
	check_eq(ScienceRules.status(game, 0)["completed"].size(), 3)


func test_expedition_lasers_save_and_arrival_before_score() -> void:
	var state := _world()
	var game: Game = state["game"]
	var city: City = state["city"]
	var player := game.state.player(0)
	for tech in ["ROCKETRY", "SATELLITES", "NANOTECHNOLOGY", "SMART_MATERIALS", "OFFWORLD_MISSION"]:
		player.known_techs[tech] = true
	for project in ["EARTH_SATELLITE", "MOON_LANDING", "MARS_COLONY", "EXOPLANET_EXPEDITION"]:
		_finish_project(game, city, project)
	check(ScienceRules.status(game, 0)["launched"])
	check_eq(ScienceRules.status(game, 0)["speed"], 1)
	check_eq(CityRules.build_error(game, city, {"kind": "project", "id": "EXOPLANET_EXPEDITION"}), "Этот проект уже завершён державой")
	check(CityRules.build_error(game, city, {"kind": "project", "id": "GROUND_LASER"}) != "")
	player.stockpile["ALUMINUM"] = 20.0
	check(CityRules.build_error(game, city, {"kind": "project", "id": "GROUND_LASER"}).contains("энергии"))
	for tile in game.state.map.grid.neighbors(city.tile).slice(1, 4):
		game.state.map.relief[tile] = GameMap.RELIEF_HILLS
		game.state.map.improvement[tile] = "WIND_FARM"
	_finish_project(game, city, "GROUND_LASER")
	_finish_project(game, city, "LAGRANGE_LASER")
	check_eq(ScienceRules.status(game, 0)["speed"], 1)
	check_eq(ScienceRules.status(game, 0)["lasers"], 2)
	check_near(float(player.stockpile["ALUMINUM"]), 0.0)
	ScienceRules.process_round(game, [])
	check_eq(ScienceRules.status(game, 0)["speed"], 3)
	for tile in game.state.map.grid.neighbors(city.tile).slice(1, 4):
		game.state.map.pillaged[tile] = 1
	ScienceRules.process_round(game, [])
	check_eq(ScienceRules.status(game, 0)["speed"], 1)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.science_data, game.state.science_data)
	var prior := game.state.to_dict()
	prior["version"] = 16
	prior.erase("energy")
	prior["science"]["0"].erase("laser_sites")
	var migrated := GameState.from_dict(prior, game.data)
	check_eq(int(migrated.science_data["0"]["laser_sites"].get(str(city.id), 0)), 2)
	var old := game.state.to_dict()
	old["version"] = 12
	old.erase("science")
	check(GameState.from_dict(old, game.data).science_data.is_empty(), "старая партия загружается без космических проектов")
	game.state.science_data["0"]["distance"] = 49
	game.state.science_data["0"]["speed"] = 1
	game.state.player(1).is_ai = false
	game.state.settings["turn_limit"] = 1
	game.apply_action({"type": "end_turn", "force": true})
	var ending := game.apply_action({"type": "end_turn", "force": true})
	check(ending.any(func(event): return event["type"] == "science_expedition_arrived"))
	check_eq(game.state.result["kind"], "science")
	check_eq(game.state.result["winners"], [0])
	check_eq(game.state.turn, 1)


func test_ai_starts_spaceport_and_project() -> void:
	var game := blank_game(26, 14, 2)
	var city := CityRules.found_city(game, 1, game.state.map.grid.index_of(8, 6))
	game.state.player(1).known_techs["ROCKETRY"] = true
	game.state.current_player = 1
	check(AIPlayer._science_production(game, city))
	check_eq(city.queue[0]["id"], "SPACEPORT")
	var district: Dictionary = DistrictRules.of_type(city, "SPACEPORT")[0]
	district["complete"] = true
	city.queue.clear()
	check(AIPlayer._science_production(game, city))
	check_eq(city.queue[0]["id"], "EARTH_SATELLITE")
