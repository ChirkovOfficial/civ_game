class_name GreatPeopleRules
extends RefCounted
## Очки от действующих районов и разовое применение великих людей в городе.


static func cfg(game: Game, key: String) -> float:
	return float(game.data.culture_content.get(key, 0.0))


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["great_person_base_cost", "great_person_cost_step", "great_person_district_points",
			"great_person_building_points", "great_person_tier_points", "great_person_patronage_gold_per_point"]:
		if float(data.culture_content.get(key, 0)) <= 0.0:
			errors.append("Великие люди: неверное значение %s" % key)
	for id in data.great_person_ids:
		var person: Dictionary = data.great_people[id]
		if not data.districts.has(person.get("district", "")):
			errors.append("Великий человек %s: неизвестный район" % id)
		if person.get("effect", "") not in ["science", "production", "gold", "work"]:
			errors.append("Великий человек %s: неизвестный эффект" % id)
		if person.get("effect", "") == "work" and not data.culture_content.get("works", {}).has(person.get("work", "")):
			errors.append("Великий человек %s: неизвестный тип шедевра" % id)
	return errors


static func cost(game: Game, kind: String) -> float:
	var count := int(game.state.culture_data["great_people_recruited"].get(kind, 0))
	return cfg(game, "great_person_base_cost") + count * cfg(game, "great_person_cost_step")


static func points_per_turn(game: Game, pid: int) -> Dictionary:
	var result := {}
	for kind in game.data.great_person_ids:
		result[kind] = 0.0
	for city in game.state.cities_of(pid):
		for district in city.districts:
			if not bool(district["complete"]) or game.state.map.pillaged[int(district["tile"])] != 0:
				continue
			for kind in game.data.great_person_ids:
				if district["type"] != game.data.great_people[kind]["district"]:
					continue
				var points := cfg(game, "great_person_district_points")
				points += maxi(0, int(district["tier"]) - 1) * cfg(game, "great_person_tier_points")
				points += district["buildings"].size() * cfg(game, "great_person_building_points")
				result[kind] = float(result[kind]) + points
	return result


static func process_turn(game: Game, pid: int) -> void:
	var player := game.state.player(pid)
	var income := points_per_turn(game, pid)
	for kind in income:
		player.great_person_points[kind] = float(player.great_person_points.get(kind, 0.0)) \
			+ float(income[kind])


static func recruit_error(game: Game, pid: int, city: City, kind: String, patronage: bool = false) -> String:
	if not game.data.great_people.has(kind):
		return "Неизвестный великий человек"
	if city == null or city.owner != pid:
		return "Нужен свой город"
	var person: Dictionary = game.data.great_people[kind]
	if person["effect"] == "work" and CultureRules.work_slots(game, city) <= city.great_works:
		return "В этом городе нет свободной ячейки шедевра"
	var player := game.state.player(pid)
	var missing := maxf(0.0, cost(game, kind) - float(player.great_person_points.get(kind, 0.0)))
	if missing > 0.0 and not patronage:
		return "Недостаточно очков великого человека"
	if patronage and player.treasury < ceilf(missing * cfg(game, "great_person_patronage_gold_per_point")):
		return "Недостаточно золота для покровительства"
	return ""


static func recruit(game: Game, pid: int, city: City, kind: String, patronage: bool, events: Array) -> String:
	var err := recruit_error(game, pid, city, kind, patronage)
	if err != "":
		return err
	var player := game.state.player(pid)
	var price := cost(game, kind)
	var current := float(player.great_person_points.get(kind, 0.0))
	var gold := ceili(maxf(0.0, price - current) * cfg(game, "great_person_patronage_gold_per_point")) if patronage else 0
	player.treasury -= gold
	player.great_person_points[kind] = maxf(0.0, current - price)
	game.state.culture_data["great_people_recruited"][kind] = int(game.state.culture_data["great_people_recruited"].get(kind, 0)) + 1
	var person: Dictionary = game.data.great_people[kind]
	match person["effect"]:
		"science":
			EmpireRules.add_research(game, pid, "tech", float(person["amount"]) * CityRules.speed_mult(game), events)
		"production":
			city.overflow += float(person["amount"]) * CityRules.speed_mult(game)
		"gold":
			player.treasury += float(person["amount"]) * CityRules.speed_mult(game)
		"work":
			while city.great_work_types.size() < city.great_works:
				city.great_work_types.append("")
			city.great_works += 1
			city.great_work_types.append(str(person["work"]))
			events.append({"type": "great_work_created", "player": pid, "city": city.id,
				"work": person["work"], "count": city.great_works})
	events.append({"type": "great_person_recruited", "player": pid, "city": city.id,
		"kind": kind, "gold": gold})
	return ""
