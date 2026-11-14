extends TestCase
## Снаряжение и командующие (docs/ARMY.md).


func _setup() -> Array:
	var g := blank_game(24, 14)
	Barbarians.setup(g)
	g.state.camps.clear()
	for i in g.state.map.size():
		g.state.map.improvement[i] = ""
	var grid := g.state.map.grid
	var s0 := g.state.add_unit(0, "SETTLER", grid.index_of(8, 6))
	CityRules.found_city(g, 0, s0.tile)
	g.state.remove_unit(s0.id)
	g.state.set_war(0, 1, true)
	return [g, grid]


func test_slots_by_era() -> void:
	var g := blank_game()
	check_eq(Army.slots_for(g, "WARRIOR"), ["weapon", "shield", "armor", "clothing"] as Array[String])
	check_eq(Army.slots_for(g, "ARCHER"), ["armor", "clothing"] as Array[String])
	check_eq(Army.slots_for(g, "MUSKETMAN"), ["tactics", "clothing"] as Array[String])
	check_eq(Army.slots_for(g, "INFANTRY"), ["kit", "clothing"] as Array[String])
	check_eq(Army.slots_for(g, "TANK"), ["plating", "clothing"] as Array[String])
	check(Army.slots_for(g, "CATAPULT").is_empty(), "у осадных снаряжения нет")


func test_regular_vs_irregular() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var a := g.state.add_unit(0, "WARRIOR", grid.index_of(12, 6))
	a.moves_left = 2.0
	var reg := g.state.add_unit(1, "WARRIOR", grid.index_of(13, 6))
	var barb := g.state.add_unit(g.state.barbarian_id(), "WARRIOR", grid.index_of(12, 7))
	# По умолчанию: копья (+5 против регулярных) и лёгкая кираса (+2 к атаке против варваров).
	check_eq(int(Combat.preview(g, a, reg.tile)["att"]), 25)
	check_eq(int(Combat.preview(g, a, barb.tile)["att"]), 22)
	a.equipment["weapon"] = "SHORT_SWORD"
	a.equipment["armor"] = "LIGHT_ARMOR"
	check_eq(int(Combat.preview(g, a, reg.tile)["att"]), 20)
	check_eq(int(Combat.preview(g, a, barb.tile)["att"]), 27, "мечи +5, кираса +2 против варваров")


func test_climate() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var u := g.state.add_unit(0, "WARRIOR", grid.index_of(15, 6))
	g.state.map.terrain[u.tile] = "SNOW"
	check_eq(Army.climate_of(g, u.tile), "COLD")
	var mods := Army.equipment_mods(g, u, "combat", {"role": "defense"})
	var total := 0
	for m in mods:
		total += int(m[1])
	check_eq(total, -3, "обычная форма в холоде")
	UnitRules.process_units_turn_start(g, 0, [])
	check_eq(u.hp, 90, "в снегах без зимней одежды теряет здоровье")
	u.equipment["clothing"] = "WINTER"
	UnitRules.process_units_turn_start(g, 0, [])
	check(u.hp >= 90, "в зимней одежде не мёрзнет")


func test_equip_action() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var u := g.state.add_unit(0, "WARRIOR", grid.index_of(8, 6))
	g.state.player(0).treasury = 100
	var ev := g.apply_action({"type": "equip", "unit": u.id, "slot": "armor", "option": "HEAVY_ARMOR"})
	check_eq(ev[0]["type"], "error", "тяжёлая броня требует железа")
	g.state.player(0).stockpile["IRON"] = 10.0
	g.apply_action({"type": "equip", "unit": u.id, "slot": "armor", "option": "HEAVY_ARMOR"})
	check_eq(u.equipment["armor"], "HEAVY_ARMOR")
	check_near(g.state.player(0).treasury, 80.0)
	check_near(float(g.state.player(0).stockpile["IRON"]), 5.0)
	u.tile = grid.index_of(18, 6)
	ev = g.apply_action({"type": "equip", "unit": u.id, "slot": "shield", "option": "HEAVY_SHIELD"})
	check_eq(ev[0]["type"], "error", "вне своей территории нельзя")


func test_heavy_slows_rough() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var u := g.state.add_unit(0, "WARRIOR", grid.index_of(15, 6))
	var hill := grid.neighbor(u.tile, 0)
	g.state.map.relief[hill] = GameMap.RELIEF_HILLS
	check_near(Movement.step_cost(g, u, u.tile, hill), 2.0)
	u.equipment["shield"] = "HEAVY_SHIELD"
	u.equipment["armor"] = "HEAVY_ARMOR"
	check_near(Movement.step_cost(g, u, u.tile, hill), 3.0, 1e-6, "тяжёлое снаряжение +1 на холмах")


func test_commander() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	check_eq(Abilities.unit_name(g, 0, "COMMANDER"), "Центурион")
	check_eq(Abilities.unit_name(g, 1, "COMMANDER"), "Вожак")
	check_eq(Army.detachment_name(g, 0), "когорта")
	var t := grid.index_of(12, 6)
	var w := g.state.add_unit(0, "WARRIOR", t)
	w.moves_left = 2.0
	var cmd := g.state.add_unit(0, "COMMANDER", t)
	cmd.moves_left = 2.0
	var before := Movement.max_moves(g, w)
	g.apply_action({"type": "attach_commander", "unit": cmd.id, "target": w.id})
	check(g.state.unit(cmd.id) == null, "командующий вошёл в отряд")
	check_near(Movement.max_moves(g, w), before + 1.0)
	var mods := Combat.unit_mods(g, w, "attack", {})
	check_eq(Combat._sum(mods), 7, "+7 к силе")
	Combat.add_xp(g, w, 15, false)
	check_eq(int(w.commander["level"]), 1, "командующий растёт вместе с отрядом")
	check_eq(Army.commander_combat(g, w), 8)
	g.apply_action({"type": "detach_commander", "unit": w.id})
	check(w.commander.is_empty())
	var cmds := g.state.units_at(t).filter(func(x): return x.type == "COMMANDER")
	check_eq(cmds.size(), 1, "командующий снова на карте")
	check_eq(cmds[0].level, 1)


func test_commander_retreats_on_defeat() -> void:
	var r := _setup()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var w := g.state.add_unit(0, "WARRIOR", grid.index_of(12, 6))
	w.commander = {"xp": 20, "level": 1}
	w.hp = 1
	var e := g.state.add_unit(1, "SWORDSMAN", grid.index_of(13, 6))
	e.moves_left = 2.0
	g.state.current_player = 1
	g.apply_action({"type": "attack", "unit": e.id, "target": w.tile})
	check(g.state.unit(w.id) == null, "отряд разбит")
	var city: City = g.state.cities_of(0)[0]
	var cmds := g.state.units_at(city.tile).filter(func(x): return x.type == "COMMANDER")
	check_eq(cmds.size(), 1, "командующий отступил в город")
	check_eq(cmds[0].hp, 50)
	check_eq(cmds[0].xp, 20)
