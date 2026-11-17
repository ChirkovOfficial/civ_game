class_name ParkRules
extends RefCounted
## Национальные парки: ромб из четырёх природных клеток одного города.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["park_min_appeal", "park_tourism_per_appeal", "park_amenities",
			"naturalist_faith_cost", "naturalist_cost_step"]:
		if float(data.culture_content.get(key, 0)) <= 0.0:
			errors.append("Национальные парки: неверное значение %s" % key)
	return errors


static func faith_cost(game: Game, pid: int) -> int:
	return ceili(float(game.data.culture_content["naturalist_faith_cost"]) \
		+ int(game.state.culture_data["naturalists_recruited"].get(str(pid), 0)) \
		* float(game.data.culture_content["naturalist_cost_step"]))


static func recruit_error(game: Game, pid: int, city: City) -> String:
	if city == null or city.owner != pid:
		return "Нужен свой город"
	if not game.state.player(pid).has_civic("CONSERVATION"):
		return "Нужен институт «Охрана природы»"
	if game.state.player(pid).faith < faith_cost(game, pid):
		return "Недостаточно веры"
	if RockBandRules.spawn_tile(game, city, "NATURALIST") < 0:
		return "Натуралисту негде появиться"
	return ""


static func recruit(game: Game, pid: int, city: City, events: Array) -> String:
	var err := recruit_error(game, pid, city)
	if err != "":
		return err
	var tile := RockBandRules.spawn_tile(game, city, "NATURALIST")
	var cost := faith_cost(game, pid)
	game.state.player(pid).faith -= cost
	game.state.culture_data["naturalists_recruited"][str(pid)] = int(game.state.culture_data["naturalists_recruited"].get(str(pid), 0)) + 1
	var unit := game.state.add_unit(pid, "NATURALIST", tile)
	unit.moves_left = 0.0
	events.append({"type": "unit_created", "unit": unit.id, "player": pid, "faith": cost})
	return ""


static func _eligible(game: Game, city: City, tile: int) -> bool:
	var map := game.state.map
	return tile >= 0 and map.owner_city[tile] == city.id and map.is_land(tile) \
		and map.district[tile] == "" and map.improvement[tile] == "" and map.resource[tile] == "" \
		and CultureRules.appeal(game, tile) >= int(game.data.culture_content["park_min_appeal"])


static func _option(game: Game, city: City, anchor: int, direction: int) -> Dictionary:
	var grid := game.state.map.grid
	var first := grid.neighbor(anchor, direction)
	var second := grid.neighbor(anchor, (direction + 1) % 6)
	if first < 0 or second < 0:
		return {}
	var last := grid.neighbor(first, (direction + 1) % 6)
	if last < 0:
		return {}
	var tiles: Array[int] = [anchor, first, second, last]
	var seen := {}
	var tourism := 0.0
	for tile in tiles:
		if seen.has(tile) or not _eligible(game, city, tile):
			return {}
		seen[tile] = true
		tourism += CultureRules.appeal(game, tile) * float(game.data.culture_content["park_tourism_per_appeal"])
	return {"tiles": tiles, "city": city.id, "tourism": tourism}


static func best_option(game: Game, pid: int, naturalist_tile: int) -> Dictionary:
	if naturalist_tile < 0 or naturalist_tile >= game.state.map.size() or game.state.map.is_mountain(naturalist_tile):
		return {}
	var city := game.state.city_owning(naturalist_tile)
	if city == null or city.owner != pid:
		return {}
	var best := {}
	var anchors: Array[int] = [naturalist_tile]
	for neighbor in game.state.map.grid.neighbors(naturalist_tile):
		anchors.append(neighbor)
	for anchor in anchors:
		for direction in 6:
			var option := _option(game, city, anchor, direction)
			if option.is_empty() or not option["tiles"].has(naturalist_tile):
				continue
			if best.is_empty() or float(option["tourism"]) > float(best["tourism"]):
				best = option
	return best


static func best_site(game: Game, pid: int) -> Dictionary:
	var best := {}
	for city in game.state.cities_of(pid):
		for tile in game.state.map.grid.tiles_in_radius(city.tile, 3):
			if game.state.map.owner_city[tile] != city.id or game.state.map.is_mountain(tile) \
					or game.state.map.feature_def(tile).get("impassable", false):
				continue
			var occupied := false
			for other in game.state.units_at(tile):
				if Movement.layer(game, other.type) == "CIVILIAN":
					occupied = true
			if occupied:
				continue
			var option := best_option(game, pid, tile)
			if option.is_empty():
				continue
			if best.is_empty() or float(option["tourism"]) > float(best["tourism"]):
				best = option.duplicate(true)
				best["stand_tile"] = tile
	return best


static func found_error(game: Game, unit: Unit) -> String:
	if unit == null or unit.type != "NATURALIST" or game.state.unit(unit.id) == null:
		return "Нужен натуралист"
	if unit.moves_left <= 0.0:
		return "Нет очков движения"
	if best_option(game, unit.owner, unit.tile).is_empty():
		return "Нужны четыре свободные природные клетки одного города с привлекательностью не ниже 2"
	return ""


static func found(game: Game, unit: Unit, events: Array) -> String:
	var err := found_error(game, unit)
	if err != "":
		return err
	var option := best_option(game, unit.owner, unit.tile)
	var city := game.state.city(int(option["city"]))
	var tiles: Array = option["tiles"]
	city.parks.append({"tiles": tiles.duplicate()})
	for tile in tiles:
		game.state.map.improvement[tile] = "NATIONAL_PARK"
		game.state.map.pillaged[tile] = 0
	game.state.remove_unit(unit.id)
	Visibility.recompute(game, city.owner)
	events.append({"type": "national_park_founded", "player": city.owner, "city": city.id,
		"tiles": tiles.duplicate(), "tourism": option["tourism"]})
	return ""


static func active(game: Game, city: City, park: Dictionary) -> bool:
	for tile in park["tiles"]:
		if game.state.map.owner_city[int(tile)] != city.id or game.state.map.improvement[int(tile)] != "NATIONAL_PARK" \
				or game.state.map.pillaged[int(tile)] != 0:
			return false
	return true


static func tourism(game: Game, city: City) -> float:
	var amount := 0.0
	for park in city.parks:
		if active(game, city, park):
			for tile in park["tiles"]:
				amount += CultureRules.appeal(game, int(tile)) * float(game.data.culture_content["park_tourism_per_appeal"])
	return amount


static func amenities(game: Game, city: City) -> int:
	var amount := 0
	for park in city.parks:
		if active(game, city, park):
			amount += int(game.data.culture_content["park_amenities"])
	return amount
