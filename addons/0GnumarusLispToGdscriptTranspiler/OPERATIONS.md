# OPERATIONS.md — Operações do transpilador Gnumarus Lisp → GDScript

Referência de todas as 72 operações implementadas: nome, descrição, onde
cada forma pode aparecer, onde é inválido usá-la e exemplos de uso com a
saída GDScript produzida. Todos os exemplos abaixo foram executados no
transpilador (ou são fixtures comparados byte a byte pela suite).

## Como ler este documento

- **Contextos**: `top` (nível do arquivo), `member` (corpo de classe),
  `local` (corpo de função). O transpilador rejeita a forma fora do seu
  contexto com mensagem de uso.
- **Statement vs valor**: algumas operações valem como statement (linha
  solta) e como valor (default de `var`, `return`, argumento, operando);
  outras são só statement. Operações de meta-template e macros somem
  antes da transpilação (fases de include, herança e expansão).
- **Regra verbatim**: átomos saem como fonte GDScript exatamente como
  escritos. Literal string GDScript exige empacotamento duplo
  (empacotar no Lisp E escrever as aspas por dentro), ex.
  `(var a String = "\"hi\"")` gera `var a: String = "hi"`.
- **Dangling**: formas que só valem em posição especial (`elif`, `branch`,
  `lambda` solta...) falham com erro de uso se alcançarem o transpilador
  fora dela.

## 1. Declarações

### `class-name` — `(class-name Nome)`

Declara `class_name Nome`, com `@` líderes opcionais (um por linha).
Exemplo:

```lisp
(class-name MyClass)
```

```gdscript
class_name MyClass
```

- **Onde pode**: só em `top`.
- **Onde é inválido**: dentro de `class` ou `func` (erro de posicionamento).

### `extends` — `(extends Base)`

Declara `extends Base`, com `@` líderes opcionais.
Exemplo:

```lisp
(extends Node)
```

```gdscript
extends Node
```

- **Onde pode**: `top` e corpos de `class` (herança de classe interna).
- **Onde é inválido**: dentro de `func`.

### `var` — `(var nome)` / `(var nome Tipo)` / `(var nome = v)` / `(var nome := v)` / `(var nome Tipo = v)`

Declara variável nas 5 formas posicionais. O `=` antes do default é
**obrigatório**; `:=` é inferência (nunca combinado com tipo).
Exemplos:

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

Inválido (falha com mensagem de uso):

```lisp
(var a String 5)
```

> `transpiler: missing '=' before default value: usage (var a String = value)`

- **Onde pode**: qualquer nível (`top`, `member`, `local`).
- **Onde é inválido**: `(var nome Tipo := v)` (o próprio GDScript rejeita);
  acessores `(get ...)`/`(set ...)` trailing só em membros (ver `get`/`set`).

### `static-var` — como `var`, com `static`

Exemplo:

```lisp
(static-var n int = 1)
```

```gdscript
static var n: int = 1
```

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func`; mesmas restrições do `var`.

### `const` — `(const nome = v)` / `(const nome := v)` / `(const nome Tipo = v)`

Declara constante (sempre com inicializador; valores só átomos).
Exemplos:

```lisp
(const max = 10)
(const max float = 10.0)
```

```gdscript
const max = 10
const max: float = 10.0
```

Inválido:

```lisp
(const a)
```

> `transpiler: invalid 'const' form; usages: (const n = v), (const n := v), (const n T = v)`

- **Onde pode**: qualquer nível, inclusive dentro de `func`.
- **Onde é inválido**: sem valor; `(const n T := v)`; valor `(lambda ...)`
  (o próprio Godot rejeita); sem anotacoes `@`.

### `comment` — `(comment texto...)`

Emite `# texto` (átomos unidos com espaço; vazio vira `#` nu). Como
primeiro elemento do corpo de `func`/`lambda`, vira comentário trailing
na linha de declaração em vez de linha própria.
Exemplo:

```lisp
(comment hello world)
```

```gdscript
# hello world
```

- **Onde pode**: qualquer nível.
- **Onde é inválido**: argumentos que sejam listas (só átomos).

### `pass` — `(pass)`

Emite `pass`. Exemplo:

```lisp
(pass)
```

```gdscript
pass
```

- **Onde pode**: qualquer nível.
- **Onde é inválido**: com argumentos.

### `func` — `(func nome (assinatura...) corpo...)`

Declara `func nome(args...) [-> Ret]:` + corpo. Assinatura com retorno
primeiro: `()` nada, `(void)` retorna `void` sem args, `(R (ARGS...))`
retorna `R` com args agrupados; resto é arg plano
(`...rest` passa literal). Argumento: átomo nu, `(n)`, `(n T)`,
`(n = v)`, `(n := v)`, `(n T = v)`.
Exemplo:

```lisp
(func _ready () (pass))
```

```gdscript
func _ready():
	pass
```

Com retorno e argumento tipado:

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

Inválido (corpo vazio):

```lisp
(func f ())
```

> `transpiler: function 'f' has no body: GDScript requires at least one indented line`

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func` (sem classes locais no GDScript);
  sem corpo (exceto `@abstract` sem corpo, que emite declaração sem `:`).

### `static-func` — como `func`, com `static`

Exemplo:

```lisp
(static-func f () (pass))
```

```gdscript
static func f():
	pass
```

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func`; com `@abstract`.

### `signal` — `(signal nome)` / `(signal nome (args...))`

Declara `signal`, com a mesma gramática de argumentos de `func`
(mas sem tipo de retorno).
Exemplos:

```lisp
(signal hit)
(signal moved (from to))
```

```gdscript
signal hit
signal moved(from, to)
```

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func`; com retorno declarado; com `@`.

### `class` — `(class Nome membros...)`

Declara classe interna `class Nome:` + membros (contexto `member`;
vale tudo de topo exceto `class-name`; aninha livremente).
Exemplo:

```lisp
(class Inner (extends Node) (pass))
```

```gdscript
class Inner:
	extends Node
	pass
```

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func`; sem corpo.

### `enum` — `(enum ENTS...)` / `(enum (Nome) ENTS...)`

Declara `enum [Nome] {...}` (entradas: átomos, `(N)`, `(N V)`).
Exemplos:

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

- **Onde pode**: `top` e corpos de `class`.
- **Onde é inválido**: dentro de `func`.

## 2. Fluxo de controle

### `if` / `elif` / `else`

`(if cond corpo...)` com `(elif ...)`/`(else ...)` trailing consumidos
como cadeia plana no mesmo nível. Condição: átomo verbatim ou expressão
de linha única.
Exemplo:

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

Inválido (fora de cadeia):

```lisp
(elif "a" (pass))
```

> `transpiler: elif is only valid as a trailing form of (if ...)`

- **Onde pode**: qualquer nível.
- **Onde é inválido**: `(elif ...)`/`(else ...)` fora de `(if ...)`; ramo
  `if` vazio antes da cadeia; `else` não por último; sub-links dentro de
  corpos de `elif`/`else` (aninhar com `(if ...)` interno).

### `while` — `(while cond corpo...)`

Exemplo:

```lisp
(while "x > 0" (pass))
```

```gdscript
while x > 0:
	pass
```

- **Onde pode**: qualquer nível.
- **Onde é inválido**: sem corpo; condição `(lambda ...)` ou multilinha.

### `for` — `(for nome in iter corpo...)` / `(for nome Tipo in iter corpo...)`

O marcador `in` espelha o GDScript; tipo opcional no 2o slot.
Exemplos:

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

- **Onde pode**: qualquer nível.
- **Onde é inválido**: sem marcador `in`; `in` como nome; iterável
  `(lambda ...)` ou multilinha.

### `break` / `continue`

Exemplo:

```lisp
(while "true" (break))
```

```gdscript
while true:
	break
```

- **Onde pode**: qualquer nível.
- **Onde é inválido**: com argumentos.

### `return` — `(return)` / `(return valor)`

Valor: átomo verbatim, `(lambda ...)` ou expressão.
Exemplo:

```lisp
(func f () (return 0))
```

```gdscript
func f():
	return 0
```

- **Onde pode**: qualquer nível.
- **Onde é inválido**: com 2+ valores.

### `match` / `branch` — `(match subj ramos...)`

Todo filho direto precisa ser `(branch padrao corpo...)`. Padrões são
átomos verbatim (empacotar múltiplos, arrays, dicts; `"_"` curinga;
binding exige `var` explícito no padrão).
Exemplo:

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

Inválido (fora de `match`):

```lisp
(branch "1" (pass))
```

> `transpiler: branch is only valid as a direct child of (match ...)`

- **Onde pode**: qualquer nível.
- **Onde é inválido**: filho direto que não seja `branch`; padrão vazio;
  sub-ramos no corpo (aninhar com `(match ...)` interno).

## 3. Funções como valores e chamadas

### `lambda` — `(lambda (assinatura...) corpo...)`

Valor `func(args...):` + corpo (mesma gramática de assinatura e
trailing-comment de `func`; sem indentação no cabeçalho, o chamador
posiciona). Vale em defaults de `var` e em `return`.
Exemplo:

```lisp
(var cb = (lambda (x) (return x)))
```

```gdscript
var cb = func(x):
	return x
```

Inválido (solta como statement):

```lisp
(lambda (x) (pass))
```

> `transpiler: lambda is only valid as a value (var default, return value...) — e.g. (var cb = (lambda (x) (pass)))`

- **Onde pode**: posições de valor (`var`, `return`, `assign`).
- **Onde é inválido**: como statement; em args/operandos de linha única;
  em `const`; em coleções.

### `call` — `(call nome args...)`

Chamada `nome(a1, a2)`, como statement e como valor (aninha sem
parênteses extras; `call` nunca precisa deles).
Exemplos:

```lisp
(call f x)
(call f (call g x))
```

```gdscript
f(x)
f(g(x))
```

Inválido:

```lisp
(call)
```

> `transpiler: usage: (call name args...) — e.g. (call print x)`

- **Onde pode**: statements, valores, operandos e args.
- **Onde é inválido**: sem nome; nome que seja lista; lambda em args
  (ligar a `var` antes).

### `get` / `set` — acessores trailing de `var`/`static-var`

`(get corpo...)` / `(set (nome) corpo...)` viram blocos (declaração
ganha `:`); forma inline de átomo único vira referência na mesma linha.
Exemplos:

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

- **Onde pode**: trailing de `var`/`static-var` em membros.
- **Onde é inválido**: soltos como statement; `var` local com acessor;
  duplicados; misto inline+bloco; `set` com ≠1 parâmetro (nu, sem tipo).

## 4. Expressões infixas, `assign`, `await`, `assert`, `breakpoint`, `ternary`

Valem como statement e como valor (operandos infixos aninhados ganham
parênteses por construção: `(* (+ a b) c)` vira `(a + b) * c`).

| Operação | GDScript | Exemplo |
|---|---|---|
| `+` (n-ária) | `a + b + c` | `(+ a b c)` |
| `-` (binário) | `a - b` | `(- a b)` |
| `-` (unário) | `-x` | `(- x)` |
| `*` `/` `%` `**` | `a * b`, `a / b`, `a % b`, `a ** b` | `(* a b)` |
| `==` `!=` `<` `>` `<=` `>=` | comparações | `(== a b)` |
| `and` `or` (n-ários) | `a and b`, `a or b` | `(and a (or b c))` → `a and (b or c)` |
| `not` (unário) | `not x` | `(not x)` |
| `is` `as` `in` | `x is Node`, `x as Node`, `x in arr` | `(is x Node)` |
| `<<` `>>` `&` `\|` `^` | shifts e bits | `(<< a 2)` → `a << 2` |
| `~` (unário, sem espaço) | `~a` | `(~ a)` |

- **Onde pode**: statements, valores e operandos.
- **Onde é inválido**: aridade errada (`(+)`, `(+ a)`, `(not a b)`);
  lambda/statement multilinha como operando.
- O operador `|` (ou bit a bit) segue a mesma regra: `(| a b)` gera
  `a | b`.

### `assign` — `(assign alvo op valor)`

`alvo OP valor` com OP em
`= += -= *= /= %= <<= >>= &= |= ^= **=` (só statement; alvo átomo).
Exemplo:

```lisp
(assign x += 1)
```

```gdscript
x += 1
```

- **Onde pode**: só como statement, qualquer nível.
- **Onde é inválido**: como valor; alvo lista; operador desconhecido.

### `await` — `(await x)`

Compõe e parentetiza como infixo solto; statement, valor e operando.
Exemplos:

```lisp
(await sig)
(var x = (await sig))
```

```gdscript
await sig
var x = await sig
```

- **Onde pode**: statements, valores e operandos.
- **Onde é inválido**: com ≠1 argumento.

### `assert` — `(assert cond)` / `(assert cond msg)`

Só statement. Exemplo:

```lisp
(assert ok)
```

```gdscript
assert(ok)
```

- **Onde pode**: só como statement.
- **Onde é inválido**: como valor; com 0 ou 3+ args.

### `breakpoint` — `(breakpoint)`

Sai `breakpoint` sem parênteses, só statement.

- **Onde pode**: só como statement.
- **Onde é inválido**: com argumentos; como valor.

### `ternary` — `(ternary cond a b)`

Emite `a if cond else b`; statement, valor e operando (condição
estruturada ganha parênteses).
Exemplo:

```lisp
(ternary c a b)
```

```gdscript
a if c else b
```

- **Onde pode**: statements, valores e operandos.
- **Onde é inválido**: com ≠3 argumentos.

## 5. Coleções

Sempre multiline (vírgula final, indent +1), exceto vazias (`[]`/`{}`).
Elementos/chaves/valores aceitam átomos e expressões aninhadas
(inclusive coleção em coleção); lambdas dentro são rejeitadas.

### `array` — `(array elems...)`

Exemplos:

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

### `dict-lua` — `(dict-lua (chave valor)...)`

Chaves saem nuas (estilo Lua). Exemplo:

```lisp
(dict-lua (a 1) (b 2))
```

```gdscript
{
	a = 1,
	b = 2,
}
```

### `dict-json` — `(dict-json (chave valor)...)`

Chaves com `:` (estilo JSON; o que precisar de aspas usa este).
Exemplo:

```lisp
(dict-json ("\"k\"" 1))
```

```gdscript
{
	"k": 1,
}
```

- **Onde pode**: statements, valores, args de `call` e elementos.
- **Onde é inválido**: pares com aridade errada; lambda dentro.

## 6. Anotações `@`

Átomos `@` líderes após o operador, um por linha verbatim no mesmo
indent (parametrizadas empacotam-se: `"@export_range(0, 100)"`).
Exemplo:

```lisp
(var @export hp int = 100)
```

```gdscript
@export
var hp: int = 100
```

- **Onde pode**: `class-name`, `extends`, `var`, `static-var`, `func`,
  `static-func`, `class`.
- **Onde é inválido**: em `signal`/`const`; `@` sozinho; nomes com `@`;
  em `comment` o `@` é só texto.

## 7. Meta-template e macros (somem antes do GDScript)

### `include` — `(include caminho)`

Substituído pelas formas de topo do arquivo (splice colado, nunca
aninhado). Caminhos: relativo ao arquivo que inclui, `res://`,
`user://`, `/` de sistema. Guardas: ciclo (pilha canônica) e
profundidade máxima 32.
Exemplo (via arquivo; texto puro + relativo falha por falta de base):

```lisp
(include "res://addons/0GnumarusLispToGdscriptTranspiler/tests/includes/common/note.gdl")
```

```gdscript
# sibling note
```

- **Onde pode**: qualquer posição (expande estruturalmente).
- **Onde é inválido**: forma malformada; arquivo ausente; ciclo;
  relativo sem arquivo-base.

### `block` — `(block NOME corpo...)`

No pai, declara default (pai sozinho continua válido: o bloco vira o
corpo colado). No filho (só `template-extends` + `block`s no topo),
sobrescreve por nome. Nomes planos.
Exemplo (pai `parent.gdl`):

```lisp
(extends Node)
(block imports
  (comment "default imports"))
(func _ready ()
  (block body
    (pass)))
```

- **Onde pode**: qualquer posição no pai; só topo no filho.
- **Onde é inválido**: bloco desconhecido/duplicado no filho; formas
  extras no topo do filho.

### `template-extends` — `(template-extends CAMINHO)`

Primeira forma do topo do filho: herda do pai e mescla overrides
(includes por lado, cadeias recursivas, limite 32).
Exemplo (filho `child.gdl` + saída):

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

- **Onde pode**: só primeira forma do topo do filho.
- **Onde é inválido**: fora da primeira posição (vira dangling no
  transpiler); pai ausente; ciclo.

### `super` — `(super)`

Sem argumentos, em corpo de override cola o default do bloco (por
ocorrência; encadeia entre níveis).
Exemplo (`super_child.gdl` → `.gd`):

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

- **Onde pode**: só em corpo de override de filho.
- **Onde é inválido**: com argumentos; sem bloco pai (dangling).

### `defmacro` — `(defmacro NOME (params...) CORPO-FORMA-UNICA)`

Define macro no topo (some, não gera código). Chamadas viram o corpo
com args crus substituídos (sem higiene). No máximo um `...rest` por
último, respingado. Expansão em ponto-fixo (macros usam macros) com
orçamento de 1024 expansões e profundidade 64 (recursão = erro).
Exemplo:

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

Fixture com `...rest` (`tests/macros/macros.gdl`):

```lisp
(defmacro safe-call (obj mname ...args)
  (if (and obj (call (join obj ".has_method") (join "\"" mname "\"")))
    (call (join obj "." mname) ...args)))

(defmacro unless (cond body)
  (if (not cond) body))
```

- **Onde pode**: só no topo (definição); chamadas em qualquer posição
  de statement/valor conforme o corpo.
- **Onde é inválido**: fora do topo; nome duplicado/reservado; aridade
  errada na chamada; recursão direta/mútua; corpo multiforma.

### `join` / `upper` / `lower` / `capitalize`

Helpers só em corpos de macro: `(join a b...)` concatena átomos;
os demais convertem caixa (estilo Jinja).
Exemplo:

```lisp
(defmacro greet (x) (join "pre-" x))
(var a = (greet hi))
```

```gdscript
var a = pre-hi
```

Inválido (fora de corpo):

```lisp
(join a b)
```

> `transpiler: join is only valid inside macro bodies`

- **Onde pode**: só em corpos de macro.
- **Onde é inválido**: fora deles (dangling no transpiler).

### `for-generate` — `(for-generate (VAR FONTE) CORPO...)`

Repete o corpo por valor: `(range A B [STEP])` (fim exclusivo) ou
lista literal. Cada iteração cola cópias com VAR ligado (macros e
`for-generate` aninhados compõem). Iterações dividem o orçamento.
Exemplo:

```lisp
(for-generate (i (range 0 3)) (var (join "slot_" i) = i))
```

```gdscript
var slot_0 = 0
var slot_1 = 1
var slot_2 = 2
```

- **Onde pode**: posições de statement/elemento (splice).
- **Onde é inválido**: em slots de valor único (ex.
  `(var t = (for-generate ...))` falha); fonte malformada; STEP zero.

### `template-set` / `tvar` / `when` / `when-not`

Ambiente plano único, avaliação sequencial: `(template-set NOME VALOR)`
expande e liga (some; redefine); `(tvar NOME)` cola o nó guardado;
`(when NOME CORPO...)` cola se ligado e verdadeiro (só `""` e `"false"`
são falsos), `(when-not ...)` inverte. Nome indefinido é erro.
Exemplos:

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

Inválido:

```lisp
(when nope (pass))
```

> `macro: undefined template variable "nope"`

- **Onde pode**: `template-set`/`when`/`when-not` em statements;
  `tvar` em valores.
- **Onde é inválido**: nome indefinido; aridades erradas.
