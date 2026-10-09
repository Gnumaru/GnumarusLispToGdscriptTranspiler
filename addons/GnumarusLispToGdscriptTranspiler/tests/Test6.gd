class_name LambdaDemo
extends Node
var handler = func(msg):
	return msg
func run():
	var local_cb = func(x):
		return x
	return local_cb
func make_greeter():
	return func(name): # hello
		return name
