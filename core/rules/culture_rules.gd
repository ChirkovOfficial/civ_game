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


static func commission_error(game: Game, city: City) -> String:
	if not game.state.player(city.owner).has_civic("HUMANISM"):
		return "Нужен институт «Гуманизм»"
	if work_slots(game, city) <= city.great_works:
		return "Нужна свободная ячейка шедевра в работающей Театральной площади II"
	return ""


static func complete_commission(game: Game, city: City, events: Array) -> void:
	city.great_works += 1
	events.append({"type": "great_work_created", "player": city.owner, "city": city.id,
		"count": city.great_works})


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
		amount += active_works(game, city) * config(game, "work_tourism")
		for religion in game.state.religions.values():
			if int(religion.get("holy_city", -1)) == city.id:
				amount += config(game, "holy_city_tourism")
		if player.has_civic("CONSERVATION"):
			for building in city.buildings:
				if game.data.buildings.get(building, {}).has("wall_hp"):
					amount += config(game, "wall_tourism")
					break
	return amount


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
