class_name Player
extends RefCounted
## Крупная держава (игрок или ИИ). ГДД 25.2.

const FOG_UNEXPLORED := 0
const FOG_REVEALED := 1   # местность видна, юниты — нет

var id: int
var name: String
var color: Color
var civ_trait_id: String = ""
var is_ai: bool = false
var alive: bool = true
var treasury: float = 0.0
var known_techs: Dictionary = {}   # id -> true
var known_civics: Dictionary = {}

## Разведанные клетки (FOG_*). Сохраняется.
var revealed: PackedByteArray
## Сколько «глаз» сейчас видят клетку. Производное — пересчитывается, не сохраняется.
var visible_count: PackedInt32Array


func init_fog(tile_count: int) -> void:
	revealed.resize(tile_count)
	revealed.fill(FOG_UNEXPLORED)
	visible_count.resize(tile_count)
	visible_count.fill(0)


func is_revealed(tile: int) -> bool:
	return revealed[tile] != FOG_UNEXPLORED


func is_visible(tile: int) -> bool:
	return visible_count[tile] > 0


func has_tech(tech_id: String) -> bool:
	return known_techs.has(tech_id)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "color": color.to_html(false),
		"civ_trait_id": civ_trait_id, "is_ai": is_ai, "alive": alive,
		"treasury": treasury, "known_techs": known_techs.keys(),
		"known_civics": known_civics.keys(), "revealed": Marshalls.raw_to_base64(revealed),
	}


static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = int(d["id"])
	p.name = d["name"]
	p.color = Color.html(d["color"])
	p.civ_trait_id = d["civ_trait_id"]
	p.is_ai = bool(d["is_ai"])
	p.alive = bool(d["alive"])
	p.treasury = float(d["treasury"])
	for t in d["known_techs"]:
		p.known_techs[t] = true
	for c in d["known_civics"]:
		p.known_civics[c] = true
	p.revealed = Marshalls.base64_to_raw(d["revealed"])
	p.visible_count.resize(p.revealed.size())
	return p
