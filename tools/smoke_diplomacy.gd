extends SceneTree
## Быстрая проверка окна дипломатии в настоящей сцене.

var main: Node3D
var frames := 0

func _initialize() -> void:
	main = load("res://view/main.tscn").instantiate()
	main.fixed_seed = 77
	root.add_child(main)

func _process(_delta: float) -> bool:
	frames += 1
	if frames != 3:
		return false
	var game: Game = main.game
	game.state.player(0).met[1] = true
	game.state.player(1).met[0] = true
	game.state.player(0).known_techs["ANIMAL_HUSBANDRY"] = true
	main.hud.open_diplomacy()
	main.hud.open_supply_offer(1, true)
	var box: VBoxContainer = main.hud.get("_research_box")
	var chooser: OptionButton = box.find_children("*", "OptionButton", true, false)[0]
	var marble := -1
	for index in chooser.item_count:
		if chooser.get_item_text(index).begins_with("Мрамор"):
			marble = index
			break
	if marble < 0:
		printerr("Мрамор не появился в окне покупки")
		quit(1)
		return true
	chooser.select(marble)
	chooser.item_selected.emit(marble)
	var submit: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "Отправить предложение":
			submit = node
	if submit == null:
		printerr("В форме покупки нет отправки предложения")
		quit(1)
		return true
	submit.pressed.emit()
	if game.state.diplomacy["offers"].size() != 1:
		printerr("Предложение покупки не создано")
		quit(1)
		return true
	var offer: Dictionary = game.state.diplomacy["offers"].values()[0]
	if offer["resource"] != "MARBLE" or int(offer["per_turn"]) != 1:
		printerr("Форма не отправила предложение доступа к одной копии мрамора")
		quit(1)
		return true
	main.hud.open_supply_offer(1, false)
	main.hud.open_diplomacy()
	if not main.hud.is_modal_open() or box.get_child_count() < 5:
		printerr("Окно дипломатии не открылось")
		quit(1)
		return true
	var friend_offer: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "Дружба":
			friend_offer = node
			break
	if friend_offer == null or friend_offer.disabled:
		printerr("В окне дипломатии нет доступного предложения дружбы")
		quit(1)
		return true
	friend_offer.pressed.emit()
	main.act({"type": "end_turn", "force": true})
	main.hud.open_diplomacy()
	if TreatyRules.until(game, "friendship", 0, 1) <= game.state.turn:
		printerr("Предложение дружбы из интерфейса не принято ИИ")
		quit(1)
		return true
	game.state.diplomacy["dependency"]["1,0"] = {"strategic": 25.0}
	main.hud.open_diplomacy()
	var demand: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "Потребовать проход" and not node.disabled:
			demand = node
			break
	if demand == null:
		printerr("В окне нет доступного требования прохода")
		quit(1)
		return true
	demand.pressed.emit()
	main.act({"type": "end_turn", "force": true})
	if TreatyRules.until(game, "passage", 0, 1) <= game.state.turn:
		printerr("ИИ не ответил на требование прохода")
		quit(1)
		return true
	game.state.player(0).met[2] = true
	game.state.player(2).met[0] = true
	game.state.player(2).met[1] = true
	game.state.set_war(0, 1, true)
	game.state.diplomacy["dependency"]["2,0"] = {"strategic": 55.0}
	main.hud.open_strong_demands(2)
	var joint_war: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text.begins_with("Вступить в войну"):
			joint_war = node
			break
	if joint_war == null:
		printerr("Совместная война не появилась среди сильных требований")
		quit(1)
		return true
	joint_war.pressed.emit()
	main.act({"type": "end_turn", "force": true})
	if not game.state.at_war(2, 1):
		printerr("ИИ не вступил в совместную войну после требования")
		quit(1)
		return true
	for pid in 3:
		game.state.player(pid).known_civics["IDEOLOGY"] = true
	main.hud.open_congress()
	var found: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "Предложить учреждение ООН" and not node.disabled:
			found = node
			break
	if found == null:
		printerr("В окне ООН не доступно учредительное голосование")
		quit(1)
		return true
	found.pressed.emit()
	var in_favor: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "За":
			in_favor = node
			break
	if in_favor == null:
		printerr("В окне ООН нет кнопки голосования")
		quit(1)
		return true
	in_favor.pressed.emit()
	main.act({"type": "end_turn", "force": true})
	if not game.state.congress_data["founded"]:
		printerr("ООН не учреждена после голосов игрока и ИИ")
		quit(1)
		return true
	var proof_id: int = game.state.congress_data["next_id"]
	game.state.congress_data["next_id"] = proof_id + 1
	game.state.congress_data["evidence"][str(proof_id)] = {"id": proof_id, "kind": "religious",
		"victim": 0, "offender": 1, "source": 1, "reason": "protest_refused",
		"turn": game.state.turn, "available_round": game.state.turn, "filed": false}
	game.state.diplomacy["influence"]["0"] = {"value": 500.0, "target": 500.0, "sources": {}}
	main.hud.open_congress()
	var religious_case: Button = null
	for node in box.find_children("*", "Button", true, false):
		if node.text == "Потребовать прекращения проповеди":
			religious_case = node
			break
	if religious_case == null or religious_case.disabled:
		printerr("Религиозное дело не доступно в окне ООН")
		quit(1)
		return true
	religious_case.pressed.emit()
	if CongressRules.polls(game).is_empty() or CongressRules.polls(game)[0]["mode"] != "religious":
		printerr("Кнопка религиозного дела не открыла голосование")
		quit(1)
		return true
	print("Дипломатия, учреждение ООН и религиозное дело работают в игровой сцене")
	quit(0)
	return true
