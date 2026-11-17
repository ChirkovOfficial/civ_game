extends TestCase


func _world() -> Dictionary:
	var game := blank_game(26, 14, 2)
	var first := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	var second := CityRules.found_city(game, 1, game.state.map.grid.index_of(18, 6))
	return {"game": game, "first": first, "second": second}


func test_great_people_points_works_patronage_and_save() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["first"]
	var tile := game.state.map.grid.neighbors(city.tile)[0]
	city.districts.append({"type": "THEATER_SQUARE", "tile": tile, "tier": 2,
		"buildings": ["AMPHITHEATER"], "complete": true, "cost": 150.0})
	game.state.map.district[tile] = "THEATER_SQUARE"
	var income := GreatPeopleRules.points_per_turn(game, 0)
	check_eq(income["WRITER"], 3.0)
	check_eq(income["ARTIST"], 3.0)
	game.state.map.pillaged[tile] = 1
	check_eq(GreatPeopleRules.points_per_turn(game, 0)["WRITER"], 0.0)
	game.state.map.pillaged[tile] = 0
	GreatPeopleRules.process_turn(game, 0)
	check_eq(game.state.player(0).great_person_points["WRITER"], 3.0)
	check_eq(game.apply_action({"type": "recruit_great_person", "city": city.id,
		"kind": "WRITER"})[0]["type"], "error")
	game.state.player(0).great_person_points["WRITER"] = 60.0
	var created := game.apply_action({"type": "recruit_great_person", "city": city.id, "kind": "WRITER"})
	check(created.any(func(event): return event["type"] == "great_work_created"))
	check_eq(city.great_works, 1)
	check_eq(city.great_work_types, ["WRITING"])
	check_eq(GreatPeopleRules.cost(game, "WRITER"), 90.0)
	check_near(CultureRules.work_tourism(game, city), 4.0)
	game.state.player(0).treasury = 1000.0
	var patron := game.apply_action({"type": "recruit_great_person", "city": city.id,
		"kind": "ARTIST", "patronage": true})
	check(patron.any(func(event): return event["type"] == "great_person_recruited"))
	check_eq(city.great_work_types, ["WRITING", "ART"])
	check_near(CultureRules.work_tourism(game, city), 9.0)
	check_near(game.state.player(0).treasury, 544.0)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.city(city.id).great_work_types, ["WRITING", "ART"])
	check_eq(int(restored.culture_data["great_people_recruited"]["WRITER"]), 1)
	check_eq(restored.player(0).great_person_points["WRITER"], 0.0)


func test_wonder_race_compensates_loser_and_saves_winner() -> void:
	var world := _world()
	var game: Game = world["game"]
	var first: City = world["first"]
	var second: City = world["second"]
	game.state.player(0).known_techs["MASONRY"] = true
	game.state.player(1).known_techs["MASONRY"] = true
	var first_tile := game.state.map.grid.neighbors(first.tile)[0]
	var second_tile := game.state.map.grid.neighbors(second.tile)[0]
	game.state.map.terrain[first_tile] = "DESERT"
	game.state.map.terrain[second_tile] = "DESERT"
	var first_action := {"type": "set_production", "city": first.id, "kind": "wonder", "id": "PYRAMIDS", "tile": first_tile}
	var second_action := {"type": "set_production", "city": second.id, "kind": "wonder", "id": "PYRAMIDS", "tile": second_tile}
	check(game.apply_action(first_action).any(func(event): return event["type"] == "wonder_placed"))
	game.state.current_player = 1
	check(game.apply_action(second_action).any(func(event): return event["type"] == "wonder_placed"))
	second.progress[City.item_key(second.current_item())] = 100.0
	game.state.current_player = 0
	var finished := []
	CityRules.process_production(game, first, CityRules.item_cost(game, first, first.current_item()), finished)
	check(finished.any(func(event): return event["type"] == "wonder_completed"))
	check_eq(WonderRules.built_city(game, "PYRAMIDS").id, first.id)
	check_near(WonderRules.tourism(game, first), 3.0)
	check(finished.any(func(event): return event["type"] == "wonder_lost"))
	check_eq(second.wonders.size(), 0)
	check(second.queue.is_empty())
	check_eq(game.state.map.district[second_tile], "")
	check_near(game.state.player(1).treasury, 50.0)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(WonderRules.built_city(Game.new(game.data, restored), "PYRAMIDS").id, first.id)


func test_scientist_engineer_merchant_and_legacy_works() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["first"]
	var player := game.state.player(0)
	for kind in ["SCIENTIST", "ENGINEER", "MERCHANT"]:
		player.great_person_points[kind] = GreatPeopleRules.cost(game, kind)
	var science := game.apply_action({"type": "recruit_great_person", "city": city.id, "kind": "SCIENTIST"})
	check(science.any(func(event): return event["type"] == "great_person_recruited"))
	check_near(float(player.tech_progress.get("_overflow", 0)), 80.0)
	game.apply_action({"type": "recruit_great_person", "city": city.id, "kind": "ENGINEER"})
	check_near(city.overflow, 120.0)
	game.apply_action({"type": "recruit_great_person", "city": city.id, "kind": "MERCHANT"})
	check_near(player.treasury, 200.0)
	var saved := game.state.to_dict()
	saved["version"] = 17
	saved.erase("culture_content")
	saved["players"][0].erase("great_person_points")
	saved["cities"][0].erase("great_work_types")
	saved["cities"][0].erase("wonders")
	saved["cities"][0]["great_works"] = 2
	var old := GameState.from_dict(saved, game.data)
	check_eq(old.city(city.id).great_work_types, ["", ""])
	check_eq(old.player(0).great_person_points, {})
	check_eq(old.culture_data["great_people_recruited"], {})


func test_seaside_resort_needs_coast_and_appeal_then_produces_tourism() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["first"]
	var tile := game.state.map.grid.neighbors(city.tile)[0]
	var around := game.state.map.grid.neighbors(tile)
	var builder := game.state.add_unit(0, "BUILDER", tile)
	builder.charges = 2
	builder.moves_left = 2.0
	game.state.player(0).known_civics["CONSERVATION"] = true
	check(ImprovementRules.build_error(game, builder, "SEASIDE_RESORT") != "")
	game.state.map.terrain[around[0]] = "COAST"
	game.state.map.feature[around[1]] = "WOODS"
	game.state.map.feature[around[2]] = "WOODS"
	check_eq(ImprovementRules.build_error(game, builder, "SEASIDE_RESORT"), "")
	check_eq(AIPlayer._improvement_gain(game, builder, tile)[0], "SEASIDE_RESORT")
	var built := game.apply_action({"type": "build_improvement", "unit": builder.id,
		"improvement": "SEASIDE_RESORT"})
	check(built.any(func(event): return event["type"] == "improvement_built"))
	check_near(CultureRules.tourism_per_turn(game, 0), 4.0)
	game.state.map.pillaged[tile] = 1
	check_near(CultureRules.tourism_per_turn(game, 0), 0.0)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.map.improvement[tile], "SEASIDE_RESORT")
