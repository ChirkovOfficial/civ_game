extends SceneTree
## Компилирует все скрипты проекта и сообщает об ошибках:
##   godot --headless --path . -s tools/check_scripts.gd


func _init() -> void:
	var bad := 0
	for path in _collect("res://"):
		var s = load(path)
		if s == null or (s is GDScript and not s.can_instantiate() and not path.contains("tools/")):
			print("ОШИБКА: ", path)
			bad += 1
	print("Проверено, ошибок: %d" % bad)
	quit(1 if bad > 0 else 0)


func _collect(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if not d.begins_with("."):
			out.append_array(_collect(dir_path.path_join(d)))
	return out
