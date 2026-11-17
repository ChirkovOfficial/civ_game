class_name City
extends RefCounted
## Город (ГДД 5, 25.2). Клетки во владении хранятся в GameMap.owner_city.

var id: int
var owner: int
var original_owner: int
var name: String
var tile: int
var population: int = 1
## Накопленное давление по религиям. Последователи выводятся из давления и населения.
var religion_pressure: Dictionary = {}
var food_stored: float = 0.0
var is_capital: bool = false
var founded_turn: int = 1
var buildings: Array[String] = []
## Созданные городом шедевры в ячейках Театральной площади.
var great_works: int = 0
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
## Ход последнего нападения на город (лечение, починка стен) и обстрел в этот ход.
var last_attacked_turn: int = -100
var has_attacked: bool = false
## Районы (docs/CITIES.md): [{"type", "tile", "tier", "buildings": [], "complete", "cost"}].
## Центр города районом в этом списке не считается — его здания в buildings.
var districts: Array = []
## Специалисты по районам: "клетка" -> число жителей.
var specialists: Dictionary = {}
## Губернатор и его доктрина ("" — губернатора нет), ходов до вступления в должность,
## ход начала действия доктрины.
## У каждого города свой губернатор. Пустая доктрина означает отсутствие специализации.
var doctrine: String = ""
var doctrine_turns: int = 0
var doctrine_since: int = 0
## Ходов эпидемии осталось (0 — эпидемии нет).
var epidemic_turns: int = 0
## Державы, завершившие торговый путь в этот город.
var trade_posts: Array[int] = []


static func item_key(item: Dictionary) -> String:
	if item.has("tile"):
		return "%s:%s:%d" % [item["kind"], item["id"], int(item["tile"])]
	return "%s:%s" % [item["kind"], item["id"]]


func current_item() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


func has_building(bid: String) -> bool:
	return buildings.has(bid)


func to_dict() -> Dictionary:
	return {
		"id": id, "owner": owner, "original_owner": original_owner, "name": name,
		"tile": tile, "population": population, "religion_pressure": religion_pressure.duplicate(), "food_stored": food_stored,
		"is_capital": is_capital, "founded_turn": founded_turn,
		"buildings": buildings.duplicate(), "great_works": great_works,
		"worked_tiles": worked_tiles.duplicate(),
		"locked_tiles": locked_tiles.duplicate(), "queue": queue.duplicate(true),
		"progress": progress.duplicate(), "overflow": overflow,
		"culture_stored": culture_stored, "border_tiles_acquired": border_tiles_acquired,
		"focus": focus, "hp": hp, "wall_hp": wall_hp,
		"last_attacked_turn": last_attacked_turn, "has_attacked": has_attacked,
		"districts": districts.duplicate(true), "specialists": specialists.duplicate(),
		"doctrine": doctrine, "doctrine_turns": doctrine_turns, "doctrine_since": doctrine_since,
		"epidemic_turns": epidemic_turns,
		"trade_posts": trade_posts.duplicate(),
	}


static func from_dict(d: Dictionary) -> City:
	var c := City.new()
	c.id = int(d["id"])
	c.owner = int(d["owner"])
	c.original_owner = int(d["original_owner"])
	c.name = d["name"]
	c.tile = int(d["tile"])
	c.population = int(d["population"])
	for rid in d.get("religion_pressure", {}):
		c.religion_pressure[str(rid)] = float(d["religion_pressure"][rid])
	c.food_stored = float(d["food_stored"])
	c.is_capital = bool(d["is_capital"])
	c.founded_turn = int(d["founded_turn"])
	c.buildings.assign(d["buildings"])
	c.great_works = int(d.get("great_works", 0))
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
	c.last_attacked_turn = int(d.get("last_attacked_turn", -100))
	c.has_attacked = bool(d.get("has_attacked", false))
	for dd in d.get("districts", []):
		var bl: Array = []
		for b in dd["buildings"]:
			bl.append(str(b))
		c.districts.append({"type": str(dd["type"]), "tile": int(dd["tile"]), "tier": int(dd["tier"]),
			"buildings": bl, "complete": bool(dd["complete"]), "cost": float(dd["cost"])})
	for k in d.get("specialists", {}):
		c.specialists[str(k)] = int(d["specialists"][k])
	c.doctrine = str(d.get("doctrine", ""))
	c.doctrine_turns = int(d.get("doctrine_turns", 0))
	c.doctrine_since = int(d.get("doctrine_since", 0))
	c.epidemic_turns = int(d.get("epidemic_turns", 0))
	for pid in d.get("trade_posts", []):
		c.trade_posts.append(int(pid))
	for q in c.queue:
		if q.has("tile"):
			q["tile"] = int(q["tile"])
	return c
