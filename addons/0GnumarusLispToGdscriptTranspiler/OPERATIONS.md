# OPERATIONS.md — GDLisp → GDScript transpiler operations

Reference for all 78 implemented operations: name, description, where
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

## 0. Operation index

All 78 operations with a one-line description. Normal operations emit
GDScript directly; special operations vanish before transpilation
(template structure resolved in the include/inheritance phases, macro
forms expanded in the macro phase).

### Normal transpilation operations (63 — emit GDScript)

| Operation | Short description |
|---|---|
| `class-name` | Declares `class_name`. |
| `extends` | Declares `extends`. |
| `var` | Declares a variable (5 positional forms). |
| `static-var` | Declares a `static` variable. |
| `const` | Declares a constant (always initialized). |
| `comment` | Emits a `#` comment. |
| `pass` | Emits `pass`. |
| `func` | Declares a function. |
| `static-func` | Declares a `static` function. |
| `signal` | Declares a signal. |
| `class` | Declares an inner class. |
| `enum` | Declares an enum. |
| `if` | `if` branch with optional trailing `elif`/`else`. |
| `elif` | `elif` branch (only trailing inside `if`). |
| `else` | `else` branch (only trailing inside `if`). |
| `while` | `while` loop. |
| `for` | `for ... in ...` loop (optional type). |
| `break` | Emits `break`. |
| `continue` | Emits `continue`. |
| `return` | Emits `return` (optional value). |
| `match` | `match` statement. |
| `branch` | `match` branch (only as a direct child of `match`). |
| `lambda` | Anonymous `func(...)` value (value positions only). |
| `call` | Function call `name(args...)`. |
| `chain` | Method/property chain `root.a().b`. |
| `get` | Trailing `get` accessor of `var`/`static-var`. |
| `set` | Trailing `set` accessor of `var`/`static-var`. |
| `+` | N-ary addition `a + b + c`. |
| `-` | Binary subtraction `a - b` / unary negation `-x`. |
| `*` | Multiplication `a * b`. |
| `/` | Division `a / b`. |
| `%` | Remainder `a % b`. |
| `**` | Power `a ** b`. |
| `==` | Equality comparison. |
| `!=` | Inequality comparison. |
| `<` | Less-than comparison. |
| `>` | Greater-than comparison. |
| `<=` | Less-than-or-equal comparison. |
| `>=` | Greater-than-or-equal comparison. |
| `and` | N-ary logical `and`. |
| `or` | N-ary logical `or`. |
| `not` | Unary logical `not`. |
| `is` | Type test `x is Node`. |
| `as` | Cast `x as Node`. |
| `in` | Membership test `x in arr`. |
| `<<` | Left shift `a << 2`. |
| `>>` | Right shift `a >> 2`. |
| `&` | Bitwise and `a & b`. |
| `|` | Bitwise or `a | b`. |
| `^` | Bitwise xor `a ^ b`. |
| `~` | Bitwise not `~a` (no space). |
| `assign` | Assignment / compound assignment statement. |
| `await` | `await` expression. |
| `assert` | `assert(...)` statement. |
| `breakpoint` | Bare `breakpoint` statement. |
| `ternary` | `a if cond else b` expression. |
| `unpack-arr-safe` | Safe array unpacking: bounds + type-checked assignments. |
| `unpack-arr` | Optimistic array unpacking: initialized declarations, no checks. |
| `unpack-dict-safe` | Safe dict unpacking: null + membership + type-checked assignments. |
| `unpack-dict` | Optimistic dict unpacking: initialized declarations, no checks. |
| `array` | Array literal. |
| `dict-lua` | Lua-style dict (`key = value`). |
| `dict-json` | JSON-style dict (`key: value`). |

Note: `@` annotations are not operations (no list form of their own);
they are leading `@` atoms on `class-name`, `extends`, `var`,
`static-var`, `func`, `static-func` and `class`.

### Special template operations (5 — resolved before transpilation)

| Operation | Short description |
|---|---|
| `include` | Splices another file's top-level forms. |
| `block` | Declares (parent) / overrides (child) a named template block. |
| `template-extends` | Inherits a child template from a parent file. |
| `super` | Pastes the parent block default inside an override. |
| `include-only` | Marks a file as an include-only snippet (no sidecar). |

### Special macro operations (10 — expanded before transpilation)

| Operation | Short description |
|---|---|
| `defmacro` | Defines a top-level syntactic macro. |
| `join` | Concatenates atoms (macro bodies only). |
| `upper` | Uppercases an atom (macro bodies only). |
| `lower` | Lowercases an atom (macro bodies only). |
| `capitalize` | Capitalizes an atom (macro bodies only). |
| `for-generate` | Template generation: unrolls a body per value (range or list). |
| `template-set` | Binds a template variable. |
| `tvar` | Pastes a template variable value. |
| `when` | Pastes a body when a variable is bound and truthy. |
| `when-not` | Pastes a body when a variable is unbound or falsy. |

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

### `unpack-arr-safe` — `(unpack-arr-safe arr (specs...))`

Unpacks an array into variables with per-index bounds checks. Each spec
uses the same 5 positional forms as `var`, without the `var` head: bare
atom (`a`), `(b)`, `(c int)`, `(d = 5)`, `(e := 6)`, `(f float = 0.5)`.
Emits one `var` declaration per spec, one `<arr>_size_<n>` snapshot (`n`
from a per-transpilation counter, so repeated unpacks never collide and
the output stays deterministic), then one `if <size> > <i>:` guard per
index (missing elements keep the declared default; assignments never
carry type hints). Specs with an explicit type read through a
`<arr>_tmp_<n>` scratch variable (emitted only when at least one spec is
checked) and assign only inside a nested
`is_instance_of(<tmp>, <check>)` guard; `<check>` is the `TYPE_*`
constant for canonical Variant type names (`int` → `TYPE_INT`,
`Object` → `TYPE_OBJECT`) and the raw atom otherwise (`Node`, custom
scripts). Untyped and `:=` specs assign directly.
Example:

```lisp
(unpack-arr-safe myarr (a (c int) (d float = 9.0)))
```

```gdscript
var a
var c: int
var d: float = 9.0
var myarr_size_0 = myarr.size()
var myarr_tmp_0
if myarr_size_0 > 0:
	a = myarr[0]
if myarr_size_0 > 1:
	myarr_tmp_0 = myarr[1]
	if is_instance_of(myarr_tmp_0, TYPE_INT):
		c = myarr_tmp_0
if myarr_size_0 > 2:
	myarr_tmp_0 = myarr[2]
	if is_instance_of(myarr_tmp_0, TYPE_FLOAT):
		d = myarr_tmp_0
```

Invalid (missing `=` before the default, like `var`):

```lisp
(unpack-arr-safe myarr ((d float 9)))
```

> `transpiler: missing '=' before default value: usage (unpack-arr-safe d float = value)`

- **Where allowed**: any level (`top`, `member`, `local`).
- **Where invalid**: as a value (`var` default, `return`, argument,
  operand — it expands to multiple lines); empty spec list; non-atom
  array; `@` annotations and `get`/`set` accessors in specs.

### `unpack-arr` — `(unpack-arr arr (specs...))`

Optimistic counterpart of `unpack-arr-safe`: one initialized declaration
per spec (`var a = arr[0]`, `var c: int = arr[2]`), with no size
snapshot and no bounds checks. Only the 3 default-less `var` shapes are
accepted (bare atom, `(n)`, `(n T)`); any `=`/`:=` default is a usage
error, since values always come straight from the array. Short arrays or
mistyped elements fail at GDScript runtime.
Example:

```lisp
(unpack-arr myarr (a (c int)))
```

```gdscript
var a = myarr[0]
var c: int = myarr[1]
```

Invalid (defaults are forbidden):

```lisp
(unpack-arr myarr ((d = 5)))
```

> `transpiler: unpack-arr forbids default values (got '["d", "=", "5"]'): values always come from the array — usages: (unpack-arr arr (n (m T)))`

- **Where allowed**: any level (`top`, `member`, `local`).
- **Where invalid**: as a value; empty spec list; non-atom array; any
  default (`=`, `:=`); `@` annotations and `get`/`set` accessors.

### `unpack-dict-safe` — `(unpack-dict-safe dict ((name key) ...))`

Safe dictionary unpacking: one `var` declaration per spec (the `var`
shapes with an explicit key second: `(n k)`, `(n k T)`, `(n k = v)`,
`(n k := v)`, `(n k T = v)`), then one `if <dict>:` null guard holding
one `if <key> in <dict>:` membership check per spec (missing keys keep
the declared default). Keys are verbatim atoms (pack String keys, e.g.
`(a "'id'")`; ints work bare: `(n 0 int)`). Like `unpack-arr-safe`,
specs with an explicit type read through a `<dict>_tmp_<n>` scratch
variable (shared per-transpilation counter, only when checked) and
assign only inside `is_instance_of(<tmp>, <check>)`; untyped and `:=`
specs assign directly.
Example:

```lisp
(unpack-dict-safe mydict ((a "'id'") (c "'age'" int)))
```

```gdscript
var a
var c: int
var mydict_tmp_0
if mydict:
	if 'id' in mydict:
		a = mydict['id']
	if 'age' in mydict:
		mydict_tmp_0 = mydict['age']
		if is_instance_of(mydict_tmp_0, TYPE_INT):
			c = mydict_tmp_0
```

Invalid (specs require an explicit key):

```lisp
(unpack-dict-safe mydict (a))
```

> `transpiler: unpack-dict-safe specs must be (name key ...) lists with an explicit key (got 'a')`

- **Where allowed**: any level (`top`, `member`, `local`).
- **Where invalid**: as a value; empty spec list; non-atom dict; bare
  atoms or key-less lists; empty/non-atom keys; `@` annotations and
  `get`/`set` accessors in specs.

### `unpack-dict` — `(unpack-dict dict ((name key) ...))`

Optimistic counterpart of `unpack-dict-safe`: one initialized
declaration per spec (`var a = d['id']`), with no null guard and no
checks. Only the 2 default-less keyed shapes (`(n k)`, `(n k T)`); any
`=`/`:=` default is a usage error. Missing keys or mistyped values fail
at GDScript runtime.
Example:

```lisp
(unpack-dict mydict ((a "'id'") (c "'age'" int)))
```

```gdscript
var a = mydict['id']
var c: int = mydict['age']
```

Invalid (defaults are forbidden):

```lisp
(unpack-dict mydict ((d "'k'" = 5)))
```

> `transpiler: unpack-dict forbids default values (got '["d", "\'k\'", "=", "5"]'): values always come from the dict — usages: (unpack-dict d ((n k) (m j T)))`

- **Where allowed**: any level (`top`, `member`, `local`).
- **Where invalid**: as a value; empty spec list; non-atom dict; bare
  atoms or key-less lists; any default (`=`, `:=`); `@` annotations
  and `get`/`set` accessors.

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

Line comments (`;` and `#` to end of line) are separate from this
operation: the tokenizer discards them anywhere outside packed spans,
so `(var a) ; trailing` transpiles to `var a`.

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

### `include` — `(include path)` / `(include path trace)`

Replaced by the file's top-level forms (glued splice, never nested).
Paths: relative to the including file, `res://`, `user://`, system `/`,
and current-user home `~/` (`USERPROFILE` with `HOME` fallback on
Windows, `HOME` elsewhere; `~name` rejected).
Guards: cycles (canonical stack) and max depth 32.
With a `true` trace flag, the spliced forms come wrapped in marker
comments (`false` or omitted: today's behavior). Markers are plain
`(comment ...)` forms, so they follow normal statement rules (leading
ones become declaration trailing comments) and compose across nesting
levels; empty includes still emit both markers.
Example (from a file; bare text + relative fails for lack of a base):

```lisp
(include "res://addons/0GnumarusLispToGdscriptTranspiler/tests/includes/common/note.gdl")
```

```gdscript
# sibling note
```

Traced example (`traced_user.gdl`):

```lisp
(class-name TracedUser)
(include "traced_snippet.gdl" true)
```

```gdscript
class_name TracedUser
# BEGIN include traced_snippet.gdl (res://addons/0GnumarusLispToGdscriptTranspiler/tests/includes/traced_snippet.gdl)
var tv = 3
# END include traced_snippet.gdl (res://addons/0GnumarusLispToGdscriptTranspiler/tests/includes/traced_snippet.gdl)
```

- **Where allowed**: any position (expands structurally).
- **Where invalid**: malformed forms (bad arity, non-`true`/`false`
  flag, traced paths with line breaks); missing files; cycles;
  relative paths without a base file.

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

### `include-only` — `(include-only)`

Marks the file as include-only: the watcher produces no sidecar for
it (parsed, never transpiled, so intentionally invalid snippets stay
silent), and inclusion strips the marker before transpiling.
Pre-existing siblings become kept orphans (delete once by hand).

- **Where allowed**: bare, at the top level of snippet files.
- **Where invalid**: reaching the transpiler (direct transpiles, inside
  functions, malformed with arguments) fails naming the directive;
  unknown in strict template-child tops.

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
