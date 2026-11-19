extends SceneTree
## Проверка реальных кнопок нового HUD и мини-карты; опциональный снимок через -- путь.png.
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result.append_array(_buttons(child))
	return result

func _press(node: Node, prefix: String) -> bool:
	for button in _buttons(node):
		if button.text.begins_with(prefix) and not button.disabled:
			button.pressed.emit()
			return true
	return false

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _run() -> void:
	main = load("res://view/main.tscn").instantiate()
	main.fixed_seed = 77
	main.map_size = "DUEL"
	root.add_child(main)
	await process_frame
	for unit in main.game.state.units_of(0):
		if unit.type == "SETTLER":
			main.act({"type": "found_city", "unit": unit.id})
	var city: City = main.game.state.cities_of(0)[0]
	main._select_city(city)
	if not _require(_press(main.hud._city_box, "Производство"), "Нет вкладки производства"):
		return
	await process_frame
	if not _require(_press(main.hud._city_box, "Строитель"), "Нет кнопки строительства"):
		return
	if not _require(city.current_item().get("id", "") == "BUILDER", "Кнопка не назначила производство"):
		return
	main.act({"type": "set_research", "kind": "tech", "id": "MINING"})
	main.act({"type": "set_research", "kind": "civic", "id": "CODE_OF_LAWS"})
	main.hud.open_research("tech")
	main.hud.close_research()
	main._set_reveal(true)
	if not _require(main.hud._minimap.reveal_all, "Мини-карта не обновила раскрытие"):
		return
	var target: int = main.game.state.map.grid.index_of(10, 10)
	main.hud._minimap.tile_pressed.emit(target)
	var expected: Vector3 = main.map_view.tile_world(target, main.camera_rig.position.x)
	if not _require(absf(main.camera_rig.position.x - expected.x) < 0.01, "Мини-карта не переместила камеру"):
		return
	main.camera_rig.focus(main.map_view.tile_world(city.tile))
	await process_frame
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
	print("UI атлас: вкладки, производство, исследования, раскрытие и навигация мини-карты работают")
	quit(0)
