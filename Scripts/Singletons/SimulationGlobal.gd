extends Node

const Particles = preload("res://Scripts/Singletons/Particles.gd")

# --- Config ---
# Target simulation tick rate in ms (60 ticks/sec).
const TICK_MS: float = 1000.0 / 60.0

# Never run more than this many ticks in a single frame. Without this a slow tick
# makes the accumulator demand even more ticks next frame and the sim spirals.
const MAX_TICKS_PER_FRAME: int = 3

# Max velocity magnitude to prevent runaway values.
const MAX_VELOCITY: float = 10.0

# Movement candidates, ordered by preference. Precomputed so the hot loop never
# allocates direction arrays.
const SOLID_DIRS: Array = [Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1)]
const LIQUID_DIRS: Array = [Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 0)]

# Cells that may become free to move once a particle vacates a cell: above,
# the two upper diagonals, and the two sides. Anything below is unaffected.
const WAKE_OFFSETS: Array = [Vector2(0, -1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0)]

const EMPTY_IDS: Array = []

# --- State ---
# Spatial lookup: Vector2 position -> Array of particle ids.
var grid: Dictionary = {}

# All particles by id.
var particles: Dictionary = {}

# Work list of particles that need updating this tick. Settled particles are
# dropped from it and only return when a neighbour vacates a cell.
var _active_particles: Array = []
var _active_set: Dictionary = {}

# Deferred mutation queues so we never modify grid while iterating it.
var _spawn_queue: Array = []
var _despawn_queue: Array = []

# type_name -> flattened, ready-to-read definition (see _build_definition).
var _defs: Dictionary = {}

# step Vector2 -> movement candidates, for gas-like particles.
var _gas_dirs: Dictionary = {}

var _next_id: int = 0
var _tick_count: int = 0
var _accumulator: float = 0.0


func _ready() -> void:
	for type_name: String in Particles.TYPES:
		_defs[type_name] = _build_definition(type_name)
	_build_gas_dirs()


func _process(delta: float) -> void:
	_accumulator += delta * 1000.0
	var ticks: int = 0
	while _accumulator >= TICK_MS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_MS
		ticks += 1
		tick(TICK_MS)
	if _accumulator >= TICK_MS:
		_accumulator = 0.0  # we fell behind; drop the backlog instead of spiralling


# Definitions
#
# Reading nested config dictionaries in the hot loop was a large share of the
# per-particle cost. Each type is flattened once here and the resulting
# dictionary is stored directly on every particle as "def".

func _build_definition(type_name: String) -> Dictionary:
	var config: Dictionary = Particles.get_config(type_name)

	var colors: Array = []
	for value: String in config.get("colors", []):
		colors.append(Color(value))
	if colors.is_empty():
		colors.append(Color.MAGENTA)

	var idle_velocity: Vector2 = Vector2.ZERO
	var idle_value: Variant = (config.get("idleBehaviors", {}) as Dictionary).get("changeVelocity")
	if idle_value is Vector2:
		idle_velocity = idle_value

	var timers: Dictionary = config.get("timers", {}) as Dictionary
	var initial_timers: Dictionary = {}
	for timer_name: String in timers:
		var despawn: Variant = (timers[timer_name] as Dictionary).get("despawn")
		if despawn is int:
			initial_timers[timer_name] = float(despawn)

	# Interactions that neither destroy, spawn, nor reset a timer can never have
	# an effect. Dropping them keeps them out of the collision hot path entirely.
	var interactions: Dictionary = {}
	for target: String in config.get("interactions", {}) as Dictionary:
		var inter: Dictionary = (config["interactions"] as Dictionary)[target]
		if inter["destroy"] or not inter["spawn"].is_empty() or not inter["resetTimers"].is_empty():
			interactions[target] = inter

	var solid: bool = config.get("solid", false)
	var liquid: bool = config.get("liquid", false)

	return {
		"type": type_name,
		"solid": solid,
		"liquid": liquid,
		"density": float(config.get("density", 1.0)),
		"gravity": config.get("initialGravity", Vector2.ZERO) as Vector2,
		"idle_velocity": idle_velocity,
		"colors": colors,
		"interactions": interactions,
		"timers": timers,
		"initial_timers": initial_timers,
		"dirs": SOLID_DIRS if solid else (LIQUID_DIRS if liquid else EMPTY_IDS),
	}


func _build_gas_dirs() -> void:
	for sy: int in [-1, 0, 1]:
		for sx: int in [-1, 0, 1]:
			var step: Vector2 = Vector2(sx, sy)
			var dirs: Array = []
			for dir: Vector2 in [step, Vector2(0, sy), Vector2(sx, 0)]:
				if dir != Vector2.ZERO and not dirs.has(dir):
					dirs.append(dir)
			_gas_dirs[step] = dirs


# Public API

func spawnParticle(type_name: String, pos: Vector2) -> bool:
	var def: Dictionary = _defs.get(type_name, {}) as Dictionary
	if def.is_empty():
		push_error("Unknown particle type: ", type_name)
		return false

	if not _can_occupy(def, pos):
		return false

	_spawn_queue.append({"type": type_name, "pos": pos})
	return true


func despawnParticle(pos: Vector2) -> int:
	var ids: Array = grid.get(pos, EMPTY_IDS)
	for id: int in ids:
		_despawn_queue.append(id)
	return ids.size()


func getParticle(pos: Vector2) -> Dictionary:
	var ids: Array = grid.get(pos, EMPTY_IDS)
	if ids.is_empty():
		return {}
	return particles.get(ids[0], {}) as Dictionary


func getParticlesAt(pos: Vector2) -> Array:
	var ids: Array = grid.get(pos, EMPTY_IDS)
	var result: Array = []
	for id: int in ids:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if not p.is_empty():
			result.append(p)
	return result


func getParticleById(id: int) -> Dictionary:
	return particles.get(id, {}) as Dictionary


func moveParticle(from: Vector2, to: Vector2) -> bool:
	var ids: Array = grid.get(from, EMPTY_IDS)
	if ids.is_empty():
		return false
	return moveParticleById(ids[0], to)


func setParticleVelocity(pos: Vector2, velocity: Vector2) -> bool:
	var ids: Array = grid.get(pos, EMPTY_IDS)
	if ids.is_empty():
		return false
	return setParticleVelocityById(ids[0], velocity)


func moveParticleById(id: int, to: Vector2) -> bool:
	var p: Dictionary = particles.get(id, {}) as Dictionary
	if p.is_empty() or not _can_occupy(p["def"], to):
		return false
	_move_particle(p, to)
	return true


func setParticleVelocityById(id: int, velocity: Vector2) -> bool:
	var p: Dictionary = particles.get(id, {}) as Dictionary
	if p.is_empty():
		return false
	p["velocity"] = velocity
	_activate_particle(id)
	return true


func getActiveCount() -> int:
	return _active_particles.size()


func tick(delta_ms: float) -> void:
	_tick_count += 1

	_flush_despawn_queue()
	_flush_spawn_queue()
	_step_active(delta_ms)


# Occupancy rules

func _in_bounds(pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 \
		and pos.x < Global.WORLD_GRID_SIZE and pos.y < Global.WORLD_GRID_SIZE


func _can_occupy(def: Dictionary, pos: Vector2) -> bool:
	if not _in_bounds(pos):
		return false

	var ids: Array = grid.get(pos, EMPTY_IDS)
	if ids.is_empty():
		return true
	if def["solid"]:
		return false  # solids never share a cell

	var wants_liquid_space: bool = def["liquid"]
	for id: int in ids:
		var other: Dictionary = particles.get(id, {}) as Dictionary
		if other.is_empty():
			continue
		var other_def: Dictionary = other["def"]
		if other_def["solid"]:
			return false
		if wants_liquid_space and other_def["liquid"]:
			return false  # two liquids cannot share a cell
	return true


func _cell_blocks(def: Dictionary, ids: Array) -> bool:
	if def["solid"]:
		return true  # caller only reaches here for non-empty cells
	var wants_liquid_space: bool = def["liquid"]
	for id: int in ids:
		var other: Dictionary = particles.get(id, {}) as Dictionary
		if other.is_empty():
			continue
		var other_def: Dictionary = other["def"]
		if other_def["solid"]:
			return true
		if wants_liquid_space and other_def["liquid"]:
			return true
	return false


func _cell_has_solid(ids: Array) -> bool:
	for id: int in ids:
		var other: Dictionary = particles.get(id, {}) as Dictionary
		if not other.is_empty() and other["def"]["solid"]:
			return true
	return false


# Active list

func _activate_particle(id: int) -> void:
	if _active_set.has(id):
		return
	_active_set[id] = true
	_active_particles.append(id)


func _is_active(p: Dictionary) -> bool:
	if p["velocity"] != Vector2.ZERO:
		return true
	if not p["timers"].is_empty():
		return true
	return p["def"]["idle_velocity"] != Vector2.ZERO


func _wake_neighbors(pos: Vector2) -> void:
	for offset: Vector2 in WAKE_OFFSETS:
		for id: int in grid.get(pos + offset, EMPTY_IDS):
			_activate_particle(id)


# Grid

func _add_to_grid(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var ids: Array = grid.get(pos, EMPTY_IDS)
	if ids.is_empty():
		grid[pos] = [p["id"]]
	else:
		ids.append(p["id"])


func _remove_from_grid(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var ids: Array = grid.get(pos, EMPTY_IDS)
	if ids.is_empty():
		return
	ids.erase(p["id"])
	if ids.is_empty():
		grid.erase(pos)


func _destroy_particle(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	_remove_from_grid(p)
	particles.erase(p["id"])
	_active_set.erase(p["id"])
	_wake_neighbors(pos)


# Queues

func _flush_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		return

	for item: Dictionary in _spawn_queue:
		var pos: Vector2 = item["pos"]
		var def: Dictionary = _defs[item["type"]]
		if not _can_occupy(def, pos):
			continue

		_next_id += 1
		var colors: Array = def["colors"]
		var p: Dictionary = {
			"id": _next_id,
			"type": def["type"],
			"def": def,
			"pos": pos,
			"velocity": def["gravity"],
			"color": colors[randi() % colors.size()],
			"timers": def["initial_timers"].duplicate(),
		}

		particles[_next_id] = p
		_add_to_grid(p)
		if _is_active(p):
			_activate_particle(_next_id)
		_wake_neighbors(pos)

	_spawn_queue.clear()


func _flush_despawn_queue() -> void:
	if _despawn_queue.is_empty():
		return

	for id: int in _despawn_queue:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if not p.is_empty():
			_destroy_particle(p)
	_despawn_queue.clear()


# Simulation step

func _step_active(delta_ms: float) -> void:
	if _active_particles.is_empty():
		return

	# Swap out the work list. Anything that still needs simulating re-queues
	# itself into the fresh list, so settled particles simply fall out.
	var pending: Array = _active_particles
	_active_particles = []
	_active_set.clear()

	for id: int in pending:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if not p.is_empty():
			_update_particle(p, delta_ms)


func _update_particle(p: Dictionary, delta_ms: float) -> void:
	var def: Dictionary = p["def"]
	var velocity: Vector2 = p["velocity"]

	velocity += def["gravity"]
	velocity += def["idle_velocity"]
	p["velocity"] = velocity.clamp(
		Vector2(-MAX_VELOCITY, -MAX_VELOCITY), Vector2(MAX_VELOCITY, MAX_VELOCITY)
	)

	_resolve_movement(p, def)
	if not particles.has(p["id"]):
		return  # destroyed during movement

	if not p["timers"].is_empty():
		_tick_timers(p, def, delta_ms)
		if not particles.has(p["id"]):
			return

	if _is_active(p):
		_activate_particle(p["id"])


func _resolve_movement(p: Dictionary, def: Dictionary) -> void:
	var velocity: Vector2 = p["velocity"]
	if velocity == Vector2.ZERO:
		return

	var dirs: Array = def["dirs"]
	if dirs.is_empty():
		dirs = _gas_dirs[Vector2(signf(velocity.x), signf(velocity.y))]

	var pos: Vector2 = p["pos"]
	var density: float = def["density"]

	for dir: Vector2 in dirs:
		var target: Vector2 = pos + dir
		if not _in_bounds(target):
			continue  # world edges act as walls

		var ids: Array = grid.get(target, EMPTY_IDS)

		if ids.is_empty():
			_move_particle(p, target)
			return

		# Solids block everything, so interactions are all that can happen.
		if _cell_has_solid(ids):
			if _handle_collisions(p, def, ids):
				return
			continue

		# Denser particles sink through lighter ones on the way down.
		if dir.y > 0:
			var lighter: Dictionary = _find_swap_target(ids, density)
			if not lighter.is_empty():
				_swap_particles(p, lighter)
				return

		# Cannot sink, so respect the sharing rules for this material.
		if _cell_blocks(def, ids):
			if _handle_collisions(p, def, ids):
				return
			continue

		# Sharing is allowed. React first, then move in if we survived, so the
		# mover never ends up reacting against itself.
		if _handle_collisions(p, def, ids):
			return
		_move_particle(p, target)
		return

	# Nowhere to go: the particle is supported, so let it settle and sleep.
	p["velocity"] = Vector2.ZERO


func _move_particle(p: Dictionary, new_pos: Vector2) -> void:
	var old_pos: Vector2 = p["pos"]
	_remove_from_grid(p)
	p["pos"] = new_pos
	_add_to_grid(p)
	_activate_particle(p["id"])
	_wake_neighbors(old_pos)


func _find_swap_target(ids: Array, density: float) -> Dictionary:
	var lightest: Dictionary = {}
	var lightest_density: float = density

	for id: int in ids:
		var other: Dictionary = particles.get(id, {}) as Dictionary
		if other.is_empty():
			continue
		var other_def: Dictionary = other["def"]
		if other_def["solid"]:
			continue
		if other_def["density"] < lightest_density:
			lightest_density = other_def["density"]
			lightest = other

	return lightest


func _swap_particles(a: Dictionary, b: Dictionary) -> void:
	var a_pos: Vector2 = a["pos"]
	var b_pos: Vector2 = b["pos"]

	_remove_from_grid(a)
	_remove_from_grid(b)
	a["pos"] = b_pos
	b["pos"] = a_pos
	_add_to_grid(a)
	_add_to_grid(b)

	# Both are moving, and b just got displaced upwards, so it needs a fresh look.
	b["velocity"] = b["def"]["gravity"]
	_activate_particle(a["id"])
	_activate_particle(b["id"])
	_wake_neighbors(a_pos)
	_wake_neighbors(b_pos)


# Interactions

func _handle_collisions(mover: Dictionary, mover_def: Dictionary, ids: Array) -> bool:
	if not _reaction_possible(mover_def, ids):
		return false

	# Reactions destroy particles, which mutates this cell's id list, so iterate
	# a snapshot. Only taken when a reaction is actually on the table.
	for id: int in ids.duplicate():
		var target: Dictionary = particles.get(id, {}) as Dictionary
		if target.is_empty():
			continue

		var target_def: Dictionary = target["def"]

		if _apply_interaction(mover, mover_def, target_def["type"]):
			return true  # mover destroyed itself

		_apply_interaction(target, target_def, mover_def["type"])

	return false


## Cheap read-only scan so the common "nothing reacts" case allocates nothing.
func _reaction_possible(mover_def: Dictionary, ids: Array) -> bool:
	var mover_interactions: Dictionary = mover_def["interactions"]

	for id: int in ids:
		var other: Dictionary = particles.get(id, {}) as Dictionary
		if other.is_empty():
			continue
		var other_def: Dictionary = other["def"]
		if mover_interactions.has(other_def["type"]):
			return true
		if (other_def["interactions"] as Dictionary).has(mover_def["type"]):
			return true

	return false


## Applies subject's reaction to touching `object_type`. Returns true if the
## subject destroyed itself.
func _apply_interaction(subject: Dictionary, subject_def: Dictionary, object_type: String) -> bool:
	var interactions: Dictionary = subject_def["interactions"]
	if not interactions.has(object_type):
		return false

	var inter: Dictionary = interactions[object_type]

	for spawn_type: String in inter["spawn"]:
		_spawn_queue.append({"type": spawn_type, "pos": subject["pos"]})

	if inter["destroy"]:
		_destroy_particle(subject)
		return true

	# Only wake the subject if a timer actually restarted. Waking on every touch
	# would stop neighbouring particles from ever settling.
	var initial_timers: Dictionary = subject_def["initial_timers"]
	for timer_name: String in inter["resetTimers"]:
		if initial_timers.has(timer_name):
			subject["timers"][timer_name] = initial_timers[timer_name]
			_activate_particle(subject["id"])

	return false


func _tick_timers(p: Dictionary, def: Dictionary, delta_ms: float) -> void:
	var timers: Dictionary = def["timers"]
	var running: Dictionary = p["timers"]
	var expired: Array = []

	for timer_name: String in running:
		running[timer_name] -= delta_ms
		if running[timer_name] <= 0.0:
			expired.append(timer_name)

	for timer_name: String in expired:
		running.erase(timer_name)
		var timer: Dictionary = timers.get(timer_name, {}) as Dictionary
		if timer.is_empty():
			continue

		if timer["despawn"] is int:
			_destroy_particle(p)
			return

		for spawn_type: String in timer["spawn"]:
			_spawn_queue.append({"type": spawn_type, "pos": p["pos"]})

		if timer["changeVelocity"] is Vector2:
			p["velocity"] += timer["changeVelocity"]
