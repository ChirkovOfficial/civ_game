extends TestCase


func test_policy_slots_and_government_change() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	check_eq(GovernmentRules.active_government(g, p)["id"], "CHIEFDOM")
	check_eq(g.apply_action({"type": "set_government", "id": "ANCIENT_REPUBLIC"})[0]["type"], "error")
	check_eq(g.apply_action({"type": "set_policy", "slot": 1, "id": "URBAN_PLANNING"})[0]["type"], "error")
	p.known_civics["CODE_OF_LAWS"] = true
	check_eq(g.apply_action({"type": "set_policy", "slot": 0, "id": "URBAN_PLANNING"})[0]["type"], "error")
	check_eq(g.apply_action({"type": "set_policy", "slot": 1, "id": "URBAN_PLANNING"})[0]["type"], "policy_changed")
	check_eq(g.apply_action({"type": "set_policy", "slot": 0, "id": "DISCIPLINE"})[0]["type"], "policy_changed")
	p.known_civics["POLITICAL_PHILOSOPHY"] = true
	check_eq(g.apply_action({"type": "set_government", "id": "ANCIENT_REPUBLIC"})[0]["type"], "government_changed")
	check_eq(p.policy_slots, ["URBAN_PLANNING", "", "", "DISCIPLINE"])
	check_eq(g.apply_action({"type": "set_policy", "slot": 1, "id": "URBAN_PLANNING"})[0]["type"], "error")
	check_eq(g.apply_action({"type": "set_policy", "slot": 2, "id": "DIPLOMATIC_MISSIONS"})[0]["type"], "policy_changed")
	check_eq(g.apply_action({"type": "set_government", "id": "CHIEFDOM"})[0]["type"], "government_changed")
	check_eq(p.policy_slots, ["DISCIPLINE", "URBAN_PLANNING"])


func test_effects_and_roundtrip() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	var settler := g.state.add_unit(0, "SETTLER", g.state.map.grid.index_of(8, 6))
	settler.moves_left = 2.0
	g.apply_action({"type": "found_city", "unit": settler.id})
	var city := g.state.cities_of(0)[0]
	var before := CityRules.city_yields(g, city)
	p.known_civics["CODE_OF_LAWS"] = true
	p.known_civics["POLITICAL_PHILOSOPHY"] = true
	g.apply_action({"type": "set_government", "id": "AUTOCRACY"})
	g.apply_action({"type": "set_policy", "slot": 0, "id": "DISCIPLINE"})
	g.apply_action({"type": "set_policy", "slot": 2, "id": "URBAN_PLANNING"})
	g.apply_action({"type": "set_doctrine", "city": city.id, "doctrine": "PERSUASION"})
	check_near(float(CityRules.city_yields(g, city)["production"]), float(before["production"]) + 2.0)
	var warrior := g.state.add_unit(0, "WARRIOR", city.tile)
	check(Combat.unit_mods(g, warrior, "attack", {"vs_irregular": true}).has(["Дисциплина", 5]))
	check(not Combat.unit_mods(g, warrior, "attack", {}).has(["Дисциплина", 5]))
	g.state.add_unit(0, "CATAPULT", city.tile)
	var upkeep := EmpireRules.maintenance(g, 0)
	p.known_civics["STATE_WORKFORCE"] = true
	g.apply_action({"type": "set_policy", "slot": 1, "id": "CONSCRIPTION"})
	check_near(EmpireRules.maintenance(g, 0), upkeep - 1.0)
	var loaded := SaveLoad.from_dict(g.data, g.state.to_dict())
	var restored := loaded.state.player(0)
	check_eq(restored.government, "AUTOCRACY")
	check_eq(restored.policy_slots, p.policy_slots)
	check_eq(loaded.state.city(city.id).doctrine_turns, 5)
	check_eq(CityRules.city_yields(loaded, loaded.state.city(city.id)), CityRules.city_yields(g, city))
	var legacy := p.to_dict()
	legacy.erase("government")
	legacy.erase("policy_slots")
	check_eq(GovernmentRules.active_government(g, Player.from_dict(legacy))["id"], "CHIEFDOM")


func test_new_policies_are_free_and_cultural_government_changes_tourism() -> void:
	var g := blank_game()
	var p := g.state.player(0)
	var city := CityRules.found_city(g, 0, g.state.map.grid.index_of(3, 5))
	city.districts.append({"type": "THEATER_SQUARE", "tile": city.tile + 1, "tier": 2,
		"buildings": [], "complete": true, "cost": 0.0})
	city.great_works = 1
	city.great_work_types.append("WRITING")
	for id in ["POLITICAL_PHILOSOPHY", "OPERA_BALLET", "SUFFRAGE"]:
		p.known_civics[id] = true
	check_eq(g.apply_action({"type": "set_government", "id": "ANCIENT_REPUBLIC"})[0]["type"], "government_changed")
	var baseline := CultureRules.tourism_per_turn(g, 0)
	check_eq(g.apply_action({"type": "set_policy", "slot": 3, "id": "PRINTING_HOUSES"})[0]["type"], "policy_changed")
	check_near(CultureRules.tourism_per_turn(g, 0), baseline * 1.10)
	check_eq(g.apply_action({"type": "set_government", "id": "DEMOCRACY"})[0]["type"], "government_changed")
	check_near(CultureRules.tourism_per_turn(g, 0), baseline * 1.25)
	var policy_slot := p.policy_slots.find("PRINTING_HOUSES")
	check_eq(g.apply_action({"type": "set_policy", "slot": policy_slot, "id": ""})[0]["type"], "policy_changed")
	check_near(CultureRules.tourism_per_turn(g, 0), baseline * 1.15)
