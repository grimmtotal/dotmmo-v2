extends Node2D

## Blits the simulation grid into a single texture. Colours are resolved once at
## spawn time and cached on the particle, so drawing is a plain lookup per cell.

var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
var _bounds: Rect2i


func _ready() -> void:
	var size: int = Global.WORLD_GRID_SIZE
	_bounds = Rect2i(0, 0, size, size)

	_image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.scale = Vector2(Global.WORLD_PIXEL_SCALE, Global.WORLD_PIXEL_SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _process(_delta: float) -> void:
	_render_frame()


func _render_frame() -> void:
	_image.fill(Color.TRANSPARENT)

	var grid: Dictionary = SimulationGlobal.grid
	var particles: Dictionary = SimulationGlobal.particles

	for pos: Vector2 in grid:
		var cell: Vector2i = Vector2i(pos)
		if not _bounds.has_point(cell):
			continue

		var ids: Array = grid[pos]
		if ids.size() == 1:
			var only: Dictionary = particles.get(ids[0], {}) as Dictionary
			if not only.is_empty():
				_image.set_pixelv(cell, only["color"])
			continue

		_image.set_pixelv(cell, _blend(ids, particles))

	_texture.update(_image)


## Overlapping non-solids (gas in water, etc.) are composited back to front.
func _blend(ids: Array, particles: Dictionary) -> Color:
	var blended: Color = Color.TRANSPARENT
	for id: int in ids:
		var p: Dictionary = particles.get(id, {}) as Dictionary
		if not p.is_empty():
			blended = blended.blend(p["color"])
	return blended
