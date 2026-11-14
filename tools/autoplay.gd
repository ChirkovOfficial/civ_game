extends SceneTree
## Автоигра без интерфейса (ГДД 23.13) — статистика для баланса:
##   godot --headless --path . -s tools/autoplay.gd -- [ходов=100] [размер=SMALL] [зерно=1]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 100
	var size := args[1] if args.size() > 1 else "SMALL"
	var seed_value := int(args[2]) if args.size() > 2 else 1
	var g := Game.new_game(GameData.get_default(), {
		"map_size": size, "map_type": "CONTINENTS", "seed": seed_value, "humans": [],
	})
	var t0 := Time.get_ticks_msec()
	for t in turns:
		AIPlayer.take_turn(g, g.state.current_player)
		g.apply_action({"type": "end_turn", "force": true})
	var dt := Time.get_ticks_msec() - t0
	print("Ходов: %d, время: %d мс (%.1f мс/ход)" % [turns, dt, float(dt) / turns])
	for p in g.state.players:
		if p.is_barbarian:
			print("Варвары: лагерей %d, юнитов %d" % [g.state.camps.size(), g.state.units_of(p.id).size()])
			continue
		var cities := g.state.cities_of(p.id)
		var pop := 0
		var buildings := 0
		var districts := []
		var max_pop := 0
		for c in cities:
			pop += c.population
			max_pop = maxi(max_pop, c.population)
			buildings += c.buildings.size()
			for d in c.districts:
				buildings += d["buildings"].size()
				districts.append("%s%s" % [d["type"].substr(0, 4), "" if d["complete"] else "…"])
		var sm := EmpireRules.summary(g, p.id)
		var y: Dictionary = sm["yields"]
		var imps := 0
		for i in g.state.map.size():
			var cid := g.state.map.owner_city[i]
			if cid >= 0 and g.state.city(cid).owner == p.id and g.state.map.improvement[i] != "":
				imps += 1
		print("%-12s городов %d, население %d, зданий %d, улучшений %d, юнитов %d, техн. %d, инст. %d, казна %d, 🔬 %.1f, 🎭 %.1f, 💰 %+.1f" % [
			p.name, cities.size(), pop, buildings, imps, g.state.units_of(p.id).size(),
			p.known_techs.size(), p.known_civics.size(), p.treasury,
			y["science"], y["culture"], sm["net_gold"]])
		print("             районы: %s; крупнейший город %d" % [", ".join(districts), max_pop])
	quit()
