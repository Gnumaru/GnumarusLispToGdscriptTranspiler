## Parser for the GDLisp dialect.
##
## Turns the GnumarusLispToGdscriptTranspilerTokenizer flat token list into a nested tree: each paren
## pair becomes an Array, each atom stays a String. The top-level result is an
## Array of forms (lists or bare atoms). It interprets no meaning: that is
## GnumarusLispToGdscriptTranspilerTranspiler's job.
class_name GnumarusLispToGdscriptTranspilerParser
extends RefCounted


## Maximum accepted nesting depth (guards against pathological inputs).
const MAX_DEPTH: int = 256


## Turns the flat token list into a nested list tree.
## Returns {"ok": true, "tree": Array, "error": ""} on success, or
## {"ok": false, "tree": [], "error": message} on unexpected parens,
## unclosed lists or excessive depth.
static func parse(p_tokens: Array) -> Dictionary:
	# Top-level tree: one form per element (list or bare atom).
	var tree: Array = []
	# Read position in the flat token list.
	var pos: int = 0
	while pos < p_tokens.size():
		# Partial expression result: {"ok", "value", "next", "error"}.
		var res: Dictionary = _parse_expr(p_tokens, pos, 0)
		if not res["ok"]:
			return {"ok": false, "tree": [], "error": res["error"]}
		tree.append(res["value"])
		pos = res["next"]
	return {"ok": true, "tree": tree, "error": ""}


## Reads one expression (atom or list) from the given position.
## Returns {"ok", "value": atom/list, "next": next position, "error"}.
static func _parse_expr(p_tokens: Array, p_pos: int, p_depth: int) -> Dictionary:
	if p_depth > MAX_DEPTH:
		return {"ok": false, "value": null, "next": p_pos, "error": "nesting beyond maximum depth (%d)" % MAX_DEPTH}
	if p_pos >= p_tokens.size():
		return {"ok": false, "value": null, "next": p_pos, "error": "unexpected end of the token list"}
	# Current token (atom String or "(" / ")").
	var tok = p_tokens[p_pos]
	if tok == "(":
		# Items of the list under construction.
		var items: Array = []
		# Read position inside the list.
		var next: int = p_pos + 1
		while next < p_tokens.size() and p_tokens[next] != ")":
			# Nested expression inside the list.
			var inner: Dictionary = _parse_expr(p_tokens, next, p_depth + 1)
			if not inner["ok"]:
				return inner
			items.append(inner["value"])
			next = inner["next"]
		if next >= p_tokens.size():
			return {"ok": false, "value": null, "next": next, "error": "open paren without matching close paren"}
		return {"ok": true, "value": items, "next": next + 1, "error": ""}
	if tok == ")":
		return {"ok": false, "value": null, "next": p_pos, "error": "unexpected close paren at position %d" % p_pos}
	# Atom: the value is the token itself, consumes one position.
	return {"ok": true, "value": tok, "next": p_pos + 1, "error": ""}
