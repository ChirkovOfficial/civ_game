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
var faith: float = 0.0
var known_techs: Dictionary = {}   # id -> true
var known_civics: Dictionary = {}
## Текущее исследование и накопленный прогресс по технологиям/институтам (ГДД 4.4, 4.5).
var current_tech: String = ""
var tech_progress: Dictionary = {}    # id -> 🔬
var current_civic: String = ""
var civic_progress: Dictionary = {}   # id -> 🎭
## Сколько юнитов каждого типа произведено (рост цены поселенцев/строителей, ГДД 5.1, 8.1).
var produced: Dictionary = {}
## Сколько имён городов уже использовано из списка цивилизации.
var city_names_used: int = 0

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


func has_civic(civic_id: String) -> bool:
	return known_civics.has(civic_id)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "color": color.to_html(false),
		"civ_trait_id": civ_trait_id, "is_ai": is_ai, "alive": alive,
		"treasury": treasury, "faith": faith, "known_techs": _sorted_keys(known_techs),
		"known_civics": _sorted_keys(known_civics), "revealed": Marshalls.raw_to_base64(revealed),
		"current_tech": current_tech, "tech_progress": tech_progress.duplicate(),
		"current_civic": current_civic, "civic_progress": civic_progress.duplicate(),
		"produced": produced.duplicate(), "city_names_used": city_names_used,
	}


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


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
	p.faith = float(d.get("faith", 0.0))
	p.current_tech = d.get("current_tech", "")
	p.current_civic = d.get("current_civic", "")
	for k in d.get("tech_progress", {}):
		p.tech_progress[k] = float(d["tech_progress"][k])
	for k in d.get("civic_progress", {}):
		p.civic_progress[k] = float(d["civic_progress"][k])
	for k in d.get("produced", {}):
		p.produced[k] = int(d["produced"][k])
	p.city_names_used = int(d.get("city_names_used", 0))
	p.visible_count.resize(p.revealed.size())
	return p
