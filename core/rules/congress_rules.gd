class_name CongressRules
extends RefCounted
## Учреждение, голосование и исполнение решений международной организации.


static func setting(game: Game, key: String) -> int:
	return int(game.data.diplomacy["congress"][key])


static func _duration(game: Game, key: String) -> int:
	return maxi(1, roundi(setting(game, key) * CityRules.speed_mult(game)))


static func _members(game: Game) -> Array[int]:
	var result: Array[int] = []
	for p in game.state.players:
		if p.alive and not p.is_barbarian:
			result.append(p.id)
	return result


static func _id(game: Game) -> int:
	var id: int = game.state.congress_data["next_id"]
	game.state.congress_data["next_id"] = id + 1
	return id


static func _rating(game: Game, pid: int) -> float:
	return float(game.state.diplomacy.get("influence", {}).get(str(pid), {}).get("value", 0.0))


static func founding_error(game: Game, pid: int) -> String:
	var data := game.state.congress_data
	if data["founded"] or not data["polls"].is_empty():
		return "Организация уже учреждена или идёт голосование"
	if game.state.turn < int(data["next_session"]):
		return "Следующая попытка учреждения доступна с хода %d" % int(data["next_session"])
	var civic := str(game.data.diplomacy["congress"]["founding_civic"])
	var members := _members(game)
	if not members.has(pid) or not game.state.player(pid).has_civic(civic):
		return "Инициатору нужна Идеология"
	var qualified := 0
	for member in members:
		if game.state.player(member).has_civic(civic):
			qualified += 1
	return "" if qualified >= setting(game, "minimum_members") else "Идеологию должны изучить минимум три державы"


static func initiate(game: Game, events: Array) -> String:
	var pid := game.state.current_player
	var error := founding_error(game, pid)
	if error != "":
		return error
	_open(game, {"id": _id(game), "mode": "founding", "issuer": pid, "accused": -1, "evidence": -1}, events)
	return ""


static func evidence_for(game: Game, pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var records: Dictionary = game.state.congress_data["evidence"]
	for key in _ordered_keys(records):
		var record: Dictionary = records[key]
		if int(record["victim"]) == pid and not record["filed"] \
				and game.state.turn - int(record["turn"]) < _duration(game, "evidence_rounds"):
			result.append(record.duplicate())
	return result


static func proposal_error(game: Game, pid: int, example: int, mode: String) -> String:
	var data := game.state.congress_data
	if not data["founded"] or not _members(game).has(pid):
		return "Международная организация ещё не действует"
	if mode not in ["ordinary", "emergency", "sanctions"]:
		return "Неизвестный вид обращения"
	if _members(game).size() < setting(game, "minimum_members"):
		return "Недостаточно держав для голосования"
	var evidence: Dictionary = data["evidence"].get(str(example), {})
	if evidence.is_empty() or int(evidence["victim"]) != pid or evidence["filed"] \
			or game.state.turn - int(evidence["turn"]) >= _duration(game, "evidence_rounds"):
		return "Нужно недавнее незаявленное нарушение договора против вашей державы"
	var accused: int = evidence["offender"]
	if not _members(game).has(accused):
		return "Адресат больше не участвует в партии"
	var power := setting(game, mode + "_influence")
	if _rating(game, pid) < power:
		return "Нужно не менее %d мирового влияния" % power
	for group in ["polls", "docket", "orders"]:
		for entry in data[group].values():
			if int(entry["issuer"]) == pid and int(entry["accused"]) == accused \
					and (group != "orders" or game.state.turn < int(entry["ends"])):
				return "На этот спор уже заведено дело"
			if group == "polls" and mode != "ordinary" and entry["mode"] != "ordinary" and int(entry["issuer"]) == pid:
				return "Ваше внеочередное голосование ещё идёт"
	if mode != "ordinary" and int(data["cooldowns"].get(str(pid), 0)) > game.state.turn:
		return "Пока действует пауза между внеочередными обращениями"
	return ""


static func propose(game: Game, action: Dictionary, events: Array) -> String:
	var pid := game.state.current_player
	var example := int(action.get("evidence", -1))
	var mode := str(action.get("mode", ""))
	var error := proposal_error(game, pid, example, mode)
	if error != "":
		return error
	var data := game.state.congress_data
	var evidence: Dictionary = data["evidence"][str(example)]
	evidence["filed"] = true
	var item := {"id": _id(game), "mode": mode, "issuer": pid, "accused": evidence["offender"],
		"evidence": example, "filed_turn": game.state.turn,
		"proof": evidence.duplicate(true),
		"recommendation": mode == "ordinary" and bool(action.get("recommendation", false))}
	if mode == "ordinary":
		data["docket"][str(item["id"])] = item
		events.append({"type": "congress_queued", "id": item["id"], "issuer": pid})
	else:
		data["cooldowns"][str(pid)] = game.state.turn + _duration(game, "emergency_cooldown")
		_open(game, item, events)
	return ""


static func _ordered_keys(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort_custom(func(a: String, b: String): return int(a) < int(b))
	return keys


static func _open(game: Game, item: Dictionary, events: Array) -> void:
	var ballots := {}
	for pid in _members(game):
		ballots[str(pid)] = {"left": setting(game, "personal_vote_turns"), "vote": "", "promise": -1}
	item["ballots"] = ballots
	game.state.congress_data["polls"][str(item["id"])] = item
	events.append({"type": "congress_opened", "id": item["id"], "issuer": item["issuer"]})


static func polls(game: Game) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active: Dictionary = game.state.congress_data["polls"]
	for key in _ordered_keys(active):
		result.append(active[key])
	return result


static func support_error(game: Game, issuer: int, recipient: int, id: int) -> String:
	var item: Dictionary = game.state.congress_data["polls"].get(str(id), {})
	if item.is_empty() or item["mode"] == "founding" or int(item["issuer"]) != issuer:
		return "Нужно открытое голосование по вашей резолюции"
	var ballot: Dictionary = item["ballots"].get(str(recipient), {})
	if ballot.is_empty() or ballot["vote"] != "" or int(ballot["promise"]) >= 0:
		return "Адресат уже проголосовал или дал обещание"
	return ""


static func promise_support(game: Game, issuer: int, recipient: int, id: int) -> void:
	game.state.congress_data["polls"][str(id)]["ballots"][str(recipient)]["promise"] = issuer


static func cast_vote(game: Game, action: Dictionary, events: Array) -> String:
	var id := str(int(action.get("id", -1)))
	var item: Dictionary = game.state.congress_data["polls"].get(id, {})
	var pid := game.state.current_player
	if item.is_empty() or not _members(game).has(pid):
		return "Голосование недоступно"
	var vote := str(action.get("vote", ""))
	var ballot: Dictionary = item["ballots"].get(str(pid), {})
	if vote not in ["yes", "no", "abstain"] or ballot.is_empty() or ballot["vote"] != "":
		return "Вы уже голосовали либо голос недействителен"
	_ballot(game, pid, ballot, vote, events)
	_finish_if_ready(game, item, events)
	return ""


static func _ballot(game: Game, pid: int, ballot: Dictionary, vote: String, events: Array) -> void:
	ballot["vote"] = vote
	var towards: int = ballot["promise"]
	if towards >= 0 and vote != "yes":
		DemandRules.note_breach(game, towards, pid)
		events.append({"type": "congress_promise_broken", "player": pid, "towards": towards})


static func end_turn(game: Game, pid: int, events: Array) -> void:
	for item in game.state.congress_data["orders"].values():
		if int(item["accused"]) == pid and game.state.turn > int(item["approved"]):
			item["grace"] = false
	for item in polls(game):
		var ballot: Dictionary = item["ballots"].get(str(pid), {})
		if not ballot.is_empty() and ballot["vote"] == "":
			ballot["left"] -= 1
			if int(ballot["left"]) <= 0:
				_ballot(game, pid, ballot, "abstain", events)
		_finish_if_ready(game, item, events)


static func _finish_if_ready(game: Game, item: Dictionary, events: Array) -> void:
	var eligible := 0
	var supporters: Array[int] = []
	var waiting := false
	for member in _members(game):
		var ballot: Dictionary = item["ballots"].get(str(member), {})
		if ballot.is_empty():
			continue
		eligible += 1
		waiting = waiting or ballot["vote"] == ""
		if ballot["vote"] == "yes":
			supporters.append(member)
	var minimum := setting(game, "minimum_members")
	if waiting and eligible >= minimum:
		return
	var founding: bool = item["mode"] == "founding"
	var valid := eligible >= minimum
	if not founding:
		valid = valid and _members(game).has(int(item["accused"])) and _members(game).has(int(item["issuer"]))
	var passed := valid and supporters.size() * 3 >= eligible * 2
	var advisory := bool(item.get("recommendation", false))
	if advisory:
		passed = valid and supporters.size() * 2 > eligible
	if founding:
		passed = valid and supporters.size() >= minimum and supporters.size() * 2 > eligible
	var data := game.state.congress_data
	data["polls"].erase(str(item["id"]))
	data["recent"] = {"id": item["id"], "mode": item["mode"], "passed": passed,
		"yes": supporters.size(), "eligible": eligible, "issuer": item["issuer"]}
	var result: Dictionary = data["recent"].duplicate()
	result["type"] = "congress_result"
	events.append(result)
	if founding:
		data["founded"] = passed
		data["next_session"] = game.state.turn + _duration(game, "session_interval")
	elif passed and not advisory:
		var order := {"id": item["id"], "mode": item["mode"], "issuer": item["issuer"],
			"accused": item["accused"], "supporters": supporters, "approved": game.state.turn,
			"ends": game.state.turn + _duration(game, "order_rounds"),
			"grace": true, "embargo_until": 0, "last_breach": -1, "damage": 0, "trust_until": 0}
		if item["mode"] == "sanctions":
			order["ends"] = game.state.turn + _duration(game, "embargo_rounds")
			order["embargo_until"] = order["ends"]
		data["orders"][str(item["id"])] = order
		if item["mode"] == "sanctions":
			data["commerce_dirty"] = true


static func close_round(game: Game, events: Array) -> void:
	var data := game.state.congress_data
	var next := game.state.turn + 1
	for item in polls(game):
		_finish_if_ready(game, item, events)
	if data["founded"] and next >= int(data["next_session"]):
		var docket: Dictionary = data["docket"]
		for key in _ordered_keys(docket):
			var item: Dictionary = docket[key]
			if _members(game).size() >= setting(game, "minimum_members") \
					and _members(game).has(int(item["issuer"])) and _members(game).has(int(item["accused"])):
				_open(game, item, events)
			docket.erase(key)
		data["next_session"] = next + _duration(game, "session_interval")
	var evidence: Dictionary = data["evidence"]
	for key in evidence.keys():
		if next - int(evidence[key]["turn"]) >= _duration(game, "evidence_rounds"):
			evidence.erase(key)
	var orders: Dictionary = data["orders"]
	for key in orders.keys():
		var order: Dictionary = orders[key]
		if next >= maxi(int(order["ends"]), maxi(int(order["embargo_until"]), int(order["trust_until"]))) \
				and _order_damage(game, order, next) <= 0:
			orders.erase(key)


static func note_supply_breach(game: Game, evidence: Dictionary, events: Array) -> void:
	var data := game.state.congress_data
	var id := _id(game)
	var record := evidence.duplicate()
	record.merge({"id": id, "turn": game.state.turn, "filed": false})
	data["evidence"][str(id)] = record
	events.append({"type": "supply_breach_recorded", "evidence": id,
		"offender": record["offender"], "victim": record["victim"]})
	var orders: Dictionary = data["orders"]
	for key in _ordered_keys(orders):
		var order: Dictionary = orders[key]
		if order["mode"] != "sanctions" and not order["grace"] and int(order["ends"]) > game.state.turn \
				and int(order["accused"]) == int(record["offender"]) and int(order["issuer"]) == int(record["victim"]):
			_penalize(game, order, events)
			return


static func _penalize(game: Game, order: Dictionary, events: Array) -> void:
	var turn := game.state.turn
	var former: int = order["last_breach"]
	if former == turn:
		return
	var amount := setting(game, "first_breach_damage" if former < 0 else "repeat_breach_damage")
	amount = mini(amount, setting(game, "maximum_damage") - int(order["damage"]))
	order["damage"] += amount
	order["last_breach"] = turn
	order["embargo_until"] = turn + _duration(game, "embargo_rounds")
	if former < 0:
		order["trust_until"] = turn + _duration(game, "damage_hold_rounds")
	var rating: Dictionary = game.state.diplomacy.get("influence", {}).get(str(order["accused"]), {})
	if not rating.is_empty():
		rating["value"] = maxf(0.0, float(rating["value"]) - amount)
		rating["target"] = maxf(0.0, float(rating.get("target", 0.0)) - amount)
		if rating.has("sources"):
			rating["sources"]["congress_damage"] = float(reputation_damage(game, int(order["accused"]), turn))
	game.state.congress_data["commerce_dirty"] = true
	events.append({"type": "congress_violation", "id": order["id"], "accused": order["accused"], "damage": amount})


static func _order_damage(game: Game, order: Dictionary, at_turn: int) -> int:
	var recover := maxi(0, at_turn - int(order["last_breach"]) - _duration(game, "damage_hold_rounds"))
	return maxi(0, int(order["damage"]) - recover * setting(game, "damage_recovery"))


static func reputation_damage(game: Game, player: int, at_turn: int) -> int:
	var total := 0
	for order in game.state.congress_data["orders"].values():
		if int(order["accused"]) == player:
			total += _order_damage(game, order, at_turn)
	return total


static func trust_penalty(game: Game, from: int, to: int) -> int:
	if from == to:
		return 0
	var total := 0
	for order in game.state.congress_data["orders"].values():
		if int(order["accused"]) == to and order["supporters"].has(from) and int(order["trust_until"]) > game.state.turn:
			total -= setting(game, "trust_penalty")
	return total


static func embargo_until(game: Game, a: int, b: int) -> int:
	if a == b:
		return 0
	var until := 0
	for order in game.state.congress_data["orders"].values():
		if (int(order["accused"]) == a and order["supporters"].has(b)) \
				or (int(order["accused"]) == b and order["supporters"].has(a)):
			until = maxi(until, int(order["embargo_until"]))
	return until


static func embargoed(game: Game, a: int, b: int) -> bool:
	return embargo_until(game, a, b) > game.state.turn


static func trade_exposure(game: Game, pid: int, target: int) -> Vector2i:
	var deals := 0
	for contract in game.state.diplomacy.get("contracts", {}).values():
		if (int(contract["seller"]) == pid and int(contract["buyer"]) == target) \
				or (int(contract["seller"]) == target and int(contract["buyer"]) == pid):
			deals += 1
	var routes := 0
	for unit in game.state.units_of(pid):
		if unit.trade_route.is_empty():
			continue
		var city := game.state.city(int(unit.trade_route["destination"]))
		if city != null and city.owner == target:
			routes += 1
	return Vector2i(deals, routes)


static func apply_commerce_effects(game: Game, events: Array) -> void:
	if not game.state.congress_data.get("commerce_dirty", false):
		return
	game.state.congress_data.erase("commerce_dirty")
	DiplomacyRules.cancel_embargoed(game, events)
	TradeRules.cancel_invalid(game, events)
