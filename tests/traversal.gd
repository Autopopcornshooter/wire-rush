extends SceneTree
const CharacterVisual = preload("res://scripts/character_visual.gd")
var game: Node3D
var visual: CharacterVisual
var crashes: int = 0
var hooks: int = 0
var samples: Array = []
## Real-gameplay regression for the "ground-locomotion pose while genuinely
## airborne" class of bug: driven by the same full autoplay loop below
## (hooking, jumping, releasing through real city geometry for 1800 frames/
## ~30s), not a synthetic isolated scenario, since that's what actually
## exposed the original report (a wire-boosted rise keeping velocity.y
## positive far longer than a plain ground jump does).
var ground_pose_while_air: int = 0
var last_anim_state: String = ""

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.start_run(true)
 game.set_physics_process(false)
 game.set_process(false)
 game.rider.notice.connect(func(text: String):
  if text.begins_with("PRACTICE RESCUE"):
   crashes += 1
   print("RESCUE ", text, " at ", game.rider.position)
 )
 for c in game.rider.visuals.get_children():
  if c is CharacterVisual:
   visual = c
 last_anim_state = visual.current_state
 for frame in range(1800):
  await physics_frame
  var r: CharacterBody3D = game.rider
  if r.anchor == null and r.position.y > 2.2:
   var side: int = -1 if hooks % 2 == 0 else 1
   var point := Vector3(side * 7.4, 18, r.position.z - 10)
   var selection: Dictionary = game.city.manual_target(r.position, r.position, (point - r.position).normalized(), r.reach(), r.get_rid())
   if r.fire_manual(selection, side):
    hooks += 1
  if r.mode == "ground":
   r.jump()
  if r.mode == "swing" and r.position.z < r.anchor.global_position.z - 1:
   r.release_wire()
  r.simulate(1.0 / 60.0, 0)
  game.distance = maxf(game.distance, -r.position.z)
  game.city.update_chunks(game.distance, r.anchor)
  visual._process(1.0 / 60.0)
  if visual.current_state != last_anim_state:
   if r.mode == "air" and visual.current_state in ["walking", "left_strafe_walk", "right_strafe_walk", "idle"]:
    ground_pose_while_air += 1
    print("[ANIM DEBUG] prev=", last_anim_state, " next=", visual.current_state, " mode=", r.mode, " velocity=", r.velocity, " position_y=", r.position.y, " hook_connected=", r.hook_connected, " anchor_valid=", is_instance_valid(r.anchor))
   last_anim_state = visual.current_state
  if frame % 120 == 0:
   samples.append({"t": frame / 60.0, "z": snappedf(r.position.z, 0.1), "y": snappedf(r.position.y, 0.1), "speed": snappedf(r.velocity.length(), 0.1), "mode": r.mode})
 print("TRAVERSAL ", JSON.stringify({"distance": game.distance, "rescues": crashes, "hooks": hooks, "ground_pose_while_air": ground_pose_while_air, "samples": samples}))
 var passed: bool = crashes == 0 and game.rider.mode != "dead" and hooks >= 10 and game.distance > 250 and ground_pose_while_air == 0
 game.free()
 await process_frame
 quit(0 if passed else 1)
