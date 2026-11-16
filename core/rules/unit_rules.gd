class_name UnitRules
extends RefCounted
## Действия юнитов вне боя (ГДД 9.3, 9.5, 8.2, 3.6, 3.8) и война/мир (17.4, упрощённо).


static func k(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


# --- Эпоха державы -------------------------------------------------------------------------

## Эпоха державы — эпоха самой поздней изученной технологии (или древность).
static func player_era(game: Game, pid: int) -> String:
	var eras: Array = k(game, "eras", [])
	var best := 0
	for t in game.state.player(pid).known_techs:
		best = maxi(best, eras.find(game.data.techs.get(t, {}).get("era", "ANCIENT")))
	return eras[best] if not eras.is_empty() else "ANCIENT"


# --- Укрепление и лечение -----------------------------------------------------------------------

static func fortify_error(game: Game, u: Unit) -> String:
	if Movement.layer(game, u.type) != "COMBAT":
		return "Укрепляться могут только боевые юниты"
	return ""


static func heal_amount(game: Game, u: Unit) -> int:
	var map := game.state.map
	var city := game.state.city_at(u.tile)
	if Movement.domain(game, u) == "SEA":
		var oc := game.state.city_owning(u.tile)
		var own := oc != null and oc.owner == u.owner
		if not own and not Combat.has_flag(game, u, "heal_anywhere"):
			return 0
	if city != null and city.owner == u.owner:
		return int(k(game, "heal_city", 20))
	var owner_city := game.state.city_owning(u.tile)
	if owner_city == null:
		return int(k(game, "heal_neutral", 10))
	if owner_city.owner == u.owner:
		return int(k(game, "heal_own", 15))
	if game.state.at_war(u.owner, owner_city.owner):
		return int(k(game, "heal_enemy", 5))
	return int(k(game, "heal_neutral", 10))


## Начало хода для юнитов игрока: лечение бездействовавших, рост укрепления, содержание ресурсов.
static func process_units_turn_start(game: Game, pid: int, events: Array) -> void:
	var p := game.state.player(pid)
	for u in game.state.units_of(pid):
		if not u.acted and u.hp < 100:
			var amount := heal_amount(game, u)
			# Флагман лечит соседние корабли.
			if Movement.domain(game, u) == "SEA":
				for other in Combat._units_near(game, u.tile, 1):
					if other.owner == u.owner and Abilities.has(game, other, "FLAGSHIP_AURA"):
						amount += int(Abilities.param(game, "FLAGSHIP_AURA", "heal", 10))
						break
			# При нехватке ресурса содержания юнит не лечится (ГДД 3.6).
			for res in game.data.unit_def(u.type).get("resource_per_turn", {}):
				if float(p.stockpile.get(res, 0.0)) <= 0.0:
					amount = 0
			u.hp = mini(100, u.hp + amount)
		# Экстремальный холод без зимней одежды (docs/ARMY.md).
		if Movement.domain(game, u) == "LAND" and Army.is_extreme_cold(game, u.tile):
			var e := Army.equipment_of(game, u)
			if e.has("clothing") and e["clothing"] != "WINTER":
				var cl: Dictionary = game.data.equipment.get("climate", {})
				u.hp = maxi(int(cl.get("extreme_cold_min_hp", 10)), u.hp - int(cl.get("extreme_cold_hp_loss", 10)))
				events.append({"type": "unit_frostbite", "unit": u.id})
		if u.orders.get("type", "") == "fortify":
			u.fortify_turns = mini(u.fortify_turns + 1, 2)
		elif game.state.map.improvement[u.tile] == "FORT" and Movement.layer(game, u.type) == "COMBAT":
			u.fortify_turns = 2
		else:
			u.fortify_turns = 0


# --- Повышения и модернизация ---------------------------------------------------------------------

static func promote_error(game: Game, u: Unit, promo: String) -> String:
	if not Combat.available_promotions(game, u).has(promo):
		return "Это повышение недоступно"
	return ""


static func promote(game: Game, u: Unit, promo: String, events: Array) -> void:
	u.promotions.append(promo)
	u.level += 1
	u.hp = mini(100, u.hp + int(k(game, "promotion_heal", 50)))
	u.moves_left = 0.0
	u.acted = true
	events.append({"type": "unit_promoted", "unit": u.id, "promotion": promo})


## Во что модернизируется юнит: ближайший открытый в линии (можно перепрыгнуть ступени).
static func upgrade_target(game: Game, u: Unit) -> String:
	var p := game.state.player(u.owner)
	var cur: String = game.data.unit_def(u.type).get("upgrades_to", "")
	var best := ""
	while cur != "":
		var def := game.data.unit_def(cur)
		if (def.has("tech") and not p.has_tech(def["tech"])) or (def.has("civic") and not p.has_civic(def["civic"])):
			break
		best = cur
		cur = def.get("upgrades_to", "")
	return best


static func upgrade_cost(game: Game, u: Unit, target: String) -> int:
	var d := float(game.data.unit_def(target).get("cost", 0)) - float(game.data.unit_def(u.type).get("cost", 0))
	var cost := maxf(0.0, d) * float(k(game, "upgrade_cost_mult", 2)) + float(k(game, "upgrade_cost_add", 10))
	var discount := GovernmentRules.sum_effect(game, u.owner, "upgrade_discount")
	return int(cost * clampf(1.0 - discount, 0.0, 1.0))


static func upgrade_error(game: Game, u: Unit) -> String:
	var target := upgrade_target(game, u)
	if target == "":
		return "Нет доступной модернизации"
	if u.moves_left <= 0.0:
		return "Нет очков движения"
	var oc := game.state.city_owning(u.tile)
	if oc == null or oc.owner != u.owner:
		return "Модернизация — только на своей территории"
	var p := game.state.player(u.owner)
	if p.treasury < upgrade_cost(game, u, target):
		return "Не хватает золота"
	var res: Dictionary = game.data.unit_def(target).get("resource", {})
	for r in res:
		if float(p.stockpile.get(r, 0.0)) < float(res[r]):
			return "Не хватает ресурса: %s" % game.data.resources[r]["name"]
	return ""


static func upgrade(game: Game, u: Unit, events: Array) -> void:
	var target := upgrade_target(game, u)
	var p := game.state.player(u.owner)
	p.treasury -= upgrade_cost(game, u, target)
	var res: Dictionary = game.data.unit_def(target).get("resource", {})
	for r in res:
		p.stockpile[r] = float(p.stockpile.get(r, 0.0)) - float(res[r])
		DiplomacyRules.record_spend(game, u.owner, r, float(res[r]))
	var old := u.type
	u.type = target
	u.moves_left = 0.0
	u.acted = true
	note_strength(game, u.owner, target)
	events.append({"type": "unit_upgraded", "unit": u.id, "from": old, "to": target})


## Запоминает сильнейший юнит ближнего/дальнего боя (оборона города, ГДД 5.7).
static func note_strength(game: Game, pid: int, unit_type: String) -> void:
	var p := game.state.player(pid)
	if Movement.layer(game, unit_type) != "COMBAT" or game.data.unit_def(unit_type).get("domain", "LAND") != "LAND":
		return
	var m := Combat.melee_strength(game, unit_type)
	var r := Combat.ranged_strength(game, unit_type)
	if r == 0 and m > int(p.best_strength.get("melee", 0)):
		p.best_strength["melee"] = m
	if r > int(p.best_strength.get("ranged", 0)):
		p.best_strength["ranged"] = r


# --- Грабёж и ремонт (ГДД 8.2) ------------------------------------------------------------------

static func pillage_error(game: Game, u: Unit) -> String:
	if not Combat.can_attack(game, u):
		return "Грабить могут только боевые юниты"
	if u.moves_left <= 0.0:
		return "Нет очков движения"
	var map := game.state.map
	var imp := map.improvement[u.tile]
	if imp == "" or map.pillaged[u.tile] == 1 or game.data.improvements.get(imp, {}).get("special", false):
		return "Здесь нечего грабить"
	var oc := game.state.city_owning(u.tile)
	if oc == null or not game.state.at_war(u.owner, oc.owner):
		return "Грабить можно только землю врага"
	return ""


static func pillage(game: Game, u: Unit, events: Array) -> void:
	var cfg: Dictionary = game.data.improvements_extra.get("pillage", {})
	game.state.map.pillaged[u.tile] = 1
	var gold := float(cfg.get("gold", 25))
	if Combat.has_flag(game, u, "loot"):
		gold *= 1.5
	game.state.player(u.owner).treasury += gold
	u.hp = mini(100, u.hp + int(cfg.get("heal", 50)))
	var cost := 1.0 if Combat.has_flag(game, u, "cheap_pillage") else float(cfg.get("move_cost", 3))
	u.moves_left = maxf(0.0, u.moves_left - cost)
	u.acted = true
	var oc := game.state.city_owning(u.tile)
	if oc != null:
		CityRules.assign_citizens(game, oc)
	events.append({"type": "pillaged", "unit": u.id, "tile": u.tile, "gold": gold})


static func repair_error(game: Game, u: Unit) -> String:
	if not game.data.unit_def(u.type).get("abilities", []).has("BUILD_IMPROVEMENT"):
		return "Чинить могут строители"
	if game.state.map.pillaged[u.tile] == 0:
		return "Здесь нечего чинить"
	var oc := game.state.city_owning(u.tile)
	if oc == null or oc.owner != u.owner:
		return "Чинить можно только на своей территории"
	if u.moves_left <= 0.0:
		return "Нет очков движения"
	return ""


# --- Дороги (ГДД 3.8; римская особенность — docs/CIVS.md) ---------------------------------------------

static func road_level_for(game: Game, pid: int) -> int:
	var table: Dictionary = k(game, "road_level_by_era", {})
	return int(table.get(player_era(game, pid), 1))


static func build_road_error(game: Game, u: Unit) -> String:
	var roman := Abilities.has(game, u, "ROAD_INSTEAD_OF_MOVE")
	var engineer := Abilities.has(game, u, "BUILD_ROAD")
	if not roman and not engineer:
		return "Этот юнит не строит дороги"
	var map := game.state.map
	if map.is_water(u.tile) or map.is_mountain(u.tile):
		return "Дорогу можно проложить только по суше"
	if map.road[u.tile] >= road_level_for(game, u.owner):
		return "Здесь уже есть дорога"
	var oc := game.state.city_owning(u.tile)
	if oc != null and oc.owner != u.owner and not game.state.at_war(u.owner, oc.owner):
		return "Нельзя строить дороги на чужой земле"
	if roman and not engineer:
		if u.moves_left < Movement.max_moves(game, u) or u.acted:
			return "Дорогу прокладывают вместо движения — юнит уже действовал в этот ход"
	elif u.charges <= 0:
		return "Нет зарядов"
	return ""


static func build_road(game: Game, u: Unit, events: Array) -> void:
	game.state.map.road[u.tile] = road_level_for(game, u.owner)
	if Abilities.has(game, u, "ROAD_INSTEAD_OF_MOVE"):
		u.moves_left = 0.0
	else:
		u.charges -= 1
		u.moves_left = 0.0
	u.acted = true
	u.fortify_turns = 0
	events.append({"type": "road_built", "unit": u.id, "tile": u.tile})


static func build_fort_error(game: Game, u: Unit) -> String:
	if not Abilities.has(game, u, "BUILD_FORT"):
		return "Этот юнит не строит форты"
	# Легионер получает это действие от своей цивилизации раньше инженера.
	var required: String = game.data.improvements.get("FORT", {}).get("tech", "")
	if required != "" and game.data.unit_def(u.type).get("abilities", []).has("BUILD_FORT") \
			and not game.state.player(u.owner).has_tech(required):
		return "Нужно изучить: %s" % game.data.techs[required]["name"]
	if u.charges <= 0:
		return "Нет зарядов"
	var map := game.state.map
	if map.is_water(u.tile) or map.is_mountain(u.tile) or game.state.city_at(u.tile) != null:
		return "Здесь нельзя построить форт"
	if map.improvement[u.tile] == "FORT":
		return "Форт уже есть"
	var oc := game.state.city_owning(u.tile)
	if oc != null and oc.owner != u.owner:
		return "Нельзя строить на чужой земле"
	if u.moves_left <= 0.0:
		return "Нет очков движения"
	return ""


static func build_fort(game: Game, u: Unit, events: Array) -> void:
	var map := game.state.map
	map.improvement[u.tile] = "FORT"
	map.pillaged[u.tile] = 0
	u.charges -= 1
	u.moves_left = 0.0
	u.acted = true
	u.fortify_turns = 2
	events.append({"type": "improvement_built", "tile": u.tile, "improvement": "FORT"})


# --- Стратегические ресурсы (ГДД 3.6) -----------------------------------------------------------------

static func strategic_income(game: Game, pid: int) -> Dictionary:
	var result := {}
	var p := game.state.player(pid)
	var per := float(k(game, "strategic_per_source", 2))
	for city in game.state.cities_of(pid):
		for t in CityRules.owned_tiles(game, city):
			var rid := game.state.map.resource[t]
			if rid == "" or game.data.resources[rid].get("class", "") != "strategic":
				continue
			if Yields.resource_visible(game.data, rid, p) and CityRules.resource_improved(game, t) \
					and game.state.map.pillaged[t] == 0:
				result[rid] = float(result.get(rid, 0.0)) + per
	return result


static func process_stockpile(game: Game, pid: int) -> void:
	var p := game.state.player(pid)
	var cap := float(k(game, "strategic_cap", 50))
	var inc := strategic_income(game, pid)
	for u in game.state.units_of(pid):
		var upkeep: Dictionary = game.data.unit_def(u.type).get("resource_per_turn", {})
		for r in upkeep:
			inc[r] = float(inc.get(r, 0.0)) - float(upkeep[r])
	for r in inc:
		p.stockpile[r] = clampf(float(p.stockpile.get(r, 0.0)) + float(inc[r]), 0.0, cap)


# --- Война и мир ------------------------------------------------------------------------------------------

static func declare_war_error(game: Game, pid: int, target: int) -> String:
	if target < 0 or target >= game.state.players.size() or target == pid:
		return "Нет такой державы"
	var t := game.state.player(target)
	if t.is_barbarian or not t.alive:
		return "С ними нельзя объявить войну"
	if not game.state.player(pid).met.has(target):
		return "Вы ещё не встретились"
	if game.state.at_war(pid, target):
		return "Война уже идёт"
	if game.state.turns_since_war_change(pid, target) < int(k(game, "peace_min_turns", 10)):
		return "После мира нельзя воевать %d ходов" % int(k(game, "peace_min_turns", 10))
	return ""


static func make_peace_error(game: Game, pid: int, target: int) -> String:
	if target < 0 or target >= game.state.players.size() or target == pid:
		return "Нет такой державы"
	if game.state.player(target).is_barbarian:
		return "С варварами мир невозможен"
	if not game.state.at_war(pid, target):
		return "Войны нет"
	if game.state.turns_since_war_change(pid, target) < int(k(game, "war_min_turns", 10)):
		return "Мир можно заключить через %d ходов после объявления войны" % int(k(game, "war_min_turns", 10))
	return ""
