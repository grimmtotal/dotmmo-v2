extends Node

## How many screen pixels wide one cell is drawn.
##
## This is the single number to change to try a different particle size: the
## grid resizes itself to keep the world the same size on screen, so 4 gives
## smaller particles and more of them, 16 gives chunkier particles and fewer.
## Simulation cost scales with the cell count, so it falls off quickly as this
## goes up - 8 costs a sixteenth of what 2 does.
const WORLD_PIXEL_SCALE: int = 8

## How big the world is on screen, in pixels. Cells divide into this.
const WORLD_PIXELS: int = 2000

const WORLD_GRID_SIZE: int = WORLD_PIXELS / WORLD_PIXEL_SCALE

## Thickness of the black outline drawn inside a cell, in screen pixels. Worth
## raising alongside WORLD_PIXEL_SCALE so the outline keeps its weight.
const OUTLINE_PIXELS: int = 1

## Outline each connected group of one material as a single silhouette, rather
## than boxing every particle in it individually. A particle with no same-type
## neighbour is still fully outlined on its own, since every side of it faces
## something different.
const GROUP_OUTLINE: bool = true
