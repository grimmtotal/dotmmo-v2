extends Node2D

## A handful of particles lifted out of the world, drawn as a ghost at the
## cursor until it is put back down.
##
## Captured particles leave the simulation entirely while they are held - they
## do not fall, react, or take part in anything - so the payload is just an
## array of packed type-and-variant values plus the offset each one sat at
## relative to the grab point. Keeping the variant byte is what makes a carried
## dune land as the same dune: every grain comes back in the shade it left with,
## instead of being re-rolled into a fresh pile.
##
## Releasing is all-or-nothing. A partial drop would either destroy whatever did
## not fit or leave the hand in some half-full state, and both are worse than
## simply refusing: the ghost turns red the moment the destination cannot take
## the whole payload, and a release there keeps hold of it so you can move and
## try again. Nothing the hand picks up can be lost.

## How far up return_to_world looks for somewhere to put a grain whose own cell
## has been taken. Matter falls, so releasing it above the blockage and letting
## it settle is the natural answer, and in a side-scroller the sky overhead is
## nearly always clear.
const RETURN_SEARCH: int = 64

const FILL_ALPHA: float = 0.55
const BLOCKED_TINT: Color = Color(1.0, 0.25, 0.25)
const BLOCKED_MIX: float = 0.7
const OUTLINE_COLOR: Color = Color(1, 1, 1, 0.5)
const OUTLINE_WIDTH: float = 2.0

## Packed type-and-variant values, as handed out by SimulationGlobal.captureParticle.
var _payload: PackedInt32Array = PackedInt32Array()
## Where each held particle sat relative to the grab point, in cells.
var _offsets: Array[Vector2i] = []

var _grid_position: Vector2i = Vector2i.ZERO
var _can_release: bool = false


func is_holding() -> bool:
	return not _payload.is_empty()


func held_count() -> int:
	return _payload.size()


## Lifts every capturable particle in `cells` out of the world. Cells holding
## something the hand cannot take are simply skipped, so brushing a mixed
## handful of sand and stone takes the sand and leaves the wall standing.
func grab(cells: Array, center: Vector2i) -> int:
	_payload = PackedInt32Array()
	_offsets = []

	for entry: Variant in cells:
		var cell: Vector2i = Vector2i(entry)
		var packed: int = SimulationGlobal.captureParticle(Vector2(cell))
		if packed == 0:
			continue
		_payload.append(packed)
		_offsets.append(cell - center)

	_grid_position = center
	_refresh()
	return _payload.size()


## Puts the whole payload back down, or nothing at all. Returns whether it went.
func release() -> bool:
	if not is_holding() or not _can_release:
		return false

	for index: int in _payload.size():
		SimulationGlobal.releaseParticle(
			Vector2(_grid_position + _offsets[index]), _payload[index])

	_payload = PackedInt32Array()
	_offsets = []
	_refresh()
	return true


## Empties the hand where it stands, for when the tool changes out from under a
## held payload - the alternative is particles sitting in limbo with no ghost on
## screen to say they exist.
##
## Unlike release() this does not refuse a blocked destination, because there is
## nowhere else for the payload to go. Each grain takes its own cell if it is
## free and otherwise the first free cell above it, which is where falling
## matter would end up anyway.
func return_to_world() -> void:
	for index: int in _payload.size():
		var cell: Vector2i = _grid_position + _offsets[index]
		for step: int in RETURN_SEARCH:
			if SimulationGlobal.releaseParticle(
					Vector2(cell.x, cell.y - step), _payload[index]):
				break

	_payload = PackedInt32Array()
	_offsets = []
	_refresh()


func set_grid_position(value: Vector2i) -> void:
	if value == _grid_position:
		return
	_grid_position = value
	_refresh()


## Whether every cell the payload would land in is empty right now.
func _refresh() -> void:
	_can_release = is_holding()
	for offset: Vector2i in _offsets:
		if not SimulationGlobal.isVacant(Vector2(_grid_position + offset)):
			_can_release = false
			break
	queue_redraw()


## The world keeps running underneath a held payload, so what was a clear
## landing spot a moment ago may not be one now. Re-checking every frame is what
## keeps the ghost's colour honest.
func _process(_delta: float) -> void:
	if is_holding():
		_refresh()


func _draw() -> void:
	if not is_holding():
		return

	var scale_px: int = Global.WORLD_PIXEL_SCALE
	var size := Vector2(scale_px, scale_px)

	for index: int in _payload.size():
		var color: Color = SimulationGlobal.colorOf(_payload[index])
		if not _can_release:
			color = color.lerp(BLOCKED_TINT, BLOCKED_MIX)
		color.a = FILL_ALPHA

		var corner := Vector2((_grid_position + _offsets[index]) * scale_px)
		draw_rect(Rect2(corner, size), color, true)

	# A single outline around the whole footprint would need the payload's
	# silhouette; the bounding box is enough to make the ghost read as one held
	# thing rather than a scatter of translucent squares.
	draw_rect(_bounds(scale_px), OUTLINE_COLOR, false, OUTLINE_WIDTH)


func _bounds(scale_px: int) -> Rect2:
	var low: Vector2i = _offsets[0]
	var high: Vector2i = _offsets[0]
	for offset: Vector2i in _offsets:
		low = low.min(offset)
		high = high.max(offset)

	return Rect2(
		Vector2((_grid_position + low) * scale_px),
		Vector2((high - low + Vector2i.ONE) * scale_px))
