extends Node2D

## The character you play as: a body that walks the world the sand falls
## through, and the thing the box and the guns now point from.
##
## The body is deliberately smaller than a cell - 48 screen pixels against a
## 64-pixel block - which is what makes a block something you stand on, shelter
## behind or have to break, rather than something you wade through. It also
## makes collision cheap: a body that size can never straddle more than two
## cells on an axis, so resolving a move is a snap to a cell edge rather than a
## search.
##
## Nothing here is simulated as particles. The body moves as one rigid box
## against the cell grid, and its *appearance* is the only part made of
## materials - CharacterCosmetics pours particles into the outline of a figure,
## so what you are wearing is a tally of what you have collected.

const CharacterCosmetics = preload("res://Scripts/CharacterCosmetics.gd")

## Collision box, in screen pixels. Narrower than the sprite on purpose: the
## arms hang outside it, so a doorway you can see through is one you fit through.
const BODY_WIDTH: float = 16.0
const BODY_HEIGHT: float = 48.0

## Where the sprite sits relative to `position`, which is the middle of the feet.
const SPRITE_OFFSET: Vector2 = Vector2(-24.0, -48.0)

const GRAVITY: float = 2200.0
const MAX_FALL: float = 1400.0
const WALK_SPEED: float = 260.0

## Enough to clear a block and a half. A body shorter than a cell cannot step up
## onto one, so every ledge in the world is a jump, and the jump has to be worth
## making.
const JUMP_SPEED: float = 700.0

## Liquids do not block, so a body in water sinks - slowly, and with the jump
## key working as a swim stroke, or falling into your own pond would be fatal in
## a game that has no way to die yet.
const LIQUID_GRAVITY: float = 0.22
const LIQUID_DRAG: float = 6.0
const SWIM_SPEED: float = -180.0

## How far the box reaches, in cells. Short enough that getting to
## somewhere is a real part of doing anything to it.
const REACH_CELLS: int = 6

## Resolution of the aim raycast, as a fraction of a cell. Quarter-cell steps
## cannot skip a block, since a block is four steps wide.
const RAY_STEP: float = 0.25

## Longest frame the physics will integrate in one go. A hitch that moved the
## body further than a cell could put it through a wall, so a slow frame is
## taken as a short one instead - the body lags rather than tunnelling.
const MAX_STEP: float = 1.0 / 30.0

## Pulled back off the surface it lands on, so the body rests just clear of a
## cell rather than exactly on the boundary, where a rounding error either way
## reads as either sinking in or floating.
const SKIN: float = 0.01

## What a fresh character is wearing. The empty body is only an outline - by
## design, so a half-filled limb reads as a vessel someone is still filling -
## which is invisible at any sensible zoom, so a new one starts with enough in
## it to read as a figure. Placeholder: this is what a character-creation screen
## would set.
const STARTING_FILL: Dictionary = {
	"torso": "Stone",
	"left_arm": "Stone",
	"right_arm": "Stone",
	"left_leg": "Rubble",
	"right_leg": "Rubble",
	"neck": "Sand",
	"head": "Sand",
	"left_eye": "Water",
	"right_eye": "Water",
}

const AIM_LINE: Color = Color(1, 1, 1, 0.22)
const AIM_WIDTH: float = 2.0

## How long the aim line runs for a tool with no reach limit. A gun's shot goes
## as far as its flight takes it, so the line is a direction indicator rather
## than a statement about range - drawing it out to the box's reach would be a
## lie about where the shot lands.
const AIM_RAY_CELLS: float = 3.5

var velocity: Vector2 = Vector2.ZERO
var cosmetics: CharacterCosmetics

## Whether a tool that aims from the body is selected, which is the only time
## the aim line is worth drawing.
var aiming: bool = false:
	set(value):
		if value == aiming:
			return
		aiming = value
		queue_redraw()

## Whether the aim line should stop where the reach does. True for the box,
## which can only touch what it can get to; false for the guns, which cannot.
var aim_shows_reach: bool = true

var _sprite: Sprite2D
var _on_ground: bool = false
var _facing_left: bool = false


func _ready() -> void:
	cosmetics = CharacterCosmetics.new()
	for segment: String in STARTING_FILL:
		cosmetics.add(segment, STARTING_FILL[segment],
			CharacterCosmetics.capacity(segment))

	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = SPRITE_OFFSET
	add_child(_sprite)
	refresh_appearance()


## Rebuilds the body image. Only needed when what the character is wearing
## changes - never per frame.
func refresh_appearance() -> void:
	_sprite.texture = ImageTexture.create_from_image(cosmetics.build_image())


# ---------------------------------------------------------------------- moving

func _physics_process(delta: float) -> void:
	var step: float = minf(delta, MAX_STEP)
	var in_liquid: bool = _is_submerged()

	_apply_input(step, in_liquid)
	_apply_gravity(step, in_liquid)

	_move_x(velocity.x * step)
	_move_y(velocity.y * step)
	_update_ground()
	_update_facing()


func _apply_input(step: float, in_liquid: bool) -> void:
	var direction: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += 1.0

	velocity.x = direction * WALK_SPEED

	var jump: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) \
			or Input.is_key_pressed(KEY_UP)
	if not jump:
		return

	if in_liquid:
		# Held rather than tapped: swimming is a steady climb, not a leap.
		velocity.y = SWIM_SPEED
	elif _on_ground:
		velocity.y = -JUMP_SPEED
		_on_ground = false


func _apply_gravity(step: float, in_liquid: bool) -> void:
	if in_liquid:
		velocity.y += GRAVITY * LIQUID_GRAVITY * step
		velocity.y = lerpf(velocity.y, 0.0, minf(LIQUID_DRAG * step, 1.0))
		return

	velocity.y = minf(velocity.y + GRAVITY * step, MAX_FALL)


## Moves horizontally, snapping to the edge of whatever it runs into. The body
## is narrower than a cell, so a blocked move can only ever be against one
## boundary and the correction is exact.
func _move_x(amount: float) -> void:
	if is_zero_approx(amount):
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var target: float = position.x + amount
	if not _blocked(Vector2(target, position.y)):
		position.x = target
		return

	if amount > 0.0:
		position.x = floorf((target + BODY_WIDTH * 0.5) / scale) * scale \
				- BODY_WIDTH * 0.5 - SKIN
	else:
		position.x = (floorf((target - BODY_WIDTH * 0.5) / scale) + 1.0) * scale \
				+ BODY_WIDTH * 0.5 + SKIN
	velocity.x = 0.0


func _move_y(amount: float) -> void:
	if is_zero_approx(amount):
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var target: float = position.y + amount
	if not _blocked(Vector2(position.x, target)):
		position.y = target
		return

	if amount > 0.0:
		position.y = floorf(target / scale) * scale - SKIN
		_on_ground = true
	else:
		position.y = (floorf((target - BODY_HEIGHT) / scale) + 1.0) * scale \
				+ BODY_HEIGHT + SKIN
	velocity.y = 0.0


## The body's box with its feet at `feet`.
func _box_at(feet: Vector2) -> Rect2:
	return Rect2(
		Vector2(feet.x - BODY_WIDTH * 0.5, feet.y - BODY_HEIGHT),
		Vector2(BODY_WIDTH, BODY_HEIGHT))


func _blocked(feet: Vector2) -> bool:
	return _box_blocked(_box_at(feet))


func _box_blocked(box: Rect2) -> bool:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var x0: int = floori(box.position.x / scale)
	var x1: int = floori((box.position.x + box.size.x - SKIN) / scale)
	var y0: int = floori(box.position.y / scale)
	var y1: int = floori((box.position.y + box.size.y - SKIN) / scale)

	for cell_y: int in range(y0, y1 + 1):
		for cell_x: int in range(x0, x1 + 1):
			if SimulationGlobal.isBlocking(Vector2i(cell_x, cell_y)):
				return true
	return false


## Standing is tested against a sliver under the feet rather than remembered
## from the last landing, so walking off a ledge takes the ground away at once.
func _update_ground() -> void:
	var box: Rect2 = _box_at(position)
	box.position.y += BODY_HEIGHT
	box.size.y = SKIN * 4.0
	_on_ground = _box_blocked(box)


func _update_facing() -> void:
	var facing_left: bool = aim_direction().x < 0.0
	if facing_left == _facing_left:
		return
	_facing_left = facing_left
	_sprite.flip_h = facing_left
	# flip_h mirrors about the sprite's own origin, so the offset has to follow
	# it or the body jumps sideways when it turns.
	_sprite.position = Vector2(
		-SPRITE_OFFSET.x if facing_left else SPRITE_OFFSET.x, SPRITE_OFFSET.y)


func _is_submerged() -> bool:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var middle: Vector2 = centre()
	return SimulationGlobal.isLiquidAt(Vector2i(
		floori(middle.x / scale), floori(middle.y / scale)))


# ---------------------------------------------------------------------- aiming

## The middle of the body, which is where a reach is measured from and where the
## aim line starts.
func centre() -> Vector2:
	return position - Vector2(0.0, BODY_HEIGHT * 0.5)


func aim_direction() -> Vector2:
	var to_pointer: Vector2 = get_global_mouse_position() - centre()
	if to_pointer.length_squared() < 1.0:
		return Vector2.LEFT if _facing_left else Vector2.RIGHT
	return to_pointer.normalized()


## The cell the body is aiming at: the first one along the aim that stops a
## reach, or the furthest one within it when nothing does.
##
## Stopping at the first blocking cell is what makes reach mean something. You
## cannot pour fire through a wall or lift sand from the far side of one, and
## the breaker lands on the face of the rock it is pointed at, which is exactly
## the cell you want to be digging out.
func target_cell() -> Vector2:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var origin: Vector2 = centre()
	var direction: Vector2 = aim_direction()
	var reach: float = float(REACH_CELLS) * scale
	var step: float = scale * RAY_STEP

	var furthest: Vector2 = Vector2(floorf(origin.x / scale), floorf(origin.y / scale))
	var travelled: float = step
	while travelled <= reach:
		var point: Vector2 = origin + direction * travelled
		var cell: Vector2 = Vector2(floorf(point.x / scale), floorf(point.y / scale))
		if SimulationGlobal.isBlocking(Vector2i(cell)):
			return cell
		furthest = cell
		travelled += step

	return furthest


func _process(_delta: float) -> void:
	if aiming:
		queue_redraw()


func _draw() -> void:
	if not aiming:
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var from: Vector2 = centre()
	var to: Vector2 = from + aim_direction() * AIM_RAY_CELLS * scale
	if aim_shows_reach:
		to = (target_cell() + Vector2(0.5, 0.5)) * scale
	draw_line(to_local(from), to_local(to), AIM_LINE, AIM_WIDTH)
