class_name GovernmentRules
extends RefCounted
## Формы правления, политические курсы и их эффекты.

const SLOT_TYPES := ["military", "economic", "diplomatic", "wildcard"]


static func active_government(game: Game, p: Player) -> Dictionary:
	var default_id: String = game.data.government_setup["default"]
	return game.data.governments.get(p.government, game.data.governments[default_id])


static func slots(def: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var counts: Dictionary = def["slots"]
	for type in SLOT_TYPES:
		for i in int(counts.get(type, 0)):
			result.append(type)
	return result


static func government_error(game: Game, p: Player, id: String) -> String:
	var def: Dictionary = game.data.governments.get(id, {})
	if def.is_empty():
		return "Неизвестная форма правления"
	if def.get("civic", "") != "" and not p.has_civic(def["civic"]):
		return "Нужно изучить: %s" % game.data.civics[def["civic"]]["name"]
	if active_government(game, p)["id"] == id:
		return "Эта форма правления уже действует"
	return ""


static func change_government(game: Game, p: Player, id: String) -> void:
	var pending := p.policy_slots.duplicate()
	p.government = id
	var types := slots(active_government(game, p))
	p.policy_slots.clear()
	for type in types:
		var selected := ""
		for policy in pending:
			if policy != "" and fits(game, type, policy):
				selected = policy
				break
		p.policy_slots.append(selected)
		if selected != "":
			pending.erase(selected)


static func fits(game: Game, type: String, id: String) -> bool:
	var def: Dictionary = game.data.policies.get(id, {})
	return not def.is_empty() and (type == "wildcard" or def["slot"] == type)


static func policy_at(p: Player, index: int) -> String:
	return p.policy_slots[index] if index >= 0 and index < p.policy_slots.size() else ""


static func policy_error(game: Game, p: Player, index: int, id: String) -> String:
	var types := slots(active_government(game, p))
	if index < 0 or index >= types.size():
		return "Нет такого слота"
	if policy_at(p, index) == id:
		return "Слот уже в этом состоянии"
	if id == "":
		return ""
	if not fits(game, types[index], id):
		return "Курс не подходит для этого слота"
	if not p.has_civic(game.data.policies[id]["civic"]):
		return "Курс ещё не открыт"
	if p.policy_slots.has(id):
		return "Этот курс уже действует в другом слоте"
	return ""


static func set_policy(p: Player, index: int, id: String) -> void:
	while p.policy_slots.size() <= index:
		p.policy_slots.append("")
	p.policy_slots[index] = id


static func effects(game: Game, p: Player) -> Array[Dictionary]:
	var result: Array[Dictionary] = [active_government(game, p)]
	for id in p.policy_slots:
		if game.data.policies.has(id):
			result.append(game.data.policies[id])
	return result


static func apply_city_yields(game: Game, city: City, yields: Dictionary) -> void:
	for effect in effects(game, game.state.player(city.owner)):
		if effect.get("capital_only", false) and not city.is_capital:
			continue
		var required: String = effect.get("requires_district", "")
		if required != "" and DistrictRules.of_type(city, required, true).is_empty():
			continue
		Yields.add_into(yields, effect.get("yields", {}))


static func sum_effect(game: Game, pid: int, key: String) -> float:
	var result := 0.0
	for effect in effects(game, game.state.player(pid)):
		result += float(effect.get(key, 0.0))
	return result


static func production_multiplier(game: Game, pid: int, item: Dictionary) -> float:
	var bonus := 0.0
	var kind: String = item.get("kind", "")
	var id: String = item.get("id", "")
	for effect in effects(game, game.state.player(pid)):
		if not effect.has("production_bonus"):
			continue
		var applies := false
		if kind == "unit":
			var def := game.data.unit_def(id)
			applies = id in effect.get("production_units", []) \
				or def.get("class", "") in effect.get("production_classes", []) \
				or (effect.has("production_domain") and def.get("domain", "") == effect["production_domain"])
			if effect.has("production_eras") and EmpireRules.unit_era(game, id) not in effect["production_eras"]:
				applies = false
		elif kind in ["district", "district_upgrade"]:
			applies = id in effect.get("production_districts", [])
		if applies:
			bonus += float(effect["production_bonus"])
	return 1.0 + bonus


static func add_route_yields(game: Game, pid: int, international: bool, result: Dictionary) -> void:
	for effect in effects(game, game.state.player(pid)):
		Yields.add_into(result, effect.get("route_yields", {}))
		if international:
			Yields.add_into(result, effect.get("international_route_yields", {}))


static func upkeep_delta(game: Game, pid: int) -> float:
	var result := 0.0
	for effect in effects(game, game.state.player(pid)):
		result += float(effect.get("unit_upkeep", 0))
	return result


static func effect_text(def: Dictionary) -> String:
	var names := {"food": "пища", "production": "производство", "gold": "золото",
		"science": "наука", "culture": "культура", "faith": "вера"}
	var parts: PackedStringArray = []
	for key in def.get("yields", {}):
		var amount := float(def["yields"][key])
		parts.append("%+.1f %s" % [amount, names[key]])
	if not parts.is_empty():
		parts.append("в столице" if def.get("capital_only", false) else str(def.get("district_label", "в каждом городе")))
	if def.has("unit_upkeep"):
		parts.append("%+.1f золота к содержанию за юнит" % float(def["unit_upkeep"]))
	if def.has("barbarian_strength"):
		parts.append("%+d к силе против варваров" % int(def["barbarian_strength"]))
	if def.has("production_bonus"):
		parts.append("+%d%% к производству %s" % [
			roundi(100.0 * float(def["production_bonus"])), def["production_label"]])
	if def.has("tile_discount"):
		parts.append("−%d%% к цене клеток" % roundi(100.0 * float(def["tile_discount"])))
	if def.has("upgrade_discount"):
		parts.append("−%d%% к цене модернизации" % roundi(100.0 * float(def["upgrade_discount"])))
	if def.has("builder_charges"):
		parts.append("+%d заряда новым строителям" % int(def["builder_charges"]))
	for key in ["route_yields", "international_route_yields"]:
		for yield_name in def.get(key, {}):
			var suffix := "международного пути" if key == "international_route_yields" else "торгового пути"
			parts.append("%+.1f %s от %s" % [float(def[key][yield_name]), names[yield_name], suffix])
	return " · ".join(parts)


static func validate_data(data: GameData) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not data.governments.has(data.government_setup.get("default", "")):
		errors.append("Не задано начальное правительство")
	for def in data.governments.values():
		if def.has("civic") and not data.civics.has(def["civic"]):
			errors.append("Неизвестный институт правительства: %s" % def["id"])
		for type in def.get("slots", {}):
			if type not in SLOT_TYPES or int(def["slots"][type]) < 0:
				errors.append("Некорректный слот правительства: %s" % def["id"])
	for def in data.policies.values():
		if def.get("slot", "") not in SLOT_TYPES or not data.civics.has(def.get("civic", "")):
			errors.append("Некорректная настройка курса: %s" % def["id"])
	return errors
