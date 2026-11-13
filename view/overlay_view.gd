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
