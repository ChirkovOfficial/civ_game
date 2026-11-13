class_name Game
extends RefCounted
## Партия: данные + состояние + применение действий (ГДД 25.1 п.1).
##
## Интерфейс и ИИ меняют мир только через apply_action(). Каждое действие
## возвращает список событий (словари с полем "type"), которые слушает
## отображение. Ядро не знает ничего о рендеринге и вводе.

signal events_emitted(events: Array)

var data: GameData
var state: GameState


func _init(game_data: GameData, game_state: GameState = null) -> void:
	data = game_data
	state = game_state


# --- Создание партии --------------------------------------------------------------

## settings: map_size, map_type, speed, seed (int), num_civs, humans (массив id игроков-людей).
static func new_game(game_data: GameData, settings: Dictionary) -> Game:
	var s := GameState.new()
	var seed_value: int = int(settings.get("seed", 1))
	s.rng = GameRng.new(seed_value)
	var size_def := game_data.map_size(settings.get("map_size", "STANDARD"))
	var num_civs: int = int(settings.get("num_civs", size_def.get("civs", 8)))
	s.settings = {
		"map_size": settings.get("map_size", "STANDARD"),
		"map_type": settings.get("map_type", "CONTINENTS"),
		"speed": settings.get("speed", "STANDARD"),
		"seed": str(seed_value),
		"num_civs": num_civs,
	}
	var gen := MapGenerator.new(game_data, s.rng)
	s.map = gen.generate(s.settings)
	s.start_positions = gen.start_positions
	var humans: Array = settings.get("humans", [0])
	var colors: Array = game_data.setup.get("player_colors", [])
	var game := Game.new(game_data, s)
	for pid in mini(num_civs, s.start_positions.size()):
		var p := Player.new()
		p.id = pid
		p.name = "Держава %d" % (pid + 1)
		p.color = Color.html(colors[pid % colors.size()]) if not colors.is_empty() else Color.WHITE
		p.is_ai = not humans.has(pid)
		p.init_fog(s.map.size())
		s.players.append(p)
		game._spawn_start_units(pid, s.start_positions[pid])
	for p in s.players:
		Visibility.recompute(game, p.id)
	s.current_player = 0
	game._begin_player_turn(0, [])
	return game


func _spawn_start_units(pid: int, start: int) -> void:
	var grid := state.map.grid
	var spots: Array[int] = [start]
	# Остальные юниты — на ближайшие свободные проходимые клетки той же суши.
	for t in grid.tiles_in_radius(start, 2):
		if t != start and state.map.is_land(t) and not state.map.is_mountain(t) \
				and state.map.continent[t] == state.map.continent[start]:
			spots.append(t)
	# Каждый юнит — на ближайшую клетку, где его слой (боевой/гражданский) свободен.
	for type in data.const_value("start_units", []):
		var layer_name := Movement.layer(self, type)
		var tile := start
		for spot in spots:
			if not _layer_taken(spot, layer_name):
				tile = spot
				break
		var u := state.add_unit(pid, type, tile)
		u.moves_left = Movement.max_moves(self, u)
		u.charges = int(data.unit_def(type).get("charges", 0))


func _layer_taken(tile: int, layer_name: String) -> bool:
	for u in state.units_at(tile):
		if Movement.layer(self, u.type) == layer_name:
			return true
	return false


# --- Действия ---------------------------------------------------------------------

## Применяет действие текущего игрока. Возвращает события; при ошибке — одно
## событие {"type": "error", "message": ...}, состояние не меняется.
func apply_action(action: Dictionary) -> Array:
	var events: Array = []
	match action.get("type", ""):
		"move_unit":
			_act_move_unit(action, events)
		"skip_unit":
			_act_skip_unit(action, events)
		"cancel_orders":
			var u := _own_unit(action, events)
			if u != null:
				u.orders = {}
		"end_turn":
			_act_end_turn(events)
		_:
			events.append(_error("Неизвестное действие: %s" % action.get("type", "")))
	if not events.is_empty():
		events_emitted.emit(events)
	return events


func _error(msg: String) -> Dictionary:
	return {"type": "error", "message": msg}


func _own_unit(action: Dictionary, events: Array) -> Unit:
	var u := state.unit(int(action.get("unit", -1)))
	if u == null:
		events.append(_error("Юнит не найден"))
		return null
	if u.owner != state.current_player:
		events.append(_error("Это не ваш юнит"))
		return null
	return u


func _act_skip_unit(action: Dictionary, events: Array) -> void:
	var u := _own_unit(action, events)
	if u == null:
		return
	u.moves_left = 0.0
	u.orders = {}
	events.append({"type": "unit_updated", "unit": u.id})


func _act_move_unit(action: Dictionary, events: Array) -> void:
	var u := _own_unit(action, events)
	if u == null:
		return
	var target := int(action.get("target", -1))
	var path := Pathfinder.find_path(self, u, target)
	if path.is_empty():
		events.append(_error("Туда нельзя пройти"))
		return
	u.orders = {"type": "move", "target": target}
	_continue_move(u, events)


## Продвигает юнит по приказу «move» столько, сколько позволяют ОД в этот ход.
## Путь пересчитывается на каждом шаге: туман мог открыть препятствия.
func _continue_move(u: Unit, events: Array) -> void:
	if u.orders.get("type", "") != "move":
		return
	var target: int = u.orders["target"]
	while u.moves_left > 0.0 and u.tile != target:
		var path := Pathfinder.find_path(self, u, target)
		if path.is_empty():
			u.orders = {}
			events.append({"type": "unit_blocked", "unit": u.id})
			return
		var next: Pathfinder.Step = path[0]
		if next.turn > 0:
			return   # дальше — в следующий ход
		# Проверка по фактическому состоянию мира (а не по знаниям игрока).
		var final := path.size() == 1 or (path.size() > 1 and path[1].turn > 0)
		if not Movement.occupancy_allows(self, u, next.tile, final):
			u.orders = {}
			events.append({"type": "unit_blocked", "unit": u.id})
			return
		var left := Movement.moves_after_step(self, u, u.tile, next.tile, u.moves_left)
		if left < 0.0:
			return
		var from := u.tile
		u.tile = next.tile
		u.moves_left = left
		u.acted = true
		u.fortify_turns = 0
		events.append({"type": "unit_moved", "unit": u.id, "from": from, "to": u.tile})
		if Visibility.recompute(self, u.owner):
			events.append({"type": "fog_changed", "player": u.owner})
	if u.tile == target:
		u.orders = {}


func _act_end_turn(events: Array) -> void:
	var finished := state.current_player
	events.append({"type": "turn_ended", "player": finished})
	var next := _next_alive_player(finished)
	if next <= finished:
		state.turn += 1
		events.append({"type": "new_round", "turn": state.turn})
	state.current_player = next
	_begin_player_turn(next, events)
	# ИИ ходит сразу; управление возвращается, когда очередь дойдёт до человека.
	var guard := 0
	while state.player(state.current_player).is_ai and guard < state.players.size():
		guard += 1
		AIPlayer.take_turn(self, state.current_player)
		var ai_id := state.current_player
		events.append({"type": "turn_ended", "player": ai_id})
		var n2 := _next_alive_player(ai_id)
		if n2 <= ai_id:
			state.turn += 1
			events.append({"type": "new_round", "turn": state.turn})
		state.current_player = n2
		_begin_player_turn(n2, events)


func _next_alive_player(from: int) -> int:
	var n := state.players.size()
	for k in range(1, n + 1):
		var cand := (from + k) % n
		if state.players[cand].alive:
			return cand
	return from


## Начало хода игрока (ГДД 2, упрощённо для M1): восстановление ОД,
## исполнение постоянных приказов, пересчёт видимости.
func _begin_player_turn(pid: int, events: Array) -> void:
	for u in state.units_of(pid):
		u.moves_left = Movement.max_moves(self, u)
		u.acted = false
	for u in state.units_of(pid):
		_continue_move(u, events)
	Visibility.recompute(self, pid)
	events.append({"type": "turn_started", "player": pid, "turn": state.turn})


# --- Запросы для интерфейса ------------------------------------------------------------

## Юниты текущего игрока, которым нужен приказ (есть ОД и нет постоянного приказа).
func units_needing_orders(pid: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in state.units_of(pid):
		if u.moves_left > 0.0 and u.orders.is_empty():
			result.append(u)
	return result
