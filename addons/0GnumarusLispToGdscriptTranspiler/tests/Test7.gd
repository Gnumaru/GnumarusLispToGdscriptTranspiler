class_name UnpackDemo
extends Node
func demo(myarr, other):
	var a
	var b
	var c: int
	var d = 5
	var e := 6
	var f: float = 0.5
	var myarr_size_0 = myarr.size()
	var myarr_tmp_0
	if myarr_size_0 > 0:
		a = myarr[0]
	if myarr_size_0 > 1:
		b = myarr[1]
	if myarr_size_0 > 2:
		myarr_tmp_0 = myarr[2]
		if is_instance_of(myarr_tmp_0, TYPE_INT):
			c = myarr_tmp_0
	if myarr_size_0 > 3:
		d = myarr[3]
	if myarr_size_0 > 4:
		e = myarr[4]
	if myarr_size_0 > 5:
		myarr_tmp_0 = myarr[5]
		if is_instance_of(myarr_tmp_0, TYPE_FLOAT):
			f = myarr_tmp_0
	var x
	var other_size_1 = other.size()
	if other_size_1 > 0:
		x = other[0]
