extends Node2D

const Particles = preload("res://Scripts/Singletons/Particles.gd")

enum Tool {
	PAINT,
	ERASE,
	SELECT
}

signal tool_changed(tool: Tool)
signal selected_particle_changed(type_name: String)
signal particle_selected(data: Dictionary, grid_pos: Vector2)
signal dev_mode_changed(enabled: bool)
signal brush_radius_changed(radius: int)

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
		brush_radius_changed.emit(brush_radius)

var _current_tool: Tool = Tool.PAINT

var _camera: Camera2D
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup_camera()
	set_process_input(dev_mode_enabled)
	set_process(dev_mode_enabled)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "DevCamera"
	_camera.position = Vector2(
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE * 0.5,
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE * 0.5
	)
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
			_zoom_camera(ZOOM_FACTOR)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / ZOOM_FACTOR)
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			if _is_panning:
				_pan_start_mouse = event.position
				_pan_start_position = _camera.position
			return
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_perform_tool_action(_mouse_to_grid())


func _process(_delta: float) -> void:
	if not dev_mode_enabled:
		return

	if _is_panning:
		var mouse_delta: Vector2 = _pan_start_mouse - get_viewport().get_mouse_position()
		_camera.position = _pan_start_position + mouse_delta / _camera.zoom
		_clamp_camera()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_perform_tool_action(_mouse_to_grid())


func _zoom_camera(factor: float) -> void:
	var new_zoom: float = clampf(_camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(new_zoom, new_zoom)


func _clamp_camera() -> void:
	var world_size: Vector2 = Vector2(
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE,
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE
	)
	var visible_size: Vector2 = get_viewport_rect().size / _camera.zoom
	var min_pos: Vector2 = visible_size * 0.5
	var max_pos: Vector2 = world_size - visible_size * 0.5
	_camera.position.x = clampf(_camera.position.x, mini(min_pos.x, max_pos.x), maxi(min_pos.x, max_pos.x))
	_camera.position.y = clampf(_camera.position.y, mini(min_pos.y, max_pos.y), maxi(min_pos.y, max_pos.y))


func set_tool(tool: Tool) -> void:
	_current_tool = tool
	tool_changed.emit(tool)


func get_current_tool() -> Tool:
	return _current_tool


func set_selected_particle(type_name: String) -> void:
	if not Particles.TYPES.has(type_name):
		push_warning("Unknown particle type selected: ", type_name)
		return
	selected_particle = type_name
	selected_particle_changed.emit(type_name)


func clear_all_particles() -> void:
	for pos: Vector2 in SimulationGlobal.grid.keys():
		SimulationGlobal.despawnParticle(pos)


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


func _spawn_brush(center: Vector2) -> void:
	for x: int in range(-brush_radius + 1, brush_radius):
		for y: int in range(-brush_radius + 1, brush_radius):
			SimulationGlobal.spawnParticle(selected_particle, center + Vector2(x, y))


func _erase_brush(center: Vector2) -> void:
	for x: int in range(-brush_radius + 1, brush_radius):
		for y: int in range(-brush_radius + 1, brush_radius):
			SimulationGlobal.despawnParticle(center + Vector2(x, y))


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
		KEY_BRACKETLEFT, KEY_MINUS:
			brush_radius -= 1
		KEY_BRACKETRIGHT, KEY_EQUAL:
			brush_radius += 1
		KEY_P:
			get_tree().paused = not get_tree().paused
