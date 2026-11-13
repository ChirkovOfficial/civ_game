extends TestCase


func test_deterministic() -> void:
	var a := small_game(5)
	var b := small_game(5)
	check_eq(JSON.stringify(a.state.map.to_dict()), JSON.stringify(b.state.map.to_dict()), "одинаковое зерно — одинаковая карта")
	var c := small_game(6)
	check(JSON.stringify(a.state.map.to_dict()) != JSON.stringify(c.state.map.to_dict()), "разные зёрна — разные карты")


func test_land_fraction_and_terrain() -> void:
	var g := small_game(11, "SMALL")
	var m := g.state.map
	var land := 0
	var counts := {}
	for i in m.size():
		if m.is_land(i):
			land += 1
		counts[m.terrain[i]] = counts.get(m.terrain[i], 0) + 1
	var frac := float(land) / m.size()
	check(frac > 0.28 and frac < 0.5, "доля суши %f" % frac)
	for t in ["GRASS", "PLAINS", "COAST", "OCEAN"]:
		check(counts.get(t, 0) > 0, "есть %s" % t)


func test_rivers_consistent() -> void:
	var g := small_game(21, "SMALL")
	var m := g.state.map
	var river_tiles := 0
	for i in m.size():
		if m.has_river(i):
			river_tiles += 1
		for d in 6:
			if m.has_river_edge(i, d):
				var n := m.grid.neighbor(i, d)
				check(n >= 0 and m.has_river_edge(n, HexGrid.opposite(d)), "ребро реки симметрично")
	check(river_tiles > 10, "реки есть (%d клеток)" % river_tiles)


func test_features_and_resources_valid() -> void:
	var g := small_game(8, "SMALL")
	var m := g.state.map
	var data := g.data
	var res_count := 0
	for i in m.size():
		if m.feature[i] != "":
			check(data.features.has(m.feature[i]))
			check(data.features[m.feature[i]]["terrains"].has(m.terrain[i]),
				"%s на %s" % [m.feature[i], m.terrain[i]])
		if m.resource[i] != "":
			res_count += 1
			check(not m.is_mountain(i), "ресурс не на горе")
	check(res_count > 30, "ресурсов: %d" % res_count)


func test_start_positions() -> void:
	var g := small_game(3, "SMALL")
	var s := g.state
	check_eq(s.start_positions.size(), 6, "стартов по числу держав")
	for a in s.start_positions:
		check(s.map.is_land(a) and not s.map.is_mountain(a))
		check(s.map.has_fresh_water(a) or s.map.is_coastal_land(a), "вода у старта")
		for b in s.start_positions:
			if a != b:
				check(s.map.grid.distance(a, b) >= 4, "столицы не вплотную")


func test_start_units() -> void:
	var g := small_game(4)
	for p in g.state.players:
		var units := g.state.units_of(p.id)
		check_eq(units.size(), 2)
		var types := units.map(func(u): return u.type)
		check(types.has("SETTLER") and types.has("WARRIOR"))
		check(p.is_revealed(g.state.start_positions[p.id]), "старт разведан")
