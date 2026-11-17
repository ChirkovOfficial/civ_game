class_name FinanceRules
extends RefCounted
## Устойчивая финансовая гегемония по собственному чистому доходу державы.


static func validate_data(data: GameData) -> PackedStringArray:
	var errors := PackedStringArray()
	var cfg: Dictionary = data.finance_setup
	if not data.techs.has(str(cfg.get("unlock_tech", ""))):
		errors.append("Финансовая победа: неизвестная технология открытия")
	for key in ["base_income", "income_per_major", "rival_multiplier", "standard_turns"]:
		if float(cfg.get(key, 0)) <= 0.0:
			errors.append("Финансовая победа: неверное значение %s" % key)
	if float(cfg.get("public_estimate_variance", -1)) < 0.0:
		errors.append("Финансовая победа: неверный диапазон оценки")
	if bool(cfg.get("include_deals", true)):
		errors.append("Финансовая победа: платежи по сделкам нельзя включать в доход")
	return errors


static func unlocked(game: Game) -> bool:
	if bool(game.state.finance_data.get("unlocked", false)):
		return true
	for player in game.state.players:
		if not player.is_barbarian and player.has_tech(str(game.data.finance_setup["unlock_tech"])):
			return true
	return false


static func threshold(game: Game) -> float:
	var majors := 0
	for player in game.state.players:
		if not player.is_barbarian:
			majors += 1
	return float(game.data.finance_setup["base_income"]) \
		+ majors * float(game.data.finance_setup["income_per_major"])


static func required_turns(game: Game) -> int:
	return maxi(1, ceili(float(game.data.finance_setup["standard_turns"]) * CityRules.speed_mult(game)))


static func economic_income(game: Game, pid: int) -> float:
	return float(EmpireRules.summary(game, pid)["net_gold"])


static func best_rival_income(game: Game, pid: int) -> float:
	var best := -INF
	for player in game.state.players:
		if player.id != pid and player.alive and not player.is_barbarian:
			best = maxf(best, economic_income(game, player.id))
	return best


static func owns_original_capital(game: Game, pid: int) -> bool:
	var id := int(game.state.original_capitals.get(str(pid), -1))
	var city := game.state.city(id)
	return city != null and city.owner == pid


static func progress(game: Game, pid: int) -> Dictionary:
	var income := economic_income(game, pid)
	var rival := best_rival_income(game, pid)
	var player := game.state.player(pid)
	var goal := float(game.data.finance_setup["rival_multiplier"]) * rival
	var eligible := unlocked(game) and player.alive and not player.is_barbarian \
		and owns_original_capital(game, pid) and player.treasury >= 0.0 \
		and income >= threshold(game) and income >= goal and rival > -INF
	var fraction := minf(income / threshold(game), income / maxf(1.0, goal))
	return {"income": income, "best_rival": rival, "threshold": threshold(game),
		"multiplier": float(game.data.finance_setup["rival_multiplier"]),
		"streak": int(game.state.finance_data.get("streaks", {}).get(str(pid), 0)),
		"required": required_turns(game), "eligible": eligible, "unlocked": unlocked(game),
		"fraction": clampf(fraction, 0.0, 1.0)}


static func begin_turn(game: Game, pid: int, events: Array, bankrupt: bool = false) -> void:
	if not bool(game.state.finance_data.get("unlocked", false)) and unlocked(game):
		game.state.finance_data["unlocked"] = true
		events.append({"type": "world_exchange_opened", "turn": game.state.turn})
	if not unlocked(game):
		return
	var last: Dictionary = game.state.finance_data["last_counted"]
	var key := str(pid)
	if int(last.get(key, -1)) == game.state.turn:
		return
	last[key] = game.state.turn
	var streaks: Dictionary = game.state.finance_data["streaks"]
	var previous := int(streaks.get(key, 0))
	var status := progress(game, pid)
	var next := previous + 1 if bool(status["eligible"]) and not bankrupt else 0
	streaks[key] = next
	if next == 0 and previous > 0:
		events.append({"type": "finance_hegemony_broken", "player": pid})
	elif next > 0:
		var remaining := maxi(0, required_turns(game) - next)
		if next == 1 or remaining <= 5:
			events.append({"type": "finance_hegemony", "player": pid,
				"streak": next, "remaining": remaining})
