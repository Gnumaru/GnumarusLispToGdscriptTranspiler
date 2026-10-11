## Template resolver for the GDLisp dialect.
##
## Implements Jinja-style template inheritance: a parent file declares named
## (block NAME body...) placeholders, and a child file starting with
## (template-extends PATH) overrides them with its own top-level blocks,
## whose bodies are spliced into the parent in place of the defaults.
## A parent compiled alone stays valid: blocks splice their default bodies.
## Include resolution happens per file with its own base (parent side with
## the parent base, each child block body with the child base), so relative
## includes keep working across the merge. Chains (parent inheriting from a
## grandparent) recurse; circular chains and excessive depth fail with clear
## errors. Runs after parsing (wrapping includes) and before transpiling.
## Non-string heads never match — never crash.
class_name GnumarusLispToGdscriptTranspilerTemplateResolver
extends RefCounted


## Tokenizer script, loaded by path.
const TokenizerScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerTokenizer.gd")
## Parser script, loaded by path.
const ParserScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerParser.gd")
## Include resolver script, loaded by path (per-side include resolution).
const IncludesScript = preload("res://addons/0GnumarusLispToGdscriptTranspiler/GnumarusLispToGdscriptTranspilerIncludeResolver.gd")
## Maximum template inheritance depth (bounds even aliasing-evaded cycles).
const MAX_TEMPLATE_DEPTH: int = 32


## Resolves template inheritance for the tree, then strips block wrappers.
## p_current_file is the file the tree came from ("" for bare text, where
## relative parent paths fail like relative includes do).
## Returns {"ok": true, "tree": Array, "error": ""} or a failure naming the
## offending file.
static func resolve(p_tree: Array, p_current_file: String, p_max_depth: int = MAX_TEMPLATE_DEPTH) -> Dictionary:
	# Template chain for cycle detection (canonical paths, innermost last).
	var stack: Array = []
	if not p_current_file.is_empty():
		stack.append(IncludesScript._canonical_key(p_current_file))
	# Merged tree with block wrappers still in place.
	var merged: Dictionary = _resolve_in(p_tree, p_current_file, stack, p_max_depth)
	if not merged["ok"]:
		return {"ok": false, "tree": [], "error": merged["error"]}
	return strip_blocks(merged["tree"])


## Recursive worker: merges one inheritance level, wrappers kept.
## p_stack holds the canonical chain of templates being processed.
static func _resolve_in(p_tree: Array, p_current_file: String, p_stack: Array, p_max_depth: int) -> Dictionary:
	if not p_tree.is_empty() and _is_template_extends(p_tree[0]):
		return _resolve_child(p_tree, p_current_file, p_stack, p_max_depth)
	# Leaf template: plain per-file include resolution, blocks untouched.
	return IncludesScript.resolve(p_tree, p_current_file)


## Tells whether a form is a (template-extends ...) list (String head required).
static func _is_template_extends(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "template-extends"


## Tells whether a form is a (block ...) list (String head required).
static func _is_block(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "block"


## Validates one (block NAME body...) form: NAME must be a non-empty string,
## bodies may be empty (placeholder splicing to nothing).
static func _check_block(p_form: Array) -> Dictionary:
	if (p_form as Array).size() < 2 or not ((p_form as Array)[1] is String) or (((p_form as Array)[1] as String).is_empty()):
		return {"ok": false, "error": "usage: (block name body...) with a non-empty block name"}
	return {"ok": true, "error": ""}


## Merges a child tree (extends + top-level blocks) with its parent chain.
static func _resolve_child(p_tree: Array, p_current_file: String, p_stack: Array, p_max_depth: int) -> Dictionary:
	# Parent spec from the leading extends form.
	var extform: Array = p_tree[0]
	if extform.size() != 2 or not (extform[1] is String) or (extform[1] as String).is_empty():
		return {"ok": false, "tree": [], "error": "usage: (template-extends path) as the first top-level form, with a single non-empty path string"}
	# Child blocks by name, in declaration order.
	var blocks: Dictionary = {}
	for form in p_tree.slice(1):
		if not _is_block(form):
			return {"ok": false, "tree": [], "error": "child templates may only contain (template-extends ...) and top-level (block ...) forms (got '%s')" % str(form)}
		# Block shape validation.
		var checked: Dictionary = _check_block(form)
		if not checked["ok"]:
			return {"ok": false, "tree": [], "error": checked["error"]}
		# Block name (non-empty String, guaranteed by _check_block).
		var bname: String = (form as Array)[1]
		if blocks.has(bname):
			return {"ok": false, "tree": [], "error": "duplicate block \"%s\" in child template" % bname}
		blocks[bname] = (form as Array).slice(2)
	# Parent location (res://, user://, system or relative to the child).
	var located: Dictionary = IncludesScript._resolve_path(extform[1], p_current_file)
	if not located["ok"]:
		return {"ok": false, "tree": [], "error": located["error"]}
	# Canonical identity for cycle detection.
	var key: String = IncludesScript._canonical_key(located["path"])
	if key in p_stack:
		# Circular chain for the error message, oldest first.
		var chain: Array = p_stack.duplicate()
		chain.append(key)
		return {"ok": false, "tree": [], "error": "circular template inheritance detected: " + " -> ".join(chain)}
	if p_stack.size() >= p_max_depth:
		return {"ok": false, "tree": [], "error": "template depth beyond maximum (%d) at %s" % [p_max_depth, located["path"]]}
	if not FileAccess.file_exists(located["path"]):
		return {"ok": false, "tree": [], "error": "parent template not found: %s" % located["path"]}
	# Raw text of the parent template.
	var text: String = FileAccess.get_file_as_string(located["path"])
	# Tokenizer output for the parent text.
	var tok: Dictionary = TokenizerScript.tokenize(text)
	if not tok["ok"]:
		return {"ok": false, "tree": [], "error": "in %s: tokenizer: %s" % [located["path"], str(tok["error"])]}
	# Parser output for the parent tokens.
	var parsed: Dictionary = ParserScript.parse(tok["tokens"])
	if not parsed["ok"]:
		return {"ok": false, "tree": [], "error": "in %s: parser: %s" % [located["path"], str(parsed["error"])]}
	# Chain extended with the parent template.
	var inner_stack: Array = p_stack.duplicate()
	inner_stack.append(key)
	# Parent side merged first (grandparent chain, parent-base includes).
	var pmerged: Dictionary = _resolve_in(parsed["tree"], located["path"], inner_stack, p_max_depth)
	if not pmerged["ok"]:
		return pmerged
	# Child block bodies include-resolved with the child base.
	var resolved_blocks: Dictionary = {}
	for bname in blocks.keys():
		# Include resolution of one block body as a form list.
		var bres: Dictionary = IncludesScript.resolve(blocks[bname], p_current_file)
		if not bres["ok"]:
			return {"ok": false, "tree": [], "error": "in block \"%s\": %s" % [bname, str(bres["error"])]}
		resolved_blocks[bname] = bres["tree"]
	# Names consumed by the merge, for the unknown-block check.
	var consumed: Array = []
	# Parent tree with overrides spliced in place of matching blocks.
	var merged: Dictionary = _merge_in(pmerged["tree"], resolved_blocks, consumed)
	if not merged["ok"]:
		return merged
	for bname in resolved_blocks.keys():
		if not (bname in consumed):
			return {"ok": false, "tree": [], "error": "unknown block \"%s\": parent template declares no such block" % bname}
	return {"ok": true, "tree": merged["tree"], "error": ""}


## Recursive merge worker: replaces parent (block NAME ...) nodes anywhere
## with the child bodies, resolving (super) placeholders against the
## overridden default body. p_consumed collects overridden names.
static func _merge_in(p_tree: Array, p_blocks: Dictionary, p_consumed: Array) -> Dictionary:
	# Output tree with overrides spliced in place of matching blocks.
	var out: Array = []
	for form in p_tree:
		if _is_block(form):
			# Block shape validation on the parent side too.
			var checked: Dictionary = _check_block(form)
			if not checked["ok"]:
				return {"ok": false, "tree": [], "error": checked["error"]}
			# Overridden block name.
			var bname: String = (form as Array)[1]
			if p_blocks.has(bname):
				p_consumed.append(bname)
				# Default body being overridden (super placeholders bind here).
				var default_body: Array = (form as Array).slice(2)
				# Child body with super placeholders resolved.
				var filled: Dictionary = _fill_super(p_blocks[bname], default_body)
				if not filled["ok"]:
					return {"ok": false, "tree": [], "error": filled["error"]}
				for spliced in (filled["tree"] as Array):
					out.append(spliced)
			else:
				out.append(form)
		elif form is Array:
			# Nested list: recurse with the same block map.
			var inner: Dictionary = _merge_in(form, p_blocks, p_consumed)
			if not inner["ok"]:
				return inner
			out.append(inner["tree"])
		else:
			# Bare atom passes through untouched.
			out.append(form)
	return {"ok": true, "tree": out, "error": ""}


## Tells whether a form is a bare (super) placeholder (String head required).
static func _is_super(p_form) -> bool:
	if not (p_form is Array):
		return false
	if (p_form as Array).is_empty():
		return false
	# Head of the candidate form.
	var head = (p_form as Array)[0]
	if not (head is String):
		return false
	return head == "super"


## Replaces (super) placeholders anywhere in a child body with copies of the
## overridden default body. (super) takes no arguments; anything else named
## super is a user error. Mid-chain parents already resolved their own
## placeholders, so surviving ones always bind to the direct default here.
static func _fill_super(p_body: Array, p_default: Array) -> Dictionary:
	# Output body with default copies spliced in place of placeholders.
	var out: Array = []
	for form in p_body:
		if _is_super(form):
			if (form as Array).size() != 1:
				return {"ok": false, "tree": [], "error": "usage: (super) takes no arguments"}
			for spliced in p_default:
				out.append(spliced)
		elif form is Array:
			# Nested list: recurse with the same default.
			var inner: Dictionary = _fill_super(form, p_default)
			if not inner["ok"]:
				return inner
			out.append(inner["tree"])
		else:
			# Bare atom passes through untouched.
			out.append(form)
	return {"ok": true, "tree": out, "error": ""}


## Strips (block NAME body...) wrappers anywhere, splicing their bodies.
## Also rejects duplicate block names in the same tree. Always runs, even
## without inheritance, so standalone parents stay valid.
static func strip_blocks(p_tree: Array) -> Dictionary:
	# Block names already seen at any level (flat namespace).
	var seen: Array = []
	return _strip_in(p_tree, seen)


## Recursive strip worker sharing the flat seen-name list.
static func _strip_in(p_tree: Array, p_seen: Array) -> Dictionary:
	# Output tree with block bodies spliced in place of wrappers.
	var out: Array = []
	for form in p_tree:
		if _is_block(form):
			# Block shape validation.
			var checked: Dictionary = _check_block(form)
			if not checked["ok"]:
				return {"ok": false, "tree": [], "error": checked["error"]}
			# Block name (non-empty String, guaranteed by _check_block).
			var bname: String = (form as Array)[1]
			if bname in p_seen:
				return {"ok": false, "tree": [], "error": "duplicate block \"%s\" in template" % bname}
			p_seen.append(bname)
			# Stripped body forms spliced here (never nested).
			var inner: Dictionary = _strip_in((form as Array).slice(2), p_seen)
			if not inner["ok"]:
				return inner
			for spliced in (inner["tree"] as Array):
				out.append(spliced)
		elif form is Array:
			# Nested list: recurse with the same seen list.
			var sub: Dictionary = _strip_in(form, p_seen)
			if not sub["ok"]:
				return sub
			out.append(sub["tree"])
		else:
			# Bare atom passes through untouched.
			out.append(form)
	return {"ok": true, "tree": out, "error": ""}
