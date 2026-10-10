@tool
class_name StressTest
extends Node
signal health_changed
signal moved(old_pos, new_pos)
signal tagged(tag: String)
var plain
var typed: int
var defaulted = 5
var inferred := 42
var full: float = 0.5
var text: String = "packed double"
var text2: String = 'packed double'
var text3: String = "packed double"
var text4: String = "packed double"
var direction: Vector2 = Vector2(1, 2)
var callback = func(msg):
	return msg
static var instance_count: int = 0
static var lazy := "hello"
const max_lives = 3
const gravity: float = 9.8
const inferred_const := "const-infer"
var _health: int = 100
var health: int = 100:
	get:
		return _health
	set(value):
		pass
@export_range(0, 100)
var max_hp: int = 100
@rpc("any_peer")
func sync_hp(value):
	_health = value
# section: inner classes
class Item:
	extends RefCounted
	signal picked(item)
	var label: String = "item"
	const kind = 1
	static var total: int = 0
	func describe():
		return label
	func use():
		const local_kind = 2
		if local_kind > 0:
			return true
		else:
			return false
	class Detail:
		var depth: int = 1
# section: flow control
func classify(x): # classifier
	if x > 0:
		return 1
	elif x == 0:
		return 0
	elif x == -1:
		return -1
	else:
		return -99
func loop_demo(items):
	var total: int = 0
	for item in items:
		if item < 0:
			continue
		if item > 100:
			break
		while total < 0:
			break
	for n: int in items:
		match n:
			0:
				return 0
			1, 2:
				return 1
			[var a, var b]:
				return a
			{"name": var who}:
				return who
			_:
				continue
	return total
func make_adder():
	return func(x): # adder
		return x
static func version():
	return "1.0"
func noop():
	pass
func convert(amount: float = 1.0, ...rest) -> Variant:
	return 1.0
static func typed_id(value) -> int:
	return 1
func sum_all(...nums):
	pass
var counter: int = 0
func bump(step):
	counter += step
	print(counter)
	return counter
func compute(x):
	return x + (2 * 3)
func pick(a, b):
	return (a == b) and (not debug_mode)
func negate(x):
	return -x
func neg_sum(a, b):
	return -(a + b)
func find_first(items, target):
	for item in items:
		if item == target:
			return item
	return -1
func safe_greet(node):
	if node and node.has_method("greet"):
		node.greet("hi")
	pass
var FLAG_READY = true
var slot_0: int = 0
var slot_1: int = 0
var slot_2: int = 0
func debug_dump():
	print("debug")
	pass
var debug_mode = false
var inventory = [
	1,
	"sword",
	false,
]
var stats = {
	hp = 100,
	name = "hero",
}
var by_id = {
	Vector2(1, 2): 1,
}
var shelves = [
	1,
	[
		2,
		3,
	],
	{
		a = 1,
	},
]
var app_name: String = "app": get = get_app_name
func get_app_name():
	return app_name
enum State {
	IDLE,
	RUNNING = 1,
	STOPPED,
}
func bit_ops(a, b):
	return (a << 1) | (b & 7)
func bit_not(v):
	return ~v
func check_kind(x):
	return x is Node
func has_item(arr, x):
	return x in arr
func wait_hp():
	await health_changed
	assert(true)
	breakpoint
	pass
func pick_or(c, a, b):
	return a if c else b
@abstract
class Shape:
	@abstract
	func area(x)
# multi atom join
# grave packed
# acute packed
# a "quoted" word
func chain_demo(o):
	var r = o.qwer(0).asdf(1)
	print(r)
	return o.zx(2).tail
