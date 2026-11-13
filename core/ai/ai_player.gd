class_name AIPlayer
extends RefCounted
## ИИ-противник (ГДД 23). Веха M1: только разведка — боевые юниты идут к
## ближайшей неразведанной области. Полноценные слои ИИ — с вехи M3.


static func take_turn(game: Game, pid: int) -> void:
	for u in game.state.units_of(pid):
		if u.moves_left <= 0.0 or not u.orders.is_empty():
			continue
		if Movement.layer(game, u.type) != "COMBAT":
			continue
		var target := _explore_target(game, u)
		if target >= 0:
			game.apply_action({"type": "move_unit", "unit": u.id, "target": target})


## Ближайшая разведанная проходимая клетка, рядом с которой есть неразведанные.
static func _explore_target(game: Game, u: Unit) -> int:
	var p := game.state.player(u.owner)
	var grid := game.state.map.grid
	var best := -1
	var best_score := -INF
	for t in grid.tiles_in_radius(u.tile, 6):
		if t == u.tile or not p.is_revealed(t) or not Movement.can_stand(game, u, t):
			continue
		var unknown := 0
		for nb in grid.neighbors(t):
			if not p.is_revealed(nb):
				unknown += 1
		if unknown == 0:
			continue
		var score := unknown * 2.0 - grid.distance(u.tile, t) + game.state.rng.randf()
		if score > best_score:
			best_score = score
			best = t
	return best
