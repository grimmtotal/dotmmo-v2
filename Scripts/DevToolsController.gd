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

@export var dev_mode_enabled: bool = true:
	set(value):
		dev_mode_enabled = value
		dev_mode_changed.emit(value)
		set_process(value)
		set_process_input(value)

@export var selected_particle: String = "Sand"
@export var brush_radius: int = 1

var _current_tool: Tool = Tool.PAINT


func _ready() -> void:
	set_process_input(dev_mode_enabled)
	set_process(dev_mode_enabled)


func _input(event: InputEvent) -> void:
	if not dev_mode_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_match_hotkey(event.keycode)

	if event is InputEventMouseButton and event.pressed:
		_perform_tool_action(_mouse_to_grid())


func _process(_delta: float) -> void:
	if not dev_mode_enabled:
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_perform_tool_action(_mouse_to_grid())


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
		KEY_P:
			get_tree().paused = not get_tree().paused
