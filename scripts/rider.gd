extends CharacterBody3D
const Rules = preload("res://scripts/rules.gd")
const CharacterVisual = preload("res://scripts/character_visual.gd")
## Swap the humanoid model here during development (see CharacterVisual.CHARACTERS).
## Empty string keeps the original primitive-box look with zero risk to it.
const ACTIVE_CHARACTER: String = "lowpoly_anime_character_cyberstyle"
signal notice(message: String)
signal crashed(reason: String)
signal slid
var city: Node3D
var mode: String = "air"
var anchor: Node3D = null
var wire_side: int = 0
var rope_length: float = 0
var hook_left: float = 0
var hook_duration: float = 0
var hook_connected: bool = false
var last_release_height: float = 0
var fresh_landing_hook: bool = false
var jump_exempt: bool = false
var invincible: float = 0
var double_jump_left: float = 0
var touching_wall_side: int = 0
var slide_left: float = 0
## Persistent 0..1 roller-skate resource (see Rules.SKATE_MAX_DURATION/
## SKATE_RECHARGE_DURATION). Only reset() touches this directly — wire
## connects, jumps, and landings never reset it, only slide usage (drain)
## and time spent not sliding (recharge) do.
var skate_charge: float = 1.0
var ignored_obstacles: Array[PhysicsBody3D] = []
var armor_charges: int = 0
var tiers: Dictionary = {
 "skates": 0, "armor": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0, "double_jump": 0,
 "attach_assist": 0, "air_control": 0, "ground_control": 0, "release_momentum": 0,
 "skate_recharge": 0, "skate_efficiency": 0, "collision_grace": 0, "armor_support": 0,
}
## Set true the instant a double jump is spent, cleared by the first
## fire_manual() afterward (successful or not) — see Rules.UPGRADES.double_jump
## tier 3 and the SKY_RUNNER synergy, both of which spend this same flag.
var just_double_jumped: bool = false
## Re-evaluated by evaluate_synergies() after every upgrade() call and on
## reset(). Not player-selectable — see PHASE A spec section 14/15.
var active_synergies: Dictionary = {"slingshot": false, "street_surfer": false, "sky_runner": false}
var practice: bool = false
var visuals: Node3D
var wire_mesh: MeshInstance3D
var wire_surface: ImmediateMesh
var high_speed: float = 0
var slides: int = 0

func _ready() -> void:
 collision_layer = 2
 collision_mask = 1
 var collider := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 # Sized to match the visual character's real-world ~1.7m height (see
 # character_visual.gd's per-character scale, solved from the same
 # head-top-to-toe-tip bone measurement). Capsule stays centered on Rider's
 # own origin — the origin itself is untouched, only its size changed.
 capsule.radius = 0.35
 capsule.height = 1.7
 collider.shape = capsule
 add_child(collider)
 visuals = Node3D.new()
 add_child(visuals)
 if ACTIVE_CHARACTER != "" and CharacterVisual.CHARACTERS.has(ACTIVE_CHARACTER):
  var character_visual := CharacterVisual.new()
  visuals.add_child(character_visual)
  character_visual.setup(ACTIVE_CHARACTER)
  character_visual.bind_rider(self)
 else:
  city.box(visuals, Vector3(0, 0.05, 0), Vector3(0.65, 0.75, 0.38), Color("e2e9e4"))
  city.box(visuals, Vector3(0, 0.65, -0.01), Vector3(0.48, 0.43, 0.46), Color("ffc876"))
  city.box(visuals, Vector3(0, 0.68, -0.26), Vector3(0.43, 0.13, 0.035), Color("162f42"))
  city.box(visuals, Vector3(0, 0.15, 0.25), Vector3(0.45, 0.5, 0.2), Color("42c4b5"), false, true)
  for side in [-1, 1]:
   city.box(visuals, Vector3(side * 0.2, -0.5, 0), Vector3(0.22, 0.55, 0.23), Color("314659"))
   city.box(visuals, Vector3(side * 0.2, -0.76, -0.07), Vector3(0.25, 0.14, 0.48), Color("67f1dc"), false, true)
   city.box(visuals, Vector3(side * 0.45, 0.0, 0), Vector3(0.20, 0.6, 0.2), Color("b2c8c8"))
 wire_mesh = MeshInstance3D.new()
 wire_surface = ImmediateMesh.new()
 wire_mesh.mesh = wire_surface
 wire_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var wire_material := StandardMaterial3D.new()
 wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 wire_material.vertex_color_use_as_albedo = true
 wire_mesh.material_override = wire_material
 add_child(wire_mesh)
 wire_mesh.top_level = true

func reset(training: bool) -> void:
 release_wire()
 clear_obstacle_exceptions()
 visuals.visible = true
 practice = training
 mode = "air"
 position = Vector3(0, city.start_height(), 0)
 velocity = Vector3(0, -2, -12)
 tiers = {
  "skates": 1 if training else 0, "armor": 0, "range": 0, "reel": 0, "hook": 0, "jump": 0, "double_jump": 0,
  "attach_assist": 0, "air_control": 0, "ground_control": 0, "release_momentum": 0,
  "skate_recharge": 0, "skate_efficiency": 0, "collision_grace": 0, "armor_support": 0,
 }
 armor_charges = 0
 invincible = 0
 last_release_height = 0
 fresh_landing_hook = false
 jump_exempt = false
 double_jump_left = 0
 touching_wall_side = 0
 slide_left = 0
 skate_charge = 1.0
 slides = 0
 high_speed = 0
 just_double_jumped = false
 evaluate_synergies()

func reach() -> float:
 return Rules.ROPE_RANGE * (1.0 + tiers.range * 0.1)

## Small widening of City.range_limited_target()'s existing "RANGE ASSIST"
## tolerance — see Rules.UPGRADES.attach_assist. Only main.gd's player-facing
## manual_target() calls pass this; tests and validation scripts that omit it
## keep the original 0.08m tolerance untouched.
func aim_slack() -> float:
 return 0.08 + tiers.attach_assist * 0.04

func fire_manual(selection: Dictionary, side: int) -> bool:
 if mode == "dead":
  return false
 if not selection.get("valid", false):
  notice.emit(selection.get("reason", "AIM AT A SURFACE"))
  return false
 var checked: Dictionary = city.validate_manual_point(global_position, selection.surface_point, selection.normal, selection.surface, reach(), get_rid())
 if not checked.valid:
  notice.emit(checked.reason)
  return false
 release_wire()
 var point := Node3D.new()
 checked.surface.add_child(point)
 point.global_position = checked.point
 anchor = point
 wire_side = side
 hook_duration = global_position.distance_to(point.global_position) / (Rules.HOOK_SPEED * (1.0 + tiers.hook * 0.2))
 # Double Jump tier 3 (and, more so, the SKY_RUNNER synergy) rewards the
 # very next wire connection after a double jump with a faster hook flight.
 # Consumed once per double jump, win or lose — see Rules.UPGRADES.double_jump
 # and PHASE A spec section 14 (SKY_RUNNER).
 if just_double_jumped and tiers.double_jump >= 3:
  hook_duration *= 0.7 if active_synergies.sky_runner else 0.85
 just_double_jumped = false
 hook_left = hook_duration
 hook_connected = false
 notice.emit("MANUAL HOOK FIRED — position locked until the next shot")
 return true

func release_wire() -> void:
 if is_instance_valid(anchor):
  if hook_connected:
   last_release_height = global_position.y
   if mode == "swing":
    # Release Momentum (small, tier-scaled) plus SLINGSHOT (Reel Speed +
    # Wire Length synergy, only above a real swinging speed) — both are
    # gentle multipliers on the velocity the physics already produced, never
    # an added force, so they can't destabilize the underlying wire physics.
    # See Rules.UPGRADES.release_momentum and PHASE A spec section 14.
    var momentum_bonus: float = 1.0 + tiers.release_momentum * 0.02
    if active_synergies.slingshot and velocity.length() > 15.0:
     momentum_bonus *= 1.05
    velocity *= momentum_bonus
  anchor.queue_free()
 anchor = null
 wire_side = 0
 hook_left = 0
 hook_connected = false
 if mode == "swing":
  mode = "air"
 # Only detaching a connected wire records player height. Empty/in-flight releases
 # preserve this history, including repeated cleanup and pause/resume calls.

func release_side(side: int) -> void:
 if wire_side == side:
  release_wire()

func jump() -> void:
 if mode in ["ground", "slide"]:
  release_wire()
  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
  mode = "air"
  jump_exempt = true
  fresh_landing_hook = false
  notice.emit("JUMP — safe landing unless you connect a new wire")
 # Wall jump disabled pending a working touch-detection pass; keep touching_wall_side tracked but unused.
 # elif mode == "air" and touching_wall_side != 0:
 #  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
 #  velocity.x = touching_wall_side * Rules.WALL_JUMP_PUSH
 #  jump_exempt = true
 #  touching_wall_side = 0
 #  notice.emit("WALL JUMP — pushed off the building")
 elif mode == "air" and tiers.double_jump > 0 and double_jump_left <= 0:
  velocity.y = Rules.JUMP_SPEED * sqrt(1.0 + tiers.jump * 0.1)
  jump_exempt = true
  double_jump_left = Rules.DOUBLE_JUMP_COOLDOWN[tiers.double_jump - 1]
  just_double_jumped = true
  notice.emit("DOUBLE JUMP")

func landing_height() -> float:
 # While attached, preview the result of releasing at the current player height.
 return global_position.y if is_instance_valid(anchor) and hook_connected else last_release_height

func landing_safe() -> bool:
 return jump_exempt or landing_height() <= Rules.SAFE_RELEASE_HEIGHT + 0.00001

func simulate(delta: float, steer: float, forward: float = 0.0) -> void:
 if mode == "dead":
  return
 touching_wall_side = 0
 for step in range(2):
  integrate(delta * 0.5, steer, forward)
 high_speed = maxf(high_speed, velocity.length())
 visuals.visible = invincible <= 0 or fmod(invincible, 0.4) > 0.16
 update_visual_banking(delta)

## Whole-body lean applied to `visuals` (never Rider/CollisionShape itself).
## Split out from simulate() so it's callable/testable on its own.
func update_visual_banking(delta: float) -> void:
 # This pitch/roll was tuned for the old primitive-box visual, which had no
 # real slide pose of its own — pitching the entire visuals node forward by
 # ~31 degrees was how "sliding" was faked. The real Running Slide animation
 # (and CharacterVisual's own yaw-only slide facing, applied a level deeper
 # on the model itself) already portrays the slide correctly, so stacking
 # this extra pitch/roll on top of it is what pivoted the character up off
 # the ground and tilted it sideways.
 if mode == "slide":
  visuals.rotation.z = lerpf(visuals.rotation.z, 0.0, delta * 8)
  visuals.rotation.x = lerpf(visuals.rotation.x, 0.0, delta * 8)
 else:
  visuals.rotation.z = lerpf(visuals.rotation.z, clampf(-velocity.x * 0.045, -0.45, 0.45), delta * 8)
  visuals.rotation.x = lerpf(visuals.rotation.x, 0.12, delta * 8)

func integrate(dt: float, steer: float, forward: float = 0.0) -> void:
 if mode == "dead":
  return
 invincible = maxf(0, invincible - dt)
 if invincible <= 0:
  clear_obstacle_exceptions()
 double_jump_left = maxf(0, double_jump_left - dt)
 if mode == "ground":
  # Forward walking uses the same top speed (4.5) as the existing left/
  # right ground steer, normalized together so a diagonal (forward+strafe)
  # input can't exceed that speed by moving sqrt(2)x faster. Ground Control
  # (Rules.UPGRADES.ground_control) scales both speed and response together.
  var ground_speed: float = 4.5 * (1.0 + tiers.ground_control * 0.08)
  var ground_accel: float = 18.0 * (1.0 + tiers.ground_control * 0.08)
  var ground_input := Vector2(steer, -forward)
  if ground_input.length() > 1.0:
   ground_input = ground_input.normalized()
  velocity.x = move_toward(velocity.x, ground_input.x * ground_speed, ground_accel * dt)
  velocity.z = move_toward(velocity.z, ground_input.y * ground_speed, ground_accel * dt)
 elif mode == "slide":
  var horizontal := Vector3(velocity.x, 0, velocity.z)
  # Steering rotates momentum; it does not add or remove speed. Duration alone ends the slide.
  var direction: Vector3 = horizontal.normalized().rotated(Vector3.UP, -steer * 0.6 * dt)
  velocity.x = direction.x * horizontal.length()
  velocity.z = direction.z * horizontal.length()
  slide_left = maxf(0, slide_left - dt)
  # Charge drains in lockstep with slide_left (both fall to 0 together,
  # since slide_left was initialized as skate_charge * max_duration above).
  # Skate Efficiency (Rules.UPGRADES.skate_efficiency) slows the drain
  # without touching the core tier's own SKATE_MAX_DURATION numbers.
  var drain_scale: float = 1.0 - tiers.skate_efficiency * 0.1
  skate_charge = maxf(0, skate_charge - dt / Rules.SKATE_MAX_DURATION[tiers.skates] * drain_scale)
  if slide_left <= 0 or skate_charge <= 0:
   stop_on_ground()
 else:
  # Air Control (Rules.UPGRADES.air_control) plus a small Double Jump tier-2
  # bonus (Rules.UPGRADES.double_jump) both scale this same lateral steering
  # accel; swing/dead never see the bonus since it's scoped to mode=="air".
  var lateral_accel: float = 3.5
  if mode == "air":
   var double_jump_bonus: float = 0.12 if tiers.double_jump >= 2 else 0.0
   lateral_accel *= 1.0 + tiers.air_control * 0.15 + double_jump_bonus
  velocity.x = move_toward(velocity.x, steer * 5, lateral_accel * dt)
 # Recharges any time the player isn't actively spending it sliding —
 # regardless of ground/air/swing mode, and never reset by wire connect,
 # jump, or landing (only actual slide usage drains it, only reset() to a
 # fresh run sets it back to full). Skate Recharge (Rules.UPGRADES.skate_recharge)
 # speeds this up without touching the core tier's own recharge numbers.
 if mode != "slide" and tiers.skates > 0 and skate_charge < 1.0:
  var recharge_scale: float = 1.0 + tiers.skate_recharge * 0.15
  skate_charge = minf(1.0, skate_charge + dt / Rules.SKATE_RECHARGE_DURATION[tiers.skates] * recharge_scale)
 velocity.y -= Rules.GRAVITY * dt
 if is_instance_valid(anchor):
  hook_left -= dt
  if hook_left <= 0:
   if not hook_connected:
    hook_connected = true
    rope_length = global_position.distance_to(anchor.global_position)
    fresh_landing_hook = true
    jump_exempt = false
   mode = "swing"
   rope_length = maxf(3, rope_length - Rules.REEL_SPEED * (1 + tiers.reel * 0.15) * dt)
   var radial: Vector3 = global_position + velocity * dt - anchor.global_position
   if radial.length() > rope_length:
    velocity = (anchor.global_position + radial.normalized() * rope_length - global_position) / dt
 velocity = velocity.limit_length(Rules.MAX_SPEED)
 var motion: Vector3 = velocity * dt
 var touched_floor: bool = false
 for collision_index in range(3):
  var incoming: Vector3 = velocity
  var hit := move_and_collide(motion)
  if hit == null:
   break
  var normal: Vector3 = hit.get_normal()
  var impact: float = maxf(0, -incoming.dot(normal))
  var collider: Object = hit.get_collider()
  if normal.y > 0.7 and collider.get_meta("road", false):
   touched_floor = true
   if mode in ["air", "swing"]:
    land(incoming)
    if mode in ["dead", "ground"]:
     return
   velocity = velocity.slide(normal)
  elif not collider.get_meta("road", false) and not collider.get_meta("building", false) and (invincible > 0 or impact > 3):
   if not hurt("OBSTACLE COLLISION"):
    return
   # Preserve incoming velocity and use the untraveled sweep after the hit.
   # Only obstacle bodies are ignored. Road landing rules remain active.
   if collider is PhysicsBody3D:
    add_collision_exception_with(collider)
    if not ignored_obstacles.has(collider):
     ignored_obstacles.append(collider)
   motion = hit.get_remainder()
   continue
  else:
   # Building walls are always safe to touch — this is what makes the wall jump usable.
   if mode == "air" and absf(normal.y) < 0.4 and collider.get_meta("building", false):
    touching_wall_side = signi(normal.x)
   velocity = velocity.slide(normal) * 0.85
  motion = hit.get_remainder().slide(normal)
 # Was -0.5, which (at ~20 m/s^2 gravity, two 1/120s substeps per real
 # frame) let the player visibly run/walk/slide a beat or two past a ledge
 # in mid-air before mode actually flipped to "air" — most noticeable
 # since forward walking was added, since it's now easy to jog straight off
 # a rooftop edge instead of only ever strafing near one. -0.2 is still
 # safely above the ~0.1667 a single resting substep's own gravity
 # accumulation can transiently reach before that substep's own floor
 # collision zeroes it back out (so standing/walking on solid ground still
 # never false-triggers this), but closes most of that visible gap.
 if mode in ["ground", "slide"] and not touched_floor and velocity.y < -0.2:
  mode = "air"
 if position.y < -8:
  hurt("MISSED THE ROAD")
 if absf(position.x) > 6.6:
  position.x = clampf(position.x, -6.6, 6.6)
  velocity.x = 0

func land(incoming: Vector3) -> void:
 # Road contact also detaches a held wire at the player contact height.
 release_wire()
 if not landing_safe():
  die("HIGH RELEASE LANDING — player released above 5m")
  return
 var can_slide: bool = fresh_landing_hook and not jump_exempt and tiers.skates > 0 and skate_charge > 0
 fresh_landing_hook = false
 jump_exempt = false
 if can_slide and Vector2(incoming.x, incoming.z).length() > Rules.STOP_SPEED:
  velocity = Vector3(incoming.x, 0, incoming.z)
  mode = "slide"
  # Uses whatever charge is currently available, scaled to this tier's max
  # duration — not always a full reset. A slide right after a previous one
  # only gets whatever's recharged back since then.
  slide_left = skate_charge * Rules.SKATE_MAX_DURATION[tiers.skates]
  slides += 1
  notice.emit("SKATING — timed slide; reconnect before landing again")
  slid.emit()
 else:
  stop_on_ground()

func stop_on_ground() -> void:
 release_wire()
 var retained: Vector3 = Vector3.ZERO
 if mode == "slide" and active_synergies.street_surfer:
  # STREET SURFER (Roller Skate core Lv3 + Momentum investment): softens the
  # otherwise-instant stop when a timed slide's duration runs out, instead
  # of zeroing velocity outright. Only applies when actually ending a slide
  # (mode == "slide" here) — an ordinary flat landing still stops cleanly.
  # See PHASE A spec section 14.
  retained = Vector3(velocity.x, 0, velocity.z) * 0.25
 mode = "ground"
 velocity = retained
 notice.emit("LANDED — stopped; Space to jump or mouse to hook")

func die(reason: String) -> void:
 release_wire()
 mode = "dead"
 visuals.visible = true
 clear_obstacle_exceptions()
 velocity = Vector3.ZERO
 crashed.emit(reason)

func clear_obstacle_exceptions() -> void:
 for body in ignored_obstacles:
  if is_instance_valid(body):
   remove_collision_exception_with(body)
 ignored_obstacles.clear()

func hurt(reason: String) -> bool:
 if invincible > 0 and position.y >= -8:
  return true
 if reason == "OBSTACLE COLLISION" and armor_charges > 0:
  armor_charges -= 1
  # Collision Grace (any protected hit) and Armor Support (armor-absorbed
  # hits only, requires the Impact Armor core already picked) both add a
  # little extra protection time on top of the base window. Both default to
  # 0 tier, so unmodified play sees exactly Rules.ARMOR_PROTECTION, unchanged.
  invincible = Rules.ARMOR_PROTECTION + tiers.collision_grace * 0.3 + tiers.armor_support * 0.4
  notice.emit("ARMOR HIT — keep moving / protected for 2 seconds")
  return true
 release_wire()
 clear_obstacle_exceptions()
 if armor_charges > 0 or practice or invincible > 0:
  if not practice and invincible <= 0:
   armor_charges -= 1
  position = Vector3(0, 6, position.z + 5)
  # Impact Armor tier 3 softens this emergency-rescue landing's flow loss:
  # instead of always resetting to a fixed forward speed, keep half of
  # whatever forward speed the player already had (still capped so it can't
  # exceed the original -12 case's clean recovery arc).
  var rescue_forward: float = -12.0
  if tiers.armor >= 3:
   rescue_forward = minf(-8.0, velocity.z * 0.5)
  velocity = Vector3(0, 0, rescue_forward)
  mode = "air"
  last_release_height = 0
  fresh_landing_hook = false
  jump_exempt = false
  invincible = 1 + tiers.collision_grace * 0.3
  notice.emit("PRACTICE RESCUE / " + reason if practice else "ARMOR SAVED YOU")
 else:
  die(reason)
 return false

func upgrade(key: String) -> void:
 if not tiers.has(key):
  return
 tiers[key] = mini(3, tiers[key] + 1)
 if key == "armor":
  armor_charges = mini(tiers.armor, armor_charges + 1)
 evaluate_synergies()

## Re-derives active_synergies from the current tiers. Not player-selectable
## (see PHASE A spec section 14/15) — just recomputed after every tier
## change so it can never end up stale or double-registered.
func evaluate_synergies() -> void:
 active_synergies.slingshot = tiers.reel >= 2 and tiers.range >= 2
 active_synergies.street_surfer = tiers.skates >= 3 and (tiers.release_momentum + tiers.skate_recharge + tiers.skate_efficiency) >= 2
 active_synergies.sky_runner = tiers.double_jump >= 3 and tiers.jump >= 2

## Purely cosmetic: where the drawn wire line starts. Physics (hook timing,
## anchor distance, rope length) all still use global_position untouched —
## this only decides what point the visible line is drawn from, so it can
## track the character's hand instead of its physics center.
func wire_visual_origin() -> Vector3:
 for child in visuals.get_children():
  if child.has_method("get_wire_grip_position"):
   return child.get_wire_grip_position()
 return global_position + Vector3(0, 0.3, 0)

func draw_wire() -> void:
 wire_surface.clear_surfaces()
 if not is_instance_valid(anchor):
  return
 var origin: Vector3 = wire_visual_origin()
 wire_surface.surface_begin(Mesh.PRIMITIVE_LINES)
 wire_surface.surface_set_color(Color("78f9e5"))
 var target: Vector3 = anchor.global_position
 if hook_left > 0:
  target = origin.lerp(target, 1 - hook_left / hook_duration)
 wire_surface.surface_add_vertex(origin)
 wire_surface.surface_add_vertex(target)
 wire_surface.surface_end()
