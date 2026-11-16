class_name DemandRules
extends RefCounted
## Требования по направленной зависимости. Адресат отвечает на своём ходу.


static func _pair(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


static func _setting(game: Game, key: String) -> int:
	return int(game.data.diplomacy[key])


static func _duration(game: Game, key: String) -> int:
	return maxi(1, roundi(_setting(game, key) * CityRules.speed_mult(game)))


static func _terms_error(game: Game, issuer: int, recipient: int, kind: String, offer_id: int) -> String:
	if not TreatyRules._valid_pair(game, issuer, recipient) \
			or not game.state.player(issuer).met.has(recipient) \
			or game.state.at_war(issuer, recipient):
		return "Требование доступно только встреченной мирной державе"
	if kind == "passage":
		return TreatyRules.passage_error(game, issuer, recipient)
	if kind == "vote_support":
		return CongressRules.support_error(game, issuer, recipient, offer_id)
	if kind == "discount":
		var offer: Dictionary = game.state.diplomacy.get("offers", {}).get(str(offer_id), {})
		if offer.is_empty() or int(offer["seller"]) != recipient or int(offer["buyer"]) != issuer \
				or int(offer.get("responder", issuer)) != issuer or int(offer["unit_price"]) <= 0 \
				or int(offer.get("discount_percent", 0)) > 0:
			return "Нужно действующее предложение продавца с ценой без скидки"
		return ""
	if kind == "joint_war":
		if not TreatyRules._valid_pair(game, issuer, offer_id) or not game.state.at_war(issuer, offer_id):
			return "Мы должны уже воевать с указанной державой"
		if TreatyRules.until(game, "alliance", recipient, offer_id) > game.state.turn:
			return "Адресат состоит с противником в союзе"
		return UnitRules.declare_war_error(game, recipient, offer_id)
	if kind == "clear_camp":
		if not is_border_camp(game, issuer, recipient, offer_id):
			return "Нужен известный лагерь у общей границы, на нейтральной земле или земле адресата"
		return ""
	if kind == "reinforcement":
		return ConcessionRules.loan_error(game, issuer, recipient, offer_id)
	if kind == "concede_city":
		return ConcessionRules.city_error(game, issuer, recipient, offer_id)
	return "Такое требование пока недоступно"


static func issue_error(game: Game, issuer: int, recipient: int, kind: String, offer_id: int = -1) -> String:
	var error := _terms_error(game, issuer, recipient, kind, offer_id)
	if error != "":
		return error
	var pair := _pair(issuer, recipient)
	if game.state.demand_data["pending"].has(pair):
		return "В этой паре уже есть требование"
	for task in game.state.demand_data["obligations"].values():
		if _pair(int(task["issuer"]), int(task["recipient"])) == pair:
			return "В этой паре уже выполняется требование"
	var available: int = game.state.demand_data["cooldowns"].get(pair, 0)
	if available > game.state.turn:
		return "Следующее требование доступно с хода %d" % available
	var dependence := DiplomacyRules.dependency_value(DiplomacyRules.dependency(game, recipient, issuer))
	if kind == "concede_city":
		return "" if dependence >= 100.0 else "Нужна полная зависимость (100)"
	if kind in ["joint_war", "clear_camp", "reinforcement"]:
		var strong := _setting(game, "strong_demand_threshold")
		return "" if dependence > strong else "Нужна зависимость выше %d" % strong
	var minimum := _setting(game, "minor_demand_threshold")
	if dependence < minimum:
		return "Нужно не менее %d очков их зависимости от нас" % minimum
	return ""


static func issue(game: Game, action: Dictionary, events: Array) -> String:
	var issuer := game.state.current_player
	var recipient := int(action.get("target", -1))
	var kind := str(action.get("kind", ""))
	var offer := int(action.get("offer", -1))
	var error := issue_error(game, issuer, recipient, kind, offer)
	if error != "":
		return error
	var key := _pair(issuer, recipient)
	var percent := int(action.get("percent", _setting(game, "discount_demand_max")))
	if kind == "discount" and (percent <= 0 or percent > _setting(game, "discount_demand_max")):
		return "Скидка вне допустимого диапазона"
	var data := game.state.demand_data
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	var demand := {"id": id, "issuer": issuer, "recipient": recipient, "kind": kind, "offer": offer,
		"percent": percent, "turns_left": _setting(game, "demand_response_turns")}
	data["pending"][key] = demand
	_emit("demand_issued", demand, events)
	return ""


static func respond(game: Game, action: Dictionary, events: Array) -> String:
	var key := str(action.get("pair", ""))
	var demand: Dictionary = game.state.demand_data["pending"].get(key, {})
	if demand.is_empty() or int(demand["id"]) != int(action.get("id", -1)) \
			or int(demand["recipient"]) != game.state.current_player:
		return "Это требование недоступно"
	var issuer: int = demand["issuer"]
	var recipient: int = demand["recipient"]
	var kind: String = demand["kind"]
	if _terms_error(game, issuer, recipient, kind, int(demand["offer"])) != "":
		_finish(game, key, demand, "demand_lapsed", events)
		return ""
	if not bool(action.get("accept", false)):
		_finish(game, key, demand, "demand_refused", events)
		return ""
	var subject: int = demand["offer"]
	match kind:
		"passage":
			TreatyRules.grant_passage(game, issuer, recipient, events)
		"vote_support":
			CongressRules.promise_support(game, issuer, recipient, subject)
		"discount":
			game.state.diplomacy["offers"][str(subject)]["discount_percent"] = demand["percent"]
		"joint_war":
			game.declare_war(recipient, subject, events)
		"clear_camp":
			var task := demand.duplicate()
			task["until"] = game.state.turn + _duration(game, "camp_demand_duration")
			game.state.demand_data["obligations"][str(demand["id"])] = task
		"reinforcement":
			ConcessionRules.lend(game, issuer, recipient, subject, events)
		"concede_city":
			ConcessionRules.transfer_city(game, issuer, recipient, subject, events)
	_finish(game, key, demand, "demand_accepted", events)
	return ""


static func _emit(event_type: String, demand: Dictionary, events: Array) -> void:
	var event := demand.duplicate()
	event["type"] = event_type
	events.append(event)


static func _finish(game: Game, key: String, demand: Dictionary, status: String, events: Array) -> void:
	var data := game.state.demand_data
	data["pending"].erase(key)
	data["cooldowns"][key] = game.state.turn + _duration(game, "demand_cooldown")
	if status == "demand_refused":
		var direction := "%d,%d" % [demand["issuer"], demand["recipient"]]
		data["refusals"][direction] = game.state.turn + _duration(game, "demand_refusal_duration")
	_emit(status, demand, events)


static func trust_penalty(game: Game, viewer: int, subject: int) -> int:
	var key := "%d,%d" % [viewer, subject]
	var until: int = game.state.demand_data["refusals"].get(key, 0)
	var breached: int = game.state.demand_data["breaches"].get(key, 0)
	var refusal := -_setting(game, "demand_refusal_penalty") if until > game.state.turn else 0
	var breach := -_setting(game, "obligation_breach_penalty") if breached > game.state.turn else 0
	return refusal + breach + ConcessionRules.city_penalty(game, viewer, subject)


static func note_breach(game: Game, issuer: int, recipient: int, from_turn: int = -1) -> void:
	var turn := game.state.turn if from_turn < 0 else from_turn
	game.state.demand_data["breaches"]["%d,%d" % [issuer, recipient]] = \
		turn + _duration(game, "obligation_breach_duration")


static func pending_for(game: Game, pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Dictionary = game.state.demand_data["pending"]
	var keys := pending.keys()
	keys.sort()
	for key in keys:
		var demand: Dictionary = pending[key]
		if pid in [int(demand["issuer"]), int(demand["recipient"])]:
			var row := demand.duplicate()
			row["pair"] = key
			result.append(row)
	return result


static func end_turn(game: Game, pid: int, events: Array) -> void:
	for demand in pending_for(game, pid):
		var key: String = demand["pair"]
		if _terms_error(game, int(demand["issuer"]), int(demand["recipient"]), demand["kind"], int(demand["offer"])) != "":
			_finish(game, key, demand, "demand_lapsed", events)
		elif int(demand["recipient"]) == pid:
			var turns := int(demand["turns_left"]) - 1
			if turns == 0:
				_finish(game, key, demand, "demand_refused", events)
			else:
				game.state.demand_data["pending"][key]["turns_left"] = turns


static func is_border_camp(game: Game, issuer: int, recipient: int, tile: int) -> bool:
	var map := game.state.map
	if not map.grid.is_valid_index(tile) or not game.state.player(issuer).is_revealed(tile) \
			or not game.state.camps.has(tile):
		return false
	var city := game.state.city_owning(tile)
	if city != null and city.owner != recipient:
		return false
	for cell in map.grid.tiles_in_radius(tile, _setting(game, "camp_demand_radius")):
		var ours := game.state.city_owning(cell)
		if ours == null or ours.owner != recipient:
			continue
		for adjacent in map.grid.neighbors(cell):
			var theirs := game.state.city_owning(adjacent)
			if theirs != null and theirs.owner == issuer:
				return true
	return false


static func obligations_for(game: Game, pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var obligations: Dictionary = game.state.demand_data["obligations"]
	var ids := obligations.keys()
	ids.sort()
	for id in ids:
		var task: Dictionary = obligations[id]
		if pid in [int(task["recipient"]), int(task["issuer"])]:
			result.append(task)
	return result


static func on_camp_cleared(game: Game, tile: int, by: int, events: Array) -> void:
	var obligations: Dictionary = game.state.demand_data["obligations"]
	for id in obligations.keys():
		var task: Dictionary = obligations[id]
		if int(task["offer"]) == tile:
			obligations.erase(id)
			_emit("obligation_fulfilled" if int(task["recipient"]) == by else "obligation_excused", task, events)


static func close_round(game: Game, events: Array) -> void:
	var obligations: Dictionary = game.state.demand_data["obligations"]
	for id in obligations.keys():
		var task: Dictionary = obligations[id]
		var issuer: int = task["issuer"]
		var recipient: int = task["recipient"]
		var city := game.state.city_owning(int(task["offer"]))
		if not game.state.camps.has(int(task["offer"])) or not TreatyRules._valid_pair(game, issuer, recipient) \
				or (city != null and city.owner != recipient) or game.state.at_war(issuer, recipient):
			obligations.erase(id)
			_emit("obligation_excused", task, events)
		elif game.state.turn + 1 >= int(task["until"]):
			obligations.erase(id)
			note_breach(game, issuer, recipient, game.state.turn + 1)
			_emit("obligation_breached", task, events)
	ConcessionRules.update_loans(game, game.state.turn + 1, events)
