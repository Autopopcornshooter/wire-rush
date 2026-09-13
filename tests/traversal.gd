extends SceneTree
var game: Node3D
var crashes: int = 0
var hooks: int = 0
var samples: Array = []

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
 for frame in range(1800):
  await physics_frame
  var r: CharacterBody3D = game.rider
  if r.anchor == null and r.position.y > 2.2:
   if r.fire(-1 if hooks % 2 == 0 else 1):
    hooks += 1
  if r.mode == "ground":
   r.jump()
  if r.mode == "swing" and r.position.z < r.anchor.global_position.z - 1:
   r.release_wire()
  r.simulate(1.0 / 60.0, 0)
  game.distance = maxf(game.distance, -r.position.z)
  game.city.update_chunks(game.distance, r.anchor)
  if frame % 120 == 0:
   samples.append({"t": frame / 60.0, "z": snappedf(r.position.z, 0.1), "y": snappedf(r.position.y, 0.1), "speed": snappedf(r.velocity.length(), 0.1), "mode": r.mode})
 print("TRAVERSAL ", JSON.stringify({"distance": game.distance, "rescues": crashes, "hooks": hooks, "samples": samples}))
 var passed: bool = crashes == 0 and hooks >= 10 and game.distance > 250
 game.free()
 await process_frame
 quit(0 if passed else 1)
