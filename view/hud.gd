class_name Hud
extends CanvasLayer
## Интерфейс поверх карты (временный, до макетов от художника).

signal end_turn_pressed
signal skip_pressed
signal new_map_pressed
signal reveal_toggled(on: bool)

var _turn_label: Label
var _player_swatch: ColorRect
var _unit_panel: PanelContainer
var _unit_label: Label
var _tile_panel: PanelContainer
var _tile_label: Label
var _end_turn_button: Button
var _reveal_button: CheckButton
var _message: Label
var _message_timer := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Верхняя панель: ход и держава.
	var top := _panel(root)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(12, 12)
	var hb := HBoxContainer.new()
	top.add_child(hb)
	_player_swatch = ColorRect.new()
	_player_swatch.custom_minimum_size = Vector2(18, 18)
	hb.add_child(_player_swatch)
	_turn_label = Label.new()
	hb.add_child(_turn_label)

	# Информация о клетке.
	_tile_panel = _panel(root)
	_tile_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tile_panel.position = Vector2(-12, 12)
	_tile_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tile_label = Label.new()
	_tile_panel.add_child(_tile_label)
	_tile_panel.visible = false

	# Выбранный юнит.
	_unit_panel = _panel(root)
	_unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_unit_panel.position = Vector2(12, -12)
	_unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var vb := VBoxContainer.new()
	_unit_panel.add_child(vb)
	_unit_label = Label.new()
	vb.add_child(_unit_label)
	var skip := Button.new()
	skip.text = "Пропустить ход юнита (Пробел)"
	skip.pressed.connect(func(): skip_pressed.emit())
	vb.add_child(skip)
	_unit_panel.visible = false

	# Кнопки справа внизу.
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-12, -12)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(br)
	_reveal_button = CheckButton.new()
	_reveal_button.text = "Вся карта (F2)"
	_reveal_button.toggled.connect(func(on): reveal_toggled.emit(on))
	br.add_child(_reveal_button)
	var new_map := Button.new()
	new_map.text = "Новая карта (F5)"
	new_map.pressed.connect(func(): new_map_pressed.emit())
	br.add_child(new_map)
	_end_turn_button = Button.new()
	_end_turn_button.text = "Конец хода (Enter)"
	_end_turn_button.custom_minimum_size = Vector2(220, 52)
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	br.add_child(_end_turn_button)

	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position = Vector2(-200, 60)
	_message.custom_minimum_size = Vector2(400, 0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	root.add_child(_message)

	# Подсказка по управлению.
	var help := Label.new()
	help.text = "ЛКМ — выбрать юнит · ПКМ — идти · WASD/стрелки, колесо, СКМ — камера · Tab — следующий юнит"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-330, -30)
	help.modulate = Color(1, 1, 1, 0.7)
	root.add_child(help)


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message.text = ""


func show_message(text: String, seconds: float = 2.5) -> void:
	_message.text = text
	_message_timer = seconds


func set_turn(turn: int, player: Player, waiting_units: int) -> void:
	_player_swatch.color = player.color
	var tail := "" if waiting_units == 0 else " · ждут приказа: %d" % waiting_units
	_turn_label.text = "  Ход %d · %s%s" % [turn, player.name, tail]


func set_reveal(on: bool) -> void:
	_reveal_button.set_pressed_no_signal(on)


func show_unit(game: Game, u: Unit) -> void:
	if u == null:
		_unit_panel.visible = false
		return
	_unit_panel.visible = true
	var def := game.data.unit_def(u.type)
	var lines := [def.get("name", u.type)]
	lines.append("Очки движения: %s / %s" % [_fmt(u.moves_left), _fmt(Movement.max_moves(game, u))])
	if def.has("combat"):
		var s := "Сила: %d" % def["combat"]
		if def.has("ranged"):
			s += " · дальний бой: %d (дальность %d)" % [def["ranged"], def.get("range", 1)]
		lines.append(s)
	lines.append("Здоровье: %d" % u.hp)
	if u.orders.get("type", "") == "move":
		lines.append("Идёт к цели…")
	_unit_label.text = "\n".join(lines)


static func _fmt(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.2f" % v


func show_tile(game: Game, viewer: Player, tile: int, reveal_all: bool) -> void:
	if tile < 0 or not (reveal_all or viewer.is_revealed(tile)):
		_tile_panel.visible = false
		return
	_tile_panel.visible = true
	var map := game.state.map
	var lines := []
	var title: String = map.terrain_def(tile).get("name", map.terrain[tile])
	if map.is_mountain(tile):
		title += " · горы"
	elif map.is_hills(tile):
		title += " · холмы"
	lines.append(title)
	if map.feature[tile] != "":
		lines.append(map.feature_def(tile).get("name", map.feature[tile]))
	var rid := map.resource[tile]
	if rid != "" and (reveal_all or Yields.resource_visible(game.data, rid, viewer)):
		var rdef: Dictionary = game.data.resources[rid]
		var cls: String = {"bonus": "бонусный", "luxury": "редкий", "strategic": "стратегический"}.get(rdef.get("class", ""), "")
		lines.append("Ресурс: %s (%s)" % [rdef.get("name", rid), cls])
	if map.has_river(tile):
		lines.append("Река")
	var y := Yields.tile_yields(map, game.data, tile, null if reveal_all else viewer)
	var parts := []
	var names := {"food": "пища", "production": "произв.", "gold": "золото", "science": "наука", "culture": "культура", "faith": "вера"}
	for k in Yields.TYPES:
		if y.get(k, 0) != 0:
			parts.append("%s %s" % [_fmt(y[k]), names[k]])
	lines.append("Доход: " + (", ".join(parts) if not parts.is_empty() else "нет"))
	var move := Movement.terrain_cost(game, tile)
	if map.is_mountain(tile) or map.feature_def(tile).get("impassable", false):
		lines.append("Непроходима")
	elif map.is_land(tile):
		lines.append("Стоимость входа: %s ОД" % _fmt(move))
	_tile_label.text = "\n".join(lines)
