extends TestCase

func test_all_biomes_and_relief_share_one_plane() -> void:
	var g := blank_game(8, 6)
	var map := g.state.map
	for tile in map.size():
		map.terrain[tile] = MapStyle.BIOME_ORDER[tile % MapStyle.BIOME_ORDER.size()]
		map.relief[tile] = tile % 3
	var before := g.state.to_dict()
	var mesh := TerrainMeshBuilder.build_terrain(map)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check_eq(vertices.size(), map.size() * 18, "У тайлов только верхние грани, без вертикальных стенок")
	for index in vertices.size():
		check_near(vertices[index].y, MapStyle.H_FLAT)
		check(normals[index].distance_to(Vector3.UP) < 0.0001, "Нет нормалей вертикальных стенок")
	var water := TerrainMeshBuilder.build_water(map)
	var water_vertices: PackedVector3Array = water.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in water_vertices:
		check_near(vertex.y, MapStyle.H_FLAT, 0.00001, "Водные тайлы на общем уровне")
	check_eq(g.state.to_dict(), before, "Выравнивание не меняет игровой тип рельефа")

func test_model_anchors_and_picking_follow_the_flat_map() -> void:
	var g := blank_game(8, 6)
	for tile in g.state.map.size():
		g.state.map.terrain[tile] = MapStyle.BIOME_ORDER[tile % 8]
		g.state.map.relief[tile] = tile % 3
	var view := MapView.new()
	view.build(g)
	view.set_reveal_all(true)
	for tile in g.state.map.size():
		var point := view.tile_world(tile)
		check_near(point.y, MapStyle.H_FLAT)
		check_eq(view.pick_tile(point + Vector3.UP * 10, Vector3.DOWN), tile, "Выбор тайла работает после выравнивания")
	for key in view._layers:
		if not str(key).begins_with("landscape_"):
			continue
		var mm: MultiMesh = view._layers[key][1].multimesh
		for index in mm.instance_count:
			check_near(mm.get_instance_transform(index).origin.y, MapStyle.H_FLAT,
				0.00001, "Модели стоят на общей плоскости")
	view.free()
