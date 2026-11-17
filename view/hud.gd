class_name Hud
extends CanvasLayer
## Интерфейс поверх карты (временный, до макетов художника).
## Все изменения мира идут через act.call(action) — тот же API, что у ИИ.

signal end_turn_pressed
signal new_map_pressed
signal save_pressed
signal load_pressed
signal menu_pressed
signal reveal_toggled(on: bool)
signal city_closed
## Игрок выбрал район в списке производства — нужно указать клетку на карте.
signal place_district(type: String)

const ICON_DIR := "res://art/icons/placeholder/"
const YIELD_NAMES := {"food": "Пища", "production": "Производство", "gold": "Золото",
	"science": "Наука", "culture": "Культура", "faith": "Вера"}

var game: Game
## Callable(action: Dictionary) -> Array: применить действие (main оборачивает apply_action).
var act: Callable

var _icons := {}
var _root: Control
var _top_box: HBoxContainer
var _unit_panel: PanelContainer
var _unit_box: VBoxContainer
var _tile_panel: PanelContainer
var _tile_label: Label
var _city_panel: PanelContainer
var _city_box: VBoxContainer
var _research_panel: PanelContainer
var _research_box: VBoxContainer
var _end_turn_button: Button
var _reveal_button: CheckButton
var _message: Label
var _message_timer := 0.0

var city_id := -1
var _research_kind := ""


func _ready() -> void:
	for k in YIELD_NAMES:
		var tex = load(ICON_DIR + "yield_%s.svg" % k)
		if tex != null:
			_icons[k] = tex
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var top := _panel(_root)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(10, 10)
	_attach(top)
	_top_box = HBoxContainer.new()
	_top_box.add_theme_constant_override("separation", 14)
	top.add_child(_top_box)

	_tile_panel = _panel(_root)
	_tile_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tile_panel.position = Vector2(-12, -170)
	_tile_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tile_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_attach(_tile_panel)
	_tile_label = Label.new()
	_tile_panel.add_child(_tile_label)
	_tile_panel.visible = false

	_unit_panel = _panel(_root)
	_unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_unit_panel.position = Vector2(10, -10)
	_unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_attach(_unit_panel)
	_unit_box = VBoxContainer.new()
	_unit_panel.add_child(_unit_box)
	_unit_panel.visible = false

	_city_panel = _panel(_root)
	_city_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_city_panel.position = Vector2(-10, 10)
	_city_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_attach(_city_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_city_panel.add_child(scroll)
	_city_box = VBoxContainer.new()
	_city_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_city_box)
	_city_panel.visible = false

	_research_panel = _panel(_root)
	_research_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_research_panel.position = Vector2(-230, 64)
	_attach(_research_panel)
	var rscroll := ScrollContainer.new()
	rscroll.custom_minimum_size = Vector2(440, 520)
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_research_panel.add_child(rscroll)
	_research_box = VBoxContainer.new()
	_research_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(_research_box)
	_research_panel.visible = false

	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-12, -12)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(br)
	_reveal_button = CheckButton.new()
	_reveal_button.text = "Вся карта (F2)"
	_reveal_button.toggled.connect(func(on): reveal_toggled.emit(on))
	br.add_child(_reveal_button)
	_button(br, "Победы и счёт", open_victory)
	_button(br, "Мировая биржа", open_finance)
	var file_row := HBoxContainer.new()
	br.add_child(file_row)
	var save_b := Button.new()
	save_b.text = "Сохранить (F6)"
	save_b.pressed.connect(func(): save_pressed.emit())
	file_row.add_child(save_b)
	var load_b := Button.new()
	load_b.text = "Загрузить (F9)"
	load_b.pressed.connect(func(): load_pressed.emit())
	file_row.add_child(load_b)
	var new_map := Button.new()
	new_map.text = "Новая карта (F5)"
	new_map.pressed.connect(func(): new_map_pressed.emit())
	br.add_child(new_map)
	_button(br, "Главное меню", func(): menu_pressed.emit())
	_end_turn_button = Button.new()
	_end_turn_button.text = "Конец хода (Enter)"
	_end_turn_button.custom_minimum_size = Vector2(280, 56)
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	br.add_child(_end_turn_button)

	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message.position = Vector2(-250, -80)
	_message.custom_minimum_size = Vector2(500, 0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	_message.add_theme_font_size_override("font_size", 20)
	_root.add_child(_message)

	var help := Label.new()
	help.text = "ЛКМ — выбрать · ПКМ — идти/атаковать · Tab — след. юнит · B — город · F — укрепиться · R — дорога · E — снаряжение"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-300, -26)
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.65)
	_root.add_child(help)


# --- Общие элементы ----------------------------------------------------------------------

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13, 0.86)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	# Добавляется в дерево позже, после якорей и позиции: так позиция считается от якоря.
	p.set_meta("pending_parent", parent)
	return p


func _attach(p: Control) -> void:
	var parent: Control = p.get_meta("pending_parent")
	parent.add_child(p)


func _icon(kind: String, size: int = 20) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _icons.get(kind)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.tooltip_text = YIELD_NAMES.get(kind, kind)
	return tr


func _yield_chip(parent: Container, kind: String, text: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.add_child(_icon(kind))
	var l := Label.new()
	l.text = text
	hb.add_child(l)
	parent.add_child(hb)


func _label(parent: Container, text: String, size: int = 0, color: Color = Color.WHITE, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.modulate = color
	parent.add_child(l)
	return l


func _button(parent: Container, text: String, cb: Callable, disabled: bool = false, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func _fmt(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.1f" % v


static func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message.text = ""


func show_message(text: String, seconds: float = 2.5) -> void:
	_message.text = text
	_message_timer = seconds


func set_reveal(on: bool) -> void:
	_reveal_button.set_pressed_no_signal(on)


func is_modal_open() -> bool:
	return _research_panel.visible


# --- Верхняя панель -----------------------------------------------------------------------------

func refresh_top() -> void:
	_clear(_top_box)
	var pid := game.state.current_player
	var p := game.state.player(pid)
	var sw := ColorRect.new()
	sw.color = p.color
	sw.custom_minimum_size = Vector2(16, 16)
	_top_box.add_child(sw)
	_label(_top_box, "Ход %d · %s" % [game.state.turn, p.name])
	var sm := EmpireRules.summary(game, pid)
	var y: Dictionary = sm["yields"]
	_yield_chip(_top_box, "gold", "%d (%+.1f)" % [int(p.treasury), float(sm["net_gold"])])
	_yield_chip(_top_box, "science", "+%s" % _fmt(snappedf(float(y["science"]), 0.1)))
	_yield_chip(_top_box, "culture", "+%s" % _fmt(snappedf(float(y["culture"]), 0.1)))
	_yield_chip(_top_box, "faith", "%d" % int(p.faith))
	var has_cities := not game.state.cities_of(pid).is_empty()
	_research_button("science", "tech", p.current_tech, float(y["science"]), has_cities)
	_research_button("culture", "civic", p.current_civic, float(y["culture"]), has_cities)
	_button(_top_box, "Правительство", open_government)
	_button(_top_box, "Религия", open_religion)
	var wars := 0
	for other in game.state.players:
		if other.id != pid and not other.is_barbarian and game.state.at_war(pid, other.id):
			wars += 1
	var db := Button.new()
	db.text = "Державы" + (" (войн: %d)" % wars if wars > 0 else "")
	var incoming := TreatyRules.offers_for(game, pid).filter(func(offer): return int(offer["to"]) == pid).size()
	incoming += DemandRules.pending_for(game, pid).filter(func(demand): return int(demand["recipient"]) == pid).size()
	if incoming > 0:
		db.text += " · +%d" % incoming
	db.pressed.connect(open_diplomacy)
	_top_box.add_child(db)


func _research_button(icon: String, kind: String, current: String, per_turn: float, enabled: bool) -> void:
	var p := game.state.player(game.state.current_player)
	var b := Button.new()
	b.icon = _icons.get(icon)
	b.add_theme_constant_override("icon_max_width", 18)
	if current == "":
		b.text = "Выбрать технологию" if kind == "tech" else "Выбрать институт"
		if enabled:
			b.modulate = Color(1.0, 0.85, 0.5)
	else:
		var tree: Dictionary = game.data.techs if kind == "tech" else game.data.civics
		var cost := EmpireRules.tech_cost(game, current) if kind == "tech" else EmpireRules.civic_cost(game, current)
		var prog: float = float((p.tech_progress if kind == "tech" else p.civic_progress).get(current, 0.0))
		var t := EmpireRules.turns_left(cost, prog, per_turn)
		b.text = "%s (%s)" % [tree[current]["name"], ("%d х." % t) if t > 0 else "—"]
	b.disabled = not enabled
	b.pressed.connect(func(): open_research(kind))
	_top_box.add_child(b)


# --- Выбор исследования ------------------------------------------------------------------------

func open_research(kind: String) -> void:
	_research_kind = kind
	_research_panel.visible = true
	refresh_research()


func close_research() -> void:
	_research_panel.visible = false


func refresh_research() -> void:
	if not _research_panel.visible:
		return
	if _research_kind == "victory":
		open_victory()
		return
	if _research_kind == "finance":
		open_finance()
		return
	if _research_kind == "diplomacy":
		open_diplomacy()
		return
	if _research_kind == "congress":
		open_congress()
		return
	if _research_kind == "religion":
		open_religion()
		return
	if _research_kind.begins_with("supply:"):
		var parts := _research_kind.split(":")
		open_supply_offer(int(parts[1]), parts[2] == "buy")
		return
	if _research_kind.begins_with("strong_demands:"):
		open_strong_demands(int(_research_kind.get_slice(":", 1)))
		return
	if _research_kind == "government":
		open_government()
		return
	if _research_kind.begins_with("trade:"):
		open_trade(int(_research_kind.split(":")[1]))
		return
	if _research_kind.begins_with("equipment:"):
		open_equipment(int(_research_kind.split(":")[1]))
		return
	_clear(_research_box)
	var pid := game.state.current_player
	var p := game.state.player(pid)
	var is_tech := _research_kind == "tech"
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Технологии" if is_tech else "Социальные институты", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	var sm := EmpireRules.summary(game, pid)
	var per := float(sm["yields"]["science" if is_tech else "culture"])
	var ids := EmpireRules.available_techs(game, pid) if is_tech else EmpireRules.available_civics(game, pid)
	var tree: Dictionary = game.data.techs if is_tech else game.data.civics
	var progress: Dictionary = p.tech_progress if is_tech else p.civic_progress
	var era_names: Dictionary = game.data.const_value("era_names", {})
	for id in ids:
		var def: Dictionary = EmpireRules.tech_display(game, pid, id) if is_tech else tree[id]
		var cost := EmpireRules.tech_cost(game, id) if is_tech else EmpireRules.civic_cost(game, id)
		var t := EmpireRules.turns_left(cost, float(progress.get(id, 0.0)), per)
		var current := (p.current_tech if is_tech else p.current_civic) == id
		var b := _button(_research_box, "%s%s — %s х." % ["▶ " if current else "", def["name"], str(t) if t > 0 else "∞"],
			func(): _choose_research(id), false, "Открывает: %s" % def.get("unlocks_text", ""))
		b.icon = _icons.get("science" if is_tech else "culture")
		b.add_theme_constant_override("icon_max_width", 18)
		var era: String = era_names.get(def.get("era", ""), "")
		var unlocks := str(def.get("unlocks_text", ""))
		if def.has("planned_text"):
			unlocks += "\n    Позже: " + str(def["planned_text"])
		if def.has("boost"):
			var boost_label := "Эврика" if is_tech else "Вдохновение"
			var key := "%s:%s" % [_research_kind, id]
			var boost_status := "получено" if p.research_boosts.has(key) else str(def.get("boost_text", ""))
			unlocks += "\n    %s: %s" % [boost_label, boost_status]
		var desc := _label(_research_box, "    " + (era + " · " if era != "" else "") + unlocks, 12, Color(0.75, 0.78, 0.85), true)
		desc.custom_minimum_size = Vector2(400, 0)
	if ids.is_empty():
		_label(_research_box, "Нет доступных исследований")


## Окно снаряжения юнита (docs/ARMY.md).
func open_equipment(unit_id: int) -> void:
	_research_kind = "equipment:%d" % unit_id
	_research_panel.visible = true
	_clear(_research_box)
	var u := game.state.unit(unit_id)
	if u == null:
		close_research()
		return
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Снаряжение: %s" % Abilities.unit_name(game, u.owner, u.type), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	var cur := Army.equipment_of(game, u)
	var slots: Dictionary = game.data.equipment.get("slots", {})
	for slot in cur:
		_label(_research_box, slots[slot]["name"], 16, Color(1.0, 0.9, 0.6))
		for opt in slots[slot]["options"]:
			var od := Army.option_def(game, opt)
			var on: bool = cur[slot] == opt
			var price := "%d золота" % Army.change_cost(game, u, opt)
			for r in od.get("resource", {}):
				price += ", %d %s" % [int(od["resource"][r]), str(game.data.resources[r]["name"]).to_lower()]
			var err := "" if on else Army.equip_error(game, u, slot, opt)
			var s: String = slot
			var o: String = opt
			_button(_research_box, "%s%s — %s%s" % ["✓ " if on else "", od.get("name", opt), od.get("text", ""), "" if on else " (%s)" % price],
				func(): act.call({"type": "equip", "unit": u.id, "slot": s, "option": o}); open_equipment(u.id), on or err != "", err)
	_label(_research_box, "Регулярные армии — войска держав; иррегулярные — варвары. Сменить снаряжение можно только на своей территории.", 12, Color(0.75, 0.78, 0.85), true)


func open_government() -> void:
	_research_kind = "government"
	_research_panel.visible = true
	_clear(_research_box)
	var p := game.state.player(game.state.current_player)
	var active := GovernmentRules.active_government(game, p)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Правительство · %s" % active["name"], 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	var slot_names: Dictionary = game.data.government_setup["slot_names"]
	var slots := GovernmentRules.slots(active)
	for index in slots.size():
		var row := HBoxContainer.new()
		_research_box.add_child(row)
		_label(row, slot_names[slots[index]])
		var options := OptionButton.new()
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(options)
		var ids: Array[String] = [""]
		options.add_item("Пусто")
		var current := GovernmentRules.policy_at(p, index)
		for id in game.data.policies:
			if id != current and GovernmentRules.policy_error(game, p, index, id) != "":
				continue
			var policy: Dictionary = game.data.policies[id]
			options.add_item(policy["name"])
			options.set_item_tooltip(ids.size(), GovernmentRules.effect_text(policy))
			ids.append(id)
		options.select(ids.find(current))
		options.item_selected.connect(func(choice: int):
			act.call({"type": "set_policy", "slot": index, "id": ids[choice]}))
		if current != "":
			_label(_research_box, GovernmentRules.effect_text(game.data.policies[current]), 12, Color(0.75, 0.78, 0.85), true)
	var current_tier := -1
	for def in game.data.governments.values():
		if int(def["tier"]) != current_tier:
			current_tier = int(def["tier"])
			_label(_research_box, "Ступень %d" % current_tier if current_tier > 0 else "Начальная форма", 16)
		var id: String = def["id"]
		var err := GovernmentRules.government_error(game, p, id)
		var description := GovernmentRules.effect_text(def)
		var label: String = def["name"]
		if id == active["id"]:
			label += " · действует"
		elif err != "":
			label += " · " + game.data.civics[def["civic"]]["name"]
		_button(_research_box, label, func(): act.call({"type": "set_government", "id": id}), err != "", description)
		if description != "":
			_label(_research_box, description, 12, Color(0.75, 0.78, 0.85), true)


func open_trade(unit_id: int) -> void:
	var unit := game.state.unit(unit_id)
	if unit == null or unit.owner != game.state.current_player or not unit.trade_route.is_empty():
		close_research()
		return
	_research_kind = "trade:%d" % unit_id
	_research_panel.visible = true
	_clear(_research_box)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Торговый путь", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	_label(_research_box, "Действующие пути · %d из %d" % [TradeRules.active_count(game, unit.owner),
		TradeRules.capacity(game, unit.owner)])
	var error := TradeRules.start_error(game, unit)
	if error != "":
		_label(_research_box, error, 0, Color.WHITE, true)
		return
	var routes := TradeRules.options(game, unit)
	if routes.is_empty():
		_label(_research_box, "Нет доступных городов назначения")
	for route in routes:
		var id := int(route["destination"])
		var city := game.state.city(id)
		var label := "%s · %s · %d х." % [city.name, game.state.player(city.owner).name, int(route["turns"])]
		_button(_research_box, label, func(): act.call({"type": "start_trade", "unit": unit_id, "destination": id}))
		_label(_research_box, _trade_yields_text(route), 12, Color(0.75, 0.78, 0.85), true)


func _trade_yields_text(route: Dictionary) -> String:
	var parts: PackedStringArray = []
	var yields := TradeRules.route_yields(game, route)
	for kind in Yields.TYPES:
		if yields.has(kind):
			parts.append("+%s %s" % [_fmt(float(yields[kind])), str(YIELD_NAMES[kind]).to_lower()])
	return " · ".join(parts)


func open_religion() -> void:
	_research_kind = "religion"
	_research_panel.visible = true
	_clear(_research_box)
	var pid := game.state.current_player
	var player := game.state.player(pid)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Религия", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	_label(_research_box, "Вера: %d · очки Великого пророка: %d/%d · основано религий: %d/%d" % [
		int(player.faith), int(player.prophet_points), int(ReligionRules.cfg(game, "prophet_points")),
		game.state.religions.size(), ReligionRules.prophet_limit(game)], 14)
	if player.pantheon == "":
		_label(_research_box, "Пантеон · %d веры. Каждый пантеон можно выбрать только один раз в мире." % int(ReligionRules.cfg(game, "pantheon_faith_cost")), 15, Color.WHITE, true)
		for option in ReligionRules.pantheon_options(game):
			var pantheon_id: String = option["id"]
			var pantheon_error := ReligionRules.pantheon_error(game, pid, pantheon_id)
			_button(_research_box, "%s — %s" % [option["name"], option["text"]],
				func(): act.call({"type": "choose_pantheon", "id": pantheon_id}); open_religion(),
				pantheon_error != "", pantheon_error)
	else:
		var pantheon := ReligionRules.belief(game, "pantheons", player.pantheon)
		_label(_research_box, "Пантеон: %s — %s" % [pantheon.get("name", player.pantheon), pantheon.get("text", "")], 14, Color.WHITE, true)
	if player.religion_id != "":
		var mine: Dictionary = game.state.religions[player.religion_id]
		var holy_city := game.state.city(int(mine["holy_city"]))
		_label(_research_box, "Ваша религия: %s · священный город: %s" % [mine["name"],
			holy_city.name if holy_city != null else "утрачен"], 16)
		_label(_research_box, "Последователи: %s · основатель: %s" % [
			ReligionRules.belief(game, "follower_beliefs", mine["follower_belief"])["name"],
			ReligionRules.belief(game, "founder_beliefs", mine["founder_belief"])["name"]], 13)
		for kind in ["cult", "enhancer"]:
			var chosen: String = str(mine.get(kind + "_belief", ""))
			var title_text := "Здание культа" if kind == "cult" else "Усиление"
			var chosen_def := ReligionRules.belief(game, kind + "_beliefs", chosen)
			_label(_research_box, "%s: %s%s" % [title_text, chosen_def.get("name", "не выбрано"),
				(" — " + str(chosen_def["text"])) if chosen_def.has("text") else ""], 13, Color.WHITE, true)
			if chosen != "":
				continue
			for unit in game.state.units_of(pid):
				if unit.type != "APOSTLE":
					continue
				var options: Array = ReligionRules.cfg(game, kind + "_beliefs", [])
				if options.is_empty() or ReligionRules.proclaim_error(game, unit, kind, str(options[0]["id"])) != "":
					continue
				for option in options:
					var option_id: String = option["id"]
					var apostle_id := unit.id
					var belief_kind: String = kind
					var error := ReligionRules.proclaim_error(game, unit, belief_kind, option_id)
					if error == "":
						_button(_research_box, "Провозгласить: %s — %s" % [option["name"], option["text"]],
							func(): act.call({"type": "proclaim_belief", "unit": apostle_id,
								"kind": belief_kind, "id": option_id}); open_religion())
				break
		_label(_research_box, "Инквизиция: %s" % ("учреждена" if bool(mine.get("inquisition_started", false)) else "не учреждена"), 14)
		if not bool(mine.get("inquisition_started", false)):
			for unit in game.state.units_of(pid):
				if ReligionRules.inquisition_error(game, unit) == "":
					var apostle_id := unit.id
					_button(_research_box, "Учредить инквизицию апостолом", func():
						act.call({"type": "start_inquisition", "unit": apostle_id}); open_religion())
					break
	else:
		var prophet: Unit = null
		for unit in game.state.units_of(pid):
			if unit.type == "PROPHET":
				prophet = unit
				break
		if prophet != null:
			_label(_research_box, "Выберите название и два верования. Пророк должен стоять на своём Священном месте.", 13, Color.WHITE, true)
			var names := OptionButton.new()
			var custom_name := LineEdit.new()
			custom_name.placeholder_text = "Или введите собственное название"
			var followers := OptionButton.new()
			var founders := OptionButton.new()
			for option in ReligionRules.name_options(game):
				names.add_item(option["name"])
				names.set_item_metadata(names.item_count - 1, option["id"])
			for option in ReligionRules.cfg(game, "follower_beliefs", []):
				followers.add_item(option["name"])
				followers.set_item_metadata(followers.item_count - 1, option["id"])
			for option in ReligionRules.cfg(game, "founder_beliefs", []):
				founders.add_item(option["name"])
				founders.set_item_metadata(founders.item_count - 1, option["id"])
			_research_box.add_child(names)
			_research_box.add_child(custom_name)
			_research_box.add_child(followers)
			_research_box.add_child(founders)
			var prophet_id := prophet.id
			var ready := names.item_count > 0
			_button(_research_box, "Основать религию", func():
				act.call({"type": "found_religion", "unit": prophet_id,
					"religion": names.get_item_metadata(names.selected) if names.item_count > 0 else "",
					"custom_name": custom_name.text,
					"follower": followers.get_item_metadata(followers.selected),
					"founder": founders.get_item_metadata(founders.selected)})
				open_religion(), not ready and custom_name.text.strip_edges() == "")
	for city in game.state.cities_of(pid):
		var rid := ReligionRules.majority(game, city)
		var label: String = str(game.state.religions.get(rid, {}).get("name", "нет большинства"))
		_label(_research_box, "%s · %s" % [city.name, label], 14)
		if player.religion_id == "":
			var prophet_error := ReligionRules.prophet_error(game, pid, city)
			if prophet_error == "":
				var city_id_for_prophet := city.id
				_button(_research_box, "Нанять Великого пророка в %s" % city.name,
					func(): act.call({"type": "recruit_prophet", "city": city_id_for_prophet}); open_religion())
		else:
			var missionary_error := ReligionRules.missionary_error(game, pid, city)
			if missionary_error == "":
				var city_id_for_missionary := city.id
				_button(_research_box, "Купить миссионера в %s · %d веры" % [city.name, ReligionRules.faith_cost(game, pid, "MISSIONARY")],
					func(): act.call({"type": "recruit_missionary", "city": city_id_for_missionary}); open_religion())
			var apostle_error := ReligionRules.apostle_error(game, pid, city)
			if apostle_error == "":
				var apostle_city_id := city.id
				_button(_research_box, "Купить апостола в %s · %d веры" % [city.name, ReligionRules.faith_cost(game, pid, "APOSTLE")],
					func(): act.call({"type": "recruit_apostle", "city": apostle_city_id}); open_religion())
			var inquisitor_error := ReligionRules.inquisitor_error(game, pid, city)
			if inquisitor_error == "":
				var inquisitor_city_id := city.id
				_button(_research_box, "Купить инквизитора в %s · %d веры" % [city.name, ReligionRules.faith_cost(game, pid, "INQUISITOR")],
					func(): act.call({"type": "recruit_inquisitor", "city": inquisitor_city_id}); open_religion())
	var conflict_data: Dictionary = game.state.religious_conflicts
	for key in conflict_data["incidents"]:
		var incident: Dictionary = conflict_data["incidents"][key]
		if int(incident["victim"]) != pid:
			continue
		if ReligiousConflictRules.protest_error(game, pid, int(incident["id"])) == "":
			var incident_id: int = incident["id"]
			var city := game.state.city(incident["city"])
			_label(_research_box, "Активная проповедь державы %s в городе %s, круг %d" % [
				game.state.player(int(incident["offender"])).name, city.name if city != null else "утрачен", int(incident["round"])], 13)
			_button(_research_box, "Потребовать прекратить проповедь на 10 кругов", func():
				act.call({"type": "religious_protest", "incident": incident_id}); open_religion())
	for key in conflict_data["requests"]:
		var request: Dictionary = conflict_data["requests"][key]
		if int(request["offender"]) == pid and str(request["status"]) == "pending":
			var request_id: int = request["id"]
			_label(_research_box, "Протест державы %s: прекратить активную проповедь" % game.state.player(int(request["victim"])).name, 13)
			_button(_research_box, "Принять требование", func():
				act.call({"type": "respond_religious_protest", "request": request_id, "accept": true}); open_religion())
			_button(_research_box, "Отказать", func():
				act.call({"type": "respond_religious_protest", "request": request_id, "accept": false}); open_religion())
	for key in conflict_data["promises"]:
		var promise: Dictionary = conflict_data["promises"][key]
		if int(promise["victim"]) == pid or int(promise["offender"]) == pid:
			_label(_research_box, "Обещание: %s не проповедует у %s до круга %d" % [
				game.state.player(int(promise["offender"])).name,
				game.state.player(int(promise["victim"])).name, int(promise["until_round"])], 13)
	for key in conflict_data["breaches"]:
		var breach: Dictionary = conflict_data["breaches"][key]
		if int(breach["victim"]) == pid:
			_label(_research_box, "Нарушение обещания державой %s, круг %d" % [
				game.state.player(int(breach["offender"])).name, int(breach["round"])], 13)
	for proof in CongressRules.evidence_for(game, pid):
		if str(proof.get("kind", "")) == "religious":
			_label(_research_box, "Есть основание для обращения в ООН против державы %s" %
				game.state.player(int(proof["offender"])).name, 13)
			_button(_research_box, "Перейти к делу в ООН", open_congress)
			break
	if game.state.religions.size() > 0:
		_label(_research_box, "Основанные религии", 16)
		for rid in game.state.religions:
			var religion: Dictionary = game.state.religions[rid]
			_label(_research_box, "%s · %s" % [religion["name"], game.state.player(int(religion["founder"])).name], 13)


func open_diplomacy() -> void:
	_research_kind = "diplomacy"
	_research_panel.visible = true
	_clear(_research_box)
	var pid := game.state.current_player
	var me := game.state.player(pid)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Державы", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "ООН", open_congress)
	_button(head, "✕", close_research)
	var d: Dictionary = game.state.diplomacy
	var score: Dictionary = d.get("influence", {}).get(str(pid), {})
	_label(_research_box, "Мировое влияние: %s / 1000 · цель %s" % [
		_fmt(float(score.get("value", 0.0))), _fmt(float(score.get("target", 0.0)))], 16)
	var sources: Dictionary = score.get("sources", {})
	_label(_research_box, "Перевес зависимости %s · пути %s · поставки %s · жизнь городов %s · дружба и союзы %s" % [
		_fmt(float(sources.get("dependency", 0.0))), _fmt(float(sources.get("routes", 0.0))),
		_fmt(float(sources.get("supplies", 0.0))), _fmt(float(sources.get("living", 0.0))),
		_fmt(float(sources.get("relations", 0.0)))],
		12, Color(0.75, 0.78, 0.85), true)
	_label(_research_box, "Религия %s · туризм и международные события появятся вместе с их механиками." % _fmt(float(sources.get("religion", 0.0))),
		12, Color(0.75, 0.78, 0.85), true)
	if float(sources.get("congress_damage", 0)) > 0.0:
		_label(_research_box, "Штраф к влиянию за нарушение резолюций · −%d" % int(sources["congress_damage"]), 13)
	_show_treaty_offers(pid)
	_show_demands(pid)
	var any := false
	for other in game.state.players:
		if other.id == pid or other.is_barbarian or not me.met.has(other.id):
			continue
		any = true
		var row := HBoxContainer.new()
		_research_box.add_child(row)
		var sw := ColorRect.new()
		sw.color = other.color
		sw.custom_minimum_size = Vector2(14, 14)
		row.add_child(sw)
		var war := game.state.at_war(pid, other.id)
		var st := "выбыла" if not other.alive else ("ВОЙНА" if war else "мир")
		var l := _label(row, "%s — %s · городов: %d" % [other.name, st, game.state.cities_of(other.id).size()])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not other.alive:
			continue
		var oid := other.id
		var sight := DiplomaticVisibility.sources(game, pid, oid)
		_label(_research_box, "Видимость: наша %d/%d · их %d/%d · представительство %s · путь %s · союз %s · Книгопечатание %s" % [
			DiplomaticVisibility.level(game, pid, oid), DiplomaticVisibility.maximum_level(game, pid, oid),
			DiplomaticVisibility.level(game, oid, pid), DiplomaticVisibility.maximum_level(game, oid, pid),
			"да" if sight["representation"] else "нет", "да" if sight["route"] else "нет",
			"да" if sight["alliance"] else "нет", "да" if sight["printing"] else "нет"],
			12, Color(0.75, 0.78, 0.85), true)
		var plans := DiplomaticVisibility.disclosed_plans(game, pid, oid)
		if plans.has("tech"):
			var tech := str(plans["tech"])
			var civic := str(plans["civic"])
			_label(_research_box, "Их планы: технология — %s; институт — %s" % [
				str(game.data.techs.get(tech, {}).get("name", "не выбрана")),
				str(game.data.civics.get(civic, {}).get("name", "не выбран"))], 12)
		if plans.has("production"):
			for city in game.state.cities_of(oid):
				var item: Dictionary = plans["production"].get(city.id, {})
				_label(_research_box, "Их производство · %s: %s" % [city.name,
					CityRules.item_name(game, item, oid) if not item.is_empty() else "ничего"], 12)
		if CongressRules.embargoed(game, pid, oid):
			_label(_research_box, "Эмбарго до начала хода %d" % CongressRules.embargo_until(game, pid, oid), 13)
		_show_treaty_status(pid, oid)
		var ours: Dictionary = d.get("dependency", {}).get("%d,%d" % [pid, oid], {})
		var theirs: Dictionary = d.get("dependency", {}).get("%d,%d" % [oid, pid], {})
		_label(_research_box, "Мы зависим: %s · зависит от нас: %s" % [
			_fmt(DiplomacyRules.dependency_value(ours)), _fmt(DiplomacyRules.dependency_value(theirs))],
			12, Color(0.75, 0.78, 0.85), true)
		if float(ours.get("goods", 0.0)) > 0.0 or float(theirs.get("goods", 0.0)) > 0.0:
			_label(_research_box, "Из них редкие ресурсы · мы %s · они %s" % [
				_fmt(float(ours.get("goods", 0.0))), _fmt(float(theirs.get("goods", 0.0)))], 12, Color.WHITE, true)
		if float(ours.get("religion", 0.0)) > 0.0 or float(theirs.get("religion", 0.0)) > 0.0:
			_label(_research_box, "Из них религия · мы %s · они %s" % [
				_fmt(float(ours.get("religion", 0.0))), _fmt(float(theirs.get("religion", 0.0)))], 12, Color.WHITE, true)
		if not ours.is_empty() and float(ours.get("strategic", 0.0)) > 0.0:
			_label(_research_box, "Наш источник: %s · целевой уровень %s" % [
				str(game.data.resources.get(ours.get("main_resource", ""), {}).get("name", "ресурс")),
				_fmt(float(ours.get("target", 0.0)) - float(ours.get("goods_target", 0.0)) - float(ours.get("religion_target", 0.0)))], 12, Color(0.75, 0.78, 0.85), true)
		if not theirs.is_empty() and float(theirs.get("strategic", 0.0)) > 0.0:
			_label(_research_box, "Их источник: %s · целевой уровень %s" % [
				str(game.data.resources.get(theirs.get("main_resource", ""), {}).get("name", "ресурс")),
				_fmt(float(theirs.get("target", 0.0)) - float(theirs.get("goods_target", 0.0)) - float(theirs.get("religion_target", 0.0)))], 12, Color(0.75, 0.78, 0.85), true)
		if war:
			var e := UnitRules.make_peace_error(game, pid, oid)
			_button(row, "Заключить мир", func(): act.call({"type": "make_peace", "target": oid}); open_diplomacy(), e != "", e)
		else:
			var e2 := UnitRules.declare_war_error(game, pid, oid)
			_button(row, "Объявить войну", func(): act.call({"type": "declare_war", "target": oid}); open_diplomacy(), e2 != "", e2)
			var delegation_error := DiplomaticVisibility.delegation_error(game, pid, oid)
			_button(_research_box, "Отправить делегацию · %d золота" % int(game.data.visibility_setup["delegation_cost"]),
				func(): act.call({"type": "send_delegation", "target": oid}),
				delegation_error != "", delegation_error)
			var embassy_error := DiplomaticVisibility.embassy_error(game, pid, oid)
			_button(_research_box, "Обменяться посольствами",
				func(): act.call({"type": "establish_embassy", "target": oid}),
				embassy_error != "", embassy_error)
			var actions := HBoxContainer.new()
			_research_box.add_child(actions)
			var embargo := CongressRules.embargoed(game, pid, oid)
			_button(actions, "Купить ресурс", func(): open_supply_offer(oid, true), embargo, "Действует эмбарго" if embargo else "")
			_button(actions, "Продать ресурс", func(): open_supply_offer(oid, false), embargo, "Действует эмбарго" if embargo else "")
			var treaties := HBoxContainer.new()
			_research_box.add_child(treaties)
			for kind in TreatyRules.KINDS:
				if kind == "alliance" and TreatyRules.alliance_level(game, pid, oid) == 0:
					continue
				var error := TreatyRules.offer_error(game, kind, pid, oid)
				_button(treaties, _treaty_label(kind),
					func(): act.call({"type": "propose_treaty", "kind": kind, "target": oid}),
					error != "", error)
			if TreatyRules.alliance_level(game, pid, oid) == 0:
				_label(_research_box, "Предложить союз с направлением:", 12)
				var choices := GridContainer.new()
				choices.columns = 2
				_research_box.add_child(choices)
				for specialization in game.data.diplomacy["alliance_specializations"]:
					var alliance_error := TreatyRules.offer_error(game, "alliance", pid, oid)
					var choice := str(specialization)
					var def: Dictionary = game.data.diplomacy["alliance_specializations"][choice]
					_button(choices, str(def["name"]),
						func(): act.call({"type": "propose_treaty", "kind": "alliance", "target": oid,
							"specialization": choice}), alliance_error != "",
						alliance_error if alliance_error != "" else str(def["description"]))
			var passage_error := DemandRules.issue_error(game, pid, oid, "passage")
			_button(_research_box, "Потребовать проход",
				func(): act.call({"type": "issue_demand", "kind": "passage", "target": oid}),
				passage_error != "", _demand_tooltip(passage_error))
			if DiplomacyRules.dependency_value(theirs) > float(game.data.diplomacy["strong_demand_threshold"]):
				_button(_research_box, "Сильные требования", func(): open_strong_demands(oid))
	if not any:
		_label(_research_box, "Вы ещё ни с кем не встретились.")
	var offer_ids: Array = d.get("offers", {}).keys()
	offer_ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in offer_ids:
		var offer: Dictionary = d["offers"][id]
		if pid not in [int(offer["seller"]), int(offer["buyer"])]:
			continue
		var other_id := int(offer["buyer"]) if int(offer["seller"]) == pid else int(offer["seller"])
		var direction := "продаём" if int(offer["seller"]) == pid else "покупаем"
		var heading := "Предложение №%s · %s · %s" % [id, game.state.player(other_id).name, direction]
		_label(_research_box, heading, 15)
		_label(_research_box, _supply_summary(offer), 12, Color(0.75, 0.78, 0.85), true)
		if int(offer.get("responder", offer["buyer"])) == pid:
			var controls := HBoxContainer.new()
			_research_box.add_child(controls)
			var offer_id := int(id)
			_button(controls, "Принять", func(): act.call({"type": "respond_supply", "id": offer_id, "accept": true}); open_diplomacy())
			_button(controls, "Отказать", func(): act.call({"type": "respond_supply", "id": offer_id, "accept": false}); open_diplomacy())
			if int(offer["buyer"]) == pid and int(offer["seller"]) == other_id:
				var discount_error := DemandRules.issue_error(game, pid, other_id, "discount", offer_id)
				_button(controls, "Потребовать скидку",
					func(): act.call({"type": "issue_demand", "kind": "discount", "target": other_id, "offer": offer_id}),
					discount_error != "", _demand_tooltip(discount_error))
		else:
			_label(_research_box, "Ожидаем ответа")
	var contract_ids: Array = d.get("contracts", {}).keys()
	contract_ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in contract_ids:
		var contract: Dictionary = d["contracts"][id]
		if pid not in [int(contract["seller"]), int(contract["buyer"])]:
			continue
		var partner := int(contract["buyer"]) if int(contract["seller"]) == pid else int(contract["seller"])
		_label(_research_box, "Договор №%s · %s" % [id, game.state.player(partner).name], 15)
		var description: String = game.data.resources[contract["resource"]]["name"]
		description += " · доступ к одной копии" if contract.has("source_tile") else ": %s за ход" % _fmt(float(contract["per_turn"]))
		_label(_research_box, "%s · осталось %d ходов · в резерве %s золота" % [description,
			int(contract["remaining"]), _fmt(DiplomacyRules.escrow_cents(contract) / 100.0)], 12, Color(0.75, 0.78, 0.85), true)
		var contract_id := int(id)
		_button(_research_box, "Прекратить договор", func(): act.call({"type": "cancel_supply", "id": contract_id}); open_diplomacy())


func _demand_tooltip(error: String) -> String:
	if error != "":
		return error
	return "Адресат может отказаться. При отказе наше доверие к нему снизится на %d." % int(game.data.diplomacy["demand_refusal_penalty"])


func _show_demands(pid: int) -> void:
	for task in DemandRules.obligations_for(game, pid):
		_label(_research_box, "%s · выполнить до начала хода %d" % [
			_demand_subject("clear_camp", int(task["offer"])), int(task["until"])], 14, Color.WHITE, true)
	for demand in DemandRules.pending_for(game, pid):
		var incoming := int(demand["recipient"]) == pid
		var peer := game.state.player(int(demand["issuer"] if incoming else demand["recipient"]))
		var title := _demand_subject(demand["kind"], int(demand["offer"]))
		if demand["kind"] == "discount":
			title = "Скидка %d%% на предложение №%d" % [int(demand["percent"]), int(demand["offer"])]
		_label(_research_box, "%s · %s · %s" % [title, peer.name,
			"требование к нам" if incoming else "наше требование"], 15, Color.WHITE, true)
		if demand["kind"] == "discount":
			var offer: Dictionary = game.state.diplomacy.get("offers", {}).get(str(demand["offer"]), {})
			if not offer.is_empty():
				_label(_research_box, _supply_summary(offer), 12, Color.WHITE, true)
		_label(_research_box, "Ходов адресата для ответа: %d · отказ снижает доверие инициатора" % int(demand["turns_left"]),
			12, Color.WHITE, true)
		if incoming:
			var actions := HBoxContainer.new()
			_research_box.add_child(actions)
			var pair: String = demand["pair"]
			var id: int = demand["id"]
			_button(actions, "Согласиться", func(): act.call({"type": "respond_demand", "pair": pair, "id": id, "accept": true}))
			_button(actions, "Отказать", func(): act.call({"type": "respond_demand", "pair": pair, "id": id, "accept": false}))


func _demand_subject(kind: String, subject: int) -> String:
	match kind:
		"vote_support": return "Поддержать резолюцию №%d" % subject
		"joint_war": return "Вступить в войну против державы «%s»" % game.state.player(subject).name
		"clear_camp":
			var grid := game.state.map.grid
			return "Ликвидировать лагерь варваров (%d, %d)" % [grid.col_of(subject), grid.row_of(subject)]
		"reinforcement":
			var unit := game.state.unit(subject)
			return "Подкрепление · %s №%d" % [Abilities.unit_name(game, ConcessionRules.legal_owner(game, unit), unit.type), subject] \
				if unit != null else "Подкрепление · отряд №%d" % subject
		"concede_city":
			var city := game.state.city(subject)
			return "Мирно уступить город «%s»" % city.name if city != null else "Мирно уступить город"
		_: return "Право прохода"


func open_congress() -> void:
	_research_kind = "congress"
	_research_panel.visible = true
	_clear(_research_box)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Международная организация", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Назад", open_diplomacy)
	_button(head, "✕", close_research)
	var pid := game.state.current_player
	var data := game.state.congress_data
	if not data["founded"]:
		var error := CongressRules.founding_error(game, pid)
		_button(_research_box, "Предложить учреждение ООН",
			func(): act.call({"type": "congress_found"}), error != "", error)
	else:
		_label(_research_box, "Следующая очередная сессия · ход %d" % int(data["next_session"]), 14)
		for entry in data["docket"].values():
			if int(entry["issuer"]) == pid:
				_label(_research_box, "Дело №%d внесено в повестку" % int(entry["id"]), 13)
		_show_congress_cases(pid)
	for item in CongressRules.polls(game):
		var id: int = item["id"]
		var founding: bool = item["mode"] == "founding"
		var heading := "Учреждение ООН"
		if not founding:
			var intent := "Предписание соблюдать поставки"
			if item["mode"] == "religious":
				intent = "Предписание прекратить активную проповедь на 20 кругов"
			if item.get("recommendation", false):
				intent = "Рекомендация соблюдать поставки"
			elif item["mode"] == "sanctions":
				intent = "Немедленное торговое эмбарго"
			heading = "№%d · %s\n%s → %s" % [id, intent, game.state.player(int(item["issuer"])).name,
				game.state.player(int(item["accused"])).name]
		_label(_research_box, heading, 16, Color.WHITE, true)
		if not founding:
			_label(_research_box, _evidence_text(item["proof"]), 12, Color.WHITE, true)
			var risk := CongressRules.trade_exposure(game, pid, int(item["accused"]))
			if not item.get("recommendation", false):
				_label(_research_box, ("Голос за включает вас в эмбарго. Под риском %d договоров и %d ваших путей." if
					item["mode"] == "sanctions" else "При нарушении эмбарго затронет %d ваших договоров и %d путей.") % [risk.x, risk.y],
					12, Color.WHITE, true)
		var ballot: Dictionary = item["ballots"].get(str(pid), {})
		if not ballot.is_empty() and ballot["vote"] == "":
			var buttons := HBoxContainer.new()
			_research_box.add_child(buttons)
			var labels := {"yes": "За", "no": "Против", "abstain": "Воздержаться"}
			for option in labels:
				_button(buttons, labels[option],
					func(): act.call({"type": "congress_vote", "id": id, "vote": option}))
			_label(_research_box, "Ваших ходов для ответа: %d%s" % [int(ballot["left"]),
				" · обещали поддержку" if int(ballot["promise"]) >= 0 else ""], 12)
		elif not ballot.is_empty():
			_label(_research_box, "Ваш голос: %s" % {"yes": "за", "no": "против", "abstain": "воздержался"}.get(ballot["vote"], ""), 12)
		if int(item["issuer"]) == pid and not founding:
			for peer in game.state.player(pid).met.keys():
				var error := DemandRules.issue_error(game, pid, int(peer), "vote_support", id)
				if error == "":
					_button(_research_box, "Потребовать поддержки · %s" % game.state.player(int(peer)).name,
						func(): act.call({"type": "issue_demand", "kind": "vote_support", "target": peer, "offer": id}))
	var recent: Dictionary = data["recent"]
	if not recent.is_empty():
		_label(_research_box, "Последнее голосование №%d · %s · за %d из %d" % [
			recent["id"], "принято" if recent["passed"] else "отклонено", recent["yes"], recent["eligible"]], 13, Color.WHITE, true)
	for order in data["orders"].values():
		if int(order["ends"]) > game.state.turn:
			var subject := "прекратить активную проповедь" if order.get("kind", "supply") == "religious" else "соблюдать поставки"
			_label(_research_box, "Решение №%d · %s: %s · до начала хода %d" % [
				order["id"], game.state.player(int(order["accused"])).name, subject, order["ends"]], 13, Color.WHITE, true)


func _evidence_text(record: Dictionary) -> String:
	if str(record.get("kind", "")) == "religious":
		var reason := "отказ прекратить проповедь" if record["reason"] == "protest_refused" else "нарушение обещания прекратить проповедь"
		return "%s · круг %d" % [reason, int(record["turn"])]
	var resource: String = game.data.resources.get(record["resource"], {}).get("name", str(record["resource"]))
	var reason := "продавец отменил договор" if record["reason"] == "seller_cancelled" else "недопоставка · %d ед." % int(record["missing"])
	return "%s · %s · ход %d" % [resource, reason, int(record["turn"])]


func _show_congress_cases(pid: int) -> void:
	for proof in CongressRules.evidence_for(game, pid):
		var id: int = proof["id"]
		_label(_research_box, "%s · %s" % [game.state.player(int(proof["offender"])).name,
			_evidence_text(proof)], 14, Color.WHITE, true)
		var names := {"religious": "Потребовать прекращения проповеди"} if str(proof.get("kind", "")) == "religious" else {"ordinary": "В повестку", "emergency": "Внеочередное дело", "sanctions": "Эмбарго"}
		var row := HBoxContainer.new()
		_research_box.add_child(row)
		for mode in names:
			var error := CongressRules.proposal_error(game, pid, id, mode)
			_button(row, names[mode], func(): act.call({"type": "congress_propose", "evidence": id, "mode": mode}),
				error != "", error)
		if str(proof.get("kind", "")) != "religious":
			var error := CongressRules.proposal_error(game, pid, id, "ordinary")
			_button(_research_box, "В повестку как рекомендацию",
				func(): act.call({"type": "congress_propose", "mode": "ordinary", "evidence": id, "recommendation": true}),
				error != "", error)


func open_strong_demands(peer: int) -> void:
	var pid := game.state.current_player
	_research_kind = "strong_demands:%d" % peer
	_research_panel.visible = true
	_clear(_research_box)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Требования · %s" % game.state.player(peer).name, 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Назад", open_diplomacy)
	var targets := {"joint_war": [], "clear_camp": game.state.camps.keys(), "reinforcement": [], "concede_city": []}
	for other in game.state.players:
		if other.id != pid and other.id != peer and not other.is_barbarian and game.state.at_war(pid, other.id):
			targets["joint_war"].append(other.id)
	for unit in game.state.units_of(peer):
		targets["reinforcement"].append(unit.id)
	for city in game.state.cities_of(peer):
		targets["concede_city"].append(city.id)
	var any := false
	for kind in targets:
		targets[kind].sort()
		for subject in targets[kind]:
			if DemandRules.issue_error(game, pid, peer, kind, int(subject)) != "":
				continue
			any = true
			_button(_research_box, _demand_subject(kind, int(subject)), func():
				act.call({"type": "issue_demand", "kind": kind, "target": peer, "offer": subject})
				open_diplomacy(), false, _demand_tooltip(""))
	if not any:
		_label(_research_box, "Сейчас нет доступных целей или ещё действует пауза после предыдущего требования.",
			13, Color.WHITE, true)


static func _treaty_label(kind: String) -> String:
	match kind:
		"friendship": return "Дружба"
		"alliance": return "Союз"
		_: return "Запросить проход"


func _show_treaty_status(pid: int, peer: int) -> void:
	var alliance := TreatyRules.until(game, "alliance", pid, peer)
	var friendship := TreatyRules.until(game, "friendship", pid, peer)
	var passage := TreatyRules.until(game, "passage", pid, peer)
	var reverse := TreatyRules.until(game, "passage", peer, pid)
	if alliance > game.state.turn:
		var level := TreatyRules.alliance_level(game, pid, peer)
		var specialization := TreatyRules.alliance_specialization(game, pid, peer)
		var name := str(game.data.diplomacy["alliance_specializations"].get(specialization, {}).get("name", "Научный"))
		_label(_research_box, "%s союз · уровень %d/3 · взаимный проход до начала хода %d" % [name, level, alliance], 13)
		_label(_research_box, str(game.data.diplomacy["alliance_specializations"].get(specialization, {}).get("description", "")), 12)
		var next_level := TreatyRules.alliance_next_level_turn(game, pid, peer)
		if next_level > 0:
			_label(_research_box, "До следующего уровня %d ходов%s" % [next_level - game.state.turn,
				" · требуется продлить союз" if next_level >= alliance else ""], 12)
	if friendship > game.state.turn:
		_label(_research_box, "Дружба до начала хода %d" % friendship, 13)
	if alliance <= game.state.turn and passage > game.state.turn:
		_label(_research_box, "Наш проход через их границы до начала хода %d" % passage, 13)
	if alliance <= game.state.turn and reverse > game.state.turn:
		_label(_research_box, "Их проход через наши границы до начала хода %d" % reverse, 13)
	var trust := TreatyRules.trust(game, pid, peer)
	var reverse_trust := TreatyRules.trust(game, peer, pid)
	if trust != 0 or reverse_trust != 0:
		_label(_research_box, "Доверие · наше %+d · их %+d" % [trust, reverse_trust], 13)


func _show_treaty_offers(pid: int) -> void:
	for offer in TreatyRules.offers_for(game, pid):
		var incoming := int(offer["to"]) == pid
		var peer := game.state.player(int(offer["from"] if incoming else offer["to"]))
		var kind: String = offer["kind"]
		var title := "Право прохода" if kind == "passage" else _treaty_label(kind)
		if kind == "alliance":
			title = "%s союз" % str(game.data.diplomacy["alliance_specializations"].get(
				str(offer.get("specialization", "science")), {}).get("name", "Научный"))
		_label(_research_box, "%s · %s · %s" % [title, peer.name,
			"входящее" if incoming else "ждём ответа"], 15)
		if kind == "alliance":
			_label(_research_box, str(game.data.diplomacy["alliance_specializations"].get(
				str(offer.get("specialization", "science")), {}).get("description", "")), 12)
		if kind == "passage":
			_label(_research_box, "Они просят проход через наши границы" if incoming else
				"Мы просим проход через их границы", 12)
		if incoming:
			var buttons := HBoxContainer.new()
			_research_box.add_child(buttons)
			var key: String = offer["key"]
			_button(buttons, "Принять", func(): act.call({"type": "respond_treaty", "offer": key, "accept": true}))
			_button(buttons, "Отклонить", func(): act.call({"type": "respond_treaty", "offer": key, "accept": false}))


func _supply_summary(offer: Dictionary) -> String:
	var resource_name: String = game.data.resources.get(offer["resource"], {}).get("name", str(offer["resource"]))
	var upfront := int(offer["upfront"])
	var periodic := int(offer["per_turn"])
	var rounds := int(offer["rounds"])
	var total := upfront + periodic * rounds
	var gold := _fmt(total * DiplomacyRules.price_cents(offer) / 100.0)
	var discount := int(offer.get("discount_percent", 0))
	var suffix := " · скидка %d%%" % discount if discount > 0 else ""
	if LuxuryTrade.is_luxury(game, offer["resource"]):
		return "%s · доступ к одной копии на %d ходов · %s золота один раз%s" % [
			resource_name, rounds, gold, suffix]
	return "%s: %d сейчас + %d за ход × %d ходов = %d ед. · %s золота один раз%s" % [
		resource_name, upfront, periodic, rounds, total, gold, suffix]


func _supply_number(parent: Container, caption: String, start: int, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, caption)
	label.custom_minimum_size.x = 160
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.rounded = true
	input.value = start
	input.custom_minimum_size.x = 120
	row.add_child(input)
	return input


func open_supply_offer(partner: int, buying: bool) -> void:
	var pid := game.state.current_player
	if partner < 0 or partner >= game.state.players.size() or partner == pid or \
			game.state.at_war(pid, partner) or not game.state.player(pid).met.has(partner):
		open_diplomacy()
		return
	_research_kind = "supply:%d:%s" % [partner, "buy" if buying else "sell"]
	_research_panel.visible = true
	_clear(_research_box)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Купить ресурс" if buying else "Продать ресурс", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Назад", open_diplomacy)
	_label(_research_box, "Партнёр: %s" % game.state.player(partner).name)
	var options := OptionButton.new()
	_research_box.add_child(options)
	var ids: Array[String] = []
	for rid in game.data.resource_ids:
		var resource_class: String = game.data.resources[rid]["class"]
		if resource_class not in ["strategic", "luxury"]:
			continue
		if not Yields.resource_visible(game.data, rid, game.state.player(pid)):
			continue
		if resource_class == "luxury" and not buying and LuxuryTrade.available_sources(game, pid, rid).is_empty():
			continue
		ids.append(rid)
		var name: String = game.data.resources[rid]["name"]
		options.add_item(name + (" · редкий" if resource_class == "luxury" else ""))
	if ids.is_empty():
		_label(_research_box, "Пока нет доступных для сделки ресурсов")
		return
	var upfront := _supply_number(_research_box, "Сразу, ед.", 0, 0, 50)
	var periodic := _supply_number(_research_box, "За ход, ед.", 2, 0, 50)
	var rounds := _supply_number(_research_box, "Число ходов", 5, 0, 100)
	var price := _supply_number(_research_box, "Золото за единицу", 2, 0, 1000)
	var preview := _label(_research_box, "", 13, Color(0.75, 0.78, 0.85), true)
	var update := func():
		var luxury := LuxuryTrade.is_luxury(game, ids[options.selected])
		upfront.get_parent().visible = not luxury
		periodic.get_parent().visible = not luxury
		var caption: Label = price.get_parent().get_child(0)
		caption.text = "Золото за ход" if luxury else "Золото за единицу"
		if luxury:
			preview.text = "Доступ к одной копии · %d золота за весь срок" % (int(rounds.value) * int(price.value))
			return
		var amount := int(upfront.value) + int(periodic.value) * int(rounds.value)
		preview.text = "Всего %d ед. · разовая оплата %d золота" % [amount, amount * int(price.value)]
	for field in [upfront, periodic, rounds, price]:
		field.value_changed.connect(func(_value): update.call())
	options.item_selected.connect(func(_index): update.call())
	update.call()
	_label(_research_box, "Оплата будущих поставок хранится до исполнения. Отправка предложения ничего не списывает.",
		12, Color(0.75, 0.78, 0.85), true)
	_button(_research_box, "Отправить предложение", func():
		var luxury := LuxuryTrade.is_luxury(game, ids[options.selected])
		var action := {"type": "propose_supply", "resource": ids[options.selected],
			"upfront": 0 if luxury else int(upfront.value), "per_turn": 1 if luxury else int(periodic.value),
			"rounds": int(rounds.value), "unit_price": int(price.value)}
		if buying:
			action["seller"] = partner
		else:
			action["buyer"] = partner
		var events: Array = act.call(action)
		if events.any(func(e): return e["type"] == "supply_proposed"):
			open_diplomacy())


func _choose_research(id: String) -> void:
	act.call({"type": "set_research", "kind": _research_kind, "id": id})
	close_research()


func open_finance() -> void:
	_research_kind = "finance"
	_research_panel.visible = true
	_clear(_research_box)
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Мировая биржа", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	var pid := game.state.current_player
	var own := FinanceRules.progress(game, pid)
	if not own["unlocked"]:
		_label(_research_box, "Гонка откроется, когда любая держава изучит Банковское дело.", 15, Color.WHITE, true)
		return
	_label(_research_box, "Ваш чистый доход: %.1f золота/ход · порог: %.1f" % [own["income"], own["threshold"]], 16)
	_label(_research_box, "Нужно в %.1f раза больше дохода лучшего соперника (сейчас %.1f)." % [
		own["multiplier"], own["best_rival"]], 14, Color.WHITE, true)
	_label(_research_box, "Гегемония: %d/%d собственных ходов подряд" % [own["streak"], own["required"]], 15)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = own["fraction"]
	bar.show_percentage = true
	_research_box.add_child(bar)
	if not FinanceRules.owns_original_capital(game, pid):
		_label(_research_box, "Для победы верните свою исходную столицу.", 13)
	_label(_research_box, "Доход по дипломатическим сделкам и разовые выплаты не входят в расчёт.", 12, Color(0.75, 0.78, 0.85), true)
	_label(_research_box, "Рейтинг держав по чистому доходу", 17)
	var rows: Array[Dictionary] = []
	for player in game.state.players:
		if player.alive and not player.is_barbarian:
			rows.append({"id": player.id, "income": FinanceRules.economic_income(game, player.id)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["income"] > b["income"])
	for row in rows:
		var other := game.state.player(int(row["id"]))
		if other.id == pid:
			_label(_research_box, "%s · %.1f золота/ход · серия %d" % [other.name, row["income"],
				int(game.state.finance_data["streaks"].get(str(other.id), 0))], 14)
		elif game.state.player(pid).met.has(other.id) \
				and DiplomaticVisibility.level(game, pid, other.id) >= int(game.data.visibility_setup["finance_exact_level"]):
			_label(_research_box, "%s · %.1f золота/ход · точные сведения · серия %d" % [other.name,
				row["income"], int(game.state.finance_data["streaks"].get(str(other.id), 0))], 14)
		elif game.state.player(pid).met.has(other.id):
			var delta := absf(float(row["income"])) * float(game.data.finance_setup["public_estimate_variance"])
			_label(_research_box, "%s · около %.1f…%.1f золота/ход · серия %d" % [other.name,
				float(row["income"]) - delta, float(row["income"]) + delta,
				int(game.state.finance_data["streaks"].get(str(other.id), 0))], 14)
		else:
			_label(_research_box, "Неизвестная держава · доход не раскрыт", 14)
	_label(_research_box, "Точный доход соперника открывается при дипломатической видимости от 2.",
		12, Color(0.75, 0.78, 0.85), true)
	_button(_research_box, "Победы и счёт", open_victory)


func open_victory() -> void:
	_research_kind = "victory"
	_research_panel.visible = true
	_clear(_research_box)
	var result := game.state.result
	var head := HBoxContainer.new()
	_research_box.add_child(head)
	var title := _label(head, "Итоги партии" if not result.is_empty() else "Победы и счёт", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", close_research)
	var pid := game.state.current_player
	if not result.is_empty():
		var winners: Array = result["winners"]
		var names: PackedStringArray = []
		for id in winners:
			names.append(game.state.player(int(id)).name)
		var human_won := false
		var has_human := false
		for player in game.state.players:
			if not player.is_ai and not player.is_barbarian:
				has_human = true
				human_won = human_won or winners.has(player.id)
		var outcome := "Совместная победа" if winners.size() > 1 else "Победа"
		if winners.is_empty():
			outcome = "Без победителя"
		elif has_human and not human_won:
			outcome = "Поражение"
		_label(_research_box, outcome, 22)
		if not names.is_empty():
			_label(_research_box, "Победители · " + ", ".join(names), 16, Color.WHITE, true)
		var reason := "Итоговый счёт"
		match str(result["kind"]):
			"domination":
				reason = "Контроль исходных столиц"
			"religion":
				var religion_id := str(result.get("religion", ""))
				var religion_name := str(game.state.religions.get(religion_id, {}).get("name", religion_id))
				reason = "Распространение религии %s" % religion_name
			"science":
				reason = "Экспедиция достигла экзопланеты"
			"culture":
				reason = "Приезжих туристов больше, чем внутренних у каждой другой державы"
			"finance":
				reason = "Устойчивая финансовая гегемония"
		_label(_research_box, "%s · ход %d" % [reason, int(result["turn"])])
	else:
		var own := VictoryRules.capital_progress(game, pid)
		_label(_research_box, "Исходные столицы под вашим контролем · %d из %d" % [own.x, own.y])
		var own_religion := game.state.player(pid).religion_id
		if own_religion == "":
			_label(_research_box, "Религиозная победа: сначала основайте религию")
		else:
			var progress := VictoryRules.religion_progress(game, own_religion)
			var complete := 0
			for row in progress:
				if int(row["total"]) > 0 and int(row["converted"]) >= int(row["required"]):
					complete += 1
			_label(_research_box, "Религиозная победа · %s · %d/%d держав имеют большинство" % [
				game.state.religions[own_religion]["name"], complete, progress.size()], 15, Color.WHITE, true)
			for row in progress:
				var other := game.state.player(int(row["player"]))
				if other.id == pid or game.state.player(pid).met.has(other.id):
					_label(_research_box, "%s · %d/%d городов · нужно %d" % [other.name,
						int(row["converted"]), int(row["total"]), int(row["required"])], 12)
		_label(_research_box, "Победа по очкам после хода %d" % VictoryRules.turn_limit(game))
		var science := ScienceRules.status(game, pid)
		if bool(science["launched"]):
			_label(_research_box, "Научная победа · экспедиция: %d/%d световых лет · скорость %d за круг" % [
				int(science["distance"]), int(game.data.science_setup["distance_required"]), int(science["speed"])],
				15, Color.WHITE, true)
		else:
			_label(_research_box, "Научная победа · завершено проектов: %d/4" % science["completed"].size(), 15)
		var visitors := CultureRules.foreign_tourists(game, pid)
		var target := 0
		for other in game.state.players:
			if other.id != pid and other.alive and not other.is_barbarian:
				target = maxi(target, CultureRules.domestic_tourists(game, other.id))
		_label(_research_box, "Культурная победа · приезжие туристы %d · нужно больше %d · туризм/круг %.1f" % [
			visitors, target, CultureRules.tourism_per_turn(game, pid)], 15, Color.WHITE, true)
		var finance := FinanceRules.progress(game, pid)
		if finance["unlocked"]:
			_label(_research_box, "Финансовая победа · доход %.1f/%.1f · серия %d/%d ходов" % [
				finance["income"], finance["threshold"], finance["streak"], finance["required"]],
				15, Color.WHITE, true)
		else:
			_label(_research_box, "Финансовая победа · откроется после изучения Банковского дела", 15)
		_button(_research_box, "Открыть Мировую биржу", open_finance)
	_label(_research_box, "Счёт держав", 17)
	for row in VictoryRules.standings(game):
		var player := game.state.player(int(row["player"]))
		if result.is_empty() and player.id != pid and not game.state.player(pid).met.has(player.id):
			continue
		var status := " · выбыла" if not player.alive else ""
		_label(_research_box, "%s · %d очков%s" % [player.name, row["score"], status], 15)
		var c: Dictionary = row["counts"]
		var capitals := VictoryRules.capital_progress(game, player.id)
		_label(_research_box, "Города %d · население %d · районы %d · здания %d\nТехнологии %d · институты %d · исходные столицы %d/%d" % [
			c["cities"], c["population"], c["districts"], c["buildings"], c["technologies"],
			c["civics"], capitals.x, capitals.y], 12, Color(0.75, 0.78, 0.85), true)
	if not result.is_empty():
		_button(_research_box, "Осмотреть карту", close_research)


# --- Юнит -------------------------------------------------------------------------------------

func show_unit(u: Unit) -> void:
	_clear(_unit_box)
	if u == null or game.state.unit(u.id) == null:
		_unit_panel.visible = false
		return
	_unit_panel.visible = true
	var def := game.data.unit_def(u.type)
	var lender := ConcessionRules.legal_owner(game, u)
	var title := Abilities.unit_name(game, lender, u.type)
	if lender != u.owner:
		title += " · подкрепление"
	if not u.commander.is_empty():
		title += " — " + Army.detachment_name(game, u.owner)
	_label(_unit_box, title, 20)
	if not u.trade_route.is_empty():
		var destination := game.state.city(int(u.trade_route["destination"]))
		if u.owner == game.state.current_player and destination != null:
			_label(_unit_box, "Путь в %s · осталось %d х." % [destination.name,
				int(u.trade_route["turns"]) - int(u.trade_route["elapsed"])], 0, Color.WHITE, true)
			_label(_unit_box, _trade_yields_text(u.trade_route), 0, Color.WHITE, true)
		return
	var lines := ["Очки движения: %s / %s" % [_fmt(u.moves_left), _fmt(Movement.max_moves(game, u))]]
	if def.has("combat"):
		var s := "Сила: %d" % def["combat"]
		if def.has("ranged"):
			s += " · дальний бой: %d (дальность %d)" % [def["ranged"], def.get("range", 1)]
		lines.append(s)
	if def.has("charges"):
		lines.append("Заряды: %d" % u.charges)
	lines.append("Здоровье: %d" % u.hp)
	if Combat.can_attack(game, u):
		lines.append("Опыт: %d / %d (уровень %d)" % [u.xp, Combat.xp_for_level(u.level + 1), u.level])
	if not u.promotions.is_empty():
		var names := []
		for pid in u.promotions:
			names.append(game.data.promotions[pid]["name"])
		lines.append("Повышения: " + ", ".join(names))
	for a in Abilities.of(game, lender, u.type):
		if game.data.abilities.has(a):
			lines.append("◆ %s" % game.data.abilities[a]["name"])
	if not u.commander.is_empty():
		lines.append("Командующий: %s, уровень %d (+%d к силе, +1 ОД)" % [Army.commander_name(game, u.owner),
			int(u.commander.get("level", 0)), Army.commander_combat(game, u)])
	var e := Army.equipment_of(game, u)
	if not e.is_empty():
		var parts := []
		for slot in e:
			parts.append(Army.option_def(game, e[slot]).get("name", e[slot]))
		lines.append("Снаряжение: " + ", ".join(parts))
		var cl := Army.climate_of(game, u.tile)
		if cl != "TEMPERATE":
			var pen := 0
			for m in Army.equipment_mods(game, u, "combat", {"role": "defense"}):
				if m[0] == Army.option_def(game, e.get("clothing", "")).get("name", ""):
					pen += int(m[1])
			lines.append("Климат: %s%s" % ["холод" if cl == "COLD" else "жара", (" — штраф %d" % pen) if pen < 0 else " — одежда подходит"])
	match u.orders.get("type", ""):
		"move":
			lines.append("Идёт к цели…")
		"sleep":
			lines.append("Спит")
		"fortify":
			lines.append("Укреплён (+%d)" % mini(u.fortify_turns * 3, 6))
	_label(_unit_box, "\n".join(lines))
	if u.owner != game.state.current_player:
		return
	var abilities: Array = def.get("abilities", [])
	if abilities.has("TRADE_ROUTE"):
		_button(_unit_box, "Выбрать торговый путь", func(): open_trade(u.id))
	if TradeRules.raid_target(game, u) != null:
		_button(_unit_box, "Разграбить торговый путь", func(): act.call({"type": "raid_trade", "unit": u.id}))
	if abilities.has("FOUND_CITY"):
		var err := CityRules.found_city_error(game, u.owner, u.tile)
		_button(_unit_box, "Основать город (B)", func(): act.call({"type": "found_city", "unit": u.id}),
			err != "" or u.moves_left <= 0.0, err)
	if abilities.has("FOUND_RELIGION"):
		_button(_unit_box, "Основать религию…", open_religion)
	if abilities.has("PROCLAIM_BELIEF"):
		_button(_unit_box, "Провозгласить верование…", open_religion)
	if abilities.has("SPREAD_RELIGION"):
		var spread_error := ReligionRules.spread_error(game, u)
		var target_city := game.state.city_at(u.tile)
		var warning := ""
		if target_city != null and target_city.owner != u.owner:
			var pair := "%d,%d" % [target_city.owner, u.owner]
			if game.state.religious_conflicts["promises"].has(pair):
				warning = " (нарушит обещание)"
			var order := CongressRules.religious_order(game, target_city.owner, u.owner)
			if not order.is_empty():
				warning = " (нарушит решение ООН)" if not order["grace"] else " (ООН: льготный срок)"
		_button(_unit_box, "Распространить религию%s" % warning, func(): act.call({"type": "spread_religion", "unit": u.id}),
			spread_error != "", spread_error)
	if abilities.has("START_INQUISITION") and ReligionRules.inquisition_error(game, u) == "":
		_button(_unit_box, "Учредить инквизицию", func(): act.call({"type": "start_inquisition", "unit": u.id}))
	if abilities.has("PURGE_RELIGION"):
		var purge_error := ReligionRules.purge_error(game, u)
		_button(_unit_box, "Очистить город от чужой веры", func(): act.call({"type": "purge_religion", "unit": u.id}),
			purge_error != "", purge_error)
	if abilities.has("THEOLOGICAL_ATTACK"):
		for tile in game.state.map.grid.neighbors(u.tile):
			for target in game.state.units_at(tile):
				if ReligionRules.theological_error(game, u, target) == "":
					var target_id := target.id
					_button(_unit_box, "Теологический бой: %s" % game.data.unit_def(target.type)["name"],
						func(): act.call({"type": "theological_attack", "unit": u.id, "target_unit": target_id}))
	if abilities.has("BUILD_IMPROVEMENT"):
		for iid in ImprovementRules.valid_improvements(game, u):
			var imp: Dictionary = game.data.improvements[iid]
			var y := []
			for k in imp.get("yields", {}):
				y.append("+%s %s" % [_fmt(float(imp["yields"][k])), str(YIELD_NAMES[k]).to_lower()])
			_button(_unit_box, "Построить: %s (%s)" % [imp["name"], ", ".join(y)],
				func(): act.call({"type": "build_improvement", "unit": u.id, "improvement": iid}), u.moves_left <= 0.0)
		var hv := ImprovementRules.harvest_preview(game, u)
		if not hv.is_empty():
			var parts := []
			for k in hv["yields"]:
				parts.append("+%s %s" % [_fmt(float(hv["yields"][k])), str(YIELD_NAMES[k]).to_lower()])
			var what := "Собрать ресурс" if hv["what"] == "resource" else "Вырубить/осушить"
			_button(_unit_box, "%s (%s в город)" % [what, ", ".join(parts)],
				func(): act.call({"type": "harvest", "unit": u.id}), u.moves_left <= 0.0)
	for pid in Combat.available_promotions(game, u):
		var pr: Dictionary = game.data.promotions[pid]
		_button(_unit_box, "★ Повышение: %s — %s" % [pr["name"], pr["text"]],
			func(): act.call({"type": "promote", "unit": u.id, "promotion": pid}))
	var target := UnitRules.upgrade_target(game, u)
	if target != "":
		var uerr := UnitRules.upgrade_error(game, u)
		_button(_unit_box, "Модернизировать в «%s» (%d золота)" % [Abilities.unit_name(game, u.owner, target), UnitRules.upgrade_cost(game, u, target)],
			func(): act.call({"type": "upgrade_unit", "unit": u.id}), uerr != "", uerr)
	if Abilities.has(game, u, "ROAD_INSTEAD_OF_MOVE") or Abilities.has(game, u, "BUILD_ROAD"):
		var rerr := UnitRules.build_road_error(game, u)
		_button(_unit_box, "Проложить дорогу (R)", func(): act.call({"type": "build_road", "unit": u.id}), rerr != "", rerr)
	if Abilities.has(game, u, "BUILD_FORT") and u.charges > 0:
		var ferr := UnitRules.build_fort_error(game, u)
		_button(_unit_box, "Построить форт", func(): act.call({"type": "build_fort", "unit": u.id}), ferr != "", ferr)
	if UnitRules.pillage_error(game, u) == "":
		_button(_unit_box, "Разграбить улучшение", func(): act.call({"type": "pillage", "unit": u.id}))
	if UnitRules.repair_error(game, u) == "":
		_button(_unit_box, "Починить улучшение", func(): act.call({"type": "repair", "unit": u.id}))
	if not Army.slots_for(game, u.type).is_empty():
		_button(_unit_box, "Снаряжение… (E)", func(): open_equipment(u.id))
	if not u.commander.is_empty():
		_button(_unit_box, "Отделить командующего", func(): act.call({"type": "detach_commander", "unit": u.id}))
	if Army.is_commander(game, u):
		for other in game.state.units_at(u.tile):
			if Army.attach_error(game, u, other) == "":
				var oid := other.id
				_button(_unit_box, "Объединить с «%s» в %s" % [Abilities.unit_name(game, other.owner, other.type), Army.detachment_name(game, u.owner)],
					func(): act.call({"type": "attach_commander", "unit": u.id, "target": oid}))
	var row := HBoxContainer.new()
	_unit_box.add_child(row)
	if Movement.layer(game, u.type) == "COMBAT":
		_button(row, "Укрепиться (F)", func(): act.call({"type": "fortify", "unit": u.id}))
	_button(row, "Пропустить (Пробел)", func(): act.call({"type": "skip_unit", "unit": u.id}))
	if Movement.layer(game, u.type) != "COMBAT":
		_button(row, "Спать (F)", func(): act.call({"type": "sleep_unit", "unit": u.id}))
	if not u.orders.is_empty():
		_button(row, "Отменить приказ", func(): act.call({"type": "cancel_orders", "unit": u.id}))


# --- Город --------------------------------------------------------------------------------------

func open_city(cid: int) -> void:
	city_id = cid
	_city_panel.visible = cid >= 0
	refresh_city()


func _close_city() -> void:
	open_city(-1)
	city_closed.emit()


func refresh_city() -> void:
	var city := game.state.city(city_id)
	if city == null:
		_city_panel.visible = false
		city_id = -1
		return
	_clear(_city_box)
	var head := HBoxContainer.new()
	_city_box.add_child(head)
	var title := _label(head, "%s%s" % ["★ " if city.is_capital else "", city.name], 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "✕", _close_city)
	var lux := CityRules.luxury_amenities(game, city.owner)
	var y := CityRules.city_yields(game, city, lux)
	var row := HFlowContainer.new()
	_city_box.add_child(row)
	for k in Yields.TYPES:
		_yield_chip(row, k, _fmt(snappedf(float(y.get(k, 0)), 0.1)))
	var thr := CityRules.growth_threshold(game, city.population)
	var ttg := CityRules.turns_to_grow(game, city)
	var food_net := float(y.get("food", 0)) - CityRules.food_consumption(game, city)
	var am := CityRules.amenity_info(game, city, lux)
	var st: Dictionary = am["state"]
	_label(_city_box, "Население: %d · рост: %s/%d (%s)\nПища: %+.1f за ход (после еды жителей)\nЖильё: %s · довольство: %d/%d — %s" % [
		city.population, _fmt(snappedf(city.food_stored, 0.1)), thr,
		("через %d х." % ttg) if ttg > 0 else ("голод" if food_net < 0 else "застой"),
		food_net, _fmt(CityRules.housing(game, city)), int(am["have"]), int(am["need"]), str(st.get("name", ""))])
	_label(_city_box, "Прочность: %d/%d%s" % [city.hp, int(game.data.const_value("city_hp", 200)),
		(" · стены %d" % city.wall_hp) if city.wall_hp > 0 else ""])
	if city.owner == game.state.current_player:
		var power := EnergyRules.report(game, city)
		_label(_city_box, "Электроэнергия: %d/%d · возобновляемая %d · резерв %d%s" % [
			int(power["supplied"]), int(power["demand"]), int(power["renewable"]), int(power["spare"]),
			(" · активных лазеров %d" % int(power["lasers_powered"])) if int(power["laser_sites"]) > 0 else ""],
			13, Color(0.8, 0.9, 1.0), true)
	var city_religion := ReligionRules.majority(game, city)
	_label(_city_box, "Религия: %s%s" % [game.state.religions.get(city_religion, {}).get("name", "нет большинства"),
		(" · %.1f последователей" % ReligionRules.followers(game, city, city_religion)) if city_religion != "" else ""])
	if city.owner == game.state.current_player and Combat.city_can_strike(game, city):
		for t in game.state.map.grid.tiles_in_radius(city.tile, int(game.data.const_value("city_ranged_range", 2))):
			if Combat.city_attack_error(game, city, t) == "":
				var tu: Unit = Combat.target_at(game, city.owner, t)["unit"]
				var tt := t
				_button(_city_box, "🏹 Обстрелять: %s (%d ♥)" % [Abilities.unit_name(game, tu.owner, tu.type), tu.hp],
					func(): act.call({"type": "city_attack", "city": city.id, "target": tt}))
	if not city.buildings.is_empty():
		var names := []
		for bid in city.buildings:
			names.append(game.data.buildings[bid]["name"])
		_label(_city_box, "Здания: " + ", ".join(names), 0, Color(0.85, 0.85, 0.9), true)
	_city_districts(city)
	if CultureRules.work_slots(game, city) > 0 or city.great_works > 0:
		_label(_city_box, "Шедевры: %d/%d · туризм %.1f за круг" % [city.great_works,
			CultureRules.work_slots(game, city), CultureRules.active_works(game, city) * CultureRules.config(game, "work_tourism")])
	_city_life(city)
	if city.owner != game.state.current_player:
		return
	_label(_city_box, "Производство", 18)
	var item := city.current_item()
	if item.is_empty():
		_label(_city_box, "Ничего не строится — выберите ниже", 0, Color(1.0, 0.8, 0.45))
	else:
		var cost := CityRules.item_cost(game, city, item)
		var prog := float(city.progress.get(City.item_key(item), 0.0))
		_label(_city_box, "▶ %s — %s/%s ⚙, %d х." % [CityRules.item_name(game, item, city.owner), _fmt(snappedf(prog, 0.1)),
			_fmt(cost), CityRules.turns_to_build(game, city, item)])
		var pb := ProgressBar.new()
		pb.max_value = cost
		pb.value = prog
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 8)
		_city_box.add_child(pb)
	var treasury := game.state.player(city.owner).treasury
	var groups := {"unit": [], "building": [], "district": [], "in_district": [], "project": [],
		"cultural_project": []}
	for it in CityRules.buildable_items(game, city):
		var g: String = it["kind"]
		if it.has("tile") and g != "district":
			g = "in_district"
		groups[g].append(it)
	var titles := {"unit": "Юниты", "building": "Здания в центре", "district": "Районы", "in_district": "Улучшение районов", "project": "Космические проекты",
		"cultural_project": "Культурные проекты"}
	for g in ["unit", "building", "district", "in_district", "project", "cultural_project"]:
		if groups[g].is_empty():
			continue
		_label(_city_box, titles[g], 14, Color(0.8, 0.85, 1.0))
		for it in groups[g]:
			var line := HBoxContainer.new()
			_city_box.add_child(line)
			var kind: String = it["kind"]
			var id: String = it["id"]
			var tile := int(it.get("tile", -1))
			var label_text := CityRules.item_name(game, it, city.owner)
			if kind == "district" and tile < 0:
				# Новый район: цена известна, клетку выбирают на карте.
				label_text = "%s (%s) — %s ⚙ · выбрать клетку" % [label_text, DistrictRules.ddef(game, id).get("name", id),
					_fmt(DistrictRules.cost(game, city, id))]
				var tp := id
				var bd := _button(line, label_text, func(): place_district.emit(tp))
				bd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bd.alignment = HORIZONTAL_ALIGNMENT_LEFT
				continue
			var t := CityRules.turns_to_build(game, city, it)
			if kind == "district":
				label_text += " (продолжить)"
			elif tile >= 0 and kind == "building":
				label_text += " · " + DistrictRules.display_name(game, city.owner, game.data.buildings[id]["district"],
					int(DistrictRules.entry_at(city, tile).get("tier", 1)))
			var b := _button(line, "%s — %s х." % [label_text, str(t) if t > 0 else "∞"],
				func(): act.call({"type": "set_production", "city": city.id, "kind": kind, "id": id, "tile": tile}))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if kind in ["district", "district_upgrade", "project", "cultural_project"]:
				continue
			var price := CityRules.purchase_cost(game, city, it)
			var buy := _button(line, "%d" % price, func(): act.call({"type": "purchase", "city": city.id, "kind": kind, "id": id, "tile": tile}),
				treasury < price, "Купить за золото")
			buy.icon = _icons.get("gold")
			buy.add_theme_constant_override("icon_max_width", 16)
	_label(_city_box, "Купить клетку: щёлкните по клетке с ценой рядом с городом.", 12, Color(0.75, 0.78, 0.85), true)


## Раздел «Районы»: что построено, что даёт, урбанизация Нерона.
func _city_districts(city: City) -> void:
	if city.districts.is_empty():
		return
	_label(_city_box, "Районы (специализированных %d из %d)" % [DistrictRules.specialized_count(game, city),
		DistrictRules.specialized_limit(city)], 18)
	for d in city.districts:
		var name := DistrictRules.display_name(game, city.owner, d["type"], int(d["tier"]))
		if not d["complete"]:
			var key := City.item_key({"kind": "district", "id": d["type"], "tile": d["tile"]})
			_label(_city_box, "• %s — строится: %s/%s ⚙" % [name, _fmt(snappedf(float(city.progress.get(key, 0.0)), 0.1)),
				_fmt(float(d["cost"]))], 0, Color(0.85, 0.8, 0.6), true)
			continue
		var o := DistrictRules.output(game, city, d)
		var parts := []
		for k in Yields.TYPES:
			var v := float(o["yields"].get(k, 0))
			if v != 0.0:
				parts.append("%s %s" % [_fmt(snappedf(v, 0.1)), str(YIELD_NAMES[k]).to_lower()])
		for pair in [["housing", "жильё"], ["amenities", "довольство"], ["sanitation", "санитария"], ["order", "порядок"]]:
			var v2 := float(o[pair[0]])
			if v2 != 0.0:
				parts.append("%+d %s" % [int(v2), pair[1]])
		var line := "• %s" % name
		if int(d["tier"]) > 1:
			line += " (ур. %d)" % int(d["tier"])
		if not parts.is_empty():
			line += ": " + ", ".join(parts)
		var bnames := []
		for bid in d["buildings"]:
			bnames.append(game.data.buildings[bid]["name"])
		if not bnames.is_empty():
			line += "\n   здания: " + ", ".join(bnames)
		var spec := int(city.specialists.get(str(d["tile"]), 0))
		if spec > 0:
			line += "\n   специалистов: %d" % spec
		var nero := DistrictRules.nero(game, city, d)
		var col := Color(0.9, 0.9, 0.95)
		if not nero.is_empty():
			line += "\n   ✿ Урбанизация Нерона +%d%%%s — рядом: %s" % [int(float(nero["bonus"]) * 100),
				(" и +%d к эффектам" % int(nero["flat"])) if int(nero["flat"]) > 0 else "", ", ".join(nero["neighbors"])]
			col = Color(0.78, 1.0, 0.7)
		_label(_city_box, line, 0, col, true)


## Раздел «Городская жизнь»: санитария, порядок, эпидемия, губернатор и доктрина.
func _city_life(city: City) -> void:
	_label(_city_box, "Городская жизнь", 18)
	var san := CityLife.sanitation(game, city)
	var ord := CityLife.order(game, city)
	var thr := int(game.data.const_value("city_life_threshold_pop", 10))
	var lines := []
	lines.append("Санитария: %s есть / %s нужно" % [_fmt(snappedf(float(san["supply"]), 0.1)), _fmt(snappedf(float(san["need"]), 0.1))])
	lines.append("Порядок: %s есть / %s нужно" % [_fmt(snappedf(float(ord["supply"]), 0.1)), _fmt(snappedf(float(ord["need"]), 0.1))])
	var col := Color(0.85, 0.88, 0.95)
	if not CityLife.active(game, city):
		lines.append("Проблемы начнутся с населения %d." % thr)
	else:
		var ch := CityLife.epidemic_chance(game, city)
		if ch > 0.0:
			lines.append("⚠ Риск эпидемии: %d%% за ход" % roundi(ch * 100.0))
			col = Color(1.0, 0.8, 0.5)
		var pen := CityLife.unrest_penalty(game, city)
		if pen > 0.0:
			lines.append("⚠ Беспорядки: −%d%% к доходам" % roundi(pen * 100.0))
			col = Color(1.0, 0.8, 0.5)
	if city.epidemic_turns > 0:
		lines.append("☣ Эпидемия! Ещё %d х.: рост остановлен, доходы −10%%" % city.epidemic_turns)
		col = Color(1.0, 0.6, 0.5)
	_label(_city_box, "\n".join(lines), 0, col, true)
	# Губернатор.
	var gov_text := "Губернатор без специализации"
	if city.doctrine != "":
		var dd := CityLife.doctrine_def(game, city.doctrine)
		gov_text = "Губернатор: %s" % dd.get("name", city.doctrine)
		if city.doctrine_turns > 0:
			gov_text += " (доктрина вступит в силу через %d х.)" % city.doctrine_turns
	_label(_city_box, gov_text, 0, Color(0.9, 0.9, 0.95), true)
	if city.owner != game.state.current_player:
		return
	var row := HFlowContainer.new()
	_city_box.add_child(row)
	for dd2 in game.data.const_value("doctrines", []):
		var did: String = dd2["id"]
		var err := CityLife.set_doctrine_error(game, city, did)
		_button(row, str(dd2["name"]), func(): act.call({"type": "set_doctrine", "city": city.id, "doctrine": did}),
			err != "", "%s%s" % [dd2.get("text", ""), ("\n(%s)" % err) if err != "" else ""])
	if city.doctrine != "":
		_button(row, "Снять доктрину", func(): act.call({"type": "set_doctrine", "city": city.id, "doctrine": ""}))


## Подсказка в режиме размещения района: соседство и урбанизация на клетке под курсором.
func show_district_preview(city: City, type: String, tile: int) -> void:
	if tile < 0:
		return
	_tile_panel.visible = true
	var lines := [_tile_label.text, ""]
	var name := DistrictRules.display_name(game, city.owner, type, 1)
	var err := DistrictRules.placement_error(game, city, type, tile)
	if err != "":
		lines.append("%s: нельзя — %s" % [name, err])
	else:
		var adj := DistrictRules.adjacency(game, city.owner, type, tile)
		var parts := []
		for k in Yields.TYPES:
			if adj.has(k):
				parts.append("+%d %s" % [int(adj[k]), str(YIELD_NAMES[k]).to_lower()])
		lines.append("%s здесь: %s" % [name, ", ".join(parts) if not parts.is_empty() else "без бонуса соседства"])
		lines.append("ЛКМ — заложить, ПКМ или Esc — отмена")
	_tile_label.text = "\n".join(lines)


# --- Клетка под курсором ------------------------------------------------------------------------

func show_tile(viewer: Player, tile: int, reveal_all: bool) -> void:
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
	if map.improvement[tile] != "":
		lines.append("Улучшение: %s" % game.data.improvements.get(map.improvement[tile], {}).get("name", ""))
	if map.district[tile] != "" and map.district[tile] != DistrictRules.CENTER:
		var a := DistrictRules.at(game, tile)
		if not a.is_empty():
			var dc: City = a[0]
			var de: Dictionary = a[1]
			lines.append("Район: %s%s" % [DistrictRules.display_name(game, dc.owner, de["type"], int(de["tier"])),
				"" if de["complete"] else " (строится)"])
	if map.has_river(tile):
		lines.append("Река")
	var owner_city := game.state.city_owning(tile)
	if owner_city != null:
		lines.append("Территория: %s (%s)" % [owner_city.name, game.state.player(owner_city.owner).name])
	var y := CityRules.tile_yields(game, tile, null if reveal_all else viewer)
	var parts := []
	for k in Yields.TYPES:
		if float(y.get(k, 0)) != 0.0:
			parts.append("%s %s" % [_fmt(float(y[k])), str(YIELD_NAMES[k]).to_lower()])
	lines.append("Доход: " + (", ".join(parts) if not parts.is_empty() else "нет"))
	if map.is_mountain(tile) or map.feature_def(tile).get("impassable", false):
		lines.append("Непроходима")
	elif map.is_land(tile):
		lines.append("Стоимость входа: %s ОД" % _fmt(Movement.terrain_cost(game, tile)))
	_tile_label.text = "\n".join(lines)


func show_combat_preview(pv: Dictionary, err: String) -> void:
	_tile_panel.visible = true
	var lines := [_tile_label.text, "", "⚔ Прогноз боя: %d против %d" % [int(pv["att"]), int(pv["def"])]]
	for m in pv["att_mods"]:
		lines.append("  наш: %s %+d" % [m[0], int(m[1])])
	for m in pv["def_mods"]:
		lines.append("  их: %s %+d" % [m[0], int(m[1])])
	lines.append("Урон врагу ≈ %d, нам ≈ %d" % [int(pv["dmg_to_def"]), int(pv["dmg_to_att"])])
	if err != "":
		lines.append("(%s)" % err)
	_tile_label.text = "\n".join(lines)


func set_end_turn_text(text: String, urgent: bool) -> void:
	_end_turn_button.text = text
	_end_turn_button.modulate = Color(1.0, 0.85, 0.5) if urgent else Color.WHITE
