class_name MacroDemo
extends Node
func greet(name):
	if name and name.has_method("greet"):
		name.greet("hi")
	if not (name == ""):
		print(name)
	pass
func silent(node):
	if node and node.has_method("stop"):
		node.stop()
	pass
