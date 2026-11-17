extends TestCase


func _city(game: Game, owner: int, x: int, y: int) -> City:
	return CityRules.found_city(game, owner, game.state.map.grid.index_of(x, y))


func _site(game: Game, city: City) -> int:
	var tile := game.state.map.grid.neighbors(city.tile)[0]
	city.districts.append({"type": "HOLY_SITE", "tile": tile, "tier": 1,
		"buildings": [], "complete": true, "cost": 1.0})
	game.state.map.district[tile] = "HOLY_SITE"
	return tile


func _found(game: Game, city: City) -> void:
	game.state.player(city.owner).faith = 25.0
	var chosen := game.apply_action({"type": "choose_pantheon", "id": "HARVEST"})
	check_eq(chosen[0]["type"], "pantheon_founded")
	game.state.player(city.owner).prophet_points = 20.0
	var recruited := game.apply_action({"type": "recruit_prophet", "city": city.id})
	check_eq(recruited[0]["type"], "unit_created")
	var prophet := game.state.unit(int(recruited[0]["unit"]))
	var result := game.apply_action({"type": "found_religion", "unit": prophet.id,
		"religion": "CATHOLICISM", "follower": "SCHOLARLY", "founder": "TITHE"})
	check_eq(result[0]["type"], "religion_founded")


func test_founder_new_city_and_save() -> void:
	var game := blank_game(32, 16)
	var capital := _city(game, 0, 5, 5)
	_site(game, capital)
	_found(game, capital)
	check_eq(ReligionRules.majority(game, capital), "CATHOLICISM")
	var new_city := _city(game, 0, 11, 5)
	check_eq(ReligionRules.majority(game, new_city), "CATHOLICISM")
	check_near(ReligionRules.followers(game, new_city, "CATHOLICISM"), 0.8)
	var science := float(CityRules.city_yields(game, capital)["science"])
	check(science >= 1.5, "верование последователей прибавляет науку")
	var restored := GameState.from_dict(game.state.to_dict(), game.data)
	check_eq(restored.religions, game.state.religions)
	check_eq(restored.city(new_city.id).religion_pressure, new_city.religion_pressure)
	check_eq(restored.player(0).religion_id, "CATHOLICISM")
	var json_restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(json_restored.religions, game.state.religions)
	var old := game.state.to_dict()
	old["version"] = 9
	old.erase("religions")
	for pd in old["players"]:
		pd.erase("religion_id")
		pd.erase("prophet_points")
	for cd in old["cities"]:
		cd.erase("religion_pressure")
	var migrated := GameState.from_dict(old, game.data)
	check(migrated.religions.is_empty(), "старое сохранение загружается без религии")


func test_missionary_spread_and_border() -> void:
	var game := blank_game(32, 16)
	var origin := _city(game, 0, 5, 5)
	_site(game, origin)
	_found(game, origin)
	var foreign := _city(game, 1, 12, 5)
	game.state.player(0).faith = 75.0
	var recruited := game.apply_action({"type": "recruit_missionary", "city": origin.id})
	check_eq(recruited[0]["type"], "unit_created")
	var unit := game.state.unit(int(recruited[0]["unit"]))
	check(TreatyRules.border_allows(game, unit, origin.tile, foreign.tile), "миссионер входит в мирные земли")
	unit.tile = foreign.tile
	unit.moves_left = 2.0
	var result := game.apply_action({"type": "spread_religion", "unit": unit.id})
	check_eq(result[0]["type"], "religion_spread")
	check_eq(ReligionRules.majority(game, foreign), "CATHOLICISM")
	check_eq(unit.charges, 2)
	check_eq(game.state.player(0).faith, 0.0)


func test_custom_name_and_rejected_duplicate() -> void:
	var game := blank_game(32, 16)
	var city := _city(game, 0, 5, 5)
	_site(game, city)
	game.state.player(0).faith = 25.0
	game.apply_action({"type": "choose_pantheon", "id": "HARVEST"})
	game.state.player(0).prophet_points = 20.0
	var recruited := game.apply_action({"type": "recruit_prophet", "city": city.id})
	var prophet_id: int = recruited[0]["unit"]
	var bad := game.apply_action({"type": "found_religion", "unit": prophet_id,
		"custom_name": "Католицизм", "follower": "SCHOLARLY", "founder": "TITHE"})
	check_eq(bad[0]["type"], "error")
	check(game.state.unit(prophet_id) != null, "ошибка не расходует пророка")
	var good := game.apply_action({"type": "found_religion", "unit": prophet_id,
		"custom_name": "Путь звёзд", "follower": "WORK_ETHIC", "founder": "TITHE"})
	check_eq(good[0]["type"], "religion_founded")
	check_eq(game.state.player(0).religion_id, "CUSTOM_0")
	check_eq(game.state.religions["CUSTOM_0"]["name"], "Путь звёзд")


func test_religious_dependency_and_influence() -> void:
	var game := blank_game(34, 18)
	var origin := _city(game, 0, 5, 5)
	_site(game, origin)
	_found(game, origin)
	var foreign_a := _city(game, 1, 12, 5)
	var foreign_b := _city(game, 1, 18, 5)
	foreign_a.religion_pressure["CATHOLICISM"] = 400.0
	DiplomacyRules.initialize(game)
	for i in 3:
		game.state.turn = i + 1
		ReligionRules.process_round(game)
		DiplomacyRules.close_round(game, [])
	check_eq(float(DiplomacyRules.dependency(game, 1, 0).get("religion", 0.0)), 0.0,
		"ровно половины городов недостаточно")
	foreign_b.religion_pressure["CATHOLICISM"] = 400.0
	foreign_a.population = 5
	foreign_b.population = 5
	for i in 3:
		game.state.turn = i + 4
		ReligionRules.process_round(game)
		DiplomacyRules.close_round(game, [])
	check(float(DiplomacyRules.dependency(game, 1, 0)["religion"]) > 0.0)
	check(float(DiplomacyRules.influence(game, 0)["sources"]["religion"]) > 0.0)
	check_eq(float(ReligionRules.founder_yields(game, 0)["gold"]), 2.0)
	var capped := {"strategic": 60.0, "goods": 15.0, "religion": 25.0,
		"target": 100.0, "goods_target": 15.0, "religion_target": 25.0}
	ConcessionRules.cap_components(capped, 50.0)
	check_near(DiplomacyRules.dependency_value(capped), 50.0)
	check_near(float(capped["religion_target"]), 12.5)


func test_pantheon_cost_unique_bonus_and_save() -> void:
	var game := blank_game(32, 16)
	var city := _city(game, 0, 5, 5)
	var farm := game.state.map.grid.neighbors(city.tile)[1]
	game.state.map.improvement[farm] = "FARM"
	city.worked_tiles.append(farm)
	var base := float(CityRules.city_yields(game, city)["food"])
	game.state.player(0).faith = 25.0
	check_eq(EmpireRules.blocking_decisions(game, 0)[0]["type"], "choose_pantheon")
	var chosen := game.apply_action({"type": "choose_pantheon", "id": "HARVEST"})
	check_eq(chosen[0]["type"], "pantheon_founded")
	check_near(float(CityRules.city_yields(game, city)["food"]), base + 1.0)
	check_near(game.state.player(0).faith, 0.0)
	var rival := _city(game, 1, 18, 5)
	game.state.player(1).faith = 25.0
	game.state.current_player = 1
	var denied := game.apply_action({"type": "choose_pantheon", "id": "HARVEST"})
	check_eq(denied[0]["type"], "error")
	check_eq(game.state.player(1).faith, 25.0)
	var other := game.apply_action({"type": "choose_pantheon", "id": "SEA"})
	check_eq(other[0]["type"], "pantheon_founded")
	check_eq(rival.owner, 1)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.player(0).pantheon, "HARVEST")
	check_eq(restored.player(1).pantheon, "SEA")


func test_apostle_cult_enhancer_and_save() -> void:
	var game := blank_game(32, 16)
	var city := _city(game, 0, 5, 5)
	_site(game, city)
	_found(game, city)
	game.state.player(0).faith = 300.0
	var premature := game.apply_action({"type": "recruit_apostle", "city": city.id})
	check_eq(premature[0]["type"], "error")
	check_eq(game.state.player(0).faith, 300.0)
	city.districts[0]["tier"] = 2
	var base_culture := float(CityRules.city_yields(game, city)["culture"])
	var first := game.apply_action({"type": "recruit_apostle", "city": city.id})
	check_eq(first[0]["type"], "unit_created")
	var apostle := game.state.unit(int(first[0]["unit"]))
	check_eq(apostle.charges, 3)
	var proclaimed := game.apply_action({"type": "proclaim_belief", "unit": apostle.id,
		"kind": "cult", "id": "CATHEDRAL"})
	check_eq(proclaimed[0]["type"], "religion_enhanced")
	check(game.state.unit(apostle.id) == null, "апостол расходуется при провозглашении")
	check_near(float(CityRules.city_yields(game, city)["culture"]), base_culture + 2.0)
	var second := game.apply_action({"type": "recruit_apostle", "city": city.id})
	var second_id: int = second[0]["unit"]
	var duplicate := game.apply_action({"type": "proclaim_belief", "unit": second_id,
		"kind": "cult", "id": "MOSQUE"})
	check_eq(duplicate[0]["type"], "error")
	check(game.state.unit(second_id) != null, "ошибка не расходует апостола")
	var enhanced := game.apply_action({"type": "proclaim_belief", "unit": second_id,
		"kind": "enhancer", "id": "PREACHERS"})
	check_eq(enhanced[0]["type"], "religion_enhanced")
	check_eq(game.state.player(0).faith, 0.0)
	var foreign := _city(game, 1, 12, 5)
	var missionary := game.state.add_unit(0, "MISSIONARY", foreign.tile)
	missionary.charges = 3
	missionary.moves_left = 2.0
	var spread := game.apply_action({"type": "spread_religion", "unit": missionary.id})
	check_eq(spread[0]["type"], "religion_spread")
	check_near(float(foreign.religion_pressure["CATHOLICISM"]), 300.0)
	var restored := GameState.from_json(game.state.to_json(), game.data)
	check_eq(restored.religions, game.state.religions)
	check_eq(restored.player(0).pantheon, "HARVEST")


func test_pantheon_and_religion_from_ai() -> void:
	var game := blank_game(32, 16)
	var city := _city(game, 1, 12, 5)
	_site(game, city)
	city.districts[0]["tier"] = 2
	game.state.current_player = 1
	var player := game.state.player(1)
	player.faith = 350.0
	player.prophet_points = 20.0
	AIPlayer._religion(game, 1)
	check(player.pantheon != "", "ИИ выбирает пантеон")
	check(player.religion_id != "", "ИИ основывает религию")
	AIPlayer._religion(game, 1)
	var religion: Dictionary = game.state.religions[player.religion_id]
	check(str(religion.get("cult_belief", "")) != "", "ИИ выбирает здание культа")
	check(str(religion.get("enhancer_belief", "")) != "", "ИИ выбирает усиление")


func test_other_belief_effects_and_version_ten_save() -> void:
	var game := blank_game(34, 18)
	var city := _city(game, 0, 5, 5)
	_site(game, city)
	_found(game, city)
	city.districts[0]["tier"] = 2
	var religion: Dictionary = game.state.religions["CATHOLICISM"]
	var before := int(CityRules.amenity_info(game, city)["have"])
	religion["cult_belief"] = "PAGODA"
	check_eq(int(CityRules.amenity_info(game, city)["have"]), before + 1)
	religion["enhancer_belief"] = "ORDERS"
	check_eq(ReligionRules.faith_cost(game, 0, "MISSIONARY"), 64)
	check_eq(ReligionRules.faith_cost(game, 0, "APOSTLE"), 128)
	religion["enhancer_belief"] = "TRADITION"
	var target := _city(game, 1, 12, 5)
	ReligionRules.process_round(game)
	check_near(float(target.religion_pressure["CATHOLICISM"]), 4.0)
	var old := game.state.to_dict()
	old["version"] = 10
	for pd in old["players"]:
		pd.erase("pantheon")
	for rid in old["religions"]:
		old["religions"][rid].erase("cult_belief")
		old["religions"][rid].erase("enhancer_belief")
	var restored := Game.new(game.data, GameState.from_dict(old, game.data))
	check_eq(restored.state.player(0).religion_id, "CATHOLICISM")
	check_eq(restored.state.player(0).pantheon, "")
	restored.state.player(0).faith = 25.0
	var chosen := restored.apply_action({"type": "choose_pantheon", "id": "SEA"})
	check_eq(chosen[0]["type"], "pantheon_founded")
