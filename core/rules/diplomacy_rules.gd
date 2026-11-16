class_name DiplomacyRules
extends RefCounted
## Первый этап дипломатии: поставки, ресурсная зависимость и мировой рейтинг.

static func cfg(game: Game, key: String) -> float:
	return float(game.data.diplomacy.get(key, 0))

static func initialize(game: Game) -> void:
	if not game.state.diplomacy.is_empty():
		return
	var ids: Array[int] = []
	for p in game.state.players:
		if not p.is_barbarian:
			ids.append(p.id)
	game.state.diplomacy = {"initial_majors": ids, "next_id": 1, "offers": {}, "contracts": {},
		"origin": {}, "delivery_history": {}, "spend_history": {}, "route_history": {},
		"living_history": {}, "dependency": {}, "influence": {}, "last_round": 0}

static func record_spend(game: Game, pid: int, rid: String, amount: float) -> void:
	if amount <= 0.0:
		return
	initialize(game)
	var history: Dictionary = game.state.diplomacy["spend_history"]
	var key := _pair(pid, 0) + ":" + rid
	if not history.has(key):
		history[key] = []
	history[key].append({"round": game.state.turn, "amount": amount})

static func _error(events: Array, message: String) -> void:
	events.append({"type": "error", "message": message})

static func _major(game: Game, pid: int) -> bool:
	return pid >= 0 and pid < game.state.players.size() and game.state.player(pid).alive \
		and not game.state.player(pid).is_barbarian

static func _pair(a: int, b: int) -> String:
	return "%d,%d" % [a, b]

static func _resource_error(game: Game, seller: int, buyer: int, rid: String) -> String:
	if not _major(game, seller) or not _major(game, buyer) or seller == buyer:
		return "Нужны две действующие державы"
	if not game.state.player(seller).met.has(buyer) or not game.state.player(buyer).met.has(seller):
		return "Державы ещё не встретились"
	if game.state.at_war(seller, buyer):
		return "Во время войны поставки невозможны"
	if not game.data.resources.has(rid) or game.data.resources[rid].get("class", "") != "strategic":
		return "Пока доступны только стратегические ресурсы"
	return ""

static func propose(game: Game, action: Dictionary, events: Array) -> void:
	initialize(game)
	var seller := int(action.get("seller", game.state.current_player))
	var buyer := int(action.get("buyer", game.state.current_player))
	var rid := str(action.get("resource", ""))
	var err := _resource_error(game, seller, buyer, rid)
	if err == "" and game.state.current_player != seller and game.state.current_player != buyer:
		err = "Предложение может сделать только одна из сторон"
	var upfront := int(action.get("upfront", -1))
	var periodic := int(action.get("per_turn", -1))
	var periods := int(action.get("rounds", -1))
	var price := int(action.get("unit_price", -1))
	if err != "":
		_error(events, err)
		return
	if upfront < 0 or periodic < 0 or periods < 0 or price < 0 or upfront + periodic * periods <= 0 \
			or (periodic == 0 and periods != 0) or (periodic > 0 and periods == 0) \
			or upfront + periodic * periods > 10000 or price > 100000:
		_error(events, "Неверные объёмы или цена поставки")
		return
	var d := game.state.diplomacy
	var id: int = d["next_id"]
	d["next_id"] = id + 1
	d["offers"][str(id)] = {"id": id, "seller": seller, "buyer": buyer,
		"responder": buyer if seller == game.state.current_player else seller, "resource": rid,
		"upfront": upfront, "per_turn": periodic, "rounds": periods, "unit_price": price,
		"created": game.state.turn}
	events.append({"type": "supply_proposed", "id": id, "seller": seller, "buyer": buyer})

static func respond(game: Game, action: Dictionary, events: Array) -> void:
	initialize(game)
	var id := str(int(action.get("id", -1)))
	var d := game.state.diplomacy
	var offer: Dictionary = d["offers"].get(id, {})
	if offer.is_empty() or int(offer.get("responder", offer.get("buyer", -1))) != game.state.current_player:
		_error(events, "Предложение недоступно")
		return
	if not bool(action.get("accept", false)):
		d["offers"].erase(id)
		events.append({"type": "supply_rejected", "id": int(id)})
		return
	var seller: int = offer["seller"]
	var buyer: int = offer["buyer"]
	var rid: String = offer["resource"]
	var err := _resource_error(game, seller, buyer, rid)
	var upfront: int = offer["upfront"]
	var total: int = upfront + int(offer["per_turn"]) * int(offer["rounds"])
	var price: int = offer["unit_price"]
	var cap: float = float(game.data.const_value("strategic_cap", 50))
	if err == "" and game.state.player(seller).stockpile.get(rid, 0.0) < upfront:
		err = "У продавца нет ресурса для первой поставки"
	if err == "" and game.state.player(buyer).stockpile.get(rid, 0.0) + upfront > cap:
		err = "Недостаточно места на складе покупателя"
	if err == "" and game.state.player(buyer).treasury < total * price:
		err = "Покупателю не хватает золота"
	if err != "":
		_error(events, err)
		return
	# Сначала проверены все условия; затем одна атомарная передача.
	game.state.player(buyer).treasury -= total * price
	game.state.player(seller).treasury += upfront * price
	if upfront > 0:
		_transfer(game, seller, buyer, rid, upfront)
	d["offers"].erase(id)
	if int(offer["rounds"]) > 0:
		d["contracts"][id] = {"id": int(id), "seller": seller, "buyer": buyer, "resource": rid,
			"per_turn": int(offer["per_turn"]), "remaining": int(offer["rounds"]),
			"unit_price": price, "escrow": (total - upfront) * price,
			"next_round": game.state.turn + 1, "shortfalls": 0}
	events.append({"type": "supply_accepted", "id": int(id), "upfront": upfront, "total": total})

static func cancel(game: Game, action: Dictionary, events: Array) -> void:
	initialize(game)
	var id := str(int(action.get("id", -1)))
	var contract: Dictionary = game.state.diplomacy["contracts"].get(id, {})
	if contract.is_empty() or game.state.current_player not in [int(contract["seller"]), int(contract["buyer"])]:
		_error(events, "Договор недоступен")
		return
	_finish(game, id, "cancelled", events)

static func _finish(game: Game, id: String, reason: String, events: Array) -> void:
	var d := game.state.diplomacy
	var c: Dictionary = d["contracts"].get(id, {})
	if c.is_empty():
		return
	var refund: int = c["escrow"]
	game.state.player(int(c["buyer"])).treasury += refund
	d["contracts"].erase(id)
	events.append({"type": "supply_closed", "id": int(id), "reason": reason, "refund": refund})

## Приводит происхождение к фактическому складу после добычи и обычного расхода.
static func _sync_origin(game: Game, pid: int, rid: String) -> Dictionary:
	var all_origins: Dictionary = game.state.diplomacy["origin"]
	var owner_key := str(pid)
	if not all_origins.has(owner_key):
		all_origins[owner_key] = {}
	var by_resource: Dictionary = all_origins[owner_key]
	if not by_resource.has(rid):
		by_resource[rid] = {}
	var buckets: Dictionary = by_resource[rid]
	var actual: float = game.state.player(pid).stockpile.get(rid, 0.0)
	var recorded := 0.0
	for source in buckets:
		recorded += float(buckets[source])
	if actual > recorded:
		buckets[owner_key] = float(buckets.get(owner_key, 0.0)) + actual - recorded
	elif recorded > actual and recorded > 0.0:
		var ratio := actual / recorded
		for source in buckets:
			buckets[source] = float(buckets[source]) * ratio
	return buckets

static func _transfer(game: Game, seller: int, buyer: int, rid: String, amount: float) -> float:
	var sources := _sync_origin(game, seller, rid)
	var destination := _sync_origin(game, buyer, rid)
	var total := float(game.state.player(seller).stockpile.get(rid, 0.0))
	if total < amount or amount <= 0.0:
		return 0.0
	var direct := 0.0
	var keys := sources.keys()
	keys.sort()
	for source in keys:
		var portion := amount * float(sources[source]) / total
		sources[source] = float(sources[source]) - portion
		destination[source] = float(destination.get(source, 0.0)) + portion
		if str(source) == str(seller):
			direct += portion
	game.state.player(seller).stockpile[rid] = total - amount
	game.state.player(buyer).stockpile[rid] = float(game.state.player(buyer).stockpile.get(rid, 0.0)) + amount
	return direct

static func close_round(game: Game, events: Array) -> void:
	initialize(game)
	var d := game.state.diplomacy
	var round_number := game.state.turn
	if int(d["last_round"]) >= round_number:
		return
	var new_round := round_number + 1
	var offer_ids: Array = d["offers"].keys()
	offer_ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in offer_ids:
		if round_number - int(d["offers"][id]["created"]) >= int(cfg(game, "max_offer_response_rounds")):
			d["offers"].erase(id)
			events.append({"type": "supply_expired", "id": int(id)})
	for key in d["spend_history"].keys():
		var recent: Array = []
		for item in d["spend_history"][key]:
			if int(item["round"]) >= round_number - int(cfg(game, "demand_window")):
				recent.append(item)
		d["spend_history"][key] = recent
	for key in d["delivery_history"].keys():
		var recent: Array = []
		for item in d["delivery_history"][key]:
			if int(item["round"]) >= round_number - int(cfg(game, "demand_window")):
				recent.append(item)
		d["delivery_history"][key] = recent
	for collection in ["route_history", "living_history"]:
		for key in d[collection].keys():
			var recent: Array = []
			for item in d[collection][key]:
				if int(item["round"]) >= round_number - int(cfg(game, "demand_window")):
					recent.append(item)
			d[collection][key] = recent
	var ids: Array = d["contracts"].keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	# Снимок не позволяет отправить полученный в этой же фазе ресурс дальше.
	var available := {}
	for id in ids:
		var contract: Dictionary = d["contracts"][id]
		var stock_key := _pair(int(contract["seller"]), 0) + ":" + str(contract["resource"])
		if not available.has(stock_key):
			available[stock_key] = float(game.state.player(int(contract["seller"])).stockpile.get(contract["resource"], 0.0))
	var planned := _proportional_allocations(d["contracts"], ids, available, new_round)
	for id in ids:
		var c: Dictionary = d["contracts"].get(id, {})
		if c.is_empty() or int(c["next_round"]) > new_round:
			continue
		var seller: int = c["seller"]
		var buyer: int = c["buyer"]
		var rid: String = c["resource"]
		if _resource_error(game, seller, buyer, rid) != "":
			_finish(game, id, "relations_changed", events)
			continue
		var stock_key := _pair(seller, 0) + ":" + rid
		var seller_stock: float = available[stock_key]
		var buyer_stock: float = game.state.player(buyer).stockpile.get(rid, 0.0)
		var cap := float(game.data.const_value("strategic_cap", 50))
		var delivered := int(minf(float(planned.get(id, 0)), minf(seller_stock, cap - buyer_stock)))
		delivered = maxi(0, delivered)
		var direct := _transfer(game, seller, buyer, rid, delivered)
		available[stock_key] = seller_stock - delivered
		var period_price: int = int(c["per_turn"]) * int(c["unit_price"])
		game.state.player(seller).treasury += delivered * int(c["unit_price"])
		game.state.player(buyer).treasury += period_price - delivered * int(c["unit_price"])
		c["escrow"] = int(c["escrow"]) - period_price
		c["remaining"] = int(c["remaining"]) - 1
		c["next_round"] = new_round + 1
		c["shortfalls"] = int(c["shortfalls"]) + 1 if delivered < int(c["per_turn"]) and seller_stock < int(c["per_turn"]) else 0
		if direct > 0.0:
			var pair := _pair(buyer, seller) + ":" + rid
			if not d["delivery_history"].has(pair):
				d["delivery_history"][pair] = []
			d["delivery_history"][pair].append({"round": new_round, "amount": direct})
		events.append({"type": "supply_settled", "id": int(id), "delivered": delivered,
			"refunded": period_price - delivered * int(c["unit_price"])})
		if int(c["remaining"]) <= 0:
			_finish(game, id, "completed", events)
		elif int(c["shortfalls"]) >= 3:
			_finish(game, id, "supplier_shortfall", events)
	_update_dependency(game, new_round, events)
	_record_route_and_living(game, new_round)
	_update_influence(game, new_round, events)
	d["last_round"] = round_number

## При дефиците одного продавца одинаковые обязательства получают равную долю.
static func _proportional_allocations(contracts: Dictionary, ids: Array, available: Dictionary, due_round: int) -> Dictionary:
	var groups := {}
	for id in ids:
		var c: Dictionary = contracts[id]
		if int(c["next_round"]) > due_round:
			continue
		var key := _pair(int(c["seller"]), 0) + ":" + str(c["resource"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(id)
	var result := {}
	for key in groups:
		var members: Array = groups[key]
		var requested := 0
		for id in members:
			requested += int(contracts[id]["per_turn"])
		var stock := maxi(0, int(floorf(float(available[key]))))
		if requested <= stock:
			for id in members:
				result[id] = int(contracts[id]["per_turn"])
			continue
		var fractions := []
		var assigned := 0
		for id in members:
			var exact := float(stock * int(contracts[id]["per_turn"])) / maxf(1.0, requested)
			var whole := int(floorf(exact))
			result[id] = whole
			assigned += whole
			fractions.append({"id": id, "fraction": exact - whole})
		fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["fraction"]) > float(b["fraction"]) or (is_equal_approx(float(a["fraction"]), float(b["fraction"])) and int(a["id"]) < int(b["id"])))
		for i in stock - assigned:
			result[fractions[i]["id"]] = int(result[fractions[i]["id"]]) + 1
	return result

static func _upkeep_need(game: Game, pid: int, rid: String) -> float:
	var total := 0.0
	for u in game.state.units_of(pid):
		total += float(game.data.unit_def(u.type).get("resource_per_turn", {}).get(rid, 0.0))
	return total

static func _resource_need(game: Game, pid: int, rid: String, round_number: int) -> float:
	var need := _upkeep_need(game, pid, rid)
	var key := _pair(pid, 0) + ":" + rid
	var history: Array = game.state.diplomacy["spend_history"].get(key, [])
	for item in history:
		if int(item["round"]) > round_number - int(cfg(game, "demand_window")):
			need += float(item["amount"]) / maxf(1.0, cfg(game, "demand_window"))
	return need

static func _recent_delivery(game: Game, buyer: int, seller: int, rid: String, round_number: int) -> float:
	var key := _pair(buyer, seller) + ":" + rid
	var history: Array = game.state.diplomacy["delivery_history"].get(key, [])
	var result := 0.0
	for item in history:
		if int(item["round"]) > round_number - int(cfg(game, "demand_window")):
			result += float(item["amount"])
	return result / maxf(1.0, cfg(game, "demand_window"))

static func _update_dependency(game: Game, round_number: int, events: Array) -> void:
	var d := game.state.diplomacy
	var majors: Array = d["initial_majors"]
	for buyer_value in majors:
		var buyer := int(buyer_value)
		if not _major(game, buyer):
			continue
		for seller_value in majors:
			var seller := int(seller_value)
			if seller == buyer or not _major(game, seller):
				continue
			var best := 0.0
			var best_rid := ""
			for rid in game.data.resource_ids:
				if game.data.resources[rid].get("class", "") != "strategic":
					continue
				var need := _resource_need(game, buyer, rid, round_number)
				var supplied := _recent_delivery(game, buyer, seller, rid, round_number)
				if need <= 0.0 or supplied <= 0.0:
					continue
				var alternatives := float(UnitRules.strategic_income(game, buyer).get(rid, 0.0))
				for other_value in majors:
					var other := int(other_value)
					if other != seller and other != buyer:
						alternatives += _recent_delivery(game, buyer, other, rid, round_number)
				var gap := maxf(0.0, need - alternatives)
				if gap <= 0.0:
					continue
				var affected := minf(gap, supplied) / need
				var reserve: float = game.state.player(buyer).stockpile.get(rid, 0.0)
				var buffer := clampf(1.0 - reserve / (cfg(game, "reserve_horizon") * gap), 0.0, 1.0)
				var exposure := affected * buffer
				if exposure > best:
					best = exposure
					best_rid = rid
			var target := cfg(game, "strategic_cap") * best
			var key := _pair(buyer, seller)
			var old: Dictionary = d["dependency"].get(key, {"strategic": 0.0})
			var current: float = old.get("strategic", 0.0)
			var value := current + clampf(target - current, -cfg(game, "dependency_fall"), cfg(game, "dependency_growth"))
			d["dependency"][key] = {"strategic": value, "goods": 0.0, "religion": 0.0,
				"target": target, "main_resource": best_rid}
			if not is_equal_approx(value, current):
				events.append({"type": "dependency_changed", "dependent": buyer, "provider": seller, "value": value})

static func dependency(game: Game, dependent: int, provider: int) -> Dictionary:
	initialize(game)
	var item: Dictionary = game.state.diplomacy["dependency"].get(_pair(dependent, provider), {})
	return item.duplicate(true)

static func influence(game: Game, pid: int) -> Dictionary:
	initialize(game)
	return game.state.diplomacy["influence"].get(str(pid), {}).duplicate(true)

static func _living(game: Game, pid: int) -> float:
	var cities := game.state.cities_of(pid)
	var people := 0.0
	var sum := 0.0
	var lux := CityRules.luxury_amenities(game, pid)
	var weights: Dictionary = game.data.diplomacy["living_weights"]
	for city in cities:
		var y := CityRules.city_yields(game, city, lux)
		var food_need := CityRules.food_consumption(game, city)
		var housing := CityRules.housing(game, city)
		var amenity := CityRules.amenity_info(game, city, lux)
		var order := CityLife.order(game, city)
		var score := float(weights["food"]) * clampf(float(y.get("food", 0.0)) / maxf(1.0, food_need), 0, 1)
		score += float(weights["housing"]) * clampf(housing / maxf(1.0, city.population), 0, 1)
		score += float(weights["amenities"]) * (1.0 if int(amenity["need"]) <= 0 else clampf(float(amenity["have"]) / float(amenity["need"]), 0, 1))
		score += float(weights["order"]) * (1.0 if float(order["need"]) <= 0.0 else clampf(float(order["supply"]) / float(order["need"]), 0, 1))
		sum += score * city.population
		people += city.population
	return sum / people if people > 0.0 else 0.0

static func _record_route_and_living(game: Game, round_number: int) -> void:
	var d := game.state.diplomacy
	for pid_value in d["initial_majors"]:
		var pid := int(pid_value)
		if not _major(game, pid):
			continue
		var living_key := str(pid)
		if not d["living_history"].has(living_key):
			d["living_history"][living_key] = []
		d["living_history"][living_key].append({"round": round_number, "strength": _living(game, pid)})
		for peer_value in d["initial_majors"]:
			var peer := int(peer_value)
			if peer == pid or not _major(game, peer):
				continue
			var routes := 0
			for u in game.state.units_of(pid):
				if not u.trade_route.is_empty():
					var target := game.state.city(int(u.trade_route["destination"]))
					if target != null and target.owner == peer:
						routes += 1
			var strength := 0.0
			if routes > 0:
				strength = cfg(game, "route_two_strength") if routes > 1 else cfg(game, "route_one_strength")
			var key := _pair(pid, peer)
			if not d["route_history"].has(key):
				d["route_history"][key] = []
			d["route_history"][key].append({"round": round_number, "strength": strength})

static func _average_strength(history: Array, round_number: int, window: int) -> float:
	var total := 0.0
	for item in history:
		if int(item["round"]) > round_number - window:
			total += float(item["strength"])
	return total / maxf(1.0, window)

static func _update_influence(game: Game, round_number: int, events: Array) -> void:
	var d := game.state.diplomacy
	var majors: Array = d["initial_majors"]
	var n := maxi(1, majors.size() - 1)
	for pid_value in majors:
		var pid := int(pid_value)
		if not _major(game, pid):
			continue
		var excess := 0.0
		var route_power := 0.0
		var supply_power := 0.0
		for peer_value in majors:
			var peer := int(peer_value)
			if peer == pid or not _major(game, peer):
				continue
			excess += maxf(0.0, float(dependency(game, peer, pid).get("strategic", 0.0)) \
					- float(dependency(game, pid, peer).get("strategic", 0.0)))
			route_power += _average_strength(d["route_history"].get(_pair(pid, peer), []),
				round_number, int(cfg(game, "demand_window")))
			var peer_supply := 0.0
			for rid in game.data.resource_ids:
				if game.data.resources[rid].get("class", "") != "strategic":
					continue
				var need := _resource_need(game, peer, rid, game.state.turn + 1)
				if need > 0.0:
					peer_supply = maxf(peer_supply, minf(1.0, _recent_delivery(game, peer, pid, rid, round_number) / need))
			supply_power += peer_supply
		var sources := {"dependency": cfg(game, "dependency_influence_cap") * minf(1.0, excess / (cfg(game, "dependency_full_average") * n)),
			"routes": cfg(game, "route_influence_cap") * minf(1.0, route_power / n),
			"supplies": cfg(game, "supply_influence_cap") * minf(1.0, supply_power / n),
			"living": cfg(game, "living_influence_cap") * _average_strength(
				d["living_history"].get(str(pid), []), round_number, int(cfg(game, "demand_window")))}
		var target := 0.0
		for amount in sources.values():
			target += float(amount)
		target = minf(cfg(game, "influence_max"), target)
		var old: Dictionary = d["influence"].get(str(pid), {"value": 0.0})
		var value: float = old.get("value", 0.0)
		var change := (target - value) * cfg(game, "influence_growth_fraction")
		value += clampf(change, -cfg(game, "influence_fall"), cfg(game, "influence_rise"))
		d["influence"][str(pid)] = {"value": value, "target": target, "sources": sources}
		if not is_equal_approx(value, float(old.get("value", 0.0))):
			events.append({"type": "influence_changed", "player": pid, "value": value})
