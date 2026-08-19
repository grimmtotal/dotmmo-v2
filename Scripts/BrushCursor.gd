extends Node2D

## Draws an outline of the current brush footprint at the hovered grid cell.

const OUTLINE_COLOR: Color = Color(1, 1, 1, 0.75)
const OUTLINE_WIDTH: float = 2.0

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
	var center: Vector2 = (grid_position + Vector2(0.5, 0.5)) * scale_px

	if radius <= 1:
		draw_rect(Rect2(grid_position * scale_px, Vector2(scale_px, scale_px)), OUTLINE_COLOR, false, OUTLINE_WIDTH)
		return

	draw_arc(center, (float(radius) - 0.5) * scale_px, 0.0, TAU, 48, OUTLINE_COLOR, OUTLINE_WIDTH)
