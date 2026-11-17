class_name TreatyRules
extends RefCounted
## Двусторонние договоры и правила прохода через мирные границы.

const KINDS := ["friendship", "alliance", "passage"]


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	var cfg := data.diplomacy
	var second := int(cfg.get("alliance_level_2_rounds", 0))
	var third := int(cfg.get("alliance_level_3_rounds", 0))
	if second <= 0 or third <= second:
		errors.append("Союзы: сроки уровней должны возрастать")
	var weights: Array = cfg.get("alliance_influence_by_level", [])
	if weights.size() != 3:
		errors.append("Союзы: нужны три коэффициента влияния")
	else:
		for weight in weights:
			if float(weight) <= 0.0:
				errors.append("Союзы: коэффициенты влияния должны быть положительными")
	var specializations: Dictionary = cfg.get("alliance_specializations", {})
	for id in ["science", "culture", "economic", "military", "religious"]:
		var def: Dictionary = specializations.get(id, {})
		if str(def.get("name", "")) == "" or str(def.get("description", "")) == "":
			errors.append("Союзы: отсутствует специализация %s" % id)
			continue
		var effect: Array = def.get("route_bonus", def.get("tourism_bonus", def.get("shared_enemy_strength", [])))
		if effect.size() != 3:
			errors.append("Союзы: нужны три ступени эффекта %s" % id)
	return errors


static func _key(kind: String, from: int, to: int) -> String:
	if kind == "passage" or kind == "trust":
		return "%s:%d:%d" % [kind, from, to]
	return "%s:%d:%d" % [kind, mini(from, to), maxi(from, to)]


static func _collection(game: Game, name: String) -> Dictionary:
	return game.state.treaty_data.get(name, {})


static func _entry(game: Game, name: String, key: String) -> Dictionary:
	return _collection(game, name).get(key, {})


static func _active(record: Dictionary, turn: int) -> bool:
	return int(record.get("until", 0)) > turn


static func until(game: Game, kind: String, from: int, to: int) -> int:
	return int(_entry(game, "active", _key(kind, from, to)).get("until", 0))


static func alliance_level(game: Game, a: int, b: int, turn: int = -1) -> int:
	if turn < 0:
		turn = game.state.turn
	if not _valid_pair(game, a, b) or game.state.at_war(a, b):
		return 0
	var treaty := _entry(game, "active", _key("alliance", a, b))
	if not _active(treaty, turn):
		return 0
	var age := maxi(0, turn - int(treaty.get("since", turn)))
	if age >= _rounds(game, "alliance_level_3_rounds"):
		return 3
	if age >= _rounds(game, "alliance_level_2_rounds"):
		return 2
	return 1


static func alliance_next_level_turn(game: Game, a: int, b: int) -> int:
	var level := alliance_level(game, a, b)
	if level == 0 or level == 3:
		return -1
	var treaty := _entry(game, "active", _key("alliance", a, b))
	return int(treaty["since"]) + _rounds(game,
		"alliance_level_2_rounds" if level == 1 else "alliance_level_3_rounds")


static func alliance_specialization(game: Game, a: int, b: int) -> String:
	if alliance_level(game, a, b) == 0:
		return ""
	return str(_entry(game, "active", _key("alliance", a, b)).get("specialization", "science"))


static func alliance_effect(game: Game, a: int, b: int, specialization: String, effect: String) -> float:
	var level := alliance_level(game, a, b)
	if level == 0 or alliance_specialization(game, a, b) != specialization:
		return 0.0
	var def: Dictionary = game.data.diplomacy["alliance_specializations"].get(specialization, {})
	var values: Array = def.get(effect, [])
	return float(values[level - 1]) if values.size() >= level else 0.0


static func shared_enemy_bonus(game: Game, own: int, enemy: int) -> int:
	var best := 0
	for partner in game.state.players:
		if partner.id == own or partner.id == enemy or partner.is_barbarian or not partner.alive:
			continue
		if game.state.at_war(partner.id, enemy):
			best = maxi(best, int(alliance_effect(game, own, partner.id, "military", "shared_enemy_strength")))
	return best


static func trust(game: Game, viewer: int, subject: int) -> int:
	var record := _entry(game, "reputation", _key("trust", viewer, subject))
	var value := int(record["value"]) if _active(record, game.state.turn) else 0
	return value + DemandRules.trust_penalty(game, viewer, subject) + CongressRules.trust_penalty(game, viewer, subject) \
		+ DiplomaticVisibility.representation_trust(game, viewer, subject)


static func _valid_pair(game: Game, a: int, b: int) -> bool:
	if a == b or mini(a, b) < 0 or maxi(a, b) >= game.state.players.size():
		return false
	var x := game.state.player(a)
	var y := game.state.player(b)
	return x.alive and y.alive and not x.is_barbarian and not y.is_barbarian


static func _treaty_error(game: Game, kind: String, from: int, to: int) -> String:
	if kind not in KINDS or not _valid_pair(game, from, to):
		return "Договор недоступен"
	if not game.state.player(from).met.has(to) or not game.state.player(to).met.has(from):
		return "Нужно установить контакт"
	if game.state.at_war(from, to):
		return "Договор невозможен во время войны"
	if kind in ["friendship", "passage"] and until(game, "alliance", from, to) > game.state.turn:
		return "Это уже предусмотрено союзом"
	if kind == "alliance" and until(game, kind, from, to) <= game.state.turn:
		var civic: String = game.data.diplomacy["alliance_civic"]
		if not game.state.player(from).has_civic(civic):
			return "Нужно изучить: %s" % game.data.civics[civic]["name"]
		var friendship := _entry(game, "active", _key("friendship", from, to))
		var minimum := _rounds(game, "alliance_friendship_rounds")
		if not _active(friendship, game.state.turn) or game.state.turn - int(friendship["since"]) < minimum:
			return "Для союза нужно не менее %d ходов непрерывной дружбы" % minimum
	return ""


static func offer_error(game: Game, kind: String, from: int, to: int) -> String:
	var error := _treaty_error(game, kind, from, to)
	if error != "":
		return error
	var key := _key(kind, from, to)
	var offer := _entry(game, "offers", key)
	if _active(offer, game.state.turn):
		return "Предложение уже ожидает ответа"
	var cooldown := _entry(game, "cooldowns", key)
	if _active(cooldown, game.state.turn):
		return "Повторное предложение доступно с хода %d" % int(cooldown["until"])
	if until(game, kind, from, to) > game.state.turn + _rounds(game, "treaty_renewal_window"):
		return "Продление можно предложить ближе к окончанию договора"
	return ""


static func _rounds(game: Game, key: String) -> int:
	return maxi(1, roundi(float(game.data.diplomacy[key]) * CityRules.speed_mult(game)))


static func _offer_event(type: String, record: Dictionary) -> Dictionary:
	return {"type": type, "kind": record["kind"], "from": record["from"], "to": record["to"]}


static func passage_error(game: Game, visitor: int, host: int) -> String:
	var error := _treaty_error(game, "passage", visitor, host)
	if error != "":
		return error
	if until(game, "passage", visitor, host) > game.state.turn:
		return "Право прохода уже действует"
	return ""


static func grant_passage(game: Game, visitor: int, host: int, events: Array) -> void:
	var key := _key("passage", visitor, host)
	var expiry := game.state.turn + _rounds(game, "passage_rounds")
	var treaty := {"kind": "passage", "from": visitor, "to": host, "since": game.state.turn, "until": expiry}
	game.state.treaty_data["active"][key] = treaty
	game.state.treaty_data["offers"].erase(key)
	var event := _offer_event("treaty_accepted", treaty)
	event["until"] = expiry
	events.append(event)


static func propose(game: Game, action: Dictionary, events: Array) -> String:
	var kind := str(action.get("kind", ""))
	var from := game.state.current_player
	var to := int(action.get("target", -1))
	var error := offer_error(game, kind, from, to)
	if error != "":
		return error
	var specialization := ""
	if kind == "alliance":
		specialization = str(action.get("specialization", "science"))
		if until(game, kind, from, to) > game.state.turn:
			var existing := alliance_specialization(game, from, to)
			if action.has("specialization") and specialization != existing:
				return "Специализацию действующего союза нельзя изменить при продлении"
			specialization = existing
		elif not game.data.diplomacy["alliance_specializations"].has(specialization):
			return "Неизвестная специализация союза"
	var record := {"kind": kind, "from": from, "to": to,
		"until": game.state.turn + _rounds(game, "treaty_offer_rounds")}
	if kind == "alliance":
		record["specialization"] = specialization
	var key := _key(kind, from, to)
	game.state.treaty_data["offers"][key] = record
	events.append(_offer_event("treaty_proposed", record))
	return ""


static func respond(game: Game, action: Dictionary, events: Array) -> String:
	var key := str(action.get("offer", ""))
	var record := _entry(game, "offers", key)
	if not _active(record, game.state.turn) or int(record["to"]) != game.state.current_player:
		return "Это предложение недоступно"
	var kind: String = record["kind"]
	var from: int = record["from"]
	var to: int = record["to"]
	if not action.get("accept", false):
		game.state.treaty_data["offers"].erase(key)
		game.state.treaty_data["cooldowns"][key] = {
			"until": game.state.turn + _rounds(game, "treaty_reoffer_rounds")}
		events.append(_offer_event("treaty_declined", record))
		return ""
	var error := _treaty_error(game, kind, from, to)
	if error != "":
		return error
	var previous := _entry(game, "active", key)
	var active := _active(previous, game.state.turn)
	var duration := _rounds(game, "passage_rounds" if kind == "passage" else "treaty_rounds")
	var start := maxi(game.state.turn, int(previous.get("until", 0)))
	var treaty := {"kind": kind, "from": from, "to": to,
		"since": int(previous.get("since", game.state.turn)) if active else game.state.turn,
		"until": start + duration}
	if kind == "alliance":
		treaty["specialization"] = str(previous.get("specialization", "science")) if active \
			else str(record.get("specialization", "science"))
	game.state.treaty_data["active"][key] = treaty
	game.state.treaty_data["offers"].erase(key)
	if kind == "alliance":
		game.state.treaty_data["active"].erase(_key("friendship", from, to))
		game.state.treaty_data["offers"].erase(_key("friendship", from, to))
	var event := _offer_event("treaty_accepted", treaty)
	event["until"] = treaty["until"]
	if kind == "alliance":
		event["specialization"] = treaty["specialization"]
	events.append(event)
	return ""


static func offers_for(game: Game, pid: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offers := _collection(game, "offers")
	var keys := offers.keys()
	keys.sort()
	for key in keys:
		var offer: Dictionary = offers[key]
		if pid in [int(offer["from"]), int(offer["to"])] and _active(offer, game.state.turn):
			var item := offer.duplicate()
			item["key"] = key
			result.append(item)
	return result


static func on_war(game: Game, attacker: int, defender: int, events: Array) -> void:
	var broken := false
	for kind in KINDS:
		var keys := [_key(kind, attacker, defender)]
		if kind == "passage":
			keys.append(_key(kind, defender, attacker))
		for key in keys:
			game.state.treaty_data["offers"].erase(key)
			var treaty := _entry(game, "active", key)
			if _active(treaty, game.state.turn):
				broken = true
				events.append(_offer_event("treaty_broken", treaty))
			game.state.treaty_data["active"].erase(key)
	if broken:
		game.state.treaty_data["reputation"][_key("trust", defender, attacker)] = {
			"value": -int(game.data.diplomacy["treaty_betrayal_penalty"]),
			"until": game.state.turn + _rounds(game, "treaty_betrayal_rounds")}


static func _owner(game: Game, tile: int) -> int:
	var city := game.state.city_owning(tile)
	return city.owner if city != null else -1


static func _closed(game: Game, visitor: int, host: int) -> bool:
	if host < 0 or host == visitor or game.state.at_war(visitor, host):
		return false
	return until(game, "alliance", visitor, host) <= game.state.turn \
		and until(game, "passage", visitor, host) <= game.state.turn


static func border_allows(game: Game, unit: Unit, from: int, to: int) -> bool:
	if Movement.layer(game, unit.type) == "TOURISM":
		var host := _owner(game, to)
		return host < 0 or host == unit.owner or not game.state.at_war(unit.owner, host)
	if Movement.layer(game, unit.type) in ["TRADE", "RELIGIOUS"]:
		return true
	var host := _owner(game, to)
	return not _closed(game, unit.owner, host) or host == _owner(game, from)


static func withdrawing(game: Game, unit: Unit) -> bool:
	if Movement.layer(game, unit.type) == "TOURISM":
		var host := _owner(game, unit.tile)
		return host >= 0 and host != unit.owner and game.state.at_war(unit.owner, host)
	return Movement.layer(game, unit.type) not in ["TRADE", "RELIGIOUS"] and _closed(game, unit.owner, _owner(game, unit.tile))


static func process_withdrawal(game: Game, pid: int, events: Array) -> void:
	var deadlines := _collection(game, "withdrawal")
	for unit in game.state.units_of(pid):
		var key := str(unit.id)
		if not withdrawing(game, unit):
			deadlines.erase(key)
			continue
		var host := _owner(game, unit.tile)
		var record: Dictionary = deadlines.get(key, {})
		if int(record.get("host", -1)) != host:
			deadlines[key] = {"host": host, "until": game.state.turn + int(game.data.diplomacy["withdrawal_turns"])}
			unit.orders = {}
			events.append({"type": "unit_withdrawing", "unit": unit.id, "player": pid})
			continue
		if _active(record, game.state.turn):
			continue
		var target := _safe_tile(game, unit)
		if target < 0:
			continue
		var from := unit.tile
		unit.tile = target
		unit.orders = {}
		unit.fortify_turns = 0
		deadlines.erase(key)
		events.append({"type": "unit_moved", "unit": unit.id, "from": from, "to": target})
		events.append({"type": "unit_relocated", "unit": unit.id, "player": pid})


static func _safe_tile(game: Game, unit: Unit) -> int:
	var best := -1
	var distance := 2147483647
	for tile in game.state.map.size():
		var d := game.state.map.grid.distance(unit.tile, tile)
		if d >= distance:
			continue
		var owner := _owner(game, tile)
		if _closed(game, unit.owner, owner) or (owner >= 0 and game.state.at_war(unit.owner, owner)):
			continue
		if Movement.can_stand(game, unit, tile) and Movement.occupancy_allows(game, unit, tile, true):
			distance = d
			best = tile
	return best


static func close_round(game: Game, events: Array = []) -> void:
	var turn := game.state.turn
	var active := _collection(game, "active")
	var history := _collection(game, "history")
	for key in history.keys():
		var recent: Array = []
		for sample in history[key]:
			if int(sample["turn"]) > turn - int(game.data.diplomacy["demand_window"]):
				recent.append(sample)
		if recent.is_empty():
			history.erase(key)
		else:
			history[key] = recent
	for key in active:
		var treaty: Dictionary = active[key]
		var a: int = treaty["from"]
		var b: int = treaty["to"]
		if treaty["kind"] == "passage" or not _active(treaty, turn) \
				or not _valid_pair(game, a, b) or game.state.at_war(a, b):
			continue
		if treaty["kind"] == "alliance" and _active(treaty, turn + 1):
			var current_level := alliance_level(game, a, b, turn)
			var next_level := alliance_level(game, a, b, turn + 1)
			if next_level > current_level:
				events.append({"type": "alliance_leveled", "from": a, "to": b, "level": next_level})
		var pair := _key("friendship", a, b)
		var samples: Array = history.get(pair, [])
		samples.append({"turn": turn, "kind": treaty["kind"],
			"level": alliance_level(game, a, b, turn) if treaty["kind"] == "alliance" else 0})
		history[pair] = samples
	for collection in ["active", "offers", "cooldowns", "reputation"]:
		var records := _collection(game, collection)
		for key in records.keys():
			if not _active(records[key], turn + 1):
				records.erase(key)
	var deadlines := _collection(game, "withdrawal")
	for key in deadlines.keys():
		if game.state.unit(int(key)) == null:
			deadlines.erase(key)


static func influence_strength(game: Game, a: int, b: int) -> float:
	var total := 0.0
	var history: Array = _collection(game, "history").get(_key("friendship", a, b), [])
	for sample in history:
		var setting := "alliance_strength" if sample["kind"] == "alliance" else "friendship_strength"
		var strength := float(game.data.diplomacy[setting])
		if sample["kind"] == "alliance":
			var weights: Array = game.data.diplomacy["alliance_influence_by_level"]
			strength *= float(weights[clampi(int(sample.get("level", 1)) - 1, 0, weights.size() - 1)])
		total += strength
	return total / maxf(1.0, float(game.data.diplomacy["demand_window"]))
