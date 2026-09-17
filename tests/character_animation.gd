extends SceneTree
const CharacterVisual = preload("res://scripts/character_visual.gd")
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 create_timer(30).timeout.connect(func(): quit(1))
 run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)
func find_character_visual(node: Node) -> Node:
 if node is CharacterVisual:
  return node
 for child in node.get_children():
  var found: Node = find_character_visual(child)
  if found != null:
   return found
 return null
func count_toon_meshes(node: Node) -> Dictionary:
 var result: Dictionary = {"found": 0, "visible": 0}
 if node is MeshInstance3D and node.mesh != null:
  for i in range(node.mesh.get_surface_count()):
   var mat: Material = node.mesh.surface_get_material(i)
   if mat != null and mat.resource_name.ends_with("Toon"):
    result.found += 1
    if node.visible:
     result.visible += 1
 for child in node.get_children():
  var sub: Dictionary = count_toon_meshes(child)
  result.found += sub.found
  result.visible += sub.visible
 return result
func find_skeleton(node: Node) -> Skeleton3D:
 if node is Skeleton3D:
  return node
 for child in node.get_children():
  var found: Skeleton3D = find_skeleton(child)
  if found != null:
   return found
 return null
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.start_run(false)
 await physics_frame

 var visual: Node = find_character_visual(game.rider.visuals)
 check(is_instance_valid(visual), "rider's visuals contain a CharacterVisual for the active character")
 check(visual.animation_tree != null and visual.animation_tree.active, "the character's AnimationTree is built and active")

 var capsule: CapsuleShape3D = game.rider.get_child(0).shape
 check(is_equal_approx(capsule.height, 1.7), "Rider's real CollisionShape3D capsule is resized to ~1.7m")
 check(capsule.radius >= 0.3 and capsule.radius <= 0.4, "the capsule radius stays in a normal human range (0.3-0.4m)")

 check(visual._left_hand_grip is BoneAttachment3D and visual._right_hand_grip is BoneAttachment3D, "both hand grip points are BoneAttachment3D nodes tracking the skeleton")
 var grip: Vector3 = visual.get_wire_grip_position()
 check(grip.distance_to(game.rider.global_position) < 2.0, "the wire grip point sits near the character, not at some unrelated location")
 check(game.rider.wire_visual_origin() == grip, "Rider's wire visual origin delegates to the character's grip point when a CharacterVisual is present")
 var skeleton: Skeleton3D = find_skeleton(visual._model)
 var chain := Transform3D.IDENTITY
 var walker: Node = skeleton
 while walker != visual:
  chain = walker.transform * chain
  walker = walker.get_parent()
 var foot_idx: int = skeleton.find_bone("mixamorig_LeftFoot_094")
 var toe_idx: int = skeleton.find_bone("mixamorig_LeftToeBase_095")
 var head_top_idx: int = skeleton.find_bone("mixamorig_HeadTop_End_08")
 var foot_y: float = (chain * skeleton.get_bone_global_rest(foot_idx)).origin.y
 var toe_y: float = (chain * skeleton.get_bone_global_rest(toe_idx)).origin.y
 var head_top_y: float = (chain * skeleton.get_bone_global_rest(head_top_idx)).origin.y
 check(absf(toe_y - (-0.85)) < 0.05, "the toe (this model's real ground-contact point) sits right at the capsule's new bottom, -0.85 (toe_y=%.3f)" % toe_y)
 check(foot_y > toe_y, "the ankle sits above the toe as expected (sanity check on the measurement itself)")
 check(absf((head_top_y - toe_y) - 1.7) < 0.02, "head-top to toe-tip spans ~1.7m, the target real-world height (measured=%.3f)" % (head_top_y - toe_y))

 var camera_offset_length: float = Rules.CAMERA_OFFSET.length()
 check(absf(camera_offset_length - 5.0) < 0.01, "the camera follow distance is ~5m (measured=%.3f)" % camera_offset_length)

 var toon_counts: Dictionary = count_toon_meshes(visual)
 check(toon_counts.found > 0, "the character model has the duplicate '...Toon' outline-shell meshes to check")
 check(toon_counts.visible == 0, "duplicate '...Toon' outline-shell meshes are hidden to avoid z-fighting/ghosting with the base mesh")

 var player: AnimationPlayer = null
 for child in visual.get_children():
  if child is AnimationPlayer:
   player = child
 check(player != null, "an AnimationPlayer with the retargeted library exists")
 var expected_states: Array[String] = ["idle", "running", "jump", "falling", "start_swinging", "swinging", "swing_hold", "slide", "slide_hold", "landing", "dead"]
 check(not player.has_animation("throw"), "throw.fbx is no longer used for the wire flow")
 for state in expected_states:
  check(player.has_animation(state), "retargeted clip exists for state '%s'" % state)
  var anim: Animation = player.get_animation(state)
  var has_position_track: bool = false
  for i in range(anim.get_track_count()):
   if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
    has_position_track = true
  check(not has_position_track, "state '%s' has no root-motion position track" % state)
  check(anim.get_track_count() > 0, "state '%s' has at least one retargeted rotation track" % state)

 # Drive rider.mode through each phase and confirm the state machine follows,
 # without ever touching rider physics fields itself. The engine may have
 # already ticked CharacterVisual._process once for free (rider starts in
 # "air" from reset()), so landing on the ground here goes through the same
 # air-to-ground edge a real jump/swing landing would.
 game.rider.mode = "ground"
 game.rider.velocity = Vector3.ZERO
 visual._process(0.016)
 check(visual.current_state == "landing", "touching down from the air plays the landing roll first")
 visual._process(1.0)
 check(visual.current_state == "idle", "standing still settles into idle once the landing roll finishes")

 game.rider.velocity = Vector3(0, 0, -8)
 visual._process(0.016)
 check(visual.current_state == "running", "moving on the ground selects running")

 game.rider.mode = "air"
 game.rider.velocity = Vector3(0, 6, 0)
 visual._process(0.016)
 check(visual.current_state == "jump", "rising in the air selects jump")

 game.rider.velocity = Vector3(0, -6, 0)
 visual._process(0.016)
 check(visual.current_state == "falling", "falling in the air selects falling")

 # Start Swinging -> Swinging -> swing_hold, each playing once in sequence,
 # right when the wire connects — never a looping swing, never a landing
 # beat while still attached.
 var anchor := Node3D.new()
 root.add_child(anchor)
 anchor.global_position = game.rider.global_position + Vector3(0, 5, 0)
 game.rider.anchor = anchor
 game.rider.hook_connected = true
 game.rider.mode = "swing"
 game.rider.velocity = Vector3(3, 0, 0)
 visual._process(0.016)
 check(visual.current_state == "start_swinging", "grabbing the wire plays start_swinging first")
 check(visual._swing_phase_timer > 0, "start_swinging timer is running right after the grab")

 visual._process(1.0)
 check(visual.current_state == "swinging", "start_swinging hands off to swinging once its own clip length elapses")

 visual._process(visual._swinging_duration)
 check(visual.current_state == "swing_hold", "swing_hold takes over once swinging's clip length has elapsed")

 visual._process(1.0)
 check(visual.current_state == "swing_hold", "swing_hold is held for as long as the wire stays connected, regardless of speed")

 # While on the wire, the model rotates to face the tangential swing
 # direction (never the Rider physics node) instead of staying fixed.
 game.rider.velocity = Vector3(5, 0, 2)
 for i in range(30):
  visual._process(0.05)
 var facing_right: Basis = visual._model.transform.basis
 game.rider.velocity = Vector3(-5, 0, 2)
 for i in range(30):
  visual._process(0.05)
 var facing_left: Basis = visual._model.transform.basis
 check(facing_right != facing_left, "swinging left vs. right produces a visibly different model orientation")
 check(game.rider.velocity == Vector3(-5, 0, 2), "the swing-facing rotation never modifies rider velocity")

 # A near-zero tangential speed (e.g. at the top of the arc) keeps the last
 # valid orientation instead of snapping to an undefined direction.
 var facing_before_stall: Basis = visual._model.transform.basis
 game.rider.velocity = Vector3.ZERO
 visual._process(0.05)
 check(visual._model.transform.basis.is_equal_approx(facing_before_stall), "near-zero swing speed holds the last facing instead of snapping")

 # Releasing the wire clears rider.anchor too (as the real release_wire()
 # does), which is what actually resets the sequence here.
 game.rider.anchor = null
 game.rider.mode = "air"
 game.rider.velocity = Vector3(0, -6, 0)
 visual._process(0.016)
 check(visual.current_state == "falling", "releasing the wire drops straight to falling, not a swing-loop landing beat")
 check(visual._model.transform.basis.is_equal_approx(visual._model_base_basis), "releasing the wire resets the model to its normal (non-swing) orientation")
 anchor.free()

 # Firing a new wire creates a brand-new anchor instance (as fire_manual()
 # does with Node3D.new()); the sequence keys off that identity change, so
 # it restarts from start_swinging even though mode may not reach "swing"
 # (hook still traveling) until later — verified here by NOT setting mode.
 var anchor2 := Node3D.new()
 root.add_child(anchor2)
 anchor2.global_position = game.rider.global_position + Vector3(0, 5, 0)
 game.rider.anchor = anchor2
 game.rider.hook_connected = false
 visual._process(0.016)
 check(visual.current_state == "start_swinging", "firing a new wire plays start_swinging immediately, before the hook even connects")

 game.rider.mode = "swing"
 visual._process(visual._start_swinging_duration + visual._swinging_duration + 0.1)
 game.rider.anchor = null
 game.rider.mode = "air"
 game.rider.velocity = Vector3(0, -6, 0)
 visual._process(0.016)
 check(visual.current_state == "falling", "releasing the wire drops straight to falling")
 anchor2.free()

 # Running Slide plays once, then holds its last frame (slide_hold) for as
 # long as the real slide lasts — never looping, never handing control back
 # to running/idle just because the clip finished.
 var y_before_slide: float = visual._model.position.y
 game.rider.mode = "slide"
 game.rider.velocity = Vector3(0, 0, -10)
 visual._process(0.016)
 check(visual.current_state == "slide", "starting to skate plays Running Slide from the start")

 visual._process(1.0)
 check(visual.current_state == "slide_hold", "slide_hold takes over once Running Slide's clip length has elapsed")

 # The extra downward ground-alignment offset blends in over ~0.13s rather
 # than snapping, and settles near the full computed value.
 check(absf(visual._slide_visual_offset - CharacterVisual.SLIDE_EXTRA_Y_OFFSET) < 0.01, "the slide ground offset has blended in to its full value by the time slide_hold is reached")
 check(visual._model.position.y < y_before_slide, "the model visibly sits lower during the slide than while standing")

 visual._process(1.0)
 check(visual.current_state == "slide_hold", "slide_hold is held for as long as the real slide continues, regardless of clip length")
 check(visual._model.position.y < y_before_slide, "the lowered slide position is sustained the whole time, not just for one frame")

 # The old whole-body pitch/roll hack (tuned for the primitive-box visual)
 # must not still be pivoting the character during slide. Drive the actual
 # banking function directly (not full rider.simulate(), which would also
 # run real physics/land the slide) — it used to target -0.55 rad pitch in
 # slide mode; it should now settle at 0.
 game.rider.visuals.rotation = Vector3(0.4, 0, -0.3)
 for i in range(60):
  game.rider.update_visual_banking(0.05)
 check(is_zero_approx(game.rider.visuals.rotation.x) and is_zero_approx(game.rider.visuals.rotation.z), "rider.visuals settles to no extra pitch/roll during slide (that used to tilt the character off the ground)")

 # Slide facing is yaw-only, toward horizontal velocity, with none of the
 # swing's rope-relative tilt logic applied.
 game.rider.velocity = Vector3(6, 0, -6)
 for i in range(30):
  visual._process(0.05)
 var slide_facing_right: Basis = visual._model.transform.basis
 game.rider.velocity = Vector3(-6, 0, -6)
 for i in range(30):
  visual._process(0.05)
 var slide_facing_left: Basis = visual._model.transform.basis
 check(slide_facing_right != slide_facing_left, "sliding left vs. right yaws the model to face the actual travel direction")

 # Ending the slide (skate physics decides this, not the animation) restores
 # both the state and the ground offset.
 game.rider.mode = "ground"
 game.rider.velocity = Vector3.ZERO
 visual._process(0.016)
 check(visual.current_state != "slide" and visual.current_state != "slide_hold", "ending the slide leaves slide/slide_hold for a normal ground state")
 visual._process(1.0)
 check(is_equal_approx(visual._model.position.y, y_before_slide), "the visual Y offset returns to the normal standing height after the slide ends")

 game.rider.mode = "dead"
 visual._process(0.016)
 check(visual.current_state == "dead", "dying selects dead regardless of prior state")

 var pos_before: Vector3 = game.rider.position
 var vel_before: Vector3 = game.rider.velocity
 visual._process(0.016)
 visual._process(0.016)
 check(game.rider.position == pos_before and game.rider.velocity == vel_before, "driving the animation state machine never writes back to rider position/velocity")
 check(not visual.has_method("integrate") and not visual.has_method("simulate"), "CharacterVisual has no physics methods of its own; it only reads Rider")

 print("CHARACTER_ANIMATION_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
