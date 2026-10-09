## Static facade of the Gnumarus Lisp → GDScript transpiler.
##
## Single entry point: takes Lisp text or a `.gdl` file path and returns a
## String of valid GDScript, chaining tokenizer, parser, template resolver
## (includes + inheritance), macro expander and transpiler. Errors name the
## failing stage ("tokenizer: ...", "parser: ...", "template: ...",
## "macro: ...", "transpiler: ..."). Uses internal preloads to avoid
## depending on the editor's global class cache.
class_name GnumarusLisp
extends RefCounted


## Tokenizer script, loaded by path.
const TokenizerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTokenizer.gd")
## Parser script, loaded by path.
const ParserScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusParser.gd")
## Template resolver script, loaded by path (includes + block inheritance).
const TemplateScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTemplateResolver.gd")
## Macro expander script, loaded by path (user-defined syntactic macros).
const MacroScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusMacroExpander.gd")
## Transpiler script, loaded by path.
const TranspilerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTranspiler.gd")


## Transpiles Lisp source text to GDScript.
## Bare text has no base file, so relative includes and relative parent
## paths fail inside it (absolute res://, user:// and system paths still
## work). Returns {"ok": true, "code": String, "error": ""}, or a failure
## naming the causing stage.
static func transpile_text(p_text: String) -> Dictionary:
	return _pipeline(p_text, "")


## Transpiles a `.gdl` file (`res://` or absolute path) to GDScript.
## The file path is the base for relative includes and parent templates.
## Returns the same shape as transpile_text; read and transpile errors quote
## the file path.
static func transpile_file(p_path: String) -> Dictionary:
	if not FileAccess.file_exists(p_path):
		return {"ok": false, "code": "", "error": "file not found: %s" % p_path}
	# Text content of the input file.
	var content: String = FileAccess.get_file_as_string(p_path)
	# Transpilation result of the content with this file as include base.
	var res: Dictionary = _pipeline(content, p_path)
	if not res["ok"]:
		res["error"] = "in %s: %s" % [p_path, str(res["error"])]
	return res


## Runs the full pipeline: tokenize, parse, resolve templates, expand
## macros, transpile. p_current_file is the include/parent base ("" for
## bare text).
static func _pipeline(p_text: String, p_current_file: String) -> Dictionary:
	# Tokenizer output: {"ok", "tokens", "error"}.
	var tok: Dictionary = TokenizerScript.tokenize(p_text)
	if not tok["ok"]:
		return {"ok": false, "code": "", "error": "tokenizer: " + str(tok["error"])}
	# Parser output: {"ok", "tree", "error"}.
	var parsed: Dictionary = ParserScript.parse(tok["tokens"])
	if not parsed["ok"]:
		return {"ok": false, "code": "", "error": "parser: " + str(parsed["error"])}
	# Template resolver output: {"ok", "tree", "error"}.
	var resolved: Dictionary = TemplateScript.resolve(parsed["tree"], p_current_file)
	if not resolved["ok"]:
		return {"ok": false, "code": "", "error": "template: " + str(resolved["error"])}
	# Macro expander output: {"ok", "tree", "error"}.
	var expanded: Dictionary = MacroScript.expand(resolved["tree"])
	if not expanded["ok"]:
		return {"ok": false, "code": "", "error": "macro: " + str(expanded["error"])}
	# Transpiler instance holding the operation table.
	var transpiler: RefCounted = TranspilerScript.new()
	# Transpiler output: {"ok", "code", "error"}.
	var out: Dictionary = transpiler.transpile(expanded["tree"])
	if not out["ok"]:
		return {"ok": false, "code": "", "error": "transpiler: " + str(out["error"])}
	return out
