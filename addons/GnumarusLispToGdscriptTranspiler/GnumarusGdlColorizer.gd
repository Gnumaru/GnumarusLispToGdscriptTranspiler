## Position-aware color model for Gnumarus Lisp source text.
##
## Scans whole documents in one pass (carrying paren depth and packed-string
## state across lines, like the tokenizer) and returns per-line color maps
## in the `{column: {"color": Color}}` shape the editor expects: rainbow
## parens by nesting depth (unbalanced closers in error red), indent blocks
## by width level (dimmed rainbow; visible with View Whitespace on),
## packed spans with the GDScript string color, numbers with the GDScript
## number color, `@` atoms with the GDScript annotation color, and bare
## atoms with the exact GDScript color of their word class (plain keywords,
## control-flow keywords kept separate, base types, engine classes, global
## functions and get/set), independent of context. Gnumarus-only operations
## fall back to the keyword color through the live transpiler table, so new
## operations never rot the highlighting. Theme colors arrive through
## configure (the highlighter impl feeds EditorSettings values); the
## GnumarusGdlTheme dark defaults apply headless and before the first sync.
## Pure data logic, fully testable without the editor.
class_name GnumarusGdlColorizer
extends RefCounted


## Transpiler script, loaded by path (live operation list only).
const TranspilerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTranspiler.gd")
## Theme script, loaded by path (word lists and fallback colors).
const ThemeScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlTheme.gd")
## Rainbow palette, one hue per nesting depth (cycles).
const RAINBOW_COLORS: Array = [
	Color(0.95, 0.35, 0.35),
	Color(0.95, 0.6, 0.25),
	Color(0.95, 0.85, 0.3),
	Color(0.45, 0.85, 0.45),
	Color(0.35, 0.75, 0.95),
	Color(0.7, 0.55, 0.95),
	Color(0.95, 0.5, 0.75),
]
## Packed-span delimiter codepoints: " ' ` ´.
const DELIMITER_CODES: Array = [34, 39, 96, 180]
## Unbalanced closer and lone "@" color (no editor setting exists for
## errors, so this red stays constant across themes).
const ERROR_COLOR: Color = Color(1.0, 0.25, 0.25)
## Indent darkening factor over the rainbow hues (lower is more visible;
## whitespace glyphs are thin, so this stays bright enough to read).
const INDENT_DARKEN: float = 0.25


## Active color per category name (synced from the theme, see configure).
var _colors: Dictionary = {}
## Gnumarus-only operation names (live transpiler table, keyword fallback).
var _gdl_ops: Dictionary = {}
## GDScript control-flow keywords for O(1) lookup.
var _control_flow: Dictionary = {}
## GDScript plain keywords for O(1) lookup.
var _keywords: Dictionary = {}
## get/set words for O(1) lookup (function color, like GDScript).
var _function_words: Dictionary = {}
## GDScript base types for O(1) lookup.
var _base_types: Dictionary = {}
## GDScript global functions for O(1) lookup.
var _global_functions: Dictionary = {}
## Gnumarus-only control-flow operations for O(1) lookup.
var _gdl_control_flow: Dictionary = {}
## Engine class names for O(1) lookup (live ClassDB list).
var _engine_types: Dictionary = {}
## Dimmed rainbow palette for indent blocks, same cycling.
var _indent_colors: Array = []


## Constructor: snapshots theme defaults, word tables, the live operation
## table and the engine class list, then derives the indent palette.
func _init() -> void:
	# Fallback colors (the impl overwrites them with EditorSettings values).
	_colors = ThemeScript.default_colors()
	# Gnumarus operations as keyword fallback (never rots when ops are added).
	var probe: RefCounted = TranspilerScript.new()
	for op in probe.operation_names():
		_gdl_ops[op] = true
	for word in ThemeScript.CONTROL_FLOW_KEYWORDS:
		_control_flow[word] = true
	for word in ThemeScript.KEYWORDS:
		_keywords[word] = true
	for word in ThemeScript.FUNCTION_WORDS:
		_function_words[word] = true
	for word in ThemeScript.BASE_TYPES:
		_base_types[word] = true
	for word in ThemeScript.GLOBAL_FUNCTIONS:
		_global_functions[word] = true
	for word in ThemeScript.GDL_CONTROL_FLOW_EXTRA:
		_gdl_control_flow[word] = true
	# Every engine class shares the engine-type color (live ClassDB query).
	for engine_class in ClassDB.get_class_list():
		_engine_types[engine_class] = true
	for hue in RAINBOW_COLORS:
		_indent_colors.append((hue as Color).darkened(INDENT_DARKEN))


## Replaces theme colors with editor values (category name -> Color).
## Unknown categories or non-Color values fail without applying anything.
## Returns {"ok": bool, "error": String}.
func configure(p_colors: Dictionary) -> Dictionary:
	# Pending colors validated before touching the active table.
	var pending: Dictionary = _colors.duplicate()
	for category in p_colors:
		if not ThemeScript.SETTING_KEYS.has(category):
			return {"ok": false, "error": "unknown color category: '%s'" % str(category)}
		if not (p_colors[category] is Color):
			return {"ok": false, "error": "color for '%s' must be a Color" % str(category)}
		pending[category] = p_colors[category]
	_colors = pending
	return {"ok": true, "error": ""}


## Returns the active color of one theme category (transparent when unknown).
func get_color(p_category: String) -> Color:
	if _colors.has(p_category):
		return _colors[p_category]
	return Color(0, 0, 0, 0)


## Hash of the active theme colors (lets the highlighter memo tell theme
## changes apart from text changes).
func theme_hash() -> int:
	# Category values in stable key order.
	var parts: Array = []
	for category in ThemeScript.SETTING_KEYS:
		parts.append(str(_colors.get(category, Color(0, 0, 0, 0))))
	return "".join(parts).hash()


## Names the word class of one bare atom ("" keeps the theme default).
## Order mirrors the GDScript highlighter: annotations, control flow,
## get/set functions, plain keywords, global functions, base types, engine
## types, Gnumarus-only operations (keyword fallback), then numbers.
func category_for_atom(p_word: String) -> String:
	# Lone "@" is an error like in the transpiler (handled by the caller).
	if p_word == "@":
		return "error"
	if p_word.begins_with("@"):
		return "annotation"
	if _control_flow.has(p_word) or _gdl_control_flow.has(p_word):
		return "control_flow"
	if _function_words.has(p_word):
		return "function"
	if _keywords.has(p_word):
		return "keyword"
	if _global_functions.has(p_word):
		return "global_function"
	if _base_types.has(p_word):
		return "base_type"
	if _engine_types.has(p_word):
		return "engine_type"
	if _gdl_ops.has(p_word):
		return "keyword"
	if p_word.is_valid_int() or p_word.is_valid_float():
		return "number"
	return ""


## Resolves the display color of one bare atom (transparent = default).
func color_for_atom(p_word: String) -> Color:
	# Category of the atom ("" means the theme default applies).
	var category: String = category_for_atom(p_word)
	if category.is_empty():
		return Color(0, 0, 0, 0)
	if category == "error":
		return ERROR_COLOR
	return get_color(category)


## Colors every line: Array of `{column: {"color": Color}}` Dictionaries.
## Depth, string state and closers carry across lines; bare atoms classify
## per line (backslash-newline continuations reclassify per segment).
func compute_all(p_lines: PackedStringArray) -> Array:
	# Per-line color maps in order.
	var maps: Array = []
	# Current paren nesting depth.
	var depth: int = 0
	# Whether the scanner is inside a packed span.
	var in_string: bool = false
	# Delimiter closing the current packed span (codepoint).
	var closing: int = 0
	# Active string color (synced from the theme).
	var string_color: Color = get_color("string")
	for li in range(p_lines.size()):
		# Current source line under coloring.
		var line: String = p_lines[li]
		# Color map of this line.
		var map: Dictionary = {}
		# Leading whitespace width (indent level of the line).
		var ws: int = 0
		while ws < line.length() and (line.unicode_at(ws) == 32 or line.unicode_at(ws) == 9):
			ws += 1
		if ws > 0:
			# Indent block color for this width level.
			var indent_color: Color = _indent_colors[ws % _indent_colors.size()]
			for c in range(ws):
				map[c] = {"color": indent_color}
		# Read position inside the line.
		var i: int = ws
		# Start column of the bare atom in progress (-1 = none).
		var atom_start: int = -1
		while i < line.length():
			# Unicode codepoint of the current character.
			var code: int = line.unicode_at(i)
			if in_string:
				if code == 92:
					# Escaped character inside the span (stays string).
					map[i] = {"color": string_color}
					if i + 1 < line.length():
						map[i + 1] = {"color": string_color}
						i += 2
					else:
						# Trailing backslash escapes the newline: span continues.
						i += 1
					continue
				map[i] = {"color": string_color}
				if code == closing:
					in_string = false
				i += 1
				continue
			if code == 32 or code == 9 or code == 10 or code == 13:
				_paint_atom(map, line, atom_start, i)
				atom_start = -1
				i += 1
				continue
			if code == 40:
				_paint_atom(map, line, atom_start, i)
				atom_start = -1
				map[i] = {"color": _rainbow(depth)}
				depth += 1
				i += 1
				continue
			if code == 41:
				_paint_atom(map, line, atom_start, i)
				atom_start = -1
				if depth > 0:
					depth -= 1
					map[i] = {"color": _rainbow(depth)}
				else:
					map[i] = {"color": ERROR_COLOR}
				i += 1
				continue
			if code == 92:
				# Escaped character joins the atom (never structural).
				if atom_start < 0:
					atom_start = i
				i += 2 if i + 1 < line.length() else 1
				continue
			if code in DELIMITER_CODES:
				_paint_atom(map, line, atom_start, i)
				atom_start = -1
				in_string = true
				closing = code
				map[i] = {"color": string_color}
				i += 1
				continue
			if atom_start < 0:
				atom_start = i
			i += 1
		_paint_atom(map, line, atom_start, line.length())
		maps.append(map)
	return maps


## Rainbow color for a nesting depth (cycles through the palette).
func _rainbow(p_depth: int) -> Color:
	return RAINBOW_COLORS[p_depth % RAINBOW_COLORS.size()]


## Classifies one bare atom range [p_start, p_end) inside its line.
## No-op for empty ranges and for theme-default words.
func _paint_atom(p_map: Dictionary, p_line: String, p_start: int, p_end: int) -> void:
	if p_start < 0 or p_end <= p_start:
		return
	# Raw atom text of the range.
	var text: String = p_line.substr(p_start, p_end - p_start)
	# Display color, transparent when the theme default applies.
	var color: Color = color_for_atom(text)
	if color == Color(0, 0, 0, 0):
		return
	for c in range(p_start, p_end):
		p_map[c] = {"color": color}
