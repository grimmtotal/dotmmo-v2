extends Node2D

## A box you sweep through the world to collect one material.
##
## The box takes a single type at a time. It has no filter until the first
## particle goes in, and that particle sets it: sweep into a bank of sand and
## the box is a sand box for as long as it holds any, ignoring the water and the
## rubble it passes over afterwards. That is the whole rule, and it is what
## makes a sweep predictable - you can drag through mixed ground without having
## to be careful about what else is under the mouth.
##
## When the first sweep touches more than one material at once, the one nearest
## where you are pointing wins. The tooltip says which that is before you press,
## so the choice is never a surprise.
##
## Contents are not a picture of what was collected. The box is a container, not
## a snapshot: it holds a count, not a shape, which is why it can be filled from
## a dozen scattered cells and poured out somewhere entirely different. Each
## grain still keeps its own variant byte, so a boxful of sand poured out has
## the same grain it had in the ground rather than being re-rolled.

## Fill level, in particles, for a box of a given brush radius.
const CAPACITY_PER_CELL: int = 8
const CAPACITY_MIN: int = 8

## Ceiling on how much moves in or out in a single frame, so a sweep reads as
## scooping rather than teleporting and a pour looks like pouring.
const FLOW_PER_FRAME: int = 12

const BOX_EDGE: Color = Color(0.82, 0.90, 1.0, 0.75)
const BOX_BACK: Color = Color(0.30, 0.42, 0.58, 0.20)
const EDGE_WIDTH: float = 3.0
const FILL_ALPHA: float = 0.80

## The cell about to be taken from, picked out so the filter choice is visible
## before the button goes down.
const MARK_COLOR: Color = Color(1, 1, 1, 0.85)
const MARK_WIDTH: float = 3.0

const LABEL_SIZE: int = 26
const LABEL_COLOR: Color = Color(0.94, 0.97, 1.0)
const LABEL_BACK: Color = Color(0.05, 0.07, 0.10, 0.82)
const LABEL_PAD: Vector2 = Vector2(10, 6)
const LABEL_LIFT: float = 14.0

## Packed type-and-variant values, all of the same type.
var _payload: PackedInt32Array = PackedInt32Array()
## Type id the box is locked to, or 0 while it is empty and unfiltered.
var _filter: int = 0
var _capacity: int = CAPACITY_MIN

var _cells: Array = []
var _aim_point: Vector2 = Vector2.ZERO
## The cell the box would take from next, and its type. Refreshed as you hover.
var _candidate_cell: Vector2 = Vector2.ZERO
var _candidate_type: int = 0


func is_holding() -> bool:
	return not _payload.is_empty()


func held_count() -> int:
	return _payload.size()


func capacity() -> int:
	return _capacity


func filter_name() -> String:
	return SimulationGlobal.typeName(_filter)


func is_full() -> bool:
	return _payload.size() >= _capacity


## Where the mouth of the box is, what it covers, and how much it holds. Called
## every frame by the controller, so the box tracks the aim and the brush.
func aim_at(cells: Array, point: Vector2, radius: int) -> void:
	_cells = cells
	_aim_point = point
	_capacity = maxi(CAPACITY_MIN, radius * radius * CAPACITY_PER_CELL)
	_find_candidate()
	queue_redraw()


## What the box would take next: the material it is already holding if it has
## one, and otherwise whatever capturable thing lies nearest the aim point.
##
## Nearest rather than first-found matters. A sweep that starts across a
## boundary would otherwise lock onto whichever cell the loop happened to reach
## first, which from the outside looks arbitrary - pointing at the sand and
## getting a box of water.
func _find_candidate() -> void:
	_candidate_type = 0
	var best: float = INF
	var scale: float = float(Global.WORLD_PIXEL_SCALE)

	for entry: Variant in _cells:
		var cell: Vector2 = entry
		var type_id: int = SimulationGlobal.capturableAt(cell)
		if type_id == 0:
			continue
		if _filter != 0 and type_id != _filter:
			continue

		var middle: Vector2 = (cell + Vector2(0.5, 0.5)) * scale
		var distance: float = middle.distance_squared_to(_aim_point)
		if distance < best:
			best = distance
			_candidate_cell = cell
			_candidate_type = type_id


## Takes what it can this frame. The first particle in sets the filter, and
## everything after it has to match.
func scoop() -> int:
	if is_full():
		return 0

	var taken: int = 0
	while taken < FLOW_PER_FRAME and not is_full():
		if _candidate_type == 0:
			break
		if _filter == 0:
			_filter = _candidate_type

		var packed: int = SimulationGlobal.captureParticle(_candidate_cell)
		if packed == 0:
			break
		_payload.append(packed)
		taken += 1
		_find_candidate()

	if taken > 0:
		queue_redraw()
	return taken


## Pours back out, nearest the aim point first, into whatever cells are free.
## Empties the filter with the last particle, so the box is ready to take
## something else the moment it is empty.
func pour() -> int:
	if not is_holding():
		return 0

	var poured: int = 0
	for entry: Variant in _sorted_by_distance():
		if poured >= FLOW_PER_FRAME or not is_holding():
			break
		var cell: Vector2 = entry
		if not SimulationGlobal.isVacant(cell):
			continue
		if SimulationGlobal.releaseParticle(cell, _payload[_payload.size() - 1]):
			_payload.remove_at(_payload.size() - 1)
			poured += 1

	if not is_holding():
		_filter = 0
	if poured > 0:
		_find_candidate()
		queue_redraw()
	return poured


func _sorted_by_distance() -> Array:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var sorted: Array = _cells.duplicate()
	var point: Vector2 = _aim_point
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return ((a + Vector2(0.5, 0.5)) * scale).distance_squared_to(point) \
			< ((b + Vector2(0.5, 0.5)) * scale).distance_squared_to(point))
	return sorted


## Empties the box where it stands, for when the tool changes out from under it.
## Anything with nowhere to go goes back above the mouth, which is where falling
## matter would end up anyway.
func empty_out() -> void:
	while is_holding():
		if pour() > 0:
			continue
		# Nothing free under the mouth - go up until something is.
		var placed: bool = false
		for lift: int in 64:
			var cell: Vector2 = _candidate_cell - Vector2(0, lift)
			if SimulationGlobal.releaseParticle(cell, _payload[_payload.size() - 1]):
				_payload.remove_at(_payload.size() - 1)
				placed = true
				break
		if not placed:
			break

	_payload = PackedInt32Array()
	_filter = 0
	queue_redraw()


func _draw() -> void:
	if _cells.is_empty():
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var box: Rect2 = _footprint(scale)

	# The mouth, with what it holds filling it from the bottom up.
	draw_rect(box, BOX_BACK, true)
	if is_holding():
		var level: float = float(_payload.size()) / float(_capacity)
		var fill: Color = SimulationGlobal.colorOf(_payload[0])
		fill.a = FILL_ALPHA
		draw_rect(Rect2(
			Vector2(box.position.x, box.position.y + box.size.y * (1.0 - level)),
			Vector2(box.size.x, box.size.y * level)), fill, true)
	draw_rect(box, BOX_EDGE, false, EDGE_WIDTH)

	# The cell it would take from next.
	if _candidate_type != 0 and not is_full():
		draw_rect(Rect2(_candidate_cell * scale, Vector2(scale, scale)),
			MARK_COLOR, false, MARK_WIDTH)

	_draw_label(box)


func _footprint(scale: float) -> Rect2:
	var low: Vector2 = _cells[0]
	var high: Vector2 = _cells[0]
	for entry: Variant in _cells:
		var cell: Vector2 = entry
		low = Vector2(minf(low.x, cell.x), minf(low.y, cell.y))
		high = Vector2(maxf(high.x, cell.x), maxf(high.y, cell.y))
	return Rect2(low * scale, (high - low + Vector2.ONE) * scale)


## Says what the box is about to take, or what it is already carrying. Without
## it the filter is invisible until after it has been chosen, which is exactly
## the wrong time to find out.
func _draw_label(box: Rect2) -> void:
	var text: String = ""
	if is_holding():
		text = "%s   %d / %d" % [filter_name(), _payload.size(), _capacity]
	elif _candidate_type != 0:
		text = SimulationGlobal.typeName(_candidate_type)
	else:
		text = "Nothing to collect"

	var font: Font = ThemeDB.fallback_font
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var corner := Vector2(
		box.position.x + box.size.x * 0.5 - size.x * 0.5 - LABEL_PAD.x,
		box.position.y - size.y - LABEL_PAD.y * 2.0 - LABEL_LIFT)

	draw_rect(Rect2(corner, size + LABEL_PAD * 2.0), LABEL_BACK, true)
	draw_string(font, corner + Vector2(LABEL_PAD.x, LABEL_PAD.y + size.y * 0.8),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)
