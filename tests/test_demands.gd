extends TestCase


func _world() -> Game:
	var game := blank_game()
	game.state.player(0).met[1] = true
	game.state.player(1).met[0] = true
	game.state.player(1).is_ai = false
	DiplomacyRules.initialize(game)
	game.state.diplomacy["dependency"]["1,0"] = {"strategic": 19.0, "goods": 1.0}
	return game


func _issue(game: Game, kind: String, offer: int = -1) -> Array:
	return game.apply_action({"type": "issue_demand", "kind": kind, "target": 1, "offer": offer})


func _respond(game: Game, event: Dictionary, accept: bool) -> Array:
	return game.apply_action({"type": "respond_demand", "pair": "0,1", "id": event["id"], "accept": accept})


func test_passage_threshold_consent_and_stale_response() -> void:
	var g := _world()
	g.state.diplomacy["dependency"]["1,0"]["goods"] = 0.99
	check_eq(_issue(g, "passage")[0]["type"], "error")
	g.state.diplomacy["dependency"]["1,0"]["goods"] = 1.0
	var issued: Dictionary = _issue(g, "passage")[0]
	check_eq(issued["type"], "demand_issued")
	check_eq(TreatyRules.until(g, "passage", 0, 1), 0)
	check_eq(_respond(g, issued, true)[0]["type"], "error")
	g.state.current_player = 1
	g.state.diplomacy["dependency"].clear()
	var events := _respond(g, issued, true)
	check(events.any(func(event): return event["type"] == "demand_accepted"))
	check_eq(TreatyRules.until(g, "passage", 0, 1), 11)
	check_eq(TreatyRules.until(g, "passage", 1, 0), 0)
	check_eq(_respond(g, issued, true)[0]["type"], "error")


func test_timeout_uses_recipient_turns_and_sets_cooldown() -> void:
	var g := _world()
	_issue(g, "passage")
	g.apply_action({"type": "end_turn", "force": true})
	check_eq(DemandRules.pending_for(g, 1)[0]["turns_left"], 2)
	g.apply_action({"type": "end_turn", "force": true})
	check_eq(DemandRules.pending_for(g, 1)[0]["turns_left"], 1)
	var restored := GameState.from_json(g.state.to_json(), g.data)
	check_eq(restored.demand_data, g.state.demand_data)
	g.apply_action({"type": "end_turn", "force": true})
	var events := g.apply_action({"type": "end_turn", "force": true})
	check(events.any(func(event): return event["type"] == "demand_refused"))
	check(DemandRules.pending_for(g, 1).is_empty())
	check_eq(TreatyRules.trust(g, 0, 1), -5)
	check_eq(TreatyRules.trust(g, 1, 0), 0)
	check_eq(_issue(g, "passage")[0]["type"], "error")


func test_discount_preserves_exact_price_and_refund() -> void:
	var g := _world()
	g.state.current_player = 1
	g.state.player(0).treasury = 100.0
	g.state.player(1).stockpile["IRON"] = 10.0
	var offer: Dictionary = g.apply_action({"type": "propose_supply", "buyer": 0, "resource": "IRON",
		"upfront": 1, "per_turn": 1, "rounds": 2, "unit_price": 3})[0]
	g.state.current_player = 0
	var issued: Dictionary = _issue(g, "discount", int(offer["id"]))[0]
	g.state.current_player = 1
	check_eq(_respond(g, issued, true)[0]["type"], "demand_accepted")
	g.state.current_player = 0
	check_eq(g.apply_action({"type": "respond_supply", "id": offer["id"], "accept": true})[0]["type"], "supply_accepted")
	check_near(g.state.player(0).treasury, 91.9)
	check_near(g.state.player(1).treasury, 2.7)
	DiplomacyRules.close_round(g, [])
	check_near(g.state.player(1).treasury, 5.4)
	g.apply_action({"type": "cancel_supply", "id": offer["id"]})
	check_near(g.state.player(0).treasury, 94.6)
