extends TestCase
## Автоигра ИИ (ГДД 23.13, 25.5): воспроизводимость и базовое развитие.


func _autoplay(seed_value: int, turns: int) -> Game:
	var g := Game.new_game(GameData.get_default(), {
		"map_size": "DUEL", "map_type": "CONTINENTS", "seed": seed_value, "humans": [],
	})
	for t in turns:
		AIPlayer.take_turn(g, g.state.current_player)
		g.apply_action({"type": "end_turn", "force": true})
	return g


func test_ai_expands() -> void:
	var g := _autoplay(31, 80)
	for p in g.state.players:
		if p.is_barbarian:
			continue
		var cities := g.state.cities_of(p.id)
		check(cities.size() >= 2, "у %s городов: %d" % [p.name, cities.size()])
		check(p.known_techs.size() >= 3, "у %s технологий: %d" % [p.name, p.known_techs.size()])
		var pop := 0
		for c in cities:
			pop += c.population
		check(pop >= 4, "у %s население %d" % [p.name, pop])


func test_ai_deterministic() -> void:
	var a := _autoplay(5, 40)
	var b := _autoplay(5, 40)
	check(a.state.to_json() == b.state.to_json(), "одинаковое зерно — одинаковая партия")
	var restored := GameState.from_bytes(a.state.to_bytes(), a.data)
	check(restored.to_json() == a.state.to_json(), "сохранение с городами восстанавливается без потерь")
