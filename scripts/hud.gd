extends Control
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var font: Font = preload("res://assets/fonts/ui_font.tres")
var buttons: Array[Button] = []
var cyan := Color("76efdc")
var muted := Color("90a7bc")
var white := Color("ecf3f5")

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

func t(english: String) -> String:
 return game.locale.text(english)

func label_at(at: Vector2, text: String, size_px: int = 18, color: Color = white, max_width: float = 0) -> void:
 var translated: String = t(text)
 var adjusted: int = size_px
 if max_width > 0:
  while adjusted > 11 and font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, adjusted).x > max_width:
   adjusted -= 1
 draw_string(font, at, translated, HORIZONTAL_ALIGNMENT_LEFT, -1, adjusted, color)

func panel(rect: Rect2, alpha: float = 0.92) -> void:
 draw_style_box(style(Color(0.035, 0.065, 0.11, alpha)), rect)

func style(color: Color) -> StyleBoxFlat:
 var result := StyleBoxFlat.new()
 result.bg_color = color
 result.corner_radius_top_left = 10
 result.corner_radius_top_right = 10
 result.corner_radius_bottom_left = 10
 result.corner_radius_bottom_right = 10
 result.border_color = Color(0.4, 0.7, 0.8, 0.18)
 result.set_border_width_all(1)
 return result

func rebuild_buttons() -> void:
 for button in buttons:
  button.disabled = true
  button.queue_free()
 buttons.clear()
 if game.phase == "menu":
  add_button("START RUN   /   ENTER", Rect2(76, 429, 340, 54), func(): game.start_run(false))
  add_button("PRACTICE   /   P", Rect2(76, 496, 340, 54), func(): game.start_run(true))
  add_button("SETTINGS", Rect2(76, 563, 164, 40), game.open_settings)
  add_button("QUIT", Rect2(252, 563, 164, 40), func(): game.get_tree().quit())
 elif game.phase == "dead":
  add_button("RUN AGAIN   /   R", Rect2(440, 461, 400, 54), func(): game.start_run(game.training))
  add_button("MAIN MENU", Rect2(440, 529, 400, 46), game.return_menu)
 elif game.phase == "paused":
  add_button("RESUME   /   ESC", Rect2(440, 338, 400, 54), game.resume)
  add_button("SETTINGS", Rect2(440, 408, 400, 48), game.open_settings)
  add_button("MAIN MENU", Rect2(440, 476, 400, 48), game.return_menu)
 elif game.phase == "settings":
  add_button("한국어", Rect2(590, 155, 150, 46), func(): game.set_language("ko"), game.preferences.language == "ko")
  add_button("English", Rect2(755, 155, 150, 46), func(): game.set_language("en"), game.preferences.language == "en")
  add_button("BACK   /   ESC", Rect2(520, 585, 240, 46), game.close_settings)
 elif game.phase == "upgrade":
  for i in range(game.choices.size()):
   var slot: int = i
   var key: String = game.choices[i]
   var tier: int = game.rider.tiers[key]
   add_button("%d   /   %s   %d > %d" % [i + 1, t(Rules.UPGRADES[key][0]), tier, mini(3, tier + 1)], Rect2(124 + i * 350, 408, 332, 72), func(): game.choose(slot))

func add_button(text: String, rect: Rect2, action: Callable, selected: bool = false) -> void:
 var button := Button.new()
 button.text = t(text)
 button.position = rect.position
 button.size = rect.size
 button.add_theme_font_size_override("font_size", 16)
 button.add_theme_font_override("font", font)
 button.add_theme_color_override("font_color", white)
 button.add_theme_stylebox_override("normal", style(Color("267468") if selected else Color("163647")))
 button.add_theme_stylebox_override("hover", style(Color("24576a")))
 button.add_theme_stylebox_override("pressed", style(Color("277b79")))
 button.focus_mode = Control.FOCUS_NONE
 button.pressed.connect(action)
 add_child(button)
 buttons.append(button)

func _draw() -> void:
 if game == null:
  return
 if game.phase == "settings":
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
  panel(Rect2(310, 72, 660, 586))
  label_at(Vector2(350, 125), "SETTINGS", 30, cyan)
  label_at(Vector2(350, 187), "LANGUAGE", 20)
  label_at(Vector2(350, 255), "MANUAL SINGLE WIRE", 22, cyan)
  label_at(Vector2(350, 303), "Point at a wall or aerial obstacle; hold either mouse button.", 16, white, 580)
  label_at(Vector2(350, 340), "Other button replaces wire. Far aim adjusts to wire reach.", 16, muted, 580)
  label_at(Vector2(350, 387), "Release with player height at 5m or below: safe landing.", 16, cyan, 580)
  label_at(Vector2(350, 424), "Release above 5m: fatal road landing, even with armor.", 16, Color("ffab8f"), 580)
  label_at(Vector2(350, 461), "Unhooked jumps are exempt. Jumping alone does not renew skating.", 16, white, 580)
  label_at(Vector2(350, 508), "Skates reduce friction. Taller buildings also raise aerial obstacles.", 16, muted, 580)
  label_at(Vector2(350, 552), "Settings could not be saved. They apply for this session." if game.settings_error else "Language is saved automatically.", 14, muted, 580)
  return
 if game.phase == "menu":
  panel(Rect2(42, 62, 420, 584))
  label_at(Vector2(76, 113), "PROTOTYPE 05  /  GODOT 4", 15, cyan)
  label_at(Vector2(72, 185), "WIRE", 68)
  label_at(Vector2(72, 254), "RUSH", 68)
  label_at(Vector2(76, 298), "Find your rhythm above the city.", 18, muted)
  label_at(Vector2(76, 343), "HOOK  >  SWING  >  RELEASE", 17, cyan)
  label_at(Vector2(76, 370), "SLIDE  >  JUMP  >  RECONNECT", 17, cyan)
  label_at(Vector2(76, 405), t("Best distance  %04d m") % game.best, 17)
  panel(Rect2(750, 457, 465, 190), 0.88)
  label_at(Vector2(776, 493), "YOUR FIRST SWING", 17, cyan)
  label_at(Vector2(776, 528), "Point at a wall or aerial obstacle to hook there.", 17, white, 418)
  label_at(Vector2(776, 556), "Hold the mouse button to reel and climb automatically.", 17, white, 418)
  label_at(Vector2(776, 584), "Release the wire when your height is 5m or below.", 17, white, 418)
  label_at(Vector2(776, 620), "Practice: skates included; releasing above 5m risks a fatal landing.", 15, muted, 418)
  label_at(Vector2(76, 630), "MANUAL SINGLE WIRE", 14, cyan, 350)
  return
 panel(Rect2(24, 22, 274, 107))
 label_at(Vector2(43, 50), "PRACTICE / AUTO RESCUE" if game.training else "DISTANCE / PERSONAL BEST", 13, cyan)
 label_at(Vector2(40, 100), "%04d" % game.distance, 44)
 label_at(Vector2(170, 98), "m   /   %04d" % game.best, 17, muted)
 panel(Rect2(1000, 22, 256, 107))
 label_at(Vector2(1020, 51), "SPEED", 13, muted)
 label_at(Vector2(1020, 99), "%02d" % game.rider.velocity.length(), 43)
 label_at(Vector2(1085, 97), "m/s  /  %s" % t(game.rider.mode.to_upper()), 14, cyan, 150)
 panel(Rect2(24, 145, 232, 143), 0.84)
 label_at(Vector2(42, 176), t("LV %02d   /   %d XP") % [game.level, game.xp], 16, white, 198)
 draw_rect(Rect2(42, 188, 196, 4), Color("263e53"))
 draw_rect(Rect2(42, 188, 196 * clampf(game.xp / Rules.xp_required(game.level), 0, 1), 4), cyan)
 label_at(Vector2(42, 219), t("SKATES  %d   /   ARMOR  %d") % [game.rider.tiers.skates, game.rider.armor_charges], 14, muted, 198)
 label_at(Vector2(42, 246), t("BUILDING HEIGHT  +%d m") % Rules.BUILDING_BONUS[game.rider.tiers.high], 14, cyan, 198)
 label_at(Vector2(42, 272), t("SKATE LANDINGS  %d") % game.rider.slides, 14, muted, 198)
 label_at(Vector2(325, 51), "MANUAL SINGLE WIRE", 16, cyan, 500)
 if game.phase == "playing":
  var color: Color = cyan if game.aim_preview.get("valid", false) else Color("ffab8f")
  var cursor: Vector2 = game.aim_screen
  draw_arc(cursor, 12, 0, TAU, 24, color, 2, true)
  draw_line(cursor - Vector2(21, 0), cursor - Vector2(6, 0), color, 2)
  draw_line(cursor + Vector2(6, 0), cursor + Vector2(21, 0), color, 2)
  draw_line(cursor - Vector2(0, 21), cursor - Vector2(0, 6), color, 2)
  draw_line(cursor + Vector2(0, 6), cursor + Vector2(0, 21), color, 2)
  var caption: String = t(game.aim_preview.get("reason", "AIM AT A BUILDING"))
  if game.aim_preview.get("valid", false):
   caption += " / %.1f m" % game.aim_preview.distance
   caption += t(" / TARGET %.1fm") % game.aim_preview.surface_point.y
   if game.aim_preview.get("adjusted", false) and not game.camera.is_position_behind(game.aim_preview.point):
    var assisted: Vector2 = game.camera.unproject_position(game.aim_preview.point)
    draw_line(cursor, assisted, Color(cyan, 0.5), 1, true)
    draw_arc(assisted, 9, 0, TAU, 24, cyan, 2, true)
    draw_circle(assisted, 3, cyan)
  var caption_pos := Vector2(clampf(cursor.x + 25, 25, 920), clampf(cursor.y - 24, 150, 570))
  panel(Rect2(caption_pos - Vector2(8, 25), Vector2(334, 38)), 0.86)
  label_at(caption_pos, caption, 15, color, 318)
  for attached in [game.rider.anchor]:
   if not is_instance_valid(attached) or game.camera.is_position_behind(attached.global_position):
    continue
   var locked: Vector2 = game.camera.unproject_position(attached.global_position)
   draw_circle(locked, 5, cyan)
   draw_arc(locked, 10, 0, TAU, 24, cyan, 2, true)
  if game.rider.mode in ["swing", "air"]:
   var height_key: String = "PLAYER %.2fm / RELEASE NOW %s" if game.rider.hook_connected else "LAST RELEASE %.2fm / LANDING %s"
   var landing_text: String = t("JUMP LANDING EXEMPT") if game.rider.jump_exempt else t(height_key) % [game.rider.landing_height(), t("SAFE" if game.rider.landing_safe() else "FATAL")]
   label_at(Vector2(425, 563), landing_text, 17, cyan if game.rider.landing_safe() else Color("ffab8f"), 500)
  if game.rider.invincible > 0:
   panel(Rect2(475, 85, 330, 44))
   label_at(Vector2(497, 114), t("OBSTACLE SHIELD / %.1f s") % game.rider.invincible, 20, cyan, 294)
  if game.rider.mode == "slide":
   panel(Rect2(24, 304, 310, 54))
   label_at(Vector2(42, 339), t("FRICTION %.2f / %.1f m/s") % [Rules.SKATE_FRICTION[game.rider.tiers.skates], Vector2(game.rider.velocity.x, game.rider.velocity.z).length()], 20, cyan, 274)
 panel(Rect2(24, 651, 1232, 47), 0.87)
 label_at(Vector2(44, 681), "HOLD LMB / RMB  hook + reel     SPACE  jump     A / D  steer     ESC  pause     R  restart", 16, muted, 1190)
 if game.notice_left > 0 and game.phase == "playing":
  panel(Rect2(270, 593, 740, 40), 0.85)
  label_at(Vector2(290, 620), game.locale.message(game.message), 17, cyan, 700)
 if game.phase in ["paused", "dead", "upgrade", "countdown"]:
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
 if game.phase == "paused":
  label_at(Vector2(502, 280), "TAKE A BREATH", 34)
 elif game.phase == "dead":
  panel(Rect2(382, 155, 516, 460))
  label_at(Vector2(437, 211), "RUN COMPLETE", 30, cyan)
  label_at(Vector2(435, 280), "%04d m" % game.distance, 54)
  label_at(Vector2(440, 321), game.locale.message(game.death_reason), 16, muted, 400)
  label_at(Vector2(440, 360), t("Top speed  %.1f m/s   /   Blocks  %d") % [game.rider.high_speed, int(game.distance / 64)], 19, white, 400)
  label_at(Vector2(440, 397), t("Skate landings  %d   /   Level  %d") % [game.rider.slides, game.level], 19, white, 400)
  label_at(Vector2(440, 430), t("Skates %d / Armor %d / Buildings %d") % [game.rider.tiers.skates, game.rider.tiers.armor, game.rider.tiers.high], 16, muted, 400)
 elif game.phase == "upgrade":
  label_at(Vector2(440, 207), "CHOOSE YOUR NEXT EDGE", 30, cyan)
  label_at(Vector2(440, 247), t("Level %d  /  physics and timers are paused") % (game.level + 1), 18, muted)
  for i in range(game.choices.size()):
   panel(Rect2(124 + i * 350, 282, 332, 215))
   var key: String = game.choices[i]
   var words: PackedStringArray = t(Rules.UPGRADES[key][1]).split(" ")
   var line: String = ""
   var y: float = 320
   for word in words:
    if font.get_string_size(line + word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 292:
     label_at(Vector2(142 + i * 350, y), line, 16, muted)
     y += 25
     line = ""
    line += word + " "
   label_at(Vector2(142 + i * 350, y), line, 16, muted)
 elif game.phase == "countdown":
  label_at(Vector2(460, 325), t("READY  /  %d") % maxi(1, ceili(game.countdown)), 48, cyan)
  label_at(Vector2(460, 370), "Release all gameplay buttons to continue", 18, muted)
