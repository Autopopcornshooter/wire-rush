extends SceneTree
var game: Node3D
func _initialize() -> void:
 run.call_deferred()
func view(cursor: Vector2 = Vector2(640, 360)) -> void:
 game.aim_screen = cursor
 for i in range(90):
  await physics_frame
  game.update_camera_goal(1.0 / 60)
  game._process(1.0 / 60)
func snapshot(name: String) -> void:
 game.hud.queue_redraw()
 game.rider.draw_wire()
 game.update_targets()
 await process_frame
 await RenderingServer.frame_post_draw
 print(name, " capture=", root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://validation/v070-" + name + ".png")))
func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.demo = true
 game.start_run(true)
 await view()
 await snapshot("rooftop-start")
 game.rider.position = Vector3(0, 24, -8)
 for i in range(3):
  game.rider.upgrade("high")
 await view(Vector2(640, 0))
 var high_point := Vector3(-7.4, 44, -12)
 game.aim_screen = game.camera.unproject_position(high_point)
 var target: Dictionary = game.city.manual_target(game.rider.position, game.camera.position, (high_point - game.camera.position).normalized(), game.rider.reach(), game.rider.get_rid())
 game.rider.fire_manual(target, -1)
 await snapshot("camera-high")
 game.start_run(true)
 game.rider.upgrade("armor")
 game.rider.hurt("OBSTACLE COLLISION")
 await view()
 game.rider.invincible = 1.9
 game.rider.visuals.visible = true
 await snapshot("armor-visible")
 game.rider.invincible = 1.7
 game.rider.visuals.visible = false
 await snapshot("armor-blink")
 game.rider.visuals.visible = true
 game.resume()
 game.countdown_started = true
 for number in [3, 2, 1]:
  game.countdown = number * game.Rules.COUNTDOWN_BEAT
  await snapshot("countdown-" + str(number))
 game.free()
 await process_frame
 quit()
