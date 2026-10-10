## Frozen GDScript theme data for Gnumarus Lisp highlighting.
##
## Holds the exact word lists and default colors the Godot editor uses for
## GDScript (extracted from the 4.7.2 sources), so `.gdl` atoms can reuse the
## same colors without any context: each known word always maps to the same
## color. Dynamic per-user values arrive later through
## GnumarusGdlColorizer.configure (fed by the highlighter impl from
## EditorSettings); the constants below are only the dark-theme fallbacks used
## headless and before the first editor sync. Pure data, fully testable.
class_name GnumarusGdlTheme
extends RefCounted


## Setting key per color category (EditorSettings text_editor theme keys).
const SETTING_KEYS: Dictionary = {
	"keyword": "text_editor/theme/highlighting/keyword_color",
	"control_flow": "text_editor/theme/highlighting/control_flow_keyword_color",
	"base_type": "text_editor/theme/highlighting/base_type_color",
	"engine_type": "text_editor/theme/highlighting/engine_type_color",
	"string": "text_editor/theme/highlighting/string_color",
	"number": "text_editor/theme/highlighting/number_color",
	"annotation": "text_editor/theme/highlighting/gdscript/annotation_color",
	"global_function": "text_editor/theme/highlighting/gdscript/global_function_color",
	"function": "text_editor/theme/highlighting/function_color",
	"comment": "text_editor/theme/highlighting/comment_color",
}
## Dark-theme fallback color per category (editor_settings.cpp defaults).
const DEFAULT_COLORS: Dictionary = {
	"keyword": Color(1.0, 1.0, 0.7),
	"control_flow": Color(1.0, 0.85, 0.7),
	"base_type": Color(0.64, 1.0, 0.83),
	"engine_type": Color(0.51, 0.83, 1.0),
	"string": Color(0.94, 0.43, 0.75),
	"number": Color(0.92, 0.58, 0.2),
	"annotation": Color(1.0, 0.7, 0.45),
	"global_function": Color(0.64, 0.64, 0.96),
	"function": Color(0.4, 0.64, 0.81),
	"comment": Color(0.4, 0.4, 0.4),
}
## GDScript control-flow keywords (is_control_flow_keyword in gdscript.cpp).
const CONTROL_FLOW_KEYWORDS: Array = [
	"break", "continue", "elif", "else", "for", "if", "match", "pass",
	"return", "when", "while",
]
## Remaining GDScript reserved words (get_reserved_words minus control flow,
## minus assert/preload which use the global-function color, minus void which
## uses the type color).
const KEYWORDS: Array = [
	"and", "as", "await", "breakpoint", "class", "class_name", "const",
	"enum", "extends", "false", "func", "in", "is", "namespace", "not",
	"null", "or", "self", "signal", "static", "super", "trait", "true",
	"var", "yield",
	"INF", "NAN", "PI", "TAU",
]
## GDScript base types (core type words plus bool/int/float/void/Variant).
const BASE_TYPES: Array = [
	"AABB", "Array", "Basis", "Callable", "Color", "Dictionary", "Plane",
	"Projection", "Quaternion", "RID", "Rect2", "Rect2i", "Signal",
	"String", "StringName", "Transform2D", "Transform3D", "Vector2",
	"Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "NodePath",
	"PackedByteArray", "PackedColorArray", "PackedFloat32Array",
	"PackedFloat64Array", "PackedInt32Array", "PackedInt64Array",
	"PackedStringArray", "PackedVector2Array", "PackedVector3Array",
	"PackedVector4Array",
	"bool", "float", "int", "void", "Variant",
]
## Words the GDScript highlighter paints with the function color.
const FUNCTION_WORDS: Array = ["get", "set"]
## Gnumarus-only operations that behave like control flow in GDScript.
const GDL_CONTROL_FLOW_EXTRA: Array = ["branch", "for-generate", "when-not"]
## Global functions (assert/preload plus GDScript and Variant utilities).
const GLOBAL_FUNCTIONS: Array = [
	"Color8", "_char", "abs", "absf", "absi", "acos", "acosh",
	"angle_difference", "asin", "asinh", "assert", "atan", "atan2", "atanh",
	"bezier_derivative", "bezier_interpolate", "bytes_to_var",
	"bytes_to_var_with_objects", "ceil", "ceilf", "ceili", "char", "clamp",
	"clampf", "clampi", "convert", "cos", "cosh", "cubic_interpolate",
	"cubic_interpolate_angle", "cubic_interpolate_angle_in_time",
	"cubic_interpolate_in_time", "db_to_linear", "deg_to_rad",
	"dict_to_inst", "ease", "error_string", "exp", "floor", "floorf",
	"floori", "fmod", "fposmod", "get_stack", "hash", "inst_to_dict",
	"instance_from_id", "inverse_lerp", "is_equal_approx", "is_finite",
	"is_inf", "is_instance_id_valid", "is_instance_of", "is_instance_valid",
	"is_nan", "is_same", "is_zero_approx", "len", "lerp", "lerp_angle",
	"lerpf", "linear_to_db", "load", "log", "max", "maxf", "maxi", "min",
	"minf", "mini", "move_toward", "nearest_po2", "ord", "pingpong",
	"posmod", "pow", "preload", "print", "print_debug", "print_rich",
	"print_stack", "print_verbose", "printerr", "printraw", "prints",
	"printt", "push_error", "push_warning", "rad_to_deg", "rand_from_seed",
	"randf", "randf_range", "randfn", "randi", "randi_range", "randomize",
	"range", "remap", "rid_allocate_id", "rid_from_int64", "rotate_toward",
	"round", "roundf", "roundi", "seed", "sign", "signf", "signi", "sin",
	"sinh", "smoothstep", "snapped", "snappedf", "snappedi", "sqrt",
	"step_decimals", "str", "str_to_var", "tan", "tanh", "type_convert",
	"type_exists", "type_string", "typeof", "var_to_bytes",
	"var_to_bytes_with_objects", "var_to_str", "weakref", "wrap", "wrapf",
	"wrapi",
]


## Returns a copy of the fallback colors (category name -> Color).
static func default_colors() -> Dictionary:
	return DEFAULT_COLORS.duplicate()
