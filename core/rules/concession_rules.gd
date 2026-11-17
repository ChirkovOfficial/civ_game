class_name ConcessionRules
extends RefCounted
## Исполнение требований, связанных с передачей города или управлением войсками.


static func _rounds(game: Game, key: String) -> int:
	return maxi(1, roundi(float(game.data.diplomacy[key]) * CityRules.speed_mult(game)))


static func legal_owner(game: Game, unit: Unit) -> int:
	return int(game.state.demand_data["loans"].get(str(unit.id), {}).get("lender", unit.owner))


static func _army_cost(game: Game, pid: int) -> float:
	var cost := 0.0
	for unit in game.state.units_of(pid):
		if Movement.layer(game, unit.type) == "COMBAT" and legal_owner(game, unit) == pid:
			cost += float(game.data.unit_def(unit.type).get("cost", 0))
	return cost


static func loan_error(game: Game, issuer: int, recipient: int, unit_id: int) -> String:
	var unit := game.state.unit(unit_id)
	if unit == null or unit.owner != recipient or legal_owner(game, unit) != recipient:
		return "Нужен собственный юнит адресата"
	if not game.state.player(issuer).is_visible(unit.tile):
		return "Нужен видимый отряд"
	if not Combat.can_attack(game, unit) or Army.is_commander(game, unit) or not unit.commander.is_empty():
		return "Нужен боевой отряд без командующего"
	for other in game.state.units_at(unit.tile):
		if other.id != unit.id and other.owner != issuer and other.trade_route.is_empty():
			return "Отряд должен стоять отдельно"
	var cap: float = game.data.diplomacy["reinforcement_army_fraction"]
	var cost := float(game.data.unit_def(unit.type).get("cost", 0))
	if cost <= 0.0 or cost > _army_cost(game, recipient) * cap:
		return "Отряд превышает 20% стоимости армии адресата"
	return ""


static func lend(game: Game, issuer: int, recipient: int, unit_id: int, events: Array) -> void:
	var unit := game.state.unit(unit_id)
	game.state.demand_data["loans"][str(unit_id)] = {"lender": recipient, "borrower": issuer,
		"until": game.state.turn + _rounds(game, "reinforcement_duration")}
	unit.owner = issuer
	unit.orders = {}
	unit.moves_left = 0.0
	unit.fortify_turns = 0
	Visibility.recompute(game, issuer)
	Visibility.recompute(game, recipient)
	events.append({"type": "reinforcement_lent", "unit": unit_id, "player": issuer, "lender": recipient})


static func update_loans(game: Game, at_turn: int, events: Array) -> void:
	var loans: Dictionary = game.state.demand_data["loans"]
	var keys := loans.keys()
	keys.sort()
	for key in keys:
		var loan: Dictionary = loans[key]
		var unit := game.state.unit(int(key))
		var lender: int = loan["lender"]
		var borrower: int = loan["borrower"]
		if unit == null:
			loans.erase(key)
			continue
		if not game.state.player(lender).alive:
			loans.erase(key)
			game.state.remove_unit(unit.id)
			Visibility.recompute(game, borrower)
			events.append({"type": "reinforcement_lost", "unit": unit.id, "player": borrower})
			continue
		if at_turn < int(loan["until"]) and game.state.player(borrower).alive and not game.state.at_war(lender, borrower):
			continue
		loans.erase(key)
		unit.owner = lender
		unit.orders = {}
		unit.moves_left = 0.0
		unit.fortify_turns = 0
		Visibility.recompute(game, lender)
		Visibility.recompute(game, borrower)
		events.append({"type": "reinforcement_returned", "unit": unit.id, "player": lender, "borrower": borrower})


static func city_error(game: Game, issuer: int, recipient: int, city_id: int) -> String:
	if game.state.demand_data["city_concessions"].has(str(issuer)):
		return "Право получить город уже использовано в этой партии"
	var city := game.state.city(city_id)
	if city == null or city.owner != recipient or not game.state.player(issuer).is_revealed(city.tile):
		return "Нужен известный город адресата"
	if city.is_capital or game.state.original_capitals.get(str(city.original_owner), -1) == city.id \
			or game.state.cities_of(recipient).size() < 2:
		return "Нельзя требовать столицу, исходную столицу или последний город"
	if city.last_attacked_turn >= game.state.turn - 1:
		return "Город недавно был атакован"
	var border := false
	for tile in CityRules.owned_tiles(game, city):
		for unit in game.state.units_at(tile):
			if game.state.at_war(recipient, unit.owner):
				return "В городе или на его территории есть силы противника"
		for adjacent in game.state.map.grid.neighbors(tile):
			var neighbor := game.state.city_owning(adjacent)
			if neighbor != null and neighbor.owner == issuer:
				border = true
	return "" if border else "Территория города не примыкает к нашей"


static func transfer_city(game: Game, issuer: int, recipient: int, city_id: int, events: Array) -> void:
	var city := game.state.city(city_id)
	city.owner = issuer
	# Накопленный прогресс сохраняется. Несовместимые приказы снимаются.
	city.queue = city.queue.filter(func(item): return CityRules.build_error(game, city, item) == "")
	CityRules.assign_citizens(game, city)
	game.state.demand_data["city_concessions"][str(issuer)] = {"from": recipient, "turn": game.state.turn}
	var key := "%d,%d" % [recipient, issuer]
	var record: Dictionary = game.state.diplomacy.get("dependency", {}).get(key, {})
	if not record.is_empty():
		cap_components(record, float(game.data.diplomacy["concession_dependency_cap"]))
	TradeRules.cancel_invalid(game, events)
	Visibility.recompute(game, issuer)
	Visibility.recompute(game, recipient)
	events.append({"type": "city_conceded", "city": city_id, "player": issuer, "from": recipient})


static func cap_components(record: Dictionary, cap: float) -> void:
	var total := DiplomacyRules.dependency_value(record)
	if total > cap:
		for kind in ["strategic", "goods", "religion"]:
			record[kind] = float(record.get(kind, 0.0)) * cap / total
	var target: float = record.get("target", 0.0)
	if target > cap:
		record["goods_target"] = float(record.get("goods_target", 0.0)) * cap / target
		record["religion_target"] = float(record.get("religion_target", 0.0)) * cap / target
		record["target"] = cap


static func concession_active(game: Game, recipient: int, issuer: int) -> bool:
	var data: Dictionary = game.state.demand_data["city_concessions"].get(str(issuer), {})
	return int(data.get("from", -1)) == recipient \
		and game.state.turn < int(data["turn"]) + _rounds(game, "concession_dependency_rounds")


static func city_penalty(game: Game, viewer: int, subject: int) -> int:
	var data: Dictionary = game.state.demand_data["city_concessions"].get(str(subject), {})
	if int(data.get("from", -1)) != viewer:
		return 0
	var age := game.state.turn - int(data["turn"])
	var elapsed := maxi(0, age - _rounds(game, "concession_trust_rounds"))
	return -maxi(0, int(game.data.diplomacy["concession_trust_penalty"])
		- elapsed * int(game.data.diplomacy["concession_trust_recovery"]))
