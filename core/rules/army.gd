class_name Army
extends RefCounted
## Снаряжение юнитов и командующие (docs/ARMY.md).
##
## Снаряжение хранится в Unit.equipment (слот → вариант); отсутствующие слоты берутся по
## умолчанию из data/equipment.json. Командующий, объединённый с войсками, хранится внутри
## юнита (Unit.commander = {"xp", "level"}); при разъединении снова становится юнитом.


static func eq(game: Game) -> Dictionary:
	return game.data.equipment


# --- Климат --------------------------------------------------------------------------------

## "COLD" | "HOT" | "TEMPERATE" — климат клетки для снаряжения.
static func climate_of(game: Game, tile: int) -> String:
	var map := game.state.map
	var cl: Dictionary = eq(game).get("climate", {})
	if cl.get("COLD", []).has(map.terrain[tile]):
		return "COLD"
	if cl.get("HOT", []).has(map.terrain[tile]) or cl.get("HOT_FEATURES", []).has(map.feature[tile]):
		return "HOT"
	return "TEMPERATE"


static func is_extreme_cold(game: Game, tile: int) -> bool:
	return eq(game).get("climate", {}).get("EXTREME_COLD", []).has(game.state.map.terrain[tile])


# --- Слоты и варианты ---------------------------------------------------------------------

## Кэш слотов по типу юнита (данные неизменны во время партии).
static var _slots_cache := {}


static func slots_for(game: Game, unit_type: String) -> Array[String]:
	if _slots_cache.has(unit_type):
		return _slots_cache[unit_type]
	var result: Array[String] = []
	var cls: String = game.data.unit_def(unit_type).get("class", "")
	var era := EmpireRules.unit_era(game, unit_type)
	for lo in eq(game).get("loadouts", []):
		if lo["classes"].has(cls) and lo["eras"].has(era):
			for s in lo["slots"]:
				if not result.has(s):
					result.append(s)
	_slots_cache[unit_type] = result
	return result


## Текущее снаряжение юнита с учётом значений по умолчанию.
static func equipment_of(game: Game, u: Unit) -> Dictionary:
	var result := {}
	var slots: Dictionary = eq(game).get("slots", {})
	for s in slots_for(game, u.type):
		var opt: String = u.equipment.get(s, slots[s].get("default", ""))
		if not slots[s]["options"].has(opt):
			opt = slots[s].get("default", "")
		result[s] = opt
	return result


static func option_def(game: Game, opt: String) -> Dictionary:
	return eq(game).get("options", {}).get(opt, {})


static func weight(game: Game, u: Unit) -> int:
	var w := 0
	var e := equipment_of(game, u)
	for s in e:
		w += int(option_def(game, e[s]).get("weight", 0))
	return w


static func is_heavy(game: Game, u: Unit) -> bool:
	if u.equipment.is_empty():
		return false   # снаряжение по умолчанию лёгкое
	return weight(game, u) >= int(eq(game).get("heavy_weight_threshold", 2))


## Модификаторы снаряжения для stat. ctx — как в Combat (role, vs_irregular, vs_ranged).
static func equipment_mods(game: Game, u: Unit, stat: String, ctx: Dictionary) -> Array:
	var result: Array = []
	if stat == "moves" and not slots_for(game, u.type).has("plating"):
		return result   # на ОД влияет только бронирование техники
	var e := equipment_of(game, u)
	var climate := climate_of(game, u.tile)
	for s in e:
		var od := option_def(game, e[s])
		var total := 0
		for m in od.get("mods", []):
			if m.get("stat", "combat") != stat:
				continue
			var when: Dictionary = m.get("when", {})
			if when.get("vs_regular", false) and ctx.get("vs_irregular", true):
				continue
			if when.get("vs_irregular", false) and not ctx.get("vs_irregular", false):
				continue
			if when.has("climate") and when["climate"] != climate:
				continue
			var rest := when.duplicate()
			rest.erase("vs_regular")
			rest.erase("vs_irregular")
			rest.erase("climate")
			if not Combat._when_ok(game, u, rest, ctx):
				continue
			total += int(m["value"])
		if total != 0:
			result.append([od.get("name", e[s]), total])
	return result


static func change_cost(game: Game, u: Unit, opt: String) -> int:
	var eras: Array = game.data.const_value("eras", [])
	var era_idx := maxi(0, eras.find(EmpireRules.unit_era(game, u.type)))
	return int(roundf(float(option_def(game, opt).get("gold", 10)) * (1.0 + era_idx * float(eq(game).get("gold_era_mult", 0.5)))))


static func equip_error(game: Game, u: Unit, slot: String, opt: String) -> String:
	if not slots_for(game, u.type).has(slot):
		return "У этого юнита нет такого слота"
	if not eq(game)["slots"][slot]["options"].has(opt):
		return "Нет такого варианта"
	if equipment_of(game, u)[slot] == opt:
		return "Уже надето"
	var oc := game.state.city_owning(u.tile)
	if oc == null or oc.owner != u.owner:
		return "Сменить снаряжение можно только на своей территории"
	var p := game.state.player(u.owner)
	if p.treasury < change_cost(game, u, opt):
		return "Не хватает золота"
	var res: Dictionary = option_def(game, opt).get("resource", {})
	for r in res:
		if float(p.stockpile.get(r, 0.0)) < float(res[r]):
			return "Нужно %d ед. ресурса «%s»" % [int(res[r]), game.data.resources[r]["name"]]
	return ""


static func equip(game: Game, u: Unit, slot: String, opt: String, events: Array) -> void:
	var p := game.state.player(u.owner)
	p.treasury -= change_cost(game, u, opt)
	var res: Dictionary = option_def(game, opt).get("resource", {})
	for r in res:
		p.stockpile[r] = float(p.stockpile.get(r, 0.0)) - float(res[r])
		DiplomacyRules.record_spend(game, u.owner, r, float(res[r]))
	u.equipment[slot] = opt
	events.append({"type": "unit_equipped", "unit": u.id, "slot": slot, "option": opt})


# --- Командующие ----------------------------------------------------------------------------

static func is_commander(game: Game, u: Unit) -> bool:
	return game.data.unit_def(u.type).get("abilities", []).has("COMMAND")


## Название командующего по эпохе державы (у цивилизации — свои звания).
static func commander_name(game: Game, owner: int, unit_type: String = "COMMANDER") -> String:
	var era := UnitRules.player_era(game, owner)
	var civ := Abilities.civ_def(game, owner)
	var names: Dictionary = civ.get("commander_names", {})
	if names.has(era):
		return names[era]
	return game.data.unit_def(unit_type).get("era_names", {}).get(era, game.data.unit_def(unit_type).get("name", "Командир"))


static func detachment_name(game: Game, owner: int) -> String:
	var civ := Abilities.civ_def(game, owner)
	if civ.has("detachment_name"):
		return civ["detachment_name"]
	return game.data.placeholder_detachment_name


static func attach_error(game: Game, cmd: Unit, target: Unit) -> String:
	if not is_commander(game, cmd):
		return "Это не командующий"
	if target == null or target.owner != cmd.owner or target.tile != cmd.tile:
		return "Войска должны стоять на той же клетке"
	if ConcessionRules.legal_owner(game, target) != target.owner:
		return "Нельзя присоединить командующего к подкреплению"
	if not Combat.can_attack(game, target) or Movement.domain(game, target) != "LAND":
		return "Командующий ведёт только наземные боевые войска"
	if not target.commander.is_empty():
		return "У этих войск уже есть командующий"
	return ""


static func attach(game: Game, cmd: Unit, target: Unit, events: Array) -> void:
	target.commander = {"xp": cmd.xp, "level": cmd.level}
	game.state.remove_unit(cmd.id)
	events.append({"type": "commander_attached", "unit": target.id, "commander": cmd.id})


static func detach(game: Game, u: Unit, events: Array) -> Unit:
	if u.commander.is_empty():
		return null
	var cmd := game.state.add_unit(u.owner, "COMMANDER", u.tile)
	cmd.xp = int(u.commander.get("xp", 0))
	cmd.level = int(u.commander.get("level", 0))
	cmd.moves_left = 0.0
	u.commander = {}
	u.moves_left = minf(u.moves_left, Movement.max_moves(game, u))
	events.append({"type": "commander_detached", "unit": u.id, "commander": cmd.id})
	return cmd


## Отряд разбит или командующего застали одного: командующий отступает раненым в ближайший город.
static func retreat_commander(game: Game, owner: int, xp: int, level: int, events: Array) -> void:
	var cities := game.state.cities_of(owner)
	if cities.is_empty():
		events.append({"type": "commander_lost", "owner": owner})
		return
	var best: City = cities[0]
	var cmd := game.state.add_unit(owner, "COMMANDER", best.tile)
	cmd.xp = xp
	cmd.level = level
	cmd.hp = int(game.data.const_value("commander_retreat_hp", 50))
	cmd.moves_left = 0.0
	events.append({"type": "commander_retreated", "commander": cmd.id, "city": best.id})


## Вызывать перед удалением погибшего юнита.
static func on_unit_killed(game: Game, u: Unit, events: Array) -> void:
	if not u.commander.is_empty():
		retreat_commander(game, u.owner, int(u.commander.get("xp", 0)), int(u.commander.get("level", 0)), events)


static func commander_combat(game: Game, u: Unit) -> int:
	if u.commander.is_empty():
		return 0
	var base := int(Abilities.param(game, "COMMAND", "combat", 7))
	var lvl := mini(int(u.commander.get("level", 0)) * int(Abilities.param(game, "COMMAND", "per_level", 1)),
		int(Abilities.param(game, "COMMAND", "max_level_bonus", 5)))
	return base + lvl


static func commander_moves(game: Game, u: Unit) -> int:
	return 0 if u.commander.is_empty() else int(Abilities.param(game, "COMMAND", "moves", 1))


## Опыт командующего растёт вместе с опытом его войск.
static func add_commander_xp(game: Game, u: Unit, amount: int) -> void:
	if u.commander.is_empty():
		return
	var xp := int(u.commander.get("xp", 0)) + amount
	var level := int(u.commander.get("level", 0))
	while xp >= Combat.xp_for_level(level + 1):
		level += 1
	u.commander = {"xp": xp, "level": level}
