extends SceneTree
## Проверка экрана итогов в главной сцене.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	main.map_size = "DUEL"
	main.fixed_seed = 17
	root.add_child(main)
	var game: Game = main.game
	game.state.settings["turn_limit"] = 1
	main.act({"type": "end_turn", "force": true})
	var hud: Hud = main.hud
	if game.state.result.get("kind") != "score" or not hud.is_modal_open() \
			or hud.get("_research_kind") != "victory":
		printerr("Экран итогов не открылся после завершения партии")
		quit(1)
		return
	hud.close_research()
	main._end_turn()
	if not hud.is_modal_open() or game.state.turn != 1:
		printerr("Итоги нельзя открыть повторно")
		quit(1)
		return
	print("Экран итогов открылся автоматически и повторно")
	quit()
