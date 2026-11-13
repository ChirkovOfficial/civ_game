class_name CityRules
extends RefCounted
## Правила городов (ГДД 4.1–4.7, 5.1–5.4).

const DEFAULT_WEIGHTS := {"food": 1.1, "production": 1.0, "gold": 0.6, "science": 0.8, "culture": 0.7, "faith": 0.5}


static func speed_mult(game: Game) -> float:
	return float(game.data.game_speed(game.state.settings.get("speed", "STANDARD")).get("multiplier", 1.0))


static func c(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


# --- Основание города (ГДД 5.1) ----------------------------------------------------------

## Пустая строка — можно основать; иначе причина отказа.
static func found_city_error(game: Game, pid: int, tile: int) -> String:
	var map := game.state.map
	if map.is_water(tile) or map.is_mountain(tile):
		return "Город можно основать только на суше (не в горах)"
	if map.feature_def(tile).get("impassable", false):
		return "Здесь нельзя основать город"
	var owner_cid := map.owner_city[tile]
	if owner_cid >= 0 and game.state.city(owner_cid).owner != pid:
		return "Это чужая территория"
	var min_dist: int = int(c(game, "city_min_distance", 4))
	for cid in game.state.cities:
		var other: City = game.state.cities[cid]
		if map.grid.distance(other.tile, tile) < min_dist:
			return "Слишком близко к городу %s (нужно не меньше %d клеток)" % [other.name, min_dist]
	return ""


static func next_city_name(game: Game, pid: int) -> String:
	var p := game.state.player(pid)
	var used := {}
	for cid in game.state.cities:
		used[game.state.cities[cid].name] = true
	var names: Array = game.data.civs.get(p.civ_trait_id, {}).get("city_names", [])
	if names.is_empty():
		names = game.data.placeholder_city_names
	while p.city_names_used < names.size():
		var n: String = names[p.city_names_used]
		p.city_names_used += 1
		if not used.has(n):
			return n
	p.city_names_used += 1
	return "Город %d" % p.city_names_used


static func found_city(game: Game, pid: int, tile: int) -> City:
	var s := game.state
	var map := s.map
	var city := City.new()
	city.id = s.next_city_id
	s.next_city_id += 1
	city.owner = pid
	city.original_owner = pid
	city.tile = tile
	city.founded_turn = s.turn
	city.name = next_city_name(game, pid)
	city.is_capital = s.cities_of(pid).is_empty()
	if city.is_capital:
		for bid in game.data.building_ids:
			if game.data.buildings[bid].get("capital_only", false):
				city.buildings.append(bid)
	s.cities[city.id] = city
	if c(game, "city_removes_features", []).has(map.feature[tile]):
		map.feature[tile] = ""
	map.improvement[tile] = ""
	claim_tile(game, city, tile)
	for nb in map.grid.neighbors(tile):
		if map.owner_city[nb] < 0:
			claim_tile(game, city, nb)
	assign_citizens(game, city)
	return city


static func claim_tile(game: Game, city: City, tile: int) -> void:
	game.state.map.owner_city[tile] = city.id


static func owned_tiles(game: Game, city: City) -> Array[int]:
	var result: Array[int] = []
	var map := game.state.map
	var radius: int = int(c(game, "city_border_radius", 5))
	for t in map.grid.tiles_in_radius(city.tile, radius):
		if map.owner_city[t] == city.id:
			result.append(t)
	result.sort()
	return result


# --- Доходы клеток ----------------------------------------------------------------------------

## Доход клетки с учётом улучшения и правил центра города.
static func tile_yields(game: Game, tile: int, player: Player) -> Dictionary:
	var map := game.state.map
	var y := Yields.tile_yields(map, game.data, tile, player)
	var imp := map.improvement[tile]
	if imp != "":
		Yields.add_into(y, game.data.improvements.get(imp, {}).get("yields", {}))
	var city := game.state.city_at(tile)
	if city != null:
		var mins: Dictionary = c(game, "city_center_min_yields", {})
		for k in mins:
			y[k] = maxf(float(y.get(k, 0)), float(mins[k]))
	return y


## Улучшен ли ресурс на клетке (для довольства и запасов): нужное улучшение или центр города.
static func resource_improved(game: Game, tile: int) -> bool:
	var map := game.state.map
	var rid := map.resource[tile]
	if rid == "":
		return false
	if game.state.city_at(tile) != null:
		return true
	var need: String = game.data.resources[rid].get("improvement", "")
	return need != "" and map.improvement[tile] == need


# --- Жильё и довольство (ГДД 4.7, 5.4) ----------------------------------------------------------

static func housing(game: Game, city: City) -> float:
	var map := game.state.map
	var h: float
	if map.has_fresh_water(city.tile):
		h = float(c(game, "housing_base_fresh_water", 5))
	elif map.is_coastal_land(city.tile):
		h = float(c(game, "housing_base_coast", 3))
	else:
		h = float(c(game, "housing_base_dry", 2))
	for bid in city.buildings:
		h += float(game.data.buildings.get(bid, {}).get("housing", 0))
	for t in owned_tiles(game, city):
		var imp := map.improvement[t]
		if imp != "":
			h += float(game.data.improvements.get(imp, {}).get("housing", 0))
	return h


static func housing_growth_mult(game: Game, city: City) -> float:
	var h := floorf(housing(game, city))
	var pop := float(city.population)
	if pop <= h - float(c(game, "housing_growth_full_below", 2)):
		return 1.0
	if pop <= h - 1.0:
		return float(c(game, "housing_growth_half", 0.5))
	if pop < h + float(c(game, "housing_growth_stop_above", 5)):
		return float(c(game, "housing_growth_over", 0.25))
	return 0.0


static func amenities_needed(city: City) -> int:
	return maxi(0, ceili((city.population - 2) / 2.0))


## Довольство от редких ресурсов по городам державы: city_id -> число.
## Каждый вид улучшенного люкса даёт +1 четырём самым нуждающимся городам (ГДД 3.6).
static func luxury_amenities(game: Game, pid: int) -> Dictionary:
	var result := {}
	var cities := game.state.cities_of(pid)
	for city in cities:
		result[city.id] = 0
	if cities.is_empty():
		return result
	var kinds := {}
	for city in cities:
		for t in owned_tiles(game, city):
			var rid := game.state.map.resource[t]
			if rid != "" and game.data.resources[rid].get("class", "") == "luxury" and resource_improved(game, t):
				kinds[rid] = true
	var kind_list := kinds.keys()
	kind_list.sort()
	var per_kind: int = int(c(game, "luxury_amenity_cities", 4))
	for _rid in kind_list:
		var order := cities.duplicate()
		order.sort_custom(func(a: City, b: City) -> bool:
			var ba := _base_amenities(game, a) + int(result[a.id]) - amenities_needed(a)
			var bb := _base_amenities(game, b) + int(result[b.id]) - amenities_needed(b)
			return ba < bb or (ba == bb and a.id < b.id))
		for k in mini(per_kind, order.size()):
			result[order[k].id] += 1
	return result


static func _base_amenities(game: Game, city: City) -> int:
	var a := 0
	for bid in city.buildings:
		a += int(game.data.buildings.get(bid, {}).get("amenities", 0))
	return a


## {"have", "need", "balance", "state": {...}} — состояние довольства города.
static func amenity_info(game: Game, city: City, lux: Dictionary = {}) -> Dictionary:
	if lux.is_empty():
		lux = luxury_amenities(game, city.owner)
	var have := _base_amenities(game, city) + int(lux.get(city.id, 0))
	var need := amenities_needed(city)
	var balance := have - need
	return {"have": have, "need": need, "balance": balance, "state": amenity_state(game, balance)}


static func amenity_state(game: Game, balance: int) -> Dictionary:
	for st in c(game, "amenity_states", []):
		if balance >= int(st["min"]):
			return st
	return {"id": "CONTENT", "name": "", "growth": 1.0, "yields": 1.0}


# --- Доходы города ------------------------------------------------------------------------------

## Полный доход города за ход (ГДД 4). Пища — до вычета потребления.
static func city_yields(game: Game, city: City, lux: Dictionary = {}) -> Dictionary:
	var p := game.state.player(city.owner)
	var y := tile_yields(game, city.tile, p)
	for t in city.worked_tiles:
		Yields.add_into(y, tile_yields(game, t, p))
	for bid in city.buildings:
		Yields.add_into(y, game.data.buildings.get(bid, {}).get("yields", {}))
	y["science"] = float(y.get("science", 0)) + city.population * float(c(game, "science_per_pop", 0.5))
	y["culture"] = float(y.get("culture", 0)) + city.population * float(c(game, "culture_per_pop", 0.3))
	var st: Dictionary = amenity_info(game, city, lux)["state"]
	var mult := float(st.get("yields", 1.0))
	if mult != 1.0:
		for k in y:
			if k != "food":
				y[k] = float(y[k]) * mult
	return y


static func food_consumption(game: Game, city: City) -> float:
	return city.population * float(c(game, "food_per_citizen", 2))


## Изменение корзины роста за ход с учётом жилья и довольства (ГДД 4.1).
static func food_delta(game: Game, city: City, lux: Dictionary = {}) -> float:
	var surplus := float(city_yields(game, city, lux).get("food", 0)) - food_consumption(game, city)
	if surplus <= 0.0:
		return surplus
	var st: Dictionary = amenity_info(game, city, lux)["state"]
	return surplus * housing_growth_mult(game, city) * float(st.get("growth", 1.0))


static func growth_threshold(game: Game, pop: int) -> int:
	var n := float(pop - 1)
	return int(floorf(float(c(game, "growth_base", 15)) + float(c(game, "growth_linear", 8)) * n
		+ pow(n, float(c(game, "growth_exp", 1.5)))))


static func turns_to_grow(game: Game, city: City) -> int:
	var delta := food_delta(game, city)
	if delta <= 0.0:
		return -1
	return ceili((growth_threshold(game, city.population) - city.food_stored) / delta)


# --- Жители (ГДД 5.2, 23.3) -------------------------------------------------------------------

## Клетки, которые город может обрабатывать: свои, в радиусе 3, не занятые другим городом.
static func workable_tiles(game: Game, city: City) -> Array[int]:
	var result: Array[int] = []
	var map := game.state.map
	var radius: int = int(c(game, "city_work_radius", 3))
	var taken := {}
	for cid in game.state.cities:
		if cid != city.id:
			for t in game.state.cities[cid].worked_tiles:
				taken[t] = true
	for t in map.grid.tiles_in_radius(city.tile, radius):
		if t == city.tile or map.owner_city[t] != city.id or taken.has(t):
			continue
		if game.state.city_at(t) != null:
			continue
		result.append(t)
	result.sort()
	return result


## Автоматическое распределение жителей: закреплённые остаются, остальные — жадно
## по взвешенной сумме доходов с приоритетом «не голодать».
static func assign_citizens(game: Game, city: City) -> void:
	var p := game.state.player(city.owner)
	var candidates := workable_tiles(game, city)
	var keep: Array[int] = []
	for t in city.locked_tiles:
		if candidates.has(t) and keep.size() < city.population:
			keep.append(t)
	city.locked_tiles = keep.duplicate()
	city.worked_tiles = keep.duplicate()
	var food := float(tile_yields(game, city.tile, p).get("food", 0))
	for bid in city.buildings:
		food += float(game.data.buildings.get(bid, {}).get("yields", {}).get("food", 0))
	for t in keep:
		food += float(tile_yields(game, t, p).get("food", 0))
	var need_food := food_consumption(game, city)
	var at_housing_cap := float(city.population) >= floorf(housing(game, city)) - 1.0
	var scores := {}
	for t in candidates:
		scores[t] = tile_yields(game, t, p)
	while city.worked_tiles.size() < city.population:
		var best := -1
		var best_score := -INF
		for t in candidates:
			if city.worked_tiles.has(t):
				continue
			var y: Dictionary = scores[t]
			var w := DEFAULT_WEIGHTS.duplicate()
			if food < need_food:
				w["food"] = float(w["food"]) * 3.0
			elif at_housing_cap:
				w["food"] = float(w["food"]) * 0.5
			if city.focus != "" and w.has(city.focus):
				w[city.focus] = float(w[city.focus]) * 2.0
			var sc := 0.0
			for k in y:
				sc += float(y[k]) * float(w.get(k, 0.5))
			if sc > best_score:
				best_score = sc
				best = t
		if best < 0:
			break   # клеток не хватает — лишние жители пока без дела (специалисты — веха M4)
		city.worked_tiles.append(best)
		food += float(scores[best].get("food", 0))


# --- Производство (ГДД 4.2, 5.3) -----------------------------------------------------------------

static func item_name(game: Game, item: Dictionary) -> String:
	if item.get("kind", "") == "unit":
		return game.data.unit_def(item["id"]).get("name", item["id"])
	return game.data.buildings.get(item.get("id", ""), {}).get("name", item.get("id", ""))


## Стоимость объекта в ⚙ с учётом скорости и роста цены (поселенцы, строители).
static func item_cost(game: Game, city: City, item: Dictionary) -> float:
	var base := 0.0
	if item["kind"] == "unit":
		var def := game.data.unit_def(item["id"])
		var made: int = int(game.state.player(city.owner).produced.get(item["id"], 0))
		base = float(def.get("cost", 0)) + float(def.get("cost_progression", 0)) * made
	else:
		base = float(game.data.buildings.get(item["id"], {}).get("cost", 0))
	return roundf(base * speed_mult(game))


static func _unlocked(p: Player, def: Dictionary) -> bool:
	if def.has("tech") and not p.has_tech(def["tech"]):
		return false
	if def.has("civic") and not p.has_civic(def["civic"]):
		return false
	return true


## Пустая строка — объект можно поставить в производство; иначе причина.
static func build_error(game: Game, city: City, item: Dictionary) -> String:
	var p := game.state.player(city.owner)
	var kind: String = item.get("kind", "")
	var id: String = item.get("id", "")
	if kind == "unit":
		var def := game.data.unit_def(id)
		if def.is_empty():
			return "Неизвестный юнит"
		if not _unlocked(p, def):
			return "Не открыто"
		if def.get("domain", "LAND") == "SEA" and not game.state.map.is_coastal_land(city.tile):
			return "Город не у моря"
		if def.get("domain", "LAND") == "AIR":
			return "Нужен аэродром"
		if int(def.get("pop_cost", 0)) > 0 and city.population <= int(def["pop_cost"]):
			return "Нужно население не меньше %d" % (int(def["pop_cost"]) + 1)
		if def.has("resource"):
			return "Нужны стратегические ресурсы (веха M10)"
		return ""
	if kind == "building":
		var b: Dictionary = game.data.buildings.get(id, {})
		if b.is_empty():
			return "Неизвестное здание"
		if b.get("not_buildable", false):
			return "Нельзя построить"
		if city.has_building(id):
			return "Уже построено"
		if b.get("district", "CITY_CENTER") != "CITY_CENTER":
			return "Нужен район"
		if not _unlocked(p, b):
			return "Не открыто"
		if b.get("requires", "") == "river" and not game.state.map.has_river(city.tile):
			return "Город должен стоять у реки"
		return ""
	return "Неизвестный объект"


static func buildable_items(game: Game, city: City) -> Array:
	var result := []
	for uid in game.data.unit_ids:
		var item := {"kind": "unit", "id": uid}
		if build_error(game, city, item) == "":
			result.append(item)
	for bid in game.data.building_ids:
		var item := {"kind": "building", "id": bid}
		if build_error(game, city, item) == "":
			result.append(item)
	return result


static func production_per_turn(game: Game, city: City, lux: Dictionary = {}) -> float:
	return float(city_yields(game, city, lux).get("production", 0))


static func turns_to_build(game: Game, city: City, item: Dictionary) -> int:
	var per := production_per_turn(game, city)
	var left := item_cost(game, city, item) - float(city.progress.get(City.item_key(item), 0.0))
	if per <= 0.0:
		return -1
	return maxi(1, ceili(left / per))


static func purchase_cost(game: Game, city: City, item: Dictionary) -> int:
	return int(ceilf(item_cost(game, city, item) * float(c(game, "gold_purchase_mult", 4))))


## Завершает объект: появление юнита или здания. Возвращает false, если юниту негде появиться.
static func complete_item(game: Game, city: City, item: Dictionary, events: Array) -> bool:
	if item["kind"] == "unit":
		var tile := spawn_tile(game, city, item["id"])
		if tile < 0:
			events.append({"type": "production_blocked", "city": city.id, "item": item})
			return false
		var u := game.state.add_unit(city.owner, item["id"], tile)
		var def := game.data.unit_def(item["id"])
		u.moves_left = Movement.max_moves(game, u)
		u.charges = int(def.get("charges", 0))
		var p := game.state.player(city.owner)
		p.produced[item["id"]] = int(p.produced.get(item["id"], 0)) + 1
		var pop_cost := int(def.get("pop_cost", 0))
		if pop_cost > 0:
			city.population = maxi(1, city.population - pop_cost)
			city.food_stored = 0.0
			assign_citizens(game, city)
		events.append({"type": "unit_created", "unit": u.id, "city": city.id})
	else:
		city.buildings.append(item["id"])
		var b: Dictionary = game.data.buildings[item["id"]]
		if b.has("wall_hp"):
			city.wall_hp = maxi(city.wall_hp, int(b["wall_hp"]))
		events.append({"type": "building_created", "building": item["id"], "city": city.id})
	return true


## Клетка появления юнита: центр города, иначе ближайшая своя свободная.
static func spawn_tile(game: Game, city: City, unit_type: String) -> int:
	var layer_name := Movement.layer(game, unit_type)
	var domain: String = game.data.unit_def(unit_type).get("domain", "LAND")
	var map := game.state.map
	var options: Array[int] = [city.tile]
	for r in [1, 2]:
		for t in map.grid.ring(city.tile, r):
			options.append(t)
	for t in options:
		if domain == "LAND" and (map.is_water(t) or map.is_mountain(t)):
			continue
		if domain == "SEA" and t != city.tile and not map.is_water(t):
			continue
		var ok := true
		for other in game.state.units_at(t):
			if other.owner != city.owner or Movement.layer(game, other.type) == layer_name:
				ok = false
				break
		if ok:
			return t
	return -1


static func process_production(game: Game, city: City, per_turn: float, events: Array) -> void:
	if city.queue.is_empty():
		return
	var item: Dictionary = city.queue[0]
	if build_error(game, city, item) != "":
		events.append({"type": "production_invalid", "city": city.id, "item": item})
		city.queue.pop_front()
		return
	var key := City.item_key(item)
	var have := float(city.progress.get(key, 0.0)) + per_turn + city.overflow
	city.overflow = 0.0
	var cost := item_cost(game, city, item)
	if have < cost:
		city.progress[key] = have
		return
	if not complete_item(game, city, item, events):
		city.progress[key] = cost
		return
	city.progress.erase(key)
	city.overflow = have - cost
	city.queue.pop_front()
	if city.queue.is_empty():
		events.append({"type": "production_needed", "city": city.id})


# --- Рост (ГДД 4.1) ----------------------------------------------------------------------------------

static func process_growth(game: Game, city: City, lux: Dictionary, events: Array) -> void:
	var delta := food_delta(game, city, lux)
	city.food_stored += delta
	var threshold := growth_threshold(game, city.population)
	if city.food_stored >= threshold:
		city.food_stored -= threshold
		city.population += 1
		assign_citizens(game, city)
		events.append({"type": "city_grew", "city": city.id, "population": city.population})
	elif city.food_stored < 0.0:
		city.food_stored = 0.0
		if city.population > 1 and delta < 0.0:
			city.population -= 1
			assign_citizens(game, city)
			events.append({"type": "city_starved", "city": city.id, "population": city.population})


# --- Границы (ГДД 4.5, 5.2) ------------------------------------------------------------------------

static func border_cost(game: Game, k: int) -> float:
	return float(c(game, "border_cost_base", 10)) + pow(float(c(game, "border_cost_mult", 6)) * k,
		float(c(game, "border_cost_exp", 1.3)))


## Клетки, на которые город может расшириться: ничьи, соседние с его территорией, в радиусе 5.
static func border_candidates(game: Game, city: City) -> Array[int]:
	var map := game.state.map
	var result: Array[int] = []
	var seen := {}
	for t in owned_tiles(game, city):
		for nb in map.grid.neighbors(t):
			if seen.has(nb) or map.owner_city[nb] >= 0:
				continue
			seen[nb] = true
			if map.grid.distance(city.tile, nb) <= int(c(game, "city_border_radius", 5)):
				result.append(nb)
	result.sort()
	return result


static func border_tile_score(game: Game, city: City, tile: int) -> float:
	var map := game.state.map
	var p := game.state.player(city.owner)
	var y := Yields.tile_yields(map, game.data, tile, p)
	var score := Yields.total(y)
	var rid := map.resource[tile]
	if rid != "" and Yields.resource_visible(game.data, rid, p):
		score += 3.0 if game.data.resources[rid].get("class", "") != "bonus" else 1.5
	score -= (map.grid.distance(city.tile, tile) - 1) * 1.5
	return score


static func best_border_tile(game: Game, city: City) -> int:
	var best := -1
	var best_score := -INF
	for t in border_candidates(game, city):
		var s := border_tile_score(game, city, t)
		if s > best_score:
			best_score = s
			best = t
	return best


static func process_borders(game: Game, city: City, culture: float, events: Array) -> void:
	city.culture_stored += culture
	var cost := border_cost(game, city.border_tiles_acquired + 1)
	if city.culture_stored < cost:
		return
	var t := best_border_tile(game, city)
	if t < 0:
		return
	city.culture_stored -= cost
	city.border_tiles_acquired += 1
	claim_tile(game, city, t)
	events.append({"type": "border_grew", "city": city.id, "tile": t})


static func tile_purchase_cost(game: Game, city: City, tile: int) -> int:
	var p := game.state.player(city.owner)
	var dist := game.state.map.grid.distance(city.tile, tile)
	var known := p.known_techs.size() + p.known_civics.size()
	var cost := float(c(game, "tile_buy_base", 50)) * (1.0 + float(c(game, "tile_buy_per_distance", 0.5)) * (dist - 1)) \
		* (1.0 + float(c(game, "tile_buy_per_known", 0.02)) * known)
	return int(roundf(cost * speed_mult(game)))


static func tile_purchase_error(game: Game, city: City, tile: int) -> String:
	var map := game.state.map
	if map.owner_city[tile] >= 0:
		return "Клетка уже кому-то принадлежит"
	if map.grid.distance(city.tile, tile) > int(c(game, "city_work_radius", 3)):
		return "Слишком далеко от города"
	var adjacent := false
	for nb in map.grid.neighbors(tile):
		if map.owner_city[nb] == city.id:
			adjacent = true
			break
	if not adjacent:
		return "Клетка должна граничить с территорией города"
	if game.state.player(city.owner).treasury < tile_purchase_cost(game, city, tile):
		return "Не хватает золота"
	return ""
