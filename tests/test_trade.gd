extends TestCase


func _reveal(game: Game, pid: int) -> void:
	game.state.player(pid).revealed.fill(Player.FOG_REVEALED)


func _trader(game: Game, city: City) -> Unit:
	game.state.player(city.owner).known_civics["FOREIGN_TRADE"] = true
	var unit := game.state.add_unit(city.owner, "TRADER", city.tile)
	unit.moves_left = 1.0
	return unit


func test_route_income_roads_capacity_and_completion() -> void:
	var g := blank_game()
	var grid := g.state.map.grid
	var origin := CityRules.found_city(g, 0, grid.index_of(3, 5))
	var target := CityRules.found_city(g, 0, grid.index_of(8, 5))
	var trader := _trader(g, origin)
	_reveal(g, 0)
	var base := CityRules.city_yields(g, origin)
	var action := {"type": "start_trade", "unit": trader.id, "destination": target.id}
	check_eq(g.apply_action(action)[0]["type"], "trade_started")
	check_eq(TradeRules.active_count(g, 0), 1)
	check_eq(TradeRules.capacity(g, 0), 1)
	var idle := _trader(g, target)
	check_eq(g.apply_action({"type": "start_trade", "unit": idle.id, "destination": origin.id})[0]["type"], "error")
	check_eq(g.apply_action({"type": "move_unit", "unit": trader.id, "target": target.tile})[0]["type"], "error")
	check_near(float(CityRules.city_yields(g, origin)["food"]), float(base["food"]) + 1.0)
	check_near(float(CityRules.city_yields(g, origin)["production"]), float(base["production"]) + 1.0)
	var turns := int(trader.trade_route["turns"])
	check_eq(turns, 20)
	TradeRules.advance(g, 0, [])
	check(trader.tile != origin.tile)
	check(g.state.map.road[trader.tile] > 0)
	var restored := GameState.from_json(g.state.to_json(), g.data)
	check(restored.to_json() == g.state.to_json(), "Действующий маршрут переживает сохранение")
	for i in range(1, turns):
		TradeRules.advance(g, 0, [])
	check(trader.trade_route.is_empty())
	check_eq(trader.tile, origin.tile)
	check(target.trade_posts.has(0))
	check_eq(TradeRules.active_count(g, 0), 0)
	check_eq(CityRules.city_yields(g, origin), base)
	target.districts = [{"type": "HARBOR", "complete": true}, {"type": "COMMERCIAL_HUB", "complete": true}]
	check_eq(TradeRules.capacity(g, 0), 2)


func test_war_cancels_international_trade_and_barbarians_raid() -> void:
	var g := blank_game(20, 12, 3)
	var grid := g.state.map.grid
	var origin := CityRules.found_city(g, 0, grid.index_of(3, 5))
	var foreign := CityRules.found_city(g, 1, grid.index_of(8, 5))
	var domestic := CityRules.found_city(g, 0, grid.index_of(3, 9))
	g.state.player(2).is_barbarian = true
	var trader := _trader(g, origin)
	_reveal(g, 0)
	var base := float(EmpireRules.summary(g, 0)["net_gold"])
	var start := {"type": "start_trade", "unit": trader.id, "destination": foreign.id}
	check_eq(g.apply_action(start)[0]["type"], "error", "Нужен контакт между державами")
	g.state.player(0).met[1] = true
	check_eq(g.apply_action(start)[0]["type"], "trade_started")
	check_near(float(EmpireRules.summary(g, 0)["net_gold"]), base + 3.0)
	TradeRules.advance(g, 0, [])
	var war := g.apply_action({"type": "declare_war", "target": 1})
	check(war.any(func(event): return event["type"] == "trade_cancelled"))
	check_eq(trader.tile, origin.tile)
	check(trader.trade_route.is_empty())
	check_near(float(EmpireRules.summary(g, 0)["net_gold"]), base)
	trader.moves_left = 1.0
	check_eq(g.apply_action({"type": "start_trade", "unit": trader.id, "destination": domestic.id})[0]["type"], "trade_started")
	var attacker := g.state.add_unit(2, "WARRIOR", trader.tile)
	attacker.moves_left = 2.0
	check(Combat.target_at(g, 2, trader.tile)["kind"] == "city")
	g.state.current_player = 2
	check_eq(g.apply_action({"type": "raid_trade", "unit": attacker.id})[0]["type"], "trade_raided")
	check_eq(g.state.unit(trader.id), null)
	check_near(g.state.player(2).treasury, 50.0)
	check_eq(TradeRules.active_count(g, 0), 0)


func test_range_and_trade_post() -> void:
	var g := blank_game(52, 12)
	var grid := g.state.map.grid
	var origin := CityRules.found_city(g, 0, grid.index_of(3, 5))
	var post := CityRules.found_city(g, 0, grid.index_of(13, 5))
	var target := CityRules.found_city(g, 0, grid.index_of(23, 5))
	_reveal(g, 0)
	check(TradeRules.plan(g, origin, target).is_empty())
	post.trade_posts.append(0)
	var route := TradeRules.plan(g, origin, target)
	check(not route.is_empty())
	check_eq(TradeRules.route_yields(g, route)["gold"], 1.0)


func test_maritime_route() -> void:
	var g := blank_game()
	var map := g.state.map
	var start := map.grid.index_of(3, 5)
	var finish := map.grid.index_of(9, 5)
	map.terrain.fill("COAST")
	map.terrain[start] = "GRASS"
	map.terrain[finish] = "GRASS"
	var origin := CityRules.found_city(g, 0, start)
	var target := CityRules.found_city(g, 0, finish)
	var trader := _trader(g, origin)
	_reveal(g, 0)
	check(TradeRules.plan(g, origin, target).is_empty())
	g.state.player(0).known_techs["SAILING"] = true
	check_eq(g.apply_action({"type": "start_trade", "unit": trader.id, "destination": target.id})[0]["type"], "trade_started")
	TradeRules.advance(g, 0, [])
	check(map.is_water(trader.tile))
	check_eq(map.road[trader.tile], 0)
