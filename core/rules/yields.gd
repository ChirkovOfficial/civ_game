class_name Yields
extends RefCounted
## Доходы клеток (ГДД 3.2, 3.3, 3.6). Доход — словарь {тип: число}, типы из
## constants.yield_types. Отсутствующий ключ = 0.

const TYPES: Array[String] = ["food", "production", "gold", "science", "culture", "faith"]


static func add_into(target: Dictionary, source: Dictionary, mult: float = 1.0) -> void:
	for k in source:
		target[k] = target.get(k, 0) + source[k] * mult


static func total(y: Dictionary) -> float:
	var s := 0.0
	for k in y:
		s += y[k]
	return s


## Виден ли ресурс игроку: стратегические скрыты до открывающей технологии.
## player == null — «взгляд создателя» (генератор карты, тесты).
static func resource_visible(data: GameData, resource_id: String, player: Player) -> bool:
	if resource_id == "":
		return false
	var def: Dictionary = data.resources.get(resource_id, {})
	if not def.has("reveal_tech") or player == null:
		return true
	return player.has_tech(def["reveal_tech"])


## Базовый доход клетки без улучшений и районов (их добавят следующие вехи).
## include_strategic=false — не учитывать стратегические ресурсы (для оценки стартов).
static func tile_yields(map: GameMap, data: GameData, i: int, player: Player = null,
		include_strategic: bool = true) -> Dictionary:
	var y := {}
	if map.is_mountain(i):
		return y
	add_into(y, map.terrain_def(i).get("yields", {}))
	if map.is_hills(i):
		add_into(y, data.relief["HILLS"].get("yields", {}))
	var fid := map.feature[i]
	if fid != "":
		var fdef: Dictionary = data.features[fid]
		add_into(y, fdef.get("yields", {}))
		var per_terrain: Dictionary = fdef.get("terrain_yields", {})
		if per_terrain.has(map.terrain[i]):
			add_into(y, per_terrain[map.terrain[i]])
	var rid := map.resource[i]
	if rid != "":
		var rdef: Dictionary = data.resources[rid]
		var is_strategic: bool = rdef.get("class", "") == "strategic"
		if (include_strategic or not is_strategic) and resource_visible(data, rid, player):
			add_into(y, rdef.get("yields", {}))
	return y
