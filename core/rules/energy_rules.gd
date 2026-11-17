class_name EnergyRules
extends RefCounted
## Энергия распределяется один раз в начале хода державы. Снимок сохраняет
## усиленные доходы до следующего хода, даже после расходования топлива.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(data.energy_setup.get("laser_power_demand", 0)) <= 0:
		errors.append("Энергия: нужна положительная потребность лазерной станции")
	for type in data.districts:
		for tier in data.districts[type].get("tiers", []):
			if tier.has("power_demand") and int(tier["power_demand"]) <= 0:
				errors.append("Энергия: неверная потребность района %s" % type)
			if tier.has("renewable_power") and int(tier["renewable_power"]) <= 0:
				errors.append("Энергия: неверная выработка района %s" % type)
			if tier.has("power_plant"):
				var plant: Dictionary = tier["power_plant"]
				if not data.resources.has(str(plant.get("resource", ""))) or \
						int(plant.get("per_resource", 0)) <= 0 or int(plant.get("radius", 0)) <= 0:
					errors.append("Энергия: неверная электростанция района %s" % type)
	for id in data.improvements:
		var improvement: Dictionary = data.improvements[id]
		if improvement.has("renewable_power") and int(improvement["renewable_power"]) <= 0:
			errors.append("Энергия: неверная выработка улучшения %s" % id)
	return errors


static func _empty_report() -> Dictionary:
	return {"demand": 0, "supplied": 0, "spare": 0, "powered": {}, "lasers_powered": 0,
		"laser_sites": 0, "renewable": 0}


static func _consumers(game: Game, city: City) -> Array:
	var result := []
	for district in city.districts:
		if not district.get("complete", false) or game.state.map.pillaged[int(district["tile"])] != 0:
			continue
		for tier in range(1, int(district["tier"]) + 1):
			var def := DistrictRules.tier_def(game, str(district["type"]), tier)
			if int(def.get("power_demand", 0)) > 0:
				result.append({"key": "%d:%d" % [int(district["tile"]), tier],
					"demand": int(def["power_demand"]), "laser": false})
	var sites: Dictionary = ScienceRules.status(game, city.owner).get("laser_sites", {})
	if ScienceRules.has_spaceport(game, city):
		for i in int(sites.get(str(city.id), 0)):
			result.append({"key": "laser:%d" % i,
				"demand": int(game.data.energy_setup["laser_power_demand"]), "laser": true})
	return result


static func _local_power(game: Game, city: City) -> int:
	var total := 0
	for district in city.districts:
		if not district.get("complete", false) or game.state.map.pillaged[int(district["tile"])] != 0:
			continue
		for tier in range(1, int(district["tier"]) + 1):
			total += int(DistrictRules.tier_def(game, str(district["type"]), tier).get("renewable_power", 0))
	for tile in CityRules.owned_tiles(game, city):
		if game.state.map.pillaged[tile] == 0:
			total += int(game.data.improvements.get(game.state.map.improvement[tile], {}).get("renewable_power", 0))
	return total


static func _plants(game: Game, pid: int) -> Array:
	var result := []
	for city in game.state.cities_of(pid):
		for district in city.districts:
			if not district.get("complete", false) or game.state.map.pillaged[int(district["tile"])] != 0:
				continue
			var plant := {}
			for tier in range(1, int(district["tier"]) + 1):
				var def := DistrictRules.tier_def(game, str(district["type"]), tier)
				if def.has("power_plant"):
					plant = def["power_plant"]
			if not plant.is_empty():
				result.append({"tile": int(district["tile"]), "resource": str(plant["resource"]),
					"per_resource": int(plant["per_resource"]), "radius": int(plant["radius"]),
					"available": 0, "burn": 0})
	return result


static func plan(game: Game, pid: int) -> Dictionary:
	var cities := game.state.cities_of(pid)
	var plants := _plants(game, pid)
	var stock := game.state.player(pid).stockpile.duplicate()
	var reports := {}
	var local_remaining := {}
	for city in cities:
		var report := _empty_report()
		var local := _local_power(game, city)
		report["renewable"] = local
		report["laser_sites"] = int(ScienceRules.status(game, pid).get("laser_sites", {}).get(str(city.id), 0))
		for consumer in _consumers(game, city):
			var demand: int = consumer["demand"]
			report["demand"] += demand
			var trial_local := local
			var trial_plants := plants.duplicate(true)
			var trial_stock := stock.duplicate()
			var need := demand
			var drawn := mini(need, trial_local)
			trial_local -= drawn
			need -= drawn
			for plant in trial_plants:
				if need <= 0:
					break
				if game.state.map.grid.distance(int(plant["tile"]), city.tile) > int(plant["radius"]):
					continue
				var rid: String = plant["resource"]
				var per: int = plant["per_resource"]
				if int(plant["available"]) < need:
					var fuel := mini(ceili(float(need - int(plant["available"])) / per),
						floori(float(trial_stock.get(rid, 0.0))))
					plant["available"] += fuel * per
					plant["burn"] += fuel
					trial_stock[rid] = float(trial_stock.get(rid, 0.0)) - fuel
				drawn = mini(need, int(plant["available"]))
				plant["available"] -= drawn
				need -= drawn
			if need > 0:
				continue
			local = trial_local
			plants = trial_plants
			stock = trial_stock
			report["powered"][consumer["key"]] = true
			report["supplied"] += demand
			if consumer["laser"]:
				report["lasers_powered"] += 1
		local_remaining[str(city.id)] = local
		reports[str(city.id)] = report
	# Резерв считается после удовлетворения всех городов, а не до них.
	for city in cities:
		var spare: int = local_remaining[str(city.id)]
		var fuel_seen := {}
		for plant in plants:
			if game.state.map.grid.distance(int(plant["tile"]), city.tile) > int(plant["radius"]):
				continue
			spare += int(plant["available"])
			var rid: String = plant["resource"]
			if not fuel_seen.has(rid):
				fuel_seen[rid] = true
				spare += maxi(0, floori(float(stock.get(rid, 0.0)))) * int(plant["per_resource"])
		reports[str(city.id)]["spare"] = spare
	var burn := {}
	for plant in plants:
		var rid: String = plant["resource"]
		burn[rid] = int(burn.get(rid, 0)) + int(plant["burn"])
	return {"turn": game.state.turn, "cities": reports, "burn": burn}


static func process_turn(game: Game, pid: int, events: Array) -> void:
	var result := plan(game, pid)
	game.state.energy_data[str(pid)] = result
	for rid in result["burn"]:
		var amount := int(result["burn"][rid])
		if amount <= 0:
			continue
		var player := game.state.player(pid)
		player.stockpile[rid] = float(player.stockpile.get(rid, 0.0)) - amount
		DiplomacyRules.record_spend(game, pid, rid, amount)
		events.append({"type": "energy_fuel_burned", "player": pid, "resource": rid, "amount": amount})


static func report(game: Game, city: City) -> Dictionary:
	var record: Dictionary = game.state.energy_data.get(str(city.owner), {})
	if int(record.get("turn", -1)) != game.state.turn:
		record = plan(game, city.owner)
	return record.get("cities", {}).get(str(city.id), _empty_report())


static func powered(game: Game, city: City, tile: int, tier: int) -> bool:
	return bool(report(game, city)["powered"].get("%d:%d" % [tile, tier], false))


static func spare_for_project(game: Game, city: City) -> int:
	var city_report := report(game, city)
	var now := int(ScienceRules.status(game, city.owner).get("laser_sites", {}).get(str(city.id), 0))
	var added := maxi(0, now - int(city_report["laser_sites"]))
	return maxi(0, int(city_report["spare"]) - added * int(game.data.energy_setup["laser_power_demand"]))
