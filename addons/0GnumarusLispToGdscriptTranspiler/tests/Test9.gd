class_name UnpackDictDemo
extends Node
func demo(mydict, other):
	var a
	var b
	var c: int
	var d: float = 0.0
	var mydict_tmp_0
	if mydict:
		if 'id' in mydict:
			a = mydict['id']
		if 'tags' in mydict:
			b = mydict['tags']
		if 'age' in mydict:
			mydict_tmp_0 = mydict['age']
			if is_instance_of(mydict_tmp_0, TYPE_INT):
				c = mydict_tmp_0
		if 'score' in mydict:
			mydict_tmp_0 = mydict['score']
			if is_instance_of(mydict_tmp_0, TYPE_FLOAT):
				d = mydict_tmp_0
	var x
	if other:
		if 'x' in other:
			x = other['x']
