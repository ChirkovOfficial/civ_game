class_name ImprovementMeshes
extends RefCounted
## Временные модели улучшений из примитивов. Каждое улучшение — набор деталей:
## {"mesh", "color", "transforms": [локальные Transform3D относительно центра клетки]}.


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, height: float, seg: int = 6) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = seg
	m.rings = 1
	return m


static func _sphere(r: float, seg: int = 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = 3
	return m


static func _at(x: float, y: float, z: float, rot_y: float = 0.0, s: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y).scaled(s), Vector3(x, y, z))


static func build_all() -> Dictionary:
	var d := {}
	# Ферма: грядки.
	var rows: Array = []
	for k in 4:
		rows.append(_at(0.0, 0.015, -0.27 + k * 0.18))
	d["FARM"] = [
		{"mesh": _box(Vector3(0.62, 0.03, 0.1)), "color": Color("d9b856"), "transforms": rows},
		{"mesh": _box(Vector3(0.66, 0.012, 0.66)), "color": Color("8c7a45"), "transforms": [_at(0, 0.005, -0.0)]},
	]
	# Рудник: вход в штольню и порода.
	d["MINE"] = [
		{"mesh": _box(Vector3(0.22, 0.2, 0.06)), "color": Color("3a3430"), "transforms": [_at(0.0, 0.1, 0.0)]},
		{"mesh": _sphere(0.09), "color": Color("8a7f75"),
		 "transforms": [_at(0.2, 0.06, 0.1), _at(-0.18, 0.05, 0.12), _at(0.05, 0.05, 0.22)]},
	]
	d["QUARRY"] = [
		{"mesh": _box(Vector3(0.14, 0.12, 0.14)), "color": Color("c9c4bb"),
		 "transforms": [_at(0, 0.06, 0), _at(0.18, 0.06, 0.08, 0.4), _at(-0.1, 0.06, 0.2, 0.9), _at(0.06, 0.18, 0.04, 0.2)]},
	]
	# Плантация: ряды кустов.
	var bushes: Array = []
	for x in 3:
		for z in 2:
			bushes.append(_at(-0.2 + x * 0.2, 0.08, -0.1 + z * 0.22))
	d["PLANTATION"] = [{"mesh": _sphere(0.085), "color": Color("4f8a3c"), "transforms": bushes}]
	d["CAMP"] = [
		{"mesh": _cyl(0.0, 0.16, 0.26, 5), "color": Color("b08a5a"), "transforms": [_at(0, 0.13, 0), _at(0.25, 0.1, 0.12, 0, Vector3.ONE * 0.75)]},
	]
	# Пастбище: изгородь из столбиков.
	var posts: Array = []
	for k in 10:
		var a := TAU * k / 10.0
		posts.append(_at(cos(a) * 0.3, 0.06, sin(a) * 0.3))
	d["PASTURE"] = [{"mesh": _cyl(0.018, 0.018, 0.12, 4), "color": Color("7a5a3a"), "transforms": posts}]
	d["FISHING_BOATS"] = [
		{"mesh": _box(Vector3(0.3, 0.07, 0.12)), "color": Color("8a5a35"), "transforms": [_at(0, 0.04, 0), _at(0.28, 0.04, 0.22, 0.6)]},
		{"mesh": _box(Vector3(0.02, 0.2, 0.12)), "color": Color("f2ede0"), "transforms": [_at(0.02, 0.16, 0), _at(0.29, 0.16, 0.22, 0.6)]},
	]
	d["LUMBER_MILL"] = [
		{"mesh": _box(Vector3(0.26, 0.16, 0.2)), "color": Color("9a6a40"), "transforms": [_at(0, 0.08, 0)]},
		{"mesh": _cyl(0.04, 0.04, 0.34, 6), "color": Color("c49a6a"),
		 "transforms": [Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.2, 0.05, 0.16))]},
	]
	d["OIL_WELL"] = [{"mesh": _cyl(0.02, 0.08, 0.4, 4), "color": Color("2a2a2e"), "transforms": [_at(0, 0.2, 0)]}]
	# Форт: частокол по кругу.
	var stakes: Array = []
	for k in 16:
		var a := TAU * k / 16.0
		stakes.append(_at(cos(a) * 0.42 + 0.1, 0.09, sin(a) * 0.42 + 0.05))
	d["FORT"] = [{"mesh": _cyl(0.03, 0.035, 0.18, 4), "color": Color("8a6440"), "transforms": stakes}]
	# Лагерь варваров: тёмные шатры и шест с флагом.
	d["BARBARIAN_CAMP"] = [
		{"mesh": _cyl(0.0, 0.17, 0.3, 5), "color": Color("5a2a24"), "transforms": [_at(0, 0.15, 0), _at(0.28, 0.12, 0.15, 0, Vector3.ONE * 0.8), _at(-0.2, 0.12, 0.22, 0, Vector3.ONE * 0.75)]},
		{"mesh": _box(Vector3(0.02, 0.5, 0.02)), "color": Color("3a2a1a"), "transforms": [_at(0.12, 0.25, -0.2)]},
		{"mesh": _box(Vector3(0.18, 0.1, 0.01)), "color": Color("b8241c"), "transforms": [_at(0.21, 0.44, -0.2)]},
	]
	# Племенное поселение: круглые хижины.
	d["TRIBAL_VILLAGE"] = [
		{"mesh": _sphere(0.11, 7), "color": Color("b59a6a"), "transforms": [_at(0, 0.05, 0, 0, Vector3(1, 0.8, 1)), _at(0.24, 0.05, 0.12, 0, Vector3(1, 0.8, 1)), _at(-0.15, 0.05, 0.22, 0, Vector3(0.9, 0.7, 0.9))]},
		{"mesh": _cyl(0.0, 0.13, 0.12, 7), "color": Color("8a6a3a"), "transforms": [_at(0, 0.16, 0), _at(0.24, 0.16, 0.12), _at(-0.15, 0.14, 0.22, 0, Vector3.ONE * 0.9)]},
	]
	return d
