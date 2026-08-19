shader_type canvas_item;

// Colours the simulation's raw cell buffers on the GPU.
//
// TEXTURE is the padded type buffer (R8, one type id per cell). A cell on the
// boundary of its connected same-type group - touching at least one same-type
// neighbour and at least one different cell - paints the outline colour;
// interior cells and lone particles look up their material colour in the
// palette (x = colour variant, y = type id).

uniform sampler2D variant_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

// Matches SimulationGlobal.FIRST_TYPE: ids below this are EMPTY and WALL.
const int FIRST_TYPE = 2;
const vec4 OUTLINE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 cell = clamp(ivec2(UV * vec2(size)), ivec2(0), size - ivec2(1));

	int own = int(texelFetch(TEXTURE, cell, 0).r * 255.0 + 0.5);
	if (own < FIRST_TYPE) {
		// Empty cells and the wall border are invisible, and skipping them here
		// also keeps every neighbour fetch below in range.
		COLOR = vec4(0.0);
	} else {
		bool has_same = false;
		bool has_diff = false;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				int other = int(texelFetch(TEXTURE, cell + ivec2(dx, dy), 0).r * 255.0 + 0.5);
				if (other == own) {
					has_same = true;
				} else {
					has_diff = true;
				}
			}
		}

		if (has_same && has_diff) {
			COLOR = OUTLINE_COLOR;
		} else {
			int variant = int(texelFetch(variant_tex, cell, 0).r * 255.0 + 0.5);
			COLOR = texelFetch(palette_tex, ivec2(variant, own), 0);
		}
	}
}
