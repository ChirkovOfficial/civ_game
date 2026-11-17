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


func _religion_setup(g: Game, home: City) -> void:
	g.state.player(0).religion_id = "TEST_FAITH"
	g.state.religions["TEST_FAITH"] = {"name": "Путь звёзд", "founder": 0,
		"holy_city": home.id, "follower_belief": "SCHOLARLY", "founder_belief": "TITHE",
		"cult_belief": "", "enhancer_belief": "", "inquisition_started": false}
	home.religion_pressure["TEST_FAITH"] = 400.0


func _spread_test_religion(g: Game, target: City) -> Array:
	g.state.current_player = 0
	var unit := g.state.add_unit(0, "MISSIONARY", target.tile)
	unit.charges = 1
	unit.moves_left = 2.0
	return g.apply_action({"type": "spread_religion", "unit": unit.id})


func test_religious_victory_needs_majority_in_every_living_civilization() -> void:
	var g := blank_game(32, 16, 3)
	var grid := g.state.map.grid
	var home := CityRules.found_city(g, 0, grid.index_of(4, 5))
	var rival_a := CityRules.found_city(g, 1, grid.index_of(12, 4))
	var rival_b := CityRules.found_city(g, 1, grid.index_of(12, 11))
	var third := CityRules.found_city(g, 2, grid.index_of(22, 5))
	_religion_setup(g, home)
	var progress := VictoryRules.religion_progress(g, "TEST_FAITH")
	check_eq(progress[1]["required"], 2, "для двух городов нужно оба")
	_spread_test_religion(g, rival_a)
	_spread_test_religion(g, third)
	check(g.state.result.is_empty(), "одного из двух городов державы недостаточно")
	check_eq(VictoryRules.religion_progress(g, "TEST_FAITH")[1]["converted"], 1)
	var final_spread := _spread_test_religion(g, rival_b)
	check(final_spread.any(func(e): return e["type"] == "game_finished"))
	check_eq(g.state.result["kind"], "religion")
	check_eq(g.state.result["religion"], "TEST_FAITH")
	check_eq(g.state.result["winners"], [0])
	var saved := g.state.to_json()
	check_eq(GameState.from_json(saved, g.data).to_json(), saved)
	check_eq(g.apply_action({"type": "end_turn", "force": true})[0]["type"], "error")
	check_eq(g.state.to_json(), saved)


func test_natural_pressure_wins_before_score_on_last_round() -> void:
	var g := blank_game(32, 16, 2)
	var grid := g.state.map.grid
	var home := CityRules.found_city(g, 0, grid.index_of(5, 5))
	var rival := CityRules.found_city(g, 1, grid.index_of(12, 5))
	_religion_setup(g, home)
	rival.religion_pressure["TEST_FAITH"] = 99.0
	g.state.player(1).is_ai = false
	g.state.settings["turn_limit"] = 1
	check_eq(ReligionRules.majority(g, rival), "")
	g.apply_action({"type": "end_turn", "force": true})
	check(g.state.result.is_empty())
	var events := g.apply_action({"type": "end_turn", "force": true})
	check_eq(ReligionRules.majority(g, rival), "TEST_FAITH")
	check_eq(g.state.result["kind"], "religion")
	check(events.any(func(e): return e["type"] == "game_finished"))
	check_eq(g.state.turn, 1)


func test_religious_victory_ignores_eliminated_but_not_cityless_living_state() -> void:
	var g := blank_game(32, 16, 3)
	var grid := g.state.map.grid
	var home := CityRules.found_city(g, 0, grid.index_of(5, 5))
	var rival := CityRules.found_city(g, 1, grid.index_of(12, 5))
	_religion_setup(g, home)
	rival.religion_pressure["TEST_FAITH"] = 400.0
	VictoryRules.check_religion(g, [])
	check(g.state.result.is_empty(), "живая держава без городов не выполняет условие")
	g.state.player(2).alive = false
	VictoryRules.check_religion(g, [])
	check_eq(g.state.result["kind"], "religion")
	var without_founder := blank_game(32, 16, 2)
	var first := CityRules.found_city(without_founder, 0, without_founder.state.map.grid.index_of(5, 5))
	var second := CityRules.found_city(without_founder, 1, without_founder.state.map.grid.index_of(12, 5))
	_religion_setup(without_founder, first)
	second.religion_pressure["TEST_FAITH"] = 400.0
	without_founder.state.player(0).alive = false
	VictoryRules.check_religion(without_founder, [])
	check(without_founder.state.result.is_empty(), "религия выбывшего основателя не побеждает")
