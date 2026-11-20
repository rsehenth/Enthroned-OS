# Enthroned OS — Lote 9.1: gate de estabilidade pré-build H4

Data: **2026-11-18** (America/Sao_Paulo). Decisão: **NO-GO para iniciar a build da Homologação 4 com o código atual.**

Há um erro de API que impede compilar Settings, uma fronteira de execução de shell insegura no launcher e defeitos de integração não exercitados pelos validadores. Nenhuma falha de boot ou atraso de login novo foi reproduzido nesta auditoria. Não se deve transformar essa ausência de reprodução em aprovação do boot.

## 1. Escopo, método e limites

- Auditoria do estado atual de `Containerfile`, `build_files`, `system_files`, `desktop-actions`, `settings`, `welcome`, scripts de verificação e blueprint local da homologação. Confrontados os documentos dos Lotes 6, 7, 7.1, 8 e 9; as correções intermediárias atribuídas a 6.1 foram conferidas nos arquivos atuais de integração, dependências e instalação. Não foi localizado um relatório autônomo identificado como Lote 6.1.
- O workspace não oferece histórico de commits utilizável para reconstruir diffs desses lotes. Já havia numerosos arquivos não rastreados na entrada. Os achados referem-se ao conteúdo atual, sem atribuir autoria ou introdução a um commit inexistente. Comentários de código com outros números de lote não foram usados como prova de validação.
- **Graphify:** consultado primeiro o grafo existente por `uv --offline tool run --from graphifyy graphify query ...`. São **1.952 nós e 3.173 ligações**, sem endpoints ausentes no JSON. As consultas apontaram para instalação, menu de contexto, primeiro login e UpdateEngine. Consultas com orçamento reduzido foram truncadas; a confirmação veio da leitura dos fontes, não da suposição de cobertura completa do grafo. Não houve rebuild/update do grafo: nenhum código foi alterado.
- **context-mode:** retomada por `ctx_resume`, execução e indexação de verificações, extração de resultados resumidos. **RTK:** estado do Git e pesquisas condensadas. **Headroom:** armazenamento/compressão de inventário e síntese intermediária. Esses recursos organizaram evidências; não provaram comportamento do sistema.
- Contratos de API conferidos em documentação oficial via Context7 e fontes upstream Qt/KDE, com links nas seções relevantes. A versão efetivamente resolvida pela base `aurora:stable` ainda precisa ser registrada na build.
- Somente verificações leves existentes e sondas temporárias em isolamento foram executadas. Nenhuma ferramenta foi instalada. Não houve compilação, imagem, boot, alteração de VM, atualização real, commit, push ou publicação. Este relatório é a única alteração persistente solicitada no projeto.

**Escala:** P0 = segurança/dados ou impedimento de boot/login/uso básico; P1 = funcionalidade importante ou integração incorreta; P2 = comportamento secundário; NÃO COMPROVADO = efeito que ainda depende de runtime/medição. Um bloqueador de compilação é marcado P1 + bloqueador de build, sem alegar que um kernel já deixou de iniciar.

## 2. Resultado das verificações executadas

| Verificação | Resultado desta auditoria | O que comprova |
| --- | --- | --- |
| `bash scripts/validate-desktop.sh` no WSL Ubuntu | exit 0; 275 linhas PASS; `ALL CHECKS PASSED` | Estrutura, referências e condições textuais implementadas pelo validador |
| `bash scripts/validate-settings.sh` no WSL | exit 0; 328 linhas PASS; Node ausente nesse PATH, explicitamente pulado | Validação estática; não compila o UpdateEngine |
| `bash scripts/validate-welcome.sh` no WSL | exit 0; 206 linhas PASS; Node ausente nesse PATH, explicitamente pulado | Validação estática |
| `bash scripts/verify-source.sh` no WSL | exit 0; 15 pass / 1 warn / 0 fail | O warning é o placeholder conhecido do destino ISO |
| `node settings/tests/run-tests.mjs` no Windows | **444 pass / 0 fail** | Contrato declarativo e parser espelhados em JavaScript |
| `node welcome/tests/run-tests.mjs` no Windows | **85 pass / 0 fail** | Contrato declarativo e lógica espelhada; não roda o controlador Qt |
| `node scripts/test-layouts.mjs` no Windows | **6 cenários passaram** | Executa os layouts reais contra uma API Plasma simulada |
| `bash -n` nos scripts Bash de scripts/build_files e helpers entregues | **18 arquivos, 0 falhas** | Sintaxe shell |
| `shellcheck -S warning` nesses mesmos 18 arquivos | exit 0 | Nenhum diagnóstico nesse nível; não analisa QML/C++ |
| `systemd-analyze verify --man=no` nas unidades Enthroned, no WSL | **exit 1, inconclusivo para a imagem** | Reclamou de executáveis ausentes no host e modos do DrvFS; não é aprovação systemd |
| Sondas temporárias de callback QML e helpers | Quatro defeitos observados nas fronteiras descritas abaixo | Não equivalem a uma sessão Plasma real |
| CMake, CTest, carregamento de QML/plugin, `verify-image.sh`, boot/VM | **NÃO EXECUTADOS** | Exigem o ambiente da build/imagem; não foram substituídos por greps |

O WSL possui ShellCheck e systemd-analyze, mas não possui os binários Aurora `bootc`, `uupd`, `flatpak` e os helpers instalados em `/usr/libexec`. O volume Windows apresenta unidades com permissões excessivas ao verificador. `build_files/build.sh:12–43` normaliza arquivos/unidades e executáveis na imagem. Os avisos do host, portanto, não comprovam permissões incorretas na imagem; a normalização também não foi executada aqui.

## 3. Achados comprovados

### H4-001 — P1, bloqueador de build: método inexistente em QStorageInfo

**Arquivo/evidência:** `settings/src/update/updateengine.cpp:592` e `:600` chamam `sysroot.exists()` e `var.exists()`, ambos declarados como `QStorageInfo`. A classe oferece `isValid()` e `isReady()`, mas não `exists()`. Confirmado na [API oficial](https://doc.qt.io/qt-6/qstorageinfo-members.html) e no [header Qt 6.8](https://github.com/qt/qtbase/blob/6.8/src/corelib/io/qstorageinfo.h).

**Impacto:** o target principal de Settings não compila. `settings/CMakeLists.txt` inclui esse arquivo no executável; `Containerfile:30–35` constrói o target antes de CTest e da instalação. O gate de mutação fechado não evita um erro de compilação. Não foi necessário executar uma build para identificar a incompatibilidade.

**Correção mínima recomendada:** usar as condições de validade/disponibilidade da API real, normalmente `isValid()`/`isReady()`, conservando o tratamento de `bytesAvailable()` e decidindo explicitamente a falha de leitura do armazenamento. Não substituir por um teste que apenas aceite a string nova.

**Regressão objetiva:** compilar o executável completo na build autorizada; testar o preflight com volume pronto, indisponível e abaixo do limite. O smoke nativo atual compila a máquina de estados, não o UpdateEngine.

### H4-002 — P0, segurança: ID de aplicativo concatenado em comando de shell

**Arquivo/evidência:** `system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/AppActions.qml:50–55` aceita qualquer string terminada em `.desktop` e executa `connectSource("enthroned-desktop-shortcut " + id)`. Não há escape/allowlist nessa fronteira. O [engine executable do Plasma5Support 6.6](https://github.com/KDE/plasma5support/blob/Plasma/6.6/src/dataengines/executable/executable.cpp) entrega o comando a `KProcess::setShellCommand`.

**Reprodução limitada e inofensiva:** para o ID controlado `audit; printf SHELL_BOUNDARY_EXECUTED #.desktop`, que satisfaz o teste de sufixo, a mesma construção de comando passou apenas `audit` ao helper simulado e imprimiu `SHELL_BOUNDARY_EXECUTED` separadamente. Nenhum aplicativo, comando destrutivo ou atualização foi executado. O helper real não protege contra interpretação que ocorre antes de recebê-lo.

**Impacto/condições:** uma entrada de aplicativo/favorito que forneça metacaracteres pode executar comandos da sessão quando o usuário pede **adicionar um atalho**, sem pedir para iniciar o aplicativo. O alcance é o usuário da sessão, sem elevação comprovada. O teste comprovou a fronteira shell; não foi executado um ataque completo pelo menu Plasma. A recomendação de nomes de arquivo da especificação desktop não deve ser tratada como validação de entrada nessa chamada.

**Correção mínima recomendada:** passar o ID como argumento sem shell, se a infraestrutura disponível permitir; mantendo o engine, rejeitar IDs fora de uma allowlist estrita de storage IDs e aplicar escape POSIX correto. No helper, rejeitar separadores de caminho e resolver apenas entradas autorizadas nos diretórios XDG. Não confiar somente em `endsWith(".desktop")`.

**Regressão objetiva:** chamar a função real com IDs contendo espaço, aspas, `;`, `$()`, quebra de linha e `../`; nenhuma segunda instrução pode ser executada e nenhum destino pode escapar do Desktop autorizado. Incluir um ID normal que ainda funcione.

### H4-003 — P1: filtro do launcher oculta aplicativos após mudar de categoria

**Arquivo/evidência:** `system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/FullRepresentation.qml:97–125`. `filterRowCallback` modifica `_seenIds` ao avaliar linhas. O conjunto só é limpo quando `modelRevision` muda; a seleção da categoria altera `rawCategoryModel`, sem limpar esse conjunto. Reavaliar a mesma linha também pode mudar `true` para `false` sem mudar o modelo.

**Reprodução:** foi extraído e executado o callback real em Node, com modelo mínimo. Para `['app.desktop','app.desktop','other.desktop']`, retornou `[true,false,true]`. Mudando o modelo para outra categoria com `['app.desktop']`, retornou **false**. Nova avaliação da mesma linha também retornou false. O [KSortFilterProxyModel](https://github.com/KDE/kitemmodels/blob/master/src/qml/ksortfilterproxymodel.cpp) chama o callback como predicado de aceitação, não como varredura única garantida.

**Impacto:** categorias podem ficar incompletas ou vazias após visitar “Todos os aplicativos” ou outra categoria. É um defeito determinístico do predicado; a sequência visual completa ainda precisa ser validada no Plasma.

**Correção mínima recomendada:** predicado sem efeitos colaterais, que aceite apenas a primeira linha com o ID no modelo atual, ou mapa de primeiras ocorrências reconstruído antes da filtragem. Limpar somente ao mudar de categoria ainda deixa o problema da reavaliação.

**Regressão objetiva:** Todos → categoria → outra categoria → Todos, com apps compartilhados; repetir invalidação e mudanças de dados. A lista deve permanecer estável e cada aplicativo aparecer uma vez. Executar também contra o proxy KDE real.

### H4-004 — P1: guarda de concorrência não observa o uupd automático

**Arquivo/evidência:** `settings/src/update/updateengine.cpp:301–312`, `:660–669` e `:802–812`. `refreshAll()` consulta `uupd.service`, mas o receptor de `unitState` retorna imediatamente quando a unidade não é `m_watchedUnit`. As operações vigiadas são check, uupd manual e unidades Enthroned; `uupd.service` não é colocado nesse campo. A única atribuição positiva a `m_autoUpdateRunning` está dentro do ramo de **UpdateFull**; não há atualização simétrica para false.

**Impacto:** a consulta do serviço automático é descartada e a guarda pode permitir uma operação enquanto o uupd já trabalha. O indicador também pode ficar incorreto após um fluxo manual. Locks internos de bootc/Flatpak podem recusar operações, mas não consertam a guarda e as mensagens da UI. Não foi comprovada corrupção nem execução concorrente real.

**Correção mínima recomendada:** tratar o estado de `uupd.service` antes do filtro da unidade vigiada, atualizar true/false em estados transitórios e terminais e consultar novamente antes de iniciar mutação. Para exclusão entre processos, usar coordenação efetiva na fronteira de execução; um bool de uma janela não é um lock compartilhado.

**Regressão objetiva:** injetar resposta `uupd.service=activating/active` com nenhuma unidade manual vigiada; nenhum `StartUnit` mutável deve ocorrer. Após `inactive/failed`, o bloqueio deve ser retirado. Cobrir duas instâncias do aplicativo e provisioning Flatpak já em curso.

### H4-005 — P1: crash do Flatpak pode derrubar Settings

**Arquivo/evidência:** `settings/src/flatpakupdatesprovider.cpp:129–145`. O handler de qualquer `errorOccurred` limpa `m_userUpdateProcess`. O handler de `finished` desreferencia esse membro sem verificar se ainda existe. No [Qt 6.8, QProcessPrivate::processFinished](https://github.com/qt/qtbase/blob/6.8/src/corelib/io/qprocess.cpp), o caso CrashExit emite `errorOccurred(Crashed)` antes de `finished`.

**Impacto:** a sequência legítima de sinais de um subprocesso que morre causa acesso a ponteiro nulo em Settings, em vez de uma falha de atualização apresentada ao usuário. O defeito está comprovado pelo fluxo dos handlers e do Qt; não foi executado o binário nativo nesta auditoria. Não há dependência desse aplicativo no boot do sistema.

**Correção mínima recomendada:** capturar a identidade do processo e garantir finalização única. Distinguir FailedToStart de erros que ainda emitem finished; ignorar callbacks de uma operação já finalizada, seguindo a proteção de identidade já usada em `BootcStatusProvider`.

**Regressão objetiva:** processo substituto local que termina por sinal, além de FailedToStart e exit não zero. Esperar um único resultado de falha, processo limpo e Settings ainda utilizável. Não requer executar Flatpak real.

### H4-006 — P1: a segunda etapa de atualização de aplicativos perde o acompanhamento

**Arquivo/evidência:** `settings/src/update/updateengine.cpp:328–330` chama `stopWatch()` antes de `handleFlatpakSystemUnitFinished()`. Esse método inicia a etapa `--user` em `:430–436`. Entretanto, `stopWatch():1095–1103` já parou o timer, apagou `m_watchedUnit` e limpou `m_updateMode`. No término da etapa user, `:205–218` considera o fluxo externo porque a unidade vigiada está vazia e retorna antes da limpeza/`refreshAll()` do ramo normal.

**Impacto:** perde-se o modo “apps”, o limite de acompanhamento e a atualização da lista/histórico ao terminar a segunda etapa. O provider user não tem timeout próprio. Uma etapa travada pode manter a UI ocupada indefinidamente. **Um término normal ainda emite `flatpak-update-success` e pode mudar a máquina para upToDate**; não se afirma que toda atualização bem-sucedida fique presa.

**Correção mínima recomendada:** separar o fim da observação da unidade systemd do fim da operação completa. Manter identidade/modo/deadline da operação até terminar `--user`; finalizar e atualizar providers uma única vez.

**Regressão objetiva:** sequência system exit 0 → user progresso → user sucesso/falha/sem resposta. Verificar modo apps até o término, um resultado final, lista atualizada e deadline limitado, usando providers falsos.

### H4-007 — P1: conclusão systemd é interpretada só pelo código numérico

**Arquivo/evidência:** `settings/src/update/systemdcalls.cpp:125–147` expõe `result` e `execMainStatus`, mas `settings/src/update/updateengine.cpp:303–336` usa somente `inactive/failed` e `execMainStatus`. Não exige `Result=success`, não lê `ExecMainCode` e não acompanha o resultado do job/condição de início. `StartUnit` retorna o caminho do job, não prova que ExecStart executou.

**Impacto:** uma condição falsa pode pular a unidade, deixando-a inactive com status numérico zero; o engine pode interpretar isso como verificação disponível ou atualização/rollback concluído. Também falta distinguir saída normal de término por sinal. Não se deve informar sucesso de uma ação que nem começou.

**Correção mínima recomendada:** acompanhar o resultado do job e distinguir condição não satisfeita, execução normal, sinal, timeout e falha. Usar as propriedades de resultado já expostas; acrescentar as indispensáveis. Preservar o significado especial de exit 77 somente no fluxo de check.

**Regressão objetiva:** unidade pulada por ConditionPathExists, falha antes de ExecStart, timeout, sinal, exit 0, exit 77 e exit 1. Só os resultados semanticamente aceitos podem produzir sucesso na UI.

### H4-008 — P1: primeiro login reativa uma preferência explicitamente desativada

**Arquivo/evidência:** `system_files/usr/libexec/enthroned-desktop-actions:66–88`. A leitura não distingue chave ausente de chave existente vazia. Para `MiddleButton;NoModifier=` intencionalmente vazio, o script grava `org.kde.paste` no login seguinte. A lógica equivalente do botão direito também reintroduz o padrão quando o plugin existe. O script roda em todos os logins; não há marker de migração inicial.

**Reprodução:** executado o helper real com kreadconfig6/kwriteconfig6 substituídos por stubs locais. A fixture de binding explicitamente vazio gerou a gravação `--key MiddleButton;NoModifier org.kde.paste`, exit 0. Nenhum arquivo da sessão real foi tocado. O relatório do Lote 7.1 §9 já reconhece que uma remoção pela GUI volta no próximo login; isso continua incompatível com preservar a escolha do usuário.

**Impacto:** preferências desativadas pelo usuário não persistem. Não se trata de uma simples aparência de menu.

**Correção mínima recomendada:** separar migração inicial de reparo de plugin ausente e registrar sua conclusão por usuário. Distinguir chave ausente de valor vazio ao semear; uma exclusão posterior à migração deve continuar excluída. Não reaplicar indiscriminadamente os padrões em cada sessão.

**Regressão objetiva:** novo usuário recebe os defaults uma vez; usuário existente com binding customizado, vazio ou removido mantém a escolha por dois logins. Reparo após remover o binário próprio deve preservar as demais preferências.

### H4-009 — P2: Desktop XDG desativado é recriado pelo helper de atalhos

**Arquivo/evidência:** `system_files/usr/bin/enthroned-desktop-shortcut:112–137`. Se `xdg-user-dir DESKTOP` retorna `$HOME`, o script trata o valor como inexistente e cai para `$HOME/Desktop`. Isso contradiz a política descrita no próprio helper.

**Reprodução:** helper real, HOME temporário, `.desktop` mínimo e `XDG_DESKTOP_DIR="$HOME"`; o comando xdg-user-dir simulado retornou HOME. Resultado exit 0: criou `home/Desktop/audit.desktop`. A sonda removeu o ambiente temporário.

**Impacto:** cria pasta/atalho apesar da opção de desativar o Desktop. Não houve perda de arquivos na sonda.

**Correção mínima recomendada:** reconhecer HOME como “desativado” e sair sem gravar. Usar fallback somente quando a configuração realmente não existe.

**Regressão objetiva:** Desktop desativado, personalizado/localizado, inexistente e atalho preexistente; não criar fallback no primeiro caso nem substituir arquivo pessoal.

### H4-010 — P2: “sem atualização” deixa a unidade de check como falha

**Arquivo/evidência:** `system_files/usr/lib/systemd/system/enthroned-update-check.service:19–20` documenta exit 77 como “sem atualização”, mas não declara `SuccessExitStatus=77`. `settings/src/update/updateengine.cpp:365–369` o trata corretamente como sucesso sem novidades na UI.

**Impacto:** quando uupd retorna 77, systemd considera ExecStart malsucedido; surge uma unidade failed/journal de erro apesar do resultado normal. Isso contamina a auditoria de estabilidade e contradiz o critério de não deixar falhas artificiais.

**Correção mínima recomendada:** aceitar explicitamente exit 77 nessa unidade, preservando a falha dos demais códigos.

**Regressão objetiva:** serviço de check com executável substituto retornando 77 deve terminar sem failed, e a UI informar ausência de atualização. Exit 1 deve continuar falhando. Não executar um update real para testar essa semântica.

### H4-011 — P2: comando de atalho não pode ser repetido na mesma instância

**Arquivo/evidência:** `system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/AppActions.qml:46–55` conecta a fonte, mas não a desconecta ao receber o resultado. O [DataSource do Plasma5Support](https://github.com/KDE/plasma5support/blob/Plasma/6.6/src/declarativeimports/datasource.cpp) ignora connectSource para uma fonte já conectada; o intervalo inicial é zero.

**Impacto:** após criar um atalho, removê-lo e pedir novamente a criação durante a vida da mesma representação do menu, o helper não é executado outra vez. Falhas iniciais também não têm uma tentativa nova garantida. O efeito depende da duração da instância do popup; a semântica de conexão foi conferida no upstream, não na VM.

**Correção mínima recomendada:** consumir o resultado e desconectar a fonte ao término, incluindo tratamento do erro. Manter a proteção de entrada de H4-002.

**Regressão objetiva:** criar → remover → criar novamente, mantendo o popup/representação instanciado; duas execuções do helper e dois resultados observáveis.

## 4. Boot/login: revisão independente do Lote 9

### NP-01 — NÃO COMPROVADO: atraso real causado por desktop-actions; espera sem limite está confirmada

`system_files/usr/lib/systemd/user/enthroned-desktop-actions.service:9–16` é **Type=oneshot**, habilitada globalmente em `build_files/build.sh:62`, com **Before=plasma-plasmashell.service** e WantedBy=plasma-core.target. O [target upstream](https://github.com/KDE/plasma-workspace/blob/Plasma/6.6/startkde/systemd/plasma-core.target) solicita o Plasma Shell. Portanto existe trabalho próprio na sequência anterior à disponibilidade do desktop, mesmo sem unidade própria na cadeia de boot do sistema.

A unidade não define TimeoutStartSec. O helper faz várias chamadas síncronas a kreadconfig6/kwriteconfig6, sem timeout externo. Para [Type=oneshot, o timeout de início é desabilitado por padrão](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), salvo configuração aplicável que o limite. `exit 0` só atua quando o script chega ao fim. O [TimeoutSec do Plasma Shell](https://github.com/KDE/plasma-workspace/blob/Plasma/6.6/shell/plasma-plasmashell.service.in) não limita o serviço anterior enquanto o job do Shell aguarda a ordenação.

**Correção do diagnóstico anterior:** a conclusão “nenhum serviço Enthroned é bloqueante”, em `docs/validation/LOTE-9-BOOT-AUDIT.md:78–83`, é ampla demais para o login gráfico. Confirma-se a dependência de ordenação; **não** se confirma que essas ferramentas travaram ou causaram os minutos observados na H3. “files-setup leva milissegundos” também não é benchmark: ele pode chamar xdg-user-dirs-update com timeout de 20 s.

**Recomendação mínima:** estabelecer limite finito para a unidade/etapa e testar que falhar ou expirar libera a sessão, sem retirar a ordenação que evita a corrida de configuração. Não desabilitar o serviço nem serviços essenciais. Medir com configuração normal e com dependência deliberadamente lenta em ambiente de teste.

**Dados indispensáveis na H4:** cadeia e tempos do gerenciador **de usuário**, propriedades de início/fim de desktop-actions e plasmashell, journal de ambos e instante do primeiro desktop utilizável. A cadeia até graphical.target do gerenciador de sistema não encerra essa investigação.

### Dracut, initramfs, bootc e bootloader

- `build_files/build.sh:418–432` exige exatamente um kernel em `/usr/lib/modules`, valida vmlinuz e regenera initramfs com `--no-hostonly --kver "$KVER"`; confere a identidade via lsinitrd. É uma defesa concreta contra usar o kernel do host, mas não prova disponibilidade de drivers, root filesystem ou boot EFI no artefato.
- Não foi identificado override próprio de bootloader que comprove uma regressão atual. Bootc/container lint e BIB/blueprint precisam ser executados somente na build autorizada. Inspecionar EFI, entradas/argumentos, correspondência kernel/initramfs e montagem real do sysroot.
- A base é a tag mutável `ghcr.io/ublue-os/aurora:stable`. Registrar digest e versões resolvidas evita comparar H3/H4 com bases implicitamente diferentes. Não foi feito pull para esta auditoria.
- As condições das quatro unidades alteradas pelo Lote 9 estão em `[Unit]`, como deveriam. Caminhos ExecStart têm origem identificável no overlay ou na base, e os chmods dos helpers constam do build.sh. A existência/SELinux/contexto e execução desses caminhos na imagem permanecem pendentes.
- O timer de provisioning é T+8 min, com Nice/IO idle e TimeoutStartSec=45min; não há dependência reversa própria que o coloque antes do graphical.target. Isso não elimina competição de I/O/Flatpak se o primeiro login demorar ou se o usuário instalar aplicativos enquanto ele roda.
- Não há nova evidência para atribuir a lentidão a ldconfig, wait-online, Plymouth, fsck, OOBE ou renderização por software. Logs históricos citados pelo Lote 9 não foram tratados como uma nova medição H4. Nenhum desses serviços deve ser mascarado por inferência.

## 5. KDE Plasma 6, instalação e primeiro login

| Integração | Conclusão de fonte e limite |
| --- | --- |
| Launcher/Plasma5Support | O import foi migrado para `org.kde.plasma.plasma5support`; não resta o tipo DataSource no import antigo. Persistem H4-002, H4-003 e H4-011. A presença do módulo QML e do engine executable na base precisa ser testada separadamente. |
| FullRepresentation/AppActions | A cadeia é carregada por `main.qml`; imports de Kicker privado, KItemModels, KConfig, KCMUtils, Kirigami Addons e demais módulos são dependências reais. Nenhum grep garante resolução de tipos ou disponibilidade de todos eles. |
| Fallback Classic/Modern | Os layouts tratam falha imediata de addWidget, mas um applet criado cujo QML falhe depois continua como único menu. O próprio teste de layouts aceita esse caso. Não há fallback automático provado para uma falha tardia de FullRepresentation. |
| Plugin C++ | `desktop-actions/CMakeLists.txt:27–39` instala no namespace `plasma/containmentactions`, com output `org.enthroned.contextmenu`, links Qt6::Gui, KF6::ConfigCore, KF6::CoreAddons e Plasma::Plasma. O Id do JSON e o nome procurado pelo helper correspondem. O construtor protegido usado é válido no [header libplasma 6.6](https://github.com/KDE/libplasma/blob/Plasma/6.6/src/plasma/containmentactions.h); não foi presumido inválido por não aparecer como construtor público na página resumida. |
| Delegação ao menu nativo | A instanciação com metadata e QVariantList segue o [PluginLoader upstream](https://github.com/KDE/libplasma/blob/Plasma/6.6/src/plasma/pluginloader.cpp). setContainment precede restore no wrapper. Isso reduz suspeitas de API; não comprova carregamento do .so, ABI ou todas as ações. |
| Presença versus carga do plugin | `plugin_installed()` verifica arquivo em dois diretórios Qt6. Não testa dependências, metadata ou sucesso de instanciação. Um .so presente e incapaz de carregar pode deixar o botão direito sem o menu esperado. Hipótese de runtime, sem falha demonstrada. |
| Configuração do wrapper | O wrapper declara não ter interface de configuração. O ajuste fino nativo por GUI fica limitado, já reconhecido no Lote 7.1; registrar como risco funcional conhecido, não dizer que a delegação preserva toda a GUI. |
| Settings/System Settings | Favoritos e Ferramentas preferem `org.enthroned.settings.desktop`. O wrapper lança enthroned-settings com fallback. KcmLauncher limita launch a módulos listados por kcmshell6; a lista real, parsing e abertura de cada KCM precisam ser verificados na base. |
| Perfis/decoração | Defaults e layouts estão instalados nos caminhos de look-and-feel; IAX, SingleClick=false, cores e ícones são consistentes em fonte. Aplicação explícita usa --resetLayout e pode reorganizar o desktop, conforme o consentimento da UI. Não é restauração completa das preferências anteriores. Renderização e aplicação real não foram testadas. |
| Lixeira/ícones | Ambos os layouts configuram Folder View e `trash.locked=true`. O teste atual simula zero desktops e, portanto, não exercita a Lixeira. Arrastar, abrir/esvaziar, proteção, geometria e reboot exigem VM. Diferenças nativas entre arraste de arquivo e widget permanecem. |
| OOBE e Welcome | Prepare do plasma-setup é indisponibilizado para evitar aplicar o perfil Aurora. A página finished e seu SVG estão presentes. CMake instala Welcome e autostart; o controlador persiste por usuário com QSaveFile e só aplica perfil por ação explícita. A sequência real OOBE → login → layout → Welcome permanece pendente. |
| Dolphin | files-setup usa caminhos XDG, marker, escrita temporária/rename e evita substituir view props existentes. Toolbar roda antes do marker para migração por versão. Validação necessária com bookmarks/toolbar de usuário já existente, Dolphin aberto durante autostart e reboot; não foi comprovada ausência de corrida. |
| Associações/persistência | mimeapps.list entrega defaults e deve ceder às escolhas do usuário. O navegador Brave é provisionado depois; não se pode garantir fallback funcional offline sem conferir o navegador que a base efetivamente contém. H4-008 e H4-009 são exceções comprovadas à promessa geral de preservar preferências. |

## 6. Atualizador: integridade, política e ausência de automatismo

**O que está presente:** comandos privilegiados fixos; sem argumento fornecido pela UI no bootc helper; unidades próprias de mutação sem instalação em targets de boot; timer próprio de staging não habilitado pelo build.sh; nenhum reboot implícito no helper. UI inicia com mutação fechada, salvo `ENTHRONED_SETTINGS_ALLOW_MUTATION=1`, e demo não executa operações reais. Esses controles não colocam Settings como dependência do boot/login.

**Canal ainda não confiável para produção:** `release-channel.json` declara production_ready=false, publish_registry=null e expected_image_references vazio. `settings/src/update/imageorigin.h` classifica repositórios não genéricos como unverified nesse estado e **permite** essa classe. Com o gate de ambiente aberto, não é exigida uma origem oficial configurada. Isso é política dev documentada, não comprovação de canal confiável. O código tampouco prova assinatura/identidade do registry ou autorização de um deployment de rollback; a origem do rollback não é exposta/verificada como a do staged.

**Fronteira privilegiada:** a regra `10-org.enthroned.settings.rules` concede gerenciamento das quatro unidades a usuário local/ativo/wheel. Não restringe o verbo a start, apesar do comentário “START/INSPECT”. As unidades/helper não verificam o gate de ambiente da UI nem o canal. Assim, o gate é uma política do aplicativo, não uma barreira contra um processo do mesmo administrador que inicie a unidade diretamente. Não se comprovou escalada de usuário sem wheel. Recomenda-se alinhar verbo/comentário e exigir a política necessária no backend antes de abrir atualização real; não trocar a política durante esta auditoria.

**Homologação sem update automático:** o blueprint local usa argumentos de kernel que mascaram `uupd.timer`, `uupd.service` e `uupd-manual.service` (`disk_config/vm.local.toml:12`). A rota QCOW2/RAW do Justfile usa esse blueprint. O overlay não habilita o timer Enthroned de sistema. Isso não certifica todos os timers/presets herdados da base, nem outras rotas de geração de disco. Verificar o resultado final e os argumentos efetivamente usados no boot. O provisioning automático de Brave é uma **instalação inicial**, continua habilitado e deve ser registrado separadamente.

**Concorrência:** H4-004 invalida a alegação de guarda completa do uupd. Não há lock próprio comum entre provisioning, unidades Enthroned e instalador user do Welcome. A serialização interna de Flatpak/bootc evita algumas operações sobrepostas, mas espera, falhas por lock e consistência das mensagens exigem testes. Não foi constatada corrupção.

**Falhas e progresso:** H4-005–H4-007 precisam de testes nativos de ciclo de vida. `SystemdCalls` também usa chamadas D-Bus síncronas na thread da UI; não houve medição de congelamento. Verificar capacidade do bootc com ajuda/versão. Se `--progress-fd` não existir, o helper atual não tem fallback sem essa flag: falhará a operação, em vez de apenas perder percentuais. A versão que a base resolver ainda não foi inspecionada, logo essa incompatibilidade permanece NÃO COMPROVADA.

**Rollback:** a UI exige deployment anterior, autorização e confirmação, e a unidade não reinicia. Não houve teste de alternância, persistência ou recuperação. Não validar rollback usando somente fixtures de estado. O gate de mutação fechado deve continuar fechado na H4 sem canal confiável.

## 7. Cobertura: o que os validadores deixam passar

1. `scripts/validate-settings.sh:259–266` conclui que há preflight/concorrência pela presença de `mutatingFlowGate`, QStorageInfo e nomes de eventos. Não detecta método inexistente, consulta descartada ou transição entre duas etapas.
2. Os testes Node de Settings/Welcome interpretam o JSON e espelham parte da lógica C++. São testes úteis de contrato, mas não executam UpdateEngine, SystemdCalls, QProcess, providers nem persistência Qt real. Fixtures de sucesso não comprovam o fluxo que deveria produzi-las.
3. `settings/tests/native-smoke.cpp` testa a máquina de estados compilada; não dirige o engine nem o FlatpakUpdatesProvider. Nenhum teste atual cobre CrashExit seguido de finished ou resultado systemd sem execução de ExecStart.
4. `scripts/test-layouts.mjs` executa o JavaScript dos layouts, mas aceita falha tardia de QML e usa `desktopsForActivity: () => []`. Não prova menu utilizável, drag de ícones, Lixeira ou persistência.
5. `validate-desktop.sh` verifica imports, strings, caminho do plugin, ordem da unidade e `exit 0`. Não instancia FullRepresentation/AppActions, não carrega o plugin e não mede a unidade que precede o Shell. Não testa pureza do filtro, escape shell ou preferência removida.
6. Os checks de timer olham o build.sh e arquivos do overlay; não enumeram enablement, presets e drop-ins efetivos da base final. Não provam ausência global de atualizações automáticas.
7. `Containerfile:50–54` executa `--help` e lint do bootc. O parser de CLI sai antes de carregar a UI: esses comandos não são smoke de QML. A compilação completa detectaria H4-001, mas ocorre tarde demais para sustentar o relatório anterior “pronto para build”.

As regressões propostas na seção 3 devem atingir essas fronteiras reais. Nenhum teste foi alterado, removido ou afrouxado para obter PASS.

## 8. Gate GO/NO-GO e plano obrigatório de H4

### 8.1 O código está pronto para iniciar a compilação?

**Não. NO-GO.** H4-001 impede construir o target principal. H4-002 compromete a integridade da ação de criar atalho. H4-003 e H4-008 afetam uso/persistência do desktop; H4-004–H4-007 deixam a integração do atualizador incorreta. PASS estático não remove nenhum deles.

**Bloqueadores a corrigir antes de um novo GO:** H4-001 a H4-008. Correções devem ser mínimas, com os testes objetivos indicados. Manter mutação fechada e canal não publicado. Resolver os P2 H4-009–H4-011 é recomendado antes da H4; eventual adiamento precisa constar do escopo e do resultado da homologação. NP-01 exige medição e contenção de espera, sem ser apresentado como causa comprovada da H3.

### 8.2 Verificações que pertencem à build/imagem

- Registrar digest Aurora, Qt, Plasma/libplasma, KF6, bootc, uupd, Flatpak e cadeia de ferramentas; verificar dependências de desenvolvimento e runtime resolvidas.
- Compilar os três projetos e executar CTest; confirmar instalação do .so, bibliotecas vinculadas, metadata/Id e descoberta no diretório Qt6 real. A existência do arquivo deve ser acompanhada de teste de carga/instanciação.
- Carregar Settings/Welcome em smoke gráfico controlado e instanciar os componentes do launcher, além de `--help`. Confirmar todos os imports, tipos e APIs privadas do Kicker na versão da base.
- Rodar os validadores existentes, `bootc container lint`, verificação de kernel/initramfs e `verify-image.sh`, somente quando existir imagem autorizada. Validar normalização de modos, ownership e contextos SELinux.
- Executar systemd-analyze verify no contexto correto para unidades de sistema e de usuário, com dependências/ExecStart da imagem disponíveis. Não reutilizar o exit 1 ambiental do WSL como resultado da imagem.
- Inspecionar enablement/presets/drop-ins de todos os atualizadores herdados e próprios, e os argumentos do artefato de homologação. Garantir uupd mascarado no artefato de teste e timer Enthroned de sistema inativo. Não habilitar atualização real para fazer esse teste.
- Verificar EFI/bootloader, entradas, referência bootc e blueprint efetivo; não usar a presença de initramfs como prova de boot concluído.

### 8.3 Testes obrigatórios dentro da VM H4

| Teste | Critério de aceite/evidência |
| --- | --- |
| Primeiro boot/OOBE | OOBE conclui; conta entra; desktop utilizável, menu abre e Welcome aparece conforme estado. Guardar tempo e journal, sem depender só de screenshot. |
| Segundo boot/login | Sem reaplicar preferências; Welcome concluído permanece fechado; sem erros novos de serviço; comparar tempos com o primeiro boot. |
| Cadeia do sistema **e do usuário** | Capturar systemd-analyze, blame e critical-chain; no usuário, incluir plasma-plasmashell.service e enthroned-desktop-actions.service. Registrar tempos de execução e espera. |
| Falha da etapa anterior ao Shell | Em ambiente controlado, simular helper lento/indisponível. A sessão deve prosseguir dentro de limite documentado. Não mascarar serviços essenciais. |
| Launcher nos dois perfis | Mouse e Meta; abrir/fechar repetidamente, favoritos, busca, categorias em ida e volta, instalar/remover app de teste. Sem “Type ... unavailable”, ReferenceError ou perda de aplicativos. |
| Ações de aplicativo | Abrir, fixar/desfixar/reordenar e criar atalho; repetir após removê-lo. Entrada malformada rejeitada, nenhuma execução shell lateral. |
| Menu de contexto C++ | Biblioteca carrega; ações nativas, Settings Enthroned, separadores e middle-click funcionam. Perfil existente e binding removido continuam respeitados após dois logins. |
| Lixeira/ícones | Abrir/esvaziar, proteção de remoção, arraste de arquivos e widget; posições persistem após logout/reboot e mudança de resolução. Registrar diferenças nativas conhecidas. |
| Preferências existentes | Antes/depois de login e reboot: wallpaper, cores, perfil, botões, favoritos, bookmarks/toolbar Dolphin, MIME e atalhos. Comparar valores, não apenas aparência. |
| Offline/rede lenta | Desktop e Welcome abrem sem rede; provisioning não trava a sessão. Nenhum falso sucesso do atualizador e nenhum requisito obrigatório de instalar Brave para usar o desktop. Conferir fallback real do navegador. |
| Atualizador com gate fechado | Botões/fluxos mutáveis permanecem bloqueados; demo não toca serviços reais. Enumerar timers e confirmar que nenhum update de sistema foi disparado automaticamente. |
| Falhas do atualizador com doubles | CrashExit/FailedToStart, condição systemd falsa, falta de autorização, serviço ausente, exit 77, timeout, duas instâncias e uupd ocupado. Settings continua utilizável e emite resultado único e correto. |
| Sistema vs apps, duas etapas | Doubles ou ambiente de integração controlado: manter modo/identidade até user concluir, renovar lista e liberar busy. Não executar atualização real na H4 sem autorização e origem confiável. |
| Capacidades/bootc status | Registrar ajuda/versão, status JSON e suporte a progress-fd/rollback; conferir parsing da origem booted/staged e mensagem de canal não configurado. |
| Journal e falhas | `systemctl --failed` e `systemctl --user --failed`; journal de sistema, kernel e usuário. Investigar erros, incluindo o check sem novidades, sem esconder saídas. |

Coleta complementar obrigatória às ferramentas do Lote 9, dentro da VM:

```sh
systemd-analyze --user blame
systemd-analyze --user critical-chain plasma-plasmashell.service
systemctl --user show enthroned-desktop-actions.service plasma-plasmashell.service \
  -p ActiveState -p Result -p TimeoutStartUSec \
  -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic \
  -p InactiveExitTimestampMonotonic -p ActiveEnterTimestampMonotonic
journalctl --user -b -o short-monotonic \
  -u enthroned-desktop-actions.service -u plasma-plasmashell.service
```

Esses comandos são roteiro, **não foram executados em VM**. Acrescentar o instante do primeiro uso real do desktop e conservar os dados do primeiro e segundo boot. blame isolado não prova causalidade.

### 8.4 Riscos que permanecem conhecidos

- Canal oficial não configurado, sem prova de assinatura/proveniência de atualização. Atualização real e ciclo real atualizar → reiniciar → rollback ficam fora desta H4 enquanto faltarem esses pré-requisitos e autorização específica.
- Dependência de APIs privadas do Kicker e de versões herdadas de uma base mutável; resolver imports/carga só pode ser encerrado na imagem efetiva.
- Ausência de baseline completo in-VM para separar boot, OOBE, sessão e composição gráfica. O efeito de NP-01 não foi medido.
- Brave depende de provisioning/rede; concorrência e espera entre instalações ainda precisam de evidência. Wrapper de menu sem interface própria de configuração e arraste de widgets diferente do de arquivos são limitações conhecidas.
- Não foi executada build, CTest, QML nativo, plugin, bootloader ou VM. Não há certificação de ausência de outros defeitos, nem aprovação de produção. A próxima decisão deve partir das correções dos bloqueadores e das evidências acima, sem abrir outro lote automaticamente.

**Entrega:** diagnóstico independente concluído; produção e testes preservados. **Estado do gate: NO-GO.**
