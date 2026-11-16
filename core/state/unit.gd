class_name Unit
extends RefCounted
## Юнит на карте (ГДД 9.1, 25.2).

## Счётчик изменений положения/состава юнитов (для кэша в GameState.units_at).
static var change_counter := 0

var id: int
var owner: int
var type: String
## Клетка. Любое изменение сбрасывает индекс «клетка → юниты» в GameState.
var tile: int:
	set(v):
		tile = v
		Unit.change_counter += 1
var hp: int = 100
var moves_left: float = 0.0
var xp: int = 0
var level: int = 0
var promotions: Array[String] = []
var charges: int = 0
var fortify_turns: int = 0
## Постоянный приказ, исполняемый в начале хода: {} или {"type": "move", "target": tile}.
var orders: Dictionary = {}
## Сделал ли юнит что-либо в этот ход (для лечения и подсказок).
var acted: bool = false
## Снаряжение: слот -> вариант (docs/ARMY.md). Пустые слоты — по умолчанию.
var equipment: Dictionary = {}
## Объединённый командующий: {} или {"xp", "level"}.
var commander: Dictionary = {}
## Действующий торговый путь. Пустой словарь означает свободного торговца.
var trade_route: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"id": id, "owner": owner, "type": type, "tile": tile, "hp": hp,
		"moves_left": moves_left, "xp": xp, "level": level,
		"promotions": promotions.duplicate(), "charges": charges,
		"fortify_turns": fortify_turns, "orders": orders.duplicate(true), "acted": acted,
		"equipment": equipment.duplicate(), "commander": commander.duplicate(),
		"trade_route": trade_route.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d["id"])
	u.owner = int(d["owner"])
	u.type = d["type"]
	u.tile = int(d["tile"])
	u.hp = int(d["hp"])
	u.moves_left = float(d["moves_left"])
	u.xp = int(d["xp"])
	u.level = int(d["level"])
	u.promotions.assign(d["promotions"])
	u.charges = int(d["charges"])
	u.fortify_turns = int(d["fortify_turns"])
	u.orders = _ints_in_dict(d["orders"])
	u.acted = bool(d["acted"])
	u.equipment = d.get("equipment", {}).duplicate()
	u.commander = _ints_in_dict(d.get("commander", {}))
	u.trade_route = _ints_in_dict(d.get("trade_route", {}))
	if not u.trade_route.is_empty():
		var path: Array[int] = []
		for tile in u.trade_route["path"]:
			path.append(int(tile))
		u.trade_route["path"] = path
	return u


## JSON превращает целые в float; приказы содержат индексы клеток — вернём int.
static func _ints_in_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		out[k] = int(v) if typeof(v) == TYPE_FLOAT and v == floorf(v) else v
	return out
