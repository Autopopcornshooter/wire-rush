extends Control
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var font: Font = ThemeDB.fallback_font
var buttons: Array[Button] = []
var cyan := Color("76efdc")
var muted := Color("90a7bc")
var white := Color("ecf3f5")

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

func label_at(at: Vector2, text: String, size_px: int = 18, color: Color = white) -> void:
 draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

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
  button.queue_free()
 buttons.clear()
 if game.phase == "menu":
  add_button("START RUN   /   ENTER", Rect2(76, 429, 340, 54), func(): game.start_run(false))
  add_button("PRACTICE   /   P", Rect2(76, 496, 340, 54), func(): game.start_run(true))
  add_button("QUIT", Rect2(76, 563, 164, 40), func(): game.get_tree().quit())
 elif game.phase == "dead":
  add_button("RUN AGAIN   /   R", Rect2(440, 461, 400, 54), func(): game.start_run(game.training))
  add_button("MAIN MENU", Rect2(440, 529, 400, 46), game.return_menu)
 elif game.phase == "paused":
  add_button("RESUME   /   ESC", Rect2(440, 338, 400, 54), game.resume)
  add_button("MAIN MENU", Rect2(440, 408, 400, 48), game.return_menu)
 elif game.phase == "upgrade":
  for i in range(game.choices.size()):
   var slot: int = i
   var key: String = game.choices[i]
   var tier: int = game.rider.tiers[key]
   add_button("%d   /   %s   %d > %d" % [i + 1, Rules.UPGRADES[key][0], tier, mini(3, tier + 1)], Rect2(124 + i * 350, 408, 332, 72), func(): game.choose(slot))

func add_button(text: String, rect: Rect2, action: Callable) -> void:
 var button := Button.new()
 button.text = text
 button.position = rect.position
 button.size = rect.size
 button.add_theme_font_size_override("font_size", 16)
 button.add_theme_color_override("font_color", white)
 button.add_theme_stylebox_override("normal", style(Color("163647")))
 button.add_theme_stylebox_override("hover", style(Color("24576a")))
 button.add_theme_stylebox_override("pressed", style(Color("277b79")))
 button.focus_mode = Control.FOCUS_NONE
 button.pressed.connect(action)
 add_child(button)
 buttons.append(button)

func _draw() -> void:
 if game == null:
  return
 if game.phase == "menu":
  panel(Rect2(42, 62, 420, 584))
  label_at(Vector2(76, 113), "PROTOTYPE 01  /  GODOT 4", 15, cyan)
  label_at(Vector2(72, 185), "WIRE", 68)
  label_at(Vector2(72, 254), "RUSH", 68)
  label_at(Vector2(76, 298), "Find your rhythm above the city.", 18, muted)
  label_at(Vector2(76, 343), "HOOK  >  SWING  >  RELEASE", 17, cyan)
  label_at(Vector2(76, 370), "SLIDE  >  JUMP  >  RECONNECT", 17, cyan)
  label_at(Vector2(76, 405), "Best distance  %04d m" % game.best, 17)
  panel(Rect2(750, 457, 465, 190), 0.88)
  label_at(Vector2(776, 493), "YOUR FIRST SWING", 17, cyan)
  label_at(Vector2(776, 528), "Hold LMB / RMB to connect left / right.", 17)
  label_at(Vector2(776, 556), "Hold Shift to shorten the wire and climb.", 17)
  label_at(Vector2(776, 584), "Let go to fly. Space jumps from the road.", 17)
  label_at(Vector2(776, 620), "Practice includes skates, twin launch & rescue.", 15, muted)
  return
 panel(Rect2(24, 22, 274, 107))
 label_at(Vector2(43, 50), "PRACTICE / AUTO RESCUE" if game.training else "DISTANCE / PERSONAL BEST", 13, cyan)
 label_at(Vector2(40, 100), "%04d" % game.distance, 44)
 label_at(Vector2(170, 98), "m   /   %04d" % game.best, 17, muted)
 panel(Rect2(1000, 22, 256, 107))
 label_at(Vector2(1020, 51), "SPEED", 13, muted)
 label_at(Vector2(1020, 99), "%02d" % game.rider.velocity.length(), 43)
 label_at(Vector2(1085, 97), "m/s  /  %s" % game.rider.mode.to_upper(), 14, cyan)
 panel(Rect2(24, 145, 232, 143), 0.84)
 label_at(Vector2(42, 176), "LV %02d   /   %d XP" % [game.level, game.xp], 16)
 draw_rect(Rect2(42, 188, 196, 4), Color("263e53"))
 draw_rect(Rect2(42, 188, 196 * clampf(game.xp / Rules.xp_required(game.level), 0, 1), 4), cyan)
 label_at(Vector2(42, 219), "SKATES  %d   /   ARMOR  %d" % [game.rider.tiers.skates, game.rider.armor_charges], 14, muted)
 label_at(Vector2(42, 246), "TWIN  " + ("LOCKED" if game.rider.tiers.launcher == 0 else ("READY [E]" if game.rider.launch_cooldown <= 0 else "%.1fs" % game.rider.launch_cooldown)), 14, cyan)
 label_at(Vector2(42, 272), "PERFECT SLIDES  %d" % game.rider.slides, 14, muted)
 if game.phase == "playing":
  for side in [-1, 1]:
   var target: Node3D = game.left_target if side == -1 else game.right_target
   if is_instance_valid(target) and not game.camera.is_position_behind(target.global_position):
    var p: Vector2 = game.camera.unproject_position(target.global_position)
    var color: Color = cyan if side == -1 else Color("ffca8d")
    draw_arc(p, 18, 0, TAU, 28, color, 2, true)
    draw_line(p + Vector2(-23, 0), p + Vector2(-13, 0), color, 2)
    draw_line(p + Vector2(13, 0), p + Vector2(23, 0), color, 2)
    label_at(p + Vector2(-15, -27), "LMB" if side == -1 else "RMB", 13, color)
  if game.rider.mode in ["swing", "air"]:
   var safe: bool = game.rider.velocity.y >= -Rules.SAFE_IMPACT
   var text: String = "SOFT LANDING" if safe else "HARD LANDING — REEL UP"
   label_at(Vector2(510, 563), text, 17, cyan if safe else Color("ffab8f"))
  if game.rider.mode == "slide":
   panel(Rect2(475, 499, 330, 62))
   label_at(Vector2(497, 538), "SLIDE  /  %02d m LEFT" % game.rider.slide_left, 24, cyan)
 panel(Rect2(24, 651, 1232, 47), 0.87)
 label_at(Vector2(44, 681), "LMB / RMB  hook     SHIFT  reel     SPACE  jump     A / D  steer     E  twin launch     ESC  pause     R  restart", 16, muted)
 if game.notice_left > 0 and game.phase == "playing":
  panel(Rect2(270, 593, 740, 40), 0.85)
  label_at(Vector2(290, 620), game.message, 17, cyan)
 if game.phase in ["paused", "dead", "upgrade", "countdown"]:
  draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.035, 0.07, 0.75))
 if game.phase == "paused":
  label_at(Vector2(502, 280), "TAKE A BREATH", 34)
 elif game.phase == "dead":
  panel(Rect2(382, 155, 516, 460))
  label_at(Vector2(437, 211), "RUN COMPLETE", 30, cyan)
  label_at(Vector2(435, 280), "%04d m" % game.distance, 54)
  label_at(Vector2(440, 321), game.death_reason, 16, muted)
  label_at(Vector2(440, 360), "Top speed  %.1f m/s   /   Blocks  %d" % [game.rider.high_speed, int(game.distance / 64)], 19)
  label_at(Vector2(440, 397), "Perfect slides  %d   /   Level  %d" % [game.rider.slides, game.level], 19)
  label_at(Vector2(440, 430), "Skates %d / Twin %d / Armor %d / High %d" % [game.rider.tiers.skates, game.rider.tiers.launcher, game.rider.tiers.armor, game.rider.tiers.high], 16, muted)
 elif game.phase == "upgrade":
  label_at(Vector2(440, 207), "CHOOSE YOUR NEXT EDGE", 30, cyan)
  label_at(Vector2(440, 247), "Level %d  /  physics and timers are paused" % (game.level + 1), 18, muted)
  for i in range(game.choices.size()):
   panel(Rect2(124 + i * 350, 282, 332, 215))
   var key: String = game.choices[i]
   var words: PackedStringArray = str(Rules.UPGRADES[key][1]).split(" ")
   var line: String = ""
   var y: float = 320
   for word in words:
    if (line + word).length() > 31:
     label_at(Vector2(142 + i * 350, y), line, 16, muted)
     y += 25
     line = ""
    line += word + " "
   label_at(Vector2(142 + i * 350, y), line, 16, muted)
 elif game.phase == "countdown":
  label_at(Vector2(460, 325), "READY  /  %d" % maxi(1, ceili(game.countdown)), 48, cyan)
  label_at(Vector2(460, 370), "Release all gameplay buttons to continue", 18, muted)
