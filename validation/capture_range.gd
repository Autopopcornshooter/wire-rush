extends SceneTree
var game: Node3D
func _initialize() -> void:
 run.call_deferred()
func snapshot(name: String, point: Vector3) -> void:
 game.camera.position = game.rider.position + game.Rules.CAMERA_OFFSET
 game._process(0.016)
 game.aim_screen = game.camera.unproject_position(point)
 game.update_targets()
 game.rider.draw_wire()
 await process_frame
 await RenderingServer.frame_post_draw
 print(name, " preview=", game.aim_preview.get("reason", ""), " capture=", root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://validation/v052-" + name + ".png")))
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.demo = true
 game.start_run(true)
 await physics_frame
 await snapshot("range-wall", Vector3(-7.4, 12, -110))
 game.city.obstacle(game.city.chunks[0], Vector3(1.8, 10, -29), Vector3(2.6, 2.2, 1.4))
 game.city.obstacle(game.city.chunks[1], Vector3(0, 12, -16), Vector3(2.6, 2.2, 1.4))
 await physics_frame
 await snapshot("range-obstacle", Vector3(0, 12, -79.3))
 game.start_run(true)
 var hazard: Node3D = game.city.obstacle(game.city.chunks[0], Vector3(0, 12, -10), Vector3(2.6, 2.2, 1.4))
 game.rider.position = Vector3(0, 12, 0)
 game.rider.velocity = Vector3.ZERO
 await physics_frame
 var selection: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, Vector3.FORWARD, 30, game.rider.get_rid())
 game.rider.fire_manual(selection, -1)
 for i in range(20):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
 game.rider.position = Vector3(0, 12, -16)
 game.rider.velocity = Vector3(0, 0, -6)
 game.rider.rope_length = 12
 for i in range(15):
  await physics_frame
  game.rider.simulate(1.0 / 60, 0)
 print("orbit connected=", game.rider.hook_connected)
 await snapshot("obstacle-orbit", hazard.global_position)
 game.free()
 await process_frame
 quit()
