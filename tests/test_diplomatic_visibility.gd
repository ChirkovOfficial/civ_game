extends TestCase


func _world() -> Dictionary:
	var game := blank_game(24, 14, 2)
	var own := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	var rival := CityRules.found_city(game, 1, game.state.map.grid.index_of(15, 6))
	game.state.player(0).met[1] = true
	game.state.player(1).met[0] = true
	return {"game": game, "own": own, "rival": rival}


func test_delegations_embassy_war_and_save() -> void:
	var world := _world()
	var game: Game = world["game"]
	check_eq(DiplomaticVisibility.level(game, 0, 1), 0)
	game.state.player(0).treasury = 20.0
	check_eq(game.apply_action({"type": "send_delegation", "target": 1})[0]["type"], "error")
	game.state.player(0).treasury = 50.0
	check_eq(game.apply_action({"type": "send_delegation", "target": 1})[0]["type"], "delegation_sent")
	check_near(game.state.player(0).treasury, 25.0)
	check_eq(DiplomaticVisibility.level(game, 0, 1), 1)
	check_eq(DiplomaticVisibility.level(game, 1, 0), 0)
	check_eq(game.apply_action({"type": "send_delegation", "target": 1})[0]["type"], "error")
	game.state.current_player = 1
	game.state.player(1).treasury = 50.0
	game.apply_action({"type": "send_delegation", "target": 0})
	check(DiplomaticVisibility.embassy_error(game, 1, 0).contains("Дипломатическая служба"))
	game.state.player(0).known_civics["DIPLOMATIC_SERVICE"] = true
	game.state.player(1).known_civics["DIPLOMATIC_SERVICE"] = true
	check_eq(game.apply_action({"type": "establish_embassy", "target": 0})[0]["type"], "embassies_opened")
	check_eq(DiplomaticVisibility.level(game, 0, 1), 1)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.visibility_data, game.state.visibility_data)
	var old := game.state.to_dict()
	old["version"] = 15
	old.erase("diplomatic_visibility")
	check_eq(GameState.from_dict(old, game.data).visibility_data["delegations"], {})
	game.declare_war(1, 0, [])
	check_eq(DiplomaticVisibility.level(game, 0, 1), 0)
	check(not DiplomaticVisibility.has_embassy(game, 0, 1))
	check(not DiplomaticVisibility.has_delegation(game, 0, 1))


func test_routes_alliance_printing_and_finance_disclosure_level() -> void:
	var world := _world()
	var game: Game = world["game"]
	var own: City = world["own"]
	var rival: City = world["rival"]
	var trader := game.state.add_unit(0, "TRADER", own.tile)
	trader.trade_route = {"origin": own.id, "destination": rival.id}
	check_eq(DiplomaticVisibility.level(game, 0, 1), 1)
	check_eq(DiplomaticVisibility.level(game, 1, 0), 0)
	game.state.treaty_data["active"]["alliance:0:1"] = {"until": game.state.turn + 5}
	check_eq(DiplomaticVisibility.level(game, 0, 1), 2)
	check_eq(DiplomaticVisibility.level(game, 1, 0), 1)
	check(DiplomaticVisibility.level(game, 0, 1) >= int(game.data.visibility_setup["finance_exact_level"]))
	game.state.player(0).known_techs["PRINTING"] = true
	check_eq(DiplomaticVisibility.level(game, 0, 1), 3)
	game.state.player(0).treasury = 50.0
	game.state.current_player = 0
	game.apply_action({"type": "send_delegation", "target": 1})
	check_eq(DiplomaticVisibility.level(game, 0, 1), 3)
	trader.trade_route = {}
	check_eq(DiplomaticVisibility.level(game, 0, 1), 3)
	game.state.treaty_data["active"].clear()
	check_eq(DiplomaticVisibility.level(game, 0, 1), 2)


func test_combat_bonus_uses_visibility_difference() -> void:
	var world := _world()
	var game: Game = world["game"]
	var attacker := game.state.add_unit(0, "WARRIOR", game.state.map.grid.index_of(7, 6))
	var defender := game.state.add_unit(1, "WARRIOR", game.state.map.grid.index_of(8, 6))
	game.state.set_war(0, 1, true)
	var baseline := Combat.preview(game, attacker, defender.tile)
	game.state.player(0).known_techs["PRINTING"] = true
	var advanced := Combat.preview(game, attacker, defender.tile)
	check_eq(int(advanced["att"]) - int(baseline["att"]), 3)
	check(advanced["att_mods"].any(func(modifier): return modifier[0] == "Дипломатическая видимость"))
	game.state.player(1).known_techs["PRINTING"] = true
	var equal := Combat.preview(game, attacker, defender.tile)
	check_eq(int(equal["att"]), int(baseline["att"]))
	game.state.player(1).known_techs.erase("PRINTING")
	game.state.player(0).known_techs.erase("PRINTING")
	var rival_city: City = world["rival"]
	var city_baseline := Combat.preview(game, attacker, rival_city.tile)
	game.state.player(1).known_techs["PRINTING"] = true
	var city_advanced := Combat.preview(game, attacker, rival_city.tile)
	check_eq(int(city_advanced["def"]) - int(city_baseline["def"]), 3)


func test_representation_trust_and_hidden_plans() -> void:
	var world := _world()
	var game: Game = world["game"]
	var own: City = world["own"]
	var rival: City = world["rival"]
	game.state.player(1).current_tech = "PRINTING"
	game.state.player(1).current_civic = "CIVIL_SERVICE"
	rival.queue = [{"kind": "unit", "id": "WARRIOR"}]
	check(DiplomaticVisibility.disclosed_plans(game, 0, 1).is_empty())
	check_eq(TreatyRules.trust(game, 0, 1), 0)
	game.state.player(0).treasury = 50.0
	game.apply_action({"type": "send_delegation", "target": 1})
	check_eq(TreatyRules.trust(game, 0, 1), 5)
	check_eq(TreatyRules.trust(game, 1, 0), 0)
	var trader := game.state.add_unit(0, "TRADER", own.tile)
	trader.trade_route = {"origin": own.id, "destination": rival.id}
	game.state.player(0).known_techs["PRINTING"] = true
	check_eq(DiplomaticVisibility.disclosed_plans(game, 0, 1)["tech"], "PRINTING")
	check_eq(DiplomaticVisibility.disclosed_plans(game, 0, 1)["civic"], "CIVIL_SERVICE")
	check(not DiplomaticVisibility.disclosed_plans(game, 0, 1).has("production"))
	game.state.treaty_data["active"]["alliance:0:1"] = {"kind": "alliance", "from": 0, "to": 1,
		"since": game.state.turn - 16, "until": game.state.turn + 5, "specialization": "science"}
	check_eq(DiplomaticVisibility.level(game, 0, 1), 4)
	check_eq(DiplomaticVisibility.disclosed_plans(game, 0, 1)["production"][rival.id]["id"], "WARRIOR")
	trader.trade_route = {}
	check(not DiplomaticVisibility.disclosed_plans(game, 0, 1).has("production"))
	game.declare_war(0, 1, [])
	check_eq(TreatyRules.trust(game, 0, 1), 0)
	check_eq(TreatyRules.trust(game, 1, 0), -25)
	check(not DiplomaticVisibility.disclosed_plans(game, 0, 1).has("production"))
