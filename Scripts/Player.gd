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

## Collision box, in screen pixels, derived from the figure that gets drawn so
## the two can never drift apart - change CharacterCosmetics.SLOT and the body
## you walk with resizes along with the body you see.
##
## As wide as the torso rather than as wide as the sprite: the arms hang outside
## the box on purpose, so a gap you can see through is one you fit through.
const SPRITE_SIZE: Vector2 = Vector2(
	CharacterCosmetics.BODY.x * CharacterCosmetics.SLOT,
	CharacterCosmetics.BODY.y * CharacterCosmetics.SLOT)
const BODY_WIDTH: float = 8.0 * CharacterCosmetics.SLOT
const BODY_HEIGHT: float = SPRITE_SIZE.y

## Where the sprite sits relative to `position`, which is the middle of the feet.
const SPRITE_OFFSET: Vector2 = Vector2(-SPRITE_SIZE.x * 0.5, -SPRITE_SIZE.y)

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

## Longest frame the physics will integrate in one go. A hitch that moved the
## body further than a cell could put it through a wall, so a slow frame is
## taken as a short one instead - the body lags rather than tunnelling.
const MAX_STEP: float = 1.0 / 30.0

## Pulled back off the surface it lands on, so the body rests just clear of a
## cell rather than exactly on the boundary, where a rounding error either way
## reads as either sinking in or floating.
const SKIN: float = 0.01

## How the body gets itself out when the world closes on it.
##
## Nothing tells the simulation the character is there, so matter falls straight
## through it: stand under a sand shelf you have just dug out and the sand
## settles inside your own collision box. Before this the body simply froze -
## every direction it tried to move was blocked, both axes snapped and zeroed
## their velocity, and that was permanent. It could not walk, fall or jump out.
##
## So each frame starts by checking whether the body is inside anything, and if
## it is, looking for a position that is clear - exhausting every distance
## upward before it will consider any other direction.
##
## Up wins outright rather than merely winning ties, and that ordering is the
## whole safety property. Taking the nearest escape instead sounds better and is
## not: a body embedded in a thin floor has open air a short way down and solid
## ground a long way up, so nearest drops it through the floor. Preferring up
## absolutely means the only way to be pushed downward is for there to be no way
## up at all within reach.
const UNSTICK_STEP: float = 4.0
const UNSTICK_REACH_CELLS: float = 4.0

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

var velocity: Vector2 = Vector2.ZERO
var cosmetics: CharacterCosmetics

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
	_unstick()

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


## Looks for the nearest clear position when the body is inside something, and
## does nothing at all when it is not - which is every ordinary frame.
func _unstick() -> void:
	if not _blocked(position):
		return

	var reach: float = UNSTICK_REACH_CELLS * float(Global.WORLD_PIXEL_SCALE)
	var steps: int = int(reach / UNSTICK_STEP)

	# Every distance upward first. Matter falls, so overhead is nearly always
	# where the room is, and coming out on top of what buried you reads as
	# climbing out.
	for i: int in range(1, steps + 1):
		var lift: float = float(i) * UNSTICK_STEP
		if not _blocked(position - Vector2(0.0, lift)):
			position.y -= lift
			velocity.y = minf(velocity.y, 0.0)
			return

	# Then sideways, nearer side first, for a body pinned under a solid ceiling.
	for i: int in range(1, steps + 1):
		var shift: float = float(i) * UNSTICK_STEP
		if not _blocked(position + Vector2(shift, 0.0)):
			position.x += shift
			return
		if not _blocked(position - Vector2(shift, 0.0)):
			position.x -= shift
			return

	# Downward only when there is no way up or out at all.
	for i: int in range(1, steps + 1):
		var drop: float = float(i) * UNSTICK_STEP
		if not _blocked(position + Vector2(0.0, drop)):
			position.y += drop
			return


## Moves along one axis in hops no longer than half a cell, so a fast move
## cannot pass through a block without being tested against it, and stops dead
## at the face of the first thing it meets.
func _move_x(amount: float) -> void:
	if is_zero_approx(amount):
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	for hop: float in _hops(amount, scale):
		var target: float = position.x + hop
		if not _blocked(Vector2(target, position.y)):
			position.x = target
			continue

		if hop > 0.0:
			position.x = floorf((target + BODY_WIDTH * 0.5) / scale) * scale \
					- BODY_WIDTH * 0.5 - SKIN
		else:
			position.x = (floorf((target - BODY_WIDTH * 0.5) / scale) + 1.0) * scale \
					+ BODY_WIDTH * 0.5 + SKIN
		velocity.x = 0.0
		return


func _move_y(amount: float) -> void:
	if is_zero_approx(amount):
		return

	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	for hop: float in _hops(amount, scale):
		var target: float = position.y + hop
		if not _blocked(Vector2(position.x, target)):
			position.y = target
			continue

		if hop > 0.0:
			position.y = floorf(target / scale) * scale - SKIN
			_on_ground = true
		else:
			position.y = (floorf((target - BODY_HEIGHT) / scale) + 1.0) * scale \
					+ BODY_HEIGHT + SKIN
		velocity.y = 0.0
		return


## Splits a move into equal hops of at most half a cell.
func _hops(amount: float, scale: float) -> PackedFloat32Array:
	var count: int = maxi(1, ceili(absf(amount) / (scale * 0.5)))
	var hop: float = amount / float(count)
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(hop)
	return out


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
#
# The body only supplies a direction now. It used to also cast a ray out to a
# reach and hand back the cell at the end of it, which put the tools on a leash
# hanging off the character - the box lagged behind the pointer and sat at the
# end of a visible line. Tools go where the pointer goes; the guns take the
# direction from here and their own flight decides the rest.

## The middle of the body, and where a shot leaves from.
func centre() -> Vector2:
	return position - Vector2(0.0, BODY_HEIGHT * 0.5)


func aim_direction() -> Vector2:
	var to_pointer: Vector2 = get_global_mouse_position() - centre()
	if to_pointer.length_squared() < 1.0:
		return Vector2.LEFT if _facing_left else Vector2.RIGHT
	return to_pointer.normalized()
