shader_type canvas_item;

// Colours the simulation's raw cell buffers on the GPU.
//
// TEXTURE is the padded type buffer (R8, one type id per cell). Each cell is
// painted with its material colour looked up from `palette_tex` by type id and
// colour variant, then shaded by that material's row in `style_tex`: grain,
// glow, bevel and alpha, authored in the "look" block in Particles.gd.
//
// All of the shading is per fragment and needs nothing from the neighbouring
// cells, which is what keeps it compatible with chunked upload - a chunk is
// drawn from its own textures alone, with nothing to read across the seam.
//
// Every buffer read is written out inline on purpose: Godot's shading language
// cannot see built-ins like TEXTURE inside a user function, and it rejects a
// function whose sampler argument receives both a built-in and a uniform, so a
// tidy `byte_at(buffer, cell)` helper fails to compile either way.

uniform sampler2D variant_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform sampler2D style_tex : filter_nearest, repeat_disable;

// Matches SimulationGlobal.FIRST_TYPE: ids below this are EMPTY and WALL.
const int FIRST_TYPE = 2;

// Matches SimulationGlobal.VARIANT_BITS: the variant byte is a colour index in
// the low bits and a per-particle render seed in the rest.
const int VARIANT_BITS = 3;
const int VARIANT_MASK = 7;
const float SEED_MAX = 31.0;

// How many texels a cell is drawn as, along each axis.
//
// A cell covers 64 screen pixels and more once the camera zooms in, so any
// shading written as a continuous function of the position within the cell
// becomes a gradient tens of pixels wide - which is exactly what makes a
// particle read as a soft blob rather than a block. Every bit of intra-cell
// shading below is therefore quantised onto this grid, so a cell reads as a
// chunky sprite whose edges stay hard at any zoom instead of smearing.
const float SUBCELLS = 8.0;

// Thickness of the lit and shadowed faces, in texels of the grid above.
const float RIM = 1.0;

// How hard the underside and the sides are shaded, relative to the lit top.
const float UNDER = 1.0;
const float SIDE = 0.45;

// How much of a material's grain is spent on texel-to-texel dither within the
// cell rather than on the particle's own overall shade. Pure per-particle
// grain leaves a single cell dead flat across all 64 pixels; a little dither
// gives the surface something to catch the eye at close range.
const float DITHER_SHARE = 0.45;


// Value noise on the cell's texel grid, keyed by the particle's own seed so
// the speckle travels with the particle instead of staying pinned to the world
// and crawling underneath it as it falls.
float texel_noise(vec2 texel, float seed) {
	return fract(sin(dot(texel + seed * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
}


void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 grid = UV * vec2(size);
	ivec2 cell = clamp(ivec2(grid), ivec2(0), size - ivec2(1));

	int own = int(texelFetch(TEXTURE, cell, 0).r * 255.0 + 0.5);
	if (own < FIRST_TYPE) {
		// Empty cells and the wall border are invisible, letting the backdrop
		// behind the world show through.
		COLOR = vec4(0.0);
	} else {
		int packed = int(texelFetch(variant_tex, cell, 0).r * 255.0 + 0.5);
		vec4 base = texelFetch(palette_tex, ivec2(packed & VARIANT_MASK, own), 0);
		vec4 style = texelFetch(style_tex, ivec2(0, own), 0);
		float grain = style.r;
		float glow = style.g;
		float bevel = style.b;

		// The particle's own seed, rolled when it was created and carried with
		// it as it moves.
		float seed = float(packed >> VARIANT_BITS) / SEED_MAX;

		// Where in the cell this fragment lands, snapped to the texel grid so
		// everything below steps between flat shades rather than ramping.
		vec2 within = fract(grid);
		vec2 texel = floor(within * SUBCELLS);

		vec3 col = base.rgb;

		// Grain: every particle sits a little above or below its material's
		// colour, so a mass of one material has texture rather than reading as
		// a single flat plane. Part of it is spent within the cell, as dither
		// across the texel grid.
		col *= 1.0 + (seed - 0.5) * 2.0 * grain * (1.0 - DITHER_SHARE);
		float dither = texel_noise(texel, seed);
		col *= 1.0 + (dither - 0.5) * 2.0 * grain * DITHER_SHARE;

		// Bevel: a lit face along the top of the cell and a shadowed one along
		// the bottom and the sides, each exactly RIM texels thick. This is
		// what makes a solid read as a block you could stand on; liquids and
		// gases leave it near zero so they run together into one continuous
		// body instead. Drawn as hard-edged faces rather than a ramp across
		// the cell, which at 64 pixels a cell would just be a blur.
		float top = step(texel.y, RIM - 1.0);
		float bottom = step(SUBCELLS - RIM, texel.y);
		float edge = min(texel.x, SUBCELLS - 1.0 - texel.x);
		float side = step(edge, RIM - 1.0) * (1.0 - top) * (1.0 - bottom);
		col *= 1.0 + bevel * (top * 0.5 - bottom * 0.5 * UNDER - side * 0.5 * SIDE);

		// Glow: brightness that moves over time, phased by the particle's seed
		// so a bed of flame churns instead of pulsing in unison.
		float pulse = sin(TIME * 5.0 + seed * 6.2831853) * 0.5 + 0.5;
		col = mix(col, mix(col, vec3(1.0), 0.6), glow * pulse);

		COLOR = vec4(col, base.a * style.a);
	}
}
