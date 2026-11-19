extends RefCounted
## Области сгенерированного атласа. Прямые участки рамок растягиваются через 9-slice.
const SHEET := preload("res://art/ui/generated/v1/strategy_ui_atlas.png")
const REGIONS := {
	"panel": Rect2(17, 279, 416, 316),
	"button": Rect2(845, 625, 97, 39),
	"hover": Rect2(946, 625, 95, 39),
	"pressed": Rect2(1045, 625, 95, 39),
	"disabled": Rect2(1143, 625, 95, 39),
	"track": Rect2(23, 949, 214, 15),
	"fill": Rect2(265, 950, 172, 14),
	"minimap": Rect2(721, 422, 232, 174),
	"turn": Rect2(900, 944, 85, 90),
}
const YIELDS := {"science": Rect2(27, 77, 48, 39), "culture": Rect2(238, 77, 42, 39),
	"gold": Rect2(445, 77, 39, 39), "food": Rect2(651, 77, 40, 39),
	"production": Rect2(856, 77, 40, 39), "faith": Rect2(1066, 77, 39, 39)}
const DISTRICTS := {"CAMPUS": Vector2(20, 622), "HOLY_SITE": Vector2(295, 622),
	"ENCAMPMENT": Vector2(563, 622), "COMMERCIAL_HUB": Vector2(20, 680),
	"THEATER_SQUARE": Vector2(295, 680), "INDUSTRIAL_ZONE": Vector2(563, 680),
	"RESIDENTIAL_HOUSING": Vector2(20, 738), "RESIDENTIAL_URBAN": Vector2(20, 738),
	"RESIDENTIAL_DENSE": Vector2(20, 738), "RESIDENTIAL_RICH": Vector2(20, 738),
	"AQUEDUCT": Vector2(295, 738), "ENTERTAINMENT_COMPLEX": Vector2(563, 738),
	"BATHS": Vector2(20, 797), "GOVERNMENT_PLAZA": Vector2(295, 797), "HARBOR": Vector2(563, 797)}

static func district(type: String) -> Texture2D:
	if DISTRICTS.has(type):
		return region(Rect2(DISTRICTS[type], Vector2(48, 52)))
	return preload("res://view/placeholder_icons.gd").district(type)

static func region(rect: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = SHEET
	texture.region = rect
	texture.filter_clip = true
	return texture

static func texture(id: String) -> AtlasTexture:
	return region(REGIONS[id])

static func box(id: String, margin: int = 8) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture(id)
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(10)
	return style

static func panel() -> StyleBoxTexture:
	# Чистая рамка без нарисованных неактивных вкладок.
	var style := box("button", 7)
	style.set_content_margin_all(14)
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	for type in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			var id: String = {"normal": "button", "hover_pressed": "pressed"}.get(state, state)
			result.set_stylebox(state, type, box(id, 7))
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color("f3d892")
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type, focus)
		result.set_color("font_color", type, Color("eee5cf"))
		result.set_color("font_disabled_color", type, Color("969b9d"))
		result.set_constant("icon_max_width", type, 24)
	result.set_stylebox("panel", "PanelContainer", box("button"))
	result.set_stylebox("panel", "PopupMenu", box("button"))
	result.set_stylebox("panel", "TooltipPanel", box("button"))
	result.set_stylebox("background", "ProgressBar", box("track", 7))
	result.set_stylebox("fill", "ProgressBar", box("fill", 7))
	result.set_color("font_color", "Label", Color("eee5cf"))
	return result
