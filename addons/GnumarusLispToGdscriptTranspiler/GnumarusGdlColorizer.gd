## Position-aware color model for Gnumarus Lisp source text.
##
## Scans whole documents in one pass (carrying paren depth and packed-string
## state across lines, like the tokenizer) and returns per-line color maps
## in the `{column: {"color": Color}}` shape the editor expects: rainbow
## parens by nesting depth (unbalanced closers in error red), indent blocks
## by width level (dimmed rainbow; visible with View Whitespace on),
## packed spans as strings, operation names as keywords (live list from the
## transpiler table, never rotten), `@` atoms as annotations and
## integer/float atoms as numbers. Bare atoms keep the theme default.
## Pure data logic, fully testable without the editor.
class_name GnumarusGdlColorizer
extends RefCounted


## Transpiler script, loaded by path (live keyword list only).
const TranspilerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTranspiler.gd")
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
## String span color.
const STRING_COLOR: Color = Color(0.6, 0.85, 0.55)
## Operation keyword color.
const KEYWORD_COLOR: Color = Color(0.4, 0.7, 1.0)
## Annotation (@...) atom color.
const ANNOTATION_COLOR: Color = Color(1.0, 0.65, 0.3)
## Number-like atom color.
const NUMBER_COLOR: Color = Color(0.75, 0.9, 0.6)
## Unbalanced closer and lone "@" color.
const ERROR_COLOR: Color = Color(1.0, 0.25, 0.25)
## Indent darkening factor over the rainbow hues.
const INDENT_DARKEN: float = 0.6


## Operation names for keyword classification (live transpiler table).
var _keywords: Dictionary = {}
## Dimmed rainbow palette for indent blocks, same cycling.
var _indent_colors: Array = []


## Constructor: snapshots the transpiler operations and derives indents.
func _init() -> void:
	# Live operation table (never rots when operations are added).
	var probe: RefCounted = TranspilerScript.new()
	for op in probe.operation_names():
		_keywords[op] = true
	for hue in RAINBOW_COLORS:
		_indent_colors.append((hue as Color).darkened(INDENT_DARKEN))


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
					map[i] = {"color": STRING_COLOR}
					if i + 1 < line.length():
						map[i + 1] = {"color": STRING_COLOR}
						i += 2
					else:
						# Trailing backslash escapes the newline: span continues.
						i += 1
					continue
				map[i] = {"color": STRING_COLOR}
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
				map[i] = {"color": STRING_COLOR}
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
## No-op for empty ranges; lone "@" is an error like in the transpiler.
func _paint_atom(p_map: Dictionary, p_line: String, p_start: int, p_end: int) -> void:
	if p_start < 0 or p_end <= p_start:
		return
	# Raw atom text of the range.
	var text: String = p_line.substr(p_start, p_end - p_start)
	# Chosen color, empty when the theme default applies.
	var color: Color = Color(0, 0, 0, 0)
	if text == "@":
		color = ERROR_COLOR
	elif text.begins_with("@"):
		color = ANNOTATION_COLOR
	elif _keywords.has(text):
		color = KEYWORD_COLOR
	elif text.is_valid_int() or text.is_valid_float():
		color = NUMBER_COLOR
	else:
		return
	for c in range(p_start, p_end):
		p_map[c] = {"color": color}
