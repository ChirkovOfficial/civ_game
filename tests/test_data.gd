extends TestCase


func test_data_valid() -> void:
	var errors := GameData.get_default().validate()
	for e in errors:
		check(false, e)


func test_tree_sizes() -> void:
	var d := GameData.get_default()
	var early := ["ANCIENT", "CLASSICAL", "MEDIEVAL", "RENAISSANCE"]
	check_eq(d.techs.values().filter(func(x): return x["era"] in early).size(), 32)
	check_eq(d.civics.values().filter(func(x): return x["era"] in early).size(), 24)
	check(d.techs["BANKING"]["prereqs"].has("EDUCATION"))
	check_eq(d.techs["CARTOGRAPHY"]["prereqs"], ["CELESTIAL_NAVIGATION", "EDUCATION"])
	check_eq(d.civics["THE_ENLIGHTENMENT"]["prereqs"], ["HUMANISM", "DIPLOMATIC_SERVICE"])


func test_cycle_detection() -> void:
	var tree := {"A": {"prereqs": ["B"]}, "B": {"prereqs": ["A"]}}
	check(not GameData._validate_tree(tree, "T").is_empty(), "цикл должен находиться")


func test_rng_deterministic_and_serializable() -> void:
	var a := GameRng.new(123)
	var b := GameRng.new(123)
	for i in 10:
		check_eq(a.randi_range(0, 1000), b.randi_range(0, 1000))
	var saved := a.to_dict()
	var x := a.randf()
	var c := GameRng.from_dict(JSON.parse_string(JSON.stringify(saved)))
	check_eq(c.randf(), x, "после восстановления ГПСЧ продолжает ту же последовательность")
