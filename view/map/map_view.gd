class_name MapView
extends Node3D
## Отрисовка карты: террасы, вода, реки, горы, леса, маркеры ресурсов, туман войны.
## Карта зациклена: рисуется в трёх копиях (слева, по центру, справа), камера
## «перескакивает» через шов незаметно.

const TERRAIN_SHADER := preload("res://view/map/shaders/terrain.gdshader")
const FEATURE_SHADER := preload("res://view/map/shaders/feature.gdshader")
const OVERLAY_SHADER := preload("res://view/map/shaders/overlay.gdshader")

var game: Game
var world_width: float
var fog_image: Image
var fog_texture: ImageTexture
var reveal_all := false
## Игрок, глазами которого показана карта (для высот неразведанных клеток).
var viewer: Player = null

var _materials: Array[ShaderMaterial] = []
var _resource_mm: MultiMesh
var _resource_mat: ShaderMaterial
var _copies: Array[Node3D] = []


func build(g: Game) -> void:
	game = g
	for c in get_children():
		c.queue_free()
	_copies.clear()
	_materials.clear()
	var map := game.state.map
	world_width = map.grid.world_width(MapStyle.HEX_SIZE)
	fog_image = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	fog_image.fill(Color.BLACK)
	fog_texture = ImageTexture.create_from_image(fog_image)

	var terrain_mat := _make_material(TERRAIN_SHADER)
	var feature_mat := _make_material(FEATURE_SHADER)
	var water_mat := _make_material(OVERLAY_SHADER)
	water_mat.render_priority = 1
	var river_mat := _make_material(OVERLAY_SHADER)
	river_mat.render_priority = 2
	_resource_mat = feature_mat

	var terrain_mesh := TerrainMeshBuilder.build_terrain(map)
	var water_mesh := TerrainMeshBuilder.build_water(map)
	var river_mesh := TerrainMeshBuilder.build_rivers(map)
	var mountains := _build_mountains(map)
	var trees := _build_trees(map)
	_resource_mm = _build_resource_markers()

	for k in [-1, 0, 1]:
		var copy := Node3D.new()
		copy.name = "Copy%d" % (k + 1)
		copy.position.x = k * world_width
		add_child(copy)
		_copies.append(copy)
		_add_mesh(copy, terrain_mesh, terrain_mat)
		_add_mesh(copy, water_mesh, water_mat)
		_add_mesh(copy, river_mesh, river_mat)
		for mm in [mountains, trees[0], trees[1], _resource_mm]:
			if mm != null and mm.instance_count > 0:
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = feature_mat
				copy.add_child(mmi)


func _make_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("fog_tex", fog_texture)
	m.set_shader_parameter("reveal_all", reveal_all)
	_materials.append(m)
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)


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


## Возвращает [кроны, стволы].
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


func _build_resource_markers() -> MultiMesh:
	var gem := SphereMesh.new()
	gem.radius = 0.09
	gem.height = 0.2
	gem.radial_segments = 4
	gem.rings = 2
	var mm := _new_multimesh(gem, 0)
	return mm


## Маркеры ресурсов зависят от технологий игрока (стратегические скрыты).
func refresh_resources(player: Player) -> void:
	if _resource_mm == null:
		return
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
	_resource_mm.instance_count = items.size()
	_fill(_resource_mm, items)
	# Пустой MultiMesh мог не попасть в копии при сборке — добавим при необходимости.
	if items.size() > 0:
		for copy in _copies:
			var has := false
			for ch in copy.get_children():
				if ch is MultiMeshInstance3D and ch.multimesh == _resource_mm:
					has = true
			if not has:
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = _resource_mm
				mmi.material_override = _resource_mat
				copy.add_child(mmi)


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
