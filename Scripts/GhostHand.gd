extends Node2D

## A spectral hand the character reaches out with, and the handful of the world
## it closes around.
##
## It has to be a ghost rather than a real hand, and the scale is what decides
## that: a block is 64 pixels and the whole character is 48, so a hand that
## could actually close around a block would be bigger than the person holding
## it. Drawing it as something translucent and conjured, sized to the handful
## rather than to the body, is the only reading of that which is not absurd -
## and it matches what it does, which is closer to telekinesis than to lifting.
##
## The hand is open while it is empty and gripping once it is full, and it turns
## with the aim, so it reads as reaching out to where it is about to take from.
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

const FILL_ALPHA: float = 0.75
const BLOCKED_TINT: Color = Color(1.0, 0.25, 0.25)
const BLOCKED_MIX: float = 0.7

## The hand itself. Cold and faint, so it never competes with the material it is
## carrying - the point of the ghost is to show you the handful, not itself.
const GHOST: Color = Color(0.62, 0.86, 1.0, 0.34)
const GHOST_EDGE: Color = Color(0.80, 0.94, 1.0, 0.55)
const GHOST_BLOCKED: Color = Color(1.0, 0.45, 0.45, 0.34)
const EDGE_WIDTH: float = 2.0

## The hand is laid out pointing along +X and the whole thing rotated onto the
## aim, so every measurement below reads as if it were reaching to the right.
##
## It grips rather than holds: the palm sits behind the handful and the fingers
## come forward over it, so the material is inside the grasp instead of stacked
## on top of a shape. That is also why the fingers are drawn after the payload
## and the palm before it - the hand closes around what it is carrying.
##
## Fingers fan out from the palm the way they do when you reach for something,
## and curl in when the hand shuts. Open and gripping differ only in the fan
## angle and how far the tips bend inward, which is enough to read instantly.
## Every measurement is a fraction of the handful's width, so the hand is always
## in proportion to what it is closing around. Keying the fingers to the palm
## instead makes them as thick as they are long the moment the palm grows, which
## reads as a bunch of blobs rather than a hand.
const FINGERS: int = 4
const PALM_RADIUS: float = 0.22
const FINGER_WIDTH: float = 0.095
const THUMB_WIDTH: float = 0.105

## Where the knuckles sit, back from the middle of the handful.
const KNUCKLE_BACK: float = 0.45

## How far the fingers come forward, and how far they fan out and bend in.
const REACH_OPEN: float = 0.95
const REACH_GRIP: float = 0.78
const FAN_OPEN: float = 0.55
const FAN_GRIP: float = 0.38
const CURL_OPEN: float = 0.10
const CURL_GRIP: float = 0.60

## The near segment's share of a finger's length; the rest is the bent tip.
const KNUCKLE_SHARE: float = 0.6

## Floor on the handful's width for drawing, so grabbing a single cell still
## leaves a hand big enough to see.
const SPAN_MIN_CELLS: float = 1.6

## Packed type-and-variant values, as handed out by SimulationGlobal.captureParticle.
var _payload: PackedInt32Array = PackedInt32Array()
## Where each held particle sat relative to the grab point, in cells.
var _offsets: Array[Vector2i] = []

var _grid_position: Vector2i = Vector2i.ZERO
var _can_release: bool = false

## Which way the hand is reaching, and how wide a handful it is set to take.
var _aim: Vector2 = Vector2.RIGHT
var _span_cells: float = 1.0


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


## The direction the hand reaches in, so it turns to face what it is grabbing.
func set_aim(direction: Vector2) -> void:
	if direction.length_squared() < 0.001 or direction.is_equal_approx(_aim):
		return
	_aim = direction.normalized()
	queue_redraw()


## How wide a handful the hand is set to take, in cells. Sizes the ghost, so a
## bigger brush is visibly a bigger hand rather than the same one with a
## different invisible footprint.
func set_span(cells: float) -> void:
	if is_equal_approx(cells, _span_cells):
		return
	_span_cells = maxf(cells, 1.0)
	queue_redraw()


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
	var scale_px: float = float(Global.WORLD_PIXEL_SCALE)
	var span: float = maxf(_span_cells, SPAN_MIN_CELLS) * scale_px
	var centre: Vector2 = (Vector2(_grid_position) + Vector2(0.5, 0.5)) * scale_px
	var fill: Color = GHOST
	var edge: Color = GHOST_EDGE
	if is_holding() and not _can_release:
		fill = GHOST_BLOCKED
		edge = Color(1.0, 0.6, 0.6, 0.6)

	# Palm behind the handful, material in the middle, fingers over the front:
	# the order is what makes the hand read as closed around what it carries.
	draw_set_transform(centre, _aim.angle(), Vector2.ONE)
	_draw_palm(span, fill, edge)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_payload(scale_px)

	draw_set_transform(centre, _aim.angle(), Vector2.ONE)
	_draw_fingers(span, fill, edge)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_payload(scale_px: float) -> void:
	if not is_holding():
		return

	var size := Vector2(scale_px, scale_px)
	for index: int in _payload.size():
		var color: Color = SimulationGlobal.colorOf(_payload[index])
		if not _can_release:
			color = color.lerp(BLOCKED_TINT, BLOCKED_MIX)
		color.a = FILL_ALPHA
		draw_rect(Rect2(Vector2(_grid_position + _offsets[index]) * scale_px, size),
			color, true)


## The heel of the hand, set back behind the handful along the aim.
func _draw_palm(span: float, fill: Color, edge: Color) -> void:
	var radius: float = span * PALM_RADIUS
	var back: Vector2 = Vector2(-(span * KNUCKLE_BACK + radius * 0.7), 0.0)
	draw_circle(back, radius, fill)
	draw_arc(back, radius, 0.0, TAU, 32, edge, EDGE_WIDTH)

	# A wrist, so the hand reads as reaching from somewhere rather than floating.
	_capsule(back, back - Vector2(radius * 1.1, 0.0), radius * 1.05, fill, edge)


func _draw_fingers(span: float, fill: Color, edge: Color) -> void:
	var gripping: bool = is_holding()
	var fan: float = FAN_GRIP if gripping else FAN_OPEN
	var curl: float = CURL_GRIP if gripping else CURL_OPEN
	var reach: float = (REACH_GRIP if gripping else REACH_OPEN) * span
	var width: float = span * FINGER_WIDTH
	var knuckle: Vector2 = Vector2(-span * KNUCKLE_BACK, 0.0)

	for i: int in FINGERS:
		var angle: float = (float(i) / float(FINGERS - 1) - 0.5) * fan * 2.0
		# Two segments: out from the knuckle, then a tip bent back toward the
		# centreline. That bend is the whole difference between open and shut.
		var joint: Vector2 = knuckle + Vector2.RIGHT.rotated(angle) * reach * KNUCKLE_SHARE
		var tip: Vector2 = joint \
				+ Vector2.RIGHT.rotated(angle - signf(angle) * curl) * reach * (1.0 - KNUCKLE_SHARE)
		_capsule(knuckle, joint, width, fill, edge)
		_capsule(joint, tip, width * 0.85, fill, edge)

	# Thumb: shorter, off to one side, and the piece that closes across the grip.
	var thumb_width: float = span * THUMB_WIDTH
	var thumb_angle: float = 0.85 if gripping else 1.15
	var thumb_joint: Vector2 = knuckle + Vector2.RIGHT.rotated(thumb_angle) * reach * 0.42
	var thumb_tip: Vector2 = thumb_joint \
			+ Vector2.RIGHT.rotated(thumb_angle - (1.0 if gripping else 0.25)) * reach * 0.32
	_capsule(knuckle, thumb_joint, thumb_width, fill, edge)
	_capsule(thumb_joint, thumb_tip, thumb_width * 0.85, fill, edge)


## A rounded bar between two points. Godot's line caps are square, so the ends
## are circles - which also rounds off the joint where two segments meet.
func _capsule(from: Vector2, to: Vector2, width: float, fill: Color, edge: Color) -> void:
	draw_line(from, to, fill, width)
	draw_circle(from, width * 0.5, fill)
	draw_circle(to, width * 0.5, fill)
	draw_arc(to, width * 0.5, 0.0, TAU, 12, edge, EDGE_WIDTH * 0.7)
