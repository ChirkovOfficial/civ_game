class_name ScienceRules
extends RefCounted
## Городские космические проекты и полёт экспедиции.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.science_projects.size() != data.science_project_ids.size() or data.science_projects.is_empty():
		errors.append("Научные проекты: пустой список или повторяющиеся id")
	if int(data.science_setup.get("distance_required", 0)) <= 0:
		errors.append("Научные проекты: нужна положительная дальность экспедиции")
	for id in data.science_project_ids:
		var project: Dictionary = data.science_projects[id]
		if str(project.get("name", "")) == "" or float(project.get("cost", 0)) <= 0.0:
			errors.append("Научный проект %s: нужны название и цена" % id)
		if not data.techs.has(str(project.get("tech", ""))):
			errors.append("Научный проект %s: неизвестная технология" % id)
		if project.has("requires") and not data.science_projects.has(str(project["requires"])):
			errors.append("Научный проект %s: неизвестная предпосылка" % id)
		for resource in project.get("resource", {}):
			if not data.resources.has(resource) or float(project["resource"][resource]) <= 0.0:
				errors.append("Научный проект %s: неверный ресурс %s" % [id, resource])
	return errors


static func status(game: Game, pid: int) -> Dictionary:
	return game.state.science_data.get(str(pid), {"completed": {}, "launched": false,
		"distance": 0, "speed": 1, "lasers": 0, "laser_sites": {}})


static func _ensure(game: Game, pid: int) -> Dictionary:
	var key := str(pid)
	if not game.state.science_data.has(key):
		game.state.science_data[key] = status(game, pid)
	return game.state.science_data[key]


static func has_spaceport(game: Game, city: City) -> bool:
	for district in DistrictRules.of_type(city, "SPACEPORT", true):
		if game.state.map.pillaged[int(district["tile"])] == 0:
			return true
	return false


static func project_error(game: Game, city: City, id: String) -> String:
	var project: Dictionary = game.data.science_projects.get(id, {})
	if project.is_empty():
		return "Неизвестный космический проект"
	if not game.state.player(city.owner).has_tech(str(project["tech"])):
		return "Нужна технология «%s»" % game.data.techs[project["tech"]]["name"]
	if not has_spaceport(game, city):
		return "Нужен работающий Космопорт в этом городе"
	var progress := status(game, city.owner)
	var completed: Dictionary = progress["completed"]
	if not bool(project.get("repeatable", false)) and completed.has(id):
		return "Этот проект уже завершён державой"
	if project.has("requires") and not completed.has(str(project["requires"])):
		return "Сначала завершите предыдущий космический проект"
	if bool(project.get("repeatable", false)) and not bool(progress["launched"]):
		return "Сначала отправьте экспедицию к экзопланете"
	if bool(project.get("power_required", false)) and EnergyRules.spare_for_project(game, city) \
			< int(game.data.energy_setup["laser_power_demand"]):
		return "Нужно %d свободной энергии в городе" % int(game.data.energy_setup["laser_power_demand"])
	for resource in project.get("resource", {}):
		if float(game.state.player(city.owner).stockpile.get(resource, 0.0)) < float(project["resource"][resource]):
			return "Нужно %d ед. ресурса «%s»" % [int(project["resource"][resource]),
				game.data.resources[resource]["name"]]
	if not bool(project.get("repeatable", false)):
		for other in game.state.cities_of(city.owner):
			if other.id != city.id and not other.queue.is_empty() \
					and other.queue[0].get("kind", "") == "project" and other.queue[0].get("id", "") == id:
				return "Этот проект уже строится в другом городе"
	return ""


static func complete(game: Game, city: City, id: String, events: Array) -> void:
	var project: Dictionary = game.data.science_projects[id]
	var pid := city.owner
	var progress := _ensure(game, pid)
	for resource in project.get("resource", {}):
		var amount := float(project["resource"][resource])
		game.state.player(pid).stockpile[resource] = float(game.state.player(pid).stockpile.get(resource, 0.0)) - amount
		DiplomacyRules.record_spend(game, pid, resource, amount)
	if not bool(project.get("repeatable", false)):
		progress["completed"][id] = true
	var culture := 0.0
	match str(project.get("effect", "")):
		"reveal_map":
			game.state.player(pid).revealed.fill(Player.FOG_REVEALED)
			events.append({"type": "fog_changed", "player": pid})
		"moon_culture":
			culture = float(EmpireRules.summary(game, pid)["yields"].get("science", 0.0)) \
				* float(game.data.science_setup.get("moon_culture_science_multiplier", 10))
			EmpireRules.add_research(game, pid, "civic", culture, events)
		"launch":
			progress["launched"] = true
			progress["distance"] = 0
			progress["speed"] = 1
		"accelerate":
			progress["lasers"] = int(progress["lasers"]) + 1
			var sites: Dictionary = progress.get("laser_sites", {})
			sites[str(city.id)] = int(sites.get(str(city.id), 0)) + 1
			progress["laser_sites"] = sites
	events.append({"type": "science_project_completed", "player": pid, "city": city.id,
		"project": id, "culture": culture})


static func process_round(game: Game, events: Array) -> void:
	var required := int(game.data.science_setup["distance_required"])
	for player in game.state.players:
		if player.is_barbarian or not player.alive:
			continue
		var progress: Dictionary = game.state.science_data.get(str(player.id), {})
		if progress.is_empty() or not bool(progress.get("launched", false)) or int(progress["distance"]) >= required:
			continue
		if progress.has("laser_sites"):
			var powered_lasers := 0
			for city in game.state.cities_of(player.id):
				powered_lasers += int(EnergyRules.report(game, city)["lasers_powered"])
			progress["speed"] = 1 + powered_lasers
		progress["distance"] = mini(required, int(progress["distance"]) + int(progress["speed"]))
		if int(progress["distance"]) >= required:
			events.append({"type": "science_expedition_arrived", "player": player.id})
