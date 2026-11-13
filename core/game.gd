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
	# Цивилизации по игрокам; по умолчанию у первого — базовая (Рим), у остальных — заглушки.
	var civ_ids: Array = settings.get("civs", ["ROME"])
	var colors: Array = game_data.setup.get("player_colors", [])
	var game := Game.new(game_data, s)
	for pid in mini(num_civs, s.start_positions.size()):
		var p := Player.new()
		p.id = pid
		p.civ_trait_id = civ_ids[pid] if pid < civ_ids.size() else ""
		var civ: Dictionary = game_data.civs.get(p.civ_trait_id, {})
		p.name = civ.get("name", "Держава %d" % (pid + 1))
		var col: String = civ.get("color", colors[pid % colors.size()] if not colors.is_empty() else "#ffffff")
		p.color = Color.html(col)
		p.is_ai = not humans.has(pid)
		p.treasury = float(game_data.const_value("starting_treasury", 0))
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
		"sleep_unit":
			var u := _own_unit(action, events)
			if u != null:
				u.orders = {"type": "sleep"}
				events.append({"type": "unit_updated", "unit": u.id})
		"found_city":
			_act_found_city(action, events)
		"build_improvement":
			_act_build_improvement(action, events)
		"harvest":
			var u := _own_unit(action, events)
			if u != null:
				var err := ImprovementRules.harvest(self, u, events)
				if err != "":
					events.append(_error(err))
		"set_production":
			_act_set_production(action, events)
		"purchase":
			_act_purchase(action, events)
		"buy_tile":
			_act_buy_tile(action, events)
		"set_research":
			_act_set_research(action, events)
		"end_turn":
			var blocking := EmpireRules.blocking_decisions(self, state.current_player)
			if not blocking.is_empty() and not action.get("force", false):
				events.append(_error(blocking[0]["text"]))
			else:
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


func _own_city(action: Dictionary, events: Array) -> City:
	var c := state.city(int(action.get("city", -1)))
	if c == null:
		events.append(_error("Город не найден"))
		return null
	if c.owner != state.current_player:
		events.append(_error("Это не ваш город"))
		return null
	return c


func _act_found_city(action: Dictionary, events: Array) -> void:
	var u := _own_unit(action, events)
	if u == null:
		return
	if not data.unit_def(u.type).get("abilities", []).has("FOUND_CITY"):
		events.append(_error("Этот юнит не может основать город"))
		return
	if u.moves_left <= 0.0:
		events.append(_error("Нет очков движения"))
		return
	var err := CityRules.found_city_error(self, u.owner, u.tile)
	if err != "":
		events.append(_error(err))
		return
	var tile := u.tile
	var pid := u.owner
	state.remove_unit(u.id)
	events.append({"type": "unit_consumed", "unit": u.id})
	var city := CityRules.found_city(self, pid, tile)
	events.append({"type": "city_founded", "city": city.id, "player": pid, "tile": tile})
	Visibility.recompute(self, pid)


func _act_build_improvement(action: Dictionary, events: Array) -> void:
	var u := _own_unit(action, events)
	if u == null:
		return
	var imp: String = action.get("improvement", "")
	var err := ImprovementRules.build_error(self, u, imp)
	if err == "" and u.moves_left <= 0.0:
		err = "Нет очков движения"
	if err != "":
		events.append(_error(err))
		return
	ImprovementRules.build(self, u, imp, events)


func _act_set_production(action: Dictionary, events: Array) -> void:
	var c := _own_city(action, events)
	if c == null:
		return
	var item := {"kind": str(action.get("kind", "")), "id": str(action.get("id", ""))}
	var err := CityRules.build_error(self, c, item)
	if err != "":
		events.append(_error(err))
		return
	# В очереди один объект: новый выбор заменяет текущий; прогресс прежнего сохраняется.
	c.queue = [item]
	events.append({"type": "city_updated", "city": c.id})


func _act_purchase(action: Dictionary, events: Array) -> void:
	var c := _own_city(action, events)
	if c == null:
		return
	var item := {"kind": str(action.get("kind", "")), "id": str(action.get("id", ""))}
	var err := CityRules.build_error(self, c, item)
	var p := state.player(c.owner)
	var price := CityRules.purchase_cost(self, c, item)
	if err == "" and p.treasury < price:
		err = "Не хватает золота (нужно %d)" % price
	if err != "":
		events.append(_error(err))
		return
	if not CityRules.complete_item(self, c, item, events):
		events.append(_error("Юниту негде появиться"))
		return
	p.treasury -= price
	c.progress.erase(City.item_key(item))
	if not c.queue.is_empty() and City.item_key(c.queue[0]) == City.item_key(item):
		c.queue.pop_front()
	events.append({"type": "purchased", "city": c.id, "item": item, "price": price})
	Visibility.recompute(self, c.owner)


func _act_buy_tile(action: Dictionary, events: Array) -> void:
	var c := _own_city(action, events)
	if c == null:
		return
	var tile := int(action.get("tile", -1))
	if not state.map.grid.is_valid_index(tile):
		events.append(_error("Нет такой клетки"))
		return
	var err := CityRules.tile_purchase_error(self, c, tile)
	if err != "":
		events.append(_error(err))
		return
	state.player(c.owner).treasury -= CityRules.tile_purchase_cost(self, c, tile)
	CityRules.claim_tile(self, c, tile)
	CityRules.assign_citizens(self, c)
	events.append({"type": "border_grew", "city": c.id, "tile": tile})
	Visibility.recompute(self, c.owner)


func _act_set_research(action: Dictionary, events: Array) -> void:
	var kind: String = action.get("kind", "tech")
	var err := EmpireRules.set_research(self, state.current_player, kind, str(action.get("id", "")))
	if err != "":
		events.append(_error(err))
		return
	events.append({"type": "research_changed", "player": state.current_player, "kind": kind})


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
	# Если людей нет (автоигра), за один вызов проходит не больше одного круга.
	var has_humans := false
	for p in state.players:
		if p.alive and not p.is_ai:
			has_humans = true
	var guard := 0
	while state.player(state.current_player).is_ai and guard < state.players.size():
		if not has_humans and next <= finished:
			break
		guard += 1
		AIPlayer.take_turn(self, state.current_player)
		var ai_id := state.current_player
		events.append({"type": "turn_ended", "player": ai_id})
		var n2 := _next_alive_player(ai_id)
		if n2 <= ai_id:
			state.turn += 1
			events.append({"type": "new_round", "turn": state.turn})
			if not has_humans:
				state.current_player = n2
				_begin_player_turn(n2, events)
				break
		state.current_player = n2
		_begin_player_turn(n2, events)


func _next_alive_player(from: int) -> int:
	var n := state.players.size()
	for k in range(1, n + 1):
		var cand := (from + k) % n
		if state.players[cand].alive:
			return cand
	return from


## Начало хода игрока (ГДД 2): доходы державы, города (рост, границы, производство),
## восстановление ОД, исполнение постоянных приказов, пересчёт видимости.
func _begin_player_turn(pid: int, events: Array) -> void:
	EmpireRules.process_turn_start(self, pid, events)
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
