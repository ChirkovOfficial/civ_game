class_name TerrainMeshBuilder
extends RefCounted
## Построение геометрии карты: плоские гексы, вода, реки и отдельные горы.
## Каждой вершине в UV2 записываются координаты клетки в текстуре тумана войны.
##
## Порядок обхода треугольников — по часовой стрелке со стороны лицевой грани
## (соглашение Godot).


static func tile_uv(grid: HexGrid, i: int) -> Vector2:
	return Vector2((grid.col_of(i) + 0.5) / grid.width, (grid.row_of(i) + 0.5) / grid.height)


static func _corner(center: Vector2, k: int) -> Vector2:
	return center + HexGrid.corner_offset(k % 6, MapStyle.HEX_SIZE)


## Цвет вершины k клетки i: среднее по клеткам той же высоты, сходящимся в вершине —
## мягкие «акварельные» переходы между ландшафтами.
static func _corner_color(map: GameMap, colors: PackedColorArray, heights: PackedFloat32Array,
		i: int, k: int) -> Color:
	var sum := colors[i]
	var count := 1.0
	for d in [(k + 5) % 6, k % 6]:
		var n := map.grid.neighbor(i, d)
		if n >= 0 and absf(heights[n] - heights[i]) < 0.01:
			sum += colors[n]
			count += 1.0
	return sum / count


static func build_terrain(map: GameMap) -> ArrayMesh:
	var grid := map.grid
	var n := map.size()
	var heights := PackedFloat32Array()
	heights.resize(n)
	var colors := PackedColorArray()
	colors.resize(n)
	for i in n:
		heights[i] = MapStyle.tile_height(map, i)
		colors[i] = MapStyle.top_color(map, i)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var c2 := grid.world_position(i, MapStyle.HEX_SIZE)
		var h := heights[i]
		var uv := tile_uv(grid, i)
		var center := Vector3(c2.x, h, c2.y)
		var center_col := colors[i].lightened(0.06)
		var corner_cols: Array[Color] = []
		for k in 6:
			corner_cols.append(_corner_color(map, colors, heights, i, k))
		# Верхняя грань: 6 треугольников из центра.
		st.set_uv(Vector2(MapStyle.biome_index(map, i), 0.0))
		for k in 6:
			var a := _corner(c2, k)
			var b := _corner(c2, k + 1)
			_v(st, center, Vector3.UP, Color(center_col, 1.0), uv)
			_v(st, Vector3(b.x, h, b.y), Vector3.UP, Color(corner_cols[(k + 1) % 6], 0.0), uv)
			_v(st, Vector3(a.x, h, a.y), Vector3.UP, Color(corner_cols[k], 0.0), uv)
	return st.commit()


static func _v(st: SurfaceTool, p: Vector3, normal: Vector3, col: Color, uv2: Vector2) -> void:
	st.set_normal(normal)
	st.set_color(col)
	st.set_uv2(uv2)
	st.add_vertex(p)


## Полупрозрачная поверхность воды над дном водных клеток.
static func build_water(map: GameMap) -> ArrayMesh:
	var grid := map.grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for i in map.size():
		if not map.is_water(i):
			continue
		var c2 := grid.world_position(i, MapStyle.HEX_SIZE)
		var col := MapStyle.WATER_DEEP if map.terrain[i] == "OCEAN" else MapStyle.WATER_SHALLOW
		if map.feature[i] == "ICE":
			col = Color(0.93, 0.96, 0.98, 0.95)
		var uv := tile_uv(grid, i)
		var y := MapStyle.WATER_Y
		var center := Vector3(c2.x, y, c2.y)
		st.set_uv(Vector2(4 if map.feature[i] == "ICE" else MapStyle.biome_index(map, i), 0.0))
		for k in 6:
			var a := _corner(c2, k)
			var b := _corner(c2, k + 1)
			_v(st, center, Vector3.UP, col, uv)
			_v(st, Vector3(b.x, y, b.y), Vector3.UP, col, uv)
			_v(st, Vector3(a.x, y, a.y), Vector3.UP, col, uv)
		count += 1
	if count == 0:
		return null
	return st.commit()


## Реки: полосы вдоль рёбер гексов.
static func build_rivers(map: GameMap) -> ArrayMesh:
	var grid := map.grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := 0.07
	var count := 0
	for i in map.size():
		if not map.has_river(i):
			continue
		var c2 := grid.world_position(i, MapStyle.HEX_SIZE)
		for d in 6:
			if not map.has_river_edge(i, d):
				continue
			var nb := grid.neighbor(i, d)
			# Каждое ребро — один раз (со стороны клетки с меньшим индексом).
			if nb >= 0 and nb < i:
				continue
			var h := MapStyle.tile_height(map, i)
			if nb >= 0:
				h = minf(h, MapStyle.tile_height(map, nb))
			h = maxf(h, MapStyle.WATER_Y) + 0.02
			var a := _corner(c2, d)
			var b := _corner(c2, d + 1)
			var along := (b - a).normalized()
			var across := Vector2(-along.y, along.x) * half_w
			# Немного продлеваем концы, чтобы сегменты стыковались без щелей.
			a -= along * half_w
			b += along * half_w
			var uv := tile_uv(grid, i)
			var p1 := Vector3(a.x + across.x, h, a.y + across.y)
			var p2 := Vector3(b.x + across.x, h, b.y + across.y)
			var p3 := Vector3(b.x - across.x, h, b.y - across.y)
			var p4 := Vector3(a.x - across.x, h, a.y - across.y)
			for tri in [[p1, p3, p2], [p1, p4, p3]]:
				for p in tri:
					_v(st, p, Vector3.UP, MapStyle.RIVER_COLOR, uv)
			count += 1
	if count == 0:
		return null
	return st.commit()


## Низкополигональная гора с вершинными цветами (камень → снег).
static func build_mountain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var radius := 0.75
	var height := 1.15
	var ring_mid_h := 0.62
	var ring_mid_r := 0.42
	var ring_top_h := 0.92
	var ring_top_r := 0.18
	var rings := [[0.0, radius, MapStyle.MOUNTAIN_ROCK.darkened(0.15)],
		[ring_mid_h, ring_mid_r, MapStyle.MOUNTAIN_ROCK_HI],
		[ring_top_h, ring_top_r, MapStyle.MOUNTAIN_SNOW]]
	var pts := []
	for r in rings:
		var ring := []
		for s in sides:
			var ang := TAU * s / sides + (0.3 if r[0] > 0 else 0.0)
			var jitter := 1.0 + (MapStyle.hash01(s, int(r[0] * 10)) - 0.5) * 0.25
			ring.append(Vector3(cos(ang) * r[1] * jitter, r[0], sin(ang) * r[1] * jitter))
		pts.append(ring)
	var apex := Vector3(0.05, height, -0.03)
	for level in 2:
		for s in sides:
			var a: Vector3 = pts[level][s]
			var b: Vector3 = pts[level][(s + 1) % sides]
			var c: Vector3 = pts[level + 1][(s + 1) % sides]
			var d: Vector3 = pts[level + 1][s]
			var ca: Color = rings[level][2]
			var cb: Color = rings[level + 1][2]
			_tri(st, a, b, c, ca, ca, cb)
			_tri(st, a, c, d, ca, cb, cb)
	for s in sides:
		var a: Vector3 = pts[2][s]
		var b: Vector3 = pts[2][(s + 1) % sides]
		_tri(st, a, b, apex, MapStyle.MOUNTAIN_SNOW, MapStyle.MOUNTAIN_SNOW, MapStyle.MOUNTAIN_SNOW)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
