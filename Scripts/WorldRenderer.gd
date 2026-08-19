extends Node2D

## Displays the simulation's RGBA buffer as a single texture.
##
## The simulation keeps its pixel buffer up to date as cells change, so there is
## no per-particle work here at all: this just uploads the buffer when something
## actually moved.

var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
var _size: Vector2i


func _ready() -> void:
	_size = SimulationGlobal.getPaddedSize()

	_image = Image.create(_size.x, _size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)
	_texture = ImageTexture.create_from_image(_image)

	var scale: int = Global.WORLD_PIXEL_SCALE

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(scale, scale)
	# The buffer carries a one-cell border, so shift it back to put world cell
	# (0, 0) at the origin.
	_sprite.position = Vector2(-scale, -scale)
	add_child(_sprite)


func _process(_delta: float) -> void:
	if not SimulationGlobal.consumePixelsDirty():
		return

	# Passed straight through: Packed arrays are copy-on-write, so the buffer is
	# only copied once, into the image.
	_image.set_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, SimulationGlobal.getPixels())
	_texture.update(_image)
