# CardVisual.gd
# Gestion du rendu visuel de la carte : dos, bord, valeur/symbole, glow preview.
# Extrait de Carte.gd — Étape 5

class_name CardVisual
extends Node

# ============= CONSTANTS =============
const BACK_TEXTURE_DECK_A := preload("res://assets/Cartes/Dos01.png")
const BACK_TEXTURE_DECK_B := preload("res://assets/Cartes/Dos02.png")

# ============= PUBLIC API =============

## Met à jour l'ensemble du rendu visuel de la carte.
func update(card: Node2D) -> void:
  _apply_back_visual(card, card.decks_color)
  _apply_border_visual(card, card.decks_color)

  if card.dos:
    _show_back(card)
    return

  _show_front(card)

  var symboles := {
    "H": "♥",
    "C": "♦",
    "P": "♠",
    "S": "♣"
  }
  var texte_couleur := Color.RED if (card.couleur == "H" or card.couleur == "C") \
    else Color.BLACK

  card.get_node("Front/Top/ValeurT").text     = card.valeur
  card.get_node("Front/Top/ValeurT").modulate = texte_couleur
  card.get_node("Front/Top/SymboleT").text    = String(symboles.get(card.couleur, "?"))
  card.get_node("Front/Top/SymboleT").modulate = texte_couleur

  card.get_node("Front/Bottom/ValeurB").text     = card.valeur
  card.get_node("Front/Bottom/ValeurB").modulate = texte_couleur
  card.get_node("Front/Bottom/SymboleB").text    = String(symboles.get(card.couleur, "?"))
  card.get_node("Front/Bottom/SymboleB").modulate = texte_couleur

## Applique le glow de preview (appelé par CardDropPreview via la carte).
func highlight_preview(card: Node2D) -> void:
  _set_border_glow(card.get_node_or_null("Front/Bord"), true)
  _set_border_glow(card.get_node_or_null("Back/Bord"),  true)

## Retire le glow et restaure le bord normal (appelé par CardDropPreview via la carte).
func reset_preview(card: Node2D) -> void:
  _set_border_glow(card.get_node_or_null("Front/Bord"), false)
  _set_border_glow(card.get_node_or_null("Back/Bord"),  false)
  _apply_border_visual(card, card.decks_color)

# ============= INTERNAL =============

func _apply_back_visual(card: Node2D, code: String) -> void:
  var back := card.get_node_or_null("Back") as TextureRect
  if back == null:
    return
  back.texture  = _get_back_texture(code)
  back.modulate = Color(1, 1, 1, 1)

func _apply_border_visual(card: Node2D, code: String) -> void:
  var deck_color := _get_back_color(code)
  _set_border_color(card.get_node_or_null("Front/Bord"), deck_color)
  _set_border_color(card.get_node_or_null("Back/Bord"),  deck_color)

func _set_border_color(bord: Panel, border_color: Color) -> void:
  if bord == null:
    return
  var style = bord.get_theme_stylebox("panel")
  if style and style is StyleBoxFlat:
    var new_style = style.duplicate()
    new_style.border_color = border_color
    bord.add_theme_stylebox_override("panel", new_style)

func _set_border_glow(bord: Panel, enabled: bool) -> void:
  if bord == null:
    return
  var style = bord.get_theme_stylebox("panel")
  if style and style is StyleBoxFlat:
    var new_style         = style.duplicate()
    new_style.shadow_size = CardElement.PREVIEW_CARD_GLOW_SIZE  if enabled else 0
    new_style.shadow_color = CardElement.PREVIEW_CARD_GLOW_COLOR if enabled \
      else Color(0, 0, 0, 0)
    new_style.shadow_offset = Vector2.ZERO
    bord.add_theme_stylebox_override("panel", new_style)

func _show_front(card: Node2D) -> void:
  card.get_node("Front").visible = true
  card.get_node("Back").visible  = false

func _show_back(card: Node2D) -> void:
  card.get_node("Front").visible = false
  card.get_node("Back").visible  = true

func _get_back_color(code: String) -> Color:
  if code == "A":
    return Color(0.77, 0.435, 0.597, 1.0)
  return Color(0.2, 0.4, 1.0)

func _get_back_texture(code: String) -> Texture2D:
  var source      := String(code).strip_edges().to_upper()
  var selected_id := CardBackManager.get_selected_back_for_source(source)

  if selected_id == "" and source == "A":
    if "card_back_a" in Global:
      selected_id = Global.card_back_a
  elif selected_id == "" and source == "B":
    if "card_back_b" in Global:
      selected_id = Global.card_back_b

  var selected_texture: Texture2D = CardBackManager.get_back_texture_by_id(selected_id)
  if selected_texture != null:
    return selected_texture

  if source == "A":
    return BACK_TEXTURE_DECK_A
  return BACK_TEXTURE_DECK_B
