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
	check_eq(_offer(g, "alliance")[0]["type"], "treaty_proposed")
