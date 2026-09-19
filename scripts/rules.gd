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
const UPGRADES: Dictionary = {
 "skates": ["ROLLER SKATES", "Keep landing speed for up to 2 / 3.5 / 5 seconds of charge. Release at player height 5m or below to slide."],
 "armor": ["IMPACT ARMOR", "Keep moving after a hit: blink and ignore obstacles for 2s. Hidden while armor remains."],
 "high": ["TALLER BUILDINGS", "Raise buildings by 10 / 20 / 30m. Aerial obstacles also rise."],
 "range": ["LONGER WIRE", "+10% wire reach. Connect to a more distant point."],
 "reel": ["FAST REEL", "+15% automatic reel speed while holding the mouse button."],
 "hook": ["FAST HOOK", "+20% hook speed. Recover sooner after firing."],
 "jump": ["HIGH JUMP", "+10% jump height for ground jumps, wall jumps, and double jumps alike."],
 "double_jump": ["DOUBLE JUMP", "Unlocks an extra air jump. Recharges in 10 / 7 / 5s as you level it up. Separate from jump height."],
}
static func xp_required(level: int) -> int:
 return roundi(180.0 * pow(1.25, mini(level - 1, 8)))
static func progress(previous: float, position_z: float, origin_offset: float) -> float:
 return maxf(previous, -position_z + origin_offset)
