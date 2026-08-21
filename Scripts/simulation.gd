extends Node2D

const WorldRenderer = preload("res://Scripts/WorldRenderer.gd")
const DevToolsController = preload("res://Scripts/DevToolsController.gd")
const Player = preload("res://Scripts/Player.gd")
const DevUI = preload("res://Scenes/DevUI.tscn")

## Somewhere to stand at startup.
##
## The world generates empty, so without this the character spawns over a drop
## the height of the world onto its floor, with nothing to walk on when it gets
## there. This is scaffolding for that and nothing more - a shelf to stand on, a
## pool to swim in and a stand of plants to set fire to, so every tool has
## something to be tried on. Delete _build_spawn_ground and the world is a blank
## sheet again.
const GROUND_TOP: int = 72
const GROUND_WIDTH: int = 90
const GROUND_DEPTH: int = 40

@export var dev_mode_enabled: bool = true:
	set(value):
		dev_mode_enabled = value
		if _tools_controller != null:
			_tools_controller.dev_mode_enabled = value

var _renderer: WorldRenderer
var _tools_controller: DevToolsController
var _player: Player
var _ui: CanvasLayer
var _spawn_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_spawn_ground()
	_setup_renderer()
	_setup_player()
	_setup_tools()
	_setup_ui()


func _build_spawn_ground() -> void:
	var left: int = (Global.WORLD_WIDTH - GROUND_WIDTH) / 2
	var scale: int = Global.WORLD_PIXEL_SCALE

	for x: int in range(left, left + GROUND_WIDTH):
		# A dip a quarter of the way along, for the water to sit in.
		var pool: bool = x > left + 24 and x < left + 40
		var surface: int = GROUND_TOP + (3 if pool else 0)

		# Stone below the surface, with a layer of sand over it where the ground
		# is dry. Order matters: a cell already holding stone refuses the sand,
		# so the sand row has to be left out of the stone fill rather than
		# painted over it.
		for y: int in range(surface + 1, GROUND_TOP + GROUND_DEPTH):
			SimulationGlobal.spawnParticle("Stone", Vector2(x, y))

		if pool:
			for y: int in range(GROUND_TOP, surface + 1):
				SimulationGlobal.spawnParticle("Water", Vector2(x, y))
		else:
			SimulationGlobal.spawnParticle("Sand", Vector2(x, surface))

	for x: int in range(left + 60, left + 72):
		for y: int in range(GROUND_TOP - 4, GROUND_TOP):
			SimulationGlobal.spawnParticle("Plant", Vector2(x, y))

	_spawn_point = Vector2((left + 8 + 0.5) * scale, GROUND_TOP * scale)


func _setup_player() -> void:
	_player = Player.new()
	_player.name = "Player"
	_player.position = _spawn_point
	_player.z_index = 50
	add_child(_player)


func _setup_renderer() -> void:
	_renderer = WorldRenderer.new()
	_renderer.name = "WorldRenderer"
	_renderer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_renderer)


func _setup_tools() -> void:
	_tools_controller = DevToolsController.new()
	_tools_controller.name = "DevToolsController"
	_tools_controller.player = _player
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

