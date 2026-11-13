extends TestCase


func test_offset_axial_roundtrip() -> void:
	var g := HexGrid.new(10, 8)
	for i in g.tile_count():
		var a := g.axial_of(i)
		check_eq(g.index_of_axial(a), i, "клетка %d" % i)


func test_dirs_identity() -> void:
	# На этом свойстве держится обход рек по рёбрам.
	for d in 6:
		check_eq(HexGrid.DIRS[(d + 2) % 6], HexGrid.DIRS[(d + 1) % 6] - HexGrid.DIRS[d], "направление %d" % d)


func test_neighbors_are_mutual() -> void:
	var g := HexGrid.new(12, 9)
	for i in g.tile_count():
		for d in 6:
			var n := g.neighbor(i, d)
			if n >= 0:
				check_eq(g.neighbor(n, HexGrid.opposite(d)), i, "клетка %d направление %d" % [i, d])
				check_eq(g.distance(i, n), 1)


func test_wrap_horizontal() -> void:
	var g := HexGrid.new(10, 6)
	var left := g.index_of(0, 2)
	var right := g.index_of(9, 2)
	check_eq(g.distance(left, right), 1, "края карты соседствуют")
	check(g.neighbors(left).has(right))
	check_eq(g.neighbor(g.index_of(5, 0), 1), -1, "за верхним краем нет клеток")


func test_distance_symmetric_and_radius() -> void:
	var g := HexGrid.new(16, 10)
	for a in [0, 17, 45, 100, 159]:
		for b in [3, 33, 80, 150]:
			check_eq(g.distance(a, b), g.distance(b, a))
	var c := g.index_of(8, 5)
	check_eq(g.tiles_in_radius(c, 1).size(), 7)
	check_eq(g.tiles_in_radius(c, 2).size(), 19)
	check_eq(g.ring(c, 2).size(), 12)


func test_world_roundtrip() -> void:
	var g := HexGrid.new(14, 9)
	for i in g.tile_count():
		var p := g.world_position(i)
		check_eq(g.index_at_world(p.x, p.y), i)
		check_eq(g.index_at_world(p.x + 0.3, p.y - 0.3), i, "смещение внутри гекса")


func test_corners_match_edges() -> void:
	# Середина ребра d (между вершинами d и d+1) лежит в направлении соседа d.
	var g := HexGrid.new(10, 10)
	var c := g.index_of(4, 4)
	var cp := g.world_position(c)
	for d in 6:
		var mid := (HexGrid.corner_offset(d) + HexGrid.corner_offset((d + 1) % 6)) * 0.5
		var np := g.world_position(g.neighbor(c, d)) - cp
		check_near(mid.normalized().dot(np.normalized()), 1.0, 1e-4, "ребро %d" % d)


func test_line_between() -> void:
	var g := HexGrid.new(20, 10)
	var a := g.index_of(2, 4)
	var b := g.index_of(6, 4)
	var line := g.line_between(a, b)
	check_eq(line.size(), 3)
	for t in line:
		check_eq(g.row_of(t), 4)
