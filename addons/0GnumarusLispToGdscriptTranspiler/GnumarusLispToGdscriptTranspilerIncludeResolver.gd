## Include resolver for the Gnumarus transpiler Lisp dialect.
##
## Expands (include PATH) forms anywhere in the parse tree, replacing each one
## with the top-level forms of the referenced file — as if the file content
## had been copy-pasted there. Included files are tokenized and parsed with
## the same Tokenizer/Parser, so errors are reported with file context.
## Included files may include others; circular chains and excessive depth fail
## with clear errors. Runs after parsing and before transpiling (and before
## any future macro expansion). Non-string heads never match — never crash.
class_name GnumarusLispToGdscriptTranspilerIncludeResolver
extends RefCounted


## Tokenizer script, loaded by path.
const TokenizerScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerTokenizer.gd")
## Parser script, loaded by path.
const ParserScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerParser.gd")
## Maximum include nesting depth (bounds even aliasing-evaded cycles).
const MAX_INCLUDE_DEPTH: int = 32


## Expands every (include PATH) form in the tree.
## p_current_file is the file the tree came from ("" for bare text, where
## relative includes fail). p_max_depth bounds nesting (default 32).
## Returns {"ok": true, "tree": Array, "error": ""} or a failure naming the
## offending file.
static func resolve(p_tree: Array, p_current_file: String, p_max_depth: int = MAX_INCLUDE_DEPTH) -> Dictionary:
	# Include chain for cycle detection (canonical paths, innermost last).
	var stack: Array = []
	if not p_current_file.is_empty():
		stack.append(_canonical_key(p_current_file))
	return _resolve_in(p_tree, p_current_file, stack, p_max_depth)


## Recursive worker: expands includes in one tree level.
## p_stack holds the canonical chain of files being processed.
static func _resolve_in(p_tree: Array, p_current_file: String, p_stack: Array, p_max_depth: int) -> Dictionary:
	# Output tree with includes spliced in place.
	var out: Array = []
	for form in p_tree:
		if _is_include(form):
			# Included file content spliced here (never nested).
			var expanded: Dictionary = _expand_include(form, p_current_file, p_stack, p_max_depth)
			if not expanded["ok"]:
				return {"ok": false, "tree": [], "error": expanded["error"]}
			for spliced in (expanded["tree"] as Array):
				# Include-only markers never leak into the includer.
				if _is_include_only(spliced):
					continue
				out.append(spliced)
		elif form is Array:
			# Nested list: recurse with the same file and chain.
			var inner: Dictionary = _resolve_in(form, p_current_file, p_stack, p_max_depth)
			if not inner["ok"]:
				return {"ok": false, "tree": [], "error": inner["error"]}
			out.append(inner["tree"])
		else:
			# Bare atom passes through untouched.
			out.append(form)
	return {"ok": true, "tree": out, "error": ""}


## Tells whether a form is an (include ...) list (String head required).
static func _is_include(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "include"


## Tells whether a form is a bare (include-only) marker (exact shape:
## malformed markers fall through to the transpiler dangling error).
static func _is_include_only(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).size() != 1:
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "include-only"


## Expands one (include PATH [TRACE]) form into the included file's
## top-level forms, wrapped in BEGIN/END marker comments when traced.
static func _expand_include(p_form: Array, p_current_file: String, p_stack: Array, p_max_depth: int) -> Dictionary:
	if (p_form as Array).size() < 2 or (p_form as Array).size() > 3 or not ((p_form as Array)[1] is String) or (((p_form as Array)[1] as String).is_empty()):
		return {"ok": false, "tree": [], "error": "usage: (include path [trace]) with a single non-empty path string and optional true/false"}
	# Written path spec from the include form.
	var spec: String = (p_form as Array)[1]
	# Trace flag (marker comments around the spliced forms).
	var traced: bool = false
	if (p_form as Array).size() == 3:
		if not ((p_form as Array)[2] is String):
			return {"ok": false, "tree": [], "error": "usage: (include path [trace]) — trace must be the true or false atom"}
		if (p_form as Array)[2] == "true":
			traced = true
		elif (p_form as Array)[2] != "false":
			return {"ok": false, "tree": [], "error": "usage: (include path [trace]) — trace must be the true or false atom"}
		if traced and (spec.contains("\n") or spec.contains("\r")):
			return {"ok": false, "tree": [], "error": "traced include paths must not contain line breaks (they would split the marker comment)"}
	# Resolved file location (res://, system or relative-to-includer).
	var located: Dictionary = _resolve_path(spec, p_current_file)
	if not located["ok"]:
		return {"ok": false, "tree": [], "error": located["error"]}
	# Canonical identity for cycle detection.
	var key: String = _canonical_key(located["path"])
	if key in p_stack:
		# Circular chain for the error message, oldest first.
		var chain: Array = p_stack.duplicate()
		chain.append(key)
		return {"ok": false, "tree": [], "error": "circular include detected: " + " -> ".join(chain)}
	if p_stack.size() >= p_max_depth:
		return {"ok": false, "tree": [], "error": "include depth beyond maximum (%d) at %s" % [p_max_depth, located["path"]]}
	if not FileAccess.file_exists(located["path"]):
		return {"ok": false, "tree": [], "error": "include file not found: %s" % located["path"]}
	# Raw text of the included file.
	var text: String = FileAccess.get_file_as_string(located["path"])
	# Tokenizer output for the included text.
	var tok: Dictionary = TokenizerScript.tokenize(text)
	if not tok["ok"]:
		return {"ok": false, "tree": [], "error": "in %s: tokenizer: %s" % [located["path"], str(tok["error"])]}
	# Parser output for the included tokens.
	var parsed: Dictionary = ParserScript.parse(tok["tokens"])
	if not parsed["ok"]:
		return {"ok": false, "tree": [], "error": "in %s: parser: %s" % [located["path"], str(parsed["error"])]}
	# Chain extended with the included file.
	var inner_stack: Array = p_stack.duplicate()
	inner_stack.append(key)
	# Nested includes resolved inside the included file.
	var inner: Dictionary = _resolve_in(parsed["tree"], located["path"], inner_stack, p_max_depth)
	if not inner["ok"]:
		return inner
	if not traced:
		return inner
	# Trace markers wrapping the spliced forms: plain comment forms, so
	# every downstream phase handles them with no special cases (always
	# emitted, even around zero forms).
	var out: Array = [["comment", "BEGIN include " + spec + " (" + located["path"] + ")"]]
	for form in (inner["tree"] as Array):
		out.append(form)
	out.append(["comment", "END include " + spec + " (" + located["path"] + ")"])
	return {"ok": true, "tree": out, "error": ""}


## Resolves an include spec to a readable location.
## res:// and user:// pass through; / is system-absolute; ~ is the current
## user's home; anything else is relative to the including file (which must
## exist for bare text).
static func _resolve_path(p_spec: String, p_current_file: String) -> Dictionary:
	if p_spec.begins_with("res://") or p_spec.begins_with("user://"):
		return {"ok": true, "path": _normalize_path(p_spec), "error": ""}
	if p_spec.begins_with("/"):
		# Absolute system path (Windows gets the drive prefix).
		var syspath: String = _normalize_path(p_spec)
		if OS.get_name() == "Windows":
			syspath = "/c:" + syspath
		return {"ok": true, "path": syspath, "error": ""}
	if p_spec == "~" or p_spec.begins_with("~/"):
		# Home-relative path (current user only; no other-user expansion).
		var home: Dictionary = _home_dir()
		if not home["ok"]:
			return {"ok": false, "path": "", "error": home["error"]}
		return {"ok": true, "path": _normalize_path((home["path"] as String) + p_spec.substr(1)), "error": ""}
	if p_spec.begins_with("~"):
		return {"ok": false, "path": "", "error": "home-relative include \"%s\" must be \"~\" or start with \"~/\" (other users are not supported)" % p_spec}
	if p_current_file.is_empty():
		return {"ok": false, "path": "", "error": "relative include \"%s\" has no base file (use transpile_file or an absolute path)" % p_spec}
	# Directory of the file containing the include form.
	var base: String = p_current_file.get_base_dir()
	return {"ok": true, "path": _normalize_path(base + "/" + p_spec), "error": ""}


## Canonical identity of a file for cycle detection: res:// locations become
## absolute filesystem paths so equivalent spellings compare equal.
static func _canonical_key(p_path: String) -> String:
	if p_path.begins_with("res://"):
		return _normalize_path(ProjectSettings.globalize_path(p_path))
	return _normalize_path(p_path)


## Resolves the current user's home directory: HOME everywhere, with
## USERPROFILE first on Windows (PowerShell $HOME matches it).
## Empty everywhere fails instead of producing a broken path.
static func _home_dir() -> Dictionary:
	# Candidate variables in preference order.
	var names: Array = ["HOME"]
	if OS.get_name() == "Windows":
		names = ["USERPROFILE", "HOME"]
	for name in names:
		if OS.has_environment(name):
			# Stored value, skipped when empty.
			var value: String = OS.get_environment(name)
			if not value.is_empty():
				return {"ok": true, "path": value, "error": ""}
	return {"ok": false, "path": "", "error": "could not determine the home directory (no usable environment variable)"}


## Lexically normalizes a path: collapses duplicate, "." and ".." segments
## while preserving the res://, user:// or leading-/ prefix.
static func _normalize_path(p_path: String) -> String:
	# Preserved prefix (project, user or filesystem root marker).
	var prefix: String = ""
	# Remainder after the prefix.
	var rest: String = p_path
	for candidate in ["res://", "user://"]:
		if rest.begins_with(candidate):
			prefix = candidate
			rest = rest.substr(candidate.length())
			break
	# Whether the remainder is rooted (leading slash kept separately).
	var rooted: bool = rest.begins_with("/")
	# Cleaned segments in order.
	var parts: Array = []
	for segment in rest.split("/", false):
		if segment == "" or segment == ".":
			continue
		if segment == "..":
			if not parts.is_empty() and parts.back() != "..":
				parts.pop_back()
			elif not rooted and prefix.is_empty():
				parts.append("..")
			continue
		parts.append(segment)
	# Reassembled remainder.
	var out: String = "/".join(parts)
	if rooted:
		out = "/" + out
	return prefix + out
