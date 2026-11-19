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
var government_setup: Dictionary = {}
var governments: Dictionary = {}
var policies: Dictionary = {}
var trade: Dictionary = {}
var diplomacy: Dictionary = {}
var religion_setup: Dictionary = {}
var science_setup: Dictionary = {}
var energy_setup: Dictionary = {}
var culture_setup: Dictionary = {}
var culture_content: Dictionary = {}
var great_people: Dictionary = {}
var wonders: Dictionary = {}
var great_person_ids: Array[String] = []
var wonder_ids: Array[String] = []
var finance_setup: Dictionary = {}
var visibility_setup: Dictionary = {}
var science_projects: Dictionary = {}
var science_project_ids: Array[String] = []
var buildings: Dictionary = {}
var districts: Dictionary = {}
var improvements: Dictionary = {}
var harvest: Dictionary = {}
## Прочие разделы improvements.json (например, "pillage").
var improvements_extra: Dictionary = {}
var civs: Dictionary = {}
var abilities: Dictionary = {}
var promotions: Dictionary = {}
var equipment: Dictionary = {}
var placeholder_detachment_name: String = "отряд"
var promotion_ids: Array[String] = []
var placeholder_city_names: Array = []
var setup: Dictionary = {}

## Порядок объявления сохраняется (для детерминированного перебора).
var resource_ids: Array[String] = []
var tech_ids: Array[String] = []
var civic_ids: Array[String] = []
var legacy_techs: Dictionary = {}
var legacy_civics: Dictionary = {}
var building_ids: Array[String] = []
var district_ids: Array[String] = []
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
	var d_list: Array = _read(dir + "districts.json").get("districts", [])
	districts = _index(d_list)
	for x in d_list:
		district_ids.append(x["id"])
	var imp := _read(dir + "improvements.json")
	var imp_list: Array = imp.get("improvements", [])
	improvements = _index(imp_list)
	for x in imp_list:
		improvement_ids.append(x["id"])
	harvest = imp.get("harvest", {})
	improvements_extra = imp
	abilities = _index(_read(dir + "abilities.json").get("abilities", []))
	var promo_list: Array = _read(dir + "promotions.json").get("promotions", [])
	promotions = _index(promo_list)
	for x in promo_list:
		promotion_ids.append(x["id"])
	var civ_file := _read(dir + "civs.json")
	civs = _index(civ_file.get("civs", []))
	placeholder_city_names = civ_file.get("placeholder", {}).get("city_names", [])
	placeholder_detachment_name = civ_file.get("placeholder", {}).get("detachment_name", "отряд")
	equipment = _read(dir + "equipment.json")
	unit_classes = _read(dir + "unit_classes.json").get("classes", {})
	var tech_file := _read(dir + "techs.json")
	legacy_techs = tech_file.get("legacy_ids", {})
	var tech_list: Array = tech_file.get("techs", [])
	techs = _index(tech_list)
	for x in tech_list:
		tech_ids.append(x["id"])
	var civic_file := _read(dir + "civics.json")
	legacy_civics = civic_file.get("legacy_ids", {})
	var civic_list: Array = civic_file.get("civics", [])
	civics = _index(civic_list)
	for x in civic_list:
		civic_ids.append(x["id"])
	government_setup = _read(dir + "governments.json")
	governments = _index(government_setup.get("governments", []))
	policies = _index(government_setup.get("policies", []))
	trade = _read(dir + "trade.json")
	diplomacy = _read(dir + "diplomacy.json")
	religion_setup = _read(dir + "religions.json")
	science_setup = _read(dir + "science_projects.json")
	energy_setup = _read(dir + "energy.json")
	culture_setup = _read(dir + "culture_victory.json")
	culture_content = _read(dir + "culture_content.json")
	var great_person_list: Array = culture_content.get("great_people", [])
	great_people = _index(great_person_list)
	for entry in great_person_list:
		great_person_ids.append(str(entry["id"]))
	var wonder_list: Array = culture_content.get("wonders", [])
	wonders = _index(wonder_list)
	for entry in wonder_list:
		wonder_ids.append(str(entry["id"]))
	finance_setup = _read(dir + "finance_victory.json")
	visibility_setup = _read(dir + "diplomatic_visibility.json")
	var project_list: Array = science_setup.get("projects", [])
	science_projects = _index(project_list)
	for project in project_list:
		science_project_ids.append(str(project["id"]))
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
		if u.has("requires_district") and not districts.has(u["requires_district"].get("type", "")):
			errors.append("Юнит %s: нет района %s" % [uid, u["requires_district"].get("type", "")])
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
	for bid in buildings:
		var b: Dictionary = buildings[bid]
		var dist: String = b.get("district", "CITY_CENTER")
		if dist != "CITY_CENTER" and not districts.has(dist):
			errors.append("Здание %s: нет района %s" % [bid, dist])
	for did in districts:
		var dd: Dictionary = districts[did]
		var reqs: Array = [dd]
		reqs.append_array(dd.get("tiers", []))
		for r in reqs:
			if r.has("tech") and not techs.has(r["tech"]):
				errors.append("Район %s: нет технологии %s" % [did, r["tech"]])
			if r.has("civic") and not civics.has(r["civic"]):
				errors.append("Район %s: нет института %s" % [did, r["civic"]])
		var pl: Dictionary = dd.get("placement", {})
		if pl.has("feature") and not features.has(pl["feature"]):
			errors.append("Район %s: нет особенности %s" % [did, pl["feature"]])
		for a in dd.get("adjacency", []):
			if a["source"] == "feature" and not features.has(a.get("id", "")):
				errors.append("Район %s: соседство с несуществующей особенностью %s" % [did, a.get("id", "")])
			if a["source"] == "district_type" and not districts.has(a.get("id", "")):
				errors.append("Район %s: соседство с несуществующим районом %s" % [did, a.get("id", "")])
			if a["source"] == "improvement" and not improvements.has(a.get("id", "")):
				errors.append("Район %s: соседство с несуществующим улучшением %s" % [did, a.get("id", "")])
	for cid in civs:
		for did in civs[cid].get("district_names", {}):
			if not districts.has(did) and did != "CITY_CENTER":
				errors.append("Цивилизация %s: название для несуществующего района %s" % [cid, did])
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
	for slot in equipment.get("slots", {}):
		var sd: Dictionary = equipment["slots"][slot]
		for opt in sd.get("options", []):
			if not equipment.get("options", {}).has(opt):
				errors.append("Снаряжение %s: нет варианта %s" % [slot, opt])
		if not sd.get("options", []).has(sd.get("default", "")):
			errors.append("Снаряжение %s: вариант по умолчанию не из списка" % slot)
	for lo in equipment.get("loadouts", []):
		for slot in lo.get("slots", []):
			if not equipment.get("slots", {}).has(slot):
				errors.append("Снаряжение: нет слота %s" % slot)
	for uid in constants.get("start_units", []):
		if not units.has(uid):
			errors.append("Стартовый юнит %s не существует" % uid)
	errors.append_array(_validate_tree(techs, "Технология"))
	errors.append_array(GovernmentRules.validate_data(self))
	errors.append_array(Movement.validate_data(self))
	errors.append_array(EmpireRules.validate_data(self))
	errors.append_array(TradeRules.validate_data(self))
	errors.append_array(ReligionRules.validate_data(self))
	errors.append_array(ScienceRules.validate_data(self))
	errors.append_array(EnergyRules.validate_data(self))
	errors.append_array(CultureRules.validate_data(self))
	errors.append_array(ParkRules.validate_data(self))
	errors.append_array(RockBandRules.validate_data(self))
	errors.append_array(GreatPeopleRules.validate_data(self))
	errors.append_array(WonderRules.validate_data(self))
	errors.append_array(FinanceRules.validate_data(self))
	errors.append_array(DiplomaticVisibility.validate_data(self))
	errors.append_array(TreatyRules.validate_data(self))
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
