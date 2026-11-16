class_name SaveLoad
extends RefCounted
## Сохранение и загрузка партии (ГДД 18). Формат — точный двоичный снимок GameState
## (JSON терял точность дробных чисел, и партия после загрузки расходилась).
## На Windows файлы лежат в %APPDATA%\Godot\app_userdata\Civ Game\saves\.

const SAVE_DIR := "user://saves/"
const QUICKSAVE := "quicksave"


static func path_for(slot: String) -> String:
	return SAVE_DIR + slot + ".sav"


## Пустая строка — успех; иначе текст ошибки.
static func save(game: Game, slot: String = QUICKSAVE) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if f == null:
		return "Не удалось записать файл сохранения"
	f.store_buffer(game.state.to_bytes())
	f.close()
	return ""


static func exists(slot: String = QUICKSAVE) -> bool:
	return FileAccess.file_exists(path_for(slot))


## Загружает партию; null — файла нет или он повреждён.
static func load_game(data: GameData, slot: String = QUICKSAVE) -> Game:
	if not exists(slot):
		return null
	var f := FileAccess.open(path_for(slot), FileAccess.READ)
	if f == null:
		return null
	var parsed = bytes_to_var(f.get_buffer(f.get_length()))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	for key in ["turn", "current_player", "map", "rng", "settings", "players", "units", "next_unit_id", "start_positions"]:
		if not parsed.has(key):
			return null
	if not parsed["players"] is Array or parsed["players"].is_empty() \
			or not int(parsed["current_player"]) in range(parsed["players"].size()):
		return null
	if not parsed["map"] is Dictionary or int(parsed["map"].get("width", 0)) <= 0 \
			or int(parsed["map"].get("height", 0)) <= 0:
		return null
	return from_dict(data, parsed)


static func from_dict(data: GameData, d: Dictionary) -> Game:
	var version := int(d.get("version", 1))
	if version < 1 or version > GameState.SAVE_VERSION:
		return null
	var game := Game.new(data, GameState.from_dict(d, data))
	# Видимость не сохраняется — пересчитываем.
	for p in game.state.players:
		Visibility.recompute(game, p.id)
	return game
