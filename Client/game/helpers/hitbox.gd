# hitbox.gd
extends RefCounted
class_name HitboxUtil

static func rect_from_collision_shape_2d(node: Node2D) -> Rect2:
	if node == null:
		return Rect2()

	var shape_node: CollisionShape2D = node.get_node_or_null("CollisionShape2D")
	if shape_node == null:
		shape_node = node.find_child("CollisionShape2D", true, false)

	if shape_node == null:
		return Rect2()

	var shape = shape_node.shape
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size
		var scale: Vector2 = shape_node.global_transform.get_scale()
		var scaled := Vector2(size.x * absf(scale.x), size.y * absf(scale.y))
		return Rect2(shape_node.global_position - scaled * 0.5, scaled)

	return Rect2()
