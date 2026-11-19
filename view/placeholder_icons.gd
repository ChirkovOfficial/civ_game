class_name PlaceholderIcons
extends RefCounted
## Временные значки из вложенного листа. AtlasTexture обрезает ячейку при выводе,
## не меняя исходное изображение. Номера ячеек сохранены для последующей замены.

const SHEET := "res://art/icons/placeholder/ui_icon_sheet.png"
const CELL_SIZE := Vector2(43, 44)
const COLUMN_STEP := 51
const LEFT := 9
const DEFAULT_TOP := 28
const DISTRICT_TOP := 157
const ROW_STEP := 51

const DEFAULT := {
	"sword": 0, "target": 1, "moon": 2, "hex": 3, "hammer": 4, "shield": 5, "arrow": 6,
	"ban": 7, "plus": 8, "circle": 9, "down": 10, "star": 11, "square": 12, "diamond": 13,
}

## 13 районных значков: 7 в верхнем ряду и 6 в нижнем.
const DISTRICT_CELLS := {
	"GOVERNMENT_PLAZA": 0,
	"HOLY_SITE": 1,
	"CAMPUS": 2,
	"ENCAMPMENT": 3,
	"HARBOR": 4,
	"THEATER_SQUARE": 5,
	"COMMERCIAL_HUB": 6,
	"BATHS": 7,
	"ENTERTAINMENT_COMPLEX": 8,
	"INDUSTRIAL_ZONE": 9,
	"RESIDENTIAL_HOUSING": 10,
	"RESIDENTIAL_URBAN": 10,
	"RESIDENTIAL_RICH": 10,
	"RESIDENTIAL_DENSE": 11,
	"WATER_PARK": 12,
}

static var _sheet: Texture2D
static var _cache: Dictionary = {}


static func _cell(index: int, top: int) -> Texture2D:
	if _sheet == null:
		_sheet = load(SHEET)
	if _sheet == null:
		return null
	var key := "%d:%d" % [index, top]
	if not _cache.has(key):
		var tex := AtlasTexture.new()
		tex.atlas = _sheet
		tex.region = Rect2(Vector2(LEFT + (index % 7) * COLUMN_STEP,
			top + (index / 7) * ROW_STEP), CELL_SIZE)
		tex.filter_clip = true
		_cache[key] = tex
	return _cache[key]


static func general(name: String) -> Texture2D:
	return _cell(int(DEFAULT.get(name, DEFAULT["hex"])), DEFAULT_TOP)


static func district(type: String) -> Texture2D:
	if DISTRICT_CELLS.has(type):
		return _cell(int(DISTRICT_CELLS[type]), DISTRICT_TOP)
	return general("hex")


static func raw_district(index: int) -> Texture2D:
	return _cell(clampi(index, 0, 12), DISTRICT_TOP)
