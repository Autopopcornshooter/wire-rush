extends Node3D
## Instances one of the humanoid GLB models and drives it with a single
## shared AnimationTree state machine + Mixamo-retargeted animation set
## (see mixamo_retarget.gd). This node is a pure visual layer: it reads
## Rider's existing public state (mode/velocity/anchor) every frame to pick
## an animation state, but never writes back to Rider and never touches
## wire/jump/slide physics. Root motion is discarded entirely by the
## retargeter (position/scale tracks are never copied), so the retargeted
## clips only ever rotate bones — Rider's CharacterBody3D motion is the only
## thing that actually moves the character through the world.
const Retarget = preload("res://scripts/mixamo_retarget.gd")

## Per-character profile: scene + bone_map (Humanoid role -> that model's
## own Skeleton3D bone name), plus rotation_deg/scale/y_offset to correct
## for a model's own forward axis, size and ground pivot — entirely on the
## visual model, never on Rider's collider/physics. Each character can carry
## its own scale and y_offset since models differ in native size and origin.
const CHARACTERS: Dictionary = {
	"lowpoly_anime_character_cyberstyle": {
		"scene": "res://models/lowpoly_anime_character_cyberstyle.glb",
		# This GLB's raw Skeleton3D bone-rest data is Z-up, BUT the glTF's
		# own node chain above the skeleton (Armature/.../Sketchfab_model/
		# Sketchfab_Scene) already carries a correction baked in from
		# however the original file was authored/exported — with zero extra
		# rotation the model already renders upright, ~1.62m foot-to-head.
		# An earlier attempt added its own -90/180 rotation on top of that
		# already-self-correcting chain, which is what actually flipped the
		# character upside down. Only a 180 turn on Y is genuinely needed,
		# to face -Z (this game's forward) instead of +Z — confirmed by the
		# toe bone sitting further +Z than the ankle at rest.
		"rotation_deg": Vector3(0, 180, 0),
		# Real-world scale: measured this model's own head-top-to-toe-tip span
		# at scale 1.0 via bone rest positions (mixamorig_HeadTop_End_08 y=
		# 1.619955, mixamorig_LeftToeBase_095 y=-0.000954, both through the
		# model's own rotation), giving a natural height of 1.620909m. Target
		# is 1.7m (matching Rider's own resized capsule below), so
		# scale = 1.7 / 1.620909 = 1.048794.
		# y_offset grounds the toe tip (this model's actual ground-contact
		# point, not the ankle) against the capsule's new bottom at
		# -half_height (-0.85): y_offset = -0.85 - toe_local_y*scale
		# = -0.85 - (-0.000954 * 1.048794) = -0.848999.
		"scale": 1.048794,
		"y_offset": -0.848999,
		"bone_map": {
			"Hips": "mixamorig_Hips_02",
			"Spine": "mixamorig_Spine_03",
			"Chest": "mixamorig_Spine1_04",
			"UpperChest": "mixamorig_Spine2_05",
			"Neck": "mixamorig_Neck_06",
			"Head": "mixamorig_Head_07",
			"LeftShoulder": "mixamorig_LeftShoulder_045",
			"LeftUpperArm": "mixamorig_LeftArm_046",
			"LeftLowerArm": "mixamorig_LeftForeArm_047",
			"LeftHand": "mixamorig_LeftHand_048",
			"RightShoulder": "mixamorig_RightShoulder_069",
			"RightUpperArm": "mixamorig_RightArm_070",
			"RightLowerArm": "mixamorig_RightForeArm_071",
			"RightHand": "mixamorig_RightHand_072",
			"LeftUpperLeg": "mixamorig_LeftUpLeg_092",
			"LeftLowerLeg": "mixamorig_LeftLeg_093",
			"LeftFoot": "mixamorig_LeftFoot_094",
			"RightUpperLeg": "mixamorig_RightUpLeg_097",
			"RightLowerLeg": "mixamorig_RightLeg_098",
			"RightFoot": "mixamorig_RightFoot_099",
		},
	},
}

## Priority order (highest first) used when more than one condition applies
## at once, e.g. dead always wins even mid-swing.
const STATES: Array[String] = ["dead", "slide_hold", "slide", "swing_hold", "swinging", "start_swinging", "jump", "falling", "landing", "running", "idle"]
const LANDING_DURATION: float = 0.5
## Below this tangential (rope-perpendicular) speed, the swing-facing
## rotation just holds its last valid orientation instead of chasing a
## nearly-zero-length vector — otherwise the facing direction would jitter
## or snap 180 degrees at the top of a swing arc where it briefly stalls.
const SWING_TANGENT_MIN_SPEED: float = 0.3
## Same idea as SWING_TANGENT_MIN_SPEED but for the slide's yaw-facing: below
## this horizontal speed, keep the last facing instead of chasing a
## near-zero-length direction (e.g. right as a slide is starting/ending).
const SLIDE_FACING_MIN_SPEED: float = 0.3
## How fast the visual orientation chases the target swing orientation
## (higher = snappier). Framerate-independent via 1 - exp(-k*delta).
const SWING_ROTATION_RATE: float = 10.0
## Extra downward visual shift applied on top of the normal standing
## y_offset while sliding. Measured directly (not eyeballed): with only the
## standing offset applied, the slide pose's lowest bone (the toe) sat at
## y=-0.4575 relative to Rider, well above the -0.85 ground reference the
## capsule bottom (and every other pose) actually touches — a ~0.39m gap,
## exactly the "floating during slide" symptom. This constant closes it:
## -0.85 - (-0.4575) = -0.392471.
const SLIDE_EXTRA_Y_OFFSET: float = -0.392471
## Blend rate for that extra offset fading in/out (1 - exp(-k*delta)); ~0.13s
## to settle, inside the requested 0.08-0.15s range.
const SLIDE_OFFSET_BLEND_RATE: float = 15.0

var rider: CharacterBody3D
var animation_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var current_state: String = "idle"
var _landing_timer: float = 0.0
var _was_airborne: bool = false
## Sequences the one-shot wire-grab clips: "" (not on a wire) ->
## "start_swinging" -> "swinging" -> "hold" (frozen pose, stays until release).
var _swing_phase: String = ""
var _swing_phase_timer: float = 0.0
var _start_swinging_duration: float = 0.0
var _swinging_duration: float = 0.0
var _model: Node3D
var _model_base_basis: Basis
var _swing_facing_basis: Basis = Basis.IDENTITY
var _slide_facing_basis: Basis = Basis.IDENTITY
var _left_hand_grip: BoneAttachment3D
var _right_hand_grip: BoneAttachment3D
var _last_anchor: Node3D = null
## Sequences the slide clip: "" (not sliding) -> "slide" (playing once) ->
## "hold" (frozen last frame, stays until the real slide ends).
var _slide_phase: String = ""
var _slide_phase_timer: float = 0.0
var _slide_duration: float = 0.0
var _base_y_offset: float = 0.0
var _slide_visual_offset: float = 0.0

func setup(character_id: String) -> void:
	var config: Dictionary = CHARACTERS[character_id]
	var model: Node3D = load(config.scene).instantiate()
	add_child(model)
	model.rotation_degrees = config.rotation_deg
	model.scale = Vector3.ONE * config.scale
	model.position.y = config.y_offset
	_base_y_offset = config.y_offset
	_model = model
	_model_base_basis = model.transform.basis
	hide_duplicate_toon_shells(model)
	var skeleton: Skeleton3D = find_skeleton(model)
	# WireGrip reference points: the drawn wire line's visual start is the
	# midpoint of these two, tracked automatically every frame by Godot's own
	# BoneAttachment3D (no manual per-frame bone-pose math needed here, and
	# it keeps working through the swing-facing rotation and the 1.2x scale
	# without any extra code). A small local offset per hand could be added
	# per character if a model's grip still looks slightly off, but none of
	# the checked characters have needed one.
	_left_hand_grip = BoneAttachment3D.new()
	_left_hand_grip.bone_name = config.bone_map.LeftHand
	skeleton.add_child(_left_hand_grip)
	_right_hand_grip = BoneAttachment3D.new()
	_right_hand_grip.bone_name = config.bone_map.RightHand
	skeleton.add_child(_right_hand_grip)
	var skeleton_path: String = str(get_path_to(skeleton))
	var library: AnimationLibrary = Retarget.build_library(config.bone_map, skeleton, skeleton_path)
	var player := AnimationPlayer.new()
	add_child(player)
	player.add_animation_library("", library)
	animation_tree = AnimationTree.new()
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(player)
	animation_tree.tree_root = build_state_machine()
	animation_tree.active = true
	playback = animation_tree.get("parameters/playback")
	playback.start("idle")
	_start_swinging_duration = player.get_animation("start_swinging").length
	_swinging_duration = player.get_animation("swinging").length
	_slide_duration = player.get_animation("slide").length

func hide_duplicate_toon_shells(node: Node) -> void:
	# Some character models (this one included) ship every body part twice:
	# once with its normal material, and again under a "...Toon" material
	# meant as a back-face-only outline shell. The Toon copy's cull mode
	# came in as CULL_DISABLED instead of CULL_FRONT, so its front faces sit
	# fully coincident with the normal mesh's front faces — two opaque
	# surfaces competing for the same depth-buffer pixels every frame. A
	# static screenshot just shows a normal edge, but which one wins the
	# depth test can flip frame to frame once the camera/character are
	# moving, which reads as flicker/ghosting trailing the silhouette.
	# Hiding the outline-shell copy removes the duplicate geometry outright.
	if node is MeshInstance3D and node.mesh != null:
		for i in range(node.mesh.get_surface_count()):
			var mat: Material = node.mesh.surface_get_material(i)
			if mat != null and mat.resource_name.ends_with("Toon"):
				node.visible = false
	for child in node.get_children():
		hide_duplicate_toon_shells(child)

func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null:
			return found
	return null

func build_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	for state in STATES:
		var anim_node := AnimationNodeAnimation.new()
		anim_node.animation = state
		machine.add_node(state, anim_node)
	# Fully-connected transition graph: travel() can go from any state to any
	# other in one hop, so the priority order above (decided in GDScript, not
	# by the graph shape) is always reachable immediately rather than queued
	# behind a multi-hop path.
	for from in STATES:
		for to in STATES:
			if from == to:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			# Wire-specific pairs get their own blend times (spec'd
			# separately) so grabbing the wire settles in deliberately but
			# letting go reads instantly; every other pair keeps the
			# snappier default.
			if from == "start_swinging" and to == "swinging":
				transition.xfade_time = 0.1
			elif from == "swinging" and to == "swing_hold":
				transition.xfade_time = 0.1
			elif from == "swing_hold" and to == "falling":
				transition.xfade_time = 0.08
			elif from == "slide" and to == "slide_hold":
				transition.xfade_time = 0.1
			else:
				transition.xfade_time = 0.15
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			machine.add_transition(from, to, transition)
	return machine

func bind_rider(target: CharacterBody3D) -> void:
	rider = target

## Called by Rider (duck-typed, no hard dependency) to know where to draw
## the wire's visual start point. Falls back to this node's own position if
## the hand attachments aren't ready for any reason.
func get_wire_grip_position() -> Vector3:
	if _left_hand_grip != null and _right_hand_grip != null:
		return (_left_hand_grip.global_position + _right_hand_grip.global_position) * 0.5
	return global_position

func _process(delta: float) -> void:
	if rider == null or playback == null:
		return
	if _landing_timer > 0:
		_landing_timer = maxf(0, _landing_timer - delta)
	var airborne: bool = rider.mode in ["air", "swing"]
	if _was_airborne and not airborne and rider.mode == "ground":
		_landing_timer = LANDING_DURATION
	_was_airborne = airborne
	# The wire-grab sequence is keyed off the anchor object itself, not
	# rider.mode: a fresh anchor exists the instant the wire is fired (from
	# fire_manual's own Node3D.new()), well before hook_left counts down and
	# mode flips to "swing". Gating on mode instead would delay Start
	# Swinging until the hook actually connects — sometimes fine for a
	# short throw, but a visibly late/skipped-looking start for a long one.
	# release_wire() always runs at the top of fire_manual(), so firing a
	# new wire while already attached reliably produces a new anchor
	# instance here too, restarting the sequence rather than resuming hold.
	var anchor_valid: bool = is_instance_valid(rider.anchor)
	if anchor_valid and rider.anchor != _last_anchor:
		_swing_phase = "start_swinging"
		_swing_phase_timer = _start_swinging_duration
	elif not anchor_valid:
		_swing_phase = ""
	elif _swing_phase_timer > 0:
		_swing_phase_timer = maxf(0, _swing_phase_timer - delta)
		if _swing_phase_timer <= 0:
			if _swing_phase == "start_swinging":
				_swing_phase = "swinging"
				_swing_phase_timer = _swinging_duration
			elif _swing_phase == "swinging":
				_swing_phase = "hold"
	_last_anchor = rider.anchor if anchor_valid else null
	var sliding: bool = rider.mode == "slide"
	update_visual_orientation(delta, sliding)
	if sliding and _slide_phase == "":
		_slide_phase = "slide"
		_slide_phase_timer = _slide_duration
	elif not sliding:
		_slide_phase = ""
	elif _slide_phase_timer > 0:
		_slide_phase_timer = maxf(0, _slide_phase_timer - delta)
		if _slide_phase_timer <= 0:
			_slide_phase = "hold"
	var slide_offset_target: float = SLIDE_EXTRA_Y_OFFSET if sliding else 0.0
	_slide_visual_offset = lerpf(_slide_visual_offset, slide_offset_target, 1.0 - exp(-SLIDE_OFFSET_BLEND_RATE * delta))
	_model.position.y = _base_y_offset + _slide_visual_offset
	var target_state: String = pick_state()
	if target_state != current_state:
		current_state = target_state
		playback.travel(target_state)

func pick_state() -> String:
	if rider.mode == "dead":
		return "dead"
	if rider.mode == "slide":
		return "slide_hold" if _slide_phase == "hold" else "slide"
	if _swing_phase != "":
		return "swing_hold" if _swing_phase == "hold" else _swing_phase
	if rider.mode == "air":
		return "jump" if rider.velocity.y > 0.5 else "falling"
	if _landing_timer > 0:
		return "landing"
	var horizontal_speed: float = Vector2(rider.velocity.x, rider.velocity.z).length()
	return "running" if horizontal_speed > 0.5 else "idle"

## Picks which visual-rotation mode applies to the model (never Rider
## itself, never CollisionShape) this frame. Swing and slide are mutually
## exclusive by construction (rider.mode is one string), so there's no
## risk of them fighting over the same basis.
func update_visual_orientation(delta: float, sliding: bool) -> void:
	if _model == null:
		return
	if rider.mode == "swing" and is_instance_valid(rider.anchor):
		apply_swing_facing(delta)
	elif sliding:
		apply_slide_facing(delta)
	elif _model.transform.basis != _model_base_basis:
		_model.transform.basis = _model_base_basis

## While on the wire, rotates the visual model to face the swing's
## tangential travel direction, with the character's "up" biased toward the
## anchor — physics stays exactly as CharacterBody3D computed it, this only
## decides which way the model is drawn facing.
func apply_swing_facing(delta: float) -> void:
	var rope: Vector3 = rider.anchor.global_position - rider.global_position
	if rope.length() > 0.01:
		var rope_dir: Vector3 = rope.normalized()
		var tangent: Vector3 = rider.velocity - rope_dir * rider.velocity.dot(rope_dir)
		if tangent.length() >= SWING_TANGENT_MIN_SPEED:
			_swing_facing_basis = Basis.looking_at(tangent.normalized(), rope_dir)
	var current: Quaternion = _model.transform.basis.get_rotation_quaternion()
	var target: Quaternion = (_swing_facing_basis * _model_base_basis).get_rotation_quaternion()
	var weight: float = 1.0 - exp(-SWING_ROTATION_RATE * delta)
	_model.transform.basis = Basis(current.slerp(target, weight)).scaled(_model.scale)

## While sliding, yaw the model to face the horizontal travel direction only
## — no pitch, no roll, and none of the swing's rope-relative tilting, since
## a ground slide has no rope to lean against. Basis.looking_at with a fixed
## world-up vector is yaw-only by construction (up never tilts), which is
## what keeps this from ever leaning sideways or flipping upside down.
func apply_slide_facing(delta: float) -> void:
	var horizontal: Vector3 = Vector3(rider.velocity.x, 0.0, rider.velocity.z)
	if horizontal.length() >= SLIDE_FACING_MIN_SPEED:
		_slide_facing_basis = Basis.looking_at(horizontal.normalized(), Vector3.UP)
	var current: Quaternion = _model.transform.basis.get_rotation_quaternion()
	var target: Quaternion = (_slide_facing_basis * _model_base_basis).get_rotation_quaternion()
	var weight: float = 1.0 - exp(-SWING_ROTATION_RATE * delta)
	_model.transform.basis = Basis(current.slerp(target, weight)).scaled(_model.scale)
