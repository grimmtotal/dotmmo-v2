extends Node2D

## Shots in flight, and what they do when they land.
##
## A fired particle cannot be a world cell while it is travelling. The
## simulation gives every material one fixed way of moving - fall, rise, flow,
## sit still - chosen from its type and shared by every grain of it, and there
## is no per-cell velocity anywhere in the grid to override that with. Putting
## one in would cost bytes on all 62,500 cells and a branch in the hot loop, to
## serve the handful of grains that are ever actually in the air.
##
## So a shot lives out here instead: a position, a velocity and a gravity of its
## own, owned by this node and drawn by it, with the grid knowing nothing about
## it until it arrives. On impact it becomes an ordinary particle in the cell it
## stopped at and the simulation takes over from there - which is why a fireball
## that lands in a plant bed sets it alight and one that lands in water turns to
## steam without a line here saying so. The reactions already exist; a shot only
## has to deliver the material to the right cell.
##
## What flies is the particle itself, not a marker for one. A shot carries a
## packed type-and-variant rolled at the muzzle - the same value the box hands
## around - is drawn at full cell size in that variant's own colour, and is put
## down with that exact byte when it lands. So the block you watched leave the
## barrel is the block that ends up in the ground, in the same shade, and there
## is no moment where one thing turns into another.
##
## There are never many. A gun firing fifteen a second, each alive under a
## second, keeps a few dozen in the air, so this is a plain array walked in full
## every frame rather than anything cleverer.

## Hard ceiling on shots alive at once, so a held trigger against a distant wall
## cannot grow the array without bound.
const MAX_SHOTS: int = 512

## Longest hop a shot may take between collision tests, as a fraction of a cell.
## Anything below one cell cannot pass through a wall without landing in it at
## least once, and half a cell leaves room for a slow frame.
const SUBSTEP: float = 0.5

## Face shading on a flying block, matching what the cell shader does to a
## settled one - lit along the top, dark underneath - so a particle in the air
## and the same particle on the ground are drawn the same way.
const BEVEL_BAND: float = 0.18
const BEVEL_LIGHT: float = 0.16
const BEVEL_DARK: float = 0.20

## A smear back to where the shot was last frame, at the same colour and width.
## Not a separate object - it is the particle's own motion, and without it a
## fast one strobes between positions instead of reading as travelling.
const TRAIL_ALPHA: float = 0.22

## What a breaker round does to what it hits. Stone is the only thing it works
## on, so it reads as a tool for digging rather than a second eraser.
const BREAKS_FROM: String = "Stone"
const BREAKS_INTO: String = "Rubble"


## One shot in the air.
class Shot:
	extends RefCounted

	var position: Vector2
	var previous: Vector2
	var velocity: Vector2
	var gravity: float
	## Packed type-and-variant, exactly as SimulationGlobal hands them around.
	## Zero for a breaker round, which carries no material of its own.
	var packed: int
	## Breaker rounds convert what they hit instead of leaving anything behind.
	var breaks: bool
	var colour: Color
	var life: float


var _shots: Array[Shot] = []


func count() -> int:
	return _shots.size()


## Puts one shot in the air. `spread` is the half-angle of the cone it may leave
## the muzzle in, in radians, which is what stops a held trigger drawing a
## perfectly straight line of beads.
func fire(from: Vector2, direction: Vector2, config: Dictionary) -> void:
	if _shots.size() >= MAX_SHOTS:
		return

	var spread: float = float(config.get("spread", 0.0))
	var aim: Vector2 = direction.rotated(randf_range(-spread, spread))
	var speed: float = float(config.get("speed", 1000.0)) * randf_range(0.85, 1.15)

	var material: String = String(config.get("material", ""))
	var shot := Shot.new()
	shot.position = from
	shot.previous = from
	shot.velocity = aim * speed
	shot.gravity = float(config.get("gravity", 0.0))
	shot.breaks = bool(config.get("breaks", false))
	shot.packed = 0 if material.is_empty() else SimulationGlobal.rollParticle(material)
	shot.life = float(config.get("life", 1.2))
	# A breaker round has no material to take a colour from, so it borrows the
	# one it is about to make.
	shot.colour = SimulationGlobal.colorOf(shot.packed) if shot.packed != 0 \
			else SimulationGlobal.colorOf(SimulationGlobal.rollParticle(BREAKS_INTO))

	_shots.append(shot)


func clear() -> void:
	_shots.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _shots.is_empty():
		return

	var alive: Array[Shot] = []
	for shot: Shot in _shots:
		if _advance(shot, delta):
			alive.append(shot)
	_shots = alive
	queue_redraw()


## Walks one shot forward, in hops small enough that it cannot cross a cell
## without being tested against it. Returns whether it is still in the air.
func _advance(shot: Shot, delta: float) -> bool:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var travel: Vector2 = shot.velocity * delta
	var hops: int = maxi(1, ceili(travel.length() / (scale * SUBSTEP)))
	var hop: Vector2 = travel / float(hops)

	shot.previous = shot.position
	for i: int in hops:
		var behind: Vector2i = _cell(shot.position)
		shot.position += hop
		var ahead: Vector2i = _cell(shot.position)
		if ahead == behind:
			continue
		# isVacant is false for anything out of bounds too, so the edge of the
		# world stops a shot the same way a wall does.
		if not SimulationGlobal.isVacant(Vector2(ahead)):
			_land(shot, behind, ahead)
			return false

	shot.velocity.y += shot.gravity * delta
	shot.life -= delta
	if shot.life > 0.0:
		return true

	# Burnt out in mid-air. It still leaves its material behind, so a flame that
	# reaches nothing lights the air where it died rather than vanishing.
	_land(shot, _cell(shot.position), _cell(shot.position))
	return false


## `behind` is the last cell the shot was clear of and `ahead` the one that
## stopped it. Material goes in behind, so a fireball lands on the face of a
## wall rather than inside it; the breaker works on ahead, because the cell that
## stopped it is the one being dug out.
func _land(shot: Shot, behind: Vector2i, ahead: Vector2i) -> void:
	if shot.breaks:
		var hit: Dictionary = SimulationGlobal.getParticle(Vector2(ahead))
		if hit.get("type", "") == BREAKS_FROM:
			SimulationGlobal.despawnParticle(Vector2(ahead))
			SimulationGlobal.spawnExactly(BREAKS_INTO, Vector2(ahead))
		return

	if shot.packed != 0:
		# The exact particle that was in the air, in the exact cell the flight
		# decided - no scatter, and no re-rolled colour.
		SimulationGlobal.releaseParticle(Vector2(behind), shot.packed)


func _cell(point: Vector2) -> Vector2i:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	return Vector2i(floori(point.x / scale), floori(point.y / scale))


func _draw() -> void:
	var scale: float = float(Global.WORLD_PIXEL_SCALE)
	var half := Vector2(scale, scale) * 0.5

	for shot: Shot in _shots:
		var trail: Color = shot.colour
		trail.a = TRAIL_ALPHA
		draw_line(shot.previous, shot.position, trail, scale)

		var block := Rect2(shot.position - half, Vector2(scale, scale))
		draw_rect(block, shot.colour, true)

		# The same lit-top, dark-bottom face the cell shader gives a settled
		# block, so a particle does not change how it is drawn when it lands.
		var band: float = scale * BEVEL_BAND
		draw_rect(Rect2(block.position, Vector2(scale, band)),
			shot.colour.lightened(BEVEL_LIGHT), true)
		draw_rect(Rect2(block.position + Vector2(0.0, scale - band), Vector2(scale, band)),
			shot.colour.darkened(BEVEL_DARK), true)
