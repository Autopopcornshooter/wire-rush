extends Control
const Rules = preload("res://scripts/rules.gd")
const UpgradeCard = preload("res://scripts/upgrade_card.gd")
const Preferences = preload("res://scripts/preferences.gd")
var game: Node3D
var font: Font = preload("res://assets/fonts/ui_font.tres")
var buttons: Array[Button] = []
var sliders: Array[Slider] = []
var cyan := Color("76efdc")
var muted := Color("90a7bc")
var white := Color("ecf3f5")
var gold := Color("ffc876")
## Ability icons: derived from game-icons.net (Delapouite, CC BY 3.0) — see THIRD_PARTY_NOTICES.md.
var icon_skate: Texture2D = preload("res://assets/icons/skate.svg")
var icon_shield: Texture2D = preload("res://assets/icons/shield.svg")
var icon_city: Texture2D = preload("res://assets/icons/city.svg")
var icon_hook: Texture2D = preload("res://assets/icons/hook.svg")
var icon_reel: Texture2D = preload("res://assets/icons/reel.svg")
var icon_jump: Texture2D = preload("res://assets/icons/jump.svg")
var last_pending_upgrades: int = -1
var levelup_trigger_time: float = -10.0
const LEVELUP_POPUP_DURATION: float = 1.0
const LEVELUP_POPUP_FADE_IN: float = 0.15
const LEVELUP_POPUP_HOLD_END: float = 0.75
const UPGRADE_BUMP_DURATION: float = 0.35
const XP_FLASH_DURATION: float = 0.5
const PAUSE_PADDING: float = 26.0
const PAUSE_BUTTON_W: float = 300.0
const PAUSE_BUTTON_H: float = 46.0
const PAUSE_BUTTON_GAP: float = 12.0
const PAUSE_TITLE_H: float = 54.0
const PAUSE_COL_GAP: float = 28.0
const PAUSE_RIGHT_W: float = 190.0
const PAUSE_KEY_ROW_H: float = 22.0
const PAUSE_KEY_PAD: float = 12.0
const PAUSE_KEY_BADGE_W: float = 64.0
const PAUSE_ICON_SIZE: float = 28.0
const PAUSE_DOT_H: float = 12.0
const PAUSE_ICON_ROW_GAP: float = 8.0
const PAUSE_ICON_PAD: float = 12.0
const PAUSE_SECTION_GAP: float = 16.0
const PAUSE_KEY_ROWS: Array = [
 ["LMB/RMB", "HOOK + REEL"],
 ["SPACE", "JUMP"],
 ["G", "UPGRADES"],
 ["A/D", "STEER"],
 ["ESC", "PAUSE"],
 ["R", "RESTART"],
]

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
 for slider in sliders:
  slider.queue_free()
 sliders.clear()
 if game.phase == "menu":
  add_button("Start Run", Rect2(76, 429, 340, 54), func(): game.start_run(false))
  add_button("Practice", Rect2(76, 496, 340, 54), func(): game.start_run(true))
  add_button("SETTINGS", Rect2(76, 563, 164, 40), game.open_settings)
  add_button("QUIT", Rect2(252, 563, 164, 40), func(): game.get_tree().quit())
 elif game.phase == "dead":
  add_button("RUN AGAIN   /   R", Rect2(440, 461, 400, 54), func(): game.start_run(game.training))
  add_button("MAIN MENU", Rect2(440, 529, 400, 46), game.return_menu)
 elif game.phase == "paused":
  var layout: Dictionary = pause_layout()
  add_button("Resume", Rect2(layout.button_x, layout.button_y, layout.button_w, layout.button_h), game.resume)
  add_button("SETTINGS", Rect2(layout.button_x, layout.button_y + layout.button_h + layout.button_gap, layout.button_w, layout.button_h), game.open_settings)
  add_button("MAIN MENU", Rect2(layout.button_x, layout.button_y + (layout.button_h + layout.button_gap) * 2, layout.button_w, layout.button_h), game.return_menu)
 elif game.phase == "settings":
  add_button("한국어", Rect2(500, 253, 150, 40), func(): game.set_language("ko"), game.preferences.language == "ko")
  add_button("English", Rect2(665, 253, 150, 40), func(): game.set_language("en"), game.preferences.language == "en")
  for i in range(Preferences.WINDOW_PRESETS.size()):
   var size: Vector2i = Preferences.WINDOW_PRESETS[i]
   var selected: bool = not game.preferences.fullscreen and game.preferences.window_size == size
   add_button("%d×%d" % [size.x, size.y], Rect2(500 + i * 130, 311, 120, 40), func(): game.set_window_size(size), selected)
  add_button("WINDOWED", Rect2(500, 369, 175, 40), func(): game.set_fullscreen(false), not game.preferences.fullscreen)
  add_button("FULLSCREEN", Rect2(690, 369, 175, 40), func(): game.set_fullscreen(true), game.preferences.fullscreen)
  add_sfx_slider()
  add_button("BACK   /   ESC", Rect2(520, 477, 240, 46), game.close_settings)
 elif game.phase == "upgrade":
  for i in range(game.choices.size()):
   var slot: int = i
   var card := UpgradeCard.new()
   card.hud = self
   card.key = game.choices[i]
   card.position = Vector2(upgrade_card_x(i), 150)
   card.size = Vector2(320, 340)
   card.pressed.connect(func(): game.choose(slot))
   add_child(card)
   buttons.append(card)

func upgrade_card_x(index: int) -> float:
 return 140 + index * 340

func pause_layout() -> Dictionary:
 var owned: Array = []
 for key in Rules.UPGRADES.keys():
  if game.rider.tiers[key] > 0:
   owned.append(key)
 var key_box_h: float = PAUSE_KEY_PAD * 2 + PAUSE_KEY_ROWS.size() * PAUSE_KEY_ROW_H
 var icon_list_h: float = 0.0
 if owned.size() > 0:
  icon_list_h = PAUSE_ICON_PAD * 2 + owned.size() * (PAUSE_ICON_SIZE + PAUSE_DOT_H + PAUSE_ICON_ROW_GAP) - PAUSE_ICON_ROW_GAP
 var right_h: float = key_box_h + (PAUSE_SECTION_GAP + icon_list_h if owned.size() > 0 else 0.0)
 var left_h: float = PAUSE_TITLE_H + 3 * PAUSE_BUTTON_H + 2 * PAUSE_BUTTON_GAP
 var content_h: float = maxf(left_h, right_h)
 var panel_w: float = PAUSE_PADDING * 2 + PAUSE_BUTTON_W + PAUSE_COL_GAP + PAUSE_RIGHT_W
 var panel_h: float = PAUSE_PADDING * 2 + content_h
 var panel_x: float = (1280 - panel_w) * 0.5
 var panel_y: float = (720 - panel_h) * 0.5
 var left_x: float = panel_x + PAUSE_PADDING
 var content_top: float = panel_y + PAUSE_PADDING
 var right_x: float = left_x + PAUSE_BUTTON_W + PAUSE_COL_GAP
 var right_y: float = content_top + (content_h - right_h)
 return {
  "panel": Rect2(panel_x, panel_y, panel_w, panel_h),
  "title_center": Vector2(left_x + PAUSE_BUTTON_W * 0.5, content_top + 30),
  "button_x": left_x,
  "button_y": content_top + PAUSE_TITLE_H,
  "button_w": PAUSE_BUTTON_W,
  "button_h": PAUSE_BUTTON_H,
  "button_gap": PAUSE_BUTTON_GAP,
  "key_box": Rect2(right_x, right_y, PAUSE_RIGHT_W, key_box_h),
  "icon_list": Rect2(right_x, right_y + key_box_h + PAUSE_SECTION_GAP, PAUSE_RIGHT_W, icon_list_h),
  "owned": owned,
 }

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

func add_sfx_slider() -> void:
 var slider := HSlider.new()
 slider.position = Vector2(500, 427)
 slider.size = Vector2(330, 24)
 slider.min_value = 0
 slider.max_value = 100
 slider.step = 1
 slider.value = roundi(game.preferences.sfx_volume * 100)
 slider.focus_mode = Control.FOCUS_NONE
 slider.value_changed.connect(func(value: float): game.set_sfx_volume(value / 100.0))
 add_child(slider)
 sliders.append(slider)

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
  panel(Rect2(290, 157, 700, 406))
  label_at(Vector2(330, 205), "SETTINGS", 30, cyan)
  label_at(Vector2(330, 282), "LANGUAGE", 18)
  label_at(Vector2(330, 340), "RESOLUTION", 18)
  label_at(Vector2(330, 398), "DISPLAY MODE", 18)
  label_at(Vector2(330, 448), "SFX VOLUME", 18)
  label_at(Vector2(845, 448), "%d%%" % roundi(game.preferences.sfx_volume * 100), 14, muted)
  if game.settings_error:
   label_at(Vector2(330, 549), "Settings could not be saved. They apply for this session.", 14, muted, 580)
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
  if game.rider.tiers.double_jump > 0:
   draw_double_jump_indicator()
  if game.rider.mode == "slide":
   draw_slide_indicator()
 label_at(Vector2(16, 693), t("LV %02d   /   %d XP") % [game.level, game.xp], 14, white, 260)
 draw_upgrade_badge(now)
 draw_xp_bar(now)
 draw_levelup_popup(now)
 if game.phase in ["paused", "dead", "upgrade", "countdown"]:
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
 if game.phase == "paused":
  var layout: Dictionary = pause_layout()
  panel(layout.panel)
  label_centered(layout.title_center.x, layout.title_center.y, "PAUSED", 28, cyan)
  draw_pause_key_box(layout.key_box)
  draw_pause_upgrade_list(layout.icon_list, layout.owned)
 elif game.phase == "dead":
  panel(Rect2(382, 155, 516, 460))
  label_at(Vector2(437, 211), "RESULT", 30, cyan)
  label_at(Vector2(435, 280), "%04d m" % game.distance, 54)
  label_at(Vector2(440, 360), t("Top speed  %.1f m/s   /   Blocks  %d") % [game.rider.high_speed, int(game.distance / 64)], 19, white, 400)
  label_at(Vector2(440, 397), t("Skate landings  %d   /   Level  %d") % [game.rider.slides, game.level], 19, white, 400)
  label_at(Vector2(440, 430), t("Skates %d / Armor %d / Buildings %d") % [game.rider.tiers.skates, game.rider.tiers.armor, game.rider.tiers.high], 16, muted, 400)
 elif game.phase == "upgrade":
  label_centered(640, 115, "CHOOSE YOUR NEXT EDGE", 30, cyan)
 elif game.phase == "countdown":
  label_at(Vector2(460, 325), t("READY  /  %d") % game.countdown_number() if game.countdown_started else t("RELEASE CONTROLS"), 48, cyan)
  label_at(Vector2(460, 370), "Aim now; held wire input fires when the countdown ends." if game.countdown_started else "Release all gameplay buttons to continue", 18, muted, 700)

func draw_double_jump_indicator() -> void:
 # Anchored near the character's lower right leg so it reads as gear on the
 # player rather than a floating screen widget.
 var world_point: Vector3 = game.rider.visuals.global_transform * Vector3(0.5, -0.6, 0.1)
 if game.camera.is_position_behind(world_point):
  return
 var screen_point: Vector2 = game.camera.unproject_position(world_point)
 var max_cooldown: float = Rules.DOUBLE_JUMP_COOLDOWN[game.rider.tiers.double_jump - 1]
 var ready: bool = game.rider.double_jump_left <= 0
 var fill_fraction: float = 1.0 if ready else clampf(game.rider.double_jump_left / max_cooldown, 0, 1)
 var fill_color: Color = Color("6cf17a") if ready else gold
 draw_arc(screen_point, 10, 0, TAU, 20, Color(muted, 0.35), 3, true)
 draw_arc(screen_point, 10, -PI * 0.5, -PI * 0.5 + TAU * fill_fraction, 20, fill_color, 3, true)

func draw_slide_indicator() -> void:
 # A vertical fuel-gauge bar beside the character's left hip, draining as the
 # timed slide runs out — replaces the old floating "Xs left / Y m/s" panel.
 var world_point: Vector3 = game.rider.visuals.global_transform * Vector3(-0.55, 0.15, 0.1)
 if game.camera.is_position_behind(world_point):
  return
 var screen_point: Vector2 = game.camera.unproject_position(world_point)
 var max_duration: float = Rules.SLIDE_SECONDS[game.rider.tiers.skates]
 var fraction: float = clampf(game.rider.slide_left / max_duration, 0, 1) if max_duration > 0 else 0.0
 var bar_size := Vector2(8, 40)
 var top_left: Vector2 = screen_point - bar_size * 0.5
 draw_rect(Rect2(top_left, bar_size), Color(muted, 0.35))
 var fill_h: float = bar_size.y * fraction
 draw_rect(Rect2(top_left + Vector2(0, bar_size.y - fill_h), Vector2(bar_size.x, fill_h)), cyan)

func draw_pause_key_box(rect: Rect2) -> void:
 draw_style_box(style(Color(0.06, 0.1, 0.15, 0.85)), rect)
 var y: float = rect.position.y + PAUSE_KEY_PAD
 for row in PAUSE_KEY_ROWS:
  var key_label: String = row[0]
  var badge: Rect2 = Rect2(rect.position.x + 10, y, PAUSE_KEY_BADGE_W, 18)
  draw_style_box(style(Color(0.12, 0.2, 0.27, 0.95)), badge)
  var key_w: float = font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
  draw_string(font, Vector2(badge.position.x + badge.size.x * 0.5 - key_w * 0.5, y + 13), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, white)
  label_at(Vector2(badge.position.x + PAUSE_KEY_BADGE_W + 8, y + 13), row[1], 11, muted)
  y += PAUSE_KEY_ROW_H

func draw_pause_upgrade_list(rect: Rect2, owned: Array) -> void:
 if owned.is_empty():
  return
 draw_style_box(style(Color(0.06, 0.1, 0.15, 0.85)), rect)
 var icon_map: Dictionary = {
  "skates": icon_skate, "armor": icon_shield, "high": icon_city, "range": icon_hook,
  "reel": icon_reel, "hook": icon_hook, "jump": icon_jump, "double_jump": icon_jump,
 }
 var cx: float = rect.position.x + rect.size.x * 0.5
 var y: float = rect.position.y + PAUSE_ICON_PAD
 for key in owned:
  var tex: Texture2D = icon_map[key]
  draw_texture_rect(tex, Rect2(cx - PAUSE_ICON_SIZE * 0.5, y, PAUSE_ICON_SIZE, PAUSE_ICON_SIZE), false, cyan)
  var tier: int = game.rider.tiers[key]
  var dot_gap: float = 10.0
  var start_x: float = cx - (tier - 1) * dot_gap * 0.5
  for i in range(tier):
   draw_circle(Vector2(start_x + i * dot_gap, y + PAUSE_ICON_SIZE + 7), 2.5, cyan)
  y += PAUSE_ICON_SIZE + PAUSE_DOT_H + PAUSE_ICON_ROW_GAP

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
