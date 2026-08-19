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

Each particle type picks 3 colors from the palette above for its grain-to-grain variation:

| Particle | Colors |
|---|---|
| Sand | `#fbffce` Pale Yellow, `#fbd439` Golden Yellow, `#f09432` Orange |
| Water | `#5af0f7` Light Cyan, `#08a0c0` Cyan Blue, `#165a7d` Dark Blue |
| Stone | `#6f288b` Purple, `#260e3e` Deep Violet, `#c635bc` Magenta |
| Fire | `#fbd439` Golden Yellow, `#f09432` Orange, `#dc532d` Burnt Orange |
| Smoke | `#ff9cc9` Pink, `#6f288b` Purple, `#260e3e` Deep Violet |
| Steam | `#fbffce` Pale Yellow, `#5af0f7` Light Cyan, `#25e2c0` Turquoise |
| Plant | `#b4dc25` Lime Green, `#26a630` Green, `#25e2c0` Turquoise |
| Ash | `#a12536` Dark Red, `#260e3e` Deep Violet, `#165a7d` Dark Blue |
| Lava | `#f43666` Crimson Pink, `#dc532d` Burnt Orange, `#a12536` Dark Red |

## Particle group outlines

Particles of the same type that are touching (including diagonally) are treated as one group. Cells on the edge of a group — the ones touching both a same-type neighbor and something else (empty space, a wall, or a different material) — render as a black outline instead of their material color. Interior cells keep their normal color, and a lone particle with no same-type neighbor is left uncolored by the outline (it just shows its own color).

Because this only depends on each cell's immediate neighbors, it falls out correctly if a group splits apart: each resulting piece gets its own outline around its own shape, with no extra bookkeeping needed.

This is implemented in `Scripts/Singletons/SimulationGlobal.gd` (`_repaint_cell` / `_repaint_neighbourhood`), which repaints a changed cell and its 8 neighbors any time a particle is placed, erased, moved, or swapped.
