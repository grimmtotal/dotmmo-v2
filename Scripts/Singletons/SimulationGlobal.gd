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
## colour variant, a life counter and a flow direction, one byte each in
## parallel arrays.

const Particles = preload("res://Scripts/Singletons/Particles.gd")

# Reserved type ids. Real materials start at FIRST_TYPE.
const EMPTY: int = 0
const WALL: int = 1
const FIRST_TYPE: int = 2

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

# Life is counted in 60Hz-equivalent ticks so lifespans stay constant in real
# time even when the tick rate drops. One byte caps a lifespan at ~4.2s.
const MAX_LIFE: int = 255

signal world_cleared

# --- Cell state (padded, parallel arrays) ---
var _type: PackedByteArray
var _variant: PackedByteArray
var _life: PackedByteArray
var _flow: PackedByteArray
var _clock: PackedByteArray

# --- Active list of flat cell indices, with a per-cell dedupe flag ---
var _active: PackedInt32Array
var _active_n: int = 0
var _queued: PackedByteArray

# The renderer reads `_type` and `_variant` directly (uploaded as textures and
# coloured on the GPU), so the simulation does no pixel work at all - it only
# raises this flag when any cell changed.
var _cells_dirty: bool = true

# --- Type tables, indexed by type id ---
var _t_name: PackedStringArray = PackedStringArray()
var _t_ids: Dictionary = {}
var _t_move: PackedByteArray
var _t_solid: PackedByteArray
var _t_liquid: PackedByteArray
var _t_reactive: PackedByteArray
var _t_density: PackedFloat32Array
var _t_life: PackedByteArray
var _t_variants: PackedByteArray
var _t_colour_base: PackedInt32Array
var _t_colours: PackedInt64Array

# What a material spawns when its life timer expires. Most materials spawn
# nothing; the few that do (Fire -> Smoke) are stored here.
var _t_death_spawn: Dictionary = {}

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

	_w = Global.WORLD_GRID_SIZE
	_h = Global.WORLD_GRID_SIZE
	_pw = _w + 2
	_ph = _h + 2
	_cells = _pw * _ph

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
	_t_life.resize(total)
	_t_variants.resize(total)
	_t_colour_base.resize(total)

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
	_t_life[id] = _lifespan_ticks(config)
	_t_death_spawn[id] = _death_spawn(config)

	if liquid:
		_t_move[id] = MOVE_LIQUID
	elif gravity.y < 0.0:
		_t_move[id] = MOVE_RISE
	elif gravity.y > 0.0:
		_t_move[id] = MOVE_FALL
	else:
		_t_move[id] = MOVE_STATIC

	var colours: Array = config.get("colors", [])
	_t_colour_base[id] = _t_colours.size()
	_t_variants[id] = maxi(colours.size(), 1)
	if colours.is_empty():
		_t_colours.append(_to_rgba32(Color.MAGENTA))
	for value: String in colours:
		_t_colours.append(_to_rgba32(Color(value)))

	_configure_reactions(id, config)


## Collapses the timer table down to a single lifespan. Every material in
## Particles.gd uses at most one despawn timer, so a per-cell byte can replace
## the old per-particle timer dictionary.
func _lifespan_ticks(config: Dictionary) -> int:
	for timer_name: String in config.get("timers", {}) as Dictionary:
		var despawn: Variant = ((config["timers"] as Dictionary)[timer_name] as Dictionary).get("despawn")
		if despawn is int:
			return clampi(roundi(float(despawn) * 0.001 * TICK_HZ_MAX), 1, MAX_LIFE)
	return 0


## Products spawned when a material's life timer expires (e.g. Fire -> Smoke).
func _death_spawn(config: Dictionary) -> PackedByteArray:
	var spawn: PackedByteArray = PackedByteArray()
	for timer_name: String in config.get("timers", {}) as Dictionary:
		for spawn_name: String in ((config["timers"] as Dictionary)[timer_name] as Dictionary).get("spawn", []):
			if _t_ids.has(spawn_name):
				spawn.append(_t_ids[spawn_name])
	return spawn


func _configure_reactions(id: int, config: Dictionary) -> void:
	for target: String in config.get("interactions", {}) as Dictionary:
		if not _t_ids.has(target):
			continue

		var inter: Dictionary = (config["interactions"] as Dictionary)[target]
		var destroy: bool = inter["destroy"]
		var reset: bool = not inter["resetTimers"].is_empty() and _t_life[id] > 0

		var spawn: PackedByteArray = PackedByteArray()
		for spawn_name: String in inter["spawn"]:
			if _t_ids.has(spawn_name):
				spawn.append(_t_ids[spawn_name])

		# A reaction that neither destroys, spawns, nor restarts a life timer can
		# never have an observable effect, so it stays out of the hot path.
		if not destroy and spawn.is_empty() and not reset:
			continue

		var key: int = (id << 8) | int(_t_ids[target])
		_react_mask[key] = 1
		_react[key] = {"destroy": destroy, "spawn": spawn, "reset": reset}
		_t_reactive[id] = 1


## Packs to little-endian RGBA8, matching Image.FORMAT_RGBA8 byte order.
func _to_rgba32(colour: Color) -> int:
	return colour.r8 | (colour.g8 << 8) | (colour.b8 << 16) | (colour.a8 << 24)


# ------------------------------------------------------------------ public API

func clearAll() -> void:
	_type.resize(_cells)
	_variant.resize(_cells)
	_life.resize(_cells)
	_flow.resize(_cells)
	_clock.resize(_cells)
	_queued.resize(_cells)

	_type.fill(EMPTY)
	_variant.fill(0)
	_life.fill(0)
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
	_cells_dirty = true
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
	if _type[i] != EMPTY:
		return false

	_place(i, id)
	_wake_around(i)
	return true


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
	if _t_life[t] > 0:
		life_ms = roundi(float(_life[i]) / TICK_HZ_MAX * 1000.0)

	return {
		"type": _t_name[t],
		"pos": Vector2(x, y),
		"density": _t_density[t],
		"solid": _t_solid[t] != 0,
		"liquid": _t_liquid[t] != 0,
		"life_ms": life_ms,
	}


func getTypeCells() -> PackedByteArray:
	return _type


func getVariantCells() -> PackedByteArray:
	return _variant


func consumeCellsDirty() -> bool:
	var was_dirty: bool = _cells_dirty
	_cells_dirty = false
	return was_dirty


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


func getPaddedSize() -> Vector2i:
	return Vector2i(_pw, _ph)


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

	for k: int in range(count - 1, -1, -1):
		var i: int = pending[k]
		var t: int = _type[i]
		if t < FIRST_TYPE:
			continue
		if _clock[i] == tick:
			continue  # something already moved into this cell this tick

		# --- lifespan ---
		if _t_life[t] != 0:
			var remaining: int = _life[i] - life_step
			if remaining <= 0:
				var death_spawn: PackedByteArray = _t_death_spawn.get(t, PackedByteArray())
				if death_spawn.is_empty():
					_erase(i)
				else:
					_erase(i)
					_place(i, death_spawn[0])
					for extra: int in range(1, death_spawn.size()):
						_spawn_beside(i, death_spawn[extra])
				_wake_around(i)
				continue
			_life[i] = remaining
			_activate(i)  # a counting-down cell always needs another look

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
	var spawn: PackedByteArray = reaction["spawn"]

	if reaction["reset"]:
		_life[i] = _t_life[_type[i]]
		_activate(i)

	if reaction["destroy"]:
		_erase(i)
		if spawn.is_empty():
			_wake_around(i)
			return true

		# The first product takes over the vacated cell; any others go beside it.
		_place(i, spawn[0])
		for extra: int in range(1, spawn.size()):
			_spawn_beside(i, spawn[extra])
		_wake_around(i)
		return true

	for id: int in spawn:
		_spawn_beside(i, id)

	return false


func _spawn_beside(i: int, id: int) -> void:
	var pw: int = _pw
	if _type[i - pw] == EMPTY:
		_place(i - pw, id)
		_wake_around(i - pw)
	elif _type[i - 1] == EMPTY:
		_place(i - 1, id)
		_wake_around(i - 1)
	elif _type[i + 1] == EMPTY:
		_place(i + 1, id)
		_wake_around(i + 1)
	elif _type[i + pw] == EMPTY:
		_place(i + pw, id)
		_wake_around(i + pw)


# ------------------------------------------------------------ cell primitives

func _place(i: int, id: int) -> void:
	var variant: int = randi() % int(_t_variants[id])
	_type[i] = id
	_variant[i] = variant
	_life[i] = _t_life[id]
	_flow[i] = randi() & 1
	_clock[i] = _tick
	_cells_dirty = true

	_count += 1
	_activate_if_exposed(i)


func _erase(i: int) -> void:
	_type[i] = EMPTY
	_life[i] = 0
	_cells_dirty = true

	_count -= 1


func _relocate(from: int, to: int) -> void:
	_type[to] = _type[from]
	_variant[to] = _variant[from]
	_life[to] = _life[from]
	_flow[to] = _flow[from]
	_clock[to] = _tick

	_type[from] = EMPTY
	_life[from] = 0
	_cells_dirty = true

	_activate_if_exposed(to)
	_wake_around(from)


func _swap(a: int, b: int) -> void:
	var t: int = _type[a]
	var v: int = _variant[a]
	var l: int = _life[a]
	var f: int = _flow[a]

	_type[a] = _type[b]
	_variant[a] = _variant[b]
	_life[a] = _life[b]
	_flow[a] = _flow[b]

	_type[b] = t
	_variant[b] = v
	_life[b] = l
	_flow[b] = f

	_clock[a] = _tick
	_clock[b] = _tick
	_cells_dirty = true

	_activate_if_exposed(a)
	_activate_if_exposed(b)
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
func _activate_if_exposed(i: int) -> void:
	var t: int = _type[i]
	if _t_life[t] > 0:
		_activate(i)
		return
	for off: int in _nbr_off:
		if _type[i + off] != t:
			_activate(i)
			return


## Wakes the cells that could newly be able to move or react now that `i`
## changed: the three above it and the two beside it. A cell being vacated
## cannot unblock anything below it, so those are deliberately skipped.
func _wake_around(i: int) -> void:
	var pw: int = _pw
	_activate_if_exposed(i - pw)
	_activate_if_exposed(i - pw - 1)
	_activate_if_exposed(i - pw + 1)
	_activate_if_exposed(i - 1)
	_activate_if_exposed(i + 1)
