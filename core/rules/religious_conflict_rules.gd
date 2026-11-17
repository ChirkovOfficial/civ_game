class_name ReligiousConflictRules
extends RefCounted
## Доказательства активной проповеди, протесты и обязательства. Пассивное давление
## религии не попадает в этот реестр. Записи эпизодов и нарушений не изменяются.


static func record_spread(game: Game, offender: int, city: City, events: Array) -> void:
	var data: Dictionary = game.state.religious_conflicts
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	var incident := {"id": id, "offender": offender, "victim": city.owner,
		"city": city.id, "round": game.state.turn, "kind": "active_spread"}
	data["incidents"][str(id)] = incident
	events.append({"type": "religious_incident", "id": id, "offender": offender,
		"victim": city.owner, "city": city.id})
	var pair := _pair(city.owner, offender)
	var promise: Dictionary = data["promises"].get(pair, {})
	if not promise.is_empty() and game.state.turn <= int(promise["until_round"]):
		var breach_id: int = data["next_id"]
		data["next_id"] = breach_id + 1
		data["breaches"][str(breach_id)] = {"id": breach_id, "incident": id,
			"request": int(promise["request"]), "offender": offender, "victim": city.owner,
			"round": game.state.turn}
		events.append({"type": "religious_promise_breached", "id": breach_id,
			"offender": offender, "victim": city.owner})
		CongressRules.note_religious_evidence(game, city.owner, offender, breach_id, "promise_breached", events)
	CongressRules.note_religious_spread(game, city.owner, offender, events)


static func _pair(victim: int, offender: int) -> String:
	return "%d,%d" % [victim, offender]


static func protest_error(game: Game, victim: int, incident_id: int) -> String:
	var data: Dictionary = game.state.religious_conflicts
	var incident: Dictionary = data["incidents"].get(str(incident_id), {})
	if incident.is_empty() or int(incident["victim"]) != victim:
		return "Нет подтверждённой активной проповеди на вашей территории"
	if game.state.turn - int(incident["round"]) > 10:
		return "С момента проповеди прошло больше 10 кругов"
	var pair := _pair(victim, int(incident["offender"]))
	if data["promises"].has(pair):
		return "Обещание прекратить проповедь уже действует"
	for request in data["requests"].values():
		if int(request["incident"]) == incident_id:
			return "По этому эпизоду протест уже заявлен"
		if str(request["status"]) == "pending" and int(request["victim"]) == victim and int(request["offender"]) == int(incident["offender"]):
			return "Ответ на предыдущий протест ещё не получен"
	return ""


static func protest(game: Game, victim: int, incident_id: int, events: Array) -> String:
	var error := protest_error(game, victim, incident_id)
	if error != "":
		return error
	var data: Dictionary = game.state.religious_conflicts
	var incident: Dictionary = data["incidents"][str(incident_id)]
	var offender: int = incident["offender"]
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	# У адресата есть два собственных хода для ответа.
	var deadline := game.state.turn + (1 if offender > victim else 2)
	data["requests"][str(id)] = {"id": id, "incident": incident_id,
		"victim": victim, "offender": offender, "round": game.state.turn,
		"deadline_round": deadline, "status": "pending", "resolved_round": -1}
	events.append({"type": "religious_protest", "id": id, "victim": victim, "offender": offender})
	return ""


static func response_error(game: Game, offender: int, request_id: int) -> String:
	var request: Dictionary = game.state.religious_conflicts["requests"].get(str(request_id), {})
	if request.is_empty() or int(request["offender"]) != offender or str(request["status"]) != "pending":
		return "Нет ожидающего ответа на религиозный протест"
	return ""


static func respond(game: Game, offender: int, request_id: int, accept: bool, events: Array) -> String:
	var error := response_error(game, offender, request_id)
	if error != "":
		return error
	var data: Dictionary = game.state.religious_conflicts
	var request: Dictionary = data["requests"][str(request_id)]
	request["status"] = "accepted" if accept else "refused"
	request["resolved_round"] = game.state.turn
	if accept:
		data["promises"][_pair(int(request["victim"]), offender)] = {"request": request_id,
			"victim": int(request["victim"]), "offender": offender,
			"until_round": game.state.turn + 9}
	else:
		CongressRules.note_religious_evidence(game, int(request["victim"]), offender,
			request_id, "protest_refused", events)
	events.append({"type": "religious_protest_answered", "id": request_id,
		"offender": offender, "victim": int(request["victim"]), "accept": accept})
	return ""


static func end_turn(game: Game, pid: int, events: Array) -> void:
	var requests: Dictionary = game.state.religious_conflicts["requests"]
	for key in requests:
		var request: Dictionary = requests[key]
		if str(request["status"]) == "pending" and int(request["offender"]) == pid and game.state.turn >= int(request["deadline_round"]):
			request["status"] = "refused"
			request["resolved_round"] = game.state.turn
			events.append({"type": "religious_protest_answered", "id": int(request["id"]),
				"offender": pid, "victim": int(request["victim"]), "accept": false})
			CongressRules.note_religious_evidence(game, int(request["victim"]), pid,
				int(request["id"]), "protest_refused", events)


static func close_round(game: Game) -> void:
	var promises: Dictionary = game.state.religious_conflicts["promises"]
	for key in promises.keys():
		if game.state.turn >= int(promises[key]["until_round"]):
			promises.erase(key)
