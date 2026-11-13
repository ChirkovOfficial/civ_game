class_name GameMap
extends RefCounted
## Клетки карты (ГДД 3.1). Хранится «столбцами» (по массиву на свойство) —
## так компактнее и быстрее, чем объект на каждую клетку.

const RELIEF_FLAT := 0
const RELIEF_HILLS := 1
const RELIEF_MOUNTAIN := 2

var grid: HexGrid
var terrain: PackedStringArray
var relief: PackedByteArray
var feature: PackedStringArray        # "" — нет особенности
var resource: PackedStringArray       # "" — нет ресурса
var improvement: PackedStringArray    # "" — нет улучшения
var river_edges: PackedByteArray      # битовая маска по направлениям 0..5
var continent: PackedInt32Array       # -1 для воды
var owner_city: PackedInt32Array      # -1 — ничья клетка

var _data: GameData


func _init(w: int, h: int, data: GameData) -> void:
	grid = HexGrid.new(w, h)
	_data = data
	var n := w * h
	terrain.resize(n)
	terrain.fill("OCEAN")
	relief.resize(n)
	feature.resize(n)
	resource.resize(n)
	improvement.resize(n)
	river_edges.resize(n)
	continent.resize(n)
	continent.fill(-1)
	owner_city.resize(n)
	owner_city.fill(-1)


var width: int:
	get: return grid.width

var height: int:
	get: return grid.height


func size() -> int:
	return grid.tile_count()


# --- Запросы -------------------------------------------------------------------

func terrain_def(i: int) -> Dictionary:
	return _data.terrains.get(terrain[i], {})


func feature_def(i: int) -> Dictionary:
	return _data.features.get(feature[i], {})


func is_water(i: int) -> bool:
	return terrain_def(i).get("water", false)


func is_land(i: int) -> bool:
	return not is_water(i)


func is_hills(i: int) -> bool:
	return relief[i] == RELIEF_HILLS


func is_mountain(i: int) -> bool:
	return relief[i] == RELIEF_MOUNTAIN


func has_river(i: int) -> bool:
	return river_edges[i] != 0


func has_river_edge(i: int, dir: int) -> bool:
	return (river_edges[i] >> dir) & 1 == 1


## Ставит реку на ребро между клеткой i и её соседом в направлении dir (с обеих сторон).
func set_river_edge(i: int, dir: int) -> void:
	var n := grid.neighbor(i, dir)
	river_edges[i] |= 1 << dir
	if n >= 0:
		river_edges[n] |= 1 << HexGrid.opposite(dir)


## Пресная вода: река, соседнее озеро или оазис (ГДД 3.4).
func has_fresh_water(i: int) -> bool:
	if has_river(i):
		return true
	for n in grid.neighbors(i):
		if terrain_def(n).get("fresh_water", false) or feature_def(n).get("fresh_water", false):
			return true
	return false


## Суша, граничащая с морской (не озёрной) водой.
func is_coastal_land(i: int) -> bool:
	if is_water(i):
		return false
	for n in grid.neighbors(i):
		if terrain[n] == "COAST" or terrain[n] == "OCEAN":
			return true
	return false


# --- Сериализация --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"width": width, "height": height,
		"terrain": Array(terrain), "relief": Array(relief),
		"feature": Array(feature), "resource": Array(resource),
		"improvement": Array(improvement), "river_edges": Array(river_edges),
		"continent": Array(continent), "owner_city": Array(owner_city),
	}


static func from_dict(d: Dictionary, data: GameData) -> GameMap:
	var m := GameMap.new(int(d["width"]), int(d["height"]), data)
	m.terrain = PackedStringArray(d["terrain"])
	m.relief = PackedByteArray(d["relief"])
	m.feature = PackedStringArray(d["feature"])
	m.resource = PackedStringArray(d["resource"])
	m.improvement = PackedStringArray(d["improvement"])
	m.river_edges = PackedByteArray(d["river_edges"])
	m.continent = PackedInt32Array(d["continent"])
	m.owner_city = PackedInt32Array(d["owner_city"])
	return m
