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
	print("Формы поставок и предложение дружбы из окна дипломатии работают")
	quit(0)
	return true
