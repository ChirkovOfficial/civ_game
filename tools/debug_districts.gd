extends SceneTree
## Отладка районов: автоигра N ходов и сводка по городам.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var turns := int(args[0]) if args.size() > 0 else 80
	var g := Game.new_game(GameData.get_default(), {
		"map_size": "SMALL", "map_type": "CONTINENTS", "seed": 3, "humans": [],
	})
	var prof := {}
	for t in turns:
		var t0 := Time.get_ticks_usec()
		AIPlayer.take_turn(g, g.state.current_player)
		var t1 := Time.get_ticks_usec()
		g.apply_action({"type": "end_turn", "force": true})
		var t2 := Time.get_ticks_usec()
		prof["ai"] = int(prof.get("ai", 0)) + t1 - t0
		prof["end"] = int(prof.get("end", 0)) + t2 - t1
	print(prof)
	for c in g.state.cities.values():
		var types := []
		for it in CityRules.district_items(g, c):
			types.append("%s%s" % [it["kind"].substr(0, 4), ":" + it["id"]])
		print("%s (%d) pop %d limit %d queue %s | %s" % [c.name, c.owner, c.population,
			DistrictRules.specialized_limit(c), c.queue, types])
	print(g.state.player(1).known_techs.keys())
	var t3 := Time.get_ticks_usec()
	for i in 20:
		for c in g.state.cities.values():
			CityRules.city_yields(g, c)
	print("city_yields x20: ", (Time.get_ticks_usec() - t3) / 1000, " мс")
	t3 = Time.get_ticks_usec()
	for c in g.state.cities.values():
		CityRules.district_items(g, c)
	print("district_items: ", (Time.get_ticks_usec() - t3) / 1000, " мс")
	quit()
