# Lote 13 — integração de assets e refinamento visual (2026-11-19)

Classificação: **SOURCE READY / STATIC VERIFIED**. Não é BUILD VERIFIED nem homologado visualmente.
Nada foi compilado em Qt/KDE, instalado ou executado em Plasma/VM: esta máquina não tem Qt, `qmllint`,
CMake nem compilador, e o Docker não estava ativo. **Não existe captura do Plasma real** (ver §10).
Não foram gerados H6, imagem OCI/ISO/QCOW2/VDI; VirtualBox não foi iniciado; H5 não foi tocada; nenhum
commit/push. Backup pontual antes de editar: `.backup-lote13/` (366 arquivos, não versionado; apague quando
quiser). SHA-256 dos 9 originais de `assets/` conferido antes e depois: **inalterados**.

## 0. Como as skills foram usadas (e o que não foi)

| Skill | Uso real |
| --- | --- |
| `impeccable` | Contexto carregado (sem `PRODUCT.md`: tratado como refinamento de código existente, o brief do lote é o contexto), `craft-floor` e `critique` lidos. **Não rodei** o pipeline `critique`/`detect`/live (é de marcação web; sem sub-agentes de A/B nem navegador sobre QML). Aplicou-se o piso: contraste, estados, foco, sem gradiente/brilho decorativo, ícones de um só conjunto. |
| `design:design-critique` | Crítica **antes** (§0.1) a partir do código QML/validadores e **depois** (§0.2), em linha, no formato da skill. |
| `design:design-system` | `docs/architecture/ENTHRONED-DESIGN-SYSTEM.md` + `design-tokens.json` schema 2 (tokens, estados, componentes, logos, regras). |
| `design:accessibility-review` | §0.3, adaptada a Qt/QML; cálculo de contraste real dos `.colors`. Sem conformidade WCAG declarada. |
| `no-slop-ui` | Critério: cartão só para uma ideia, sem brilho roxo nas bordas, sem gradiente, sombra só do compositor, animação mínima. |
| `design-dna` | Fase 2 manual: cores **medidas** (k-means em `assets/`) → `identity.measured` nos tokens. O `measure-colors.mjs` da skill (npm) não foi executado. |
| `ui-ux-pro-max` | Lida; usadas as regras do Quick Reference (contraste, alvos, estados, ícones coerentes). **Nenhuma busca `search.py` foi feita** — não era necessária, a paleta veio dos assets. |

### 0.1 Crítica antes (código existente)

| Achado | Gravidade | Correção neste lote |
| --- | --- | --- |
| Identidade azul/âmbar e coroa genérica, sem relação com a arte do proprietário | 🔴 | esquemas violeta medidos dos assets; logos originais |
| Mesmo ícone de coroa nos dois perfis; sem diferença Classic × Modern no Iniciar | 🔴 | E × trono, por perfil |
| `highlight` do tema escuro com 2,3–2,7:1 sobre as superfícies (barra de progresso, switch, slider, barra de seleção) | 🟡 | 3,1–3,5:1 (token); auditoria no gerador |
| Seção “wallpapers” em `RowLayout` de largura fixa (13 gridUnit × n) e carregando PNG de 1920 px como miniatura | 🟡 | grade responsiva + miniatura leve |
| Itens da navegação com ~30 px de altura | 🟡 | 38 px |
| Cabeçalhos de seção sem assimetria de espaço (colavam no grupo anterior) | 🟢 | `SectionHeading` único |
| Sobre misturava ícone do SO e do dispositivo | 🟢 | wordmark do SO + ícone `computer` do dispositivo |
| Splash claro no Classic e wallpaper escuro (clarão na entrada) | 🟢 | splash violeta nos dois |
| Pastas âmbar destoando da interface | 🟢 | pastas violeta |

### 0.2 Crítica depois (o que foi resolvido / o que não)

Resolvido: todos os itens acima, **na fonte**. Não resolvido / não verificável: render real do QML (hierarquia
percebida, ritmo vertical, aparência da grade de wallpapers, nitidez do E a 32 px no painel real); ícones dos
apps Settings e Welcome ainda são coroa/porta (apenas recoloridos para violeta) — decisão de arte pendente do
proprietário; página Atualizações mantém a estrutura (já era cartão de estado + seções), só ganhou
`SectionHeading` e a cor nova; Home continua com cartões por área (densidade a avaliar na VM).

### 0.3 Acessibilidade (Qt/QML; sem afirmar conformidade)

| Verificação | Resultado | Evidência |
| --- | --- | --- |
| Contraste de texto (1.4.3) | 268 pares, todos ≥ 4,5:1 | `scripts/gen-color-schemes.py --check` (estático) |
| Contraste não-textual (1.4.11) | anel de foco ≥ 3:1 nas duas escalas (6,6:1 escuro / 6,3:1 claro sobre Window); highlight ≥ 3:1 (3,1–3,5 escuro; 7,1–8,2 claro) | idem |
| Foco visível (2.4.7) | anel de 2 px `focusColor` em navegação, tiles e busca (já existia; cor nova passa 3:1) | código; não visto em execução |
| Alvos (2.5.5/WCAG 2.2 24 px) | navegação 38 px, botões padrão Kirigami; painéis 44/48 px | código |
| Nome acessível | novos: wordmark (`Graphic` “Enthroned OS”), botão de wallpaper “Definir %1 como papel de parede”, `SectionHeading` com papel `Heading`, miniaturas decorativas ignoradas | código |
| Redução de animação | só `Kirigami.Units.*Duration`; o spinner do splash é a exceção documentada (já existia) | código |
| pt_BR/inglês | 4 strings novas no catálogo do Settings, 1 no Welcome; validador de i18n passa | `validate-settings.sh` |
| Escala/DPI | tamanhos por `Kirigami.Units`; grade de wallpapers calcula colunas pela largura; sem largura fixa total | código; não visto em 125/150/200 % |
| Teclado, leitor de tela, 1920×1080 e telas menores | **não testados** | pendente VM |

## 1. Assets identificados e integrados

Originais em `assets/` (intactos; hashes conferidos). Todos PNG 8 bits.

| Arquivo | Dimensão | Modo | Observação de contraste | Integração |
| --- | --- | --- | --- | --- |
| `E Logo.png` | 1247×1261 | RGBA | branco/prata com contorno escuro: bom no escuro, ~1,1:1 no claro | derivado mono (reservado) |
| `E Logo-2.png` | 1247×1261 | RGBA | roxo/cromado: legível nos dois temas | **Iniciar Classic**, logo do sistema |
| `Enthroned Throne.png` | 1150×1368 | RGBA | assento preto some no painel escuro | não usado como ícone |
| `Enthroned Throne-2.png` | 1150×1368 | RGBA | silhueta e brilhos roxos legíveis | **Iniciar Modern** |
| `EnthronedLogo.png` | 1984×793 | RGBA | prata/branco | `enthroned-wordmark-mono.png` |
| `EnthronedLogo-2.png` | 1983×793 | RGBA | colorido | Sobre, Welcome, splash |
| `wall1.png` | **1672×941** | RGB | — | Enthroned — Soberania |
| `wall2.png` | **1672×941** | RGB | — | Enthroned — Ascensão |
| `wall3.png` | **1672×941** | RGB | — | Enthroned — Vigília (padrão) |

> O prompt dizia 1920×1080; os arquivos reais são **1672×941**. Foram instalados no tamanho real, sem
> redimensionar (Plasma escala em tempo de execução). O 1672×941 (1,7769) difere de 16:9 (1,7778) em ~1 px.

Derivados técnicos (`scripts/gen-brand-assets.py`, determinístico, só Pillow): ícones hicolor
16/22/24/32/48/64/128/256/512 px (recorte ao desenho, tela quadrada, Lanczos em alfa pré-multiplicado, nitidez
leve ≤ 48 px), wordmark 1000 px (e 720 px nos splashes), miniaturas 640×360 dos wallpapers. Nada redesenhado.

## 2. Nomes finais dos wallpapers

| Pacote (`/usr/share/wallpapers/…`) | Nome no seletor do KDE |
| --- | --- |
| `EnthronedSoberania` | Enthroned — Soberania |
| `EnthronedAscensao` | Enthroned — Ascensão |
| `EnthronedVigilia` | Enthroned — Vigília |

## 3. Como `wall3.png` é o padrão

Declarativo, sem autostart e sem segunda fonte de verdade para o *usuário*:

- `look-and-feel/org.enthroned.{classic,modern}/contents/defaults`: `[Wallpaper] Image=EnthronedVigilia`
  (mecanismo que já existia; antes `Enthroned` / `EnthronedNocturne`).
- Tela de bloqueio (`/etc/xdg/kscreenlockerrc`) e login (`/etc/plasmalogin.conf.d/10-enthroned.conf`).
- Build (`build_files/build.sh`): defaults do Aurora, `default.jxl`/`default-dark.jxl` e a paisagem do
  plasma-setup (`Next`) agora derivam de `wall3` (Lanczos a 3840×2160 / 5120×2880 em tempo de build; o pacote
  original não é alterado). Os dois PNG “claro/escuro” do setup ficam iguais porque só há arte escura.
- Nada reaplica a escolha no login; os pacotes antigos `Enthroned` e `EnthronedNocturne` **continuam
  instalados** (compatibilidade com configs existentes) e ainda aparecem no seletor → **decisão do
  proprietário**: removê-los na próxima imagem deixa só os três oficiais.

**Não verificado:** se o Plasma 6.6 aplica de fato o `[Wallpaper] Image` do `defaults` a um usuário novo
(é o mecanismo pré-existente; falta VM). Se não aplicar, o fallback é o `Next` (também Vigília).

## 4. Como o usuário troca de wallpaper

Pelo seletor nativo (Configurações do Sistema → Papel de parede): os três pacotes aparecem com nome e
miniatura; qualquer imagem externa continua selecionável. Também em Enthroned Settings → Personalização
(grade de 3 miniaturas, botão “Definir … como papel de parede”, usa `plasma-apply-wallpaperimage`).
**Alternar Classic ↔ Modern não reseta a escolha:** `plasma-apply-lookandfeel --resetLayout` recria os
desktops (e perderia a config), então `enthroned-profile` lê o `Image` de cada tela no plasmashell
(`evaluateScript`, por monitor) antes e o regrava depois — só se havia escolha, sem gravar nada em disco, sem
rodar no login; entradas malformadas são descartadas. *Isto altera `enthroned-profile`, mas não a lógica de
gerenciamento de perfis (mesmos comandos, mesma ordem); é o mínimo para o requisito 6.* A API
`evaluateScript` **não foi verificada** no Plasma 6.6 (§11).

## 5. Ícone por modo

| Perfil | Ícone | Variante | Por quê |
| --- | --- | --- | --- |
| Classic | `org.enthroned.launcher-classic` (E) | roxa (`E Logo-2`) | a branca tem ~1,1:1 no painel claro |
| Modern | `org.enthroned.launcher-modern` (trono) | colorida (`Throne-2`) | silhueta nítida a 24–48 px no painel escuro |

Mecanismo: o layout de cada perfil grava `General/icon` no applet (`menu.writeConfig`) a cada reset — no
launcher próprio **e** no Kickoff de recuperação —, o plasmoid já lia `Plasmoid.configuration.icon`
(binding existente). Persiste porque é config do applet (appletsrc). Nomes de tema, sem caminho absoluto;
o menu de contexto não é tocado; um widget de menu por painel (o `test-layouts.mjs` continua exigindo isso).
O cabeçalho do menu aberto mostra o mesmo ícone a 32 px (era 22). Instalações antigas (H5): o `icon` não
está gravado → Modern mostra o E até reaplicar o perfil (esperado).

## 6. Melhorias no Settings

- **Identidade/cores:** esquemas violeta (§7); ícone do app e sidebar passam a usar o E; Sobre com o wordmark
  original (ícone `computer` para o dispositivo); Welcome idem.
- **Navegação:** alvo de 38 px; demais estados (hover/selecionado/foco/barra de acento) mantidos e agora com cor
  que passa 3:1.
- **Hierarquia:** `SectionHeading` (semibold, mais espaço acima) em Sobre, Personalização, Apps, Início,
  Privacidade, Sistema e Atualizações (19 cabeçalhos).
- **Personalização:** grade responsiva de wallpapers (miniaturas de 640 px, selo “Padrão”, nome acessível),
  texto explicando o seletor do KDE e a persistência; prévias de perfil usam Vigília.
- **Atualizações:** só visual (cabeçalhos e cor). **Máquina de estados, UpdateEngine, políticas, permissões e
  polkit não foram tocados**; correções dos Gates 12.1–12.4 preservadas (os testes deles passam).
- Estados vazios e `InfoRow`/`EmptyState`/`ShortcutTile` já seguiam o padrão; sem mudança.

## 7. Melhorias na interface geral

- **Cores:** `EnthronedDark`/`EnthronedLight` regenerados por `scripts/gen-color-schemes.py` (neutros violeta,
  acento `#9A3DD6` escuro / `#6F26A8` claro, foco `#B684EA` / `#7A32BE`), com auditoria; barras de título
  seguem (seção `[WM]`). Estrutura dos arquivos preservada (diff de seções idêntico).
- **Splash** (Classic e Modern): fundo `#120428` (mesma família do wallpaper) + wordmark; anel de carregamento
  violeta; página final do plasma-setup usa o E.
- **Pastas do Dolphin/Places:** âmbar → violeta (2 temas, 18 arquivos), glifos brancos intactos.
- **Menu Iniciar:** ícone do cabeçalho 32 px; estados já usam `highlightColor`.
- **Dolphin / KWin / Breeze:** sem fork e sem mudança de configuração; herdam esquema e ícones.
- **Design system:** `ENTHRONED-DESIGN-SYSTEM.md` + tokens schema 2.

## 8. Arquivos

Removidos (placeholders genéricos): `icons/hicolor/scalable/apps/org.enthroned.{crown,enthroned-os,launcher}.svg`,
os dois `splash/images/enthroned-logo.svg` e `org.kde.plasmasetup.finished/.../enthroned-logo.svg`.

Adicionados: `scripts/gen-brand-assets.py`, `scripts/gen-color-schemes.py`,
`scripts/test-profile-wallpaper-preserve.sh`, `docs/architecture/ENTHRONED-DESIGN-SYSTEM.md`,
`docs/evidence/lote13-preview-esquematica.png`, este relatório; `settings/qml/components/{BrandWordmark,SectionHeading}.qml`;
em `system_files/usr/share`: `wallpapers/Enthroned{Soberania,Ascensao,Vigilia}/` (9 arquivos),
`icons/hicolor/<9 tamanhos>/apps/org.enthroned.{launcher-classic,launcher-modern,enthroned-os}.png` (27),
`enthroned-os/branding/enthroned-wordmark{,-mono}.png`, `…/splash/images/enthroned-wordmark.png` (×2).

Modificados (62): `color-schemes/Enthroned{Dark,Light}.colors`, `branding/design-tokens.json`,
`look-and-feel/*/{defaults,layouts/…layout.js,splash/Splash.qml,splash/images/busy-ring.svg}`,
`plasmoids/org.enthroned.launcher/{metadata.json,contents/config/main.xml,contents/ui/FullRepresentation.qml}`,
`org.kde.plasmasetup.finished/contents/ui/main.qml`, 18 SVGs de pastas, `etc/xdg/kscreenlockerrc`,
`etc/plasmalogin.conf.d/10-enthroned.conf`, `usr/bin/enthroned-profile`; `settings/` (`CMakeLists.txt`, `Main.qml`,
`AppearancePage`, `AboutPage`, `HomePage`, `AppsPage`, `PrivacyPage`, `SystemPage`, `UpdatesPage`,
`personalizationcontroller.{cpp,h}`, ícone do app); `welcome/qml/pages/{WelcomePage,StylePage}.qml`;
`build_files/build.sh` e os catálogos pt_BR do Settings e do Welcome; `scripts/{test-layouts.mjs,validate-desktop.sh,verify-image.sh}`;
`README.md` e 5 documentos em `docs/`.

Observação: `docs/validation/GATE-12-6-H5-DIAGNOSTICS.md` apareceu na árvore **depois** do meu backup; não é meu
e não foi tocado.

## 9. Testes e resultados (todos estáticos/simulados)

| Verificação | Resultado |
| --- | --- |
| Linha de base antes de editar (layouts, launcher ×3, menu de contexto, validate-desktop/settings/welcome, verify-source) | todos 0 |
| `scripts/test-layouts.mjs` (+ asserção do ícone por perfil, 6 cenários) | passa (API do Plasma simulada) |
| `scripts/test-profile-wallpaper-preserve.sh` (novo; ferramentas KDE simuladas: 2 monitores, sem escolha, entradas hostis, sem D-Bus) | 6/6 |
| `scripts/gen-color-schemes.py --check` | 268 pares, 0 abaixo do limite |
| `scripts/validate-desktop.sh` (novas checagens: PNG byte-idêntico a `assets/`, nomes do seletor, padrão Vigília nos 4 pontos, ícone por perfil) | `ALL CHECKS PASSED` (386 PASS) |
| `scripts/validate-settings.sh` (QML balanceado, i18n, C++, CMake) | passa |
| `scripts/validate-welcome.sh` | passa |
| `settings/tests/run-tests.mjs` / `welcome/tests/run-tests.mjs` | 517/0 · 104/0 |
| `test-launcher-{filter,pinned-dedupe,appactions}`, `test-update-engine`, `test-profile-context-menu`, `test-desktop-helpers`, `test-diagnostics-ptbr` | passam |
| `scripts/verify-source.sh` | 14 pass, 2 warn, 0 fail (mesmos 2 avisos da linha de base) |
| `bash -n` em `build.sh`, `enthroned-profile`, `verify-image.sh`, validador | ok |
| Originais de `assets/` + wallpapers instalados | SHA-256 iguais; `cmp` byte a byte dos 3 pacotes |

**Não executado:** compilação Qt/CMake, `qmllint`, execução QML offscreen, `verify-image.sh` (precisa de imagem),
qualquer coisa em Plasma real. Nenhum teste pesado de componente não alterado foi repetido.

## 10. Capturas / prévias

`docs/evidence/lote13-preview-esquematica.png` — **esquemática, gerada por script a partir dos assets e dos
`.colors` reais; não é captura do Plasma nem render do QML.** Mostra os dois painéis (Classic/Modern) sobre o
wall3, o botão Iniciar em 1:1 (ampliado 2×), o wordmark nas duas superfícies, as 3 miniaturas do seletor e a
tabela de contraste calculada. Servem para conferir cor, escala e legibilidade do ícone; não provam o layout.

## 11. Pendências para a próxima VM

Roteiro completo em `docs/operations/NEXT-HOMOLOGATION.md` §6. Os itens críticos:

1. `evaluateScript` (D-Bus do plasmashell) devolve `print()` e existe `desktop.screen`? Do contrário, a troca de
   perfil volta a Vigília (a troca em si não quebra).
2. Plasma aplica `[Wallpaper] Image` do `defaults` em usuário novo? Persistência após logout/reboot; 2 monitores.
3. Ícone E/trono nítido no painel real, sem widget duplicado, persistente; menu de contexto intacto.
4. Render real do Settings/Welcome em pt_BR e inglês, teclado, 125/150/200 %, 1920×1080 e telas menores.
5. Splash, plasma-setup, bloqueio, login; pastas violeta; contraste visto no tema claro e no escuro.
6. Decisões do proprietário: remover os wallpapers procedurais antigos; refazer os ícones do Settings/Welcome
   (hoje coroa recolorida); aprovar o splash violeta único para os dois perfis.

## 12. GO / NO-GO

- **GO para revisão visual na próxima VM** (fonte consistente, testes estáticos verdes, requisitos 1–9 do prompt
  implementados na fonte).
- **NO-GO para declarar “homologado” ou “aprovado visualmente”:** nada foi visto no Plasma real; a restauração
  do wallpaper e o padrão do `defaults` dependem de comportamento do Plasma 6.6 não verificado aqui.
