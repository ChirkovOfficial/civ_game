class_name Pathfinder
extends RefCounted
## Поиск пути A* по правилам движения (ГДД 3.5) с учётом многоходовых маршрутов.
##
## Состояние в клетке — (ходов прошло, ОД осталось). Больше ОД при том же числе
## ходов никогда не хуже, поэтому достаточно хранить лучшее состояние на клетку.
## Планирование идёт от лица владельца юнита: неразведанные клетки считаются
## проходимыми, учитываются только видимые чужие юниты.

## Минимальная стоимость шага (железная дорога) — для допустимой эвристики.
const MIN_STEP_COST := 0.25
const MAX_TURNS := 60


class Step:
	var tile: int
	## Номер хода прибытия: 0 — в этот ход, 1 — в следующий и т.д.
	var turn: int
	var moves_left: float


## Путь от текущей клетки юнита до target (без стартовой клетки). Пустой — пути нет.
static func find_path(game: Game, unit: Unit, target: int) -> Array[Step]:
	var result: Array[Step] = []
	var map := game.state.map
	if target == unit.tile or not map.grid.is_valid_index(target):
		return result
	var me := game.state.player(unit.owner)
	var max_m := Movement.max_moves_at(game, unit, unit.tile)
	if max_m <= 0.0:
		return result
	if me.is_revealed(target) and not Movement.can_stand(game, unit, target):
		return result
	var embarked_m := float(game.data.const_value("embark_moves", 2))
	var fast_tech := str(game.data.const_value("embark_fast_tech", ""))
	if fast_tech != "" and me.has_tech(fast_tech):
		embarked_m += float(game.data.const_value("embark_fast_bonus", 2))
	var key := maxf(Movement.max_land_moves(game, unit), embarked_m) + 1.0
	# Лучшие (turns, moves) по клетке.
	var best_turns := {}
	var best_moves := {}
	var came_from := {}
	var open := _Heap.new()
	best_turns[unit.tile] = 0
	best_moves[unit.tile] = unit.moves_left
	open.push(_h(map, unit.tile, target), unit.tile)
	while not open.is_empty():
		var cur: int = open.pop()
		var t: int = best_turns[cur]
		var m: float = best_moves[cur]
		if cur == target:
			break
		if t > MAX_TURNS:
			continue
		# Если ОД кончились — ход заканчивается здесь, нельзя стоять в занятой клетке.
		if m <= 0.0:
			if cur != unit.tile and not Movement.occupancy_allows(game, unit, cur, true, true):
				continue
			t += 1
			m = Movement.max_moves_at(game, unit, cur)
		for nb in map.grid.neighbors(cur):
			var known := me.is_revealed(nb)
			if not Movement.occupancy_allows(game, unit, nb, nb == target, true):
				continue
			var left := Movement.moves_after_step(game, unit, cur, nb, m, known, true)
			if left < 0.0:
				continue
			if not _better(t, left, best_turns.get(nb, -1), best_moves.get(nb, 0.0)):
				continue
			best_turns[nb] = t
			best_moves[nb] = left
			came_from[nb] = cur
			var g := t * key + (key - 1.0 - left)
			open.push(g + _h(map, nb, target), nb)
	if not came_from.has(target):
		return result
	var tiles: Array[int] = []
	var c := target
	while c != unit.tile:
		tiles.push_front(c)
		c = came_from[c]
	for tile in tiles:
		var s := Step.new()
		s.tile = tile
		s.turn = best_turns[tile]
		s.moves_left = best_moves[tile]
		result.append(s)
	return result


static func _better(t: int, m: float, bt: int, bm: float) -> bool:
	if bt < 0:
		return true
	return t < bt or (t == bt and m > bm)


static func _h(map: GameMap, a: int, b: int) -> float:
	return map.grid.distance(a, b) * MIN_STEP_COST


## Двоичная куча (минимум по приоритету). При равенстве — меньший порядковый номер
## вставки, чтобы результат не зависел от реализации сортировки.
class _Heap:
	var _items: Array = []   # [priority, seq, value]
	var _seq := 0

	func is_empty() -> bool:
		return _items.is_empty()

	func push(priority: float, value: int) -> void:
		_items.append([priority, _seq, value])
		_seq += 1
		var i := _items.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if _less(_items[i], _items[p]):
				var tmp = _items[i]
				_items[i] = _items[p]
				_items[p] = tmp
				i = p
			else:
				break

	func pop() -> int:
		var top = _items[0]
		var last = _items.pop_back()
		if not _items.is_empty():
			_items[0] = last
			var i := 0
			var n := _items.size()
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var s := i
				if l < n and _less(_items[l], _items[s]):
					s = l
				if r < n and _less(_items[r], _items[s]):
					s = r
				if s == i:
					break
				var tmp = _items[i]
				_items[i] = _items[s]
				_items[s] = tmp
				i = s
		return top[2]

	static func _less(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
