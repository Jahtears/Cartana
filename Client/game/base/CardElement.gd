# Client/game/base/CardElement.gd
extends Node2D
class_name CardElement

# ============= CONSTANTS =============
const DRAG_Z := 3000
const HOVER_SCALE := 1.08
const DRAG_SCALE := 1.05
const PREVIEW_CHECK_INTERVAL := 3
const PREVIEW_CARD_GLOW_COLOR := Color(0.35, 0.95, 0.45, 0.45)
const PREVIEW_CARD_GLOW_SIZE := 6

# ============= STATE MACHINE =============
enum CardState {
	IDLE,
	HOVER,
	HOVER_TOP,
	DRAG,
	PREVIEW_SLOT,
	DROP,
	ANIMATING
}

var state: CardState = CardState.IDLE

# ============= ANIMATION STATE =============
var _is_animating := false
var _animation_type: String = ""

# ============= VISUAL STATE =============
var _base_scale := Vector2.ONE

# ============= LIFECYCLE =============
func _ready() -> void:
	add_to_group("card_elements")
	_base_scale = scale

# ============= STATE MACHINE =============
func set_state(new_state: CardState) -> void:
	if state == new_state:
		return

	_exit_state(state)
	state = new_state
	_enter_state(state)

func _enter_state(s: CardState) -> void:
	match s:
		CardState.IDLE:
			_apply_scale(_base_scale)
			_apply_hover_modulation(Color.WHITE)

		CardState.HOVER:
			_apply_scale(_base_scale * HOVER_SCALE)
			_apply_hover_modulation(Color.WHITE)

		CardState.HOVER_TOP:
			_apply_scale(_base_scale * HOVER_SCALE)
			_apply_hover_modulation(Color.WHITE)

		CardState.DRAG:
			_apply_scale(_base_scale * DRAG_SCALE)
			_apply_hover_modulation(Color.WHITE)

		CardState.PREVIEW_SLOT:
			_apply_scale(_base_scale * DRAG_SCALE)
			_apply_hover_modulation(Color.WHITE)

		CardState.DROP:
			_apply_scale(_base_scale)
			_apply_hover_modulation(Color.WHITE)

		CardState.ANIMATING:
			# Ne change pas scale/color pendant animation
			pass

func _exit_state(_s: CardState) -> void:
	pass

# ============= ANIMATION MANAGEMENT =============
func start_animation(anim_type: String) -> void:
	_is_animating = true
	_animation_type = anim_type
	set_state(CardState.ANIMATING)
	EventDispatcher.emit_animation_started(self, anim_type)

func finish_animation() -> void:
	var prev_anim = _animation_type
	_is_animating = false
	_animation_type = ""
	set_state(CardState.IDLE)
	EventDispatcher.emit_animation_finished(self, prev_anim)

func is_animating() -> bool:
	return _is_animating

# ============= VISUAL UPDATES =============
func _apply_scale(new_scale: Vector2) -> void:
	scale = new_scale

func _apply_hover_modulation(color: Color) -> void:
	modulate = color

# ============= QUERY METHODS =============
func can_interact() -> bool:
	return true  # Override in Carte

func get_card_state() -> CardState:
	return state

func get_animation_type() -> String:
	return _animation_type
