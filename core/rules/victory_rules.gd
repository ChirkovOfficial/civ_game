class_name VictoryRules
extends RefCounted
## Победа за исходные столицы, распространение религии и по очкам (ГДД 20).


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


## Для каждой живой крупной державы: сколько её городов исповедует religion_id.
## Город без строгого большинства не засчитывается ни одной религии.
static func religion_progress(game: Game, religion_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for player in game.state.players:
		if player.is_barbarian or not player.alive:
			continue
		var cities := game.state.cities_of(player.id)
		var converted := 0
		for city in cities:
			if ReligionRules.majority(game, city) == religion_id:
				converted += 1
		rows.append({"player": player.id, "converted": converted, "total": cities.size(),
			"required": floori(cities.size() * 0.5) + 1})
	return rows


static func check_religion(game: Game, events: Array) -> void:
	if not game.state.result.is_empty():
		return
	var ids := game.state.religions.keys()
	ids.sort()
	for rid in ids:
		var founder := int(game.state.religions[rid].get("founder", -1))
		if founder < 0 or founder >= game.state.players.size() or not game.state.player(founder).alive:
			continue
		var progress := religion_progress(game, str(rid))
		if progress.size() < 2:
			continue
		var complete := true
		for row in progress:
			if int(row["total"]) == 0 or int(row["converted"]) < int(row["required"]):
				complete = false
				break
		if complete:
			_finish(game, "religion", [founder], events, {"religion": str(rid)})
			return


static func check_science(game: Game, events: Array) -> void:
	if not game.state.result.is_empty():
		return
	var required := int(game.data.science_setup.get("distance_required", 50))
	for player in game.state.players:
		if not player.alive or player.is_barbarian:
			continue
		var progress := ScienceRules.status(game, player.id)
		if bool(progress["launched"]) and int(progress["distance"]) >= required:
			_finish(game, "science", [player.id], events)
			return


static func check_culture(game: Game, events: Array) -> void:
	if not game.state.result.is_empty():
		return
	for player in game.state.players:
		if player.is_barbarian or not player.alive or game.state.cities_of(player.id).is_empty():
			continue
		var rivals := 0
		var visitors := CultureRules.foreign_tourists(game, player.id)
		var won := true
		for other in game.state.players:
			if other.id == player.id or other.is_barbarian or not other.alive:
				continue
			rivals += 1
			if game.state.cities_of(other.id).is_empty() or visitors <= CultureRules.domestic_tourists(game, other.id):
				won = false
				break
		if rivals > 0 and won:
			_finish(game, "culture", [player.id], events)
			return


static func check_finance(game: Game, pid: int, events: Array) -> void:
	if not game.state.result.is_empty():
		return
	if int(game.state.finance_data["streaks"].get(str(pid), 0)) >= FinanceRules.required_turns(game):
		_finish(game, "finance", [pid], events)


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


static func _finish(game: Game, kind: String, winners: Array[int], events: Array, details: Dictionary = {}) -> void:
	game.state.result = {"kind": kind, "winners": winners, "turn": game.state.turn}
	game.state.result.merge(details)
	var event := game.state.result.duplicate(true)
	event["type"] = "game_finished"
	events.append(event)
