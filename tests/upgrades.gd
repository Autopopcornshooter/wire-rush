extends SceneTree
## PHASE A: Player Progression (Normal/Core upgrades, pending queue, Building
## Height removal, Synergies). See scripts/rules.gd (Rules.UPGRADES,
## Rules.CORE_UPGRADE_INTERVAL), scripts/main.gd (pending_upgrades,
## upgrade_pool, open_upgrades, choose), scripts/rider.gd (evaluate_synergies,
## active_synergies).
const Rules = preload("res://scripts/rules.gd")
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
 create_timer(30).timeout.connect(func(): quit(1))
 run.call_deferred()

func check(ok: bool, description: String) -> void:
 checks += 1
 if ok:
  print("PASS ", description)
 else:
  failures += 1
  push_error("FAIL " + description)

func fixture() -> void:
 game.start_run(false)
 game.rider.position = Vector3(0, 6, 0)
 game.rider.velocity = Vector3(0, 0, -12)
 game.set_physics_process(false)
 game.set_process(false)
 await physics_frame

## main.gd's pending_upgrades is Array[String]; assigning a plain array
## literal directly to that typed property from outside the class doesn't
## get the same implicit element-typing a `var x: Array[String] = [...]`
## declaration gets, so route it through a typed local first.
func typed_queue(entries: Array) -> Array[String]:
 var typed: Array[String] = []
 for entry in entries:
  typed.append(entry)
 return typed

## Mirrors main.gd's own _physics_process level-up loop, so tests can drive
## leveling without simulating real XP gain frame by frame.
func level_up_to(target_level: int) -> void:
 while game.level < target_level:
  game.level += 1
  game.pending_upgrades.append("CORE" if game.level % Rules.CORE_UPGRADE_INTERVAL == 0 else "NORMAL")

func run() -> void:
 game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)

 # ---- Catalog shape -------------------------------------------------
 await fixture()
 check(not Rules.UPGRADES.has("high"), "Building Height is not in the player upgrade catalog")
 check(Rules.CORE_UPGRADE_INTERVAL == 5, "core upgrades occur every 5 levels")
 var core_keys: Array = Rules.UPGRADES.keys().filter(func(k: String): return Rules.UPGRADES[k].type == "CORE")
 check(core_keys.size() == 3 and "double_jump" in core_keys and "skates" in core_keys and "armor" in core_keys, "exactly three core abilities exist: double jump, roller skates, armor")
 var normal_keys: Array = Rules.UPGRADES.keys().filter(func(k: String): return Rules.UPGRADES[k].type == "NORMAL")
 check(normal_keys.size() == 12, "twelve normal upgrades exist")
 for key in normal_keys:
  check(Rules.UPGRADES[key].category in ["WIRE", "MOBILITY", "MOMENTUM", "SURVIVAL"], "%s belongs to one of the four player categories" % key)

 # ---- Level-up queue: type per entry, not just a count --------------
 await fixture()
 game.level = 1
 game.pending_upgrades.clear()
 level_up_to(2)
 check(game.pending_upgrades == ["NORMAL"], "an ordinary level-up queues a NORMAL upgrade")
 await fixture()
 game.level = 1
 game.pending_upgrades.clear()
 level_up_to(5)
 check(game.pending_upgrades == ["NORMAL", "NORMAL", "NORMAL", "CORE"], "level 5 queues a CORE upgrade; levels 2-4 stay NORMAL")
 await fixture()
 game.level = 5
 game.pending_upgrades.clear()
 level_up_to(10)
 check(game.pending_upgrades == ["NORMAL", "NORMAL", "NORMAL", "NORMAL", "CORE"], "level 10 also queues CORE")
 await fixture()
 game.level = 3
 game.pending_upgrades.clear()
 level_up_to(6)
 check(game.pending_upgrades == ["NORMAL", "CORE", "NORMAL"], "levels 4, 5, 6 stacked together queue NORMAL, CORE, NORMAL in order")
 game.open_upgrades()
 check(game.choices.all(func(k: String): return Rules.UPGRADES[k].type == "NORMAL"), "the first queued (NORMAL) entry only offers normal-pool upgrades")
 game.choose(0)
 check(game.pending_upgrades == ["CORE", "NORMAL"], "G consumes the queue strictly in order")
 check(game.choices.all(func(k: String): return Rules.UPGRADES[k].type == "CORE"), "the queue's next (CORE) entry immediately offers only core abilities")
 game.choose(0)
 check(game.pending_upgrades == ["NORMAL"], "the trailing NORMAL entry survives the CORE pick untouched")
 check(game.choices.all(func(k: String): return Rules.UPGRADES[k].type == "NORMAL"), "the final entry is still NORMAL, independent of the player's now-higher level")
 game.choose(0)
 check(game.pending_upgrades.is_empty() and game.phase == "countdown", "the whole stack resolves and resumes play once empty")

 # ---- Pool separation -------------------------------------------------
 # upgrade_pool() itself is deterministic (tiers only, no rng); the actual
 # randomness lives in open_upgrades()'s choices selection, so exercise that
 # across several seeds instead of the pool function directly.
 await fixture()
 var normal_pool: Array = game.upgrade_pool("NORMAL")
 check(not normal_pool.any(func(k: String): return Rules.UPGRADES[k].type == "CORE"), "the NORMAL pool never contains a core ability")
 var core_pool: Array = game.upgrade_pool("CORE")
 check(not core_pool.any(func(k: String): return Rules.UPGRADES[k].type == "NORMAL"), "the CORE pool never contains a normal upgrade")
 for seed_value in range(20):
  game.rng.seed = seed_value
  game.pending_upgrades = typed_queue(["NORMAL"])
  game.open_upgrades()
  check(game.choices.all(func(k: String): return Rules.UPGRADES[k].type == "NORMAL"), "a NORMAL offer never contains a core ability (seed %d)" % seed_value)
  game.pending_upgrades = typed_queue(["CORE"])
  game.open_upgrades()
  check(game.choices.all(func(k: String): return Rules.UPGRADES[k].type == "CORE"), "a CORE offer never contains a normal upgrade (seed %d)" % seed_value)

 # ---- Max-tier exclusion ----------------------------------------------
 await fixture()
 game.rider.tiers.range = Rules.UPGRADES.range.max_tier
 check(not "range" in game.upgrade_pool("NORMAL"), "a maxed-tier normal upgrade is excluded from its own pool")
 game.rider.tiers.double_jump = Rules.UPGRADES.double_jump.max_tier
 check(not "double_jump" in game.upgrade_pool("CORE"), "a maxed-tier core ability is excluded from the core pool")

 # ---- requires: gated normal upgrades ----------------------------------
 await fixture()
 check(not "skate_recharge" in game.upgrade_pool("NORMAL"), "Skate Recharge is hidden until the Roller Skates core is picked")
 game.rider.tiers.skates = 1
 check("skate_recharge" in game.upgrade_pool("NORMAL"), "Skate Recharge appears once Roller Skates has been picked")
 check(not "armor_support" in game.upgrade_pool("NORMAL"), "Armor Support is hidden until the Impact Armor core is picked")
 game.rider.tiers.armor = 1
 check("armor_support" in game.upgrade_pool("NORMAL"), "Armor Support appears once Impact Armor has been picked")

 # ---- Core ability tiers rise via the CORE pool/choose() path ----------
 await fixture()
 game.pending_upgrades = typed_queue(["CORE"])
 game.open_upgrades()
 while not "double_jump" in game.choices:
  game.rng.seed += 1
  game.open_upgrades()
 var double_jump_slot: int = game.choices.find("double_jump")
 game.choose(double_jump_slot)
 check(game.rider.tiers.double_jump == 1, "choosing Double Jump from a CORE offer raises its tier")
 await fixture()
 game.pending_upgrades = typed_queue(["CORE"])
 game.open_upgrades()
 while not "skates" in game.choices:
  game.rng.seed += 1
  game.open_upgrades()
 game.choose(game.choices.find("skates"))
 check(game.rider.tiers.skates == 1, "choosing Roller Skates from a CORE offer raises its tier")
 await fixture()
 game.pending_upgrades = typed_queue(["CORE"])
 game.open_upgrades()
 while not "armor" in game.choices:
  game.rng.seed += 1
  game.open_upgrades()
 game.choose(game.choices.find("armor"))
 check(game.rider.tiers.armor == 1 and game.rider.armor_charges == 1, "choosing Impact Armor from a CORE offer raises its tier and grants a charge")

 # ---- SLINGSHOT synergy -------------------------------------------------
 await fixture()
 game.rider.tiers.reel = 1
 game.rider.tiers.range = 1
 game.rider.evaluate_synergies()
 check(not game.rider.active_synergies.slingshot, "SLINGSHOT is inactive below the Reel Speed + Wire Length threshold")
 game.rider.tiers.reel = 2
 game.rider.tiers.range = 2
 game.rider.evaluate_synergies()
 check(game.rider.active_synergies.slingshot, "SLINGSHOT activates once both Reel Speed and Wire Length reach tier 2")
 game.rider.evaluate_synergies()
 game.rider.evaluate_synergies()
 check(game.rider.active_synergies.slingshot == true, "re-evaluating an already-active synergy never toggles or duplicates it")
 # Effect: a small momentum bonus on a fast swing release, never triggered without it.
 await fixture()
 game.rider.mode = "swing"
 game.rider.hook_connected = true
 game.rider.anchor = Node3D.new()
 game.add_child(game.rider.anchor)
 game.rider.velocity = Vector3(0, 0, -20)
 var speed_before_plain: float = game.rider.velocity.length()
 game.rider.release_wire()
 check(is_equal_approx(game.rider.velocity.length(), speed_before_plain), "releasing a fast swing at tier 0 with no synergy preserves velocity exactly")
 await fixture()
 game.rider.tiers.reel = 2
 game.rider.tiers.range = 2
 game.rider.evaluate_synergies()
 game.rider.mode = "swing"
 game.rider.hook_connected = true
 game.rider.anchor = Node3D.new()
 game.add_child(game.rider.anchor)
 game.rider.velocity = Vector3(0, 0, -20)
 var speed_before_slingshot: float = game.rider.velocity.length()
 game.rider.release_wire()
 check(game.rider.velocity.length() > speed_before_slingshot, "SLINGSHOT adds a small momentum bonus on a fast swing release")

 # ---- STREET SURFER synergy ---------------------------------------------
 await fixture()
 game.rider.tiers.skates = 3
 game.rider.evaluate_synergies()
 check(not game.rider.active_synergies.street_surfer, "STREET SURFER needs Momentum-category investment beyond maxed Roller Skates alone")
 game.rider.tiers.skate_recharge = 2
 game.rider.evaluate_synergies()
 check(game.rider.active_synergies.street_surfer, "STREET SURFER activates with Roller Skate Lv3 plus enough Momentum investment")
 game.rider.mode = "slide"
 game.rider.velocity = Vector3(10, 0, -10)
 game.rider.stop_on_ground()
 check(game.rider.mode == "ground" and game.rider.velocity.length() > 0.1, "STREET SURFER keeps some momentum when a timed slide ends")
 await fixture()
 game.rider.tiers.skates = 3
 game.rider.evaluate_synergies()
 check(not game.rider.active_synergies.street_surfer, "fixture: inactive without Momentum investment")
 game.rider.mode = "slide"
 game.rider.velocity = Vector3(10, 0, -10)
 game.rider.stop_on_ground()
 check(game.rider.velocity == Vector3.ZERO, "without STREET SURFER, ending a slide still stops cleanly as before")

 # ---- SKY RUNNER synergy -------------------------------------------------
 await fixture()
 game.rider.tiers.double_jump = 3
 game.rider.tiers.jump = 1
 game.rider.evaluate_synergies()
 check(not game.rider.active_synergies.sky_runner, "SKY RUNNER needs Jump Power investment beyond Double Jump Lv3 alone")
 game.rider.tiers.jump = 2
 game.rider.evaluate_synergies()
 check(game.rider.active_synergies.sky_runner, "SKY RUNNER activates with Double Jump Lv3 plus Jump Power tier 2")
 game.rider.mode = "air"
 game.rider.velocity.y = 2
 game.rider.jump()
 check(game.rider.just_double_jumped, "fixture: a double jump was spent")
 var aim_point := Vector3(-7.4, 4, game.rider.position.z - 8)
 var target: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (aim_point - game.rider.position).normalized(), game.rider.reach(), game.rider.get_rid())
 check(game.rider.fire_manual(target, -1), "fixture: wire fires after the double jump")
 var boosted_duration: float = game.rider.hook_duration
 check(not game.rider.just_double_jumped, "the double-jump wire bonus is consumed by the first wire action")
 game.rider.release_wire()
 var target2: Dictionary = game.city.manual_target(game.rider.position, game.rider.position, (aim_point - game.rider.position).normalized(), game.rider.reach(), game.rider.get_rid())
 check(game.rider.fire_manual(target2, -1), "fixture: a second wire fires without another double jump")
 var normal_duration: float = game.rider.hook_duration
 check(boosted_duration < normal_duration, "only the first wire connection after a double jump gets the SKY RUNNER speed bonus, not repeated ones")

 print("UPGRADES_RESULT ", checks - failures, "/", checks, " passed; failures=", failures)
 game.free()
 await process_frame
 quit(0 if failures == 0 else 1)
