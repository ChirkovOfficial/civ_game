class_name CultureRules
extends RefCounted
## Шедевры, туризм между державами и культурная победа.


static func config(game: Game, key: String) -> float:
	return float(game.data.culture_setup.get(key, 0.0))


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["domestic_culture_divisor", "tourism_divisor_per_major", "commission_cost",
			"work_culture", "work_tourism", "holy_city_tourism", "wall_tourism"]:
		if float(data.culture_setup.get(key, -1)) <= 0.0:
			errors.append("Культурная победа: неверное значение %s" % key)
	for key in ["domestic_divisor_per_extra_major", "trade_route_bonus", "open_borders_bonus",
			"different_religion_penalty", "different_tier3_government_penalty",
			"computers_bonus", "social_media_bonus"]:
		if float(data.culture_setup.get(key, -1)) < 0.0:
			errors.append("Культурная победа: неверный модификатор %s" % key)
	return errors


static func work_slots(game: Game, city: City) -> int:
	var slots := 0
	for district in DistrictRules.of_type(city, "THEATER_SQUARE", true):
		if game.state.map.pillaged[int(district["tile"])] != 0:
			continue
		var tier := int(district["tier"])
		if tier >= 2:
			slots += 3 if tier == 2 else 6
	return slots


static func active_works(game: Game, city: City) -> int:
	return mini(city.great_works, work_slots(game, city))


static func work_culture(game: Game, city: City) -> float:
	var amount := active_works(game, city) * config(game, "work_culture")
	for i in mini(active_works(game, city), city.great_work_types.size()):
		var def: Dictionary = game.data.culture_content.get("works", {}).get(city.great_work_types[i], {})
		amount += float(def.get("culture", config(game, "work_culture"))) - config(game, "work_culture")
	return amount


static func work_tourism(game: Game, city: City) -> float:
	var amount := active_works(game, city) * config(game, "work_tourism")
	for i in mini(active_works(game, city), city.great_work_types.size()):
		var def: Dictionary = game.data.culture_content.get("works", {}).get(city.great_work_types[i], {})
		amount += float(def.get("tourism", config(game, "work_tourism"))) - config(game, "work_tourism")
		for tech in def.get("tech_tourism_multiplier", {}):
			if game.state.player(city.owner).has_tech(tech):
				amount += float(def.get("tourism", config(game, "work_tourism"))) \
					* (float(def["tech_tourism_multiplier"][tech]) - 1.0)
	return amount


static func appeal(game: Game, tile: int) -> int:
	var map := game.state.map
	var score := 2
	if map.has_river(tile):
		score += 1
	for neighbor in map.grid.neighbors(tile):
		if map.is_mountain(neighbor) or map.feature[neighbor] == "WOODS":
			score += 1
		if map.district[neighbor].begins_with("WONDER:"):
			var owner_city := game.state.city_owning(neighbor)
			if owner_city != null and WonderRules.entry_at(owner_city, neighbor).get("complete", false):
				score += 1
		score += int(game.data.improvements.get(map.improvement[neighbor], {}).get("appeal", 0))
	return maxi(0, score)


static func commission_error(game: Game, city: City) -> String:
	if not game.state.player(city.owner).has_civic("HUMANISM"):
		return "Нужен институт «Гуманизм»"
	if work_slots(game, city) <= city.great_works:
		return "Нужна свободная ячейка шедевра в работающей Театральной площади II"
	return ""


static func complete_commission(game: Game, city: City, events: Array) -> void:
	while city.great_work_types.size() < city.great_works:
		city.great_work_types.append("")
	city.great_works += 1
	city.great_work_types.append("")
	events.append({"type": "great_work_created", "player": city.owner, "city": city.id,
		"count": city.great_works})


static func move_work_error(game: Game, pid: int, source: City, target: City, index: int) -> String:
	if source == null or target == null or source.owner != pid or target.owner != pid:
		return "Нужны два своих города"
	if source.id == target.id:
		return "Выберите другой город"
	if index < 0 or index >= source.great_works:
		return "Такого шедевра нет"
	if target.great_works >= work_slots(game, target):
		return "В другом городе нет свободной ячейки шедевра"
	return ""


static func move_work(game: Game, pid: int, source: City, target: City, index: int, events: Array) -> String:
	var err := move_work_error(game, pid, source, target, index)
	if err != "":
		return err
	while source.great_work_types.size() < source.great_works:
		source.great_work_types.append("")
	while target.great_work_types.size() < target.great_works:
		target.great_work_types.append("")
	var kind: String = source.great_work_types[index]
	source.great_work_types.remove_at(index)
	source.great_works -= 1
	target.great_work_types.append(kind)
	target.great_works += 1
	events.append({"type": "great_work_moved", "player": pid, "from_city": source.id,
		"to_city": target.id, "work": kind})
	return ""


static func domestic_tourists(game: Game, pid: int) -> int:
	if game.state.cities_of(pid).is_empty():
		return 0
	var divisor := config(game, "domestic_culture_divisor") \
		+ maxi(0, major_count(game) - 2) * config(game, "domestic_divisor_per_extra_major")
	return maxi(1, floori(game.state.player(pid).culture_total / divisor))


static func major_count(game: Game) -> int:
	var n := 0
	for player in game.state.players:
		if not player.is_barbarian:
			n += 1
	return n


static func visiting_tourists(game: Game, pid: int, from: int) -> int:
	var points := float(game.state.player(pid).tourism_points.get(str(from), 0.0))
	return floori(points / (config(game, "tourism_divisor_per_major") * major_count(game)))


static func foreign_tourists(game: Game, pid: int) -> int:
	var total := 0
	for other in game.state.players:
		if other.id != pid and other.alive and not other.is_barbarian:
			total += visiting_tourists(game, pid, other.id)
	return total


static func tourism_per_turn(game: Game, pid: int) -> float:
	var amount := 0.0
	var player := game.state.player(pid)
	for city in game.state.cities_of(pid):
		amount += work_tourism(game, city)
		amount += WonderRules.tourism(game, city)
		amount += ParkRules.tourism(game, city)
		for tile in game.state.map.grid.tiles_in_radius(city.tile, 3):
			if game.state.map.owner_city[tile] == city.id and game.state.map.improvement[tile] == "SEASIDE_RESORT" \
					and game.state.map.pillaged[tile] == 0:
				amount += appeal(game, tile) * float(game.data.culture_content.get("resort_tourism_per_appeal", 1))
		for religion in game.state.religions.values():
			if int(religion.get("holy_city", -1)) == city.id:
				amount += config(game, "holy_city_tourism")
		if player.has_civic("CONSERVATION"):
			for building in city.buildings:
				if game.data.buildings.get(building, {}).has("wall_hp"):
					amount += config(game, "wall_tourism")
					break
	return amount * (1.0 + GovernmentRules.sum_effect(game, pid, "tourism_bonus"))


static func _has_route(game: Game, a: int, b: int) -> bool:
	for player_id in [a, b]:
		for unit in game.state.units_of(player_id):
			if unit.trade_route.is_empty():
				continue
			var destination := game.state.city(int(unit.trade_route.get("destination", -1)))
			if destination != null and destination.owner == (b if player_id == a else a):
				return true
	return false


static func _main_religion(game: Game, pid: int) -> String:
	var counts := {}
	for city in game.state.cities_of(pid):
		var rid := ReligionRules.majority(game, city)
		if rid != "":
			counts[rid] = int(counts.get(rid, 0)) + 1
	var best := ""
	for rid in counts:
		if int(counts[rid]) > int(counts.get(best, 0)):
			best = str(rid)
	return best


static func pair_multiplier(game: Game, visitor: int, source: int) -> float:
	var result := 1.0
	var player := game.state.player(visitor)
	if _has_route(game, visitor, source):
		result += config(game, "trade_route_bonus")
	if TreatyRules.until(game, "passage", visitor, source) > game.state.turn or \
			TreatyRules.until(game, "alliance", visitor, source) > game.state.turn:
		result += config(game, "open_borders_bonus")
	result += TreatyRules.alliance_effect(game, visitor, source, "culture", "tourism_bonus")
	var own_religion := _main_religion(game, visitor)
	var other_religion := _main_religion(game, source)
	if own_religion != "" and other_religion != "" and own_religion != other_religion \
			and not player.has_civic("THE_ENLIGHTENMENT"):
		result -= config(game, "different_religion_penalty")
	var own_government: Dictionary = game.data.governments.get(player.government, {})
	var other_government: Dictionary = game.data.governments.get(game.state.player(source).government, {})
	if int(own_government.get("tier", 0)) >= 3 and int(other_government.get("tier", 0)) >= 3 \
			and player.government != game.state.player(source).government:
		result -= config(game, "different_tier3_government_penalty")
	if player.has_tech("COMPUTERS"):
		result += config(game, "computers_bonus")
	if player.has_civic("SOCIAL_MEDIA"):
		result += config(game, "social_media_bonus")
	return maxf(0.0, result)


static func process_round(game: Game) -> void:
	for player in game.state.players:
		if player.is_barbarian or not player.alive or game.state.cities_of(player.id).is_empty():
			continue
		var base := tourism_per_turn(game, player.id)
		if base <= 0.0:
			continue
		for other in game.state.players:
			if other.id == player.id or other.is_barbarian or not other.alive \
					or game.state.cities_of(other.id).is_empty() or not player.met.has(other.id):
				continue
			var key := str(other.id)
			player.tourism_points[key] = float(player.tourism_points.get(key, 0.0)) \
				+ base * pair_multiplier(game, player.id, other.id)
