# Enthroned OS — Lote 12 de confiabilidade

19 de novembro de 2026 · America/Sao_Paulo

**GO para revisão independente. NO-GO para abrir o canal de produção.** A confirmação do deployment e a retomada do Welcome passaram nos testes automatizados. A integração com systemd, SELinux e Plasma em um boot real continua pendente.

O diagnóstico usa os quatro relatórios de entrada. [Gate 11C](GATE-11C-INTEGRATION.md), [Lote 11A](LOTE-11A-SYSTEM-STABILITY.md), [Lote 11B](LOTE-11B-UX-FIXES.md) e homologação H5 (`H5-VM-HOMOLOGATION.md`, evidência local).

## O1 — Confirmação do deployment

Antes de mudar o código, a reprodução com a spec e eventos simulados começou em `updating`. A leitura do cache de boot sem `staged` manteve `updating`, `update-success` levou a `upToDate` e outra leitura do cache manteve `upToDate`. A asserção que exigia confirmação pendente falhou. O serviço de status era executado uma vez por boot e o UpdateEngine relia o mesmo arquivo ao receber a saída da unidade. A spec também permitia que uma leitura sem staging derrubasse `restartRequired` para `upToDate`.

- O cache de boot informa a versão instalada. O resultado da verificação de disponibilidade continua no campo **Última verificação**. A leitura do deployment preserva esse resultado.
- A saída bem-sucedida da unidade correlacionada leva a **Confirmação do deployment pendente**. O UpdateEngine exige um snapshot válido cuja consulta tenha começado depois do `ExecMainExitTimestampMonotonic` da unidade. Uma publicação atrasada de consulta antiga, um timestamp igual ao de saída, a ausência de timestamp e uma falha de leitura mantêm a confirmação pendente. O evento de sucesso do journal sozinho deixa de concluir a operação.
- Uma captura recente com `staged` produz **Reinicialização necessária** e a notificação correspondente. Uma captura recente sem `staged` produz **Atualização do sistema concluída**, com indicação de que nenhum reinício está pendente. Uma leitura sem staging deixa de transformar uma reinicialização confirmada em **Sistema atualizado**. Falhas da unidade continuam visíveis mesmo quando o cache anterior informa staging.
- O observador do diretório acompanha a publicação atômica e o botão **Consultar status do deployment** relê somente o arquivo. Enquanto falta a confirmação, a Central mantém disponíveis navegação, detalhes e histórico. Uma nova operação fica suspensa para preservar o resultado pendente. A confirmação funciona por evento de arquivo, sem polling adicional.

### Republicação e autorização

O helper existente consulta apenas `/usr/bin/bootc status --format=json`. O serviço de boot continua publicando após `graphical.target`. A unidade de atualização do sistema e um drop-in da unidade de atualização completa `uupd-manual.service` reutilizam o helper em `ExecStartPost`, com limite de 30 s. Um erro na consulta fica no journal e preserva o resultado da atualização para que a interface possa reportar confirmação pendente. O instante da captura usa o mesmo relógio monotônico e a mesma unidade de tempo do systemd. [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) · [Propriedades D-Bus do systemd](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html).

As unidades já autorizadas continuam sendo os pontos de entrada. A regra polkit, os comandos de mutação e a configuração do canal foram preservados. O helper serializa os escritores, verifica o diretório de destino, grava por renomeação atômica e publica como root/`0644`. O leitor mantém a validação do descritor aberto, origem, tipo, tamanho, permissões e estrutura JSON. A abertura sem bloqueio permite rejeitar FIFO antes da leitura.

## O2 — Política do Welcome

| Ação | Resultado |
| --- | --- |
| Primeiro login | Abre o assistente pelo autostart. |
| Fechar no meio | Guarda a etapa e oferece retomada automática no próximo login. |
| Encerramento inesperado | O próximo login recupera a última etapa gravada de um assistente em andamento. |
| Concluir na etapa final | Grava `completed` e suprime o autostart. |
| Pular assistente | Grava `dismissed`, preserva etapa e preferências e suprime o autostart. |
| Abrir manualmente | Disponível em todos os estados. Fechar ou interromper a revisita mantém a decisão anterior. Quem dispensou pode concluir depois. |

O arquivo em `$XDG_STATE_HOME/enthroned-os/welcome-state.json` continua usando gravação atômica com `QSaveFile`. Registros v1 existentes conservam fase, etapa e preferências válidas. O antigo campo `manualReopen` deixa de afetar o autostart. Versões antigas gravavam **Pular** como `completed`, portanto esses usuários permanecem fora do autostart como concluídos. A fase antiga não permite distinguir as duas ações. Um arquivo ausente, corrompido ou com versão desconhecida volta ao estado inicial. A seleção Classic ou Modern continua exigindo ação explícita.

## Arquivos

O repositório começou sem commits em `main`. Foram alterados 35 arquivos de código, teste e configuração preexistentes. O inventário e as cópias verificadas por SHA-256 ficam no diretório de backup. output/lote-12-backup-20261119 (`../../output/lote-12-backup-20261119/`, evidência local).

| Área | Arquivos alterados |
| --- | --- |
| Settings | `settings/src/bootcstatusprovider.{cpp,h}`, `settings/src/update/updateengine.{cpp,h}`, `settings/src/update/systemdcalls.{cpp,h}`, `settings/src/update/systemdpropertymap.h`, `settings/src/update/update-state-spec.json`, `settings/src/update/demo/scenarios/restart-pending.json`, `settings/qml/pages/UpdatesPage.qml` |
| Regressões do Settings | `settings/tests/{bootc-status-smoke.cpp,update-engine-integration-smoke.cpp,run-tests.mjs}`, `scripts/test-update-engine.mjs` |
| Cache e unidades | `system_files/usr/libexec/enthroned-bootc-status`, `system_files/usr/lib/systemd/system/{enthroned-bootc-status.service,enthroned-system-update.service}`. Novo `system_files/usr/lib/systemd/system/uupd-manual.service.d/enthroned-bootc-status.conf`. |
| Welcome | `welcome/src/{main.cpp,welcome-state-spec.json,welcomecontroller.cpp,welcomecontroller.h}`, `welcome/qml/Main.qml`, `welcome/tests/{native-smoke.cpp,run-tests.mjs}`, cenários `02-conclusao`, `03-pular-primeira-etapa`, `06-instancias-duplicadas`, `07-artcraft-padrao-desmarcado`, `15-sessao-offline`, `17-usuario-existente` e `18-reabertura-manual` em `welcome/tests/scenarios/` |
| Traduções e validadores | `build_files/l10n/pt_BR/enthroned-{settings,welcome}.po`, `scripts/validate-welcome.sh`, `scripts/validate-desktop.sh`. O validador do Desktop agora verifica a saída `75` para falta de rede, de acordo com o Lote 11A. |
| Documentação e índice | Este relatório e saídas regeneradas do Graphify em `graphify-out/`. |

## Verificações do Lote 12

Compilação Release com CMake/Ninja da Central e do Welcome em contêiner descartável no Podman/WSL. O código foi montado em somente leitura. Base Aurora aprovada, `sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`. O teste do helper usou um segundo contêiner sem rede, com um executável fictício que só aceita leitura de status.

| Verificação | Resultado |
| --- | --- |
| CTest Settings e Welcome | **6/6** e **2/2**, incluindo encerramento do Settings e ciclo Flatpak. |
| Regressões nativas dirigidas | **59** verificações do leitor bootc, **62** de integração do UpdateEngine e **40** de persistência/retomada no Welcome, sem falhas. |
| JavaScript | Settings **488**, Welcome **104**, espelho do UpdateEngine **59**, filtro do launcher **12**, deduplicação de fixados **11**, ações do launcher **41**. Zero falhas. |
| Perfis Classic e Modern | **2** verificações do menu de contexto e **6** cenários simulados de layout. |
| Validadores | Settings **342**, Welcome **210**, Desktop **352** linhas `PASS`. `test-system-stability.sh` **65 PASS**, incluindo Firstboot-flatpaks com saídas `0/75/77/1` e canal fechado. |
| Publicador bootc e systemd | **6** verificações isoladas, incluindo publicação posterior à saída simulada, lock, cache inválido, diretório gravável rejeitado e verificação estática das **3** unidades. Exatamente **3** execuções do bootc fictício, todas de leitura. `bash -n` e ShellCheck saíram com 0. |
| Discover | `flatpak-backend` carregado via `--listbackends`. `plasma-discover-packagekit`, `plasma-discover-offline-updates` e daemon PackageKit ausentes na transação testada. |
| QML e pt_BR | Os **2** QML alterados passaram no `qmllint`, com **349** avisos em `UpdatesPage.qml` e **39** em `Main.qml` do Welcome. `msgfmt --check` passou nos **2** catálogos, com avisos de metadados já existentes no cabeçalho. |
| Teclado e acessibilidade | Tela Xvfb com Qt e AT-SPI. `Tab` alcançou **Pular assistente**, cujo nome e descrição apareceram em pt_BR. `Espaço` gravou a dispensa. Dois autostarts posteriores saíram sem janela, inclusive após interromper uma revisita manual. `Ctrl+F`, busca de `bootc` e `Enter` abriram a Central, com o título pt_BR de reinicialização no cenário simulado. |

## Riscos residuais e homologação

- Homologar no Plasma real o autostart entre logins, a retomada após fechamento, o foco e a aparência em Classic e Modern. Repetir também a validação visual dos Fixados e o catálogo e instalação Flatpak do Discover sem PackageKit.
- Verificar em boot real a ordem efetiva de `ExecStartPost`, os rótulos SELinux, a publicação em `/run` e a notificação de reinicialização. A confirmação pendente dura enquanto a instância da Central está aberta. Na próxima abertura, o aplicativo começa pelo status disponível e sem um resultado de verificação naquela instância. Atualizações fora das duas unidades integrantes e o estado após uma operação externa ficam para revisão e homologação.
- A retomada depende de um diretório de estado gravável. A publicação depende do cache e dos binários da base aprovada. A confirmação fica pendente se o helper falhar e nenhuma captura recente for publicada.
- Seguem no backlog `/var` somente leitura após desligamento inesperado, tempo de inicialização do `tuned`, captura de teclado do KRunner e espaço livre incorreto no Dolphin. As evidências anteriores continuam nos relatórios H5 e 11C.

Canal `f1-dev`, `production_ready: false` e lista de origens esperadas vazia. A execução ficou em testes simulados e contêineres descartáveis. H4/H5, imagens existentes, VirtualBox, registry e histórico Git ficaram fora da execução.
