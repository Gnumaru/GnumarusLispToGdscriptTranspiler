# GENERATED FROM Test2.gdl BY GNUMARUS - DO NOT EDIT
class_name OtherClass
extends Node
signal health_changed
signal moved(old_pos, new_pos)
var score: int = 100
var greeting: String = "hello packed world"
var pos: Vector2 = Vector2(1, 2)
var inferred := 42
static var instance_count: int = 0
const max_speed: float = 10.0
# hello world with spaces
# she said "hi" and left
func _process(delta): # runs every frame
	const frame_limit = 60
	var elapsed: float = 0.0
	pass
static func default_speed():
	return 10.0
