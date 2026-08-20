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

// How far into a cell the side shading reaches, as a fraction of the cell.
const float EDGE = 0.06;


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

		vec3 col = base.rgb;

		// Grain: every particle sits a little above or below its material's
		// colour, so a mass of one material has texture rather than reading as
		// a single flat plane.
		col *= 1.0 + (seed - 0.5) * 2.0 * grain;

		// Bevel: lit along the top of the cell, dark along the bottom, with the
		// sides pulled down as well. This is what makes a solid read as a block
		// you could stand on; liquids and gases leave it near zero so they run
		// together into one continuous body instead.
		vec2 within = fract(grid);
		col *= 1.0 + (0.5 - within.y) * bevel;
		float side = min(within.x, 1.0 - within.x);
		col *= 1.0 - bevel * 0.6 * smoothstep(EDGE, 0.0, side);

		// Glow: brightness that moves over time, phased by the particle's seed
		// so a bed of flame churns instead of pulsing in unison.
		float pulse = sin(TIME * 5.0 + seed * 6.2831853) * 0.5 + 0.5;
		col = mix(col, mix(col, vec3(1.0), 0.6), glow * pulse);

		COLOR = vec4(col, base.a * style.a);
	}
}
