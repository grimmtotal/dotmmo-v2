extends Node2D

const Particles = preload("res://Scripts/Singletons/Particles.gd")
const BrushCursor = preload("res://Scripts/BrushCursor.gd")
const CollectorBox = preload("res://Scripts/CollectorBox.gd")
const Player = preload("res://Scripts/Player.gd")
const Projectiles = preload("res://Scripts/Projectiles.gd")

enum Tool {
	PAINT,
	ERASE,
	SELECT,
	BOX,
	FLAME,
	STEAM,
	BREAKER
}

signal tool_changed(tool: Tool)
signal selected_particle_changed(type_name: String)
signal particle_selected(data: Dictionary, grid_pos: Vector2)
signal dev_mode_changed(enabled: bool)
signal brush_radius_changed(radius: int)

## Cursor colours for the tools that are not about a material. Paint takes the
## selected material's own colour instead, so the cursor always says what a
## click will do without anyone reading the toolbar.
const ERASE_COLOR: Color = Color(1.0, 0.36, 0.36)
const SELECT_COLOR: Color = Color(0.55, 0.9, 1.0)
const BOX_COLOR: Color = Color(0.85, 0.9, 1.0)
const BREAKER_COLOR: Color = Color(0.95, 0.82, 0.5)

## The guns, as ballistics rather than as area effects.
##
## Every one of these fires a shot that leaves the muzzle along the aim and
## travels until it hits something, so where a gun lands its material is decided
## by the flight rather than by the cursor - the arc, the range and whatever is
## in the way all get a say. Shots resolve into ordinary particles when they
## land, which is what puts the simulation's own reactions in charge of the
## result: nothing here says a fireball into water makes steam.
##
## `speed` is muzzle velocity in pixels a second, `gravity` the pull on the shot
## while it flies - negative for the things that rise, so flame and steam arc
## upward the way the materials themselves do. `spread` is the half-angle of the
## muzzle cone in radians, which is what keeps a held trigger from drawing a
## straight line of beads. `rate` is far lower than the old area tools used:
## with a shot you can watch travelling, fifteen a second is already a torrent.
const GUNS: Dictionary = {
	Tool.FLAME: {
		"material": "Fire", "rate": 15.0, "speed": 1500.0,
		"gravity": -700.0, "spread": 0.11, "life": 1.1,
	},
	Tool.STEAM: {
		"material": "Steam", "rate": 15.0, "speed": 1200.0,
		"gravity": -1100.0, "spread": 0.15, "life": 1.1,
	},
	# Breaks rock instead of leaving anything behind, so it carries no material.
	# Slow, fast and tightly grouped: a single heavy round you aim, and the only
	# way to get carryable matter out of terrain.
	Tool.BREAKER: {
		"material": "", "breaks": true, "rate": 5.0, "speed": 2400.0,
		"gravity": 0.0, "spread": 0.015, "life": 0.7,
	},
}

## Ceiling on a single frame's shots, so a hitch does not empty a whole second
## of the gun down the barrel at once.
const MAX_SHOTS_PER_FRAME: int = 8

## How far from the body a shot starts, so it leaves at arm's length rather than
## out of the middle of the chest.
const MUZZLE_OFFSET: float = 26.0

## The tools the character holds, as opposed to the ones that edit the world.
##
## Both kinds act where the pointer is - the difference is what supplies the
## rest. A gun takes only its direction from the body and leaves the flight to
## decide where its shot ends up, and the box draws itself instead of using the
## brush outline. The editor tools keep the plain brush box, because placing
## terrain is a thing you do to the world rather than a thing the character does
## in it.
const BODY_TOOLS: Array[Tool] = [Tool.BOX, Tool.FLAME, Tool.STEAM, Tool.BREAKER]

## How fast the camera closes on the character, as a fraction of the remaining
## distance a second. Following exactly makes the whole world twitch with every
## step; lagging slightly lets the body move within the frame.
const CAMERA_LAG: float = 8.0


const MIN_ZOOM: float = 0.2
const MAX_ZOOM: float = 4.0
const ZOOM_FACTOR: float = 1.1

@export var dev_mode_enabled: bool = true:
	set(value):
		dev_mode_enabled = value
		dev_mode_changed.emit(value)
		set_process(value)
		set_process_input(value)

@export var selected_particle: String = "Sand"
@export var brush_radius: int = 1:
	set(value):
		brush_radius = clampi(value, 1, 20)
		if _cursor != null:
			_cursor.radius = brush_radius
		brush_radius_changed.emit(brush_radius)

var _current_tool: Tool = Tool.PAINT

## The character. Set by the scene once it exists; everything here still works
## without one, falling back to the cursor for every tool.
var player: Player = null

var _cursor: BrushCursor
var _box: CollectorBox
var _projectiles: Projectiles
## Cleared when the pointer is used to look around, restored the moment the
## character is walked again.
var _camera_follows: bool = true
## Fractional shots carried between frames, so a gun's rate is honoured even
## when it does not divide evenly into a frame.
var _shot_credit: float = 0.0
var _camera: Camera2D
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_camera()
	_setup_projectiles()
	_setup_cursor()
	_setup_box()
	set_process_input(dev_mode_enabled)
	set_process(dev_mode_enabled)


func _setup_cursor() -> void:
	_cursor = BrushCursor.new()
	_cursor.name = "BrushCursor"
	_cursor.radius = brush_radius
	_cursor.z_index = 100
	add_child(_cursor)
	_refresh_cursor_color()


func _setup_projectiles() -> void:
	_projectiles = Projectiles.new()
	_projectiles.name = "Projectiles"
	_projectiles.z_index = 60
	add_child(_projectiles)


func _setup_box() -> void:
	_box = CollectorBox.new()
	_box.name = "CollectorBox"
	_box.z_index = 99
	add_child(_box)


func _refresh_cursor_color() -> void:
	if _cursor == null:
		return
	match _current_tool:
		Tool.ERASE:
			_cursor.color = ERASE_COLOR
		Tool.SELECT:
			_cursor.color = SELECT_COLOR
		Tool.BOX:
			_cursor.color = BOX_COLOR
		Tool.BREAKER:
			_cursor.color = BREAKER_COLOR
		Tool.FLAME, Tool.STEAM:
			_cursor.color = _material_color(GUNS[_current_tool]["material"])
		_:
			_cursor.color = _material_color(selected_particle)


## The first colour a material is drawn with, brightened so the cursor reads as
## an overlay rather than a stray particle of that material.
func _material_color(type_name: String) -> Color:
	var colours: Array = Particles.get_config(type_name).get("colors", [])
	if colours.is_empty():
		return Color.WHITE
	return Color(colours[0] as String).lightened(0.35)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "DevCamera"
	_camera.position = Vector2(Global.WORLD_PIXELS) * 0.5
	if player != null:
		_camera.position = player.centre()
	_camera.zoom = Vector2.ONE
	_camera.enabled = true
	add_child(_camera)
	_camera.call_deferred("make_current")


func _input(event: InputEvent) -> void:
	if not dev_mode_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_match_hotkey(event.keycode)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not _is_pointer_over_ui():
				_zoom_camera(ZOOM_FACTOR)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not _is_pointer_over_ui():
				_zoom_camera(1.0 / ZOOM_FACTOR)
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			if _is_panning:
				_camera_follows = false
				_pan_start_mouse = event.position
				_pan_start_position = _camera.position
			return
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _is_pointer_over_ui():
			_perform_tool_action(_mouse_to_grid())


func _process(delta: float) -> void:
	if not dev_mode_enabled:
		return

	if _is_panning:
		var mouse_delta: Vector2 = _pan_start_mouse - get_viewport().get_mouse_position()
		_camera.position = _pan_start_position + mouse_delta / _camera.zoom
		_clamp_camera()

	_follow_player(delta)

	var over_ui: bool = _is_pointer_over_ui()
	# The brush box means nothing to a gun that goes where it is pointed, and
	# the box draws itself, so the brush box belongs to the editor tools alone.
	_cursor.visible = not over_ui and not _is_body_tool()
	_box.visible = not over_ui and _current_tool == Tool.BOX
	if not over_ui:
		# Every tool acts where the pointer is. The box used to sit at the end
		# of a reach cast from the body, which meant it lagged behind the mouse
		# and hung off the character on a line - the box is the thing you are
		# pointing with, so it goes where you point it.
		_cursor.grid_position = _mouse_to_grid()
		if _current_tool == Tool.BOX:
			var target: Vector2 = _cursor.grid_position
			_box.aim_at(_brush_cells(target), _aim_point(target), brush_radius)

	# The box is worked by dragging rather than clicking: hold left to sweep
	# material in, hold right to pour it back out.
	if _current_tool == Tool.BOX:
		if over_ui:
			return
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_box.scoop()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_box.pour()
		return

	if over_ui or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Primed, so the next trigger pull fires on its first frame instead of
		# waiting out a fraction of the rate.
		_shot_credit = 1.0
		return

	match _current_tool:
		Tool.PAINT, Tool.ERASE, Tool.SELECT:
			_perform_tool_action(_cursor.grid_position)
		Tool.FLAME, Tool.STEAM, Tool.BREAKER:
			_fire(delta, _cursor.grid_position)
		_:
			pass


func _is_body_tool() -> bool:
	return player != null and BODY_TOOLS.has(_current_tool)


## Walking the character takes the camera back, so looking around with the
## pointer is a glance rather than a mode you have to leave.
func _follow_player(delta: float) -> void:
	if player == null:
		return

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) \
			or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT):
		_camera_follows = true

	if not _camera_follows or _is_panning:
		return

	_camera.position = _camera.position.lerp(
		player.centre(), minf(CAMERA_LAG * delta, 1.0))
	_clamp_camera()


func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _zoom_camera(factor: float) -> void:
	var new_zoom: float = clampf(_camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(new_zoom, new_zoom)


func _clamp_camera() -> void:
	var world_size: Vector2 = Vector2(Global.WORLD_PIXELS)
	var visible_size: Vector2 = get_viewport_rect().size / _camera.zoom
	var min_pos: Vector2 = visible_size * 0.5
	var max_pos: Vector2 = world_size - visible_size * 0.5
	_camera.position.x = clampf(_camera.position.x, minf(min_pos.x, max_pos.x), maxf(min_pos.x, max_pos.x))
	_camera.position.y = clampf(_camera.position.y, minf(min_pos.y, max_pos.y), maxf(min_pos.y, max_pos.y))


func set_tool(tool: Tool) -> void:
	# Anything still in the box is put down before the box goes away, or it
	# would sit out of the world with nothing on screen to say it exists.
	if _current_tool == Tool.BOX and tool != Tool.BOX and _box != null:
		_box.empty_out()

	_current_tool = tool
	_refresh_cursor_color()
	tool_changed.emit(tool)


func get_current_tool() -> Tool:
	return _current_tool


func set_selected_particle(type_name: String) -> void:
	if not Particles.TYPES.has(type_name):
		push_warning("Unknown particle type selected: ", type_name)
		return
	selected_particle = type_name
	_refresh_cursor_color()
	selected_particle_changed.emit(type_name)


func clear_all_particles() -> void:
	SimulationGlobal.clearAll()


func _mouse_to_grid() -> Vector2:
	var mouse_pos: Vector2 = get_global_mouse_position()
	return Vector2(floor(mouse_pos.x / Global.WORLD_PIXEL_SCALE), floor(mouse_pos.y / Global.WORLD_PIXEL_SCALE))


func _perform_tool_action(grid_pos: Vector2) -> void:
	match _current_tool:
		Tool.PAINT:
			_spawn_brush(grid_pos)
		Tool.ERASE:
			_erase_brush(grid_pos)
		Tool.SELECT:
			_select_particle(grid_pos)
		Tool.FLAME, Tool.STEAM, Tool.BREAKER:
			_fire(0.0, grid_pos)


## Where the box measures "nearest" from: the point being aimed at, in world
## pixels, which is what the pointer actually controls.
func _aim_point(target: Vector2) -> Vector2:
	return (target + Vector2(0.5, 0.5)) * float(Global.WORLD_PIXEL_SCALE)


## Fires the active gun for one frame's worth of its rate. `delta` of zero is
## the click itself, which spends the credit primed while the trigger was up and
## so always gets one shot away immediately.
##
## `fallback` is only reached without a character to fire from - the editor
## still has to be usable then, so shots leave the cursor pointing right.
func _fire(delta: float, fallback: Vector2) -> void:
	var config: Dictionary = GUNS[_current_tool] as Dictionary

	_shot_credit += float(config["rate"]) * delta
	var shots: int = mini(int(_shot_credit), MAX_SHOTS_PER_FRAME)
	if shots <= 0:
		return
	_shot_credit -= float(shots)

	var direction: Vector2 = Vector2.RIGHT
	var muzzle: Vector2 = (fallback + Vector2(0.5, 0.5)) * Global.WORLD_PIXEL_SCALE
	if player != null:
		direction = player.aim_direction()
		muzzle = player.centre() + direction * MUZZLE_OFFSET

	for shot: int in shots:
		_projectiles.fire(muzzle, direction, config)


func _spawn_brush(center: Vector2) -> void:
	for cell: Vector2 in _brush_cells(center):
		SimulationGlobal.spawnParticle(selected_particle, cell)


func _erase_brush(center: Vector2) -> void:
	for cell: Vector2 in _brush_cells(center):
		SimulationGlobal.despawnParticle(cell)


func _brush_cells(center: Vector2) -> Array:
	if brush_radius <= 1:
		return [center]

	var cells: Array = []
	var limit: float = float(brush_radius) - 0.5
	for x: int in range(-brush_radius + 1, brush_radius):
		for y: int in range(-brush_radius + 1, brush_radius):
			if Vector2(x, y).length() <= limit:
				cells.append(center + Vector2(x, y))
	return cells


func _select_particle(grid_pos: Vector2) -> void:
	var data: Dictionary = SimulationGlobal.getParticle(grid_pos)
	particle_selected.emit(data, grid_pos)


func _match_hotkey(key: int) -> void:
	match key:
		KEY_1:
			set_tool(Tool.PAINT)
		KEY_2:
			set_tool(Tool.ERASE)
		KEY_3:
			set_tool(Tool.SELECT)
		KEY_4:
			set_tool(Tool.BOX)
		KEY_5:
			set_tool(Tool.FLAME)
		KEY_6:
			set_tool(Tool.STEAM)
		KEY_7:
			set_tool(Tool.BREAKER)
		KEY_BRACKETLEFT, KEY_MINUS:
			brush_radius -= 1
		KEY_BRACKETRIGHT, KEY_EQUAL:
			brush_radius += 1
		KEY_P:
			get_tree().paused = not get_tree().paused
