class_name DiplomaticVisibility
extends RefCounted
## Направленная дипломатическая видимость между встреченными державами.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	var cfg: Dictionary = data.visibility_setup
	if not data.civics.has(str(cfg.get("embassy_civic", ""))):
		errors.append("Дипломатическая видимость: неизвестный институт посольства")
	if not data.techs.has(str(cfg.get("printing_tech", ""))):
		errors.append("Дипломатическая видимость: неизвестная технология")
	for key in ["delegation_cost", "max_level", "highest_alliance_max_level", "finance_exact_level",
			"combat_per_level", "representation_trust", "research_disclosure_level", "production_disclosure_level"]:
		if int(cfg.get(key, 0)) <= 0:
			errors.append("Дипломатическая видимость: неверное значение %s" % key)
	if int(cfg.get("highest_alliance_max_level", 0)) <= int(cfg.get("max_level", 0)):
		errors.append("Дипломатическая видимость: развитый союз должен повышать предел")
	if int(cfg.get("research_disclosure_level", 0)) > int(cfg.get("max_level", 0)) or \
			int(cfg.get("production_disclosure_level", 0)) > int(cfg.get("highest_alliance_max_level", 0)):
		errors.append("Дипломатическая видимость: сведения превышают предел уровня")
	return errors


static func _key(a: int, b: int) -> String:
	return "%d,%d" % [a, b]


static func _pair(a: int, b: int) -> String:
	return _key(mini(a, b), maxi(a, b))


static func has_delegation(game: Game, from: int, to: int) -> bool:
	return bool(game.state.visibility_data["delegations"].get(_key(from, to), false))


static func has_embassy(game: Game, a: int, b: int) -> bool:
	return bool(game.state.visibility_data["embassies"].get(_pair(a, b), false))


static func representation_trust(game: Game, viewer: int, subject: int) -> int:
	if _pair_error(game, viewer, subject) != "":
		return 0
	return int(game.data.visibility_setup["representation_trust"]) if \
			(has_delegation(game, viewer, subject) or has_embassy(game, viewer, subject)) else 0


static func _pair_error(game: Game, from: int, to: int) -> String:
	if from == to or mini(from, to) < 0 or maxi(from, to) >= game.state.players.size():
		return "Нет такой державы"
	var me := game.state.player(from)
	var other := game.state.player(to)
	if me.is_barbarian or other.is_barbarian or not me.alive or not other.alive:
		return "Дипломатическое представительство недоступно"
	if not me.met.has(to) or not other.met.has(from):
		return "Нужно установить контакт"
	if game.state.at_war(from, to):
		return "Во время войны представительство невозможно"
	return ""


static func delegation_error(game: Game, from: int, to: int) -> String:
	var error := _pair_error(game, from, to)
	if error != "":
		return error
	if has_delegation(game, from, to) or has_embassy(game, from, to):
		return "Представительство уже отправлено"
	if game.state.player(from).treasury < int(game.data.visibility_setup["delegation_cost"]):
		return "Недостаточно золота для делегации"
	return ""


static func send_delegation(game: Game, from: int, to: int, events: Array) -> String:
	var error := delegation_error(game, from, to)
	if error != "":
		return error
	game.state.player(from).treasury -= int(game.data.visibility_setup["delegation_cost"])
	game.state.visibility_data["delegations"][_key(from, to)] = true
	events.append({"type": "delegation_sent", "player": from, "target": to})
	return ""


static func embassy_error(game: Game, from: int, to: int) -> String:
	var error := _pair_error(game, from, to)
	if error != "":
		return error
	if has_embassy(game, from, to):
		return "Посольства уже открыты"
	if not has_delegation(game, from, to) or not has_delegation(game, to, from):
		return "Для обмена посольствами нужны взаимные делегации"
	var civic := str(game.data.visibility_setup["embassy_civic"])
	if not game.state.player(from).has_civic(civic) or not game.state.player(to).has_civic(civic):
		return "Обеим державам нужна «Дипломатическая служба»"
	return ""


static func establish_embassy(game: Game, from: int, to: int, events: Array) -> String:
	var error := embassy_error(game, from, to)
	if error != "":
		return error
	game.state.visibility_data["embassies"][_pair(from, to)] = true
	events.append({"type": "embassies_opened", "player": from, "target": to})
	return ""


static func on_war(game: Game, a: int, b: int) -> void:
	game.state.visibility_data["delegations"].erase(_key(a, b))
	game.state.visibility_data["delegations"].erase(_key(b, a))
	game.state.visibility_data["embassies"].erase(_pair(a, b))


static func _has_route(game: Game, from: int, to: int) -> bool:
	for unit in game.state.units_of(from):
		if unit.trade_route.is_empty():
			continue
		var destination := game.state.city(int(unit.trade_route.get("destination", -1)))
		if destination != null and destination.owner == to:
			return true
	return false


static func sources(game: Game, from: int, to: int) -> Dictionary:
	if from == to or mini(from, to) < 0 or maxi(from, to) >= game.state.players.size():
		return {"representation": false, "route": false, "alliance": false, "printing": false}
	if _pair_error(game, from, to) != "" and not game.state.at_war(from, to):
		return {"representation": false, "route": false, "alliance": false, "printing": false}
	var player := game.state.player(from)
	return {"representation": has_delegation(game, from, to) or has_embassy(game, from, to),
		"route": _has_route(game, from, to),
		"alliance": TreatyRules.until(game, "alliance", from, to) > game.state.turn,
		"printing": player.has_tech(str(game.data.visibility_setup["printing_tech"]))}


static func level(game: Game, from: int, to: int) -> int:
	var result := 0
	for enabled in sources(game, from, to).values():
		if enabled:
			result += 1
	return mini(result, maximum_level(game, from, to))


static func maximum_level(game: Game, from: int, to: int) -> int:
	if TreatyRules.alliance_level(game, from, to) >= 3:
		return int(game.data.visibility_setup["highest_alliance_max_level"])
	return int(game.data.visibility_setup["max_level"])


static func disclosed_plans(game: Game, viewer: int, subject: int) -> Dictionary:
	var sight := level(game, viewer, subject)
	var result := {}
	if sight >= int(game.data.visibility_setup["research_disclosure_level"]):
		var player := game.state.player(subject)
		result["tech"] = player.current_tech
		result["civic"] = player.current_civic
	if sight >= int(game.data.visibility_setup["production_disclosure_level"]):
		var production := {}
		for city in game.state.cities_of(subject):
			production[city.id] = city.queue[0].duplicate(true) if not city.queue.is_empty() else {}
		result["production"] = production
	return result


static func combat_bonus(game: Game, own: int, enemy: int) -> int:
	if own < 0 or enemy < 0 or own == enemy or maxi(own, enemy) >= game.state.players.size() \
			or game.state.player(own).is_barbarian or game.state.player(enemy).is_barbarian:
		return 0
	return maxi(0, level(game, own, enemy) - level(game, enemy, own)) \
		* int(game.data.visibility_setup["combat_per_level"])
