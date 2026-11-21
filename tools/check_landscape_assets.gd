extends SceneTree
## Проверка экспортированных glTF: импорт, материалы, UV, отсутствие смещения из галереи.
var errors: PackedStringArray = []

func _init() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/landscape/catalog.json"))
	var count := 0
	for asset in catalog["assets"]:
		var path: String = "res://art/landscape/" + str(asset["file"])
		var packed := load(path) as PackedScene
		if packed == null:
			errors.append("Не импортирован " + path)
			continue
		var instance := packed.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect(instance, meshes)
		if meshes.is_empty():
			errors.append("Пустая модель " + path)
		for object in meshes:
			if object.position.length() > 0.01:
				errors.append("Смещение галереи попало в экспорт " + path)
			var bounds := object.mesh.get_aabb()
			if bounds.size.y <= 0 or bounds.size.y > float(asset["bounds_blender_z_up"]["max"][2]) + 0.05:
				errors.append("Неверная вертикальная ось или масштаб " + path)
			var textured := false
			for surface in object.mesh.get_surface_count():
				var mat := object.mesh.surface_get_material(surface) as StandardMaterial3D
				if mat == null:
					errors.append("Нет PBR материала " + path)
				elif mat.albedo_texture != null:
					textured = true
				var arrays := object.mesh.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_TEX_UV] == null:
					errors.append("Нет UV " + path)
			if not textured:
				errors.append("Нет текстуры " + path)
		instance.free()
		count += 1
	for error in errors:
		push_error(error)
	print("Моделей проверено: %d, ошибок: %d" % [count, errors.size()])
	quit(0 if errors.is_empty() and count == 25 else 1)

func _collect(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect(child, result)
