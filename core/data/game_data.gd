class_name GameData
extends RefCounted
## Весь игровой контент, загруженный из data/*.json (ГДД 25.1 п.2).
## Код не должен содержать идентификаторов конкретного контента — только
## ссылки через константы из constants.json.

const DATA_DIR := "res://data/"

var constants: Dictionary = {}
var terrains: Dictionary = {}      # id -> def
var relief: Dictionary = {}        # "HILLS"/"MOUNTAIN" -> def
var features: Dictionary = {}
var resources: Dictionary = {}
var units: Dictionary = {}
var unit_classes: Dictionary = {}
var techs: Dictionary = {}
var civics: Dictionary = {}
var buildings: Dictionary = {}
var improvements: Dictionary = {}
var harvest: Dictionary = {}
var civs: Dictionary = {}
var abilities: Dictionary = {}
var promotions: Dictionary = {}
var promotion_ids: Array[String] = []
var placeholder_city_names: Array = []
var setup: Dictionary = {}

## Порядок объявления сохраняется (для детерминированного перебора).
var resource_ids: Array[String] = []
var tech_ids: Array[String] = []
var civic_ids: Array[String] = []
var building_ids: Array[String] = []
var improvement_ids: Array[String] = []
var unit_ids: Array[String] = []

var load_errors: PackedStringArray = []

static var _cached: GameData = null


## Общий экземпляр (данные неизменяемы во время партии).
static func get_default() -> GameData:
	if _cached == null:
		_cached = GameData.new()
		_cached.load_all()
	return _cached


func load_all(dir: String = DATA_DIR) -> void:
	constants = _read(dir + "constants.json")
	var t := _read(dir + "terrains.json")
	terrains = _index(t.get("terrains", []))
	relief = t.get("relief", {})
	features = _index(_read(dir + "features.json").get("features", []))
	var res_list: Array = _read(dir + "resources.json").get("resources", [])
	resources = _index(res_list)
	for r in res_list:
		resource_ids.append(r["id"])
	var unit_list: Array = _read(dir + "units.json").get("units", [])
	units = _index(unit_list)
	for x in unit_list:
		unit_ids.append(x["id"])
	var b_list: Array = _read(dir + "buildings.json").get("buildings", [])
	buildings = _index(b_list)
	for x in b_list:
		building_ids.append(x["id"])
	var imp := _read(dir + "improvements.json")
	var imp_list: Array = imp.get("improvements", [])
	improvements = _index(imp_list)
	for x in imp_list:
		improvement_ids.append(x["id"])
	harvest = imp.get("harvest", {})
	abilities = _index(_read(dir + "abilities.json").get("abilities", []))
	var promo_list: Array = _read(dir + "promotions.json").get("promotions", [])
	promotions = _index(promo_list)
	for x in promo_list:
		promotion_ids.append(x["id"])
	var civ_file := _read(dir + "civs.json")
	civs = _index(civ_file.get("civs", []))
	placeholder_city_names = civ_file.get("placeholder", {}).get("city_names", [])
	unit_classes = _read(dir + "unit_classes.json").get("classes", {})
	var tech_list: Array = _read(dir + "techs.json").get("techs", [])
	techs = _index(tech_list)
	for x in tech_list:
		tech_ids.append(x["id"])
	var civic_list: Array = _read(dir + "civics.json").get("civics", [])
	civics = _index(civic_list)
	for x in civic_list:
		civic_ids.append(x["id"])
	setup = _read(dir + "game_setup.json")


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("Не удалось открыть %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("Ошибка JSON в %s" % path)
		return {}
	return parsed


static func _index(list: Array) -> Dictionary:
	var d := {}
	for item in list:
		d[item["id"]] = item
	return d


# --- Удобные геттеры ------------------------------------------------------------

func const_value(key: String, default: Variant = null) -> Variant:
	return constants.get(key, default)


func unit_def(id: String) -> Dictionary:
	return units.get(id, {})


func unit_class_def(unit_id: String) -> Dictionary:
	return unit_classes.get(unit_def(unit_id).get("class", ""), {})


func map_size(id: String) -> Dictionary:
	for s in setup.get("map_sizes", []):
		if s["id"] == id:
			return s
	return {}


func map_type(id: String) -> Dictionary:
	for s in setup.get("map_types", []):
		if s["id"] == id:
			return s
	return {}


func game_speed(id: String) -> Dictionary:
	for s in setup.get("game_speeds", []):
		if s["id"] == id:
			return s
	return {}


# --- Проверка целостности (ГДД 25.5) -----------------------------------------------

## Возвращает список найденных проблем; пустой список = данные корректны.
func validate() -> PackedStringArray:
	var errors := PackedStringArray(load_errors)
	for rid in resources:
		var r: Dictionary = resources[rid]
		if r.has("reveal_tech") and not techs.has(r["reveal_tech"]):
			errors.append("Ресурс %s: нет технологии %s" % [rid, r["reveal_tech"]])
		for p in r.get("placements", []):
			for tid in p.get("terrain", []):
				if not terrains.has(tid):
					errors.append("Ресурс %s: нет ландшафта %s" % [rid, tid])
			for fid in p.get("feature", []):
				if not features.has(fid):
					errors.append("Ресурс %s: нет особенности %s" % [rid, fid])
	for fid in features:
		for tid in features[fid].get("terrains", []):
			if not terrains.has(tid):
				errors.append("Особенность %s: нет ландшафта %s" % [fid, tid])
	for uid in units:
		var u: Dictionary = units[uid]
		if not unit_classes.has(u.get("class", "")):
			errors.append("Юнит %s: нет класса %s" % [uid, u.get("class", "")])
		if u.has("tech") and not techs.has(u["tech"]):
			errors.append("Юнит %s: нет технологии %s" % [uid, u["tech"]])
		if u.has("civic") and not civics.has(u["civic"]):
			errors.append("Юнит %s: нет института %s" % [uid, u["civic"]])
		if u.has("upgrades_to"):
			var up: String = u["upgrades_to"]
			if not units.has(up):
				errors.append("Юнит %s: модернизация в несуществующий %s" % [uid, up])
		for res_id in u.get("resource", {}).keys() + u.get("resource_per_turn", {}).keys():
			if not resources.has(res_id):
				errors.append("Юнит %s: нет ресурса %s" % [uid, res_id])
	for bid in buildings:
		var b: Dictionary = buildings[bid]
		if b.has("tech") and not techs.has(b["tech"]):
			errors.append("Здание %s: нет технологии %s" % [bid, b["tech"]])
		if b.has("civic") and not civics.has(b["civic"]):
			errors.append("Здание %s: нет института %s" % [bid, b["civic"]])
	for iid in improvements:
		var im: Dictionary = improvements[iid]
		if im.has("tech") and not techs.has(im["tech"]):
			errors.append("Улучшение %s: нет технологии %s" % [iid, im["tech"]])
		for p in im.get("placements", []):
			if p.has("civic") and not civics.has(p["civic"]):
				errors.append("Улучшение %s: нет института %s" % [iid, p["civic"]])
	for rid in resources:
		var imp_id: String = resources[rid].get("improvement", "")
		if imp_id != "" and not improvements.has(imp_id):
			errors.append("Ресурс %s: нет улучшения %s" % [rid, imp_id])
	for uid in units:
		for a in units[uid].get("abilities", []):
			if not abilities.has(a) and not ["FOUND_CITY", "BUILD_IMPROVEMENT", "TRADE_ROUTE", "OPEN_TERRAIN_BONUS_MOVE"].has(a):
				errors.append("Юнит %s: нет особенности %s" % [uid, a])
	for cid in civs:
		var civ: Dictionary = civs[cid]
		for a in civ.get("land_combat_abilities", []):
			if not abilities.has(a):
				errors.append("Цивилизация %s: нет особенности %s" % [cid, a])
		for slot in civ.get("units", {}):
			if not units.has(slot):
				errors.append("Цивилизация %s: нет юнита-слота %s" % [cid, slot])
			for a in civ["units"][slot].get("abilities", []):
				if not abilities.has(a):
					errors.append("Цивилизация %s, юнит %s: нет особенности %s" % [cid, slot, a])
	for uid in constants.get("start_units", []):
		if not units.has(uid):
			errors.append("Стартовый юнит %s не существует" % uid)
	errors.append_array(_validate_tree(techs, "Технология"))
	errors.append_array(_validate_tree(civics, "Институт"))
	return errors


static func _validate_tree(tree: Dictionary, label: String) -> PackedStringArray:
	var errors := PackedStringArray()
	for id in tree:
		for p in tree[id].get("prereqs", []):
			if not tree.has(p):
				errors.append("%s %s: нет предпосылки %s" % [label, id, p])
	# Поиск циклов: 0 = не посещено, 1 = в стеке, 2 = готово.
	var state := {}
	for id in tree:
		if _has_cycle(tree, id, state):
			errors.append("%s: цикл в графе предпосылок через %s" % [label, id])
			break
	return errors


static func _has_cycle(tree: Dictionary, id: String, state: Dictionary) -> bool:
	var s: int = state.get(id, 0)
	if s == 1:
		return true
	if s == 2:
		return false
	state[id] = 1
	for p in tree.get(id, {}).get("prereqs", []):
		if tree.has(p) and _has_cycle(tree, p, state):
			return true
	state[id] = 2
	return false
