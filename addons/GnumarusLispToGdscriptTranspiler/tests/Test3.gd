class_name FlowDemo
extends Node
func check(x):
	if x > 0:
		return 1
	elif x < 0:
		return -1
	else:
		return 0
func first_positive(items):
	for item in items:
		if item < 0:
			continue
		if item > 100:
			break
		return item
	return -1
func drain(items):
	while items.size() > 0:
		if items[0] < 0:
			return "empty"
		return items[0]
	return "done"
func first_int(items):
	for n: int in items:
		return n
	return -1
