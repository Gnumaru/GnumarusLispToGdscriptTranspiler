# GENERATED FROM Test4.gdl BY GNUMARUS - DO NOT EDIT
class_name MatchDemo
extends Node
func describe(x):
	match x:
		1:
			return "one"
		2, 3:
			return "few"
		[var a, var b]:
			return a
		{"name": var n}:
			return n
		_:
			return "other"
func nested(v):
	match v:
		_:
			match v:
				0:
					return 0
				_:
					return -1
