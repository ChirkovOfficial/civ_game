class_name OverlayView
extends Node3D
## Подсветка клетки под курсором и предпросмотр пути с номерами ходов.

var map_view: MapView
var _hover: MeshInstance3D
var _path_root: Node3D
var _dot_mesh: SphereMesh
var _dot_mat: StandardMaterial3D
var _dot_mat_far: StandardMaterial3D


func setup(mv: MapView) -> void:
	map_view = mv
	for c in get_children():
		c.queue_free()
	_hover = MeshInstance3D.new()
	_hover.mesh = _hex_outline_mesh()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1, 1, 1, 0.85)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover.material_override = hm
	_hover.visible = false
	add_child(_hover)
	_path_root = Node3D.new()
	add_child(_path_root)
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = 0.06
	_dot_mesh.height = 0.12
	_dot_mesh.radial_segments = 8
	_dot_mesh.rings = 4
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = Color(1.0, 0.95, 0.6)
	_dot_mat_far = _dot_mat.duplicate()
	_dot_mat_far.albedo_color = Color(0.75, 0.85, 1.0)


func _hex_outline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := 0.86
	for k in 6:
		var a := HexGrid.corner_offset(k, MapStyle.HEX_SIZE)
		var b := HexGrid.corner_offset((k + 1) % 6, MapStyle.HEX_SIZE)
		var ai := a * inner
		var bi := b * inner
		for p in [a, b, bi, a, bi, ai]:
			st.add_vertex(Vector3(p.x, 0, p.y))
	return st.commit()


func show_hover(tile: int, cam_x: float) -> void:
	if tile < 0:
		_hover.visible = false
		return
	_hover.visible = true
	_hover.position = map_view.tile_world(tile, cam_x) + Vector3(0, 0.025, 0)


var _city_root: Node3D = null


## Режим города: отмечает обрабатываемые клетки и цены клеток, доступных для покупки.
func show_city(game: Game, city: City, cam_x: float) -> void:
	clear_city()
	_city_root = Node3D.new()
	add_child(_city_root)
	var worker := SphereMesh.new()
	worker.radius = 0.09
	worker.height = 0.18
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(1.0, 0.95, 0.75)
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for t in city.worked_tiles:
		var mi := MeshInstance3D.new()
		mi.mesh = worker
		mi.material_override = wm
		mi.position = map_view.tile_world(t, cam_x) + Vector3(-0.3, 0.25, -0.3)
		_city_root.add_child(mi)
	if city.owner != game.state.current_player:
		return
	var treasury := game.state.player(city.owner).treasury
	for t in game.state.map.grid.tiles_in_radius(city.tile, int(game.data.const_value("city_work_radius", 3))):
		if game.state.map.owner_city[t] >= 0:
			continue
		var adjacent := false
		for nb in game.state.map.grid.neighbors(t):
			if game.state.map.owner_city[nb] == city.id:
				adjacent = true
		if not adjacent:
			continue
		var cost := CityRules.tile_purchase_cost(game, city, t)
		var label := Label3D.new()
		label.text = "%d" % cost
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.004
		label.outline_size = 10
		label.modulate = Color(1.0, 0.86, 0.35) if treasury >= cost else Color(0.7, 0.7, 0.7)
		label.outline_modulate = Color(0.1, 0.08, 0.02)
		label.no_depth_test = true
		label.position = map_view.tile_world(t, cam_x) + Vector3(0, 0.3, 0)
		_city_root.add_child(label)


func clear_city() -> void:
	if _city_root != null:
		_city_root.queue_free()
		_city_root = null


func clear_path() -> void:
	for c in _path_root.get_children():
		c.queue_free()


func show_path(path: Array, cam_x: float) -> void:
	clear_path()
	for k in path.size():
		var step: Pathfinder.Step = path[k]
		var p := map_view.tile_world(step.tile, cam_x) + Vector3(0, 0.12, 0)
		var dot := MeshInstance3D.new()
		dot.mesh = _dot_mesh
		dot.material_override = _dot_mat if step.turn == 0 else _dot_mat_far
		dot.position = p
		_path_root.add_child(dot)
		# Номер хода — там, где юнит закончит ход, и в конечной точке.
		var ends_turn: bool = k == path.size() - 1 or path[k + 1].turn != step.turn
		if ends_turn:
			var label := Label3D.new()
			label.text = str(step.turn + 1)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 64
			label.pixel_size = 0.004
			label.outline_size = 12
			label.modulate = Color(1, 1, 1)
			label.outline_modulate = Color(0.1, 0.1, 0.15)
			label.no_depth_test = true
			label.position = p + Vector3(0, 0.22, 0)
			_path_root.add_child(label)
