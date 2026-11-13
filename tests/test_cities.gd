extends TestCase
## Города: основание, рост, производство, границы, покупки (ГДД 4, 5, 24).


func _city_game() -> Array:
	var g := blank_game(24, 14)
	var grid := g.state.map.grid
	var tile := grid.index_of(8, 6)
	var settler := g.state.add_unit(0, "SETTLER", tile)
	settler.moves_left = 2.0
	var ev := g.apply_action({"type": "found_city", "unit": settler.id})
	check_eq(ev[-1]["type"], "city_founded")
	var city: City = g.state.cities_of(0)[0]
	return [g, city, grid]


func test_formulas() -> void:
	var g := blank_game()
	check_eq(CityRules.growth_threshold(g, 1), 15)
	check_eq(CityRules.growth_threshold(g, 2), 24)
	check_eq(CityRules.growth_threshold(g, 3), 33)
	check_near(CityRules.border_cost(g, 1), 10.0 + pow(6.0, 1.3), 1e-4)
	var city := City.new()
	for pop_need in [[1, 0], [2, 0], [3, 1], [4, 1], [5, 2], [8, 3]]:
		city.population = pop_need[0]
		check_eq(CityRules.amenities_needed(city), pop_need[1], "довольство при населении %d" % pop_need[0])


func test_found_city() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	check(city.is_capital)
	check(city.has_building("PALACE"))
	check_eq(city.name, "Рим")
	check_eq(CityRules.owned_tiles(g, city).size(), 7)
	check(g.state.units.is_empty(), "поселенец израсходован")
	check_eq(city.worked_tiles.size(), 1)


func test_found_too_close() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var near := grid.index_of(11, 6)
	check(CityRules.found_city_error(g, 0, near) != "", "3 клетки — слишком близко")
	var far := grid.index_of(12, 6)
	check_eq(grid.distance(city.tile, far), 4)
	# Клетка в 4 от столицы, но не наша территория — можно.
	check_eq(CityRules.found_city_error(g, 0, far), "")


func test_center_min_yields_and_palace() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var y := CityRules.tile_yields(g, city.tile, g.state.player(0))
	check_eq(y.get("food", 0), 2.0)
	check_eq(y.get("production", 0), 1.0, "центр города минимум 1 ⚙")
	var cy := CityRules.city_yields(g, city)
	# центр 2🍞1⚙ + Дворец 2⚙2🔬1🎭5💰 + луг 2🍞 + 0.5🔬/0.3🎭 за жителя
	check_near(float(cy["food"]), 4.0)
	check_near(float(cy["production"]), 3.0)
	check_near(float(cy["gold"]), 5.0)
	check_near(float(cy["science"]), 2.5)
	check_near(float(cy["culture"]), 1.3)


func test_growth() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	# Сухое место: жильё 2 + Дворец 1 = 3; население 1 ≤ 3−2 — рост 100%.
	check_near(CityRules.housing(g, city), 3.0)
	check_near(CityRules.food_delta(g, city), 2.0)
	check_eq(CityRules.turns_to_grow(g, city), 8)
	city.queue = [{"kind": "building", "id": "MONUMENT"}]
	for t in 8:
		g.apply_action({"type": "end_turn", "force": true})
	check_eq(city.population, 2)
	check_eq(city.worked_tiles.size(), 2)
	# Население 2 = жильё−1 → рост 50%.
	check_near(CityRules.housing_growth_mult(g, city), 0.5)


func test_production_and_overflow() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	g.apply_action({"type": "set_production", "city": city.id, "kind": "unit", "id": "WARRIOR"})
	check_near(CityRules.production_per_turn(g, city), 3.0)
	check_eq(CityRules.turns_to_build(g, city, city.queue[0]), 14)
	for t in 14:
		g.apply_action({"type": "end_turn", "force": true})
	var warriors := g.state.units_of(0).filter(func(u): return u.type == "WARRIOR")
	check_eq(warriors.size(), 1, "воин построен за 14 ходов")
	check_near(city.overflow, 2.0, 1e-6, "переполнение 42−40")
	check(city.queue.is_empty())


func test_settler_needs_pop_two() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var ev := g.apply_action({"type": "set_production", "city": city.id, "kind": "unit", "id": "SETTLER"})
	check_eq(ev[0]["type"], "error")
	city.population = 2
	ev = g.apply_action({"type": "set_production", "city": city.id, "kind": "unit", "id": "SETTLER"})
	check_eq(ev[0]["type"], "city_updated")
	check_near(CityRules.item_cost(g, city, city.queue[0]), 80.0)
	g.state.player(0).produced["SETTLER"] = 2
	check_near(CityRules.item_cost(g, city, city.queue[0]), 140.0, 1e-6, "80 + 30·2")


func test_purchase() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var p := g.state.player(0)
	p.treasury = 100.0
	var ev := g.apply_action({"type": "purchase", "city": city.id, "kind": "building", "id": "MONUMENT"})
	check_eq(ev[0]["type"], "error", "не хватает золота")
	p.treasury = 300.0
	g.apply_action({"type": "purchase", "city": city.id, "kind": "building", "id": "MONUMENT"})
	check(city.has_building("MONUMENT"))
	check_near(p.treasury, 60.0, 1e-6, "60⚙ × 4 = 240💰")


func test_borders_grow() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	city.queue = [{"kind": "building", "id": "MONUMENT"}]
	var before := CityRules.owned_tiles(g, city).size()
	# 1.3 🎭/ход; первая клетка стоит ~20.3.
	for t in 16:
		g.apply_action({"type": "end_turn", "force": true})
	check_eq(CityRules.owned_tiles(g, city).size(), before + 1)
	check_eq(city.border_tiles_acquired, 1)


func test_buy_tile() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var t := grid.index_of(10, 6)
	check_eq(grid.distance(city.tile, t), 2)
	g.state.player(0).treasury = 200.0
	var cost := CityRules.tile_purchase_cost(g, city, t)
	check_eq(cost, 75, "50 × (1 + 0.5 × 1)")
	g.apply_action({"type": "buy_tile", "city": city.id, "tile": t})
	check_eq(g.state.map.owner_city[t], city.id)
	check_near(g.state.player(0).treasury, 125.0)
	var far := grid.index_of(14, 6)
	var ev := g.apply_action({"type": "buy_tile", "city": city.id, "tile": far})
	check_eq(ev[0]["type"], "error")


func test_research_and_overflow() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	city.queue = [{"kind": "building", "id": "MONUMENT"}]
	var p := g.state.player(0)
	check(EmpireRules.available_techs(g, 0).has("POTTERY"))
	check(not EmpireRules.available_techs(g, 0).has("WRITING"), "нужна предпосылка")
	g.apply_action({"type": "set_research", "kind": "tech", "id": "POTTERY"})
	p.tech_progress["POTTERY"] = 24.0
	g.apply_action({"type": "end_turn", "force": true})   # +2.5 🔬
	check(p.has_tech("POTTERY"))
	check_near(float(p.tech_progress.get("_overflow", 0.0)), 1.5)
	g.apply_action({"type": "set_research", "kind": "tech", "id": "WRITING"})
	check_near(float(p.tech_progress["WRITING"]), 1.5, 1e-6, "переполнение перенесено")


func test_end_turn_blocking() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var ev := g.apply_action({"type": "end_turn"})
	check_eq(ev[0]["type"], "error", "без выбора исследования и производства ход не закончить")
	var city: City = r[1]
	g.apply_action({"type": "set_research", "kind": "tech", "id": "POTTERY"})
	g.apply_action({"type": "set_research", "kind": "civic", "id": "CODE_OF_LAWS"})
	g.apply_action({"type": "set_production", "city": city.id, "kind": "building", "id": "MONUMENT"})
	ev = g.apply_action({"type": "end_turn"})
	check_eq(ev[0]["type"], "turn_ended")


func test_luxury_amenities() -> void:
	var r := _city_game()
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var t := grid.neighbor(city.tile, 0)
	g.state.map.resource[t] = "WINE"
	check_eq(int(CityRules.luxury_amenities(g, 0)[city.id]), 0, "неулучшенный люкс не считается")
	g.state.map.improvement[t] = "PLANTATION"
	check_eq(int(CityRules.luxury_amenities(g, 0)[city.id]), 1)
	city.population = 5
	var info := CityRules.amenity_info(g, city)
	# Дворец +1, вино +1, нужно 2 → баланс 0.
	check_eq(int(info["balance"]), 0)
