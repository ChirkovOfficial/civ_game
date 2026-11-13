class_name Visibility
extends RefCounted
## Туман войны и линии обзора (ГДД 3.1).
##
## Высота препятствия клетки = высота рельефа (холмы 1, горы 3) + добавка
## особенности (лес/джунгли +1). Клетка видна, если все промежуточные клетки
## линии обзора имеют высоту препятствия не больше высоты наблюдателя
## (на равнине 0, на холме 1). Соседние клетки видны всегда.


static func observer_height(game: Game, tile: int) -> int:
	var map := game.state.map
	if map.is_mountain(tile):
		return int(game.data.relief["MOUNTAIN"].get("sight_height", 3))
	if map.is_hills(tile):
		return int(game.data.relief["HILLS"].get("sight_height", 1))
	return 0


static func obstruction_height(game: Game, tile: int) -> int:
	var map := game.state.map
	var h := 0
	if map.is_mountain(tile):
		h = int(game.data.relief["MOUNTAIN"].get("sight_height", 3))
	elif map.is_hills(tile):
		h = int(game.data.relief["HILLS"].get("sight_height", 1))
	h += int(map.feature_def(tile).get("sight_add", 0))
	return h


static func visible_tiles(game: Game, from: int, sight: int) -> PackedInt32Array:
	var grid := game.state.map.grid
	var eye := observer_height(game, from)
	var result := PackedInt32Array()
	for t in grid.tiles_in_radius(from, sight):
		if grid.distance(from, t) <= 1 or _line_clear(game, from, t, eye):
			result.append(t)
	return result


static func _line_clear(game: Game, from: int, to: int, eye: int) -> bool:
	var grid := game.state.map.grid
	# Линия может проходить ровно по ребру — проверяем оба варианта округления.
	for nudge in [1, -1]:
		var clear := true
		for mid in grid.line_between(from, to, nudge):
			if obstruction_height(game, mid) > eye:
				clear = false
				break
		if clear:
			return true
	return false


static func unit_sight(game: Game, unit: Unit) -> int:
	return int(game.data.unit_def(unit.type).get("sight", game.data.const_value("unit_default_sight", 2)))


## Полный пересчёт видимости игрока; разведанные клетки накапливаются.
## Возвращает true, если появились новые разведанные клетки.
static func recompute(game: Game, player_id: int) -> bool:
	var p := game.state.player(player_id)
	p.visible_count.fill(0)
	var newly := false
	var eyes: Array[PackedInt32Array] = []
	for u in game.state.units_of(player_id):
		eyes.append(visible_tiles(game, u.tile, unit_sight(game, u)))
	# Город видит свою территорию и окрестности центра.
	var city_sight: int = int(game.data.const_value("city_sight", 3))
	var map := game.state.map
	for city in game.state.cities_of(player_id):
		eyes.append(visible_tiles(game, city.tile, city_sight))
		var own := PackedInt32Array()
		for t in map.grid.tiles_in_radius(city.tile, int(game.data.const_value("city_border_radius", 5))):
			if map.owner_city[t] == city.id:
				own.append(t)
		eyes.append(own)
	for tiles in eyes:
		for t in tiles:
			p.visible_count[t] += 1
			if p.revealed[t] == Player.FOG_UNEXPLORED:
				p.revealed[t] = Player.FOG_REVEALED
				newly = true
	return newly
