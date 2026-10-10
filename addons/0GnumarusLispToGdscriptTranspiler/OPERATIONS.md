# OPERATIONS.md — Gnumarus Lisp → GDScript transpiler operations

Reference for all 73 implemented operations: name, description, where
each form may appear, where using it is invalid, and usage examples with
the produced GDScript output. Every example below was executed on the
transpiler (or is a fixture compared byte for byte by the suite).

## How to read this document

- **Contexts**: `top` (file level), `member` (class body),
  `local` (function body). The transpiler rejects out-of-context forms
  with a usage message.
- **Statement vs value**: some operations work as statements (bare line)
  and as values (`var` default, `return`, argument, operand); others are
  statement-only. Meta-template and macro operations vanish before
  transpilation (include, inheritance and expansion phases).
- **Verbatim rule**: atoms come out as GDScript source exactly as
  written. A GDScript string literal requires double packing
  (pack it in Lisp AND write the quotes inside), e.g.
  `(var a String = "\"hi\"")` produces `var a: String = "hi"`.
- **Dangling**: forms only valid in a special position (`elif`,
  `branch`, bare `lambda`...) fail with a usage error when they reach
  the transpiler outside of it.

## 1. Declarations

### `class-name` — `(class-name Name)`

Declares `class_name Name`, with optional leading `@` atoms (one per
line).
Example:

```lisp
(class-name MyClass)
```

```gdscript
class_name MyClass
```

- **Where allowed**: `top` only.
- **Where invalid**: inside `class` or `func` (placement error).

### `extends` — `(extends Base)`

Declares `extends Base`, with optional leading `@` atoms.
Example:

```lisp
(extends Node)
```

```gdscript
extends Node
```

- **Where allowed**: `top` and `class` bodies (inner-class inheritance).
- **Where invalid**: inside `func`.

### `var` — `(var name)` / `(var name Type)` / `(var name = v)` / `(var name := v)` / `(var name Type = v)`

Declares a variable in the 5 positional forms. The `=` before the
default is **mandatory**; `:=` is inference (never combined with a
type).
Examples:

```lisp
(var a)
(var b int)
(var n = 5)
(var n := 10)
(var c float = 0.0)
```

```gdscript
var a
var b: int
var n = 5
var n := 10
var c: float = 0.0
```

Invalid (fails with a usage message):

```lisp
(var a String 5)
```

> `transpiler: missing '=' before default value: usage (var a String = value)`

- **Where allowed**: any level (`top`, `member`, `local`).
- **Where invalid**: `(var name Type := v)` (plain GDScript rejects it);
  trailing `(get ...)`/`(set ...)` accessors only on members (see
  `get`/`set`).

### `static-var` — like `var`, with `static`

Example:

```lisp
(static-var n int = 1)
```

```gdscript
static var n: int = 1
```

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func`; same restrictions as `var`.

### `const` — `(const name = v)` / `(const name := v)` / `(const name Type = v)`

Declares a constant (always with an initializer; atom values only).
Examples:

```lisp
(const max = 10)
(const max float = 10.0)
```

```gdscript
const max = 10
const max: float = 10.0
```

Invalid:

```lisp
(const a)
```

> `transpiler: invalid 'const' form; usages: (const n = v), (const n := v), (const n T = v)`

- **Where allowed**: any level, including inside `func`.
- **Where invalid**: without a value; `(const n T := v)`; `(lambda ...)`
  values (plain Godot rejects them); no `@` annotations.

### `comment` — `(comment text...)`

Emits `# text` (atoms joined with spaces; empty yields a bare `#`). As
the first body element of `func`/`lambda`, it becomes a trailing
comment on the declaration line instead of its own line.
Example:

```lisp
(comment hello world)
```

```gdscript
# hello world
```

- **Where allowed**: any level.
- **Where invalid**: list arguments (atoms only).

### `pass` — `(pass)`

Emits `pass`. Example:

```lisp
(pass)
```

```gdscript
pass
```

- **Where allowed**: any level.
- **Where invalid**: with arguments.

### `func` — `(func name (signature...) body...)`

Declares `func name(args...) [-> Ret]:` + body. Return-first
signature: `()` nothing, `(void)` returns `void` with no args,
`(R (ARGS...))` returns `R` with grouped args; anything else is a flat
arg (`...rest` passes through literally). Argument: bare atom, `(n)`,
`(n T)`, `(n = v)`, `(n := v)`, `(n T = v)`.
Example:

```lisp
(func _ready () (pass))
```

```gdscript
func _ready():
	pass
```

With return type and typed argument:

```lisp
(func f ((a int)) (pass))
(func f (void) (pass))
```

```gdscript
func f(a: int):
	pass
func f() -> void:
	pass
```

Invalid (empty body):

```lisp
(func f ())
```

> `transpiler: function 'f' has no body: GDScript requires at least one indented line`

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func` (no local classes in GDScript);
  without a body (except bodiless `@abstract`, which emits a `:`-less
  declaration).

### `static-func` — like `func`, with `static`

Example:

```lisp
(static-func f () (pass))
```

```gdscript
static func f():
	pass
```

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func`; with `@abstract`.

### `signal` — `(signal name)` / `(signal name (args...))`

Declares a `signal`, with the same argument grammar as `func`
(but no return type).
Examples:

```lisp
(signal hit)
(signal moved (from to))
```

```gdscript
signal hit
signal moved(from, to)
```

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func`; with a declared return type; with
  `@`.

### `class` — `(class Name members...)`

Declares an inner class `class Name:` + members (`member` context;
everything top-level except `class-name`; nests freely).
Example:

```lisp
(class Inner (extends Node) (pass))
```

```gdscript
class Inner:
	extends Node
	pass
```

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func`; without a body.

### `enum` — `(enum ITEMS...)` / `(enum (Name) ITEMS...)`

Declares `enum [Name] {...}` (entries: atoms, `(N)`, `(N V)`).
Examples:

```lisp
(enum (E) A (B 1))
(enum A B)
```

```gdscript
enum E {
	A,
	B = 1,
}
enum {
	A,
	B,
}
```

- **Where allowed**: `top` and `class` bodies.
- **Where invalid**: inside `func`.

## 2. Control flow

### `if` / `elif` / `else`

`(if cond body...)` with trailing `(elif ...)`/`(else ...)` consumed as
a flat chain at the same level. Condition: verbatim atom or single-line
expression.
Example:

```lisp
(if "x > 0" (return 1) (elif "x < 0" (return -1)) (else (return 0)))
```

```gdscript
if x > 0:
	return 1
elif x < 0:
	return -1
else:
	return 0
```

Invalid (outside a chain):

```lisp
(elif "a" (pass))
```

> `transpiler: elif is only valid as a trailing form of (if ...)`

- **Where allowed**: any level.
- **Where invalid**: `(elif ...)`/`(else ...)` outside `(if ...)`; empty
  `if` branch before the chain; non-trailing `else`; sub-links inside
  `elif`/`else` bodies (nest an inner `(if ...)` instead).

### `while` — `(while cond body...)`

Example:

```lisp
(while "x > 0" (pass))
```

```gdscript
while x > 0:
	pass
```

- **Where allowed**: any level.
- **Where invalid**: without a body; `(lambda ...)` or multiline
  condition.

### `for` — `(for name in iter body...)` / `(for name Type in iter body...)`

The `in` marker mirrors GDScript; optional type in the 2nd slot.
Examples:

```lisp
(for x in items (pass))
(for n int in items (pass))
```

```gdscript
for x in items:
	pass
for n: int in items:
	pass
```

- **Where allowed**: any level.
- **Where invalid**: without the `in` marker; `in` as the name;
  `(lambda ...)` or multiline iterable.

### `break` / `continue`

Example:

```lisp
(while "true" (break))
```

```gdscript
while true:
	break
```

- **Where allowed**: any level.
- **Where invalid**: with arguments.

### `return` — `(return)` / `(return value)`

Value: verbatim atom, `(lambda ...)` or expression.
Example:

```lisp
(func f () (return 0))
```

```gdscript
func f():
	return 0
```

- **Where allowed**: any level.
- **Where invalid**: with 2+ values.

### `match` / `branch` — `(match subject branches...)`

Every direct child must be a `(branch pattern body...)` form. Patterns
are verbatim atoms (pack multiples, arrays, dicts; `"_"` wildcard;
binding requires an explicit `var` in the pattern).
Example:

```lisp
(match "x" (branch "1" (pass)) (branch "_" (pass)))
```

```gdscript
match x:
	1:
		pass
	_:
		pass
```

Invalid (outside `match`):

```lisp
(branch "1" (pass))
```

> `transpiler: branch is only valid as a direct child of (match ...)`

- **Where allowed**: any level.
- **Where invalid**: direct children that are not `branch`; empty
  pattern; sub-branches in the body (nest an inner `(match ...)`
  instead).

## 3. Functions as values and calls

### `lambda` — `(lambda (signature...) body...)`

A `func(args...):` value + body (same signature grammar and
trailing-comment rule as `func`; header carries no indentation, the
caller places the line). Valid in `var` defaults and `return`.
Example:

```lisp
(var cb = (lambda (x) (return x)))
```

```gdscript
var cb = func(x):
	return x
```

Invalid (bare as a statement):

```lisp
(lambda (x) (pass))
```

> `transpiler: lambda is only valid as a value (var default, return value...) — e.g. (var cb = (lambda (x) (pass)))`

- **Where allowed**: value positions (`var`, `return`, `assign`).
- **Where invalid**: as a statement; in single-line args/operands; in
  `const`; in collections.

### `call` — `(call name args...)`

A `name(a1, a2)` call, as a statement and as a value (nests without
extra parentheses; `call` never needs them). The target may itself be
an expression, invoking the returned value: `(call (call f x) 1)`
produces `f(x)(1)`.
Examples:

```lisp
(call f x)
(call f (call g x))
```

```gdscript
f(x)
f(g(x))
```

Invalid:

```lisp
(call)
```

> `transpiler: usage: (call name args...) — e.g. (call print x)`

- **Where allowed**: statements, values, operands and args.
- **Where invalid**: without a name; lambdas in args (bind to a `var`
  first); collections as targets. Non-atom targets must be expressions:
  `(call (a) x)` fails.

### `chain` — `(chain root links...)`

A `root.link(...).prop` chain: each list link appends `.name(args)`
and each bare-atom link appends `.name` (property access). The root is
a verbatim atom or a nested expression (chains compose in root
position); links never nest. Statement, value and operand.
Examples:

```lisp
(chain myobj (qwer 0) (asdf 1) (zxcv 2))
(chain o pos x)
(chain (call f x) (m 1))
```

```gdscript
myobj.qwer(0).asdf(1).zxcv(2)
o.pos.x
f(x).m(1)
```

Invalid:

```lisp
(chain o)
```

> `transpiler: usage: (chain root (method args...)... [prop]...) — e.g. (chain myobj (qwer 0) (asdf 1))`

- **Where allowed**: statements, values and operands.
- **Where invalid**: without links; empty links; empty root or property;
  malformed link shapes.

### `get` / `set` — trailing accessors of `var`/`static-var`

`(get body...)` / `(set (name) body...)` become blocks (the declaration
gains `:`); single-atom inline form becomes a same-line reference.
Examples:

```lisp
(var h int = 1 (get (return h)))
(var h = 1 (set (v) (pass)))
(var e = 1 (get get_e))
```

```gdscript
var h: int = 1:
	get:
		return h
var h = 1:
	set(v):
		pass
var e = 1: get = get_e
```

- **Where allowed**: trailing `var`/`static-var` on members.
- **Where invalid**: bare as statements; local `var` with accessors;
  duplicates; mixed inline+block; `set` with anything but 1 bare
  parameter (no type).

## 4. Infix expressions, `assign`, `await`, `assert`, `breakpoint`, `ternary`

Valid as statements and as values (nested infix operands gain
parentheses by construction: `(* (+ a b) c)` becomes `(a + b) * c`).

| Operation | GDScript | Example |
|---|---|---|
| `+` (n-ary) | `a + b + c` | `(+ a b c)` |
| `-` (binary) | `a - b` | `(- a b)` |
| `-` (unary) | `-x` | `(- x)` |
| `*` `/` `%` `**` | `a * b`, `a / b`, `a % b`, `a ** b` | `(* a b)` |
| `==` `!=` `<` `>` `<=` `>=` | comparisons | `(== a b)` |
| `and` `or` (n-ary) | `a and b`, `a or b` | `(and a (or b c))` → `a and (b or c)` |
| `not` (unary) | `not x` | `(not x)` |
| `is` `as` `in` | `x is Node`, `x as Node`, `x in arr` | `(is x Node)` |
| `<<` `>>` `&` `^` | shifts and bits | `(<< a 2)` → `a << 2` |
| `~` (unary, no space) | `~a` | `(~ a)` |

- **Where allowed**: statements, values and operands.
- **Where invalid**: wrong arity (`(+)`, `(+ a)`, `(not a b)`);
  lambda/multiline statement as an operand.
- The `|` operator (bitwise or) follows the same rule: `(| a b)`
  produces `a | b`.

### `assign` — `(assign target op value)`

`target OP value` with OP in
`= += -= *= /= %= <<= >>= &= |= ^= **=` (statement only, atom target).
Example:

```lisp
(assign x += 1)
```

```gdscript
x += 1
```

- **Where allowed**: statement-only, any level.
- **Where invalid**: as a value; list targets; unknown operators.

### `await` — `(await x)`

Composes and parenthesizes like a bare infix; statement, value and
operand.
Examples:

```lisp
(await sig)
(var x = (await sig))
```

```gdscript
await sig
var x = await sig
```

- **Where allowed**: statements, values and operands.
- **Where invalid**: with anything but 1 argument.

### `assert` — `(assert cond)` / `(assert cond msg)`

Statement-only. Example:

```lisp
(assert ok)
```

```gdscript
assert(ok)
```

- **Where allowed**: statement-only.
- **Where invalid**: as a value; with 0 or 3+ args.

### `breakpoint` — `(breakpoint)`

Emits a bare `breakpoint` without parentheses, statement-only.

- **Where allowed**: statement-only.
- **Where invalid**: with arguments; as a value.

### `ternary` — `(ternary cond a b)`

Emits `a if cond else b`; statement, value and operand (structured
conditions gain parentheses).
Example:

```lisp
(ternary c a b)
```

```gdscript
a if c else b
```

- **Where allowed**: statements, values and operands.
- **Where invalid**: with anything but 3 arguments.

## 5. Collections

Always multiline (trailing comma, +1 indent), except empty ones
(`[]`/`{}`). Elements, keys and values accept atoms and nested
expressions (including collection-in-collection); lambdas inside are
rejected.

### `array` — `(array elems...)`

Examples:

```lisp
(array)
(array 1 2)
```

```gdscript
[]
[
	1,
	2,
]
```

### `dict-lua` — `(dict-lua (key value)...)`

Keys come out bare (Lua style). Example:

```lisp
(dict-lua (a 1) (b 2))
```

```gdscript
{
	a = 1,
	b = 2,
}
```

### `dict-json` — `(dict-json (key value)...)`

Keys with `:` (JSON style; anything needing quotes uses this one).
Example:

```lisp
(dict-json ("\"k\"" 1))
```

```gdscript
{
	"k": 1,
}
```

- **Where allowed**: statements, values, `call` args and elements.
- **Where invalid**: pairs with wrong arity; lambdas inside.

## 6. `@` annotations

Leading `@` atoms after the operator, one verbatim line per annotation
at the same indent (parameterized ones pack: `"@export_range(0, 100)"`).
Example:

```lisp
(var @export hp int = 100)
```

```gdscript
@export
var hp: int = 100
```

- **Where allowed**: `class-name`, `extends`, `var`, `static-var`,
  `func`, `static-func`, `class`.
- **Where invalid**: on `signal`/`const`; lone `@`; `@` names; inside
  `comment` the `@` is plain text.

## 7. Meta-template and macros (vanish before GDScript)

### `include` — `(include path)`

Replaced by the file's top-level forms (glued splice, never nested).
Paths: relative to the including file, `res://`, `user://`, system `/`.
Guards: cycles (canonical stack) and max depth 32.
Example (from a file; bare text + relative fails for lack of a base):

```lisp
(include "res://addons/0GnumarusLispToGdscriptTranspiler/tests/includes/common/note.gdl")
```

```gdscript
# sibling note
```

- **Where allowed**: any position (expands structurally).
- **Where invalid**: malformed forms; missing files; cycles; relative
  paths without a base file.

### `block` — `(block NAME body...)`

In the parent, declares a default (a lone parent stays valid: the
block becomes the glued body). In the child (only `template-extends` +
`block`s at the top), overrides by name. Flat names.
Example (parent `parent.gdl`):

```lisp
(extends Node)
(block imports
  (comment "default imports"))
(func _ready ()
  (block body
    (pass)))
```

- **Where allowed**: any position in the parent; top-level only in the
  child.
- **Where invalid**: unknown/duplicated blocks in the child; extra
  top-level forms in the child.

### `template-extends` — `(template-extends PATH)`

First top-level form of the child: inherits from the parent and merges
overrides (per-side includes, recursive chains, limit 32).
Example (child `child.gdl` + output):

```lisp
(template-extends "parent.gdl")
(block imports
  (comment "child imports"))
(block body
  (call print "\"hi\""))
```

```gdscript
extends Node
# child imports
func _ready():
	print("hi")
```

- **Where allowed**: first top-level form of the child only.
- **Where invalid**: anywhere else (dangling at the transpiler);
  missing parent; cycles.

### `super` — `(super)`

Argument-less, in an override body pastes the block default (per
occurrence; chains across levels).
Example (`super_child.gdl` → `.gd`):

```lisp
(template-extends "parent.gdl")
(block body
  (super)
  (call print "\"hi\""))
```

```gdscript
extends Node
# default imports
func _ready():
	pass
	print("hi")
```

- **Where allowed**: override bodies of a child only.
- **Where invalid**: with arguments; without a parent block (dangling).

### `defmacro` — `(defmacro NAME (params...) SINGLE-FORM-BODY)`

Defines a top-level macro (vanishes, produces no code). Calls become
the body with raw args substituted (unhygienic). At most one trailing
`...rest`, splashed where the atom appears. Fixed-point expansion
(macros use macros) with a 1024-expansion budget and depth 64
(recursion = error).
Example:

```lisp
(defmacro twice (x) (array x x))
(var a = (twice 1))
```

```gdscript
var a = [
	1,
	1,
]
```

Fixture with `...rest` (`tests/macros/macros.gdl`):

```lisp
(defmacro safe-call (obj mname ...args)
  (if (and obj (call (join obj ".has_method") (join "\"" mname "\"")))
    (call (join obj "." mname) ...args)))

(defmacro unless (cond body)
  (if (not cond) body))
```

- **Where allowed**: top-level only (definitions); calls in any
  statement/value position the body fits.
- **Where invalid**: outside the top level; duplicated/reserved names;
  wrong call arity; direct/mutual recursion; multi-form bodies.

### `join` / `upper` / `lower` / `capitalize`

Macro-body helpers only: `(join a b...)` concatenates atoms; the rest
convert case (Jinja style).
Example:

```lisp
(defmacro greet (x) (join "pre-" x))
(var a = (greet hi))
```

```gdscript
var a = pre-hi
```

Invalid (outside a body):

```lisp
(join a b)
```

> `transpiler: join is only valid inside macro bodies`

- **Where allowed**: macro bodies only.
- **Where invalid**: outside them (dangling at the transpiler).

### `for-generate` — `(for-generate (VAR SOURCE) BODY...)`

Repeats the body per value: `(range A B [STEP])` (exclusive end) or a
literal value list. Each iteration pastes copies with VAR bound (nested
macros and `for-generate` compose). Iterations share the budget.
Example:

```lisp
(for-generate (i (range 0 3)) (var (join "slot_" i) = i))
```

```gdscript
var slot_0 = 0
var slot_1 = 1
var slot_2 = 2
```

- **Where allowed**: statement/element positions (splice).
- **Where invalid**: in single-value slots, which fail fast naming both
  forms:

```lisp
(var t = (for-generate (i (range 0 2)) (pass)))
```

> `macro: (for-generate ...) cannot be used as a single value (here: inside (var ...)) — it expands to zero or multiple forms, so it is only valid in statement positions`

Malformed sources and zero STEP also fail.

### `template-set` / `tvar` / `when` / `when-not`

Single flat environment, sequential evaluation:
`(template-set NAME VALUE)` expands and binds (vanishes; redefinable);
`(tvar NAME)` pastes the stored node; `(when NAME BODY...)` pastes when
bound and truthy (only `""` and `"false"` are falsy),
`(when-not ...)` inverts. Undefined names are errors.
Examples:

```lisp
(template-set debug true)
(when debug (var d = 1))
```

```gdscript
var d = 1
```

```lisp
(template-set greeting "\"hi\"")
(var g = (tvar greeting))
```

```gdscript
var g = "hi"
```

Invalid:

```lisp
(when nope (pass))
```

> `macro: undefined template variable "nope"`

- **Where allowed**: `template-set`/`when`/`when-not` in statements;
  `tvar` in values.
- **Where invalid**: undefined names; wrong arities.
