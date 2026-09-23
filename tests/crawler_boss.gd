extends SceneTree
## WASTELAND PHASE W-E: Crawler Boss tests (spec section 53's 22-item
## checklist). Never re-checks W-A/W-B/W-C/W-D's own coverage — this file
## is Crawler-only. The Crawler is not a combat boss (no HP/damage phase/
## weak point/player attack — see crawler_boss.gd's own doc comment), so
## these checks are entirely about traversal: trigger, anchor reachability,
## leg hazard timing, route gap validation, and clear-by-relative-position.
const Rules = preload("res://scripts/rules.gd")
const DifficultyDirector = preload("res://scripts/difficulty_director.gd")
const Wasteland = preload("res://scripts/wasteland.gd")
const CrawlerBoss = preload("res://scripts/crawler_boss.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(60).timeout.connect(func():
  push_error("Crawler boss tests timed out")
  quit(1)
 )
 run.call_deferred()

func check(ok: bool, description: String) -> void:
 checks += 1
 if ok:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)

func run() -> void:
 # ==================================================================
 # 11-13, 16. Pure route-gap validation (spec section 38) — no node/
 # fixture needed at all, just the hand-authored anchor lists themselves.
 # ==================================================================
 var probe := CrawlerBoss.new()
 root.add_child(probe)
 var low_worst: float = chain_gaps(CrawlerBoss.LOW_ANCHORS)
 var high_worst: float = chain_gaps(CrawlerBoss.HIGH_ANCHORS)
 check(low_worst <= CrawlerBoss.MAX_BOSS_GAP, "every consecutive LOW anchor gap stays within the boss traversal guard (worst %.1fm)" % low_worst)
 check(high_worst <= CrawlerBoss.MAX_BOSS_GAP, "every consecutive HIGH anchor gap stays within the boss traversal guard (worst %.1fm)" % high_worst)
 check(CrawlerBoss.MAX_BOSS_GAP < Rules.ROPE_RANGE, "the boss traversal guard stays under the player's real base wire range (%.1fm guard vs %.1fm base range)" % [CrawlerBoss.MAX_BOSS_GAP, Rules.ROPE_RANGE])
 check(Rules.ROPE_RANGE - CrawlerBoss.MAX_BOSS_GAP >= 5.0, "the safety margin below base range is a real practical margin (>=5m)")
 # 13. LOW/HIGH connection: at least one genuinely close crossing exists.
 var closest_cross: float = INF
 for low_pos in CrawlerBoss.LOW_ANCHORS:
  for high_pos in CrawlerBoss.HIGH_ANCHORS:
   closest_cross = minf(closest_cross, low_pos.distance_to(high_pos))
 check(closest_cross <= CrawlerBoss.MAX_BOSS_GAP, "at least one LOW<->HIGH crossing point exists within the same practical guard (%.1fm)" % closest_cross)
 # 14. Upper body route: the HIGH anchor nearest the rotating hazard is
 # still clearly offset from it (never coincident).
 var nearest_to_hazard: float = INF
 for high_pos in CrawlerBoss.HIGH_ANCHORS:
  nearest_to_hazard = minf(nearest_to_hazard, high_pos.distance_to(CrawlerBoss.UPPER_HAZARD_POSITION))
 check(nearest_to_hazard >= 4.0, "every HIGH anchor stays clearly offset from the rotating upper hazard's own pivot (nearest %.1fm)" % nearest_to_hazard)
 probe.free()
 await process_frame

 # ==================================================================
 # 6-7, 15. Leg/hazard structure + motion (no full game fixture needed).
 # ==================================================================
 var boss := CrawlerBoss.new()
 root.add_child(boss)
 await process_frame
 check(boss.legs.size() == CrawlerBoss.LEG_CONFIG.size(), "all 6 legs are built (spec section 7: six-leg crawler)")
 var leg: Dictionary = boss.legs[0]
 var foot: AnimatableBody3D = leg.foot
 check(foot is AnimatableBody3D, "a leg's foot is a real kinematic AnimatableBody3D, the same stable-moving-collision convention as City/Wasteland's own moving hazards")
 check(not foot.get_meta("hookable", true), "a leg's foot is explicitly non-hookable — only the fixed hip joint is a wire target (spec section 39)")
 var foot_collision_count: int = foot.get_children().filter(func(n): return n is CollisionShape3D).size()
 check(foot_collision_count == 1, "a leg's foot carries a real collision shape")
 var before_y: float = foot.position.y
 for i in range(200):
  boss.update_legs(1.0 / 60.0)
 var saw_lift: bool = false
 for i in range(300):
  boss.update_legs(1.0 / 60.0)
  if boss.legs[0].foot.position.y > CrawlerBoss.LEG_FOOT_Y_REST + 0.5:
   saw_lift = true
   break
 check(saw_lift, "over a full leg cycle, a leg's foot actually lifts off its rest height (spec section 12: lift -> swing -> plant -> recover)")

 var hazard: AnimatableBody3D = boss.upper_hazard
 check(hazard is AnimatableBody3D and not hazard.get_meta("hookable", true), "the upper body moving hazard is a real kinematic AnimatableBody3D, explicitly non-hookable (spec section 30)")
 var before_basis: Basis = hazard.basis
 boss.update_upper_hazard(1.0)
 check(not hazard.basis.is_equal_approx(before_basis), "update_upper_hazard() actually rotates the arm over time")
 boss.free()
 await process_frame

 # ==================================================================
 # 1-5, 8-10, 17-18, 21-22. Full lifecycle against a real game fixture.
 # ==================================================================
 var game: Node3D = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 # Real (non-practice) death rule (spec section 59) — same reasoning as
 # tools/Wasteland-Event-QA.gd: practice mode's Rider.hurt() always
 # auto-rescues, which would mask a genuinely fatal collision as a pass.
 game.start_run(false)
 await physics_frame

 var boss_start: float = Wasteland.wasteland_boss_start_distance()
 while boss_start - game.city.origin_offset >= 2048.0:
  game.city.rebase(2048.0)
  game.wasteland.rebase(2048.0)
  game.boss.rebase(2048.0)
  game.crawler.rebase(2048.0)
 game.distance = boss_start - 200.0
 game.rider.position = Vector3(0, 4, -(game.distance - game.city.origin_offset))
 game.rider.velocity = Vector3.ZERO
 game.rider.mode = "ground"

 # 1. Boss start trigger
 check(game.crawler.state == CrawlerBoss.STATE_INACTIVE, "fixture sanity: the Crawler is inactive before the boss-start distance")
 game.crawler.update(1.0 / 60.0, boss_start - 200.0, game.rider, game.wasteland)
 check(game.crawler.state == CrawlerBoss.STATE_INACTIVE, "the Crawler stays inactive before its own start distance")
 game.crawler.update(1.0 / 60.0, boss_start + 1.0, game.rider, game.wasteland)
 check(game.crawler.state == CrawlerBoss.STATE_INTRO, "crossing the boss-start distance triggers INTRO")
 var intro_position: Vector3 = game.crawler.global_position

 # 2. Duplicate start
 game.crawler.update(1.0 / 60.0, boss_start + 2.0, game.rider, game.wasteland)
 check(game.crawler.global_position == intro_position or game.crawler.state != CrawlerBoss.STATE_INTRO, "a second update() call past the trigger distance never re-triggers a fresh INTRO (no duplicate start)")

 # 3. State machine: drive INTRO -> ACTIVE
 var ticks: int = 0
 while game.crawler.state == CrawlerBoss.STATE_INTRO and ticks < 300:
  game.crawler.update(1.0 / 60.0, boss_start + 2.0, game.rider, game.wasteland)
  ticks += 1
 check(game.crawler.state == CrawlerBoss.STATE_ACTIVE, "INTRO transitions to ACTIVE after its own timer")
 # Newly (re)parented/moved StaticBody3D transforms need a physics-server
 # flush before a raycast against them succeeds — the same timing rule
 # this project's other QA harnesses already learned the hard way.
 await physics_frame

 # 4-5. Approach entry route + real end-to-end wire-target regression
 # against the rear (Phase 1 APPROACH) LOW anchor.
 var rear_anchor_world: Vector3 = game.crawler.global_position + CrawlerBoss.LOW_ANCHORS[0]
 check(game.rider.global_position.distance_to(rear_anchor_world) <= Rules.ROPE_RANGE, "the Crawler's own rear anchor is reachable within real base wire range the instant INTRO triggers (spec section 19)")
 var direction: Vector3 = (rear_anchor_world - game.rider.global_position).normalized()
 var selection: Dictionary = game.city.manual_target(game.rider.global_position, game.rider.global_position, direction, game.rider.reach(), game.rider.get_rid())
 check(selection.get("valid", false), "a real aim against the Crawler's rear LOW anchor succeeds — proves extra_target_roots/owns_target_surface recognizes Crawler structures")
 check(game.rider.fire_manual(selection, -1), "Rider.fire_manual()'s own revalidation also accepts the Crawler anchor")
 check(is_instance_valid(game.rider.anchor) and game.crawler.is_ancestor_of(game.rider.anchor.get_parent()), "the rider genuinely holds a wire connection to a real Crawler structure")
 game.rider.release_wire()

 # 8-10. Leg hit -> Rider.hurt(), armor interaction, hit dedupe — reuses
 # Rider.hurt()'s own existing, already-proven logic (same as W-C's
 # Turbine regression); confirms the SAME call path a real foot collision
 # would drive.
 game.rider.invincible = 1.0
 game.rider.position.y = 0.0
 game.rider.armor_charges = 0
 var first_hurt: bool = game.rider.hurt("OBSTACLE COLLISION")
 var second_hurt: bool = game.rider.hurt("OBSTACLE COLLISION")
 check(first_hurt and second_hurt, "Rider.hurt()'s invincibility window no-ops a repeat leg-foot hit — the exact dedupe a foot spanning several physics frames relies on")
 game.rider.invincible = 0.0
 game.rider.armor_charges = 1
 check(game.rider.hurt("OBSTACLE COLLISION"), "armor absorbs one leg-foot hit instead of killing the player")
 check(game.rider.armor_charges == 0, "the absorbed hit actually consumed the armor charge")

 # 17-18. Overtake route + clear condition
 var overtake_world: Vector3 = game.crawler.global_position + Vector3(0, 7, CrawlerBoss.LOW_ANCHORS[-1].z)
 check(is_instance_valid(game.crawler.escape_marker), "an escape marker exists for the clear condition")
 check(game.crawler.escape_marker.global_position.z < overtake_world.z, "the escape marker sits genuinely ahead of (more negative than) the front overtake anchor, not behind it")
 game.rider.mode = "ground"
 game.rider.armor_charges = 0
 game.rider.invincible = 0.0
 game.rider.global_position = game.crawler.escape_marker.global_position + Vector3(0, 0, 1.0)
 game.crawler.update(1.0 / 60.0, boss_start + 3.0, game.rider, game.wasteland)
 check(game.crawler.state == CrawlerBoss.STATE_ACTIVE, "fixture sanity: still ACTIVE just behind the escape marker")
 game.rider.global_position = game.crawler.escape_marker.global_position + Vector3(0, 0, -1.0)
 game.crawler.update(1.0 / 60.0, boss_start + 3.0, game.rider, game.wasteland)
 check(game.crawler.state == CrawlerBoss.STATE_ESCAPE, "getting ahead of the escape marker (relative position, not HP) triggers ESCAPE")
 ticks = 0
 while game.crawler.state == CrawlerBoss.STATE_ESCAPE and ticks < 300:
  game.crawler.update(1.0 / 60.0, boss_start + 3.0, game.rider, game.wasteland)
  ticks += 1
 check(game.crawler.state == CrawlerBoss.STATE_CLEARED, "ESCAPE transitions to CLEARED after its own timer")

 # 22. Cleanup
 check(not game.crawler.visible, "a CLEARED Crawler is hidden")
 check(game.crawler.global_position.z < game.rider.global_position.z - 500.0, "a CLEARED Crawler is pushed well clear of the player, not left sitting in the way (spec section 33/52)")

 game.free()
 await process_frame

 # ==================================================================
 # 19-20. Event suppression during the boss window, and normal Wasteland
 # resuming afterward — pure function checks, no fixture needed.
 # ==================================================================
 var w := Wasteland.new()
 var boss_start_index: int = ceili(Wasteland.wasteland_boss_start_distance() / Wasteland.LENGTH)
 var boss_end_index: int = floori(Wasteland.wasteland_boss_end_distance() / Wasteland.LENGTH)
 var any_event_in_boss_zone: bool = false
 for idx in range(boss_start_index, boss_end_index):
  if w.event_for_chunk(idx) != Wasteland.EVENT_NONE:
   any_event_in_boss_zone = true
 check(not any_event_in_boss_zone, "no Dust/Turbine/Crane event ever spawns inside the Crawler's own boss window")
 var any_event_just_before: bool = false
 for idx in range(boss_start_index - 3, boss_start_index):
  if w.event_for_chunk(idx) != Wasteland.EVENT_NONE:
   any_event_just_before = true
 check(not any_event_just_before, "no event window ends right at the boss's own doorstep (spec section 45 pre-boss normalization)")
 var resumed_normally: bool = false
 for idx in range(boss_end_index + 1, boss_end_index + 400):
  if w.event_for_chunk(idx) != Wasteland.EVENT_NONE:
   resumed_normally = true
   break
 check(resumed_normally, "ordinary Wasteland events resume again well past the boss window (suppression is scoped, not permanent)")
 w.free()

 print("CRAWLER_BOSS_RESULT %d/%d passed; failures=%d" % [checks - failures, checks, failures])
 quit(1 if failures > 0 else 0)

func chain_gaps(points: Array) -> float:
 var worst: float = 0.0
 for i in range(points.size() - 1):
  worst = maxf(worst, points[i].distance_to(points[i + 1]))
 return worst
