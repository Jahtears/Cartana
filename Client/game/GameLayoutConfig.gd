# GameLayoutConfig.gd - Centralise toutes les constantes et helpers de layout

extends RefCounted
class_name GameLayoutConfig

# ============= SLOT LAYOUT =============
const MAIN_COUNT := 1
const BANC_COUNT := 4

# ============= SPACING =============
const MIN_SLOT_SPACING := 64.0
const MAX_SLOT_SPACING := 120.0
const DEFAULT_SLOT_SPACING := 100.0
const SIDE_MARGIN := 100.0
const TABLE_SPACING := 100

# ============= BOARD POSITIONS =============
const PLAYER_TOP_Y_RATIO := 0.18
const PLAYER_BOTTOM_Y_RATIO := 0.82
const TABLE_Y_RATIO := 0.5
const START_POS := Vector2.ZERO

# ============= LAYOUT DYNAMIQUE - POSITIONS DES JOUEURS =============
const P1_MAIN_OFFSET := 150
const P2_MAIN_OFFSET := 150

# ============= BOUTON QUITTER =============
const QUITTER_WIDTH := 64.0
const QUITTER_HEIGHT := 32.0
const QUITTER_OFFSET_X := 0.0
const QUITTER_OFFSET_Y := 8.0

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

# ============= PREVIEW COLORS (SLOT) =============
const PREVIEW_HIGHLIGHT_COLOR := Color(1, 1, 0.5)
const PREVIEW_NORMAL_COLOR := Color(1, 1, 1)

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
