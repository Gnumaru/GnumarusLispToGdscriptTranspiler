## Macro expander for the Gnumarus transpiler Lisp dialect.
##
## Implements user-defined syntactic macros: (defmacro NAME (PARAMS...) BODY)
## declares a single-form template, and (NAME ARGS...) call sites are replaced
## by the body with arguments substituted as raw subtrees (non-hygienic, like
## C macros — arguments with side effects evaluate once per pasted copy).
## Parameters are bare names; at most one trailing ...rest parameter splices
## any number of arguments where its atom appears. (join A B...) inside bodies
## concatenates atom parts after substitution (building dotted names and
## quoted literals); (upper X), (lower X) and (capitalize X) convert case the
## same way. (template-set NAME VALUE) binds template variables (expanded at
## set time, redefinable); (tvar NAME) pastes the value; (when NAME BODY...)
## splices BODY iff NAME is defined and truthy (only "" and "false" are
## falsy), (when-not NAME BODY...) inverts. Evaluation is sequential in
## encounter order with one flat environment (no scoping); undefined names
## are errors, never silent. (for-generate (VAR SOURCE) BODY...) unrolls template iteration:
## SOURCE is (range A B [STEP]) (Python-style, end-exclusive) or a literal
## value list; each iteration splices BODY copies with VAR bound to the value,
## so generation composes with macros (bodies may call macros, macro bodies
## may generate). Statement/element positions only: single-value slots
## (var defaults, operands...) fail fast here with a clear error naming
## both forms instead of leaking confusing errors downstream.
## Macros may use other macros; expansion recurses
## depth-first until no macro heads remain. A budget bounds total expansions
## and generated iterations (self- and mutually-recursive macros fail instead
## of hanging). Runs after template resolution and before transpiling.
## Non-string heads never match — never crash.
class_name GnumarusLispToGdscriptTranspilerMacroExpander
extends RefCounted


## Transpiler script, loaded by path (reserved names and the live infix list).
const TranspilerScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerTranspiler.gd")
## Maximum total node expansions before giving up (recursion guard).
const MAX_MACRO_EXPANSIONS: int = 1024
## Maximum nested macro expansions (depth guard: GDScript stacks overflow
## near a thousand nested frames, so this stays far below that).
const MAX_MACRO_DEPTH: int = 64


## Collects top-level (defmacro ...) forms, removes them, and expands every
## macro call in the tree. Returns {"ok": true, "tree": Array, "error": ""}
## or a failure naming the offending macro.
static func expand(p_tree: Array, p_max_expansions: int = MAX_MACRO_EXPANSIONS) -> Dictionary:
	# Macros by name: {"params": Array[String], "rest": String, "body": Array}.
	var macros: Dictionary = {}
	# Tree without macro definitions.
	var code: Array = []
	for form in p_tree:
		if _is_defmacro(form):
			# Definition validated and stored (emits no code).
			var defed: Dictionary = _define_macro(form, macros)
			if not defed["ok"]:
				return {"ok": false, "tree": [], "error": defed["error"]}
		else:
			code.append(form)
	# Shared expansion counter (single-element Array, by reference).
	var counter: Array = [0]
	# Flat template variable environment (name -> expanded value node).
	var env: Dictionary = {}
	# Fully expanded output tree.
	var out: Array = []
	for form in code:
		# One top-level form expanded depth-first (nesting starts at zero).
		var expanded: Dictionary = _expand_node(form, macros, env, counter, 0, p_max_expansions, MAX_MACRO_DEPTH)
		if not expanded["ok"]:
			return {"ok": false, "tree": [], "error": expanded["error"]}
		_append_expanded(out, expanded)
	return {"ok": true, "tree": out, "error": ""}


## Tells whether a form is a (defmacro ...) list (String head required).
static func _is_defmacro(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "defmacro"


## Validates one (defmacro NAME (PARAMS...) BODY) form and stores it.
## BODY must be a single list form; params are bare names with at most one
## trailing ...rest. p_macros is filled in place.
static func _define_macro(p_form: Array, p_macros: Dictionary) -> Dictionary:
	if (p_form as Array).size() != 4:
		return {"ok": false, "error": "usage: (defmacro name (params...) body) with a single body form"}
	# Macro name (non-empty String).
	var mname = (p_form as Array)[1]
	if not (mname is String) or (mname as String).is_empty():
		return {"ok": false, "error": "macro name must be a non-empty string"}
	if p_macros.has(mname):
		return {"ok": false, "error": "duplicate macro \"%s\"" % mname}
	# Reserved names collide with transpiler operations (checked live).
	var probe: RefCounted = TranspilerScript.new()
	if probe.has_operation(mname):
		return {"ok": false, "error": "macro name \"%s\" is reserved (an operation already exists)" % mname}
	# Parameter list (Array of bare names).
	var params = (p_form as Array)[2]
	if not (params is Array):
		return {"ok": false, "error": "macro parameters must be a list — e.g. (defmacro m (a b) ...)"}
	# Normal parameters in order.
	var normal: Array = []
	# Rest parameter name ("") when absent.
	var rest: String = ""
	for param in (params as Array):
		if not (param is String) or (param as String).is_empty():
			return {"ok": false, "error": "macro parameters must be non-empty names"}
		if (param as String).begins_with("..."):
			if (param as String).length() <= 3:
				return {"ok": false, "error": "rest parameter needs a name — e.g. ...args"}
			if not rest.is_empty():
				return {"ok": false, "error": "at most one rest parameter per macro"}
			rest = param
		elif not rest.is_empty():
			return {"ok": false, "error": "rest parameter must come last"}
		elif param in normal:
			return {"ok": false, "error": "duplicate macro parameter \"%s\"" % param}
		else:
			normal.append(param)
	# Body must be a single list form (splice-free expansion everywhere).
	var body = (p_form as Array)[3]
	if not (body is Array):
		return {"ok": false, "error": "macro body must be a single list form"}
	p_macros[mname] = {"params": normal, "rest": rest, "body": body}
	return {"ok": true, "error": ""}


## Expands one node depth-first. Template forms (set/tvar/when/for-generate)
## evaluate against the flat environment; macro calls substitute, collapse
## helpers and recurse; anything else recurses into children untouched.
## p_counter[0] counts expansions against p_max; p_depth counts nested
## expansions against p_max_depth (tree walking never consumes depth).
## p_owner names the enclosing single-value slot ("" in statement position):
## splice markers (for-generate/when/template-set) landing there fail fast
## with a clear error instead of confusing the transpiler downstream.
static func _expand_node(p_node, p_macros: Dictionary, p_env: Dictionary, p_counter: Array, p_depth: int, p_max: int, p_max_depth: int, p_owner: String = "") -> Dictionary:
	if not (p_node is Array) or (p_node as Array).is_empty():
		return {"ok": true, "node": p_node, "error": ""}
	# Head of the candidate call form.
	var head = (p_node as Array)[0]
	# Splice producers never belong in single-value slots: name both forms.
	if not p_owner.is_empty() and (head is String) and (head == "for-generate" or head == "when" or head == "when-not" or head == "template-set"):
		return {"ok": false, "node": null, "error": "(%s ...) cannot be used as a single value (here: inside (%s ...)) — it expands to zero or multiple forms, so it is only valid in statement positions" % [head, p_owner]}
	if (head is String) and head == "for-generate":
		return _expand_generate(p_node, p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
	if (head is String) and head == "template-set":
		return _expand_set(p_node, p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
	if (head is String) and head == "tvar":
		return _expand_tvar(p_node, p_env)
	if (head is String) and (head == "when" or head == "when-not"):
		return _expand_when(p_node, p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
	if (head is String) and p_macros.has(head):
		# Macro definition for this call site.
		var macro: Dictionary = p_macros[head]
		# Raw argument subtrees (never pre-expanded: pasted opaquely).
		var args: Array = (p_node as Array).slice(1)
		if not (macro["rest"] as String).is_empty():
			if args.size() < (macro["params"] as Array).size():
				return {"ok": false, "node": null, "error": "macro \"%s\" expects at least %d arguments (got %d)" % [head, (macro["params"] as Array).size(), args.size()]}
		elif args.size() != (macro["params"] as Array).size():
			return {"ok": false, "node": null, "error": "macro \"%s\" expects %d arguments (got %d)" % [head, (macro["params"] as Array).size(), args.size()]}
		# Normal parameter bindings (name -> raw subtree).
		var bindings: Dictionary = {}
		for i in range((macro["params"] as Array).size()):
			bindings[(macro["params"] as Array)[i]] = args[i]
		# Rest arguments spliced where the rest atom appears.
		var rest_args: Array = args.slice((macro["params"] as Array).size())
		# Body with parameters substituted.
		var subst: Dictionary = _subst_list(macro["body"], bindings, macro["rest"], rest_args)
		if not subst["ok"]:
			return {"ok": false, "node": null, "error": subst["error"]}
		p_counter[0] += 1
		if p_counter[0] > p_max:
			return {"ok": false, "node": null, "error": "macro expansion budget exhausted (%d expansions) — possible recursive macro" % p_max}
		if p_depth + 1 > p_max_depth:
			return {"ok": false, "node": null, "error": "macro expansion nesting beyond maximum depth (%d) — possible recursive macro" % p_max_depth}
		# Inner calls expanded before helper collapsing (calls may yield atoms).
		# The call-site slot carries over: a splice body in a value slot fails here.
		var inner: Dictionary = _expand_node(subst["list"], p_macros, p_env, p_counter, p_depth + 1, p_max, p_max_depth, p_owner)
		if not inner["ok"]:
			return inner
		# Helpers collapsed after everything inside expanded.
		var collapsed: Dictionary = _collapse_helpers(inner["node"])
		if not collapsed["ok"]:
			return {"ok": false, "node": null, "error": collapsed["error"]}
		return {"ok": true, "node": collapsed["node"], "error": ""}
	# Ordinary form: recurse into children (same nesting depth).
	var out: Array = []
	# Owner head for single-value errors ("" when headless or in statements).
	var owner: String = head if (head is String) else ""
	for i in range((p_node as Array).size()):
		# Whether child i is a single-value slot of this form.
		var slot: String = owner if _is_value_slot(p_node, i) else ""
		# One child expanded depth-first.
		var child: Dictionary = _expand_node((p_node as Array)[i], p_macros, p_env, p_counter, p_depth, p_max, p_max_depth, slot)
		if not child["ok"]:
			return child
		_append_expanded(out, child)
	return {"ok": true, "node": out, "error": ""}


## Tells whether child p_idx of p_form is a single-value slot (exactly one
## value in: var defaults, return values, call args, operands...) as opposed
## to statement lists or collection elements (multi-form splices glue in
## place there). Unknown heads (macro calls, future operations) never flag:
## their arguments paste opaquely and validate at the use site.
static func _is_value_slot(p_form: Array, p_idx: int) -> bool:
	# Head positions never hold values (atoms by grammar).
	if p_idx == 0:
		return false
	# Head of the form (non-string heads hold no value slots).
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	# Argument index of the child (head itself excluded).
	var arg: int = p_idx - 1
	match head:
		"var", "static-var":
			# Default by shape prefix: (n = X) third slot, (n T = X)
			# fourth (trailing get/set accessors never count as values).
			if (p_form as Array).size() >= 4 and ((p_form as Array)[2] is String) and ((p_form as Array)[2] == "=" or (p_form as Array)[2] == ":="):
				return arg == 2
			if (p_form as Array).size() >= 5 and ((p_form as Array)[3] is String) and (p_form as Array)[3] == "=":
				return arg == 3
			return false
		"const":
			# Same shape prefixes as var (constants take no accessors).
			if (p_form as Array).size() >= 4 and ((p_form as Array)[2] is String) and ((p_form as Array)[2] == "=" or (p_form as Array)[2] == ":="):
				return arg == 2
			if (p_form as Array).size() >= 5 and ((p_form as Array)[3] is String) and (p_form as Array)[3] == "=":
				return arg == 3
			return false
		"return":
			return (p_form as Array).size() >= 2 and arg == 0
		"assign":
			return (p_form as Array).size() >= 3 and arg == 2
		"call", "assert":
			# Every argument is one value (name included: it must be one atom).
			return arg >= 0
		"chain":
			# Root and every link hold one segment (splice bodies would
			# silently become method links, so they fail fast instead).
			return (p_form as Array).size() >= 2 and arg >= 0
		"ternary":
			return arg >= 0 and arg <= 2
		"await":
			return (p_form as Array).size() == 2 and arg == 0
		"if", "elif", "while", "match":
			# Conditions and the match subject are single expressions.
			return (p_form as Array).size() >= 2 and arg == 0
		"for":
			# Iterable by shape: (n in I ...) third slot, (n T in I ...) fifth.
			if (p_form as Array).size() >= 5 and ((p_form as Array)[2] is String) and (p_form as Array)[2] == "in":
				return arg == 2
			if (p_form as Array).size() >= 6 and ((p_form as Array)[3] is String) and (p_form as Array)[3] == "in":
				return arg == 4
			return false
	if (head as String) in TranspilerScript.INFIX_OPS:
		# Every operand is one value (unary and n-ary alike).
		return arg >= 0
	return false


## Appends an expanded child to a form list, splicing multi-form
## (for-generate ...) results in place. Markers only reach spliceable
## lists: single-value slots fail fast in _expand_node before markers arise.
static func _append_expanded(p_out: Array, p_expanded: Dictionary) -> void:
	# Expanded node (single node or splice marker).
	var node = p_expanded["node"]
	if (node is Dictionary) and (node as Dictionary).has("splice"):
		for spliced in ((node as Dictionary)["splice"] as Array):
			p_out.append(spliced)
	else:
		p_out.append(node)


## Binds one template variable: (template-set NAME VALUE) expands VALUE now
## (macros and generators run with the macros known upfront and the
## environment so far) and stores it, redefining any previous binding.
## Emits nothing (empty splice). p_env is filled in place.
static func _expand_set(p_node: Array, p_macros: Dictionary, p_env: Dictionary, p_counter: Array, p_depth: int, p_max: int, p_max_depth: int) -> Dictionary:
	if (p_node as Array).size() != 3:
		return {"ok": false, "node": null, "error": "usage: (template-set name value) with a single value"}
	# Variable name (bare non-empty atom).
	var vname = (p_node as Array)[1]
	if not (vname is String) or (vname as String).is_empty():
		return {"ok": false, "node": null, "error": "template variable name must be a non-empty string"}
	# Value expanded now (fail fast, current environment; a splice body
	# in this single slot fails here naming template-set).
	var expanded: Dictionary = _expand_node((p_node as Array)[2], p_macros, p_env, p_counter, p_depth, p_max, p_max_depth, "template-set")
	if not expanded["ok"]:
		return expanded
	p_env[vname] = expanded["node"]
	return {"ok": true, "node": {"splice": []}, "error": ""}


## Pastes one template variable: (tvar NAME) becomes the stored value node
## (already expanded at set time, pasted as-is). Undefined names are errors.
static func _expand_tvar(p_node: Array, p_env: Dictionary) -> Dictionary:
	if (p_node as Array).size() != 2 or not ((p_node as Array)[1] is String):
		return {"ok": false, "node": null, "error": "usage: (tvar name) with a template variable name"}
	# Referenced variable name.
	var vname: String = (p_node as Array)[1]
	if not p_env.has(vname):
		return {"ok": false, "node": null, "error": "undefined template variable \"%s\"" % vname}
	return {"ok": true, "node": p_env[vname], "error": ""}


## Tells whether a stored template value counts as true: only the atoms ""
## and "false" are falsy (every list and other atom is truthy).
static func _is_truthy(p_value) -> bool:
	if p_value is String:
		return not (p_value as String).is_empty() and p_value != "false"
	return true


## Conditionally includes body forms: (when NAME BODY...) splices BODY iff
## NAME is defined and truthy; (when-not NAME BODY...) inverts. Bodies need
## at least one form and expand on inclusion (sequential semantics).
static func _expand_when(p_node: Array, p_macros: Dictionary, p_env: Dictionary, p_counter: Array, p_depth: int, p_max: int, p_max_depth: int) -> Dictionary:
	# Branch kind: "when" or "when-not" (checked by the caller).
	var kind: String = (p_node as Array)[0]
	if (p_node as Array).size() < 3 or not ((p_node as Array)[1] is String):
		return {"ok": false, "node": null, "error": "usage: (%s name body...) with a variable name and at least one body form" % kind}
	# Tested variable name.
	var vname: String = (p_node as Array)[1]
	if not p_env.has(vname):
		return {"ok": false, "node": null, "error": "undefined template variable \"%s\"" % vname}
	# Condition result, inverted for when-not.
	var cond: bool = _is_truthy(p_env[vname])
	if kind == "when-not":
		cond = not cond
	# Included body forms, expanded in order.
	var included: Array = []
	if cond:
		for body in (p_node as Array).slice(2):
			# One body form expanded with the current environment.
			var expanded: Dictionary = _expand_node(body, p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
			if not expanded["ok"]:
				return expanded
			_append_expanded(included, expanded)
	return {"ok": true, "node": {"splice": included}, "error": ""}


## Unrolls one (for-generate (VAR SOURCE) BODY...) form into a splice marker
## holding every iteration copy, VAR bound per value. Bodies expand after
## binding (macro calls and nested generators compose). Iterations share the
## expansion budget. Returns {"ok", "node": {"splice": [...]}, "error"}.
static func _expand_generate(p_node: Array, p_macros: Dictionary, p_env: Dictionary, p_counter: Array, p_depth: int, p_max: int, p_max_depth: int) -> Dictionary:
	if (p_node as Array).size() < 3:
		return {"ok": false, "node": null, "error": "usage: (for-generate (var source) body...) with at least one body form"}
	# Loop binder: exactly (VAR SOURCE).
	var binder = (p_node as Array)[1]
	if not (binder is Array) or (binder as Array).size() != 2:
		return {"ok": false, "node": null, "error": "for-generate binder must be (var source) — e.g. (for-generate (i (range 0 3)) ...)"}
	# Loop variable (bare non-empty atom).
	var loopvar = (binder as Array)[0]
	if not (loopvar is String) or (loopvar as String).is_empty():
		return {"ok": false, "node": null, "error": "for-generate variable must be a non-empty name"}
	# Iteration values from the range or literal list.
	var values: Dictionary = _generate_values((binder as Array)[1], p_max)
	if not values["ok"]:
		return {"ok": false, "node": null, "error": values["error"]}
	# Body forms instantiated per iteration.
	var bodies: Array = (p_node as Array).slice(2)
	# Unrolled copies across every value.
	var copies: Array = []
	for value in (values["values"] as Array):
		p_counter[0] += 1
		if p_counter[0] > p_max:
			return {"ok": false, "node": null, "error": "generation budget exhausted (%d iterations) — possible runaway for-generate" % p_max}
		# Single-iteration bindings (loop var -> value node).
		var bindings: Dictionary = {loopvar: value}
		for body in bodies:
			if (body is String) and bindings.has(body):
				# Bare loop variable as a whole body form takes the value.
				var bound: Dictionary = _expand_node(bindings[body], p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
				if not bound["ok"]:
					return bound
				# Helpers collapsed per instance (generation binds values too).
				var bcollapsed: Dictionary = _collapse_helpers(bound["node"])
				if not bcollapsed["ok"]:
					return {"ok": false, "node": null, "error": bcollapsed["error"]}
				_append_expanded(copies, bcollapsed)
				continue
			if not (body is Array):
				# Plain atom passes through (downstream validates forms).
				copies.append(body)
				continue
			# Body copy with the loop variable bound.
			var subst: Dictionary = _subst_list(body, bindings, "", [])
			if not subst["ok"]:
				return {"ok": false, "node": null, "error": subst["error"]}
			# Instance expanded (macros and nested generators compose).
			var inst: Dictionary = _expand_node(subst["list"], p_macros, p_env, p_counter, p_depth, p_max, p_max_depth)
			if not inst["ok"]:
				return inst
			# Helpers collapsed per instance (generation binds values too).
			var collapsed: Dictionary = _collapse_helpers(inst["node"])
			if not collapsed["ok"]:
				return {"ok": false, "node": null, "error": collapsed["error"]}
			_append_expanded(copies, collapsed)
	return {"ok": true, "node": {"splice": copies}, "error": ""}


## Builds iteration values: (range A B [STEP]) integers (end-exclusive,
## Python-style; explicit STEP for reversed ranges) or a literal value list.
## Ranges/Lists beyond p_max values fail upfront. Bounds must be integer
## atoms (macro substitution already ran, so params work).
static func _generate_values(p_source, p_max: int) -> Dictionary:
	if (p_source is Array) and not (p_source as Array).is_empty() and ((p_source as Array)[0] is String) and (p_source as Array)[0] == "range":
		if (p_source as Array).size() < 3 or (p_source as Array).size() > 4:
			return {"ok": false, "values": [], "error": "usage: (range start end [step]) with integer bounds"}
		# Range bounds as integer atoms.
		var start_text = (p_source as Array)[1]
		var end_text = (p_source as Array)[2]
		if not (start_text is String) or not (end_text is String) or not start_text.is_valid_int() or not end_text.is_valid_int():
			return {"ok": false, "values": [], "error": "range bounds must be integer atoms"}
		# Step (default +1), must be a nonzero integer atom when given.
		var step_text = "1"
		if (p_source as Array).size() == 4:
			step_text = (p_source as Array)[3]
		if not (step_text is String) or not step_text.is_valid_int() or int(step_text) == 0:
			return {"ok": false, "values": [], "error": "range step must be a nonzero integer atom"}
		# Integer values from start (inclusive) to end (exclusive).
		var values: Array = []
		var i: int = int(start_text)
		var step: int = int(step_text)
		while (step > 0 and i < int(end_text)) or (step < 0 and i > int(end_text)):
			values.append(str(i))
			i += step
			if values.size() > p_max:
				return {"ok": false, "values": [], "error": "range too large (beyond %d values)" % p_max}
		return {"ok": true, "values": values, "error": ""}
	if p_source is Array:
		if (p_source as Array).size() > p_max:
			return {"ok": false, "values": [], "error": "value list too large (beyond %d values)" % p_max}
		return {"ok": true, "values": (p_source as Array).duplicate(), "error": ""}
	return {"ok": false, "values": [], "error": "for-generate source must be (range ...) or a value list"}


## Substitutes parameters in a body list: normal params become their raw
## subtree (any position, heads included); the rest atom splices its argument
## list where it appears as a direct element (heads included, downstream
## validates). Returns {"ok", "list", "error"} (infallible, kept uniform).
static func _subst_list(p_list: Array, p_bind: Dictionary, p_rest: String, p_rest_args: Array) -> Dictionary:
	# Output list with bindings applied.
	var out: Array = []
	for element in p_list:
		if (element is String) and not p_rest.is_empty() and element == p_rest:
			for a in p_rest_args:
				out.append(a)
		elif (element is String) and p_bind.has(element):
			out.append(p_bind[element])
		elif element is Array:
			# Nested list substituted with the same bindings.
			var sub: Dictionary = _subst_list(element, p_bind, p_rest, p_rest_args)
			if not sub["ok"]:
				return sub
			out.append(sub["list"])
		else:
			out.append(element)
	return {"ok": true, "list": out, "error": ""}


## Collapses atom helpers bottom-up: (join A B...) concatenates, (upper X),
## (lower X) and (capitalize X) convert case (Jinja-style capitalize: first
## upper, rest lower). Non-atom parts (after inner expansion) are user errors.
## Standalone helpers never reach here — only substituted bodies do.
static func _collapse_helpers(p_node) -> Dictionary:
	if not (p_node is Array):
		return {"ok": true, "node": p_node, "error": ""}
	if (p_node as Array).is_empty():
		return {"ok": true, "node": p_node, "error": ""}
	# Every element collapsed bottom-up, head included (innermost wins).
	var collapsed: Array = []
	for element in (p_node as Array):
		# One element collapsed bottom-up.
		var part: Dictionary = _collapse_helpers(element)
		if not part["ok"]:
			return part
		collapsed.append(part["node"])
	if not ((collapsed[0] is String) and (collapsed[0] == "join" or collapsed[0] == "upper" or collapsed[0] == "lower" or collapsed[0] == "capitalize")):
		return {"ok": true, "node": collapsed, "error": ""}
	# Helper head (one of the four above, guaranteed by the check).
	var helper: String = collapsed[0]
	# Helper arguments after the head.
	var hargs: Array = collapsed.slice(1)
	if helper == "join":
		if hargs.is_empty():
			return {"ok": false, "node": null, "error": "(join ...) needs at least one part"}
		# Concatenated text of the atom parts.
		var text: String = ""
		for part in hargs:
			if not (part is String):
				return {"ok": false, "node": null, "error": "(join ...) parts must be atoms (got '%s')" % str(part)}
			text += part
		return {"ok": true, "node": text, "error": ""}
	if hargs.size() != 1 or not (hargs[0] is String):
		return {"ok": false, "node": null, "error": "(%s ...) takes exactly one atom part" % helper}
	# Source text converted by the case helper.
	var source: String = hargs[0]
	if helper == "upper":
		return {"ok": true, "node": source.to_upper(), "error": ""}
	if helper == "lower":
		return {"ok": true, "node": source.to_lower(), "error": ""}
	return {"ok": true, "node": source.substr(0, 1).to_upper() + source.substr(1).to_lower(), "error": ""}
