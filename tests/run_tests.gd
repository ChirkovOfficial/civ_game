extends SceneTree
## Запуск всех тестов без окна:
##   godot --headless --path . -s tests/run_tests.gd
## Код возврата 0 — все тесты прошли.


func _init() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var filter := OS.get_environment("TEST_FILTER")
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if m["name"].begins_with("test_"):
				methods.append(m["name"])
		methods.sort()
		for m in methods:
			if filter != "" and not (f + ":" + m).contains(filter):
				continue
			var inst: TestCase = script.new()
			inst.current_test = f.get_basename() + "." + m
			var t0 := Time.get_ticks_msec()
			inst.call(m)
			var dt := Time.get_ticks_msec() - t0
			total += 1
			if inst.failures.is_empty():
				print("  ok   %s (%d мс)" % [inst.current_test, dt])
			else:
				failed += 1
				print("  FAIL %s" % inst.current_test)
				for msg in inst.failures:
					print("       ", msg)
	print("\nТестов: %d, провалено: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
