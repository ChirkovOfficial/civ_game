class_name RockBandRules
extends RefCounted
## Покупка рок-групп за веру и разовые концерты в чужих городах.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["rock_band_faith_cost", "rock_band_cost_step", "rock_band_concert_tourism",
			"rock_band_charges"]:
		if float(data.culture_content.get(key, 0)) <= 0.0:
			errors.append("Рок-группы: неверное значение %s" % key)
	for key in ["rock_band_concert_growth", "rock_band_break_chance"]:
		var value := float(data.culture_content.get(key, -1))
		if value < 0.0 or (key == "rock_band_break_chance" and value > 1.0):
			errors.append("Рок-группы: неверное значение %s" % key)
	return errors


static func spawn_tile(game: Game, city: City, type: String) -> int:
	var layer := Movement.layer(game, type)
	var map := game.state.map
	for tile in map.grid.tiles_in_radius(city.tile, 2):
		if map.owner_city[tile] != city.id or map.is_water(tile) or map.is_mountain(tile) \
				or map.feature_def(tile).get("impassable", false):
			continue
		var free := true
		for other in game.state.units_at(tile):
			if other.owner != city.owner or Movement.layer(game, other.type) == layer:
				free = false
				break
		if free:
			return tile
	return -1


static func faith_cost(game: Game, pid: int) -> int:
	return ceili(float(game.data.culture_content["rock_band_faith_cost"]) \
		+ int(game.state.culture_data["rock_bands_recruited"].get(str(pid), 0)) \
		* float(game.data.culture_content["rock_band_cost_step"]))


static func recruit_error(game: Game, pid: int, city: City) -> String:
	if city == null or city.owner != pid:
		return "Нужен свой город"
	if not game.state.player(pid).has_civic("COLD_WAR"):
		return "Нужен институт «Холодная война»"
	if game.state.player(pid).faith < faith_cost(game, pid):
		return "Недостаточно веры"
	if spawn_tile(game, city, "ROCK_BAND") < 0:
		return "Рок-группе негде появиться"
	return ""


static func recruit(game: Game, pid: int, city: City, events: Array) -> String:
	var err := recruit_error(game, pid, city)
	if err != "":
		return err
	var tile := spawn_tile(game, city, "ROCK_BAND")
	var cost := faith_cost(game, pid)
	game.state.player(pid).faith -= cost
	game.state.culture_data["rock_bands_recruited"][str(pid)] = int(game.state.culture_data["rock_bands_recruited"].get(str(pid), 0)) + 1
	var unit := game.state.add_unit(pid, "ROCK_BAND", tile)
	unit.charges = int(game.data.culture_content["rock_band_charges"])
	unit.moves_left = 0.0
	events.append({"type": "unit_created", "unit": unit.id, "player": pid, "faith": cost})
	return ""


static func venue(game: Game, unit: Unit) -> Dictionary:
	var host_city := game.state.city_owning(unit.tile)
	if host_city == null or host_city.owner == unit.owner or game.state.at_war(unit.owner, host_city.owner):
		return {}
	var best := {}
	var tiles: Array[int] = [unit.tile]
	for neighbor in game.state.map.grid.neighbors(unit.tile):
		tiles.append(neighbor)
	for tile in tiles:
		if game.state.map.owner_city[tile] != host_city.id or game.state.map.pillaged[tile] != 0:
			continue
		var marker: String = game.state.map.district[tile]
		var multiplier := 0.0
		if marker == "CITY_CENTER":
			multiplier = 1.0
		elif marker == "THEATER_SQUARE" or marker == "ENTERTAINMENT_COMPLEX":
			var district := DistrictRules.entry_at(host_city, tile)
			if not district.is_empty() and district["complete"]:
				multiplier = 1.25
		elif marker.begins_with("WONDER:") and WonderRules.entry_at(host_city, tile).get("complete", false):
			multiplier = 1.5
		if multiplier > float(best.get("multiplier", 0.0)):
			best = {"city": host_city.id, "host": host_city.owner, "tile": tile, "multiplier": multiplier}
	return best


static func concert_error(game: Game, unit: Unit) -> String:
	if unit == null or unit.type != "ROCK_BAND" or game.state.unit(unit.id) == null:
		return "Нужна рок-группа"
	if unit.moves_left <= 0.0 or unit.charges <= 0:
		return "Нет очков движения или выступлений"
	var place := venue(game, unit)
	if place.is_empty():
		return "Нужна доступная концертная площадка в городе мирной чужой державы"
	if not game.state.player(unit.owner).met.has(int(place["host"])):
		return "Вы ещё не встретили эту державу"
	return ""


static func perform(game: Game, unit: Unit, events: Array) -> String:
	var err := concert_error(game, unit)
	if err != "":
		return err
	var place := venue(game, unit)
	var host := int(place["host"])
	var value := float(game.data.culture_content["rock_band_concert_tourism"]) * float(place["multiplier"]) \
		* (1.0 + unit.xp * float(game.data.culture_content["rock_band_concert_growth"])) \
		* CultureRules.pair_multiplier(game, unit.owner, host)
	var player := game.state.player(unit.owner)
	player.tourism_points[str(host)] = float(player.tourism_points.get(str(host), 0.0)) + value
	unit.xp += 1
	unit.charges -= 1
	unit.moves_left = 0.0
	unit.acted = true
	var dissolved := unit.charges <= 0 or game.state.rng.chance(float(game.data.culture_content["rock_band_break_chance"]))
	events.append({"type": "rock_concert", "player": unit.owner, "host": host, "city": place["city"],
		"tourism": value, "dissolved": dissolved})
	if dissolved:
		game.state.remove_unit(unit.id)
		Visibility.recompute(game, player.id)
	else:
		events.append({"type": "unit_updated", "unit": unit.id})
	return ""
