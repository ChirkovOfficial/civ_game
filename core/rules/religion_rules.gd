class_name ReligionRules
extends RefCounted
## Религия хранит действительного основателя, давление в городах и выбранные верования.


static func cfg(game: Game, key: String, fallback: Variant = 0) -> Variant:
	return game.data.religion_setup.get(key, fallback)


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	var names := {}
	for option in data.religion_setup.get("names", []):
		var id: String = str(option.get("id", ""))
		if id == "" or str(option.get("name", "")) == "" or names.has(id):
			errors.append("Некорректное или повторное название религии: %s" % id)
		names[id] = true
	for kind in ["pantheons", "follower_beliefs", "founder_beliefs", "cult_beliefs", "enhancer_beliefs"]:
		var ids := {}
		for option in data.religion_setup.get(kind, []):
			var id: String = str(option.get("id", ""))
			if id == "" or ids.has(id):
				errors.append("Некорректное или повторное верование: %s" % id)
			ids[id] = true
			if option.has("yield") and not Yields.TYPES.has(option["yield"]):
				errors.append("Верование %s: неизвестный доход" % id)
			if kind == "pantheons":
				if option.has("improvement") and not data.improvements.has(option["improvement"]):
					errors.append("Пантеон %s: неизвестное улучшение" % id)
				if option.has("feature") and not data.features.has(option["feature"]):
					errors.append("Пантеон %s: неизвестная особенность клетки" % id)
				if not option.has("yield") or float(option.get("amount", 0)) <= 0.0:
					errors.append("Пантеон %s: нужен положительный доход" % id)
	if data.religion_setup.get("names", []).is_empty() or data.religion_setup.get("pantheons", []).is_empty() or data.religion_setup.get("follower_beliefs", []).is_empty() or data.religion_setup.get("founder_beliefs", []).is_empty() or data.religion_setup.get("cult_beliefs", []).is_empty() or data.religion_setup.get("enhancer_beliefs", []).is_empty():
		errors.append("Религия: нужны названия, пантеоны и все четыре вида верований")
	var max_civs := 0
	for size in data.setup.get("map_sizes", []):
		max_civs = maxi(max_civs, int(size.get("civs", 0)))
	if data.religion_setup.get("pantheons", []).size() < max_civs:
		errors.append("Религия: пантеонов меньше, чем держав на самой большой карте")
	return errors


static func holy_site(city: City, min_tier: int = 1) -> Dictionary:
	for d in city.districts:
		if d["type"] == "HOLY_SITE" and d["complete"] and int(d["tier"]) >= min_tier:
			return d
	return {}


static func prophet_limit(game: Game) -> int:
	var majors := 0
	for p in game.state.players:
		if not p.is_barbarian:
			majors += 1
	return majors / 2 + 1


static func name_options(game: Game) -> Array:
	var result := []
	for option in cfg(game, "names", []):
		if not game.state.religions.has(option["id"]):
			result.append(option)
	return result


static func belief(game: Game, kind: String, id: String) -> Dictionary:
	for option in cfg(game, kind, []):
		if option["id"] == id:
			return option
	return {}


static func pantheon_options(game: Game) -> Array:
	var taken := {}
	for player in game.state.players:
		if player.pantheon != "":
			taken[player.pantheon] = true
	var result := []
	for option in cfg(game, "pantheons", []):
		if not taken.has(option["id"]):
			result.append(option)
	return result


static func pantheon_error(game: Game, pid: int, id: String) -> String:
	if pid < 0 or pid >= game.state.players.size() or game.state.player(pid).is_barbarian:
		return "Пантеон доступен крупной державе"
	var player := game.state.player(pid)
	if player.pantheon != "":
		return "Пантеон уже выбран"
	if game.state.cities_of(pid).is_empty():
		return "Нужен основанный город"
	if player.faith < float(cfg(game, "pantheon_faith_cost")):
		return "Недостаточно веры для пантеона"
	if not pantheon_options(game).any(func(option): return option["id"] == id):
		return "Этот пантеон уже выбран или неизвестен"
	return ""


static func choose_pantheon(game: Game, pid: int, id: String, events: Array) -> String:
	var error := pantheon_error(game, pid, id)
	if error != "":
		return error
	game.state.player(pid).faith -= float(cfg(game, "pantheon_faith_cost"))
	game.state.player(pid).pantheon = id
	events.append({"type": "pantheon_founded", "player": pid, "pantheon": id})
	return ""


static func pantheon_tile_yields(game: Game, tile: int, player: Player) -> Dictionary:
	if player.pantheon == "":
		return {}
	var option := belief(game, "pantheons", player.pantheon)
	if option.is_empty():
		return {}
	if option.has("improvement") and game.state.map.improvement[tile] != option["improvement"]:
		return {}
	if option.has("feature") and game.state.map.feature[tile] != option["feature"]:
		return {}
	return {option["yield"]: float(option["amount"])}


static func pantheon_score(game: Game, pid: int, option: Dictionary) -> int:
	var score := 0
	for city in game.state.cities_of(pid):
		for tile in CityRules.owned_tiles(game, city):
			var useful := false
			if option.has("feature"):
				useful = game.state.map.feature[tile] == option["feature"]
			elif option.has("improvement"):
				var rid: String = game.state.map.resource[tile]
				useful = game.state.map.improvement[tile] == option["improvement"] or \
					(rid != "" and game.data.resources[rid].get("improvement", "") == option["improvement"])
			if useful:
				score += 3 if city.worked_tiles.has(tile) else 1
	return score


static func prophet_error(game: Game, pid: int, city: City) -> String:
	if city == null or city.owner != pid:
		return "Выберите свой город"
	if game.state.player(pid).religion_id != "":
		return "Держава уже основала религию"
	if game.state.player(pid).pantheon == "":
		return "Сначала выберите пантеон"
	if game.state.religions.size() >= prophet_limit(game):
		return "Предел религий в мире достигнут"
	if game.state.player(pid).prophet_points < float(cfg(game, "prophet_points")):
		return "Недостаточно очков Великого пророка"
	for unit in game.state.units_of(pid):
		if unit.type == "PROPHET":
			return "У державы уже есть Великий пророк"
	var site := holy_site(city)
	if site.is_empty():
		return "Нужно готовое Священное место"
	for unit in game.state.units_at(int(site["tile"])):
		if Movement.layer(game, unit.type) == "RELIGIOUS":
			return "Священное место занято религиозным юнитом"
	return ""


static func recruit_prophet(game: Game, pid: int, city: City, events: Array) -> String:
	var error := prophet_error(game, pid, city)
	if error != "":
		return error
	game.state.player(pid).prophet_points -= float(cfg(game, "prophet_points"))
	var unit := game.state.add_unit(pid, "PROPHET", int(holy_site(city)["tile"]))
	unit.moves_left = 0.0
	events.append({"type": "unit_created", "unit": unit.id, "player": pid})
	return ""


static func found_error(game: Game, unit: Unit, name_id: String, follower: String, founder: String,
		custom_name: String = "") -> String:
	if unit == null or unit.type != "PROPHET" or unit.owner != game.state.current_player:
		return "Нужен свой Великий пророк"
	if game.state.player(unit.owner).religion_id != "":
		return "Держава уже основала религию"
	if game.state.player(unit.owner).pantheon == "":
		return "Сначала выберите пантеон"
	if game.state.religions.size() >= prophet_limit(game):
		return "Предел религий в мире достигнут"
	var site := DistrictRules.at(game, unit.tile)
	if site.size() < 2 or site[0].owner != unit.owner or site[1]["type"] != "HOLY_SITE" or not site[1]["complete"]:
		return "Великий пророк должен находиться на своём Священном месте"
	var custom := custom_name.strip_edges()
	if custom != "":
		if custom.length() > 40:
			return "Название религии не должно быть длиннее 40 символов"
		for option in cfg(game, "names", []):
			if str(option["name"]).to_lower() == custom.to_lower():
				return "Это название уже есть в списке религий"
		for religion in game.state.religions.values():
			if str(religion["name"]).to_lower() == custom.to_lower():
				return "Название религии занято"
	elif not name_options(game).any(func(x): return x["id"] == name_id):
		return "Название религии занято или неизвестно"
	if belief(game, "follower_beliefs", follower).is_empty() or belief(game, "founder_beliefs", founder).is_empty():
		return "Выберите оба верования"
	return ""


static func found(game: Game, unit: Unit, name_id: String, follower: String, founder: String, events: Array,
		custom_name: String = "") -> String:
	var error := found_error(game, unit, name_id, follower, founder, custom_name)
	if error != "":
		return error
	var city: City = DistrictRules.at(game, unit.tile)[0]
	var name := custom_name.strip_edges()
	if name != "":
		name_id = "CUSTOM_%d" % unit.owner
	else:
		for option in cfg(game, "names", []):
			if option["id"] == name_id:
				name = option["name"]
				break
	game.state.religions[name_id] = {"name": name, "founder": unit.owner, "holy_city": city.id,
		"follower_belief": follower, "founder_belief": founder,
		"cult_belief": "", "enhancer_belief": ""}
	game.state.player(unit.owner).religion_id = name_id
	city.religion_pressure[name_id] = float(cfg(game, "holy_city_pressure"))
	game.state.remove_unit(unit.id)
	events.append({"type": "religion_founded", "player": city.owner, "city": city.id, "religion": name_id})
	return ""


static func on_city_founded(game: Game, city: City) -> void:
	var rid := game.state.player(city.owner).religion_id
	if rid != "":
		city.religion_pressure[rid] = float(cfg(game, "new_city_pressure"))


static func followers(game: Game, city: City, rid: String) -> float:
	var total := 100.0
	for amount in city.religion_pressure.values():
		total += maxf(0.0, float(amount))
	return city.population * maxf(0.0, float(city.religion_pressure.get(rid, 0.0))) / total


static func majority(game: Game, city: City) -> String:
	for rid in city.religion_pressure:
		if followers(game, city, str(rid)) > city.population * 0.5:
			return str(rid)
	return ""


static func city_follower_yields(game: Game, city: City) -> Dictionary:
	var religion: Dictionary = game.state.religions.get(majority(game, city), {})
	if religion.is_empty():
		return {}
	var option := belief(game, "follower_beliefs", religion["follower_belief"])
	var tiers := 0
	var advanced := false
	for site in DistrictRules.of_type(city, "HOLY_SITE", true):
		tiers += int(site["tier"])
		advanced = advanced or int(site["tier"]) >= 2
	var yields := {}
	if option.has("yield"):
		yields[option["yield"]] = tiers * float(option["per_holy_site_tier"])
	var cult := belief(game, "cult_beliefs", str(religion.get("cult_belief", "")))
	if advanced and cult.has("yield"):
		yields[cult["yield"]] = float(yields.get(cult["yield"], 0.0)) + float(cult["amount"])
	return yields


static func city_amenities(game: Game, city: City) -> int:
	var religion: Dictionary = game.state.religions.get(majority(game, city), {})
	if religion.is_empty() or holy_site(city).is_empty():
		return 0
	var result := int(belief(game, "follower_beliefs", religion["follower_belief"]).get("amenity_with_holy_site", 0))
	var cult := belief(game, "cult_beliefs", str(religion.get("cult_belief", "")))
	for site in DistrictRules.of_type(city, "HOLY_SITE", true):
		if int(site["tier"]) >= 2:
			result += int(cult.get("amenities", 0))
			break
	return result


static func enhancer(game: Game, rid: String) -> Dictionary:
	var religion: Dictionary = game.state.religions.get(rid, {})
	return belief(game, "enhancer_beliefs", str(religion.get("enhancer_belief", "")))


static func faith_cost(game: Game, pid: int, unit_type: String) -> int:
	var base := float(cfg(game, "apostle_faith_cost")) if unit_type == "APOSTLE" else float(cfg(game, "missionary_faith_cost"))
	return ceili(base * float(enhancer(game, game.state.player(pid).religion_id).get("faith_cost_multiplier", 1.0)))


static func founder_yields(game: Game, pid: int) -> Dictionary:
	var rid := game.state.player(pid).religion_id
	if rid == "":
		return {}
	var religion: Dictionary = game.state.religions.get(rid, {})
	if religion.is_empty():
		return {}
	var option := belief(game, "founder_beliefs", religion["founder_belief"])
	var people := 0.0
	var cities := 0
	for city in game.state.cities.values():
		if city.owner == pid:
			continue
		people += followers(game, city, rid)
		if majority(game, city) == rid:
			cities += 1
	var value := 0.0
	if option.has("foreign_followers_per_point"):
		value = floorf(people / float(option["foreign_followers_per_point"]))
	elif option.has("foreign_majority_cities_per_point"):
		value = floorf(float(cities) / float(option["foreign_majority_cities_per_point"]))
	return {option["yield"]: minf(value, float(option["cap"]))} if not option.is_empty() else {}


static func missionary_error(game: Game, pid: int, city: City) -> String:
	if city == null or city.owner != pid:
		return "Выберите свой город"
	var rid := game.state.player(pid).religion_id
	if rid == "" or majority(game, city) != rid:
		return "Город должен исповедовать основанную вами религию"
	var site := holy_site(city)
	if site.is_empty():
		return "Нужно готовое Священное место"
	if game.state.player(pid).faith < faith_cost(game, pid, "MISSIONARY"):
		return "Недостаточно веры"
	for unit in game.state.units_at(int(site["tile"])):
		if Movement.layer(game, unit.type) == "RELIGIOUS":
			return "Священное место занято религиозным юнитом"
	return ""


static func recruit_missionary(game: Game, pid: int, city: City, events: Array) -> String:
	var error := missionary_error(game, pid, city)
	if error != "":
		return error
	game.state.player(pid).faith -= faith_cost(game, pid, "MISSIONARY")
	var unit := game.state.add_unit(pid, "MISSIONARY", int(holy_site(city)["tile"]))
	unit.charges = 3
	unit.moves_left = 0.0
	events.append({"type": "unit_created", "unit": unit.id, "player": pid})
	return ""


static func apostle_error(game: Game, pid: int, city: City) -> String:
	if city == null or city.owner != pid:
		return "Выберите свой город"
	var rid := game.state.player(pid).religion_id
	if rid == "" or majority(game, city) != rid:
		return "Город должен исповедовать основанную вами религию"
	var site := holy_site(city, 2)
	if site.is_empty():
		return "Нужно готовое Священное место II"
	if game.state.player(pid).faith < faith_cost(game, pid, "APOSTLE"):
		return "Недостаточно веры"
	for unit in game.state.units_at(int(site["tile"])):
		if Movement.layer(game, unit.type) == "RELIGIOUS":
			return "Священное место занято религиозным юнитом"
	return ""


static func recruit_apostle(game: Game, pid: int, city: City, events: Array) -> String:
	var error := apostle_error(game, pid, city)
	if error != "":
		return error
	game.state.player(pid).faith -= faith_cost(game, pid, "APOSTLE")
	var unit := game.state.add_unit(pid, "APOSTLE", int(holy_site(city, 2)["tile"]))
	unit.charges = int(cfg(game, "apostle_charges"))
	unit.moves_left = 0.0
	events.append({"type": "unit_created", "unit": unit.id, "player": pid})
	return ""


static func proclaim_error(game: Game, unit: Unit, kind: String, id: String) -> String:
	if unit == null or unit.type != "APOSTLE" or unit.owner != game.state.current_player:
		return "Нужен свой апостол"
	if unit.charges < int(cfg(game, "apostle_charges")):
		return "Для провозглашения нужны все заряды апостола"
	var site := DistrictRules.at(game, unit.tile)
	if site.size() < 2 or site[0].owner != unit.owner or site[1]["type"] != "HOLY_SITE" or not site[1]["complete"] or int(site[1]["tier"]) < 2:
		return "Апостол должен находиться на своём Священном месте II"
	var rid := game.state.player(unit.owner).religion_id
	if rid == "":
		return "Держава не основала религию"
	if kind not in ["cult", "enhancer"]:
		return "Неизвестный вид верования"
	var field := kind + "_belief"
	if str(game.state.religions[rid].get(field, "")) != "":
		return "Это верование уже провозглашено"
	if belief(game, kind + "_beliefs", id).is_empty():
		return "Неизвестное верование"
	return ""


static func proclaim(game: Game, unit: Unit, kind: String, id: String, events: Array) -> String:
	var error := proclaim_error(game, unit, kind, id)
	if error != "":
		return error
	var rid := game.state.player(unit.owner).religion_id
	game.state.religions[rid][kind + "_belief"] = id
	game.state.remove_unit(unit.id)
	events.append({"type": "religion_enhanced", "player": game.state.current_player,
		"religion": rid, "kind": kind, "belief": id})
	return ""


static func spread_error(game: Game, unit: Unit) -> String:
	if unit == null or unit.type not in ["MISSIONARY", "APOSTLE"] or unit.owner != game.state.current_player:
		return "Нужен свой миссионер или апостол"
	if unit.charges <= 0 or unit.moves_left <= 0.0:
		return "Религиозный юнит уже действовал в этот ход"
	if game.state.player(unit.owner).religion_id == "":
		return "Держава не основала религию"
	var city := game.state.city_at(unit.tile)
	if city == null:
		return "Религиозный юнит должен находиться в центре города"
	if game.state.at_war(unit.owner, city.owner):
		return "Во время войны распространение здесь невозможно"
	return ""


static func spread(game: Game, unit: Unit, events: Array) -> String:
	var error := spread_error(game, unit)
	if error != "":
		return error
	var city := game.state.city_at(unit.tile)
	var rid := game.state.player(unit.owner).religion_id
	for other in city.religion_pressure.keys():
		if other != rid:
			city.religion_pressure[other] = float(city.religion_pressure[other]) * float(cfg(game, "missionary_other_pressure_factor"))
	var base := float(cfg(game, "apostle_pressure")) if unit.type == "APOSTLE" else float(cfg(game, "missionary_pressure"))
	city.religion_pressure[rid] = float(city.religion_pressure.get(rid, 0.0)) + base * float(enhancer(game, rid).get("spread_multiplier", 1.0))
	unit.charges -= 1
	unit.moves_left = 0.0
	unit.acted = true
	events.append({"type": "religion_spread", "player": unit.owner, "city": city.id, "religion": rid})
	if unit.charges <= 0:
		game.state.remove_unit(unit.id)
		events.append({"type": "unit_killed", "unit": unit.id, "owner": unit.owner, "reason": "spent"})
	return ""


static func process_turn(game: Game, pid: int) -> void:
	if game.state.player(pid).religion_id != "":
		return
	for city in game.state.cities_of(pid):
		for site in DistrictRules.of_type(city, "HOLY_SITE", true):
			game.state.player(pid).prophet_points += int(site["tier"]) * float(cfg(game, "prophet_points_per_holy_site_tier"))


static func process_round(game: Game) -> void:
	var increments := {}
	for source in game.state.cities.values():
		var rid := majority(game, source)
		if rid == "":
			continue
		var extra := enhancer(game, rid)
		var power := float(cfg(game, "holy_city_natural_pressure")) if int(game.state.religions.get(rid, {}).get("holy_city", -1)) == source.id else float(cfg(game, "natural_pressure"))
		power += float(extra.get("natural_pressure_bonus", 0.0))
		for tile in game.state.map.grid.tiles_in_radius(source.tile, int(cfg(game, "pressure_radius")) + int(extra.get("radius_bonus", 0))):
			var target := game.state.city_at(tile)
			if target != null:
				var key := "%d:%s" % [target.id, rid]
				increments[key] = float(increments.get(key, 0.0)) + power
	for key in increments:
		var parts: PackedStringArray = str(key).split(":")
		var city: City = game.state.city(int(parts[0]))
		city.religion_pressure[parts[1]] = float(city.religion_pressure.get(parts[1], 0.0)) + float(increments[key])


static func religious_dependency_target(game: Game, dependent: int, provider: int, previous: Dictionary) -> Dictionary:
	var rid := game.state.player(provider).religion_id
	var cities := game.state.cities_of(dependent)
	var majority_count := 0
	var people := 0
	var believers := 0.0
	for city in cities:
		people += city.population
		if rid != "":
			believers += followers(game, city, rid)
			if majority(game, city) == rid:
				majority_count += 1
	var qualifying := not cities.is_empty() and majority_count * 2 > cities.size()
	var streak := int(previous.get("religion_streak", 0))
	streak = mini(3, maxi(0, streak) + 1) if qualifying else maxi(-3, mini(0, streak) - 1)
	var active := bool(previous.get("religion_active", false))
	if streak >= int(cfg(game, "religion_majority_rounds")):
		active = true
	elif streak <= -int(cfg(game, "religion_majority_rounds")):
		active = false
	var target := float(cfg(game, "religion_dependency_cap")) * believers / people if active and people > 0 else 0.0
	return {"target": target, "active": active, "streak": streak}


static func influence_source(game: Game, pid: int, initial_majors: int) -> float:
	var rid := game.state.player(pid).religion_id
	if rid == "":
		return 0.0
	var foreign_people := 0
	var believers := 0.0
	for city in game.state.cities.values():
		if city.owner == pid or game.state.player(city.owner).is_barbarian or not game.state.player(city.owner).alive:
			continue
		foreign_people += city.population
		believers += followers(game, city, rid)
	if foreign_people == 0:
		return 0.0
	var share := minf(1.0, (believers / foreign_people) / float(cfg(game, "religion_influence_full_share")))
	var reach := minf(1.0, believers / (float(cfg(game, "religion_influence_reach_population")) * maxi(1, initial_majors - 1)))
	return float(cfg(game, "religion_influence_cap")) * share * reach
