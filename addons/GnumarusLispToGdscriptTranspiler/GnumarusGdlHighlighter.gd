## Gnumarus syntax highlighter for `.gdl` sources in the Godot editor.
##
## Registered with the script editor by the addon (auto-selected for the
## `gdl` extension): rainbow parens, indent levels, strings, keywords,
## annotations and numbers via GnumarusGdlColorizer. Thin by design —
## per-line results memoize per document hash, so full scans run once per
## text state and line queries stay O(segments). Reopened files pick it up
## automatically; files opened before registration need a reopen.
@tool
class_name GnumarusGdlHighlighter
extends EditorSyntaxHighlighter


## Colorizer script, loaded by path.
const ColorizerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlColorizer.gd")


## Stateless color engine (built in _init, shared by every line query).
var _colorizer: RefCounted
## Document hash of the memoized color maps (-1 = nothing cached).
var _cache_hash: int = -1
## Memoized per-line color maps for the cached document.
var _cache_maps: Array = []


## Constructor: builds the shared colorizer.
func _init() -> void:
	_colorizer = ColorizerScript.new()


## Display name shown in the editor highlighter menu.
func _get_name() -> String:
	return "Gnumarus"


## Extensions auto-selecting this highlighter (matched against the file
## extension for non-script resources like plain-text `.gdl`).
func _get_supported_languages() -> PackedStringArray:
	return PackedStringArray(["gdl"])


## Per-editor instance factory (the editor clones one copy per open file).
func _create() -> EditorSyntaxHighlighter:
	return GnumarusGdlHighlighter.new()


## Colors one line for the editor (empty without an attached TextEdit,
## which also keeps headless use safe). Memoizes per document hash.
func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
	# Hosting text editor (null outside the editor).
	var te: TextEdit = get_text_edit()
	if te == null:
		return {}
	if p_line < 0 or p_line >= te.get_line_count():
		return {}
	_ensure_cache(te)
	if p_line < _cache_maps.size():
		return _cache_maps[p_line]
	return {}


## Recomputes the memo when the document text moved, else reuses it.
func _ensure_cache(p_te: TextEdit) -> void:
	# Hash of the current document text.
	var h: int = p_te.get_text().hash()
	if h == _cache_hash:
		return
	_cache_hash = h
	# Exact line list (avoids split/count mismatches on trailing newlines).
	var lines := PackedStringArray()
	for i in range(p_te.get_line_count()):
		lines.append(p_te.get_line(i))
	_cache_maps = _colorizer.compute_all(lines)
