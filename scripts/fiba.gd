extends RefCounted
## FIBA dimensions in metres. Court is centred at the origin, long axis along Z.

const COURT_WIDTH = 15.0
const COURT_LENGTH = 28.0
const LINE_WIDTH = 0.05

const RIM_HEIGHT = 3.05            # top edge of the ring
const RIM_RADIUS = 0.225           # inner radius (diameter 45 cm)
const RIM_TUBE = 0.0095            # ring bar radius (diameter 19 mm)
const RIM_FROM_ENDLINE = 1.575     # ring centre projected onto the floor
const BOARD_TO_RIM = 0.151         # board face to the nearest inner edge of the ring
const BOARD_SIZE = Vector2(1.80, 1.05)
const BOARD_BOTTOM = 2.90
const BOARD_THICKNESS = 0.03
const TARGET_SIZE = Vector2(0.59, 0.45)
const NET_LENGTH = 0.42

const THREE_POINT_RADIUS = 6.75    # to the outer edge of the line
const THREE_POINT_SIDE = 0.90      # straight part distance from the sideline
const KEY_WIDTH = 4.90
const FREE_THROW_DISTANCE = 5.80   # endline to the far edge of the free-throw line
const CIRCLE_RADIUS = 1.80
const NO_CHARGE_RADIUS = 1.25

const BALL_RADIUS = 0.12           # size 7, circumference ~75 cm
const BALL_MASS = 0.60


## end_sign = -1 for the main hoop (negative Z), +1 for the opposite one.
static func rim_center(end_sign: float) -> Vector3:
	return Vector3(0.0, RIM_HEIGHT, end_sign * (COURT_LENGTH * 0.5 - RIM_FROM_ENDLINE))


static func is_three_point_spot(foot: Vector3, rim: Vector3) -> bool:
	var dx := foot.x - rim.x
	var dz := foot.z - rim.z
	if Vector2(dx, dz).length() > THREE_POINT_RADIUS:
		return true
	var corner_x := COURT_WIDTH * 0.5 - THREE_POINT_SIDE
	var toward_endline := signf(rim.z) * dz > 0.0
	var corner_depth := sqrt(THREE_POINT_RADIUS * THREE_POINT_RADIUS - corner_x * corner_x)
	return absf(foot.x) > corner_x and (toward_endline or absf(dz) < corner_depth)
