class_name GameState
extends RefCounted
## Полное состояние партии (ГДД 25.2). Сериализуется целиком: сохранения,
## реплеи и тесты опираются на to_dict()/from_dict().

const SAVE_VERSION := 1

var turn: int = 1
var current_player: int = 0
var rng: GameRng
## {"map_size", "map_type", "speed", "seed", "num_civs"}
var settings: Dictionary = {}
var map: GameMap
var players: Array[Player] = []
var units: Dictionary = {}   # id -> Unit
var next_unit_id: int = 1
var start_positions: PackedInt32Array
## Пары держав в состоянии войны: "меньшийId,большийId" -> true. Дипломатия — веха M6.
var wars: Dictionary = {}


func player(id: int) -> Player:
	return players[id]


func unit(id: int) -> Unit:
	return units.get(id)


## Юниты в клетке (в порядке id — детерминированно).
func units_at(tile: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for id in _sorted_unit_ids():
		var u: Unit = units[id]
		if u.tile == tile:
			result.append(u)
	return result


func units_of(player_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for id in _sorted_unit_ids():
		var u: Unit = units[id]
		if u.owner == player_id:
			result.append(u)
	return result


func _sorted_unit_ids() -> Array:
	var ids := units.keys()
	ids.sort()
	return ids


static func _war_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


func at_war(a: int, b: int) -> bool:
	return a != b and wars.has(_war_key(a, b))


func set_war(a: int, b: int, value: bool) -> void:
	if value:
		wars[_war_key(a, b)] = true
	else:
		wars.erase(_war_key(a, b))


func add_unit(owner: int, type: String, tile: int) -> Unit:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.owner = owner
	u.type = type
	u.tile = tile
	units[u.id] = u
	return u


func remove_unit(id: int) -> void:
	units.erase(id)


# --- Сериализация --------------------------------------------------------------

func to_dict() -> Dictionary:
	var unit_list := []
	for id in _sorted_unit_ids():
		unit_list.append(units[id].to_dict())
	var player_list := []
	for p in players:
		player_list.append(p.to_dict())
	return {
		"version": SAVE_VERSION,
		"turn": turn, "current_player": current_player,
		"rng": rng.to_dict(), "settings": settings.duplicate(true),
		"map": map.to_dict(), "players": player_list, "units": unit_list,
		"next_unit_id": next_unit_id, "start_positions": Array(start_positions),
		"wars": wars.keys(),
	}


static func from_dict(d: Dictionary, data: GameData) -> GameState:
	var s := GameState.new()
	s.turn = int(d["turn"])
	s.current_player = int(d["current_player"])
	s.rng = GameRng.from_dict(d["rng"])
	s.settings = Unit._ints_in_dict(d["settings"])
	s.map = GameMap.from_dict(d["map"], data)
	for pd in d["players"]:
		s.players.append(Player.from_dict(pd))
	for ud in d["units"]:
		var u := Unit.from_dict(ud)
		s.units[u.id] = u
	s.next_unit_id = int(d["next_unit_id"])
	s.start_positions = PackedInt32Array(d["start_positions"])
	for k in d.get("wars", []):
		s.wars[k] = true
	return s


func to_json() -> String:
	return JSON.stringify(to_dict())


static func from_json(text: String, data: GameData) -> GameState:
	return from_dict(JSON.parse_string(text), data)
