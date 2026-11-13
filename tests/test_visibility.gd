extends TestCase


func test_flat_sight_radius() -> void:
	var g := blank_game()
	var grid := g.state.map.grid
	var c := grid.index_of(8, 6)
	check_eq(Visibility.visible_tiles(g, c, 2).size(), 19)


func test_woods_block_flat_observer() -> void:
	var g := blank_game()
	var grid := g.state.map.grid
	var c := grid.index_of(8, 6)
	var woods := grid.index_of(9, 6)
	var behind := grid.index_of(10, 6)
	g.state.map.feature[woods] = "WOODS"
	var vis := Visibility.visible_tiles(g, c, 2)
	check(vis.has(woods), "сам лес виден")
	check(not vis.has(behind), "за лесом не видно")
	# С холма видно поверх леса на равнине.
	g.state.map.relief[c] = GameMap.RELIEF_HILLS
	check(Visibility.visible_tiles(g, c, 2).has(behind), "с холма видно поверх леса")


func test_hills_block_and_mountain() -> void:
	var g := blank_game()
	var grid := g.state.map.grid
	var c := grid.index_of(8, 6)
	var mid := grid.index_of(9, 6)
	var behind := grid.index_of(10, 6)
	g.state.map.relief[mid] = GameMap.RELIEF_MOUNTAIN
	g.state.map.relief[c] = GameMap.RELIEF_HILLS
	check(not Visibility.visible_tiles(g, c, 2).has(behind), "гора закрывает обзор даже с холма")


func test_fog_reveal_accumulates() -> void:
	var g := blank_game()
	var grid := g.state.map.grid
	var u := g.state.add_unit(0, "SCOUT", grid.index_of(3, 6))
	u.moves_left = 3.0
	Visibility.recompute(g, 0)
	var p := g.state.player(0)
	var far := grid.index_of(9, 6)
	check(not p.is_revealed(far))
	g.apply_action({"type": "move_unit", "unit": u.id, "target": grid.index_of(6, 6)})
	check(p.is_revealed(grid.index_of(8, 6)))
	check(p.is_revealed(grid.index_of(3, 6)), "пройденное остаётся разведанным")
	check(not p.is_visible(grid.index_of(1, 6)), "но уже не видно")


func test_save_load_roundtrip() -> void:
	var g := small_game(9)
	var u := g.state.units_of(0)[1]
	var target := -1
	for t in g.state.map.grid.tiles_in_radius(u.tile, 2):
		if Movement.can_stand(g, u, t) and t != u.tile and g.state.units_at(t).is_empty():
			target = t
			break
	g.apply_action({"type": "move_unit", "unit": u.id, "target": target})
	g.apply_action({"type": "end_turn", "force": true})
	var text := g.state.to_json()
	var restored := GameState.from_json(text, g.data)
	var a: Dictionary = g.state.to_dict()
	var b: Dictionary = restored.to_dict()
	for k in a:
		check(JSON.stringify(a[k]) == JSON.stringify(b.get(k)), "поле %s совпадает после загрузки" % k)
	for k in a["map"]:
		check(JSON.stringify(a["map"][k]) == JSON.stringify(b["map"].get(k)), "поле карты %s совпадает" % k)
	check_eq(restored.turn, g.state.turn)
	check_eq(restored.rng.randf(), g.state.rng.randf(), "ГПСЧ продолжает ту же последовательность")
