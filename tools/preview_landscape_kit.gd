extends SceneTree
## Снимок экспортированных моделей в Godot; -- путь.png. Требует графический рендер.
var _frames := 0

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	root.size = Vector2i(1500, 850)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("26343d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5e0dd")
	environment.environment.ambient_light_energy = 0.35
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	stage.add_child(light)
	var ids := ["forest_mixed_tile_a", "jungle_tile_a", "mountain_peak_a"]
	for i in ids.size():
		var model: Node3D = load("res://art/landscape/models/%s.gltf" % ids[i]).instantiate()
		model.position.x = (i - 1) * 2.15
		stage.add_child(model)
		var base := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.98
		cylinder.bottom_radius = 0.98
		cylinder.height = 0.025
		cylinder.radial_segments = 6
		base.mesh = cylinder
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("566650")
		mat.roughness = 1.0
		base.material_override = mat
		base.position = Vector3(model.position.x, -0.02, 0)
		stage.add_child(base)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.2
	stage.add_child(camera)
	camera.position = Vector3(0, 4.1, 5.4)
	camera.look_at(Vector3(0, 0.2, 0), Vector3.UP)
	camera.current = true

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var args := OS.get_cmdline_user_args()
		var destination := args[0] if not args.is_empty() else "res://art/landscape/previews/godot_export_preview.png"
		var error := root.get_texture().get_image().save_png(destination)
		print("Превью glTF: %s, код %d" % [destination, error])
		quit(0 if error == OK else 1)
	return false
