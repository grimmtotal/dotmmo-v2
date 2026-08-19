# dotmmo-V2

A flat-array falling-sand simulation built in Godot 4.7.

## Particle color palette

Every particle color comes from this fixed 16-color palette (`Scripts/Singletons/Particles.gd`). Nothing outside this list is used for particle colors.

| Swatch | Hex | Name |
|---|---|---|
| ![#fbffce](https://placehold.co/16x16/fbffce/fbffce.png) | `#fbffce` | Pale Yellow |
| ![#b4dc25](https://placehold.co/16x16/b4dc25/b4dc25.png) | `#b4dc25` | Lime Green |
| ![#26a630](https://placehold.co/16x16/26a630/26a630.png) | `#26a630` | Green |
| ![#5af0f7](https://placehold.co/16x16/5af0f7/5af0f7.png) | `#5af0f7` | Light Cyan |
| ![#fbd439](https://placehold.co/16x16/fbd439/fbd439.png) | `#fbd439` | Golden Yellow |
| ![#ff9cc9](https://placehold.co/16x16/ff9cc9/ff9cc9.png) | `#ff9cc9` | Pink |
| ![#25e2c0](https://placehold.co/16x16/25e2c0/25e2c0.png) | `#25e2c0` | Turquoise |
| ![#08a0c0](https://placehold.co/16x16/08a0c0/08a0c0.png) | `#08a0c0` | Cyan Blue |
| ![#f09432](https://placehold.co/16x16/f09432/f09432.png) | `#f09432` | Orange |
| ![#f43666](https://placehold.co/16x16/f43666/f43666.png) | `#f43666` | Crimson Pink |
| ![#c635bc](https://placehold.co/16x16/c635bc/c635bc.png) | `#c635bc` | Magenta |
| ![#165a7d](https://placehold.co/16x16/165a7d/165a7d.png) | `#165a7d` | Dark Blue |
| ![#dc532d](https://placehold.co/16x16/dc532d/dc532d.png) | `#dc532d` | Burnt Orange |
| ![#a12536](https://placehold.co/16x16/a12536/a12536.png) | `#a12536` | Dark Red |
| ![#6f288b](https://placehold.co/16x16/6f288b/6f288b.png) | `#6f288b` | Purple |
| ![#260e3e](https://placehold.co/16x16/260e3e/260e3e.png) | `#260e3e` | Deep Violet |

### Particle color assignments

Each particle type uses at most two colors from the palette — one where the material reads as uniform, two where a little grain-to-grain variation helps it feel like a substance rather than a flat fill:

| Particle | Colors |
|---|---|
| Sand | `#fbd439` Golden Yellow |
| Water | `#5af0f7` Light Cyan, `#08a0c0` Cyan Blue |
| Stone | `#165a7d` Dark Blue, `#260e3e` Deep Violet |
| Plant | `#b4dc25` Lime Green, `#26a630` Green |
| Fire | `#f09432` Orange, `#dc532d` Burnt Orange |
| Lava | `#f43666` Crimson Pink, `#a12536` Dark Red |
| Smoke | `#6f288b` Purple |
| Steam | `#fbffce` Pale Yellow |
| Ash | `#260e3e` Deep Violet |

The palette has no true neutrals, so the dark materials borrow from the blues and violets: Stone and Ash share Deep Violet, which reads fine in practice since Stone is static terrain and Ash falls and despawns.

## Cell size and particle outlines

Particles of the same type that are touching (including diagonally) are treated as one group, and the black outline traces the outside of the whole group rather than boxing each particle in it. Because cells are drawn as 8×8 blocks, the outline fits *inside* a cell: a 1px black border on the sides that face something else, with the material color still filling the middle. A particle with no same-type neighbor ends up fully outlined on its own — every side of it faces something different — which is what a lone grain should look like.

Since it only depends on each cell's immediate neighbors, this falls out correctly when a group splits apart: each piece immediately outlines its own new shape, with no extra bookkeeping.

The rendering is entirely GPU-side (`Shaders/WorldCells.gdshader`): the simulation's raw type and variant buffers are uploaded as R8 textures, and the fragment shader figures out from each screen pixel's position within its cell which edges it sits against, then tests only those directions against the neighboring cells. The CPU simulation does no color or outline work at all — it just flips a dirty flag when cells change, keeping the hot loop free of rendering costs.

### Tuning it

Everything visual lives in `Scripts/Singletons/Global.gd`:

| Constant | Meaning |
|---|---|
| `WORLD_PIXEL_SCALE` | Screen pixels per cell — the one number to change to try a different particle size |
| `WORLD_PIXELS` | How big the world is on screen; `WORLD_GRID_SIZE` is derived from it |
| `OUTLINE_PIXELS` | Outline thickness, worth raising alongside the scale |
| `GROUP_OUTLINE` | Off boxes every particle individually instead of outlining groups |

`WORLD_GRID_SIZE` is derived (`WORLD_PIXELS / WORLD_PIXEL_SCALE`), so changing the scale alone keeps the world the same size on screen and adjusts the cell count to match. Simulation cost scales with cell count, so it drops fast as the scale goes up: at 8px the world is 250×250 cells, a sixteenth of the cost of the same world at 2px.

## Performance: skipping fully-surrounded particles

A cell that is completely surrounded by same-type neighbors can never move or react on its own — every neighbor it could swap into or displace is identical to it, which always blocks the attempt, and materials never react with their own type. So instead of re-checking those interior cells every tick, the simulation leaves them out of its active list entirely once they become fully surrounded, and only reconsiders them when a neighboring cell actually changes (the same wake-up path already used to notify neighbors of a move).

In practice this means a large falling or settled clump of one material costs work proportional to its outer shell each tick, not its full volume — interior grains ride along for free, and any grain that gets exposed (the group breaks apart, erodes, or lands) automatically rejoins individual simulation the moment that happens. Materials with a despawn timer (Fire, Smoke, Steam, Ash) are exempted and always stay active, since they need to keep counting down even while buried.

This is implemented via `_activate_if_exposed` in `Scripts/Singletons/SimulationGlobal.gd`.
