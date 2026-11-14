extends TestCase
## Районы и городская жизнь (docs/CITIES.md, веха M4).


## Город Рима в центре пустой карты; вся территория в радиусе 3 — его.
func _setup(techs: Array = []) -> Array:
	var g := blank_game(24, 14)
	var grid := g.state.map.grid
	var settler := g.state.add_unit(0, "SETTLER", grid.index_of(8, 6))
	settler.moves_left = 2.0
	g.apply_action({"type": "found_city", "unit": settler.id})
	var city: City = g.state.cities_of(0)[0]
	for t in grid.tiles_in_radius(city.tile, 3):
		CityRules.claim_tile(g, city, t)
	var p := g.state.player(0)
	for t in techs:
		if g.data.techs.has(t):
			p.known_techs[t] = true
		else:
			p.known_civics[t] = true
	return [g, city, grid]


func _build(g: Game, city: City, type: String, tile: int) -> Dictionary:
	var ev := g.apply_action({"type": "set_production", "city": city.id, "kind": "district", "id": type, "tile": tile})
	check(ev[0]["type"] != "error", "район %s ставится: %s" % [type, ev[0].get("text", "")])
	var e := DistrictRules.entry_at(city, tile)
	CityRules.complete_item(g, city, city.queue[0], [])
	city.queue = []
	return e


func _ring1(grid: HexGrid, center: int) -> Array:
	return Array(grid.neighbors(center))


func test_place_and_complete() -> void:
	var r := _setup(["WRITING"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var tile: int = _ring1(grid, city.tile)[0]
	var ev := g.apply_action({"type": "set_production", "city": city.id, "kind": "district", "id": "CAMPUS", "tile": tile})
	check_eq(ev[0]["type"], "district_placed")
	check_eq(g.state.map.district[tile], "CAMPUS")
	check_eq(g.state.map.district[city.tile], "CITY_CENTER")
	var e := DistrictRules.entry_at(city, tile)
	check(not e["complete"], "заложен, но не построен")
	check(not CityRules.workable_tiles(g, city).has(tile), "клетку района не обрабатывают")
	# Цена фиксируется при закладке: 54 × (1 + 9 × доля открытого).
	var p := g.state.player(0)
	var frac := maxf(float(p.known_techs.size()) / g.data.techs.size(), float(p.known_civics.size()) / g.data.civics.size())
	check_near(float(e["cost"]), roundf(54.0 * (1.0 + 9.0 * frac)), 0.01)
	check_eq(CityRules.item_cost(g, city, city.queue[0]), float(e["cost"]))
	city.progress[City.item_key(city.queue[0])] = float(e["cost"]) - 0.5
	CityRules.process_production(g, city, 1.0, [])
	check(e["complete"], "район достроен")
	# Здание района.
	var lib := {"kind": "building", "id": "LIBRARY", "tile": tile}
	check_eq(CityRules.build_error(g, city, lib), "")
	check(CityRules.build_error(g, city, {"kind": "building", "id": "LIBRARY"}) != "", "без клетки района — нельзя")
	check(CityRules.build_error(g, city, {"kind": "building", "id": "UNIVERSITY", "tile": tile}) != "")
	var sci0 := float(CityRules.city_yields(g, city).get("science", 0))
	CityRules.complete_item(g, city, lib, [])
	check_near(float(CityRules.city_yields(g, city).get("science", 0)), sci0 + 2.0, 1e-4, "Библиотека +2 🔬")
	check(CityRules.build_error(g, city, lib) != "", "второй раз не строится")
	# Районы за золото не покупаются.
	p.treasury = 10000.0
	var ev2 := g.apply_action({"type": "purchase", "city": city.id, "kind": "district", "id": "CAMPUS", "tile": _ring1(grid, city.tile)[2]})
	check_eq(ev2[0]["type"], "error")


func test_limit_by_population() -> void:
	var r := _setup(["WRITING", "ASTROLOGY", "POTTERY"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	check_eq(DistrictRules.specialized_limit(city), 1)
	_build(g, city, "CAMPUS", _ring1(grid, city.tile)[0])
	check(DistrictRules.type_error(g, city, "HOLY_SITE") != "", "лимит 1 при населении 1")
	check_eq(DistrictRules.type_error(g, city, "RESIDENTIAL_DENSE"), "", "жилые районы вне лимита")
	city.population = 4
	check_eq(DistrictRules.specialized_limit(city), 2)
	check_eq(DistrictRules.type_error(g, city, "HOLY_SITE"), "")
	check_eq(DistrictRules.type_error(g, city, "CAMPUS"), "", "второй Кампус в том же городе можно")
	# Каждый следующий однотипный дороже на 25%.
	var c1 := DistrictRules.cost(g, city, "HOLY_SITE")
	check_near(DistrictRules.cost(g, city, "CAMPUS"), roundf(c1 * 1.25), 1.0)


func test_adjacency() -> void:
	var r := _setup(["WRITING", "CURRENCY"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var map := g.state.map
	# Кампус в 2 клетках от центра; рядом две горы.
	var tile := -1
	for t in grid.ring(city.tile, 2):
		tile = t
		break
	var nbs := Array(grid.neighbors(tile))
	var mountains := []
	for nb in nbs:
		if grid.distance(nb, city.tile) == 3 and mountains.size() < 2:
			map.relief[nb] = GameMap.RELIEF_MOUNTAIN
			mountains.append(nb)
	check_eq(mountains.size(), 2)
	check_eq(DistrictRules.adjacency(g, 0, "CAMPUS", tile), {"science": 2.0})
	# Соседний район +0.5 — округляется вниз; два района — +1.
	var other := -1
	for nb in nbs:
		if grid.distance(nb, city.tile) == 2 and map.relief[nb] == 0:
			other = nb
			break
	city.population = 4
	_build(g, city, "COMMERCIAL_HUB", other)
	check_eq(DistrictRules.adjacency(g, 0, "CAMPUS", tile), {"science": 2.0}, "+0.5 округляется вниз")
	var center_nb := -1
	for nb in nbs:
		if grid.distance(nb, city.tile) == 1:
			center_nb = nb
	city.population = 7
	_build(g, city, "COMMERCIAL_HUB", center_nb)
	check_eq(DistrictRules.adjacency(g, 0, "CAMPUS", tile), {"science": 3.0}, "два района рядом — +1")
	# Коммерческий центр у реки: +2 золота.
	map.set_river_edge(other, 0)
	check_eq(float(DistrictRules.adjacency(g, 0, "COMMERCIAL_HUB", other).get("gold", 0)), 2.0)


func test_cluster_rule() -> void:
	var r := _setup(["WRITING"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	city.population = 30
	# Три Кампуса в ряд на расстоянии 2 от центра.
	var row := []
	var c := grid.index_of(8, 6)
	for col in [7, 8, 9]:
		row.append(grid.index_of(col, 4))
	for t in row:
		_build(g, city, "CAMPUS", t)
	check_eq(DistrictRules.of_type(city, "CAMPUS").size(), 3)
	# Четвёртый вплотную к группе — нельзя.
	var adj := grid.index_of(10, 4)
	check(grid.distance(adj, row[2]) == 1)
	check(DistrictRules.placement_error(g, city, "CAMPUS", adj).begins_with("Не больше"), "больше трёх в группе нельзя")
	# Не вплотную, но ближе 3 клеток к полной группе — тоже нельзя.
	var near := -1
	for t in grid.tiles_in_radius(c, 3):
		if DistrictRules.min_distance_to(grid, t, row) == 2:
			near = t
			break
	check(near >= 0)
	check(DistrictRules.placement_error(g, city, "CAMPUS", near) != "")
	# В 3 клетках от группы — можно.
	var far := -1
	for t in grid.tiles_in_radius(c, 3):
		if DistrictRules.min_distance_to(grid, t, row) >= 3:
			far = t
			break
	check(far >= 0)
	check_eq(DistrictRules.placement_error(g, city, "CAMPUS", far), "")
	# Другой тип рядом с группой — можно.
	g.state.player(0).known_techs["ASTROLOGY"] = true
	check_eq(DistrictRules.placement_error(g, city, "HOLY_SITE", adj), "")


func test_aqueduct_and_dam() -> void:
	var r := _setup(["ENGINEERING", "BUTTRESS"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var map := g.state.map
	var t1: int = _ring1(grid, city.tile)[0]
	check(DistrictRules.placement_error(g, city, "AQUEDUCT", t1) != "", "без воды и гор — нельзя")
	for nb in grid.neighbors(t1):
		if grid.distance(nb, city.tile) == 2:
			map.relief[nb] = GameMap.RELIEF_MOUNTAIN
			break
	check_eq(DistrictRules.placement_error(g, city, "AQUEDUCT", t1), "")
	var h0 := CityRules.housing(g, city)
	_build(g, city, "AQUEDUCT", t1)
	check_near(CityRules.housing(g, city), h0 + 2.0, 1e-4, "акведук +2 жилья")
	# Второй акведук — не ближе 3 клеток к первому.
	for t in grid.tiles_in_radius(city.tile, 3):
		map.river_edges[t] = 1
	for t in grid.tiles_in_radius(city.tile, 3):
		if map.district[t] != "" or map.is_mountain(t):
			continue
		var err := DistrictRules.placement_error(g, city, "AQUEDUCT", t)
		check_eq(err == "", grid.distance(t, t1) >= 3, "акведук на %d (дистанция %d)" % [t, grid.distance(t, t1)])
	# Плотина: пойма и река по двум рёбрам.
	var dt := grid.index_of(10, 8)
	check(DistrictRules.placement_error(g, city, "DAM", dt) != "")
	map.feature[dt] = "FLOODPLAINS"
	map.river_edges[dt] = 0
	map.set_river_edge(dt, 0)
	check(DistrictRules.placement_error(g, city, "DAM", dt) != "", "одно ребро — мало")
	map.set_river_edge(dt, 1)
	check_eq(DistrictRules.placement_error(g, city, "DAM", dt), "")


func test_upgrade_and_roman_names() -> void:
	var r := _setup(["WRITING"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var tile: int = _ring1(grid, city.tile)[0]
	var e := _build(g, city, "CAMPUS", tile)
	check_eq(DistrictRules.display_name(g, 0, "CAMPUS", 1), "Атенеум")
	var up := {"kind": "district_upgrade", "id": "CAMPUS", "tile": tile}
	check(CityRules.build_error(g, city, up) != "", "без технологии — нельзя")
	g.state.player(0).known_techs["EDUCATION"] = true
	check_eq(CityRules.build_error(g, city, up), "")
	check_eq(CityRules.item_name(g, up, 0), "Атенеум → Студиум")
	check_near(CityRules.item_cost(g, city, up), roundf(float(e["cost"]) * 0.5), 0.01)
	CityRules.complete_item(g, city, up, [])
	check_eq(int(e["tier"]), 2)
	check_eq(DistrictRules.display_name(g, 0, "CAMPUS", 2), "Студиум")
	check_eq(float(DistrictRules.output(g, city, e)["yields"].get("science", 0)), 1.0, "уровень II: +1 🔬, соседство центра 0.5 × 1.25 → 0")
	# У чужой (не римской) державы — нейтральные названия.
	check_eq(DistrictRules.display_name(g, 1, "CAMPUS", 2), "Кампус II")


func test_nero_urbanization() -> void:
	var r := _setup(["WRITING", "ASTROLOGY", "CURRENCY"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	city.population = 10
	var ring := _ring1(grid, city.tile)
	# Кампус и вокруг него два других специализированных района.
	var campus := _build(g, city, "CAMPUS", ring[0])
	check(DistrictRules.nero(g, city, campus).is_empty(), "соседей нет — бонуса нет")
	var shared := []
	for nb in grid.neighbors(ring[0]):
		if grid.distance(nb, city.tile) == 1:
			shared.append(nb)
	_build(g, city, "HOLY_SITE", shared[0])
	check(DistrictRules.nero(g, city, campus).is_empty(), "одного соседа мало")
	_build(g, city, "COMMERCIAL_HUB", shared[1])
	var n := DistrictRules.nero(g, city, campus)
	check_near(float(n["bonus"]), 0.1)
	check_eq(n["neighbors"].size(), 2)
	city.population = 15
	check_near(float(DistrictRules.nero(g, city, campus)["bonus"]), 0.2)
	check_eq(int(DistrictRules.nero(g, city, campus)["flat"]), 1)
	city.population = 25
	check_near(float(DistrictRules.nero(g, city, campus)["bonus"]), 0.3)
	# Не-римская держава бонуса не получает.
	check(DistrictRules.city_ability(g, 1, "NERO_URBANIZATION").is_empty())
	# Жилой район соседом не считается.
	var e := DistrictRules.entry_at(city, shared[1])
	e["type"] = "RESIDENTIAL_DENSE"
	g.state.map.district[shared[1]] = "RESIDENTIAL_DENSE"
	check(DistrictRules.nero(g, city, campus).is_empty())


func test_specialists() -> void:
	var r := _setup(["WRITING"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	# Оставим городу только первое кольцо.
	for t in grid.tiles_in_radius(city.tile, 3):
		if grid.distance(t, city.tile) > 1:
			g.state.map.owner_city[t] = -1
	var tile: int = _ring1(grid, city.tile)[0]
	_build(g, city, "CAMPUS", tile)
	CityRules.complete_item(g, city, {"kind": "building", "id": "LIBRARY", "tile": tile}, [])
	city.population = 7
	CityRules.assign_citizens(g, city)
	check_eq(city.worked_tiles.size(), 5)
	check_eq(int(city.specialists.get(str(tile), 0)), 1, "одно место специалиста — у Библиотеки")
	var e := DistrictRules.entry_at(city, tile)
	check_eq(float(DistrictRules.output(g, city, e)["yields"].get("science", 0)), 2.0 + 2.0 + 0.0,
		"Библиотека 2 + специалист 2 (соседство центра 0.5 → 0)")


func test_city_life() -> void:
	var r := _setup(["POTTERY"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	city.population = 9
	check(not CityLife.active(g, city))
	check_eq(CityLife.epidemic_chance(g, city), 0.0)
	check_eq(CityLife.unrest_penalty(g, city), 0.0)
	city.population = 14
	# 5 жителей сверх порога: нужно 5 × 0.5 × 1.25 (Рим) санитарии и 5 × 0.3 порядка.
	var san := CityLife.sanitation(g, city)
	check_near(float(san["need"]), 3.125)
	check_near(CityLife.epidemic_chance(g, city), 3.125 * 0.02)
	check_near(CityLife.unrest_penalty(g, city), 1.5 * 0.05)
	# Термы: +2 санитарии.
	_build(g, city, "BATHS", _ring1(grid, city.tile)[0])
	check_near(float(CityLife.sanitation(g, city)["supply"]), 2.0)
	# Эпидемия: −1 житель, рост остановлен, доходы ×0.9.
	var y0 := float(CityRules.city_yields(g, city).get("production", 0))
	city.epidemic_turns = 5
	check_near(float(CityRules.city_yields(g, city).get("production", 0)), y0 * 0.9, 1e-4)
	check_eq(CityLife.growth_mult(g, city), 0.0)
	var ev := []
	for i in 5:
		CityLife.process_city(g, city, ev)
	check_eq(city.epidemic_turns, 0)
	check_eq(ev[-1]["type"], "epidemic_ended")


func test_governors_and_doctrines() -> void:
	var r := _setup()
	var g: Game = r[0]
	var city: City = r[1]
	check_eq(CityLife.governors_total(g, 0), 1)
	var ev := g.apply_action({"type": "set_doctrine", "city": city.id, "doctrine": "AUTOCRACY"})
	check_eq(ev[0]["type"], "city_updated")
	check(not CityLife.doctrine_active(city), "губернатор вступает в должность не сразу")
	for i in 5:
		CityLife.process_city(g, city, [])
	check(CityLife.doctrine_active(city))
	check_near(float(CityLife.order(g, city)["supply"]), 6.0)
	check_near(CityLife.growth_mult(g, city), 0.75)
	# Усталость автократии через 20 ходов.
	g.state.turn += 25
	check_near(float(CityLife.order(g, city)["supply"]), 4.0)
	# Второго губернатора нет.
	var c2 := City.new()
	c2.id = 99
	c2.owner = 0
	c2.tile = 0
	g.state.cities[99] = c2
	check(CityLife.set_doctrine_error(g, c2, "PERSUASION") != "")
	# Убеждение стоит золота: 0.5 за жителя.
	g.apply_action({"type": "set_doctrine", "city": city.id, "doctrine": "PERSUASION"})
	city.doctrine_turns = 0
	city.population = 6
	check_near(float(CityLife.doctrine_upkeep(g, city)["gold"]), 3.0)


func test_district_save_roundtrip() -> void:
	var r := _setup(["WRITING", "POTTERY"])
	var g: Game = r[0]
	var city: City = r[1]
	var grid: HexGrid = r[2]
	var ring := _ring1(grid, city.tile)
	_build(g, city, "CAMPUS", ring[0])
	CityRules.complete_item(g, city, {"kind": "building", "id": "LIBRARY", "tile": ring[0]}, [])
	city.population = 4
	g.apply_action({"type": "set_production", "city": city.id, "kind": "district", "id": "BATHS", "tile": ring[3]})
	city.specialists = {str(ring[0]): 1}
	city.epidemic_turns = 2
	g.apply_action({"type": "set_doctrine", "city": city.id, "doctrine": "RELIGIOUS"})
	var restored := GameState.from_bytes(g.state.to_bytes(), g.data)
	var a: Dictionary = g.state.to_dict()
	var b: Dictionary = restored.to_dict()
	check(JSON.stringify(a["cities"]) == JSON.stringify(b["cities"]), "города с районами совпадают")
	check(JSON.stringify(a["map"]["district"]) == JSON.stringify(b["map"]["district"]), "районы на карте совпадают")
	var rc: City = restored.cities[city.id]
	check_eq(City.item_key(rc.queue[0]), City.item_key(city.queue[0]))
	var js := GameState.from_json(g.state.to_json(), g.data)
	check(JSON.stringify(js.to_dict()["cities"]) == JSON.stringify(a["cities"]), "и через JSON тоже")
