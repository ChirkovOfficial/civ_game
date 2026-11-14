class_name Hud
extends CanvasLayer
## Интерфейс поверх карты (временный, до макетов художника).
## Все изменения мира идут через act.call(action) — тот же API, что у ИИ.

signal end_turn_pressed
signal new_map_pressed
signal save_pressed
signal load_pressed
signal reveal_toggled(on: bool)
signal city_closed

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
	_research_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_research_panel.position = Vector2(10, 64)
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
	_end_turn_button = Button.new()
	_end_turn_button.text = "Конец хода (Enter)"
	_end_turn_button.custom_minimum_size = Vector2(280, 56)
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	br.add_child(_end_turn_button)

	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.position = Vector2(-250, 70)
	_message.custom_minimum_size = Vector2(500, 0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	_message.add_theme_font_size_override("font_size", 20)
	_root.add_child(_message)

	var help := Label.new()
	help.text = "ЛКМ — юнит/город · ПКМ — идти · WASD, колесо, СКМ — камера · Tab — следующий юнит · B — город · F — укрепиться/спать · R — дорога"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-420, -28)
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
	var wars := 0
	for other in game.state.players:
		if other.id != pid and not other.is_barbarian and game.state.at_war(pid, other.id):
			wars += 1
	var db := Button.new()
	db.text = "Державы" + (" (войн: %d)" % wars if wars > 0 else "")
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
	if _research_kind == "diplomacy":
		open_diplomacy()
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
	for id in ids:
		var def: Dictionary = tree[id]
		var cost := EmpireRules.tech_cost(game, id) if is_tech else EmpireRules.civic_cost(game, id)
		var t := EmpireRules.turns_left(cost, float(progress.get(id, 0.0)), per)
		var current := (p.current_tech if is_tech else p.current_civic) == id
		var b := _button(_research_box, "%s%s — %s х." % ["▶ " if current else "", def["name"], str(t) if t > 0 else "∞"],
			func(): _choose_research(id), false, "Открывает: %s" % def.get("unlocks_text", ""))
		b.icon = _icons.get("science" if is_tech else "culture")
		b.add_theme_constant_override("icon_max_width", 18)
		var desc := _label(_research_box, "    " + str(def.get("unlocks_text", "")), 12, Color(0.75, 0.78, 0.85), true)
		desc.custom_minimum_size = Vector2(400, 0)
	if ids.is_empty():
		_label(_research_box, "Нет доступных исследований")


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
	_button(head, "✕", close_research)
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
		if war:
			var e := UnitRules.make_peace_error(game, pid, oid)
			_button(row, "Заключить мир", func(): act.call({"type": "make_peace", "target": oid}); open_diplomacy(), e != "", e)
		else:
			var e2 := UnitRules.declare_war_error(game, pid, oid)
			_button(row, "Объявить войну", func(): act.call({"type": "declare_war", "target": oid}); open_diplomacy(), e2 != "", e2)
	if not any:
		_label(_research_box, "Вы ещё ни с кем не встретились.")
	_label(_research_box, "Дипломатия появится на этапе M6; пока доступны только война и мир. С варварами всегда война.", 12, Color(0.75, 0.78, 0.85), true)


func _choose_research(id: String) -> void:
	act.call({"type": "set_research", "kind": _research_kind, "id": id})
	close_research()


# --- Юнит -------------------------------------------------------------------------------------

func show_unit(u: Unit) -> void:
	_clear(_unit_box)
	if u == null or game.state.unit(u.id) == null:
		_unit_panel.visible = false
		return
	_unit_panel.visible = true
	var def := game.data.unit_def(u.type)
	_label(_unit_box, Abilities.unit_name(game, u.owner, u.type), 20)
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
	for a in Abilities.of(game, u.owner, u.type):
		if game.data.abilities.has(a):
			lines.append("◆ %s" % game.data.abilities[a]["name"])
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
	if abilities.has("FOUND_CITY"):
		var err := CityRules.found_city_error(game, u.owner, u.tile)
		_button(_unit_box, "Основать город (B)", func(): act.call({"type": "found_city", "unit": u.id}),
			err != "" or u.moves_left <= 0.0, err)
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
	for it in CityRules.buildable_items(game, city):
		var line := HBoxContainer.new()
		_city_box.add_child(line)
		var t := CityRules.turns_to_build(game, city, it)
		var kind: String = it["kind"]
		var id: String = it["id"]
		var b := _button(line, "%s — %s х." % [CityRules.item_name(game, it, city.owner), str(t) if t > 0 else "∞"],
			func(): act.call({"type": "set_production", "city": city.id, "kind": kind, "id": id}))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var price := CityRules.purchase_cost(game, city, it)
		var buy := _button(line, "%d" % price, func(): act.call({"type": "purchase", "city": city.id, "kind": kind, "id": id}),
			treasury < price, "Купить за золото")
		buy.icon = _icons.get("gold")
		buy.add_theme_constant_override("icon_max_width", 16)
	_label(_city_box, "Купить клетку: щёлкните по клетке с ценой рядом с городом.", 12, Color(0.75, 0.78, 0.85), true)


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
