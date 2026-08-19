shader_type canvas_item;

// Colours the simulation's raw cell buffers on the GPU.
//
// TEXTURE is the padded type buffer (R8, one type id per cell), drawn so that
// each cell covers `cell_pixels` screen pixels. The outer `outline_pixels` ring
// of a cell is painted black and the rest keeps the material colour, so a
// particle reads as an outlined block rather than a flat dot.

uniform sampler2D variant_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

// Screen pixels per cell, and how thick the black ring inside one is.
uniform float cell_pixels = 8.0;
uniform float outline_pixels = 1.0;

// When true, an edge is only drawn where the neighbouring cell holds something
// different, so a connected same-type group is outlined as a single silhouette
// instead of every particle in it being boxed individually.
uniform bool group_outline = false;

// Matches SimulationGlobal.FIRST_TYPE: ids below this are EMPTY and WALL.
const int FIRST_TYPE = 2;
const vec4 OUTLINE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);


// Reads one cell out of an R8 buffer (type ids and colour variants alike).
int cell_byte(sampler2D buffer, ivec2 cell) {
	return int(texelFetch(buffer, cell, 0).r * 255.0 + 0.5);
}


void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 grid = UV * vec2(size);
	ivec2 cell = clamp(ivec2(grid), ivec2(0), size - ivec2(1));

	int own = cell_byte(TEXTURE, cell);
	if (own < FIRST_TYPE) {
		// Empty cells and the wall border are invisible. Bailing out here also
		// keeps every neighbour fetch below in range, since a real particle can
		// never sit on the padded border.
		COLOR = vec4(0.0);
	} else {
		vec2 inner = fract(grid);
		float band = clamp(outline_pixels / cell_pixels, 0.0, 0.5);

		bool left = inner.x < band;
		bool right = inner.x > 1.0 - band;
		bool top = inner.y < band;
		bool bottom = inner.y > 1.0 - band;

		bool outlined;
		if (group_outline) {
			outlined = (left && cell_byte(TEXTURE, cell + ivec2(-1, 0)) != own)
				|| (right && cell_byte(TEXTURE, cell + ivec2(1, 0)) != own)
				|| (top && cell_byte(TEXTURE, cell + ivec2(0, -1)) != own)
				|| (bottom && cell_byte(TEXTURE, cell + ivec2(0, 1)) != own)
				// A corner whose two orthogonal neighbours match but whose
				// diagonal does not still sits on the group's silhouette.
				|| (left && top && cell_byte(TEXTURE, cell + ivec2(-1, -1)) != own)
				|| (right && top && cell_byte(TEXTURE, cell + ivec2(1, -1)) != own)
				|| (left && bottom && cell_byte(TEXTURE, cell + ivec2(-1, 1)) != own)
				|| (right && bottom && cell_byte(TEXTURE, cell + ivec2(1, 1)) != own);
		} else {
			outlined = left || right || top || bottom;
		}

		if (outlined) {
			COLOR = OUTLINE_COLOR;
		} else {
			COLOR = texelFetch(palette_tex, ivec2(cell_byte(variant_tex, cell), own), 0);
		}
	}
}
