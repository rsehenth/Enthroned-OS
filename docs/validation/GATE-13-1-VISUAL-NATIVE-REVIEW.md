# Gate 13.1 — Refinamento visual e validação nativa

19 de novembro de 2026 · America/Sao_Paulo

**Classificação: SOURCE READY / NATIVE BUILD + CTEST VERIFIED / PLASMA REAL NOT RUN.**
O Settings e o Welcome compilam na Aurora fixada e todos os CTests passam. O QML foi renderizado de verdade
(Qt offscreen/xcb em software), mas **nada foi visto no Plasma real**. A preservação do wallpaper **não está homologada**.

Base: `ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`
(Plasma 6.8.3, KWin 6.8.3, Qt 6.11.2, KF6 6.32.0, Kirigami 6.32.0). Ubuntu WSL2 + Podman 5.7 rootful, `--pull=never`,
`--network=host` (o `nft` continua ausente), contêiner descartável `gate131`. Nada foi instalado no Windows.
Não foram gerados H6, OCI, ISO, QCOW2 nem VDI; o VirtualBox não foi iniciado; H5, bootc, polkit e systemd não foram tocados; sem commit nem push.

## 1. Decisões de branding aplicadas
| Item | Decisão | Fonte |
| --- | --- | --- |
| Menu Iniciar Classic | E roxo (mantido) | `E Logo-2` |
| Menu Iniciar Modern | poltrona colorida (mantida) | `Enthroned Throne-2` |
| **Aplicativo Enthroned Settings** | **E oficial** (era a coroa/engrenagem) | `E Logo-2` |
| **Aplicativo Enthroned Welcome** | **trono oficial** (era a coroa sobre a porta) | `Enthroned Throne-2` |
| Páginas institucionais | logotipo completo mantido (`BrandWordmark` no About; wordmark no splash) | inalterado |
| Splash | violeta único Classic/Modern, mantido, sem animações novas | inalterado |
| Wallpapers | Soberania, Ascensão, Vigília mantidos; Vigília é o padrão | inalterado |

- Os ícones são derivados técnicos (corte ao desenho, tela quadrada, Lanczos pré-multiplicado, nitidez leve ≤ 48 px) pela função
  `square_icon` já usada nos ícones do Menu Iniciar. `scripts/gen-brand-assets.py` ganhou `APP_ICONS`; **os originais em `assets/` não foram alterados**.
- Saída: `settings/data/icons/hicolor/<N>x<N>/apps/org.enthroned.settings.png` e `welcome/data/icons/hicolor/…/org.enthroned.welcome.png`,
  N = 16, 22, 24, 32, 48, 64, 128, 256, 512. Os dois SVG antigos foram removidos da fonte (cópias no backup); o CMake de cada
  app agora instala `data/icons/hicolor` (`install(DIRECTORY …)`). `cmake --install` confirmou 9 PNG e 0 SVG por app.
- **Variante escolhida**: as versões coloridas (`-2`). As contornadas (`E Logo`, `Enthroned Throne`) só têm contraste sobre um fundo
  (preto sobre claro ou branco sobre escuro) e não servem como ícone de tema claro e escuro.
- Verificação: todos os tamanhos têm RGBA e cantos transparentes (a 16 px o trono ocupa a célula inteira); o resultado foi inspecionado
  sobre fundo claro e escuro (`docs/evidence/gate13-1-app-icons-16-to-128.png`). Nítidos a partir de 32 px; **a 16 e 22 px o desenho é
  muito ornamentado e perde detalhe** (igual aos ícones do Menu Iniciar). Sem redesenho, é o limite da arte. A integração com o tema de
  ícones KDE (hicolor, nome `org.enthroned.*`) é por nome e **fica pendente de conferência no Plasma real**.

## 2. Melhorias adicionais do Settings
Aplicadas ao QML nativo, sem dependências novas e sem trocar componentes Kirigami. Nenhuma string nova (o catálogo pt_BR não mudou).
- **`components/SettingsPage.qml` (novo)**: base de todas as 13 páginas, com largura de leitura de 56 gridUnits (acompanha fonte e escala).
  Em 1080p os cartões deixam de se esticar por toda a tela; a barra de rolagem fica na borda da janela. A largura é definida uma só vez em `Main.qml`
  (`contentMaxWidth`/`contentInset`).
- **Cabeçalho de página**: ícone + título nível 1, fixo acima da página, alinhado ao conteúdo. A barra global vazia do Kirigami (faixa de ~45 px
  em branco) foi removida (`globalToolBar.style: None`). Antes **nenhuma página mostrava o próprio título**.
- **Sidebar**: separador entre a lista e o controle de modo avançado; o controle passou a ocupar toda a largura; o texto de versão ficou à esquerda, em fonte pequena.
- **Home**: o nome do dispositivo é H2 (o H1 é o cabeçalho); os cartões de Rede e Atualizações têm a mesma altura; mais espaço acima das seções
  (`SectionHeading`).
- **Personalização**: duas colunas a partir de 40 gridUnits (antes 900 px fixos, o que mantinha uma coluna no tamanho padrão da janela); a prévia
  preenche o cartão; os cartões de perfil têm altura igual.
- **Acessibilidade**: `ModuleCard` deixou de usar `opacity: 0.75` para “indisponível” (reduzia o contraste do texto); a nota e o botão desabilitado indicam o estado.
- **Central de Atualizações**: só herdou o cabeçalho e a largura (troca de tipo-base). Nenhuma lógica foi alterada; `run-tests.mjs` continua com 517/517.
- Não foi aplicado: agrupamento da navegação em seções (exigiria entradas separadoras e afetaria a navegação por teclado) nem novas descrições por página (exigiriam strings novas e catálogo).

Princípios usados: `no-slop-ui` (sem efeitos, sombras ou animações novas; cartões e bordas do estilo nativo), `design:design-system` (um componente-base, tokens do esquema de cores)
e `design:accessibility-review` (contraste, foco, alvos). As demais skills citadas (`impeccable`, `design:design-critique`) orientaram a crítica das capturas, não geraram código.

## 3. Política dos wallpapers legados
**Decisão: manter `Enthroned` e `EnthronedNocturne` instalados. Nada foi ocultado, renomeado nem apagado.**
- Nenhum perfil, layout, `defaults`, bloqueio de tela nem login referencia mais esses pacotes (`grep`: só aparecem no `build.sh`, para permissões, e no gerador procedural).
  Eles servem apenas como alvo de preferências antigas (`Image=…/Enthroned/contents/images/…`), que se quebrariam se o pacote sumisse.
- Procurei um modo seguro de tirá-los do seletor. No `libplasma_wallpaper_image.so` do Plasma 6.8.3 não há tratamento reconhecível de `Hidden`/`NoDisplay`
  para pacotes `Wallpaper/Images`, e o experimento com `ImageBackend.wallpaperModel` não pôde rodar (ver §4: sem KWin/plasmashell funcional no contêiner).
  **A ocultação por metadado ficou não verificada e não foi aplicada.**
- Opções para o proprietário: (a) manter como está; (b) acrescentar “(legado)” ao `Name` dos dois pacotes (sem mudar o `Id`; preserva as preferências); (c) remover em uma versão futura,
  depois de migrar as preferências. Recomendação: (b) após confirmar no Plasma real que eles aparecem no seletor.

## 4. Investigação da API do plasmashell (`enthroned-profile`)
**Veredito: NÃO HOMOLOGADO. Foi encontrado e corrigido um defeito real; a API existe na versão aprovada, mas o comportamento em sessão não foi observado.**

**Defeito encontrado (Lote 13)**: o script de snapshot enviado ao `evaluateScript` tinha uma **quebra de linha literal dentro de uma string JavaScript**
(`out += … + "↵"`), um erro de sintaxe (“Invalid or unexpected token”, confirmado com `new Function` no código antigo do backup). O `QJSEngine` rejeitaria o script
inteiro, `wallpaper_snapshot` voltaria vazio e **a restauração nunca escreveria nada** (o wallpaper cairia em Vigília a cada troca de perfil). O mock dos testes
anteriores não executava JS e não podia revelar isso. Correção: `"\n"` escapado. Dois testes novos compilam em JavaScript o snapshot e o script de restauração.

**O que foi confirmado na Aurora (Plasma 6.8.3)**
- O binário do `plasmashell` embute a interface D-Bus com `evaluateScript(s script) → s output` e `loadLookAndFeelDefaultLayout`, e os identificadores
  `readConfig`, `writeConfig`, `reloadConfig`, `wallpaperPlugin`, `currentConfigGroup`, `desktops` e `screen`.
- O `plasma-apply-wallpaperimage` da mesma versão usa exatamente o mesmo modelo (`desktops()`, `d.wallpaperPlugin = 'org.kde.image'`, `d.currentConfigGroup = ['Wallpaper','org.kde.image','General']`, `writeConfig`).
- `qdbus6` não existe na imagem; `qdbus-qt6` existe e já está na lista de busca do script.
- Não há arquivo de ativação D-Bus para `org.kde.plasmashell`, mas o script agora também não depende disso (ver abaixo).

**Endurecimento aplicado (mesmo mecanismo, nenhum outro mais arriscado)**
- Só chama o plasmashell se `NameHasOwner org.kde.plasmashell` for `true` (nunca inicia um plasmashell novo por ativação, por exemplo a partir de um TTY).
- `timeout` (15 s, configurável por `ENTHRONED_PLASMA_TIMEOUT`) em cada chamada: um plasmashell travado não bloqueia a troca.
- O script de restauração imprime quantos desktops escreveu; se for 0 (containments ainda não recriados após `--resetLayout`) repete até 3 vezes. Nunca cria containment ou widget: só escreve em `desktops()` existentes.

| Pergunta do gate | Situação |
| --- | --- |
| Escolha independente por monitor | Código: um par `screen|imagem` por desktop, restauração por `d.screen`. Testado só com mock (2 monitores). **Não observado.** |
| Preservação da configuração | Só imagem única (`org.kde.image`). **Apresentação de slides e cor sólida não são preservadas** (voltam ao padrão do perfil). Limitação registrada. |
| Substituição involuntária por Vigília | Sem escolha prévia vale o padrão do perfil (intencional). Com escolha, depende de `evaluateScript` funcionar em sessão: **não observado**. |
| Segurança das strings | `screen` só numérico; imagem só `file:///…` ou `/…`; recusa `\`, `"` e caracteres de controle; vai como argumento (sem shell). Testado com entradas hostis (aspas, barra invertida, `http://`, tela não numérica). |
| plasmashell não responde | `timeout` + teste com mock travado: volta em < 15 s e o perfil é aplicado. |
| API indisponível | Sem qdbus, ou sem dono do nome: a troca segue e vale o padrão do perfil. Testado. |
| Widgets/containments duplicados | A restauração não cria nada (só `writeConfig` em desktops existentes). **Não observado em sessão.** |

**Tentativa de sessão real (não concluída)**: `plasmashell` em Xvfb (xcb) aborta por falta de tela/KWin; o `kwin_wayland --virtual` não carrega o plugin
de plataforma no contêiner (sem `CAP_SYS_NICE` e com falha de QPA). Sem um compositor, `/PlasmaShell` não é registrado e o `evaluateScript` real não pôde ser chamado.
O comportamento de `d.screen`, `readConfig` com `Image` não escrito e a temporização após `--resetLayout` ficam para o Plasma real.

## 5. Compilação e CTests reais (Aurora fixada)
| Verificação | Resultado |
| --- | --- |
| Settings, CMake/Ninja Release, `BUILD_TESTING=ON` | compilou (com os ícones e o `SettingsPage` novos) |
| `ctest` do Settings | **6/6 passaram** (`appstreamtest`, `settings-close-smoke`, `settings-native-smoke`, `flatpak-lifecycle-smoke`, `bootc-status-smoke`, `update-engine-integration-smoke`) em 6,8 s |
| Welcome, Release | compilou |
| `ctest` do Welcome | **2/2 passaram** (`appstreamtest`, `welcome-native-smoke`) |
| `scripts/validate-settings.sh` | exit 0, **517 / 0** na seção de testes + 359 PASS no total, incluindo os novos checks do conjunto de ícones |
| `scripts/validate-welcome.sh` | exit 0, 212 PASS |
| `scripts/validate-desktop.sh` | exit 0, 390 PASS, “ALL CHECKS PASSED” |
| `node settings/tests/run-tests.mjs` | **517 passaram, 0 falharam** (sem regressão na Central de Atualizações) |
| `scripts/test-update-engine.mjs` | ALL CHECKS PASSED |
| `scripts/test-layouts.mjs` | 6 cenários passaram (API do Plasma **simulada**) |
| `scripts/test-profile-wallpaper-preserve.sh` | **11/11** (6 novos: JS válido ×2, plasmashell ausente, plasmashell travado, escrita vazia, e a regressão do erro de sintaxe) |
| `msgfmt --check` (5 catálogos pt_BR) | exit 0; só os três avisos de cabeçalho já conhecidos (nenhum catálogo foi modificado) |
| Metadados dos wallpapers | 3 pacotes oficiais com `Id`/`Name` corretos |

## 6. Resultados de QML e acessibilidade
- **`qmllint` (alvo `all_qmllint` do CMake)**: nenhum erro. Settings: 4 `missing-property` (`clicked` em `currentItem`, já existentes e fora do que foi alterado), 5 `unused-imports` (já existentes) e
  os avisos `unqualified` de `i18n`/propriedades de contexto (inerentes a esta base). Welcome: apenas `unqualified`. Minha alteração introduziu 2 avisos de `sidePadding`; foram eliminados movendo o valor para `Main.qml`.
- **Renderização real do QML** (Xvfb + backend de software, estilo `org.kde.desktop`, `EnthronedLight/Dark.colors` aplicados, `pt_BR`; **não é o Plasma**; sem decoração de janela nem KWin):
  Home, Personalização e Central de Atualizações em 1920×1080 (escala 1×, 1,5× e 2×) e em janela estreita; Welcome em 1280×800, escala 1×, só para ver o ícone/aplicativo (navegação recolhida em ícones). Sem sobreposição, corte de texto crítico nem barras horizontais.
  Evidência: `docs/evidence/gate13-1-settings-*-qml-offscreen.png`.
- **Contraste** (calculado dos `.colors`, WCAG): texto da sidebar 14,3:1 claro e 15,8:1 escuro; rótulo de versão 6,1 e 7,9:1; texto secundário dos cartões 6,8–7,7:1; “Ativo” 6,6 e 8,6:1; foco 6,3 e 6,6:1;
  barra de seleção 6,9:1 (claro) e 3,65:1 (escuro; passa o mínimo de 3:1 para componentes de interface, e a seleção também usa fundo, negrito e anel de foco).
- **Teclado/leitor de tela**: os papéis e nomes acessíveis existentes foram preservados (lista, itens de menu, botões); o título da página ganhou `Accessible.role: Heading` e o ícone do cabeçalho é ignorado.
  **Navegação por Tab, anel de foco real e leitor de tela não foram exercitados** (xdotool só enviou cliques e teclas simples): pendente no Plasma real.
- Alvos de toque: itens da navegação ≥ 36 px (já existente).

## 7. Arquivos alterados
Backup anterior à etapa: `.backup-gate13-1/` (268 arquivos + `MANIFEST.sha256`; `settings`, `welcome`, `scripts`, `build_files/l10n`, `enthroned-profile`, wallpapers, ícones hicolor, `plasma/`, `docs/operations`).
`.backup-lote13/`, `assets/` e os relatórios anteriores ficaram intactos.
- Settings: `CMakeLists.txt`, `qml/Main.qml`, `qml/components/{SettingsPage (novo),ModuleCard,SectionHeading}.qml`, 13 páginas em `qml/pages/` (tipo-base; Home e Personalização com ajustes visuais), `data/icons/hicolor/**` (9 PNG novos), `data/icons/org.enthroned.settings.svg` removido.
- Welcome: `CMakeLists.txt`, `data/icons/hicolor/**` (9 PNG novos), `data/icons/org.enthroned.welcome.svg` removido.
- `system_files/usr/bin/enthroned-profile` (snapshot corrigido, guarda de nome, timeout, nova tentativa).
- `scripts/gen-brand-assets.py`, `scripts/test-profile-wallpaper-preserve.sh`, `scripts/validate-settings.sh`, `scripts/validate-welcome.sh`.
- Documentação: `docs/operations/{NEXT-HOMOLOGATION §7,DESKTOP-INTEGRATION,WELCOME-INTEGRATION}.md`, `docs/architecture/{ENTHRONED-DESIGN-SYSTEM,ENTHRONED-DESKTOP-ARCHITECTURE}.md` (edições pequenas; **estes dois não estavam no backup**, a mudança é só o parágrafo/linha citada), este relatório e 4 imagens em `docs/evidence/`.
- Não tocados: `build_files/l10n/*` (nenhuma string nova), wallpapers e `look-and-feel`, bootc, polkit, systemd, H5.

## 8. Pendências para o Plasma real
1. `evaluateScript` responde? `desktops()`, `d.screen` e `readConfig("Image")` retornam o esperado? Teste de ida e volta Classic ↔ Modern com wallpaper escolhido, em 1 e 2 monitores; sem containment/widget duplicado; o wallpaper de slides/cor sólida volta ao padrão (limitação conhecida).
2. Tempo de recriação dos containments após `--resetLayout` (a nova tentativa cobre ~2 s; confirmar).
3. Ícones E (Settings) e trono (Welcome) no menu, no painel, na barra de título e no alternador de janelas, nos temas `Enthroned` e `EnthronedDark`; o aspecto a 16/22 px.
4. Settings no Plasma: decoração de janela real, escala 125/150/200 %, Tab/foco/leitor de tela, tema claro e escuro, estados da Central de Atualizações.
5. Os dois wallpapers legados no seletor; decisão (a)/(b)/(c) do §3.
6. Splash violeta único e demais itens do Lote 13 (`NEXT-HOMOLOGATION.md` §6 e §7).

## 9. GO / NO-GO
- **GO** para a revisão visual na próxima VM: fonte consistente, compilação nativa Release e 8/8 CTests, validadores verdes, QML renderizado sem defeitos visíveis em três escalas e dois temas.
- **NO-GO** para declarar “homologado” ou “aprovado visualmente”: nenhum pixel do Plasma foi visto.
- **NO-GO** específico para a persistência do wallpaper entre perfis: o defeito do Lote 13 foi corrigido e protegido por teste, mas a API só foi confirmada por inspeção do binário e por mock; depende da primeira execução em sessão real.
