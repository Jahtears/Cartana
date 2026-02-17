# GameLayoutConfig.gd - Centralise toutes les constantes et helpers de layout

extends RefCounted
class_name GameLayoutConfig

# ============= SLOT LAYOUT =============
const MAIN_COUNT := 1
const BANC_COUNT := 4
const SLOT_WIDTH := 80.0
const SLOT_HEIGHT := 120.0

# ============= SPACING =============
const MIN_SLOT_SPACING := 64.0
const MAX_SLOT_SPACING := 120.0
const DEFAULT_SLOT_SPACING := 100.0
const SIDE_MARGIN := 100.0
const PIOCHE_RIGHT_MARGIN := 80.0
const TABLE_SPACING := 100

# ============= BOARD POSITIONS =============
const PLAYER_TOP_Y_RATIO := 0.18
const PLAYER_BOTTOM_Y_RATIO := 0.82
const TABLE_Y_RATIO := 0.5
const START_POS := Vector2.ZERO

# ============= LAYOUT DYNAMIQUE - POSITIONS DES JOUEURS =============
const P1_MAIN_OFFSET := 150
const P2_MAIN_OFFSET := 150
const TIMEBAR_Y := 420.0
const MESSAGE_Y_RATIO := 0.37

# ============= BOUTON QUITTER =============
const QUITTER_WIDTH := 64.0
const QUITTER_HEIGHT := 32.0
const QUITTER_OFFSET_X := 0.0
const QUITTER_OFFSET_Y := 8.0

# ============= MESSAGE UI =============
const MESSAGE_DISPLAY_DURATION := 2.0
const MESSAGE_FADE_DURATION := 0.3
const MESSAGE_MARGIN_TOP := 50
const MESSAGE_MARGIN_BOTTOM := 20
const MESSAGE_MARGIN_LEFT := 10
const MESSAGE_MARGIN_RIGHT := 10

# ============= CARD VISUAL =============
const DRAG_Z := 3000
const DRAG_SCALE := 1.05
const HOVER_SCALE := 1.08
const MIN_OVERLAP_AREA := 200.0
const PREVIEW_CARD_BORDER_COLOR := Color.GREEN
const PREVIEW_CARD_BORDER_COLOR_NORMAL := Color(0, 0, 0, 1)

# ============= HAND FAN (LAYOUT) =============
const HAND_FAN_X_STEP := 60.0
const HAND_FAN_CENTER_LIFT := 20.0
const HAND_FAN_MAX_ANGLE_DEG := 50.0
const HAND_FAN_MAX_CARDS := 5

# ============= CASCADE OFFSETS =============
const CASCADE_BANC := Vector2(0, 24)
const CASCADE_TABLE := Vector2(0, 0)
const CASCADE_DEFAULT := Vector2(0, 0)

# ============= ANIMATION TIMINGS =============
const SNAP_DURATION := 0.50
const PREVIEW_CHECK_INTERVAL := 3

# ============= PREVIEW COLORS (SLOT) =============
const PREVIEW_HIGHLIGHT_COLOR := Color(1, 1, 0.5)
const PREVIEW_NORMAL_COLOR := Color(1, 1, 1)
const PREVIEW_CARD_SCALE := Vector2(1.03, 1.03)

# ============= HELPER FUNCTIONS =============

static func get_player_layout(player_id: int, positions: Dictionary, slot_spacing: float) -> Dictionary:
	"""Retourne les positions calculées pour un joueur
	
	Args:
		player_id: 1 pour Player1, 2 pour Player2
		positions: Dictionnaire avec vw, vh, center_x, left_x, right_x
		slot_spacing: Espacement entre les slots
	
	Returns:
		Dictionnaire avec root_y, deck_x, main_x, banc_x
	"""
	var is_p1 = player_id == 1
	var center_x = positions["center_x"]
	var vh = positions["vh"]
	
	return {
		"root_y": vh * (PLAYER_BOTTOM_Y_RATIO if is_p1 else PLAYER_TOP_Y_RATIO),
		"deck_x": positions["left_x"] if is_p1 else positions["right_x"],
		"main_x": center_x - P1_MAIN_OFFSET if is_p1 else center_x + P2_MAIN_OFFSET,
		"banc_x": (positions["right_x"] - ((BANC_COUNT - 1) * slot_spacing)) if is_p1 else positions["left_x"],
	}

static func get_message_config() -> Dictionary:
	"""Retourne la config du système de messages"""
	return {
		"display_duration": MESSAGE_DISPLAY_DURATION,
		"fade_duration": MESSAGE_FADE_DURATION,
		"margin_top": MESSAGE_MARGIN_TOP,
		"margin_bottom": MESSAGE_MARGIN_BOTTOM,
		"margin_left": MESSAGE_MARGIN_LEFT,
		"margin_right": MESSAGE_MARGIN_RIGHT,
	}

static func get_card_config() -> Dictionary:
	"""Retourne la config des cartes"""
	return {
		"drag_z": DRAG_Z,
		"drag_scale": DRAG_SCALE,
		"hover_scale": HOVER_SCALE,
		"min_overlap_area": MIN_OVERLAP_AREA,
		"border_color_active": PREVIEW_CARD_BORDER_COLOR,
		"border_color_normal": PREVIEW_CARD_BORDER_COLOR_NORMAL,
	}

static func get_hand_fan_config() -> Dictionary:
	"""Retourne la config du fan de main"""
	return {
		"x_step": HAND_FAN_X_STEP,
		"center_lift": HAND_FAN_CENTER_LIFT,
		"max_angle_deg": HAND_FAN_MAX_ANGLE_DEG,
		"max_cards": HAND_FAN_MAX_CARDS,
	}

static func get_layout_config() -> Dictionary:
	"""Retourne la config du layout dynamique"""
	return {
		"p1_main_offset": P1_MAIN_OFFSET,
		"p2_main_offset": P2_MAIN_OFFSET,
		"timebar_y": TIMEBAR_Y,
		"message_y_ratio": MESSAGE_Y_RATIO,
	}
