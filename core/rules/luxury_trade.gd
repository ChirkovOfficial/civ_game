class_name LuxuryTrade
extends RefCounted
## Договор передаёт только доступ к одной собственной улучшенной копии.


static func is_luxury(game: Game, rid: String) -> bool:
	return game.data.resources.get(rid, {}).get("class", "") == "luxury"


static func valid_source(game: Game, seller: int, rid: String, tile: int) -> bool:
	var map := game.state.map
	if not map.grid.is_valid_index(tile) or map.resource[tile] != rid or map.pillaged[tile] != 0:
		return false
	var city := game.state.city_owning(tile)
	return city != null and city.owner == seller and CityRules.resource_improved(game, tile)


static func _access(game: Game, contract: Dictionary) -> bool:
	return contract.has("source_tile") and int(contract["remaining"]) > 0 \
		and game.state.player(int(contract["seller"])).alive \
		and game.state.player(int(contract["buyer"])).alive \
		and not game.state.at_war(int(contract["seller"]), int(contract["buyer"])) \
		and valid_source(game, int(contract["seller"]), contract["resource"], int(contract["source_tile"]))


static func _exports(game: Game, pid: int) -> Dictionary:
	var tiles := {}
	for contract in game.state.diplomacy.get("contracts", {}).values():
		if int(contract["seller"]) == pid and _access(game, contract):
			tiles[int(contract["source_tile"])] = true
	return tiles


static func available_sources(game: Game, pid: int, rid: String, include_offered: bool = false) -> Array[int]:
	var sources: Array[int] = []
	var exports := _exports(game, pid)
	if not include_offered:
		for offer in game.state.diplomacy.get("offers", {}).values():
			if int(offer["seller"]) == pid and offer.has("source_tile"):
				exports[int(offer["source_tile"])] = true
	for city in game.state.cities_of(pid):
		for tile in CityRules.owned_tiles(game, city):
			if not exports.has(tile) and valid_source(game, pid, rid, tile):
				sources.append(tile)
	sources.sort()
	return sources


static func kinds(game: Game, pid: int, without_provider: int = -1) -> Dictionary:
	var result := {}
	var exports := _exports(game, pid)
	var map := game.state.map
	for city in game.state.cities_of(pid):
		for tile in CityRules.owned_tiles(game, city):
			var rid := map.resource[tile]
			if is_luxury(game, rid) and not exports.has(tile) and map.pillaged[tile] == 0 \
					and CityRules.resource_improved(game, tile):
				result[rid] = true
	for contract in game.state.diplomacy.get("contracts", {}).values():
		if int(contract["buyer"]) == pid and int(contract["seller"]) != without_provider and _access(game, contract):
			result[contract["resource"]] = true
	return result


static func affected_share(game: Game, buyer: int, seller: int) -> float:
	var imported := false
	for contract in game.state.diplomacy.get("contracts", {}).values():
		if int(contract["buyer"]) == buyer and int(contract["seller"]) == seller and _access(game, contract):
			imported = true
			break
	if not imported:
		return 0.0
	var with_access := kinds(game, buyer)
	var without_access := kinds(game, buyer, seller)
	if with_access.size() == without_access.size():
		return 0.0
	var full := CityRules.distribute_luxuries(game, buyer, with_access)
	var reduced := CityRules.distribute_luxuries(game, buyer, without_access)
	var population := 0
	var affected := 0
	for city in game.state.cities_of(buyer):
		population += city.population
		if CityRules.amenity_info(game, city, full)["state"]["id"] != \
				CityRules.amenity_info(game, city, reduced)["state"]["id"] and full[city.id] > reduced[city.id]:
			affected += city.population
	return float(affected) / population if population > 0 else 0.0


static func invalid_contracts(game: Game) -> Array[String]:
	var result: Array[String] = []
	var contracts: Dictionary = game.state.diplomacy.get("contracts", {})
	for id in contracts:
		if contracts[id].has("source_tile") and not _access(game, contracts[id]):
			result.append(id)
	result.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return result
