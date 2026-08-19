shader_type canvas_item;

// Colours the simulation's raw cell buffers on the GPU.
//
// TEXTURE is the padded type buffer (R8, one type id per cell), drawn so that
// each cell covers `cell_pixels` screen pixels. The outer `outline_pixels` ring
// of a cell is painted black and the rest keeps the material colour, so a
// particle reads as an outlined block rather than a flat dot.
//
// Every buffer read is written out inline on purpose: Godot's shading language
// cannot see built-ins like TEXTURE inside a user function, and it rejects a
// function whose sampler argument receives both a built-in and a uniform, so a
// tidy `byte_at(buffer, cell)` helper fails to compile either way.

uniform sampler2D variant_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;

// Screen pixels per cell, and how thick the black ring inside one is.
uniform float cell_pixels = 8.0;
uniform float outline_pixels = 1.0;

// When true, an edge is only drawn where it faces something other than the same
// material, so a connected same-type group is outlined as a single silhouette
// instead of every particle in it being boxed individually. A particle with no
// same-type neighbour still ends up fully boxed, since every side of it faces
// something different.
uniform bool group_outline = true;

// Matches SimulationGlobal.FIRST_TYPE: ids below this are EMPTY and WALL.
const int FIRST_TYPE = 2;
const vec4 OUTLINE_COLOR = vec4(0.0, 0.0, 0.0, 1.0);


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
		// Which edge of its own cell this pixel sits against, as an outward
		// direction. (0, 0) means it is in the cell's interior; a diagonal
		// means it is in a corner, where two edges meet.
		vec2 inner = fract(grid);
		float band = clamp(outline_pixels / cell_pixels, 0.0, 0.5);
		ivec2 out_dir = ivec2(0, 0);
		if (inner.x < band) {
			out_dir.x = -1;
		} else if (inner.x > 1.0 - band) {
			out_dir.x = 1;
		}
		if (inner.y < band) {
			out_dir.y = -1;
		} else if (inner.y > 1.0 - band) {
			out_dir.y = 1;
		}

		bool outlined = out_dir != ivec2(0, 0);
		if (outlined && group_outline) {
			// Keep only the edges that face a different material. A corner
			// pixel has to check the diagonal it points at as well, so a
			// neighbour touching just that diagonal still closes the outline.
			outlined = false;
			if (out_dir.x != 0
					&& int(texelFetch(TEXTURE, cell + ivec2(out_dir.x, 0), 0).r * 255.0 + 0.5) != own) {
				outlined = true;
			}
			if (out_dir.y != 0
					&& int(texelFetch(TEXTURE, cell + ivec2(0, out_dir.y), 0).r * 255.0 + 0.5) != own) {
				outlined = true;
			}
			if (out_dir.x != 0 && out_dir.y != 0
					&& int(texelFetch(TEXTURE, cell + out_dir, 0).r * 255.0 + 0.5) != own) {
				outlined = true;
			}
		}

		if (outlined) {
			COLOR = OUTLINE_COLOR;
		} else {
			int variant = int(texelFetch(variant_tex, cell, 0).r * 255.0 + 0.5);
			COLOR = texelFetch(palette_tex, ivec2(variant, own), 0);
		}
	}
}
