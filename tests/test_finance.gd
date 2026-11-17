extends TestCase


func _world() -> Dictionary:
	var game := blank_game(26, 14, 2)
	var data := GameData.new()
	data.load_all()
	game.data = data
	var own := CityRules.found_city(game, 0, game.state.map.grid.index_of(6, 6))
	var rival := CityRules.found_city(game, 1, game.state.map.grid.index_of(17, 6))
	return {"game": game, "own": own, "rival": rival}


func _set_income(game: Game, city: City, target: float) -> void:
	var id := "TEST_INCOME_%d" % city.id
	if not game.data.buildings.has(id):
		game.data.buildings[id] = {"yields": {"gold": 0.0}, "maintenance": 0.0}
		city.buildings.append(id)
	var current := FinanceRules.economic_income(game, city.owner)
	game.data.buildings[id]["yields"]["gold"] += target - current


func test_world_exchange_threshold_rival_and_reset() -> void:
	var world := _world()
	var game: Game = world["game"]
	_set_income(game, world["own"], 700.0)
	_set_income(game, world["rival"], 460.0)
	check_near(FinanceRules.economic_income(game, 0), 700.0)
	check_near(FinanceRules.threshold(game), 350.0)
	check_near(FinanceRules.threshold(blank_game(26, 14, 8)), 650.0)
	var events: Array = []
	FinanceRules.begin_turn(game, 0, events)
	check(not FinanceRules.unlocked(game))
	check_eq(FinanceRules.progress(game, 0)["streak"], 0)
	game.state.player(1).known_techs["BANKING"] = true
	FinanceRules.begin_turn(game, 0, events)
	check(events.any(func(event): return event["type"] == "world_exchange_opened"))
	check_eq(FinanceRules.progress(game, 0)["streak"], 1)
	check_eq(GameState.from_json(game.state.to_json(), game.data).finance_data["streaks"]["0"], 1)
	FinanceRules.begin_turn(game, 0, events)
	check_eq(FinanceRules.progress(game, 0)["streak"], 1)
	game.state.turn += 1
	_set_income(game, world["rival"], 470.0)
	FinanceRules.begin_turn(game, 0, events)
	check_eq(FinanceRules.progress(game, 0)["streak"], 0)
	check(events.any(func(event): return event["type"] == "finance_hegemony_broken"))
	game.state.turn += 1
	_set_income(game, world["own"], 300.0)
	game.state.player(0).treasury += 10000.0
	check_near(FinanceRules.economic_income(game, 0), 300.0)
	FinanceRules.begin_turn(game, 0, events)
	check_eq(FinanceRules.progress(game, 0)["streak"], 0)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.finance_data, game.state.finance_data)
	var old := game.state.to_dict()
	old["version"] = 14
	old.erase("finance")
	check_eq(GameState.from_dict(old, game.data).finance_data["streaks"], {})


func test_capital_bankruptcy_and_speed_requirements() -> void:
	var world := _world()
	var game: Game = world["game"]
	_set_income(game, world["own"], 900.0)
	_set_income(game, world["rival"], 100.0)
	game.state.player(0).known_techs["BANKING"] = true
	game.state.settings["speed"] = "ONLINE"
	check_eq(FinanceRules.required_turns(game), 5)
	game.state.settings["speed"] = "QUICK"
	check_eq(FinanceRules.required_turns(game), 7)
	game.state.settings["speed"] = "EPIC"
	check_eq(FinanceRules.required_turns(game), 15)
	game.state.settings["speed"] = "STANDARD"
	game.state.player(0).treasury = -5.0
	FinanceRules.begin_turn(game, 0, [], true)
	check_eq(FinanceRules.progress(game, 0)["streak"], 0)
	game.state.player(0).treasury = 10.0
	game.state.turn += 1
	var own: City = world["own"]
	own.owner = 1
	FinanceRules.begin_turn(game, 0, [])
	check_eq(FinanceRules.progress(game, 0)["streak"], 0)
	own.owner = 0
	game.state.turn += 1
	FinanceRules.begin_turn(game, 0, [])
	check_eq(FinanceRules.progress(game, 0)["streak"], 1)


func test_finance_victory_on_own_turn_before_score() -> void:
	var world := _world()
	var game: Game = world["game"]
	_set_income(game, world["own"], 700.0)
	_set_income(game, world["rival"], 100.0)
	game.data.finance_setup["standard_turns"] = 2
	game.state.player(1).known_techs["BANKING"] = true
	game.state.player(1).is_ai = false
	game.state.settings["turn_limit"] = 3
	game.apply_action({"type": "end_turn", "force": true})
	game.apply_action({"type": "end_turn", "force": true})
	check_eq(FinanceRules.progress(game, 0)["streak"], 1)
	game.apply_action({"type": "end_turn", "force": true})
	var ending := game.apply_action({"type": "end_turn", "force": true})
	check(ending.any(func(event): return event["type"] == "game_finished"))
	check_eq(game.state.result["kind"], "finance")
	check_eq(game.state.result["winners"], [0])
	check_eq(game.state.turn, 3)
