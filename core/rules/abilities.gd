class_name Abilities
extends RefCounted
## Особенности юнитов с учётом цивилизации владельца (docs/CIVS.md, data/abilities.json).


static func civ_def(game: Game, owner: int) -> Dictionary:
	if owner < 0 or owner >= game.state.players.size():
		return {}
	return game.data.civs.get(game.state.player(owner).civ_trait_id, {})


## Название юнита для держав owner: своё у цивилизации или нейтральное название слота.
static func unit_name(game: Game, owner: int, unit_type: String) -> String:
	if game.data.unit_def(unit_type).has("era_names") and owner >= 0:
		return Army.commander_name(game, owner, unit_type)
	var civ := civ_def(game, owner)
	var own: Dictionary = civ.get("units", {}).get(unit_type, {})
	if own.has("name"):
		return own["name"]
	return game.data.unit_def(unit_type).get("name", unit_type)


## Все особенности юнита: из слота, общие для наземных боевых юнитов цивилизации и личные.
static func of(game: Game, owner: int, unit_type: String) -> Array[String]:
	var result: Array[String] = []
	var def := game.data.unit_def(unit_type)
	for a in def.get("abilities", []):
		result.append(a)
	var civ := civ_def(game, owner)
	if def.get("domain", "LAND") == "LAND" and Movement.layer(game, unit_type) == "COMBAT":
		for a in civ.get("land_combat_abilities", []):
			if not result.has(a):
				result.append(a)
	for a in civ.get("units", {}).get(unit_type, {}).get("abilities", []):
		if not result.has(a):
			result.append(a)
	return result


static func has(game: Game, u: Unit, ability: String) -> bool:
	return of(game, u.owner, u.type).has(ability)


static func param(game: Game, ability: String, key: String, default: Variant = 0) -> Variant:
	return game.data.abilities.get(ability, {}).get(key, default)
