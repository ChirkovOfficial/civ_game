class_name GameRng
extends RefCounted
## Единственный источник случайности в симуляции (ГДД 25.1 п.3).
## Детерминирован: одинаковое зерно + одинаковые вызовы = одинаковый результат.
## Системный randf()/randi() в ядре использовать запрещено.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## true с вероятностью p.
func chance(p: float) -> bool:
	return _rng.randf() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Выбор индекса по весам (веса >= 0). -1, если все веса нулевые.
func pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return -1
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= maxf(0.0, weights[i])
		if roll < 0.0:
			return i
	return weights.size() - 1


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Производное зерно для независимых подсистем (например, шум генератора карты).
func derive_seed() -> int:
	return _rng.randi()


func to_dict() -> Dictionary:
	# Числа храним строками: JSON теряет точность 64-битных целых.
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


static func from_dict(d: Dictionary) -> GameRng:
	var r := GameRng.new()
	r._rng.seed = int(d["seed"])
	r._rng.state = int(d["state"])
	return r
