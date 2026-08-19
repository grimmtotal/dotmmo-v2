extends Node

# Cells are drawn as chunky 8x8 blocks, which leaves room inside each one for
# its own outline. Halving the grid alongside the bigger blocks keeps the world
# the same size on screen (250 * 8 == 1000 * 2 == 2000 pixels) while cutting the
# cell count - and with it the per-tick simulation work and the per-frame
# texture upload - to a sixteenth of what 1000 cells at 2px cost.
const WORLD_GRID_SIZE: int = 250
const WORLD_PIXEL_SCALE: int = 8
