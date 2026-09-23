extends SceneTree
## Optional, slow City continuity audit. Requires --test (no user saves).
## Headless: --headless --fixed-fps 60 --script tools/City-Run-QA.gd -- --test
## GPU: --fixed-fps 60 --disable-render-loop --script tools/City-Run-QA.gd -- --test
## The GPU mode draws every 30 simulated ticks, retaining actual physics
## between draws. This is an accelerated ground-route input bot, not a
## substitute for a human wire-traversal playthrough or an FPS benchmark.
var game: Node3D
var frame: int = 0
var max_nodes: int = 0
var max_vehicles: int = 0
var max_chunks: int = 0
var samples: Array = []
var outputs: Array = []
var visual: Node3D
var air_ground_errors: int = 0
func _initialize() -> void:
 if not "--test" in OS.get_cmdline_user_args():
  push_error("City QA requires --test to protect player saves")
  quit(1)
  return
 run.call_deferred()
func key(code: int, down: bool) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = down
 Input.parse_input_event(event)
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 for build in ["standard", "control", "no-upgrades"]:
  game.start_run(false)
  visual = game.rider.visuals.get_child(0)
  frame = 0
  samples = []
  air_ground_errors = 0
  max_nodes = 0
  max_chunks = 0
  max_vehicles = 0
  key(KEY_W, true)
  while game.phase == "playing" and frame < 100000:
   await physics_frame
   var r: CharacterBody3D = game.rider
   # This is an input bot, never a teleport/rescue/invincibility probe.
   # Pick actual earned offers, leaving poor-luck run completely unspent.
   if build != "no-upgrades" and not game.pending_upgrades.is_empty():
    game.open_upgrades()
    var preference: Array = ["skates","skate_efficiency","range","reel","armor"] if build == "standard" else ["air_control","ground_control","jump","double_jump","armor"]
    var pick: int = 0
    for wanted in preference:
     if game.choices.has(wanted):
      pick = game.choices.find(wanted)
      break
    game.choose(pick)
    # Same wait as a real resume, with all physical inputs released.
    key(KEY_W, false)
    while game.phase == "countdown":
     await physics_frame
     game._physics_process(1.0/60)
    key(KEY_W, true)
   var desired_x: float = 0
   for robot in game.boss.barrage_robots:
    if not is_instance_valid(robot):
     continue
    var relative: Vector3 = robot.position - r.position
    var relative_velocity: Vector3 = robot.get_meta("velocity") - r.velocity
    if relative_velocity.z <= 0:
     continue
    var crossing_time: float = -relative.z / relative_velocity.z
    var crossing: Vector3 = relative + relative_velocity * crossing_time
    # React to a projected body intersection, rather than steering into
    # traffic merely because a robot is in front but still well overhead.
    if crossing_time > 0 and crossing_time < 0.55 and absf(crossing.x) < 1.7 and absf(crossing.y) < 1.95 and r.mode == "ground":
     key(KEY_SPACE, true)
     key(KEY_SPACE, false)
   key(KEY_A, desired_x - r.position.x < -0.15)
   key(KEY_D, desired_x - r.position.x > 0.15)
   key(KEY_W, true)
   game._physics_process(1.0/60)
   visual._process(1.0/60)
   if DisplayServer.get_name() != "headless":
    game._process(1.0/60)
    if frame % 30 == 0:
     RenderingServer.force_draw()
   if frame > 2 and r.mode == "air" and visual.current_state in ["idle","walking","left_strafe_walk","right_strafe_walk"]:
    air_ground_errors += 1
   if frame % 600 == 0:
    max_nodes = maxi(max_nodes,get_node_count())
    max_chunks = maxi(max_chunks,game.city.chunks.size())
    max_vehicles = maxi(max_vehicles,game.city.vehicles.size())
    samples.append({"m":snappedf(game.distance,.1),"phase":game.phase,"boss":game.boss.pattern,"nodes":get_node_count()})
    print("RUN_PROGRESS ",build," ",snappedf(game.distance,.1))
   frame += 1
  key(KEY_W,false)
  key(KEY_A,false)
  key(KEY_D,false)
  var output: Dictionary = {"build":build,"distance":game.distance,"phase":game.phase,"reason":game.death_reason,"frames":frame,"level":game.level,"tiers":game.rider.tiers.duplicate(),"origin":game.city.origin_offset,"signals":game.played_signals.duplicate(),"peak_nodes":max_nodes,"peak_chunks":max_chunks,"peak_vehicles":max_vehicles,"air_ground_errors":air_ground_errors,"samples":samples}
  if DisplayServer.get_name() != "headless":
   game._process(1.0/60)
   await process_frame
   RenderingServer.force_draw()
   root.get_texture().get_image().save_png("res://validation/city-run-%s.png" % build)
  outputs.append(output)
  print("FULL_RUN_RESULT ",JSON.stringify(output))
  FileAccess.open("res://validation/city-full-runs.json",FileAccess.WRITE).store_string(JSON.stringify(outputs," "))
 game.free()
 await process_frame
 quit(0 if outputs.size() == 3 and outputs.all(func(result: Dictionary): return result.phase == "complete" and result.air_ground_errors == 0) else 1)
