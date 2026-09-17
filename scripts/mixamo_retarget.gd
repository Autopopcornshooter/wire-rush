extends RefCounted
## Loads Mixamo FBX animations and rewrites their bone tracks onto a target
## character's own Skeleton3D bone names, using a per-character bone-name
## dictionary (the "Humanoid" mapping) instead of Godot's editor-only
## import-time retarget dialog, so the whole pipeline stays scriptable.
##
## Each rotation key is stored as the bone's full LOCAL pose rotation, which
## only means the same thing on the target skeleton if the target bone's own
## rest orientation matches the source bone's rest orientation exactly. Real
## character rigs rarely do (this project's own models don't — one is
## authored Z-up, another is a full Rigify control rig), so keys are
## converted to a rest-relative delta on the source skeleton and re-applied
## on top of the target's own rest, instead of being copied verbatim:
##   delta = source_rest.inverse() * source_pose
##   target_pose = target_rest * delta
## This is the standard "local rest-pose delta" retarget and keeps working
## regardless of whatever whole-body correction a model's rest pose needs.

## Humanoid role -> Mixamo skeleton's own bone name. Every Mixamo FBX in
## animations/ shares this exact rig, so one table covers all 9 clips.
const MIXAMO_BONES: Dictionary = {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
}

## Game animation state -> source Mixamo file + whether it should loop.
## throw.fbx is not used at all. Start Swinging and Swinging are both
## trimmed source files (fire/grab motion only, and grab-to-kick motion
## only, respectively — no landing/finish beat baked into either), each
## played once; "swing_hold" (built below) freezes Swinging's own last
## frame instead of ever looping a full swing or playing a landing beat
## while still on the wire.
const CLIPS: Dictionary = {
	"idle": {"file": "res://animations/Idle.fbx", "loop": true},
	"running": {"file": "res://animations/Running.fbx", "loop": true},
	"jump": {"file": "res://animations/Running Jump.fbx", "loop": false},
	"falling": {"file": "res://animations/Falling Idle.fbx", "loop": true},
	"start_swinging": {"file": "res://animations/Start Swinging.fbx", "loop": false},
	"swinging": {"file": "res://animations/Swinging.fbx", "loop": false},
	"slide": {"file": "res://animations/Running Slide.fbx", "loop": false},
	"landing": {"file": "res://animations/Falling To Roll.fbx", "loop": false},
	"dead": {"file": "res://animations/Defeated.fbx", "loop": false},
}

## Any one Mixamo FBX carries the full source rig + rest pose; every clip
## shares that same skeleton, so it only needs to be loaded once.
const SOURCE_SKELETON_FILE: String = "res://animations/Idle.fbx"

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Skeleton3D = find_skeleton(child)
		if found != null:
			return found
	return null

static func load_source_animation(fbx_path: String) -> Animation:
	var scene: Node = load(fbx_path).instantiate()
	var anim: Animation = null
	for child in scene.get_children():
		if child is AnimationPlayer:
			for lib_name in child.get_animation_library_list():
				var lib: AnimationLibrary = child.get_animation_library(lib_name)
				for anim_name in lib.get_animation_list():
					anim = lib.get_animation(anim_name)
	scene.free()
	return anim

## bone_map: Humanoid role name -> the TARGET skeleton's actual bone name
## (only roles present in both MIXAMO_BONES and bone_map are copied).
static func retarget(source_anim: Animation, source_skeleton: Skeleton3D, bone_map: Dictionary, target_skeleton: Skeleton3D, skeleton_node_name: String, loop: bool) -> Animation:
	var result := Animation.new()
	result.length = source_anim.length
	result.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for role in bone_map:
		if not MIXAMO_BONES.has(role):
			continue
		var source_bone: String = MIXAMO_BONES[role]
		var source_track: int = source_anim.find_track(NodePath("Skeleton3D:" + source_bone), Animation.TYPE_ROTATION_3D)
		if source_track < 0:
			continue
		var source_bone_idx: int = source_skeleton.find_bone(source_bone)
		var target_bone: String = bone_map[role]
		var target_bone_idx: int = target_skeleton.find_bone(target_bone)
		if source_bone_idx < 0 or target_bone_idx < 0:
			continue
		var source_rest: Quaternion = source_skeleton.get_bone_rest(source_bone_idx).basis.get_rotation_quaternion()
		var target_rest: Quaternion = target_skeleton.get_bone_rest(target_bone_idx).basis.get_rotation_quaternion()
		var new_track: int = result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(new_track, NodePath(skeleton_node_name + ":" + target_bone))
		for key_index in range(source_anim.track_get_key_count(source_track)):
			var time: float = source_anim.track_get_key_time(source_track, key_index)
			var source_pose: Quaternion = source_anim.rotation_track_interpolate(source_track, time)
			var delta: Quaternion = source_rest.inverse() * source_pose
			var target_pose: Quaternion = target_rest * delta
			result.rotation_track_insert_key(new_track, time, target_pose)
	return result

## Freezes one instant of an already-retargeted animation into a single-key,
## non-looping pose — used for "swing_hold" (a held pose derived from
## Swinging's own last frame instead of a separate animation file).
static func freeze_pose(source: Animation, time: float) -> Animation:
	var result := Animation.new()
	result.loop_mode = Animation.LOOP_NONE
	result.length = 0.001
	for i in range(source.get_track_count()):
		var new_track: int = result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(new_track, source.track_get_path(i))
		result.rotation_track_insert_key(new_track, 0.0, source.rotation_track_interpolate(i, time))
	return result

## Builds one AnimationLibrary with all CLIPS retargeted onto bone_map,
## ready to hand to an AnimationPlayer.
static func build_library(bone_map: Dictionary, target_skeleton: Skeleton3D, skeleton_node_name: String) -> AnimationLibrary:
	var source_scene: Node = load(SOURCE_SKELETON_FILE).instantiate()
	var source_skeleton: Skeleton3D = find_skeleton(source_scene)
	var library := AnimationLibrary.new()
	for state in CLIPS:
		var clip: Dictionary = CLIPS[state]
		var source: Animation = load_source_animation(clip.file)
		library.add_animation(state, retarget(source, source_skeleton, bone_map, target_skeleton, skeleton_node_name, clip.loop))
	source_scene.free()
	var swinging: Animation = library.get_animation("swinging")
	library.add_animation("swing_hold", freeze_pose(swinging, swinging.length))
	var slide: Animation = library.get_animation("slide")
	library.add_animation("slide_hold", freeze_pose(slide, slide.length))
	return library
