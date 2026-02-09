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
		var scaled: Vector2 = Vector2(size.x * absf(scale.x), size.y * absf(scale.y))
		return Rect2(shape_node.global_position - scaled * 0.5, scaled)

	return Rect2()

static func contains_global_point(node: Node2D, global_point: Vector2) -> bool:
	var rect: Rect2 = rect_from_collision_shape_2d(node)
	if rect.size == Vector2.ZERO:
		return false
	return rect.has_point(global_point)

static func pick_topmost_node_at_point(candidates: Array, global_point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_z: int = -2147483648
	var best_order: int = -2147483648

	for item in candidates:
		if not (item is Node2D):
			continue
		var node: Node2D = item as Node2D
		if not is_instance_valid(node):
			continue
		if not contains_global_point(node, global_point):
			continue

		var node_z: int = node.z_index
		var node_order: int = node.get_index()
		if best == null:
			best = node
			best_z = node_z
			best_order = node_order
			continue

		if node_z > best_z or (node_z == best_z and node_order > best_order):
			best = node
			best_z = node_z
			best_order = node_order

	return best
