extends TestCase


func _district(game: Game, city: City, type: String, tier: int, tile: int) -> Dictionary:
	var district := {"type": type, "tile": tile, "tier": tier, "buildings": [],
		"complete": true, "cost": 100.0}
	city.districts.append(district)
	game.state.map.district[tile] = type
	return district


func test_fuel_regional_power_blackout_and_save() -> void:
	var game := blank_game(30, 14, 2)
	var grid := game.state.map.grid
	var source := CityRules.found_city(game, 0, grid.index_of(6, 6))
	var client := CityRules.found_city(game, 0, grid.index_of(12, 6))
	var plant_tile := grid.index_of(7, 6)
	var campus_tile := grid.index_of(13, 6)
	var plant := _district(game, source, "INDUSTRIAL_ZONE", 4, plant_tile)
	_district(game, client, "CAMPUS", 3, campus_tile)
	var player := game.state.player(0)
	plant["tier"] = 3
	check(CityRules.build_error(game, source, {"kind": "district_upgrade", "id": "INDUSTRIAL_ZONE",
		"tile": plant_tile}).begins_with("Нужно"))
	player.known_techs["INDUSTRIALIZATION"] = true
	check_eq(CityRules.build_error(game, source, {"kind": "district_upgrade", "id": "INDUSTRIAL_ZONE",
		"tile": plant_tile}), "")
	plant["tier"] = 4
	player.stockpile["COAL"] = 2.0
	var events: Array = []
	EnergyRules.process_turn(game, 0, events)
	check_eq(int(EnergyRules.report(game, source)["supplied"]), 3)
	check_eq(int(EnergyRules.report(game, client)["supplied"]), 3)
	check_eq(int(game.state.energy_data["0"]["burn"]["COAL"]), 2)
	check_near(float(player.stockpile["COAL"]), 0.0)
	check(DiplomacyRules._resource_need(game, 0, "COAL", game.state.turn) > 0.0)
	check_eq(int(DistrictRules.output(game, client, client.districts[0])["yields"]["science"]), 16)
	check_eq(GameState.from_json(game.state.to_json(), game.data).energy_data, game.state.energy_data)
	var old := game.state.to_dict()
	old["version"] = 16
	old.erase("energy")
	check(GameState.from_dict(old, game.data).energy_data.is_empty())
	game.state.turn += 1
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, client)["supplied"]), 0)
	check_eq(int(DistrictRules.output(game, client, client.districts[0])["yields"]["science"]), 11)
	plant["tier"] = 5
	player.stockpile["OIL"] = 2.0
	game.state.turn += 1
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, client)["supplied"]), 3)
	check_eq(int(game.state.energy_data["0"]["burn"]["OIL"]), 2)
	game.state.map.pillaged[plant_tile] = 1
	game.state.turn += 1
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, client)["supplied"]), 0)


func test_hydro_and_renewable_power_without_fuel() -> void:
	var game := blank_game(24, 14, 2)
	var grid := game.state.map.grid
	var city := CityRules.found_city(game, 0, grid.index_of(7, 6))
	var campus_tile := grid.index_of(8, 6)
	var dam_tile := grid.index_of(7, 7)
	_district(game, city, "CAMPUS", 3, campus_tile)
	_district(game, city, "DAM", 2, dam_tile)
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, city)["renewable"]), 6)
	check_eq(int(EnergyRules.report(game, city)["supplied"]), 3)
	check_eq(game.state.energy_data["0"]["burn"], {})
	game.state.map.pillaged[dam_tile] = 1
	var wind_tile := grid.index_of(6, 6)
	game.state.map.relief[wind_tile] = GameMap.RELIEF_HILLS
	game.state.map.improvement[wind_tile] = "WIND_FARM"
	game.state.turn += 1
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, city)["renewable"]), 3)
	check_eq(int(EnergyRules.report(game, city)["supplied"]), 3)
	game.state.map.pillaged[wind_tile] = 1
	game.state.turn += 1
	EnergyRules.process_turn(game, 0, [])
	check_eq(int(EnergyRules.report(game, city)["supplied"]), 0)


func test_ai_values_wind_farm_for_power_shortage() -> void:
	var game := blank_game(20, 12, 2)
	var city := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	_district(game, city, "CAMPUS", 3, game.state.map.grid.index_of(7, 6))
	var tile := game.state.map.grid.index_of(6, 7)
	game.state.map.relief[tile] = GameMap.RELIEF_HILLS
	game.state.player(0).known_techs["ELECTRICITY"] = true
	game.state.player(0).known_techs["MINING"] = true
	var builder := game.state.add_unit(0, "BUILDER", tile)
	builder.charges = 3
	check_eq(AIPlayer._improvement_gain(game, builder, tile)[0], "WIND_FARM")


func test_turn_start_spends_fuel_before_powered_income() -> void:
	var game := blank_game(20, 12, 2)
	var city := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	_district(game, city, "INDUSTRIAL_ZONE", 4, game.state.map.grid.index_of(7, 6))
	_district(game, city, "CAMPUS", 3, game.state.map.grid.index_of(6, 7))
	game.state.player(0).stockpile["COAL"] = 2.0
	EmpireRules.process_turn_start(game, 0, [])
	check_eq(int(game.state.energy_data["0"]["turn"]), game.state.turn)
	check_eq(int(EnergyRules.report(game, city)["supplied"]), 6)
	check_near(float(game.state.player(0).stockpile["COAL"]), 0.0)
	check(float(EmpireRules.summary(game, 0)["yields"]["science"]) > 15.0)
