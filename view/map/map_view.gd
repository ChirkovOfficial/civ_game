class_name MapView
extends Node3D
## Отрисовка карты: террасы, вода, реки, горы, леса, маркеры ресурсов, туман войны.
## Карта зациклена: рисуется в трёх копиях (слева, по центру, справа), камера
## «перескакивает» через шов незаметно.

const TERRAIN_SHADER := preload("res://view/map/shaders/terrain.gdshader")
const FEATURE_SHADER := preload("res://view/map/shaders/feature.gdshader")
const FOREST_SPRITE_SHADER := preload("res://view/map/shaders/forest_sprite.gdshader")
const OVERLAY_SHADER := preload("res://view/map/shaders/overlay.gdshader")
const FOREST_SHEET := preload("res://art/terrain/placeholder/forest_sheet.png")

## Старые кроны и стволы сохранены для сравнения, по умолчанию не рисуются.
@export var use_legacy_tree_meshes := false

var game: Game
var world_width: float
var fog_image: Image
var fog_texture: ImageTexture
var reveal_all := false
## Игрок, глазами которого показана карта (для высот неразведанных клеток).
var viewer: Player = null

var _materials: Array[ShaderMaterial] = []
var _copies: Array[Node3D] = []
## Слои отрисовки: имя -> [узел в копии 0, 1, 2].
var _layers := {}
var _terrain_mat: ShaderMaterial
var _feature_mat: ShaderMaterial
var _forest_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _river_mat: ShaderMaterial
var _border_mat: ShaderMaterial
var _improvement_meshes := {}


func build(g: Game) -> void:
	game = g
	for c in get_children():
		c.queue_free()
	_copies.clear()
	_materials.clear()
	_layers.clear()
	var map := game.state.map
	world_width = map.grid.world_width(MapStyle.HEX_SIZE)
	fog_image = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	fog_image.fill(Color.BLACK)
	fog_texture = ImageTexture.create_from_image(fog_image)

	_terrain_mat = _make_material(TERRAIN_SHADER)
	_feature_mat = _make_material(FEATURE_SHADER)
	_forest_mat = _make_material(FOREST_SPRITE_SHADER)
	_forest_mat.set_shader_parameter("forest_sheet", FOREST_SHEET)
	_water_mat = _make_material(OVERLAY_SHADER)
	_water_mat.render_priority = 1
	_river_mat = _make_material(OVERLAY_SHADER)
	_river_mat.render_priority = 2
	_border_mat = _make_material(OVERLAY_SHADER)
	_border_mat.render_priority = 3
	_improvement_meshes = ImprovementMeshes.build_all()

	for k in [-1, 0, 1]:
		var copy := Node3D.new()
		copy.name = "Copy%d" % (k + 1)
		copy.position.x = k * world_width
		add_child(copy)
		_copies.append(copy)
	_set_layer("water", TerrainMeshBuilder.build_water(map), _water_mat)
	_set_layer("rivers", TerrainMeshBuilder.build_rivers(map), _river_mat)
	_set_layer("mountains", _build_mountains(map), _feature_mat)
	refresh_geometry()


## Пересобирает то, что меняется по ходу игры. parts — набор из
## "terrain" (рельеф и леса), "improvements", "borders"; пустой — всё.
func refresh_geometry(parts: Dictionary = {}) -> void:
	var map := game.state.map
	var all := parts.is_empty()
	if all or parts.has("terrain"):
		_set_layer("terrain", TerrainMeshBuilder.build_terrain(map), _terrain_mat)
		if use_legacy_tree_meshes:
			var trees := _build_trees(map)
			_set_layer("crowns", trees[0], _feature_mat)
			_set_layer("trunks", trees[1], _feature_mat)
		else:
			_set_layer("forest_sprites", _build_forest_sprites(map), _forest_mat)
	if all or parts.has("improvements"):
		refresh_improvements()
	if all or parts.has("borders"):
		refresh_borders()
	if all or parts.has("roads"):
		refresh_roads()
	if viewer != null and (all or parts.has("terrain")):
		refresh_resources(viewer)


## Создаёт/обновляет слой в трёх копиях. res — Mesh или MultiMesh.
func _set_layer(layer_name: String, res: Resource, mat: Material, is_multimesh: bool = false) -> void:
	if not _layers.has(layer_name):
		var nodes := []
		for copy in _copies:
			var node: GeometryInstance3D
			if res is MultiMesh or is_multimesh:
				node = MultiMeshInstance3D.new()
			else:
				node = MeshInstance3D.new()
			node.name = layer_name
			node.material_override = mat
			copy.add_child(node)
			nodes.append(node)
		_layers[layer_name] = nodes
	for node in _layers[layer_name]:
		if node is MultiMeshInstance3D:
			node.multimesh = res
		else:
			node.mesh = res


func _make_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("fog_tex", fog_texture)
	m.set_shader_parameter("reveal_all", reveal_all)
	_materials.append(m)
	return m


# --- Объекты на клетках -----------------------------------------------------------

func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _tile_pos(i: int) -> Vector3:
	var map := game.state.map
	var p := map.grid.world_position(i, MapStyle.HEX_SIZE)
	return Vector3(p.x, MapStyle.tile_height(map, i), p.y)


func _custom(i: int) -> Color:
	var uv := TerrainMeshBuilder.tile_uv(game.state.map.grid, i)
	return Color(uv.x, uv.y, 0, 0)


func _build_mountains(map: GameMap) -> MultiMesh:
	var items: Array = []
	for i in map.size():
		if not map.is_mountain(i):
			continue
		var base := _tile_pos(i)
		var peaks := 1 + int(MapStyle.hash01(i, 3) * 2.5)
		for p in peaks:
			var ang := MapStyle.hash01(i, 10 + p) * TAU
			var r := 0.0 if p == 0 else 0.42
			var scale := (1.0 if p == 0 else 0.6) * (0.85 + MapStyle.hash01(i, 20 + p) * 0.3)
			var t := Transform3D(Basis(Vector3.UP, MapStyle.hash01(i, 30 + p) * TAU).scaled(Vector3.ONE * scale),
				base + Vector3(cos(ang) * r, 0, sin(ang) * r))
			items.append([t, Color.WHITE, _custom(i)])
	var mm := _new_multimesh(TerrainMeshBuilder.build_mountain_mesh(), items.size())
	_fill(mm, items)
	return mm


## Плоские деревья из верхних двух рядов временного атласа. Варианты и позиции
## зависят только от индекса клетки, поэтому не меняются при обновлении карты.
func _build_forest_sprites(map: GameMap) -> MultiMesh:
	var items: Array = []
	for i in map.size():
		var feature := map.feature[i]
		if feature != "WOODS" and feature != "RAINFOREST":
			continue
		var base := _tile_pos(i)
		var variants := [0, 1, 2, 3, 5, 7, 8, 9, 10, 11]
		if feature == "RAINFOREST":
			variants = [6, 7, 9, 10, 11, 0]
		elif map.terrain[i] == "TUNDRA":
			variants = [4, 4, 1]
		var count := 3 if feature == "RAINFOREST" else 2
		for k in count:
			var choice := mini(variants.size() - 1, int(MapStyle.hash01(i, 80 + k) * variants.size()))
			var cell: int = variants[choice]
			var angle := (k + MapStyle.hash01(i, 90 + k) * 0.5) * TAU / count
			var radius := 0.12 + 0.2 * MapStyle.hash01(i, 100 + k)
			var scale := 0.82 + 0.28 * MapStyle.hash01(i, 110 + k)
			var pos := base + Vector3(cos(angle) * radius, 0.95 * scale * 0.5 - 0.03,
				sin(angle) * radius)
			var transform := Transform3D(Basis().scaled(Vector3.ONE * scale), pos)
			var tile_uv := TerrainMeshBuilder.tile_uv(map.grid, i)
			items.append([transform, Color.WHITE,
				Color(tile_uv.x, tile_uv.y, float(cell % 6) / 5.0, 0.0 if cell < 6 else 1.0)])
	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.95)
	var mm := _new_multimesh(quad, items.size())
	_fill(mm, items)
	return mm


## Старый 3D лес: возвращает [кроны, стволы]. Сохранён для переключателя выше.
func _build_trees(map: GameMap) -> Array:
	var crowns: Array = []
	var trunks: Array = []
	for i in map.size():
		var f := map.feature[i]
		if f != "WOODS" and f != "RAINFOREST":
			continue
		var base := _tile_pos(i)
		var conifer := f == "WOODS" and (map.terrain[i] == "TUNDRA" or map.terrain[i] == "SNOW")
		var count := 4 if f == "RAINFOREST" else 3
		for k in count:
			var ang := (k + MapStyle.hash01(i, 40 + k) * 0.6) * TAU / count
			var r := 0.22 + MapStyle.hash01(i, 50 + k) * 0.32
			var pos := base + Vector3(cos(ang) * r, 0, sin(ang) * r)
			var s := 0.8 + MapStyle.hash01(i, 60 + k) * 0.5
			var palette: Array[Color] = MapStyle.WOODS_COLORS
			if f == "RAINFOREST":
				palette = MapStyle.RAINFOREST_COLORS
				s *= 1.15
			elif conifer:
				palette = MapStyle.CONIFER_COLORS
			var col: Color = palette[int(MapStyle.hash01(i, 70 + k) * palette.size()) % palette.size()]
			var crown_basis := Basis().scaled(Vector3(s, s * (1.6 if conifer else 1.0), s))
			crowns.append([Transform3D(crown_basis, pos + Vector3(0, 0.24 * s + 0.12, 0)), col, _custom(i)])
			trunks.append([Transform3D(Basis().scaled(Vector3.ONE * s), pos + Vector3(0, 0.1 * s, 0)), MapStyle.TRUNK_COLOR, _custom(i)])
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.25
	crown_mesh.height = 0.42
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.03
	trunk_mesh.bottom_radius = 0.04
	trunk_mesh.height = 0.24
	trunk_mesh.radial_segments = 5
	var mm_c := _new_multimesh(crown_mesh, crowns.size())
	_fill(mm_c, crowns)
	var mm_t := _new_multimesh(trunk_mesh, trunks.size())
	_fill(mm_t, trunks)
	return [mm_c, mm_t]


## Маркеры ресурсов зависят от технологий игрока (стратегические скрыты).
func refresh_resources(player: Player) -> void:
	var map := game.state.map
	var items: Array = []
	for i in map.size():
		var rid := map.resource[i]
		if rid == "" or not (reveal_all or Yields.resource_visible(game.data, rid, player)):
			continue
		var cls: String = game.data.resources[rid].get("class", "bonus")
		var pos := _tile_pos(i) + Vector3(0.38, 0.3, 0.28)
		if map.is_water(i):
			pos.y = MapStyle.WATER_Y + 0.2
		items.append([Transform3D(Basis(), pos), MapStyle.RESOURCE_COLORS.get(cls, Color.WHITE), _custom(i)])
	var gem := SphereMesh.new()
	gem.radius = 0.09
	gem.height = 0.2
	gem.radial_segments = 4
	gem.rings = 2
	var mm := _new_multimesh(gem, items.size())
	_fill(mm, items)
	_set_layer("resources", mm, _feature_mat)


## Улучшения клеток: по слою на каждую деталь каждого типа.
func refresh_improvements() -> void:
	var map := game.state.map
	var per_part := {}   # "IMP#k" -> [items]
	for i in map.size():
		var imp := map.improvement[i]
		if imp == "" or not _improvement_meshes.has(imp):
			continue
		var base := _tile_pos(i)
		if map.is_water(i):
			base.y = MapStyle.WATER_Y
		var rot := Basis(Vector3.UP, MapStyle.hash01(i, 90) * TAU)
		var parts: Array = _improvement_meshes[imp]
		for k in parts.size():
			var part: Dictionary = parts[k]
			var key := "%s#%d" % [imp, k]
			if not per_part.has(key):
				per_part[key] = []
			for local in part["transforms"]:
				var t: Transform3D = local
				var world := Transform3D(rot * t.basis, base + rot * t.origin + Vector3(-0.1, 0, -0.05))
				var col: Color = part["color"]
				if map.pillaged[i] == 1:
					col = col.darkened(0.6)   # разграблено
				per_part[key].append([world, col, _custom(i)])
	for imp in _improvement_meshes:
		var parts: Array = _improvement_meshes[imp]
		for k in parts.size():
			var key := "%s#%d" % [imp, k]
			var items: Array = per_part.get(key, [])
			var mm := _new_multimesh(parts[k]["mesh"], items.size())
			_fill(mm, items)
			_set_layer("imp_" + key, mm, _feature_mat)


## Дороги: полосы между центрами соседних клеток с дорогой (и «пятачок» в клетке).
func refresh_roads() -> void:
	var map := game.state.map
	var grid := map.grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var col := Color("9c8463")
	for i in map.size():
		if map.road[i] == 0:
			continue
		var c2 := grid.world_position(i, MapStyle.HEX_SIZE)
		var h := MapStyle.tile_height(map, i) + 0.02
		var uv := TerrainMeshBuilder.tile_uv(grid, i)
		var lvl_col := col.lightened(0.08 * map.road[i])
		var links := 0
		for d in 6:
			var nb := grid.neighbor(i, d)
			if nb < 0 or map.road[nb] == 0:
				continue
			links += 1
			# Половина отрезка до середины ребра — вторую половину нарисует сосед.
			var mid := c2 + (HexGrid.corner_offset(d, MapStyle.HEX_SIZE) + HexGrid.corner_offset((d + 1) % 6, MapStyle.HEX_SIZE)) * 0.5
			var along := (mid - c2).normalized()
			var across := Vector2(-along.y, along.x) * 0.07
			var pts := [Vector3(c2.x + across.x, h, c2.y + across.y), Vector3(mid.x + across.x, h, mid.y + across.y),
				Vector3(mid.x - across.x, h, mid.y - across.y), Vector3(c2.x - across.x, h, c2.y - across.y)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(lvl_col)
				st.set_uv2(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[idx])
			count += 1
		# Пятачок в центре клетки.
		for kk in 6:
			var a := c2 + HexGrid.corner_offset(kk, 0.12)
			var b := c2 + HexGrid.corner_offset((kk + 1) % 6, 0.12)
			for p in [Vector3(c2.x, h, c2.y), Vector3(a.x, h, a.y), Vector3(b.x, h, b.y)]:
				st.set_color(lvl_col)
				st.set_uv2(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
		count += 1
	_set_layer("roads", st.commit() if count > 0 else null, _river_mat)


## Границы держав: цветная полоса вдоль рёбер, где сосед не принадлежит той же державе.
func refresh_borders() -> void:
	var map := game.state.map
	var grid := map.grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for i in map.size():
		var cid := map.owner_city[i]
		if cid < 0:
			continue
		var owner_id := game.state.city(cid).owner
		var col := game.state.player(owner_id).color
		var c2 := grid.world_position(i, MapStyle.HEX_SIZE)
		var h := maxf(MapStyle.tile_height(map, i), MapStyle.WATER_Y) + 0.03
		var uv := TerrainMeshBuilder.tile_uv(grid, i)
		for d in 6:
			var nb := grid.neighbor(i, d)
			var other := -1
			if nb >= 0 and map.owner_city[nb] >= 0:
				other = game.state.city(map.owner_city[nb]).owner
			if other == owner_id:
				continue
			var a := c2 + HexGrid.corner_offset(d, MapStyle.HEX_SIZE)
			var b := c2 + HexGrid.corner_offset((d + 1) % 6, MapStyle.HEX_SIZE)
			var ai := c2 + (a - c2) * 0.84
			var bi := c2 + (b - c2) * 0.84
			var pts := [Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(bi.x, h, bi.y), Vector3(ai.x, h, ai.y)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(col.r, col.g, col.b, 0.9))
				st.set_uv2(uv)
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[idx])
			count += 1
	_set_layer("borders", st.commit() if count > 0 else null, _border_mat)


func _fill(mm: MultiMesh, items: Array) -> void:
	for k in items.size():
		mm.set_instance_transform(k, items[k][0])
		mm.set_instance_color(k, items[k][1])
		mm.set_instance_custom_data(k, items[k][2])


# --- Туман войны ----------------------------------------------------------------------

func refresh_fog(player: Player) -> void:
	viewer = player
	var map := game.state.map
	for i in map.size():
		var v := 0.0
		if player.is_visible(i):
			v = 1.0
		elif player.is_revealed(i):
			v = 0.5
		fog_image.set_pixel(map.grid.col_of(i), map.grid.row_of(i), Color(v, 0, 0, 1))
	fog_texture.update(fog_image)


func set_reveal_all(value: bool) -> void:
	reveal_all = value
	for m in _materials:
		m.set_shader_parameter("reveal_all", value)


# --- Координаты -------------------------------------------------------------------------

## Позиция центра клетки на верхней грани, в копии, ближайшей к точке near_x.
func tile_world(i: int, near_x: float = INF) -> Vector3:
	var p := _tile_pos(i)
	if map_is_water(i):
		p.y = MapStyle.WATER_Y
	if not reveal_all and viewer != null and not viewer.is_revealed(i):
		p.y = 0.02   # неразведанное — ровная пелена, рельеф не выдаём
	if near_x != INF:
		p.x += round((near_x - p.x) / world_width) * world_width
	return p


func map_is_water(i: int) -> bool:
	return game.state.map.is_water(i)


## Клетка под лучом камеры (с учётом высоты террас). -1 — мимо карты.
func pick_tile(origin: Vector3, dir: Vector3) -> int:
	if absf(dir.y) < 1e-4:
		return -1
	var grid := game.state.map.grid
	var y := 0.0
	var tile := -1
	# Несколько итераций: пересекаем плоскость, уточняем по высоте найденной клетки.
	for _iter in 3:
		var t := (y - origin.y) / dir.y
		if t < 0:
			return -1
		var hit := origin + dir * t
		var x := fposmod(hit.x, world_width)
		tile = grid.index_at_world(x, hit.z, MapStyle.HEX_SIZE)
		if tile < 0:
			return -1
		var ny := tile_world(tile).y
		if absf(ny - y) < 0.01:
			break
		y = ny
	return tile
