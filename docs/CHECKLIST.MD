# CHECKLIST.MD — Passos de desenvolvimento (v1 + futuro)

Legenda: `[x]` feito, `[ ]` pendente/futuro.

## Etapa v1 — Nucleo sintatico (escopo atual)

- [x] 1. Pesquisa: confirmar binario do Godot (`/sync/opt/godot/godot4.x86_64`, versao 4.7.2) e estrutura do projeto.
- [x] 2. Planejamento: escrever `docs/IMPLEMENTATION.md` (arquitetura, sintaxe, fases) e este `docs/CHECKLIST.MD`.
- [x] 3. Estrutura inicial: criar `addons/0GnumarusLispToGdscriptTranspiler/` e `tests/`.
- [x] 4. Codigo core — `GnumarusLispToGdscriptTranspilerTokenizer.gd` (`RefCounted`, 4 delimitadores, escapes com backslash, erros em portugues).
- [x] 5. Codigo core — `GnumarusLispToGdscriptTranspilerParser.gd` (lista plana → arvore aninhada, parenteses balanceados, limite de profundidade).
- [x] 6. Codigo core — `GnumarusLispToGdscriptTranspilerTranspiler.gd` (tabela `_operations`, ops `class-name/extends/var/comment/func/pass`, indentacao com tab, trailing comment de `func`).
- [x] 7. Codigo core — `GnumarusLispToGdscriptTranspilerLisp.gd` (fachada `transpile_text` / `transpile_file`).
- [x] 8. Testes — fixtures `tests/Test1.gdl` → `tests/Test1.gd` (exemplo pedido, byte a byte).
- [x] 9. Testes — fixtures `tests/Test2.gdl` → `tests/Test2.gd` (delimitadores alternativos, escapes, espacos).
- [x] 10. Testes — `tests/TestRunner.gd` (tokenizer, parser, ponta a ponta, erros; saida 0/1).
- [x] 11. Validacao — importar o projeto headless, rodar o TestRunner e checar `--check-only` nos `.gd` gerados/esperados.
- [x] 12. Documentacao — comentarios `##`/`#` em toda classe, funcao e variavel.

## Revisao v3.14 — comentarios de linha `;`/`#`

- [x] 142. Tokenizer descarta `;`/`#` ate LF/CR em qualquer ponto fora de empacotados (inclusive mid-atomo); `\;`/`\#` e empacotados preservam; colorizador pinta com a cor `comment`.
- [x] 143. Bateria `_test_line_comments` (tokens, escapes, packed, EOF, CR, trailing, transpile vazio, cores); TestRunner 815/815 + `--check-only`.

## Revisao v3.13 — `chain` + alvos-call aninhados

- [x] 140. Nova operacao `chain` (`(chain raiz elos...)`, elos-metodo e elos-propriedade com atomo nu, raiz aninhavel; statement, valor e operando) + alvos `call` como expressoes (invocacao do retorno); raiz/elos no `_is_value_slot`.
- [x] 141. Bateria `_test_chain` + exemplo no `StressTest` (byte a byte); 73 operacoes; OPERATIONS.md + tabela do IMPLEMENTATION.md; TestRunner 803/803 + `--check-only`.

## Revisao v3.12 — erro claro em slots de valor unico

- [x] 138. Guarda no expansor (`_is_value_slot` + dono): `for-generate`/`when`/`template-set` em defaults, returns, args, operandos e condicoes falham nomeando as duas formas (antes vazava erro confuso do transpiler, ex. "misplaced '='" no `var`).
- [x] 139. Checks de mensagem em 6 slots + positivo em elementos de array; OPERATIONS cita a nova mensagem; TestRunner 765/765 + `--check-only`.

## Revisao v3.11 — OPERATIONS.md (referencia das 72 operacoes)

- [x] 136. `OPERATIONS.md` no addon (nome, descricao, contextos validos/invalidos, exemplos executados no transpilador + fixtures byte a byte); cobertura 72/72 verificada por script.
- [x] 137. Sonda temporaria removida; nenhum codigo alterado (suite segue 753/753).

## Revisao v3.10 — prefixo das classes (GnumarusLispToGdscriptTranspiler*)

- [x] 134. 13 arquivos + `.uid` renomeados; 94 trocas de identificadores (`class_name`, preloads, `plugin.cfg`, refs em comentarios/docs); prosa, carimbo `GNUMARUS`, menu e nome do dropdown intactos.
- [x] 135. 2 comentarios obsoletos ("keyword fallback") corrigidos; cache global reconstruido (check-only do proxy); TestRunner 753/753 + `--check-only` em tudo + zero carimbos.

## Revisao v3.9 — rename do diretorio (0Gnumarus...)

- [x] 132. Diretorio renomeado para `0GnumarusLispToGdscriptTranspiler` (ordenacao no dock); `plugin.cfg` intacto (caminho relativo); `project.godot` ja estava sem a entrada do plugin.
- [x] 133. Troca mecanica do prefixo em 10 `.gd` + 2 docs (sem `class_name` afetado); TestRunner 753/753 no novo caminho + `--check-only` + zero carimbos.

## Revisao v3.8 — matiz proprio das operacoes Gnumarus

- [x] 130. Categoria `gnumarus` (lima inventado, configuravel, sem chave no editor): ops so-Gnumarus distinguiveis a olho; palavras GDScript intactas, segmentos de hifen independentes.
- [x] 131. `CATEGORIES` no tema (validacao do `configure` + `theme_hash`); versao do dropdown em 3.8; TestRunner 753/753 + `--check-only`.

## Revisao v3.7 — ordem das entradas (contrato do TextEdit)

- [x] 128. Mapas com chaves ascendentes: o desenho percorre em ordem de insercao e para na primeira chave maior — vaos anexados por ultimo vazavam na tela com o mapa "correto" (causa dos vazamentos pos-v3.6).
- [x] 129. `_engine_color` no runner replica o loop do motor (controle negativo executado: 3 falhas sem o fix); diagnostico temporario via arquivo usado e removido; TestRunner 746/746 + `--check-only`.

## Revisao v3.6 — sem vazamento + hifen fatiado

- [x] 124. Categoria `text` (`text_color`) + preenchimento dos vaos em `compute_all`: nenhuma cor vaza para a direita.
- [x] 125. `_paint_hyphenated` (so `-` interior; `-5` intacto; `=` e nomes no cinza texto, sem tocar em `.`/`/`).
- [x] 126. Checks de vao, fatiamento (`static-var`, `class-name`, `when-not`) e negativo; TestRunner 738/738 + `--check-only`.
- [x] 127. Nome do highlighter versionado (`Gnumarus 3.6`, via `HIGHLIGHTER_VERSION`) para o dropdown do editor dizer qual regra esta ativa.

## Revisao v3.5 — watcher ignora fixtures do addon

- [x] 122. `ADDON_TESTS_ROOT` + poda em `_collect_gdl_in`: salvar `.gdl` com o plugin ativo nao reescreve (nem carimba) os `.gd` esperados dos testes.
- [x] 123. Regressao em `_test_watcher` (`collect_gdl` vazio + `transpile_sidecars` forcado sem tocar nada); TestRunner 721/721 + `--check-only`.

## Revisao v3.4 — highlighter com as cores do GDScript

- [x] 117. `GnumarusLispToGdscriptTranspilerGdlTheme` (listas e cores padrao do GDScript 4.7.2: keyword/controle separados, base, get/set, globais, anotacoes).
- [x] 118. `GnumarusLispToGdscriptTranspilerGdlColorizer` com `category_for_atom`/`color_for_atom`/`configure`/`theme_hash`; engine via `ClassDB`, fallback keyword pela tabela viva, rainbow mantido.
- [x] 119. `GnumarusLispToGdscriptTranspilerGdlHighlighterImpl` (memo texto+tema, `sync_theme` de `EditorSettings`, no-op headless) + `GnumarusLispToGdscriptTranspilerGdlHighlighter` como proxy burro (excecao `_create` documentada).
- [x] 120. Bateria `_test_highlighter` ampliada (categorias, defaults byte a byte, injecao via `configure`, impl com proxy nulo); 24 fixtures restaurados (linha de carimbo removida) apos contaminacao por watcher.
- [x] 121. Revalidar: TestRunner 719/719 + `--check-only` nos `.gd` tocados.

## Revisao v3.3 — highlighter rainbow `.gdl`

- [x] 113. `GnumarusLispToGdscriptTranspilerGdlColorizer` (scanner posicional: rainbow por profundidade, `)` solto em vermelho, indent por largura, strings/keywords/`@`/numeros; keywords da tabela viva).
- [x] 114. `GnumarusLispToGdscriptTranspilerGdlHighlighter` (`EditorSyntaxHighlighter`, auto-select por `gdl`, memo por hash) + registro no plugin (reabrir arquivos antigos).
- [x] 115. Bateria `_test_highlighter` (profundidades, carry entre linhas, escapes, erros); indent visivel com View Whitespace.
- [x] 116. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` (inclui colorizer/highlighter).

## Revisao v3.2 — watcher sidecar (troca o import plugin)

- [x] 108. Remover `GnumarusLispToGdscriptTranspilerGdlImport*` (import plugin era a ferramenta errada: destino sempre `.godot/imported`).
- [x] 109. `GnumarusLispToGdscriptTranspilerLispPluginImpl` observador: `filesystem_changed` + item manual, `transpile_sidecars` (hash de conteudo, so reescreve se mudou, `GENERATED`, orfao fica, anti-spam de falha, `force` p/ transitivo).
- [x] 110. Auto-add de `gdl` em `textfile_extensions` ao ativar (persiste no exit; `.gdl` abre como texto, sem parsing GDScript).
- [x] 111. Bateria `_test_watcher` (round-trip, quietude, reedicao, falha, orfao, raiz ausente); sem ligar no `project.godot` (fixtures quebrados).
- [x] 112. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` (inclui plugin/impl).

## Revisao v3.1 — EditorImportPlugin `.gdl` (addon de verdade)

- [x] 104. Regra nova do AGENTS.md: proxies burros (`GnumarusLispToGdscriptTranspilerGdlImport`, `GnumarusLispToGdscriptTranspilerLispPlugin`) + impls `RefCounted` (`GnumarusLispToGdscriptTranspilerGdlImportImpl`, `GnumarusLispToGdscriptTranspilerLispPluginImpl`) + `plugin.cfg`.
- [x] 105. Importer `gnumarus.gdl`: extensao `gdl`, saida `gd`, tipo `Script`, 1 preset; `_import` transpila e escreve (OK / ERR_FILE_NOT_FOUND / ERR_PARSE_ERROR / ERR_CANT_CREATE).
- [x] 106. Bateria `_test_import_plugin` (metadados via proxy, round-trip em `./tmp`, falhas, wiring do plugin); sem ligar no `project.godot` (fixtures quebrados de proposito poluiriam o import).
- [x] 107. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` (inclui proxies/impls) + ativacao temporaria provando o `plugin.cfg`.

## Revisao v2.6 — `template-set`/`tvar`/`when`

- [x] 101. Env plano no expansor (set expande e liga, tvar cola, when/when-not sequenciais, so `""`/`"false"` falsos).
- [x] 102. Bateria `_test_set_when` + `debug_dump` no `StressTest`; dangling (72 operacoes).
- [x] 103. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v2.5 — `for-generate` (iteracao de template)

- [x] 97. `_expand_generate` + `_generate_values` no expansor (range/lista, splice, composicao com macros, orcamento compartilhado).
- [x] 98. Helpers colapsam por instancia gerada; dangling (68 operacoes).
- [x] 99. Bateria `_test_generate` + slots no `StressTest`.
- [x] 100. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v2.4 — `super()` + filtros de atomo

- [x] 93. `(super)` sem args em override cola o default (`_fill_super`; sem pai = dangling).
- [x] 94. `(upper/lower/capitalize X)` no `_collapse_helpers` (so corpos; fora = dangling); 67 operacoes.
- [x] 95. Fixtures `super_child` + erros + bateria + `flag` no `StressTest`.
- [x] 96. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v2.3 — macros `(defmacro ...)` + `join` + `...rest`

- [x] 89. Nova classe `GnumarusLispToGdscriptTranspilerMacroExpander` (substituicao crua, rest por ultimo, join em corpos, ponto-fixo com orcamento 1024).
- [x] 90. Fiacao na fachada (macro apos template, antes do transpiler) + guards dangling (63 operacoes).
- [x] 91. Fixture `tests/macros/` + bateria `_test_macros` + `safe-call` no `StressTest`.
- [x] 92. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v2.2 — heranca de templates `(block ...)` (meta-template Jinja)

- [x] 85. Nova classe `GnumarusLispToGdscriptTranspilerTemplateResolver` (override por splice, filho estrito, nomes planos, includes por lado, cadeia + pilha + limite 32).
- [x] 86. Fiacao na fachada (template apos parse, antes do transpiler) + guards dangling (61 operacoes).
- [x] 87. Fixtures `tests/templates/` + bateria `_test_templates` no runner.
- [x] 88. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v2.1 — includes `(include ...)` (meta-template, fase 2)

- [x] 81. Nova classe `GnumarusLispToGdscriptTranspilerIncludeResolver` (splice recursivo, 4 formas de caminho, pilha canonica + limite 32).
- [x] 82. Fiacao na fachada (pipeline tokenizer→parser→includes→transpiler) + guarda dangling no transpiler (59 operacoes).
- [x] 83. Fixtures `tests/includes/` + bateria `_test_includes` no runner.
- [x] 84. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.17 — condicoes/iteraveis estruturados

- [x] 77. Auditoria: `if`/`elif`/`while`/`match`/`for` aceitavam so atomos.
- [x] 78. Condicoes/sujeito/iteravel via `_emit_operand` (atomos ou expressoes, sem parens, sem lambda).
- [x] 79. Casos no `TestRunner.gd` + `find_first` no `StressTest`; sem novas operacoes.
- [x] 80. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.16 — resto da sintaxe (is/as/in, shifts, `await`, `enum`...)

- [x] 73. Sondar + ler engine: todos os heads validos; `@abstract` existe (func sem corpo e sem `:`).
- [x] 74. Heads em INFIX_OPS + `~` unario; `await`/`assert`/`breakpoint`/`enum`/`ternary`; regra `@abstract` (49 operacoes).
- [x] 75. Bateria `_test_small_forms` + exemplos no `StressTest`; blindagem `Array == String` em `_is_lambda`.
- [x] 76. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.15 — anotacoes `@`

- [x] 69. Sondar: stack uma-por-linha ok; `@tool` antes de `extends` ok.
- [x] 70. `_split_annotations`/`_prefix_annotations` em class-name/extends/var/func/class; `@` sozinho e nomes com `@` viram erro.
- [x] 71. Bateria `_test_annotations` + exemplos no `StressTest` (@tool, export_range, rpc); sem novas operacoes.
- [x] 72. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.14 — menos unario `(- x)`

- [x] 66. `_emit_infix_code`: `-` com 1 operando vira unario (regra de aridade, como `not`).
- [x] 67. Casos no `TestRunner.gd` + funcs no `StressTest` (negate, neg_sum, sem novas operacoes).
- [x] 68. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.13 — literais `array`/`dict-lua`/`dict-json`

- [x] 62. Sondar: multiline com trailing comma, aninhados e colecao em arg de call, tudo ok.
- [x] 63. `_is_collection`/`_emit_collection_code`/`_emit_array_code`/`_emit_dict_code`; colecoes em valores, args, operandos e elementos.
- [x] 64. Bateria `_test_collections` + exemplos no `StressTest`; 44 operacoes.
- [x] 65. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.12 — `call`, aritmetica/logica e `assign`

- [x] 58. Sondar: expressao solta como statement ok; lambda em atribuicao ok; todos os compostos (`<<=`, `**=`, ...) ok.
- [x] 59. `_emit_call_code`/`_emit_infix_code`/`_emit_operand` (parenteses por construcao) + `_emit_assign`; valores aceitam expressoes.
- [x] 60. Bateria `_test_expressions` + exemplos no `StressTest` (bump, compute, pick); 41 operacoes.
- [x] 61. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.11 — acessores inline (`get = f`)

- [x] 54. Sondar: inline mesma-linha ok (sozinho, sem valor, `static`); bloco com `get = f` invalido; misto impossivel.
- [x] 55. `_accessor_inline_ref`: tudo-inline vira linha unica, qualquer bloco exige tudo-bloco, misto e erro.
- [x] 56. Casos no `TestRunner.gd` + exemplo no `StressTest` (app_name/get_app_name).
- [x] 57. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.10 — getters/setters `(get ...)`/`(set ...)`

- [x] 50. Sondar no 4.7.2: bloco ok; `get() -> T` invalido; `set` tipado invalido; `var` sem valor + getter ok; `static` + acessores ok; local + acessor invalido; inline existe (follow-up).
- [x] 51. Split declaracao/acessores em `_emit_variable` + `_emit_accessor`; `get`/`set` soltos viram erro; 24 operacoes.
- [x] 52. Bateria `_test_accessors` + exemplo no `StressTest` (backing `_health`).
- [x] 53. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.9 — assinaturas: retorno primeiro + args tipados

- [x] 46. Sondar: lambda com `->` ok, `:=` em params ok (binario 4.7.2).
- [x] 47. Helpers `_parse_arg`/`_parse_signature`; `func`/`static-func`/`lambda` com retorno, `signal` com args tipados (sem retorno).
- [x] 48. Bateria `_test_signatures` + exemplos no `StressTest` (convert, typed_id, sum_all, tagged).
- [x] 49. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.8 — `StressTest.gdl` vivo

- [x] 44. Criar `tests/StressTest.gdl` → `tests/StressTest.gd` cobrindo todas as capacidades; entrar no runner.
- [x] 45. Revalidar: TestRunner 0 falhas + `--check-only` (inclui StressTest).

## Revisao v1.7 — lambdas `(lambda ...)` como valores

- [x] 40. Sondar no binario 4.7.2: lambda multilinha como valor/retorno ok; em `const` o Godot rejeita.
- [x] 41. Helpers `_emit_value`/`_emit_lambda_value`/`_take_trailing_comment`; `var`/`return` aceitam lambda, `const` segue so-atomos.
- [x] 42. Fixture `Test6.gdl` → `Test6.gd` + casos no `TestRunner.gd` (22 operacoes).
- [x] 43. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.6 — classes aninhadas (`class`)

- [x] 36. Sondar no binario 4.7.2: `class X extends Y:` ok, `extends` no corpo ok, aninhamento duplo ok, classe local em func invalida.
- [x] 37. Refactor de contexto (`"top"`/`"member"`/`"local"`): `class` no topo e em corpos; `func`/`static`/signal/`extends` liberados em corpos; `class-name` so no topo.
- [x] 38. Fixture `Test5.gdl` → `Test5.gd` + casos no `TestRunner.gd` (21 operacoes).
- [x] 39. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.5 — `static var`, `static func`, `signal` e `const`

- [x] 32. Sondar no binario 4.7.2: `static var` com `:=` ok, `const` tipado ok, `const` com `:=` ok, `const` tipo+`:=` invalido.
- [x] 33. Refactors `_emit_variable` (`var`/`static-var`) e `_emit_function` (`func`/`static-func`); novos `_emit_signal` e `_emit_const` (20 operacoes).
- [x] 34. Fixture `Test2` (signals, static-var, const classe + const local, static-func) + casos no `TestRunner.gd`.
- [x] 35. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.4 — `match` com `branch`

- [x] 29. Operacoes `match`/`branch`: filhos diretos validados, padroes verbatim, corpos sem sub-ramos.
- [x] 30. Fixture `Test4.gdl` → `Test4.gd` + casos positivos/negativos no `TestRunner.gd`.
- [x] 31. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.3 — vars de loop tipadas

- [x] 25. Verificar no Godot 4.7.2 que `for x: int in ...` e GDScript valido (`--check-only` em probe).
- [x] 26. `_emit_for`: forma `(for nome Tipo in iter corpo...)`; `in` como nome e erro.
- [x] 27. Fixture `Test3` (func `first_int`) + casos positivos/negativos no `TestRunner.gd`.
- [x] 28. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.2 — controles de fluxo (exceto `match`)

- [x] 22. Novas operacoes: `if`/`elif`/`else` (cadeia plana via trailing), `while`, `for` (marcador `in`), `break`, `continue`, `return`.
- [x] 23. Fixture `Test3.gdl` → `Test3.gd` + casos positivos/negativos no `TestRunner.gd`.
- [x] 24. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Revisao v1.1 — sintaxe posicional do `var` + `:=` + regra verbatim

- [x] 18. Reescrever `_emit_var`: 5 formas posicionais, `=` obrigatorio, `:=` sem tipo, verbatim sem aspas magicas.
- [x] 19. Atualizar fixtures `Test1.gdl`/`Test2.gdl` (+ `Test2.gd`) e casos do `TestRunner.gd` (formas validas e invalidas).
- [x] 20. Traduzir codigo e comentarios para ingles (AGENTS.md); docs de planejamento seguem em portugues.
- [x] 21. Revalidar: TestRunner 0 falhas + `--check-only` nos `.gd` esperados.

## Futuro (fora da v1, ordem sugerida)

- [ ] 13. Interface de addon propriamente dita (plugin Godot, dock/editor import).
- [ ] 14. `include` de arquivos (relativo, `res://`, `/` sistema, prefixo `/c:` no Windows).
- [ ] 15. `defmacro` + expansao iterativa (macros dentro de macros) ate forma final sem macros.
- [ ] 16. Guardas anti-recursao: limite maximo de desdobramentos + deteccao de macros mutuamente recursivas.
- [ ] 17. Novas operacoes GDScript (literais string, `if/for/while`, chamadas, args tipados) + testes e docs.
