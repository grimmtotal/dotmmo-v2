extends RefCounted

## A character's appearance: particles poured into the outline of a body.
##
## Nothing here is simulated. A segment has a capacity in slots, you put N
## particles of a material into it, and N slots take that material's colour -
## half an arm's worth of Emerald fills half the arm. The whole appearance is a
## count per material per segment, a few dozen bytes, which is what makes it
## cheap enough to send everyone in a world every player's exact look.
##
## A slot is deliberately tiny next to a world cell. A world cell is drawn at 64
## screen pixels and a slot at 2, so a full body costs a few hundred blocks of
## material to colour a figure 48 pixels tall. That ratio is the point: the
## conspicuous waste is the status signal, and it explains itself without any UI.

const Particles = preload("res://Scripts/Singletons/Particles.gd")

## Screen pixels per slot, and the body in slots. One particle fills one slot.
const SLOT: int = 2
const BODY: Vector2i = Vector2i(24, 24)

## Segments, in slots. Left and right are the viewer's, not the character's.
##
## Eyes sit over the head rather than being cut out of it, so the head keeps a
## simple rectangle to fill and the eyes read as their own colour on top.
const SEGMENTS: Dictionary = {
	"torso": Rect2i(8, 9, 8, 8),
	"left_arm": Rect2i(5, 9, 3, 8),
	"right_arm": Rect2i(16, 9, 3, 8),
	"left_leg": Rect2i(9, 17, 3, 7),
	"right_leg": Rect2i(13, 17, 3, 7),
	"neck": Rect2i(10, 8, 4, 1),
	"head": Rect2i(8, 0, 8, 8),
	"left_eye": Rect2i(9, 3, 2, 2),
	"right_eye": Rect2i(13, 3, 2, 2),
}

## Painted in this order, so the head covers the neck and the eyes the head.
const DRAW_ORDER: Array = [
	"torso", "left_arm", "right_arm", "left_leg", "right_leg",
	"neck", "head", "left_eye", "right_eye",
]

const OUTLINE: Color = Color(0.62, 0.66, 0.71, 0.85)

# segment name -> { material name: slot count }
var _fill: Dictionary = {}


func _init() -> void:
	for segment: String in SEGMENTS:
		_fill[segment] = {}


# ------------------------------------------------------------------ capacities

static func capacity(segment: String) -> int:
	if not SEGMENTS.has(segment):
		return 0
	var rect: Rect2i = SEGMENTS[segment]
	return rect.size.x * rect.size.y


static func total_capacity() -> int:
	var total: int = 0
	for segment: String in SEGMENTS:
		total += capacity(segment)
	return total


func filled(segment: String) -> int:
	var used: int = 0
	for material: String in _fill.get(segment, {}):
		used += int((_fill[segment] as Dictionary)[material])
	return used


func space_left(segment: String) -> int:
	return capacity(segment) - filled(segment)


func contents(segment: String) -> Dictionary:
	return (_fill.get(segment, {}) as Dictionary).duplicate()


# --------------------------------------------------------------------- filling

## Puts up to `count` particles into a segment, returning how many went in.
## A segment that is already full takes none, so the caller can hand back
## whatever did not fit rather than destroying it.
func add(segment: String, material: String, count: int) -> int:
	if not SEGMENTS.has(segment) or not Particles.TYPES.has(material) or count <= 0:
		return 0

	var accepted: int = mini(count, space_left(segment))
	if accepted <= 0:
		return 0

	var held: Dictionary = _fill[segment]
	held[material] = int(held.get(material, 0)) + accepted
	return accepted


## Takes particles back out, returning how many came back. Filling is
## reversible: what goes into a body can be worn for a while and then sold, so
## a full set of cosmetics is wealth parked in view rather than wealth spent.
func remove(segment: String, material: String, count: int) -> int:
	if not SEGMENTS.has(segment) or count <= 0:
		return 0

	var held: Dictionary = _fill[segment]
	var have: int = int(held.get(material, 0))
	var returned: int = mini(count, have)
	if returned <= 0:
		return 0

	if returned == have:
		held.erase(material)
	else:
		held[material] = have - returned
	return returned


## Empties the whole body, returning every particle as a material -> count
## tally the caller can pay back.
func remove_all() -> Dictionary:
	var refund: Dictionary = {}
	for segment: String in SEGMENTS:
		for material: String in (_fill[segment] as Dictionary):
			refund[material] = int(refund.get(material, 0)) + int((_fill[segment] as Dictionary)[material])
		_fill[segment] = {}
	return refund


# ------------------------------------------------------------------- rendering

## Paints the body into an image, ready to hand to a sprite.
##
## This is a pure function of the counts above, so there is no layout to store
## or keep in sync - and it only needs running when someone changes what they
## are wearing, never per frame.
func build_image() -> Image:
	var image: Image = Image.create(BODY.x * SLOT, BODY.y * SLOT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for segment: String in DRAW_ORDER:
		_paint_segment(image, segment)

	return image


func _paint_segment(image: Image, segment: String) -> void:
	var rect: Rect2i = SEGMENTS[segment]
	var slots: int = rect.size.x * rect.size.y

	# Denser material settles to the bottom of a segment, the same rule the
	# world runs on. Deriving the order from density rather than from the order
	# things were added means the layout never has to be stored - the picture is
	# always recoverable from the counts alone.
	var materials: Array = (_fill[segment] as Dictionary).keys()
	materials.sort_custom(func(a: String, b: String) -> bool:
		return _density(a) > _density(b))

	var slot: int = 0
	for material: String in materials:
		var colours: Array = Particles.get_config(material).get("colors", [])
		var count: int = int((_fill[segment] as Dictionary)[material])
		for i: int in count:
			if slot >= slots:
				break
			# Bottom-up, and relative to the segment rather than the world, so a
			# limb swinging in an animation does not slosh.
			var x: int = rect.position.x + (slot % rect.size.x)
			var y: int = rect.position.y + rect.size.y - 1 - (slot / rect.size.x)
			_paint_slot(image, x, y, _variant(colours, x, y))
			slot += 1

	_paint_outline(image, rect)


## Materials carry two or three near-identical colours. Picking between them per
## slot, from the slot's own position, makes a filled limb read as packed grains
## instead of a flat swatch - for no stored state and no cost.
static func _variant(colours: Array, x: int, y: int) -> Color:
	if colours.is_empty():
		return Color.MAGENTA
	var hash: int = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	hash = ((hash ^ (hash >> 13)) * 1274126177) & 0xFFFFFFFF
	hash = (hash ^ (hash >> 16)) & 0xFFFFFFFF
	return Color(colours[hash % colours.size()])


static func _density(material: String) -> float:
	return float(Particles.get_config(material).get("density", 1.0))


static func _paint_slot(image: Image, slot_x: int, slot_y: int, colour: Color) -> void:
	for dy: int in SLOT:
		for dx: int in SLOT:
			image.set_pixel(slot_x * SLOT + dx, slot_y * SLOT + dy, colour)


## The empty body is an outline, so a half-filled arm reads as a vessel someone
## is still filling rather than as a broken sprite.
static func _paint_outline(image: Image, rect: Rect2i) -> void:
	var x0: int = rect.position.x * SLOT
	var y0: int = rect.position.y * SLOT
	var x1: int = x0 + rect.size.x * SLOT - 1
	var y1: int = y0 + rect.size.y * SLOT - 1

	for x: int in range(x0, x1 + 1):
		_blend(image, x, y0)
		_blend(image, x, y1)
	for y: int in range(y0 + 1, y1):
		_blend(image, x0, y)
		_blend(image, x1, y)


## Drawn over whatever is underneath, so an outline never erases a filled slot.
static func _blend(image: Image, x: int, y: int) -> void:
	var under: Color = image.get_pixel(x, y)
	if under.a <= 0.0:
		image.set_pixel(x, y, OUTLINE)
	else:
		image.set_pixel(x, y, under.lerp(OUTLINE, 0.35))
