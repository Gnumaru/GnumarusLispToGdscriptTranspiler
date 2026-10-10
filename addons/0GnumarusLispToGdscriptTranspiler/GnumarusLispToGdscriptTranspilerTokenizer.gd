## Tokenizer for the Gnumarus transpiler Lisp dialect.
##
## Turns source text into a flat token list: each atom becomes a String and
## each structural paren becomes "(" or ")". It builds no structure (that is
## GnumarusLispToGdscriptTranspilerParser's job) and interprets no meaning (that is
## GnumarusLispToGdscriptTranspilerTranspiler's job). All state is local: the function is pure and
## testable.
##
## Atom rules (see AGENTS.md):
## - atoms without whitespace, parens, backslash or delimiters need no quotes;
## - "packed" spans use " ' ` or ´, without mixing the opening/closing pair;
##   packed content is appended to the atom in progress;
## - a backslash (\) escapes the next character in any position;
## - ";" and "#" start a line comment anywhere outside packed spans
##   (even mid-atom): the rest of the line is discarded up to LF/CR.
##   Escape them (\; \#) or pack them ("a;b") to keep them literal.
class_name GnumarusLispToGdscriptTranspilerTokenizer
extends RefCounted


## Codepoints opening and closing packed spans: " ' ` ´.
const DELIMITER_CODES: Array = [34, 39, 96, 180]
## Codepoint of the backslash, the escape character.
const BACKSLASH_CODE: int = 92
## Codepoint of the structural open paren.
const OPEN_PAREN_CODE: int = 40
## Codepoint of the structural close paren.
const CLOSE_PAREN_CODE: int = 41
## Codepoint of the semicolon, a line comment starter.
const SEMICOLON_CODE: int = 59
## Codepoint of the hash, a line comment starter.
const HASH_CODE: int = 35


## Tells whether a Unicode codepoint separates atoms.
## Separators are: space, tab, LF and CR.
static func is_whitespace(p_code: int) -> bool:
	return p_code == 32 or p_code == 9 or p_code == 10 or p_code == 13


## Tells whether a codepoint is one of the 4 packed-span delimiters.
static func is_delimiter(p_code: int) -> bool:
	return p_code in DELIMITER_CODES


## Splits source text into a flat token list (`;`/`#` line comments
## discarded along the way).
## Returns {"ok": true, "tokens": Array[String], "error": ""} on success, or
## {"ok": false, "tokens": [], "error": message} on unterminated span or
## trailing lone backslash.
static func tokenize(p_text: String) -> Dictionary:
	# Flat token list being produced (atoms and structural "("/")" ).
	var tokens: Array = []
	# Text of the atom under construction (includes closed packed spans).
	var atom: String = ""
	# Whether an atom is in progress (tells packed "" apart from "nothing").
	var atom_active: bool = false
	# Whether we are inside a packed span.
	var in_string: bool = false
	# Delimiter closing the current packed span (codepoint, 0 = none).
	var closing_code: int = 0
	# Index of the current character in the source text.
	var i: int = 0
	# Total character count of the source text.
	var n: int = p_text.length()
	while i < n:
		# Unicode codepoint of the current character.
		var code: int = p_text.unicode_at(i)
		if in_string:
			if code == BACKSLASH_CODE:
				if i + 1 >= n:
					return {"ok": false, "tokens": [], "error": "lone backslash at the end of a packed span"}
				# Escapes the next character literally (e.g. \" becomes ").
				atom += p_text.substr(i + 1, 1)
				atom_active = true
				i += 2
				continue
			if code == closing_code:
				# Closes the packed span, back to plain atom accumulation.
				in_string = false
				closing_code = 0
				atom_active = true
				i += 1
				continue
			# Ordinary character (even whitespace/parens) inside the span.
			atom += p_text.substr(i, 1)
			atom_active = true
			i += 1
			continue
		if is_whitespace(code):
			if atom_active:
				tokens.append(atom)
				atom = ""
				atom_active = false
			i += 1
			continue
		if code == OPEN_PAREN_CODE:
			if atom_active:
				tokens.append(atom)
				atom = ""
				atom_active = false
			tokens.append("(")
			i += 1
			continue
		if code == CLOSE_PAREN_CODE:
			if atom_active:
				tokens.append(atom)
				atom = ""
				atom_active = false
			tokens.append(")")
			i += 1
			continue
		if code == BACKSLASH_CODE:
			if i + 1 >= n:
				return {"ok": false, "tokens": [], "error": "lone backslash at the end of the text"}
			# Escapes outside packed spans too (e.g. \( becomes a literal "(",
			# \; and \# stay literal instead of starting comments).
			atom += p_text.substr(i + 1, 1)
			atom_active = true
			i += 2
			continue
		if code == SEMICOLON_CODE or code == HASH_CODE:
			# Line comment anywhere (even mid-atom): flush the atom in
			# progress, then discard raw characters up to (not including)
			# the next line break (delimiters inside never count).
			if atom_active:
				tokens.append(atom)
				atom = ""
				atom_active = false
			while i < n:
				# Codepoint under the comment skip.
				var skip: int = p_text.unicode_at(i)
				if skip == 10 or skip == 13:
					break
				i += 1
			continue
		if code in DELIMITER_CODES:
			# Opens a packed span without breaking the atom in progress.
			in_string = true
			closing_code = code
			atom_active = true
			i += 1
			continue
		# Ordinary atom character.
		atom += p_text.substr(i, 1)
		atom_active = true
		i += 1
	if in_string:
		return {"ok": false, "tokens": [], "error": "unterminated packed span (missing closing delimiter)"}
	if atom_active:
		tokens.append(atom)
	return {"ok": true, "tokens": tokens, "error": ""}
