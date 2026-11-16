class_name TradeRules
extends RefCounted
## Маршрут хранится у торговца. За ход он проходит одну клетку и возвращается в город отправления.


static func capacity(game: Game, pid: int) -> int:
	var p := game.state.player(pid)
	if not p.has_civic(game.data.trade["unlock"]):
		return 0
	var total := 1
	for city in game.state.cities_of(pid):
		for district in city.districts:
			if district["complete"] and district["type"] in game.data.trade["capacity_districts"]:
				total += 1
				break
	return total


static func active_count(game: Game, pid: int) -> int:
	var total := 0
	for unit in game.state.units_of(pid):
		if not unit.trade_route.is_empty():
			total += 1
	return total


static func start_error(game: Game, unit: Unit) -> String:
	if unit.type != game.data.trade["trader"] or not unit.trade_route.is_empty():
		return "Нужен свободный торговец"
	if unit.moves_left <= 0.0:
		return "Торговец уже действовал в этом ходу"
	var origin := game.state.city_at(unit.tile)
	if origin == null or origin.owner != unit.owner:
		return "Торговец должен находиться в своём городе"
	if active_count(game, unit.owner) >= capacity(game, unit.owner):
		return "Достигнут лимит торговых путей"
	return ""


static func options(game: Game, unit: Unit) -> Array[Dictionary]:
	if start_error(game, unit) != "":
		return []
	return plans_from(game, game.state.city_at(unit.tile))


static func plans_from(game: Game, origin: City) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var city_ids := game.state.cities.keys()
	city_ids.sort()
	for id in city_ids:
		var route := plan(game, origin, game.state.city(id))
		if not route.is_empty():
			result.append(route)
	return result


static func plan(game: Game, origin: City, destination: City) -> Dictionary:
	if destination == null or destination == origin:
		return {}
	var pid := origin.owner
	var p := game.state.player(pid)
	if not p.is_revealed(destination.tile) or game.state.at_war(pid, destination.owner):
		return {}
	if destination.owner != pid and not p.met.has(destination.owner):
		return {}
	var path := _find_path(game, origin, destination, false)
	if p.has_tech(game.data.trade["sailing"]) and game.state.map.is_coastal_land(origin.tile) \
			and game.state.map.is_coastal_land(destination.tile):
		var sea_path := _find_path(game, origin, destination, true)
		if not sea_path.is_empty() and (path.is_empty() or sea_path.size() < path.size()):
			path = sea_path
	if path.is_empty():
		return {}
	var round_trip := 2 * (path.size() - 1)
	var minimum := ceili(float(game.data.trade["minimum_turns"]) * CityRules.speed_mult(game))
	var turns := maxi(1, ceili(float(minimum) / round_trip)) * round_trip
	return {"origin": origin.id, "destination": destination.id, "path": path, "elapsed": 0, "turns": turns}


## Поиск в ширину по разведанным клеткам. Свой торговый пост начинает новый участок пути.
static func _find_path(game: Game, origin: City, destination: City, sea: bool) -> Array[int]:
	var map := game.state.map
	var p := game.state.player(origin.owner)
	var limit := int(game.data.trade["sea_range" if sea else "land_range"])
	var tiles: Array[int] = [origin.tile]
	var legs: Array[int] = [0]
	var parents: Array[int] = [-1]
	var best_leg := {origin.tile: 0}
	var cursor := 0
	while cursor < tiles.size():
		var tile := tiles[cursor]
		if tile == destination.tile:
			var result: Array[int] = []
			while cursor >= 0:
				result.append(tiles[cursor])
				cursor = parents[cursor]
			result.reverse()
			return result
		if legs[cursor] < limit:
			for next in map.grid.neighbors(tile):
				if not p.is_revealed(next) or not _passable(game, p, next, destination.tile, sea):
					continue
				var city := game.state.city_owning(next)
				var distance := legs[cursor] + 1
				if city != null and city.tile == next and city.trade_posts.has(p.id):
					distance = 0
				if distance >= int(best_leg.get(next, limit + 1)):
					continue
				best_leg[next] = distance
				tiles.append(next)
				legs.append(distance)
				parents.append(cursor)
		cursor += 1
	return []


static func _passable(game: Game, p: Player, tile: int, destination: int, sea: bool) -> bool:
	var map := game.state.map
	var owner := game.state.city_owning(tile)
	if owner != null and game.state.at_war(p.id, owner.owner):
		return false
	if map.feature_def(tile).get("impassable", false):
		return false
	if not sea:
		return map.is_land(tile) and not map.is_mountain(tile)
	if map.is_water(tile):
		var need: String = map.terrain_def(tile).get("requires_tech", "")
		return not map.terrain_def(tile).get("fresh_water", false) and (need == "" or p.has_tech(need))
	return owner != null and owner.tile == tile and (tile == destination or owner.trade_posts.has(p.id))


static func route_yields(game: Game, route: Dictionary) -> Dictionary:
	var origin := game.state.city(int(route["origin"]))
	var destination := game.state.city(int(route["destination"]))
	if origin == null or destination == null:
		return {}
	var table: Dictionary = game.data.trade["domestic" if origin.owner == destination.owner else "international"]
	var result: Dictionary = table["CITY_CENTER"].duplicate()
	for district in destination.districts:
		if district["complete"]:
			Yields.add_into(result, table.get(district["type"], {}))
	var counted := {}
	var path: Array = route["path"]
	for index in range(1, path.size() - 1):
		var tile := int(path[index])
		var city := game.state.city_owning(tile)
		if city != null and city.tile == tile and city.trade_posts.has(origin.owner) and not counted.has(city.id):
			counted[city.id] = true
			result["gold"] = float(result.get("gold", 0)) + float(game.data.trade["post_gold"])
	return result


static func add_city_yields(game: Game, city: City, yields: Dictionary) -> void:
	if not game.state.player(city.owner).has_civic(game.data.trade["unlock"]):
		return
	for unit in game.state.units_of(city.owner):
		if int(unit.trade_route.get("origin", -1)) == city.id:
			Yields.add_into(yields, route_yields(game, unit.trade_route))


static func start(unit: Unit, route: Dictionary, events: Array) -> void:
	unit.trade_route = route
	unit.moves_left = 0.0
	unit.orders = {}
	events.append({"type": "trade_started", "unit": unit.id, "player": unit.owner, "destination": route["destination"]})


static func cancel_invalid(game: Game, events: Array) -> void:
	for p in game.state.players:
		for unit in game.state.units_of(p.id):
			var route := unit.trade_route
			if route.is_empty():
				continue
			var origin := game.state.city(int(route["origin"]))
			var destination := game.state.city(int(route["destination"]))
			var blocked := origin == null or origin.owner != unit.owner or destination == null \
				or game.state.at_war(unit.owner, destination.owner)
			if not blocked:
				for tile in route["path"]:
					var city := game.state.city_owning(int(tile))
					if city != null and game.state.at_war(unit.owner, city.owner):
						blocked = true
						break
			if blocked:
				_cancel(game, unit, origin, events)


static func _cancel(game: Game, unit: Unit, origin: City, events: Array) -> void:
	unit.trade_route = {}
	unit.moves_left = 0.0
	events.append({"type": "trade_cancelled", "unit": unit.id, "player": unit.owner})
	if origin != null and origin.owner == unit.owner:
		unit.tile = origin.tile
	else:
		var fallback := game.state.cities_of(unit.owner)
		if fallback.is_empty():
			game.state.remove_unit(unit.id)
		else:
			unit.tile = fallback[0].tile
	Visibility.recompute(game, unit.owner)


static func advance(game: Game, pid: int, events: Array) -> void:
	for unit in game.state.units_of(pid):
		var route := unit.trade_route
		if route.is_empty():
			continue
		var path: Array = route["path"]
		var span := path.size() - 1
		var elapsed := int(route["elapsed"]) + 1
		var offset := elapsed % (2 * span)
		var from := unit.tile
		unit.tile = int(path[mini(offset, 2 * span - offset)])
		route["elapsed"] = elapsed
		events.append({"type": "unit_moved", "unit": unit.id, "from": from, "to": unit.tile})
		_build_road(game, pid, from, unit.tile, events)
		if elapsed == int(route["turns"]):
			var destination := game.state.city(int(route["destination"]))
			if not destination.trade_posts.has(pid):
				destination.trade_posts.append(pid)
			unit.trade_route = {}
			events.append({"type": "trade_completed", "unit": unit.id, "player": pid, "destination": destination.id})


static func _build_road(game: Game, pid: int, from: int, tile: int, events: Array) -> void:
	var map := game.state.map
	if map.is_water(from) or map.is_water(tile):
		return
	var level := UnitRules.road_level_for(game, pid)
	for t in [from, tile]:
		if map.road[t] < level:
			map.road[t] = level
			events.append({"type": "road_built", "tile": t})


static func raid_target(game: Game, attacker: Unit) -> Unit:
	if attacker.moves_left <= 0.0 or not Combat.can_attack(game, attacker):
		return null
	for unit in game.state.units_at(attacker.tile):
		if not unit.trade_route.is_empty() and game.state.at_war(attacker.owner, unit.owner):
			return unit
	return null


static func raid(game: Game, attacker: Unit, trader: Unit, events: Array) -> void:
	var gold := int(game.data.trade["raid_gold"])
	game.state.player(attacker.owner).treasury += gold
	attacker.moves_left = 0.0
	attacker.acted = true
	attacker.orders = {}
	game.state.remove_unit(trader.id)
	Visibility.recompute(game, trader.owner)
	events.append({"type": "trade_raided", "unit": trader.id, "player": trader.owner, "by": attacker.owner, "gold": gold})


static func validate_data(data: GameData) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not data.units.has(data.trade.get("trader")) or not data.civics.has(data.trade.get("unlock")) \
			or not data.techs.has(data.trade.get("sailing")):
		errors.append("Неверная настройка торговца или открытия торговли")
	for id in data.trade.get("capacity_districts", []):
		if not data.districts.has(id):
			errors.append("Неизвестный район для лимита торговли: %s" % id)
	return errors
