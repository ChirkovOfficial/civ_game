extends TestCase


func _capture(g: Game, city: City) -> Array:
	var unit := g.state.add_unit(0, "SWORDSMAN", g.state.map.grid.neighbor(city.tile, 3))
	unit.moves_left = 2.0
	city.hp = 1
	g.state.set_war(0, city.owner, true)
	return g.apply_action({"type": "attack", "unit": unit.id, "target": city.tile})


func test_original_capitals_end_game_even_if_rival_has_new_capital() -> void:
	var g := blank_game(30, 12, 3)
	var grid := g.state.map.grid
	CityRules.found_city(g, 0, grid.index_of(2, 5))
	var rival := CityRules.found_city(g, 1, grid.index_of(8, 5))
	var replacement := CityRules.found_city(g, 1, grid.index_of(14, 5))
	var last := CityRules.found_city(g, 2, grid.index_of(22, 5))
	_capture(g, rival)
	check(replacement.is_capital)
	check(g.state.result.is_empty())
	check_eq(VictoryRules.capital_progress(g, 0), Vector2i(2, 3))
	var old := g.state.to_dict()
	old["version"] = 2
	old.erase("original_capitals")
	old.erase("result")
	g = SaveLoad.from_dict(g.data, old)
	check_eq(int(g.state.original_capitals["1"]), rival.id)
	var events := _capture(g, g.state.city(last.id))
	check_eq(events.filter(func(e): return e["type"] == "game_finished").size(), 1)
	check_eq(g.state.result["kind"], "domination")
	check_eq(g.state.result["winners"], [0])
	check(g.state.player(1).alive)
	var saved := g.state.to_json()
	var restored := GameState.from_json(saved, g.data)
	check_eq(restored.to_json(), saved)
	check_eq(g.apply_action({"type": "end_turn", "force": true})[0]["type"], "error")
	check_eq(g.state.to_json(), saved, "Итоговая карта остаётся неизменной")


func test_score_is_decided_after_every_player_finishes_last_round() -> void:
	var g := blank_game(20, 12, 3)
	var grid := g.state.map.grid
	CityRules.found_city(g, 0, grid.index_of(3, 5))
	CityRules.found_city(g, 1, grid.index_of(10, 5))
	g.state.player(1).is_ai = false
	g.state.player(2).is_barbarian = true
	g.state.player(2).known_techs["MINING"] = true
	g.state.settings["turn_limit"] = 1
	g.apply_action({"type": "end_turn", "force": true})
	check(g.state.result.is_empty())
	check_eq(g.state.current_player, 1)
	g.state.player(1).known_techs["MINING"] = true
	var events := g.apply_action({"type": "end_turn", "force": true})
	check_eq(g.state.result["kind"], "score")
	check_eq(g.state.result["winners"], [1])
	check_eq(g.state.turn, 1)
	check(not events.any(func(e): return e["type"] == "turn_started"))


func test_score_tie_and_scaled_default_limit() -> void:
	var g := blank_game()
	g.state.settings["speed"] = "QUICK"
	check_eq(VictoryRules.turn_limit(g), 335)
	g.state.player(1).is_ai = false
	g.state.current_player = 1
	g.state.turn = 335
	g.apply_action({"type": "end_turn", "force": true})
	check_eq(g.state.result["winners"], [0, 1])
