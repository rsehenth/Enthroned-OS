# F2.1 — Desktop Experience Refinement: estado da fase

- **Data do registro:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11
- **Fonte do escopo:** prompt mestre F2.1 (fornecido na sessão)
- **Base alvo de API:** KDE Plasma 6.6 (Aurora stable / Fedora 44). **Todos os
  contratos usados nesta fase foram verificados diretamente no código-fonte
  oficial do branch `Plasma/6.6`** (plasma-workspace, plasma-desktop) — lista
  completa na seção "Fontes oficiais consultadas".

## Objetivos da fase

Transformar a camada visual da F2 em uma experiência desktop própria:
menu Iniciar distinto (launcher Enthroned nativo), perfis Classic/Modern
realmente diferenciados, Lixeira na área de trabalho, Dolphin refinado,
infraestrutura real de troca de perfil e validação estática estendida —
sem builds, sem KDE executável, sem tocar no host.

## Estados de conclusão (definições separadas)

| Estado | Valor | Evidência |
| --- | --- | --- |
| F2.1 IMPLEMENTED | **ATINGIDO** | Launcher plasmoid, layouts, perfil-tool, dolphinrc, validador — todos existem em código |
| F2.1 STATIC VERIFIED | **ATINGIDO** | `scripts/validate-desktop.sh`: **116/116 PASS** (74 herdados + 42 novos); `verify-source.sh` 14 PASS / 2 WARN / 0 FAIL (baseline F1 intacto); `bash -n` em todos os scripts bash (validador, enthroned-profile, enthroned-identity, build.sh); `node --check` wallpapers |
| F2.1 RUNTIME VERIFIED | **NOT RUN** | Nenhum Plasma executável no ambiente (Windows host) |
| F2.1 INTEGRATED BUILD VERIFIED | **NOT RUN** | Nenhum build OCI (bloqueio herdado F1: podman/just ausentes) |
| F2.1 BOOT VERIFIED | **NOT RUN** | Depende da imagem + VM |

**Nenhuma funcionalidade simulada é declarada operacional.** O launcher é
STATIC VERIFIED: os contratos QML/C++ que ele usa foram conferidos linha a
linha no código oficial do Plasma 6.6, mas a UI nunca foi carregada num
plasmashell real.

## 1. Enthroned Launcher (menu Iniciar próprio)

**Componente principal da fase.** Novo plasmoid nativo Qt/QML:

`system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/`

- `metadata.json` — KPackage `Plasma/Applet`, `Category: Application
  Launchers`, `X-Plasma-Provides: ["org.kde.plasma.launchermenu"]` → o
  Plasma oferece o kickoff como alternativa nativa ao nosso launcher
  (botão direito → "Mostrar alternativas") e vice-versa.
- `contents/ui/main.qml` — `PlasmoidItem` com os **mesmos modelos do
  Application Launcher oficial** (kickoff), via módulo
  `org.kde.plasma.private.kicker` (C++, plasma-workspace):
  - `Kicker.RootModel` — listagem real de aplicativos e categorias
    (KServiceGroup/KSycoca), favoritos **por instância e persistentes**
    (KAStats, `favoritesModel.initForClient(...)` + port única de
    `favorites` do config via `portOldFavorites` — mecanismo idêntico ao
    kickoff).
  - `Kicker.RunnerModel` — busca KRunner (aplicativos, arquivos,
    configurações…), `mergeResults: true`.
  - `Kicker.SystemModel` — comandos de sessão oficiais (bloquear,
    encerrar sessão, suspender, hibernar, reiniciar, desligar) via
    `trigger(row, actionId, argument)` — a mesma API que o kickoff usa.
- `contents/ui/FullRepresentation.qml` — popup:
  busca destacada no topo (Windows 11), **barra lateral de categorias**
  (Zorin: Favoritos / Todos os aplicativos / categorias reais), lista de
  aplicativos com seções por grupo na busca, rodapé com **avatar do
  usuário** (kcm_users) e botão de sessão/energia. Sem cores fixas — toda a
  paleta vem do esquema Enthroned Light/Dark ativo.
- `contents/ui/AppListDelegate.qml` — item (ícone + nome + nome genérico),
  abertura por `model.trigger(index, "", null)` (contrato oficial
  `AbstractModel`), navegação por teclado (Enter/Return, setas nativas).
- `contents/ui/CompactRepresentation.qml` — botão quadrado do painel
  (ícone `org.enthroned.launcher`), Accessible.Button, clique alterna o popup.
- `contents/config/main.xml` — chaves `icon` (padrão Enthroned),
  `favorites` (curados: navegador padrão, Dolphin, terminal, Configurações,
  Discover) e `favoritesPortedToKAstats`.

**Diferenciação real em relação ao kickoff:** barra lateral de categorias
sempre visível (Zorin), busca em destaque no topo, rodapé com usuário +
energia (Windows 11), identidade Enthroned; **base técnica 100% nativa** —
nenhum modelo duplicado em JS, nenhum serviço novo, custo equivalente ao
kickoff (mesmos modelos C++).

**Fallback preservado:** o layout script dos dois perfis tenta
`panel.addWidget("org.enthroned.launcher")` (try/catch + checagem de
`Error`); se o plasmoid não puder ser criado, aplica o kickoff nativo com
ícone Enthroned e favoritos curados — exatamente como a F2 fazia. O
kickoff também continua disponível a um clique ("Alternativas").

**Pendências registradas (não implementadas nesta fase):** menus de
contexto dos itens (fixar/desafixar pela UI), arrastar-e-soltar de itens
para o painel, reordenação de favoritos por arrasto, KCM de configuração
própria. O kickoff permanece instalado e cobre esses fluxos se o usuário
optar por ele.

## 2. Layouts dos perfis (Classic / Modern)

`org.enthroned.classic` e `org.enthroned.modern` — `contents/layouts/`:

| | **Classic** | **Modern** |
| --- | --- | --- |
| Painel | inferior, 40 px (F4+: 44 px), `floating=false`, `hiding="none"`, **`opacity="opaque"`** | inferior, 44 px (F4+: 48 px), `floating=true`, `hiding="none"` |
| Menu | Enthroned Launcher à esquerda + taskbar | Enthroned Launcher + taskbar **centralizados** (panelspacers), bandeja/relógio à direita |
| Relógio | `showDate=true` (data + hora) | `showDate=false` (só hora, Windows 11) |
| Área de trabalho | wallpaper Enthroned + **Lixeira** | wallpaper Enthroned Nocturne + **Lixeira** |

Propriedades de painel **comprovas na fonte** (`shell/scripting/panel.cpp`
do Plasma 6.6): `floating`, `hiding`, `opacity`, `alignment`, `height`,
`lengthMode`, `offset`, `minimumLength`, `maximumLength`. A ressalva da F2
sobre `floating`/`hiding` ficou **resolvida**: fazem parte da API oficial
de scripting (o aviso de homologação permanece para a execução real).

## 3. Área de trabalho

- Folder View nativo mantido (ícones, criar/renomear, arrastar-e-soltar,
  menu contextual, persistência — comportamento upstream).
- **Lixeira na área de trabalho**: widget nativo `org.kde.plasma.trash`
  adicionado pelo layout script via `containment.addWidget(...)` —
  contrato verificado em `shell/scripting/containment.cpp`; removível
  pelo usuário (reversível). Nenhum atalho fictício foi criado; a pasta
  Desktop de usuários existentes nunca é tocada.

## 4. Dolphin (Enthroned File Experience)

`usr/etc/xdg/dolphinrc` ganhou `OpenExternallyCalledFolderInNewTab=true`
(pastas abertas por outros aplicativos abrem como aba — navegação por abas
tipo Explorer). Chaves da F2 mantidas (`ShowFullPath`,
`ShowFullPathInTitlebar`, `GlobalViewProps`, `ShowCopyMoveMenu`,
`ShowZoomSlider`). Sem fork, sem reimplementação; confirmações destrutivas
intactas; `~/.config` do usuário sempre vence (`/usr/etc` é camada de
default).

## 5. Personalização de perfil (infraestrutura real, sem UI falsa)

Novo utilitário `usr/bin/enthroned-profile` (bash, sem root, sem daemon):

```
enthroned-profile status     # perfil ativo + alvo de restore
enthroned-profile list       # look-and-feels instalados (* = ativo)
enthroned-profile apply classic|modern
enthroned-profile restore    # re-aplica o look-and-feel anterior
```

- Aplica via **mecanismo oficial** (`plasma-apply-lookandfeel -a`).
- Registra o look-and-feel anterior em
  `$XDG_STATE_HOME/enthroned-os/previous-lookandfeel` e restaura no
  `restore` (um passo; não promete reversão de preferências individuais —
  o mecanismo KDE não garante isso).
- Sem `sudo`; validado sintaticamente e pelo verificador estático.
- A interface gráfica continua sendo a nativa (System Settings → Colors &
  Themes → Look and Feel lista os dois perfis). Uma UI gráfica própria foi
  considerada **não segura para implementação sem execução** e fica como
  extensão da F3.

## 6. Verificações executadas nesta sessão

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-desktop.sh` (116 checagens) | **PASS 116/116** (exit 0) |
| `bash scripts/verify-source.sh` (regressão F1) | PASS 14 / WARN 2 / FAIL 0 — baseline intacto |
| `bash -n scripts/validate-desktop.sh` | PASS |
| `bash -n system_files/usr/bin/enthroned-profile` | PASS |
| `bash -n system_files/usr/bin/enthroned-identity` | PASS (não modificado) |
| `bash -n build_files/build.sh` | PASS (uma linha adicionada: chmod do enthroned-profile) |
| `node --check scripts/enthroned-wallpapers.js` | PASS (não modificado) |

Novas checagens do validador (42, todas PASS): metadados do plasmoid
(KPackageStructure, Id=dir, categoria, `X-Plasma-Provides`,
API-min, ícone existente), QML balanceado e **sem cores fixas** nos 4
arquivos, uso dos modelos kicker (RootModel/RunnerModel/SystemModel),
favoritos por instância + port única, config main.xml (grupo/entradas/
defaults resolvíveis), launcher com fallback kickoff nos 2 layouts,
Lixeira na área de trabalho nos 2 layouts, diferenciação real dos perfis
(floating/opaque/showDate), dolphinrc com nova chave, `enthroned-profile`
(usa mecanismo oficial, referencia os dois perfis, registra restore, sem
sudo), higiene estendida a `.xml`.

## 7. Bloqueios e limitações

1. **Runtime:** nenhum componente foi carregado em Plasma real. O launcher
   é STATIC VERIFIED; a homologação em VM deve abrir o menu, buscar,
   alternar categorias, abrir um app, testar energia e o fallback.
2. **API interna `org.kde.plasma.private.kicker`:** módulo C++ do próprio
   plasma-workspace, usado exatamente como o kickoff o usa (mesmos tipos,
   mesmos papéis, mesma chamada `trigger`). Risco aceito e isolado: se o
   módulo mudar upstream, o kickoff do sistema continua funcionando e o
   fallback do layout script mantém o menu operável.
3. **Sem menus de contexto / drag-and-drop no launcher v1** — pendência
   explícita; kickoff disponível como alternativa nativa.
4. **Dependência kirigami-addons** (`AvatarButton`): o kickoff oficial usa o
   mesmo módulo no Plasma 6.6, logo o pacote está presente na base Aurora;
   se ausente em alguma imagem derivada, a importação falha apenas no
   popup do launcher (fallback kickoff cobre o fluxo).
5. context-mode (MCP) permaneceu indisponível (conforme F1/F2); pesquisa
   feita por fetch direto das fontes oficiais.

## Fontes oficiais consultadas (branch Plasma/6.6, 2026-11-16)

- `plasma-desktop/applets/kickoff/` — `main.qml`, `FullRepresentation.qml`,
  `Header.qml`, `Footer.qml`, `LeaveButtons.qml`, `ApplicationsPage.qml`,
  `PlacesPage.qml`, `KickoffListView.qml`, `KickoffListDelegate.qml`,
  `AbstractKickoffItemDelegate.qml`, `KickoffSingleton.qml`, `metadata.json`,
  `main.xml`, `CMakeLists.txt` (`plasma_add_applet(org.kde.plasma.kickoff)`).
- `plasma-workspace/applets/kicker/` — `CMakeLists.txt`
  (`ecm_add_qml_module(... URI "org.kde.plasma.private.kicker" VERSION 0.1)`),
  `appsmodel.{h,cpp}`, `rootmodel.{h,cpp}`, `runnermodel.h`,
  `systemmodel.h`, `systementry.h`, `appentry.cpp`, `computermodel.cpp`,
  `processrunner.h`, `actionlist.h`.
- `plasma-workspace/shell/scripting/panel.cpp` — propriedades de painel
  (`floating`, `hiding`, `opacity`, `alignment`, `height`, `lengthMode`).
- `plasma-workspace/shell/scripting/containment.cpp` —
  `Containment::addWidget` (widget na área de trabalho).
- `plasma-desktop/applets/trash/` — id instalado `org.kde.plasma.trash`.
- `plasma-desktop/applets/icontasks/metadata.json` — formato canônico de
  metadata de applet (`KPackageStructure: Plasma/Applet`,
  `X-Plasma-Provides`).

## Próxima ação mínima

Homologação em ambiente Linux (VM QCOW2 da imagem construída):
primeiro login (Classic + Enthroned Launcher), busca, categorias, abertura
de app, menu de energia, Meta no teclado, Lixeira na área de trabalho,
troca para Modern via `enthroned-profile apply modern` (ou System
Settings), `enthroned-profile restore`, fallback forçado do launcher
(p.ex. renomear o diretório do plasmoid num deploy de teste) — preenchendo
RUNTIME VERIFIED / INTEGRATED BUILD VERIFIED.
