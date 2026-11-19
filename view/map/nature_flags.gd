extends RefCounted
## Соответствие ресурсов и особенностей фактическим областям сгенерированного листа.
static var _entries: Array = []

static func entries() -> Array:
	if _entries.is_empty():
		var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/map_flags/atlas.json"))
		_entries = parsed["entries"]
	return _entries

static func index(id: String) -> int:
	var list := entries()
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1

static func regions() -> Array[Vector4]:
	var result: Array[Vector4] = []
	for entry in entries():
		var rect: Array = entry["region"]
		result.append(Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	return result
