class_name ImprovementRules
extends RefCounted
## Строители и улучшения клеток (ГДД 8).


static func _has_ability(game: Game, u: Unit, ability: String) -> bool:
	return game.data.unit_def(u.type).get("abilities", []).has(ability)


static func _placement_ok(game: Game, p: Player, tile: int, placement: Dictionary) -> bool:
	var map := game.state.map
	if placement.has("terrain") and not placement["terrain"].has(map.terrain[tile]):
		return false
	if placement.has("feature"):
		if not placement["feature"].has(map.feature[tile]):
			return false
	elif map.feature[tile] != "":
		return false
	var rel: String = placement.get("relief", "FLAT")
	if rel == "FLAT" and map.relief[tile] != GameMap.RELIEF_FLAT:
		return false
	if rel == "HILLS" and map.relief[tile] != GameMap.RELIEF_HILLS:
		return false
	if rel == "ANY" and map.is_mountain(tile):
		return false
	if placement.has("civic") and not p.has_civic(placement["civic"]):
		return false
	if placement.has("tech") and not p.has_tech(placement["tech"]):
		return false
	return true


## Пустая строка — строитель может построить улучшение на своей клетке; иначе причина.
static func build_error(game: Game, u: Unit, imp_id: String) -> String:
	if not _has_ability(game, u, "BUILD_IMPROVEMENT"):
		return "Этот юнит не строит улучшения"
	if u.charges <= 0:
		return "Нет зарядов"
	var def: Dictionary = game.data.improvements.get(imp_id, {})
	if def.is_empty():
		return "Неизвестное улучшение"
	var tile := u.tile
	var map := game.state.map
	var p := game.state.player(u.owner)
	var city := game.state.city_owning(tile)
	if city == null or city.owner != u.owner:
		return "Строить можно только на своей территории"
	if game.state.city_at(tile) != null:
		return "В центре города улучшения не строятся"
	if def.has("tech") and not p.has_tech(def["tech"]):
		return "Нужна технология: %s" % game.data.techs.get(def["tech"], {}).get("name", def["tech"])
	if map.improvement[tile] == imp_id:
		return "Уже построено"
	var rid := map.resource[tile]
	if rid != "" and Yields.resource_visible(game.data, rid, p):
		if game.data.resources[rid].get("improvement", "") == imp_id:
			return ""
		return "На этом ресурсе строится: %s" % game.data.improvements.get(
			game.data.resources[rid].get("improvement", ""), {}).get("name", "другое улучшение")
	if def.get("resource_only", false):
		return "Строится только на подходящем ресурсе"
	for pl in def.get("placements", []):
		if _placement_ok(game, p, tile, pl):
			return ""
	return "Здесь нельзя построить"


static func valid_improvements(game: Game, u: Unit) -> Array[String]:
	var result: Array[String] = []
	for iid in game.data.improvement_ids:
		if build_error(game, u, iid) == "":
			result.append(iid)
	return result


static func _spend_charge(game: Game, u: Unit, events: Array) -> void:
	u.charges -= 1
	u.moves_left = 0.0
	u.acted = true
	if u.charges <= 0:
		events.append({"type": "unit_consumed", "unit": u.id})
		game.state.remove_unit(u.id)


static func build(game: Game, u: Unit, imp_id: String, events: Array) -> void:
	var tile := u.tile
	game.state.map.improvement[tile] = imp_id
	events.append({"type": "improvement_built", "tile": tile, "improvement": imp_id})
	var city := game.state.city_owning(tile)
	_spend_charge(game, u, events)
	if city != null:
		CityRules.assign_citizens(game, city)


# --- Сбор (вырубка, осушение, сбор бонусного ресурса) ----------------------------------------------

## Что даст сбор на клетке строителя: {} — нечего собирать; иначе {"what": "resource"|"feature", "yields": {...}}.
static func harvest_preview(game: Game, u: Unit) -> Dictionary:
	if not _has_ability(game, u, "BUILD_IMPROVEMENT") or u.charges <= 0:
		return {}
	var tile := u.tile
	var map := game.state.map
	var p := game.state.player(u.owner)
	var city := game.state.city_owning(tile)
	if city == null or city.owner != u.owner or game.state.city_at(tile) != null:
		return {}
	var h: Dictionary = game.data.harvest
	var known := p.known_techs.size() + p.known_civics.size()
	var amount := float(h.get("base", 20)) * (1.0 + float(h.get("per_known", 0.05)) * known) * CityRules.speed_mult(game)
	var rid := map.resource[tile]
	if rid != "" and Yields.resource_visible(game.data, rid, p) \
			and game.data.resources[rid].get("class", "") == h.get("resource_class", "bonus"):
		var ry: Dictionary = game.data.resources[rid].get("yields", {})
		var key := "food"
		for k in ry:
			key = k
			break
		return {"what": "resource", "yields": {key: roundf(amount)}}
	var fid := map.feature[tile]
	var shares: Dictionary = h.get("features", {})
	if fid != "" and shares.has(fid):
		var need: String = game.data.features[fid].get("removable_by", "")
		if need != "" and not p.has_tech(need):
			return {}
		var y := {}
		for k in shares[fid]:
			y[k] = roundf(amount * float(shares[fid][k]))
		return {"what": "feature", "yields": y}
	return {}


static func harvest(game: Game, u: Unit, events: Array) -> String:
	var pre := harvest_preview(game, u)
	if pre.is_empty():
		return "Здесь нечего собирать"
	var tile := u.tile
	var map := game.state.map
	var city := game.state.city_owning(tile)
	if pre["what"] == "resource":
		map.resource[tile] = ""
	else:
		map.feature[tile] = ""
		if map.improvement[tile] == "LUMBER_MILL":
			map.improvement[tile] = ""
	var y: Dictionary = pre["yields"]
	city.food_stored += float(y.get("food", 0))
	if y.has("production"):
		if city.queue.is_empty():
			city.overflow += float(y["production"])
		else:
			var key := City.item_key(city.queue[0])
			city.progress[key] = float(city.progress.get(key, 0.0)) + float(y["production"])
	game.state.player(u.owner).treasury += float(y.get("gold", 0))
	events.append({"type": "harvested", "tile": tile, "city": city.id, "yields": y})
	_spend_charge(game, u, events)
	CityRules.assign_citizens(game, city)
	return ""
