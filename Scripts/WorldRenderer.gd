extends Node2D

## Displays the simulation's cells as a grid of chunk quads, coloured on the GPU.
##
## Each chunk owns a small pair of R8 textures - the simulation's raw type and
## variant bytes for that chunk - and a shader maps type + variant to a palette
## colour, painting each cell as a flat coloured block. The CPU side never
## touches colours at all.
##
## The world used to be one quad over the whole cell buffer, re-uploaded in full
## whenever any single cell changed. That is fine at 250x250 (63KB a frame) and
## ruinous at sidescroller sizes: an 8000x2000 world would push 32MB per frame
## across the bus to redraw a puff of smoke. Uploading per chunk makes the cost
## track the area that actually changed instead of the size of the world, which
## is what lets the world grow at all.

const CELL_SHADER := preload("res://Shaders/WorldCells.gdshader")

## The sky the world hangs in. Empty cells are transparent, so without this the
## void behind the particles is whatever the engine happens to clear to - and a
## flat grey field is most of what makes a falling-sand world look like a
## readout rather than a place. The gradient runs from open sky at the top to
## near-black at the bottom of the world, which also gives depth a free read:
## how dark it is around you is how deep you have dug.
const SKY: Array[Color] = [
	Color("#3f6ea8"), # Open sky
	Color("#24406b"), # Horizon
	Color("#101a2c"), # Shallow ground
	Color("#070a12"), # Deep ground
]
const SKY_STOPS: Array[float] = [0.0, 0.16, 0.34, 1.0]

## Resolution of the backdrop texture. It is stretched over the whole world and
## sampled with linear filtering, so a couple of hundred rows is plenty for a
## gradient that only varies vertically.
const SKY_ROWS: int = 256

var _sprites: Array[Sprite2D] = []
var _type_images: Array[Image] = []
var _variant_images: Array[Image] = []
var _type_textures: Array[ImageTexture] = []
var _variant_textures: Array[ImageTexture] = []


func _ready() -> void:
	_add_backdrop()

	var style := ImageTexture.create_from_image(SimulationGlobal.buildStyleImage())
	var palette := ImageTexture.create_from_image(SimulationGlobal.buildPaletteImage())
	var grid: Vector2i = SimulationGlobal.getChunkGrid()
	var scale: int = Global.WORLD_PIXEL_SCALE

	for chunk: int in grid.x * grid.y:
		var rect: Rect2i = SimulationGlobal.chunkRect(chunk)

		var type_image: Image = Image.create_from_data(
			rect.size.x, rect.size.y, false, Image.FORMAT_R8,
			SimulationGlobal.chunkCells(chunk, false))
		var variant_image: Image = Image.create_from_data(
			rect.size.x, rect.size.y, false, Image.FORMAT_R8,
			SimulationGlobal.chunkCells(chunk, true))

		var type_texture := ImageTexture.create_from_image(type_image)
		var variant_texture := ImageTexture.create_from_image(variant_image)

		# The palette is shared, but each chunk needs its own material to carry
		# its own variant buffer.
		var material := ShaderMaterial.new()
		material.shader = CELL_SHADER
		material.set_shader_parameter("variant_tex", variant_texture)
		material.set_shader_parameter("palette_tex", palette)
		material.set_shader_parameter("style_tex", style)

		var sprite := Sprite2D.new()
		sprite.texture = type_texture
		sprite.material = material
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(scale, scale)
		sprite.position = Vector2(rect.position * scale)
		add_child(sprite)

		_sprites.append(sprite)
		_type_images.append(type_image)
		_variant_images.append(variant_image)
		_type_textures.append(type_texture)
		_variant_textures.append(variant_texture)


func _add_backdrop() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(SKY_STOPS)
	gradient.colors = PackedColorArray(SKY)

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = SKY_ROWS
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)

	var sprite := Sprite2D.new()
	sprite.name = "Backdrop"
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2(Global.WORLD_PIXELS) / Vector2(1, SKY_ROWS)
	sprite.z_index = -10
	add_child(sprite)


func _process(_delta: float) -> void:
	for chunk: int in SimulationGlobal.consumeDirtyChunks():
		var rect: Rect2i = SimulationGlobal.chunkRect(chunk)

		# Passed straight through: Packed arrays are copy-on-write, so each
		# chunk's bytes are only copied once, into its image, then uploaded.
		_type_images[chunk].set_data(rect.size.x, rect.size.y, false, Image.FORMAT_R8,
			SimulationGlobal.chunkCells(chunk, false))
		_variant_images[chunk].set_data(rect.size.x, rect.size.y, false, Image.FORMAT_R8,
			SimulationGlobal.chunkCells(chunk, true))
		_type_textures[chunk].update(_type_images[chunk])
		_variant_textures[chunk].update(_variant_images[chunk])
