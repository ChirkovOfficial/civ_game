class_name Barbarians
extends RefCounted
## Варвары и племенные поселения (ГДД 10).
##
## Лагерь держит защитника, высылает разведчика; когда разведчик замечает город,
## лагерь начинает набег — выпускает несколько юнитов, которые идут к этому городу,
## грабят улучшения, захватывают гражданских и нападают на слабых.

const RAID_COOLDOWN := 20


static func k(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


# --- Подготовка партии ---------------------------------------------------------------------------

static func setup(game: Game) -> void:
	var s := game.state
	var barb := Player.new()
	barb.id = s.players.size()
	barb.name = "Варвары"
	barb.color = Color("3a3a3a")
	barb.is_ai = true
	barb.is_barbarian = true
	barb.init_fog(s.map.size())
	barb.revealed.fill(Player.FOG_REVEALED)
	barb.best_strength = {"melee": 20, "ranged": 15}
	s.players.append(barb)
	_place_tribal_villages(game)
	var count := int(k(game, "barbarian_camps_start_per_civ", 1)) * (s.players.size() - 1)
	for _i in count:
		try_spawn_camp(game, [])


static func _place_tribal_villages(game: Game) -> void:
	var map := game.state.map
	var land := 0
	var candidates: Array = []
	for i in map.size():
		if map.is_land(i) and not map.is_mountain(i):
			land += 1
			if map.resource[i] == "" and map.improvement[i] == "":
				candidates.append(i)
	game.state.rng.shuffle(candidates)
	var target := land / maxi(1, int(k(game, "tribal_villages_per_land", 45)))
	var placed: Array[int] = []
	for t in candidates:
		if placed.size() >= target:
			break
		var ok := true
		for sp in game.state.start_positions:
			if map.grid.distance(sp, t) < 3:
				ok = false
		for p in placed:
			if map.grid.distance(p, t) < 4:
				ok = false
		if ok:
			map.improvement[t] = "TRIBAL_VILLAGE"
			placed.append(t)


## Пытается основать лагерь на клетке вне обзора всех держав и вдали от городов.
static func try_spawn_camp(game: Game, events: Array) -> bool:
	var s := game.state
	var map := s.map
	var min_dist := int(k(game, "barbarian_camp_min_dist_city", 7))
	var options: Array = []
	for i in map.size():
		if map.is_water(i) or map.is_mountain(i) or map.owner_city[i] >= 0 or map.improvement[i] != "":
			continue
		if not s.units_at(i).is_empty():
			continue
		var bad := false
		for p in s.players:
			if not p.is_barbarian and p.is_visible(i):
				bad = true
				break
		if bad:
			continue
		for sp in s.start_positions:
			if map.grid.distance(sp, i) < min_dist:
				bad = true
				break
		if bad:
			continue
		for cid in s.cities:
			if map.grid.distance(s.cities[cid].tile, i) < min_dist:
				bad = true
				break
		if bad:
			continue
		for ct in s.camps:
			if map.grid.distance(int(ct), i) < 6:
				bad = true
				break
		if not bad:
			options.append(i)
	if options.is_empty():
		return false
	var tile: int = s.rng.pick(options)
	map.improvement[tile] = "BARBARIAN_CAMP"
	s.camps[tile] = {"tile": tile, "timer": 0, "spawned": 0, "target": -1, "scout": -1, "cooldown": 0}
	_spawn(game, tile, best_type(game, "SPEARMAN"))
	events.append({"type": "camp_spawned", "tile": tile})
	return true


## Лучший юнит линии, технология которого известна большинству держав.
static func best_type(game: Game, start_slot: String) -> String:
	var majors: Array[Player] = []
	for p in game.state.players:
		if p.alive and not p.is_barbarian:
			majors.append(p)
	var best := start_slot
	var cur := start_slot
	while cur != "":
		var def := game.data.unit_def(cur)
		if def.has("tech"):
			var knows := 0
			for p in majors:
				if p.has_tech(def["tech"]):
					knows += 1
			if knows * 2 < majors.size():
				break
		if def.has("resource") or def.has("resource_per_turn") or def.has("civic"):
			break
		best = cur
		cur = def.get("upgrades_to", "")
	return best


static func _spawn(game: Game, tile: int, unit_type: String) -> Unit:
	var barb := game.state.barbarian_id()
	var u := game.state.add_unit(barb, unit_type, tile)
	u.moves_left = Movement.max_moves(game, u)
	UnitRules.note_strength(game, barb, unit_type)
	return u


# --- Ход варваров --------------------------------------------------------------------------------

static func take_turn(game: Game, events: Array) -> void:
	var s := game.state
	var barb := s.barbarian_id()
	if barb < 0:
		return
	for u in s.units_of(barb):
		if not u.acted and u.hp < 100:
			u.hp = mini(100, u.hp + 10)
		u.moves_left = Movement.max_moves(game, u)
		u.acted = false
	Visibility.recompute(game, barb)
	var every := int(k(game, "barbarian_spawn_every", 3))
	for tile in _sorted_camps(game):
		var camp: Dictionary = s.camps[tile]
		camp["timer"] = int(camp["timer"]) + 1
		camp["cooldown"] = maxi(0, int(camp.get("cooldown", 0)) - 1)
		var has_guard := false
		for u in s.units_at(tile):
			if u.owner == barb:
				has_guard = true
		if not has_guard and int(camp["timer"]) % every == 0:
			_spawn(game, tile, best_type(game, "SPEARMAN"))
			continue
		var scout := s.unit(int(camp["scout"]))
		if scout == null and int(camp["target"]) < 0 and int(camp["cooldown"]) == 0 and int(camp["timer"]) % every == 0:
			var sp := _spawn_near(game, tile, "SCOUT")
			if sp != null:
				camp["scout"] = sp.id
		# Разведчик заметил город — набег.
		if scout != null and int(camp["target"]) < 0:
			for cid in s.cities:
				var c: City = s.cities[cid]
				if s.map.grid.distance(c.tile, scout.tile) <= 4:
					camp["target"] = c.tile
					camp["spawned"] = 0
					events.append({"type": "barbarian_raid", "camp": tile, "target": c.id})
					break
		var raid_size := int(k(game, "barbarian_raid_units", 2)) + _era_index(game) / 2
		var total_units := s.units_of(barb).size()
		var cap := s.camps.size() * int(k(game, "barbarian_max_units_per_camp", 4))
		if int(camp["target"]) >= 0 and int(camp["timer"]) % every == 0 and total_units < cap:
			if int(camp["spawned"]) < raid_size:
				var line: String = ["WARRIOR", "SLINGER", "SPEARMAN"][int(camp["spawned"]) % 3]
				var rt := best_type(game, line)
				if _spawn_near(game, tile, rt) != null:
					camp["spawned"] = int(camp["spawned"]) + 1
			else:
				camp["target"] = -1
				camp["cooldown"] = RAID_COOLDOWN
	# Новые лагеря время от времени.
	var max_camps := (s.players.size() - 1) * int(k(game, "barbarian_max_camps_per_civ", 1))
	if s.turn % int(k(game, "barbarian_new_camp_every", 12)) == 0 and s.camps.size() < max_camps:
		try_spawn_camp(game, events)
	_move_units(game, barb, events)


static func _era_index(game: Game) -> int:
	var eras: Array = k(game, "eras", [])
	var best := 0
	for p in game.state.players:
		if p.alive and not p.is_barbarian:
			best = maxi(best, eras.find(UnitRules.player_era(game, p.id)))
	return best


static func _sorted_camps(game: Game) -> Array:
	var keys := game.state.camps.keys()
	keys.sort()
	return keys


static func _spawn_near(game: Game, camp_tile: int, unit_type: String) -> Unit:
	var map := game.state.map
	for t in [camp_tile] + Array(map.grid.ring(camp_tile, 1)):
		if map.is_water(t) or map.is_mountain(t):
			continue
		var free := true
		for other in game.state.units_at(t):
			if Movement.layer(game, other.type) == "COMBAT" or other.owner != game.state.barbarian_id():
				free = false
		if free:
			return _spawn(game, t, unit_type)
	return null


static func _target_of(game: Game, u: Unit) -> int:
	for tile in game.state.camps:
		var camp: Dictionary = game.state.camps[tile]
		if int(camp["target"]) >= 0 and game.state.map.grid.distance(int(tile), u.tile) <= 12:
			return int(camp["target"])
	return -1


## ГДД 10: защитник стоит в лагере; остальные — атакуют слабейшую цель в радиусе 6
## (гражданские → раненые → прочие), грабят улучшения, иначе идут к цели набега или бродят.
static func _move_units(game: Game, barb: int, events: Array) -> void:
	var s := game.state
	for u in s.units_of(barb):
		if s.unit(u.id) == null or u.moves_left <= 0.0:
			continue
		if s.camps.has(u.tile) and _guards(game, u):
			continue
		var trader := TradeRules.raid_target(game, u)
		if trader != null:
			TradeRules.raid(game, u, trader, events)
			continue
		var best_tile := -1
		var best_score := -INF
		for t in s.map.grid.tiles_in_radius(u.tile, 6):
			var tgt := Combat.target_at(game, barb, t)
			if tgt["kind"] == "" or tgt["kind"] == "camp":
				continue
			var score := 10.0 - s.map.grid.distance(u.tile, t)
			match tgt["kind"]:
				"civilian":
					score += 30.0
				"unit":
					score += 15.0 + (100 - tgt["unit"].hp) * 0.2
				"city":
					score += 5.0 if tgt["city"].hp < 100 else -20.0
			if score > best_score:
				best_score = score
				best_tile = t
		if best_tile >= 0:
			_approach_and_attack(game, u, best_tile)
			continue
		if UnitRules.pillage_error(game, u) == "":
			game.apply_action({"type": "pillage", "unit": u.id})
			continue
		var target := _target_of(game, u)
		if target >= 0:
			game.apply_action({"type": "move_unit", "unit": u.id, "target": target})
		else:
			var opts: Array = []
			for t in s.map.grid.ring(u.tile, 3):
				if Movement.can_stand(game, u, t):
					opts.append(t)
			if not opts.is_empty():
				game.apply_action({"type": "move_unit", "unit": u.id, "target": s.rng.pick(opts)})


static func _guards(game: Game, u: Unit) -> bool:
	var count := 0
	for other in game.state.units_at(u.tile):
		if other.owner == u.owner and Movement.layer(game, other.type) == "COMBAT":
			count += 1
	return count >= 1 and game.data.unit_def(u.type).get("class", "") != "RECON"


static func _approach_and_attack(game: Game, u: Unit, tile: int) -> void:
	if Combat.attack_error(game, u, tile) == "":
		game.apply_action({"type": "attack", "unit": u.id, "target": tile})
		return
	# Подойти вплотную (для дальнобойных — на дистанцию выстрела).
	var grid := game.state.map.grid
	var best := -1
	var best_d := 999
	for t in grid.tiles_in_radius(tile, Combat.attack_range(game, u) if Combat.is_ranged(game, u) else 1):
		if t == tile or not Movement.can_stand(game, u, t) or not Movement.occupancy_allows(game, u, t, true):
			continue
		var d := grid.distance(u.tile, t)
		if d < best_d:
			best_d = d
			best = t
	if best >= 0 and best != u.tile:
		game.apply_action({"type": "move_unit", "unit": u.id, "target": best})
	if game.state.unit(u.id) != null and u.moves_left > 0.0 and Combat.attack_error(game, u, tile) == "":
		game.apply_action({"type": "attack", "unit": u.id, "target": tile})


# --- Зачистка лагеря и племенные поселения ----------------------------------------------------------

## Юнит вошёл в клетку: лагерь (зачистка) или племенное поселение (награда).
static func on_enter(game: Game, u: Unit, events: Array) -> void:
	var s := game.state
	var map := s.map
	var p := s.player(u.owner)
	if p.is_barbarian:
		return
	var imp := map.improvement[u.tile]
	if imp == "BARBARIAN_CAMP" and Movement.layer(game, u.type) == "COMBAT":
		map.improvement[u.tile] = ""
		s.camps.erase(u.tile)
		var gold := float(k(game, "barbarian_camp_gold", 50)) * (1.0 + _era_index(game) * 0.5)
		p.treasury += gold
		events.append({"type": "camp_cleared", "tile": u.tile, "player": u.owner, "gold": gold})
		DemandRules.on_camp_cleared(game, u.tile, u.owner, events)
	elif imp == "TRIBAL_VILLAGE":
		map.improvement[u.tile] = ""
		_village_reward(game, u, events)


static func _village_reward(game: Game, u: Unit, events: Array) -> void:
	var p := game.state.player(u.owner)
	var rewards: Array = k(game, "tribal_rewards", [])
	var weights := []
	for r in rewards:
		weights.append(float(r.get("weight", 1)))
	var idx := game.state.rng.pick_weighted(weights)
	var r: Dictionary = rewards[idx] if idx >= 0 else {"type": "gold", "amount": 30}
	var text := ""
	match r["type"]:
		"gold":
			p.treasury += float(r["amount"])
			text = "+%d золота" % int(r["amount"])
		"faith":
			p.faith += float(r["amount"])
			text = "+%d веры" % int(r["amount"])
		"science", "culture":
			var kind := "tech" if r["type"] == "science" else "civic"
			var cur := p.current_tech if kind == "tech" else p.current_civic
			if cur == "":
				p.treasury += 30.0
				text = "+30 золота"
			else:
				var cost := EmpireRules.tech_cost(game, cur) if kind == "tech" else EmpireRules.civic_cost(game, cur)
				EmpireRules.add_research(game, u.owner, kind, cost * float(r.get("fraction", 0.4)), events)
				text = "Ускорение исследования"
		"unit":
			var nu := game.state.add_unit(u.owner, r["unit"], u.tile)
			nu.charges = int(game.data.unit_def(r["unit"]).get("charges", 0))
			text = "Новый юнит: %s" % Abilities.unit_name(game, u.owner, r["unit"])
		"xp":
			u.xp += int(r["amount"])
			text = "Опыт юниту"
		"population":
			var cities := game.state.cities_of(u.owner)
			if cities.is_empty():
				p.treasury += 30.0
				text = "+30 золота"
			else:
				cities[0].population += 1
				CityRules.assign_citizens(game, cities[0])
				text = "+1 житель в %s" % cities[0].name
	events.append({"type": "village_reward", "player": u.owner, "tile": u.tile, "text": text})
