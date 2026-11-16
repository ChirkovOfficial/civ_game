extends TestCase

func _game() -> Game:
	var g := blank_game()
	g.state.player(0).met[1] = true
	g.state.player(1).met[0] = true
	g.state.player(0).stockpile["OIL"] = 50.0
	g.state.player(1).treasury = 210.0
	return g

func _offer(g: Game) -> int:
	var result := g.apply_action({"type": "propose_supply", "buyer": 1, "resource": "OIL",
		"upfront": 20, "per_turn": 5, "rounds": 10, "unit_price": 3})
	check_eq(result[0]["type"], "supply_proposed")
	return int(result[0]["id"])

func _accept(g: Game, id: int) -> Array:
	g.state.current_player = 1
	return g.apply_action({"type": "respond_supply", "id": id, "accept": true})

func test_contract_escrow_delivery_and_dependency() -> void:
	var g := _game()
	var id := _offer(g)
	check_eq(_accept(g, id)[0]["type"], "supply_accepted")
	check_near(g.state.player(1).treasury, 0.0)
	check_near(g.state.player(0).treasury, 60.0)
	check_near(g.state.player(1).stockpile["OIL"], 20.0)
	var active_save := GameState.from_json(g.state.to_json(), g.data)
	check_eq(active_save.to_dict()["diplomacy"], g.state.to_dict()["diplomacy"])
	for i in 5:
		g.state.add_unit(1, "INFANTRY", g.state.map.grid.index_of(10 + i, 5))
	for _i in 10:
		g.state.player(0).stockpile["OIL"] += 5.0
		g.state.player(1).stockpile["OIL"] -= 5.0
		var events: Array = []
		DiplomacyRules.close_round(g, events)
		check(events.any(func(e): return e["type"] == "supply_settled" and e["delivered"] == 5))
		g.state.turn += 1
	check_eq(g.state.diplomacy["contracts"].size(), 0)
	check_near(g.state.player(0).treasury, 210.0)
	check_near(g.state.player(1).treasury, 0.0)
	check_near(g.state.player(0).stockpile["OIL"], 30.0)
	check_near(g.state.player(1).stockpile["OIL"], 20.0)
	check(float(DiplomacyRules.dependency(g, 1, 0)["strategic"]) > 0.0)
	check(float(DiplomacyRules.influence(g, 0)["target"]) > 0.0)
	var loaded := GameState.from_dict(g.state.to_dict(), g.data)
	check_eq(loaded.to_dict()["diplomacy"], g.state.to_dict()["diplomacy"])
	var before_decline := float(DiplomacyRules.dependency(g, 1, 0)["strategic"])
	for _i in 5:
		DiplomacyRules.close_round(g, [])
		g.state.turn += 1
	check(float(DiplomacyRules.dependency(g, 1, 0)["strategic"]) < before_decline)

func test_shortfall_refund_cancel_and_no_double_settlement() -> void:
	var g := _game()
	var id := _offer(g)
	_accept(g, id)
	g.state.player(0).stockpile["OIL"] = 0.0
	var first: Array = []
	DiplomacyRules.close_round(g, first)
	check(first.any(func(e): return e["type"] == "supply_settled" and e["delivered"] == 0 and e["refunded"] == 15))
	check_near(g.state.player(1).treasury, 15.0)
	var repeat: Array = []
	DiplomacyRules.close_round(g, repeat)
	check_eq(repeat.size(), 0)
	g.state.current_player = 1
	var cancelled := g.apply_action({"type": "cancel_supply", "id": id})
	check_eq(cancelled[0]["type"], "supply_closed")
	check_near(g.state.player(1).treasury, 150.0)
	check_near(g.state.player(0).treasury, 60.0)
	check_eq(g.state.diplomacy["contracts"].size(), 0)

func test_reject_invalid_offer_atomically() -> void:
	var g := _game()
	var id := _offer(g)
	g.state.player(0).stockpile["OIL"] = 19.0
	var response := _accept(g, id)
	check_eq(response[0]["type"], "error")
	check_near(g.state.player(1).treasury, 210.0)
	check_near(g.state.player(0).treasury, 0.0)
	check(g.state.diplomacy["offers"].has(str(id)))
	g.state.player(0).stockpile["OIL"] = 50.0
	check_eq(_accept(g, id)[0]["type"], "supply_accepted")
	check_eq(_accept(g, id)[0]["type"], "error")

func test_competing_contracts_share_shortage() -> void:
	var g := _game()
	g.state.player(0).stockpile["OIL"] = 3.0
	for _i in 2:
		var result := g.apply_action({"type": "propose_supply", "buyer": 1, "resource": "OIL",
			"upfront": 0, "per_turn": 5, "rounds": 1, "unit_price": 1})
		g.state.current_player = 1
		check_eq(g.apply_action({"type": "respond_supply", "id": result[0]["id"], "accept": true})[0]["type"], "supply_accepted")
		g.state.current_player = 0
	var events: Array = []
	DiplomacyRules.close_round(g, events)
	var delivered: Array = []
	for event in events:
		if event["type"] == "supply_settled":
			delivered.append(event["delivered"])
	check_eq(delivered, [2, 1])
	check_near(g.state.player(0).stockpile["OIL"], 0.0)
	check_near(g.state.player(1).stockpile["OIL"], 3.0)
	check_near(g.state.player(0).treasury, 3.0)
	check_near(g.state.player(1).treasury, 207.0)

func test_war_refunds_future_periods() -> void:
	var g := _game()
	var id := _offer(g)
	_accept(g, id)
	g.state.set_war(0, 1, true)
	var events: Array = []
	DiplomacyRules.close_round(g, events)
	check(events.any(func(e): return e["type"] == "supply_closed" and e["reason"] == "relations_changed" and e["refund"] == 150))
	check_near(g.state.player(1).treasury, 150.0)
	check_near(g.state.player(0).treasury, 60.0)
	check_eq(g.state.diplomacy["contracts"].size(), 0)

func test_reexport_preserves_original_source() -> void:
	var g := blank_game(20, 12, 3)
	DiplomacyRules.initialize(g)
	g.state.player(0).stockpile["OIL"] = 10.0
	var original := DiplomacyRules._transfer(g, 0, 1, "OIL", 10.0)
	var relayed := DiplomacyRules._transfer(g, 1, 2, "OIL", 10.0)
	check_near(original, 10.0)
	check_near(relayed, 0.0)
	check_near(g.state.player(0).stockpile["OIL"], 0.0)
	check_near(g.state.player(2).stockpile["OIL"], 10.0)
	check_near(float(g.state.diplomacy["origin"]["2"]["OIL"]["0"]), 10.0)

func test_buyer_can_start_offer_and_seller_accepts() -> void:
	var g := _game()
	g.state.current_player = 1
	var events := g.apply_action({"type": "propose_supply", "seller": 0, "resource": "OIL",
		"upfront": 20, "per_turn": 5, "rounds": 10, "unit_price": 3})
	check_eq(events[0]["type"], "supply_proposed")
	var id := str(events[0]["id"])
	check_eq(g.state.diplomacy["offers"][id]["responder"], 0)
	check_near(g.state.player(1).treasury, 210.0)
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "respond_supply", "id": int(id), "accept": true})[0]["type"], "supply_accepted")
	check_near(g.state.player(1).treasury, 0.0)
	check_near(g.state.player(0).treasury, 60.0)
