extends Control
## Мини-карта читает только разведанные клетки. Щелчок переносит камеру.
signal tile_pressed(tile: int)
signal zoom_pressed(direction: int)
const UiSkin := preload("res://view/ui_skin.gd")
var game: Game
var reveal_all := false
var _texture: ImageTexture
var _map_rect := Rect2(17, 17, 174, 139)

func _ready() -> void:
	custom_minimum_size = Vector2(234, 176)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Мини-карта · щёлкните, чтобы переместить камеру"
	for direction in [1, -1]:
		var button := Button.new()
		button.text = "+" if direction > 0 else "−"
		button.position = Vector2(199, 52 if direction > 0 else 96)
		button.size = Vector2(28, 34)
		button.pressed.connect(func(): zoom_pressed.emit(direction))
		add_child(button)

func refresh(g: Game, revealed: bool) -> void:
	game = g
	reveal_all = revealed
	var map := game.state.map
	var player := game.state.player(game.state.current_player)
	var image := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	for tile in map.size():
		var color := Color("141e29")
		if reveal_all or player.is_revealed(tile):
			color = MapStyle.top_color(map, tile)
			if map.is_mountain(tile):
				color = Color("b9b6a3")
			var city := game.state.city_at(tile)
			if city != null:
				color = game.state.player(city.owner).color
			if not reveal_all and not player.is_visible(tile):
				color = color.darkened(0.4)
		image.set_pixel(map.grid.col_of(tile), map.grid.row_of(tile), color)
	_texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, _map_rect, false)
	# Берём только рамку с прозрачным окном; декоративные +/- закрыты фоном.
	draw_texture_rect(UiSkin.texture("minimap"), Rect2(Vector2.ZERO, Vector2(234, 176)), false)
	draw_style_box(UiSkin.box("button"), Rect2(196, 35, 34, 116))

func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _map_rect.has_point(event.position):
			var uv: Vector2 = (event.position - _map_rect.position) / _map_rect.size
			var map := game.state.map
			var tile := map.grid.index_of(clampi(int(uv.x * map.width), 0, map.width - 1),
				clampi(int(uv.y * map.height), 0, map.height - 1))
			tile_pressed.emit(tile)
		accept_event()
