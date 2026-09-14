extends Control
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var font: Font = preload("res://assets/fonts/ui_font.tres")
var buttons: Array[Button] = []
var cyan := Color("76efdc")
var muted := Color("90a7bc")
var white := Color("ecf3f5")
var gold := Color("ffc876")
var last_pending_upgrades: int = -1
var levelup_trigger_time: float = -10.0
const LEVELUP_POPUP_DURATION: float = 1.0
const LEVELUP_POPUP_FADE_IN: float = 0.15
const LEVELUP_POPUP_HOLD_END: float = 0.75
const UPGRADE_BUMP_DURATION: float = 0.35
const XP_FLASH_DURATION: float = 0.5

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

func label_centered(center_x: float, y: float, text: String, size_px: int = 18, color: Color = white) -> void:
 var translated: String = t(text)
 var width: float = font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
 draw_string(font, Vector2(center_x - width * 0.5, y), translated, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

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
  add_button("Start Run", Rect2(76, 429, 340, 54), func(): game.start_run(false))
  add_button("Practice", Rect2(76, 496, 340, 54), func(): game.start_run(true))
  add_button("SETTINGS", Rect2(76, 563, 164, 40), game.open_settings)
  add_button("QUIT", Rect2(252, 563, 164, 40), func(): game.get_tree().quit())
 elif game.phase == "dead":
  add_button("RUN AGAIN   /   R", Rect2(440, 461, 400, 54), func(): game.start_run(game.training))
  add_button("MAIN MENU", Rect2(440, 529, 400, 46), game.return_menu)
 elif game.phase == "paused":
  add_button("Resume", Rect2(440, 358, 400, 54), game.resume)
  add_button("SETTINGS", Rect2(440, 428, 400, 48), game.open_settings)
  add_button("MAIN MENU", Rect2(440, 496, 400, 48), game.return_menu)
 elif game.phase == "settings":
  add_button("한국어", Rect2(590, 155, 150, 46), func(): game.set_language("ko"), game.preferences.language == "ko")
  add_button("English", Rect2(755, 155, 150, 46), func(): game.set_language("en"), game.preferences.language == "en")
  add_button("BACK   /   ESC", Rect2(520, 340, 240, 46), game.close_settings)
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
 # Pure presentation: detect a level-up by watching the existing pending_upgrades
 # counter change, without touching how or when main.gd increments it.
 var now: float = Time.get_ticks_msec() / 1000.0
 if last_pending_upgrades >= 0 and game.pending_upgrades > last_pending_upgrades:
  levelup_trigger_time = now
  game.tone(880, 0.18)
 last_pending_upgrades = game.pending_upgrades
 if game.phase == "settings":
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
  panel(Rect2(310, 72, 660, 300))
  label_at(Vector2(350, 125), "SETTINGS", 30, cyan)
  label_at(Vector2(350, 187), "LANGUAGE", 20)
  label_at(Vector2(350, 300), "Settings could not be saved. They apply for this session." if game.settings_error else "Language is saved automatically.", 14, muted, 580)
  return
 if game.phase == "menu":
  panel(Rect2(42, 62, 420, 584))
  label_at(Vector2(72, 185), "WIRE", 68)
  label_at(Vector2(72, 254), "RUSH", 68)
  label_at(Vector2(76, 405), t("Best distance  %04d m") % game.best, 17)
  return
 panel(Rect2(24, 22, 300, 180))
 label_at(Vector2(43, 50), "PRACTICE / AUTO RESCUE" if game.training else "DISTANCE / PERSONAL BEST", 13, cyan)
 label_at(Vector2(40, 100), "%04d" % game.distance, 44)
 label_at(Vector2(170, 98), "m   /   %04d" % game.best, 17, muted)
 label_at(Vector2(43, 138), t("SPEED %02d m/s   /   %s") % [game.rider.velocity.length(), t(game.rider.mode.to_upper())], 16, cyan, 260)
 label_at(Vector2(43, 168), t("SKATES %d / ARMOR %d / HEIGHT +%dm / SLIDES %d") % [game.rider.tiers.skates, game.rider.armor_charges, Rules.BUILDING_BONUS[game.rider.tiers.high], game.rider.slides], 12, muted, 260)
 panel(Rect2(24, 210, 150, 34), 0.8)
 draw_style_box(style(Color(0.12, 0.2, 0.27, 0.95)), Rect2(32, 217, 38, 20))
 label_at(Vector2(37, 231), "ESC", 11, white)
 label_at(Vector2(80, 233), "PAUSE", 13, muted)
 if game.phase == "playing":
  var color: Color = cyan if game.aim_preview.get("valid", false) else Color("ffab8f")
  var cursor: Vector2 = game.aim_screen
  draw_arc(cursor, 12, 0, TAU, 24, color, 2, true)
  draw_line(cursor - Vector2(21, 0), cursor - Vector2(6, 0), color, 2)
  draw_line(cursor + Vector2(6, 0), cursor + Vector2(21, 0), color, 2)
  draw_line(cursor - Vector2(0, 21), cursor - Vector2(0, 6), color, 2)
  draw_line(cursor + Vector2(0, 6), cursor + Vector2(0, 21), color, 2)
  if game.aim_preview.get("valid", false) and game.aim_preview.get("adjusted", false) and not game.camera.is_position_behind(game.aim_preview.point):
   var assisted: Vector2 = game.camera.unproject_position(game.aim_preview.point)
   draw_line(cursor, assisted, Color(cyan, 0.5), 1, true)
   draw_arc(assisted, 9, 0, TAU, 24, cyan, 2, true)
   draw_circle(assisted, 3, cyan)
  if is_instance_valid(game.rider.anchor) and not game.camera.is_position_behind(game.rider.anchor.global_position):
   var locked: Vector2 = game.camera.unproject_position(game.rider.anchor.global_position)
   draw_circle(locked, 5, cyan)
   draw_arc(locked, 10, 0, TAU, 24, cyan, 2, true)
  if game.rider.mode == "slide":
   panel(Rect2(24, 304, 310, 54))
   label_at(Vector2(42, 339), t("SLIDE %.1fs LEFT / %.1f m/s") % [game.rider.slide_left, Vector2(game.rider.velocity.x, game.rider.velocity.z).length()], 20, cyan, 274)
 label_at(Vector2(16, 693), t("LV %02d   /   %d XP") % [game.level, game.xp], 14, white, 260)
 draw_upgrade_badge(now)
 draw_xp_bar(now)
 draw_levelup_popup(now)
 if game.phase in ["paused", "dead", "upgrade", "countdown"]:
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
 if game.phase == "paused":
  panel(Rect2(340, 150, 600, 410))
  label_centered(640, 195, "PAUSED", 34, cyan)
  label_centered(640, 250, "LMB/RMB hook + reel   /   SPACE jump   /   G upgrades", 14, muted)
  label_centered(640, 276, "A/D steer   /   ESC pause   /   R restart", 14, muted)
 elif game.phase == "dead":
  panel(Rect2(382, 155, 516, 460))
  label_at(Vector2(437, 211), "RESULT", 30, cyan)
  label_at(Vector2(435, 280), "%04d m" % game.distance, 54)
  label_at(Vector2(440, 360), t("Top speed  %.1f m/s   /   Blocks  %d") % [game.rider.high_speed, int(game.distance / 64)], 19, white, 400)
  label_at(Vector2(440, 397), t("Skate landings  %d   /   Level  %d") % [game.rider.slides, game.level], 19, white, 400)
  label_at(Vector2(440, 430), t("Skates %d / Armor %d / Buildings %d") % [game.rider.tiers.skates, game.rider.tiers.armor, game.rider.tiers.high], 16, muted, 400)
 elif game.phase == "upgrade":
  label_at(Vector2(440, 207), "CHOOSE YOUR NEXT EDGE", 30, cyan)
  var remaining_text: String = t(" / %d MORE QUEUED") % (game.pending_upgrades - 1) if game.pending_upgrades > 1 else ""
  label_at(Vector2(440, 247), t("Level %d  /  physics and timers are paused") % game.level + remaining_text, 18, muted)
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
  label_at(Vector2(460, 325), t("READY  /  %d") % game.countdown_number() if game.countdown_started else t("RELEASE CONTROLS"), 48, cyan)
  label_at(Vector2(460, 370), "Aim now; held wire input fires when the countdown ends." if game.countdown_started else "Release all gameplay buttons to continue", 18, muted, 700)

func draw_upgrade_badge(now: float) -> void:
 if game.pending_upgrades <= 0:
  return
 var pivot := Vector2(1176, 692)
 var since_bump: float = now - levelup_trigger_time
 var bump: float = 0.0
 if since_bump >= 0 and since_bump < UPGRADE_BUMP_DURATION:
  bump = (1.0 - since_bump / UPGRADE_BUMP_DURATION)
 var pulse: float = 0.5 + 0.5 * sin(now * 2.4)
 var scale: float = 1.0 + 0.05 * pulse + 0.22 * bump
 var glow_alpha: float = 0.12 + 0.1 * pulse + 0.35 * bump
 var label_text: String = t("[G] UPGRADE") + " ×%d" % game.pending_upgrades
 var width: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
 var box_size := Vector2(width + 36, 34)
 draw_set_transform(pivot, 0, Vector2(scale, scale))
 # Soft layered glow behind the pill; cheap stand-in for a blurred outer glow.
 draw_style_box(style(Color(gold, glow_alpha * 0.5)), Rect2(-box_size.x * 0.5 - 10, -box_size.y * 0.5 - 8, box_size.x + 20, box_size.y + 16))
 draw_style_box(style(Color(0.035, 0.065, 0.11, 0.92)), Rect2(-box_size.x * 0.5, -box_size.y * 0.5, box_size.x, box_size.y))
 var text_color := Color(gold, 0.85 + 0.15 * pulse)
 draw_string(font, Vector2(-width * 0.5, 6), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, text_color)
 draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_xp_bar(now: float) -> void:
 var fraction: float = clampf(game.xp / Rules.xp_required(game.level), 0, 1)
 var since_flash: float = now - levelup_trigger_time
 var flash: float = 0.0
 if since_flash >= 0 and since_flash < XP_FLASH_DURATION:
  flash = 1.0 - since_flash / XP_FLASH_DURATION
 draw_rect(Rect2(0, 712, 1280, 6), Color("263e53"))
 draw_rect(Rect2(0, 712, 1280 * fraction, 6), cyan.lerp(white, flash * 0.7))
 if flash > 0:
  draw_rect(Rect2(0, 712 - flash * 2, 1280, 6 + flash * 4), Color(white, flash * 0.35))

func draw_levelup_popup(now: float) -> void:
 var elapsed: float = now - levelup_trigger_time
 if elapsed < 0 or elapsed > LEVELUP_POPUP_DURATION:
  return
 var alpha: float
 var pop_scale: float
 if elapsed < LEVELUP_POPUP_FADE_IN:
  var progress: float = elapsed / LEVELUP_POPUP_FADE_IN
  alpha = progress
  pop_scale = lerpf(1.28, 1.0, progress)
 elif elapsed < LEVELUP_POPUP_HOLD_END:
  alpha = 1.0
  pop_scale = 1.0
 else:
  alpha = 1.0 - (elapsed - LEVELUP_POPUP_HOLD_END) / (LEVELUP_POPUP_DURATION - LEVELUP_POPUP_HOLD_END)
  pop_scale = 1.0
 var pivot := Vector2(640, 210)
 draw_set_transform(pivot, 0, Vector2(pop_scale, pop_scale))
 draw_style_box(style(Color(0.035, 0.065, 0.11, 0.85 * alpha)), Rect2(-160, -38, 320, 84))
 label_centered(0, -8, "UPGRADE READY", 26, Color(gold, alpha))
 label_centered(0, 22, "Upgrade Point +1", 15, Color(white, alpha))
 draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
