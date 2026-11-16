class_name Movement
extends RefCounted
## Правила движения (ГДД 3.5).
##
## Главное правило Civ VI: войти в клетку можно, только если осталось ОД не
## меньше стоимости входа; исключение — юнит с полным запасом ОД всегда может
## сделать шаг в любую проходимую клетку. Пересечение реки без моста тратит все
## оставшиеся ОД. Вход в зону контроля врага обнуляет ОД.

## Вернуть при невозможности войти.
const IMPASSABLE := -1.0
## Стоимость «все оставшиеся ОД» (река без моста).
const ALL_MOVES := -2.0


static func max_moves(game: Game, unit: Unit) -> float:
	var m := float(game.data.unit_def(unit.type).get("moves", 1)) + Combat.promo_stat(game, unit, "moves", {})
	m += Army.commander_moves(game, unit)
	for mod in Army.equipment_mods(game, unit, "moves", {}):
		m += float(mod[1])
	return m


static func domain(game: Game, unit: Unit) -> String:
	return game.data.unit_def(unit.type).get("domain", "LAND")


static func layer(game: Game, unit_type: String) -> String:
	var def := game.data.unit_def(unit_type)
	return def.get("layer", game.data.unit_classes.get(def.get("class", ""), {}).get("layer", "COMBAT"))


## Может ли юнит в принципе находиться на клетке (ландшафт, домен, технологии).
## known=false — клетка не разведана игроком: считаем проходимой (как в оригинале).
static func can_stand(game: Game, unit: Unit, tile: int, known: bool = true) -> bool:
	if not known:
		return true
	var map := game.state.map
	if map.feature_def(tile).get("impassable", false):
		return false
	var dom := domain(game, unit)
	if dom == "LAND":
		# Посадка на корабли (embark) — следующие вехи.
		return map.is_land(tile) and not map.is_mountain(tile)
	if dom == "SEA":
		if not map.is_water(tile):
			return false
		var req: String = map.terrain_def(tile).get("requires_tech", "")
		return req == "" or game.state.player(unit.owner).has_tech(req)
	return false


## Базовая стоимость входа в клетку (без учёта рек и ZOC).
static func terrain_cost(game: Game, tile: int) -> float:
	var map := game.state.map
	var cost := float(map.terrain_def(tile).get("move_cost", 1))
	var fdef := map.feature_def(tile)
	if not fdef.is_empty() and fdef.has("move_cost"):
		cost = maxf(cost, float(fdef["move_cost"]))
	if map.is_hills(tile):
		cost += float(game.data.relief["HILLS"].get("move_cost_add", 1))
	return cost


## Стоимость шага from -> to (соседние клетки) для юнита: число, ALL_MOVES или IMPASSABLE.
## known — разведана ли клетка назначения (для планирования пути игроком).
static func step_cost(game: Game, unit: Unit, from: int, to: int, known: bool = true) -> float:
	if not can_stand(game, unit, to, known):
		return IMPASSABLE
	if not known:
		return 1.0
	var map := game.state.map
	var dir := map.grid.direction_to(from, to)
	if dom_is_land(game, unit) and map.has_river_edge(from, dir) and not _has_bridge(game, from, to):
		return ALL_MOVES
	if dom_is_land(game, unit) and map.road[from] > 0 and map.road[to] > 0:
		return road_cost(game, mini(map.road[from], map.road[to]))
	var cost := terrain_cost(game, to)
	# Тяжёлое снаряжение: +1 ОД на холмах, в лесу и джунглях.
	if (map.is_hills(to) or map.feature[to] == "WOODS" or map.feature[to] == "RAINFOREST") and Army.is_heavy(game, unit):
		cost += 1.0
	# Повышения разведчиков: лес/холмы стоят 1 ОД.
	if unit.promotions.size() > 0:
		if (map.feature[to] == "WOODS" or map.feature[to] == "RAINFOREST") and Combat.has_flag(game, unit, "woods_cost_1"):
			cost = 1.0 + (1.0 if map.is_hills(to) and not Combat.has_flag(game, unit, "hills_cost_1") else 0.0)
		elif map.is_hills(to) and Combat.has_flag(game, unit, "hills_cost_1"):
			cost = maxf(1.0, cost - 1.0)
	return cost


static func road_cost(game: Game, level: int) -> float:
	var levels: Array = game.data.const_value("road_levels", [])
	if level <= 0 or levels.is_empty():
		return 1.0
	return float(levels[mini(level, levels.size()) - 1].get("cost", 1.0))


static func dom_is_land(game: Game, unit: Unit) -> bool:
	return domain(game, unit) == "LAND"


## Мост — дороги классического уровня и выше по обе стороны реки (ГДД 3.4, 3.8).
static func _has_bridge(game: Game, from: int, to: int) -> bool:
	var need: int = int(game.data.const_value("road_bridge_level", 2))
	return game.state.map.road[from] >= need and game.state.map.road[to] >= need


## Находится ли клетка в зоне контроля врага для этого юнита (ГДД 3.5).
## only_visible — учитывать только видимых игроку врагов (для планирования).
static func in_enemy_zoc(game: Game, unit: Unit, tile: int, only_visible: bool = false) -> bool:
	var cls: Dictionary = game.data.unit_class_def(unit.type)
	if cls.get("ignores_zoc", false):
		return false
	var map := game.state.map
	if map.is_water(tile):
		return false
	var me := game.state.player(unit.owner)
	for d in HexGrid.DIR_COUNT:
		var nb := map.grid.neighbor(tile, d)
		if nb < 0 or map.is_water(nb) or map.has_river_edge(tile, d):
			continue
		if only_visible and not me.is_visible(nb):
			continue
		for other in game.state.units_at(nb):
			if other.owner == unit.owner or not game.state.at_war(unit.owner, other.owner):
				continue
			if game.data.unit_class_def(other.type).get("exerts_zoc", false):
				return true
	return false


## Можно ли войти в клетку с учётом других юнитов (стэкинг, чужие юниты).
## final=true — юнит закончит здесь движение (нужен свободный слой).
static func occupancy_allows(game: Game, unit: Unit, tile: int, final: bool,
		only_visible: bool = false) -> bool:
	var me := game.state.player(unit.owner)
	if only_visible and not me.is_visible(tile):
		return true
	var my_layer := layer(game, unit.type)
	for other in game.state.units_at(tile):
		if other.id == unit.id or not other.trade_route.is_empty():
			continue
		if other.owner != unit.owner:
			return false   # атака — отдельное действие (веха M3)
		if final and my_layer != "TRADE" and layer(game, other.type) == my_layer:
			return false
	return true


## Результат шага при оставшихся ОД moves: новые ОД или -1, если шаг невозможен.
static func moves_after_step(game: Game, unit: Unit, from: int, to: int, moves: float,
		known: bool = true, zoc_visible_only: bool = false) -> float:
	var cost := step_cost(game, unit, from, to, known)
	if cost == IMPASSABLE or moves <= 0.0:
		return -1.0
	var full := moves >= max_moves(game, unit)
	var left: float
	if cost == ALL_MOVES:
		left = 0.0
	elif moves >= cost or full:
		left = maxf(0.0, moves - cost)
	else:
		return -1.0
	if known and in_enemy_zoc(game, unit, to, zoc_visible_only):
		left = 0.0
	return left
