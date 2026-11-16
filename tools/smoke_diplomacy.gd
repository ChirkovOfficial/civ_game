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
	print("Покупка мрамора, дружба, требование прохода и совместной войны работают")
	quit(0)
	return true
