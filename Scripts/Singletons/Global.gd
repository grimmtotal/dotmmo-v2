extends Node

## How many screen pixels wide one cell is drawn.
##
## This is the single number to change to try a different particle size, and it
## is also the cheapest performance lever there is: simulation cost scales with
## the cell count and the cell count scales with the square of this, so every
## doubling costs a quarter as much to simulate.
##
## At 64 a block is comfortably larger than the character, which is the point.
## It buys a world hundreds of characters wide for the price of a small one,
## and it makes a block something you stand on, shelter behind or get crushed
## by rather than something you wade through.
const WORLD_PIXEL_SCALE: int = 64

## The world, in cells.
##
## Wide and shallow, because this is a side-scroller: the axis you walk along is
## the one worth spending cells on, and a world 125 blocks deep is already far
## further than anyone digs. Cost tracks the two multiplied together, so trading
## height for width is free.
const WORLD_WIDTH: int = 500
const WORLD_HEIGHT: int = 125

## The whole world in screen pixels. Far larger than any window - the camera
## looks at a piece of it.
const WORLD_PIXELS: Vector2i = Vector2i(
	WORLD_WIDTH * WORLD_PIXEL_SCALE,
	WORLD_HEIGHT * WORLD_PIXEL_SCALE
)
