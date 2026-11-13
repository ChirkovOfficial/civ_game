class_name HexGrid
extends RefCounted
## Геометрия гексагональной карты (ГДД 3.1).
##
## Гексы «заострённой вершиной вверх», строки со смещением (нечётные строки
## сдвинуты вправо, схема odd-r). Карта зациклена по горизонтали (цилиндр).
## Клетка однозначно задаётся индексом `index = row * width + col`.
## Для вычислений используются осевые координаты (q, r), где r == row.
##
## Направления (по часовой стрелке на экране, против часовой в математике,
## т.к. ось r направлена вниз):
##   0 = E, 1 = NE, 2 = NW, 3 = W, 4 = SW, 5 = SE
## Свойство, на которое опирается код рек: DIRS[d+2] == DIRS[d+1] - DIRS[d].

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const DIR_COUNT := 6
const SQRT3 := 1.7320508075688772

var width: int
var height: int


func _init(w: int, h: int) -> void:
	assert(w > 0 and h > 0)
	width = w
	height = h


func tile_count() -> int:
	return width * height


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < width * height


# --- Преобразования координат -------------------------------------------------

func index_of(col: int, row: int) -> int:
	if row < 0 or row >= height:
		return -1
	return row * width + posmod(col, width)


func col_of(index: int) -> int:
	return index % width


func row_of(index: int) -> int:
	return index / width


func offset_of(index: int) -> Vector2i:
	return Vector2i(index % width, index / width)


static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


static func axial_to_offset(q: int, r: int) -> Vector2i:
	return Vector2i(q + (r - (r & 1)) / 2, r)


func axial_of(index: int) -> Vector2i:
	return offset_to_axial(index % width, index / width)


## Индекс клетки по осевым координатам с учётом цилиндра; -1 вне карты по вертикали.
func index_of_axial(axial: Vector2i) -> int:
	var off := axial_to_offset(axial.x, axial.y)
	return index_of(off.x, off.y)


# --- Соседи и расстояния -------------------------------------------------------

## Сосед в направлении dir (0..5) или -1, если за верхним/нижним краем.
func neighbor(index: int, dir: int) -> int:
	return index_of_axial(axial_of(index) + DIRS[dir])


## Все существующие соседи (порядок по направлениям, без -1).
func neighbors(index: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var a := axial_of(index)
	for d in DIR_COUNT:
		var n := index_of_axial(a + DIRS[d])
		if n >= 0:
			result.append(n)
	return result


## Направление от a к соседней клетке b, либо -1, если они не соседи.
func direction_to(a: int, b: int) -> int:
	for d in DIR_COUNT:
		if neighbor(a, d) == b:
			return d
	return -1


static func opposite(dir: int) -> int:
	return (dir + 3) % 6


static func axial_distance(dq: int, dr: int) -> int:
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Расстояние в клетках с учётом зацикливания по горизонтали.
func distance(a: int, b: int) -> int:
	var aa := axial_of(a)
	var bb := axial_of(b)
	var dq := bb.x - aa.x
	var dr := bb.y - aa.y
	var best := axial_distance(dq, dr)
	best = mini(best, axial_distance(dq - width, dr))
	best = mini(best, axial_distance(dq + width, dr))
	return best


## Осевые координаты b, «развёрнутые» так, чтобы быть ближе всего к a
## (нужно для линий обзора и интерполяции через шов цилиндра).
func unwrapped_axial(a: int, b: int) -> Vector2i:
	var aa := axial_of(a)
	var bb := axial_of(b)
	var best := bb
	var best_d := axial_distance(bb.x - aa.x, bb.y - aa.y)
	for shift in [-width, width]:
		var cand := Vector2i(bb.x + shift, bb.y)
		var d := axial_distance(cand.x - aa.x, cand.y - aa.y)
		if d < best_d:
			best_d = d
			best = cand
	return best


## Все клетки на расстоянии <= radius (включая центр), без повторов.
func tiles_in_radius(center: int, radius: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var seen := {}
	var c := axial_of(center)
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var idx := index_of_axial(Vector2i(c.x + dq, c.y + dr))
			if idx >= 0 and not seen.has(idx):
				seen[idx] = true
				result.append(idx)
	return result


## Клетки ровно на расстоянии radius.
func ring(center: int, radius: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for idx in tiles_in_radius(center, radius):
		if distance(center, idx) == radius:
			result.append(idx)
	return result


# --- Линии (для обзора) --------------------------------------------------------

static func _cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundi(fq)
	var r := roundi(fr)
	var s := roundi(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## Промежуточные клетки линии от a к b (без концов). nudge = ±1 сдвигает
## точки на эпсилон, чтобы разрешать неоднозначности на рёбрах в обе стороны.
func line_between(a: int, b: int, nudge: int = 1) -> PackedInt32Array:
	var result := PackedInt32Array()
	var aa := axial_of(a)
	var bb := unwrapped_axial(a, b)
	var n := axial_distance(bb.x - aa.x, bb.y - aa.y)
	var eps := 1e-4 * nudge
	for i in range(1, n):
		var t := float(i) / n
		var fq := lerpf(aa.x + eps, bb.x + eps, t)
		var fr := lerpf(aa.y + eps * 2.0, bb.y + eps * 2.0, t)
		var idx := index_of_axial(_cube_round(fq, fr))
		if idx >= 0:
			result.append(idx)
	return result


# --- Мировые координаты (для отображения) -------------------------------------

## Центр клетки в плоскости XZ при радиусе гекса size.
func world_position(index: int, size: float = 1.0) -> Vector2:
	var col := index % width
	var row := index / width
	return Vector2(size * SQRT3 * (col + 0.5 * (row & 1)), size * 1.5 * row)


func world_width(size: float = 1.0) -> float:
	return size * SQRT3 * width


## Клетка под точкой (x, z) плоскости; -1 вне карты по вертикали.
func index_at_world(x: float, z: float, size: float = 1.0) -> int:
	var fq := (SQRT3 / 3.0 * x - z / 3.0) / size
	var fr := (2.0 / 3.0 * z) / size
	return index_of_axial(_cube_round(fq, fr))


## Угол (вершина) k гекса в локальных координатах. Вершина k лежит между
## рёбрами k-1 и k; ребро d соединяет вершины d и d+1 и обращено к соседу d.
static func corner_offset(k: int, size: float = 1.0) -> Vector2:
	# Угол отсчитывается от оси +x к «верху экрана» (ось z направлена вниз).
	# Ребро d обращено к соседу под углом 60*d, вершина k — под углом 60*k - 30.
	var angle := deg_to_rad(60.0 * k - 30.0)
	return Vector2(cos(angle), -sin(angle)) * size
