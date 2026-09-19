extends RefCounted
const GRAVITY: float = 20.0
const JUMP_SPEED: float = 10.95
const MAX_SPEED: float = 35.0
const HOOK_SPEED: float = 80.0
const ROPE_RANGE: float = 30.0
const REEL_SPEED: float = 5.0
const SAFE_RELEASE_HEIGHT: float = 5.0
const DOUBLE_JUMP_COOLDOWN: Array[float] = [10.0, 7.0, 5.0]
const WALL_JUMP_PUSH: float = 8.5
const STOP_SPEED: float = 0.15
## Roller-skate charge system (index 0 is the unused "no skates" tier).
## Charge is a persistent 0..1 resource (Rider.skate_charge): draining while
## actively sliding, recovering while not, independent of wire/jump/landing
## events. SKATE_MAX_DURATION is how long a *full* charge lasts once spent;
## SKATE_RECHARGE_DURATION is how long an *empty* charge takes to refill.
const SKATE_MAX_DURATION: Array[float] = [0.0, 2.0, 3.5, 5.0]
const SKATE_RECHARGE_DURATION: Array[float] = [1.0, 4.0, 7.0, 10.0]
## World-side building height tier. No longer settable by a player upgrade —
## see UPGRADES below — but kept here (and as City.high_level, driven by
## City.apply_height_level()) as the API a future Phase B Difficulty
## Director can drive. Defaults to tier 0 until something sets it.
const BUILDING_BONUS: Array[float] = [0.0, 10.0, 20.0, 30.0]
const ARMOR_PROTECTION: float = 2.0
const COUNTDOWN_BEAT: float = 0.7
const CAMERA_DAMPING: float = 5.0
## Same direction as the original (0, 4.5, 12.0) offset, uniformly scaled
## down to a 5.0m boom length — like shortening a SpringArm3D without
## rotating it: the elevation angle (and therefore the follow/smoothing/
## look-at behavior built around this vector elsewhere) is unchanged, only
## the distance is. FOV/projection untouched.
const CAMERA_OFFSET := Vector3(0, 1.755617, 4.681646)
## Every 5th level (5, 10, 15, ...) queues a CORE upgrade choice instead of a
## NORMAL one. See Main.pending_upgrades (an ordered Array[String] of
## "NORMAL"/"CORE", one entry per queued level-up — never just a count) and
## Main.open_upgrades().
const CORE_UPGRADE_INTERVAL: int = 5
## Player progression catalog. Each entry:
##  type: "NORMAL" (offered every non-core level-up) or "CORE" (offered only
##   every CORE_UPGRADE_INTERVAL levels; exactly the 3 keys below).
##  category: WIRE / MOBILITY / MOMENTUM / SURVIVAL / CORE — display grouping only.
##  max_tier: highest value rider.tiers[key] can reach via upgrade().
##  requires: (normal upgrades only, optional) another upgrade id that must
##   already be tier>0 before this one can appear in the offer pool — used by
##   upgrades that only make sense once a related CORE ability is unlocked.
## Building Height ("high") is intentionally absent: it is no longer a player
## upgrade (see City.apply_height_level/City.high_level for the world-side
## mechanism that still exists for a future Difficulty Director).
const UPGRADES: Dictionary = {
 "range": {"type": "NORMAL", "category": "WIRE", "max_tier": 3, "name": "LONGER WIRE", "description": "+10% wire reach. Connect to a more distant point."},
 "reel": {"type": "NORMAL", "category": "WIRE", "max_tier": 3, "name": "FAST REEL", "description": "+15% automatic reel speed while holding the mouse button."},
 "hook": {"type": "NORMAL", "category": "WIRE", "max_tier": 3, "name": "FAST HOOK", "description": "+20% hook speed. Recover sooner after firing."},
 "attach_assist": {"type": "NORMAL", "category": "WIRE", "max_tier": 3, "name": "ATTACH ASSIST", "description": "Widens the existing range-assist window slightly, so near-miss aims still find a real surface."},
 "jump": {"type": "NORMAL", "category": "MOBILITY", "max_tier": 3, "name": "HIGH JUMP", "description": "+10% jump height for ground jumps, wall jumps, and double jumps alike."},
 "air_control": {"type": "NORMAL", "category": "MOBILITY", "max_tier": 3, "name": "AIR CONTROL", "description": "Steer more effectively while airborne."},
 "ground_control": {"type": "NORMAL", "category": "MOBILITY", "max_tier": 3, "name": "GROUND CONTROL", "description": "Sharper, faster ground steering and walking response."},
 "release_momentum": {"type": "NORMAL", "category": "MOMENTUM", "max_tier": 3, "name": "RELEASE MOMENTUM", "description": "Keep a little more speed when you let go of the wire."},
 "skate_recharge": {"type": "NORMAL", "category": "MOMENTUM", "max_tier": 3, "name": "SKATE RECHARGE", "description": "Roller-skate charge recovers faster while not sliding.", "requires": "skates"},
 "skate_efficiency": {"type": "NORMAL", "category": "MOMENTUM", "max_tier": 3, "name": "SKATE EFFICIENCY", "description": "Roller-skate charge drains slower while sliding.", "requires": "skates"},
 "collision_grace": {"type": "NORMAL", "category": "SURVIVAL", "max_tier": 3, "name": "COLLISION GRACE", "description": "A little extra invincibility after any protected hit."},
 "armor_support": {"type": "NORMAL", "category": "SURVIVAL", "max_tier": 3, "name": "ARMOR SUPPORT", "description": "Impact Armor grants extra protection time when it saves you.", "requires": "armor"},
 "double_jump": {"type": "CORE", "category": "CORE", "max_tier": 3, "name": "DOUBLE JUMP", "description": "Unlocks an extra air jump. Recharges in 10 / 7 / 5s as you level it up. Higher tiers also sharpen air control and speed up your next wire connection right after a double jump."},
 "skates": {"type": "CORE", "category": "CORE", "max_tier": 3, "name": "ROLLER SKATES", "description": "Keep landing speed for up to 2 / 3.5 / 5 seconds of charge. Release at player height 5m or below to slide."},
 "armor": {"type": "CORE", "category": "CORE", "max_tier": 3, "name": "IMPACT ARMOR", "description": "Keep moving after a hit: blink and ignore obstacles for 2s. Higher tiers add extra protection time and soften the emergency-rescue landing."},
}
static func xp_required(level: int) -> int:
 return roundi(180.0 * pow(1.25, mini(level - 1, 8)))
static func progress(previous: float, position_z: float, origin_offset: float) -> float:
 return maxf(previous, -position_z + origin_offset)
