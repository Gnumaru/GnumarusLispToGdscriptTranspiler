## Syntactic transpiler from the Lisp tree to GDScript source code.
##
## Walks the GnumarusLispToGdscriptTranspilerParser nested tree and emits a String of valid GDScript.
## The Lisp-to-GDScript mapping lives in the _operations table (operation
## name -> emitter Callable), so new operations can extend the transpiler
## without changing the traversal. It performs no semantic validation: pure
## syntax transformation. Indentation uses tabs, as the Godot editor does.
##
## Value emission is verbatim: atom content is emitted as GDScript source
## exactly as written (after Lisp unescaping). The transpiler never adds
## quotes on its own. A GDScript string literal therefore requires the user
## to "double pack": pack it in Lisp AND write the GDScript quotes inside,
## e.g. (var a String = "\"hi\"") emits var a: String = "hi". The same hatch
## covers any literal unrepresentable as bare atoms, e.g. "Vector2(1, 2)".
class_name GnumarusLispToGdscriptTranspilerTranspiler
extends RefCounted


## Infix expression operators (usable as statements and values): arithmetic,
## comparison and logic heads, emitted `left OP right` with nested infix
## operands in parentheses (precedence-safe by construction, never by guessing).
const INFIX_OPS: Array = ["+", "-", "*", "/", "%", "**", "==", "!=", "<", ">", "<=", ">=", "and", "or", "not", "is", "as", "in", "<<", ">>", "&", "|", "^", "~"]
## Compound assignment operators accepted by (assign ...), probed on Godot 4.7.2.
const ASSIGN_OPS: Array = ["=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "|=", "^=", "**="]
## Collection constructors (usable as statements and values): always multiline
## except when empty. Shared by operands, arguments, values and elements.
const COLLECTION_OPS: Array = ["array", "dict-lua", "dict-json"]


## Operation table: Lisp name (String) -> emitter method (Callable).
## Each emitter takes (form: Array, indent: int) -> Dictionary
## {"ok": bool, "code": String, "error": String}.
var _operations: Dictionary = {}


## Constructor: registers the operations supported in v1.
func _init() -> void:
	_operations = {
		"class-name": Callable(self, "_emit_class_name"),
		"extends": Callable(self, "_emit_extends"),
		"var": Callable(self, "_emit_var"),
		"comment": Callable(self, "_emit_comment"),
		"func": Callable(self, "_emit_func"),
		"pass": Callable(self, "_emit_pass"),
		"if": Callable(self, "_emit_if"),
		"elif": Callable(self, "_emit_elif_dangling"),
		"else": Callable(self, "_emit_else_dangling"),
		"while": Callable(self, "_emit_while"),
		"for": Callable(self, "_emit_for"),
		"break": Callable(self, "_emit_break"),
		"continue": Callable(self, "_emit_continue"),
		"return": Callable(self, "_emit_return"),
		"match": Callable(self, "_emit_match"),
		"branch": Callable(self, "_emit_branch_dangling"),
		"static-var": Callable(self, "_emit_static_var"),
		"static-func": Callable(self, "_emit_static_func"),
		"signal": Callable(self, "_emit_signal"),
		"const": Callable(self, "_emit_const"),
		"class": Callable(self, "_emit_class"),
		"lambda": Callable(self, "_emit_lambda_dangling"),
		"get": Callable(self, "_emit_get_dangling"),
		"set": Callable(self, "_emit_set_dangling"),
		"call": Callable(self, "_emit_call"),
		"chain": Callable(self, "_emit_chain"),
		"+": Callable(self, "_emit_infix_statement"),
		"-": Callable(self, "_emit_infix_statement"),
		"*": Callable(self, "_emit_infix_statement"),
		"/": Callable(self, "_emit_infix_statement"),
		"%": Callable(self, "_emit_infix_statement"),
		"**": Callable(self, "_emit_infix_statement"),
		"==": Callable(self, "_emit_infix_statement"),
		"!=": Callable(self, "_emit_infix_statement"),
		"<": Callable(self, "_emit_infix_statement"),
		">": Callable(self, "_emit_infix_statement"),
		"<=": Callable(self, "_emit_infix_statement"),
		">=": Callable(self, "_emit_infix_statement"),
		"and": Callable(self, "_emit_infix_statement"),
		"or": Callable(self, "_emit_infix_statement"),
		"not": Callable(self, "_emit_infix_statement"),
		"is": Callable(self, "_emit_infix_statement"),
		"as": Callable(self, "_emit_infix_statement"),
		"in": Callable(self, "_emit_infix_statement"),
		"<<": Callable(self, "_emit_infix_statement"),
		">>": Callable(self, "_emit_infix_statement"),
		"&": Callable(self, "_emit_infix_statement"),
		"|": Callable(self, "_emit_infix_statement"),
		"^": Callable(self, "_emit_infix_statement"),
		"~": Callable(self, "_emit_infix_statement"),
		"assign": Callable(self, "_emit_assign"),
		"await": Callable(self, "_emit_await"),
		"assert": Callable(self, "_emit_assert"),
		"breakpoint": Callable(self, "_emit_breakpoint"),
		"enum": Callable(self, "_emit_enum"),
		"ternary": Callable(self, "_emit_ternary"),
		"array": Callable(self, "_emit_array"),
		"dict-lua": Callable(self, "_emit_dict_lua"),
		"dict-json": Callable(self, "_emit_dict_json"),
		"include": Callable(self, "_emit_include_dangling"),
		"block": Callable(self, "_emit_block_dangling"),
		"template-extends": Callable(self, "_emit_template_extends_dangling"),
		"defmacro": Callable(self, "_emit_defmacro_dangling"),
		"join": Callable(self, "_emit_join_dangling"),
		"super": Callable(self, "_emit_super_dangling"),
		"upper": Callable(self, "_emit_upper_dangling"),
		"lower": Callable(self, "_emit_lower_dangling"),
		"capitalize": Callable(self, "_emit_capitalize_dangling"),
		"for-generate": Callable(self, "_emit_for_generate_dangling"),
		"template-set": Callable(self, "_emit_template_set_dangling"),
		"tvar": Callable(self, "_emit_tvar_dangling"),
		"when": Callable(self, "_emit_when_dangling"),
		"when-not": Callable(self, "_emit_when_not_dangling"),
	}


## Lists the supported operation names (introspection/extensibility).
func operation_names() -> Array:
	return _operations.keys()


## Tells whether an operation is supported by the transpiler.
func has_operation(p_name: String) -> bool:
	return _operations.has(p_name)


## Transpiles the whole tree (top-level form list) to GDScript.
## Returns {"ok": true, "code": String, "error": ""}; output ends with "\n"
## when non-empty. On failure returns {"ok": false, "code": "", ...}.
func transpile(p_tree: Array) -> Dictionary:
	# Code blocks, one per top-level form (func yields a multiline block).
	var blocks: Array = []
	for form in p_tree:
		# GDScript code of the current top-level form.
		var res: Dictionary = transpile_statement(form, 0, "top")
		if not res["ok"]:
			return {"ok": false, "code": "", "error": res["error"]}
		blocks.append(res["code"])
	# Final code with blocks separated by newlines.
	var code: String = ""
	if not blocks.is_empty():
		code = "\n".join(blocks) + "\n"
	return {"ok": true, "code": code, "error": ""}


## Transpiles a single form (list whose first item names the operation).
## p_indent is the indentation level (tabs); p_context gates placement:
## "top" (file level), "member" (class body) or "local" (function body).
func transpile_statement(p_form, p_indent: int, p_context: String) -> Dictionary:
	if not (p_form is Array):
		return _fail("form must be a list, got the atom '%s'" % str(p_form))
	if (p_form as Array).is_empty():
		return _fail("empty list is not a valid form (use () only as func argument list)")
	# Operation name (first item of the form).
	var head = (p_form as Array)[0]
	if not (head is String):
		return _fail("form operator must be a string")
	if not _operations.has(head):
		return _fail("unknown operation: '%s'" % head)
	if not _is_placement_valid(head, p_context):
		return _fail("operation '%s' is not valid here (%s)" % [head, _placement_rule(head)])
	# Emitter registered in the operation table.
	var emitter: Callable = _operations[head]
	# Dictionary {"ok", "code", "error"} produced by the emitter.
	var res: Dictionary = emitter.call(p_form, p_indent, p_context)
	return res


## Tells whether an operation may appear in the given context.
## "class-name" is file-level only; member-capable operations work at the top
## level and in class bodies; plain statements work anywhere.
func _is_placement_valid(p_head: String, p_context: String) -> bool:
	match p_head:
		"class-name":
			return p_context == "top"
		"extends", "func", "static-func", "static-var", "signal", "class", "enum":
			return p_context == "top" or p_context == "member"
	return true


## Short placement rule text used in error messages.
func _placement_rule(p_head: String) -> String:
	if p_head == "class-name":
		return "only valid at the top level"
	return "valid at the top level and in class bodies, not inside functions"


## Builds the indentation prefix (one tab per level).
func _indent_text(p_indent: int) -> String:
	return "\t".repeat(p_indent)


## Builds a success return with the generated GDScript code.
func _ok(p_code: String) -> Dictionary:
	return {"ok": true, "code": p_code, "error": ""}


## Builds a failure return with an English error message.
func _fail(p_message: String) -> Dictionary:
	return {"ok": false, "code": "", "error": p_message}


## Emits `class_name X` from (class-name X), with leading @ annotations
## each on their own line. Top level only.
func _emit_class_name(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Leading annotations stripped first (never reach the grammar below).
	var split: Dictionary = _split_annotations(p_form.slice(1))
	if not split["ok"]:
		return _fail(str(split["error"]))
	var rest: Array = split["rest"]
	if rest.size() != 1 or not (rest[0] is String) or (rest[0] as String).is_empty() or (rest[0] as String).begins_with("@"):
		return _fail("usage: (class-name Name) — e.g. (class-name MyClass)")
	return _ok(_prefix_annotations(split["annotations"], p_indent, "class_name %s" % rest[0]))


## Emits `extends X` from (extends X), with leading @ annotations each on
## their own line. Top level and class bodies.
func _emit_extends(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Leading annotations stripped first (never reach the grammar below).
	var split: Dictionary = _split_annotations(p_form.slice(1))
	if not split["ok"]:
		return _fail(str(split["error"]))
	var rest: Array = split["rest"]
	if rest.size() != 1 or not (rest[0] is String) or (rest[0] as String).is_empty() or (rest[0] as String).begins_with("@"):
		return _fail("usage: (extends Base) — e.g. (extends Node)")
	return _ok(_prefix_annotations(split["annotations"], p_indent, "%sextends %s" % [_indent_text(p_indent), rest[0]]))


## Emits `var ...` from (var ...) in the 5 positional forms. Valid at any level.
func _emit_var(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	return _emit_variable(p_form, p_indent, "var", "var", p_context)


## Emits `static var ...` from (static-var ...) in the same 5 positional
## forms as (var ...). Top level only (enforced by transpile_statement).
func _emit_static_var(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	return _emit_variable(p_form, p_indent, "static-var", "static var", p_context)


## Shared `var` / `static-var` emitter.
## p_op names the operation in usage messages; p_keyword opens the output line.
## Trailing (get ...) / (set ...) forms become accessor blocks (declaration
## gains ":"); they are rejected inside functions. Values are verbatim atoms
## or (lambda ...) forms; a GDScript string literal needs double packing,
## e.g. (var a String = "\"hi\"").
func _emit_variable(p_form: Array, p_indent: int, p_op: String, p_keyword: String, p_context: String) -> Dictionary:
	# Leading annotations stripped first (never reach the grammar below).
	var asplit: Dictionary = _split_annotations(p_form.slice(1))
	if not asplit["ok"]:
		return _fail(str(asplit["error"]))
	# Arguments after the operator and the annotations.
	var args: Array = asplit["rest"]
	# Annotation lines prefixed to every successful exit below.
	var annotations: Array = asplit["annotations"]
	# Declaration slots (before any accessor).
	var decl: Array = []
	# Trailing get/set accessor forms, in order.
	var accessors: Array = []
	# Whether a get/set form was already seen (only accessors may follow).
	var seen_accessor: bool = false
	for element in args:
		if _is_accessor(element):
			seen_accessor = true
			accessors.append(element)
		elif seen_accessor:
			return _fail("only (get ...) and (set ...) forms may follow a get/set accessor in (%s ...)" % p_op)
		else:
			decl.append(element)
	# Plain declaration line (no trailing colon yet).
	var decres: Dictionary = _emit_plain_variable(decl, p_indent, p_op, p_keyword)
	if not decres["ok"]:
		return decres
	if accessors.is_empty():
		return _ok(_prefix_annotations(annotations, p_indent, decres["code"]))
	if p_context == "local":
		return _fail("get/set accessors are only valid on member variables, not inside functions")
	if (decres["code"] as String).contains("\n"):
		return _fail("get/set accessors cannot combine with a (lambda ...) default in (%s ...)" % p_op)
	# Duplicate kinds are rejected for inline and block forms alike.
	var seen_get: bool = false
	var seen_set: bool = false
	for acc in accessors:
		# Accessor kind: "get" or "set" (guaranteed by _is_accessor).
		var akind: String = (acc as Array)[0]
		if akind == "get":
			if seen_get:
				return _fail("duplicate (get ...) in (%s ...) — at most one getter" % p_op)
			seen_get = true
		else:
			if seen_set:
				return _fail("duplicate (set ...) in (%s ...) — at most one setter" % p_op)
			seen_set = true
	# Same-line references ("get = f") for single-atom accessors, if any.
	var inline_refs: Array = []
	# Whether any accessor is a block body (forces the block form for all).
	var has_block: bool = false
	for acc in accessors:
		# Same-line reference text, or "" when the accessor is a block.
		var ref: String = _accessor_inline_ref(acc)
		if ref.is_empty():
			has_block = true
		else:
			inline_refs.append(ref)
	if not inline_refs.is_empty() and has_block:
		return _fail("cannot mix inline references and block bodies in one (%s ...) declaration" % p_op)
	if not has_block:
		return _ok("%s: %s" % [decres["code"], ", ".join(inline_refs)])
	# Declaration line with colon + accessor blocks one level deeper.
	var lines: Array = [decres["code"] + ":"]
	for acc in accessors:
		# GDScript code of one accessor block.
		var ares: Dictionary = _emit_accessor(acc, p_indent + 1)
		if not ares["ok"]:
			return ares
		lines.append(ares["code"])
	return _ok(_prefix_annotations(annotations, p_indent, "\n".join(lines)))


## Plain `var` / `static-var` declaration line, without accessors.
## p_decl holds the declaration slots; p_op/p_keyword as in _emit_variable.
func _emit_plain_variable(p_decl: Array, p_indent: int, p_op: String, p_keyword: String) -> Dictionary:
	# Working copy under the historical name used below.
	var args: Array = p_decl
	if args.is_empty():
		return _fail("invalid '%s' form; usages: (%s n), (%s n T), (%s n = v), (%s n := v), (%s n T = v)" % [p_op, p_op, p_op, p_op, p_op, p_op])
	# Declared variable name (first positional slot, always an atom, never @).
	var vname = args[0]
	if not (vname is String) or (vname as String).is_empty() or vname == "=" or vname == ":=" or (vname as String).begins_with("@"):
		return _fail("variable name must be a non-empty identifier (got '%s')" % str(vname))
	# Indentation prefix of the current level.
	var prefix: String = _indent_text(p_indent)
	match args.size():
		1:
			return _ok("%s%s %s" % [prefix, p_keyword, vname])
		2:
			if (args[1] is String) and (args[1] == "=" or args[1] == ":="):
				return _fail("missing default value: usage (%s %s %s value)" % [p_op, vname, args[1]])
			if not (args[1] is String) or (args[1] as String).is_empty():
				return _fail("variable type must be a non-empty string")
			return _ok("%s%s %s: %s" % [prefix, p_keyword, vname, args[1]])
		3:
			if (args[1] is String) and (args[1] == "=" or args[1] == ":="):
				# Default value: verbatim atom or (lambda ...) form.
				var vres: Dictionary = _emit_value(args[2], p_indent, "default value")
				if not vres["ok"]:
					return vres
				return _ok("%s%s %s %s %s" % [prefix, p_keyword, vname, args[1], vres["code"]])
			return _fail("missing '=' before default value: usage (%s %s %s = value)" % [p_op, vname, args[1]])
		4:
			if (args[1] is String) and (args[1] == "=" or args[1] == ":="):
				return _fail("misplaced '%s': usages with a type are (%s %s T) and (%s %s T = value)" % [args[1], p_op, vname, p_op, vname])
			if not (args[1] is String) or (args[1] as String).is_empty():
				return _fail("variable type must be a non-empty string")
			if (args[2] is String) and args[2] == "=":
				# Default value: verbatim atom or (lambda ...) form.
				var vres4: Dictionary = _emit_value(args[3], p_indent, "default value")
				if not vres4["ok"]:
					return vres4
				return _ok("%s%s %s: %s = %s" % [prefix, p_keyword, vname, args[1], vres4["code"]])
			if (args[2] is String) and args[2] == ":=":
				return _fail("'%s %s: %s := ...' is invalid GDScript (type hint and inference cannot be combined)" % [p_keyword, vname, args[1]])
			return _fail("expected '=' before default value: usage (%s %s %s = value)" % [p_op, vname, args[1]])
	return _fail("invalid '%s' form; usages: (%s n), (%s n T), (%s n = v), (%s n := v), (%s n T = v)" % [p_op, p_op, p_op, p_op, p_op, p_op])


## Emits `# text` from (comment text...). Valid at any level.
## Multiple atoms are joined with one space; empty text yields bare "#".
func _emit_comment(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Text atoms after the "comment" operator.
	var args: Array = p_form.slice(1)
	for a in args:
		if not (a is String):
			return _fail("'comment' arguments must be strings, not lists")
	# Final comment text, with atoms joined by spaces.
	var text: String = " ".join(args)
	if text.is_empty():
		return _ok("%s#" % _indent_text(p_indent))
	return _ok("%s# %s" % [_indent_text(p_indent), text])


## Emits `pass` from (pass). Valid at any level.
func _emit_pass(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 1:
		return _fail("usage: (pass) — takes no arguments")
	return _ok("%spass" % _indent_text(p_indent))


## Emits `func name(args):` + indented body from
## (func name (args...) body...). Top level only in v1.
## A leading (comment text) body element becomes a trailing comment on the
## declaration line (e.g. `func _ready(): # text`).
func _emit_func(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	return _emit_function(p_form, p_indent, "func", "func")


## Emits `static func name(args):` + indented body from
## (static-func name (args...) body...). Top level only
## (enforced by transpile_statement). Same trailing-comment rule as func.
func _emit_static_func(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	return _emit_function(p_form, p_indent, "static func", "static-func")


## Parses one argument: bare atom (untyped, emitted literally — this is how
## `...rest` passes through) or sublist (n), (n T), (n = v), (n := v), (n T = v).
## Returns {"ok", "code": rendered text, "error"}.
func _parse_arg(p_arg) -> Dictionary:
	if p_arg is String:
		if (p_arg as String).is_empty():
			return {"ok": false, "code": "", "error": "argument name must be a non-empty string"}
		return {"ok": true, "code": p_arg, "error": ""}
	if not (p_arg is Array):
		return {"ok": false, "code": "", "error": "argument must be a name or a (name ...) list (got '%s')" % str(p_arg)}
	# Argument sublist elements.
	var parts: Array = p_arg
	if parts.is_empty():
		return {"ok": false, "code": "", "error": "empty argument list; usages: (n), (n T), (n = v), (n := v), (n T = v)"}
	# Argument name (first slot, always an atom).
	var aname = parts[0]
	if not (aname is String) or (aname as String).is_empty() or aname == "=" or aname == ":=":
		return {"ok": false, "code": "", "error": "argument name must be a non-empty identifier (got '%s')" % str(aname)}
	match parts.size():
		1:
			return {"ok": true, "code": aname, "error": ""}
		2:
			if (parts[1] is String) and (parts[1] == "=" or parts[1] == ":="):
				return {"ok": false, "code": "", "error": "missing default value: usage (%s %s value)" % [aname, parts[1]]}
			if not (parts[1] is String) or (parts[1] as String).is_empty():
				return {"ok": false, "code": "", "error": "argument type must be a non-empty string"}
			return {"ok": true, "code": "%s: %s" % [aname, parts[1]], "error": ""}
		3:
			if (parts[1] is String) and (parts[1] == "=" or parts[1] == ":="):
				if not (parts[2] is String) or (parts[2] as String).is_empty():
					return {"ok": false, "code": "", "error": "argument default must be a non-empty string"}
				return {"ok": true, "code": "%s %s %s" % [aname, parts[1], parts[2]], "error": ""}
			return {"ok": false, "code": "", "error": "missing '=' before argument default: usage (%s %s = value)" % [aname, parts[1]]}
		4:
			if (parts[1] is String) and (parts[1] == "=" or parts[1] == ":="):
				return {"ok": false, "code": "", "error": "misplaced '%s' in argument list" % parts[1]}
			if not (parts[1] is String) or (parts[1] as String).is_empty():
				return {"ok": false, "code": "", "error": "argument type must be a non-empty string"}
			if (parts[2] is String) and parts[2] == "=":
				if not (parts[3] is String) or (parts[3] as String).is_empty():
					return {"ok": false, "code": "", "error": "argument default must be a non-empty string"}
				return {"ok": true, "code": "%s: %s = %s" % [aname, parts[1], parts[3]], "error": ""}
			if (parts[2] is String) and parts[2] == ":=":
				return {"ok": false, "code": "", "error": "'%s: %s := ...' is invalid GDScript (type hint and inference cannot be combined)" % [aname, parts[1]]}
			return {"ok": false, "code": "", "error": "expected '=' before argument default"}
	return {"ok": false, "code": "", "error": "invalid argument; usages: (n), (n T), (n = v), (n := v), (n T = v)"}


## Parses an argument list into rendered GDScript fragments.
## Returns {"ok", "args": Array[String], "error"}.
func _parse_arg_list(p_list: Array) -> Dictionary:
	# Rendered arguments in order.
	var rendered: Array = []
	for element in p_list:
		# Parsed single argument.
		var parsed: Dictionary = _parse_arg(element)
		if not parsed["ok"]:
			return {"ok": false, "args": [], "error": parsed["error"]}
		rendered.append(parsed["code"])
	return {"ok": true, "args": rendered, "error": ""}


## Parses a signature list into return type + arguments.
## Shapes: () plain; (void) return without args; (R (args...)) return with
## grouped args; anything else is flat args without return. A bare atom
## followed by a list always opens return position — ((x) (a int)) means two
## args, (x (a int)) means return x. Returns {"ok", "return_type", "args", "error"}.
func _parse_signature(p_sig: Array) -> Dictionary:
	if p_sig.is_empty():
		return {"ok": true, "return_type": "", "args": [], "error": ""}
	if p_sig.size() == 1 and (p_sig[0] is String) and p_sig[0] == "void":
		return {"ok": true, "return_type": "void", "args": [], "error": ""}
	if p_sig.size() >= 2 and (p_sig[0] is String) and (p_sig[1] is Array):
		if p_sig.size() != 2:
			return {"ok": false, "return_type": "", "args": [], "error": "with a return type, arguments must come grouped in one list — e.g. (R ((a) (b)))"}
		if (p_sig[0] as String).is_empty():
			return {"ok": false, "return_type": "", "args": [], "error": "return type must be a non-empty string"}
		# Grouped argument list after the return type.
		var grouped: Dictionary = _parse_arg_list(p_sig[1])
		if not grouped["ok"]:
			return {"ok": false, "return_type": "", "args": [], "error": grouped["error"]}
		return {"ok": true, "return_type": p_sig[0], "args": grouped["args"], "error": ""}
	# Flat form: every element is one argument, no return type.
	var flat: Dictionary = _parse_arg_list(p_sig)
	if not flat["ok"]:
		return {"ok": false, "return_type": "", "args": [], "error": flat["error"]}
	return {"ok": true, "return_type": "", "args": flat["args"], "error": ""}


## Shared `func` / `static-func` emitter.
## p_keyword opens the declaration line; p_op names the operation in usage.
## Leading @ annotations (each on its own line) precede the declaration.
func _emit_function(p_form: Array, p_indent: int, p_keyword: String, p_op: String) -> Dictionary:
	# Leading annotations stripped first (never reach the grammar below).
	var asplit: Dictionary = _split_annotations(p_form.slice(1))
	if not asplit["ok"]:
		return _fail(str(asplit["error"]))
	var rest: Array = asplit["rest"]
	# Annotation lines prefixed to the successful exit below.
	var annotations: Array = asplit["annotations"]
	# Abstract functions (engine-verified) never take a body — and the
	# engine forbids @abstract on static functions altogether.
	if "@abstract" in annotations and p_op == "static-func":
		return _fail("\"@abstract\" cannot be applied to static functions")
	if rest.size() < 2:
		return _fail("usage: (%s name (signature...) body...) — e.g. (%s _ready () (pass))" % [p_op, p_op])
	# Function name (non-empty String, never @).
	var fname = rest[0]
	# Signature list: return type first, then arguments (see docs).
	var sig = rest[1]
	if not (fname is String) or (fname as String).is_empty() or (fname as String).begins_with("@"):
		return _fail("function name must be a non-empty string")
	if not (sig is Array):
		return _fail("'%s' signature must be a list — e.g. (%s f (a (b int)) ...)" % [p_op, p_op])
	# Parsed return type ("") and rendered argument list.
	var parsed: Dictionary = _parse_signature(sig)
	if not parsed["ok"]:
		return _fail(str(parsed["error"]))
	var fargs: Array = parsed["args"]
	# Return suffix (" -> Type") or empty when untyped.
	var retsuffix: String = ""
	if not (parsed["return_type"] as String).is_empty():
		retsuffix = " -> %s" % parsed["return_type"]
	# Function body forms (may start with a trailing-comment comment).
	var raw_body: Array = rest.slice(2)
	# Leading (comment ...) consumed as the declaration trailing comment.
	var split: Dictionary = _take_trailing_comment(raw_body)
	if not split["ok"]:
		return _fail(str(split["error"]))
	var trailing: String = split["trailing"]
	var body: Array = split["rest"]
	if body.is_empty():
		if "@abstract" in annotations:
			# Bodiless abstract declaration: header without colon or suite.
			var ahead: String = "%s%s %s(%s)%s%s" % [_indent_text(p_indent), p_keyword, fname, ", ".join(fargs), retsuffix, trailing]
			return _ok(_prefix_annotations(annotations, p_indent, ahead))
		return _fail("function '%s' has no body: GDScript requires at least one indented line" % fname)
	if "@abstract" in annotations:
		return _fail("an abstract function cannot have a body")
	# Function declaration line, with optional return type and trailing comment.
	var header: String = "%s%s %s(%s)%s:%s" % [_indent_text(p_indent), p_keyword, fname, ", ".join(fargs), retsuffix, trailing]
	# Output lines: declaration + each body form indented one level deeper.
	var lines: Array = [header]
	for stmt in body:
		# GDScript code of one body form: function bodies are local context.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, "local")
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok(_prefix_annotations(annotations, p_indent, "\n".join(lines)))


## Tells whether a body form opens an elif/else chain link.
## Used to split an (if ...) body into the then-branch and the chain.
## Non-string heads (nested lists) are never links — and never crash here.
func _is_chain_link(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "elif" or head == "else"


## Emits `if COND:` + indented body from (if COND body...).
## Trailing (elif ...) / (else ...) body forms are consumed as the flat
## elif/else chain at the same level (like the trailing comment of func).
## Valid at any level.
func _emit_if(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	if p_form.size() < 3:
		return _fail("usage: (if condition body...) — e.g. (if \"x > 0\" (pass))")
	# Branch condition: verbatim atom or single-line expression (pack with
	# spaces, e.g. "x > 0"; structured forms like (== x 1) also work).
	var cond = p_form[1]
	var cres: Dictionary = _emit_operand(cond, false, p_indent)
	if not cres["ok"]:
		return _fail("invalid if condition: " + str(cres["error"]))
	var cond_code: String = cres["code"]
	# Raw body forms after the condition.
	var rest: Array = p_form.slice(2)
	# Leading plain statements of the if branch.
	var then_body: Array = []
	# Trailing elif/else links of the chain.
	var chain: Array = []
	# Whether an elif/else link was already seen (only links may follow).
	var seen_link: bool = false
	for stmt in rest:
		if _is_chain_link(stmt):
			seen_link = true
			chain.append(stmt)
		elif seen_link:
			return _fail("only elif/else forms may follow an elif/else link in (if ...)")
		else:
			then_body.append(stmt)
	if then_body.is_empty():
		return _fail("if branch needs at least one statement before elif/else")
	# Header line + then branch indented one level deeper.
	var lines: Array = ["%sif %s:" % [_indent_text(p_indent), cond_code]]
	for stmt in then_body:
		# GDScript code of one then-branch statement, same context as the if.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
		if not r["ok"]:
			return r
		lines.append(r["code"])
	# Chain links, each emitted at the same level as the if header.
	var seen_else: bool = false
	for link in chain:
		if seen_else:
			return _fail("nothing may follow (else ...) in an if chain")
		# GDScript code of one elif/else link, same context as the if.
		var lr: Dictionary = _emit_chain_link(link, p_indent, p_context)
		if not lr["ok"]:
			return lr
		lines.append(lr["code"])
		if ((link as Array)[0] as String) == "else":
			seen_else = true
	return _ok("\n".join(lines))


## Emits one flat chain link: (elif COND body...) or (else body...).
## Link bodies hold plain statements only; nested chains need an inner (if ...).
func _emit_chain_link(p_link: Array, p_indent: int, p_context: String) -> Dictionary:
	# Link kind: "elif" or "else".
	var kind: String = (p_link as Array)[0]
	if kind == "elif":
		if p_link.size() < 3:
			return _fail("usage: (elif condition body...) — e.g. (elif \"x < 0\" (pass))")
		# Branch condition: verbatim atom or single-line expression, like (if ...).
		var cond = p_link[1]
		var cres: Dictionary = _emit_operand(cond, false, p_indent)
		if not cres["ok"]:
			return _fail("invalid elif condition: " + str(cres["error"]))
		var cond_code: String = cres["code"]
		# Plain statements of the elif branch.
		var body: Array = p_link.slice(2)
		if body.is_empty():
			return _fail("elif branch needs at least one statement")
		for stmt in body:
			if _is_chain_link(stmt):
				return _fail("if chains are flat: elif bodies cannot hold further elif/else links (nest an (if ...) instead)")
		# Header line + branch indented one level deeper.
		var lines: Array = ["%selif %s:" % [_indent_text(p_indent), cond_code]]
		for stmt in body:
			# GDScript code of one elif-branch statement, same context.
			var r: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
			if not r["ok"]:
				return r
			lines.append(r["code"])
		return _ok("\n".join(lines))
	# Body statements of the else branch.
	var ebody: Array = p_link.slice(1)
	if ebody.is_empty():
		return _fail("usage: (else body...) — else branch needs at least one statement")
	for stmt in ebody:
		if _is_chain_link(stmt):
			return _fail("if chains are flat: else bodies cannot hold further elif/else links (nest an (if ...) instead)")
	# Header line + branch indented one level deeper.
	var elines: Array = ["%selse:" % _indent_text(p_indent)]
	for stmt in ebody:
		# GDScript code of one else-branch statement, same context.
		var er: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
		if not er["ok"]:
			return er
		elines.append(er["code"])
	return _ok("\n".join(elines))


## Dangling (elif ...) reached outside an (if ...) chain. Always an error.
func _emit_elif_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("elif is only valid as a trailing form of (if ...)")


## Dangling (else ...) reached outside an (if ...) chain. Always an error.
func _emit_else_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("else is only valid as a trailing form of (if ...)")


## Emits `while COND:` + indented body from (while COND body...).
## Valid at any level.
func _emit_while(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	if p_form.size() < 3:
		return _fail("usage: (while condition body...) — e.g. (while \"x > 0\" (pass))")
	# Loop condition: verbatim atom or single-line expression (pack with
	# spaces, e.g. "x > 0"; structured forms like (== x 1) also work).
	var cond = p_form[1]
	var cres: Dictionary = _emit_operand(cond, false, p_indent)
	if not cres["ok"]:
		return _fail("invalid while condition: " + str(cres["error"]))
	var cond_code: String = cres["code"]
	# Loop body forms.
	var body: Array = p_form.slice(2)
	# Header line + body indented one level deeper.
	var lines: Array = ["%swhile %s:" % [_indent_text(p_indent), cond_code]]
	for stmt in body:
		# GDScript code of one loop statement, same context as the while.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok("\n".join(lines))


## Emits `for VAR in ITER:` / `for VAR: TYPE in ITER:` + indented body from
## (for VAR in ITER body...) / (for VAR TYPE in ITER body...).
## The "in" marker mirrors GDScript and the "=" marker of var: when the slot
## after the name is "in" the loop is untyped, otherwise it names the type.
## Valid at any level.
func _emit_for(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	if p_form.size() < 5:
		return _fail("usage: (for name in iterable body...) or (for name type in iterable body...) — e.g. (for x in items (pass))")
	# Loop variable name (first positional slot).
	var vname = p_form[1]
	if not (vname is String) or (vname as String).is_empty() or vname == "in":
		return _fail("for loop variable must be a non-empty identifier (got '%s')" % str(vname))
	# Slot after the name: "in" (untyped loop) or a type name (typed loop).
	var second = p_form[2]
	# Declared loop variable type, empty when untyped.
	var vtype: String = ""
	# Index of the iterable slot and of the first body form.
	var iter_idx: int = 3
	if not (second is String) or second != "in":
		if not (second is String) or (second as String).is_empty():
			return _fail("for loop type must be a non-empty string")
		vtype = second
		iter_idx = 4
		if p_form.size() < 6:
			return _fail("usage: (for name type in iterable body...) — e.g. (for n int in items (pass))")
		if not (p_form[3] is String) or p_form[3] != "in":
			return _fail("usage: (for name type in iterable body...) — missing 'in' marker")
	# Iterable: verbatim atom or single-line expression, e.g. (call range 10).
	var iter = p_form[iter_idx]
	var ires: Dictionary = _emit_operand(iter, false, p_indent)
	if not ires["ok"]:
		return _fail("invalid for iterable: " + str(ires["error"]))
	var iter_code: String = ires["code"]
	# Loop body forms.
	var body: Array = p_form.slice(iter_idx + 1)
	# Header line, typed or plain, + body indented one level deeper.
	var header: String = "%sfor %s in %s:" % [_indent_text(p_indent), vname, iter_code]
	if not vtype.is_empty():
		header = "%sfor %s: %s in %s:" % [_indent_text(p_indent), vname, vtype, iter_code]
	var lines: Array = [header]
	for stmt in body:
		# GDScript code of one loop statement, same context as the for.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok("\n".join(lines))


## Emits `break` from (break). Valid at any level.
func _emit_break(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 1:
		return _fail("usage: (break) — takes no arguments")
	return _ok("%sbreak" % _indent_text(p_indent))


## Emits `continue` from (continue). Valid at any level.
func _emit_continue(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 1:
		return _fail("usage: (continue) — takes no arguments")
	return _ok("%scontinue" % _indent_text(p_indent))


## Emits `return` / `return VALUE` from (return) / (return VALUE).
## Values are verbatim atoms or (lambda ...) forms; GDScript strings still
## need double packing, e.g. (return "\"done\""). Valid at any level.
func _emit_return(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() == 1:
		return _ok("%sreturn" % _indent_text(p_indent))
	if p_form.size() == 2:
		# Returned value: verbatim atom or (lambda ...) form.
		var vres: Dictionary = _emit_value(p_form[1], p_indent, "return value")
		if not vres["ok"]:
			return vres
		return _ok("%sreturn %s" % [_indent_text(p_indent), vres["code"]])
	return _fail("usage: (return) or (return value) — e.g. (return 0)")


## Tells whether a form is a match branch, i.e. a (branch ...) list.
## Used to validate direct children of (match ...).
## Non-string heads (nested lists) are never branches — and never crash here.
func _is_branch(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var bhead = (p_form as Array)[0]
	if not (bhead is String):
		return false
	return bhead == "branch"


## Emits `match SUBJECT:` + branches from (match SUBJECT branch...).
## Every direct child must be a (branch PATTERN body...) form; anything else
## is an error (GDScript expects patterns right after the match header).
## Valid at any level.
func _emit_match(p_form: Array, p_indent: int, p_context: String) -> Dictionary:
	if p_form.size() < 3:
		return _fail("usage: (match subject branch...) — e.g. (match \"x\" (branch \"1\" (pass)))")
	# Match subject: verbatim atom or single-line expression.
	var subject = p_form[1]
	var sres: Dictionary = _emit_operand(subject, false, p_indent)
	if not sres["ok"]:
		return _fail("invalid match subject: " + str(sres["error"]))
	var subject_code: String = sres["code"]
	# Direct children: all of them must be branches.
	var branches: Array = p_form.slice(2)
	# Header line + branches one level deeper.
	var lines: Array = ["%smatch %s:" % [_indent_text(p_indent), subject_code]]
	for child in branches:
		if not _is_branch(child):
			return _fail("match children must be (branch pattern body...) forms (got '%s')" % str(child))
		# GDScript code of one branch, same context as the match.
		var r: Dictionary = _emit_match_branch(child, p_indent + 1, p_context)
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok("\n".join(lines))


## Emits one match branch: pattern line + indented body.
## Patterns are verbatim atoms (pack them when needed, e.g. "1, 2",
## "[a, b]", "_"). Branch bodies hold plain statements only.
func _emit_match_branch(p_branch: Array, p_indent: int, p_context: String) -> Dictionary:
	if p_branch.size() < 3:
		return _fail("usage: (branch pattern body...) — e.g. (branch \"1\" (pass))")
	# Branch pattern, emitted verbatim.
	var pattern = p_branch[1]
	if not (pattern is String) or (pattern as String).is_empty():
		return _fail("branch pattern must be a non-empty string atom (pack patterns, e.g. \"1, 2\")")
	# Plain statements of the branch body.
	var body: Array = p_branch.slice(2)
	for stmt in body:
		if _is_branch(stmt):
			return _fail("branch bodies cannot hold further branch forms (nest a (match ...) instead)")
	# Pattern line + body indented one level deeper.
	var lines: Array = ["%s%s:" % [_indent_text(p_indent), pattern]]
	for stmt in body:
		# GDScript code of one branch statement, same context as the match.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, p_context)
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok("\n".join(lines))


## Dangling (branch ...) reached outside a (match ...) body. Always an error.
func _emit_branch_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("branch is only valid as a direct child of (match ...)")


## Emits `signal NAME` / `signal NAME(args)` from (signal NAME) /
## (signal NAME (args...)). Same argument grammar as func, but signals
## cannot declare a return type. Top level and class bodies.
func _emit_signal(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() < 2 or p_form.size() > 3:
		return _fail("usage: (signal name) or (signal name (args...)) — e.g. (signal hit) or (signal moved (from to))")
	# Signal name (non-empty String, never @: signals take no annotations).
	var sname = p_form[1]
	if not (sname is String) or (sname as String).is_empty() or (sname as String).begins_with("@"):
		return _fail("signal name must be a non-empty string")
	# Indentation prefix of the current level.
	var prefix: String = _indent_text(p_indent)
	if p_form.size() == 2:
		return _ok("%ssignal %s" % [prefix, sname])
	# Signal argument list with the shared signature grammar (no return).
	var sargs = p_form[2]
	if not (sargs is Array):
		return _fail("signal arguments must be a list — e.g. (signal moved (from to))")
	var parsed: Dictionary = _parse_signature(sargs)
	if not parsed["ok"]:
		return _fail(str(parsed["error"]))
	if not (parsed["return_type"] as String).is_empty():
		return _fail("signals cannot declare a return type")
	var srendered: Array = parsed["args"]
	return _ok("%ssignal %s(%s)" % [prefix, sname, ", ".join(srendered)])


## Emits `const NAME = VALUE` / `const NAME := VALUE` /
## `const NAME: TYPE = VALUE` from the matching (const ...) forms.
## Constants always need an initializer; (const NAME TYPE := VALUE) is invalid
## GDScript, like its var counterpart. Valid at any level, including funcs.
func _emit_const(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Arguments after the "const" operator.
	var args: Array = p_form.slice(1)
	for a in args:
		if not (a is String):
			return _fail("'const' arguments must be strings, not lists")
	if args.is_empty():
		return _fail("invalid 'const' form; usages: (const n = v), (const n := v), (const n T = v)")
	# Constant name (first positional slot, never @: consts take no annotations).
	var cname: String = args[0]
	if cname.is_empty() or cname == "=" or cname == ":=" or cname.begins_with("@"):
		return _fail("constant name must be a non-empty identifier (got '%s')" % cname)
	# Indentation prefix of the current level.
	var prefix: String = _indent_text(p_indent)
	if args.size() == 3 and args[1] == "=":
		if (args[2] as String).is_empty():
			return _fail("constant value must be a non-empty string")
		return _ok("%sconst %s = %s" % [prefix, cname, args[2]])
	if args.size() == 3 and args[1] == ":=":
		if (args[2] as String).is_empty():
			return _fail("constant value must be a non-empty string")
		return _ok("%sconst %s := %s" % [prefix, cname, args[2]])
	if args.size() == 4 and not (args[1] == "=" or args[1] == ":=") and args[2] == "=":
		if (args[1] as String).is_empty():
			return _fail("constant type must be a non-empty string")
		if (args[3] as String).is_empty():
			return _fail("constant value must be a non-empty string")
		return _ok("%sconst %s: %s = %s" % [prefix, cname, args[1], args[3]])
	if args.size() == 4 and args[2] == ":=":
		return _fail("'const %s: %s := ...' is invalid GDScript (type hint and inference cannot be combined)" % [cname, args[1]])
	return _fail("invalid 'const' form; usages: (const n = v), (const n := v), (const n T = v)")


## Emits `class Name:` + indented body from (class Name body...), with
## leading @ annotations each on their own line.
## Members run in "member" context: everything a top-level class has
## (extends, var, func, signal...) except class-name, which is file-level.
## Inner classes nest freely. Valid at the top level and in class bodies,
## not inside functions (GDScript has no local classes).
func _emit_class(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Leading annotations stripped first (never reach the grammar below).
	var split: Dictionary = _split_annotations(p_form.slice(1))
	if not split["ok"]:
		return _fail(str(split["error"]))
	var rest: Array = split["rest"]
	# Annotation lines prefixed to the successful exit below.
	var annotations: Array = split["annotations"]
	if rest.size() < 1:
		return _fail("usage: (class Name body...) — e.g. (class Inner (extends Node) (var x = 1))")
	# Inner class name (non-empty String, never @).
	var cname = rest[0]
	if not (cname is String) or (cname as String).is_empty() or (cname as String).begins_with("@"):
		return _fail("class name must be a non-empty string")
	# Member forms of the class body.
	var body: Array = rest.slice(1)
	if body.is_empty():
		return _fail("class '%s' has no body: GDScript requires at least one indented line" % cname)
	# Header line + members indented one level deeper, in member context.
	var lines: Array = ["%sclass %s:" % [_indent_text(p_indent), cname]]
	for stmt in body:
		# GDScript code of one member.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, "member")
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok(_prefix_annotations(annotations, p_indent, "\n".join(lines)))


## Splits leading @ atoms (annotations) from a form tail.
## Scanning stops at the first non-annotation (non-@ atom or list).
## Returns {"ok", "annotations": Array[String], "rest": Array, "error"}.
## A lone "@" is an error; annotations never reach the grammar that follows.
func _split_annotations(p_items: Array) -> Dictionary:
	# Leading annotation atoms, in order.
	var annotations: Array = []
	# Index of the first non-annotation item.
	var idx: int = 0
	while idx < p_items.size():
		# Current tail item, possibly an annotation.
		var item = p_items[idx]
		if not (item is String) or not (item as String).begins_with("@"):
			break
		if (item as String).length() < 2:
			return {"ok": false, "annotations": [], "rest": [], "error": "a lone \"@\" is not a valid annotation"}
		annotations.append(item)
		idx += 1
	return {"ok": true, "annotations": annotations, "rest": p_items.slice(idx), "error": ""}


## Prefixes annotation lines (verbatim, same indent) to emitted code.
## With no annotations the code passes through untouched.
func _prefix_annotations(p_annotations: Array, p_indent: int, p_code: String) -> String:
	if p_annotations.is_empty():
		return p_code
	# Annotation lines plus the declaration they attach to.
	var lines: Array = []
	for annotation in p_annotations:
		lines.append("%s%s" % [_indent_text(p_indent), annotation])
	lines.append(p_code)
	return "\n".join(lines)


## Consumes a leading (comment ...) body element as trailing declaration text.
## Returns {"ok", "trailing": " # text" or "", "rest": remaining body, "error"}.
func _take_trailing_comment(p_body: Array) -> Dictionary:
	# Suffix for the declaration line (empty when no leading comment).
	var trailing: String = ""
	# Body forms after the optional leading comment.
	var rest: Array = p_body.duplicate()
	# Head of the first body form, when it is a non-empty list.
	var first_head = null
	if not rest.is_empty() and rest[0] is Array and not (rest[0] as Array).is_empty():
		first_head = (rest[0] as Array)[0]
	if (first_head is String) and first_head == "comment" and (rest[0] as Array).size() > 1:
		# Text atoms of the trailing comment.
		var cargs: Array = (rest[0] as Array).slice(1)
		for c in cargs:
			if not (c is String):
				return {"ok": false, "trailing": "", "rest": [], "error": "'comment' arguments must be strings, not lists"}
		# Trailing comment text, with atoms joined by spaces.
		var ctext: String = " ".join(cargs)
		if not ctext.is_empty():
			trailing = " # " + ctext
		rest = rest.slice(1)
	return {"ok": true, "trailing": trailing, "rest": rest, "error": ""}


## Tells whether a value form is an inline lambda, i.e. a (lambda ...) list.
## Non-string heads (nested lists) are never lambdas — and never crash here.
func _is_lambda(p_value) -> bool:
	if not (p_value is Array):
		return false
	if (p_value as Array).is_empty():
		return false
	# Head of the candidate form.
	var lhead = (p_value as Array)[0]
	if not (lhead is String):
		return false
	return lhead == "lambda"


## Emits one value: a verbatim atom, a (lambda ...) form, or a call/infix
## expression or collection constructor (which also compose). p_owner names
## the value in error messages ("default value", "return value", ...).
func _emit_value(p_value, p_indent: int, p_owner: String) -> Dictionary:
	if p_value is String:
		if (p_value as String).is_empty():
			return _fail("%s must be a non-empty atom, a (lambda ...) or an expression" % p_owner)
		return _ok(p_value)
	if _is_lambda(p_value):
		return _emit_lambda_value(p_value, p_indent)
	if _is_expression(p_value) or _is_collection(p_value):
		return _emit_expression_code(p_value, p_indent)
	return _fail("%s must be a verbatim atom, a (lambda ...) or a (call ...)/(operator ...) expression (got '%s')" % [p_owner, str(p_value)])


## Emits an inline lambda value: `func(args):` / `func(args) -> R:` + body.
## The header carries no indentation (the caller places the line); body lines
## use p_indent + 1. Same signature grammar and trailing-comment rule as func.
func _emit_lambda_value(p_form: Array, p_indent: int) -> Dictionary:
	if p_form.size() < 2:
		return _fail("usage: (lambda (signature...) body...) — e.g. (lambda (x) (return x))")
	# Signature list: return type first, then arguments (see docs).
	var sig = p_form[1]
	if not (sig is Array):
		return _fail("'lambda' signature must be a list — e.g. (lambda (x) ...)")
	# Parsed return type ("") and rendered argument list.
	var parsed: Dictionary = _parse_signature(sig)
	if not parsed["ok"]:
		return _fail(str(parsed["error"]))
	var largs: Array = parsed["args"]
	# Return suffix (" -> Type") or empty when untyped.
	var retsuffix: String = ""
	if not (parsed["return_type"] as String).is_empty():
		retsuffix = " -> %s" % parsed["return_type"]
	# Lambda body forms (may start with a trailing-comment comment).
	var raw_body: Array = p_form.slice(2)
	# Leading (comment ...) consumed as the header trailing comment.
	var split: Dictionary = _take_trailing_comment(raw_body)
	if not split["ok"]:
		return _fail(str(split["error"]))
	var trailing: String = split["trailing"]
	var body: Array = split["rest"]
	if body.is_empty():
		return _fail("lambda has no body: GDScript requires at least one indented line")
	# Header line (no indentation: the caller places the line) + body deeper.
	var lines: Array = ["func(%s)%s:%s" % [", ".join(largs), retsuffix, trailing]]
	for stmt in body:
		# GDScript code of one lambda statement.
		var r: Dictionary = transpile_statement(stmt, p_indent + 1, "local")
		if not r["ok"]:
			return r
		lines.append(r["code"])
	return _ok("\n".join(lines))


## Dangling (lambda ...) reached as a statement instead of a value.
## Always an error: lambdas only live in value positions (var, return...).
func _emit_lambda_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("lambda is only valid as a value (var default, return value...) — e.g. (var cb = (lambda (x) (pass)))")


## Tells whether a form is a get/set accessor, i.e. a (get ...)/(set ...) list.
## Non-string heads (nested lists) are never accessors — and never crash here.
func _is_accessor(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var ahead = (p_form as Array)[0]
	if not (ahead is String):
		return false
	return ahead == "get" or ahead == "set"


## Emits one accessor block: (get BODY...) -> `get:` or
## (set (NAME) BODY...) -> `set(NAME):`, each + indented body in local context.
## Getters take no arguments and declare no return type; setters take exactly
## one bare parameter name (both probed against Godot 4.7.2).
func _emit_accessor(p_form: Array, p_indent: int) -> Dictionary:
	# Accessor kind: "get" or "set" (guaranteed by _is_accessor).
	var kind: String = (p_form as Array)[0]
	if kind == "get":
		# Getter body forms.
		var gbody: Array = (p_form as Array).slice(1)
		if gbody.is_empty():
			return _fail("usage: (get body...) — getter branch needs at least one statement")
		# Header line + body indented one level deeper, in local context.
		var glines: Array = ["%sget:" % _indent_text(p_indent)]
		for stmt in gbody:
			# GDScript code of one getter statement.
			var gr: Dictionary = transpile_statement(stmt, p_indent + 1, "local")
			if not gr["ok"]:
				return gr
			glines.append(gr["code"])
		return _ok("\n".join(glines))
	# Setter parameter list with exactly one bare name.
	if (p_form as Array).size() < 2:
		return _fail("usage: (set (name) body...) — e.g. (set (value) (pass))")
	var sargs = (p_form as Array)[1]
	if not (sargs is Array) or (sargs as Array).size() != 1:
		return _fail("set takes exactly one parameter name — e.g. (set (value) ...)")
	# Setter parameter name (bare atom; typed setter params are invalid GDScript).
	var sname = (sargs as Array)[0]
	if not (sname is String) or (sname as String).is_empty():
		return _fail("set parameter must be a non-empty name")
	# Setter body forms.
	var sbody: Array = (p_form as Array).slice(2)
	if sbody.is_empty():
		return _fail("usage: (set (name) body...) — setter branch needs at least one statement")
	# Header line + body indented one level deeper, in local context.
	var slines: Array = ["%sset(%s):" % [_indent_text(p_indent), sname]]
	for stmt in sbody:
		# GDScript code of one setter statement.
		var sr: Dictionary = transpile_statement(stmt, p_indent + 1, "local")
		if not sr["ok"]:
			return sr
		slines.append(sr["code"])
	return _ok("\n".join(slines))


## Dangling (get ...) reached outside a (var ...)/(static-var ...) tail.
## Always an error.
func _emit_get_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("get is only valid as a trailing form of (var ...)/(static-var ...)")


## Same-line reference text ("get = f") of an accessor with a single bare
## atom, or "" when the accessor is a block body. Single-side and valueless
## inline forms are valid GDScript; mixing inline and block in one declaration
## is not, so the caller rejects the mix.
func _accessor_inline_ref(p_form: Array) -> String:
	if (p_form as Array).size() == 2 and ((p_form as Array)[1] is String) and not ((p_form as Array)[1] as String).is_empty():
		return "%s = %s" % [(p_form as Array)[0], (p_form as Array)[1]]
	return ""


## Dangling (set ...) reached outside a (var ...)/(static-var ...) tail.
## Always an error.
func _emit_set_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("set is only valid as a trailing form of (var ...)/(static-var ...)")


## Dangling (include ...) reached the transpiler unresolved.
## Always an error: includes expand in the resolver stage, before transpiling.
func _emit_include_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("include forms must be resolved before transpiling")


## Dangling (block ...) reached the transpiler unresolved.
## Always an error: blocks splice in the template stage, before transpiling.
func _emit_block_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("block forms must be resolved before transpiling")


## Dangling (template-extends ...) reached the transpiler unresolved.
## Always an error: inheritance merges in the template stage, and the form is
## only valid as the first top-level form of a child template.
func _emit_template_extends_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("template-extends is only valid as the first top-level form of a child template")


## Dangling (defmacro ...) reached the transpiler uncollected.
## Always an error: definitions belong to the top level and vanish in the
## macro stage, before transpiling.
func _emit_defmacro_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("defmacro is only valid at the top level (collected before transpiling)")


## Dangling (join ...) reached the transpiler uncollapsed.
## Always an error: join helpers only collapse inside macro bodies.
func _emit_join_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("join is only valid inside macro bodies")


## Dangling (super) reached the transpiler unfilled.
## Always an error: super placeholders only fill inside an overriding child
## block (a parentless super has no default content to copy).
func _emit_super_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("super is only valid inside an overriding child block")


## Dangling (upper ...) reached the transpiler uncollapsed.
## Always an error: case helpers only collapse inside macro bodies.
func _emit_upper_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("upper is only valid inside macro bodies")


## Dangling (lower ...) reached the transpiler uncollapsed.
## Always an error: case helpers only collapse inside macro bodies.
func _emit_lower_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("lower is only valid inside macro bodies")


## Dangling (capitalize ...) reached the transpiler uncollapsed.
## Always an error: case helpers only collapse inside macro bodies.
func _emit_capitalize_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("capitalize is only valid inside macro bodies")


## Dangling (for-generate ...) reached the transpiler unexpanded.
## Always an error: generation unrolls in the macro stage, before transpiling.
func _emit_for_generate_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("for-generate is only valid in statement and element positions (unrolled before transpiling)")


## Dangling (template-set ...) reached the transpiler unevaluated.
## Always an error: template variables bind in the macro stage.
func _emit_template_set_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("template-set is evaluated before transpiling (nothing should reach here)")


## Dangling (tvar ...) reached the transpiler unresolved.
## Always an error: template variables paste in the macro stage.
func _emit_tvar_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("tvar is resolved before transpiling (nothing should reach here)")


## Dangling (when ...) reached the transpiler unevaluated.
## Always an error: conditional inclusion runs in the macro stage.
func _emit_when_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("when is evaluated before transpiling (nothing should reach here)")


## Dangling (when-not ...) reached the transpiler unevaluated.
## Always an error: conditional inclusion runs in the macro stage.
func _emit_when_not_dangling(p_form: Array, _p_indent: int, _p_context: String) -> Dictionary:
	return _fail("when-not is evaluated before transpiling (nothing should reach here)")


## Tells whether a form is a call, chain, await, ternary or infix/logic expression.
## Used for operands, call arguments and values. Lambdas and collections are
## handled on their own paths. Non-string heads never match — never crash.
func _is_expression(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var ehead = (p_form as Array)[0]
	if not (ehead is String):
		return false
	return ehead == "call" or ehead == "chain" or ehead == "await" or ehead == "ternary" or ehead in INFIX_OPS


## Tells whether a nested operand needs parentheses: infix/logic, await and
## ternary heads (loose binders); calls, chains, collections and atoms never do.
func _needs_parens(p_head: String) -> bool:
	return p_head in INFIX_OPS or p_head == "await" or p_head == "ternary"


## Tells whether a form is an array/dict constructor (possibly multiline).
## Used for operands, arguments, values and elements. Non-string heads
## (nested lists) are never collections — never crash here.
func _is_collection(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var chead = (p_form as Array)[0]
	if not (chead is String):
		return false
	return chead in COLLECTION_OPS


## Emits one operand/argument/element: verbatim atom, nested single-line
## expression or nested collection. p_paren_infix wraps nested infix operands
## in parentheses (precedence-safe); p_indent feeds multiline collections.
## Lambdas are rejected with guidance (bind to a var first).
func _emit_operand(p_operand, p_paren_infix: bool, p_indent: int) -> Dictionary:
	if p_operand is String:
		if (p_operand as String).is_empty():
			return _fail("operand must be a non-empty atom or an expression")
		return _ok(p_operand)
	if _is_expression(p_operand):
		# Nested expression code (await included).
		var nested: Dictionary = _emit_expression_code(p_operand, p_indent)
		if not nested["ok"]:
			return nested
		if p_paren_infix and _needs_parens((p_operand as Array)[0]):
			return _ok("(%s)" % nested["code"])
		return nested
	if _is_collection(p_operand):
		return _emit_collection_code(p_operand, p_indent)
	if _is_lambda(p_operand):
		return _fail("lambdas cannot nest inside operands, arguments or elements — bind to a var first")
	return _fail("operand must be a value or a (call ...)/(chain ...)/(operator ...)/(collection ...) expression (got '%s')" % str(p_operand))


## Emits expression code (no leading indentation): call, chain, await,
## ternary, infix or collection. Single-line except collections, which carry
## absolute continuation lines. The form must satisfy _is_expression or _is_collection.
func _emit_expression_code(p_form: Array, p_indent: int) -> Dictionary:
	# Expression head: "call", "chain", "await", "ternary", infix or collection.
	var head: String = (p_form as Array)[0]
	if head == "call":
		return _emit_call_code(p_form, p_indent)
	if head == "chain":
		return _emit_chain_code(p_form, p_indent)
	if head == "await":
		return _emit_await_code(p_form, p_indent)
	if head == "ternary":
		return _emit_ternary_code(p_form, p_indent)
	if head in INFIX_OPS:
		return _emit_infix_code(p_form, p_indent)
	return _emit_collection_code(p_form, p_indent)


## Emits `NAME(a1, a2)` from (call NAME ARGS...); zero args give `NAME()`.
## Names are verbatim atoms (plain and dotted names work bare); arguments are
## verbatim atoms or nested expressions (collections included).
func _emit_call_code(p_form: Array, p_indent: int) -> Dictionary:
	if p_form.size() < 2:
		return _fail("usage: (call name args...) — e.g. (call print x)")
	# Called target: verbatim atom, or a nested expression whose value gets
	# invoked (e.g. (call (call f x) 1) calls the returned callable).
	var cname = p_form[1]
	# Rendered target (loose binders parenthesized, calls/chains already grouped).
	var target: String = ""
	if cname is String:
		if (cname as String).is_empty():
			return _fail("call target must be a non-empty atom or an expression")
		target = cname
	elif _is_expression(cname):
		var tres: Dictionary = _emit_operand(cname, true, p_indent)
		if not tres["ok"]:
			return tres
		target = tres["code"]
	elif _is_lambda(cname):
		return _fail("lambdas cannot nest inside operands, arguments or elements — bind to a var first")
	else:
		return _fail("call target must be a non-empty atom or a (call ...)/(chain ...) expression (got '%s')" % str(cname))
	# Rendered argument list.
	var rendered: Array = []
	for arg in (p_form as Array).slice(2):
		# One argument, never wrapped (call parens already group).
		var ares: Dictionary = _emit_operand(arg, false, p_indent)
		if not ares["ok"]:
			return ares
		rendered.append(ares["code"])
	return _ok("%s(%s)" % [target, ", ".join(rendered)])


## Emits `a OP b ...` from (OP ...): n-ary (+ * and or), binary or more
## (- / % ** comparisons, shifts, bitwise, is/as/in), unary minus (- x),
## unary not (not x) and unary bit-not (~ x). Operands are verbatim atoms or
## nested expressions, loose binders parenthesized (see _needs_parens).
func _emit_infix_code(p_form: Array, p_indent: int) -> Dictionary:
	# Operator head (one of INFIX_OPS, guaranteed by table/expression checks).
	var op: String = (p_form as Array)[0]
	# Operand forms after the operator.
	var operands: Array = (p_form as Array).slice(1)
	# Whether this is a prefix unary form: (not x), (- x) or (~ x).
	var is_unary: bool = false
	if op == "not" or op == "~":
		if operands.size() != 1:
			return _fail("usage: (%s x) — %s takes exactly one operand" % [op, op])
		is_unary = true
	elif op == "-" and operands.size() == 1:
		is_unary = true
	elif operands.size() < 2:
		return _fail("usage: (%s a b ...) — %s needs at least two operands" % [op, op])
	# Rendered operands, nested infix ones parenthesized.
	var rendered: Array = []
	for operand in operands:
		# One operand, parenthesized when infix-headed.
		var ores: Dictionary = _emit_operand(operand, true, p_indent)
		if not ores["ok"]:
			return ores
		rendered.append(ores["code"])
	# Separator with single spaces: `a + b`, `x == y`, `a and b`.
	var sep: String = " %s " % op
	if op == "not":
		return _ok("not %s" % rendered[0])
	if op == "~":
		return _ok("~%s" % rendered[0])
	if is_unary:
		return _ok("-%s" % rendered[0])
	return _ok(sep.join(rendered))


## Emits a call statement from (call ...). Valid at any level.
func _emit_call(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Call code without indentation (always single-line).
	var r: Dictionary = _emit_call_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits `root.link(...).prop` from (chain root links...): each list link
## appends `.name(args)` and each bare-atom link appends `.name` (property
## access). Root is a verbatim atom or a nested expression (chains compose
## in root position); links never nest. Single-line, like call.
func _emit_chain_code(p_form: Array, p_indent: int) -> Dictionary:
	if p_form.size() < 3:
		return _fail("usage: (chain root (method args...)... [prop]...) — e.g. (chain myobj (qwer 0) (asdf 1))")
	# Chain root: verbatim atom or nested expression (loose binders parenthesized).
	var root = p_form[1]
	var rres: Dictionary = _emit_operand(root, true, p_indent)
	if not rres["ok"]:
		return rres
	# Rendered chain, one dot segment per link.
	var code: String = rres["code"]
	for link in (p_form as Array).slice(2):
		if link is String:
			if (link as String).is_empty():
				return _fail("chain property must be a non-empty atom")
			code += "." + link
		elif (link is Array) and not (link as Array).is_empty() and ((link as Array)[0] is String) and not (((link as Array)[0] as String).is_empty()):
			# Link method name (verbatim, dotted names pass through).
			var mname: String = (link as Array)[0]
			# Rendered link arguments, never wrapped (link parens group).
			var rendered: Array = []
			for arg in (link as Array).slice(1):
				var ares: Dictionary = _emit_operand(arg, false, p_indent)
				if not ares["ok"]:
					return ares
				rendered.append(ares["code"])
			code += ".%s(%s)" % [mname, ", ".join(rendered)]
		else:
			return _fail("chain links must be property atoms or (method args...) lists (got '%s')" % str(link))
	return _ok(code)


## Emits a chained-call statement from (chain ...). Valid at any level.
func _emit_chain(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Chain code without indentation (always single-line).
	var r: Dictionary = _emit_chain_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits an infix/logic statement from (OP ...). Valid at any level.
func _emit_infix_statement(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Expression code without indentation (always single-line).
	var r: Dictionary = _emit_infix_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits `TARGET OP VALUE` from (assign TARGET OP VALUE), OP in ASSIGN_OPS.
## Targets are verbatim atoms (plain, dotted and subscripted names work bare);
## values accept the full _emit_value range (atoms, calls, arithmetic, lambda).
## Assignment is a statement only — never a value. Valid at any level.
func _emit_assign(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 4:
		return _fail("usage: (assign target op value) — e.g. (assign x = 5), (assign x += 1)")
	# Assignment target (verbatim atom).
	var target = p_form[1]
	if not (target is String) or (target as String).is_empty():
		return _fail("assign target must be a non-empty string")
	# Compound operator, validated against the probed ASSIGN_OPS set.
	var op = p_form[2]
	if not (op is String) or not (op in ASSIGN_OPS):
		return _fail("assign operator must be one of =, +=, -=, *=, /=, %%=, <<=, >>=, &=, |=, ^=, **= (got '%s')" % str(op))
	# Assigned value in the full value range.
	var vres: Dictionary = _emit_value(p_form[3], p_indent, "assign value")
	if not vres["ok"]:
		return vres
	return _ok("%s%s %s %s" % [_indent_text(p_indent), target, op, vres["code"]])


## Emits collection code (first line bare, continuation absolute):
## (array ...) / (dict-lua ...) / (dict-json ...). The form must satisfy
## _is_collection (checked by callers).
func _emit_collection_code(p_form: Array, p_indent: int) -> Dictionary:
	# Collection head: "array", "dict-lua" or "dict-json" (String, guaranteed).
	var head: String = (p_form as Array)[0]
	if head == "array":
		return _emit_array_code(p_form, p_indent)
	if head == "dict-lua":
		return _emit_dict_code(p_form, p_indent, " = ")
	return _emit_dict_code(p_form, p_indent, ": ")


## Emits `[...]` from (array E...): `[]` when empty, otherwise one indented
## element line each with trailing comma. Elements are verbatim atoms or
## nested expressions/collections (lambdas rejected with guidance).
func _emit_array_code(p_form: Array, p_indent: int) -> Dictionary:
	# Element forms after the operator.
	var elements: Array = (p_form as Array).slice(1)
	if elements.is_empty():
		return _ok("[]")
	# Opener + one indented element line each + closer at this level.
	var lines: Array = ["["]
	for element in elements:
		# Element code without leading indentation (this loop places it).
		var eres: Dictionary = _emit_operand(element, false, p_indent + 1)
		if not eres["ok"]:
			return eres
		lines.append("%s%s," % [_indent_text(p_indent + 1), eres["code"]])
	lines.append("%s]" % _indent_text(p_indent))
	return _ok("\n".join(lines))


## Emits `{...}` from (dict-lua (K V)...) / (json-dict (K V)...): `{}` when
## empty, otherwise one `K SEP V,` line each. Pairs must be 2-sublists; keys
## and values follow the same element rules as arrays.
func _emit_dict_code(p_form: Array, p_indent: int, p_sep: String) -> Dictionary:
	# Pair forms after the operator.
	var pairs: Array = (p_form as Array).slice(1)
	if pairs.is_empty():
		return _ok("{}")
	# Opener + one indented pair line each + closer at this level.
	var lines: Array = ["{"]
	for pair in pairs:
		if not (pair is Array) or (pair as Array).size() != 2:
			return _fail("dict entries must be (key value) pairs (got '%s')" % str(pair))
		# Key and value without leading indentation (this loop places them).
		var kres: Dictionary = _emit_operand((pair as Array)[0], false, p_indent + 1)
		if not kres["ok"]:
			return kres
		var vres: Dictionary = _emit_operand((pair as Array)[1], false, p_indent + 1)
		if not vres["ok"]:
			return vres
		lines.append("%s%s%s%s," % [_indent_text(p_indent + 1), kres["code"], p_sep, vres["code"]])
	lines.append("%s}" % _indent_text(p_indent))
	return _ok("\n".join(lines))


## Emits an array statement from (array ...). Valid at any level.
func _emit_array(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Collection code without leading indentation (placed here).
	var r: Dictionary = _emit_collection_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits a Lua-style dict statement from (dict-lua ...). Valid at any level.
func _emit_dict_lua(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Collection code without leading indentation (placed here).
	var r: Dictionary = _emit_collection_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits a JSON-style dict statement from (dict-json ...). Valid at any level.
func _emit_dict_json(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Collection code without leading indentation (placed here).
	var r: Dictionary = _emit_collection_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits `await X` from (await X): exactly one operand, verbatim atom or
## nested expression. Statement, value and operand positions all work.
## Valid at any level.
func _emit_await_code(p_form: Array, p_indent: int) -> Dictionary:
	if p_form.size() != 2:
		return _fail("usage: (await x) — e.g. (await ready)")
	# Awaited expression, never wrapped (await binds loosest by itself).
	var ores: Dictionary = _emit_operand((p_form as Array)[1], false, p_indent)
	if not ores["ok"]:
		return ores
	return _ok("await %s" % ores["code"])


## Emits an await statement from (await ...). Valid at any level.
func _emit_await(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Await code without indentation (always single-line).
	var r: Dictionary = _emit_await_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])


## Emits `assert(C)` / `assert(C, MSG)` from (assert C) / (assert C MSG).
## Arguments are verbatim atoms or nested single-line expressions.
## Statement only — never a value. Valid at any level.
func _emit_assert(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 2 and p_form.size() != 3:
		return _fail("usage: (assert cond) or (assert cond msg) — e.g. (assert ok)")
	# Rendered argument list.
	var rendered: Array = []
	for arg in (p_form as Array).slice(1):
		# One argument, never wrapped (call parens already group).
		var ares: Dictionary = _emit_operand(arg, false, p_indent)
		if not ares["ok"]:
			return ares
		rendered.append(ares["code"])
	return _ok("%sassert(%s)" % [_indent_text(p_indent), ", ".join(rendered)])


## Emits `breakpoint` from (breakpoint): no parentheses, no arguments.
## Statement only — never a value. Valid at any level.
func _emit_breakpoint(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	if p_form.size() != 1:
		return _fail("usage: (breakpoint) — takes no arguments")
	return _ok("%sbreakpoint" % _indent_text(p_indent))


## Emits `enum { ... }` / `enum Name { ... }` from (enum ENTRIES...) /
## (enum (NAME) ENTRIES...): a leading 1-sublist names the enum, anything
## else is flat anonymous entries. Entries are bare atoms, (N) or (N V);
## values accept nested expressions. Empty enums stay single-line.
## Top level and class bodies (GDScript has no local enums).
func _emit_enum(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Tail after the operator.
	var tail: Array = (p_form as Array).slice(1)
	# Enum name ("") and entry forms.
	var ename: String = ""
	var entries: Array = tail
	if not tail.is_empty() and tail[0] is Array and (tail[0] as Array).size() == 1 and ((tail[0] as Array)[0] is String) and not (((tail[0] as Array)[0] as String).is_empty()):
		ename = (tail[0] as Array)[0]
		entries = tail.slice(1)
	if entries.is_empty():
		if ename.is_empty():
			return _ok("%senum {}" % _indent_text(p_indent))
		return _ok("%senum %s {}" % [_indent_text(p_indent), ename])
	# Opener + one indented entry line each + closer at this level.
	var lines: Array = []
	if ename.is_empty():
		lines.append("%senum {" % _indent_text(p_indent))
	else:
		lines.append("%senum %s {" % [_indent_text(p_indent), ename])
	for entry in entries:
		# Rendered entry line without trailing comma (added below).
		var eres: Dictionary = _emit_enum_entry(entry, p_indent)
		if not eres["ok"]:
			return eres
		lines.append("%s%s," % [_indent_text(p_indent + 1), eres["code"]])
	lines.append("%s}" % _indent_text(p_indent))
	return _ok("\n".join(lines))


## Emits one enum entry: bare atom, (N) or (N V) with nested value allowed.
func _emit_enum_entry(p_entry, p_indent: int) -> Dictionary:
	if p_entry is String:
		if (p_entry as String).is_empty():
			return _fail("enum entry must be a non-empty name")
		return _ok(p_entry)
	if p_entry is Array and (p_entry as Array).size() == 1 and ((p_entry as Array)[0] is String) and not (((p_entry as Array)[0] as String).is_empty()):
		return _ok((p_entry as Array)[0])
	if p_entry is Array and (p_entry as Array).size() == 2 and ((p_entry as Array)[0] is String) and not (((p_entry as Array)[0] as String).is_empty()):
		# Entry value in full operand range (constant-foldable in practice).
		var vres: Dictionary = _emit_operand((p_entry as Array)[1], false, p_indent)
		if not vres["ok"]:
			return vres
		return _ok("%s = %s" % [(p_entry as Array)[0], vres["code"]])
	return _fail("enum entries must be names, (N) or (N value) (got '%s')" % str(p_entry))


## Emits `A if C else B` from (ternary C A B): GDScript's conditional
## expression with Lisp-side order (condition first). All three sides accept
## the full operand range, nested loose binders parenthesized.
## Statement, value and operand positions all work. Valid at any level.
func _emit_ternary_code(p_form: Array, p_indent: int) -> Dictionary:
	if p_form.size() != 4:
		return _fail("usage: (ternary cond then else) — e.g. (ternary ok 1 0)")
	# Condition, then and else sides, each parenthesized when loose.
	var cres: Dictionary = _emit_operand((p_form as Array)[1], true, p_indent)
	if not cres["ok"]:
		return cres
	var tres: Dictionary = _emit_operand((p_form as Array)[2], true, p_indent)
	if not tres["ok"]:
		return tres
	var eres: Dictionary = _emit_operand((p_form as Array)[3], true, p_indent)
	if not eres["ok"]:
		return eres
	return _ok("%s if %s else %s" % [tres["code"], cres["code"], eres["code"]])


## Emits a ternary statement from (ternary ...). Valid at any level.
func _emit_ternary(p_form: Array, p_indent: int, _p_context: String) -> Dictionary:
	# Ternary code without indentation (always single-line).
	var r: Dictionary = _emit_ternary_code(p_form, p_indent)
	if not r["ok"]:
		return r
	return _ok("%s%s" % [_indent_text(p_indent), r["code"]])
