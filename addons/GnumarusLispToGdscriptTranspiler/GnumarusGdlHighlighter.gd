## Dumb editor proxy for the Gnumarus `.gdl` syntax highlighter.
##
## Per the addon rule, this class holds no logic: it instantiates
## GnumarusGdlHighlighterImpl in _init (passing itself) and every function
## below only delegates to the identically-named implementation method.
## The single exception is _create: the engine requires an
## EditorSyntaxHighlighter instance and the RefCounted implementation cannot
## satisfy that return type, so the one-line factory lives here.
@tool
class_name GnumarusGdlHighlighter
extends EditorSyntaxHighlighter


## Implementation script, loaded by path.
const ImplScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlHighlighterImpl.gd")


## Real implementation (built in _init, kept alive by this reference).
var _impl: RefCounted


## Constructor: builds the implementation with a reference to this proxy.
func _init() -> void:
	_impl = ImplScript.new(self)


## Display name shown in the editor highlighter menu (delegated).
func _get_name() -> String:
	return _impl._get_name()


## Extensions auto-selecting this highlighter (delegated).
func _get_supported_languages() -> PackedStringArray:
	return _impl._get_supported_languages()


## Per-editor instance factory (must return an EditorSyntaxHighlighter,
## which the RefCounted implementation cannot construct).
func _create() -> EditorSyntaxHighlighter:
	return GnumarusGdlHighlighter.new()


## Colors one line for the editor (delegated).
func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
	return _impl._get_line_syntax_highlighting(p_line)
