extends TestCase
const Flags := preload("res://view/map/nature_flags.gd")

func test_atlas_covers_every_resource_and_feature() -> void:
	var data := GameData.get_default()
	for id in data.resource_ids:
		check(Flags.index(id) >= 0, "Нужен флаг ресурса " + id)
	for id in data.features:
		check(Flags.index(id) >= 0, "Нужен флаг особенности " + id)
	check_eq(Flags.regions().size(), 60)
	for rect in Flags.regions():
		check(rect.x >= 0 and rect.y >= 0 and rect.x + rect.z <= 1.001 and rect.y + rect.w <= 1.001,
			"Область внутри атласа")

func test_flags_respect_exploration_technology_and_removed_feature() -> void:
	var g := blank_game(8, 6)
	g.state.map.feature[10] = "WOODS"
	g.state.map.resource[10] = "IRON"
	var player := g.state.player(0)
	var view := MapView.new()
	view.build(g)
	view.refresh_resources(player)
	var layer: MultiMeshInstance3D = view._layers["nature_flags"][1]
	check_eq(layer.multimesh.instance_count, 0, "Неразведанный тайл скрыт")
	player.revealed[10] = 1
	view.refresh_resources(player)
	check_eq(layer.multimesh.instance_count, 1, "Виден лес, железо скрыто до технологии")
	player.known_techs["BRONZE_WORKING"] = true
	view.refresh_resources(player)
	check_eq(layer.multimesh.instance_count, 2, "Особенность и ресурс показаны отдельно")
	g.state.map.feature[10] = ""
	view.refresh_geometry({"terrain": true})
	view.refresh_resources(player)
	check_eq(layer.multimesh.instance_count, 1, "Флаг вырубленного леса пропал")
	check(not view._layers.has("crowns") and not view._layers.has("forest_sprites") \
		and not view._layers.has("resources"), "Старые природные объекты отключены")
	check(view._layers.has("mountains"), "Горный слой сохранён")
	view.free()
