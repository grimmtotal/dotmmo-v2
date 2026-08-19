extends Node2D

const Particles = preload("res://Scripts/Singletons/Particles.gd")

var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D


func _ready() -> void:
	_image = Image.create(Global.WORLD_GRID_SIZE, Global.WORLD_GRID_SIZE, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.scale = Vector2(Global.WORLD_PIXEL_SCALE, Global.WORLD_PIXEL_SCALE)
	add_child(_sprite)


func _process(_delta: float) -> void:
	_render_frame()


func _render_frame() -> void:
	_image.fill(Color.TRANSPARENT)

	var grid: Dictionary = SimulationGlobal.grid
	var particle_data: Dictionary = SimulationGlobal.particles

	for pos: Vector2 in grid:
		var ids = grid[pos]
		if ids.is_empty():
			continue

		var color: Color = _resolve_color(ids, particle_data)
		if pos.x >= 0 and pos.x < Global.WORLD_GRID_SIZE and pos.y >= 0 and pos.y < Global.WORLD_GRID_SIZE:
			_image.set_pixel(int(pos.x), int(pos.y), color)

	_texture.update(_image)


func _resolve_color(ids: Array, particle_data: Dictionary) -> Color:
	if ids.size() == 1:
		return _particle_color(particle_data[ids[0]] as Dictionary)

	# Blend colors when multiple non-solids share a cell.
	var blended: Color = Color.TRANSPARENT
	for id: int in ids:
		var p: Dictionary = particle_data.get(id, {}) as Dictionary
		if p.is_empty():
			continue
		blended = blended.blend(_particle_color(p))
	return blended


func _particle_color(p: Dictionary) -> Color:
	var config: Dictionary = Particles.get_config(p["type"])
	var colors: Array = config.get("colors", [])
	if colors.is_empty():
		return Color.MAGENTA

	var index: int = p.get("color_index", 0)
	return Color(colors[index])
