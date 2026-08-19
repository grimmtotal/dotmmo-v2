extends Node2D

## Displays the simulation's cells as a single quad, coloured on the GPU.
##
## The sprite's texture is the simulation's raw type buffer (R8); a shader maps
## type + variant to a palette colour, painting each cell as a flat coloured
## block. The CPU side never touches colours at all: it just re-uploads the two
## byte buffers when the simulation reports a change.

const CELL_SHADER := preload("res://Shaders/WorldCells.gdshader")

var _type_image: Image
var _variant_image: Image
var _type_texture: ImageTexture
var _variant_texture: ImageTexture
var _sprite: Sprite2D
var _size: Vector2i


func _ready() -> void:
	_size = SimulationGlobal.getPaddedSize()

	_type_image = Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_R8, SimulationGlobal.getTypeCells())
	_variant_image = Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_R8, SimulationGlobal.getVariantCells())
	_type_texture = ImageTexture.create_from_image(_type_image)
	_variant_texture = ImageTexture.create_from_image(_variant_image)

	var scale: int = Global.WORLD_PIXEL_SCALE

	var material := ShaderMaterial.new()
	material.shader = CELL_SHADER
	material.set_shader_parameter("variant_tex", _variant_texture)
	material.set_shader_parameter("palette_tex", ImageTexture.create_from_image(SimulationGlobal.buildPaletteImage()))

	_sprite = Sprite2D.new()
	_sprite.texture = _type_texture
	_sprite.material = material
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(scale, scale)
	# The buffer carries a one-cell border, so shift it back to put world cell
	# (0, 0) at the origin.
	_sprite.position = Vector2(-scale, -scale)
	add_child(_sprite)


func _process(_delta: float) -> void:
	if not SimulationGlobal.consumeCellsDirty():
		return

	# Passed straight through: Packed arrays are copy-on-write, so each buffer
	# is only copied once, into its image, then uploaded.
	_type_image.set_data(_size.x, _size.y, false, Image.FORMAT_R8, SimulationGlobal.getTypeCells())
	_variant_image.set_data(_size.x, _size.y, false, Image.FORMAT_R8, SimulationGlobal.getVariantCells())
	_type_texture.update(_type_image)
	_variant_texture.update(_variant_image)
