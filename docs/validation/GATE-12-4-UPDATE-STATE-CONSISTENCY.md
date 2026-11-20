# Gate 12.4 — Consistência de estados da Central de Atualizações

19 de novembro de 2026 · America/Sao_Paulo

**GO para fechar as correções do Gate 12.4.** O Settings compilou na Aurora fixada e os seis CTests passaram. A homologação em Plasma real fica pendente. O canal segue `f1-dev`, com `production_ready: false`, lista de origens vazia e registry nulo.

## 1. Causa demonstrada

O `UpdateEngine` aceitava um cache com `staged`, informava `restartRequired` e depois passava a `failed` quando a segunda operação falhava. Essa transição representava corretamente o erro. O motor preservava a falha quando relia o cache, mas o QML vinculava o aviso e o botão **Reinicializar** exclusivamente a `state === "restartRequired"`. A abertura de outra instância restaurava o aviso porque a descoberta inicial do mesmo cache voltava a `restartRequired`. O defeito estava no uso do estado da operação para apresentar o estado do deployment. [Gate 12.1, seção 9](GATE-12-1-SECURITY-REVIEW.md#9-decisões-que-precisam-de-autorização)

Uma releitura com `staged` também podia inserir outra observação no histórico local. O histórico mesclado mostra os 100 registros locais mais recentes, então observações repetidas podiam ocupar o lugar de resultados de operações. O cache ausente limpava os campos do leitor, o que tornava insuficiente vincular diretamente o aviso a `bootc.stagedPresent`.

## 2. Correção

- O motor conserva a última observação válida de staging para indicar reinício. Cache ausente, inválido ou anterior à observação aceita preserva a pendência conhecida. Uma captura válida e posterior sem staging pode encerrá-la. A reabertura consulta o cache do boot atual e carrega o histórico persistido. Com cache indisponível na abertura, os detalhes do deployment ficam **Indisponíveis**.
- **Falha** continua no título e nos detalhes da operação. Se o deployment também aguarda reinício, a Central mostra **A reinicialização continua necessária para aplicar a alteração preparada. Salve seu trabalho antes de reiniciar.** O botão usa a autorização existente e fica desabilitado com operação em andamento, confirmação pendente ou serviço indisponível. Com canal fechado, a indicação pode aparecer e o botão permanece desabilitado.
- Uma releitura do mesmo staging na sessão preserva o resultado da operação e evita inserir outro registro de staging. Um resultado novo entra no histórico assim que é salvo. A reabertura reconstrói a indicação de reinício pelo cache e mostra a falha anterior no histórico. O título volta a refletir o que se conhece na nova sessão.
- Sucesso no comando ainda leva a `deploymentPending`. A confirmação exige cache válido, com início da captura estritamente posterior a `ExecMainExitTimestampMonotonic` da operação correlacionada. Os alertas sobre a origem do staged e os bloqueios de mutação continuam ativos. [Lote 12](LOTE-12-RELIABILITY.md)

## 3. Verificações antes e depois

| Verificação | Resultado |
| --- | --- |
| `node settings/tests/run-tests.mjs`, antes de alterar a implementação | **494 passaram, 2 falharam**. O teste executou a sequência da spec e as condições reais `visible` do QML. Em `failed`, o erro continuou visível, o aviso e o botão de reinício desapareceram. Ambos reapareceram no cenário de reabertura simulado. |
| `node settings/tests/run-tests.mjs`, após a correção | **517 passaram, 0 falharam** na Aurora. Inclui as condições reais do aviso e do botão, mensagens de falha e indisponibilidade, transições e textos pt_BR no catálogo. O teste JavaScript verifica as condições de apresentação, sem renderizar Qt Quick. |
| `node scripts/test-update-engine.mjs` | **59 passaram**, incluindo a correlação entre job e resposta terminal e a propriedade de relógio monotônico. |
| `scripts/validate-settings.sh` | **347 linhas PASS**, exit 0 na Aurora. Inclui checks de spec, QML, tradução e da regra polkit distribuída. |
| Compilação Release e `ctest --output-on-failure` | **6/6 passaram** em 7,39 s. `appstreamtest`, `settings-close-smoke` com Qt offscreen, `settings-native-smoke`, `flatpak-lifecycle-smoke`, `bootc-status-smoke` e `update-engine-integration-smoke`. O leitor bootc passou **73 verificações**. A integração passou novamente em execução direta. |
| Cenários da integração nativa | Staging sem erro, segunda operação com falha, refresh com staging válido ou ausente, cache antigo, duas operações com timestamps distintos, serviço indisponível, histórico após refresh, fechamento e reabertura, novo boot e canal fechado. |
| `msgfmt --check` para `enthroned-settings.po` | Exit 0. Permanecem os três avisos de cabeçalho para `PO-Revision-Date`, `Last-Translator` e `Language-Team`. |
| `scripts/test-bootc-status-helper.sh` | **28 passaram, 0 falharam**. Todas as chamadas ao bootc simulado foram de leitura. |
| `scripts/test-auto-update-safety.sh` | **9 grupos passaram**. As nove unidades ficaram mascaradas e recusaram partida com canal ausente, inclusive para root. O harness usa marcadores inertes no lugar dos comandos de atualização. |
| `scripts/test-polkit-uupd.sh` | **83 passaram, 0 falharam**. 20 consultas com polkit real e 63 no harness com as regras da Aurora e do Enthroned. Os dois controles que dependem das regras `empower.rules` e `22-ublue-rebase-systemd.rules` passaram na base. |

O host tinha 13,36 GiB livres de 31,84 GiB antes da partida. Só o Ubuntu WSL2 foi iniciado. O Podman confirmou a base local `ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`. A compilação usou CMake/Ninja em Release, `BUILD_TESTING=ON`, três jobs e fonte montada somente para leitura. O CMake registrou avisos sobre alvos de plugins Kirigami. O build e o teste de encerramento Qt passaram.

O ambiente carecia de `newuidmap` para Podman rootless e de `nft` para a bridge padrão. A validação usou Podman rootful com `--pull=never`. Os contêineres de compilação e polkit usaram a rede do WSL para instalar ferramentas temporárias em seus próprios filesystems. Os testes de máscara e publicação rodaram sem rede. O inventário final confirmou a remoção dos contêineres e de seus diretórios de trabalho, com o mesmo ID e digest da Aurora preservados. O WSL mostrava Ubuntu e Docker Desktop parados na última consulta.

## 4. Compatibilidade e arquivos modificados

A verificação estática confirmou os quatro timers desabilitados pelo preset e as nove máscaras do Gate 12.3, os três `ExecStartPost` leitores e o canal fechado. Os hashes SHA-256 de dez arquivos de política, units, drop-ins e publicação do cache coincidiram antes e depois. A sintaxe Bash da política, do publicador e dos três testes relacionados passou em `bash -n`. A restrição polkit do Gate 12.2 e a publicação segura do cache do Gate 12.1 continuam usando os mesmos arquivos. As evidências de execução privilegiada anteriores estão nos Gates [12.1](GATE-12-1-SECURITY-REVIEW.md), [12.2](GATE-12-2-POLKIT-UUPD.md) e [12.3](GATE-12-3-AUTO-UPDATE-SAFETY.md).

- `settings/src/update/updateengine.{h,cpp}` e `settings/src/update/update-state-spec.json`
- `settings/qml/pages/UpdatesPage.qml` e `build_files/l10n/pt_BR/enthroned-settings.po`
- `settings/tests/update-engine-integration-smoke.cpp` e `settings/tests/run-tests.mjs`
- Este relatório e o índice de código em `graphify-out/`

A atualização do Graphify também gravou automaticamente no snapshot datado `graphify-out/2026-11-19/` a versão anterior do índice. Os diretórios de backup do sistema em `output/` ficaram fora da execução.

## 5. Riscos residuais e homologação

- O estado de staging conservado em memória dura até o encerramento da Central. Se o cache continuar ausente na próxima abertura, o aplicativo precisa de uma nova captura para indicar reinício. O histórico depende de gravação em `XDG_STATE_HOME` e mantém seus limites existentes.
- A homologação em Plasma real deve conferir os estados e textos pt_BR, o foco e a disponibilidade do botão em **Falha**, **Serviço indisponível** e com canal fechado. Conferir também a reabertura com staging, a reabertura após boot sem staging e a presença do erro no histórico.
- A verificação em boot real de SELinux, cache em `/run`, ordem efetiva dos `ExecStartPost`, nove `LoadState=masked` e sessões polkit `wheel` e comum depende de autorização separada. Os testes deste gate usam resultados e deployments simulados.

A validação nativa confirmou a correção existente. O GO encerra este gate e autorizações para H6 e abertura de produção seguem fora do seu escopo.
