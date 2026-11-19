class_name EmpireRules
extends RefCounted
## Уровень державы: доходы, казна, содержание, исследования (ГДД 2, 4.3–4.6, 21, 22).

const BOOST_CONDITIONS := ["met_major", "stat", "known_tech", "known_civic", "pantheon", "religion",
	"government_slots", "treasury", "alliances", "trade_routes", "units", "revealed_continents",
	"revealed_mountain", "other_continent_city", "renewable_sources", "coastal_city", "cities",
	"population", "city_population", "city_buildings", "religious_cities", "parks", "great_works",
	"wonders", "districts", "distinct_districts", "specialized_district", "improvements"]


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
	Yields.add_into(total, ReligionRules.founder_yields(game, pid))
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

static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	for definitions in [data.techs, data.civics]:
		for id in definitions:
			var def: Dictionary = definitions[id]
			if def.get("future_shuffled", false) or def.get("repeatable", false):
				continue
			var boost: Dictionary = def.get("boost", {})
			if def.has("boost_text") and boost.is_empty():
				errors.append("Условия эврики/вдохновения нет: %s" % id)
			if boost.is_empty():
				continue
			var condition := str(boost.get("condition", ""))
			if condition not in BOOST_CONDITIONS or int(boost.get("minimum", 1)) < 1:
				errors.append("Неверное условие эврики/вдохновения: %s" % id)
			var target := str(boost.get("id", ""))
			if (condition == "known_tech" and not data.techs.has(target)) \
					or (condition == "known_civic" and not data.civics.has(target)) \
					or (condition == "units" and target != "" and not data.units.has(target)) \
					or (condition == "districts" and target != "" and not data.districts.has(target)) \
					or (condition == "improvements" and target != "" and not data.improvements.has(target)):
				errors.append("Неизвестный объект эврики/вдохновения: %s" % id)
	return errors

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


static func record_research_events(game: Game, events: Array) -> void:
	for event in events:
		var pid := int(event.get("player", event.get("by", -1)))
		if pid < 0 or pid >= game.state.players.size() or game.state.player(pid).is_barbarian:
			continue
		var p := game.state.player(pid)
		match str(event.get("type", "")):
			"unit_killed":
				_add_research_stat(p, "unit_kills")
				if event.has("by_unit_type"):
					_add_research_stat(p, "kills_as:" + str(event["by_unit_type"]))
				var owner := int(event.get("owner", -1))
				if owner >= 0 and owner < game.state.players.size() and game.state.player(owner).is_barbarian:
					_add_research_stat(p, "barbarian_kills")
			"camp_cleared", "trade_started", "wonder_completed":
				_add_research_stat(p, str(event["type"]))
			"great_person_recruited":
				_add_research_stat(p, "great_people")
				_add_research_stat(p, "great_person:" + str(event.get("kind", "")))


static func _add_research_stat(p: Player, key: String) -> void:
	p.research_stats[key] = int(p.research_stats.get(key, 0)) + 1


static func _boost_reached(game: Game, pid: int, boost: Dictionary) -> bool:
	var condition: String = str(boost.get("condition", ""))
	var p := game.state.player(pid)
	var total := 0
	var minimum := int(boost.get("minimum", 1))
	var wanted := str(boost.get("id", ""))
	match condition:
		"met_major":
			return p.met.size() >= minimum
		"stat":
			return int(p.research_stats.get(wanted, 0)) >= minimum
		"known_tech":
			return p.has_tech(wanted)
		"known_civic":
			return p.has_civic(wanted)
		"pantheon":
			return p.pantheon != ""
		"religion":
			return p.religion_id != ""
		"government_slots":
			return GovernmentRules.slots(GovernmentRules.active_government(game, p)).size() >= minimum
		"treasury":
			return p.treasury >= minimum
		"alliances":
			for other in game.state.players:
				if other.id != pid and not other.is_barbarian and TreatyRules.alliance_level(game, pid, other.id) > 0:
					total += 1
			return total >= minimum
		"trade_routes":
			for unit in game.state.units_of(pid):
				if not unit.trade_route.is_empty():
					total += 1
			return total >= minimum
		"units":
			for unit in game.state.units_of(pid):
				if wanted != "" and unit.type != wanted:
					continue
				var def: Dictionary = game.data.unit_def(unit.type)
				if boost.has("class") and def.get("class", "") != boost["class"]:
					continue
				if boost.get("combat", false) and def.get("class", "") in ["CIVILIAN", "SUPPORT", "RELIGIOUS"]:
					continue
				if boost.has("domain") and def.get("domain", "") != boost["domain"]:
					continue
				total += 1
			return total >= minimum
		"revealed_continents":
			var seen := {}
			for tile in game.state.map.terrain.size():
				var continent := game.state.map.continent[tile]
				if continent >= 0 and p.is_revealed(tile):
					seen[continent] = true
			return seen.size() >= minimum
		"revealed_mountain":
			for tile in game.state.map.terrain.size():
				if p.is_revealed(tile) and game.state.map.relief[tile] == GameMap.RELIEF_MOUNTAIN:
					return true
			return false
		"other_continent_city":
			var capital_continent := -1
			for city in game.state.cities_of(pid):
				if city.is_capital:
					capital_continent = game.state.map.continent[city.tile]
					break
			if capital_continent < 0:
				return false
			for city in game.state.cities_of(pid):
				if game.state.map.continent[city.tile] >= 0 and game.state.map.continent[city.tile] != capital_continent:
					total += 1
			return total >= minimum
		"renewable_sources":
			for tile in game.state.map.improvement.size():
				if game.state.map.owner_city[tile] < 0 or game.state.city(game.state.map.owner_city[tile]).owner != pid:
					continue
				if game.state.map.pillaged[tile] == 0 and game.state.map.improvement[tile] in ["WIND_FARM", "SOLAR_FARM"]:
					total += 1
			return total >= minimum
	var distinct := {}
	for city in game.state.cities_of(pid):
		match condition:
			"coastal_city":
				if game.state.map.is_coastal_land(city.tile):
					return true
			"cities":
				total += 1
			"population":
				total += city.population
			"city_population":
				if city.population >= minimum:
					return true
			"city_buildings":
				if city.buildings.has(wanted):
					total += 1
			"religious_cities":
				if p.religion_id != "" and ReligionRules.majority(game, city) == p.religion_id:
					total += 1
			"parks":
				total += city.parks.size()
			"great_works":
				total += city.great_works
			"wonders":
				for wonder in city.wonders:
					if wonder.get("complete", false):
						total += 1
			"districts", "distinct_districts", "specialized_district":
				for district in city.districts:
					if not district.get("complete", false):
						continue
					if condition == "specialized_district":
						if game.data.districts.get(district["type"], {}).get("specialized", false):
							return true
					elif condition == "distinct_districts" and not game.data.districts.get(district["type"], {}).get("specialized", false):
						continue
					elif (wanted == "" or district["type"] == wanted) and int(district["tier"]) >= int(boost.get("tier", 1)):
						total += 1
						distinct[district["type"]] = true
			"improvements":
				for tile in CityRules.owned_tiles(game, city):
					var improvement := game.state.map.improvement[tile]
					if improvement != "" and game.state.map.pillaged[tile] == 0 and \
							not game.data.improvements.get(improvement, {}).get("special", false) \
							and improvement == str(boost.get("id", improvement)) \
							and (not boost.has("resource") or game.state.map.resource[tile] == boost["resource"]) \
							and (not boost.get("any_resource", false) or game.state.map.resource[tile] != ""):
						total += 1
		if condition != "distinct_districts" and total >= minimum:
			return true
	return distinct.size() >= minimum if condition == "distinct_districts" else false


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
	if kind == "civic":
		p.culture_total += maxf(0.0, amount)
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
	UnitRules.process_stockpile(game, pid)
	EnergyRules.process_turn(game, pid, events)
	# 1. Доходы державы.
	var sum := summary(game, pid)
	var y: Dictionary = sum["yields"]
	p.treasury += float(sum["net_gold"])
	p.faith += float(y.get("faith", 0.0))
	ReligionRules.process_turn(game, pid)
	GreatPeopleRules.process_turn(game, pid)
	if not cities.is_empty():
		apply_research_boosts(game, pid, events)
		add_research(game, pid, "tech", float(y.get("science", 0.0)), events)
		add_research(game, pid, "civic", float(y.get("culture", 0.0)), events)
	# Пусть результат текущего исследования (если оно завершилось) сразу засчитается.
	if p.treasury < 0.0:
		_bankruptcy(game, pid, events)
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
		if p.pantheon == "" and p.faith >= float(ReligionRules.cfg(game, "pantheon_faith_cost")) and not ReligionRules.pantheon_options(game).is_empty():
			result.append({"type": "choose_pantheon", "text": "Выберите пантеон"})
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
