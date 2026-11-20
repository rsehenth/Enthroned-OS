# Arquitetura da camada desktop do Enthroned OS

- **Data:** 2026-11-16 (F2; atualizado em F2.1)
- **Plataforma:** KDE Plasma 6.6+ sobre Aurora Stable (Fedora, bootc/OCI)
- **Princípio:** usar exclusivamente os mecanismos nativos do Plasma
  (look-and-feel, layout scripts, widgets, KConfig, modelos kicker). Nenhum
  serviço residente, nenhum fork de componente upstream, nenhuma dependência
  nova.

## 1. Camadas

```
ENTHRONED OS
|
+-- Enthroned Desktop Experience        (esta camada — 100% declarativa/config)
|   |
|   +-- Visual Identity                 .colors + SVGs + wallpapers + tokens
|   +-- Launcher / Taskbar              widgets nativos configurados via layout script
|   +-- Desktop Layout                  Folder View nativo (ícones na área de trabalho)
|   +-- File Experience                 /etc/xdg/dolphinrc (defaults de sistema)
|   +-- Appearance Profiles             look-and-feel Classic e Modern
|
+-- KDE Plasma / KWin                   (intocado)
+-- Aurora Stable                       (intocado)
+-- Fedora Linux
```

A camada Enthroned **não contém executáveis nem daemons**: são pacotes de
dados (KPackage), arquivos KConfig e um script de layout JavaScript executado
pelo próprio plasmashell no primeiro login.

## 2. Inventário de componentes → mecanismos KDE

| Componente Enthroned | Mecanismo nativo | Arquivos | API verificada em |
| --- | --- | --- | --- |
| Esquemas de cores | Color Schemes (KConfig) | `usr/share/color-schemes/Enthroned{Light,Dark}.colors` | `breeze/colors/BreezeLight.colors` (Plasma 6.6) |
| Identidade gráfica | Icon Loader (hicolor) | `usr/share/icons/hicolor/<N>x<N>/apps/org.enthroned.*.png` (derivados de `assets/`) | — |
| Papéis de parede | Wallpaper package (`org.kde.image`) | `usr/share/wallpapers/Enthroned{Soberania,Ascensao,Vigilia}/` (Lote 13) | `breeze/wallpapers/Next/metadata.json` |
| Perfis de aparência | Look-and-feel KPackage | `usr/share/plasma/look-and-feel/org.enthroned.{classic,modern}/` | `plasma-workspace/lookandfeel/org.kde.breeze/` |
| **Menu Iniciar (F2.1)** | **Plasmoid próprio `org.enthroned.launcher` sobre os modelos C++ do kicker (`org.kde.plasma.private.kicker`)** | `usr/share/plasma/plasmoids/org.enthroned.launcher/` | `plasma-desktop/applets/kickoff/*` + `plasma-workspace/applets/kicker/{appsmodel.h,rootmodel.h,runnermodel.h,systemmodel.h}` (Plasma/6.6) |
| Barra de tarefas | `org.kde.plasma.icontasks` + `panelspacer` | configuração no layout script | `defaultPanel layout.js` + `applets/CMakeLists.txt` |
| Bandeja/relógio | `org.kde.plasma.systemtray` + `org.kde.plasma.digitalclock` | configuração no layout script | `plasma-workspace/applets/digital-clock/main.xml` |
| Ícones na área de trabalho | Folder View (containment padrão do Plasma 6) | nenhum (comportamento nativo mantido) | comportamento padrão upstream |
| **Lixeira na área de trabalho (F2.1)** | widget nativo `org.kde.plasma.trash` via `containment.addWidget` no layout script | no layout script dos dois perfis | `plasma-workspace/shell/scripting/containment.cpp` (Plasma/6.6) |
| Propriedades do painel | Desktop scripting (`floating`, `hiding`, `opacity`, `alignment`, `height`) | layout scripts | `plasma-workspace/shell/scripting/panel.cpp` (Plasma/6.6) |
| Explorador de arquivos | Dolphin via `/etc/xdg/dolphinrc` | `usr/etc/xdg/dolphinrc` | contrato XDG + bootc `/usr/etc` |
| Splash screen | Splash do look-and-feel | `.../contents/splash/Splash.qml` + imagens | `org.kde.breeze/contents/splash/Splash.qml` |
| **Troca de perfil (F2.1)** | `plasma-apply-lookandfeel` (oficial) via CLI `enthroned-profile` | `usr/bin/enthroned-profile` | ferramenta oficial do Plasma 6 |
| Tokens de design | documento único | `usr/share/enthroned-os/branding/design-tokens.json` | — |

## 3. Fluxo de primeiro boot (usuário novo)

1. `/usr/etc/xdg/kdeglobals` (mesclado para `/etc/xdg/kdeglobals` pelo bootc)
   define `LookAndFeelPackage=org.enthroned.classic` e
   `ColorScheme=EnthronedLight` — camada de default de sistema; qualquer
   `~/.config/kdeglobals` do usuário vence.
2. O plasmashell, ao criar a sessão de um usuário sem configuração, aplica o
   look-and-feel apontado: mescla `contents/defaults` (cores, ícones, cursor,
   tema Plasma, decorações de janela, wallpaper, **clique duplo** via
   `kcminputrc`) e executa o layout script de `contents/layouts/`.
3. O layout script cria o painel inferior com o **Enthroned Launcher**
   (atalho Meta) e o icontasks (fixados); se o plasmoid não puder ser
   instanciado, o layout aplica o kickoff nativo com o mesmo ícone e
   favoritos curados (fallback automático).
4. O desktop permanece no Folder View padrão (ícones, arrastar-e-soltar,
   menu contextual de criação/renomeação — nativos) e recebe o widget
   nativo da Lixeira (`org.kde.plasma.trash`).

Usuários **existentes** não são tocados: nada é escrito em `$HOME`, e o
look-and-feel só é aplicado a quem ainda não tem configuração (ou que optar
explicitamente, ver §6).

## 4. Perfis

| | **Enthroned Classic** | **Enthroned Modern** |
| --- | --- | --- |
| Referência | Zorin OS (calmo, organizado) | Windows 11 (familiar, moderno) |
| Cores | Enthroned Light | Enthroned Dark |
| Papel de parede | Enthroned — Vigília (padrão; os três oficiais ficam à escolha do usuário) | idem |
| Painel | inferior, 44 px (F4+; era 40), sólido (`floating=false`, `opacity=opaque`), menu à esquerda, relógio com data | inferior, 48 px (F4+; era 44), flutuante, menu+tarefas centralizados, bandeja à direita, relógio só com hora |
| Área de trabalho | wallpaper + Lixeira (`org.kde.plasma.trash`) | wallpaper + Lixeira (`org.kde.plasma.trash`) |
| Splash | fundo claro | fundo escuro |
| ID | `org.enthroned.classic` | `org.enthroned.modern` |

Ambos compartilham a mesma base: mesmos widgets (incluindo o Enthroned
Launcher), mesmo formato de layout script, mesmos tokens de marca; diferem
apenas nos valores declarados (verificados por checagens estáticas).

## 5. Decisões técnicas relevantes (ADRs informais)

1. **Menu Iniciar = plasmoid próprio sobre os modelos oficiais do kicker
   (F2.1).** O `org.enthroned.launcher` usa o módulo C++
   `org.kde.plasma.private.kicker` — o mesmo `RootModel`/`RunnerModel`/
   `SystemModel` do Application Launcher oficial — com UI própria
   (barra lateral de categorias, busca em destaque, rodapé de usuário e
   energia). Sem duplicação de modelos em JavaScript, sem polling, sem
   serviços. Os contratos foram conferidos linha a linha no código do
   Plasma/6.6 (`plasma-desktop/applets/kickoff/*` e
   `plasma-workspace/applets/kicker/*`): Papéis de dados
   (`display`, `decoration`, `description`, `group`, `favoriteId`...),
   `favoritesModel.initForClient(...)` + `portOldFavorites` (favoritos
   persistentes por instância), ordem de linhas do RootModel
   (0 = Favoritos, 1 = Todos os aplicativos, 2+ = categorias),
   `AbstractModel.trigger(row, actionId, argument)` para abrir aplicativos
   e executar ações de sessão. **Risco aceito e isolado:** é um módulo
   `private` (sem garantia de estabilidade entre versões maiores do
   Plasma); mitigação — o layout script tem fallback automático para o
   kickoff nativo e o `X-Plasma-Provides: org.kde.plasma.launchermenu`
   mantém os dois como alternativas oficiais entre si.
2. **Layout por script de look-and-feel, não por appletsrc cru.** É o
   mecanismo usado pelo próprio Breeze (`contents/layouts/` + API de
   scripting), tolerante a múltiplas telas (`desktopsForActivity`) e sem IDs
   frágeis de containment. Propriedades de painel usadas (`floating`,
   `hiding`, `opacity`) estão na API oficial de scripting (verificadas em
   `shell/scripting/panel.cpp`, Plasma/6.6).
3. **Defaults de sistema via `/usr/etc/xdg`.** No bootc, `/usr/etc` é
   mesclado em `/etc` no deploy; `XDG_CONFIG_DIRS` inclui `/etc/xdg`. Isso dá
   uma camada de default que o usuário sempre pode sobrepor — sem tocar em
   `$HOME` e sem scripts de primeira-execução.
4. **Sem tema de ícones completo.** Herdar Breeze mantém a imagem leve e
   consistente; os 3 SVGs Enthroned cobrem os pontos de marca (menu, logo,
   splash).
5. **Sem serviços/daemons.** Nenhum processo residente foi adicionado; toda
   a personalização é estática (KConfig) ou executada pelo plasmashell uma
   vez no primeiro login. O `enthroned-profile` é uma ferramenta sob
   demanda (chamada pelo usuário), não um daemon.
6. **Lixeira na área de trabalho = widget nativo, não hack.** O layout
   script adiciona `org.kde.plasma.trash` ao containment via
   `Containment::addWidget` (API oficial, `shell/scripting/containment.cpp`);
   removível pelo usuário.

## 5.1 Desempenho (diretrizes F2.8/F2.1.9 aplicadas)

- Widgets nativos + o Enthroned Launcher, que **reaproveita os modelos C++
  do kicker** (os mesmos do kickoff) — sem duplicação de modelos, sem
  polling, sem engines web, sem serviços residentes; a busca roda apenas
  enquanto há texto na consulta (mesmo perfil de custo do kickoff).
- Nenhuma animação/efeito customizado além das transições padrão dos
  componentes; splash usa o padrão Breeze (fade + giro leve, interrompido
  se animações estiverem desativadas).
- Wallpapers em PNG otimizado (65–186 KB) — custo de memória comparável ao
  wallpaper padrão do upstream.
- Números de consumo **não são afirmados** (nada medido); critérios de
  medição futura: RSS do plasmashell/kwin com `smem`/`ps` em VM QCOW2 da F3,
  comparando Classic × Modern × Breeze padrão.

## 5.2 Acessibilidade e idiomas

- Textos próprios do launcher em português do Brasil como língua de
  referência, escritos via `i18n()` (prontos para catálogo de tradução
  próprio na F3); nomes de produtos ("Enthroned OS") não são traduzíveis.
  Todos os demais textos vêm dos widgets nativos, já traduzidos pelo KDE
  (incluindo pt_BR).
- Contraste das paletas revisado estaticamente para AA em texto normal
  (tokens em `design-tokens.json`); foco/hover/ativo/desabilitado usam os
  papéis nativos `DecorationFocus/DecorationHover/Selection/ColorEffects:Disabled`
  — o launcher não fixa cores (checagem estática dedicada).
- Navegação por teclado: Meta abre o menu; busca focada ao abrir; setas
  navegam nas listas; Enter abre o item selecionado; papéis e nomes
  Accessible definidos nos delegates/botões; escala de DPI continua nativa
  (`Kirigami.Units`).

## 6. Pontos de integração F3/F4

- **F3 (implementada):** a Central de Configurações/Atualizações ficou como
  **aplicação autônoma** Qt Quick/Kirigami (`settings/`, ADR-0005), não como
  plasmoid — esta camada F2 permanece intocada. A Aparência do app reutiliza
  o `enthroned-profile`; a nota abaixo sobre "plasmoid" foi a sugestão
  original da F2, superada pela decisão registrada no ADR-0005.
- **F4 (Brave/ArtCraft):** os favoritos usam `preferred://browser` e
  `preferred://filemanager`, que resolvem dinamicamente para o aplicativo
  padrão instalado — quando o Brave for o navegador padrão, o menu e a
  barra passam a exibi-lo automaticamente, sem alterar esta camada. A suíte
  ArtCraft entra como `.desktop` em `/usr/share/applications`; nada aqui
  anuncia aplicativos inexistentes.

## 7. O que esta arquitetura NÃO faz (escopo F2/F2.1)

- Não substitui KWin, Dolphin ou o gerenciador de janelas; o menu Iniciar
  é um plasmoid próprio, mas construído sobre os modelos oficiais do
  Plasma (sem fork de UI upstream, sem menu de contexto por item na v1).
- Não cria tema de ícones completo, tema Plasma (`plasmarc`) próprio ou
  tema de decoração de janela — usa Breeze (upstream) com nossa paleta.
- Não altera o comportamento de sessão/energia além dos pontos oficiais
  (`SystemModel`, `plasma-apply-lookandfeel`).
- Não gerencia o wallpaper do gerenciador de login (Plasma Login) — pendência
  documentada.
