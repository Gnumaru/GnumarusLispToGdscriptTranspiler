## Automated test entry point for the transpiler (v1 + var revision).
##
## Run from the project root:
## /sync/opt/godot/godot4.x86_64 --headless --path . --script res://addons/GnumarusLispToGdscriptTranspiler/tests/TestRunner.gd
## The process exits with code 0 when everything passes, 1 otherwise.
## Covers: tokenizer (basic, 4 delimiters, escapes, errors), parser
## (nesting, errors), var forms (positional, =, :=, verbatim values, errors)
## and end to end (Test1/Test2 via text and file).
extends SceneTree


## Tokenizer script, loaded by path.
const TokenizerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTokenizer.gd")
## Parser script, loaded by path.
const ParserScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusParser.gd")
## Transpiler script, loaded by path.
const TranspilerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusTranspiler.gd")
## Facade script, loaded by path.
const FacadeScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusLisp.gd")
## Include resolver script, loaded by path.
const IncludesScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusIncludeResolver.gd")

## Directory holding the .gdl (input) / .gd (expected output) pairs.
const TESTS_DIR: String = "res://addons/GnumarusLispToGdscriptTranspiler/tests"
## Directory holding the include fixtures (pairs plus error cases).
const INCLUDES_DIR: String = "res://addons/GnumarusLispToGdscriptTranspiler/tests/includes"
## Directory holding the template fixtures (pairs plus error cases).
const TEMPLATES_DIR: String = "res://addons/GnumarusLispToGdscriptTranspiler/tests/templates"
## Directory holding the macro fixture (pair) for end-to-end coverage.
const MACROS_DIR: String = "res://addons/GnumarusLispToGdscriptTranspiler/tests/macros"
## Lisp editor plugin proxy script, loaded by path (parse guard: proxies
## only instantiate inside the editor).
const LispPluginScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusLispPlugin.gd")
## Lisp editor plugin implementation script, loaded by path.
const PluginImplScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusLispPluginImpl.gd")
## Gdl colorizer script, loaded by path (pure coloring logic).
const ColorizerScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlColorizer.gd")
## Gdl theme script, loaded by path (fallback colors and word lists).
const ThemeScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlTheme.gd")
## Gdl highlighter implementation script, loaded by path.
const HighlighterImplScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusGdlHighlighterImpl.gd")

## Count of passing checks.
var _passed: int = 0
## Count of failing checks.
var _failed: int = 0


## Constructor: runs every battery and exits with the matching code.
func _init() -> void:
	_test_tokenizer_basic()
	_test_tokenizer_strings()
	_test_tokenizer_errors()
	_test_parser()
	_test_parser_errors()
	_test_var_forms()
	_test_var_errors()
	_test_flow_forms()
	_test_flow_errors()
	_test_match_forms()
	_test_match_errors()
	_test_class_forms()
	_test_class_errors()
	_test_inner_class()
	_test_lambda()
	_test_signatures()
	_test_accessors()
	_test_expressions()
	_test_collections()
	_test_annotations()
	_test_small_forms()
	_test_includes()
	_test_templates()
	_test_macros()
	_test_generate()
	_test_set_when()
	_test_watcher()
	_test_highlighter()
	_test_end_to_end()
	_test_transpiler_errors()
	print("--------------------------------------------------")
	print("TestRunner: %d PASS, %d FAIL" % [_passed, _failed])
	if _failed > 0:
		printerr("TestRunner: FAILED")
		quit(1)
	else:
		print("TestRunner: SUCCESS")
		quit(0)


## Records one boolean check with a name and optional detail.
func _check(p_name: String, p_condition: bool, p_detail: String = "") -> void:
	if p_condition:
		_passed += 1
		print("PASS: " + p_name)
	else:
		_failed += 1
		if p_detail.is_empty():
			printerr("FAIL: " + p_name)
		else:
			printerr("FAIL: " + p_name + " | " + p_detail)


## Records one equality comparison between actual and expected.
func _check_eq(p_name: String, p_actual, p_expected) -> void:
	_check(p_name, p_actual == p_expected, "actual=%s expected=%s" % [str(p_actual), str(p_expected)])


## Records one queue check: transpiles Lisp and compares against GDScript.
func _check_transpiles(p_name: String, p_lisp: String, p_expected_gd: String) -> void:
	# Facade result for the Lisp snippet.
	var r: Dictionary = FacadeScript.transpile_text(p_lisp)
	_check(p_name + ": ok", r["ok"] == true, str(r.get("error", "")))
	if r["ok"]:
		_check_eq(p_name + ": output", r["code"], p_expected_gd)


## Basic tokenizer tests: atoms, parens and separators.
func _test_tokenizer_basic() -> void:
	# Tokenization result of a typed var form.
	var r: Dictionary = TokenizerScript.tokenize("(var b int)")
	_check("tokenizer basic: ok", r["ok"] == true, str(r))
	_check_eq("tokenizer basic: tokens", r["tokens"], ["(", "var", "b", "int", ")"])
	# Mixed newlines and tabs as separators.
	var r2: Dictionary = TokenizerScript.tokenize("(class-name\n\tMyClass)")
	_check_eq("tokenizer basic: varied whitespace", r2["tokens"], ["(", "class-name", "MyClass", ")"])
	# = and := tokenize as plain bare atoms.
	var r3: Dictionary = TokenizerScript.tokenize("(var n := 10)")
	_check_eq("tokenizer basic: := atom", r3["tokens"], ["(", "var", "n", ":=", "10", ")"])


## Tests of the 4 packed-span delimiters and of escapes.
func _test_tokenizer_strings() -> void:
	# Double quotes holding single quotes + space (no pair mixing).
	var r1: Dictionary = TokenizerScript.tokenize("(comment \"a'b e c\")")
	_check_eq("tokenizer: double quotes holding single", r1["tokens"], ["(", "comment", "a'b e c", ")"])
	# Single quotes holding double quotes.
	var r2: Dictionary = TokenizerScript.tokenize("(comment 'a\"b')")
	_check_eq("tokenizer: single quotes holding double", r2["tokens"], ["(", "comment", "a\"b", ")"])
	# Grave holding acute.
	var r3: Dictionary = TokenizerScript.tokenize("(comment `m´n`)")
	_check_eq("tokenizer: grave holding acute", r3["tokens"], ["(", "comment", "m´n", ")"])
	# Acute holding grave.
	var r4: Dictionary = TokenizerScript.tokenize("(comment ´p`q´)")
	_check_eq("tokenizer: acute holding grave", r4["tokens"], ["(", "comment", "p`q", ")"])
	# Delimiter and backslash escapes inside a packed span.
	var r5: Dictionary = TokenizerScript.tokenize("(comment \"ela disse \\\"oi\\\"\")")
	_check_eq("tokenizer: quote escape", r5["tokens"], ["(", "comment", "ela disse \"oi\"", ")"])
	# Paren escape outside a packed span becomes a literal atom.
	var r6: Dictionary = TokenizerScript.tokenize("(var a\\(b)")
	_check_eq("tokenizer: open paren escape", r6["tokens"], ["(", "var", "a(b", ")"])
	# Empty packed pair yields an empty atom (distinct from "no atom").
	var r7: Dictionary = TokenizerScript.tokenize("(comment \"\")")
	_check_eq("tokenizer: empty packed string", r7["tokens"], ["(", "comment", "", ")"])
	# Close paren escape becomes an atom literal, not structure.
	var r8: Dictionary = TokenizerScript.tokenize("(var a\\))")
	_check_eq("tokenizer: close paren escape", r8["tokens"], ["(", "var", "a)", ")"])
	# Double packing: GDScript quotes written inside Lisp packing.
	var r9: Dictionary = TokenizerScript.tokenize("(var a String = \"\\\"hi\\\"\")")
	_check_eq("tokenizer: double packed string", r9["tokens"], ["(", "var", "a", "String", "=", "\"hi\"", ")"])


## Tokenizer error tests: unterminated strings and lone backslash.
func _test_tokenizer_errors() -> void:
	# Packed span opened and never closed.
	var r1: Dictionary = TokenizerScript.tokenize("(comment \"abc)")
	_check("tokenizer error: unterminated string", r1["ok"] == false, str(r1))
	# Backslash as the very last character of the text.
	var r2: Dictionary = TokenizerScript.tokenize("(var a\\")
	_check("tokenizer error: lone backslash", r2["ok"] == false, str(r2))


## Parser tests: flat list becomes a nested list tree.
func _test_parser() -> void:
	# Tokens of (func _ready () (pass)), including the empty arg list.
	var toks: Array = ["(", "func", "_ready", "(", ")", "(", "pass", ")", ")"]
	# Nested tree produced by the parser.
	var r: Dictionary = ParserScript.parse(toks)
	_check("parser: ok", r["ok"] == true, str(r))
	_check_eq("parser: nested tree", r["tree"], [["func", "_ready", [], ["pass"]]])
	# Two top-level forms become two tree elements.
	var r2: Dictionary = ParserScript.parse(["(", "var", "a", ")", "(", "pass", ")"])
	_check_eq("parser: two forms", r2["tree"], [["var", "a"], ["pass"]])


## Parser error tests: unbalanced parens.
func _test_parser_errors() -> void:
	# Unmatched close paren.
	var r1: Dictionary = ParserScript.parse([")"])
	_check("parser error: lone closer", r1["ok"] == false, str(r1))
	# Open paren never closed.
	var r2: Dictionary = ParserScript.parse(["(", "var", "a"])
	_check("parser error: unclosed list", r2["ok"] == false, str(r2))


## Tests of the 5 positional var forms, including verbatim values.
func _test_var_forms() -> void:
	_check_transpiles("var plain", "(var a)", "var a\n")
	_check_transpiles("var typed", "(var b int)", "var b: int\n")
	_check_transpiles("var untyped default", "(var n = 5)", "var n = 5\n")
	_check_transpiles("var inference", "(var n := 10)", "var n := 10\n")
	_check_transpiles("var typed default", "(var c float = 0.0)", "var c: float = 0.0\n")
	# Double packed string: GDScript quotes live inside Lisp packing.
	_check_transpiles("var double packed string", "(var a String = \"\\\"hi\\\"\")", "var a: String = \"hi\"\n")
	# Verbatim hatch: packed expression emitted as GDScript source.
	_check_transpiles("var verbatim expression", "(var v Vector2 = \"Vector2(1, 2)\")", "var v: Vector2 = Vector2(1, 2)\n")
	# Alternate outer delimiter avoids quote escaping entirely.
	_check_transpiles("var single packed string", "(var a String = '\"hi\"')", "var a: String = \"hi\"\n")


## Tests of invalid var forms: every one must fail with a usage message.
func _test_var_errors() -> void:
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(var)",
		"(var a String 5)",
		"(var n int := 5)",
		"(var a =)",
		"(var = 5)",
		"(var a = \"\")",
		"(var a int =)",
		"(var a int extra = 5)",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("var error: %s" % c, r["ok"] == false, str(r))


## Tests of the flow forms: if/elif/else chains, while, for, break,
## continue and return, including nesting.
func _test_flow_forms() -> void:
	_check_transpiles("if basic", "(if \"x > 0\" (pass))", "if x > 0:\n\tpass\n")
	_check_transpiles("if elif else",
		"(if \"x > 0\" (return 1) (elif \"x < 0\" (return -1)) (else (return 0)))",
		"if x > 0:\n\treturn 1\nelif x < 0:\n\treturn -1\nelse:\n\treturn 0\n")
	_check_transpiles("if multiple elif",
		"(if \"a\" (pass) (elif \"b\" (pass)) (elif \"c\" (pass)))",
		"if a:\n\tpass\nelif b:\n\tpass\nelif c:\n\tpass\n")
	_check_transpiles("if nested",
		"(if \"a\" (if \"b\" (pass)))",
		"if a:\n\tif b:\n\t\tpass\n")
	_check_transpiles("while basic", "(while \"x > 0\" (pass))", "while x > 0:\n\tpass\n")
	_check_transpiles("if structured cond",
		"(if (== x 1) (pass))",
		"if x == 1:\n\tpass\n")
	_check_transpiles("if elif structured",
		"(if a (pass) (elif (or b c) (pass)))",
		"if a:\n\tpass\nelif b or c:\n\tpass\n")
	_check_transpiles("while call cond",
		"(while (call more) (pass))",
		"while more():\n\tpass\n")
	_check_transpiles("for call iterable",
		"(for i in (call range 10) (pass))",
		"for i in range(10):\n\tpass\n")
	_check_transpiles("match call subject",
		"(match (call f x) (branch \"1\" (pass)))",
		"match f(x):\n\t1:\n\t\tpass\n")
	_check_transpiles("for basic", "(for x in items (pass))", "for x in items:\n\tpass\n")
	_check_transpiles("for typed", "(for n int in items (pass))", "for n: int in items:\n\tpass\n")
	_check_transpiles("for nested body",
		"(for x in items (if \"x\" (pass)) (pass))",
		"for x in items:\n\tif x:\n\t\tpass\n\tpass\n")
	_check_transpiles("break", "(while \"true\" (break))", "while true:\n\tbreak\n")
	_check_transpiles("continue", "(while \"true\" (continue))", "while true:\n\tcontinue\n")
	_check_transpiles("return bare", "(func f () (return))", "func f():\n\treturn\n")
	_check_transpiles("return value", "(func f () (return 0))", "func f():\n\treturn 0\n")
	_check_transpiles("return packed", "(func f () (return \"\\\"done\\\"\"))", "func f():\n\treturn \"done\"\n")


## Tests of invalid flow forms: every one must fail with a usage message.
func _test_flow_errors() -> void:
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(elif \"a\" (pass))",
		"(else (pass))",
		"(if \"a\")",
		"(if \"a\" (else (pass)))",
		"(if \"a\" (pass) (else))",
		"(if \"a\" (pass) (else (pass)) (elif \"b\" (pass)))",
		"(if \"a\" (pass) 42)",
		"(if \"a\" (pass) (elif \"b\" (pass) (else (pass))))",
		"(while \"c\")",
		"(while \"c\" (elif \"d\" (pass)))",
		"(if (lambda (x) (pass)) (pass))",
		"(if (if \"a\" (pass)) (pass))",
		"(for i in (lambda (x) (pass)) (pass))",
		"(match (pass) (branch \"1\" (pass)))",
		"(for x items (pass))",
		"(for x in)",
		"(for x in items)",
		"(for n int items (pass))",
		"(for n int in)",
		"(for n int in items)",
		"(for in in items (pass))",
		"(break x)",
		"(continue x)",
		"(return 1 2)",
		"(return (pass))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("flow error: %s" % c, r["ok"] == false, str(r))


## Tests of the match forms: subject, literal/multi/array/wildcard patterns
## and nesting.
func _test_match_forms() -> void:
	_check_transpiles("match basic",
		"(match \"x\" (branch \"1\" (pass)) (branch \"_\" (pass)))",
		"match x:\n\t1:\n\t\tpass\n\t_:\n\t\tpass\n")
	_check_transpiles("match multi pattern",
		"(match \"x\" (branch \"1, 2, 3\" (pass)))",
		"match x:\n\t1, 2, 3:\n\t\tpass\n")
	_check_transpiles("match array pattern",
		"(match \"v\" (branch \"[var a, var b]\" (return a)))",
		"match v:\n\t[var a, var b]:\n\t\treturn a\n")
	_check_transpiles("match dict pattern",
		"(match \"d\" (branch \"{\\\"key\\\": v}\" (return v)))",
		"match d:\n\t{\"key\": v}:\n\t\treturn v\n")
	_check_transpiles("match nested",
		"(match \"a\" (branch \"_\" (match \"b\" (branch \"_\" (pass)))))",
		"match a:\n\t_:\n\t\tmatch b:\n\t\t\t_:\n\t\t\t\tpass\n")


## Tests of invalid match forms: every one must fail with a usage message.
func _test_match_errors() -> void:
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(match)",
		"(match \"x\")",
		"(match \"x\" (pass))",
		"(match \"x\" (\"1\" (pass)))",
		"(match \"x\" (branch))",
		"(match \"x\" (branch \"\" (pass)))",
		"(match \"x\" (branch \"1\"))",
		"(match \"x\" (branch \"1\" (branch \"2\" (pass))))",
		"(branch \"1\" (pass))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("match error: %s" % c, r["ok"] == false, str(r))


## Tests of the class-level forms: static-var (same 5 forms as var),
## static-func, signal and const (also valid inside funcs).
func _test_class_forms() -> void:
	_check_transpiles("static-var plain", "(static-var n)", "static var n\n")
	_check_transpiles("static-var typed", "(static-var n int)", "static var n: int\n")
	_check_transpiles("static-var default", "(static-var n = 1)", "static var n = 1\n")
	_check_transpiles("static-var inference", "(static-var n := 1)", "static var n := 1\n")
	_check_transpiles("static-var typed default", "(static-var n int = 1)", "static var n: int = 1\n")
	_check_transpiles("static-func basic",
		"(static-func f () (pass))",
		"static func f():\n\tpass\n")
	_check_transpiles("static-func trailing",
		"(static-func f () (comment \"hi\") (pass))",
		"static func f(): # hi\n\tpass\n")
	_check_transpiles("signal plain", "(signal hit)", "signal hit\n")
	_check_transpiles("signal args", "(signal moved (from to))", "signal moved(from, to)\n")
	_check_transpiles("signal empty args", "(signal ping ())", "signal ping()\n")
	_check_transpiles("const plain", "(const max = 10)", "const max = 10\n")
	_check_transpiles("const inference", "(const max := 10)", "const max := 10\n")
	_check_transpiles("const typed", "(const max float = 10.0)", "const max: float = 10.0\n")
	_check_transpiles("const nested",
		"(func f () (const limit = 60) (pass))",
		"func f():\n\tconst limit = 60\n\tpass\n")


## Tests of invalid class-level forms: every one must fail.
func _test_class_errors() -> void:
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(static-var)",
		"(static-var a String 5)",
		"(static-func f ())",
		"(signal)",
		"(signal hit (pass) (pass))",
		"(signal 1 2 3)",
		"(const a)",
		"(const a b)",
		"(const a =)",
		"(const a int := 5)",
		"(func f () (signal x) (pass))",
		"(func f () (static-var n) (pass))",
		"(func f () (static-func g () (pass)) (pass))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("class error: %s" % c, r["ok"] == false, str(r))


## Tests of inner classes: members, body extends, nesting and placement.
func _test_inner_class() -> void:
	_check_transpiles("class basic",
		"(class A (pass))",
		"class A:\n\tpass\n")
	_check_transpiles("class body extends",
		"(class A (extends Node) (pass))",
		"class A:\n\textends Node\n\tpass\n")
	_check_transpiles("class nested",
		"(class A (class B (pass)))",
		"class A:\n\tclass B:\n\t\tpass\n")
	_check_transpiles("class func member",
		"(class A (func f () (pass)))",
		"class A:\n\tfunc f():\n\t\tpass\n")
	_check_transpiles("class flow member",
		"(class A (if \"x\" (pass)))",
		"class A:\n\tif x:\n\t\tpass\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(class)",
		"(class A)",
		"(class A (class-name X))",
		"(func f () (class A (pass)) (pass))",
		"(func f () (extends Node) (pass))",
		"(func f () (signal x) (pass))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("class error: %s" % c, r["ok"] == false, str(r))


## Tests of inline lambdas as values: var defaults (member and local),
## return values, nesting and the trailing comment rule.
func _test_lambda() -> void:
	_check_transpiles("lambda var value",
		"(var cb = (lambda (x) (return x)))",
		"var cb = func(x):\n\treturn x\n")
	_check_transpiles("lambda nested indent",
		"(func f () (var cb = (lambda (x) (pass))) (pass))",
		"func f():\n\tvar cb = func(x):\n\t\tpass\n\tpass\n")
	_check_transpiles("lambda trailing",
		"(var cb = (lambda (x) (comment \"hi\") (pass)))",
		"var cb = func(x): # hi\n\tpass\n")
	_check_transpiles("lambda return",
		"(func f () (return (lambda (x) (pass))))",
		"func f():\n\treturn func(x):\n\t\tpass\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(lambda (x) (pass))",
		"(var cb = (lambda (x)))",
		"(var cb = (lambda x (pass)))",
		"(var cb = (foo))",
		"(const c = (lambda (x) (pass)))",
		"(func f () (return (lambda (x))))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("lambda error: %s" % c, r["ok"] == false, str(r))


## Tests of signature lists: typed/default/variadic arguments and
## return-first signatures, on func, static-func, lambda and signal.
func _test_signatures() -> void:
	_check_transpiles("sig typed arg",
		"(func f ((a int)) (pass))",
		"func f(a: int):\n\tpass\n")
	_check_transpiles("sig two args kept",
		"(func f (a b) (pass))",
		"func f(a, b):\n\tpass\n")
	_check_transpiles("sig void return",
		"(func f (void) (pass))",
		"func f() -> void:\n\tpass\n")
	_check_transpiles("sig empty group return",
		"(func f (int ()) (pass))",
		"func f() -> int:\n\tpass\n")
	_check_transpiles("sig return then typed arg",
		"(func f (Variant ((amount float = 1.0))) (pass))",
		"func f(amount: float = 1.0) -> Variant:\n\tpass\n")
	_check_transpiles("sig return with untyped group",
		"(func f (R (a b)) (pass))",
		"func f(a, b) -> R:\n\tpass\n")
	_check_transpiles("sig return one grouped typed arg",
		"(func f (R ((b int))) (pass))",
		"func f(b: int) -> R:\n\tpass\n")
	_check_transpiles("sig mixed flat args",
		"(func f ((x) (a int)) (pass))",
		"func f(x, a: int):\n\tpass\n")
	_check_transpiles("sig variadic",
		"(func f (...args) (pass))",
		"func f(...args):\n\tpass\n")
	_check_transpiles("sig infer default",
		"(func f ((a := 5)) (pass))",
		"func f(a := 5):\n\tpass\n")
	_check_transpiles("sig plain default",
		"(func f ((a = 5)) (pass))",
		"func f(a = 5):\n\tpass\n")
	_check_transpiles("sig static return",
		"(static-func f (int ((v))) (return v))",
		"static func f(v) -> int:\n\treturn v\n")
	_check_transpiles("sig lambda typed",
		"(var cb = (lambda ((x int)) (pass)))",
		"var cb = func(x: int):\n\tpass\n")
	_check_transpiles("sig lambda return",
		"(var cb = (lambda (int ((x))) (pass)))",
		"var cb = func(x) -> int:\n\tpass\n")
	_check_transpiles("sig signal typed",
		"(signal s ((a int)))",
		"signal s(a: int)\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(func f (R (a) (b)) (pass))",
		"(func f (\"\" (a)) (pass))",
		"(func f ((a int =)) (pass))",
		"(func f ((a :=)) (pass))",
		"(signal s (int (a)))",
		"(var cb = (lambda (int (x) (y)) (pass)))",
		"(var x (a int) 5)",
		"(if \"x\" ((y)))",
		"(for x (a) (pass))",
		"(match \"x\" (branch \"1\" ((y))))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("sig error: %s" % c, r["ok"] == false, str(r))


## Tests of get/set accessors: trailing forms of var/static-var, order,
## duplicates, placement and the probed GDScript limits (bare setter param,
## no getter return, members only).
func _test_accessors() -> void:
	_check_transpiles("accessor getter",
		"(var h int = 1 (get (return h)))",
		"var h: int = 1:\n\tget:\n\t\treturn h\n")
	_check_transpiles("accessor setter",
		"(var h = 1 (set (v) (pass)))",
		"var h = 1:\n\tset(v):\n\t\tpass\n")
	_check_transpiles("accessor both reversed",
		"(var h = 1 (set (v) (pass)) (get (return h)))",
		"var h = 1:\n\tset(v):\n\t\tpass\n\tget:\n\t\treturn h\n")
	_check_transpiles("accessor static",
		"(static-var h = 1 (get (return h)))",
		"static var h = 1:\n\tget:\n\t\treturn h\n")
	_check_transpiles("accessor untyped no default",
		"(var h (get (return 1)))",
		"var h:\n\tget:\n\t\treturn 1\n")
	_check_transpiles("accessor inline both",
		"(var e = 1 (get get_e) (set set_e))",
		"var e = 1: get = get_e, set = set_e\n")
	_check_transpiles("accessor inline single",
		"(var e = 1 (get get_e))",
		"var e = 1: get = get_e\n")
	_check_transpiles("accessor inline no value",
		"(var e (get get_e))",
		"var e: get = get_e\n")
	_check_transpiles("accessor inline static",
		"(static-var s = 1 (get get_s))",
		"static var s = 1: get = get_s\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(get (pass))",
		"(set (v) (pass))",
		"(var h = 1 (get))",
		"(var h = 1 (set (v)))",
		"(var h = 1 (set (a b) (pass)))",
		"(var h = 1 (set ((v int)) (pass)))",
		"(var h = 1 (get (pass)) (get (pass)))",
		"(var h = 1 (set (a) (pass)) (set (b) (pass)))",
		"(var h = 1 (pass) (get (pass)))",
		"(var h = 1 (get (pass)) (var x))",
		"(func f () (var h = 1 (get (pass))) (pass))",
		"(const c = 1 (get (pass)))",
		"(var cb = (lambda (x) (pass)) (get (pass)))",
		"(var e = 1 (get get_e) (set (v) (pass)))",
		"(var e = 1 (get a) (get b))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("accessor error: %s" % c, r["ok"] == false, str(r))


## Tests of calls, infix arithmetic/logic and assignment: statements,
## values, nesting, precedence parentheses and the single-line rule.
func _test_expressions() -> void:
	_check_transpiles("call bare", "(call f)", "f()\n")
	_check_transpiles("call args", "(call f x \"a, b\")", "f(x, a, b)\n")
	_check_transpiles("call dotted", "(call node.foo x)", "node.foo(x)\n")
	_check_transpiles("call nested", "(call f (call g x))", "f(g(x))\n")
	_check_transpiles("call nested stmt",
		"(func f () (call print (call str x)) (pass))",
		"func f():\n\tprint(str(x))\n\tpass\n")
	_check_transpiles("arith n-ary", "(+ a b c)", "a + b + c\n")
	_check_transpiles("arith binary", "(- a b)", "a - b\n")
	_check_transpiles("logic not", "(not x)", "not x\n")
	_check_transpiles("unary minus", "(- x)", "-x\n")
	_check_transpiles("unary minus nested", "(- (+ a b))", "-(a + b)\n")
	_check_transpiles("unary minus call", "(- (call f x))", "-f(x)\n")
	_check_transpiles("logic compare", "(== a b)", "a == b\n")
	_check_transpiles("logic nested", "(and a (or b c))", "a and (b or c)\n")
	_check_transpiles("arith precedence", "(* (+ a b) c)", "(a + b) * c\n")
	_check_transpiles("arith call operand", "(* (call f x) c)", "f(x) * c\n")
	_check_transpiles("arith as value", "(var t = (+ 1 2))", "var t = 1 + 2\n")
	_check_transpiles("call as value", "(var t = (call f x))", "var t = f(x)\n")
	_check_transpiles("arith as return",
		"(func f (x) (return (+ x 1)))",
		"func f(x):\n\treturn x + 1\n")
	_check_transpiles("assign plain", "(assign x = 5)", "x = 5\n")
	_check_transpiles("assign compound", "(assign x += 1)", "x += 1\n")
	_check_transpiles("assign dotted", "(assign a.b = (call f y))", "a.b = f(y)\n")
	_check_transpiles("assign lambda",
		"(func f () (assign cb = (lambda (x) (pass))) (pass))",
		"func f():\n\tcb = func(x):\n\t\tpass\n\tpass\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(call)",
		"(call (a) x)",
		"(+)",
		"(+ a)",
		"(not a b)",
		"(+ a (lambda (x) (pass)))",
		"(+ a (if \"x\" (pass)))",
		"(call f (lambda (x) (pass)))",
		"(assign x)",
		"(assign x %%% v)",
		"(assign (a) = 5)",
		"(var t = (assign x = 1))",
		"(var t = (if \"x\" (pass)))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("expr error: %s" % c, r["ok"] == false, str(r))


## Tests of array/dict literals: shapes, nesting, expressions inside,
## values, call args and the lambda/placement rules.
func _test_collections() -> void:
	_check_transpiles("array empty", "(array)", "[]\n")
	_check_transpiles("array basic",
		"(array 1 2)",
		"[\n\t1,\n\t2,\n]\n")
	_check_transpiles("array packed string",
		"(array 1 \"\\\"hi\\\"\")",
		"[\n\t1,\n\t\"hi\",\n]\n")
	_check_transpiles("array nested",
		"(array 1 (array 2 3))",
		"[\n\t1,\n\t[\n\t\t2,\n\t\t3,\n\t],\n]\n")
	_check_transpiles("array call element",
		"(array (call f x))",
		"[\n\tf(x),\n]\n")
	_check_transpiles("dict-lua empty", "(dict-lua)", "{}\n")
	_check_transpiles("dict-lua basic",
		"(dict-lua (a 1) (b 2))",
		"{\n\ta = 1,\n\tb = 2,\n}\n")
	_check_transpiles("dict-lua packed value",
		"(dict-lua (name \"\\\"hi\\\"\"))",
		"{\n\tname = \"hi\",\n}\n")
	_check_transpiles("dict-json empty", "(dict-json)", "{}\n")
	_check_transpiles("dict-json basic",
		"(dict-json (\"\\\"k\\\"\" 1))",
		"{\n\t\"k\": 1,\n}\n")
	_check_transpiles("dict-json call key",
		"(dict-json ((call Vector2 1 2) 1))",
		"{\n\tVector2(1, 2): 1,\n}\n")
	_check_transpiles("collection as value",
		"(var a = (array 1))",
		"var a = [\n\t1,\n]\n")
	_check_transpiles("collection as return",
		"(func f () (return (dict-lua (a 1))))",
		"func f():\n\treturn {\n\t\ta = 1,\n\t}\n")
	_check_transpiles("collection as call arg",
		"(call f (array 1))",
		"f([\n\t1,\n])\n")
	_check_transpiles("collection nested indent",
		"(func f () (var a = (array (dict-lua (x 1)))) (pass))",
		"func f():\n\tvar a = [\n\t\t{\n\t\t\tx = 1,\n\t\t},\n\t]\n\tpass\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(array (lambda (x) (pass)))",
		"(dict-lua (a))",
		"(dict-lua a)",
		"(dict-json (a 1 2))",
		"(dict-lua ((lambda (x) (pass)) 1))",
		"(dict-lua (a (if \"x\" (pass))))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("collection error: %s" % c, r["ok"] == false, str(r))


## Tests of @ annotations: leading atoms on their own lines, stacked and
## parameterized forms, member indentation, exclusions and the lone-@ error.
func _test_annotations() -> void:
	_check_transpiles("annotation var",
		"(var @export hp int = 100)",
		"@export\nvar hp: int = 100\n")
	_check_transpiles("annotation stacked",
		"(var \"@export_category(\\\"Stats\\\")\" @export hp = 1)",
		"@export_category(\"Stats\")\n@export\nvar hp = 1\n")
	_check_transpiles("annotation func",
		"(func \"@rpc(\\\"any_peer\\\")\" heal () (pass))",
		"@rpc(\"any_peer\")\nfunc heal():\n\tpass\n")
	_check_transpiles("annotation static-func",
		"(static-func \"@rpc(\\\"any_peer\\\")\" f () (pass))",
		"@rpc(\"any_peer\")\nstatic func f():\n\tpass\n")
	_check_transpiles("annotation class-name",
		"(class-name \"@icon(\\\"res://icon.svg\\\")\" MyClass)",
		"@icon(\"res://icon.svg\")\nclass_name MyClass\n")
	_check_transpiles("annotation member indent",
		"(class A (var @export x = 1))",
		"class A:\n\t@export\n\tvar x = 1\n")
	_check_transpiles("annotation comment kept",
		"(comment @todo fix)",
		"# @todo fix\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(var @ n = 1)",
		"(signal @foo x)",
		"(const @c n = 1)",
		"(var @export)",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("annotation error: %s" % c, r["ok"] == false, str(r))


## Tests of the remaining small forms: keyword infix heads, await, assert,
## breakpoint, enum, ternary and bodiless abstract functions.
func _test_small_forms() -> void:
	_check_transpiles("infix is", "(is x Node)", "x is Node\n")
	_check_transpiles("infix as", "(as x Node)", "x as Node\n")
	_check_transpiles("infix in", "(in x arr)", "x in arr\n")
	_check_transpiles("infix shift", "(<< a 2)", "a << 2\n")
	_check_transpiles("infix bitand", "(& a b)", "a & b\n")
	_check_transpiles("infix bitor", "(| a b)", "a | b\n")
	_check_transpiles("infix bitxor", "(^ a b)", "a ^ b\n")
	_check_transpiles("infix bitnot", "(~ a)", "~a\n")
	_check_transpiles("infix bitnot nested", "(~ (| a b))", "~(a | b)\n")
	_check_transpiles("await basic", "(await sig)", "await sig\n")
	_check_transpiles("await value", "(var x = (await sig))", "var x = await sig\n")
	_check_transpiles("await operand", "(+ (await x) 1)", "(await x) + 1\n")
	_check_transpiles("assert cond", "(assert ok)", "assert(ok)\n")
	_check_transpiles("assert msg", "(assert ok \"\\\"bad\\\"\")", "assert(ok, \"bad\")\n")
	_check_transpiles("breakpoint", "(breakpoint)", "breakpoint\n")
	_check_transpiles("enum anonymous",
		"(enum A B)",
		"enum {\n\tA,\n\tB,\n}\n")
	_check_transpiles("enum named",
		"(enum (E) A (B 1))",
		"enum E {\n\tA,\n\tB = 1,\n}\n")
	_check_transpiles("enum empty", "(enum)", "enum {}\n")
	_check_transpiles("enum named empty", "(enum (E))", "enum E {}\n")
	_check_transpiles("ternary basic",
		"(ternary c a b)",
		"a if c else b\n")
	_check_transpiles("ternary nested",
		"(ternary (== a b) x y)",
		"x if (a == b) else y\n")
	_check_transpiles("ternary value",
		"(var t = (ternary c 1 2))",
		"var t = 1 if c else 2\n")
	_check_transpiles("abstract bodiless",
		"(func @abstract f (x))",
		"@abstract\nfunc f(x)\n")
	_check_transpiles("abstract return",
		"(func @abstract f (int ()))",
		"@abstract\nfunc f() -> int\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(await)",
		"(await a b)",
		"(assert)",
		"(assert a b c)",
		"(breakpoint x)",
		"(enum (A B C))",
		"(func f () (enum (A)) (pass))",
		"(ternary a b)",
		"(func @abstract f (x) (pass))",
		"(static-func @abstract f (x))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("small error: %s" % c, r["ok"] == false, str(r))


## Tests of file inclusion: splicing, nesting, diamonds, cycles, depth,
## path kinds, usage errors and the transpiler dangling guard.
func _test_includes() -> void:
	# Main pair: transpile_file output matches main.gd byte for byte.
	var main_expected: String = FileAccess.get_file_as_string(INCLUDES_DIR + "/main.gd")
	var rmain: Dictionary = FacadeScript.transpile_file(INCLUDES_DIR + "/main.gdl")
	_check("include main: ok", rmain["ok"] == true, str(rmain.get("error", "")))
	if rmain["ok"]:
		_check_eq("include main: output", rmain["code"], main_expected)
	# Diamond pair: shared content pasted twice, still fine.
	var dia_expected: String = FileAccess.get_file_as_string(INCLUDES_DIR + "/diamond_top.gd")
	var rdia: Dictionary = FacadeScript.transpile_file(INCLUDES_DIR + "/diamond_top.gdl")
	_check("include diamond: ok", rdia["ok"] == true, str(rdia.get("error", "")))
	if rdia["ok"]:
		_check_eq("include diamond: output", rdia["code"], dia_expected)
	# Mutual cycle names the chain.
	var rcyc: Dictionary = FacadeScript.transpile_file(INCLUDES_DIR + "/cycle_a.gdl")
	_check("include cycle: fails", rcyc["ok"] == false, str(rcyc))
	_check("include cycle: names chain", str(rcyc.get("error", "")).contains("circular"), str(rcyc.get("error", "")))
	# Self include is a cycle of one.
	var rself: Dictionary = FacadeScript.transpile_file(INCLUDES_DIR + "/self_inc.gdl")
	_check("include self: fails", rself["ok"] == false, str(rself))
	_check("include self: names chain", str(rself.get("error", "")).contains("circular"), str(rself.get("error", "")))
	# Missing file names the path.
	var rmiss: Dictionary = FacadeScript.transpile_file(INCLUDES_DIR + "/missing_inc.gdl")
	_check("include missing: fails", rmiss["ok"] == false, str(rmiss))
	_check("include missing: names file", str(rmiss.get("error", "")).contains("not found"), str(rmiss.get("error", "")))
	# Depth guard: d1 -> d2 -> d3 fails with max 2, passes by default.
	var d1_text: String = FileAccess.get_file_as_string(INCLUDES_DIR + "/d1.gdl")
	var d1_tok: Dictionary = TokenizerScript.tokenize(d1_text)
	var d1_tree: Dictionary = ParserScript.parse(d1_tok["tokens"])
	var rdeep: Dictionary = IncludesScript.resolve(d1_tree["tree"], INCLUDES_DIR + "/d1.gdl", 2)
	_check("include depth: fails", rdeep["ok"] == false, str(rdeep))
	_check("include depth: names limit", str(rdeep.get("error", "")).contains("depth"), str(rdeep.get("error", "")))
	var rok: Dictionary = IncludesScript.resolve(d1_tree["tree"], INCLUDES_DIR + "/d1.gdl")
	_check("include depth: default ok", rok["ok"] == true, str(rok))
	# Bare text with a res:// include needs no base file.
	var rres: Dictionary = FacadeScript.transpile_text("(include \"" + INCLUDES_DIR + "/common/note.gdl\")")
	_check("include res text: ok", rres["ok"] == true, str(rres.get("error", "")))
	if rres["ok"]:
		_check_eq("include res text: output", rres["code"], "# sibling note\n")
	# Bare text with a relative include has no base and fails.
	var rrel: Dictionary = FacadeScript.transpile_text("(include \"common/note.gdl\")")
	_check("include relative text: fails", rrel["ok"] == false, str(rrel))
	_check("include relative text: names base", str(rrel.get("error", "")).contains("no base"), str(rrel.get("error", "")))
	# Malformed include forms fail before any file access.
	var cases: Array = [
		"(include)",
		"(include \"a.gdl\" \"b.gdl\")",
		"(include (name))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("include error: %s" % c, r["ok"] == false, str(r))
	# Unresolved include reaching the transpiler fails cleanly.
	var transpiler: RefCounted = TranspilerScript.new()
	var rdang: Dictionary = transpiler.transpile([["include", "x.gdl"]])
	_check("include dangling: fails", rdang["ok"] == false, str(rdang))


## Tests of template inheritance: parent defaults, child overrides, nested
## positions, relative parents, strictness errors, cycles and guards.
func _test_templates() -> void:
	# Pair cases (relpath under TEMPLATES_DIR, expected .gd beside).
	var pairs: Array = ["parent", "child", "nested/child", "super_child"]
	for rel in pairs:
		# Expected GDScript read from the .gd file.
		var expected: String = FileAccess.get_file_as_string(TEMPLATES_DIR + "/" + rel + ".gd")
		# Transpilation from file.
		var r: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/" + rel + ".gdl")
		_check("template " + rel + ": ok", r["ok"] == true, str(r.get("error", "")))
		if r["ok"]:
			_check_eq("template " + rel + ": output", r["code"], expected)
	# Unknown block names fail.
	var runk: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/bad_unknown.gdl")
	_check("template unknown: fails", runk["ok"] == false, str(runk))
	_check("template unknown: names block", str(runk.get("error", "")).contains("unknown"), str(runk.get("error", "")))
	# Duplicate blocks fail.
	var rdup: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/bad_dup.gdl")
	_check("template dup: fails", rdup["ok"] == false, str(rdup))
	_check("template dup: names dup", str(rdup.get("error", "")).contains("duplicate"), str(rdup.get("error", "")))
	# Non-block top-level forms in a child fail.
	var rext: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/bad_extra.gdl")
	_check("template extra: fails", rext["ok"] == false, str(rext))
	_check("template extra: names rule", str(rext.get("error", "")).contains("only"), str(rext.get("error", "")))
	# Extends away from the first form reaches the transpiler dangling.
	var rnof: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/bad_notfirst.gdl")
	_check("template notfirst: fails", rnof["ok"] == false, str(rnof))
	_check("template notfirst: names form", str(rnof.get("error", "")).contains("template-extends"), str(rnof.get("error", "")))
	# Mutual parent cycle names the chain.
	var rcyc: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/cyc_a.gdl")
	_check("template cycle: fails", rcyc["ok"] == false, str(rcyc))
	_check("template cycle: names chain", str(rcyc.get("error", "")).contains("circular"), str(rcyc.get("error", "")))
	# Missing parent names the path.
	var rmiss: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/missing_parent.gdl")
	_check("template missing: fails", rmiss["ok"] == false, str(rmiss))
	_check("template missing: names file", str(rmiss.get("error", "")).contains("not found"), str(rmiss.get("error", "")))
	# Super with arguments fails.
	var rsargs: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/bad_super_args.gdl")
	_check("template super args: fails", rsargs["ok"] == false, str(rsargs))
	_check("template super args: names usage", str(rsargs.get("error", "")).contains("no arguments"), str(rsargs.get("error", "")))
	# Parentless super reaches the transpiler dangling.
	var rlone: Dictionary = FacadeScript.transpile_file(TEMPLATES_DIR + "/lone_super.gdl")
	_check("template lone super: fails", rlone["ok"] == false, str(rlone))
	_check("template lone super: names super", str(rlone.get("error", "")).contains("super"), str(rlone.get("error", "")))
	# Bare text with a res:// parent needs no base file.
	var rres: Dictionary = FacadeScript.transpile_text("(template-extends \"" + TEMPLATES_DIR + "/parent.gdl\") (block body (pass))")
	_check("template res text: ok", rres["ok"] == true, str(rres.get("error", "")))
	if rres["ok"]:
		_check_eq("template res text: output", rres["code"], "extends Node\n# default imports\nfunc _ready():\n\tpass\n")
	# Bare text with a relative parent has no base and fails.
	var rrel: Dictionary = FacadeScript.transpile_text("(template-extends \"parent.gdl\") (block body (pass))")
	_check("template relative text: fails", rrel["ok"] == false, str(rrel))
	_check("template relative text: names base", str(rrel.get("error", "")).contains("no base"), str(rrel.get("error", "")))
	# Unresolved forms reaching the transpiler fail cleanly.
	var transpiler: RefCounted = TranspilerScript.new()
	var rblock: Dictionary = transpiler.transpile([["block", "a", ["pass"]]])
	_check("template block dangling: fails", rblock["ok"] == false, str(rblock))
	var rextd: Dictionary = transpiler.transpile([["template-extends", "x.gdl"]])
	_check("template extends dangling: fails", rextd["ok"] == false, str(rextd))


## Tests of user macros: substitution, rest splicing, join, macros in
## macros, values, statements, guards and definition errors.
func _test_macros() -> void:
	# End-to-end pair: safe-call + unless through transpile_file.
	var expected: String = FileAccess.get_file_as_string(MACROS_DIR + "/macros.gd")
	var rpair: Dictionary = FacadeScript.transpile_file(MACROS_DIR + "/macros.gdl")
	_check("macro pair: ok", rpair["ok"] == true, str(rpair.get("error", "")))
	if rpair["ok"]:
		_check_eq("macro pair: output", rpair["code"], expected)
	_check_transpiles("macro value",
		"(defmacro twice (x) (array x x)) (var a = (twice 1))",
		"var a = [\n\t1,\n\t1,\n]\n")
	_check_transpiles("macro in macro",
		"(defmacro twice (x) (array x x)) (defmacro wrap (x) (twice x)) (var a = (wrap 5))",
		"var a = [\n\t5,\n\t5,\n]\n")
	_check_transpiles("macro rest empty",
		"(defmacro mkcall (f ...args) (call f ...args)) (var r = (mkcall foo))",
		"var r = foo()\n")
	_check_transpiles("macro rest multi",
		"(defmacro mkcall (f ...args) (call f ...args)) (var r = (mkcall foo 1 2))",
		"var r = foo(1, 2)\n")
	_check_transpiles("macro join",
		"(defmacro greet (x) (join \"pre-\" x)) (var a = (greet hi))",
		"var a = pre-hi\n")
	_check_transpiles("macro composed arg",
		"(defmacro twice (x) (array x x)) (var a = (twice (call f x)))",
		"var a = [\n\tf(x),\n\tf(x),\n]\n")
	_check_transpiles("macro statement",
		"(defmacro inc (x) (assign x = (+ x 1))) (func f () (inc n) (pass))",
		"func f():\n\tn = n + 1\n\tpass\n")
	_check_transpiles("macro upper",
		"(defmacro sig (n) (signal (join \"on_\" (upper n)))) (sig fell)",
		"signal on_FELL\n")
	_check_transpiles("macro lower",
		"(defmacro mk (n) (var (join \"v_\" (lower n)) = 1)) (mk ABC)",
		"var v_abc = 1\n")
	_check_transpiles("macro capitalize",
		"(defmacro mkc (n) (var (capitalize n) = 1)) (mkc hello)",
		"var Hello = 1\n")
	_check_transpiles("macro nested helpers",
		"(defmacro mk (x y) (var (join (upper x) (lower y)) = 1)) (mk AB Cd)",
		"var ABcd = 1\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(defmacro twice (x) (array x x)) (var a = (twice))",
		"(defmacro twice (x) (array x x)) (var a = (twice 1 2))",
		"(defmacro twice (x) (array x x)) (defmacro twice (x) x)",
		"(defmacro if (x) x)",
		"(func f () (defmacro m (x) x) (pass))",
		"(defmacro loop (x) (loop x)) (loop 1)",
		"(defmacro a (x) (b x)) (defmacro b (x) (a x)) (a 1)",
		"(defmacro bad (x) (join x (call f))) (bad 1)",
		"(defmacro)",
		"(defmacro f)",
		"(defmacro f (x))",
		"(defmacro f x (pass))",
		"(defmacro f (... ) (pass))",
		"(defmacro f (x ...y z) (pass))",
		"(defmacro mk (n) (var (upper n n) = 1)) (mk a)",
		"(defmacro mk (n) (var (upper (call f)) = 1)) (mk a)",
		"(upper x)",
		"(lower x)",
		"(capitalize x)",
		"(join a b)",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("macro error: " + c.left(60), r["ok"] == false, str(r))


## Tests of template iteration: ranges, steps, value lists, nesting,
## composition with macros and the statement-position rule.
func _test_generate() -> void:
	_check_transpiles("generate range",
		"(for-generate (i (range 0 3)) (var (join \"slot_\" i) = i))",
		"var slot_0 = 0\nvar slot_1 = 1\nvar slot_2 = 2\n")
	_check_transpiles("generate step",
		"(for-generate (i (range 0 6 2)) (call print i))",
		"print(0)\nprint(2)\nprint(4)\n")
	_check_transpiles("generate reversed",
		"(for-generate (i (range 3 0 -1)) (call print i))",
		"print(3)\nprint(2)\nprint(1)\n")
	_check_transpiles("generate values",
		"(for-generate (s (a b)) (call print s))",
		"print(a)\nprint(b)\n")
	_check_transpiles("generate empty",
		"(for-generate (i (range 2 2)) (call print i))",
		"")
	_check_transpiles("generate nested",
		"(for-generate (a (x y)) (for-generate (b (1 2)) (var (join a b) = 0)))",
		"var x1 = 0\nvar x2 = 0\nvar y1 = 0\nvar y2 = 0\n")
	_check_transpiles("generate in func",
		"(func f () (for-generate (i (range 0 2)) (pass)))",
		"func f():\n\tpass\n\tpass\n")
	_check_transpiles("generate calls macro",
		"(defmacro twice (x) (array x x)) (for-generate (i (range 0 2)) (var (join \"a\" i) = (twice i)))",
		"var a0 = [\n\t0,\n\t0,\n]\nvar a1 = [\n\t1,\n\t1,\n]\n")
	_check_transpiles("macro generates",
		"(defmacro gen (n) (for-generate (i (range 0 n)) (var (join \"v\" i) = i))) (gen 2)",
		"var v0 = 0\nvar v1 = 1\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(for-generate)",
		"(for-generate (i (range 0 2)))",
		"(for-generate i (pass))",
		"(for-generate ((i) (range 0 2)) (pass))",
		"(for-generate (i x) (pass))",
		"(for-generate (i (range a b)) (pass))",
		"(for-generate (i (range 0 2 0)) (pass))",
		"(for-generate (i (range 0 2000)) (pass))",
		"(var t = (for-generate (i (range 0 2)) (pass)))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("generate error: " + c.left(60), r["ok"] == false, str(r))
	# Unresolved generator reaching the transpiler fails cleanly.
	var transpiler: RefCounted = TranspilerScript.new()
	var rdang: Dictionary = transpiler.transpile([["for-generate", ["i", ["range", "0", "1"]], ["pass"]]])
	_check("generate dangling: fails", rdang["ok"] == false, str(rdang))


## Tests of template variables and conditional inclusion: set/tvar values,
## when/when-not branches, redefinition, sequential order and errors.
func _test_set_when() -> void:
	_check_transpiles("setwhen value",
		"(template-set greeting \"\\\"hi\\\"\") (var g = (tvar greeting))",
		"var g = \"hi\"\n")
	_check_transpiles("setwhen when true",
		"(template-set debug true) (when debug (var d = 1)) (var always = 2)",
		"var d = 1\nvar always = 2\n")
	_check_transpiles("setwhen when false",
		"(template-set debug false) (when debug (var d = 1)) (var always = 2)",
		"var always = 2\n")
	_check_transpiles("setwhen when-not",
		"(template-set debug false) (when-not debug (var r = 1))",
		"var r = 1\n")
	_check_transpiles("setwhen when-not true",
		"(template-set debug true) (when-not debug (var r = 1)) (var s = 2)",
		"var s = 2\n")
	_check_transpiles("setwhen redefine",
		"(template-set a 1) (template-set a 2) (var b = (tvar a))",
		"var b = 2\n")
	_check_transpiles("setwhen in func",
		"(template-set x 5) (func f () (var y = (tvar x)) (when x (pass)))",
		"func f():\n\tvar y = 5\n\tpass\n")
	_check_transpiles("setwhen call value",
		"(template-set maker (call make 1)) (var m = (tvar maker))",
		"var m = make(1)\n")
	# Bare forms rejected by the facade (ok must be false).
	var cases: Array = [
		"(when nope (pass))",
		"(var x = (tvar nope))",
		"(template-set)",
		"(template-set x)",
		"(template-set x 1 2)",
		"(when debug)",
		"(template-set debug true) (when-not nope (pass))",
	]
	for c in cases:
		# Facade result, expected to fail.
		var r: Dictionary = FacadeScript.transpile_text(c)
		_check("setwhen error: " + c.left(60), r["ok"] == false, str(r))
	# Unresolved forms reaching the transpiler fail cleanly.
	var transpiler2: RefCounted = TranspilerScript.new()
	for dangling in [["template-set", "x", "1"], ["tvar", "x"], ["when", "x", ["pass"]], ["when-not", "x", ["pass"]]]:
		# One dangling form transpiled directly.
		var rdang: Dictionary = transpiler2.transpile([dangling])
		_check("setwhen dangling: fails", rdang["ok"] == false, str(rdang))


## Tests of the sidecar watcher through the plugin implementation (null
## proxy: the core takes explicit paths, editor wiring stays unwired).
## Covers collection, sibling generation with stamp header, change-only
## rewrites, failure handling with retry guards and orphan retention.
func _test_watcher() -> void:
	# Watcher implementation without editor (null proxy, core only).
	var watcher: RefCounted = PluginImplScript.new(null)
	# Probe source with known content in ./tmp.
	var src: String = "res://tmp/watch_probe.gdl"
	var dst: String = "res://tmp/watch_probe.gd"
	var probe: FileAccess = FileAccess.open(src, FileAccess.WRITE)
	probe.store_string("(class-name WatchProbe)\n(extends Node)\n(var w = 7)\n")
	probe.close()
	# First run writes the stamped sibling.
	var r1: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: updated", (r1["updated"] as Array) == [dst], str(r1))
	_check_eq("watcher: content", FileAccess.get_file_as_string(dst), "# GENERATED FROM watch_probe.gdl BY GNUMARUS - DO NOT EDIT\nclass_name WatchProbe\nextends Node\nvar w = 7\n")
	# Second run changes nothing (content hashes, no rewrite).
	var r2: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: quiet", (r2["updated"] as Array).is_empty() and (r2["failed"] as Array).is_empty(), str(r2))
	# Edited source regenerates the sibling.
	var edit: FileAccess = FileAccess.open(src, FileAccess.WRITE)
	edit.store_string("(class-name WatchProbe)\n(extends Node)\n(var w = 8)\n")
	edit.close()
	var r3: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: reupdated", (r3["updated"] as Array) == [dst], str(r3))
	_check("watcher: new content", FileAccess.get_file_as_string(dst).contains("var w = 8"), FileAccess.get_file_as_string(dst))
	# Broken source fails without touching the good sibling.
	var bad: FileAccess = FileAccess.open(src, FileAccess.WRITE)
	bad.store_string("(nope bar)\n")
	bad.close()
	var r4: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: failed", (r4["failed"] as Array) == [src], str(r4))
	_check("watcher: sibling kept", FileAccess.get_file_as_string(dst).contains("var w = 8"), FileAccess.get_file_as_string(dst))
	# Same broken hash is not reported twice (spam guard).
	var r5: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: guarded", (r5["failed"] as Array).is_empty(), str(r5))
	# Deleted source leaves its orphan sibling behind.
	DirAccess.remove_absolute(src)
	var r6: Dictionary = watcher.transpile_sidecars("res://tmp")
	_check("watcher: orphan kept", FileAccess.file_exists(dst), "orphan sibling removed")
	DirAccess.remove_absolute(dst)
	# Missing root reports nothing to do (no crash).
	var r7: Dictionary = watcher.transpile_sidecars("res://tmp/no_such_dir")
	_check("watcher: missing root", (r7["updated"] as Array).is_empty() and (r7["failed"] as Array).is_empty(), str(r7))
	# The addon self-test fixtures are never watcher inputs, not even
	# forced: saving a `.gdl` while hacking the addon cannot stamp the
	# expected `.gd` outputs the byte comparisons rely on.
	_check("watcher: skips addon tests", PluginImplScript.collect_gdl(TESTS_DIR).is_empty(), str(PluginImplScript.collect_gdl(TESTS_DIR)))
	# Forced run over the fixtures root touches nothing (no stamps back).
	var r8: Dictionary = watcher.transpile_sidecars(TESTS_DIR, true)
	_check("watcher: forced skip", (r8["updated"] as Array).is_empty() and (r8["failed"] as Array).is_empty(), str(r8))


## Tests of Gnumarus source coloring: rainbow depths, indent levels,
## strings, GDScript word classes (keyword vs control flow, base and engine
## types, global functions, get/set, annotations), numbers, errors, theme
## injection and state carrying.
func _test_highlighter() -> void:
	# Color engine without editor (pure data logic).
	var colorizer: RefCounted = ColorizerScript.new()
	# Fallback colors (Godot dark-theme defaults).
	var defaults: Dictionary = ThemeScript.DEFAULT_COLORS
	# Rainbow depths on one line (matchers share the opener hue).
	var maps: Array = colorizer.compute_all(PackedStringArray(["(func f (x) (pass))"]))
	_check_eq("highlight open depth", maps[0][0]["color"], ColorizerScript.RAINBOW_COLORS[0])
	_check_eq("highlight nested depth", maps[0][8]["color"], ColorizerScript.RAINBOW_COLORS[1])
	_check_eq("highlight matcher depth", maps[0][10]["color"], ColorizerScript.RAINBOW_COLORS[1])
	_check_eq("highlight inner close", maps[0][17]["color"], ColorizerScript.RAINBOW_COLORS[1])
	_check_eq("highlight close depth", maps[0][18]["color"], ColorizerScript.RAINBOW_COLORS[0])
	# Plain GDScript keywords share the keyword color (context-free).
	_check_eq("highlight keyword", maps[0][1]["color"], defaults["keyword"])
	_check_eq("highlight keyword atom", colorizer.color_for_atom("var"), defaults["keyword"])
	_check_eq("highlight keyword class_name", colorizer.color_for_atom("class_name"), defaults["keyword"])
	_check_eq("highlight keyword operator", colorizer.color_for_atom("and"), defaults["keyword"])
	_check_eq("highlight keyword value", colorizer.color_for_atom("true"), defaults["keyword"])
	_check("highlight plain atom", not maps[0].has(6), str(maps[0].keys()))
	_check_eq("highlight plain category", colorizer.category_for_atom("my_var"), "")
	# Control-flow keywords keep their own red, Gnumarus extras included.
	_check_eq("highlight control if", colorizer.category_for_atom("if"), "control_flow")
	_check_eq("highlight control while", colorizer.category_for_atom("while"), "control_flow")
	_check_eq("highlight control return", colorizer.category_for_atom("return"), "control_flow")
	_check_eq("highlight control match", colorizer.category_for_atom("match"), "control_flow")
	_check_eq("highlight control branch", colorizer.category_for_atom("branch"), "control_flow")
	_check_eq("highlight control for-generate", colorizer.category_for_atom("for-generate"), "control_flow")
	_check_eq("highlight control when-not", colorizer.category_for_atom("when-not"), "control_flow")
	_check_eq("highlight control color", colorizer.color_for_atom("if"), defaults["control_flow"])
	var flow: Array = colorizer.compute_all(PackedStringArray(["(if x (pass))"]))
	_check_eq("highlight control line", flow[0][1]["color"], defaults["control_flow"])
	# Gnumarus-only operations fall back to the keyword color.
	_check_eq("highlight gdl defmacro", colorizer.category_for_atom("defmacro"), "keyword")
	_check_eq("highlight gdl join", colorizer.category_for_atom("join"), "keyword")
	_check_eq("highlight gdl class-name", colorizer.category_for_atom("class-name"), "keyword")
	_check_eq("highlight gdl dict-lua", colorizer.category_for_atom("dict-lua"), "keyword")
	_check_eq("highlight gdl call", colorizer.category_for_atom("call"), "keyword")
	# get/set use the function color, like the GDScript highlighter.
	_check_eq("highlight get category", colorizer.category_for_atom("get"), "function")
	_check_eq("highlight set category", colorizer.category_for_atom("set"), "function")
	_check_eq("highlight get color", colorizer.color_for_atom("get"), defaults["function"])
	# Global functions share the global-function color.
	_check_eq("highlight global assert", colorizer.category_for_atom("assert"), "global_function")
	_check_eq("highlight global print", colorizer.category_for_atom("print"), "global_function")
	_check_eq("highlight global range", colorizer.category_for_atom("range"), "global_function")
	_check_eq("highlight global lerp", colorizer.category_for_atom("lerp"), "global_function")
	_check_eq("highlight global color", colorizer.color_for_atom("print"), defaults["global_function"])
	# Base types and every engine class map to their GDScript colors.
	_check_eq("highlight base int", colorizer.category_for_atom("int"), "base_type")
	_check_eq("highlight base String", colorizer.category_for_atom("String"), "base_type")
	_check_eq("highlight base Array", colorizer.category_for_atom("Array"), "base_type")
	_check_eq("highlight base void", colorizer.category_for_atom("void"), "base_type")
	_check_eq("highlight base color", colorizer.color_for_atom("int"), defaults["base_type"])
	_check_eq("highlight engine Node", colorizer.category_for_atom("Node"), "engine_type")
	_check_eq("highlight engine Node3D", colorizer.category_for_atom("Node3D"), "engine_type")
	_check_eq("highlight engine Resource", colorizer.category_for_atom("Resource"), "engine_type")
	_check_eq("highlight engine color", colorizer.color_for_atom("Node"), defaults["engine_type"])
	var typed: Array = colorizer.compute_all(PackedStringArray(["(var n int = 5)"]))
	_check_eq("highlight line keyword", typed[0][1]["color"], defaults["keyword"])
	_check_eq("highlight line base type", typed[0][7]["color"], defaults["base_type"])
	_check_eq("highlight line number", typed[0][13]["color"], defaults["number"])
	var extends_line: Array = colorizer.compute_all(PackedStringArray(["(extends Node)"]))
	_check_eq("highlight line engine type", extends_line[0][9]["color"], defaults["engine_type"])
	# Lowercase array is the Gnumarus operation, not the GDScript type.
	_check_eq("highlight array op", colorizer.category_for_atom("array"), "keyword")
	# Fallbacks match the Godot dark-theme defaults byte for byte.
	_check_eq("highlight default keyword", defaults["keyword"], Color(1.0, 1.0, 0.7))
	_check_eq("highlight default control", defaults["control_flow"], Color(1.0, 0.85, 0.7))
	_check_eq("highlight default base", defaults["base_type"], Color(0.64, 1.0, 0.83))
	_check_eq("highlight default engine", defaults["engine_type"], Color(0.51, 0.83, 1.0))
	_check_eq("highlight default string", defaults["string"], Color(0.94, 0.43, 0.75))
	_check_eq("highlight default number", defaults["number"], Color(0.92, 0.58, 0.2))
	_check_eq("highlight default annotation", defaults["annotation"], Color(1.0, 0.7, 0.45))
	_check_eq("highlight default global", defaults["global_function"], Color(0.64, 0.64, 0.96))
	_check_eq("highlight default function", defaults["function"], Color(0.4, 0.64, 0.81))
	# Theme injection swaps colors, moves the theme hash and validates input.
	var before_hash: int = colorizer.theme_hash()
	var custom: Dictionary = {"keyword": Color(0.1, 0.2, 0.3), "control_flow": Color(0.4, 0.5, 0.6)}
	var rok: Dictionary = colorizer.configure(custom)
	_check("highlight configure: ok", rok["ok"] == true, str(rok))
	_check_eq("highlight configure: keyword", colorizer.color_for_atom("var"), Color(0.1, 0.2, 0.3))
	_check_eq("highlight configure: control", colorizer.color_for_atom("if"), Color(0.4, 0.5, 0.6))
	_check_eq("highlight configure: untouched", colorizer.color_for_atom("int"), defaults["base_type"])
	_check("highlight configure: hash moved", colorizer.theme_hash() != before_hash, "")
	var bad_key: Dictionary = colorizer.configure({"nope": Color.WHITE})
	_check("highlight configure: bad key", bad_key["ok"] == false, str(bad_key))
	_check_eq("highlight configure: kept keyword", colorizer.color_for_atom("var"), Color(0.1, 0.2, 0.3))
	var bad_value: Dictionary = colorizer.configure({"keyword": "red"})
	_check("highlight configure: bad value", bad_value["ok"] == false, str(bad_value))
	_check_eq("highlight configure: kept anyway", colorizer.color_for_atom("var"), Color(0.1, 0.2, 0.3))
	# Indented line: indent block plus depth-zero parens.
	var indented: Array = colorizer.compute_all(PackedStringArray(["  (var x)"]))
	_check_eq("highlight indent", indented[0][0]["color"], ColorizerScript.RAINBOW_COLORS[2].darkened(ColorizerScript.INDENT_DARKEN))
	_check_eq("highlight indent paren", indented[0][2]["color"], ColorizerScript.RAINBOW_COLORS[0])
	# Unbalanced closers glow error red.
	var unbalanced: Array = colorizer.compute_all(PackedStringArray(["(a))"]))
	_check_eq("highlight unbalanced", unbalanced[0][3]["color"], ColorizerScript.ERROR_COLOR)
	# Packed spans color whole, escapes never close early.
	var strings: Array = colorizer.compute_all(PackedStringArray(["(comment \"a\\\"b c\")"]))
	for c in [9, 10, 11, 12, 13, 14, 15]:
		_check_eq("highlight string " + str(c), strings[0][c]["color"], defaults["string"])
	# Annotations and numbers classify, lone @ errors.
	var special: Array = colorizer.compute_all(PackedStringArray(["(var @export n = 42)"]))
	_check_eq("highlight annotation", special[0][5]["color"], defaults["annotation"])
	_check_eq("highlight annotation atom", colorizer.color_for_atom("@export"), defaults["annotation"])
	_check_eq("highlight number", special[0][17]["color"], defaults["number"])
	var lone: Array = colorizer.compute_all(PackedStringArray(["(var @ n)"]))
	_check_eq("highlight lone at", lone[0][5]["color"], ColorizerScript.ERROR_COLOR)
	# Depth and string state carry across lines (closer mid-line resumes).
	# Line depths: "(func f" opens 1; "(comment" opens 2; the "(pass))"
	# line therefore opens at 2 and shuts 3->2->1.
	var carried: Array = colorizer.compute_all(PackedStringArray(["(func f", "  (comment \"a", "b\" trailing", "(pass))"]))
	_check_eq("highlight carried depth", carried[1][2]["color"], ColorizerScript.RAINBOW_COLORS[1])
	_check_eq("highlight carried closer", carried[2][1]["color"], defaults["string"])
	_check("highlight resumed atom", not carried[2].has(3), str(carried[2].keys()))
	_check_eq("highlight resumed paren", carried[3][0]["color"], ColorizerScript.RAINBOW_COLORS[2])
	_check_eq("highlight resumed close", carried[3][6]["color"], ColorizerScript.RAINBOW_COLORS[1])
	# Highlighter implementation without editor (null proxy: no TextEdit,
	# theme sync stays a no-op and line queries come back empty).
	var impl: RefCounted = HighlighterImplScript.new(null)
	_check_eq("highlight impl name", impl._get_name(), "Gnumarus")
	_check_eq("highlight impl langs", impl._get_supported_languages(), PackedStringArray(["gdl"]))
	_check("highlight impl no editor", impl._get_line_syntax_highlighting(0).is_empty(), "")
	impl.sync_theme()
	_check("highlight impl sync headless", impl._get_line_syntax_highlighting(0).is_empty(), "")
	# NOTE: GnumarusGdlHighlighter itself only instantiates inside the editor
	# (engine rule for editor-virtual classes, like the proxies), so the thin
	# proxy (name/langs/factory/memo) is covered by preload parse plus review;
	# all coloring logic above runs through plain RefCounted classes.


## End to end tests: .gdl -> code identical to the expected .gd.
func _test_end_to_end() -> void:
	# Fixture cases (base file names under TESTS_DIR).
	var cases: Array = ["Test1", "Test2", "Test3", "Test4", "Test5", "Test6", "StressTest"]
	for c in cases:
		# Lisp input text read from the .gdl file.
		var gdl: String = FileAccess.get_file_as_string(TESTS_DIR + "/" + c + ".gdl")
		# Expected GDScript read from the .gd file.
		var expected: String = FileAccess.get_file_as_string(TESTS_DIR + "/" + c + ".gd")
		# Transpilation from text.
		var r: Dictionary = FacadeScript.transpile_text(gdl)
		_check(c + ": transpile_text ok", r["ok"] == true, str(r.get("error", "")))
		if r["ok"]:
			_check_eq(c + ": output matches expected", r["code"], expected)
		# Transpilation from file.
		var rf: Dictionary = FacadeScript.transpile_file(TESTS_DIR + "/" + c + ".gdl")
		_check(c + ": transpile_file ok", rf["ok"] == true, str(rf.get("error", "")))
		if rf["ok"]:
			_check_eq(c + ": file matches expected", rf["code"], expected)


## Facade/transpiler error tests: invalid operations and missing file.
func _test_transpiler_errors() -> void:
	# Transpiler instance holding the v1 operation table.
	var transpiler: RefCounted = TranspilerScript.new()
	_check("transpiler: 72 registered operations", transpiler.operation_names().size() == 72, str(transpiler.operation_names()))
	# Unknown operation must fail, not invent output.
	var r1: Dictionary = FacadeScript.transpile_text("(foo bar)")
	_check("transpiler error: unknown operation", r1["ok"] == false, str(r1))
	# Func without body must fail (GDScript needs an indented block).
	var r3: Dictionary = FacadeScript.transpile_text("(func f ())")
	_check("transpiler error: bodiless func", r3["ok"] == false, str(r3))
	# Nested class-name inside a func body must fail (top level only).
	var r4: Dictionary = FacadeScript.transpile_text("(func f () (class-name X) (pass))")
	_check("transpiler error: nested class-name", r4["ok"] == false, str(r4))
	# Missing file must fail quoting the path.
	var r5: Dictionary = FacadeScript.transpile_file(TESTS_DIR + "/Missing.gdl")
	_check("facade error: missing file", r5["ok"] == false, str(r5))
