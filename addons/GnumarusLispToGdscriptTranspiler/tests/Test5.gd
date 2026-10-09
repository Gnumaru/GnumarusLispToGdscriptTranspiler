class_name InnerDemo
extends Node
var title: String = "demo"
class Item:
	extends RefCounted
	signal picked
	var label: String = "item"
	const kind = 1
	static var total: int = 0
	func describe():
		return label
	class Detail:
		var depth: int = 2
func get_item():
	return Item.new()
