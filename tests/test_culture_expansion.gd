extends TestCase


func _world() -> Dictionary:
	var game := blank_game(30, 16, 2)
	var home := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 7))
	var second := CityRules.found_city(game, 0, game.state.map.grid.index_of(14, 7))
	var rival := CityRules.found_city(game, 1, game.state.map.grid.index_of(23, 7))
	game.state.player(0).met[1] = true
	game.state.player(1).met[0] = true
	return {"game": game, "home": home, "second": second, "rival": rival}


func test_national_park_geometry_tourism_amenities_and_save() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["home"]
	for tile in game.state.map.grid.tiles_in_radius(city.tile, 3):
		game.state.map.owner_city[tile] = city.id
	var stand := game.state.map.grid.index_of(8, 7)
	var unit := game.state.add_unit(0, "NATURALIST", stand)
	unit.moves_left = 2.0
	var option := ParkRules.best_option(game, 0, stand)
	check_eq(option.get("tiles", []).size(), 4)
	check_near(float(option.get("tourism", 0)), 8.0)
	var before: int = int(CityRules.amenity_info(game, city)["have"])
	var events := game.apply_action({"type": "found_park", "unit": unit.id})
	check(events.any(func(event): return event["type"] == "national_park_founded"))
	check_eq(game.state.unit(unit.id), null)
	check_eq(city.parks.size(), 1)
	check_near(ParkRules.tourism(game, city), 8.0)
	check_eq(CityRules.amenity_info(game, city)["have"], before + 2)
	var park_tile := int(city.parks[0]["tiles"][0])
	check_eq(game.state.map.improvement[park_tile], "NATIONAL_PARK")
	var builder := game.state.add_unit(0, "BUILDER", park_tile)
	builder.charges = 1
	check(ImprovementRules.build_error(game, builder, "FARM").contains("Национальный парк"))
	check(DistrictRules.placement_error(game, city, "CAMPUS", park_tile) != "")
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.city(city.id).parks.size(), 1)
	check_near(ParkRules.tourism(Game.new(game.data, restored), restored.city(city.id)), 8.0)
	game.state.remove_unit(builder.id)
	game.state.wars["0,1"] = true
	var raider := game.state.add_unit(1, "WARRIOR", park_tile)
	raider.moves_left = 2.0
	game.state.current_player = 1
	check_eq(UnitRules.pillage_error(game, raider), "")
	game.apply_action({"type": "pillage", "unit": raider.id})
	check_near(ParkRules.tourism(game, city), 0.0)
	check_eq(CityRules.amenity_info(game, city)["have"], before)
	game.state.remove_unit(raider.id)
	var repairer := game.state.add_unit(0, "BUILDER", park_tile)
	repairer.moves_left = 2.0
	game.state.current_player = 0
	game.apply_action({"type": "repair", "unit": repairer.id})
	check_near(ParkRules.tourism(game, city), 8.0)


func test_naturalist_recruitment_and_old_save_defaults() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["home"]
	game.state.player(0).faith = 500.0
	check(game.apply_action({"type": "recruit_naturalist", "city": city.id})[0]["type"] == "error")
	game.state.player(0).known_civics["CONSERVATION"] = true
	var recruited := game.apply_action({"type": "recruit_naturalist", "city": city.id})
	check(recruited.any(func(event): return event["type"] == "unit_created"))
	check_near(game.state.player(0).faith, 300.0)
	check_eq(ParkRules.faith_cost(game, 0), 225)
	var old := game.state.to_dict()
	old["version"] = 18
	old["culture_content"].erase("naturalists_recruited")
	old["culture_content"].erase("rock_bands_recruited")
	for entry in old["cities"]:
		entry.erase("parks")
	var loaded := GameState.from_dict(old, game.data)
	check_eq(loaded.city(city.id).parks, [])
	check_eq(loaded.culture_data["naturalists_recruited"], {})


func test_rock_band_concert_targets_host_and_respects_war() -> void:
	var world := _world()
	var game: Game = world["game"]
	var home: City = world["home"]
	var rival: City = world["rival"]
	game.state.player(0).faith = 500.0
	check_eq(game.apply_action({"type": "recruit_rock_band", "city": home.id})[0]["type"], "error")
	game.state.player(0).known_civics["COLD_WAR"] = true
	var recruited := game.apply_action({"type": "recruit_rock_band", "city": home.id})
	check(recruited.any(func(event): return event["type"] == "unit_created"))
	check_near(game.state.player(0).faith, 200.0)
	check_eq(RockBandRules.faith_cost(game, 0), 375)
	var band: Unit = null
	for unit in game.state.units_of(0):
		if unit.type == "ROCK_BAND":
			band = unit
	check(band != null)
	if band == null:
		return
	check(TreatyRules.border_allows(game, band, home.tile, rival.tile))
	band.tile = rival.tile
	band.moves_left = 2.0
	game.state.wars["0,1"] = true
	check(not TreatyRules.border_allows(game, band, home.tile, rival.tile))
	check(RockBandRules.concert_error(game, band) != "")
	game.state.wars.erase("0,1")
	var concert := game.apply_action({"type": "perform_concert", "unit": band.id})
	check(concert.any(func(event): return event["type"] == "rock_concert"))
	check_near(float(game.state.player(0).tourism_points.get("1", 0)), 250.0)
	check_eq(game.state.player(0).tourism_points.size(), 1)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_near(float(restored.player(0).tourism_points.get("1", 0)), 250.0)


func test_move_work_between_own_cities_restores_inactive_tourism() -> void:
	var world := _world()
	var game: Game = world["game"]
	var home: City = world["home"]
	var second: City = world["second"]
	for city in [home, second]:
		var tile := game.state.map.grid.neighbors(city.tile)[0]
		city.districts.append({"type": "THEATER_SQUARE", "tile": tile, "tier": 2,
			"buildings": [], "complete": true, "cost": 150.0})
		game.state.map.district[tile] = "THEATER_SQUARE"
	home.great_works = 2
	home.great_work_types.assign(["WRITING", "MUSIC"])
	game.state.map.pillaged[int(home.districts[0]["tile"])] = 1
	check_near(CultureRules.work_tourism(game, home), 0.0)
	var moved := game.apply_action({"type": "move_great_work", "city": home.id,
		"target_city": second.id, "index": 1})
	check(moved.any(func(event): return event["type"] == "great_work_moved"))
	check_eq(home.great_work_types, ["WRITING"])
	check_eq(second.great_work_types, ["MUSIC"])
	check_near(CultureRules.work_tourism(game, second), 6.0)
	check_eq(game.apply_action({"type": "move_great_work", "city": home.id,
		"target_city": world["rival"].id, "index": 0})[0]["type"], "error")
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.city(second.id).great_work_types, ["MUSIC"])


func test_ai_uses_naturalist_and_rock_band_actions() -> void:
	var world := _world()
	var game: Game = world["game"]
	var city: City = world["home"]
	var rival: City = world["rival"]
	for tile in game.state.map.grid.tiles_in_radius(city.tile, 3):
		game.state.map.owner_city[tile] = city.id
	var stand := game.state.map.grid.index_of(8, 7)
	game.state.player(0).known_civics["CONSERVATION"] = true
	game.state.player(0).faith = 500.0
	AIPlayer._culture_recruits(game, 0)
	var naturalist: Unit = null
	for candidate in game.state.units_of(0):
		if candidate.type == "NATURALIST":
			naturalist = candidate
	check(naturalist != null)
	if naturalist == null:
		return
	naturalist.tile = stand
	naturalist.moves_left = 2.0
	AIPlayer._handle_naturalist(game, naturalist)
	check_eq(city.parks.size(), 1)
	var band := game.state.add_unit(0, "ROCK_BAND", rival.tile)
	band.moves_left = 2.0
	band.charges = 3
	AIPlayer._handle_rock_band(game, band)
	check_near(float(game.state.player(0).tourism_points.get("1", 0)), 250.0)
