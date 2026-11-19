class_name Combat
extends RefCounted
## Боевая система (ГДД 9.4–9.6, 5.7).
##
## Цель атаки — клетка. На ней может быть город (бой идёт с городом, гарнизон
## усиливает его оборону), боевой юнит или только гражданские (их захватывают).


static func k(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


static func unit_class(game: Game, u: Unit) -> String:
	return game.data.unit_def(u.type).get("class", "")


static func melee_strength(game: Game, unit_type: String) -> int:
	return int(game.data.unit_def(unit_type).get("combat", 0))


static func embarked_defense(game: Game, unit: Unit) -> int:
	var eras: Array = k(game, "eras", [])
	var rank := maxi(0, eras.find(UnitRules.player_era(game, unit.owner)))
	return int(k(game, "embark_defense_base", 10)) \
		+ rank * int(k(game, "embark_defense_per_era", 5))


static func ranged_strength(game: Game, unit_type: String) -> int:
	return int(game.data.unit_def(unit_type).get("ranged", 0))


static func is_ranged(game: Game, u: Unit) -> bool:
	return ranged_strength(game, u.type) > 0


static func can_attack(game: Game, u: Unit) -> bool:
	if Movement.layer(game, u.type) != "COMBAT" or TreatyRules.withdrawing(game, u):
		return false
	return melee_strength(game, u.type) > 0 or ranged_strength(game, u.type) > 0


static func attack_range(game: Game, u: Unit) -> int:
	var r := int(game.data.unit_def(u.type).get("range", 1))
	r += promo_stat(game, u, "range", {})
	# Корректировщик рядом даёт +1 осадным.
	if unit_class(game, u) == "SIEGE":
		for other in _units_near(game, u.tile, 1):
			if other.owner == u.owner and Abilities.has(game, other, "SIEGE_SPOTTER"):
				r += int(Abilities.param(game, "SIEGE_SPOTTER", "range", 1))
				break
	return r


static func _units_near(game: Game, tile: int, radius: int) -> Array[Unit]:
	var result: Array[Unit] = []
	var grid := game.state.map.grid
	for id in game.state.units:
		var other: Unit = game.state.units[id]
		if other.tile != tile and grid.distance(other.tile, tile) <= radius:
			result.append(other)
	return result


# --- Опыт и повышения (ГДД 9.6) ----------------------------------------------------------

static func xp_for_level(n: int) -> int:
	return 15 * n * (n + 1) / 2


static func can_promote(u: Unit) -> bool:
	return u.xp >= xp_for_level(u.level + 1)


## Сумма числовых эффектов повышений юнита для stat при условиях ctx.
static func promo_stat(game: Game, u: Unit, stat: String, ctx: Dictionary) -> int:
	var total := 0
	for pid in u.promotions:
		var pr: Dictionary = game.data.promotions.get(pid, {})
		for m in pr.get("mods", []):
			if m.get("stat", "combat") != stat:
				continue
			if _when_ok(game, u, m.get("when", {}), ctx):
				total += int(m["value"])
	return total


static func has_flag(game: Game, u: Unit, flag: String) -> bool:
	for pid in u.promotions:
		if game.data.promotions.get(pid, {}).get("flags", []).has(flag):
			return true
	return false


static func _when_ok(game: Game, u: Unit, when: Dictionary, ctx: Dictionary) -> bool:
	if when.has("role") and when["role"] != ctx.get("role", ""):
		return false
	if when.has("vs_class") and not when["vs_class"].has(ctx.get("vs_class", "")):
		return false
	if when.get("vs_ranged", false) and not ctx.get("vs_ranged", false):
		return false
	if when.get("vs_district", false) and not ctx.get("vs_district", false):
		return false
	if when.get("vs_units", false) and ctx.get("vs_district", false):
		return false
	if when.has("vs_domain") and when["vs_domain"] != ctx.get("vs_domain", ""):
		return false
	if when.get("vs_wounded", false) and not ctx.get("vs_wounded", false):
		return false
	if when.get("vs_fortified", false) and not ctx.get("vs_fortified", false):
		return false
	if when.get("in_district", false) and not _in_district(game, u.tile):
		return false
	if when.has("terrain"):
		var map := game.state.map
		var here := [map.feature[u.tile]]
		if map.is_hills(u.tile):
			here.append("HILLS")
		var ok := false
		for t in when["terrain"]:
			if here.has(t):
				ok = true
		if not ok:
			return false
	return true


static func _in_district(game: Game, tile: int) -> bool:
	return game.state.city_at(tile) != null or game.state.map.improvement[tile] == "FORT"


static func available_promotions(game: Game, u: Unit) -> Array[String]:
	var result: Array[String] = []
	if not can_promote(u):
		return result
	var cls := unit_class(game, u)
	var tiers_have := {}
	for pid in u.promotions:
		tiers_have[int(game.data.promotions.get(pid, {}).get("tier", 0))] = true
	for pid in game.data.promotion_ids:
		var pr: Dictionary = game.data.promotions[pid]
		if pr["class"] != cls or u.promotions.has(pid):
			continue
		var tier := int(pr["tier"])
		if tier == 1 or tiers_have.has(tier - 1):
			result.append(pid)
	return result


static func add_xp(game: Game, u: Unit, amount: int, vs_barbarian: bool) -> void:
	Army.add_commander_xp(game, u, amount)
	u.xp += amount
	if vs_barbarian:
		var cap := xp_for_level(int(k(game, "xp_barbarian_cap_level", 1)))
		if u.level == 0 and u.xp > cap:
			u.xp = cap


# --- Сила с модификаторами (ГДД 9.4) ------------------------------------------------------

## Модификаторы обороны/атаки юнита. Возвращает [[подпись, значение], ...].
static func unit_mods(game: Game, u: Unit, role: String, ctx: Dictionary) -> Array:
	var mods: Array = []
	if ctx.has("vs_player"):
		var visibility_bonus := DiplomaticVisibility.combat_bonus(game, u.owner, int(ctx["vs_player"]))
		if visibility_bonus > 0:
			mods.append(["Дипломатическая видимость", visibility_bonus])
		var alliance_bonus := TreatyRules.shared_enemy_bonus(game, u.owner, int(ctx["vs_player"]))
		if alliance_bonus > 0:
			mods.append(["Военный союз", alliance_bonus])
	if ctx.get("vs_irregular", false):
		for effect in GovernmentRules.effects(game, game.state.player(u.owner)):
			if effect.has("barbarian_strength"):
				mods.append([effect["name"], int(effect["barbarian_strength"])])
	var map := game.state.map
	var lost := 100 - u.hp
	if lost > 0:
		mods.append(["Ранения", -mini(int(k(game, "wound_penalty_max", 10)), lost / 10 * int(k(game, "wound_penalty_per_10hp", 1)))])
	if role == "defense" and Movement.is_embarked(game, u):
		return mods
	if role == "defense" and Movement.domain(game, u) == "LAND" and not Movement.is_embarked(game, u):
		var td: Dictionary = k(game, "terrain_defense", {})
		if map.is_hills(u.tile):
			mods.append(["Холмы", int(td.get("HILLS", 3))])
		var f := map.feature[u.tile]
		if td.has(f):
			mods.append([game.data.features[f]["name"], int(td[f])])
		var fort := mini(u.fortify_turns * int(k(game, "fortify_per_turn", 3)), int(k(game, "fortify_max", 6)))
		if map.improvement[u.tile] == "FORT" and not map.pillaged[u.tile]:
			mods.append(["Форт", int(game.data.improvements["FORT"].get("defense", 4))])
			fort = int(k(game, "fortify_max", 6))
		if fort > 0:
			mods.append(["Укрепление", fort])
	var cls_bonus: Dictionary = game.data.unit_class_def(u.type).get("bonus_vs", {})
	var vs_class: String = ctx.get("vs_class", "")
	if cls_bonus.has(vs_class):
		mods.append(["Против класса", int(cls_bonus[vs_class])])
	var cls_def: Dictionary = game.data.unit_class_def(u.type)
	if role == "attack" and ctx.get("ranged_attack", false):
		if ctx.get("vs_district", false) and cls_def.has("ranged_penalty_vs_districts"):
			mods.append(["Против города", -int(cls_def["ranged_penalty_vs_districts"])])
		if not ctx.get("vs_district", false) and cls_def.has("ranged_penalty_vs_units"):
			mods.append(["Осадное против юнитов", -int(cls_def["ranged_penalty_vs_units"])])
	# Особенности цивилизации.
	if Abilities.has(game, u, "TESTUDO") and role == "defense" and ctx.get("vs_ranged", false):
		mods.append(["Черепаха", int(Abilities.param(game, "TESTUDO", "defense_vs_ranged", 5))])
	if Abilities.has(game, u, "FORMATION"):
		var near := 0
		for other in _units_near(game, u.tile, 1):
			if other.owner == u.owner and Movement.layer(game, other.type) == "COMBAT":
				near += 1
		if near >= int(Abilities.param(game, "FORMATION", "min_adjacent", 2)):
			mods.append(["Строй", int(Abilities.param(game, "FORMATION", "combat", 4))])
	if Abilities.has(game, u, "LAST_STAND") and role == "defense":
		var oc := game.state.city_owning(u.tile)
		if oc != null and oc.owner == u.owner:
			mods.append(["Последний рубеж", int(Abilities.param(game, "LAST_STAND", "defense_in_own_territory", 5))])
	if Movement.domain(game, u) == "SEA":
		for other in _units_near(game, u.tile, int(Abilities.param(game, "FLAGSHIP_AURA", "radius", 1))):
			if other.owner == u.owner and Abilities.has(game, other, "FLAGSHIP_AURA"):
				mods.append(["Флагман", int(Abilities.param(game, "FLAGSHIP_AURA", "combat", 3))])
				break
	# Фланги и поддержка (с института «Военная традиция»).
	var civic: String = k(game, "flanking_civic", "")
	if civic == "" or game.state.player(u.owner).has_civic(civic):
		if role == "attack" and not ctx.get("ranged_attack", false) and ctx.has("target_tile"):
			var flank := 0
			for other in _units_near(game, int(ctx["target_tile"]), 1):
				if other.owner == u.owner and other.id != u.id and Movement.layer(game, other.type) == "COMBAT":
					flank += 1
			if flank > 0:
				mods.append(["Фланг", flank * int(k(game, "flanking_bonus", 2))])
		if role == "defense":
			var sup := 0
			for other in _units_near(game, u.tile, 1):
				if other.owner == u.owner and Movement.layer(game, other.type) == "COMBAT":
					sup += 1
			if sup > 0:
				mods.append(["Поддержка", sup * int(k(game, "support_bonus", 2))])
	for em in Army.equipment_mods(game, u, "combat", ctx.merged({"role": role})):
		mods.append(em)
	var cb := Army.commander_combat(game, u)
	if cb > 0:
		mods.append(["Командующий", cb])
	var promo := promo_stat(game, u, "combat", ctx.merged({"role": role}))
	if ctx.get("ranged_attack", false) and role == "attack":
		promo += promo_stat(game, u, "ranged", ctx.merged({"role": role}))
	if promo != 0:
		mods.append(["Повышения", promo])
	return mods


static func _sum(mods: Array) -> int:
	var s := 0
	for m in mods:
		s += int(m[1])
	return s


## Сила обороны города (ГДД 5.7).
static func city_strength(game: Game, city: City) -> Array:
	var p := game.state.player(city.owner)
	var base := int(p.best_strength.get("melee", 20)) + int(k(game, "city_strength_offset", -10))
	var mods: Array = []
	for u in game.state.units_at(city.tile):
		if u.owner == city.owner and Movement.layer(game, u.type) == "COMBAT":
			base = maxi(base, melee_strength(game, u.type))
	if game.state.map.is_hills(city.tile):
		mods.append(["Холмы", int(k(game, "city_hills_bonus", 3))])
	if city.is_capital:
		mods.append(["Столица", int(k(game, "city_capital_bonus", 3))])
	var lost := int(k(game, "city_hp", 200)) - city.hp
	if lost > 0:
		mods.append(["Повреждения", -mini(10, lost / 20)])
	return [base, mods]


static func city_ranged_strength(game: Game, city: City) -> int:
	var p := game.state.player(city.owner)
	var cs: Array = city_strength(game, city)
	return maxi(int(p.best_strength.get("ranged", 0)), int(cs[0]))


static func city_can_strike(game: Game, city: City) -> bool:
	return city.wall_hp > 0 and not city.has_attacked


# --- Урон ---------------------------------------------------------------------------

static func damage(game: Game, delta: int, roll: float) -> int:
	var base := float(k(game, "combat_base_damage", 30))
	var f := float(k(game, "combat_exp_factor", 0.04))
	return maxi(1, roundi(base * exp(f * delta) * roll))


static func _roll(game: Game) -> float:
	return game.state.rng.randf_range(float(k(game, "combat_rand_min", 0.8)), float(k(game, "combat_rand_max", 1.2)))


# --- Прогноз и выполнение атаки -----------------------------------------------------------

## Что находится на клетке цели для атакующего: {"kind": "city"|"unit"|"civilian"|"camp"|"", ...}.
static func target_at(game: Game, attacker_owner: int, tile: int) -> Dictionary:
	var city := game.state.city_at(tile)
	if city != null and city.owner != attacker_owner:
		return {"kind": "city", "city": city}
	var best: Unit = null
	var civilians: Array[Unit] = []
	for u in game.state.units_at(tile):
		if not u.trade_route.is_empty():
			continue
		if u.owner == attacker_owner:
			return {"kind": ""}
		if Movement.layer(game, u.type) == "COMBAT":
			if best == null or melee_strength(game, u.type) > melee_strength(game, best.type):
				best = u
		else:
			civilians.append(u)
	if best != null:
		return {"kind": "unit", "unit": best}
	if not civilians.is_empty():
		return {"kind": "civilian", "units": civilians}
	if game.state.map.improvement[tile] == "BARBARIAN_CAMP":
		return {"kind": "camp"}
	return {"kind": ""}


## Причина, по которой атака невозможна, или "".
static func attack_error(game: Game, u: Unit, tile: int) -> String:
	if not can_attack(game, u):
		return "Этот юнит не сражается"
	if u.moves_left <= 0.0:
		return "Нет очков движения"
	if Movement.is_embarked(game, u):
		if is_ranged(game, u) or game.state.map.is_water(tile):
			return "Посаженный юнит может атаковать только при высадке на сушу"
		if Movement.step_cost(game, u, u.tile, tile) == Movement.IMPASSABLE:
			return "Здесь нельзя высадиться"
	var t := target_at(game, u.owner, tile)
	if t["kind"] == "" or t["kind"] == "camp":
		return "Здесь некого атаковать"
	var other_owner := -1
	if t["kind"] == "city":
		other_owner = t["city"].owner
	elif t["kind"] == "unit":
		other_owner = t["unit"].owner
	else:
		other_owner = t["units"][0].owner
	if not game.state.at_war(u.owner, other_owner):
		return "Нужно объявить войну"
	var dist := game.state.map.grid.distance(u.tile, tile)
	if is_ranged(game, u):
		if dist > attack_range(game, u):
			return "Цель вне дальности"
		if unit_class(game, u) == "SIEGE" and u.moves_left < Movement.max_moves(game, u) \
				and not has_flag(game, u, "attack_after_move"):
			return "Осадный юнит не стреляет после движения"
		if not Visibility.visible_tiles(game, u.tile, attack_range(game, u)).has(tile):
			return "Нет прямой видимости"
	else:
		if dist != 1:
			return "Цель должна быть рядом"
		if t["kind"] == "civilian" or t["kind"] == "unit" or t["kind"] == "city":
			if Movement.step_cost(game, u, u.tile, tile) == Movement.IMPASSABLE and t["kind"] != "city":
				return "Сюда не пройти"
	return ""


## Прогноз боя без случайности: {"att": сила, "def": сила, "dmg_to_def", "dmg_to_att", "att_mods", "def_mods"}.
static func preview(game: Game, u: Unit, tile: int) -> Dictionary:
	var t := target_at(game, u.owner, tile)
	var ranged := is_ranged(game, u)
	var map := game.state.map
	var barb := game.state.barbarian_id()
	var ctx := {"ranged_attack": ranged, "target_tile": tile, "vs_irregular": false}
	var att_base := ranged_strength(game, u.type) if ranged else melee_strength(game, u.type)
	var def_base := 0
	var def_mods: Array = []
	if t["kind"] == "city":
		ctx["vs_district"] = true
		ctx["vs_player"] = t["city"].owner
		var cs: Array = city_strength(game, t["city"])
		def_base = int(cs[0])
		def_mods = cs[1]
		var city_visibility := DiplomaticVisibility.combat_bonus(game, t["city"].owner, u.owner)
		if city_visibility > 0:
			def_mods.append(["Дипломатическая видимость", city_visibility])
		var military_bonus := TreatyRules.shared_enemy_bonus(game, t["city"].owner, u.owner)
		if military_bonus > 0:
			def_mods.append(["Военный союз", military_bonus])
	elif t["kind"] == "unit":
		var d: Unit = t["unit"]
		ctx["vs_player"] = d.owner
		ctx["vs_irregular"] = d.owner == barb
		ctx["vs_class"] = unit_class(game, d)
		ctx["vs_domain"] = Movement.effective_domain(game, d)
		ctx["vs_wounded"] = d.hp < 100
		ctx["vs_fortified"] = d.fortify_turns > 0
		def_base = melee_strength(game, d.type)
		if Movement.is_embarked(game, d):
			def_base = embarked_defense(game, d)
		def_mods = unit_mods(game, d, "defense", {"vs_class": unit_class(game, u), "vs_ranged": ranged,
			"vs_domain": Movement.effective_domain(game, u), "vs_irregular": u.owner == barb, "vs_player": u.owner})
	var att_mods := unit_mods(game, u, "attack", ctx)
	if Movement.is_embarked(game, u) and not ranged:
		att_mods.append(["Высадка с моря", -int(k(game, "embark_attack_penalty", 10))])
	if not ranged:
		var dir := map.grid.direction_to(u.tile, tile)
		if dir >= 0 and map.has_river_edge(u.tile, dir) and not has_flag(game, u, "ignore_river_penalty"):
			att_mods.append(["Через реку", -int(k(game, "river_attack_penalty", 5))])
	var att := att_base + _sum(att_mods)
	var def := def_base + _sum(def_mods)
	var delta := att - def
	return {"att": att, "def": def, "att_mods": att_mods, "def_mods": def_mods, "kind": t["kind"],
		"dmg_to_def": damage(game, delta, 1.0), "dmg_to_att": 0 if ranged else damage(game, -delta, 1.0)}


## Выполняет атаку. Перед вызовом проверить attack_error.
static func attack(game: Game, u: Unit, tile: int, events: Array) -> void:
	var t := target_at(game, u.owner, tile)
	var pv := preview(game, u, tile)
	var ranged := is_ranged(game, u)
	var delta := int(pv["att"]) - int(pv["def"])
	var att_owner := u.owner
	var barb := game.state.barbarian_id()
	u.acted = true
	u.fortify_turns = 0
	if u.orders.get("type", "") == "fortify":
		u.orders = {}
	match t["kind"]:
		"civilian":
			_capture_civilians(game, u, tile, t["units"], events)
			return
		"unit":
			var d: Unit = t["unit"]
			var dmg_def := damage(game, delta, _roll(game))
			var dmg_att := 0 if ranged else damage(game, -delta, _roll(game))
			d.hp -= dmg_def
			u.hp -= dmg_att
			d.acted = true
			var killed := d.hp <= 0
			events.append({"type": "combat", "attacker": u.id, "defender": d.id, "tile": tile,
				"dmg_to_def": dmg_def, "dmg_to_att": dmg_att, "ranged": ranged})
			add_xp(game, u, int(k(game, "xp_attack", 5)) * (int(k(game, "xp_kill_mult", 2)) if killed else 1), d.owner == barb)
			if not killed:
				add_xp(game, d, int(k(game, "xp_defense", 2)), att_owner == barb)
			if killed:
				events.append({"type": "unit_killed", "unit": d.id, "owner": d.owner, "by": att_owner,
					"by_unit_type": u.type})
				Army.on_unit_killed(game, d, events)
				game.state.remove_unit(d.id)
			if u.hp <= 0:
				events.append({"type": "unit_killed", "unit": u.id, "owner": att_owner, "by": d.owner,
					"by_unit_type": d.type})
				Army.on_unit_killed(game, u, events)
				game.state.remove_unit(u.id)
				return
			if killed and not ranged:
				_advance(game, u, tile, events)
		"city":
			_attack_city(game, u, t["city"], delta, ranged, events)
	if game.state.unit(u.id) != null:
		if not has_flag(game, u, "move_after_attack"):
			u.moves_left = 0.0
		else:
			u.moves_left = maxf(0.0, u.moves_left - 1.0)


static func _advance(game: Game, u: Unit, tile: int, events: Array) -> void:
	if not Movement.can_stand(game, u, tile):
		return
	# Гражданских в клетке захватываем.
	var civ: Array[Unit] = []
	for other in game.state.units_at(tile):
		if other.owner != u.owner and other.trade_route.is_empty():
			civ.append(other)
	if not civ.is_empty():
		_capture_civilians(game, u, tile, civ, events)
		return
	var from := u.tile
	u.tile = tile
	events.append({"type": "unit_moved", "unit": u.id, "from": from, "to": tile})
	game.on_unit_entered(u, events)


## Захват гражданских: поселенцы и строители становятся строителями захватчика (у варваров — гибнут).
static func _capture_civilians(game: Game, u: Unit, tile: int, units: Array, events: Array) -> void:
	var barb := game.state.barbarian_id()
	for c in units:
		var cu: Unit = c
		var t := cu.type
		var old_owner := cu.owner
		if Army.is_commander(game, cu):
			game.state.remove_unit(cu.id)
			Army.retreat_commander(game, old_owner, cu.xp, cu.level, events)
			continue
		game.state.remove_unit(cu.id)
		events.append({"type": "unit_captured", "unit": cu.id, "owner": old_owner, "by": u.owner})
		if u.owner != barb and (t == "SETTLER" or t == "BUILDER"):
			var nu := game.state.add_unit(u.owner, "BUILDER", tile)
			nu.charges = int(game.data.unit_def("BUILDER").get("charges", 3))
			nu.moves_left = 0.0
	if Movement.can_stand(game, u, tile) and not Combat.is_ranged(game, u):
		var from := u.tile
		u.tile = tile
		events.append({"type": "unit_moved", "unit": u.id, "from": from, "to": tile})
		game.on_unit_entered(u, events)
	u.moves_left = 0.0


static func _attack_city(game: Game, u: Unit, city: City, delta: int, ranged: bool, events: Array) -> void:
	var dmg := damage(game, delta, _roll(game))
	var cls := unit_class(game, u)
	var full_vs_walls := cls == "SIEGE" or cls == "NAVAL_RANGED"
	var hp_dmg := dmg
	if city.wall_hp > 0:
		city.wall_hp = maxi(0, city.wall_hp - dmg)
		if not full_vs_walls:
			hp_dmg = roundi(dmg * float(k(game, "wall_ranged_hp_factor", 0.5) if ranged else k(game, "wall_melee_hp_factor", 0.15)))
	city.hp = maxi(0, city.hp - hp_dmg)
	city.last_attacked_turn = game.state.turn
	var dmg_att := 0
	if not ranged:
		dmg_att = damage(game, -delta, _roll(game))
		u.hp -= dmg_att
	events.append({"type": "combat", "attacker": u.id, "city": city.id, "tile": city.tile,
		"dmg_to_def": hp_dmg, "dmg_to_walls": dmg if city.wall_hp >= 0 else 0, "dmg_to_att": dmg_att, "ranged": ranged})
	add_xp(game, u, int(k(game, "xp_attack_city", 3)), false)
	if u.hp <= 0:
		events.append({"type": "unit_killed", "unit": u.id, "owner": u.owner, "by": city.owner})
		Army.on_unit_killed(game, u, events)
		game.state.remove_unit(u.id)
		return
	if not ranged and city.hp <= 0:
		capture_city(game, u, city, events)


## Захват города (ГДД 5.7). Варвары не удерживают города — разоряют (кроме столиц).
static func capture_city(game: Game, u: Unit, city: City, events: Array) -> void:
	var old_owner := city.owner
	var map := game.state.map
	# Юниты прежнего владельца в городе гибнут.
	for other in game.state.units_at(city.tile):
		if other.owner != u.owner and other.trade_route.is_empty():
			events.append({"type": "unit_killed", "unit": other.id, "owner": other.owner, "by": u.owner})
			game.state.remove_unit(other.id)
	if game.state.player(u.owner).is_barbarian:
		if city.is_capital or city.id in game.state.original_capitals.values():
			city.hp = 1
			return
		_destroy_city(game, city, events)
		var from_b := u.tile
		u.tile = city.tile
		events.append({"type": "unit_moved", "unit": u.id, "from": from_b, "to": city.tile})
		return
	city.owner = u.owner
	city.hp = int(k(game, "city_hp", 200)) / 4
	city.population = maxi(1, city.population - maxi(1, roundi(city.population * float(k(game, "capture_pop_loss", 0.25)))))
	city.queue = []
	city.progress = {}
	city.locked_tiles = []
	city.doctrine = ""
	city.doctrine_turns = 0
	# Недостроенные районы при захвате пропадают.
	for d in city.districts.duplicate():
		if not d["complete"]:
			game.state.map.district[int(d["tile"])] = ""
			city.districts.erase(d)
	for wonder in city.wonders.duplicate():
		if not wonder["complete"]:
			game.state.map.district[int(wonder["tile"])] = ""
			city.wonders.erase(wonder)
	var was_capital := city.is_capital
	city.is_capital = false
	for bid in city.buildings.duplicate():
		if game.data.buildings.get(bid, {}).get("capital_only", false):
			city.buildings.erase(bid)
	city.food_stored = 0.0
	var from := u.tile
	u.tile = city.tile
	events.append({"type": "unit_moved", "unit": u.id, "from": from, "to": city.tile})
	events.append({"type": "city_captured", "city": city.id, "from": old_owner, "by": u.owner})
	CityRules.assign_citizens(game, city)
	if was_capital:
		_move_capital(game, old_owner, events)
	_check_elimination(game, old_owner, events)
	Visibility.recompute(game, u.owner)
	Visibility.recompute(game, old_owner)


static func _destroy_city(game: Game, city: City, events: Array) -> void:
	var map := game.state.map
	for park in city.parks:
		for tile in park["tiles"]:
			if map.improvement[int(tile)] == "NATIONAL_PARK":
				map.improvement[int(tile)] = ""
	for t in map.grid.tiles_in_radius(city.tile, int(k(game, "city_border_radius", 5))):
		if map.owner_city[t] == city.id:
			map.owner_city[t] = -1
			map.district[t] = ""
	var owner := city.owner
	game.state.cities.erase(city.id)
	events.append({"type": "city_destroyed", "city": city.id, "owner": owner, "tile": city.tile})
	_check_elimination(game, owner, events)


static func _move_capital(game: Game, pid: int, events: Array) -> void:
	var cities := game.state.cities_of(pid)
	if cities.is_empty():
		return
	var best: City = cities[0]
	for c in cities:
		if c.population > best.population:
			best = c
	best.is_capital = true
	for bid in game.data.building_ids:
		if game.data.buildings[bid].get("capital_only", false) and not best.has_building(bid):
			best.buildings.append(bid)
	events.append({"type": "capital_moved", "player": pid, "city": best.id})


static func _check_elimination(game: Game, pid: int, events: Array) -> void:
	var p := game.state.player(pid)
	if p.is_barbarian or not p.alive:
		return
	if game.state.cities_of(pid).is_empty():
		var has_settler := false
		for u in game.state.units_of(pid):
			if game.data.unit_def(u.type).get("abilities", []).has("FOUND_CITY"):
				has_settler = true
		# Держава без городов выбывает, если ей уже нечем основать новый.
		if not has_settler:
			p.alive = false
			ConcessionRules.update_loans(game, game.state.turn, events)
			for u in game.state.units_of(pid):
				game.state.remove_unit(u.id)
			events.append({"type": "player_eliminated", "player": pid})


# --- Обстрел из города (ГДД 5.7) -----------------------------------------------------------

static func city_attack_error(game: Game, city: City, tile: int) -> String:
	if not city_can_strike(game, city):
		return "Город может стрелять только со стенами и раз в ход"
	if game.state.map.grid.distance(city.tile, tile) > int(k(game, "city_ranged_range", 2)):
		return "Цель вне дальности"
	var t := target_at(game, city.owner, tile)
	if t["kind"] != "unit":
		return "Нет цели"
	if not game.state.at_war(city.owner, t["unit"].owner):
		return "Нужно объявить войну"
	return ""


static func city_attack(game: Game, city: City, tile: int, events: Array) -> void:
	var t := target_at(game, city.owner, tile)
	var d: Unit = t["unit"]
	var def := melee_strength(game, d.type) + _sum(unit_mods(game, d, "defense", {"vs_ranged": true,
		"vs_irregular": game.state.player(city.owner).is_barbarian, "vs_player": city.owner}))
	var visibility_bonus := DiplomaticVisibility.combat_bonus(game, city.owner, d.owner)
	var alliance_bonus := TreatyRules.shared_enemy_bonus(game, city.owner, d.owner)
	var dmg := damage(game, city_ranged_strength(game, city) + visibility_bonus + alliance_bonus - def, _roll(game))
	d.hp -= dmg
	city.has_attacked = true
	events.append({"type": "combat", "city_attacker": city.id, "defender": d.id, "tile": tile, "dmg_to_def": dmg, "ranged": true})
	if d.hp <= 0:
		events.append({"type": "unit_killed", "unit": d.id, "owner": d.owner, "by": city.owner})
		Army.on_unit_killed(game, d, events)
		game.state.remove_unit(d.id)
