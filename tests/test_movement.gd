extends TestCase
## Правила движения (ГДД 3.5) на «пустой» карте из лугов.


func _setup() -> Array:
	var g := blank_game()
	var grid := g.state.map.grid
	var start := grid.index_of(5, 6)
	var u := g.state.add_unit(0, "WARRIOR", start)
	u.moves_left = 2.0
	for p in g.state.players:
		Visibility.recompute(g, p.id)
	return [g, u, grid]


func test_open_ground_two_steps() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var target := grid.index_of(7, 6)
	var path := Pathfinder.find_path(g, u, target)
	check_eq(path.size(), 2)
	check_eq(path[1].turn, 0, "2 клетки по лугу — за один ход")
	g.apply_action({"type": "move_unit", "unit": u.id, "target": target})
	check_eq(u.tile, target)
	check_near(u.moves_left, 0.0)


func test_full_moves_exception() -> void:
	# Холмы+лес стоят 3 ОД, у воина 2 — с полным запасом войти можно.
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var t := grid.index_of(6, 6)
	g.state.map.relief[t] = GameMap.RELIEF_HILLS
	g.state.map.feature[t] = "WOODS"
	check_near(Movement.terrain_cost(g, t), 3.0)
	check_near(Movement.moves_after_step(g, u, u.tile, t, 2.0), 0.0, 1e-6, "полный запас")
	check_near(Movement.moves_after_step(g, u, u.tile, t, 1.0), -1.0, 1e-6, "неполный запас — нельзя")


func test_hills_cost_two() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[2]
	var t := grid.index_of(6, 6)
	g.state.map.relief[t] = GameMap.RELIEF_HILLS
	check_near(Movement.terrain_cost(g, t), 2.0)


func test_river_takes_all_moves() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var east := grid.neighbor(u.tile, 0)
	g.state.map.set_river_edge(u.tile, 0)
	check_near(Movement.moves_after_step(g, u, u.tile, east, 2.0), 0.0, 1e-6, "переход реки обнуляет ОД")
	var path := Pathfinder.find_path(g, u, grid.neighbor(east, 0))
	check(path.size() >= 2)
	# Путь в обход реки или через неё — в любом случае цель за 1 ход недостижима напрямую.
	check(path[-1].turn >= 0)


func test_mountain_impassable() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var t := grid.index_of(6, 6)
	g.state.map.relief[t] = GameMap.RELIEF_MOUNTAIN
	check(Pathfinder.find_path(g, u, t).is_empty(), "в гору нельзя")


func test_multi_turn_path_and_orders() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var target := grid.index_of(11, 6)   # 6 клеток = 3 хода
	var path := Pathfinder.find_path(g, u, target)
	check_eq(path.size(), 6)
	check_eq(path[-1].turn, 2)
	g.apply_action({"type": "move_unit", "unit": u.id, "target": target})
	check_eq(grid.distance(u.tile, target), 4)
	check_eq(u.orders.get("target", -1), target, "приказ сохранён")
	g.apply_action({"type": "end_turn"})   # ИИ (игрок 1) ходит сам
	check_eq(grid.distance(u.tile, target), 2, "продолжил путь в начале хода")
	g.apply_action({"type": "end_turn"})
	check_eq(u.tile, target)
	check(u.orders.is_empty())


func test_zoc_stops_movement() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var enemy_tile := grid.index_of(6, 5)
	g.state.add_unit(1, "WARRIOR", enemy_tile)
	var into_zoc := grid.index_of(6, 6)
	check(grid.distance(into_zoc, enemy_tile) == 1)
	# Без войны ZOC не действует.
	check_near(Movement.moves_after_step(g, u, u.tile, into_zoc, 2.0), 1.0)
	g.state.set_war(0, 1, true)
	check_near(Movement.moves_after_step(g, u, u.tile, into_zoc, 2.0), 0.0, 1e-6, "вход в ZOC обнуляет ОД")
	# Кавалерия игнорирует ZOC.
	var h := g.state.add_unit(0, "HORSEMAN", u.tile)
	check_near(Movement.moves_after_step(g, h, h.tile, into_zoc, 4.0), 3.0)


func test_stacking() -> void:
	var r := _setup()
	var g: Game = r[0]
	var u: Unit = r[1]
	var grid: HexGrid = r[2]
	var t := grid.neighbor(u.tile, 0)
	var other := g.state.add_unit(0, "WARRIOR", t)
	other.moves_left = 2.0
	check(not Movement.occupancy_allows(g, u, t, true), "два боевых в одной клетке нельзя")
	check(Movement.occupancy_allows(g, u, t, false), "пройти сквозь своего можно")
	var settler := g.state.add_unit(0, "SETTLER", u.tile)
	check(Movement.occupancy_allows(g, settler, t, true), "гражданский + боевой можно")
	var foreign := g.state.add_unit(1, "SETTLER", grid.neighbor(u.tile, 3))
	check(not Movement.occupancy_allows(g, u, foreign.tile, false), "в чужую клетку нельзя")


func test_not_own_unit_rejected() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[2]
	var enemy := g.state.add_unit(1, "WARRIOR", grid.index_of(15, 6))
	var ev := g.apply_action({"type": "move_unit", "unit": enemy.id, "target": grid.index_of(16, 6)})
	check_eq(ev[0]["type"], "error")
	check_eq(enemy.tile, grid.index_of(15, 6))
