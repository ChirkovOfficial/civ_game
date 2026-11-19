extends TestCase


func test_both_trees_can_be_researched_from_start_through_renaissance() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	var eras := ["ANCIENT", "CLASSICAL", "MEDIEVAL", "RENAISSANCE"]
	for kind in ["tech", "civic"]:
		var definitions := g.data.techs if kind == "tech" else g.data.civics
		var amount := 32 if kind == "tech" else 24
		for _step in amount:
			var available := EmpireRules.available_techs(g, 0) if kind == "tech" else EmpireRules.available_civics(g, 0)
			var early := available.filter(func(id): return definitions[id]["era"] in eras)
			if early.is_empty():
				check(false, "%s: дерево заблокировано раньше Возрождения" % kind)
				return
			var id: String = early[0]
			check_eq(g.apply_action({"type": "set_research", "kind": kind, "id": id})[0]["type"], "research_changed")
			var cost := EmpireRules.tech_cost(g, id) if kind == "tech" else EmpireRules.civic_cost(g, id)
			EmpireRules.add_research(g, 0, kind, cost, [])
		check_eq(p.known_techs.size() if kind == "tech" else p.known_civics.size(), amount)
	check(EmpireRules.available_techs(g, 0).has("INDUSTRIALIZATION"))
	check(EmpireRules.available_civics(g, 0).has("COLONIALISM"))


func test_migrate_combined_research_in_old_save() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	p.known_techs["SHIPBUILDING"] = true
	p.current_tech = "MILITARY_TACTICS"
	p.tech_progress["MILITARY_TACTICS"] = 36.0
	p.tech_progress["MILITARY_ENGINEERING"] = 20.0
	p.current_civic = "MEDIEVAL_FAIRES"
	p.civic_progress["MEDIEVAL_FAIRES"] = 17.0
	var save := g.state.to_dict()
	save["version"] = 8
	var restored := SaveLoad.from_dict(g.data, save)
	var r := restored.state.player(0)
	check(r.has_tech("CELESTIAL_NAVIGATION"))
	check(not r.has_tech("SHIPBUILDING"))
	check_eq(r.current_tech, "MILITARY_ENGINEERING")
	check_near(r.tech_progress["MILITARY_ENGINEERING"], 36.0)
	check_eq(r.current_civic, "GUILDS")
	check_near(r.civic_progress["GUILDS"], 17.0)


func test_eureka_and_inspiration_are_saved_and_grant_progress_once() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	p.met[1] = true
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	city.population = 6
	var events: Array = []
	EmpireRules.apply_research_boosts(g, 0, events)
	check_eq(events.filter(func(e): return e["type"] == "research_boost").size(), 3)
	check_near(p.tech_progress["WRITING"], 20.0)
	check_near(p.civic_progress["EARLY_EMPIRE"], 28.0)
	check(not p.has_tech("WRITING"), "Эврика не обходит предпосылки")
	var restored := SaveLoad.from_dict(g.data, g.state.to_dict())
	var after: Array = []
	EmpireRules.apply_research_boosts(restored, 0, after)
	check(after.is_empty())
	check_near(restored.state.player(0).tech_progress["WRITING"], 20.0)


func test_late_boost_event_counter_and_old_save() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	EmpireRules.record_research_events(g, [
		{"type": "great_person_recruited", "player": 0, "kind": "SCIENTIST"},
		{"type": "unit_killed", "owner": 2, "by": 0, "by_unit_type": "SLINGER"}])
	var events: Array = []
	EmpireRules.apply_research_boosts(g, 0, events)
	check_near(float(p.tech_progress["EDUCATION"]), EmpireRules.tech_cost(g, "EDUCATION") * 0.4)
	check_near(float(p.tech_progress["ARCHERY"]), EmpireRules.tech_cost(g, "ARCHERY") * 0.4)
	var restored := SaveLoad.from_dict(g.data, g.state.to_dict())
	check_eq(restored.state.player(0).research_stats, p.research_stats)
	var after: Array = []
	EmpireRules.apply_research_boosts(restored, 0, after)
	check(after.is_empty(), "Сохранённые эврики не начисляются второй раз")
	var old := p.to_dict()
	old.erase("research_stats")
	check(Player.from_dict(old).research_stats.is_empty(), "Старые сохранения не содержат счётчиков")


func test_technology_and_institution_improve_worked_tiles() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	var center := g.state.map.grid.index_of(8, 8)
	var neighbors := g.state.map.grid.neighbors(center)
	g.state.map.improvement[center] = "FARM"
	g.state.map.improvement[neighbors[0]] = "FARM"
	g.state.map.improvement[neighbors[1]] = "FARM"
	var base_food := float(CityRules.tile_yields(g, center, p)["food"])
	p.known_civics["FEUDALISM"] = true
	check_near(float(CityRules.tile_yields(g, center, p)["food"]), base_food + 1.0)
	p.known_techs["REPLACEABLE_PARTS"] = true
	check_near(float(CityRules.tile_yields(g, center, p)["food"]), base_food + 3.0)
	g.state.map.improvement[center] = "MINE"
	var base_production := float(CityRules.tile_yields(g, center, p).get("production", 0.0))
	p.known_techs["APPRENTICESHIP"] = true
	check_near(float(CityRules.tile_yields(g, center, p).get("production", 0.0)), base_production + 1.0)
	g.state.map.improvement[center] = "QUARRY"
	var base_gold := float(CityRules.tile_yields(g, center, p).get("gold", 0.0))
	p.known_techs["BANKING"] = true
	check_near(float(CityRules.tile_yields(g, center, p).get("gold", 0.0)), base_gold + 1.0)


func test_distinct_district_boost_counts_types_not_copies() -> void:
	var g := blank_game()
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	for i in 3:
		city.districts.append({"type": "CAMPUS", "tile": city.tile + i + 1, "tier": 1,
			"buildings": [], "complete": true, "cost": 0.0})
	var boost := {"condition": "distinct_districts", "minimum": 3}
	check(not EmpireRules._boost_reached(g, 0, boost))
	for type in ["HARBOR", "INDUSTRIAL_ZONE"]:
		city.districts.append({"type": type, "tile": city.tile + city.districts.size() + 1,
			"tier": 1, "buildings": [], "complete": true, "cost": 0.0})
	check(EmpireRules._boost_reached(g, 0, boost))


func test_walls_require_previous_tier_and_use_new_unlocks() -> void:
	var g := blank_game()
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	var p := g.state.player(0)
	p.known_techs["MASONRY"] = true
	p.known_techs["CASTLES"] = true
	p.known_techs["METAL_CASTING"] = true
	p.treasury = 5000.0
	check_eq(g.apply_action({"type": "purchase", "kind": "building", "id": "RENAISSANCE_WALLS", "city": city.id})[0]["type"], "error")
	for id in ["ANCIENT_WALLS", "MEDIEVAL_WALLS", "RENAISSANCE_WALLS"]:
		check_eq(CityRules.build_error(g, city, {"kind": "building", "id": id}), "")
		g.apply_action({"type": "purchase", "kind": "building", "id": id, "city": city.id})
		check(city.has_building(id))
	check_eq(city.wall_hp, 300)


func test_craft_policy_speeds_builders_through_production() -> void:
	var g := blank_game()
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	var p := g.state.player(0)
	p.known_civics["CRAFTSMANSHIP"] = true
	var slots := GovernmentRules.slots(GovernmentRules.active_government(g, p))
	g.apply_action({"type": "set_policy", "slot": slots.find("economic"), "id": "ILKUM"})
	check_eq(GovernmentRules.policy_at(p, slots.find("economic")), "ILKUM")
	var item := {"kind": "unit", "id": "BUILDER"}
	city.queue.append(item)
	CityRules.process_production(g, city, 10.0, [])
	check_near(city.progress[City.item_key(item)], 13.0)
	g.apply_action({"type": "set_policy", "slot": slots.find("military"), "id": "AGOGE"})
	check_near(GovernmentRules.production_multiplier(g, 0, {"kind": "unit", "id": "WARRIOR"}), 1.5)
