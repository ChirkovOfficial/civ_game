class_name EmpireRules
extends RefCounted
## Уровень державы: доходы, казна, содержание, исследования (ГДД 2, 4.3–4.6, 21, 22).


# --- Доходы державы ---------------------------------------------------------------------------

## Сводка за ход: доходы по типам, содержание, чистое золото.
static func summary(game: Game, pid: int) -> Dictionary:
	var total := {}
	for t in Yields.TYPES:
		total[t] = 0.0
	var lux := CityRules.luxury_amenities(game, pid)
	for city in game.state.cities_of(pid):
		var y := CityRules.city_yields(game, city, lux)
		for k in y:
			if k != "food" and k != "production":
				total[k] = float(total.get(k, 0.0)) + float(y[k])
	var upkeep := maintenance(game, pid)
	return {
		"yields": total,
		"maintenance": upkeep,
		"net_gold": float(total["gold"]) - upkeep,
	}


static func unit_era(game: Game, unit_type: String) -> String:
	var def := game.data.unit_def(unit_type)
	if def.has("tech"):
		return game.data.techs.get(def["tech"], {}).get("era", "START")
	if def.has("civic"):
		return game.data.civics.get(def["civic"], {}).get("era", "START")
	return "START"


static func unit_maintenance(game: Game, unit_type: String) -> float:
	var def := game.data.unit_def(unit_type)
	if def.has("maintenance_gold"):
		return float(def["maintenance_gold"])
	if def.get("class", "") == "CIVILIAN":
		return 0.0
	var table: Dictionary = game.data.const_value("unit_maintenance_by_era", {})
	return float(table.get(unit_era(game, unit_type), 0))


static func maintenance(game: Game, pid: int) -> float:
	var m := 0.0
	var delta := GovernmentRules.upkeep_delta(game, pid)
	for u in game.state.units_of(pid):
		m += _effective_unit_upkeep(game, u, delta)
	for city in game.state.cities_of(pid):
		for bid in city.buildings:
			m += float(game.data.buildings.get(bid, {}).get("maintenance", 0))
		for d in city.districts:
			m += DistrictRules.maintenance(game, d)
		m += float(CityLife.doctrine_upkeep(game, city)["gold"])
	return m


static func _effective_unit_upkeep(game: Game, u: Unit, delta: float) -> float:
	var upkeep := maxf(0.0, unit_maintenance(game, u.type) + delta)
	if not u.commander.is_empty():
		upkeep += maxf(0.0, unit_maintenance(game, "COMMANDER") + delta)
	return upkeep


# --- Исследования -----------------------------------------------------------------------------

## Уникальная технология занимает тот же узел и сохраняет его идентификатор в сохранениях.
static func tech_display(game: Game, pid: int, tech_id: String) -> Dictionary:
	var def: Dictionary = game.data.techs.get(tech_id, {})
	var variant: Dictionary = Abilities.civ_def(game, pid).get("tech_overrides", {}).get(tech_id, {})
	return def if variant.is_empty() else def.merged(variant, true)


static func tech_cost(game: Game, tech_id: String) -> float:
	return roundf(float(game.data.techs.get(tech_id, {}).get("cost", 0)) * CityRules.speed_mult(game))


static func civic_cost(game: Game, civic_id: String) -> float:
	return roundf(float(game.data.civics.get(civic_id, {}).get("cost", 0)) * CityRules.speed_mult(game))


## При объединении узлов сохраняем открытие и наибольший накопленный прогресс.
static func migrate_research(player: Player, data: GameData) -> void:
	player.current_tech = _migrate_tree(player.known_techs, player.tech_progress, player.current_tech, data.legacy_techs)
	player.current_civic = _migrate_tree(player.known_civics, player.civic_progress, player.current_civic, data.legacy_civics)


static func _migrate_tree(known: Dictionary, progress: Dictionary, current: String, aliases: Dictionary) -> String:
	for old_id in aliases:
		var id: String = aliases[old_id]
		if known.erase(old_id):
			known[id] = true
		if progress.has(old_id):
			progress[id] = maxf(float(progress.get(id, 0.0)), float(progress[old_id]))
			progress.erase(old_id)
	var next: String = aliases.get(current, current)
	if known.has(next):
		progress["_overflow"] = float(progress.get("_overflow", 0.0)) + float(progress.get(next, 0.0))
		progress.erase(next)
		next = ""
	return next


static func apply_research_boosts(game: Game, pid: int, events: Array) -> void:
	var p := game.state.player(pid)
	for kind in ["tech", "civic"]:
		var definitions := game.data.techs if kind == "tech" else game.data.civics
		var ids := game.data.tech_ids if kind == "tech" else game.data.civic_ids
		var known := p.known_techs if kind == "tech" else p.known_civics
		var progress := p.tech_progress if kind == "tech" else p.civic_progress
		for id in ids:
			var boost: Dictionary = definitions[id].get("boost", {})
			if boost.is_empty() or known.has(id):
				continue
			var key := "%s:%s" % [kind, id]
			if p.research_boosts.has(key) or not _boost_reached(game, pid, boost):
				continue
			var cost := tech_cost(game, id) if kind == "tech" else civic_cost(game, id)
			var amount := cost * float(game.data.const_value("research_boost_fraction", 0.4))
			# Эврика ускоряет только свой узел, не пополняя общий запас.
			progress[id] = minf(cost, float(progress.get(id, 0.0)) + amount)
			p.research_boosts[key] = true
			events.append({"type": "research_boost", "player": pid, "kind": kind, "id": id})


static func _boost_reached(game: Game, pid: int, boost: Dictionary) -> bool:
	var condition: String = boost["condition"]
	if condition == "met_major":
		return not game.state.player(pid).met.is_empty()
	var total := 0
	var minimum := int(boost.get("minimum", 1))
	for city in game.state.cities_of(pid):
		match condition:
			"coastal_city":
				if game.state.map.is_coastal_land(city.tile):
					return true
			"population":
				total += city.population
			"specialized_district":
				for district in city.districts:
					if district["complete"] and game.data.districts.get(district["type"], {}).get("specialized", false):
						return true
			"improvements":
				for tile in CityRules.owned_tiles(game, city):
					var improvement := game.state.map.improvement[tile]
					if improvement != "" and game.state.map.pillaged[tile] == 0 and \
							not game.data.improvements.get(improvement, {}).get("special", false) \
							and improvement == str(boost.get("id", improvement)):
						total += 1
		if total >= minimum:
			return true
	return false


static func _available(tree: Dictionary, ids: Array[String], known: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		if known.has(id):
			continue
		var def: Dictionary = tree[id]
		if def.get("future_shuffled", false) or def.get("repeatable", false):
			continue   # эра будущего — веха M10
		var ok := true
		for pre in def.get("prereqs", []):
			if not known.has(pre):
				ok = false
				break
		if ok:
			result.append(id)
	return result


static func available_techs(game: Game, pid: int) -> Array[String]:
	return _available(game.data.techs, game.data.tech_ids, game.state.player(pid).known_techs)


static func available_civics(game: Game, pid: int) -> Array[String]:
	return _available(game.data.civics, game.data.civic_ids, game.state.player(pid).known_civics)


static func turns_left(cost: float, progress: float, per_turn: float) -> int:
	if per_turn <= 0.0:
		return -1
	return maxi(1, ceili((cost - progress) / per_turn))


## Вкладывает очки в текущее исследование. Переполнение идёт в следующее (хранится в прогрессе
## под ключом "_overflow" до выбора). kind: "tech" | "civic".
static func add_research(game: Game, pid: int, kind: String, amount: float, events: Array) -> void:
	var p := game.state.player(pid)
	var progress: Dictionary = p.tech_progress if kind == "tech" else p.civic_progress
	var current: String = p.current_tech if kind == "tech" else p.current_civic
	if current == "":
		progress["_overflow"] = float(progress.get("_overflow", 0.0)) + amount
		return
	progress[current] = float(progress.get(current, 0.0)) + amount
	var cost := tech_cost(game, current) if kind == "tech" else civic_cost(game, current)
	if float(progress[current]) < cost:
		return
	var extra := float(progress[current]) - cost
	progress.erase(current)
	progress["_overflow"] = float(progress.get("_overflow", 0.0)) + extra
	if kind == "tech":
		p.known_techs[current] = true
		p.current_tech = ""
		events.append({"type": "tech_researched", "player": pid, "tech": current})
	else:
		p.known_civics[current] = true
		p.current_civic = ""
		events.append({"type": "civic_completed", "player": pid, "civic": current})


## Выбор исследования: переносит накопленное переполнение в новый объект.
static func set_research(game: Game, pid: int, kind: String, id: String) -> String:
	var p := game.state.player(pid)
	var avail := available_techs(game, pid) if kind == "tech" else available_civics(game, pid)
	if not avail.has(id):
		return "Это исследование сейчас недоступно"
	var progress: Dictionary = p.tech_progress if kind == "tech" else p.civic_progress
	var ov := float(progress.get("_overflow", 0.0))
	progress.erase("_overflow")
	if kind == "tech":
		p.current_tech = id
	else:
		p.current_civic = id
	progress[id] = float(progress.get(id, 0.0)) + ov
	return ""


# --- Обработка начала хода (ГДД 2) ---------------------------------------------------------------

static func process_turn_start(game: Game, pid: int, events: Array) -> void:
	var p := game.state.player(pid)
	var cities := game.state.cities_of(pid)
	var lux := CityRules.luxury_amenities(game, pid)
	# 1. Доходы державы.
	var sum := summary(game, pid)
	var y: Dictionary = sum["yields"]
	p.treasury += float(sum["net_gold"])
	p.faith += float(y.get("faith", 0.0))
	if not cities.is_empty():
		apply_research_boosts(game, pid, events)
		add_research(game, pid, "tech", float(y.get("science", 0.0)), events)
		add_research(game, pid, "civic", float(y.get("culture", 0.0)), events)
	# Пусть результат текущего исследования (если оно завершилось) сразу засчитается.
	if p.treasury < 0.0:
		_bankruptcy(game, pid, events)
	UnitRules.process_stockpile(game, pid)
	# 2. Города: лечение и стены, рост, границы, производство.
	var hp_max := int(game.data.const_value("city_hp", 200))
	for city in cities:
		city.has_attacked = false
		if city.last_attacked_turn < game.state.turn - 1:
			city.hp = mini(hp_max, city.hp + int(game.data.const_value("city_heal", 20)))
		var wall_max := 0
		for bid in city.buildings:
			wall_max = maxi(wall_max, int(game.data.buildings.get(bid, {}).get("wall_hp", 0)))
		if city.wall_hp < wall_max and game.state.turn - city.last_attacked_turn >= int(game.data.const_value("wall_regen_delay", 3)):
			city.wall_hp = mini(wall_max, city.wall_hp + int(game.data.const_value("wall_regen", 25)))
	for city in cities:
		CityLife.process_city(game, city, events)
	for city in cities:
		var cy := CityRules.city_yields(game, city, lux)
		CityRules.process_growth(game, city, lux, events)
		CityRules.process_borders(game, city, float(cy.get("culture", 0.0)), events)
		CityRules.process_production(game, city, float(cy.get("production", 0.0)), events)
		CityRules.assign_citizens(game, city)


## Банкротство (ГДД 4.3): расформировать самый дорогой в содержании юнит.
static func _bankruptcy(game: Game, pid: int, events: Array) -> void:
	var worst: Unit = null
	var worst_cost := 0.0
	var delta := GovernmentRules.upkeep_delta(game, pid)
	for u in game.state.units_of(pid):
		var m := _effective_unit_upkeep(game, u, delta)
		if m > worst_cost:
			worst_cost = m
			worst = u
	if worst != null:
		events.append({"type": "unit_disbanded", "unit": worst.id, "player": pid, "reason": "bankruptcy"})
		game.state.remove_unit(worst.id)
	game.state.player(pid).treasury = 0.0


# --- Обязательные решения перед концом хода (ГДД 2) --------------------------------------------

## Список того, что мешает закончить ход: [{"type": ..., ...}].
static func blocking_decisions(game: Game, pid: int) -> Array:
	var result := []
	var p := game.state.player(pid)
	var cities := game.state.cities_of(pid)
	if not cities.is_empty():
		if p.current_tech == "" and not available_techs(game, pid).is_empty():
			result.append({"type": "choose_tech", "text": "Выберите исследование"})
		if p.current_civic == "" and not available_civics(game, pid).is_empty():
			result.append({"type": "choose_civic", "text": "Выберите институт"})
	for city in cities:
		if city.queue.is_empty():
			result.append({"type": "city_production", "city": city.id, "text": "Город %s ждёт производства" % city.name})
	for u in game.units_needing_orders(pid):
		result.append({"type": "unit_orders", "unit": u.id, "text": "Юнит ждёт приказа"})
	return result
