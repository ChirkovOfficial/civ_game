extends TestCase


func _world() -> Game:
	var g := blank_game(24, 12, 3)
	var map := g.state.map
	for pid in 3:
		var city := CityRules.found_city(g, pid, map.grid.index_of(3 + 7 * pid, 5))
		city.population = 5
		g.state.player(pid).treasury = 100.0
		for peer in 3:
			if pid != peer:
				g.state.player(pid).met[peer] = true
	_add_marble(g, 0)
	return g


func _add_marble(g: Game, pid: int) -> int:
	var tile := g.state.map.grid.neighbor(g.state.cities_of(pid)[0].tile, 0)
	g.state.map.resource[tile] = "MARBLE"
	g.state.map.improvement[tile] = "QUARRY"
	return tile


func _offer(g: Game, buyer: int) -> Dictionary:
	g.state.current_player = 0
	return g.apply_action({"type": "propose_supply", "buyer": buyer, "resource": "MARBLE",
		"upfront": 0, "per_turn": 1, "rounds": 4, "unit_price": 3})[0]


func test_exclusive_access_payment_dependency_and_war_refund() -> void:
	var g := _world()
	var offer := _offer(g, 1)
	check_eq(offer["type"], "supply_proposed")
	check(LuxuryTrade.kinds(g, 0).has("MARBLE"), "Предложение пока сохраняет доступ продавца")
	check_eq(_offer(g, 2)["type"], "error", "Одну копию нельзя предложить двум покупателям")
	g.state.current_player = 1
	var accepted := g.apply_action({"type": "respond_supply", "id": offer["id"], "accept": true})
	check_eq(accepted[0]["type"], "supply_accepted")
	check(not LuxuryTrade.kinds(g, 0).has("MARBLE"))
	check(LuxuryTrade.kinds(g, 1).has("MARBLE"))
	check(LuxuryTrade.available_sources(g, 1, "MARBLE").is_empty(), "Импорт нельзя перепродать")
	check_near(g.state.player(0).treasury, 100.0)
	check_near(g.state.player(1).treasury, 88.0)
	DiplomacyRules.close_round(g, [])
	g.state.turn += 1
	check_near(g.state.player(0).treasury, 103.0)
	var dependence := DiplomacyRules.dependency(g, 1, 0)
	check_near(float(dependence["goods"]), 2.0)
	check_near(float(dependence["goods_target"]), 15.0)
	check(float(DiplomacyRules.influence(g, 0)["sources"]["dependency"]) > 0.0)
	var saved := g.state.to_json()
	var restored := GameState.from_bytes(g.state.to_bytes(), g.data)
	check(restored.to_json() == saved, "Двоичное сохранение сохраняет договор и историю без потери точности")
	var json_restore := GameState.from_json(saved, g.data)
	check_eq(json_restore.diplomacy["contracts"], g.state.diplomacy["contracts"])
	g.apply_action({"type": "declare_war", "target": 0})
	check_near(g.state.player(1).treasury, 97.0)
	check(LuxuryTrade.kinds(g, 0).has("MARBLE"))
	check(not LuxuryTrade.kinds(g, 1).has("MARBLE"))
	DiplomacyRules.close_round(g, [])
	check_near(float(DiplomacyRules.dependency(g, 1, 0)["goods"]), 0.0)


func test_duplicate_marble_grants_no_dependency_and_source_loss_refunds() -> void:
	var g := _world()
	var source := _add_marble(g, 0)
	_add_marble(g, 1)
	var offer := _offer(g, 1)
	g.state.current_player = 1
	g.apply_action({"type": "respond_supply", "id": offer["id"], "accept": true})
	check_near(LuxuryTrade.affected_share(g, 1, 0), 0.0)
	var city := g.state.cities_of(1)[0]
	check_eq(CityRules.luxury_amenities(g, 1)[city.id], 1)
	g.state.map.pillaged[source] = 1
	var events: Array = []
	DiplomacyRules.close_round(g, events)
	check(events.any(func(event): return event["type"] == "supply_closed" and event["refund"] == 12))
	check_near(g.state.player(1).treasury, 100.0)
	check_eq(CityRules.luxury_amenities(g, 1)[city.id], 1)
	check(g.state.diplomacy["contracts"].is_empty())


func test_spare_copy_leaves_seller_access_and_contract_expires() -> void:
	var g := _world()
	var second := g.state.map.grid.neighbor(g.state.cities_of(0)[0].tile, 1)
	g.state.map.resource[second] = "MARBLE"
	g.state.map.improvement[second] = "QUARRY"
	var offer := _offer(g, 1)
	g.state.current_player = 1
	g.apply_action({"type": "respond_supply", "id": offer["id"], "accept": true})
	check(LuxuryTrade.kinds(g, 0).has("MARBLE"))
	check_eq(LuxuryTrade.available_sources(g, 0, "MARBLE").size(), 1)
	for _turn in 4:
		DiplomacyRules.close_round(g, [])
		g.state.turn += 1
	check_near(g.state.player(0).treasury, 112.0)
	check_near(g.state.player(1).treasury, 88.0)
	check_eq(LuxuryTrade.available_sources(g, 0, "MARBLE").size(), 2)
	check(not LuxuryTrade.kinds(g, 1).has("MARBLE"))
	check(g.state.diplomacy["contracts"].is_empty())
