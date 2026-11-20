# Lote 7.1 — Fechamento de UX (2026-11-18)

Status: **SOURCE READY / STATIC VERIFIED**. Nenhuma build, imagem, disco ou VM
foi gerada (contrato do lote). Tudo o que depende de execução está marcado como
RUNTIME PENDING.

Base de evidência: leitura do código-fonte do Plasma 6.6 (branches
`Plasma/6.6` de plasma-workspace, plasma-desktop, libplasma e
plasma-integration, nov/2026 — o containment do desktop e o `desktoppackage`
vivem no plasma-desktop desde o 6.6; o plugin de menu nativo
`containmentactions/contextmenu` vive no plasma-workspace) e dos validadores
estáticos do repositório. O ponto de partida foi o backlog do Lote 7
(`docs/validation/LOTE-7-CORRETIVA-HOMOLOGACAO-3.md`).

## 1. Correções concluídas

| # | Item | Implementação | Arquivos |
| --- | --- | --- | --- |
| 1 | Menu de contexto: "Configurações do Enthroned" | Novo plugin ContainmentActions `org.enthroned.contextmenu` que substitui o binding do botão direito do desktop e **delega o menu inteiro ao plugin nativo** (`org.kde.contextmenu`, instanciado exatamente como `PluginLoader::loadContainmentActions` faz: `KPluginMetaData("plasma/containmentactions/…", AllowEmptyMetaData)` + `KPluginFactory::instantiatePlugin`, verificado em `libplasma src/plasma/pluginloader.cpp`), apenas **antepondo** a ação "Configurações do Enthroned" (lança `enthroned-settings`, com fallback para `systemsettings`). Somente API pública estável (`Plasma::ContainmentActions`, `KPluginFactory`); nenhuma linha do Plasma é modificada. Se o plugin nativo faltar (rollback bootc), o menu degrada para a entrada Enthroned e o script do item 2 repara o binding no próximo login | `desktop-actions/` (novo: CMakeLists.txt, src/enthronedcontextmenu.cpp, src/org.enthroned.contextmenu.json); `Containerfile` |
| 2 | Menu de contexto: binding + limpeza de separadores desde a **1ª sessão** (correção desta rodada) | Causa-raiz do atraso para a 2ª sessão encontrada no código 6.6: os bindings de ação são chaveados por **tipo** de containment — `Containment::restore` e `ContainmentPrivate::containmentActionsConfig()` leem/escrevem `[ActionPlugins][0]` (0 = Desktop) no appletsrc, no momento em que **cada** containment desktop é criado, inclusive o que o layout padrão cria no 1º login; e os toggles de item (`_sep*`) lidos por `ContextMenu::restore` ficam no subgrupo `[ActionPlugins][0][RightButton;NoModifier]`. O script anterior gravava os separadores em `[Containments][<id>][ContainmentActions]` — grupo **não lido** pelo Plasma 6.6 — e por isso a limpeza dependia de ids que só existiam após a 1ª sessão. Correção: o serviço de usuário (`Before=plasma-plasmashell.service`, `WantedBy=plasma-core.target`) grava, por **tipo** e sem sobrescrever valor existente: (a) `RightButton;NoModifier=org.enthroned.contextmenu`; (b) `MiddleButton;NoModifier=org.kde.paste` — necessária porque um grupo `[ActionPlugins][0]` existente faz o Plasma **pular** os shell defaults (`desktoppackage/contents/defaults`, `[Desktop][ContainmentActions]`), o que perderia o colar nativo do botão do meio; (c) `_sep1/_sep3/_sep4=false` no subgrupo do trigger. Sem ids, sem segunda sessão, sem condição de corrida (ordem estrita do systemd) | `system_files/usr/lib/systemd/user/enthroned-desktop-actions.service`, `system_files/usr/libexec/enthroned-desktop-actions`; `build_files/build.sh` |
| 3 | Settings como app principal | Os favoritos padrão (launcher, fallback kickoff dos dois temas e `kicker-extra-favoritesrc`) passam a fixar `org.enthroned.settings.desktop` em vez de `systemsettings.desktop`. O System Settings nativo permanece como infraestrutura: o link "Configurações" da coluna Ferramentas mantém o fallback honesto para `systemsettings.desktop`, e o hub abre módulos KDE reais via `kcmshell6` (`KcmLauncher` valida com `--list` antes de abrir — nada é renomeado nem simulado) | `system_files/.../org.enthroned.launcher/contents/config/main.xml`, `system_files/.../org.enthroned.{classic,modern}/contents/layouts/org.kde.plasma.desktop-layout.js`, `system_files/etc/xdg/kicker-extra-favoritesrc` |
| 4 | Validadores | Seção 8.6 em `validate-desktop.sh`: integridade do plugin (fonte, metadata JSON, Id, namespace de instalação, delegação ao menu nativo, fallback, link `KF6::ConfigCore`), unidade systemd (ordem `Before=plasma-plasmashell.service`), script (chaveamento por tipo, preservação do `org.kde.paste`, only-if-missing, auto-reparo para o menu nativo, `exit 0`), integração no Containerfile/build.sh e favoritos apontando para o hub | `scripts/validate-desktop.sh` |

## 2. Lixeira — análise com evidência (nenhuma mudança necessária)

Investigação no Plasma 6.6 confirma que `trash.locked = true` (Lote 7) é a
implementação correta e completa; **não** impede a movimentação:

- **locked → UserImmutable**: `WorkspaceScripting::Applet::setLocked`
  (plasma-workspace `shell/scripting/applet.cpp`) grava
  `setImmutability(UserImmutable)` e persiste `immutability` na config do
  applet — a proteção sobrevive a reinícios.
- **Remoção impedida em todas as vias**: `AppletPrivate::askDestroy`
  (libplasma `src/plasma/private/applet_p.cpp`: "if (q->immutability() !=
  Types::Mutable …) return;") recusa qualquer applet com
  `immutability() != Mutable`; no menu de contexto do widget,
  "Remove this Widget" e "Widget Settings" ficam invisíveis/desabilitados
  (`Applet::constraintsEvent`, evento `ImmutableConstraint`) e o botão
  "Alternativas" nem é criado para applets não-Mutable.
- **Arrastar sem modo de edição**: o caminho de arraste
  (`ContainmentLayoutManager::ItemContainer`, plasma-workspace
  `components/containmentlayoutmanager`) **não consulta a imutabilidade do
  applet** — o `Locked` vem da imutabilidade do *containment*
  (`Plasmoid.immutable`), que no Enthroned é Mutable. No desktop
  (`org.kde.plasma.folder`, plasma-desktop 6.6) os widgets movem-se com o
  comportamento nativo *segurar e arrastar* (`AfterPressAndHold`), sem o modo
  de edição global; a posição persiste na config do *containment*
  (`ItemGeometries-<resolução>`), que a trava da Lixeira não afeta.
- **Abrir/Esvaziar preservados**: as ações do próprio applet
  (`contextualActions()`) são adicionadas incondicionalmente ao menu
  (`ContainmentItem::addAppletActions`).

**RUNTIME PENDING (cosmético, upstream)**: ao segurar a Lixeira, o overlay
per-item (`plasma-desktop 6.6`, `containments/desktop/package/contents/ui/
ConfigOverlay.qml`, botão `closeButton` "Remove") força
`internalAction("remove").enabled = true` em `Component.onCompleted` — a
visibilidade do botão depende **apenas** dessa ação interna existir e estar
habilitada; não há chave de configuração, hook público ou mecanismo de
extensão para ocultá-lo sem patch no arquivo QML do próprio Plasma (o que
violaria o contrato de não modificar fontes do Plasma e não sobreviveria a
atualizações). O clique é um no-op silencioso (`askDestroy` recusa; a
animação de escala roda e o widget permanece). Registrar na homologação para
não ser confundido com falha do requisito.

## 3. Arrastar ícones "como no Windows" — verificado no código 6.6

| Alvo | Comportamento no Plasma 6.6 | Equivalente ao Windows? |
| --- | --- | --- |
| Ícones do desktop (pastas, arquivos, atalhos `.desktop` renderizados pelo Folder View) | **Arraste direto com o botão esquerdo**: `isDrag` (`containments/desktop/package/contents/ui/main.qml`) inicia o arraste assim que o movimento excede `QGuiApplication::styleHints()->startDragDistance()`, sem espera e sem modo de edição. Posições livres garantidas por `sortMode 0` + `locked false` (já no layout Enthroned) | Sim — nativo |
| Widgets do desktop (Lixeira, atalhos como widgets) | **Segurar-e-arrastar**: `editModeCondition` fixado em QML como `AfterPressAndHold` (`desktoppackage/contents/ui/main.qml`, linhas do `AppletsLayout` e do `BasicAppletContainer`) — o modo de arraste do item abre após `mousePressAndHoldInterval()` do Qt (≈500 ms, padrão; o plasma-integration 6.6 **não** expõe esse hint em `kdeglobals`) ou arraste pela alça do overlay; também move no Modo de Edição | Não — diferença inerente |
| Mecanismo alternativo | O enum `ItemContainer::EditModeCondition` inclui `AfterPress` (arraste imediato sem espera), mas o desktop package **não o expõe por configuração** — mudar exigiria patch no QML upstream | Indisponível sem patch |

Diferenças inevitáveis vs Windows, para documentar na homologação:

1. Widget (Lixeira/atalhos como widget) exige segurar ~0,5 s antes de
   arrastar; no Windows é arraste imediato.
2. Clicar uma vez em um widget não seleciona/move; o overlay só aparece
   após a espera (ou no Modo de Edição).
3. Ícones de arquivos/pastas no desktop são arrastáveis imediatamente
   (paridade com Windows).

Nenhuma camada própria de drag-and-drop foi implementada (contrato do lote).

## 4. Integração do Settings — pontos revisados

| Ponto de entrada | Estado |
| --- | --- |
| Menu Iniciar (coluna Ferramentas) | OK desde o Lote 7 (`org.enthroned.settings.desktop` com fallback) |
| Menu Iniciar (favoritos padrão) | Corrigido neste lote (item 3 da tabela) |
| Atalhos | Nenhum atalho global apresenta o System Settings no repositório; nada a corrigir. O Meta abre o launcher, que expõe o hub |
| Configuração da área de trabalho | O diálogo "Configure Desktop and Wallpaper" é o `ContainmentConfigView` do próprio plasmashell (infraestrutura nativa, não renomeável por config). Intocado de propósito |
| Personalização | `PersonalizationController` do hub opera só com esquemas/papéis Enthroned (`plasma-apply-colorscheme`), sem strings Aurora |
| Abertura dos módulos KDE | Preservada: `kcmshell6` validado por `--list` (mesmo mecanismo dos lotes anteriores); `kcm_ublue` segue NoDisplay com nome blindado (Lote 6/7) |

## 5. Plugin `org.enthroned.contextmenu` — revisão de compilação (item 4 da missão)

Verificado por inspeção contra as fontes reais do Plasma 6.6 (branches
`Plasma/6.6`):

- **API**: construtor protegido `ContainmentActions(QObject*, const
  QVariantList&)`, virtuais `restore(const KConfigGroup&)`, `save(KConfigGroup&)`,
  `contextualActions()`, `performNextAction()/performPreviousAction()` e o
  `setContainment()` público — exatamente os usados pelo wrapper. `K_PLUGIN_CLASS_WITH_JSON`
  é o mesmo macro do plugin nativo (`containmentactions/contextmenu/menu.cpp`).
  Não há `init()` nem `performAction()` no header 6.6 — nada faltando a delegar.
- **Instanciação do plugin nativo**: idêntica a `PluginLoader::loadContainmentActions`
  (mesmo lookup `plasma/containmentactions/<id>` com `AllowEmptyMetaData` —
  o `.so` nativo não embute Id no metadata; o id é o nome do arquivo).
- **CMake/KF6**: `kcoreaddons_add_plugin(... INSTALL_NAMESPACE "plasma/containmentactions")`
  + `OUTPUT_NAME org.enthroned.contextmenu` — mesmo padrão do exemplo oficial
  `examples/testcontainmentactionsplugin` do libplasma 6.6. Correção desta
  rodada: `KConfigGroup` pertence ao **KF6::ConfigCore**; `Plasma::Plasma` o
  propaga publicamente (build funcionaria), mas a dependência passou a ser
  declarada de forma explícita (`find_package(KF6 … Config)`,
  `KF6::ConfigCore` em `target_link_libraries`; pacote Fedora
  `kf6-kconfig-devel`, puxado por `libplasma-devel`).
- **Pacotes Fedora (Containerfile)**: `gcc-c++`, `cmake`, `ninja-build`,
  `extra-cmake-modules`, `qt6-qtbase-devel` (Qt6Core+Qt6Gui, usados),
  `kf6-kcoreaddons-devel`, `libplasma-devel` — nomes corretos; nenhum pacote
  faltante identificado para o plugin.
- **Metadata**: `KPlugin.Id=org.enthroned.contextmenu`,
  `X-Plasma-HasConfigurationInterface=false` (sem UI de configuração —
  coerente com o wrapper não sobrescrever `createConfigurationInterface`).
- **Instalação**: `<plugindir>/plasma/containmentactions/org.enthroned.contextmenu.so`
  (= `/usr/lib64/qt6/plugins/plasma/containmentactions/` no Fedora), mesmo
  caminho verificado por `plugin_installed()` no script do item 2.
- **Erros/fallback**: plugin nativo ausente → menu degrada à entrada
  Enthroned (`qWarning` registrado) e o script repara o binding na próxima
  sessão; `enthroned-settings` ausente → fallback `systemsettings`; nenhum
  dos dois → ação silenciosamente inerte (sem crash).

**Compilação real continua RUNTIME PENDING** (sem toolchain Qt/KF6 no host
Windows; roda no estágio `apps-builder`). Riscos residuais baixos: (1) tempo
de build da moc/AUTOMOC com classe em namespace anônimo — padrão suportado,
mas só comprovado ao compilar; (2) assinaturas públicas estáveis desde 6.4
(`id()`, `hasConfigurationInterface()`), sem previsão de quebra na 6.6.

## 6. Boot

Nenhuma ação (contrato do lote: aguardar `boot-diagnostico.txt` da VM da
Homologação 3). Nenhum serviço foi desativado. O serviço de usuário é
oneshot, roda antes do plasmashell e sempre sai 0 — não participa da cadeia
de boot do sistema.

## 7. Validações executadas (host, sem build)

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-desktop.sh` | **ALL CHECKS PASSED** (inclui os checks novos da rodada: chaveamento por tipo, `org.kde.paste`, separadores no grupo do menu nativo, `KF6::ConfigCore`) |
| `bash scripts/verify-source.sh` | 15 pass / 1 warn / 0 fail — o warn é ambiental/pré-existente: placeholder do namespace no `iso.toml` (ADR-0002) |
| `bash -n` no `enthroned-desktop-actions` | OK |
| JSON do metadata do plugin | OK (parser do validador; `jq` ausente no host, igual às rodadas anteriores) |
| `validate-settings.sh` / `validate-welcome.sh` | Não reexecutados nesta rodada — nenhum arquivo desses projetos foi tocado |
| Compilação C++ / shellcheck | NOT RUN no host (sem toolchain Qt/KF6 nem shellcheck no Windows; rodam no estágio `apps-builder` e no WSL na próxima build) |
| Referência cruzada dos fontes do Plasma 6.6 | `libplasma` (`containment.cpp`, `containment_p.cpp/h`, `containmentactions.h/cpp`, `corona.cpp`, `pluginloader.cpp`, `applet_p.cpp`, `packagestructure/shell/shellpackage.cpp`), `plasma-workspace` (`shellcorona.cpp`, `currentcontainmentactionsmodel.cpp`, `shell/plasma-plasmashell.service.in`, `startkde/systemd/plasma-core.target`, `containmentactions/contextmenu/`), `plasma-desktop` (`containments/desktop/package/contents/ui/{main,FolderView,ConfigOverlay}.qml`, `desktoppackage/contents/defaults`), `plasma-integration` (`khintssettings.cpp`) |

## 8. Pendente de runtime (próxima build/VM)

1. Menu de contexto **no primeiro login** (sem segunda sessão): confirmar
   visualmente "Configurações do Enthroned" no topo, as três linhas vazias
   sumidas e nenhuma ação nativa perdida — incluindo o **colar do botão do
   meio** no desktop (novo check desta rodada). A lista esperada é:
   Configurações do Enthroned / Editar Modo... / Configurar Área de Trabalho
   e Papel de Parede... / Configurações de Tela.
2. Lixeira: segurar-e-arrastar move o widget sem entrar no modo de edição;
   Esvaziar/Abrir funcionam; o botão "Remove" do overlay (se visível) não
   remove — capturar screenshot do overlay.
3. Arraste de ícones do desktop com um clique-esquerdo e movimento imediato
   (Folder View), e a diferença esperada para widgets (segurar ~0,5 s).
4. Favoritos do launcher mostrando "Configurações do Enthroned" (ícone do hub).
5. O plugin C++ só é exercitável na primeira build (fonte pronta; o
   `apps-builder` compila e instala em `/usr/lib64/qt6/plugins/plasma/
   containmentactions/org.enthroned.contextmenu.so`).

## 9. Restrições técnicas identificadas

- O conjunto de itens do menu de contexto do desktop é fixo em C++
  (`ContextMenu::restore`, plasma-workspace 6.6); config só alterna ids
  existentes — daí o plugin.
- Uma associação (botão;modificador) aceita **um** plugin
  (`PluginLoader::loadContainmentActions` não divide listas) — daí o wrapper
  em vez de um segundo plugin.
- O appletsrc é aberto com `KConfig::SimpleConfig`: `/etc/xdg` **não**
  cascata — a entrega precisa ser no arquivo do usuário, com ordem garantida
  (`Before=plasma-plasmashell.service`). O `kconf_update` (via kded6) corre
  em paralelo ao plasmashell e perderia a corrida — por isso não foi usado.
- Os bindings/toggles vivem em `[ActionPlugins][<tipo>]` (chaveado por tipo
  de containment, não por id): um único grupo cobre todos os desktops, vale
  desde a 1ª sessão e é onde a GUI de Mouse Actions grava
  (`CurrentContainmentActionsModel`). O antigo formato por-containment
  (`[Containments][<id>][ActionPlugins]`) não é lido pelo Plasma 6.6.
- Um grupo `[ActionPlugins][0]` existente desativa os shell defaults do
  `desktoppackage/contents/defaults` — por isso o script preserva
  explicitamente `MiddleButton;NoModifier=org.kde.paste`.
- Se o usuário **remover** por completo um binding pela GUI (em vez de
  trocá-lo), o script volta a gravar o valor no login seguinte (não é
  possível distinguir "removido de propósito" de "nunca configurado" só com
  kreadconfig6). Trocas de plugin pelo usuário são sempre respeitadas.
- `ContainmentActions` não expõe UI de configuração no nosso wrapper — o
  ajuste fino do menu nativo via GUI deixa de estar disponível enquanto o
  wrapper estiver associado (os toggles por arquivo continuam valendo; a GUI
  escreve exatamente nos grupos que o wrapper repassa ao plugin nativo).
- Arraste estilo Windows **para widgets** exigiria patch no
  `desktoppackage` (`AfterPressAndHold` fixado em QML); ícones do Folder View
  já arrastam diretamente. `mousePressAndHoldInterval` não é configurável
  via plasma-integration/kdeglobals.

## 10. Estado do Git

Branch `main`, sem commits (como nas rodadas anteriores — commit só sob
instrução explícita). Novos arquivos: `desktop-actions/` (3),
`system_files/usr/lib/systemd/user/enthroned-desktop-actions.service`,
`system_files/usr/libexec/enthroned-desktop-actions`,
`docs/validation/LOTE-7-1-FECHAMENTO-UX.md`. Modificados: `Containerfile`,
`build_files/build.sh`, `scripts/validate-desktop.sh`, favoritos (4 arquivos)
— e nesta rodada de fechamento: `desktop-actions/CMakeLists.txt`
(`KF6::ConfigCore` explícito), `system_files/usr/libexec/enthroned-desktop-actions`
(bindings por tipo + colar do meio + separadores no grupo correto desde a
1ª sessão), `system_files/usr/lib/systemd/user/enthroned-desktop-actions.service`
(comentários) e `scripts/validate-desktop.sh` (checks atualizados). Nada em
`output/` ou VMs foi tocado.
