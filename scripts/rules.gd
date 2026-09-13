extends RefCounted
## Central tuning values. All numbers are prototype hypotheses.
const GRAVITY: float = 20.0
const RUN_SPEED: float = 6.0
const JUMP_SPEED: float = 10.95
const MAX_SPEED: float = 35.0
const HOOK_SPEED: float = 80.0
const ROPE_RANGE: float = 30.0
const REEL_SPEED: float = 5.0
const BASE_ANCHOR_HEIGHT: float = 16.0
const SLIDE_MIN_SPEED: float = 0.5
const SLIDE_SECONDS: Array[float] = [0.0, 2.0, 3.5, 5.0]
const LAUNCH_SPEEDS: Array[float] = [0.0, 28.0, 32.0, 35.0]
const LAUNCH_SECONDS: float = 0.65
const RESUME_PROTECTION: float = 2.0
const CAMERA_OFFSET := Vector3(0, 2.2, 6.0)
const HIGH_ANCHORS: Array[float] = [0.0, 4.0, 7.0, 10.0]
const UPGRADES: Dictionary = {
 "skates": ["ROLLER SKATES", "Keep landing speed for 2 / 3.5 / 5 seconds. No release timing needed."],
 "launcher": ["TWIN LAUNCH", "E: dash toward the midpoint of two anchors, invulnerable. 10s cooldown."],
 "armor": ["IMPACT ARMOR", "Survive one more hard collision. Refills one charge."],
 "high": ["HIGH NETWORK", "Future blocks gain optional higher anchors. Low routes stay."],
 "range": ["LONGER WIRE", "+10% wire reach. Connect to a more distant anchor."],
 "reel": ["FAST REEL", "+15% automatic reel speed while holding the mouse button."],
 "hook": ["FAST HOOK", "+20% hook speed. Recover sooner after firing."],
 "jump": ["HIGH JUMP", "+10% jump height. More room to reconnect."],
}

static func xp_required(level: int) -> int:
 return roundi(180.0 * pow(1.25, mini(level - 1, 8)))

static func progress(previous: float, position_z: float, origin_offset: float) -> float:
 return maxf(previous, -position_z + origin_offset)

static func floor_outcome(speed: float, skates: int, armed: bool) -> String:
 if skates > 0 and speed >= SLIDE_MIN_SPEED and armed:
  return "slide"
 return "ground"
