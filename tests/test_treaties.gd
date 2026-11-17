extends TestCase


func _setup() -> Game:
	var g := blank_game()
	for pid in 2:
		var p := g.state.player(pid)
		p.met[1 - pid] = true
		p.is_ai = false
		p.revealed.fill(Player.FOG_REVEALED)
	return g


func _offer(g: Game, kind: String) -> Array:
	g.state.current_player = 0
	return g.apply_action({"type": "propose_treaty", "kind": kind, "target": 1})


func _accept(g: Game, kind: String) -> Array:
	g.state.current_player = 1
	return g.apply_action({"type": "respond_treaty", "offer": kind + ":0:1", "accept": true})


func test_alliance_requires_friendship_and_war_removes_access() -> void:
	var g := _setup()
	check_eq(_offer(g, "alliance")[0]["type"], "error")
	check_eq(_offer(g, "friendship")[0]["type"], "treaty_proposed")
	check_eq(g.apply_action({"type": "respond_treaty", "offer": "friendship:0:1", "accept": true})[0]["type"], "error")
	check_eq(_accept(g, "friendship")[0]["type"], "treaty_accepted")
	for _i in 5:
		TreatyRules.close_round(g)
		DiplomacyRules.close_round(g, [])
		g.state.turn += 1
	check_near(float(DiplomacyRules.influence(g, 0)["sources"]["relations"]), 40.0)
	check_eq(_offer(g, "alliance")[0]["type"], "error", "Союзы открывает Гражданская служба")
	g.state.player(0).known_civics["CIVIL_SERVICE"] = true
	check_eq(_offer(g, "alliance")[0]["type"], "treaty_proposed")
	check_eq(_accept(g, "alliance")[0]["type"], "treaty_accepted")
	check_eq(TreatyRules.until(g, "friendship", 0, 1), 0)
	check_eq(TreatyRules.until(g, "alliance", 1, 0), 26)
	var saved := g.state.to_json()
	check_eq(GameState.from_json(saved, g.data).to_json(), saved)
	g.state.current_player = 0
	var events := g.apply_action({"type": "declare_war", "target": 1})
	check(events.any(func(event): return event["type"] == "treaty_broken"))
	check_eq(TreatyRules.until(g, "alliance", 0, 1), 0)
	check_eq(TreatyRules.trust(g, 1, 0), -25)
	check_eq(TreatyRules.trust(g, 0, 1), 0)


func test_alliance_levels_renewal_influence_and_visibility_four() -> void:
	var g := _setup()
	_offer(g, "friendship")
	_accept(g, "friendship")
	g.state.turn = 6
	g.state.player(0).known_civics["CIVIL_SERVICE"] = true
	_offer(g, "alliance")
	_accept(g, "alliance")
	check_eq(TreatyRules.alliance_level(g, 0, 1), 1)
	var own := CityRules.found_city(g, 0, g.state.map.grid.index_of(5, 6))
	var rival := CityRules.found_city(g, 1, g.state.map.grid.index_of(13, 6))
	var trader := g.state.add_unit(0, "TRADER", own.tile)
	trader.trade_route = {"origin": own.id, "destination": rival.id}
	g.state.player(0).known_techs["PRINTING"] = true
	g.state.player(0).treasury = 30.0
	g.state.current_player = 0
	g.apply_action({"type": "send_delegation", "target": 1})
	check_eq(DiplomaticVisibility.level(g, 0, 1), 3)
	g.state.turn = 13
	var events: Array = []
	TreatyRules.close_round(g, events)
	check(events.any(func(event): return event["type"] == "alliance_leveled" and event["level"] == 2))
	g.state.turn = 14
	check_eq(TreatyRules.alliance_level(g, 0, 1), 2)
	check_eq(DiplomaticVisibility.level(g, 0, 1), 3)
	g.state.turn = 21
	check_eq(_offer(g, "alliance")[0]["type"], "treaty_proposed")
	check_eq(_accept(g, "alliance")[0]["type"], "treaty_accepted")
	check_eq(TreatyRules.until(g, "alliance", 0, 1), 46)
	events.clear()
	TreatyRules.close_round(g, events)
	check(events.any(func(event): return event["type"] == "alliance_leveled" and event["level"] == 3))
	g.state.turn = 22
	check_eq(TreatyRules.alliance_level(g, 0, 1), 3)
	check_eq(DiplomaticVisibility.level(g, 0, 1), 4)
	g.state.treaty_data["history"]["friendship:0:1"] = [
		{"turn": 22, "kind": "alliance", "level": 3}]
	check_near(TreatyRules.influence_strength(g, 0, 1), 0.3)
	trader.trade_route = {}
	check_eq(DiplomaticVisibility.level(g, 0, 1), 3)
	g.state.turn = 46
	check_eq(TreatyRules.alliance_level(g, 0, 1), 0)
	check_eq(DiplomaticVisibility.level(g, 0, 1), 2)


func test_alliance_specializations_effects_and_renewal() -> void:
	var g := _setup()
	_offer(g, "friendship")
	_accept(g, "friendship")
	g.state.turn = 6
	g.state.player(0).known_civics["CIVIL_SERVICE"] = true
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "propose_treaty", "kind": "alliance", "target": 1,
		"specialization": "unknown"})[0]["type"], "error")
	check_eq(g.state.treaty_data["offers"].size(), 0)
	check_eq(g.apply_action({"type": "propose_treaty", "kind": "alliance", "target": 1,
		"specialization": "economic"})[0]["type"], "treaty_proposed")
	check_eq(_accept(g, "alliance")[0]["specialization"], "economic")
	check_eq(TreatyRules.alliance_specialization(g, 0, 1), "economic")
	var own := CityRules.found_city(g, 0, g.state.map.grid.index_of(5, 6))
	var rival := CityRules.found_city(g, 1, g.state.map.grid.index_of(13, 6))
	var route := {"origin": own.id, "destination": rival.id, "path": [own.tile, rival.tile]}
	check_near(float(TradeRules.route_yields(g, route)["gold"]), 5.0)
	g.state.turn = 14
	check_near(float(TradeRules.route_yields(g, route)["gold"]), 7.0)
	g.state.turn = 21
	check_eq(g.apply_action({"type": "propose_treaty", "kind": "alliance", "target": 1,
		"specialization": "science"})[0]["type"], "error")
	check_eq(_offer(g, "alliance")[0]["type"], "treaty_proposed")
	_accept(g, "alliance")
	check_eq(TreatyRules.alliance_specialization(g, 0, 1), "economic")
	check_eq(GameState.from_json(g.state.to_json(), g.data).treaty_data["active"]["alliance:0:1"]["specialization"], "economic")
	g.state.turn = 22
	check_near(float(TradeRules.route_yields(g, route)["gold"]), 9.0)
	for specialization in ["science", "religious", "culture"]:
		g.state.treaty_data["active"]["alliance:0:1"]["specialization"] = specialization
		if specialization == "culture":
			check_near(CultureRules.pair_multiplier(g, 0, 1),
				1.0 + float(g.data.culture_setup["open_borders_bonus"]) + 0.30)
		else:
			var yield_name := "science" if specialization == "science" else "faith"
			check_near(float(TradeRules.route_yields(g, route).get(yield_name, 0.0)), 3.0)
	g.state.treaty_data["active"]["alliance:0:1"]["specialization"] = "military"
	check_eq(TreatyRules.shared_enemy_bonus(g, 0, 1), 0)
	g.state.turn = 46
	check_eq(TreatyRules.alliance_specialization(g, 0, 1), "")
	check_near(float(TradeRules.route_yields(g, route)["gold"]), 3.0)


func test_military_alliance_requires_shared_enemy() -> void:
	var g := blank_game(20, 12, 3)
	g.state.treaty_data["active"]["alliance:0:1"] = {"kind": "alliance", "from": 0, "to": 1,
		"since": 0, "until": 30, "specialization": "military"}
	g.state.turn = 16
	g.state.set_war(0, 2, true)
	var attacker := g.state.add_unit(0, "WARRIOR", g.state.map.grid.index_of(5, 6))
	var defender := g.state.add_unit(2, "WARRIOR", g.state.map.grid.index_of(6, 6))
	var before := Combat.preview(g, attacker, defender.tile)
	check_eq(TreatyRules.shared_enemy_bonus(g, 0, 2), 0)
	g.state.set_war(1, 2, true)
	var after := Combat.preview(g, attacker, defender.tile)
	check_eq(TreatyRules.shared_enemy_bonus(g, 0, 2), 4)
	check_eq(int(after["att"]) - int(before["att"]), 4)
	g.state.treaty_data["active"].erase("alliance:0:1")
	check_eq(TreatyRules.shared_enemy_bonus(g, 0, 2), 0)


func test_passage_is_one_way_and_expiry_relocates_unit() -> void:
	var g := _setup()
	var grid := g.state.map.grid
	var own := CityRules.found_city(g, 0, grid.index_of(4, 6))
	var host := CityRules.found_city(g, 1, grid.index_of(12, 6))
	var outside := grid.index_of(10, 6)
	var inside := grid.index_of(11, 6)
	var visitor := g.state.add_unit(0, "WARRIOR", outside)
	visitor.moves_left = 2.0
	var other := g.state.add_unit(1, "WARRIOR", grid.index_of(6, 6))
	other.moves_left = 2.0
	check(Pathfinder.find_path(g, visitor, inside).is_empty())
	_offer(g, "passage")
	_accept(g, "passage")
	check(Pathfinder.find_path(g, other, own.tile).is_empty())
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "move_unit", "unit": visitor.id, "target": inside})[0]["type"], "unit_moved")
	check_eq(visitor.tile, inside)
	g.state.turn = 11
	TreatyRules.process_withdrawal(g, 0, [])
	check(TreatyRules.withdrawing(g, visitor))
	check(not Combat.can_attack(g, visitor))
	check_eq(g.apply_action({"type": "fortify", "unit": visitor.id})[0]["type"], "error")
	check(TreatyRules.border_allows(g, visitor, inside, outside))
	check(not TreatyRules.border_allows(g, visitor, outside, inside))
	g.state.turn = 13
	TreatyRules.process_withdrawal(g, 0, [])
	check_eq(visitor.tile, inside)
	g.state.turn = 14
	var events: Array = []
	TreatyRules.process_withdrawal(g, 0, events)
	check(events.any(func(event): return event["type"] == "unit_relocated"))
	check(not TreatyRules.withdrawing(g, visitor))
	check_eq(grid.distance(visitor.tile, inside), 1)
	check_eq(g.state.map.owner_city[inside], host.id)


func test_renewal_preserves_friendship_age_and_decline_delays_offer() -> void:
	var g := _setup()
	var offered := _offer(g, "friendship")
	check_eq(offered[0]["type"], "treaty_proposed")
	g.state.current_player = 1
	check_eq(g.apply_action({"type": "respond_treaty", "offer": "friendship:0:1", "accept": false})[0]["type"], "treaty_declined")
	check_eq(_offer(g, "friendship")[0]["type"], "error")
	g.state.turn = 6
	_offer(g, "friendship")
	_accept(g, "friendship")
	g.state.turn = 21
	_offer(g, "friendship")
	_accept(g, "friendship")
	check_eq(TreatyRules.until(g, "friendship", 0, 1), 46)
	g.state.player(0).known_civics["CIVIL_SERVICE"] = true
	check_eq(_offer(g, "alliance")[0]["type"], "treaty_proposed")
