class_name WonderRules
extends RefCounted
## Уникальные мировые чудеса с закреплённой клеткой и гонкой производства.

const ERAS := ["ANCIENT", "CLASSICAL", "MEDIEVAL", "RENAISSANCE", "INDUSTRIAL", "MODERN",
	"ATOMIC", "INFORMATION", "FUTURE"]


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	if float(data.culture_content.get("wonder_loser_gold_fraction", -1)) < 0.0:
		errors.append("Чудеса: неверная компенсация")
	for id in data.wonder_ids:
		var wonder: Dictionary = data.wonders[id]
		if float(wonder.get("cost", 0)) <= 0 or float(wonder.get("tourism", 0)) < 0:
			errors.append("Чудо %s: неверная стоимость или туризм" % id)
		if wonder.has("tech") and not data.techs.has(wonder["tech"]):
			errors.append("Чудо %s: неизвестная технология" % id)
		if wonder.has("civic") and not data.civics.has(wonder["civic"]):
			errors.append("Чудо %s: неизвестный институт" % id)
		if wonder.has("adjacent") and not data.districts.has(wonder["adjacent"]):
			errors.append("Чудо %s: неизвестный соседний район" % id)
	return errors


static func built_city(game: Game, id: String) -> City:
	for city in game.state.cities.values():
		for wonder in city.wonders:
			if wonder["id"] == id and wonder["complete"]:
				return city
	return null


static func type_error(game: Game, city: City, id: String) -> String:
	var def: Dictionary = game.data.wonders.get(id, {})
	if def.is_empty():
		return "Неизвестное чудо света"
	var player := game.state.player(city.owner)
	if def.has("tech") and not player.has_tech(def["tech"]):
		return "Нужна технология «%s»" % game.data.techs[def["tech"]]["name"]
	if def.has("civic") and not player.has_civic(def["civic"]):
		return "Нужен институт «%s»" % game.data.civics[def["civic"]]["name"]
	if built_city(game, id) != null:
		return "Чудо уже построено в мире"
	for own in game.state.cities_of(city.owner):
		for wonder in own.wonders:
			if wonder["id"] == id:
				return "Это чудо уже заложено вашей державой"
	return ""


static func placement_error(game: Game, city: City, id: String, tile: int) -> String:
	var def: Dictionary = game.data.wonders.get(id, {})
	if def.is_empty():
		return "Неизвестное чудо света"
	if tile < 0 or tile >= game.state.map.size():
		return "Выберите клетку"
	var existing := entry_at(city, tile)
	if not existing.is_empty() and existing["id"] == id and not existing["complete"]:
		return "" if built_city(game, id) == null else "Чудо уже построено в мире"
	var err := type_error(game, city, id)
	if err != "":
		return err
	var map := game.state.map
	if map.owner_city[tile] != city.id or map.grid.distance(city.tile, tile) > 3:
		return "Клетка должна принадлежать городу в радиусе трёх клеток"
	if map.is_water(tile) or map.is_mountain(tile) or map.district[tile] != "" or map.improvement[tile] != "":
		return "Нужна свободная клетка суши без района и улучшения"
	if map.resource[tile] != "":
		return "Чудо не строится на ресурсе"
	if def.has("terrain") and not def["terrain"].has(map.terrain[tile]):
		return "Неподходящая местность"
	if def.has("adjacent"):
		var found := false
		for neighbor in map.grid.neighbors(tile):
			var district := DistrictRules.at(game, neighbor)
			if not district.is_empty() and district[0].owner == city.owner and district[1]["type"] == def["adjacent"] \
					and bool(district[1]["complete"]):
				found = true
		if not found:
			return "Нужен соседний действующий район «%s»" % game.data.districts[def["adjacent"]]["name"]
	return ""


static func valid_tiles(game: Game, city: City, id: String) -> Array[int]:
	var result: Array[int] = []
	for tile in game.state.map.grid.tiles_in_radius(city.tile, 3):
		if placement_error(game, city, id, tile) == "":
			result.append(tile)
	return result


static func entry_at(city: City, tile: int) -> Dictionary:
	for wonder in city.wonders:
		if int(wonder["tile"]) == tile:
			return wonder
	return {}


static func place(game: Game, city: City, id: String, tile: int) -> void:
	city.wonders.append({"id": id, "tile": tile, "complete": false})
	game.state.map.district[tile] = "WONDER:" + id


static func current_era(game: Game, pid: int) -> int:
	var rank := 0
	var player := game.state.player(pid)
	for tech in player.known_techs:
		rank = maxi(rank, ERAS.find(str(game.data.techs.get(tech, {}).get("era", "ANCIENT"))))
	for civic in player.known_civics:
		rank = maxi(rank, ERAS.find(str(game.data.civics.get(civic, {}).get("era", "ANCIENT"))))
	return rank


static func complete(game: Game, city: City, item: Dictionary, events: Array) -> void:
	var wonder := entry_at(city, int(item["tile"]))
	wonder["complete"] = true
	wonder["built_era"] = current_era(game, city.owner)
	events.append({"type": "wonder_completed", "player": city.owner, "city": city.id,
		"wonder": item["id"], "tile": int(item["tile"])})
	# Проигравшие освобождают участки сразу, в том числе если сменили производство.
	for other in game.state.cities.values():
		if other.id == city.id:
			continue
		for rival in other.wonders.duplicate():
			if rival["id"] != item["id"] or rival["complete"]:
				continue
			var rival_item := {"kind": "wonder", "id": item["id"], "tile": int(rival["tile"])}
			resolve_lost(game, other, rival_item, events)
			if not other.queue.is_empty() and City.item_key(other.queue[0]) == City.item_key(rival_item):
				other.queue.pop_front()
				events.append({"type": "production_needed", "city": other.id})


static func resolve_lost(game: Game, city: City, item: Dictionary, events: Array) -> void:
	var tile := int(item["tile"])
	var wonder := entry_at(city, tile)
	if wonder.is_empty():
		return
	var progress := float(city.progress.get(City.item_key(item), 0.0))
	var gold := floori(progress * float(game.data.culture_content["wonder_loser_gold_fraction"]))
	game.state.player(city.owner).treasury += gold
	city.wonders.erase(wonder)
	game.state.map.district[tile] = ""
	city.progress.erase(City.item_key(item))
	events.append({"type": "wonder_lost", "city": city.id, "wonder": item["id"], "gold": gold})


static func yields(game: Game, city: City) -> Dictionary:
	var result := {}
	for wonder in city.wonders:
		if wonder["complete"]:
			Yields.add_into(result, game.data.wonders.get(wonder["id"], {}).get("yields", {}))
	return result


static func tourism(game: Game, city: City) -> float:
	var result := 0.0
	for wonder in city.wonders:
		if not wonder["complete"]:
			continue
		var def: Dictionary = game.data.wonders.get(wonder["id"], {})
		result += float(def.get("tourism", 0)) + maxi(0, current_era(game, city.owner) - int(wonder.get("built_era", 0))) \
			* float(game.data.culture_content.get("wonder_tourism_per_era", 0))
	return result
