# Shop.gd
# Logique du shop (UI et interactions), découplée de Global.gd, utilise CardBackManager
extends Control

@onready var _shop_title_label: Label = $ShopVBox/ShopTitle
@onready var _shop_grid: GridContainer = $ShopVBox/BacksScroll/BacksGrid

const SHOP_SOURCE_A := "A"
const SHOP_SOURCE_B := "B"
const SHOP_CARD_MIN_WIDTH := 220.0
const SHOP_BACK_PREVIEW_SIZE := Vector2(88, 132)

var _shop_buttons_by_back_id: Dictionary = {}
var _shop_no_back_label: Label = null

func _ready() -> void:
    _init_shop_tab()

func _init_shop_tab() -> void:
    _rebuild_shop_back_items()
    _apply_shop_language()

func _rebuild_shop_back_items() -> void:
    _shop_buttons_by_back_id.clear()
    _shop_no_back_label = null
    for child in _shop_grid.get_children():
        _shop_grid.remove_child(child)
        child.queue_free()
    var back_ids: Array[String] = CardBackManager.get_available_back_ids()
    if back_ids.is_empty():
        var no_back_label := Label.new()
        no_back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        no_back_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _shop_grid.add_child(no_back_label)
        _shop_no_back_label = no_back_label
        return
    for back_id in back_ids:
        _shop_grid.add_child(_create_shop_back_item(back_id))
    # Synchronise l'état visuel des boutons avec la persistance
    _refresh_shop_selection_buttons()

func _create_shop_back_item(back_id: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(SHOP_CARD_MIN_WIDTH, 0.0)
    panel.size_flags_horizontal = Control.SIZE_EXPAND
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.12, 0.12, 0.16, 0.85)
    panel_style.border_color = Color(0.25, 0.25, 0.30, 1.0)
    panel_style.border_width_left = 1
    panel_style.border_width_top = 1
    panel_style.border_width_right = 1
    panel_style.border_width_bottom = 1
    panel_style.corner_radius_top_left = 6
    panel_style.corner_radius_top_right = 6
    panel_style.corner_radius_bottom_left = 6
    panel_style.corner_radius_bottom_right = 6
    panel.add_theme_stylebox_override("panel", panel_style)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    panel.add_child(content)
    var title := Label.new()
    title.text = back_id
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    content.add_child(title)
    var preview_wrap := CenterContainer.new()
    preview_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(preview_wrap)
    var preview := TextureRect.new()
    preview.texture = CardBackManager.get_back_texture_by_id(back_id)
    preview.custom_minimum_size = SHOP_BACK_PREVIEW_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
    preview_wrap.add_child(preview)
    var buttons_row := HBoxContainer.new()
    buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons_row.add_theme_constant_override("separation", 8)
    content.add_child(buttons_row)
    var source_a_button := Button.new()
    source_a_button.focus_mode = Control.FOCUS_NONE
    source_a_button.toggle_mode = true
    source_a_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    source_a_button.pressed.connect(func() -> void:
        _on_shop_back_source_pressed(SHOP_SOURCE_A, back_id)
    )
    buttons_row.add_child(source_a_button)
    var source_b_button := Button.new()
    source_b_button.focus_mode = Control.FOCUS_NONE
    source_b_button.toggle_mode = true
    source_b_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    source_b_button.pressed.connect(func() -> void:
        _on_shop_back_source_pressed(SHOP_SOURCE_B, back_id)
    )
    buttons_row.add_child(source_b_button)
    _shop_buttons_by_back_id[back_id] = {
        SHOP_SOURCE_A: source_a_button,
        SHOP_SOURCE_B: source_b_button,
    }
    return panel

func _on_shop_back_source_pressed(source: String, back_id: String) -> void:
    CardBackManager.assign_back_to_source(source, back_id)
    _refresh_shop_selection_buttons()

func _apply_shop_language() -> void:
    _shop_title_label.text = LanguageManager.ui_text("UI_SHOP_TITLE", "Card backs")
    if _shop_no_back_label != null:
        _shop_no_back_label.text = LanguageManager.ui_text("UI_SHOP_NO_BACKS", "No card backs available")
    _refresh_shop_selection_buttons()

func _shop_source_label(source: String) -> String:
    if source == SHOP_SOURCE_A:
        return LanguageManager.ui_text("UI_SHOP_SOURCE_A", "Source A")
    return LanguageManager.ui_text("UI_SHOP_SOURCE_B", "Source B")

func _refresh_shop_selection_buttons() -> void:
    var selected_a = CardBackManager.get_selected_back_for_source(SHOP_SOURCE_A)
    var selected_b = CardBackManager.get_selected_back_for_source(SHOP_SOURCE_B)
    for raw_back_id in _shop_buttons_by_back_id.keys():
        var back_id := String(raw_back_id)
        var mapping_value = _shop_buttons_by_back_id.get(back_id, {})
        if not (mapping_value is Dictionary):
            continue
        var mapping := mapping_value as Dictionary
        var source_a_button := mapping.get(SHOP_SOURCE_A, null) as Button
        var source_b_button := mapping.get(SHOP_SOURCE_B, null) as Button
        if source_a_button != null:
            _set_shop_button_state(source_a_button, SHOP_SOURCE_A, back_id == selected_a)
        if source_b_button != null:
            _set_shop_button_state(source_b_button, SHOP_SOURCE_B, back_id == selected_b)

func _set_shop_button_state(button: Button, source: String, is_selected: bool) -> void:
    var label := _shop_source_label(source)
    button.text = label
    button.button_pressed = is_selected
    button.modulate = Color(0.392, 0.722, 0.0, 1.0) if is_selected else Color(0.84, 0.84, 0.84, 1)
