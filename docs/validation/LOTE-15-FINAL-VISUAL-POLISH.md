# Lote 15 — Polimento visual final e Personalização

Data: 2026-11-19. Estado: **SOURCE READY / STATIC + AURORA-NATIVE VERIFIED. Plasma real e VM pendentes.**
Nenhuma imagem foi gerada, nenhuma VM iniciada, nada foi commitado. H6, H5, `.backup-*` e as evidências anteriores ficaram intactos.
Não foram tocados UpdateEngine, bootc, Polkit, regras de atualização, serviços de inicialização nem os mecanismos dos Gates 12.

## Resumo executivo

| Área | Resultado |
| --- | --- |
| Menu Iniciar — lista estreita em "Sistema" | **Causa raiz achada e corrigida** (a coluna Locais dividia o espaço com a lista) |
| Menu Iniciar — ícones | Blocos fixados de 48 → 56 px; PNGs oficiais inalterados |
| Dolphin — menu em área vazia | Origem identificada (Filelight e plugin nativo de cor de pasta); ocultados por `/etc/xdg/kservicemenurc`, **provado** com o código real do KIO |
| Personalização | Reescrita em 4 seções; 13 controles reais, todos com padrão restaurável; 0 controles falsos |
| Defeito latente encontrado | Os botões Claro/Escuro passavam `"Enthroned Light"` ao `plasma-apply-colorscheme`, que **recusa** esse nome; corrigido |
| Cores de pasta | 11 cores nativas do KDE com a identidade Enthroned (44 SVG), claro e escuro |

## 1. Melhorias implementadas

### 1.1 Menu Iniciar (`org.enthroned.launcher`)
- **Causa raiz da lista estreita.** Em `FullRepresentation.qml`, a coluna Locais é um `ColumnLayout` com `Layout.preferredWidth: 10 gridUnits`. Num `RowLayout`, um layout aninhado tem `fillWidth: true` por padrão, então Locais e painel central **dividiam igualmente** o espaço que sobrava. Na captura da H6 (`boot2/launcher-modern-180449.png`, 1920×1080, popup de 828 px) o painel central tem ~300 px e Locais ~275 px, embora Locais só precise de 180 px. Correção: `Layout.fillWidth: false` na coluna Locais.
- Popup de 46 → **50 gridUnits** (ainda limitado à área útil da tela menos 2 gridUnits) e painel central com `Layout.minimumWidth` de 14 gridUnits.
- Nova propriedade `placesCompact`: Locais vira só ícones com dica abaixo de **45 gridUnits** de popup (antes só abaixo de 36 junto com a barra lateral), para nunca espremer a lista.
- Altura da célula dos fixados de 6 → 6,5 gridUnits (comporta o ícone maior mais duas linhas de rótulo).
- Ícone dos blocos fixados de 48 → **56 px** (`AppTileDelegate.qml`), com o PNG de 64 px reduzido (continua nítido). É o que dá mais presença ao **E** das Configurações e ao trono do Boas-vindas.
- Mantidos sem alteração: pesquisa, fixados, favoritos, navegação por teclado, ações do menu de contexto, dica (tooltip) com o nome completo quando truncado, truncamento com reticências, botão do launcher e ícone oficial do Iniciar do Lote 14.

Largura da coluna de aplicativos (fórmulas do próprio QML, gridUnit = 18 px, **calculado, não medido em tela**; o "antes" bate com a captura da H6: ~290 px calculado × ~300 px medido):

| Resolução / escala | Popup antes → depois | Lista de aplicativos antes | depois |
| --- | --- | --- | --- |
| 1280×720 a 100 % | 828 → 900 px | 290 px (16,1 gu) | 481 px (26,7 gu) |
| 1920×1080 a 100 % | 828 → 900 px | 290 px (16,1 gu) | 481 px (26,7 gu) |
| 1920×1080 a 150 % (1280 lógicos) | 828 → 900 px | 290 px (16,1 gu) | 481 px (26,7 gu) |
| 1920×1080 a 200 % (960 lógicos) | 828 → 900 px | 290 px (16,1 gu) | 481 px (26,7 gu) |
| 1024×768 a 100 % | 828 → 900 px | 290 px (16,1 gu) | 481 px (26,7 gu) |
| 800×600 a 100 % | 764 → 764 px | 258 px (14,3 gu) | 462 px (25,7 gu) |
| 640×480 a 100 % | 604 → 604 px | 329 px (18,3 gu) | 329 px (18,3 gu) |

### 1.2 Dolphin — menu de contexto numa área vazia
Investigação com o **código real** do KIO/Dolphin da Aurora fixada (`ghcr.io/ublue-os/aurora:stable`, KDE Gear 26.08.3): um programa de teste (`KFileItemActions`, o mesmo que o Dolphin usa) montou o menu para uma pasta, com três configurações:

| Cenário | Entradas relevantes |
| --- | --- |
| A — padrão | "Exibir estatísticas de uso do disco"; uma ação sem texto (a faixa de cores com "Outros"); Abrir com, Atividades, Comprimir, Etiquetas… |
| B — `[Show] filelight=false` + `setfoldericonitemaction=false` | as duas somem; **tudo o mais idêntico** |
| C — só `filelight=false` | a faixa de cores continua (prova que cada chave age sozinha) |

Origem das duas entradas (**não são customização do Enthroned**; nada no repositório as menciona):
- "Exibir estatísticas de uso do disco": menu de serviço do pacote **filelight 26.08.3** (`/usr/share/kio/servicemenus/filelight.desktop`, `MimeType=inode/directory`).
- Faixa de ícones de cor e "Outros": plugin nativo `setfoldericonitemaction.so` do pacote **dolphin-libs 26.08.3** ("Definir ícone da pasta", grava `Icon=folder-<cor>` no `.directory`).

Mudança: `system_files/etc/xdg/kservicemenurc` com `[Show] filelight=false` e `setfoldericonitemaction=false` (são as chaves que a página Configurações → Menu de contexto do Dolphin grava). Sem fork, sem desinstalar o Filelight (o aplicativo continua no menu Iniciar), sem tocar em Copiar/Colar, Propriedades, Terminal, Comprimir, Etiquetas.

**Limite, dito às claras:** o Dolphin monta o menu de "área vazia" e o de "pasta selecionada" com o mesmo item (a própria pasta) e o mesmo tipo MIME; os dois plugins não distinguem os contextos. Não existe como ocultar só na área vazia sem fork. Por isso a faixa de cores **também sai do menu de uma pasta selecionada**. A função não se perdeu: a cor de pasta passou para Configurações → Personalização → Arquivos e pastas (§1.3), com restauração do padrão. Reverter: apagar as chaves (ou, por usuário, `~/.config/kservicemenurc`, que a cascata normal do KConfig prioriza; esta última precedência não foi exercitada).

### 1.3 Personalização (`settings/qml/pages/AppearancePage.qml`)
Página reorganizada em **Aparência geral · Área de trabalho · Arquivos e pastas · Painel e Menu Iniciar**, seguida de "Mais configurações do KDE" (atalhos aos módulos nativos, como antes). Visual: linhas de preferência sem cartões (`SettingRow`: título, uma linha de explicação, controle à direita; abaixo de 34 gridUnits o controle desce), cartões só para os perfis e a pré-visualização; avisos como notificação passiva (visíveis em qualquer ponto da página longa) em vez de uma barra no topo. Textos técnicos removidos da superfície.

Novos componentes: `SettingRow`, `ColorSwatch` (seleção nunca só por cor: marca de verificação + anel, foco por contorno separado, papel de rádio e nome acessível), `ChoiceBox`, `ToggleBox` (ligados a chaves permitidas do controlador, com `Binding` para a escolha do usuário não quebrar o vínculo).

### 1.4 Cores de pasta (identidade Enthroned)
O plugin nativo oferece 11 cores Breeze (`folder-black|blue|brown|cyan|green|grey|magenta|orange|red|violet|yellow`; **não há `folder-white`** no KDE 26.08). Sem arquivos próprios, elas cairiam nos ícones planos do Breeze e destoariam do violeta Enthroned. `scripts/gen-folder-colors.py` gera `folder-<cor>.svg` e `folder-<cor>-open.svg` a partir da geometria e dos três tons de `folder.svg`/`folder-open.svg` (só muda o matiz; cinza e preto usam neutros levemente violeta como os neutros da marca), nos temas `Enthroned` e `EnthronedDark` (44 arquivos). `folder-violet` é idêntico ao ícone padrão. Pré-visualização renderizada: `docs/evidence/lote15/folder-colours-preview.html`.

## 2. Problemas corrigidos

| # | Problema | Correção |
| --- | --- | --- |
| 1 | Lista de aplicativos estreita em "Sistema" etc. | `fillWidth: false` em Locais; popup 50 gu; `placesCompact`; mínimo do painel central |
| 2 | Ícones do Iniciar com pouca presença | Blocos de 56 px |
| 3 | "Exibir estatísticas de uso do disco" e faixa de cores no menu da área vazia | `kservicemenurc` (§1.2) |
| 4 | **Latente:** Claro/Escuro chamavam `plasma-apply-colorscheme "Enthroned Light"`. Na Aurora fixada o comando responde `Could not find theme "Enthroned Light"`; só o id do arquivo (`EnthronedLight`) funciona (o mesmo vale para `Breeze Dark` × `BreezeDark`) | Controlador passa o id do arquivo; teste e `validate-desktop.sh` impedem a regressão |
| 5 | Trocar o tema voltaria a cor de destaque ao padrão do esquema (verificado: aplicar outro esquema zera o destaque) | O destaque escolhido é reaplicado depois de Claro/Escuro e depois de trocar de perfil |
| 6 | Trocar Classic ↔ Modern recria o desktop (`--resetLayout`) e perderia o tamanho dos ícones | `enthroned-profile` guarda e restaura o tamanho dos ícones por tela (mesmo método do wallpaper) e reaplica o destaque |

## 3. Novas opções de Personalização

| Seção | Controle | Padrão / restauração |
| --- | --- | --- |
| Aparência geral | Perfis Classic/Modern (como antes) | "Restaurar aparência anterior" |
| | Tema claro / escuro | — |
| | **Cor de destaque**: 7 cores + violeta Enthroned, **pré-visualização** (item selecionado, botão, anel de foco) antes de aplicar | "Restaurar padrão" |
| | **Bordas das janelas** (automática, fina, normal, larga) | Automática (apaga as chaves) |
| | **Velocidade das animações** (padrão, rápida, instantânea) | Padrão (apaga a chave) |
| Área de trabalho | Wallpapers oficiais (como antes) + **"Usar sua própria imagem…"** | os oficiais continuam |
| | **Tamanho dos ícones** (pequeno … extra grande) | Grande (valor padrão do KDE) |
| | Cores de seleção e retângulo de arrastar | **Sem controle próprio, de propósito:** o retângulo usa a cor de destaque; o texto da linha do destaque diz isso |
| Arquivos e pastas | **Cor de pasta** (escolher pasta + 11 cores) | "Restaurar aparência padrão da pasta" |
| | Dolphin: visualização (detalhes, ícones, compacta), tamanho dos ícones, arquivos ocultos, pré-visualizações | "Restaurar padrões do Dolphin" (detalhes é o padrão Enthroned) |
| Painel e Menu Iniciar | **Tamanho do painel** (compacto 36, padrão do perfil 44/48, grande 56) | Padrão do perfil |
| | Tamanho dos ícones do Menu Iniciar | **Não oferecido:** não há ajuste do KDE; o launcher usa uma escala única; a página diz isso em uma linha |

Também entraram na busca de Configurações (5 novas entradas). Traduções pt-BR: 92 novas mensagens em `build_files/l10n/pt_BR/enthroned-settings.po` (`msgfmt -c` OK; 0 mensagens sem tradução nos arquivos alterados).

## 4. Integrações KDE utilizadas

| Controle | Mecanismo nativo |
| --- | --- |
| Perfis | `enthroned-profile` → `plasma-apply-lookandfeel` |
| Claro/Escuro, destaque | `plasma-apply-colorscheme <IdDoArquivo>` e `--accent-color #RRGGBB` |
| Wallpaper (oficial e próprio) | `plasma-apply-wallpaperimage` (só PNG/JPEG/WebP/BMP/GIF existentes e legíveis) |
| Animações | `kdeglobals [KDE] AnimationDurationFactor` (a chave da página Animações do KDE), `kwriteconfig6 --notify` |
| Bordas das janelas | `kwinrc [org.kde.kdecoration2] BorderSize` + `BorderSizeAuto=false`, depois `org.kde.KWin /KWin reconfigure` |
| Dolphin | `~/.local/share/dolphin/view_properties/global/.directory`, grupo `[Dolphin]` (o mesmo arquivo que `enthroned-files-setup` semeia; `GlobalViewProps=true`): `ViewMode`, `IconSize`, `HiddenFilesShown`, `PreviewsShown` |
| Cor de pasta | `<pasta>/.directory`, `[Desktop Entry] Icon=folder-<cor>` (o que a ação "Definir ícone da pasta" grava); remove só um `Icon` que esta função escreveu |
| Ícones da área de trabalho, altura do painel | Scripting do Plasma por D-Bus (`org.kde.plasmashell evaluateScript`), a mesma API dos scripts de layout; só com um plasmashell já em execução |
| Persistência do destaque | `~/.config/enthronedpersonalizationrc` `[Accent] Id/Hex` |

Todos os valores vêm de listas fechadas no controlador (id ou valor de um conjunto permitido; só a imagem e a pasta escolhidas pelo usuário são caminhos livres, validados). Sem shell, sem privilégio.

## 5. Arquivos modificados

Alterados:
`system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/FullRepresentation.qml`, `…/AppTileDelegate.qml`; `settings/src/personalizationcontroller.h/.cpp`; `settings/qml/pages/AppearancePage.qml`; `settings/qml/SearchIndex.qml`; `settings/CMakeLists.txt`; `build_files/l10n/pt_BR/enthroned-settings.po`; `system_files/usr/bin/enthroned-profile`; `scripts/validate-desktop.sh`; `scripts/test-profile-wallpaper-preserve.sh`; `docs/operations/START-MENU.md`; `docs/operations/NEXT-HOMOLOGATION.md`.

Novos:
`settings/qml/components/SettingRow.qml`, `ColorSwatch.qml`, `ChoiceBox.qml`, `ToggleBox.qml`; `settings/tests/personalization-smoke.cpp`; `system_files/etc/xdg/kservicemenurc`; `scripts/gen-folder-colors.py`; 44 SVG `folder-<cor>[-open].svg` em `system_files/usr/share/icons/Enthroned/` e `EnthronedDark/`; `docs/evidence/lote15/*`; este relatório.

**Backup:** o espaço de trabalho não tem commits e **não foi feita cópia prévia** dos arquivos alterados neste lote (diferente do Lote 14). O estado anterior está descrito aqui; reverter o Menu Iniciar exige desfazer as edições listadas em §1.1.

## 6. Testes e resultados

| Verificação | Onde | Resultado |
| --- | --- | --- |
| Compilação nativa do Settings (cmake, Qt 6 + KF6 da Aurora fixada) | contêiner descartável | **OK** |
| CTest (7 testes: appstream, close-smoke, native, flatpak, bootc, update-engine, **personalization-smoke**) | idem | **7/7 passam** |
| `personalization-smoke` (novo, 24 verificações) com `kwriteconfig6`/`kreadconfig6` reais, HOME isolado e `plasma-apply-colorscheme` falso | idem | **PASS**: lista fechada rejeita id/valor inválido; salvar e restaurar animações, bordas (com a chave companheira), Dolphin, cor de pasta (restaurar nunca apaga um ícone personalizado); destaque aplicado com o hex da paleta, persistido, reaplicado após trocar de esquema, reset por esquema vizinho e volta; o nome com espaço nunca é passado |
| `all_qmllint` do Settings | idem | exit 0; **0** avisos novos além de "Unqualified access" (padrão antigo do projeto: `i18n` e objetos de contexto) |
| `qmllint` dos arquivos do launcher alterados | Aurora fixada | exit 0; só avisos antigos (`launcher`, `Qt.labs.platform`), nenhum nas linhas alteradas |
| Renderização **real** da página (Xvfb + backend de software + `org.kde.desktop` + EnthronedLight/Dark, aplicativo real) | idem | Página carrega sem erros, claro e escuro; ver §7 |
| Menu de contexto do Dolphin (`KFileItemActions` real) | idem | cenários A/B/C acima |
| `scripts/validate-desktop.sh` | host | ALL CHECKS PASSED (+ 18 verificações novas: `kservicemenurc`, 11 cores × 2 variantes × 2 temas e violeta idêntico, largura do launcher, `enthroned-profile`, id do esquema) |
| `scripts/validate-settings.sh` | host | 527 passam, 0 falham |
| `scripts/test-profile-wallpaper-preserve.sh` | host | 16 PASS (+4 novos: ícones por tela, entradas hostis descartadas, nada quando não houve mudança, JS válido) |
| `test-layouts.mjs`, `test-launcher-*.mjs`, `test-profile-context-menu.mjs`, `test-desktop-helpers.sh` | host | PASS |
| `welcome/tests/run-tests.mjs` | host | 104 passam, 0 falham |
| `scripts/test-system-stability.sh` | WSL, cópia | ALL PASS |
| `scripts/verify-source.sh` | host | 14 pass, 2 warn (antigos), 0 fail |
| `msgfmt -c` do catálogo pt-BR | contêiner | OK, 665 mensagens |

Não reexecutados (área não tocada): `test-auto-update-safety.sh`, `test-polkit-uupd.sh`, CTest do Welcome.

## 7. Capturas e renderizações reais

Todas são do **aplicativo Settings real em Xvfb** (não é o Plasma: sem KWin, sem decoração de janela, sem wallpapers instalados no contêiner, ícones sem o tema Enthroned):
`docs/evidence/lote15/settings-personalization-claro-1.png`, `-claro-2.png`, `-escuro-1.png`, `-escuro-2.png`.
Ícones: `docs/evidence/lote15/folder-colours-preview.html` (SVG renderizados, tema claro e escuro).
**O Menu Iniciar não foi renderizado** (depende do Plasma); só `qmllint` e as contas da §1.1.

## 8. Pendências de homologação (Plasma real / VM)

1. **Menu Iniciar**: categoria Sistema com nomes completos legíveis; Locais com largura fixa; 100/150/200 %; blocos de 56 px sem corte; tooltip dos nomes truncados.
2. **Dolphin real**: botão direito numa área vazia sem as duas entradas; menu de arquivo, pasta selecionada, Copiar/Colar, Propriedades, Terminal e extensões legítimas presentes. Só o `KFileItemActions` foi exercitado, não o `DolphinContextMenu`.
3. **Claro/Escuro e destaque no Plasma**: Claro/Escuro nunca foi observado em Plasma real; conferir aplicar/restaurar do destaque, que ele sobrevive a Claro/Escuro e à troca de perfil, e o retângulo de seleção do desktop com a nova cor. O reset do destaque usa "esquema vizinho e volta" (pode piscar por um instante).
4. **Scripting do Plasma** (nunca executado: plasmashell não roda sem sessão): tamanho dos ícones da área de trabalho (chave `iconSize` 0–6 do contêiner da pasta) e altura do painel (`panels()[i].height`); preservação do tamanho dos ícones na troca de perfil (testada só com simulação).
5. **Dolphin**: valores de `ViewMode` (0 ícones, 1 detalhes, 2 compacta; o 1 vem da nota de `enthroned-files-setup`, não do código-fonte do Dolphin) e efeito de `IconSize` nos três modos; a configuração vale ao abrir pastas, não em janelas já abertas.
6. **Cores de pasta** no Dolphin real: ícone Enthroned colorido, claro e escuro; o preto no tema escuro tem pouco contraste com o fundo (cor nativa, mantida).
7. **Acessibilidade**: navegação por Tab e foco visível nos novos controles e leitura por tecnologia assistiva só foram revistas no código (papéis, nomes, foco), não exercitadas; conferir 150 % e 200 % na página (modo estreito de `SettingRow` abaixo de 34 gridUnits não foi renderizado).
8. **pt-BR**: a página não foi renderizada em português (o locale do contêiner não carregou o catálogo); o catálogo é válido e completo.
9. **Bordas e animações**: aplicar de fato em janelas abertas (`KWin reconfigure`).

## 9. GO / NO-GO para a próxima imagem

**GO condicional.** Não há bloqueio conhecido: o código compila nativamente, os 7 testes do Settings e todas as validações estáticas passam, a página renderiza de verdade nos dois temas, a causa raiz da lista estreita está identificada e corrigida, e a origem das entradas do Dolphin está provada. Antes de chamar de homologado, é preciso executar as pendências da §8 numa VM (itens 1–4 são os de maior risco para o usuário: Menu Iniciar, Dolphin, Claro/Escuro/destaque e scripting do Plasma). Se o item 2 mostrar que as duas entradas continuam, bastará remover `system_files/etc/xdg/kservicemenurc`, sem efeito sobre o resto.

Decisão do proprietário (**aceita em 2026-11-19**): aceitar que a **faixa de cores sai também do menu de pastas selecionadas** (a cor passa a ser escolhida em Personalização), já que o Dolphin não permite separar os dois contextos sem fork.

Lote concluído. Nenhum outro lote foi iniciado.
