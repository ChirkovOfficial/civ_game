extends TestCase
## Посадка и высадка сухопутных юнитов без каналов.


func test_unlocks_coast_ocean_and_embarked_speed() -> void:
	var g := blank_game()
	var start := g.state.map.grid.index_of(5, 6)
	var coast := g.state.map.grid.neighbor(start, 0)
	var ocean := g.state.map.grid.neighbor(coast, 0)
	g.state.map.terrain[coast] = "COAST"
	g.state.map.terrain[ocean] = "OCEAN"
	var warrior := g.state.add_unit(0, "WARRIOR", start)
	var builder := g.state.add_unit(0, "BUILDER", start)
	var player := g.state.player(0)
	check(not Movement.can_stand(g, warrior, coast))
	check(not Movement.can_stand(g, builder, coast))
	player.known_techs["SAILING"] = true
	check(Movement.can_stand(g, builder, coast))
	check(not Movement.can_stand(g, warrior, coast))
	player.known_techs["CELESTIAL_NAVIGATION"] = true
	check(Movement.can_stand(g, warrior, coast))
	check(not Movement.can_stand(g, warrior, ocean))
	check_near(Movement.moves_after_step(g, warrior, start, coast, 2.0), 0.0)
	warrior.tile = coast
	check_near(Movement.max_moves(g, warrior), 2.0)
	player.known_techs["CARTOGRAPHY"] = true
	check(Movement.can_stand(g, warrior, ocean))
	player.known_techs["STEAM_POWER"] = true
	check_near(Movement.max_moves(g, warrior), 4.0)
	check_near(Movement.moves_after_step(g, warrior, coast, ocean, 4.0), 3.0)
	check_near(Movement.max_moves_at(g, warrior, start), 2.0)


func test_city_and_harbor_crossings_preserve_moves() -> void:
	var g := blank_game()
	var start := g.state.map.grid.index_of(5, 6)
	var coast := g.state.map.grid.neighbor(start, 0)
	var harbor := g.state.map.grid.neighbor(coast, 0)
	g.state.map.terrain[coast] = "COAST"
	g.state.map.terrain[harbor] = "COAST"
	var warrior := g.state.add_unit(0, "WARRIOR", start)
	g.state.player(0).known_techs["CELESTIAL_NAVIGATION"] = true
	check_eq(Movement.step_cost(g, warrior, start, coast), Movement.ALL_MOVES)
	var city := CityRules.found_city(g, 0, start)
	check_near(Movement.step_cost(g, warrior, start, coast), 1.0)
	check_near(Movement.moves_after_step(g, warrior, start, coast, 2.0), 1.0)
	warrior.tile = coast
	check_near(Movement.step_cost(g, warrior, coast, start), 1.0)
	city.districts.append({"type": "HARBOR", "tile": harbor, "tier": 1,
		"buildings": [], "complete": true, "cost": 0.0})
	g.state.map.owner_city[harbor] = city.id
	var shore := g.state.map.grid.neighbor(harbor, 0)
	check(g.state.map.is_land(shore))
	check_near(Movement.step_cost(g, warrior, harbor, shore), 1.0)
	g.state.map.pillaged[harbor] = 1
	check_eq(Movement.step_cost(g, warrior, harbor, shore), Movement.ALL_MOVES)


func test_builder_sails_to_fish_and_builds_boats() -> void:
	var g := blank_game()
	var start := g.state.map.grid.index_of(5, 6)
	var coast := g.state.map.grid.neighbor(start, 0)
	g.state.map.terrain[coast] = "COAST"
	g.state.map.resource[coast] = "FISH"
	var city := CityRules.found_city(g, 0, start)
	check_eq(g.state.map.owner_city[coast], city.id)
	var builder := g.state.add_unit(0, "BUILDER", start)
	builder.charges = 3
	builder.moves_left = 2.0
	g.state.player(0).known_techs["SAILING"] = true
	Visibility.recompute(g, 0)
	var moved := g.apply_action({"type": "move_unit", "unit": builder.id, "target": coast})
	check(not moved.is_empty())
	check_eq(builder.tile, coast)
	check_near(builder.moves_left, 1.0)
	check_eq(ImprovementRules.build_error(g, builder, "FISHING_BOATS"), "")
	g.apply_action({"type": "build_improvement", "unit": builder.id, "improvement": "FISHING_BOATS"})
	check_eq(g.state.map.improvement[coast], "FISHING_BOATS")


func test_pathfinder_crosses_sea_and_orders_survive_save() -> void:
	var g := blank_game(16, 8)
	g.state.map.terrain.fill("COAST")
	var start := g.state.map.grid.index_of(3, 4)
	var target := g.state.map.grid.index_of(7, 4)
	g.state.map.terrain[start] = "GRASS"
	g.state.map.terrain[target] = "GRASS"
	var warrior := g.state.add_unit(0, "WARRIOR", start)
	warrior.moves_left = 2.0
	var player := g.state.player(0)
	player.revealed.fill(Player.FOG_REVEALED)
	check(Pathfinder.find_path(g, warrior, target).is_empty())
	player.known_techs["CELESTIAL_NAVIGATION"] = true
	var path := Pathfinder.find_path(g, warrior, target)
	check(not path.is_empty())
	check(path[-1].turn > 0)
	g.apply_action({"type": "move_unit", "unit": warrior.id, "target": target})
	check(Movement.is_embarked(g, warrior))
	check_eq(warrior.orders.get("target", -1), target)
	var loaded := SaveLoad.from_dict(g.data, g.state.to_dict())
	var restored := loaded.state.unit(warrior.id)
	check(Movement.is_embarked(loaded, restored))
	check_eq(restored.orders.get("target", -1), target)
	for i in 8:
		if restored.tile == target:
			break
		loaded.apply_action({"type": "end_turn", "force": true})
	check_eq(restored.tile, target)
	check(restored.orders.is_empty())


func test_embarked_defense_and_landing_attack() -> void:
	var g := blank_game()
	var coast := g.state.map.grid.index_of(6, 6)
	g.state.map.terrain[coast] = "COAST"
	var shore := g.state.map.grid.neighbor(coast, 0)
	var other_water := g.state.map.grid.neighbor(coast, 1)
	g.state.map.terrain[other_water] = "COAST"
	var warrior := g.state.add_unit(0, "WARRIOR", coast)
	warrior.moves_left = 2.0
	g.state.player(0).known_techs["CELESTIAL_NAVIGATION"] = true
	var galley := g.state.add_unit(1, "GALLEY", other_water)
	galley.moves_left = 3.0
	g.state.set_war(0, 1, true)
	check_eq(Combat.preview(g, galley, coast)["def"], 15)
	check(Combat.attack_error(g, warrior, other_water) != "")
	var enemy := g.state.add_unit(1, "WARRIOR", shore)
	var landing := Combat.preview(g, warrior, shore)
	check(landing["att_mods"].has(["Высадка с моря", -10]))
	check_eq(Combat.attack_error(g, warrior, shore), "")
	check(UnitRules.fortify_error(g, warrior) != "")


func test_ai_explorer_chooses_coast_after_unlock() -> void:
	var g := blank_game()
	g.state.map.terrain.fill("COAST")
	var start := g.state.map.grid.index_of(8, 6)
	g.state.map.terrain[start] = "GRASS"
	var scout := g.state.add_unit(0, "SCOUT", start)
	g.state.player(0).known_techs["CELESTIAL_NAVIGATION"] = true
	Visibility.recompute(g, 0)
	var target := AIPlayer._explore_target(g, scout)
	check(target >= 0)
	if target >= 0:
		check(g.state.map.is_water(target))
		check(not Pathfinder.find_path(g, scout, target).is_empty())
