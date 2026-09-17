extends Button
## One selectable ability card in the upgrade screen. Owns its own drawing so
## clip_contents can trim the NEW ribbon flush to the card corner.
var hud: Control
var key: String = ""

func _ready() -> void:
 clip_contents = true
 focus_mode = Control.FOCUS_NONE
 text = ""
 var empty := StyleBoxEmpty.new()
 add_theme_stylebox_override("normal", empty)
 add_theme_stylebox_override("hover", empty)
 add_theme_stylebox_override("pressed", empty)
 add_theme_stylebox_override("focus", empty)
 mouse_entered.connect(queue_redraw)
 mouse_exited.connect(queue_redraw)

func _draw() -> void:
 if not is_instance_valid(hud):
  return
 draw_style_box(hud.style(Color(0.035, 0.065, 0.11, 0.92)), Rect2(0, 0, 320, 340))
 if is_hovered():
  draw_style_box(hover_style(), Rect2(0, 0, 320, 340))
 draw_badge()
 draw_icon()
 var label_text: String = hud.t(hud.Rules.UPGRADES[key][0])
 var w: float = hud.font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
 draw_string(hud.font, Vector2(160 - w * 0.5, 300), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, hud.white)

func hover_style() -> StyleBoxFlat:
 # A brighter tint + cyan border on top of the normal panel, so it's clear
 # which card a mouse/gamepad cursor is currently over before clicking.
 var result := StyleBoxFlat.new()
 result.bg_color = Color(hud.cyan.r, hud.cyan.g, hud.cyan.b, 0.1)
 result.corner_radius_top_left = 10
 result.corner_radius_top_right = 10
 result.corner_radius_bottom_left = 10
 result.corner_radius_bottom_right = 10
 result.border_color = hud.cyan
 result.set_border_width_all(3)
 return result

func draw_icon() -> void:
 match key:
  "skates":
   draw_icon_tex(hud.icon_skate, 160, 130, hud.cyan)
  "armor":
   draw_icon_tex(hud.icon_shield, 160, 130, hud.cyan)
  "high":
   draw_icon_tex(hud.icon_city, 160, 130, hud.cyan)
  "range":
   draw_icon_tex(hud.icon_hook, 160, 110, hud.cyan)
   draw_range_arrow(160, 205)
  "reel":
   draw_icon_tex(hud.icon_reel, 160, 130, hud.cyan)
  "hook":
   draw_icon_tex(hud.icon_hook, 160, 130, hud.cyan)
  "jump":
   draw_icon_tex(hud.icon_jump, 160, 130, hud.cyan)
  "double_jump":
   draw_icon_tex(hud.icon_jump, 174, 142, Color(hud.gold, 0.35))
   draw_icon_tex(hud.icon_jump, 160, 130, hud.cyan)

func draw_icon_tex(tex: Texture2D, cx: float, cy: float, color: Color) -> void:
 var size := 130.0
 draw_texture_rect(tex, Rect2(cx - size * 0.5, cy - size * 0.5, size, size), false, color)

func draw_range_arrow(cx: float, cy: float) -> void:
 # Unified cyan to match the rest of the icon set.
 var c: Color = hud.cyan
 var half := 45.0
 draw_line(Vector2(cx - half, cy), Vector2(cx + half, cy), c, 3, true)
 draw_line(Vector2(cx - half, cy), Vector2(cx - half + 12, cy - 7), c, 3, true)
 draw_line(Vector2(cx - half, cy), Vector2(cx - half + 12, cy + 7), c, 3, true)
 draw_line(Vector2(cx + half, cy), Vector2(cx + half - 12, cy - 7), c, 3, true)
 draw_line(Vector2(cx + half, cy), Vector2(cx + half - 12, cy + 7), c, 3, true)

func draw_badge() -> void:
 # Armor is a charge-based exception: no NEW ribbon and no tier dots.
 if key == "armor":
  return
 var tier: int = hud.game.rider.tiers[key]
 if tier <= 0:
  draw_new_ribbon()
 else:
  draw_tier_dots(tier)

func draw_new_ribbon() -> void:
 # A full-width top banner instead of a diagonal corner ribbon: its layout
 # never depends on card size/resolution, unlike a rotated corner band.
 draw_rect(Rect2(0, 0, 320, 34), hud.cyan)
 var label_text: String = hud.t("NEW")
 var w: float = hud.font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
 draw_string(hud.font, Vector2(160 - w * 0.5, 24), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("082019"))

func draw_tier_dots(tier: int) -> void:
 var gap := 24.0
 var start_x: float = 160 - (tier - 1) * gap * 0.5
 for i in range(tier):
  draw_circle(Vector2(start_x + i * gap, 30), 4, hud.cyan)
