
# Module utilitaire pour la géométrie des cartes (rect, picking, etc.)
# Extraction depuis Carte.gd

extends Node
class_name CardGeometry

static func get_card_rect(node: Node2D) -> Rect2:
  var size := Vector2(80, 120)
  var shape = node.get_node_or_null("Area2D/CollisionShape2D")
  if shape:
    shape = shape.shape
  if shape is RectangleShape2D:
    size = (shape as RectangleShape2D).size
  return Rect2(node.global_position - size * 0.5, size)

static func rect_intersection(a: Rect2, b: Rect2) -> Rect2:
  var x1 = maxf(a.position.x, b.position.x)
  var y1 = maxf(a.position.y, b.position.y)
  var x2 = minf(a.position.x + a.size.x, b.position.x + b.size.x)
  var y2 = minf(a.position.y + a.size.y, b.position.y + b.size.y)

  var w = x2 - x1
  var h = y2 - y1
  if w <= 0.0 or h <= 0.0:
    return Rect2()

  return Rect2(Vector2(x1, y1), Vector2(w, h))

static func rect_from_collision_shape_node(node: Node2D) -> Rect2:
  if node == null:
    return Rect2()

  var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
  if shape_node == null:
    shape_node = node.find_child("CollisionShape2D", true, false) as CollisionShape2D
  if shape_node == null:
    return Rect2()

  var shape := shape_node.shape
  if shape is RectangleShape2D:
    var size := (shape as RectangleShape2D).size
    var shape_scale := shape_node.global_transform.get_scale()
    var scaled := Vector2(size.x * absf(shape_scale.x), size.y * absf(shape_scale.y))
    return Rect2(shape_node.global_position - scaled * 0.5, scaled)

  return Rect2()

static func contains_global_point(node: Node2D, global_point: Vector2) -> bool:
  var rect := CardGeometry.rect_from_collision_shape_node(node)
  if rect.size == Vector2.ZERO:
    return false
  return rect.has_point(global_point)

static func pick_topmost_node_at_point(candidates: Array, global_point: Vector2) -> Node2D:
  var best: Node2D = null
  var best_z := -2147483648
  var best_order := -2147483648

  for item in candidates:
    if not (item is Node2D):
      continue
    var node := item as Node2D
    if not is_instance_valid(node):
      continue
    if not CardGeometry.contains_global_point(node, global_point):
      continue

    var node_z := node.z_index
    var node_order := node.get_index()
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
