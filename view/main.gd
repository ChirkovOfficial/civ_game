extends Node3D
## Точка входа: создаёт партию и связывает ядро с отображением и вводом.
## Ядро (core/) меняется только через Game.apply_action().

## Параметры новой партии (позже появится экран настройки).
@export var map_size := "SMALL"
@export var map_type := "CONTINENTS"
@export var fixed_seed := 0   # 0 — случайное зерно

var game: Game
var map_view: MapView
var units_view: UnitsView
var overlay: OverlayView
var camera_rig: CameraRig
var hud: Hud

var selected: Unit = null
var hover_tile := -1
var _hover_path_target := -2


func _ready() -> void:
	_setup_environment()
	map_view = MapView.new()
	map_view.name = "Map"
	add_child(map_view)
	overlay = OverlayView.new()
	overlay.name = "Overlay"
	add_child(overlay)
	units_view = UnitsView.new()
	units_view.name = "Units"
	add_child(units_view)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	hud = Hud.new()
	add_child(hud)
	hud.end_turn_pressed.connect(_end_turn)
	hud.skip_pressed.connect(_skip_selected)
	hud.new_map_pressed.connect(_new_game)
	hud.reveal_toggled.connect(_set_reveal)
	_new_game()


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1a1d24")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c9d4e8")
	e.ambient_light_energy = 0.38
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.light_energy = 0.7
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _new_game() -> void:
	var seed_value := fixed_seed if fixed_seed != 0 else randi() % 1000000 + 1
	var t0 := Time.get_ticks_msec()
	game = Game.new_game(GameData.get_default(), {
		"map_size": map_size, "map_type": map_type, "seed": seed_value, "humans": [0],
	})
	print("Карта создана за %d мс, зерно %d" % [Time.get_ticks_msec() - t0, seed_value])
	game.events_emitted.connect(_on_events)
	map_view.build(game)
	var map := game.state.map
	camera_rig.setup(map_view.world_width, map.grid.world_position(map.size() - 1).y + 1.0)
	units_view.setup(game, map_view)
	overlay.setup(map_view)
	selected = null
	_refresh_all()
	var start := game.state.start_positions[0]
	camera_rig.focus(map_view.tile_world(start))
	_select_next_unit()
	hud.show_message("Зерно карты: %d" % seed_value)


func _viewer() -> Player:
	return game.state.player(game.state.current_player)


func _refresh_all() -> void:
	var viewer := _viewer()
	map_view.refresh_fog(viewer)
	map_view.refresh_resources(viewer)
	units_view.selected_id = selected.id if selected != null else -1
	units_view.refresh(viewer, camera_rig.position.x)
	hud.set_turn(game.state.turn, viewer, game.units_needing_orders(viewer.id).size())
	hud.show_unit(game, selected)


func _on_events(events: Array) -> void:
	for e in events:
		if e["type"] == "error":
			hud.show_message(e["message"])
		elif e["type"] == "unit_blocked" and game.state.unit(e["unit"]) != null \
				and game.state.unit(e["unit"]).owner == game.state.current_player:
			hud.show_message("Путь перекрыт")


func _process(_delta: float) -> void:
	if game == null:
		return
	# Фигурки и наложения следуют за камерой через шов цилиндра.
	units_view.refresh(_viewer(), camera_rig.position.x)
	_update_hover()


func _update_hover() -> void:
	var mouse := get_viewport().get_mouse_position()
	var cam := camera_rig.camera
	var tile := map_view.pick_tile(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if get_viewport().gui_get_hovered_control() != null:
		tile = -1
	if tile != hover_tile:
		hover_tile = tile
		hud.show_tile(game, _viewer(), tile, map_view.reveal_all)
	overlay.show_hover(tile, camera_rig.position.x)
	# Предпросмотр пути для выбранного юнита.
	var path_target := tile if selected != null and selected.moves_left >= 0.0 else -1
	if path_target != _hover_path_target:
		_hover_path_target = path_target
		if path_target >= 0 and selected != null and path_target != selected.tile:
			overlay.show_path(Pathfinder.find_path(game, selected, path_target), camera_rig.position.x)
		else:
			overlay.clear_path()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_select_at(hover_tile)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and selected != null and hover_tile >= 0:
			_move_selected(hover_tile)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_end_turn()
			KEY_SPACE:
				_skip_selected()
			KEY_TAB:
				_select_next_unit(true)
			KEY_F2:
				_set_reveal(not map_view.reveal_all)
				hud.set_reveal(map_view.reveal_all)
			KEY_F5:
				_new_game()
			KEY_ESCAPE:
				_select(null)


func _select(u: Unit) -> void:
	selected = u
	_hover_path_target = -2
	units_view.selected_id = u.id if u != null else -1
	hud.show_unit(game, u)


func _select_at(tile: int) -> void:
	if tile < 0:
		_select(null)
		return
	var mine: Array[Unit] = []
	for u in game.state.units_at(tile):
		if u.owner == game.state.current_player:
			mine.append(u)
	if mine.is_empty():
		_select(null)
		return
	# Повторный клик по той же клетке переключает между юнитами в ней.
	var idx := mine.find(selected)
	_select(mine[(idx + 1) % mine.size()])


func _select_next_unit(cycle: bool = false) -> void:
	var waiting := game.units_needing_orders(game.state.current_player)
	if waiting.is_empty():
		_select(null)
		return
	var idx := waiting.find(selected) if cycle else -1
	var u: Unit = waiting[(idx + 1) % waiting.size()]
	_select(u)
	camera_rig.focus(map_view.tile_world(u.tile, camera_rig.position.x))


func _move_selected(tile: int) -> void:
	game.apply_action({"type": "move_unit", "unit": selected.id, "target": tile})
	_after_action()
	if selected != null and selected.moves_left <= 0.0:
		_select_next_unit()


func _skip_selected() -> void:
	if selected == null:
		return
	game.apply_action({"type": "skip_unit", "unit": selected.id})
	_after_action()
	_select_next_unit()


func _end_turn() -> void:
	game.apply_action({"type": "end_turn"})
	_select(null)
	_after_action()
	_select_next_unit()
	hud.show_message("Ход %d" % game.state.turn, 1.5)


func _after_action() -> void:
	_hover_path_target = -2
	_refresh_all()


func _set_reveal(on: bool) -> void:
	map_view.set_reveal_all(on)
	map_view.refresh_resources(_viewer())
	hud.show_tile(game, _viewer(), hover_tile, on)
