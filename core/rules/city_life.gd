class_name CityLife
extends RefCounted
## Городская жизнь (docs/CITIES.md): санитария, порядок, эпидемии, губернаторы и доктрины.
##
## Проблемы начинаются с населения city_life_threshold_pop (10). Ниже — показатели видны,
## но ни на что не влияют.


static func k(game: Game, key: String, default: Variant = 0) -> Variant:
	return game.data.const_value(key, default)


static func active(game: Game, city: City) -> bool:
	return city.population >= int(k(game, "city_life_threshold_pop", 10))


## Жители сверх порога (население 10 → 1, 11 → 2 …): от них растёт «давление».
static func excess_pop(game: Game, city: City) -> int:
	return maxi(0, city.population - int(k(game, "city_life_threshold_pop", 10)) + 1)


# --- Доктрины и губернаторы -----------------------------------------------------------------------

static func doctrine_def(game: Game, id: String) -> Dictionary:
	for d in k(game, "doctrines", []):
		if d.get("id", "") == id:
			return d
	return {}


## Доктрина действует: губернатор вступил в должность.
static func doctrine_active(city: City) -> bool:
	return city.doctrine != "" and city.doctrine_turns <= 0


## Эффект действующей доктрины (с «усталостью» автократии).
static func doctrine_effect(game: Game, city: City) -> Dictionary:
	if not doctrine_active(city):
		return {}
	var d := doctrine_def(game, city.doctrine).duplicate()
	if d.has("fatigue_turns") and game.state.turn - city.doctrine_since >= int(d["fatigue_turns"]):
		d["order"] = float(d.get("order", 0)) + float(d.get("fatigue_order", 0))
	return d


## Каждый город имеет губернатора. Пустой идентификатор снимает специализацию.
static func set_doctrine_error(game: Game, city: City, doctrine: String) -> String:
	if doctrine == city.doctrine:
		return "Эта доктрина уже выбрана"
	if doctrine != "" and doctrine_def(game, doctrine).is_empty():
		return "Нет такой доктрины"
	return ""


## Выбранная доктрина начинает действовать через несколько ходов.
static func set_doctrine(game: Game, city: City, doctrine: String) -> void:
	city.doctrine = doctrine
	city.doctrine_turns = int(k(game, "governor_appoint_turns", 5)) if doctrine != "" else 0
	city.doctrine_since = game.state.turn + city.doctrine_turns


## Расход доктрины за ход: {"gold": x, "faith": y}.
static func doctrine_upkeep(game: Game, city: City) -> Dictionary:
	var d := doctrine_effect(game, city)
	return {"gold": float(d.get("gold_per_pop", 0.0)) * city.population,
		"faith": float(d.get("faith_per_pop", 0.0)) * city.population}


# --- Санитария и порядок -------------------------------------------------------------------------

static func _pressure_mult(game: Game, city: City) -> float:
	var ab := DistrictRules.city_ability(game, city.owner, "NERO_URBANIZATION")
	return float(ab.get("sanitation_pressure_mult", 1.0))


## {"supply", "need", "balance", "sources": [[название, число]]}.
static func sanitation(game: Game, city: City, totals: Dictionary = {}) -> Dictionary:
	if totals.is_empty():
		totals = DistrictRules.city_totals(game, city)
	var sources := []
	var supply := 0.0
	for d in city.districts:
		var o := DistrictRules.output(game, city, d)
		if float(o["sanitation"]) != 0.0:
			sources.append([DistrictRules.display_name(game, city.owner, d["type"], int(d["tier"])), float(o["sanitation"])])
			supply += float(o["sanitation"])
	var de := doctrine_effect(game, city)
	if float(de.get("sanitation", 0)) != 0.0:
		sources.append([de.get("name", ""), float(de["sanitation"])])
		supply += float(de["sanitation"])
	var need := excess_pop(game, city) * float(k(game, "sanitation_per_pop", 0.5)) * _pressure_mult(game, city)
	return {"supply": supply, "need": need, "balance": supply - need, "sources": sources}


static func order(game: Game, city: City) -> Dictionary:
	var sources := []
	var supply := float(k(game, "governor_base_order", 0))
	if supply != 0.0:
		sources.append(["Губернатор", supply])
	for d in city.districts:
		var o := DistrictRules.output(game, city, d)
		if float(o["order"]) != 0.0:
			sources.append([DistrictRules.display_name(game, city.owner, d["type"], int(d["tier"])), float(o["order"])])
			supply += float(o["order"])
	var de := doctrine_effect(game, city)
	if float(de.get("order", 0)) != 0.0:
		sources.append([de.get("name", ""), float(de["order"])])
		supply += float(de["order"])
	var need := excess_pop(game, city) * float(k(game, "order_per_pop", 0.3))
	return {"supply": supply, "need": need, "balance": supply - need, "sources": sources}


## Доля потерь доходов (кроме пищи) от беспорядков: 0..order_unrest_max_penalty.
static func unrest_penalty(game: Game, city: City) -> float:
	if not active(game, city):
		return 0.0
	var bal := float(order(game, city)["balance"])
	if bal >= 0.0:
		return 0.0
	return minf(float(k(game, "order_unrest_max_penalty", 0.5)), -bal * float(k(game, "order_unrest_yield_penalty_per_point", 0.05)))


static func epidemic_chance(game: Game, city: City) -> float:
	if not active(game, city) or city.epidemic_turns > 0:
		return 0.0
	var bal := float(sanitation(game, city)["balance"])
	if bal >= 0.0:
		return 0.0
	return minf(float(k(game, "epidemic_chance_max", 0.3)), -bal * float(k(game, "epidemic_chance_per_point", 0.02)))


## Множитель всех доходов города (эпидемия) и отдельно для не-пищи (беспорядки).
static func yield_mults(game: Game, city: City) -> Dictionary:
	var all := float(k(game, "epidemic_yield_mult", 0.9)) if city.epidemic_turns > 0 else 1.0
	return {"all": all, "non_food": 1.0 - unrest_penalty(game, city)}


static func growth_mult(game: Game, city: City) -> float:
	if city.epidemic_turns > 0:
		return 0.0
	return float(doctrine_effect(game, city).get("growth_mult", 1.0))


# --- Начало хода ------------------------------------------------------------------------------------

## Губернатор вступает в должность, доктрина оплачивается, болезни приходят и уходят.
static func process_city(game: Game, city: City, events: Array) -> void:
	var p := game.state.player(city.owner)
	if city.doctrine != "" and city.doctrine_turns > 0:
		city.doctrine_turns -= 1
		if city.doctrine_turns == 0:
			events.append({"type": "governor_ready", "city": city.id, "doctrine": city.doctrine})
	elif doctrine_active(city):
		var up := doctrine_upkeep(game, city)
		if float(up["faith"]) > 0.0:
			if p.faith >= float(up["faith"]):
				p.faith -= float(up["faith"])
			else:
				# Нечем платить — доктрина приостанавливается на ход.
				city.doctrine_turns = 1
				events.append({"type": "doctrine_unpaid", "city": city.id})
	if city.epidemic_turns > 0:
		city.epidemic_turns -= 1
		if city.epidemic_turns == 0:
			events.append({"type": "epidemic_ended", "city": city.id})
		return
	var ch := epidemic_chance(game, city)
	if ch > 0.0 and game.state.rng.chance(ch):
		city.epidemic_turns = int(k(game, "epidemic_turns", 5))
		if city.population > 1:
			city.population -= 1
			city.food_stored = 0.0
		events.append({"type": "epidemic", "city": city.id, "population": city.population})
