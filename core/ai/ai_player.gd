class_name AIPlayer
extends RefCounted
## ИИ-противник (ГДД 23). Веха M2: исследования, расселение, производство в городах,
## строители, гарнизоны и разведка. Стратегический слой, дипломатия и война — дальше.
##
## ИИ действует только через Game.apply_action — как и игрок.

const SETTLE_RADIUS := 8
const EXPLORE_RADIUS := 8


static func take_turn(game: Game, pid: int) -> void:
	if not game.state.result.is_empty():
		return
	_treaty_diplomacy(game, pid)
	_supply_diplomacy(game, pid)
	_choose_research(game, pid)
	_choose_government(game, pid)
	_tactical(game, pid)
	if not game.state.result.is_empty():
		return
	for u in game.state.units_of(pid):
		if game.state.unit(u.id) == null:
			continue
		var abilities: Array = game.data.unit_def(u.type).get("abilities", [])
		if abilities.has("FOUND_CITY"):
			_handle_settler(game, u)
		elif abilities.has("BUILD_IMPROVEMENT"):
			_handle_builder(game, u)
		elif abilities.has("TRADE_ROUTE") and u.trade_route.is_empty():
			_handle_trader(game, u)
	for city in game.state.cities_of(pid):
		if city.queue.is_empty():
			_choose_production(game, city)
	_spend_gold(game, pid)
	_choose_doctrines(game, pid)
	_handle_commanders(game, pid)
	_handle_military(game, pid)
	_equip_units(game, pid)

## ИИ заключает договоры с надёжными державами и торговыми партнёрами.
static func _treaty_diplomacy(game: Game, pid: int) -> void:
	for offer in TreatyRules.offers_for(game, pid):
		if int(offer["to"]) != pid:
			continue
		var accept := TreatyRules.trust(game, pid, int(offer["from"])) >= 0
		game.apply_action({"type": "respond_treaty", "offer": offer["key"], "accept": accept})
	# Державы сами закрепляют отношения с партнёрами по действующим маршрутам.
	var partners := {}
	for unit in game.state.units_of(pid):
		if unit.trade_route.is_empty():
			continue
		var destination := game.state.city(int(unit.trade_route["destination"]))
		if destination != null and destination.owner != pid:
			partners[destination.owner] = true
	var ids := partners.keys()
	ids.sort()
	for other in ids:
		if TreatyRules.trust(game, pid, other) < 0:
			continue
		for kind in ["alliance", "friendship"]:
			if TreatyRules.offer_error(game, kind, pid, other) == "":
				game.apply_action({"type": "propose_treaty", "kind": kind, "target": other})
				return


## ИИ принимает посильные полезные поставки и предлагает избыток ресурса.
static func _supply_diplomacy(game: Game, pid: int) -> void:
	DiplomacyRules.initialize(game)
	var d := game.state.diplomacy
	var offer_ids: Array = d["offers"].keys()
	offer_ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in offer_ids:
		var offer: Dictionary = d["offers"][id]
		if int(offer.get("responder", offer["buyer"])) != pid:
			continue
		var rid: String = offer["resource"]
		var total: int = (int(offer["upfront"]) + int(offer["per_turn"]) * int(offer["rounds"])) * int(offer["unit_price"])
		var need := DiplomacyRules._resource_need(game, pid, rid, game.state.turn)
		var supply: float = UnitRules.strategic_income(game, pid).get(rid, 0.0)
		var accept := need > supply and game.state.player(pid).treasury >= total + 30.0
		if int(offer["seller"]) == pid:
			accept = float(game.state.player(pid).stockpile.get(rid, 0.0)) >= float(offer["upfront"]) \
				and float(game.state.player(pid).stockpile.get(rid, 0.0)) >= 20.0 \
				and int(offer["unit_price"]) >= 2
		game.apply_action({"type": "respond_supply", "id": int(id), "accept": accept})
	# Не создаём предложения без выявленной потребности и контакта.
	for other in game.state.players:
		if other.id == pid or other.is_barbarian or not other.alive or not game.state.player(pid).met.has(other.id):
			continue
		if game.state.at_war(pid, other.id):
			continue
		for rid in game.data.resource_ids:
			if game.data.resources[rid].get("class", "") != "strategic":
				continue
			if float(game.state.player(pid).stockpile.get(rid, 0.0)) < 30.0:
				continue
			var need := DiplomacyRules._resource_need(game, other.id, rid, game.state.turn)
			if need <= float(UnitRules.strategic_income(game, other.id).get(rid, 0.0)):
				continue
			var already := false
			for id in d["offers"]:
				var offer: Dictionary = d["offers"][id]
				if int(offer["seller"]) == pid and int(offer["buyer"]) == other.id and offer["resource"] == rid:
					already = true
			for id in d["contracts"]:
				var contract: Dictionary = d["contracts"][id]
				if int(contract["seller"]) == pid and int(contract["buyer"]) == other.id and contract["resource"] == rid:
					already = true
			if already:
				continue
			game.apply_action({"type": "propose_supply", "buyer": other.id, "resource": rid,
				"upfront": 0, "per_turn": 2, "rounds": 5, "unit_price": 2})
			return


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
			if item["kind"] == "district" or item["kind"] == "district_upgrade":
				continue
			if p.treasury - CityRules.purchase_cost(game, city, item) < reserve:
				continue
			var t := CityRules.turns_to_build(game, city, item)
			if t > best_turns:
				best_turns = t
				best = city
		if best == null or best_turns < 3:
			break
		var it: Dictionary = best.queue[0]
		game.apply_action({"type": "purchase", "city": best.id, "kind": it["kind"], "id": it["id"], "tile": int(it.get("tile", -1))})
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
		for other in game.state.units_at(t):
			if game.state.at_war(pid, other.owner) and Movement.layer(game, other.type) == "COMBAT":
				score -= 15.0
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
	# Под угрозой закрепляемся на подходящем месте или отступаем.
	if not _enemies_near(game, u.owner, u.tile, 2).is_empty():
		if CityRules.found_city_error(game, u.owner, u.tile) == "":
			game.apply_action({"type": "found_city", "unit": u.id})
			return
		var home := _nearest_own_city(game, u.owner, u.tile)
		if home != null and home.tile != u.tile:
			game.apply_action({"type": "move_unit", "unit": u.id, "target": home.tile})
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


static func _handle_trader(game: Game, unit: Unit) -> void:
	if unit.moves_left <= 0.0:
		return
	var city := game.state.city_at(unit.tile)
	if city == null or city.owner != unit.owner:
		var home := _nearest_own_city(game, unit.owner, unit.tile)
		if home != null:
			game.apply_action({"type": "move_unit", "unit": unit.id, "target": home.tile})
		return
	var best := -1
	var best_score := -INF
	for route in TradeRules.options(game, unit):
		var score := 0.0
		var yields := TradeRules.route_yields(game, route)
		for kind in yields:
			score += float(yields[kind]) * float(CityRules.DEFAULT_WEIGHTS.get(kind, 1.0))
		score -= float(route["path"].size()) * 0.025
		if score > best_score:
			best_score = score
			best = int(route["destination"])
	if best >= 0:
		game.apply_action({"type": "start_trade", "unit": unit.id, "destination": best})


static func _queued(game: Game, pid: int, unit_id: String) -> int:
	var n := 0
	for city in game.state.cities_of(pid):
		if not city.queue.is_empty() and city.queue[0].get("id", "") == unit_id:
			n += 1
	return n


static func _best_combat_unit(game: Game, city: City) -> String:
	var best := ""
	var best_str := -1
	for uid in game.data.unit_ids:
		var item := {"kind": "unit", "id": uid}
		if CityRules.build_error(game, city, item) != "":
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
	var threatened := not _enemies_near(game, pid, city.tile, 5).is_empty()
	if threatened and combat != "":
		candidates.append({"kind": "unit", "id": combat})
		candidates.append({"kind": "building", "id": "ANCIENT_WALLS"})
	if (military < cities.size() + 1 or not garrisoned) and combat != "":
		candidates.append({"kind": "unit", "id": combat})
	if cities.size() + settlers < target_cities and settlers < 1:
		candidates.append({"kind": "unit", "id": "SETTLER"})
	# Развитый город сначала строит районы, а не очередного строителя (docs/CITIES.md).
	var districts_first := city.population >= 4 and builders >= cities.size() / 2
	var district_list := _district_candidates(game, city, threatened)
	if districts_first:
		candidates.append_array(district_list)
	if builders < cities.size():
		candidates.append({"kind": "unit", "id": "BUILDER"})
	var trader: String = game.data.trade["trader"]
	var trade_limit := TradeRules.capacity(game, pid)
	if trade_limit > 0 and _count_units(game, pid, func(u: Unit) -> bool: return u.type == trader) \
			+ _queued(game, pid, trader) < trade_limit and not TradeRules.plans_from(game, city).is_empty():
		candidates.append({"kind": "unit", "id": trader})
	for bid in ["MONUMENT", "GRANARY", "WATER_MILL"]:
		candidates.append({"kind": "building", "id": bid})
	if not districts_first:
		candidates.append_array(district_list)
	if combat != "" and military < cities.size() * 2:
		candidates.append({"kind": "unit", "id": combat})
	var commanders := _count_units(game, pid, func(u: Unit) -> bool: return Army.is_commander(game, u) or not u.commander.is_empty()) \
		+ _queued(game, pid, "COMMANDER")
	if military >= 4 and commanders < military / 4:
		candidates.append({"kind": "unit", "id": "COMMANDER"})
	candidates.append({"kind": "unit", "id": "SETTLER"})
	candidates.append({"kind": "unit", "id": "BUILDER"})
	if combat != "":
		candidates.append({"kind": "unit", "id": combat})
	for item in candidates:
		if CityRules.build_error(game, city, item) == "":
			game.apply_action({"type": "set_production", "city": city.id, "kind": item["kind"], "id": item["id"],
				"tile": int(item.get("tile", -1))})
			return


# --- Районы и губернаторы (docs/CITIES.md) -----------------------------------------------------------

## Порядок предпочтения специализированных районов.
const DISTRICT_PRIORITY := ["CAMPUS", "COMMERCIAL_HUB", "INDUSTRIAL_ZONE", "HOLY_SITE", "THEATER_SQUARE",
	"HARBOR", "ENCAMPMENT", "ENTERTAINMENT_COMPLEX", "GOVERNMENT_PLAZA"]


## Кандидаты производства в районах: достроить начатое, здания и улучшения районов,
## жилые районы и акведук при нехватке жилья, Термы для больших городов, новый спец. район.
static func _district_candidates(game: Game, city: City, threatened: bool) -> Array:
	var result := []
	var items := CityRules.district_items(game, city)
	for it in items:
		if it["kind"] == "district" and it.has("tile"):
			result.append(it)
	var buildings := []
	for it in items:
		if it["kind"] == "building" or it["kind"] == "district_upgrade":
			buildings.append(it)
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return CityRules.item_cost(game, city, a) < CityRules.item_cost(game, city, b))
	result.append_array(buildings)
	var types := {}
	for it in items:
		if it["kind"] == "district" and not it.has("tile"):
			types[it["id"]] = true
	var housing := CityRules.housing(game, city)
	if float(city.population) >= housing - 1.0:
		for t in ["AQUEDUCT", "DAM", "RESIDENTIAL_URBAN", "RESIDENTIAL_HOUSING", "RESIDENTIAL_DENSE"]:
			if types.has(t):
				result.append(_district_pick(game, city, t))
	if city.population >= int(game.data.const_value("city_life_threshold_pop", 10)) - 1:
		if types.has("BATHS"):
			result.append(_district_pick(game, city, "BATHS"))
	var order := DISTRICT_PRIORITY.duplicate()
	if threatened:
		order.erase("ENCAMPMENT")
		order.push_front("ENCAMPMENT")
	var best := {}
	var best_score := -INF
	for i in order.size():
		var t2: String = order[i]
		if not types.has(t2) or (t2 == "ENCAMPMENT" and not threatened and DistrictRules.of_type(city, t2).size() > 0):
			continue
		var pick := _district_pick(game, city, t2)
		var sc := float(pick["score"]) - i * 0.4 - DistrictRules.of_type(city, t2).size() * 1.5
		if sc > best_score:
			best_score = sc
			best = pick
	if not best.is_empty():
		result.append(best)
	var clean := []
	for r in result:
		if not r.is_empty():
			var item: Dictionary = r.duplicate()
			item.erase("score")
			clean.append(item)
	return clean


## Лучшая клетка для района: соседство + римская урбанизация − потеря дохода клетки.
static func _district_pick(game: Game, city: City, type: String) -> Dictionary:
	var best := {}
	var best_score := -INF
	var p := game.state.player(city.owner)
	var map := game.state.map
	var nero := not DistrictRules.city_ability(game, city.owner, "NERO_URBANIZATION").is_empty()
	for t in DistrictRules.valid_tiles(game, city, type):
		var sc := Yields.total(DistrictRules.adjacency(game, city.owner, type, t))
		sc -= Yields.total(CityRules.tile_yields(game, t, p)) * 0.3
		if nero and DistrictRules.is_specialized(game, type):
			for nb in map.grid.neighbors(t):
				var nd := map.district[nb]
				if nd != "" and nd != DistrictRules.CENTER and nd != type and DistrictRules.is_specialized(game, nd):
					sc += 0.6
		sc -= map.grid.distance(city.tile, t) * 0.1
		if sc > best_score:
			best_score = sc
			best = {"kind": "district", "id": type, "tile": t, "score": sc}
	return best


## Губернаторы: в самые большие города; доктрина по обстановке.
static func _choose_government(game: Game, pid: int) -> void:
	var p := game.state.player(pid)
	var tier := int(GovernmentRules.active_government(game, p)["tier"])
	var best := ""
	for def in game.data.governments.values():
		if int(def["tier"]) > tier and GovernmentRules.government_error(game, p, def["id"]) == "":
			best = def["id"]
			tier = int(def["tier"])
	if best != "":
		game.apply_action({"type": "set_government", "id": best})
	var slots := GovernmentRules.slots(GovernmentRules.active_government(game, p))
	for index in slots.size():
		if GovernmentRules.policy_at(p, index) != "":
			continue
		for id in game.data.policies:
			if GovernmentRules.policy_error(game, p, index, id) == "":
				game.apply_action({"type": "set_policy", "slot": index, "id": id})
				break


static func _choose_doctrines(game: Game, pid: int) -> void:
	var p := game.state.player(pid)
	var cities := game.state.cities_of(pid)
	cities.sort_custom(func(a: City, b: City) -> bool:
		return a.population > b.population or (a.population == b.population and a.id < b.id))
	for city in cities:
		if city.population < int(game.data.const_value("city_life_threshold_pop", 10)) - 2:
			continue
		var want := "PERSUASION"
		var order_bal := float(CityLife.order(game, city)["balance"])
		if order_bal < -2.0:
			want = "AUTOCRACY"
		elif p.faith > city.population * 10.0:
			want = "RELIGIOUS"
		elif EmpireRules.summary(game, pid)["net_gold"] < city.population:
			want = "AUTOCRACY"
		if city.doctrine == "" or (city.doctrine != want and CityLife.doctrine_active(city) and order_bal < -3.0):
			game.apply_action({"type": "set_doctrine", "city": city.id, "doctrine": want})


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
	_clear_camps(game, pid)
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


# --- Тактика (ГДД 23.10, упрощённо) ----------------------------------------------------------------

static func _enemies_near(game: Game, pid: int, tile: int, radius: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var p := game.state.player(pid)
	var grid := game.state.map.grid
	for id in game.state.units:
		var e: Unit = game.state.units[id]
		if e.owner != pid and game.state.at_war(pid, e.owner) and p.is_visible(e.tile) \
				and Movement.layer(game, e.type) == "COMBAT" and grid.distance(e.tile, tile) <= radius:
			result.append(e)
	return result


static func _nearest_own_city(game: Game, pid: int, tile: int) -> City:
	var best: City = null
	var best_d := 999
	for c in game.state.cities_of(pid):
		var d := game.state.map.grid.distance(c.tile, tile)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _tactical(game: Game, pid: int) -> void:
	var s := game.state
	# Обстрел из городов.
	for city in s.cities_of(pid):
		if not Combat.city_can_strike(game, city):
			continue
		var best := -1
		var best_hp := 999
		for t in s.map.grid.tiles_in_radius(city.tile, int(game.data.const_value("city_ranged_range", 2))):
			if Combat.city_attack_error(game, city, t) == "":
				var hp: int = Combat.target_at(game, pid, t)["unit"].hp
				if hp < best_hp:
					best_hp = hp
					best = t
		if best >= 0:
			game.apply_action({"type": "city_attack", "city": city.id, "target": best})
	# Повышения.
	for u in s.units_of(pid):
		var promos := Combat.available_promotions(game, u)
		if not promos.is_empty() and u.moves_left > 0.0 and _enemies_near(game, pid, u.tile, 2).is_empty():
			game.apply_action({"type": "promote", "unit": u.id, "promotion": promos[0]})
	# Атаки: сначала дальнобойные, затем ближний бой.
	var attackers: Array[Unit] = []
	for u in s.units_of(pid):
		if Combat.can_attack(game, u) and u.moves_left > 0.0:
			attackers.append(u)
	attackers.sort_custom(func(a: Unit, b: Unit) -> bool:
		return int(Combat.is_ranged(game, a)) > int(Combat.is_ranged(game, b)) or \
			(Combat.is_ranged(game, a) == Combat.is_ranged(game, b) and a.id < b.id))
	for u in attackers:
		if s.unit(u.id) == null or u.moves_left <= 0.0:
			continue
		if TradeRules.raid_target(game, u) != null:
			game.apply_action({"type": "raid_trade", "unit": u.id})
			continue
		var reach := Combat.attack_range(game, u) if Combat.is_ranged(game, u) else 1
		var best_t := -1
		var best_score := 0.0
		for t in s.map.grid.tiles_in_radius(u.tile, reach):
			if t == u.tile or Combat.attack_error(game, u, t) != "":
				continue
			var pv := Combat.preview(game, u, t)
			var tgt := Combat.target_at(game, pid, t)
			var score := float(pv["dmg_to_def"]) - float(pv["dmg_to_att"]) * 1.2
			if tgt["kind"] == "unit" and int(pv["dmg_to_def"]) >= tgt["unit"].hp:
				score += 40.0
			if tgt["kind"] == "civilian":
				score += 50.0
			if tgt["kind"] == "city":
				if Combat.is_ranged(game, u):
					score *= 0.7
				elif tgt["city"].hp > int(pv["dmg_to_def"]):
					score = -1.0
				else:
					score += 100.0
			if not Combat.is_ranged(game, u) and u.hp - int(pv["dmg_to_att"]) < 25:
				score = -1.0
			if score > best_score:
				best_score = score
				best_t = t
		if best_t >= 0:
			game.apply_action({"type": "attack", "unit": u.id, "target": best_t})
	# Раненые отходят; остальные идут навстречу врагу у своих городов.
	for u in s.units_of(pid):
		if s.unit(u.id) == null or u.moves_left <= 0.0 or Movement.layer(game, u.type) != "COMBAT":
			continue
		var near := _enemies_near(game, pid, u.tile, 3)
		if u.hp < 40 and not near.is_empty():
			var home := _nearest_own_city(game, pid, u.tile)
			if home != null and home.tile != u.tile:
				game.apply_action({"type": "move_unit", "unit": u.id, "target": home.tile})
			if s.unit(u.id) != null:
				game.apply_action({"type": "fortify", "unit": u.id})
			continue
		for city in s.cities_of(pid):
			var threats := _enemies_near(game, pid, city.tile, 4)
			if threats.is_empty() or s.map.grid.distance(u.tile, city.tile) > 6 or s.city_at(u.tile) != null:
				continue
			var e: Unit = threats[0]
			var spot := _adjacent_free(game, u, e.tile)
			if spot >= 0:
				game.apply_action({"type": "cancel_orders", "unit": u.id})
				game.apply_action({"type": "move_unit", "unit": u.id, "target": spot})
			break


static func _adjacent_free(game: Game, u: Unit, tile: int) -> int:
	var best := -1
	var best_d := 999
	for t in game.state.map.grid.neighbors(tile):
		if not Movement.can_stand(game, u, t) or not Movement.occupancy_allows(game, u, t, true):
			continue
		var d := game.state.map.grid.distance(u.tile, t)
		if d < best_d:
			best_d = d
			best = t
	return best


## Зачистка лагерей варваров в 8 клетках от своих городов: двумя свободными юнитами.
static func _clear_camps(game: Game, pid: int) -> void:
	var s := game.state
	var p := s.player(pid)
	var camp_tiles := s.camps.keys()
	camp_tiles.sort()
	for tile in camp_tiles:
		var ct := int(tile)
		if not p.is_revealed(ct):
			continue
		var home := _nearest_own_city(game, pid, ct)
		if home == null or s.map.grid.distance(home.tile, ct) > 8:
			continue
		var free: Array[Unit] = []
		for u in s.units_of(pid):
			if Combat.can_attack(game, u) and u.moves_left > 0.0 and s.city_at(u.tile) == null \
					and u.orders.get("type", "") != "sleep" and u.hp >= 60:
				free.append(u)
		if free.size() < 2:
			return
		for u in free.slice(0, 2):
			if s.map.grid.distance(u.tile, ct) == 1:
				var has_guard := false
				for e in s.units_at(ct):
					if e.owner != pid:
						has_guard = true
				if not has_guard:
					game.apply_action({"type": "move_unit", "unit": u.id, "target": ct})
				continue
			var spot := _adjacent_free(game, u, ct)
			if spot >= 0:
				game.apply_action({"type": "cancel_orders", "unit": u.id})
				game.apply_action({"type": "move_unit", "unit": u.id, "target": spot})
		return


# --- Командующие и снаряжение (docs/ARMY.md) -------------------------------------------------------

## Свободный командующий идёт к сильнейшему боевому юниту без командующего и объединяется с ним.
static func _handle_commanders(game: Game, pid: int) -> void:
	var s := game.state
	for cmd in s.units_of(pid):
		if s.unit(cmd.id) == null or not Army.is_commander(game, cmd):
			continue
		var best: Unit = null
		var best_score := -INF
		for u in s.units_of(pid):
			if not u.commander.is_empty() or not Combat.can_attack(game, u) or Movement.domain(game, u) != "LAND":
				continue
			var sc := Combat.melee_strength(game, u.type) - s.map.grid.distance(u.tile, cmd.tile) * 2.0
			if sc > best_score:
				best_score = sc
				best = u
		if best == null:
			if cmd.orders.is_empty():
				game.apply_action({"type": "sleep_unit", "unit": cmd.id})
			continue
		if best.tile != cmd.tile and cmd.moves_left > 0.0:
			game.apply_action({"type": "cancel_orders", "unit": cmd.id})
			game.apply_action({"type": "move_unit", "unit": cmd.id, "target": best.tile})
		if s.unit(cmd.id) != null and Army.attach_error(game, cmd, best) == "":
			game.apply_action({"type": "attach_commander", "unit": cmd.id, "target": best.id})


## Простые правила: одежда по климату клетки, против варваров — лёгкое, против держав — тяжёлое.
static func _equip_units(game: Game, pid: int) -> void:
	var s := game.state
	var p := s.player(pid)
	var vs_major := false
	for other in s.players:
		if other.id != pid and not other.is_barbarian and s.at_war(pid, other.id):
			vs_major = true
	var reserve := 80.0
	for u in s.units_of(pid):
		if p.treasury < reserve:
			return
		var oc := s.city_owning(u.tile)
		if oc == null or oc.owner != pid:
			continue
		var slots := Army.slots_for(game, u.type)
		var want := {}
		if slots.has("weapon"):
			want["weapon"] = "SPEAR" if vs_major else "SHORT_SWORD"
		if slots.has("tactics"):
			want["tactics"] = "LINE_DRILL" if vs_major else "SKIRMISH_DRILL"
		if slots.has("kit"):
			want["kit"] = "ASSAULT_KIT" if vs_major else "PATROL_KIT"
		if slots.has("clothing"):
			var cl := Army.climate_of(game, u.tile)
			want["clothing"] = "WINTER" if cl == "COLD" else ("DESERT_GEAR" if cl == "HOT" else "STANDARD")
		for slot in want:
			if Army.equip_error(game, u, slot, want[slot]) == "":
				game.apply_action({"type": "equip", "unit": u.id, "slot": slot, "option": want[slot]})
