extends SceneTree
## Дымовой тест интерфейса: запускает главную сцену и проходит типичные действия игрока.
##   xvfb-run -a godot --path . -s tools/smoke_view.gd
## Ошибки скриптов видны в выводе. Последний кадр сохраняется в /tmp/smoke.png.

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://view/main.tscn").instantiate()
	_main.fixed_seed = 77
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var g: Game = _main.game if _main != null else null
	match _frames:
		3:
			# Основать столицу поселенцем.
			for u in g.state.units_of(0):
				if u.type == "SETTLER":
					_main.act({"type": "found_city", "unit": u.id})
		4:
			var city: City = g.state.cities_of(0)[0]
			_main.act({"type": "set_production", "city": city.id, "kind": "unit", "id": "BUILDER"})
			_main.act({"type": "set_research", "kind": "tech", "id": "MINING"})
			_main.act({"type": "set_research", "kind": "civic", "id": "CODE_OF_LAWS"})
			_main.hud.open_research("tech")
			_main.hud.close_research()
			for u in g.state.units_of(0):
				_main.act({"type": "sleep_unit", "unit": u.id})
		5:
			var city2: City = g.state.cities_of(0)[0]
			g.state.player(0).treasury = 500
			for t in CityRules.border_candidates(g, city2):
				if CityRules.tile_purchase_error(g, city2, t) == "":
					_main._select_city(city2)
					_main._click_tile(t)
					break
	if _frames > 5 and _frames < 40:
		# Играем ходы: новые юниты — спать, строитель — строить.
		for u in g.state.units_of(0):
			if u.moves_left > 0.0 and u.orders.is_empty():
				var imps := ImprovementRules.valid_improvements(g, u)
				if not imps.is_empty():
					_main.act({"type": "build_improvement", "unit": u.id, "improvement": imps[0]})
				else:
					_main.act({"type": "sleep_unit", "unit": u.id})
		for c in g.state.cities_of(0):
			if c.queue.is_empty():
				_main.act({"type": "set_production", "city": c.id, "kind": "building", "id": "MONUMENT"})
				if c.queue.is_empty():
					_main.act({"type": "set_production", "city": c.id, "kind": "unit", "id": "WARRIOR"})
		var p := g.state.player(0)
		if p.current_tech == "":
			_main.act({"type": "set_research", "kind": "tech", "id": EmpireRules.available_techs(g, 0)[0]})
		if p.current_civic == "":
			_main.act({"type": "set_research", "kind": "civic", "id": EmpireRules.available_civics(g, 0)[0]})
		_main._end_turn()
		_main._set_reveal(_frames % 7 == 0)
	if _frames == 41:
		var city3: City = g.state.cities_of(0)[0]
		_main._select_city(city3)
		_main.camera_rig.focus(_main.map_view.tile_world(city3.tile))
	if _frames == 45:
		# Командующий + войска → когорта; окно снаряжения.
		_main._select_city(null)
		for u in g.state.units_of(0):
			if Combat.can_attack(g, u) and g.state.city_owning(u.tile) != null:
				var cmd := g.state.add_unit(0, "COMMANDER", u.tile)
				_main.act({"type": "attach_commander", "unit": cmd.id, "target": u.id})
				_main._select(u)
				_main.hud.open_equipment(u.id)
				_main.camera_rig.focus(_main.map_view.tile_world(u.tile))
				_main.camera_rig.target_distance = 9.0
				break
	if _frames == 42:
		_main.save_game()
	if _frames == 43:
		_main._new_game()
	if _frames == 44:
		_main.load_game()
		g = _main.game
	if _frames == 52:
		root.get_viewport().get_texture().get_image().save_png("/tmp/smoke.png")
		var h: Hud = _main.hud
		for n in ["_city_panel", "_unit_panel", "_tile_panel", "_research_panel"]:
			var c: Control = h.get(n)
			print(n, " visible=", c.visible, " rect=", c.get_global_rect())
		var c0: City = g.state.cities_of(0)[0]
		print("Дымовой тест: ход %d, городов %d, население столицы %d, юнитов %d, технологий %d" % [
			g.state.turn, g.state.cities.size(), c0.population, g.state.units.size(),
			g.state.player(0).known_techs.size()])
		return true
	return false
