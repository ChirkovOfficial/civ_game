class_name GameState
extends RefCounted
## Полное состояние партии (ГДД 25.2). Сериализуется целиком: сохранения,
## реплеи и тесты опираются на to_dict()/from_dict().

const SAVE_VERSION := 4

var treaty_data := {"active": {}, "offers": {}, "history": {}, "cooldowns": {},
	"reputation": {}, "withdrawal": {}}

## ID первой столицы каждой державы и зафиксированный итог партии.
var original_capitals: Dictionary = {}
var result: Dictionary = {}

var turn: int = 1
var current_player: int = 0
var rng: GameRng
## {"map_size", "map_type", "speed", "seed", "num_civs"}
var settings: Dictionary = {}
var map: GameMap
var players: Array[Player] = []
var units: Dictionary = {}   # id -> Unit
var next_unit_id: int = 1
var cities: Dictionary = {}  # id -> City
var next_city_id: int = 1
var start_positions: PackedInt32Array
## Пары держав в состоянии войны: "меньшийId,большийId" -> true. Дипломатия — веха M6.
var wars: Dictionary = {}
## Ход последнего объявления войны или мира в паре: "a,b" -> ход.
var war_changed: Dictionary = {}
## Договоры поставок, направленные зависимости и мировой рейтинг.
var diplomacy: Dictionary = {}
## Лагеря варваров: клетка -> {"spawned", "timer", "target", "scout"}.
var camps: Dictionary = {}


func player(id: int) -> Player:
	return players[id]


func unit(id: int) -> Unit:
	return units.get(id)


var _tile_index := {}
var _tile_index_version := -1


## Юниты в клетке (в порядке id — детерминированно). Индекс пересобирается при перемещениях.
func units_at(tile: int) -> Array[Unit]:
	if _tile_index_version != Unit.change_counter:
		_tile_index.clear()
		for id in _sorted_unit_ids():
			var u: Unit = units[id]
			if not _tile_index.has(u.tile):
				var arr: Array[Unit] = []
				_tile_index[u.tile] = arr
			_tile_index[u.tile].append(u)
		_tile_index_version = Unit.change_counter
	var result: Array[Unit] = []
	if _tile_index.has(tile):
		result.assign(_tile_index[tile])
	return result


func units_of(player_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for id in _sorted_unit_ids():
		var u: Unit = units[id]
		if u.owner == player_id:
			result.append(u)
	return result


func city(id: int) -> City:
	return cities.get(id)


## Город, центр которого в клетке, или null.
func city_at(tile: int) -> City:
	for id in _sorted_city_ids():
		var c: City = cities[id]
		if c.tile == tile:
			return c
	return null


## Город, которому принадлежит клетка (по границам), или null.
func city_owning(tile: int) -> City:
	var cid := map.owner_city[tile]
	return cities.get(cid) if cid >= 0 else null


func cities_of(player_id: int) -> Array[City]:
	var result: Array[City] = []
	for id in _sorted_city_ids():
		var c: City = cities[id]
		if c.owner == player_id:
			result.append(c)
	return result


func _sorted_city_ids() -> Array:
	var ids := cities.keys()
	ids.sort()
	return ids


func _sorted_unit_ids() -> Array:
	var ids := units.keys()
	ids.sort()
	return ids


static func _war_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


func at_war(a: int, b: int) -> bool:
	if a == b:
		return false
	if (a >= 0 and a < players.size() and players[a].is_barbarian) or (b >= 0 and b < players.size() and players[b].is_barbarian):
		return true
	return wars.has(_war_key(a, b))


func barbarian_id() -> int:
	for p in players:
		if p.is_barbarian:
			return p.id
	return -1


func set_war(a: int, b: int, value: bool) -> void:
	if value:
		wars[_war_key(a, b)] = true
	else:
		wars.erase(_war_key(a, b))
	war_changed[_war_key(a, b)] = turn


func turns_since_war_change(a: int, b: int) -> int:
	return turn - int(war_changed.get(_war_key(a, b), -1000))


func add_unit(owner: int, type: String, tile: int) -> Unit:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.owner = owner
	u.type = type
	u.tile = tile
	units[u.id] = u
	Unit.change_counter += 1
	return u


func remove_unit(id: int) -> void:
	units.erase(id)
	Unit.change_counter += 1


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
		"cities": _sorted_city_ids().map(func(id): return cities[id].to_dict()),
		"war_changed": war_changed.duplicate(),
		"diplomacy": diplomacy.duplicate(true),
		"treaties": treaty_data.duplicate(true),
		"original_capitals": original_capitals.duplicate(),
		"result": result.duplicate(true),
		"camps": _camps_list(),
		"next_city_id": next_city_id,
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
	for cd in d.get("cities", []):
		var c := City.from_dict(cd)
		s.cities[c.id] = c
	s.next_city_id = int(d.get("next_city_id", 1))
	if d.has("original_capitals"):
		for key in d["original_capitals"]:
			s.original_capitals[str(key)] = int(d["original_capitals"][key])
	else:
		# В старых сохранениях первая сохранившаяся постройка державы — ближайшее
		# приближение исходной столицы, включая города под чужим контролем.
		for id in s._sorted_city_ids():
			var city: City = s.cities[id]
			var key := str(city.original_owner)
			if not s.original_capitals.has(key):
				s.original_capitals[key] = city.id
	s.result = d.get("result", {}).duplicate(true)
	if not s.result.is_empty():
		s.result["turn"] = int(s.result["turn"])
		var winners: Array[int] = []
		for id in s.result["winners"]:
			winners.append(int(id))
		s.result["winners"] = winners
	for k in d.get("war_changed", {}):
		s.war_changed[k] = int(d["war_changed"][k])
	s.diplomacy = d.get("diplomacy", {}).duplicate(true)
	var saved_treaties: Dictionary = d.get("treaties", {})
	for collection in s.treaty_data:
		var records: Dictionary = saved_treaties.get(collection, {})
		for key in records:
			if collection == "history":
				var samples := []
				for sample in records[key]:
					samples.append(Unit._ints_in_dict(sample))
				s.treaty_data[collection][key] = samples
			else:
				s.treaty_data[collection][key] = Unit._ints_in_dict(records[key])
	if not s.diplomacy.is_empty():
		var majors: Array[int] = []
		for pid in s.diplomacy.get("initial_majors", []):
			majors.append(int(pid))
		s.diplomacy["initial_majors"] = majors
		for key in ["last_round", "next_id"]:
			s.diplomacy[key] = int(s.diplomacy.get(key, 0))
		for collection in ["offers", "contracts"]:
			for id in s.diplomacy.get(collection, {}):
				var record: Dictionary = s.diplomacy[collection][id]
				for field in record:
					if field not in ["resource"]:
						record[field] = int(record[field])
		for collection in ["delivery_history", "spend_history", "route_history", "living_history"]:
			for key in s.diplomacy.get(collection, {}):
				for record in s.diplomacy[collection][key]:
					record["round"] = int(record["round"])
	for c in d.get("camps", []):
		var camp := Unit._ints_in_dict(c)
		s.camps[int(camp["tile"])] = camp
	return s


func _camps_list() -> Array:
	var keys := camps.keys()
	keys.sort()
	var out := []
	for k in keys:
		out.append(camps[k].duplicate())
	return out


func to_json() -> String:
	# full_precision: иначе дробные числа округляются и партия после загрузки расходится.
	return JSON.stringify(to_dict(), "", true, true)


## Точный двоичный снимок (без потерь дробных чисел) — для файлов сохранений.
func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())


static func from_bytes(bytes: PackedByteArray, data: GameData) -> GameState:
	return from_dict(bytes_to_var(bytes), data)


static func from_json(text: String, data: GameData) -> GameState:
	return from_dict(JSON.parse_string(text), data)
