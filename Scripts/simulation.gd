extends Node2D

const WorldRenderer = preload("res://Scripts/WorldRenderer.gd")
const DevToolsController = preload("res://Scripts/DevToolsController.gd")
const DevUI = preload("res://Scenes/DevUI.tscn")

@export var dev_mode_enabled: bool = true:
	set(value):
		dev_mode_enabled = value
		if _tools_controller != null:
			_tools_controller.dev_mode_enabled = value

var _renderer: WorldRenderer
var _tools_controller: DevToolsController
var _ui: CanvasLayer


func _ready() -> void:
	_setup_renderer()
	_setup_tools()
	_setup_ui()
	_setup_viewport()


func _setup_renderer() -> void:
	_renderer = WorldRenderer.new()
	_renderer.name = "WorldRenderer"
	_renderer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_renderer)


func _setup_tools() -> void:
	_tools_controller = DevToolsController.new()
	_tools_controller.name = "DevToolsController"
	_tools_controller.dev_mode_enabled = dev_mode_enabled
	_tools_controller.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_tools_controller)


func _setup_ui() -> void:
	_ui = DevUI.instantiate()
	_ui.name = "DevUI"
	_ui.tools_controller = _tools_controller
	_ui.visible = dev_mode_enabled
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)


func _setup_viewport() -> void:
	var viewport_size: Vector2 = Vector2(
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE,
		Global.WORLD_GRID_SIZE * Global.WORLD_PIXEL_SCALE
	)
	get_viewport().size = viewport_size
