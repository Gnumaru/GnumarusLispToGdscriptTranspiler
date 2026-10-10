## Real implementation behind the GnumarusGdlHighlighter editor proxy.
##
## Owns the GnumarusGdlColorizer, syncs its theme colors from the editor
## settings (so `.gdl` sources follow the user's GDScript colors, including
## custom themes) and memoizes per-line color maps by document hash plus
## theme hash (theme edits recompute even when the text is unchanged).
## Editor calls go through the proxy (kept from the constructor); the color
## engine itself stays headless-safe (null proxy yields empty maps).
class_name GnumarusGdlHighlighterImpl
extends RefCounted


## Colorizer script, loaded by path.
const ColorizerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlColorizer.gd")
## Theme script, loaded by path (setting keys).
const ThemeScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlTheme.gd")


## Proxy owning this implementation (editor calls go through it).
var _proxy: Object
## Stateless color engine (shared by every line query).
var _colorizer: RefCounted
## Document hash of the memoized color maps (-1 = nothing cached).
var _cache_hash: int = -1
## Theme hash of the memoized color maps (-1 = theme changed).
var _cache_theme: int = -1
## Memoized per-line color maps for the cached document.
var _cache_maps: Array = []
## Whether the theme-change signal is already connected (editor only).
var _theme_connected: bool = false


## Constructor: stores the proxy reference and builds the color engine.
func _init(p_proxy: Object) -> void:
	_proxy = p_proxy
	_colorizer = ColorizerScript.new()


## Display name shown in the editor highlighter menu.
func _get_name() -> String:
	return "Gnumarus"


## Extensions auto-selecting this highlighter (matched against the file
## extension for non-script resources like plain-text `.gdl`).
func _get_supported_languages() -> PackedStringArray:
	return PackedStringArray(["gdl"])


## Colors one line for the editor (empty without an attached TextEdit,
## which also keeps headless use safe). Memoizes per document hash.
func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
	# Hosting text editor (null outside the editor or without a proxy).
	var te: TextEdit = _proxy_text_edit()
	if te == null:
		return {}
	if p_line < 0 or p_line >= te.get_line_count():
		return {}
	_ensure_cache(te)
	if p_line < _cache_maps.size():
		return _cache_maps[p_line]
	return {}


## Recomputes the memo when the document text or the theme moved.
func _ensure_cache(p_te: TextEdit) -> void:
	# Theme values in place before hashing (cheap no-op when unchanged).
	sync_theme()
	# Hash of the current document text.
	var h: int = p_te.get_text().hash()
	# Hash of the active theme colors.
	var t: int = _colorizer.theme_hash()
	if h == _cache_hash and t == _cache_theme:
		return
	_cache_hash = h
	_cache_theme = t
	# Exact line list (avoids split/count mismatches on trailing newlines).
	var lines := PackedStringArray()
	for i in range(p_te.get_line_count()):
		lines.append(p_te.get_line(i))
	_cache_maps = _colorizer.compute_all(lines)


## Reads the editor theme colors into the colorizer (no-op headless or
## without editor settings; keeps the dark-theme fallbacks then).
func sync_theme() -> void:
	# Editor settings singleton (null outside the editor).
	var settings: EditorSettings = _editor_settings()
	if settings == null:
		return
	_connect_theme_signal(settings)
	# Theme colors keyed by category name.
	var colors: Dictionary = {}
	for category in ThemeScript.SETTING_KEYS:
		# Setting key holding the category color.
		var key: String = ThemeScript.SETTING_KEYS[category]
		if not settings.has_setting(key):
			continue
		# Stored value, expected to be a Color.
		var value = settings.get_setting(key)
		if value is Color:
			colors[category] = value
	if not colors.is_empty():
		_colorizer.configure(colors)


## Returns the hosting TextEdit through the proxy (null without a proxy).
func _proxy_text_edit() -> TextEdit:
	if _proxy == null or not is_instance_valid(_proxy):
		return null
	if not _proxy.has_method("get_text_edit"):
		return null
	return _proxy.get_text_edit() as TextEdit


## Returns the editor settings singleton (null outside the editor).
func _editor_settings() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()


## Watches theme edits so cached maps recompute on the next line query.
func _connect_theme_signal(p_settings: EditorSettings) -> void:
	if _theme_connected:
		return
	_theme_connected = true
	if not p_settings.is_connected("settings_changed", Callable(self, "_on_settings_changed")):
		p_settings.settings_changed.connect(Callable(self, "_on_settings_changed"))


## Drops the theme stamp on any settings edit (forces a recompute).
func _on_settings_changed() -> void:
	_cache_theme = -1
