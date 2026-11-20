# Enthroned OS — Lote 9.2: correções dos bloqueadores da Homologação 4

Data: **2026-11-18** (America/Sao_Paulo). Entrada: `docs/validation/PREBUILD-H4-STABILITY-GATE.md` (decisão **NO-GO**).
Escopo: correção dos achados H4-001 a H4-011 e contenção do risco NP-01, com regressões mínimas. Sem novas funcionalidades, sem redesign, sem build de imagem, sem commit.

## 1. Resumo do estado final

| Achado | Estado da correção | Teste de regressão | Resultado local | Depende da build/VM |
| --- | --- | --- | --- | --- |
| H4-001 (P1, build) | **Corrigido** | `settings/tests/native-smoke.cpp` (matriz de preflight) + espelho `scripts/test-update-engine.mjs` | Espelho PASS (7 casos) | native-smoke: NOT RUN (requer Qt) |
| H4-002 (P0) | **Corrigido** (QML + helper) | `scripts/test-launcher-appactions.mjs` + caso 9.7 de `scripts/test-desktop-helpers.sh` | PASS (26 IDs malformados + fronteira shell) | Carregamento QML real na VM |
| H4-003 (P1) | **Corrigido** | `scripts/test-launcher-filter.mjs` (executa o callback real do QML) | PASS (12 cenários, incl. reprodução da auditoria) | Sequência visual no Plasma |
| H4-004 (P1) | **Corrigido** (guarda da UI) | Espelho `scripts/test-update-engine.mjs` (regra do uupd) | PASS (5 casos) | D-Bus/duas instâncias na VM |
| H4-005 (P1) | **Corrigido** | `settings/tests/flatpak-lifecycle-smoke.cpp` (novo, CTest) | NOT RUN (requer Qt) | CTest na build |
| H4-006 (P1) | **Corrigido** | Revisão dirigida + decisões espelhadas | Espelhos PASS | Fluxo real na VM (doubles) |
| H4-007 (P1) | **Corrigido** | Matriz de resultado em native-smoke + espelho | Espelho PASS (12 casos) | native-smoke + VM |
| H4-008 (P1) | **Corrigido** | `scripts/test-desktop-helpers.sh` (casos 8.1–8.6) | PASS (10 casos) | Dois logins reais na VM |
| H4-009 (P2) | **Corrigido** | `scripts/test-desktop-helpers.sh` (casos 9.1–9.5) | PASS | Desktop desativado real na VM |
| H4-010 (P2) | **Corrigido** | `systemd-analyze verify` + tratamento 77 no engine | Espelho PASS; unidade parseada | Semantics de exit 77 na VM |
| H4-011 (P2) | **Corrigido** | `scripts/test-launcher-appactions.mjs` (ciclo connect/consume) | PASS | Popup real na VM |
| NP-01 (NÃO COMPROVADO) | **Contido** (limite finito) | `systemd-analyze verify`; sem medição | Unidade parseada | Medição obrigatória na VM (§5) |

Verificações executadas nesta rodada (todas com exit 0 salvo indicação):

- `node settings/tests/run-tests.mjs` → **444 pass / 0 fail** (re-executado após todas as edições).
- `node welcome/tests/run-tests.mjs` → **85 pass / 0 fail**.
- `bash scripts/validate-settings.sh` → ALL CHECKS PASSED (inclui os arquivos C++ alterados).
- `bash scripts/validate-desktop.sh` → ALL CHECKS PASSED (com 1 verificação atualizada, §3 H4-008).
- `bash scripts/validate-welcome.sh` → ALL CHECKS PASSED.
- `bash scripts/verify-source.sh` → 15 pass / 1 warn / 0 fail (warning conhecido: placeholder do destino ISO).
- `bash -n` nos 3 scripts shell alterados/criados → OK.
- `shellcheck -S warning` nos mesmos 3 → sem diagnósticos.
- `systemd-analyze verify --man=no` nas 2 unidades alteradas → apenas reclamações ambientais já documentadas pela auditoria (bits de permissão DrvFS, executáveis ausentes no host); nenhum erro de conteúdo.
- Novos testes: `scripts/test-update-engine.mjs` (31 verificações PASS), `scripts/test-launcher-filter.mjs` (12 PASS), `scripts/test-launcher-appactions.mjs` (41 PASS), `scripts/test-desktop-helpers.sh` (30 PASS).

**NÃO EXECUTADOS nesta rodada** (exigem ambiente da build/imagem): compilação Qt/KF6, CTest (native-smoke estendido e flatpak-lifecycle-smoke), carregamento de QML/plugin, boot/VM, `verify-image.sh`. Não há toolchain Qt neste host (Windows sem compilador; WSL sem Qt6/KF6). Nenhum update real, nenhuma imagem OCI/QCOW2/VDI/ISO, nenhum VirtualBox, nenhum commit/push.

## 2. H4-001 — método inexistente em QStorageInfo (bloqueador de build)

- **Causa:** `settings/src/update/updateengine.cpp` (preflight) chamava `QStorageInfo::exists()`, método que não existe na classe; o target principal não compila.
- **Correção:** a decisão de preflight foi extraída para o cabeçalho puro `settings/src/update/storagepreflight.h` (`storagePreflightCheck`), que distingue explicitamente quatro estados: válido+pronto com espaço (`Ok`), válido+pronto sem espaço (`Insufficient`) e **inválido, não pronto ou tamanho indeterminado (`Unreadable`)** — `isValid()`/`isReady()`/`bytesAvailable() < 0`. O preflight passou a falhar fechado: armazenamento ilegível bloqueia a mutação com mensagem própria, em vez de passar silenciosamente como antes. Não foi uma troca de string: `exists()` desapareceu do fonte (verificado por busca) e a matriz completa de estados virou caso de teste.
- **Arquivos:** `settings/src/update/storagepreflight.h` (novo), `settings/src/update/updateengine.cpp`, `settings/tests/native-smoke.cpp`, `scripts/test-update-engine.mjs` (novo).
- **Teste:** matriz de 7 casos (3 GiB, 1 GiB, 2 GiB−1, `bytesAvailable = -1`, não pronto, inválido, ambos) em `native-smoke.cpp` e no espelho Node.
- **Resultado:** espelho Node PASS; native-smoke NOT RUN nesta rodada (compila na build autorizada).
- **Limitação:** o comportamento de `QStorageInfo` para `/ostree` e `/var` na imagem real só se prova na build/VM.

## 3. H4-002 — ID de aplicativo concatenado em comando de shell (P0)

- **Causa:** `AppActions.qml` aceitava qualquer string terminada em `.desktop` e concatenava em `connectSource("enthroned-desktop-shortcut " + id)`; o engine `executable` do Plasma5Support entrega o comando a `KProcess::setShellCommand` — metacaracteres executavam comandos adicionais da sessão.
- **Correção (três camadas):**
  1. **Construção do comando isolada** em `contents/ui/ShortcutCommand.js` (novo, compartilhado com os testes Node): `isValidStorageId` aceita apenas nomes de arquivo XDG (`^[A-Za-z0-9][A-Za-z0-9._-]*\.desktop$`, sem `..`, sem separadores, sem espaços/aspas/metacaracteres, não-oculto) e `shellQuote` aplica escape POSIX por aspas simples mesmo assim. IDs malformados nunca chegam ao shell: `buildCommand` retorna vazio e `request` não conecta fonte nenhuma.
  2. **Ciclo no AppActions.qml** delegado ao módulo (`request`/`consume`), mantendo `P5Support.DataSource` e o import de plasma5support exigidos pelo validador.
  3. **Helper revalida** (`system_files/usr/bin/enthroned-desktop-shortcut`): a mesma allowlist estrita é aplicada antes de qualquer resolução; o ID só é usado dentro dos diretórios XDG de aplicações — sem `endsWith(".desktop")` como única defesa.
- **Arquivos:** `contents/ui/ShortcutCommand.js` (novo), `contents/ui/AppActions.qml`, `system_files/usr/bin/enthroned-desktop-shortcut`, `scripts/test-launcher-appactions.mjs` (novo), `scripts/test-desktop-helpers.sh` (novo).
- **Teste:** 26 IDs malformados (espaço, aspas simples/duplas, `;`, `|`, `&`, `` ` ``, `$()`, `\n`, barras, `../`, `..`, oculto, vazio, sufixo ausente, prefixo `applications:`, tipos não-string) rejeitados sem nenhuma chamada de `connectSource`; IDs reais (`org.kde.dolphin.desktop`, `ai.storyteller.artcraft-launcher.desktop` do Welcome) continuam produzindo comando único e citado. O caso 9.7 do harness passa o literal `$(touch …).desktop` como argv ao helper real e prova ausência de efeito colateral.
- **Resultado:** PASS local.
- **Limitação:** o caminho completo (menu Plasma → DataSource → engine executável) só é exercido na VM; a fronteira de shell foi comprovada no nível do comando construído e do helper real.

## 4. H4-003 — filtro do launcher oculta aplicativos ao trocar de categoria

- **Causa:** `filterRowCallback` mutava `_seenIds` ao avaliar linhas; o conjunto só era limpo em `modelRevision`. Trocar de categoria não limpava o conjunto e a reavaliação da mesma linha invertia `true`→`false` — o predicado tinha efeitos colaterais (reprodução da auditoria: `[true,false,true]` virava `false` para o modelo seguinte).
- **Correção:** predicado **puro**: a linha é aceita somente se nenhuma linha anterior do modelo atual tem o mesmo `favoriteId`; nenhuma memória entre chamadas. Custo O(n²) por passagem de filtro, aceitável para categorias do menu. `_seenIds` foi removido; `onModelRevisionChanged` mantém apenas `invalidateFilter()`.
- **Arquivos:** `contents/ui/FullRepresentation.qml`, `scripts/test-launcher-filter.mjs` (novo).
- **Teste:** o teste extrai o callback REAL do QML (por extração sintática, sem cópia) e o executa contra um modelo mínimo: duplicatas, reavaliação repetida, Trocas de categoria em ida e volta com apps compartilhados, invalidação com mudança de dados, IDs vazios e passagem sem role. Reprodução exata da auditoria incluída.
- **Resultado:** PASS local (12 cenários).
- **Limitação:** a sequência visual completa (KSortFilterProxyModel real + delegates) segue para a VM.

## 5. H4-004 — guarda de concorrência não observava o uupd automático

- **Causa:** o receptor de `unitState` descartava respostas de `uupd.service` porque `m_watchedUnit` filtrava antes; `m_autoUpdateRunning` só recebia `true` num ramo de UpdateFull e nunca `false` simetricamente. O booleano local era tratado como bloqueio entre processos.
- **Correção:** o receptor rastreia `uupd.service` em TODA resposta, antes do filtro da unidade vigiada: estados transitórios (`activating`, `active`, `reloading`, `deactivating`) marcam executando; `inactive`/`failed` liberam — atualização simétrica com `autoUpdatesChanged()`. `mutatingFlowGate` reconsulta `uupd.service` **antes de cada mutação** (`unitState` responde sincronamente) e decide sobre estado fresco. Mapas de erro não alteram a flag.
- **Coordenação entre processos preservada:** a exclusão real continua sendo do lockfile do uupd e dos locks internos de bootc/Flatpak; a flag + reconsulta são a guarda da UI, agora honesta sobre eles (documentado no código).
- **Arquivos:** `settings/src/update/updateengine.cpp` (receptor `unitState`, `mutatingFlowGate`), `scripts/test-update-engine.mjs`.
- **Teste:** regra do uupd espelhada (activating/active/reloading bloqueiam; inactive/failed liberam) — PASS. O cenário de duas instâncias do aplicativo e provisioning Flatpak em curso exige D-Bus real (VM).
- **Resultado:** espelho PASS; integração NOT RUN nesta rodada.
- **Limitação:** duas instâncias de Settings continuam sem lock compartilhado próprio (como antes); a serialização cross-process segue sendo do uupd/bootc/Flatpak.

## 6. H4-005 — crash do Flatpak podia derrubar Settings

- **Causa:** em `FlatpakUpdatesProvider::updateUserInstallations`, o handler de `errorOccurred` limpava `m_userUpdateProcess` e emitia resultado; o handler de `finished` dereferenciava o membro sem verificar. `CrashExit` emite `errorOccurred(Crashed)` **antes** de `finished` (Qt 6.8) — sequência legítima com acesso a ponteiro nulo.
- **Correção:** ciclo com identidade: cada conexão captura o próprio `QProcess`; callbacks de operação já finalizada são ignorados (`m_userUpdateProcess != process` → return). A finalização é única e centralizada em `finishUserUpdate` (limpa membro, `deleteLater`, um `userUpdateFinished`). Apenas `FailedToStart` finaliza no handler de erro (é o único que nunca emite `finished`); `Crashed` espera o `finished` para ler stderr e finalizar uma vez.
- **Testabilidade:** `FlatpakUpdatesProvider` ganhou um seam de construção (`binaryOverride`, default vazio — produção inalterada) para que o teste execute o provider REAL contra um programa `flatpak` falso por caminho absoluto, nunca o binário real (a base de build, aurora:stable, tem flatpak instalado).
- **Arquivos:** `settings/src/flatpakupdatesprovider.h/.cpp`, `settings/src/main.cpp` e `settings/src/update/updateengine.cpp` (ajuste de instanciação), `settings/tests/flatpak-lifecycle-smoke.cpp` (novo), `settings/CMakeLists.txt` (novo teste no CTest).
- **Teste:** quatro casos com processo substituto: `kill -9 $$` (Crashed→finished), exit 1, exit 0 e FailedToStart; cada um deve produzir exatamente UM resultado, com `ok` correto e provider livre.
- **Resultado:** NOT RUN nesta rodada (sem toolchain Qt local); roda no `ctest` da build autorizada.
- **Limitação:** sem execução nativa, a correção está coberta por revisão dirigida do fluxo de sinais; o smoke compila e roda na build.

## 7. H4-006 — segunda etapa de atualização de aplicativos perdia o acompanhamento

- **Causa:** `stopWatch()` era chamado antes de `handleFlatpakSystemUnitFinished` e já limpava timer, `m_watchedUnit` e `m_updateMode`; no término da etapa `--user`, o fluxo era tratado como externo (guarda via `m_watchedUnit.isEmpty()`) e retornava antes da limpeza/`refreshAll()`. Timeout e histórico da operação morriam na fronteira das etapas.
- **Correção:** separação entre **observação de unidade** e **operação**: `stopWatch()` agora encerra apenas a observação (limpa `m_watchedUnit`; o timer e o deadline continuam — a etapa `--user` fica limitada pelo mesmo `kWatchTimeoutMs`); a nova `endOperation()` encerra a operação (timer, unidade, elapsed e `m_updateMode` com `stateChanged`). A guarda do `userUpdateFinished` passou a usar o modo da operação (`m_updateMode.isEmpty()`), e resultados fora de fluxo são registrados com `pushEvent` (o comentário antigo dizia "sem mover a máquina", mas o código usava `applyEvent` — agora o comportamento corresponde ao contrato e um resultado tardio não pode mover a máquina após um timeout já reportado). Finalização única: cada ramo termina exatamente uma operação.
- **Arquivos:** `settings/src/update/updateengine.cpp` (+ `updateengine.h`).
- **Teste:** os fluxos de engine exigem Qt/D-Bus (NOT RUN aqui); as decisões puras envolvidas (timeout por operação, resultado único) estão cobertas por revisão e pelos espelhos de H4-004/007. O cenário de regressão objetiva (system exit 0 → user progresso → sucesso/falha/sem resposta com providers falsos) permanece nos testes obrigatórios de VM/doubles da auditoria.
- **Resultado:** correção aplicada; validação comportamental completa NOT RUN nesta rodada.
- **Limitação:** sem execução nativa do engine; o caminho completo segue para doubles/VM.

## 8. H4-007 — conclusão systemd interpretada só pelo código numérico

- **Causa:** o engine usava apenas `inactive/failed` + `ExecMainStatus`. Uma unidade pulada por condição ficava `inactive` com status 0 e era lida como sucesso; sinal, timeout, falha antes do ExecStart e autorização não eram distinguidos.
- **Correção:** `SystemdCalls::unitState` passa a expor `ExecMainCode` (1=CLD_EXITED, 2=CLD_KILLED, 3=CLD_DUMPED) e `ConditionResult`. A classificação semântica vive no cabeçalho puro `settings/src/update/systemdoutcome.h` (`classifyUnitOutcome`): `Completed` exige ExecStart executado, exit 0 e `Result=success`; `ExitedWithError` para códigos válidos não nulos; `Killed` (sinal/core-dump); `TimedOut` (`Result=timeout`, avaliado antes do Killed); `Skipped` (condição falsa — nunca sucesso); `NotExecuted` (exec 203, `dependency`, `start-limit`, terminal sem ExecMainCode de saída concluída). Os quatro handlers consomem o outcome com mensagens distintas (`unitFailureText`) e **somente `Completed` produz sucesso** — no fluxo de check, o significado especial do exit 77 foi preservado (77+ExitedWithError → `check-no-update`, sucesso sem novidades). StartUnit negado por autorização continua tratado em `startUnitResult`.
- **Arquivos:** `settings/src/update/systemdcalls.h/.cpp`, `settings/src/update/systemdoutcome.h` (novo), `settings/src/update/updateengine.cpp/.h`, `settings/tests/native-smoke.cpp`, `scripts/test-update-engine.mjs`.
- **Teste:** matriz de 12 resultados (exit 0, 77, 1, sinal, core-dump, timeout, condição falsa, exec 203, dependency, start-limit, protocolo-sem-ExecMainCode) + mapeamento do fluxo de check (7 casos: só 0 e 77 geram sucesso; pulado/não executado/timeout/sinal → `check-failed`). Espelho PASS local; native-smoke NOT RUN (build).
- **Limitação:** propriedades reais do systemd na imagem (incl. resultado de job via caminho retornado por `StartUnit`) seguem para a VM; o par `Result`/`ExecMainCode` cobre os casos listados pela auditoria sem leitura do job path, aceita como "quando necessário".

## 9. H4-008 — primeiro login reativava preferência explicitamente desativada

- **Causa:** `enthroned-desktop-actions` não distinguia chave ausente de chave existente vazia (`kreadconfig6` devolve vazio nos dois casos) e reaplicava padrões em TODOS os logins, sem marker de migração: `MiddleButton;NoModifier=` removido pelo usuário voltava como `org.kde.paste`.
- **Correção:** separação entre **migração inicial** e **reparo**: a migração roda uma única vez por usuário (marker `${XDG_CONFIG_HOME}/enthroned/desktop-actions.done`) e semeia os padrões SOMENTE para chaves ausentes, sondadas com `--default` e sentinela (`__ENTHRONED_CONFIG_ABSENT__`) — valor explicitamente vazio é escolha do usuário e não é semeado. Após a migração, os padrões nunca são reaplicados: remoções e customizações sobrevivem a logins seguintes. A cada login permanece apenas a cura do binding obsoleto (plugin Enthroned ausente → volta `org.kde.contextmenu`), que toca somente o próprio binding.
- **Arquivos:** `system_files/usr/libexec/enthroned-desktop-actions`, `scripts/validate-desktop.sh` (a verificação textual "only writes missing values" codificava o padrão antigo e foi substituída pela nova invariante: sonda por sentinela + marker), `scripts/test-desktop-helpers.sh` (novo).
- **Teste (harness bash, helpers REAIS com kreadconfig6/kwriteconfig6/xdg-user-dir/gio simulados):** 8.1 migração semeia defaults uma vez e grava o marker; 8.2 valor esvaziado e separador removido após a migração permanecem em dois logins seguintes (reprodução direta do H4-008); 8.6 binding removido não é re-semeado; 8.5 usuário novo com valor explicitamente vazio antes do primeiro login mantém a escolha; 8.4 binding Enthroned obsoleto cura para o menu nativo; 8.3 binding customizado nunca é reescrito.
- **Resultado:** PASS (10 casos).
- **Limitação:** a semente do botão direito com plugin PRESENTE não é executável no host (o plugin é checado em diretórios reais do sistema); coberta na imagem. Dois logins reais na VM completam a prova.

## 10. H4-009 — Desktop XDG desativado era recriado pelo helper de atalhos

- **Causa:** `enthroned-desktop-shortcut` tratava `xdg-user-dir DESKTOP` = `$HOME` como inexistente e caía para `$HOME/Desktop`, contradizendo a própria política documentada no script.
- **Correção:** `$HOME` é reconhecido como "Desktop desativado" → saída limpa (`exit 0`), nada gravado. Quando `xdg-user-dir` não responde, o `user-dirs.dirs` é consultado: caminho `$HOME/subdir` é honrado; um `XDG_DESKTOP_DIR` presente sem subcaminho `$HOME` também é tratado como desativado/customizado (sem fallback); o fallback `$HOME/Desktop` acontece somente quando a configuração realmente não existe.
- **Arquivos:** `system_files/usr/bin/enthroned-desktop-shortcut`, `scripts/test-desktop-helpers.sh`.
- **Teste:** 9.1 Desktop desativado via xdg-user-dir → exit 0 e nenhum `$HOME/Desktop`; 9.2 desativado via `user-dirs.dirs` → idem; 9.3 sem configuração → fallback legado funciona; 9.4 diretório localizado é usado; 9.5 arquivo pessoal preexistente não é sobrescrito.
- **Resultado:** PASS.
- **Limitação:** combinação real do Plasma (xdg-user-dirs-update na imagem) segue para a VM.

## 11. H4-010 — "sem atualização" deixava a unidade de check como falha

- **Causa:** `enthroned-update-check.service` documentava exit 77 como "sem atualização" mas não declarava `SuccessExitStatus=77`; o systemd registrava ExecStart malsucedido.
- **Correção:** `SuccessExitStatus=77` adicionado em `[Service]`; demais códigos continuam falhando. O tratamento na interface foi preservado e reforçado (H4-007: 77 → `check-no-update`).
- **Arquivos:** `system_files/usr/lib/systemd/system/enthroned-update-check.service`, `settings/src/update/updateengine.cpp`.
- **Teste:** `systemd-analyze verify` parseou a unidade sem erro de conteúdo (ressalvas ambientais da auditoria persistem); semântica 77/0/1 coberta no espelho e na matriz nativa.
- **Resultado:** correção aplicada; a prova de "unidade não marcada failed com 77" exige executável `uupd` na imagem (VM). Nenhum update real foi executado para testar a semântica, conforme exigido.

## 12. H4-011 — comando de atalho não podia ser repetido na mesma instância

- **Causa:** `AppActions.qml` conectava a fonte e nunca desconectava; o DataSource ignora `connectSource` para fonte já conectada — criar → remover → criar não executava o helper de novo.
- **Correção:** no `ShortcutCommand.js`: `request` desconecta a fonte pendente antes de conectar a nova (uma pendente por vez) e `consume` desconecta ao receber o resultado — sucesso ou falha — registrando a falha no console. Reexecução garantida na mesma instância do popup; proteção de entrada do H4-002 mantida em todos os caminhos.
- **Arquivos:** `contents/ui/ShortcutCommand.js`, `contents/ui/AppActions.qml`, `scripts/test-launcher-appactions.mjs`.
- **Teste:** ciclo criar→consumir→criar gera DUAS execuções com desconexão entre elas; retry após falha; substituição de pendente; resultado obsoleto não limpa pendente novo; pedido inválido cancela pendente sem conectar.
- **Resultado:** PASS local.
- **Limitação:** a semântica real do DataSource na sessão Plasma segue para a VM (conforme auditoria upstream).

## 13. NP-01 — espera sem limite de `enthroned-desktop-actions.service` antes do plasmashell

- **Diagnóstico mantido:** a unidade é `Type=oneshot`, `Before=plasma-plasmashell.service`, habilitada globalmente; o timeout de início era desabilitado por padrão. **Nada foi afirmado sobre a lentidão observada na H3** — a auditoria não a reproduziu e este lote não mede boot.
- **Contenção aplicada:**
  - `TimeoutStartSec=15s` na unidade: helper travado é morto dentro de um orçamento pequeno e a sessão segue (a ordenação `Before=` é mantida — é ela que evita a corrida de configuração do menu; nenhuma dependência essencial foi removida).
  - O helper ficou mais barato: as escritas de migração agora acontecem uma vez por usuário (H4-008) em vez de todos os logins; falhas não criam loops (sem repetição, saída `exit 0` preservada).
- **Arquivos:** `system_files/usr/lib/systemd/user/enthroned-desktop-actions.service`, `system_files/usr/libexec/enthroned-desktop-actions`.
- **Teste:** `systemd-analyze verify --user` sem erro de conteúdo (ressalvas ambientais). **A medição obrigatória da auditoria (cadeia do gerenciador de usuário, blame/critical-chain, journal e instante do primeiro desktop utilizável, primeiro vs. segundo boot) NÃO foi executada — requer VM e continua pendente para a H4.**
- **Resultado:** contenção aplicada; efeito real NÃO COMPROVADO (e não afirmado).

## 14. Preservação e política

- Nenhuma alteração em: arquitetura Fedora Atomic/Aurora, bootc, identidade/temas, Welcome, Dolphin, layout do desktop, pipeline do Lote 8 (únicos toques em Welcome/engine: ajuste de construtor do provider para o seam de teste — comportamento idêntico).
- **A atualização real continua bloqueada:** o gate de mutação (`ENTHRONED_SETTINGS_ALLOW_MUTATION`, demo, origem estrangeira/unknown, staged bloqueado) foi preservado; `release-channel.json` segue sem canal confiável; nenhum `bootc upgrade`, rollback ou atualização real de Flatpak foi executado. As unidades de mutação e o polkit não foram alterados.
- Validadores: apenas 1 verificação textual do `validate-desktop.sh` foi atualizada (§9) porque codificava o padrão defeituoso antigo; nenhuma verificação foi afrouxada ou removida.
- Nenhum commit, push, imagem OCI/QCOW2/VDI/ISO ou VirtualBox.

## 15. Verificações pendentes que a build/VM da H4 deve fechar

1. Compilar os três projetos e rodar CTest — agora inclui `settings-native-smoke` (matriz H4-001/H4-007) e `flatpak-lifecycle-smoke` (H4-005 com flatpak falso).
2. Carregar Settings/launcher em smoke gráfico; exercitar FullRepresentation/AppActions reais (H4-002/003/011) e o plugin de menu de contexto.
3. Doubles do atualizador: duas etapas system→user com sucesso/falha/sem resposta (H4-006), uupd ocupado, duas instâncias (H4-004), 77/condição/timeout/sinal reais (H4-007/010).
4. VM: dois logins para H4-008; Desktop desativado para H4-009; medição completa do NP-01 (blame/critical-chain/journal + primeiro desktop utilizável, 1º e 2º boot).
5. Registrar digest/versões resolvidas da base (Aurora, Qt, Plasma, KF6, bootc, uupd, Flatpak).

**Estado do gate: as correções dos bloqueadores estão aplicadas com regressões locais PASS; o GO/NO-GO continua dependendo da build autorizada e das evidências de VM listadas acima. Nenhuma declaração de "pronto para uso" ou "boot corrigido" é feita neste relatório.**
