extends CanvasLayer

const Particles = preload("res://Scripts/Singletons/Particles.gd")
const DevToolsController = preload("res://Scripts/DevToolsController.gd")

const SWATCH_SIZE: int = 26
const LABEL_COLOR: String = "#a6adbb"
const STATS_INTERVAL: float = 0.25

@export var tools_controller: DevToolsController

var _particle_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _button_group: ButtonGroup = ButtonGroup.new()
var _stats_countdown: float = 0.0


func _ready() -> void:
	if tools_controller == null:
		push_warning("DevUI: tools_controller is not assigned.")
		return

	_connect_toolbar()
	_build_palette()

	tools_controller.tool_changed.connect(_on_tool_changed)
	tools_controller.selected_particle_changed.connect(_show_particle_details)
	tools_controller.particle_selected.connect(_on_particle_inspected)
	tools_controller.dev_mode_changed.connect(_on_dev_mode_changed)
	tools_controller.brush_radius_changed.connect(_on_brush_radius_changed)

	%BrushSlider.value = tools_controller.brush_radius
	_on_brush_radius_changed(tools_controller.brush_radius)
	_show_particle_details(tools_controller.selected_particle)


func _process(delta: float) -> void:
	_stats_countdown -= delta
	if _stats_countdown > 0.0:
		return
	_stats_countdown = STATS_INTERVAL

	%Stats.text = "%d particles  ·  %d awake  ·  %d Hz  ·  %d fps" % [
		SimulationGlobal.getParticleCount(),
		SimulationGlobal.getActiveCount(),
		roundi(SimulationGlobal.getTickRate()),
		Engine.get_frames_per_second(),
	]


# Toolbar

func _connect_toolbar() -> void:
	%PlayButton.toggled.connect(_on_play_toggled)
	%ClearButton.pressed.connect(tools_controller.clear_all_particles)
	%BrushSlider.value_changed.connect(_on_brush_slider_changed)

	_tool_buttons = {
		DevToolsController.Tool.PAINT: %Tools.get_node("Paint"),
		DevToolsController.Tool.ERASE: %Tools.get_node("Erase"),
		DevToolsController.Tool.SELECT: %Tools.get_node("Select"),
	}

	var tool_group: ButtonGroup = ButtonGroup.new()
	for tool: int in _tool_buttons:
		var button: Button = _tool_buttons[tool]
		button.button_group = tool_group
		button.pressed.connect(tools_controller.set_tool.bind(tool))


# Palette

func _build_palette() -> void:
	for type_name: String in Particles.TYPES:
		var button: Button = _make_palette_entry(type_name)
		%ParticleList.add_child(button)
		_particle_buttons[type_name] = button

	_highlight_selected(tools_controller.selected_particle)


func _make_palette_entry(type_name: String) -> Button:
	var config: Dictionary = Particles.get_config(type_name)

	var button: Button = Button.new()
	button.name = type_name
	button.text = "  " + type_name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_group = _button_group
	button.custom_minimum_size = Vector2(0, 34)
	button.icon = _make_swatch_texture(config.get("colors", []))
	button.tooltip_text = _describe_particle(type_name, config, false)
	button.pressed.connect(tools_controller.set_selected_particle.bind(type_name))
	return button


func _make_swatch_texture(colors: Array) -> ImageTexture:
	var stripes: int = maxi(colors.size(), 1)
	var image: Image = Image.create(stripes, 1, false, Image.FORMAT_RGBA8)
	for i: int in stripes:
		image.set_pixel(i, 0, _color_at(colors, i))
	image.resize(SWATCH_SIZE, SWATCH_SIZE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func _color_at(colors: Array, index: int) -> Color:
	if colors.is_empty():
		return Color.MAGENTA
	return Color(colors[index % colors.size()])


# Details panel

func _show_particle_details(type_name: String, extra: String = "") -> void:
	_highlight_selected(type_name)

	if type_name.is_empty() or not Particles.TYPES.has(type_name):
		%DetailName.text = "Nothing selected"
		%DetailSwatch.color = Color(0, 0, 0, 0.35)
		%InfoLabel.text = extra
		return

	var config: Dictionary = Particles.get_config(type_name)
	%DetailName.text = type_name
	%DetailSwatch.color = _color_at(config.get("colors", []), 0)

	var text: String = _describe_particle(type_name, config, true)
	if not extra.is_empty():
		text += "\n" + extra
	%InfoLabel.text = text


func _describe_particle(type_name: String, config: Dictionary, rich: bool) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if not rich:
		lines.append(type_name)

	lines.append(_field("State", _state_name(config), rich))
	lines.append(_field("Density", "%.2f" % float(config.get("density", 1.0)), rich))
	lines.append(_field("Falls", _gravity_name(config.get("initialGravity", Vector2.ZERO)), rich))

	var reactions: PackedStringArray = _reaction_lines(config)
	if not reactions.is_empty():
		lines.append(_field("Reacts with", "", rich))
		for line: String in reactions:
			lines.append("   " + line)

	var lifespan: String = _lifespan_text(config)
	if not lifespan.is_empty():
		lines.append(_field("Lifespan", lifespan, rich))

	return "\n".join(lines)


func _field(label: String, value: String, rich: bool) -> String:
	var heading: String = "[color=%s]%s:[/color]" % [LABEL_COLOR, label] if rich else label + ":"
	if value.is_empty():
		return heading
	return "%s %s" % [heading, value]


func _state_name(config: Dictionary) -> String:
	if config.get("solid", false):
		return "Solid"
	if config.get("liquid", false):
		return "Liquid"
	return "Gas"


func _gravity_name(gravity: Vector2) -> String:
	if is_zero_approx(gravity.y):
		return "Stays in place"
	return "Downward" if gravity.y > 0.0 else "Upward"


func _reaction_lines(config: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var interactions: Dictionary = config.get("interactions", {}) as Dictionary

	for target: String in interactions:
		var inter: Dictionary = interactions[target] as Dictionary
		var effects: PackedStringArray = PackedStringArray()
		if inter.get("destroy", false):
			effects.append("is consumed")
		var spawned: Array = inter.get("spawn", [])
		if not spawned.is_empty():
			effects.append("creates " + ", ".join(spawned))
		if effects.is_empty():
			continue
		lines.append("%s -> %s" % [target, " and ".join(effects)])

	return lines


func _lifespan_text(config: Dictionary) -> String:
	var timers: Dictionary = config.get("timers", {}) as Dictionary
	for timer_name: String in timers:
		var despawn: Variant = (timers[timer_name] as Dictionary).get("despawn")
		if despawn is int:
			return "%.1fs" % (float(despawn) / 1000.0)
	return ""


# Signal handlers

func _on_tool_changed(tool: DevToolsController.Tool) -> void:
	if _tool_buttons.has(tool):
		_tool_buttons[tool].button_pressed = true


func _on_particle_inspected(data: Dictionary, grid_pos: Vector2) -> void:
	if data.is_empty():
		_show_particle_details("", "Nothing at %d, %d." % [grid_pos.x, grid_pos.y])
		return

	_show_particle_details(data.get("type", ""), _field(
		"Position", "%d, %d" % [grid_pos.x, grid_pos.y], true
	))


func _on_dev_mode_changed(enabled: bool) -> void:
	visible = enabled


func _on_play_toggled(paused: bool) -> void:
	get_tree().paused = paused
	%PlayButton.text = "Play" if paused else "Pause"


func _on_brush_slider_changed(value: float) -> void:
	tools_controller.brush_radius = int(value)


func _on_brush_radius_changed(radius: int) -> void:
	%BrushSlider.set_value_no_signal(radius)
	%BrushValue.text = str(radius)


func _highlight_selected(type_name: String) -> void:
	if _particle_buttons.has(type_name):
		_particle_buttons[type_name].button_pressed = true
