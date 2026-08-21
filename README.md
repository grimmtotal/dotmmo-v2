# dotmmo-V2

A flat-array falling-sand simulation built in Godot 4.7.

## How particles are drawn

Rendering is entirely GPU-side (`Shaders/WorldCells.gdshader`). The simulation's
raw type and variant buffers are uploaded as R8 textures and the fragment shader
turns them into colour; the CPU simulation does no colour work at all, it just
flips a dirty flag when cells change, keeping the hot loop free of rendering
cost.

### Colours

Each material lists one to three colours in `Scripts/Singletons/Particles.gd`,
and every particle picks one when it is created. Two colours far enough apart to
tell from each other is what stops a mass of one material reading as a single
poured fill.

| Particle | Colours |
|---|---|
| Sand | `#e8c46a` Pale Sand, `#c99a45` Deep Sand |
| Water | `#2f86e0` Surface Blue, `#1c5da8` Deep Blue |
| Stone | `#6b7480` Slate, `#565f6b` Dark Slate |
| Plant | `#46b055` Leaf, `#2b7c38` Deep Leaf |
| Fire | `#ffd34d` Yellow Core, `#ff8a1f` Orange, `#f2451f` Red Edge |
| Lava | `#ff9a2b` Molten, `#c22a10` Crust |
| Ember | `#ff7a1a` Hot Cinder, `#a83208` Dull Cinder |
| Smoke | `#585a66` Ash Grey, `#464855` Dark Grey |
| Steam | `#e6f0f4` Off-White, `#c3d3dc` Pale Blue |
| Ash | `#3a3a40` Charcoal, `#2c2c31` Soot |
| Rubble | `#8a8578` Grit, `#6d6a60` Dark Grit |

### Look parameters

Colour alone leaves every cell a flat square, which is most of what makes a
falling-sand world look like a readout instead of a place. So each material also
carries a `look` block, uploaded once at startup as a lookup row per type and
applied per fragment:

| Field | What it does |
|---|---|
| `grain` | How far a particle's shade strays from its material's colour |
| `glow` | Brightness that moves over time - flame flicker high, a surface glint low |
| `bevel` | Face shading across the cell: lit on top, dark underneath and at the sides |
| `alpha` | Opacity |

The split between them is what separates the three states of matter by feel
rather than only by colour. Solids take a strong `bevel`, so a wall of stone
reads as blocks you could stand on. Liquids and gases leave it near zero and run
together into one continuous body, and lean on `alpha` instead, so a plume of
smoke shows the sky through it. Fire, lava and embers carry the `glow`.

Every one of these is a per-fragment effect that reads nothing from the
neighbouring cells. That is deliberate: the world is uploaded in chunks, each
drawn from its own pair of textures, so anything that sampled across a chunk
edge would show a seam there.

### The render seed

`grain` and `glow` need a per-particle random number, and it has to be the
*same* number every frame - a shade recomputed from the cell position would make
a falling grain flicker through every shade on the way down.

So the variant byte carries both: the low three bits are the colour index and
the remaining five are a render seed, rolled once when the particle is created.
Both already travel with the particle when it moves, since the whole byte is
copied on every relocate and swap, so the seed rides along for free and a grain
keeps the shade it was born with. Three bits caps a material at eight colours,
five more than the most colourful one uses.

### The backdrop

Empty cells are transparent, so the world hangs in front of a gradient drawn
behind it (`WorldRenderer._add_backdrop`), running from open sky at the top to
near-black at the bottom of the world. Depth then reads for free: how dark it is
around you is how deep you have dug.

## The character

You play as a body that walks the world the sand falls through
(`Scripts/Player.gd`). A D or the arrow keys walk, Space jumps, and the mouse
aims.

The body is deliberately smaller than a cell - 48 screen pixels against a
64-pixel block - which is what makes a block something you stand on, shelter
behind or have to break, rather than something you wade through. It also makes
collision cheap: a body that size can never straddle more than two cells on an
axis, so resolving a move is a snap to a cell edge rather than a search. Solid
cells block; liquids do not, so you sink into water rather than standing on it,
slowed by drag, with the jump key working as a swim stroke.

Nothing about the body is simulated as particles. It moves as one rigid box
against the cell grid. Its *appearance* is the only part made of materials:
`CharacterCosmetics` pours particles into the outline of a figure, so what you
are wearing is a tally of what you have collected, and a denser material settles
to the bottom of a limb the same way it would in the world.

### Reach

The tools the character holds act on the cell it is aiming at, found by walking
a ray from the body toward the pointer until it either runs out of reach (six
cells) or hits something solid. Stopping at the first blocking cell is what
makes reach mean something: you cannot pour fire through a wall or lift sand
from the far side of one, and the breaker lands on the face of the rock it is
pointed at, which is exactly the cell you want to be digging out.

## Tools

The editor tools act on the cell under the pointer, because placing terrain is
something you do to the world. The held tools act on the character's aim cell,
because they are things the character does in it.

| Key | Tool | What it does |
|---|---|---|
| 1 | Paint | *Editor.* Lays down the selected material across the brush |
| 2 | Erase | *Editor.* Removes whatever the brush covers |
| 3 | Inspect | *Editor.* Reads out a single particle |
| 4 | Hand | *Held.* Picks matter up and carries it |
| 5 | Flame gun | *Held.* Sprays fire |
| 6 | Steam gun | *Held.* Sprays steam |
| 7 | Breaker | *Held.* Chews stone into rubble |

Paint and erase work on the whole brush footprint every frame, which is what
you want for laying down terrain. The guns instead fire a fixed number of
particles per second into random cells of the footprint, so they read as a
stream with gaps in it rather than a pour - a flame that looks like it is
burning instead of being dumped.

### The hand

Click to fill the hand with everything capturable under the brush, click again
to put it down. Held particles leave the simulation entirely - they do not fall
or react while carried - and each one keeps its colour and render seed, so a
carried dune lands as the same dune rather than a freshly rolled one.

Releasing is all or nothing. The ghost turns red the moment the destination
cannot take the whole payload, and releasing there is refused: the hand keeps
hold so you can move and try again. Nothing the hand picks up can be lost.

### What can be carried

The `capturable` flag in `Particles.gd` decides it, and nothing else does:

| Can be carried | Cannot |
|---|---|
| Sand, Water, Lava, Ash, Rubble | Stone, Plant, Fire, Smoke, Steam, Ember |

Loose matter can be gathered; terrain and living things cannot, and neither can
fire or the gases, which are not things you close a hand around. Stone is
deliberately out - it has to be broken into Rubble with the breaker before any
of it can be picked up, which is what makes digging something you do rather
than something you skip. Ash has no despawn timer for the same reason: it is a
material you collect now, so a heap of it has to still be there when you come
back for it.

## Starting ground

The world generates empty, so `simulation.gd` builds a shelf to spawn onto - a
stone bank under a layer of sand, a pool cut into it, and a stand of plants, so
every tool has something to be tried on. This is scaffolding until there is real
terrain generation: delete `_build_spawn_ground` and the world is a blank sheet
again.

## Cell size

Cells are drawn as `WORLD_PIXEL_SCALE`-pixel blocks. Everything sizing the world
lives in `Scripts/Singletons/Global.gd`:

| Constant | Meaning |
|---|---|
| `WORLD_PIXEL_SCALE` | Screen pixels per cell - the one number to change to try a different particle size |
| `WORLD_WIDTH`, `WORLD_HEIGHT` | The world in cells; `WORLD_PIXELS` is derived from them |

Simulation cost tracks the cell count, so it drops fast as the scale goes up: a
world drawn at 64px per cell costs a sixteenth of the same world at 16px.

## Performance: skipping fully-surrounded particles

A cell that is completely surrounded by same-type neighbors can never move or react on its own — every neighbor it could swap into or displace is identical to it, which always blocks the attempt, and materials never react with their own type. So instead of re-checking those interior cells every tick, the simulation leaves them out of its active list entirely once they become fully surrounded, and only reconsiders them when a neighboring cell actually changes (the same wake-up path already used to notify neighbors of a move).

In practice this means a large falling or settled clump of one material costs work proportional to its outer shell each tick, not its full volume — interior grains ride along for free, and any grain that gets exposed (the group breaks apart, erodes, or lands) automatically rejoins individual simulation the moment that happens. Materials with a despawn timer (Fire, Smoke, Steam, Ash) are exempted and always stay active, since they need to keep counting down even while buried.

This is implemented via `_activate_if_exposed` in `Scripts/Singletons/SimulationGlobal.gd`.
