extends Node

const Particles = preload("res://Scripts/Singletons/Particles.gd")

# --- Config ---
# Target simulation tick rate in ms (60 ticks/sec).
const TICK_MS: float = 1000.0 / 60.0

# Max active particles updated per tick. Keeps the sim bounded when things get busy.
const UPDATES_PER_TICK: int = 2000

# Max velocity magnitude to prevent runaway values.
const MAX_VELOCITY: float = 10.0

# --- State ---
# Spatial lookup: Vector2 position -> Array[int] of particle ids.
var grid: Dictionary = {}

# All particles by id.
var particles: Dictionary = {}

# Only particles that actually need updates are tracked here. Settled solids and
# idle non-solids are skipped until an active particle collides with them.
var _active_particles: Array = []
var _active_set: Dictionary = {}
var _active_dirty: bool = false

# Cursor into _active_particles for round-robin batch updates.
var _batch_cursor: int = 0

# Deferred mutation queues so we never modify grid while iterating it.
var _spawn_queue: Array = []
var _despawn_queue: Array = []

var _next_id: int = 0
var _tick_count: int = 0
var _accumulator: float = 0.0


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	_accumulator += delta * 1000.0
	while _accumulator >= TICK_MS:
		_accumulator -= TICK_MS
		tick(TICK_MS)


# Public API

func spawnParticle(type_name: String, pos: Vector2) -> bool:
	if not Particles.TYPES.has(type_name):
		push_error("Unknown particle type: ", type_name)
		return false

	var config: Dictionary = Particles.get_config(type_name)
	if config.get("solid", false):
		if _has_any_particle_at(pos):
			return false
	elif config.get("liquid", false):
		if _has_solid_at(pos) or _has_liquid_at(pos):
			return false
	else:
		if _has_solid_at(pos):
			return false

	_spawn_queue.append({"type": type_name, "pos": pos})
	return true


func despawnParticle(pos: Vector2) -> int:
	var ids = grid.get(pos, [])
	var count: int = ids.size()
	for id: int in ids:
		_despawn_queue.append(id)
	return count


func getParticle(pos: Vector2) -> Dictionary:
	var ids = grid.get(pos, [])
	if ids.is_empty():
		return {}
	return particles.get(ids[0], {}) as Dictionary


func getParticlesAt(pos: Vector2) -> Array:
	var ids = grid.get(pos, [])
	var result = []
	result.resize(ids.size())
	for i: int in ids.size():
		result[i] = particles.get(ids[i], {}) as Dictionary
	return result


func getParticleById(id: int) -> Dictionary:
	return particles.get(id, {}) as Dictionary


func moveParticle(from: Vector2, to: Vector2) -> bool:
	var ids = grid.get(from, [])
	if ids.is_empty():
		return false
	return moveParticleById(ids[0], to)


func setParticleVelocity(pos: Vector2, velocity: Vector2) -> bool:
	var ids = grid.get(pos, [])
	if ids.is_empty():
		return false
	return setParticleVelocityById(ids[0], velocity)


func moveParticleById(id: int, to: Vector2) -> bool:
	var p: Dictionary = particles.get(id, {}) as Dictionary
	if p.is_empty():
		return false
	var config: Dictionary = Particles.get_config(p["type"])
	if config.get("solid", false):
		if _has_any_particle_at(to):
			return false
	elif config.get("liquid", false):
		if _has_solid_at(to) or _has_liquid_at(to):
			return false
	else:
		if _has_solid_at(to):
			return false
	var was_active: bool = _active_set.has(id)
	_remove_from_grid(p)
	p["pos"] = to
	_add_to_grid(p)
	if was_active:
		_activate_particle(id)
	else:
		_active_dirty = true
	return true


func setParticleVelocityById(id: int, velocity: Vector2) -> bool:
	var p: Dictionary = particles.get(id, {}) as Dictionary
	if p.is_empty():
		return false
	p["velocity"] = velocity
	_activate_particle(id)
	return true


func tick(delta_ms: float) -> void:
	_tick_count += 1

	_flush_despawn_queue()
	_flush_spawn_queue()
	_rebuild_active_particles()
	_process_batch(delta_ms)


# Internal

func _is_active(p: Dictionary) -> bool:
	var config: Dictionary = Particles.get_config(p["type"])
	if p["velocity"] != Vector2.ZERO:
		return true
	if not p["timers"].is_empty():
		return true
	var idle_vel: Variant = config.get("idleBehaviors", {}).get("changeVelocity")
	if idle_vel is Vector2 and idle_vel != Vector2.ZERO:
		return true
	return false


func _activate_particle(id: int) -> void:
	if _active_set.has(id):
		return
	_active_set[id] = true
	_active_particles.append(id)


func _deactivate_particle(id: int) -> void:
	if _active_set.has(id):
		_active_set.erase(id)
		_active_dirty = true


func _add_to_grid(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	if not grid.has(pos):
		grid[pos] = []
	grid[pos].append(p["id"])


func _remove_from_grid(p: Dictionary) -> void:
	var ids = grid.get(p["pos"], [])
	if ids.is_empty():
		return
	ids.erase(p["id"])
	if ids.is_empty():
		grid.erase(p["pos"])


func _has_any_particle_at(pos: Vector2) -> bool:
	var ids = grid.get(pos, [])
	return not ids.is_empty()


func _has_solid_at(pos: Vector2) -> bool:
	var ids = grid.get(pos, [])
	for id: int in ids:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if p.is_empty():
			continue
		var config: Dictionary = Particles.get_config(p["type"])
		if config.get("solid", false):
			return true
	return false


func _has_liquid_at(pos: Vector2) -> bool:
	var ids = grid.get(pos, [])
	for id: int in ids:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if p.is_empty():
			continue
		var config: Dictionary = Particles.get_config(p["type"])
		if config.get("liquid", false):
			return true
	return false


func _get_particles_at(pos: Vector2) -> Array:
	var ids = grid.get(pos, [])
	var result = []
	result.resize(ids.size())
	var write: int = 0
	for id: int in ids:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if not p.is_empty():
			result[write] = p
			write += 1
	result.resize(write)
	return result


func _destroy_particle(p: Dictionary) -> void:
	var id: int = p["id"]
	_remove_from_grid(p)
	particles.erase(id)
	_active_set.erase(id)
	_active_dirty = true


func _flush_spawn_queue() -> void:
	for item: Dictionary in _spawn_queue:
		var type_name: String = item["type"]
		var pos: Vector2 = item["pos"]
		var config: Dictionary = Particles.get_config(type_name)

		if config.get("solid", false):
			if _has_any_particle_at(pos):
				continue
		else:
			if _has_solid_at(pos):
				continue

		_next_id += 1
		var p: Dictionary = {
			"id": _next_id,
			"type": type_name,
			"pos": pos,
			"velocity": config.get("initialGravity", Vector2.ZERO),
			"timers": {},
		}

		for timer_name: String in config.get("timers", {}):
			var t: Dictionary = (config["timers"] as Dictionary)[timer_name] as Dictionary
			if t["despawn"] is int:
				p["timers"][timer_name] = float(t["despawn"])

		particles[p["id"]] = p
		_add_to_grid(p)
		if _is_active(p):
			_activate_particle(p["id"])
	_spawn_queue.clear()


func _flush_despawn_queue() -> void:
	for id: int in _despawn_queue:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if p != null:
			_destroy_particle(p)
	_despawn_queue.clear()


func _rebuild_active_particles() -> void:
	if not _active_dirty:
		return

	var rebuilt: Array = []
	var rebuilt_set: Dictionary = {}
	for id: int in _active_particles:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if p.is_empty():
			continue
		if not _is_active(p):
			continue
		if rebuilt_set.has(id):
			continue
		rebuilt_set[id] = true
		rebuilt.append(id)

	_active_particles = rebuilt
	_active_set = rebuilt_set
	_active_dirty = false
	_batch_cursor = 0


func _process_batch(delta_ms: float) -> void:
	var count: int = _active_particles.size()
	if count == 0:
		return

	var batch_size: int = mini(UPDATES_PER_TICK, count)
	var start: int = _batch_cursor
	var end: int = start + batch_size

	if end <= count:
		_update_range(start, end, delta_ms)
		_batch_cursor = end % count
	else:
		_update_range(start, count, delta_ms)
		_update_range(0, end - count, delta_ms)
		_batch_cursor = end - count


func _update_range(from_index: int, to_index: int, delta_ms: float) -> void:
	for i: int in range(from_index, to_index):
		var id: int = _active_particles[i]
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if p.is_empty():
			continue
		_update_particle(p, delta_ms)


func _update_particle(p: Dictionary, delta_ms: float) -> void:
	var config: Dictionary = Particles.get_config(p["type"])

	# Apply gravity.
	var gravity: Vector2 = config.get("initialGravity", Vector2.ZERO)
	if gravity != Vector2.ZERO:
		p["velocity"] += gravity

	# Apply idle velocity changes.
	var idle: Dictionary = config.get("idleBehaviors", {}) as Dictionary
	var idle_vel: Variant = idle.get("changeVelocity")
	if idle_vel is Vector2 and idle_vel != Vector2.ZERO:
		p["velocity"] += idle_vel

	# Resolve movement and interactions.
	var moved: bool = _resolve_movement(p, config)
	if moved and not particles.has(p["id"]):
		return  # particle was destroyed during movement

	# Tick timers.
	_tick_timers(p, config, delta_ms)

	# Clamp velocity to avoid runaway values.
	p["velocity"] = p["velocity"].clamp(Vector2(-MAX_VELOCITY, -MAX_VELOCITY), Vector2(MAX_VELOCITY, MAX_VELOCITY))

	# If the particle has settled, stop spending cycles on it.
	if not _is_active(p):
		_deactivate_particle(p["id"])


func _resolve_movement(p: Dictionary, config: Dictionary) -> bool:
	var vel: Vector2 = p["velocity"]
	if vel == Vector2.ZERO:
		return false

	var attempts: Array
	var is_solid: bool = config.get("solid", false)
	var is_liquid: bool = config.get("liquid", false)
	if is_solid:
		# Solids fall straight down and slide down diagonal slopes.
		attempts = [Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1)]
	else:
		# Non-solids follow their velocity direction.
		var step: Vector2 = Vector2(signf(vel.x), signf(vel.y))
		attempts = _unique_dirs([
			Vector2(step.x, step.y),
			Vector2(0, step.y),
			Vector2(step.x, 0),
		])

	var pos: Vector2 = p["pos"]
	var moving_density: float = config.get("density", 1.0)

	for dir: Vector2 in attempts:
		var target: Vector2 = pos + dir
		var targets: Array = _get_particles_at(target)

		if targets.is_empty():
			_move_particle(p, target)
			return true

		var has_solid: bool = _cell_has_solid(target, targets)

		if has_solid:
			# Any particle is blocked by solids. Solids also pile up against each other.
			var result: Dictionary = _handle_collisions(p, targets)
			if result["destroyed"]:
				return true
			continue

		# No solids in target. Try density-based sinking when moving downward.
		var swap_target: Dictionary = {}
		if dir.y > 0:
			swap_target = _find_swap_target(targets, moving_density)
		if not swap_target.is_empty():
			_swap_particles(p, swap_target, pos, target)
			return true

		# Can't sink. Solids can't share cells with non-solids.
		if is_solid:
			var result: Dictionary = _handle_collisions(p, targets)
			if result["destroyed"]:
				return true
			continue

		# Can't sink. Liquids cannot share a cell with another liquid.
		if is_liquid and _cell_has_liquid(target, targets):
			var result: Dictionary = _handle_collisions(p, targets)
			if result["destroyed"]:
				return true
			continue

		# Otherwise move in and share the cell, triggering interactions.
		_move_particle(p, target)
		_handle_collisions(p, targets)
		return true

	return false


func _unique_dirs(dirs: Array) -> Array:
	var seen: Dictionary = {}
	var unique: Array = []
	for dir: Vector2 in dirs:
		if dir != Vector2.ZERO and not seen.has(dir):
			seen[dir] = true
			unique.append(dir)
	return unique


func _cell_has_solid(_pos: Vector2, particle_list: Array) -> bool:
	for other: Dictionary in particle_list:
		var other_config: Dictionary = Particles.get_config(other["type"])
		if other_config.get("solid", false):
			return true
	return false


func _move_particle(p: Dictionary, new_pos: Vector2) -> void:
	_remove_from_grid(p)
	p["pos"] = new_pos
	_add_to_grid(p)
	_activate_particle(p["id"])


func _find_swap_target(targets: Array, moving_density: float) -> Dictionary:
	var best: Dictionary = {}
	var best_density: float = INF
	for target: Dictionary in targets:
		var target_config: Dictionary = Particles.get_config(target["type"])
		if target_config.get("solid", false):
			continue
		var target_density: float = target_config.get("density", 1.0)
		if target_density < best_density:
			best_density = target_density
			best = target
	if best.is_empty():
		return {}
	if moving_density > best_density:
		return best
	return {}


func _swap_particles(a: Dictionary, b: Dictionary, a_pos: Vector2, b_pos: Vector2) -> void:
	_remove_from_grid(a)
	_remove_from_grid(b)
	a["pos"] = b_pos
	b["pos"] = a_pos
	_add_to_grid(a)
	_add_to_grid(b)
	_activate_particle(a["id"])
	_activate_particle(b["id"])


func _cell_has_liquid(_pos: Vector2, particle_list: Array) -> bool:
	for other: Dictionary in particle_list:
		var other_config: Dictionary = Particles.get_config(other["type"])
		if other_config.get("liquid", false):
			return true
	return false


func _handle_collisions(mover: Dictionary, targets: Array) -> Dictionary:
	var handled: bool = false
	var mover_destroyed: bool = false
	var mover_config: Dictionary = Particles.get_config(mover["type"])

	for target: Dictionary in targets:
		if mover_destroyed:
			break

		var target_config: Dictionary = Particles.get_config(target["type"])

		var mover_result: Dictionary = _apply_interaction(mover, target["type"], mover_config)
		handled = handled or mover_result["handled"]
		mover_destroyed = mover_result["destroyed"]

		if mover_destroyed:
			break

		var target_result: Dictionary = _apply_interaction(target, mover["type"], target_config)
		handled = handled or target_result["handled"]
		if target_result["activated"] and not target_result["destroyed"]:
			_activate_particle(target["id"])

	return {"handled": handled, "destroyed": mover_destroyed}


func _apply_interaction(subject: Dictionary, object_type: String, subject_config: Dictionary) -> Dictionary:
	var interactions: Dictionary = subject_config.get("interactions", {}) as Dictionary
	if not interactions.has(object_type):
		return {"handled": false, "destroyed": false, "activated": false}

	var inter: Dictionary = interactions[object_type] as Dictionary
	var destroyed: bool = inter.get("destroy", false)
	var activated: bool = false

	# Spawn any requested particles at the subject's position.
	for spawn_type: String in inter.get("spawn", []):
		_spawn_queue.append({"type": spawn_type, "pos": subject["pos"]})
		activated = true

	# Destroy self if requested.
	if destroyed:
		_destroy_particle(subject)
		return {"handled": true, "destroyed": true, "activated": false}

	# Reset specified timers on self.
	var reset_timers: Array = inter.get("resetTimers", [])
	for timer_name: String in reset_timers:
		var t: Dictionary = (subject_config.get("timers", {}) as Dictionary).get(timer_name, {}) as Dictionary
		if t.get("despawn") is int:
			subject["timers"][timer_name] = float(t["despawn"])
			activated = true

	return {"handled": true, "destroyed": false, "activated": activated}


func _tick_timers(p: Dictionary, config: Dictionary, delta_ms: float) -> void:
	var timers: Dictionary = config.get("timers", {}) as Dictionary
	var expired: Array = []

	for timer_name: String in p["timers"]:
		if not timers.has(timer_name):
			expired.append(timer_name)
			continue
		p["timers"][timer_name] -= delta_ms
		if p["timers"][timer_name] <= 0.0:
			expired.append(timer_name)

	for timer_name: String in expired:
		p["timers"].erase(timer_name)
		var t: Dictionary = timers[timer_name] as Dictionary

		var despawn: Variant = t.get("despawn")
		if despawn is int:
			_destroy_particle(p)
			return

		for spawn_type: String in t.get("spawn", []):
			_spawn_queue.append({"type": spawn_type, "pos": p["pos"]})

		var vel_change: Variant = t.get("changeVelocity")
		if vel_change is Vector2:
			p["velocity"] += vel_change
