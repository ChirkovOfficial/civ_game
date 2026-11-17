extends TestCase


func _world(count: int = 3) -> Game:
	var g := blank_game(30, 14, count)
	for p in g.state.players:
		p.is_ai = false
		p.known_civics["IDEOLOGY"] = true
		p.treasury = 100.0
		for peer in count:
			if peer != p.id:
				p.met[peer] = true
	DiplomacyRules.initialize(g)
	return g


func _vote(g: Game, pid: int, id: int, choice: String) -> Array:
	g.state.current_player = pid
	return g.apply_action({"type": "congress_vote", "id": id, "vote": choice})


func _found(g: Game) -> void:
	g.state.current_player = 0
	var events := g.apply_action({"type": "congress_found"})
	check_eq(events[0]["type"], "congress_opened")
	var id := int(events[0]["id"])
	for pid in g.state.players.size():
		_vote(g, pid, id, "yes")
	check(g.state.congress_data["founded"])


func _deal(g: Game, seller: int, buyer: int, resource: String = "IRON") -> int:
	g.state.current_player = seller
	var offer := g.apply_action({"type": "propose_supply", "buyer": buyer, "resource": resource,
		"upfront": 0, "per_turn": 2, "rounds": 5, "unit_price": 3})
	check_eq(offer[0]["type"], "supply_proposed")
	var id := int(offer[0]["id"])
	g.state.current_player = buyer
	check_eq(g.apply_action({"type": "respond_supply", "id": id, "accept": true})[0]["type"], "supply_accepted")
	return id


func _proof(g: Game, seller: int = 1, buyer: int = 0) -> int:
	var contract := _deal(g, seller, buyer)
	g.state.current_player = seller
	var events := g.apply_action({"type": "cancel_supply", "id": contract})
	check(events.any(func(event): return event["type"] == "supply_breach_recorded"))
	return int(CongressRules.evidence_for(g, buyer)[0]["id"])


func test_founding_requires_three_and_votes_time_out_on_own_turns() -> void:
	var duel := _world(2)
	check_eq(duel.apply_action({"type": "congress_found"})[0]["type"], "error")
	var g := _world()
	var opened := g.apply_action({"type": "congress_found"})
	var id := int(opened[0]["id"])
	check_eq(_vote(g, 0, id, "yes").size(), 0)
	check_eq(_vote(g, 0, id, "yes")[0]["type"], "error")
	_vote(g, 1, id, "yes")
	CongressRules.end_turn(g, 0, [])
	CongressRules.end_turn(g, 2, [])
	check_eq(CongressRules.polls(g)[0]["ballots"]["2"]["left"], 1)
	var events: Array = []
	CongressRules.end_turn(g, 2, events)
	check(events.any(func(event): return event["type"] == "congress_result" and not event["passed"]))
	check(not g.state.congress_data["founded"])


func test_regular_agenda_keeps_evidence_and_recommendation_uses_majority() -> void:
	var g := _world(5)
	_found(g)
	var evidence := _proof(g)
	g.state.diplomacy["influence"]["0"] = {"value": 300.0, "target": 300.0, "sources": {}}
	g.state.current_player = 0
	var request := {"type": "congress_propose", "mode": "ordinary", "evidence": evidence, "recommendation": true}
	var queued := g.apply_action(request)
	check_eq(queued[0]["type"], "congress_queued")
	var id := int(queued[0]["id"])
	check_eq(g.apply_action(request)[0]["type"], "error")
	check(CongressRules.polls(g).is_empty())
	g.state.turn = int(g.state.congress_data["next_session"]) - 1
	CongressRules.close_round(g, [])
	check(g.state.congress_data["evidence"].is_empty())
	check_eq(CongressRules.polls(g)[0]["proof"]["resource"], "IRON")
	for pid in 5:
		_vote(g, pid, id, "yes" if pid < 3 else "no")
	check(g.state.congress_data["recent"]["passed"])
	check(g.state.congress_data["orders"].is_empty())


func test_support_is_a_promise_and_binding_motion_requires_two_thirds() -> void:
	var g := _world(4)
	_found(g)
	var evidence := _proof(g)
	g.state.diplomacy["influence"]["0"] = {"value": 500.0, "target": 500.0, "sources": {}}
	g.state.diplomacy["dependency"]["2,0"] = {"strategic": 20.0}
	g.state.current_player = 0
	var opened := g.apply_action({"type": "congress_propose", "mode": "emergency", "evidence": evidence})
	check_eq(opened[0]["type"], "congress_opened")
	var id := int(opened[0]["id"])
	var demand := g.apply_action({"type": "issue_demand", "kind": "vote_support", "target": 2, "offer": id})
	check_eq(demand[0]["type"], "demand_issued")
	g.state.current_player = 2
	check_eq(g.apply_action({"type": "respond_demand", "pair": "0,2", "id": demand[0]["id"], "accept": true})[0]["type"], "demand_accepted")
	var saved := g.state.to_json()
	check_eq(GameState.from_json(saved, g.data).congress_data, g.state.congress_data)
	_vote(g, 0, id, "yes")
	_vote(g, 1, id, "no")
	_vote(g, 2, id, "abstain")
	_vote(g, 3, id, "yes")
	check(not g.state.congress_data["recent"]["passed"])
	check_eq(TreatyRules.trust(g, 0, 2), -15)
	check_near(float(DiplomacyRules.influence(g, 0)["value"]), 500.0)


func test_new_breach_after_grace_enforces_embargo_and_refunds() -> void:
	var g := _world()
	_found(g)
	var proof := _proof(g)
	var route_origin := CityRules.found_city(g, 2, g.state.map.grid.index_of(3, 5))
	var route_destination := CityRules.found_city(g, 1, g.state.map.grid.index_of(9, 5))
	g.state.player(2).revealed.fill(Player.FOG_REVEALED)
	var trader := g.state.add_unit(2, "TRADER", route_origin.tile)
	trader.trade_route = TradeRules.plan(g, route_origin, route_destination)
	check(not trader.trade_route.is_empty())
	g.state.diplomacy["influence"]["0"] = {"value": 500.0, "target": 500.0, "sources": {}}
	g.state.diplomacy["influence"]["1"] = {"value": 300.0, "target": 300.0, "sources": {}}
	g.state.current_player = 0
	var opened := g.apply_action({"type": "congress_propose", "mode": "emergency", "evidence": proof})
	var id := int(opened[0]["id"])
	_vote(g, 0, id, "yes")
	_vote(g, 1, id, "no")
	_vote(g, 2, id, "yes")
	check(g.state.congress_data["recent"]["passed"])
	_proof(g)
	check(not CongressRules.embargoed(g, 0, 1))
	g.state.player(1).stockpile["HORSES"] = 8.0
	var remaining := _deal(g, 1, 2, "HORSES")
	check_near(g.state.player(2).treasury, 70.0)
	g.state.turn += 1
	CongressRules.end_turn(g, 1, [])
	var breach := _deal(g, 1, 0)
	g.state.current_player = 1
	var events := g.apply_action({"type": "cancel_supply", "id": breach})
	check(events.any(func(event): return event["type"] == "congress_violation"))
	check(CongressRules.embargoed(g, 0, 1) and CongressRules.embargoed(g, 2, 1))
	check(not CongressRules.embargoed(g, 0, 2))
	check(not g.state.diplomacy["contracts"].has(str(remaining)))
	check(trader.trade_route.is_empty())
	check_near(g.state.player(2).treasury, 100.0)
	check_near(float(DiplomacyRules.influence(g, 1)["value"]), 260.0)
	check_eq(TreatyRules.trust(g, 2, 1), -15)
	check(TradeRules.plan(g, route_origin, route_destination).is_empty())
	check_eq(g.apply_action({"type": "propose_supply", "buyer": 0, "resource": "IRON",
		"upfront": 0, "per_turn": 1, "rounds": 1, "unit_price": 1})[0]["type"], "error")
	g.state.turn += 10
	check(not CongressRules.embargoed(g, 0, 1))


func test_supplier_shortage_creates_evidence_but_full_buyer_warehouse_does_not() -> void:
	var g := _world()
	g.state.player(2).stockpile["IRON"] = 50.0
	_deal(g, 1, 2)
	_deal(g, 1, 0)
	DiplomacyRules.close_round(g, [])
	check_eq(CongressRules.evidence_for(g, 0).size(), 1)
	check_eq(CongressRules.evidence_for(g, 0)[0]["missing"], 2)
	check(CongressRules.evidence_for(g, 2).is_empty())


func test_immediate_embargo_requires_700_and_affirmative_votes() -> void:
	var g := _world()
	_found(g)
	var proof := _proof(g)
	g.state.diplomacy["influence"]["0"] = {"value": 699.0}
	g.state.current_player = 0
	var request := {"type": "congress_propose", "mode": "sanctions", "evidence": proof}
	check_eq(g.apply_action(request)[0]["type"], "error")
	g.state.diplomacy["influence"]["0"]["value"] = 700.0
	var opened := g.apply_action(request)
	check_eq(opened[0]["type"], "congress_opened")
	var id := int(opened[0]["id"])
	_vote(g, 0, id, "yes")
	_vote(g, 1, id, "no")
	check(not CongressRules.embargoed(g, 0, 1))
	_vote(g, 2, id, "yes")
	check(CongressRules.embargoed(g, 0, 1))
	check(CongressRules.embargoed(g, 2, 1))
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 0)
	check_near(float(DiplomacyRules.influence(g, 0)["value"]), 700.0)


func _preach(g: Game, offender: int, city: City, charges: int = 1) -> Array:
	g.state.current_player = offender
	var unit := g.state.add_unit(offender, "MISSIONARY", city.tile)
	unit.charges = charges
	unit.moves_left = 2.0
	return g.apply_action({"type": "spread_religion", "unit": unit.id})


func test_religious_resolution_requires_protest_and_new_breach_after_grace() -> void:
	var g := _world()
	_found(g)
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(5, 5))
	g.state.player(1).religion_id = "TEST_FAITH"
	var first := _preach(g, 1, city)
	check(first.any(func(event): return event["type"] == "religious_incident"))
	check(CongressRules.evidence_for(g, 0).is_empty(), "до протеста нет дела для ООН")
	var incident_id: int = first[1]["id"]
	g.state.current_player = 0
	var protest := g.apply_action({"type": "religious_protest", "incident": incident_id})
	check_eq(protest[0]["type"], "religious_protest")
	g.state.current_player = 1
	g.apply_action({"type": "respond_religious_protest", "request": protest[0]["id"], "accept": false})
	check(CongressRules.evidence_for(g, 0).is_empty(), "обращение в тот же ход отказа запрещено")
	g.state.turn = 2
	var proof: int = CongressRules.evidence_for(g, 0)[0]["id"]
	g.state.diplomacy["influence"]["0"] = {"value": 499.0, "target": 499.0, "sources": {}}
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "congress_propose", "mode": "religious", "evidence": proof})[0]["type"], "error")
	g.state.diplomacy["influence"]["0"]["value"] = 500.0
	check_eq(g.apply_action({"type": "congress_propose", "mode": "sanctions", "evidence": proof})[0]["type"], "error")
	var opened := g.apply_action({"type": "congress_propose", "mode": "religious", "evidence": proof})
	check_eq(opened[0]["type"], "congress_opened")
	var order_id: int = opened[0]["id"]
	_vote(g, 0, order_id, "yes")
	_vote(g, 1, order_id, "no")
	_vote(g, 2, order_id, "yes")
	check(g.state.congress_data["recent"]["passed"])
	check_eq(g.state.congress_data["orders"][str(order_id)]["kind"], "religious")
	g.state.diplomacy["influence"]["1"] = {"value": 300.0, "target": 300.0, "sources": {}}
	_preach(g, 1, city)
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 0)
	CongressRules.end_turn(g, 1, [])
	check(g.state.congress_data["orders"][str(order_id)]["grace"], "льготный срок включает полный собственный ход")
	g.state.player(1).stockpile["HORSES"] = 8.0
	var contract := _deal(g, 1, 2, "HORSES")
	check_near(g.state.player(2).treasury, 70.0)
	g.state.turn = 3
	CongressRules.end_turn(g, 1, [])
	var violation := _preach(g, 1, city)
	check(violation.any(func(event): return event["type"] == "congress_violation"))
	check(CongressRules.embargoed(g, 1, 0) and CongressRules.embargoed(g, 1, 2))
	check(not g.state.diplomacy["contracts"].has(str(contract)))
	check_near(g.state.player(2).treasury, 100.0)
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 40)
	check_eq(TreatyRules.trust(g, 2, 1), -15)
	check_near(float(DiplomacyRules.influence(g, 1)["value"]), 260.0)
	_preach(g, 1, city)
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 40)
	g.state.turn = 4
	_preach(g, 1, city)
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 50)
	check_eq(int(g.state.congress_data["orders"][str(order_id)]["trust_until"]), 24)
	var restored := GameState.from_json(g.state.to_json(), g.data)
	check_eq(restored.congress_data["orders"], g.state.congress_data["orders"])
	for round_number in range(5, 12):
		g.state.turn = round_number
		_preach(g, 1, city)
	check_eq(CongressRules.reputation_damage(g, 1, g.state.turn), 100)


func test_broken_religious_promise_becomes_congress_evidence() -> void:
	var g := _world()
	_found(g)
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(5, 5))
	g.state.player(1).religion_id = "TEST_FAITH"
	var spread := _preach(g, 1, city)
	g.state.current_player = 0
	var protest := g.apply_action({"type": "religious_protest", "incident": spread[1]["id"]})
	g.state.current_player = 1
	g.apply_action({"type": "respond_religious_protest", "request": protest[0]["id"], "accept": true})
	check(CongressRules.evidence_for(g, 0).is_empty())
	_preach(g, 1, city)
	g.state.turn = 2
	var proof: Dictionary = CongressRules.evidence_for(g, 0)[0]
	check_eq(proof["reason"], "promise_breached")
	check_eq(proof["kind"], "religious")
	g.state.diplomacy["influence"]["0"] = {"value": 500.0}
	g.state.current_player = 0
	AIPlayer._congress(g, 0)
	check_eq(CongressRules.polls(g)[0]["mode"], "religious")
