class_name AIPlayer
extends RefCounted
## ИИ-противник (ГДД 23). Веха M2: исследования, расселение, производство в городах,
## строители, гарнизоны и разведка. Стратегический слой, дипломатия и война — дальше.
##
## ИИ действует только через Game.apply_action — как и игрок.

const SETTLE_RADIUS := 8
const EXPLORE_RADIUS := 8


static func take_turn(game: Game, pid: int) -> void:
	_choose_research(game, pid)
	for u in game.state.units_of(pid):
		if game.state.unit(u.id) == null:
			continue
		var abilities: Array = game.data.unit_def(u.type).get("abilities", [])
		if abilities.has("FOUND_CITY"):
			_handle_settler(game, u)
		elif abilities.has("BUILD_IMPROVEMENT"):
			_handle_builder(game, u)
	for city in game.state.cities_of(pid):
		if city.queue.is_empty():
			_choose_production(game, city)
	_spend_gold(game, pid)
	_handle_military(game, pid)


## Покупки (ГДД 23.3): держим резерв, излишек тратим на текущее производство города,
## которому до готовности дольше всего; иначе — на клетки с ресурсами.
static func _spend_gold(game: Game, pid: int) -> void:
	var p := game.state.player(pid)
	var reserve := 60.0 + EmpireRules.maintenance(game, pid) * 10.0
	for _attempt in 3:
		var best: City = null
		var best_turns := 0
		for city in game.state.cities_of(pid):
			if city.queue.is_empty():
				continue
			var item: Dictionary = city.queue[0]
			if p.treasury - CityRules.purchase_cost(game, city, item) < reserve:
				continue
			var t := CityRules.turns_to_build(game, city, item)
			if t > best_turns:
				best_turns = t
				best = city
		if best == null or best_turns < 3:
			break
		var it: Dictionary = best.queue[0]
		game.apply_action({"type": "purchase", "city": best.id, "kind": it["kind"], "id": it["id"]})
	for city in game.state.cities_of(pid):
		for t in CityRules.border_candidates(game, city):
			var rid := game.state.map.resource[t]
			if rid == "" or not Yields.resource_visible(game.data, rid, p):
				continue
			if CityRules.tile_purchase_error(game, city, t) == "" \
					and p.treasury - CityRules.tile_purchase_cost(game, city, t) >= reserve:
				game.apply_action({"type": "buy_tile", "city": city.id, "tile": t})


# --- Исследования (ГДД 23.6, упрощённо) ------------------------------------------------------------

static func _choose_research(game: Game, pid: int) -> void:
	var p := game.state.player(pid)
	if p.current_tech == "":
		var best := _cheapest(game, EmpireRules.available_techs(game, pid), game.data.techs)
		if best != "":
			game.apply_action({"type": "set_research", "kind": "tech", "id": best})
	if p.current_civic == "":
		var best_c := _cheapest(game, EmpireRules.available_civics(game, pid), game.data.civics)
		if best_c != "":
			game.apply_action({"type": "set_research", "kind": "civic", "id": best_c})


static func _cheapest(game: Game, ids: Array[String], tree: Dictionary) -> String:
	var best := ""
	var best_cost := INF
	for id in ids:
		var cost := float(tree[id].get("cost", 0)) * (1.0 + game.state.rng.randf() * 0.3)
		if cost < best_cost:
			best_cost = cost
			best = id
	return best


# --- Расселение (ГДД 23.4) -------------------------------------------------------------------------

## Оценка клетки под город с точки зрения держа­вы pid; -INF — нельзя.
static func settle_score(game: Game, pid: int, tile: int) -> float:
	if CityRules.found_city_error(game, pid, tile) != "":
		return -INF
	var map := game.state.map
	var p := game.state.player(pid)
	var score := 0.0
	for t in map.grid.tiles_in_radius(tile, 3):
		if not p.is_revealed(t):
			score += 1.0
			continue
		var d := map.grid.distance(tile, t)
		var w := 1.0 if d <= 1 else (0.7 if d == 2 else 0.4)
		var y := Yields.tile_yields(map, game.data, t, p)
		score += (float(y.get("food", 0)) + float(y.get("production", 0)) + float(y.get("gold", 0)) * 0.5
			+ (float(y.get("science", 0)) + float(y.get("culture", 0)) + float(y.get("faith", 0))) * 0.7) * w
		if map.owner_city[t] >= 0:
			score -= 1.5
		var rid := map.resource[t]
		if rid != "" and Yields.resource_visible(game.data, rid, p) and game.data.resources[rid]["class"] != "bonus":
			score += 3.0
	if map.has_fresh_water(tile):
		score += 12.0
	elif map.is_coastal_land(tile):
		score += 6.0
	if map.is_hills(tile):
		score += 2.0
	# Идеальная дистанция до своих городов — 4–6 клеток.
	var nearest := 99
	for city in game.state.cities_of(pid):
		nearest = mini(nearest, map.grid.distance(city.tile, tile))
	if nearest < 99 and nearest > 6:
		score -= (nearest - 6) * 4.0
	return score


static func _handle_settler(game: Game, u: Unit) -> void:
	if u.moves_left <= 0.0:
		return
	var map := game.state.map
	var here := settle_score(game, u.owner, u.tile)
	var best := u.tile
	var best_score := here
	for t in map.grid.tiles_in_radius(u.tile, SETTLE_RADIUS):
		if not game.state.player(u.owner).is_revealed(t):
			continue
		# Дальние клетки должны быть заметно лучше: время тоже ценно.
		var s := settle_score(game, u.owner, t) - map.grid.distance(u.tile, t) * 1.5
		if s > best_score:
			best_score = s
			best = t
	if best == u.tile and here > -INF:
		game.apply_action({"type": "found_city", "unit": u.id})
		return
	if best != u.tile:
		if u.orders.get("target", -1) != best:
			game.apply_action({"type": "move_unit", "unit": u.id, "target": best})
		if game.state.unit(u.id) != null and u.tile == best and u.moves_left > 0.0:
			game.apply_action({"type": "found_city", "unit": u.id})
	else:
		game.apply_action({"type": "skip_unit", "unit": u.id})


# --- Строители (ГДД 23.5) ----------------------------------------------------------------------------

static func _improvement_gain(game: Game, u: Unit, tile: int) -> Array:
	var probe := Unit.new()
	probe.owner = u.owner
	probe.type = u.type
	probe.charges = u.charges
	probe.tile = tile
	var best := ""
	var best_gain := 0.0
	for iid in ImprovementRules.valid_improvements(game, probe):
		var y: Dictionary = game.data.improvements[iid].get("yields", {})
		var gain := Yields.total(y) + float(game.data.improvements[iid].get("housing", 0)) * 2.0
		if game.state.map.resource[tile] != "":
			gain += 2.0
		if gain > best_gain:
			best_gain = gain
			best = iid
	return [best, best_gain]


static func _handle_builder(game: Game, u: Unit) -> void:
	if u.moves_left <= 0.0:
		return
	var here: Array = _improvement_gain(game, u, u.tile)
	if here[0] != "":
		game.apply_action({"type": "build_improvement", "unit": u.id, "improvement": here[0]})
		return
	var map := game.state.map
	var best := -1
	var best_score := 0.0
	for city in game.state.cities_of(u.owner):
		for t in CityRules.owned_tiles(game, city):
			if game.state.city_at(t) != null:
				continue
			var g: Array = _improvement_gain(game, u, t)
			if g[0] == "":
				continue
			var s: float = float(g[1]) + (3.0 if city.worked_tiles.has(t) else 0.0)
			s /= float(map.grid.distance(u.tile, t) + 1)
			if s > best_score:
				best_score = s
				best = t
	if best >= 0:
		game.apply_action({"type": "move_unit", "unit": u.id, "target": best})
		if game.state.unit(u.id) != null and u.tile == best and u.moves_left > 0.0:
			var g2: Array = _improvement_gain(game, u, u.tile)
			if g2[0] != "":
				game.apply_action({"type": "build_improvement", "unit": u.id, "improvement": g2[0]})
	else:
		game.apply_action({"type": "sleep_unit", "unit": u.id})


# --- Производство (ГДД 23.3, упрощённо) ------------------------------------------------------------

static func _count_units(game: Game, pid: int, pred: Callable) -> int:
	var n := 0
	for u in game.state.units_of(pid):
		if pred.call(u):
			n += 1
	return n


static func _queued(game: Game, pid: int, unit_id: String) -> int:
	var n := 0
	for city in game.state.cities_of(pid):
		if not city.queue.is_empty() and city.queue[0].get("id", "") == unit_id:
			n += 1
	return n


static func _best_combat_unit(game: Game, city: City) -> String:
	var best := ""
	var best_str := -1
	for item in CityRules.buildable_items(game, city):
		if item["kind"] != "unit":
			continue
		var def := game.data.unit_def(item["id"])
		var cls: String = def.get("class", "")
		if cls != "MELEE" and cls != "RANGED" and cls != "ANTI_CAVALRY":
			continue
		var st := int(def.get("combat", 0)) + int(def.get("ranged", 0))
		if st > best_str:
			best_str = st
			best = item["id"]
	return best


static func _choose_production(game: Game, city: City) -> void:
	var pid := city.owner
	var cities := game.state.cities_of(pid)
	var military := _count_units(game, pid, func(u: Unit) -> bool: return Movement.layer(game, u.type) == "COMBAT")
	var settlers := _count_units(game, pid, func(u: Unit) -> bool:
		return game.data.unit_def(u.type).get("abilities", []).has("FOUND_CITY")) + _queued(game, pid, "SETTLER")
	var builders := _count_units(game, pid, func(u: Unit) -> bool:
		return game.data.unit_def(u.type).get("abilities", []).has("BUILD_IMPROVEMENT")) + _queued(game, pid, "BUILDER")
	var target_cities := 6
	var candidates: Array = []
	var garrisoned := false
	for u in game.state.units_at(city.tile):
		if Movement.layer(game, u.type) == "COMBAT":
			garrisoned = true
	var combat := _best_combat_unit(game, city)
	if military < cities.size() and not garrisoned and combat != "":
		candidates.append({"kind": "unit", "id": combat})
	if cities.size() + settlers < target_cities and settlers < 1:
		candidates.append({"kind": "unit", "id": "SETTLER"})
	if builders < cities.size():
		candidates.append({"kind": "unit", "id": "BUILDER"})
	for bid in ["MONUMENT", "GRANARY", "WATER_MILL"]:
		candidates.append({"kind": "building", "id": bid})
	if combat != "" and military < cities.size() * 2:
		candidates.append({"kind": "unit", "id": combat})
	candidates.append({"kind": "unit", "id": "SETTLER"})
	candidates.append({"kind": "unit", "id": "BUILDER"})
	if combat != "":
		candidates.append({"kind": "unit", "id": combat})
	for item in candidates:
		if CityRules.build_error(game, city, item) == "":
			game.apply_action({"type": "set_production", "city": city.id, "kind": item["kind"], "id": item["id"]})
			return


# --- Гарнизоны и разведка -----------------------------------------------------------------------------

static func _handle_military(game: Game, pid: int) -> void:
	var cities := game.state.cities_of(pid)
	# Город без гарнизона — ближайший свободный боевой юнит идёт туда.
	for city in cities:
		var guard: Unit = null
		for u in game.state.units_at(city.tile):
			if Movement.layer(game, u.type) == "COMBAT" and u.owner == pid:
				guard = u
		if guard != null:
			if guard.orders.is_empty():
				game.apply_action({"type": "sleep_unit", "unit": guard.id})
			continue
		var best: Unit = null
		var best_d := 999
		for u in game.state.units_of(pid):
			if Movement.layer(game, u.type) != "COMBAT" or u.orders.get("type", "") == "sleep":
				continue
			var d := game.state.map.grid.distance(u.tile, city.tile)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			game.apply_action({"type": "move_unit", "unit": best.id, "target": city.tile})
			if game.state.unit(best.id) != null and best.tile == city.tile:
				game.apply_action({"type": "sleep_unit", "unit": best.id})
	for u in game.state.units_of(pid):
		if u.moves_left <= 0.0 or not u.orders.is_empty():
			continue
		if Movement.layer(game, u.type) != "COMBAT":
			continue
		var target := _explore_target(game, u)
		if target >= 0:
			game.apply_action({"type": "move_unit", "unit": u.id, "target": target})
		else:
			game.apply_action({"type": "sleep_unit", "unit": u.id})


## Ближайшая разведанная проходимая клетка, рядом с которой есть неразведанные.
static func _explore_target(game: Game, u: Unit) -> int:
	var p := game.state.player(u.owner)
	var grid := game.state.map.grid
	var best := -1
	var best_score := -INF
	for t in grid.tiles_in_radius(u.tile, EXPLORE_RADIUS):
		if t == u.tile or not p.is_revealed(t) or not Movement.can_stand(game, u, t):
			continue
		var unknown := 0
		for nb in grid.neighbors(t):
			if not p.is_revealed(nb):
				unknown += 1
		if unknown == 0:
			continue
		var score := unknown * 2.0 - grid.distance(u.tile, t) + game.state.rng.randf()
		if score > best_score:
			best_score = score
			best = t
	return best
