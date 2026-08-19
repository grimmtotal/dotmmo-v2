extends Node

## How many screen pixels wide one cell is drawn.
##
## This is the single number to change to try a different particle size: the
## grid resizes itself to keep the world the same size on screen, so 4 gives
## smaller particles and more of them, 16 gives chunkier particles and fewer.
##
## It is also the cheapest performance lever there is. Simulation cost scales
## with the cell count and the cell count scales with the square of this, so
## every doubling costs a quarter as much to simulate - 8 costs a sixteenth of
## what 2 does. Nothing else in the engine buys a factor of four for one line.
##
## 16 puts a cell at the size of a tile in the games this one takes after, and
## makes one particle - the unit the whole economy is denominated in - big
## enough to see and count on screen.
const WORLD_PIXEL_SCALE: int = 16

## How big the world is on screen, in pixels. Cells divide into this.
const WORLD_PIXELS: int = 2000

const WORLD_GRID_SIZE: int = WORLD_PIXELS / WORLD_PIXEL_SCALE
