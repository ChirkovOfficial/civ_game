extends TestCase


func _world() -> Game:
	var g := blank_game(32, 14, 3)
	var grid := g.state.map.grid
	for pid in 3:
		g.state.player(pid).is_ai = false
		g.state.player(pid).revealed.fill(Player.FOG_REVEALED)
		for peer in 3:
			if pid != peer:
				g.state.player(pid).met[peer] = true
		CityRules.found_city(g, pid, grid.index_of(4 + pid * 8, 5))
	DiplomacyRules.initialize(g)
	g.state.diplomacy["dependency"]["1,0"] = {"strategic": 53.0}
	return g


func _ask(g: Game, kind: String, subject: int) -> Dictionary:
	g.state.current_player = 0
	return g.apply_action({"type": "issue_demand", "kind": kind, "target": 1, "offer": subject})[0]


func _accept(g: Game, demand: Dictionary) -> Array:
	g.state.current_player = 1
	return g.apply_action({"type": "respond_demand", "pair": "0,1", "id": demand.get("id", -1), "accept": true})


func test_joint_war_respects_threshold_and_truce_then_uses_war_rules() -> void:
	var g := _world()
	g.state.set_war(0, 2, true)
	g.state.diplomacy["dependency"]["1,0"]["strategic"] = 50.0
	check_eq(_ask(g, "joint_war", 2)["type"], "error")
	g.state.diplomacy["dependency"]["1,0"]["strategic"] = 50.1
	g.state.set_war(1, 2, false)
	check_eq(_ask(g, "joint_war", 2)["type"], "error")
	g.state.turn += 10
	var issued := _ask(g, "joint_war", 2)
	check_eq(issued["type"], "demand_issued")
	check(not g.state.at_war(1, 2))
	check(_accept(g, issued).any(func(e): return e["type"] == "war_declared" and e["player"] == 1))
	check(g.state.at_war(1, 2))
	check(not g.state.at_war(0, 1))


func _camp(g: Game) -> int:
	var grid := g.state.map.grid
	var a := g.state.cities_of(0)[0]
	var b := g.state.cities_of(1)[0]
	CityRules.claim_tile(g, a, grid.index_of(8, 5))
	CityRules.claim_tile(g, b, grid.index_of(9, 5))
	var tile := grid.index_of(9, 6)
	g.state.camps[tile] = {"tile": tile}
	g.state.map.improvement[tile] = "BARBARIAN_CAMP"
	return tile


func test_camp_obligation_distinguishes_fulfillment_and_third_party() -> void:
	for by in [1, 2]:
		var g := _world()
		var tile := _camp(g)
		var issued := _ask(g, "clear_camp", tile)
		check_eq(issued["type"], "demand_issued")
		_accept(g, issued)
		check_eq(DemandRules.obligations_for(g, 1).size(), 1)
		var unit := g.state.add_unit(by, "WARRIOR", tile)
		var events: Array = []
		Barbarians.on_enter(g, unit, events)
		var result := "obligation_fulfilled" if by == 1 else "obligation_excused"
		check(events.any(func(e): return e["type"] == result))
		check(DemandRules.obligations_for(g, 1).is_empty())
		check_eq(TreatyRules.trust(g, 0, 1), 0)


func test_camp_obligation_missed_deadline_penalizes_recipient() -> void:
	var g := _world()
	var issued := _ask(g, "clear_camp", _camp(g))
	_accept(g, issued)
	var events: Array = []
	g.state.turn = 10
	DemandRules.close_round(g, events)
	g.state.turn = 11
	check(events.any(func(e): return e["type"] == "obligation_breached"))
	check_eq(TreatyRules.trust(g, 0, 1), -15)


func test_loan_returns_same_unit_and_cannot_be_reassigned() -> void:
	var g := _world()
	var tile := g.state.map.grid.index_of(7, 8)
	var unit := g.state.add_unit(1, "WARRIOR", tile)
	g.state.player(0).visible_count[tile] = 1
	check_eq(_ask(g, "reinforcement", unit.id)["type"], "error")
	for i in 4:
		g.state.add_unit(1, "WARRIOR", g.state.map.grid.index_of(10 + i, 8))
	var issued := _ask(g, "reinforcement", unit.id)
	check_eq(issued["type"], "demand_issued")
	var events := _accept(g, issued)
	check(events.any(func(e): return e["type"] == "reinforcement_lent"))
	check_eq(unit.owner, 0)
	check_eq(ConcessionRules.legal_owner(g, unit), 1)
	check_eq(g.state.units.size(), 5)
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "upgrade_unit", "unit": unit.id})[0]["type"], "error")
	var save := GameState.from_json(g.state.to_json(), g.data)
	check_eq(save.demand_data["loans"], g.state.demand_data["loans"])
	ConcessionRules.update_loans(g, 11, [])
	check_eq(unit.owner, 1)
	check_eq(unit.tile, tile)
	check_eq(g.state.units.size(), 5)


func test_city_concession_preserves_city_and_caps_dependency() -> void:
	var g := _world()
	var grid := g.state.map.grid
	var city := CityRules.found_city(g, 1, grid.index_of(7, 5))
	CityRules.claim_tile(g, city, grid.index_of(6, 5))
	city.population = 4
	city.hp = 180
	city.buildings.append("MONUMENT")
	city.progress["building:GRANARY"] = 20.0
	var guard := g.state.add_unit(1, "WARRIOR", city.tile)
	check_eq(_ask(g, "concede_city", city.id)["type"], "error")
	g.state.diplomacy["dependency"]["1,0"] = {"strategic": 60.0, "goods": 15.0, "religion": 25.0, "target": 100.0}
	check_eq(_ask(g, "concede_city", g.state.cities_of(1)[0].id)["type"], "error")
	var issued := _ask(g, "concede_city", city.id)
	check_eq(issued["type"], "demand_issued")
	check(_accept(g, issued).any(func(e): return e["type"] == "city_conceded"))
	check_eq(city.owner, 0)
	check_eq(city.population, 4)
	check_eq(city.hp, 180)
	check(city.has_building("MONUMENT"))
	check_near(city.progress["building:GRANARY"], 20.0)
	check_eq(guard.owner, 1)
	check_eq(TreatyRules.trust(g, 1, 0), -40)
	check_near(DiplomacyRules.dependency_value(DiplomacyRules.dependency(g, 1, 0)), 50.0)
	check(ConcessionRules.concession_active(g, 1, 0))
