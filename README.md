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

### Aiming

The body supplies a direction and nothing else. It used to also cast a ray out
to a reach and hand back the cell at the end of it, which put the tools on a
leash: the box lagged behind the pointer and hung off the character on a visible
line. Every tool now acts on the cell under the pointer, and the guns take only
their direction from the body - their own flight decides where a shot ends up.

## Tools

The editor tools act on the cell under the pointer, because placing terrain is
something you do to the world. The held tools act on the character's aim cell,
because they are things the character does in it.

| Key | Tool | What it does |
|---|---|---|
| 1 | Paint | *Editor.* Lays down the selected material across the brush |
| 2 | Erase | *Editor.* Removes whatever the brush covers |
| 3 | Inspect | *Editor.* Reads out a single particle |
| 4 | Box | *Held.* Collects one material and carries it |
| 5 | Flame gun | *Held.* Fires arcing fireballs |
| 6 | Steam gun | *Held.* Fires steam |
| 7 | Breaker | *Held.* Fires a round that breaks stone into rubble |

Paint and erase work on the whole brush footprint every frame, which is what
you want for laying down terrain. The guns are not area tools at all.

### The guns are ballistic

A fired particle cannot be a world cell while it is travelling. The simulation
gives every material one fixed way of moving - fall, rise, flow, sit still -
chosen from its type and shared by every grain of it, with no per-cell velocity
anywhere in the grid to override it. Adding one would cost bytes on all 62,500
cells and a branch in the hot loop, to serve the handful of grains that are ever
actually in the air.

So a shot lives outside the grid (`Scripts/Projectiles.gd`): a position, a
velocity and a gravity of its own, with the simulation knowing nothing about it
until it arrives. Each gun sets its own muzzle velocity, spread cone and flight
gravity - negative for flame and steam, so they arc upward the way the materials
themselves do.

**What flies is the particle itself, not a marker for one.** A shot carries a
packed type-and-variant rolled at the muzzle - the same value the box passes
around - is drawn at full cell size in that variant's own colour with the same
lit-top, dark-bottom face the cell shader gives a settled block, and is put down
with that exact byte when it lands. The block you watch leave the barrel is the
block that ends up in the ground, in the same shade, with no moment where one
thing turns into another.

On impact the shot becomes an ordinary particle in the last cell it was clear
of, which is what puts the simulation's own reactions in charge of the result:
**nothing in the projectile code says a fireball into a plant bed sets it
alight, or that one into water is quenched.** Those reactions already existed;
a shot only has to deliver the material to the right cell.

### The box

A container you sweep through the world, sitting on the cell under the pointer.
Left-drag fills it, right-drag pours it back out.

**The box takes one material at a time.** It has no filter until the first
particle goes in, and that particle sets it: sweep into a bank of sand and the
box is a sand box for as long as it holds any, ignoring the water and the rubble
it passes over afterwards. That is the whole rule, and it is what makes a sweep
predictable - you can drag through mixed ground without having to be careful
about what else is under the mouth. The filter clears the moment the last
particle leaves.

**When the first sweep touches more than one material, the one nearest where you
are pointing wins.** Nearest rather than first-found matters: a sweep that
starts across a boundary would otherwise lock onto whichever cell the loop
happened to reach first, which from the outside looks arbitrary - pointing at
the sand and getting a box of water. The tooltip names what will be taken before
you press, and the cell it will be taken from is outlined, so the choice is
never a surprise.

**Capacity comes from the brush size**, and the box draws its own fill level, so
"how much have I got" is answered by looking at it. The mouth only reaches what
it covers, so filling a box bigger than its footprint means dragging it across
the ground rather than holding it still.

Contents are not a picture of what was collected. The box is a container, not a
snapshot: it holds a count, not a shape, which is why it can be filled from a
dozen scattered cells and poured out somewhere entirely different. Each grain
still keeps its own variant byte, so a boxful of sand poured out has the grain it
had in the ground rather than being re-rolled.

### What can be collected

The `capturable` flag in `Particles.gd` decides it, and nothing else does:

| Can be collected | Cannot |
|---|---|
| Sand, Water, Lava, Ash, Rubble | Stone, Plant, Fire, Smoke, Steam, Ember |

Loose matter can be gathered; terrain and living things cannot, and neither can
fire or the gases, which are not things you scoop into a box. Stone is
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
