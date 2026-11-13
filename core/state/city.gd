class_name City
extends RefCounted
## Город (ГДД 5, 25.2). Клетки во владении хранятся в GameMap.owner_city.

var id: int
var owner: int
var original_owner: int
var name: String
var tile: int
var population: int = 1
var food_stored: float = 0.0
var is_capital: bool = false
var founded_turn: int = 1
var buildings: Array[String] = []
## Обрабатываемые жителями клетки (без центра — он обрабатывается бесплатно).
var worked_tiles: Array[int] = []
## Клетки, закреплённые игроком вручную (автоуправляющий их не снимает).
var locked_tiles: Array[int] = []
## Очередь производства: [{"kind": "unit"|"building", "id": "..."}]. Строится первый элемент.
var queue: Array = []
## Накопленный прогресс по объектам: "kind:id" -> ⚙. Смена объекта сохраняет прогресс (ГДД 4.2).
var progress: Dictionary = {}
## Излишек производства, перешедший с завершённого объекта.
var overflow: float = 0.0
var culture_stored: float = 0.0
## Сколько клеток уже получено за культуру (k в формуле ГДД 4.5).
var border_tiles_acquired: int = 0
## Фокус автоуправляющего: "" (сбалансированно) или тип дохода.
var focus: String = ""
var hp: int = 200
var wall_hp: int = 0


static func item_key(item: Dictionary) -> String:
	return "%s:%s" % [item["kind"], item["id"]]


func current_item() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


func has_building(bid: String) -> bool:
	return buildings.has(bid)


func to_dict() -> Dictionary:
	return {
		"id": id, "owner": owner, "original_owner": original_owner, "name": name,
		"tile": tile, "population": population, "food_stored": food_stored,
		"is_capital": is_capital, "founded_turn": founded_turn,
		"buildings": buildings.duplicate(), "worked_tiles": worked_tiles.duplicate(),
		"locked_tiles": locked_tiles.duplicate(), "queue": queue.duplicate(true),
		"progress": progress.duplicate(), "overflow": overflow,
		"culture_stored": culture_stored, "border_tiles_acquired": border_tiles_acquired,
		"focus": focus, "hp": hp, "wall_hp": wall_hp,
	}


static func from_dict(d: Dictionary) -> City:
	var c := City.new()
	c.id = int(d["id"])
	c.owner = int(d["owner"])
	c.original_owner = int(d["original_owner"])
	c.name = d["name"]
	c.tile = int(d["tile"])
	c.population = int(d["population"])
	c.food_stored = float(d["food_stored"])
	c.is_capital = bool(d["is_capital"])
	c.founded_turn = int(d["founded_turn"])
	c.buildings.assign(d["buildings"])
	for t in d["worked_tiles"]:
		c.worked_tiles.append(int(t))
	for t in d["locked_tiles"]:
		c.locked_tiles.append(int(t))
	c.queue = d["queue"].duplicate(true)
	for k in d["progress"]:
		c.progress[k] = float(d["progress"][k])
	c.overflow = float(d["overflow"])
	c.culture_stored = float(d["culture_stored"])
	c.border_tiles_acquired = int(d["border_tiles_acquired"])
	c.focus = d["focus"]
	c.hp = int(d["hp"])
	c.wall_hp = int(d["wall_hp"])
	return c
