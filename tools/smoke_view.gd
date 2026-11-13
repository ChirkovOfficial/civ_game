extends SceneTree
## Дымовой тест интерфейса: запускает главную сцену, двигает юнит, жмёт «конец хода».
##   xvfb-run -a godot --path . -s tools/smoke_view.gd
## Ошибки скриптов видны в выводе.

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://view/main.tscn").instantiate()
	_main.fixed_seed = 77
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var u: Unit = _main.selected
		var grid: HexGrid = _main.game.state.map.grid
		var target := u.tile
		for k in 5:
			var n := grid.neighbor(target, (k % 2) * 5)
			if n >= 0:
				target = n
		_main._move_selected(target)
	if _frames > 3 and _frames < 13:
		_main._end_turn()
		_main._set_reveal(_frames % 2 == 0)
	if _frames == 14:
		_main._new_game()
	if _frames == 16:
		print("Дымовой тест: ход %d, юнитов %d" % [_main.game.state.turn, _main.game.state.units.size()])
		return true
	return false
