extends Node

## Flat-array falling-sand simulation.
##
## Cells live in padded PackedByteArrays indexed as `i = (y + 1) * _pw + (x + 1)`.
## The one-cell border is filled with WALL, so movement never needs a bounds
## check: the edge of the world simply blocks like any other solid.
##
## Exactly one particle occupies a cell. Displacement (gas rising through water,
## lava sinking through water) is done by swapping the two cells.
##
## There are no per-particle objects. A particle *is* its cell: a type id, a
## colour variant, a life counter, a repeating-timer counter and a flow
## direction, one entry each in parallel arrays.

const Particles = preload("res://Scripts/Singletons/Particles.gd")

# Reserved type ids. Real materials start at FIRST_TYPE.
const EMPTY: int = 0
const WALL: int = 1
const FIRST_TYPE: int = 2

## How much of the variant byte the colour index gets. The rest is the render
## seed. Three bits caps a material at 8 colours, which is five more than the
## most colourful one uses.
const VARIANT_BITS: int = 3
const VARIANT_MASK: int = (1 << VARIANT_BITS) - 1
const SEED_RANGE: int = 1 << (8 - VARIANT_BITS)

# Movement classes.
const MOVE_STATIC: int = 0
const MOVE_FALL: int = 1
const MOVE_LIQUID: int = 2
const MOVE_RISE: int = 3

# Adaptive pacing: ease the tick rate down as the world gets busy so a heavy
# scene degrades in smoothness rather than collapsing into a slideshow.
const TICK_HZ_MAX: float = 60.0
const TICK_HZ_MIN: float = 30.0
const ADAPT_FROM: int = 6000
const ADAPT_TO: int = 30000
const MAX_TICKS_PER_FRAME: int = 2

# Timers are counted in 60Hz-equivalent ticks so durations stay constant in real
# time even when the tick rate drops.
#
# The counters are 32-bit rather than packed into a byte alongside the rest of
# the cell state. A byte caps a duration at 255 ticks, or ~4.2s, and anything
# longer was silently clamped to that - a 40s timer quietly became a 4.2s one,
# with nothing in the authored config to show for it. The cap below is only a
# guard against a typo running away with a counter, not a design limit.
const MAX_TIMER: int = 60 * 60 * 60  # one hour at 60Hz

# Cells per chunk edge. Chunks are the unit the renderer redraws in: a step that
# disturbs one corner of the world uploads that corner, not the whole buffer.
#
# A power of two so a cell's chunk comes out of a shift rather than a division -
# this is worked out inline at every cell write, which is the hottest path there
# is. 32 keeps a chunk's pixels (1KB per buffer) comfortably inside a cache line
# run while staying coarse enough that a busy world dirties tens of chunks, not
# thousands.
const CHUNK_SHIFT: int = 5
const CHUNK: int = 1 << CHUNK_SHIFT

# Reaction probabilities are fixed-point over this range; CERTAIN always fires.
const CHANCE_MASK: int = 0xFFFF
const CERTAIN: int = 0x10000

signal world_cleared

# --- Cell state (padded, parallel arrays) ---
var _type: PackedByteArray
# Colour variant in the low VARIANT_BITS, a per-particle render seed above it.
# Both travel with the particle when it moves, which is the whole point of
# keeping the seed here rather than deriving it from the cell position: a
# falling grain keeps the shade it was born with instead of flickering through
# every shade on the way down.
var _variant: PackedByteArray
var _life: PackedInt32Array
var _timer: PackedInt32Array
var _flow: PackedByteArray
var _clock: PackedByteArray

# --- Active list of flat cell indices, with a per-cell dedupe flag ---
var _active: PackedInt32Array
var _active_n: int = 0
var _queued: PackedByteArray

# The renderer reads `_type` and `_variant` directly (uploaded as textures and
# coloured on the GPU), so the simulation does no pixel work at all - it only
# records which chunks changed.
#
# `_chunk_dirty` is the per-chunk dedupe flag and `_dirty_chunks` the list to
# hand out, exactly the arrangement the active list uses for cells. The list can
# never outgrow the chunk count, since a chunk is only added while its flag is
# clear, so it is sized once and never resized.
var _chunk_dirty: PackedByteArray
var _dirty_chunks: PackedInt32Array
var _dirty_n: int = 0
var _chunks_x: int
var _chunks_y: int

# --- Type tables, indexed by type id ---
var _t_name: PackedStringArray = PackedStringArray()
var _t_ids: Dictionary = {}
var _t_move: PackedByteArray
var _t_solid: PackedByteArray
var _t_liquid: PackedByteArray
var _t_reactive: PackedByteArray
var _t_density: PackedFloat32Array
var _t_variants: PackedByteArray
# Four bytes per type - grain, glow, bevel, alpha - handed to the shader as a
# lookup row. See the "look" block in Particles.gd for what each one does.
var _t_look: PackedByteArray
var _t_colour_base: PackedInt32Array
var _t_colours: PackedInt64Array
var _t_spread_x: PackedInt32Array
var _t_spread_y: PackedInt32Array

# Timer durations, as the inclusive tick range a particle rolls within when it
# is created. A range of zero means the material has no timer of that kind.
#
# The life timer runs once and ends the particle; the repeat timer runs over and
# over and leaves it alone, spawning its products beside it each time it comes
# round. Their products (Fire -> Smoke on death, Lava -> Fire on repeat) are
# kept out of the packed arrays because most materials spawn nothing at all.
var _t_life_min: PackedInt32Array
var _t_life_max: PackedInt32Array
var _t_death_spawn: Dictionary = {}
var _t_every_min: PackedInt32Array
var _t_every_max: PackedInt32Array
var _t_every_spawn: Dictionary = {}

# Reactions. `_react_mask[(a << 8) | b]` is 1 when material `a` responds to
# touching material `b`; the details then come out of `_react`.
var _react_mask: PackedByteArray
var _react: Dictionary = {}

var _w: int
var _h: int
var _pw: int
var _ph: int
var _cells: int

var _tick: int = 0
var _tick_hz: float = TICK_HZ_MAX
var _life_step: int = 1
var _accumulator: float = 0.0
var _count: int = 0


func _ready() -> void:
	_build_types()

	_w = Global.WORLD_WIDTH
	_h = Global.WORLD_HEIGHT
	_pw = _w + 2
	_ph = _h + 2
	_cells = _pw * _ph

	# The last chunk in a row or column is short when the world is not a whole
	# number of chunks across; `chunkRect` reports each chunk's real extent.
	_chunks_x = (_w + CHUNK - 1) >> CHUNK_SHIFT
	_chunks_y = (_h + CHUNK - 1) >> CHUNK_SHIFT
	_chunk_dirty.resize(_chunks_x * _chunks_y)
	_dirty_chunks.resize(_chunks_x * _chunks_y)

	_active.resize(8192)
	clearAll()


# ---------------------------------------------------------------- type tables

func _build_types() -> void:
	var names: Array = Particles.TYPES.keys()
	var total: int = names.size() + FIRST_TYPE

	_t_name.resize(total)
	_t_move.resize(total)
	_t_solid.resize(total)
	_t_liquid.resize(total)
	_t_reactive.resize(total)
	_t_density.resize(total)
	_t_life_min.resize(total)
	_t_life_max.resize(total)
	_t_every_min.resize(total)
	_t_every_max.resize(total)
	_t_variants.resize(total)
	_t_look.resize(total * 4)
	_t_colour_base.resize(total)
	_t_spread_x.resize(total)
	_t_spread_y.resize(total)

	_react_mask.resize(65536)
	_react_mask.fill(0)

	# EMPTY and WALL share a transparent entry; walls are never painted.
	_t_colours.append(0)
	_t_name[WALL] = "Wall"
	_t_solid[WALL] = 1
	_t_variants[EMPTY] = 1
	_t_variants[WALL] = 1

	# Names must all be registered before reactions can be resolved.
	for offset: int in names.size():
		var id: int = FIRST_TYPE + offset
		_t_ids[names[offset]] = id
		_t_name[id] = names[offset]

	for offset: int in names.size():
		_configure_type(FIRST_TYPE + offset, Particles.get_config(names[offset]))


func _configure_type(id: int, config: Dictionary) -> void:
	var solid: bool = config.get("solid", false)
	var liquid: bool = config.get("liquid", false)
	var gravity: Vector2 = config.get("initialGravity", Vector2.ZERO)

	_t_solid[id] = 1 if solid else 0
	_t_liquid[id] = 1 if liquid else 0
	_t_density[id] = float(config.get("density", 1.0))
	var spread: Vector2i = config.get("spread", Vector2i.ZERO)
	_t_spread_x[id] = spread.x
	_t_spread_y[id] = spread.y
	var life: Vector2i = _timer_ticks(config, "despawn")
	_t_life_min[id] = life.x
	_t_life_max[id] = life.y
	_t_death_spawn[id] = _timer_spawn(config, "despawn")

	var every: Vector2i = _timer_ticks(config, "every")
	_t_every_min[id] = every.x
	_t_every_max[id] = every.y
	_t_every_spawn[id] = _timer_spawn(config, "every")

	if liquid:
		_t_move[id] = MOVE_LIQUID
	elif gravity.y < 0.0:
		_t_move[id] = MOVE_RISE
	elif gravity.y > 0.0:
		_t_move[id] = MOVE_FALL
	else:
		_t_move[id] = MOVE_STATIC

	var look: Dictionary = config.get("look", {})
	_t_look[id * 4] = _to_byte(look.get("grain", 0.0))
	_t_look[id * 4 + 1] = _to_byte(look.get("glow", 0.0))
	_t_look[id * 4 + 2] = _to_byte(look.get("bevel", 0.0))
	_t_look[id * 4 + 3] = _to_byte(look.get("alpha", 1.0))

	var colours: Array = config.get("colors", [])
	if colours.size() > VARIANT_MASK + 1:
		push_warning("Too many colours for ", _t_name[id], "; only the first ",
				VARIANT_MASK + 1, " fit the variant byte.")
		colours = colours.slice(0, VARIANT_MASK + 1)
	_t_colour_base[id] = _t_colours.size()
	_t_variants[id] = maxi(colours.size(), 1)
	if colours.is_empty():
		_t_colours.append(_to_rgba32(Color.MAGENTA))
	for value: String in colours:
		_t_colours.append(_to_rgba32(Color(value)))

	_configure_reactions(id, config)


## Collapses the timer table down to a single duration range for one kind of
## timer ("despawn" or "every"). Every material in Particles.gd uses at most one
## timer of each kind, so a pair of per-cell bytes can replace the old
## per-particle timer dictionary.
##
## Durations are authored in milliseconds, either as a single value or as a
## Vector2i(min, max) range that each particle rolls within, so identical
## material spawned in one stroke does not fire in lockstep. A zero range means
## the material has no timer of that kind.
func _timer_ticks(config: Dictionary, key: String) -> Vector2i:
	for timer_name: String in config.get("timers", {}) as Dictionary:
		var value: Variant = ((config["timers"] as Dictionary)[timer_name] as Dictionary).get(key)
		if value is int:
			var fixed: int = _ms_to_ticks(value)
			return Vector2i(fixed, fixed)
		if value is Vector2i:
			return Vector2i(_ms_to_ticks(mini(value.x, value.y)), _ms_to_ticks(maxi(value.x, value.y)))
	return Vector2i.ZERO


func _ms_to_ticks(ms: int) -> int:
	return clampi(roundi(float(ms) * 0.001 * TICK_HZ_MAX), 1, MAX_TIMER)


## Products spawned when one of a material's timers fires: Fire -> Smoke as its
## life runs out, Lava -> Fire each time its bubble timer comes round.
func _timer_spawn(config: Dictionary, key: String) -> PackedByteArray:
	var spawn: PackedByteArray = PackedByteArray()
	for timer_name: String in config.get("timers", {}) as Dictionary:
		var timer: Dictionary = (config["timers"] as Dictionary)[timer_name] as Dictionary
		if timer.get(key) == null:
			continue
		for spawn_name: String in timer.get("spawn", []):
			if _t_ids.has(spawn_name):
				spawn.append(_t_ids[spawn_name])
	return spawn


## Rolls a per-particle duration out of a material's tick range. A material with
## a fixed duration has min == max, so it costs one comparison and no dice.
func _roll(lo: int, hi: int) -> int:
	return lo if hi <= lo else randi_range(lo, hi)


func _configure_reactions(id: int, config: Dictionary) -> void:
	for target: String in config.get("interactions", {}) as Dictionary:
		if not _t_ids.has(target):
			continue

		var inter: Dictionary = (config["interactions"] as Dictionary)[target]
		var destroy: bool = inter["destroy"]
		var reset: bool = not inter["resetTimers"].is_empty() and _t_life_min[id] > 0

		# Held as a 16-bit threshold rather than a float so the roll is one
		# mask and one compare, and so it stays exact when the simulation is
		# eventually made to reproduce bit for bit from a seed.
		var chance: int = clampi(roundi(float(inter.get("chance", 1.0)) * float(CERTAIN)), 0, CERTAIN)

		var spawn: PackedByteArray = PackedByteArray()
		for spawn_name: String in inter["spawn"]:
			if _t_ids.has(spawn_name):
				spawn.append(_t_ids[spawn_name])

		# A reaction that neither destroys, spawns, nor restarts a life timer can
		# never have an observable effect, and one that never rolls true can
		# never happen at all, so both stay out of the hot path.
		if chance == 0 or (not destroy and spawn.is_empty() and not reset):
			continue

		var key: int = (id << 8) | int(_t_ids[target])
		_react_mask[key] = 1
		_react[key] = {"destroy": destroy, "spawn": spawn, "reset": reset, "chance": chance}
		_t_reactive[id] = 1


func _to_byte(value: float) -> int:
	return int(round(clampf(value, 0.0, 1.0) * 255.0))


## Packs to little-endian RGBA8, matching Image.FORMAT_RGBA8 byte order.
func _to_rgba32(colour: Color) -> int:
	return colour.r8 | (colour.g8 << 8) | (colour.b8 << 16) | (colour.a8 << 24)


# ------------------------------------------------------------------ public API

func clearAll() -> void:
	_type.resize(_cells)
	_variant.resize(_cells)
	_life.resize(_cells)
	_timer.resize(_cells)
	_flow.resize(_cells)
	_clock.resize(_cells)
	_queued.resize(_cells)

	_type.fill(EMPTY)
	_variant.fill(0)
	_life.fill(0)
	_timer.fill(0)
	_flow.fill(0)
	_clock.fill(0)
	_queued.fill(0)

	var last_row: int = (_ph - 1) * _pw
	for x: int in _pw:
		_type[x] = WALL
		_type[last_row + x] = WALL
	for y: int in _ph:
		var row: int = y * _pw
		_type[row] = WALL
		_type[row + _pw - 1] = WALL

	_active_n = 0
	_count = 0
	_dirty_n = 0
	for chunk: int in _chunk_dirty.size():
		_chunk_dirty[chunk] = 1
		_dirty_chunks[chunk] = chunk
	_dirty_n = _chunk_dirty.size()
	world_cleared.emit()


func spawnParticle(type_name: String, pos: Vector2) -> bool:
	if not _t_ids.has(type_name):
		push_error("Unknown particle type: ", type_name)
		return false
	return spawnAt(_t_ids[type_name], int(pos.x), int(pos.y))


func spawnAt(id: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return false
	var i: int = (y + 1) * _pw + (x + 1)
	return _spawn(i, id)


func despawnParticle(pos: Vector2) -> int:
	var x: int = int(pos.x)
	var y: int = int(pos.y)
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return 0

	var i: int = (y + 1) * _pw + (x + 1)
	if _type[i] < FIRST_TYPE:
		return 0

	_erase(i)
	_wake_around(i)
	return 1


## Snapshot of a single cell for the inspector. Never called from the hot loop.
func getParticle(pos: Vector2) -> Dictionary:
	var x: int = int(pos.x)
	var y: int = int(pos.y)
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return {}

	var i: int = (y + 1) * _pw + (x + 1)
	var t: int = _type[i]
	if t < FIRST_TYPE:
		return {}

	var life_ms: int = 0
	if _t_life_min[t] > 0:
		life_ms = roundi(float(_life[i]) / TICK_HZ_MAX * 1000.0)

	var timer_ms: int = 0
	if _t_every_min[t] > 0:
		timer_ms = roundi(float(_timer[i]) / TICK_HZ_MAX * 1000.0)

	return {
		"type": _t_name[t],
		"pos": Vector2(x, y),
		"density": _t_density[t],
		"solid": _t_solid[t] != 0,
		"liquid": _t_liquid[t] != 0,
		"life_ms": life_ms,
		"timer_ms": timer_ms,
	}


## Chunks whose cells changed since the last call, then clears the record. The
## renderer redraws exactly these and leaves the rest of the world alone.
func consumeDirtyChunks() -> PackedInt32Array:
	var changed: PackedInt32Array = _dirty_chunks.slice(0, _dirty_n)
	for k: int in _dirty_n:
		_chunk_dirty[_dirty_chunks[k]] = 0
	_dirty_n = 0
	return changed


func getChunkGrid() -> Vector2i:
	return Vector2i(_chunks_x, _chunks_y)


## Where a chunk sits in the world and how big it really is. Chunks along the
## right and bottom edges are short when the world is not a whole number of
## chunks across.
func chunkRect(chunk: int) -> Rect2i:
	var x: int = (chunk % _chunks_x) << CHUNK_SHIFT
	var y: int = (chunk / _chunks_x) << CHUNK_SHIFT
	return Rect2i(x, y, mini(CHUNK, _w - x), mini(CHUNK, _h - y))


## One chunk's cells, unpadded and packed row by row, ready to hand to an Image.
## Only the rows the chunk covers are touched, so the cost tracks the area that
## actually changed rather than the size of the world.
func chunkCells(chunk: int, variants: bool) -> PackedByteArray:
	var rect: Rect2i = chunkRect(chunk)
	var source: PackedByteArray = _variant if variants else _type
	var out: PackedByteArray = PackedByteArray()
	for row: int in rect.size.y:
		var from: int = (rect.position.y + row + 1) * _pw + rect.position.x + 1
		out.append_array(source.slice(from, from + rect.size.x))
	return out


## Palette lookup texture for the cell shader: x = colour variant, y = type id.
## Reserved ids (EMPTY, WALL) stay transparent. Built once at startup.
func buildPaletteImage() -> Image:
	var max_variants: int = 1
	for id: int in _t_variants.size():
		max_variants = maxi(max_variants, _t_variants[id])

	var image: Image = Image.create(max_variants, _t_variants.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for id: int in _t_variants.size():
		if id < FIRST_TYPE:
			continue
		for v: int in _t_variants[id]:
			var packed: int = _t_colours[_t_colour_base[id] + v]
			image.set_pixel(v, id, Color8(
				packed & 0xFF,
				(packed >> 8) & 0xFF,
				(packed >> 16) & 0xFF,
				(packed >> 24) & 0xFF))

	return image


## Look-parameter lookup texture for the cell shader: one texel per type id,
## carrying that material's grain, glow, bevel and alpha. Built once at startup.
func buildStyleImage() -> Image:
	var image: Image = Image.create(1, _t_variants.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for id: int in _t_variants.size():
		if id < FIRST_TYPE:
			continue
		image.set_pixel(0, id, Color8(
			_t_look[id * 4],
			_t_look[id * 4 + 1],
			_t_look[id * 4 + 2],
			_t_look[id * 4 + 3]))

	return image


func getActiveCount() -> int:
	return _active_n


func getParticleCount() -> int:
	return _count


func getTickRate() -> float:
	return _tick_hz


# --------------------------------------------------------------------- pacing

func _process(delta: float) -> void:
	_adapt_tick_rate(delta)

	var interval: float = 1.0 / _tick_hz
	_accumulator += delta

	var ticks: int = 0
	while _accumulator >= interval and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= interval
		ticks += 1
		_step()

	if _accumulator >= interval:
		_accumulator = 0.0  # fell behind; drop the backlog instead of spiralling


func _adapt_tick_rate(delta: float) -> void:
	var target: float = TICK_HZ_MAX
	if _active_n > ADAPT_FROM:
		var load: float = float(_active_n - ADAPT_FROM) / float(ADAPT_TO - ADAPT_FROM)
		target = lerpf(TICK_HZ_MAX, TICK_HZ_MIN, clampf(load, 0.0, 1.0))

	_tick_hz = move_toward(_tick_hz, target, 60.0 * delta)
	_life_step = maxi(roundi(TICK_HZ_MAX / _tick_hz), 1)


# ------------------------------------------------------------------- the step

## The whole update deliberately lives in one function. In GDScript both function
## calls and member lookups cost real time, and this loop runs once per awake
## cell per tick, so the movement rules are inlined rather than factored out.
func _step() -> void:
	if _active_n == 0:
		return

	_tick = (_tick + 1) & 0xFF
	var tick: int = _tick
	var pw: int = _pw
	var life_step: int = _life_step

	# Falling only reads correctly when the lowest rows move first. Flat indices
	# sort by row, so an ascending sort walked backwards gives bottom-up order.
	var pending: PackedInt32Array = _active.slice(0, _active_n)
	pending.sort()

	var count: int = _active_n
	for k: int in count:
		_queued[pending[k]] = 0
	_active_n = 0

	# Alternating the diagonal preference each tick stops piles from leaning.
	var flip: bool = (tick & 1) == 1

	# Sorted flat indices walked backwards also fix the horizontal scan to
	# right-to-left, and that direction leaks into how liquids spread. When the
	# rightmost cell of a run steps right it frees its cell, the cell to its
	# left is looked at next and takes that gap, and so on: a whole run shifts
	# right within one tick. Leftward spread gets no such chain, because a cell
	# moving left lands where the scan has not reached yet and is then held by
	# the tick guard. The result is a pronounced rightward drift (a dropped
	# blob of water leads its start point by ~75 cells after 200 ticks).
	#
	# Reversing each row's run on alternate ticks makes the scan cross that row
	# left-to-right instead, so the chain runs the other way and the two cancel.
	# Rows stay in bottom-up order, which is what falling depends on. Row runs
	# are contiguous here, so this costs one division per row and a swap per
	# cell, rather than anything per-cell in the step body itself.
	if flip:
		var start: int = 0
		while start < count:
			var row_end: int = (pending[start] / pw) * pw + pw
			var last: int = start
			while last + 1 < count and pending[last + 1] < row_end:
				last += 1
			var a: int = start
			var b: int = last
			while a < b:
				var swap_tmp: int = pending[a]
				pending[a] = pending[b]
				pending[b] = swap_tmp
				a += 1
				b -= 1
			start = last + 1

	for k: int in range(count - 1, -1, -1):
		var i: int = pending[k]
		var t: int = _type[i]
		if t < FIRST_TYPE:
			continue
		if _clock[i] == tick:
			# Something already moved into this cell this tick, so leave it be
			# until the next one. `_clock` is a byte and `tick` wraps every 256
			# ticks, so this also fires spuriously on a cell that has sat still
			# that long - and a skipped cell is never re-queued by the code
			# below. Re-activating here costs nothing in the real case (the move
			# that set the clock already queued this cell) and keeps a settled
			# particle from freezing for good in the spurious one.
			_activate_if_exposed(i)
			continue

		# --- lifespan ---
		if _t_life_min[t] != 0:
			var remaining: int = _life[i] - life_step
			if remaining <= 0:
				var death_spawn: PackedByteArray = _t_death_spawn.get(t, PackedByteArray())
				if death_spawn.is_empty():
					_erase(i)
				else:
					_erase(i)
					_spawn(i, death_spawn[0])
					for extra: int in range(1, death_spawn.size()):
						_spawn_beside(i, death_spawn[extra])
				_wake_around(i)
				continue
			_life[i] = remaining
			_activate(i)  # a counting-down cell always needs another look

		# --- repeating timer ---
		# Unlike the lifespan this fires over and over and leaves the particle
		# where it is: every time it comes round the material tries to place its
		# products in a neighbouring cell. A lava pool bubbles fire off its
		# exposed surface while the body of it stays quiet.
		#
		# Only a cell with somewhere to put its products stays awake for this.
		# A repeating timer is the one thing in the simulation that keeps a cell
		# in the active list of its own accord, for as long as the cell exists -
		# so a pool walled into stone was paying for its whole perimeter, every
		# tick, forever, to run a timer whose products had nowhere to go. Cells
		# that fail this test are woken again the moment a neighbour clears,
		# through the same `_wake_around` every other dormant cell relies on.
		if _t_every_min[t] != 0 and (_type[i - pw] == EMPTY or _type[i - 1] == EMPTY \
				or _type[i + 1] == EMPTY or _type[i + pw] == EMPTY):
			var due: int = _timer[i] - life_step
			if due <= 0:
				due = _roll(_t_every_min[t], _t_every_max[t])
				for spawn_id: int in _t_every_spawn[t] as PackedByteArray:
					_spawn_beside(i, spawn_id)
			_timer[i] = due
			_activate(i)  # still somewhere to bubble into; look again next tick

		# --- reactions against the four orthogonal neighbours ---
		if _t_reactive[t] != 0:
			var base: int = t << 8
			var other: int = _type[i - pw]
			if other >= FIRST_TYPE and _react_mask[base | other] != 0 and _apply_reaction(i, base | other):
				continue
			other = _type[i - 1]
			if other >= FIRST_TYPE and _react_mask[base | other] != 0 and _apply_reaction(i, base | other):
				continue
			other = _type[i + 1]
			if other >= FIRST_TYPE and _react_mask[base | other] != 0 and _apply_reaction(i, base | other):
				continue
			other = _type[i + pw]
			if other >= FIRST_TYPE and _react_mask[base | other] != 0 and _apply_reaction(i, base | other):
				continue

		# --- movement ---
		var move: int = _t_move[t]
		if move == MOVE_STATIC:
			continue

		var density: float = _t_density[t]
		var straight: int = i - pw if move == MOVE_RISE else i + pw

		if _try_step(i, straight, t, density, true):
			continue

		var near: int = straight - 1 if flip else straight + 1
		var far: int = straight + 1 if flip else straight - 1
		if _try_step(i, near, t, density, true):
			continue
		if _try_step(i, far, t, density, true):
			continue

		if move == MOVE_FALL:
			continue  # powders pile up rather than spreading sideways

		# Liquids and gases spread sideways, keeping their direction until they
		# are blocked, so they flow rather than jitter on the spot.
		var dir: int = 1 if _flow[i] != 0 else -1
		if _try_step(i, i + dir, t, density, false):
			continue
		_flow[i] = 0 if _flow[i] != 0 else 1
		_try_step(i, i - dir, t, density, false)


## Attempts to move cell `from` into `to`. `vertical` enables density swapping,
## which only makes sense when gravity or buoyancy is doing the work.
func _try_step(from: int, to: int, t: int, density: float, vertical: bool) -> bool:
	var other: int = _type[to]

	if other == EMPTY:
		_relocate(from, to)
		return true

	if other == WALL or _t_solid[other] != 0:
		return false

	if not vertical:
		return false  # sideways movement never displaces anything

	# Heavier material sinks and lighter material rises, by trading places.
	if _t_move[t] == MOVE_RISE:
		if _t_density[other] <= density:
			return false
	elif _t_density[other] >= density:
		return false

	_swap(from, to)
	return true


## Returns true when cell `i` no longer holds the material that reacted.
func _apply_reaction(i: int, key: int) -> bool:
	var reaction: Dictionary = _react[key]

	# A reaction that is not certain gets one roll per tick of contact, so the
	# odds of it having happened climb the longer the two stay touching.
	#
	# A losing roll has to put the cell back in the active list itself. Nothing
	# else will: settled material drops out precisely because it cannot move,
	# and it is only woken again when a neighbour changes - so a plant beside a
	# steady flame would get one roll, ever, and a 4%-per-tick burn would spread
	# at 4% per fire rather than creeping through a bed the way it reads. The
	# cell stops re-arming as soon as the reagent beside it is gone, because
	# then the step loop no longer reaches this function at all.
	var chance: int = reaction["chance"]
	if chance != CERTAIN and (randi() & CHANCE_MASK) >= chance:
		_activate(i)
		return false

	var spawn: PackedByteArray = reaction["spawn"]

	if reaction["reset"]:
		var reset_id: int = _type[i]
		_life[i] = _roll(_t_life_min[reset_id], _t_life_max[reset_id])
		_activate(i)

	if reaction["destroy"]:
		_erase(i)
		if spawn.is_empty():
			_wake_around(i)
			return true

		# The first product takes over the vacated cell; any others go beside it.
		_spawn(i, spawn[0])
		for extra: int in range(1, spawn.size()):
			_spawn_beside(i, spawn[extra])
		_wake_around(i)
		return true

	for id: int in spawn:
		_spawn_beside(i, id)

	return false


func _spawn_beside(i: int, id: int) -> void:
	var pw: int = _pw
	# Try each orthogonal neighbour in turn; `_spawn` applies the material's
	# spread and handles the empty check + wake, so the first one that lands
	# wins.
	if _spawn(i - pw, id) \
			or _spawn(i - 1, id) \
			or _spawn(i + 1, id) \
			or _spawn(i + pw, id):
		return


# ------------------------------------------------------------ cell primitives

func _place(i: int, id: int) -> void:
	var variant: int = randi() % int(_t_variants[id])
	_type[i] = id
	_variant[i] = variant | ((randi() % SEED_RANGE) << VARIANT_BITS)
	_life[i] = _roll(_t_life_min[id], _t_life_max[id])
	_timer[i] = _roll(_t_every_min[id], _t_every_max[id])
	_flow[i] = randi() & 1
	_clock[i] = _tick

	var row_place: int = i / _pw
	var chunk_place: int = ((row_place - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((i - row_place * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_place] == 0:
		_chunk_dirty[chunk_place] = 1
		_dirty_chunks[_dirty_n] = chunk_place
		_dirty_n += 1

	_count += 1
	_activate_if_exposed(i)
	_wake_reactors(i)


## Spawns a particle at cell `i`, jittered by the material's spread range.
##
## Every spawn path (brush, reactions, death spawns) goes through here, so a
## non-zero `spread` scatters products the same way everywhere. If the jittered
## target is occupied, the spawn falls back to the original cell so a reaction
## never silently loses a product; only when both are occupied does it give up.
func _spawn(i: int, id: int) -> bool:
	var target: int = i
	var sx: int = _t_spread_x[id]
	var sy: int = _t_spread_y[id]
	if sx != 0 or sy != 0:
		var x: int = (i % _pw) - 1
		var y: int = (i / _pw) - 1
		x = clampi(x + randi_range(-sx, sx), 0, _w - 1)
		y = clampi(y + randi_range(-sy, sy), 0, _h - 1)
		target = (y + 1) * _pw + (x + 1)
		if _type[target] != EMPTY:
			target = i

	if _type[target] != EMPTY:
		return false

	_place(target, id)
	_wake_around(target)
	return true


func _erase(i: int) -> void:
	_type[i] = EMPTY
	_life[i] = 0
	_timer[i] = 0

	var row_erase: int = i / _pw
	var chunk_erase: int = ((row_erase - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((i - row_erase * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_erase] == 0:
		_chunk_dirty[chunk_erase] = 1
		_dirty_chunks[_dirty_n] = chunk_erase
		_dirty_n += 1

	_count -= 1


func _relocate(from: int, to: int) -> void:
	_type[to] = _type[from]
	_variant[to] = _variant[from]
	_life[to] = _life[from]
	_timer[to] = _timer[from]
	_flow[to] = _flow[from]
	_clock[to] = _tick

	_type[from] = EMPTY
	_life[from] = 0
	_timer[from] = 0

	var row_src: int = from / _pw
	var chunk_src: int = ((row_src - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((from - row_src * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_src] == 0:
		_chunk_dirty[chunk_src] = 1
		_dirty_chunks[_dirty_n] = chunk_src
		_dirty_n += 1
	var row_dst: int = to / _pw
	var chunk_dst: int = ((row_dst - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((to - row_dst * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_dst] == 0:
		_chunk_dirty[chunk_dst] = 1
		_dirty_chunks[_dirty_n] = chunk_dst
		_dirty_n += 1

	_activate_if_exposed(to)
	_wake_reactors(to)
	_wake_around(from)


func _swap(a: int, b: int) -> void:
	var t: int = _type[a]
	var v: int = _variant[a]
	var l: int = _life[a]
	var m: int = _timer[a]
	var f: int = _flow[a]

	_type[a] = _type[b]
	_variant[a] = _variant[b]
	_life[a] = _life[b]
	_timer[a] = _timer[b]
	_flow[a] = _flow[b]

	_type[b] = t
	_variant[b] = v
	_life[b] = l
	_timer[b] = m
	_flow[b] = f

	_clock[a] = _tick
	_clock[b] = _tick

	var row_a: int = a / _pw
	var chunk_a: int = ((row_a - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((a - row_a * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_a] == 0:
		_chunk_dirty[chunk_a] = 1
		_dirty_chunks[_dirty_n] = chunk_a
		_dirty_n += 1
	var row_b: int = b / _pw
	var chunk_b: int = ((row_b - 1) >> CHUNK_SHIFT) * _chunks_x \
			+ ((b - row_b * _pw - 1) >> CHUNK_SHIFT)
	if _chunk_dirty[chunk_b] == 0:
		_chunk_dirty[chunk_b] = 1
		_dirty_chunks[_dirty_n] = chunk_b
		_dirty_n += 1

	_activate_if_exposed(a)
	_activate_if_exposed(b)
	_wake_reactors(a)
	_wake_reactors(b)
	_wake_around(a)
	_wake_around(b)


# --------------------------------------------------------------- active list

func _activate(i: int) -> void:
	if _queued[i] != 0:
		return
	_queued[i] = 1
	if _active_n >= _active.size():
		_active.resize(_active.size() * 2)
	_active[_active_n] = i
	_active_n += 1


## Same as `_activate`, but skips cells that are fully surrounded by their own
## type. Every move `_try_step` could attempt from such a cell targets a
## same-type neighbour, and a same-type neighbour always blocks it (solids
## refuse the swap outright; matching density blocks it for liquids/gases;
## reactions never fire between two cells of the same type either) - so a
## fully surrounded cell is provably stuck until one of its neighbours
## changes. That makes it safe to leave it out of the active list: a large
## settled or free-falling blob then costs work proportional to its surface,
## not its volume. Whichever neighbour changes wakes this cell back up through
## the normal `_wake_around` call at that neighbour, exactly like any other
## dormant cell.
##
## A cell whose material has a life timer is always activated regardless,
## since it needs to be in the active list to count down and despawn even
## while fully surrounded (e.g. Smoke buried in the middle of a thick cloud).
##
## The cheap disqualifiers run first (already queued, nothing there) so the
## 8-neighbour scan only happens for real particles that aren't queued yet.
## EMPTY and WALL never activate at all: the step loop would skip them anyway,
## so listing them was always wasted work.
func _activate_if_exposed(i: int) -> void:
	if _queued[i] != 0:
		return
	var t: int = _type[i]
	if t < FIRST_TYPE:
		return
	if _t_life_min[t] > 0:
		_activate(i)
		return
	var pw: int = _pw
	if _type[i - pw - 1] != t or _type[i - pw] != t or _type[i - pw + 1] != t \
			or _type[i - 1] != t or _type[i + 1] != t \
			or _type[i + pw - 1] != t or _type[i + pw] != t or _type[i + pw + 1] != t:
		_activate(i)


## Wakes the cells that could newly be able to move now that `i` changed: the
## three above it and the two beside it. A cell being vacated cannot unblock
## anything below it, so those are deliberately skipped.
##
## This is movement only. A cell that gains a *neighbour* rather than a gap
## needs `_wake_reactors` instead.
func _wake_around(i: int) -> void:
	var pw: int = _pw
	_activate_if_exposed(i - pw)
	_activate_if_exposed(i - pw - 1)
	_activate_if_exposed(i - pw + 1)
	_activate_if_exposed(i - 1)
	_activate_if_exposed(i + 1)

	# The cell below is the one exception. It can never be unblocked for
	# movement by a gap opening above it, which is why it is skipped otherwise -
	# but it can be unblocked for a repeating timer, which needs open space to
	# put its products in. Without this a lava cell goes quiet for good the
	# first time its own smoke drifts across it.
	var below: int = i + pw
	if _t_every_min[_type[below]] != 0:
		_activate(below)


## Wakes the neighbours that react to whatever now occupies `i`.
##
## Movement only ever wakes cells that might newly be able to *move*, which
## deliberately excludes everything below a change. Reactions have the opposite
## requirement: the particle that just had something land on it is exactly the
## one that has to be looked at again, and it is usually dormant - settled
## material drops out of the active list precisely because it cannot move.
## Without this, a reaction between a resting particle and something placed
## against it simply never runs: sand survives being buried in lava, and a
## plant never catches from the fire sitting on top of it (which also leaves
## that fire resetting its lifespan against fuel that never burns away, so it
## burns forever).
##
## Only the four orthogonal neighbours are woken, matching the neighbourhood
## the step loop actually tests reactions against, and only those that really
## do react to `i`'s material - one mask lookup each, so an inert pile costs
## nothing.
func _wake_reactors(i: int) -> void:
	var t: int = _type[i]
	if t < FIRST_TYPE:
		return

	var pw: int = _pw
	var n: int = i - pw
	if _react_mask[(_type[n] << 8) | t] != 0:
		_activate(n)
	n = i - 1
	if _react_mask[(_type[n] << 8) | t] != 0:
		_activate(n)
	n = i + 1
	if _react_mask[(_type[n] << 8) | t] != 0:
		_activate(n)
	n = i + pw
	if _react_mask[(_type[n] << 8) | t] != 0:
		_activate(n)
