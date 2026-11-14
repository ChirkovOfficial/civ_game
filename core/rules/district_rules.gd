class_name DistrictRules
extends RefCounted
## Районы (ГДД 6, docs/CITIES.md).
##
## Район — запись в City.districts: {"type", "tile", "tier", "buildings": [], "complete", "cost"}.
## Клетка района отмечена в GameMap.district. Однотипных районов в городе может быть
## несколько; ограничения — лимит по населению и правило скоплений.

const CENTER := "CITY_CENTER"


static func k(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


static func ddef(game: Game, type: String) -> Dictionary:
	return game.data.districts.get(type, {})


static func is_specialized(game: Game, type: String) -> bool:
	return bool(ddef(game, type).get("specialized", true))


# --- Поиск -------------------------------------------------------------------------------------

## [город, запись района] для клетки или [] — района нет. Центр города — тоже «район».
static func at(game: Game, tile: int) -> Array:
	var map := game.state.map
	if map.district[tile] == "":
		return []
	var city := game.state.city_owning(tile)
	if city == null:
		return []
	if map.district[tile] == CENTER:
		return [city, {"type": CENTER, "tile": tile, "tier": 1, "buildings": city.buildings, "complete": true}]
	for d in city.districts:
		if int(d["tile"]) == tile:
			return [city, d]
	return []


static func of_type(city: City, type: String, only_complete: bool = false) -> Array:
	var result := []
	for d in city.districts:
		if d["type"] == type and (not only_complete or d["complete"]):
			result.append(d)
	return result


static func specialized_count(game: Game, city: City) -> int:
	var n := 0
	for d in city.districts:
		if is_specialized(game, d["type"]):
			n += 1
	return n


static func specialized_limit(city: City) -> int:
	return 1 + (city.population - 1) / 3


## Название района с учётом цивилизации и уровня (docs/CITIES.md).
static func display_name(game: Game, owner: int, type: String, tier: int = 1) -> String:
	var civ := Abilities.civ_def(game, owner)
	var names: Array = civ.get("district_names", {}).get(type, [])
	if not names.is_empty():
		return names[clampi(tier - 1, 0, names.size() - 1)]
	var tiers: Array = ddef(game, type).get("tiers", [])
	if tiers.size() >= tier and tier >= 1:
		return tiers[tier - 1].get("name", type)
	return ddef(game, type).get("name", "Центр города" if type == CENTER else type)


# --- Размещение ----------------------------------------------------------------------------------

static func _unlocked(p: Player, def: Dictionary) -> bool:
	if def.get("tech", "") != "" and not p.has_tech(def["tech"]):
		return false
	if def.get("civic", "") != "" and not p.has_civic(def["civic"]):
		return false
	return true


## Ошибка постройки района этого типа вообще (без учёта клетки).
static func type_error(game: Game, city: City, type: String) -> String:
	var def := ddef(game, type)
	if def.is_empty():
		return "Нет такого района"
	var p := game.state.player(city.owner)
	if not _unlocked(p, def):
		return "Не открыто"
	if is_specialized(game, type) and specialized_count(game, city) >= specialized_limit(city):
		return "Лимит районов: нужно больше жителей (сейчас %d из %d)" % [specialized_count(game, city), specialized_limit(city)]
	if def.get("placement", {}).get("one_per_civ", false):
		for c in game.state.cities_of(city.owner):
			if not of_type(c, type).is_empty():
				return "Такой район может быть только один на державу"
	var excl: String = def.get("exclusive_with", "")
	if excl != "" and not of_type(city, excl).is_empty():
		return "Нельзя вместе с районом «%s»" % display_name(game, city.owner, excl)
	for other in game.data.districts:
		if ddef(game, other).get("exclusive_with", "") == type and not of_type(city, other).is_empty():
			return "Нельзя вместе с районом «%s»" % display_name(game, city.owner, other)
	return ""


## Пустая строка — можно поставить район на клетку.
static func placement_error(game: Game, city: City, type: String, tile: int) -> String:
	var err := type_error(game, city, type)
	if err != "":
		return err
	var map := game.state.map
	var def := ddef(game, type)
	var pl: Dictionary = def.get("placement", {})
	if map.owner_city[tile] != city.id:
		return "Клетка должна принадлежать городу"
	if map.grid.distance(city.tile, tile) > int(k(game, "city_work_radius", 3)):
		return "Слишком далеко от центра (не дальше 3 клеток)"
	if map.district[tile] != "" or map.is_mountain(tile):
		return "Клетка занята"
	if map.feature_def(tile).get("impassable", false):
		return "Здесь нельзя строить"
	var rid := map.resource[tile]
	if rid != "" and game.data.resources[rid].get("class", "") != "bonus":
		return "На редком или стратегическом ресурсе район не строится"
	for u in game.state.units_at(tile):
		if u.owner != city.owner:
			return "Клетку занимает чужой юнит"
	if pl.get("water", false):
		if not map.is_water(tile) or map.terrain[tile] == "OCEAN":
			return "Строится на прибрежной воде"
		var near_land := false
		for nb in map.grid.neighbors(tile):
			if map.is_land(nb):
				near_land = true
		if not near_land:
			return "Нужна суша рядом"
	elif map.is_water(tile):
		return "Строится на суше"
	if pl.get("flat", false) and map.relief[tile] != GameMap.RELIEF_FLAT:
		return "Нужна ровная клетка"
	if pl.get("not_adjacent_city_center", false) and map.grid.distance(city.tile, tile) <= 1:
		return "Не вплотную к центру города"
	if pl.has("feature") and map.feature[tile] != pl["feature"]:
		return "Нужна особенность: %s" % game.data.features.get(pl["feature"], {}).get("name", pl["feature"])
	if pl.has("river_edges"):
		var edges := 0
		for dir in 6:
			if map.has_river_edge(tile, dir):
				edges += 1
		if edges < int(pl["river_edges"]):
			return "Река должна проходить по %d рёбрам клетки" % int(pl["river_edges"])
	if pl.get("needs_fresh_or_mountain", false):
		var ok := map.has_river(tile)
		for nb in map.grid.neighbors(tile):
			if map.is_mountain(nb) or map.terrain[nb] == "LAKE" or map.feature[nb] == "OASIS":
				ok = true
		if not ok:
			return "Нужна река, озеро, оазис или гора рядом"
	if pl.has("requires_adjacent_any"):
		var ok2 := false
		for nb in map.grid.neighbors(tile):
			var a := at(game, nb)
			for req in pl["requires_adjacent_any"]:
				var r: String = req
				if r == CENTER and nb == city.tile:
					ok2 = true
				elif r.begins_with("BUILDING:") and not a.is_empty() and a[1]["buildings"].has(r.substr(9)):
					ok2 = true
				elif r.begins_with("DISTRICT_TIER:") and not a.is_empty():
					var parts := r.split(":")
					if a[1]["type"] == parts[1] and a[1].get("complete", false) and int(a[1].get("tier", 1)) >= int(parts[2]):
						ok2 = true
		if not ok2:
			return "Нужно соседство с центром города или Банком (Коммерческий центр II уровня)"
	# Дистанция между однотипными (акведуки, плотины) или правило скоплений.
	if pl.has("min_same_distance"):
		for c in game.state.cities_of(city.owner):
			for d in of_type(c, type):
				if map.grid.distance(int(d["tile"]), tile) < int(pl["min_same_distance"]):
					return "Не ближе %d клеток к другому такому району" % int(pl["min_same_distance"])
	else:
		var ce := cluster_error(game, city.owner, type, tile)
		if ce != "":
			return ce
	return ""


## Правило скоплений (docs/CITIES.md): связная группа однотипных районов — не больше 3;
## новый район не ближе 3 клеток к полной группе.
static func cluster_error(game: Game, owner: int, type: String, tile: int) -> String:
	var map := game.state.map
	var max_size := int(k(game, "district_cluster_max", 3))
	var gap := int(k(game, "district_cluster_gap", 3))
	var same := {}
	for c in game.state.cities_of(owner):
		for d in of_type(c, type):
			same[int(d["tile"])] = true
	if same.is_empty():
		return ""
	# Группа, которая получится с новым районом.
	var group := {tile: true}
	var stack := [tile]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for nb in map.grid.neighbors(cur):
			if same.has(nb) and not group.has(nb):
				group[nb] = true
				stack.append(nb)
	if group.size() > max_size:
		return "Не больше %d одинаковых районов рядом" % max_size
	# Полные группы, к которым новый район не примыкает, — держать дистанцию.
	var seen := {}
	for t in same:
		if seen.has(t) or group.has(t):
			continue
		var g := {t: true}
		var st := [t]
		while not st.is_empty():
			var cur2: int = st.pop_back()
			for nb in map.grid.neighbors(cur2):
				if same.has(nb) and not g.has(nb):
					g[nb] = true
					st.append(nb)
		for x in g:
			seen[x] = true
		if g.size() >= max_size:
			for x in g:
				if map.grid.distance(int(x), tile) < gap:
					return "Рядом уже %d таких района — новый не ближе %d клеток" % [max_size, gap]
	return ""


static func min_distance_to(grid: HexGrid, tile: int, tiles: Array) -> int:
	var best := 1 << 30
	for t in tiles:
		best = mini(best, grid.distance(tile, int(t)))
	return best


static func valid_tiles(game: Game, city: City, type: String) -> Array[int]:
	var result: Array[int] = []
	if type_error(game, city, type) != "":
		return result
	for t in game.state.map.grid.tiles_in_radius(city.tile, int(k(game, "city_work_radius", 3))):
		if placement_error(game, city, type, t) == "":
			result.append(t)
	return result


static func available_types(game: Game, city: City) -> Array[String]:
	var result: Array[String] = []
	for type in game.data.district_ids:
		if not valid_tiles(game, city, type).is_empty():
			result.append(type)
	return result


# --- Стоимость --------------------------------------------------------------------------------------

## Цена района (ГДД 6.1): растёт с прогрессом в технологиях/институтах, +25% за каждый
## такой же район в городе (docs/CITIES.md). Фиксируется при закладке.
static func cost(game: Game, city: City, type: String) -> float:
	var def := ddef(game, type)
	if def.has("cost_override"):
		return roundf(float(def["cost_override"]) * CityRules.speed_mult(game))
	var p := game.state.player(city.owner)
	var tp := float(p.known_techs.size()) / maxf(1.0, game.data.techs.size())
	var cp := float(p.known_civics.size()) / maxf(1.0, game.data.civics.size())
	var base := float(k(game, "district_base_cost", 54)) * (1.0 + float(k(game, "district_cost_progress_mult", 9)) * maxf(tp, cp))
	base *= float(def.get("cost_mult", 1.0))
	base *= 1.0 + float(k(game, "district_repeat_cost", 0.25)) * of_type(city, type).size()
	return roundf(base * CityRules.speed_mult(game))


## Закладка района: клетка резервируется, улучшение и особенность убираются.
static func place(game: Game, city: City, type: String, tile: int) -> Dictionary:
	var map := game.state.map
	var entry := {"type": type, "tile": tile, "tier": 1, "buildings": [], "complete": false, "cost": cost(game, city, type)}
	city.districts.append(entry)
	map.district[tile] = type
	map.improvement[tile] = ""
	map.pillaged[tile] = 0
	if rid_is_bonus(game, map.resource[tile]):
		map.resource[tile] = ""   # бонусный ресурс под районом пропадает (как в оригинале)
	if map.feature[tile] != "" and not ddef(game, type).get("placement", {}).has("feature"):
		map.feature[tile] = ""
	city.worked_tiles.erase(tile)
	city.locked_tiles.erase(tile)
	return entry


static func rid_is_bonus(game: Game, rid: String) -> bool:
	return rid != "" and game.data.resources.get(rid, {}).get("class", "") == "bonus"


static func entry_at(city: City, tile: int) -> Dictionary:
	for d in city.districts:
		if int(d["tile"]) == tile:
			return d
	return {}


# --- Уровни районов ------------------------------------------------------------------------------

static func tier_def(game: Game, type: String, tier: int) -> Dictionary:
	var tiers: Array = ddef(game, type).get("tiers", [])
	if tier < 1 or tier > tiers.size():
		return {}
	return tiers[tier - 1]


static func upgrade_error(game: Game, city: City, entry: Dictionary) -> String:
	if not entry.get("complete", false):
		return "Район ещё строится"
	var next := tier_def(game, entry["type"], int(entry["tier"]) + 1)
	if next.is_empty():
		return "Это высший уровень"
	if not _unlocked(game.state.player(city.owner), next):
		var need: String = next.get("tech", next.get("civic", ""))
		var tree: Dictionary = game.data.techs if next.has("tech") else game.data.civics
		return "Нужно: %s" % tree.get(need, {}).get("name", need)
	return ""


static func upgrade_cost(game: Game, city: City, entry: Dictionary) -> float:
	return roundf(float(entry.get("cost", 54)) * float(k(game, "district_upgrade_cost_frac", 0.5)) * (int(entry["tier"])))


# --- Здания районов -----------------------------------------------------------------------------

static func building_error(game: Game, city: City, bid: String, tile: int) -> String:
	var b: Dictionary = game.data.buildings.get(bid, {})
	var dtype: String = b.get("district", CENTER)
	if dtype == CENTER:
		return ""
	var entry := entry_at(city, tile)
	if entry.is_empty() or entry["type"] != dtype:
		return "Нужен район «%s»" % display_name(game, city.owner, dtype)
	if not entry["complete"]:
		return "Район ещё строится"
	if entry["buildings"].has(bid):
		return "Уже построено"
	var grp: String = b.get("exclusive_group", "")
	if grp != "":
		for other in entry["buildings"]:
			if game.data.buildings.get(other, {}).get("exclusive_group", "") == grp:
				return "Уже есть здание этой группы"
	var req: String = b.get("requires_building", "")
	if req != "":
		var ok: bool = entry["buildings"].has(req)
		for other in entry["buildings"]:
			if game.data.buildings.get(other, {}).get("exclusive_group", "") == req:
				ok = true
		if not ok:
			return "Сначала нужно предыдущее здание"
	return ""


# --- Выход района ----------------------------------------------------------------------------------

## Бонус соседства клетки для района типа type (ГДД 6.1): {доход: число}, дроби округляются вниз.
static func adjacency(game: Game, owner: int, type: String, tile: int, mult: float = 1.0) -> Dictionary:
	var def := ddef(game, type)
	var map := game.state.map
	var main: String = def.get("main_yield", "")
	var raw := {}
	var river_done := false
	for nb in map.grid.neighbors(tile):
		var nd := map.district[nb]
		var nb_def := ddef(game, nd) if nd != "" and nd != CENTER else {}
		var nb_owner := -1
		if nd != "":
			var oc := game.state.city_owning(nb)
			nb_owner = oc.owner if oc != null else -1
		for a in def.get("adjacency", []):
			var y: String = a.get("yield", main)
			if y == "":
				continue
			var hit := false
			match a["source"]:
				"mountain":
					hit = map.is_mountain(nb)
				"feature":
					hit = map.feature[nb] == a.get("id", "")
				"district":
					hit = nd != "" and nb_owner == owner
				"district_type":
					hit = nd == a.get("id", "") and nb_owner == owner
				"city_center":
					hit = nd == CENTER and nb_owner == owner
				"sea_resource":
					hit = map.is_water(nb) and map.resource[nb] != ""
				"strategic_resource":
					var r := map.resource[nb]
					hit = r != "" and game.data.resources[r].get("class", "") == "strategic"
				"improvement":
					hit = map.improvement[nb] == a.get("id", "")
			if hit:
				raw[y] = float(raw.get(y, 0.0)) + float(a["value"])
		# Правительственная площадь даёт +1 соседним специализированным районам.
		if not nb_def.is_empty() and nb_def.has("gives_adjacency") and nb_owner == owner and is_specialized(game, type) and main != "":
			raw[main] = float(raw.get(main, 0.0)) + float(nb_def["gives_adjacency"])
	for a in def.get("adjacency", []):
		if a["source"] == "river" and not river_done and map.has_river(tile):
			var y2: String = a.get("yield", main)
			raw[y2] = float(raw.get(y2, 0.0)) + float(a["value"])
			river_done = true
	var result := {}
	for y3 in raw:
		var v := floorf(float(raw[y3]) * mult + 1e-6)
		if v > 0:
			result[y3] = v
	return result


## Особенности городов цивилизации владельца (например, «Урбанизация Нерона»).
static func city_ability(game: Game, owner: int, id: String) -> Dictionary:
	for a in Abilities.civ_def(game, owner).get("city_abilities", []):
		if a.get("id", "") == id:
			return a
	return {}


## «Урбанизация Нерона»: {"bonus", "flat", "neighbors": [названия]} или {}.
static func nero(game: Game, city: City, entry: Dictionary) -> Dictionary:
	var ab := city_ability(game, city.owner, "NERO_URBANIZATION")
	if ab.is_empty() or not entry.get("complete", false) or not is_specialized(game, entry["type"]):
		return {}
	var map := game.state.map
	var names := []
	for nb in map.grid.neighbors(int(entry["tile"])):
		var nd := map.district[nb]
		if nd == "" or nd == CENTER or nd == entry["type"] or not is_specialized(game, nd):
			continue
		var a := at(game, nb)
		if a.is_empty() or a[0].owner != city.owner or not a[1].get("complete", false):
			continue
		names.append(display_name(game, city.owner, nd, int(a[1].get("tier", 1))))
	if names.size() < int(ab.get("min_neighbors", 2)):
		return {}
	var best := {"bonus": 0.0, "flat": 0}
	for t in ab.get("tiers", []):
		if city.population >= int(t["pop"]):
			best = {"bonus": float(t["bonus"]), "flat": int(t.get("flat", 0))}
	best["neighbors"] = names
	return best


## Полный выход района: {"yields", "housing", "amenities", "sanitation", "order", "specialist_slots"}.
static func output(game: Game, city: City, entry: Dictionary) -> Dictionary:
	var out := {"yields": {}, "housing": 0.0, "amenities": 0, "sanitation": 0.0, "order": 0.0, "specialist_slots": 0}
	if not entry.get("complete", false) or game.state.map.pillaged[int(entry["tile"])] == 1:
		return out
	var type: String = entry["type"]
	var def := ddef(game, type)
	var tier := int(entry.get("tier", 1))
	var mult := 1.0
	var y := {}
	# Базовые эффекты типа и всех пройденных уровней.
	Yields.add_into(y, def.get("base_yields", {}))
	out["housing"] = float(def.get("housing", 0))
	out["amenities"] = int(def.get("amenities", 0))
	out["sanitation"] = float(def.get("sanitation", 0))
	out["order"] = float(def.get("order", 0))
	for t in range(1, tier + 1):
		var td := tier_def(game, type, t)
		Yields.add_into(y, td.get("yields", {}))
		out["housing"] += float(td.get("housing", 0))
		out["amenities"] += int(td.get("amenities", 0))
		out["sanitation"] += float(td.get("sanitation", 0))
		out["specialist_slots"] += int(td.get("specialist_slots", 0))
		mult = float(td.get("adjacency_mult", mult))
	var adj := adjacency(game, city.owner, type, int(entry["tile"]), mult)
	Yields.add_into(y, adj)
	for bid in entry.get("buildings", []):
		var b: Dictionary = game.data.buildings.get(bid, {})
		Yields.add_into(y, b.get("yields", {}))
		out["housing"] += float(b.get("housing", 0))
		out["amenities"] += int(b.get("amenities", 0))
		out["specialist_slots"] += int(b.get("specialist_slots", 0))
	var spec_n := int(city.specialists.get(str(entry["tile"]), 0))
	Yields.add_into(y, def.get("specialist", {}), spec_n)
	var nr := nero(game, city, entry)
	if not nr.is_empty():
		for yt in y:
			y[yt] = float(y[yt]) * (1.0 + float(nr["bonus"]))
		var flat := int(nr["flat"])
		if flat > 0:
			if out["housing"] > 0:
				out["housing"] += flat
			if out["amenities"] > 0:
				out["amenities"] += flat
			if out["sanitation"] != 0:
				out["sanitation"] += flat
			out["order"] += flat
	out["yields"] = y
	return out


## Места специалистов в районе: от уровней и зданий.
static func specialist_slots(game: Game, entry: Dictionary) -> int:
	if not entry.get("complete", false):
		return 0
	var n := 0
	for t in range(1, int(entry["tier"]) + 1):
		n += int(tier_def(game, entry["type"], t).get("specialist_slots", 0))
	for bid in entry["buildings"]:
		n += int(game.data.buildings.get(bid, {}).get("specialist_slots", 0))
	return n


## Содержание района: тип, пройденные уровни, здания.
static func maintenance(game: Game, entry: Dictionary) -> float:
	var m := float(ddef(game, entry["type"]).get("maintenance", 0))
	if entry.get("complete", false):
		for t in range(1, int(entry["tier"]) + 1):
			m += float(tier_def(game, entry["type"], t).get("maintenance", 0))
	for bid in entry["buildings"]:
		m += float(game.data.buildings.get(bid, {}).get("maintenance", 0))
	return m


## Сумма выходов всех районов города + региональные эффекты зданий соседних городов.
static func city_totals(game: Game, city: City) -> Dictionary:
	var tot := {"yields": {}, "housing": 0.0, "amenities": 0, "sanitation": 0.0, "order": 0.0, "specialist_slots": 0}
	for d in city.districts:
		var o := output(game, city, d)
		Yields.add_into(tot["yields"], o["yields"])
		for key in ["housing", "amenities", "sanitation", "order", "specialist_slots"]:
			tot[key] += o[key]
	# Региональные здания (Фабрика, Зоопарк, Стадион): лучший эффект каждого вида в радиусе.
	var best_regional := {}
	for c in game.state.cities_of(city.owner):
		for d in c.districts:
			if not d.get("complete", false):
				continue
			# Региональный эффект уровня района (Фабрика — Промышленная зона II).
			for t in range(1, int(d["tier"]) + 1):
				var td := tier_def(game, d["type"], t)
				if td.has("radius") and game.state.map.grid.distance(int(d["tile"]), city.tile) <= int(td["radius"]):
					best_regional["%s:%d" % [d["type"], t]] = td
			for bid in d["buildings"]:
				var b: Dictionary = game.data.buildings.get(bid, {})
				if not b.has("radius") or game.state.map.grid.distance(int(d["tile"]), city.tile) > int(b["radius"]):
					continue
				best_regional[bid] = b
	for bid in best_regional:
		var b2: Dictionary = best_regional[bid]
		Yields.add_into(tot["yields"], b2.get("regional", {}))
		tot["amenities"] += int(b2.get("regional_amenities", 0))
	return tot
