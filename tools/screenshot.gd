extends SceneTree
## Снимок экрана главной сцены (для проверки графики без окна):
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png [seed] [reveal] [zoom]
## Используется Claude для проверки изменений в отображении.

var _frames := 0
var _out := "screenshot.png"
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var scene: PackedScene = load("res://view/main.tscn")
	_main = scene.instantiate()
	if args.size() > 1:
		_main.fixed_seed = int(args[1])
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main != null and _frames >= 5:
		_main.set_process(false)   # не перерисовывать путь от «мыши»
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 2:
		if args.size() > 2 and args[2] == "reveal":
			_main._set_reveal(true)
		if args.size() > 3:
			_main.camera_rig.target_distance = float(args[3])
			_main.camera_rig.distance = float(args[3])
			_main.camera_rig._update_camera()
	if _frames == 5 and args.size() > 4 and args[4] == "path":
		# Показать предпросмотр пути выбранного юнита к клетке в 4 шагах на восток.
		var u: Unit = _main.selected
		if u != null:
			var t := u.tile
			for k in 4:
				var n: int = _main.game.state.map.grid.neighbor(t, 0)
				if n >= 0:
					t = n
			_main.overlay.show_path(Pathfinder.find_path(_main.game, u, t), _main.camera_rig.position.x)
	if _frames == 30:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("Снимок сохранён: ", _out)
		return true
	return false
