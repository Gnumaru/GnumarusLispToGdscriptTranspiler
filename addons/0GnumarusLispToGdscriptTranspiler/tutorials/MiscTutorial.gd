# GENERATED FROM MiscTutorial.gdl BY GNUMARUS - DO NOT EDIT
class_name MyMiscTutorialClass
extends Node
# BEGIN include MiscTutorialInc.gdl (res://addons/0GnumarusLispToGdscriptTranspiler/tutorials/MiscTutorialInc.gdl)
class MyInnerClass:
	extends RefCounted
	var prop
# END include MiscTutorialInc.gdl (res://addons/0GnumarusLispToGdscriptTranspiler/tutorials/MiscTutorialInc.gdl)
# this will generate a comment in gdscript
# this will also generate a comment in gdscript, but the quotes are discarded
# 'this will also generate a comment in gdscript, but the quotes are kept'
enum MyEnumName {
	member_0,
	member_1 = 1,
}
enum {
	my_anonym_enum_member_0,
	my_anonym_enum_member_1,
}
const my_const_0: float = 9.0
const my_const_1 := true
static var my_stat_var_0
static var my_stat_var_1: int
static var my_stat_var_2: float = 9.0
static var my_stat_var_3 := true
var my_var_0
var my_var_1: int
var my_var_2: float = 9.0
var my_var_3 := true
@export
var my_export_var_0: int
@export
var my_export_var_1: float = 9.0
@export
var my_export_var_2 := true
@export
var my_export_var_3: float = 9.0
@onready
var my_onreadyexport_var_0: Node = %node
@onready
var my_onreadyexport_var_1 := $node
@onready
var my_onreadyexport_var_2 := $path/to/my/node
var my_prop_0: int = 0:
	get:
		return my_prop_0
	set(p):
		my_prop_0 = p
var my_prop_1:
	get:
		return my_prop_0
	set(p):
		my_prop_0 = p
func my_func(a: int) -> void:
	var b: int = 1
	b += 1
	b = 1 + 2 + 3 + 4
