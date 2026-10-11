class_name PipeDemo
extends Node
func func1(x):
	return x
func func2(x, y):
	return x
func func3(x, y):
	return x
func func4(x, y):
	return x
func func5(x, y):
	return x
func demo(myval):
	var myres = myval
	myres = func1(myres)
	myres = func2(myres, 123)
	myres = func3(myres, 123)
	myres = func4(myres, 123)
	myres = func5(123, myres)
