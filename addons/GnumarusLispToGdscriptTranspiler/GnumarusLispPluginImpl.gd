## Real implementation behind the GnumarusLispPlugin editor proxy.
##
## Watches `.gdl` files and transpiles them to sibling `.gd` files (same
## directory, never `.godot/imported`): on editor start it connects to the
## filesystem `filesystem_changed` signal, and the Project menu gains a
## manual "Transpile Gnumarus files" item. Only changed sources transpile
## (session stamps, no clock reads), outputs are only rewritten when content
## differs, failures are reported with push_error and retried only after the
## source changes again. Deleted sources leave their orphan `.gd` behind.
## Editor calls go through the proxy (kept from the constructor); the
## transpile core takes explicit paths and is fully testable headless.
class_name GnumarusLispPluginImpl
extends RefCounted


## Facade script, loaded by path (avoids the global class cache).
const FacadeScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusLisp.gd")
## Highlighter script, loaded by path (registered with the script editor).
const HighlighterScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlHighlighter.gd")
## Editor setting holding the comma-separated text file extensions.
const TEXTFILE_EXTENSIONS_SETTING: String = "docks/filesystem/textfile_extensions"
## Project tool menu item name for manual transpilation.
const TOOL_MENU_NAME: String = "Transpile Gnumarus files"
## Project path holding the addon self-test fixtures (never watcher
## inputs: its `.gd` files are expected test outputs, not build artifacts,
## so saving a `.gdl` while hacking the addon cannot stamp them).
const ADDON_TESTS_ROOT: String = "res://addons/GnumarusLispToGdscriptTranspiler/tests"
## First line stamped on generated files (source name appended).
const GENERATED_STAMP: String = "# GENERATED FROM %s BY GNUMARUS - DO NOT EDIT"


## Proxy owning this implementation (editor calls go through it).
var _proxy: Object
## Whether the editor wiring is active (enter/exit guard).
var _entered: bool = false
## Registered Gnumarus highlighter (kept alive while registered).
var _highlighter: RefCounted = null
## Sibling outputs already generated: dst path -> source content hash.
var _done_stamp: Dictionary = {}
## Failed sources already reported: src path -> source content hash (no spam).
var _failed_stamp: Dictionary = {}


## Constructor: stores the proxy reference.
func _init(p_proxy: Object) -> void:
	_proxy = p_proxy


## Wires the editor: text extension, filesystem watch and tool menu item.
func _enter_tree() -> void:
	if _entered:
		return
	_entered = true
	_ensure_textfile_extension()
	# Filesystem watcher for automatic sidecar generation.
	var filesystem: EditorFileSystem = _proxy.get_editor_interface().get_resource_filesystem()
	if not filesystem.is_connected("filesystem_changed", Callable(self, "_on_filesystem_changed")):
		filesystem.filesystem_changed.connect(Callable(self, "_on_filesystem_changed"))
	_proxy.add_tool_menu_item(TOOL_MENU_NAME, Callable(self, "transpile_all"))
	# Gnumarus highlighter for `.gdl` sources (auto-selected by extension;
	# files opened before registration need a reopen to pick it up).
	_highlighter = HighlighterScript.new()
	_proxy.get_editor_interface().get_script_editor().register_syntax_highlighter(_highlighter)


## Unwires the editor: watch, menu item and wiring flag.
func _exit_tree() -> void:
	if not _entered:
		return
	_entered = false
	# Filesystem watcher disconnected when present.
	var filesystem: EditorFileSystem = _proxy.get_editor_interface().get_resource_filesystem()
	if filesystem.is_connected("filesystem_changed", Callable(self, "_on_filesystem_changed")):
		filesystem.filesystem_changed.disconnect(Callable(self, "_on_filesystem_changed"))
	_proxy.remove_tool_menu_item(TOOL_MENU_NAME)
	if _highlighter != null:
		_proxy.get_editor_interface().get_script_editor().unregister_syntax_highlighter(_highlighter)
		_highlighter = null


## Appends "gdl" to the editor text extensions (persists on editor exit).
## Lets `.gdl` sources open as plain text: no GDScript highlighting and,
## most importantly, no GDScript validation errors on Lisp code.
func _ensure_textfile_extension() -> void:
	# Editor settings singleton behind the proxy interface.
	var settings: EditorSettings = _proxy.get_editor_interface().get_editor_settings()
	# Current extensions as written (comma-separated, maybe spaced).
	var raw: String = str(settings.get_setting(TEXTFILE_EXTENSIONS_SETTING))
	for part in raw.split(",", false):
		if part.strip_edges() == "gdl":
			return
	if raw.strip_edges().is_empty():
		settings.set_setting(TEXTFILE_EXTENSIONS_SETTING, "gdl")
	else:
		settings.set_setting(TEXTFILE_EXTENSIONS_SETTING, raw + ",gdl")


## Reacts to filesystem scans: brings every sidecar up to date, quietly.


## Reacts to filesystem scans: brings every sidecar up to date, quietly.
func _on_filesystem_changed() -> void:
	transpile_sidecars("res://")


## Manual entry point (tool menu): transpiles everything with a summary.
## Forces all files (fixes transitive staleness: edits inside included or
## parent templates do not retrigger dependents on their own).
func transpile_all() -> void:
	# Bring-everything result across the whole project.
	var res: Dictionary = transpile_sidecars("res://", true)
	print("Gnumarus: %d file(s) updated, %d failed" % [(res["updated"] as Array).size(), (res["failed"] as Array).size()])


## Transpiles every stale `.gdl` under p_root to a sibling `.gd`.
## A source is stale when its content hash moved since the last run
## (p_force bypasses the stamps). Included/parent edits do not retrigger
## dependents — use transpile_all then.
## Returns {"updated": Array[String] of written dsts, "failed": Array[String]}.
func transpile_sidecars(p_root: String, p_force: bool = false) -> Dictionary:
	# Written destinations in this run.
	var updated: Array = []
	# Sources that failed in this run.
	var failed: Array = []
	for src in collect_gdl(p_root):
		# Sibling output next to the source (never .godot/imported).
		var dst: String = src.get_basename() + ".gd"
		# Source content hash driving both session stamps (no clocks).
		var stamp: int = FileAccess.get_file_as_string(src).hash()
		if not p_force and _done_stamp.get(dst, -1) == stamp:
			continue
		if not p_force and _failed_stamp.get(src, -1) == stamp:
			continue
		# Transpilation result for the source file.
		var res: Dictionary = FacadeScript.transpile_file(src)
		if not res["ok"]:
			push_error("Gnumarus: %s" % str(res["error"]))
			_failed_stamp[src] = stamp
			failed.append(src)
			continue
		_failed_stamp.erase(src)
		# Full output text: generated stamp plus transpiled code.
		var text: String = GENERATED_STAMP % src.get_file() + "\n" + str(res["code"])
		if FileAccess.file_exists(dst) and FileAccess.get_file_as_string(dst) == text:
			_done_stamp[dst] = stamp
			continue
		# Output handle for the sibling GDScript file.
		var out: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
		if out == null:
			push_error("Gnumarus: cannot write output for: %s" % src)
			_failed_stamp[src] = stamp
			failed.append(src)
			continue
		out.store_string(text)
		out.close()
		_done_stamp[dst] = stamp
		updated.append(dst)
	return {"updated": updated, "failed": failed}


## Collects every `.gdl` file under p_root (sorted, `.godot` and the addon
## self-test fixtures skipped).
static func collect_gdl(p_root: String) -> Array:
	# Found sources in scan order.
	var found: Array = []
	_collect_gdl_in(p_root, found)
	found.sort()
	return found


## Recursive scan worker appending `.gdl` paths (skips `.godot` and the
## addon self-test fixtures, which are expectations, not build artifacts).
static func _collect_gdl_in(p_dir: String, p_found: Array) -> void:
	# Never descends into the addon tests tree (see ADDON_TESTS_ROOT).
	if p_dir == ADDON_TESTS_ROOT or p_dir.begins_with(ADDON_TESTS_ROOT + "/"):
		return
	# Directory handle for listing entries.
	var dir: DirAccess = DirAccess.open(p_dir)
	if dir == null:
		push_error("Gnumarus: cannot scan directory: %s" % p_dir)
		return
	dir.list_dir_begin()
	# Current entry name ("" ends the listing).
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if entry != ".godot":
				_collect_gdl_in(p_dir.path_join(entry), p_found)
		elif (entry as String).to_lower().ends_with(".gdl"):
			p_found.append(p_dir.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
