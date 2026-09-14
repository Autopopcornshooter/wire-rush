extends SceneTree
var game: Node3D
var results: Array[Dictionary] = []
var quick: bool = false
func _initialize() -> void:
 quick = "--quick" in OS.get_cmdline_user_args()
 run.call_deferred()

func candidate(side: int) -> Dictionary:
 var r: Node3D = game.rider
 var point := Vector3(side * 7.4, 18 + game.Rules.BUILDING_BONUS[r.tiers.high] * 0.5, r.position.z - 10)
 var target: Dictionary = game.city.manual_target(r.position, r.position, (point - r.position).normalized(), r.reach(), r.get_rid())
 if target.get("valid", false) and (not target.surface.get_meta("building", false) or signf(target.surface.global_position.x) != side):
  return {"valid": false}
 return target

func preferred_side(route: String, hooks: int) -> int:
 if route == "sparse":
  var slot: int = floori((-game.rider.position.z + 10) / 16)
  var index: int = slot / 4
  return -1 if game.city.has_building(index, slot % 4, -1) else 1
 if route == "barriers":
  var upcoming: int = maxi(2, ceili((-game.rider.position.z - 28) / 64))
  return 1 if upcoming % 2 == 0 else -1
 return -1 if hooks % 2 == 0 else 1

func trial(route: String, policy: String, start_speed: float, aerial: bool, use_e: bool, high: bool = false) -> void:
 game.preferences.route = route
 game.start_run(not aerial)
 game.rider.practice = false
 game.rider.velocity.z = -start_speed
 if high:
  for i in range(3):
   game.rider.upgrade("high")
   game.rider.upgrade("range")
 var hooks: int = 0
 var switches: int = 0
 var launches: int = 0
 var last_side: int = 0
 var left: int = 0
 var right: int = 0
 var stopped: float = 0
 var elapsed: float = 0
 for frame in range(3600):
  await physics_frame
  var r: CharacterBody3D = game.rider
  var side: int = (-1 if policy == "left" else 1) if policy != "adaptive" else preferred_side(route, hooks)
  if r.mode == "swing" and is_instance_valid(r.anchor):
   if r.position.z < r.anchor.global_position.z - 1 or (policy == "adaptive" and route == "barriers" and signf(r.anchor.global_position.x) != side):
    r.release_wire()
  if not is_instance_valid(r.anchor) and r.launch_left <= 0 and r.position.y > 2.2:
   if use_e and r.launch_cooldown <= 0 and r.launch():
    launches += 1
   else:
    var target: Dictionary = candidate(side)
    if not target.get("valid", false) and policy == "adaptive":
     side = -side
     target = candidate(side)
    if target.get("valid", false) and r.fire_manual(target, side):
     hooks += 1
     if last_side != 0 and last_side != side:
      switches += 1
     last_side = side
     if side < 0:
      left += 1
     else:
      right += 1
  if r.mode == "ground":
   r.jump()
  var steer: float = clampf((side * 3.2 - r.position.x) * 0.7, -1, 1) if route == "barriers" else 0
  r.simulate(1.0 / 60, steer)
  game.distance = maxf(game.distance, -r.position.z)
  game.city.update_chunks(game.distance, r.anchor, r.twin_anchors)
  elapsed = (frame + 1) / 60.0
  stopped = stopped + 1.0 / 60 if absf(r.velocity.z) < 0.5 else 0
  if r.mode == "dead" or game.distance >= 600 or stopped >= 3:
   break
 var result: Dictionary = {"route": route, "policy": policy, "start_speed": start_speed, "aerial": aerial, "e": use_e, "high": high, "distance": snappedf(game.distance, 0.1), "seconds": snappedf(elapsed, 0.01), "finish": game.distance >= 600, "state": game.rider.mode, "reason": game.death_reason, "hooks": hooks, "left": left, "right": right, "switches": switches, "launches": launches}
 results.append(result)
 print("TRIAL ", JSON.stringify(result))

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 for route in ["standard", "sparse", "barriers"]:
  for policy in ["left", "right", "adaptive"]:
   for speed in ([12.0] if quick else [12.0, 16.0, 20.0]):
    await trial(route, policy, speed, false, false)
 if not quick:
  for route in ["standard", "sparse", "barriers"]:
   for speed in [12.0, 16.0, 20.0]:
    await trial(route, "adaptive", speed, true, false)
    await trial(route, "adaptive", speed, true, true)
   await trial(route, "left", 16, false, false, true)
   await trial(route, "adaptive", 16, false, false, true)
 var file := FileAccess.open("res://validation/route-comparison" + ("-quick" if quick else "") + ".json", FileAccess.WRITE)
 file.store_string(JSON.stringify(results, "  "))
 file.close()
 game.free()
 await process_frame
 quit()
