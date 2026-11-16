class_name VictoryRules
extends RefCounted
## Победа за исходные столицы и по очкам (ГДД 18, 20).


static func turn_limit(game: Game) -> int:
	if game.state.settings.has("turn_limit"):
		return int(game.state.settings["turn_limit"])
	var rules: Dictionary = game.data.setup["victory"]
	return maxi(1, roundi(float(rules["standard_turn_limit"]) * CityRules.speed_mult(game)))


static func standings(game: Game) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var weights: Dictionary = game.data.setup["victory"]["score_weights"]
	for p in game.state.players:
		if p.is_barbarian:
			continue
		var cities := game.state.cities_of(p.id)
		var counts := {"cities": cities.size(), "population": 0, "districts": 0, "buildings": 0,
			"technologies": p.known_techs.size(), "civics": p.known_civics.size()}
		for city in cities:
			counts["population"] += city.population
			counts["buildings"] += city.buildings.size()
			for district in city.districts:
				if district["complete"]:
					counts["districts"] += 1
		var score := 0
		for key in counts:
			score += int(counts[key]) * int(weights[key])
		rows.append({"player": p.id, "alive": p.alive, "score": score, "counts": counts})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["alive"] != b["alive"]:
			return a["alive"]
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["player"] < b["player"])
	return rows


static func capital_progress(game: Game, pid: int) -> Vector2i:
	var controlled := 0
	var required := 0
	for p in game.state.players:
		if p.is_barbarian:
			continue
		var id := int(game.state.original_capitals.get(str(p.id), -1))
		# Держава, выбывшая до основания первого города, не оставляет столицу.
		if id < 0 and not p.alive:
			continue
		required += 1
		var city := game.state.city(id)
		if city != null and city.owner == pid:
			controlled += 1
	return Vector2i(controlled, required)


static func check_capitals(game: Game, events: Array) -> void:
	if not game.state.result.is_empty():
		return
	var majors := 0
	for p in game.state.players:
		if not p.is_barbarian:
			majors += 1
	if majors < 2:
		return
	for p in game.state.players:
		if not p.alive or p.is_barbarian:
			continue
		var progress := capital_progress(game, p.id)
		if progress.x > 0 and progress.x == progress.y:
			_finish(game, "domination", [p.id], events)
			return


static func check_turn_limit(game: Game, events: Array) -> void:
	if not game.state.result.is_empty() or game.state.turn < turn_limit(game):
		return
	var winners: Array[int] = []
	var best := -1
	for row in standings(game):
		if not row["alive"] or int(row["score"]) < best:
			break
		best = int(row["score"])
		winners.append(int(row["player"]))
	_finish(game, "score", winners, events)


static func _finish(game: Game, kind: String, winners: Array[int], events: Array) -> void:
	game.state.result = {"kind": kind, "winners": winners, "turn": game.state.turn}
	var event := game.state.result.duplicate(true)
	event["type"] = "game_finished"
	events.append(event)
