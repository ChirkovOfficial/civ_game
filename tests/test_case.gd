class_name TestCase
extends RefCounted
## Базовый класс тестов. Каждый метод test_* — отдельный тест.

var failures: PackedStringArray = []
var current_test := ""


func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: %s" % [current_test, msg if msg != "" else "условие не выполнено"])


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		failures.append("%s: %s ожидалось %s (%s), получено %s (%s)" % [current_test, msg, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
	elif actual != expected:
		failures.append("%s: %s ожидалось %s, получено %s" % [current_test, msg, str(expected), str(actual)])


func check_near(actual: float, expected: float, eps: float = 1e-6, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		failures.append("%s: %s ожидалось %f, получено %f" % [current_test, msg, expected, actual])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Небольшая тестовая партия (одинаковая для всех тестов при одном зерне).
static func small_game(seed_value: int = 42, map_size: String = "DUEL") -> Game:
	return Game.new_game(GameData.get_default(), {
		"map_size": map_size, "map_type": "CONTINENTS", "seed": seed_value, "humans": [0],
	})


## Пустая партия: карта целиком из лугов, без рек и особенностей — для точных
## проверок правил движения и обзора.
static func blank_game(w: int = 20, h: int = 12, num_players: int = 2) -> Game:
	var data := GameData.get_default()
	var s := GameState.new()
	s.rng = GameRng.new(7)
	s.settings = {"map_size": "CUSTOM", "map_type": "BLANK", "speed": "STANDARD", "seed": "7", "num_civs": num_players}
	s.map = GameMap.new(w, h, data)
	s.map.terrain.fill("GRASS")
	for pid in num_players:
		var p := Player.new()
		p.id = pid
		p.name = "P%d" % pid
		p.color = Color.WHITE
		p.is_ai = pid != 0
		p.civ_trait_id = "ROME" if pid == 0 else ""
		p.init_fog(s.map.size())
		s.players.append(p)
	return Game.new(data, s)
