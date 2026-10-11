# IMPLEMENTATION.md — Transpilador Gnumarus Lisp → GDScript (v1)

Documento de planejamento da etapa inicial. Todo o codigo mora em
`addons/0GnumarusLispToGdscriptTranspiler/`, os testes em
`addons/0GnumarusLispToGdscriptTranspiler/tests/` e este planejamento em `docs/`.

## 1. Objetivo da v1

Criar as classes capazes de fazer parsing e transpilacao (sem montar um addon
propriamente dito ainda), gerando a partir de texto Lisp o seguinte GDScript valido:

```gdscript
class_name MyClass
extends Node
var a
var b: int
# comentario1
var c: float = 0.0
func _ready(): # comentario2
	pass
```

O transpilador e **puramente sintatico**: nao valida semantica, nao assume nada
sobre runtime e nao interpreta codigo. Trabalha so com strings e listas,
aplicando transformacoes a partir de uma tabela de operacoes de nomes conhecidos.

## 2. Arquitetura (pipeline em 3 etapas + fachada)

```
texto .gdl ──▶ GnumarusLispToGdscriptTranspilerTokenizer ──▶ lista plana de tokens ──▶ GnumarusLispToGdscriptTranspilerParser
   ──▶ arvore aninhada (Strings e Arrays) ──▶ GnumarusLispToGdscriptTranspilerTranspiler ──▶ String GDScript
```

| Arquivo | Classe (`RefCounted`) | Responsabilidade |
|---|---|---|
| `GnumarusLispToGdscriptTranspilerTokenizer.gd` | `GnumarusLispToGdscriptTranspilerTokenizer` | Quebra o texto em lista plana de tokens (`(`, `)` e atomos String), respeitando os 4 delimitadores de string e escapes com backslash. |
| `GnumarusLispToGdscriptTranspilerParser.gd` | `GnumarusLispToGdscriptTranspilerParser` | Converte a lista plana em arvore aninhada de listas. Detecta parenteses desbalanceados e limita a profundidade. |
| `GnumarusLispToGdscriptTranspilerTranspiler.gd` | `GnumarusLispToGdscriptTranspilerTranspiler` | Percorre a arvore e emite GDScript via tabela de operacoes (`_operations`: nome → `Callable`). Controla indentacao com tabs. |
| `GnumarusLispToGdscriptTranspilerLisp.gd` | `GnumarusLispToGdscriptTranspilerLisp` | Fachada estatica: `transpile_text(text)` e `transpile_file(path)` encadeiam as 3 etapas e prefixam erros com a etapa que falhou. |

Retorno padrao de todas as etapas: `{"ok": bool, "error": String, ...}` mais
`"tokens"` (tokenizer), `"tree"` (parser) ou `"code"` (transpiler/fachada).
Sucesso = `ok == true` e `error == ""`. Falha nunca lanca excecao: retorna `ok == false`
com mensagem em portugues.

## 3. Regras do tokenizer (vindas do AGENTS.md)

- Whitespace separador: espaco, tab, LF, CR.
- `(` e `)` fora de trechos empacotados sao tokens estruturais.
- Atomos nao precisam de aspas, exceto se contiverem whitespace, parenteses,
  backslash ou delimitadores.
- Trechos empacotados: `"`, `'`, `` ` `` ou `´`; abre e fecha com o **mesmo**
  caractere (nao misturar). Conteudo empacotado e anexado ao atomo em curso
  (ex.: `` `OutraClasse` `` vira o atomo `OutraClasse`).
- `\` escapa o proximo caractere em qualquer posicao: `\"` vira `"`,
  `\\` vira `\`, `\(` vira `(` literal, etc.
- `""` (par vazio) gera um atomo vazio valido (ex.: `(comment "")`).
- Comentarios de linha: `;` e `#` fora de trechos empacotados descartam
  o resto da linha ate LF/CR, em qualquer ponto (inclusive no meio de
  um atomo, engolindo estrutura); escapar (`\;`, `\#`) ou empacotar
  (`"a;b"`) mantem o literal.
- Erros: string empacotada nao terminada, backslash solto no fim do texto.

## 4. Sintaxe Lisp da v1 (tabela de operacoes)

| Forma Lisp | Saida GDScript |
|---|---|
| `(class-name Nome)` | `class_name Nome` (so no topo) |
| `(extends Base)` | `extends Base` (so no topo) |
| `(var nome)` | `var nome` |
| `(var nome Tipo)` | `var nome: Tipo` |
| `(var nome = valor)` | `var nome = valor` |
| `(var nome := valor)` | `var nome := valor` (inferencia de tipo) |
| `(var nome Tipo = valor)` | `var nome: Tipo = valor` |
| `(comment texto...)` | `# texto...` (varios atomos sao unidos com espaco) |
| `(pass)` | `pass` |
| `(if cond corpo...)` | `if cond:` + corpo indentado |
| `(elif cond corpo...)` | `elif cond:` — so como trailing de `if`/`elif` |
| `(else corpo...)` | `else:` — so como trailing, por ultimo |
| `(while cond corpo...)` | `while cond:` + corpo indentado |
| `(for nome in iter corpo...)` | `for nome in iter:` + corpo indentado |
| `(for nome Tipo in iter corpo...)` | `for nome: Tipo in iter:` + corpo indentado |
| `(break)` / `(continue)` | `break` / `continue` |
| `(return)` / `(return valor)` | `return` / `return valor` (atomo ou `(lambda ...)`) |
| `(match subj ramos...)` | `match subj:` + ramos |
| `(branch padrao corpo...)` | `padrao:` + corpo indentado (so filho direto de `match`) |
| `(static-var ...)` | igual a `var`, com `static` (so no topo) |
| `(const nome = v)` / `(const nome := v)` / `(const nome T = v)` | `const ...` (qualquer nivel, inclusive funcs) |
| `(class Nome membros...)` | `class Nome:` + membros (topo e corpos de classe; `class-name` fora) |
| `(func nome (sig...) corpo...)` | `func nome(args...) [-> Ret]:` + corpo |
| `(static-func nome (sig...) corpo...)` | `static func ...` (mesma assinatura) |
| `(signal nome)` / `(signal nome (args...))` | `signal ...` (args sem retorno) |
| `(lambda (sig...) corpo...)` | `func(args...) [-> Ret]:` como valor |
| `(var ... (get corpo...) [(set (nome) corpo...)])` | `var ...:` + blocos (so membros) |
| `(call nome args...)` | `nome(a1, a2)` (statement e valor; aninha; alvo pode ser expressao invocada: `(call (call f x) 1)` vira `f(x)(1)`) |
| `(chain raiz elos...)` | `raiz.elo(...).prop` (elos `(nome args...)` ou atomos-propriedade; raiz aninha; statement, valor e operando) |
| `(+ a b ...)` `(- a b)` `(- x)` `(* ...)` `(/ ...)` `(% ...)` `(** ...)` | infixas n-arias/binarias + menos unario |
| `(== a b)` `(!= ...)` `(< ...)` `(> ...)` `(<= ...)` `(>= ...)` | comparacoes (statement e valor) |
| `(and a b ...)` `(or ...)` `(not x)` | logicos (statement e valor; `not` unario) |
| `(assign alvo op valor)` | `alvo OP valor`, OP em `= += -= *= /= %= <<= >>= &= \|= ^= **=` |
| `(array e...)` | `[e1, e2,]` multiline (ou `[]`) |
| `(dict-lua (c v)...)` | `{c = v,}` multiline (ou `{}`) |
| `(dict-json (c v)...)` | `{c: v,}` multiline (ou `{}`) |
| `(await x)` | `await x` (statement, valor e operando) |
| `(assert c)` / `(assert c msg)` | `assert(c[, m])` (so statement) |
| `(breakpoint)` | `breakpoint` sem parenteses (so statement) |
| `(enum ENTS...)` / `(enum (N) ENTS...)` | `enum [N] {...}` (topo e membros; entradas atomos, `(N)`, `(N V)`) |
| `(ternary c a b)` | `a if c else b` (statement, valor e operando) |
| `(include caminho)` | some: colado pelas formas de topo do arquivo (qualquer posicao) |
| `(block nome corpo...)` | declara/some: vira o corpo colado (pai sozinho ou apos override) |
| `(template-extends caminho)` | primeira forma do filho: herda e sobrescreve blocos do pai |
| `(defmacro nome (params...) corpo)` | define macro de forma unica (some; so no topo) |
| `(join a b...)` | concatena atomos (so em corpo de macro) |
| `(upper x)` / `(lower x)` / `(capitalize x)` | caixa do atomo (so em corpo de macro) |
| `(super)` | cola o default do bloco (so em override de filho) |
| `(for-generate (v fonte) corpo...)` | repete o corpo por valor: `(range a b [s])` ou lista |
| `(template-set nome valor)` | liga variavel de template (some; redefinivel) |
| `(tvar nome)` | cola o valor ligado |
| `(when nome corpo...)` / `(when-not ...)` | inclui o corpo se verdadeiro/falso |
| `@...` lider em `class-name/extends/var/static-var/func/static-func/class` | uma linha verbatim por anotacao |

Cadeia `if`/`elif`/`else`: formas `(elif ...)`/`(else ...)` no corpo do `if`
sao consumidas como cadeia plana no mesmo nivel (mesmo truque do comentario
trailing no `func`). Regras: ramo `if` precisa de ao menos uma forma antes
da cadeia; apos o primeiro link so links; no maximo um `else`, por ultimo;
corpos de `elif`/`else` nao tem sub-links (cadeia plana — aninhar com `(if ...)`
interno). `(elif ...)`/`(else ...)` fora de cadeia e erro. Condicoes e
iteraveis sao verbatim (empacotar quando necessario: `(if "x > 0" ...)`).

Ramos de `match`: todo filho direto de `(match ...)` precisa ser
`(branch padrao corpo...)`; qualquer outra forma e erro (o GDScript espera
padroes logo apos o cabecalho). Padroes sao atomos verbatim — empacotar
multiplos (`"1, 2"`), arrays (`"[var a, var b]"`), dicts (`"{\"key\": var n}"`) e usar
`"_"` nu para o curinga. Corpos de ramo nao tem sub-ramos (aninhar com
`(match ...)` interno). Nao validamos ordem do `_` nem guards (o GDScript
nao tem guards em `match`). Nota semantica do GDScript (o transpiler so
transcreve): identificadores nus em padroes comparam, nao ligam — binding
exige `var` explicito (`[var a, var b]`, `{"name": var n}`).

Condicoes (`if`/`elif`/`while`), sujeito de `match` e iteravel de `for`:
atomo verbatim ou expressao de linha unica (`(if (== x 1) ...)`,
`(for i in (call range 10) ...)`); sem parenteses extras, o `:` delimita;
lambdas ai dentro sao rejeitadas.

Posicionamento (contextos `"top"`, `"member"`, `"local"` no transpiler):
`class-name` so no topo; `extends`, `func`, `static-func`, `static-var`,
`signal` e `class` no topo e em corpos de classe (nunca em funcs — o GDScript
nao tem classes locais); o resto (`var`, `const`, `comment`, fluxo...)
vale em qualquer nivel. Heranca de classe interna via `(extends ...)` no
corpo (forma valida sondada no Godot 4.7.2, junto com aninhamento duplo).

Valores (`var`, `return`): atomo verbatim ou `(lambda (args...) corpo...)`,
que emite `func(args...):` + corpo indentado (vale em membro e em func;
`return` de lambda e valido; `const` com lambda e rejeitado pelo proprio
Godot, entao `const` so aceita atomos). `(lambda ...)` solto como forma e
erro.

Assinaturas (`func`, `static-func`, `lambda`, args de `signal`): retorno
primeiro, parametros depois. `()` nada; `(void)` retorna `void` sem args
(unica excecao); `(R (ARGS...))` retorna `R` com args agrupados;
qualquer outra forma e args planos sem retorno — atomo nu (inclui
`...rest` literal), `(n)`, `(n T)`, `(n = v)`, `(n := v)`, `(n T = v)`.
ATENCAO (aresta afiada): atomo nu seguido de lista abre posicao de retorno —
`(x (a int))` e `-> x`, nao dois args; para dois args escreva
`((x) (a int))`. Com retorno, args extras fora do grupo sao erro.

Acessores (`var`/`static-var`): `(get corpo...)` / `(set (nome) corpo...)`
trailing viram blocos (declaracao ganha `:`); no maximo um de cada, qualquer
ordem; so em membros (var local com acessor e invalido no GDScript).
Sondado no 4.7.2: `get` sem args e sem retorno, `set` com exatamente 1
parametro nu, `var` sem valor + getter ok, `static` + acessores ok.
Forma inline: acessor de atomo unico vira referencia na mesma linha
(`(var e = 1 (get get_e))` gera `var e = 1: get = get_e`); vale sozinho,
sem valor e em `static`. Misto inline+bloco na mesma declaracao e erro
(a gramatica GDScript nao tem forma mista).

Expressoes: `call` e infixas valem como statement e como valor (var,
return, args e operandos aninhados); operandos infixos aninhados ganham
parenteses sempre (correto por construcao: `(* (+ a b) c)` vira
`(a + b) * c`); `call` nunca precisa (ja parentetizado); lambdas nao
aninham em args/operandos de linha unica (ligar a `var` antes);
`assign` e so statement, alvo e atomo verbatim, valor na faixa total.

Anotacoes: atomos `@` lideres apos o operador, um por linha verbatim no
mesmo indent (com parametros empacota-se: `"@export_range(0, 100)"`);
valem em `class-name`, `extends`, `var`, `static-var`, `func`,
`static-func` e `class` — `signal`/`const`/`comment` ficam de fora
(`comment` mantem `@` como texto); `@` sozinho e erro, e nomes nao
podem comecar com `@`.

Colecoes: sempre multiline (virgula final, indent +1 por nivel), exceto
vazias (`[]`/`{}`); elementos, chaves e valores aceitam atomos e expressoes
aninhadas (inclusive colecao em colecao e colecao em arg de call —
sondado); lambdas dentro rejeitadas (ligar a `var` antes); chaves Lua saem
nuas, o que precisar de aspas usa `dict-json`.

Heads novos sem desenho: `is as in << >> & | ^` (infixas) e `~`
(unario sem espaco, como `-`). `await` compoe e parentetiza como infix
solto; `assert`/`breakpoint` sao so statement; `enum` com nome em
sublista-1 (`(enum (E) ...)`, anonimo sem ela) mora no topo e em membros;
`func @abstract` sem corpo emite declaracao sem `:` (e com corpo e erro,
como `@abstract` em `static`).

Includes (`GnumarusLispToGdscriptTranspilerIncludeResolver`, fase 2/meta-template): `(include
caminho)` em qualquer posicao e **substituido pelas formas de topo** do
arquivo (splice colado, nunca aninhado; vazio some; empacotado intocado;
formas `(include-only)` nuas sao descartadas no splice).
Caminhos: relativo ao arquivo que inclui, `res://`, `user://`, `/` de
sistema (`/c:` no Windows) e `~/` do lar atual (so proprio usuario:
`USERPROFILE` com fallback `HOME` no Windows, `HOME` no resto;
`~nome` e rejeitado; vazio em tudo e erro); texto puro + relativo e
erro (sem base). Flag opcional de rastreio `(include caminho true)`:
envolve as formas com `# BEGIN/END include <spec> (<resolvido)>`
(sempre emitidos, mesmo vazios; compostos por nivel).
Guardas: pilha canonica (`globalize_path` em `res://`) detecta ciclo e
mostra a cadeia; profundidade maxima 32 (default). Roda apos o parse e
antes do transpiler (e das futuras macros). Include em posicao esquisita
expande estruturalmente e pode falhar depois no transpiler com erro de
uso — aceito e documentado. Erros de transpiler em conteudo incluido
perdem o nome do arquivo (sem rastros de span, fora de escopo).

Heranca de templates (`GnumarusLispToGdscriptTranspilerTemplateResolver`, meta-template Jinja):
pai declara `(block NOME corpo...)` em qualquer posicao; filho com
`(template-extends CAMINHO)` como primeira forma do topo sobrescreve por
nome, colando o corpo do filho no lugar (nunca aninhado). Pai sozinho
continua valido (bloco vira o default colado, inclusive vazio que some).
Nomes planos (aninhados no mesmo namespace). Filho estrito: no topo so
extends + `block`; bloco desconhecido, duplicado ou extends fora da
primeira posicao e erro. Caminhos do pai: mesmas 5 formas do include,
relativo ao filho; includes resolvem por lado (pai com base do pai,
corpos do filho com base do filho) antes do merge; cadeias (pai com
extends) recursam; pilha canonica + limite 32. `(super)` sem args em corpo
de override cola o default (copia por ocorrencia; encadeia entre niveis);
`super` sem pai e erro.

Macros (`GnumarusLispToGdscriptTranspilerMacroExpander`, depois dos templates): `(defmacro NOME
(params...) CORPO-FORMA-UNICA)` no topo (some, nao gera codigo); chamadas
`(NOME args...)` viram o corpo com args crus substituidos (sem higiene;
arg com efeito avalia uma vez por copia). No maximo um `...rest` por
ultimo, respingado onde o atomo aparece. `(join ...)` em corpos concatena
atomos (nomes com ponto, literais com aspas); `(upper/lower/capitalize X)`
convertem caixa (estilo Jinja) pelo mesmo mecanismo. Macros usam macros por
ponto-fixo com profundidade; orcamento de 1024 expansoes e profundidade 64
(auto/mutua recursao = erro, sem estourar a pilha do GDScript). Aridade exata; nome duplicado/reservado e `defmacro`
fora do topo = erro. Multi-forma com splice e higiene ficam para depois.

Geracao (`for-generate (VAR FONTE) CORPO...`, no expansor): FONTE e
`(range A B [STEP])` (fim exclusivo, estilo Python; STEP explicito para
reverter) ou lista literal de valores; cada iteracao cola copias do corpo
com VAR ligado (atomo ou subarvore), que expandem depois (macros e
`for-generate` aninhados compoem; helpers colapsam por instancia).
Posicoes de statement/elemento apenas (slots de valor unico — defaults,
returns, args, operandos, condicoes — falham no expansor nomeando as duas
formas). Iteracoes dividem o orcamento de expansoes.

Variaveis de template (no expansor, ambiente plano unico): `(template-set
NOME VALOR)` expande o valor na hora e liga (some; redefine); `(tvar NOME)`
cola o no guardado; `(when NOME CORPO...)` cola o corpo se ligado e
verdadeiro (so `""` e `"false"` sao falsos), `(when-not ...)` inverte.
Avaliacao sequencial em ordem de encontro (sem escopo); nome indefinido
e erro, nunca silencio.

Regras do `var`:

- Forma posicional, sem marcador `:`: o 2o slot e tipo, `=` (sem tipo) ou
  `:=` (inferencia). O `=` antes do default e **obrigatorio**; sem ele
  (ex.: `(var a String 5)`) e erro.
- `(var nome Tipo := valor)` e invalido (o proprio GDScript rejeita dica de
  tipo combinada com inferencia).
- **Emissao verbatim**: o conteudo do atomo sai como fonte GDScript exatamente
  como escrito (apos o unescape do Lisp); o transpiler nunca poe aspas
  sozinho. Um literal string GDScript exige "empacotamento duplo": empacotar
  no Lisp E escrever as aspas do GDScript por dentro, ex.
  `(var a String = "\"oi\"")` gera `var a: String = "oi"`. O mesmo alçapao
  cobre qualquer literal nao-expressavel como atomos nus, ex.
  `(var v Vector2 = "Vector2(1, 2)")` gera `var v: Vector2 = Vector2(1, 2)`.
- Preco do alçapao: escada de escapes — `\` do GDScript precisa ser `\\` no
  Lisp. Trocar o delimitador externo (ex.: `'"oi"'` em vez de `"\"oi\""`)
  elimina os escapes de aspas, mas nao os de backslash.

Detalhes de `func`:

- `()` e a lista vazia de argumentos (ex.: `(func _ready () ...)`).
- Se o **primeiro** elemento do corpo for `(comment ...)` com texto, ele vira
  comentario trailing na linha de declaracao (`func _ready(): # comentario2`)
  em vez de linha propria. Isso produz o exemplo pedido sem sintaxe extra.
- Corpo vazio e erro (GDScript exige bloco indentado; nada e inventado
  silenciosamente).
- `class-name`, `extends` e `func` so valem no nivel de topo; `var`,
  `comment` e `pass` valem em qualquer nivel.

Entrada Lisp que gera o exemplo pedido (`tests/Test1.gdl`):

```lisp
(class-name MyClass)
(extends Node)
(var a)
(var b int)
(comment "comentario1")
(var c float = 0.0)
(func _ready () (comment "comentario2") (pass))
```

## 5. Testes

- `tests/Test1.gdl` → `tests/Test1.gd`: o exemplo pedido, byte a byte
  (inclui tab antes de `pass` e `\n` final).
- `tests/Test2.gdl` → `tests/Test2.gd`: delimitadores alternativos
  (`` ` ``, `'`), escapes (`\"`), comentarios com espacos, `:=`, string
  duplamente empacotada, alçapao verbatim (`Vector2`) e func com argumento.
- `tests/TestRunner.gd` (`extends SceneTree`): roda sem editor via
  `--headless --script`, cobre tokenizer (basico, 4 delimitadores, escapes,
  erros), parser (aninhamento, erros) e ponta a ponta (texto e arquivo).
  Sai com codigo 0 em sucesso, 1 em falha.
- `tests/Test3.gdl` → `tests/Test3.gd`: cadeia `if`/`elif`/`else`, `for`
  com `break`/`continue`, `while`, `return` com e sem valor e `if` aninhado.
- `tests/Test4.gdl` → `tests/Test4.gd`: `match` com padroes literal,
  multiplo, array e curinga, mais `match` aninhado.
- `tests/Test5.gdl` → `tests/Test5.gd`: classe interna com `extends` no
  corpo, signal/var/const/static, func interna e aninhamento duplo.
- `tests/Test6.gdl` → `tests/Test6.gd`: lambdas como default de `var`
  (membro e local) e como valor de `return`, com comentario trailing.
- `tests/StressTest.gdl` → `tests/StressTest.gd`: cobertura viva de todas
  as capacidades (todas as formas de `var`/`const`, signals, funcs, classe
  interna, fluxo, `match`, lambdas, 4 delimitadores, escapes, alçapao
  verbatim). Cresce a cada feature nova.
- `tests/includes/`: fixtures `main.gdl` → `main.gd` (splice, aninhado,
  relativo com `..`), `diamond_top.gdl` → `.gd` (diamante legal, colado 2x),
  ciclo A↔B, auto-include, ausente, cadeia d1→d2→d3 para o limite.
- `tests/templates/`: `parent.gdl` → `.gd` (defaults sozinho), `child.gdl`
  → `.gd` (override total), `nested/child.gdl` → `.gd` (pai com `..`,
  bloco dentro de `func`), erros (desconhecido, duplicado, extra, nao-primeiro,
  ciclo, ausente).
- `tests/macros/macros.gdl` → `.gd`: `safe-call` + `unless` ponta a ponta
  (join, rest, macro como valor/statement).
- Validação extra: `--check-only --script` nos `.gd` esperados prova que a
  saida e GDScript parseavel pelo Godot 4.7.2.

## 6. Limitacoes conhecidas da v1 (proposital, incremental)

- Sem `include` de outros arquivos (fase 2).
- Sem definicao/expansao de macros e sem guardas de recursao (fase 3).
- Sem literais string "magicos" na saida: o transpiler nunca adiciona aspas;
  quem escreve o default empacota duplamente (ver regra verbatim acima).
- Sem argumentos tipados em `func`, sem anotacoes.

## 7. Proximas fases (fora do escopo da v1)

1. **Includes**: `(include caminho)` com resolucao relativo-ao-arquivo-atual,
   `res://` absoluto de projeto e `/` absoluto de sistema (`/c:` no Windows).
2. **Macros**: `(defmacro ...)` + expansao iterativa ate forma sem macros,
   com limite maximo de desdobramentos e deteccao de recursao mutua.
3. **Mais operacoes**: literais, `if`, `for`, `while`, `return`, chamadas,
   argumentos tipados, trailing comments genericos.

## 9. Addon de editor (v3.2: watcher sidecar; v3.1 import plugin removido)

O import plugin (v3.1) era a ferramenta errada: o destino do `_import` e
sempre `.godot/imported`, e o `type="Script"` fazia o editor abrir `.gdl`
como GDScript (cores + falsos erros). Trocado por observador: o impl do
plugin conecta `filesystem_changed` e oferece item manual no menu Project,
transpilando cada `.gdl` para um irmao `.gd` ao lado da fonte. So
transpila com hash de conteudo novo (sem relogio: imune a granularidade
de `mtime`); so reescreve com conteudo diferente; apos escrever empurra
cada irmao via `update_file` (sincrono, novos e alterados — scan puro
cega no mesmo segundo: `st_mtime` tem precisao de segundos e diretorios
com mtime igual sao pulados) com scan diferido de rede para pastas
desconhecidas; carimba
`GENERATED ... DO NOT EDIT`; fontes marcadas `(include-only)` nao geram
irmao (pre-checagem por parse, silenciosa, com carimbo proprio; irmao
antigo vira orfao mantido); editores abertos re-checam via
`reload_open_files()` (mudo com auto-reload, dialogo sem); falha com `push_error` e so retenta se a
fonte mudar; fonte deletada deixa o orfao. Edicao em include/pai nao retriggera dependentes
(item manual força tudo). Ao ativar, adiciona `gdl` em
`docks/filesystem/textfile_extensions` (persiste no exit): `.gdl` abre
como texto puro — sem parsing GDScript. Nao ligado no `project.godot`
deste repo (fixtures de erro dariam spam a cada scan). O coletor nunca
desce em `addons/0GnumarusLispToGdscriptTranspiler/tests` (nem forcado):
os `.gd` ali sao saidas esperadas dos testes, nao artefatos de build —
salvar um `.gdl` com o plugin ativo nao os carimba mais.

Highlighter (v3.4): `GnumarusLispToGdscriptTranspilerGdlTheme` (`RefCounted` puro, so dados)
congela as listas e cores padrao do GDScript 4.7.2 (keywords separadas em
`keyword`/`control_flow`, tipos base, `get`/`set` com cor de funcao, funcoes
globais, anotacoes; vermelho de erro constante, sem chave de tema).
`GnumarusLispToGdscriptTranspilerGdlColorizer` classifica cada atomo sem contexto pela mesma cor do
GDScript (`category_for_atom`/`color_for_atom` publicos e testaveis;
`configure` injeta cores e `theme_hash` distingue troca de tema de edicao
de texto); tipos da engine via `ClassDB` ao vivo, ops so-Gnumarus caem no
keyword pela tabela viva, rainbow de parenteses e indent mantidos.
`GnumarusLispToGdscriptTranspilerGdlHighlighterImpl` (`RefCounted`, dono do colorizer + memo por
hash de texto + hash de tema) sincroniza de `EditorSettings`
(`sync_theme`, no-op headless; reinscreve em `settings_changed`) e
`GnumarusLispToGdscriptTranspilerGdlHighlighter` e proxy burro (excecao documentada: `_create`
precisa retornar `EditorSyntaxHighlighter`, o que o `RefCounted` nao pode
construir). Vao entre atomos usa o cinza `text` (`text_color`), entao
nenhuma cor vaza para a direita; atomos com `-` interior fatiam por
segmento (`static-var` pinta `static`, o separador e `var`; `-` inicial
nunca fatia, `-5` segue numero). Mapas saem com chaves em ordem ascendente
de coluna: o loop de desenho do `TextEdit` percorre as entradas em ordem
de insercao e para na primeira chave maior (v3.7; sem isso os vaos
preenchidos por ultimo vazavam na tela mesmo com o mapa correto).
Operacoes so-Gnumarus (`call`, `defmacro`, `join`, `lambda`...) levam um
lima inventado (`gnumarus`, sem chave no editor); palavras do GDScript
seguem fieis, e segmentos de hifen classificam sozinhos (`static-var`
segue vermelho/vermelho, `template-set` sai texto/azul de funcao).

## 8. Alternativas consideradas

- **Comentario trailing via keyword** (`(func _ready () :comment "x" ...)`):
  descartado por adicionar sintaxe; reaproveitar `(comment ...)` em primeira
  posicao e mais lispy e nao cria operacao nova.
- **`pass` automatico em func vazia**: descartado; erro explicito evita
  inventar corpo silenciosamente (transpilador nao assume semantica).
- **Aspas de string via `(str ...)`**: descartado em favor do empacotamento
  duplo (regra verbatim) — menos operacoes, nenhuma magica, generaliza para
  qualquer literal/expressao e nao exige mudanca no tokenizer.
- **Inferencia de tipo pelo nome do tipo**: descartada — conhecimento
  semantico entrando pela porta dos fundos; quebra em `StringName` (`&"..."`),
  tipos customizados e defaults nao-tipados.
- **`=` opcional ou so como placeholder**: descartado; `=` sempre obrigatorio
  antes do default da forma canonica unica e parsing trivial.
- **Tokens como Dicionarios tipados**: descartado na v1; `String` para atomos
  e `"("/ ")"` estruturais e suficiente e mais testavel (comparacao direta).
- **Indentacao com espacos**: descartado; Godot usa tab por padrao.
