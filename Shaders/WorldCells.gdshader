shader_type canvas_item;

// Colours the simulation's raw cell buffers on the GPU.
//
// TEXTURE is the padded type buffer (R8, one type id per cell). Each cell is
// painted with its material colour looked up from `palette_tex` by type id and
// colour variant, so a particle reads as a flat coloured block.
//
// Every buffer read is written out inline on purpose: Godot's shading language
// cannot see built-ins like TEXTURE inside a user function, and it rejects a
// function whose sampler argument receives both a built-in and a uniform, so a
// tidy `byte_at(buffer, cell)` helper fails to compile either way.

uniform sampler2D variant_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

// Matches SimulationGlobal.FIRST_TYPE: ids below this are EMPTY and WALL.
const int FIRST_TYPE = 2;


void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 grid = UV * vec2(size);
	ivec2 cell = clamp(ivec2(grid), ivec2(0), size - ivec2(1));

	int own = int(texelFetch(TEXTURE, cell, 0).r * 255.0 + 0.5);
	if (own < FIRST_TYPE) {
		// Empty cells and the wall border are invisible. Bailing out here also
		// keeps every neighbour fetch below in range, since a real particle can
		// never sit on the padded border.
		COLOR = vec4(0.0);
	} else {
		int variant = int(texelFetch(variant_tex, cell, 0).r * 255.0 + 0.5);
		COLOR = texelFetch(palette_tex, ivec2(variant, own), 0);
	}
}
