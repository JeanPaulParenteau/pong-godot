## Per-difficulty tuning for the CPU opponent. One bot algorithm, three feels.

## Max paddle travel in world units per second. The bot rate-limits itself here,
## kept below the simulation's own paddle cap (GameConfig.PADDLE_SPEED) so the
## bot's limit is the binding one — the single biggest lever on how beatable it is.
var max_speed: float

## How often (seconds) the bot re-reads the ball and commits a new aim point.
## Larger = more sluggish/human reaction lag.
var react_delay: float

## Max vertical aim error (world units) applied when committing an aim point.
var aim_error: float

## If true, aim at the predicted wall-reflected intercept; if false, just chase
## the ball's current y (fooled by sharp angles).
var predict_intercept: bool


func _init(p_max_speed: float, p_react_delay: float, p_aim_error: float,
		p_predict_intercept: bool) -> void:
	max_speed = p_max_speed
	react_delay = p_react_delay
	aim_error = p_aim_error
	predict_intercept = p_predict_intercept


# Tuned against the current ball (BALL_BASE_SPEED 7, step 1.2, UNCAPPED — speed keeps
# climbing for as long as the rally lasts) and the capped player paddle (PADDLE_SPEED 16).
# The bot's max_speed (≤ 15, Hard) sits under the paddle cap, so a long rally eventually
# out-runs even Hard — that's intended: out-rallying the CPU is the reward. Easy/Medium keep
# pace early but fall behind sooner. aim_error stays <= PADDLE_HALF_HEIGHT
# (0.9) on every tier, and the committed aim is additionally edge-biased (PongBot.edge_safe_aim)
# so even the worst sample keeps the bot's intended contact on the front face — it concedes
# by being slow/late or fooled by angles, not by clipping its own paddle edge into a
# self-score (GameSession edge-clip physics).

static func easy():  # -> BotProfile
	return new(8.0, 0.20, 0.80, false)


static func medium():  # -> BotProfile
	return new(11.0, 0.10, 0.40, false)


static func hard():  # -> BotProfile
	return new(15.0, 0.05, 0.12, true)
