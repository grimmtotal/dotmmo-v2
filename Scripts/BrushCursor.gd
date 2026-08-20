extends Node2D

## Draws the brush footprint at the hovered grid cell, in the colour of whatever
## it is about to do.
##
## A plain white box is legible but says nothing - you have to read the toolbar
## to know what a click will drop. Tinting the cursor with the selected
## material, and painting a fill inside it, makes the answer part of the cursor
## itself, and the dark stroke under the bright one keeps it readable over pale
## sand and dark stone alike.

const SHADOW_COLOR: Color = Color(0, 0, 0, 0.55)
const SHADOW_WIDTH: float = 5.0
const OUTLINE_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.16
const ARC_POINTS: int = 48

var color: Color = Color.WHITE:
	set(value):
		if value == color:
			return
		color = value
		queue_redraw()

var radius: int = 1:
	set(value):
		radius = value
		queue_redraw()

var grid_position: Vector2 = Vector2.ZERO:
	set(value):
		if value == grid_position:
			return
		grid_position = value
		queue_redraw()


func _draw() -> void:
	var scale_px: int = Global.WORLD_PIXEL_SCALE
	var fill: Color = Color(color, FILL_ALPHA)

	if radius <= 1:
		var rect := Rect2(grid_position * scale_px, Vector2(scale_px, scale_px))
		draw_rect(rect, fill, true)
		draw_rect(rect, SHADOW_COLOR, false, SHADOW_WIDTH)
		draw_rect(rect, color, false, OUTLINE_WIDTH)
		return

	var center: Vector2 = (grid_position + Vector2(0.5, 0.5)) * scale_px
	var arc_radius: float = (float(radius) - 0.5) * scale_px
	draw_circle(center, arc_radius, fill)
	draw_arc(center, arc_radius, 0.0, TAU, ARC_POINTS, SHADOW_COLOR, SHADOW_WIDTH)
	draw_arc(center, arc_radius, 0.0, TAU, ARC_POINTS, color, OUTLINE_WIDTH)
