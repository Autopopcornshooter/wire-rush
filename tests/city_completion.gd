extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL " + description)
 else:
  print("PASS ", description)
func first_mesh(node: Node) -> MeshInstance3D:
 if node is MeshInstance3D:
  return node
 for child in node.get_children():
  var found: MeshInstance3D = first_mesh(child)
  if found != null:
   return found
 return null
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.start_run(false)
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame
 game.complete_city()
 check(game.phase == "playing", "City cannot complete before the exit")
 for key in game.rider.tiers:
  game.rider.tiers[key] = 3
 var rect: Rect2 = game.hud.pause_layout().panel
 check(rect.position.y >= 0 and rect.end.y <= 720, "all 15 upgrades fit within 720p pause panel")
 check(game.hud.pause_layout().owned.size() == 15, "wrapping preserves every owned upgrade")
 var models: Array = []
 var first: MeshInstance3D
 var legacy_nodes: int = 0
 for index in range(6):
  var sequence: Array = []
  for building in game.city.chunks[index].get_children():
   if building.get_meta("building",false):
    sequence.append(building.get_meta("model_seed") % 3)
    legacy_nodes += building.get_node("Windows").get_child_count()
    if first == null:
     first = first_mesh(building.get_node("RealisticModel"))
  if not models.has(sequence):
   models.append(sequence)
 check(legacy_nodes == 0, "streamed buildings do not allocate hidden legacy windows")
 check(models.size() >= 3, "adjacent chunks no longer repeat one model sequence")
 var original: Material = first.get_active_material(0)
 var original_uv: Vector3 = original.uv1_scale
 game.city.apply_height_level(3)
 game.city.create_chunk(10)
 check(first.get_active_material(0) == original and original.uv1_scale == original_uv, "new tall buildings do not mutate existing facade materials")
 for height in [0.85,12.0,40.0,65.0]:
  game.rider.position = Vector3(0,height,-3200)
  game.update_camera_goal(1)
  game.camera.position = game.camera_goal
  game.camera.look_at(game.camera_look)
  game.boss.rider = game.rider
  var point: Vector3 = game.boss.boss_target_position()
  var screen: Vector2 = game.camera.unproject_position(point)
  check(not game.camera.is_position_behind(point) and Rect2(0,0,1280,720).has_point(screen), "boss source visible at player height %.2f" % height)
 var cues: Array[String] = []
 game.boss.cue.connect(func(kind: String): cues.append(kind))
 game.boss.update(1.0/60,3200,game.rider,game.city)
 game.boss.state = game.boss.STATE_ACTIVE
 game.boss.start_pattern(game.boss.PATTERN_PATH_BLOCK)
 # PATH_BLOCK's telegraph now runs at the same EXTENDED_WARNING_TIME_SCALE
 # cadence as LASER_PLANE (98 ticks, not 65) so both patterns give the
 # player the same warning-to-active time.
 for i in range(99):
  game.boss.update_current_pattern(1.0/60)
 check(cues.count("warning") == 3, "three warning blinks each emit one audio pulse")
 check(cues.count("laser") == 1, "laser activation emits one cue")
 game.boss.start_pattern(game.boss.PATTERN_ROBOT_BARRAGE)
 game.boss.pattern_phase = game.boss.PHASE_ACTIVE
 game.boss.phase_timer = 1
 var launches: int = cues.count("launch")
 game.boss.update(1.0/60,4700,game.rider,game.city)
 check(cues.count("launch") == launches and game.boss.barrage_robots.is_empty(), "Rest boundary is resolved before a scheduled robot launch")
 game.city.update_chunks(5000)
 check(game.city.chunks.keys().all(func(index: int): return index <= 79), "no gameplay chunks stream beyond City exit")
 var exit_signs: Array = game.city.chunks[79].find_children("*", "Label3D", true, false)
 check(exit_signs.all(func(sign: Label3D): return sign.get_meta("route_text") != "SKY ROUTE"), "City exit does not preview an event from an unbuilt chapter")
 game.set_language("en")
 check(exit_signs.all(func(sign: Label3D): return sign.text == sign.get_meta("route_text")), "existing world signs follow language changes")
 # Signs convey navigation, but never serve as chapter-state triggers.
 for sign in game.get_tree().get_nodes_in_group("city_route_signs"):
  sign.queue_free()
 await process_frame
 check(game.get_tree().get_nodes_in_group("city_route_signs").is_empty(), "fixture removes world signs before the actual City exit crossing")
 game.city.rebase(4096)
 game.rider.position = Vector3(0,0.86,-5100+4096)
 game.rider.velocity = Vector3.ZERO
 game.rider.mode = "ground"
 game.distance = 5099
 await physics_frame
 game._physics_process(1.0/60)
 check(game.phase == "complete", "crossing 5100m completes City after origin shift")
 check(game.distance == 5100 and game.best == 5100, "completion records exact City length")
 check(not game.boss.visible and game.boss.barrage_robots.is_empty() and game.boss.laser_node == null and game.boss.block_node == null, "completion removes every boss attack")
 var stopped: Vector3 = game.rider.position
 for i in range(10):
  game._physics_process(1.0/60)
 check(game.rider.position == stopped, "completion stops simulation beyond City")
 game.end_run("late collision callback")
 check(game.phase == "complete", "delayed collision cannot replace completion with death")
 check(game.hud.buttons.size() == 2, "completion offers replay and menu")
 game.start_run(true)
 game.distance = 5100
 game.complete_city()
 check(game.phase == "playing", "practice remains open ended")
 game.start_run(false)
 game.city.update_chunks(5099)
 game.rider.position = Vector3(0,0.86,-5100)
 game.rider.velocity = Vector3(0,-4,0)
 game.rider.last_release_height = 6
 game.rider.jump_exempt = false
 game.rider.mode = "air"
 game.distance = 5099
 await physics_frame
 game._physics_process(1.0/60)
 check(game.phase == "dead", "fatal landing takes precedence over chapter completion")
 check(game.played_signals.is_empty(), "restarting clears story playback state")
 game.start_run(false)
 game.phase = "paused"
 game.rider.hurt("pending collision at pause")
 check(game.phase == "dead" and game.rider.mode == "dead", "pending collision at pause cannot leave a dead rider behind a resumable pause menu")
 print("CITY_COMPLETION_RESULT ",checks-failures,"/",checks," passed; failures=",failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
