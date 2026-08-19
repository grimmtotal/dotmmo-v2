extends CanvasLayer

const Particles = preload("res://Scripts/Singletons/Particles.gd")
const DevToolsController = preload("res://Scripts/DevToolsController.gd")

@export var tools_controller: DevToolsController

var _particle_buttons: Dictionary = {}
var _info_label: Label
var _play_button: Button
var _brush_label: Label


func _ready() -> void:
	if tools_controller == null:
		push_warning("DevUI: tools_controller is not assigned.")
		return

	_info_label = %InfoLabel
	_build_toolbar()
	_build_particle_picker()

	tools_controller.tool_changed.connect(_on_tool_changed)
	tools_controller.selected_particle_changed.connect(_on_selected_particle_changed)
	tools_controller.particle_selected.connect(_on_particle_inspected)
	tools_controller.dev_mode_changed.connect(_on_dev_mode_changed)
	tools_controller.brush_radius_changed.connect(_on_brush_radius_changed)

	_update_info_panel(tools_controller.selected_particle)
	_update_brush_label(tools_controller.brush_radius)


func _build_toolbar() -> void:
	var toolbar: HBoxContainer = %Toolbar

	_play_button = Button.new()
	_play_button.text = "Pause"
	_play_button.toggle_mode = true
	_play_button.button_pressed = false
	_play_button.toggled.connect(_on_play_toggled)
	toolbar.add_child(_play_button)

	var clear_button: Button = Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(tools_controller.clear_all_particles)
	toolbar.add_child(clear_button)

	toolbar.add_child(_tool_button("Paint", DevToolsController.Tool.PAINT, true))
	toolbar.add_child(_tool_button("Erase", DevToolsController.Tool.ERASE))
	toolbar.add_child(_tool_button("Select", DevToolsController.Tool.SELECT))

	_brush_label = Label.new()
	_brush_label.name = "BrushLabel"
	_brush_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar.add_child(_brush_label)


func _tool_button(text: String, tool: DevToolsController.Tool, active: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = active
	button.toggled.connect(func(is_pressed: bool) -> void:
		if is_pressed:
			tools_controller.set_tool(tool)
	)
	button.name = text
	return button


func _build_particle_picker() -> void:
	var list: VBoxContainer = %ParticleList

	for type_name: String in Particles.TYPES.keys():
		var config: Dictionary = Particles.get_config(type_name)
		var button: Button = Button.new()
		button.text = type_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = _format_particle_tooltip(type_name, config)
		button.pressed.connect(func() -> void:
			tools_controller.set_selected_particle(type_name)
		)
		list.add_child(button)
		_particle_buttons[type_name] = button

	_highlight_selected(tools_controller.selected_particle)


func _format_particle_tooltip(type_name: String, config: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s" % type_name)
	lines.append("Gravity: %s" % str(config.get("initialGravity", Vector2.ZERO)))
	lines.append("Solid: %s" % str(config.get("solid", false)))
	lines.append("Liquid: %s" % str(config.get("liquid", false)))
	lines.append("Density: %s" % str(config.get("density", 1.0)))

	var timers: Dictionary = config.get("timers", {}) as Dictionary
	if not timers.is_empty():
		lines.append("Timers:")
		for timer_name: String in timers:
			var t: Dictionary = timers[timer_name] as Dictionary
			lines.append("  %s: despawn=%s spawn=%s" % [timer_name, str(t.get("despawn")), str(t.get("spawn"))])

	var interactions: Dictionary = config.get("interactions", {}) as Dictionary
	if not interactions.is_empty():
		lines.append("Interactions:")
		for target: String in interactions:
			var inter: Dictionary = interactions[target] as Dictionary
			lines.append("  -> %s: destroy=%s spawn=%s reset=%s" % [
				target, str(inter.get("destroy", false)), str(inter.get("spawn", [])), str(inter.get("resetTimers", []))
			])

	return "\n".join(lines)


func _on_tool_changed(tool: DevToolsController.Tool) -> void:
	var tool_name: String = DevToolsController.Tool.keys()[tool]
	for child in %Toolbar.get_children():
		if child is Button and child.name in ["Paint", "Erase", "Select"]:
			child.button_pressed = child.name == tool_name


func _on_selected_particle_changed(type_name: String) -> void:
	_highlight_selected(type_name)
	_update_info_panel(type_name)


func _on_particle_inspected(data: Dictionary, _grid_pos: Vector2) -> void:
	if data.is_empty():
		_update_info_panel(tools_controller.selected_particle, "No particle selected.")
	else:
		_update_info_panel(data.get("type", ""), "Grid: %s\nVelocity: %s\nTimers: %s" % [
			str(_grid_pos), str(data.get("velocity", Vector2.ZERO)), str(data.get("timers", {}))
		])


func _on_dev_mode_changed(enabled: bool) -> void:
	visible = enabled


func _on_play_toggled(pressed: bool) -> void:
	get_tree().paused = pressed
	_play_button.text = "Play" if pressed else "Pause"


func _on_brush_radius_changed(radius: int) -> void:
	_update_brush_label(radius)


func _update_brush_label(radius: int) -> void:
	if _brush_label != null:
		_brush_label.text = "Brush: %d" % radius


func _highlight_selected(type_name: String) -> void:
	for name: String in _particle_buttons:
		var button: Button = _particle_buttons[name]
		button.disabled = (name == type_name)


func _update_info_panel(type_name: String, extra: String = "") -> void:
	if type_name.is_empty() or not Particles.TYPES.has(type_name):
		_info_label.text = extra
		return
	var config: Dictionary = Particles.get_config(type_name)
	var text: String = _format_particle_tooltip(type_name, config)
	if not extra.is_empty():
		text += "\n\n" + extra
	_info_label.text = text
