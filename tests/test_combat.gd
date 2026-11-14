extends TestCase
## Бой (ГДД 9.4–9.6, 5.7), дороги, варвары, война.


func _war_game() -> Array:
	var g := blank_game(24, 14)
	Barbarians.setup(g)   # варвары — отдельная держава
	g.state.camps.clear()
	for i in g.state.map.size():
		g.state.map.improvement[i] = ""
	g.state.player(0).met[1] = true
	g.state.player(1).met[0] = true
	return [g, g.state.map.grid]


func test_damage_formula() -> void:
	var g := blank_game()
	check_eq(Combat.damage(g, 0, 1.0), 30)
	check_eq(Combat.damage(g, 10, 1.0), 45)
	check_eq(Combat.damage(g, -10, 1.0), 20)
	check(Combat.damage(g, 30, 1.0) >= 99, "Δ=+30 — почти гарантированное убийство")
	check_eq(Combat.xp_for_level(1), 15)
	check_eq(Combat.xp_for_level(3), 90)


func test_need_war_to_attack() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var a := g.state.add_unit(0, "WARRIOR", grid.index_of(5, 6))
	a.moves_left = 2.0
	var d := g.state.add_unit(1, "WARRIOR", grid.index_of(6, 6))
	check(Combat.attack_error(g, a, d.tile).contains("войну"))
	var ev := g.apply_action({"type": "declare_war", "target": 1})
	check_eq(ev[0]["type"], "war_declared")
	check_eq(Combat.attack_error(g, a, d.tile), "")
	ev = g.apply_action({"type": "make_peace", "target": 1})
	check_eq(ev[0]["type"], "error", "мир — не раньше 10 ходов")


func test_melee_exchange() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	g.state.set_war(0, 1, true)
	var a := g.state.add_unit(0, "WARRIOR", grid.index_of(5, 6))
	a.moves_left = 2.0
	var d := g.state.add_unit(1, "WARRIOR", grid.index_of(6, 6))
	var pv := Combat.preview(g, a, d.tile)
	check_eq(int(pv["att"]), int(pv["def"]), "равные воины на лугу")
	g.apply_action({"type": "attack", "unit": a.id, "target": d.tile})
	check(a.hp < 100 and d.hp < 100, "ближний бой ранит обоих")
	check(a.hp >= 64 and d.hp >= 64, "урон 24..36")
	check_near(a.moves_left, 0.0)
	check_eq(a.xp, 5)
	check_eq(d.xp, 2)


func test_ranged_no_retaliation_and_kill() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	g.state.set_war(0, 1, true)
	var a := g.state.add_unit(0, "ARCHER", grid.index_of(4, 6))
	a.moves_left = 2.0
	var d := g.state.add_unit(1, "SCOUT", grid.index_of(6, 6))
	d.hp = 10
	Visibility.recompute(g, 0)
	check_eq(Combat.attack_error(g, a, d.tile), "")
	g.apply_action({"type": "attack", "unit": a.id, "target": d.tile})
	check_eq(a.hp, 100, "дальний бой без ответного урона")
	check(g.state.unit(d.id) == null, "раненый разведчик убит")
	check_eq(a.tile, grid.index_of(4, 6), "стрелок не двигается")


func test_terrain_and_fortify_mods() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var d := g.state.add_unit(1, "WARRIOR", grid.index_of(6, 6))
	g.state.map.relief[d.tile] = GameMap.RELIEF_HILLS
	g.state.map.feature[d.tile] = "WOODS"
	d.fortify_turns = 2
	var mods := Combat.unit_mods(g, d, "defense", {})
	check_eq(Combat._sum(mods), 12, "холмы +3, лес +3, укрепление +6")
	d.hp = 55
	check_eq(Combat._sum(Combat.unit_mods(g, d, "defense", {})), 8, "ранение −4")


func test_class_bonus_and_river() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	g.state.set_war(0, 1, true)
	var a := g.state.add_unit(0, "SPEARMAN", grid.index_of(5, 6))
	a.moves_left = 2.0
	var d := g.state.add_unit(1, "HORSEMAN", grid.index_of(6, 6))
	var pv := Combat.preview(g, a, d.tile)
	check_eq(int(pv["att"]), 40, "копейщик 25 + 10 против конницы + 5 копья против регулярной армии")
	g.state.map.set_river_edge(a.tile, 0)
	check_eq(int(Combat.preview(g, a, d.tile)["att"]), 35, "атака через реку −5")


func test_roman_formation_and_testudo() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var leg := g.state.add_unit(0, "SWORDSMAN", grid.index_of(8, 6))
	check_eq(Abilities.unit_name(g, 0, "SWORDSMAN"), "Легионер")
	check(Abilities.has(g, leg, "TESTUDO"))
	check(Abilities.has(g, leg, "ROAD_INSTEAD_OF_MOVE"), "все римские наземные войска строят дороги")
	var mods := Combat.unit_mods(g, leg, "defense", {"vs_ranged": true})
	check_eq(Combat._sum(mods), 5)
	var lor := g.state.add_unit(0, "MAN_AT_ARMS", grid.index_of(12, 6))
	check_eq(Combat._sum(Combat.unit_mods(g, lor, "attack", {})), 0)
	g.state.add_unit(0, "WARRIOR", grid.neighbor(lor.tile, 0))
	g.state.add_unit(0, "WARRIOR", grid.neighbor(lor.tile, 3))
	check_eq(Combat._sum(Combat.unit_mods(g, lor, "attack", {})), 4, "Строй: рядом два своих")
	var foreign := g.state.add_unit(1, "SWORDSMAN", grid.index_of(16, 6))
	check(not Abilities.has(g, foreign, "TESTUDO"), "у нейтральной державы нет римских особенностей")
	check_eq(Abilities.unit_name(g, 1, "SWORDSMAN"), "Мечник")


func test_roman_road() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var u := g.state.add_unit(0, "WARRIOR", grid.index_of(5, 6))
	u.moves_left = 2.0
	g.apply_action({"type": "build_road", "unit": u.id})
	check_eq(g.state.map.road[u.tile], 1)
	check_near(u.moves_left, 0.0, 1e-6, "вместо движения")
	var v := g.state.add_unit(0, "WARRIOR", grid.index_of(10, 6))
	v.moves_left = 1.0
	check(UnitRules.build_road_error(g, v) != "", "уже двигался — нельзя")
	# Дорога через лес: со дороги на дорогу — 1 ОД.
	var t := grid.neighbor(u.tile, 0)
	g.state.map.feature[t] = "WOODS"
	g.state.map.road[t] = 1
	check_near(Movement.step_cost(g, u, u.tile, t), 1.0)
	g.state.map.road[t] = 0
	check_near(Movement.step_cost(g, u, u.tile, t), 2.0)
	var e := g.state.add_unit(1, "WARRIOR", grid.index_of(15, 6))
	e.moves_left = 2.0
	check(UnitRules.build_road_error(g, e) != "", "не римляне дороги не строят")


func test_city_capture() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var s1 := g.state.add_unit(1, "SETTLER", grid.index_of(12, 6))
	CityRules.found_city(g, 1, s1.tile)
	g.state.remove_unit(s1.id)
	var s0 := g.state.add_unit(0, "SETTLER", grid.index_of(4, 6))
	CityRules.found_city(g, 0, s0.tile)
	g.state.remove_unit(s0.id)
	var city: City = g.state.cities_of(1)[0]
	g.state.set_war(0, 1, true)
	var a := g.state.add_unit(0, "SWORDSMAN", grid.neighbor(city.tile, 3))
	a.moves_left = 2.0
	city.hp = 5
	g.apply_action({"type": "attack", "unit": a.id, "target": city.tile})
	check_eq(city.owner, 0, "город захвачен")
	check_eq(a.tile, city.tile)
	check(not city.is_capital and not city.has_building("PALACE"))
	check(not g.state.player(1).alive, "держава без городов и поселенцев выбывает")


func test_walls_absorb() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var s1 := g.state.add_unit(1, "SETTLER", grid.index_of(12, 6))
	CityRules.found_city(g, 1, s1.tile)
	g.state.remove_unit(s1.id)
	var city: City = g.state.cities_of(1)[0]
	city.wall_hp = 100
	g.state.set_war(0, 1, true)
	var a := g.state.add_unit(0, "WARRIOR", grid.neighbor(city.tile, 3))
	a.moves_left = 2.0
	g.apply_action({"type": "attack", "unit": a.id, "target": city.tile})
	check(city.wall_hp < 100, "стены приняли удар")
	check(city.hp > 190, "здоровье города почти не пострадало")
	check(Combat.city_can_strike(g, city))


func test_promotion() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var u := g.state.add_unit(0, "WARRIOR", grid.index_of(5, 6))
	u.moves_left = 2.0
	u.hp = 40
	check(Combat.available_promotions(g, u).is_empty())
	u.xp = 15
	var opts := Combat.available_promotions(g, u)
	check_eq(opts.size(), 2, "два повышения первого уровня")
	g.apply_action({"type": "promote", "unit": u.id, "promotion": "BATTLECRY"})
	check_eq(u.level, 1)
	check_eq(u.hp, 90, "повышение лечит на 50")
	check(Combat.available_promotions(g, u).is_empty(), "до следующего уровня нужно 45 опыта")


func test_heal_and_upgrade() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var s0 := g.state.add_unit(0, "SETTLER", grid.index_of(8, 6))
	CityRules.found_city(g, 0, s0.tile)
	g.state.remove_unit(s0.id)
	var u := g.state.add_unit(0, "SLINGER", grid.index_of(8, 6))
	u.hp = 50
	UnitRules.process_units_turn_start(g, 0, [])
	check_eq(u.hp, 70, "в городе +20")
	u.moves_left = 2.0
	check(UnitRules.upgrade_error(g, u) != "", "лучник не открыт")
	g.state.player(0).known_techs["ARCHERY"] = true
	g.state.player(0).treasury = 100
	check_eq(UnitRules.upgrade_cost(g, u, "ARCHER"), 60, "(60−35)×2+10")
	g.apply_action({"type": "upgrade_unit", "unit": u.id})
	check_eq(u.type, "ARCHER")
	check_near(g.state.player(0).treasury, 40.0)


func test_strategic_requirement() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var s0 := g.state.add_unit(0, "SETTLER", grid.index_of(8, 6))
	CityRules.found_city(g, 0, s0.tile)
	g.state.remove_unit(s0.id)
	var city: City = g.state.cities_of(0)[0]
	var p := g.state.player(0)
	p.known_techs["BRONZE_WORKING"] = true
	p.known_techs["IRON_WORKING"] = true
	var item := {"kind": "unit", "id": "SWORDSMAN"}
	check(CityRules.build_error(g, city, item).contains("Железо"))
	var t := grid.neighbor(city.tile, 0)
	g.state.map.resource[t] = "IRON"
	g.state.map.relief[t] = GameMap.RELIEF_HILLS
	g.state.map.improvement[t] = "MINE"
	UnitRules.process_stockpile(g, 0)
	check_near(float(p.stockpile["IRON"]), 2.0)
	p.stockpile["IRON"] = 20.0
	check_eq(CityRules.build_error(g, city, item), "")


func test_camp_and_village() -> void:
	var r := _war_game()
	var g: Game = r[0]
	var grid: HexGrid = r[1]
	var camp := grid.index_of(10, 6)
	g.state.map.improvement[camp] = "BARBARIAN_CAMP"
	g.state.camps[camp] = {"tile": camp, "timer": 0, "spawned": 0, "target": -1, "scout": -1, "cooldown": 0}
	var u := g.state.add_unit(0, "WARRIOR", grid.neighbor(camp, 3))
	u.moves_left = 2.0
	g.apply_action({"type": "move_unit", "unit": u.id, "target": camp})
	check_eq(g.state.map.improvement[camp], "", "лагерь зачищен")
	check(g.state.player(0).treasury >= 50.0)
	var vil := grid.index_of(14, 6)
	g.state.map.improvement[vil] = "TRIBAL_VILLAGE"
	var sc := g.state.add_unit(0, "SCOUT", grid.neighbor(vil, 3))
	sc.moves_left = 3.0
	var ev := g.apply_action({"type": "move_unit", "unit": sc.id, "target": vil})
	var got := false
	for e in ev:
		if e["type"] == "village_reward":
			got = true
	check(got, "награда племенного поселения")


func test_barbarians_spawn_in_game() -> void:
	var g := small_game(12)
	check(g.state.barbarian_id() >= 0)
	check(not g.state.camps.is_empty(), "лагеря созданы")
	var villages := 0
	for i in g.state.map.size():
		if g.state.map.improvement[i] == "TRIBAL_VILLAGE":
			villages += 1
	check(villages > 0, "племенные поселения есть")
	check(g.state.at_war(0, g.state.barbarian_id()), "с варварами — всегда война")
