extends TestCase
## Строители и улучшения (ГДД 8).


func _setup() -> Array:
	var g := blank_game(24, 14)
	var grid := g.state.map.grid
	var tile := grid.index_of(8, 6)
	var settler := g.state.add_unit(0, "SETTLER", tile)
	settler.moves_left = 2.0
	g.apply_action({"type": "found_city", "unit": settler.id})
	var city: City = g.state.cities_of(0)[0]
	var b := g.state.add_unit(0, "BUILDER", grid.neighbor(tile, 0))
	b.moves_left = 2.0
	b.charges = 3
	return [g, city, grid, b]


func test_farm() -> void:
	var r := _setup()
	var g: Game = r[0]
	var city: City = r[1]
	var b: Unit = r[3]
	check(ImprovementRules.valid_improvements(g, b).has("FARM"))
	check(not ImprovementRules.valid_improvements(g, b).has("MINE"), "рудник — только на холмах и с технологией")
	var before := CityRules.housing(g, city)
	g.apply_action({"type": "build_improvement", "unit": b.id, "improvement": "FARM"})
	check_eq(g.state.map.improvement[b.tile], "FARM")
	check_eq(b.charges, 2)
	check_near(b.moves_left, 0.0)
	check_eq(float(CityRules.tile_yields(g, b.tile, g.state.player(0))["food"]), 3.0)
	check_near(CityRules.housing(g, city), before + 0.5)


func test_builder_used_up() -> void:
	var r := _setup()
	var g: Game = r[0]
	var b: Unit = r[3]
	b.charges = 1
	g.apply_action({"type": "build_improvement", "unit": b.id, "improvement": "FARM"})
	check(g.state.unit(b.id) == null, "последний заряд — строитель исчезает")


func test_outside_territory() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[2]
	var b: Unit = r[3]
	b.tile = grid.index_of(15, 6)
	check(ImprovementRules.build_error(g, b, "FARM") != "")


func test_mine_requires_tech_and_hills() -> void:
	var r := _setup()
	var g: Game = r[0]
	var b: Unit = r[3]
	g.state.map.relief[b.tile] = GameMap.RELIEF_HILLS
	check(ImprovementRules.build_error(g, b, "MINE").contains("технология"))
	g.state.player(0).known_techs["MINING"] = true
	check_eq(ImprovementRules.build_error(g, b, "MINE"), "")


func test_resource_requires_its_improvement() -> void:
	var r := _setup()
	var g: Game = r[0]
	var b: Unit = r[3]
	g.state.map.resource[b.tile] = "CATTLE"
	check(ImprovementRules.build_error(g, b, "FARM") != "", "на скоте — только пастбище")
	g.state.player(0).known_techs["ANIMAL_HUSBANDRY"] = true
	check_eq(ImprovementRules.build_error(g, b, "PASTURE"), "")


func test_harvest_woods() -> void:
	var r := _setup()
	var g: Game = r[0]
	var city: City = r[1]
	var b: Unit = r[3]
	g.state.map.feature[b.tile] = "WOODS"
	check(ImprovementRules.harvest_preview(g, b).is_empty(), "вырубка леса — с «Горного дела»")
	g.state.player(0).known_techs["MINING"] = true
	city.queue = [{"kind": "unit", "id": "WARRIOR"}]
	g.apply_action({"type": "harvest", "unit": b.id})
	check_eq(g.state.map.feature[b.tile], "")
	check(float(city.progress.get("unit:WARRIOR", 0.0)) >= 20.0, "производство ушло в город")
