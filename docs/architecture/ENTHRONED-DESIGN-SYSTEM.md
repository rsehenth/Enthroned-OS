# Enthroned OS — Design System

- **Versão:** Lote 13 (consolida `design-tokens.json` schema 2 e o refinamento F4+).
- **Fonte de verdade dos valores:** `system_files/usr/share/enthroned-os/branding/design-tokens.json`
  e os dois esquemas `system_files/usr/share/color-schemes/Enthroned{Dark,Light}.colors`.
- **Este documento** explica o *porquê* e as regras de uso. Em conflito, vale o JSON.
- **Sem `DESIGN.md` separado:** este arquivo + o JSON de tokens são o equivalente
  (a skill `impeccable` só exige `DESIGN.md` quando não há documento equivalente).

## 1. Identidade (DNA extraído dos assets originais)

Medido por clusterização de cor nos arquivos de `assets/` (nada é estimado “de olho”):

| Papel | Valores medidos | Origem |
| --- | --- | --- |
| Violeta quase preto | `#070113` `#120428` `#1C063A` `#2A0C50` | wall3 (fundo dominante, ~77 % da área) |
| Violeta médio | `#3D156C` `#5E2596` | wall3, brilhos das ondas |
| Acento magenta-violeta | `#8922B8` `#932EBF` | E, trono e logotipo (estrelas e arestas) |
| Realce lilás | `#9B66BD` | wall3 |
| Prata | `#E0D4E5` `#A996B3` | metal cromado do E, do trono e do logotipo |

Caráter: sóbrio, noturno, nobre; o acento brilha **em pontos** (estrelas, arestas), não em superfícies
inteiras. A interface imita isso: superfícies escuras e calmas, acento usado em estados e indicadores.

## 2. Cores

Dois esquemas KDE nativos; os componentes só usam `Kirigami.Theme.*` (nunca hex), exceto os splashes
(`#120428`), que renderizam antes de qualquer esquema existir.

| Token | Enthroned Dark (Modern) | Enthroned Light (Classic) |
| --- | --- | --- |
| Superfície (Window) | `#17111F` | `#F6F3FA` |
| Superfície alternada (sidebar, listras) | `#120D1A` | `#ECE7F3` |
| View | `#1C1626` | `#FDFCFF` |
| Elevada (Button, Tooltip) | `#241D32` | `#EFEAF6` |
| Texto | `#ECE7F4` | `#1E162C` |
| Texto secundário | `#ADA2BF` | `#5A5070` |
| Acento / seleção (Selection, “highlight”) | `#9A3DD6` | `#6F26A8` |
| Foco / hover (DecorationFocus) | `#B684EA` | `#7A32BE` |
| Link | `#BC8EEA` | `#6A25A6` |
| Positivo / Neutro / Negativo | `#45CB93` / `#E8A64A` / `#F28A9B` | `#17693F` / `#855210` / `#A8344A` |

Regras:

1. **Um acento só (violeta).** Prata é de logotipo e destaque pontual, não de controles.
2. **Cor nunca sozinha:** estado = cor + ícone/texto/forma (barra de seleção de 3 px, selo “Padrão”).
3. **Semânticas** (verde/âmbar/vermelho) sempre com ícone e rótulo.
4. O acento de seleção também é o “highlight” do Breeze (barra de progresso, switch, slider): por isso
   precisa de ≥ 3:1 contra as superfícies **e** carregar texto branco a ≥ 4,5:1. Os tons secundários
   sobre a seleção (`ForegroundInactive` etc.) são tintas claras da própria matiz.
5. Alterar cores = editar `scripts/gen-color-schemes.py` e rodá-lo (grava os `.colors` e **falha** se
   algum par ficar abaixo de 4,5:1 / 3:1). Nunca editar os `.colors` à mão.

Auditoria: 268 pares (134 por esquema) sem falhas; foco e highlight ≥ 3:1. Cálculo estático — não confirmado
em sessão Plasma real.

## 3. Tipografia

Fonte do sistema (Noto Sans); o projeto não embute nem troca fontes. Hierarquia: título de página (toolbar do
Kirigami) → `Kirigami.Heading` nível 1–2 (cartões de identidade/estado) → **`SectionHeading`** (nível 3,
semibold, mais espaço acima que abaixo) → texto → secundário (`disabledTextColor`) → legenda (`smallFont`).
Números de dados e versões em fonte normal; sem monoespaçada decorativa.

## 4. Espaço, forma e elevação

- Escala: 4 · 8 · 12 · 16 · 24 · 32 px (via `Kirigami.Units.smallSpacing/largeSpacing`).
- Raios: controle ×1,5, superfície ×2, sobreposição ×3 de `smallSpacing` (6/8/12 px).
- Alvos interativos: ≥ 36 px (navegação do Settings 38 px); painéis ≥ 44 px.
- Elevação: plana. Separação por cor alternada + separador 1 px. Sombra só do compositor.

## 5. Estados

| Estado | Tratamento |
| --- | --- |
| Hover | camada `highlightColor` a 10 % |
| Pressed | camada a 20–22 % |
| Selected | camada a 16 % + barra de acento 3 px (+ texto semibold na navegação) |
| Focus | anel `DecorationFocus` de 2 px, sempre visível por teclado |
| Disabled | desaturação nativa (`ColorEffects:Disabled`) |
| Animação | só `Kirigami.Units.*Duration` (zera quando o usuário desliga animações) |

## 6. Componentes reutilizáveis (Settings)

| Componente | Uso |
| --- | --- |
| `SectionHeading` | título de grupo de configurações (único estilo) |
| `BrandWordmark` | logotipo completo original; fallback para o símbolo E; reserva espaço pela proporção do arquivo |
| `InfoRow` | par rótulo/valor; “Indisponível” quando não há dado real |
| `ShortcutTile` | atalho clicável com foco, hover e teclado |
| `StatusIcon` | disco de tom + ícone para o estado de atualização (tom ≠ única informação) |
| `EmptyState` | listas vazias/fontes indisponíveis, sem conteúdo inventado |
| `ProfilePreview` | miniatura esquemática do perfil (cópia idêntica no Welcome) |

Cartões (`AbstractCard`) agrupam **uma** ideia; cartão dentro de cartão é proibido.

## 7. Logotipos e ícones

| Asset original | Derivado instalado | Uso |
| --- | --- | --- |
| `E Logo-2.png` (roxo/cromado) | `org.enthroned.launcher-classic`, `org.enthroned.enthroned-os` (hicolor 16–512) | botão Iniciar Classic; logo do sistema, Sobre, Settings, Welcome (fallback) |
| `Enthroned Throne-2.png` | `org.enthroned.launcher-modern` | botão Iniciar Modern |
| `EnthronedLogo-2.png` | `branding/enthroned-wordmark.png` (+ 720 px nos splashes) | Sobre, Welcome, splash |
| `E Logo.png`, `Enthroned Throne.png`, `EnthronedLogo.png` (brancos/prata) | `enthroned-wordmark-mono.png` | **somente** sobre fundo escuro; nunca como ícone sobre superfície clara |

Por que a variante colorida nos ícones: a branca do E tem ~1,1:1 sobre o painel claro do Classic; a colorida
mantém a silhueta nos dois temas. Derivação (`scripts/gen-brand-assets.py`): recorte ao desenho, tela
quadrada, Lanczos em alfa pré-multiplicado, leve nitidez ≤ 48 px. **Nada é redesenhado**; originais intactos.
Área livre ≥ 1/8 da altura; nunca esticar, recolorir ou colocar sobre imagem movimentada.

Pastas do Dolphin (`Enthroned`, `EnthronedDark`): duas camadas violeta (`#5E2596` / `#8B38C2`) com glifo branco.

## 7.1 Wallpapers

Três pacotes KPackage nativos, originais byte-idênticos (1672×941; o Plasma escala): **Enthroned — Soberania**
(wall1), **Ascensão** (wall2), **Vigília** (wall3, padrão). O padrão é declarado só nos `defaults` do
look-and-feel (+ bloqueio/login); nada reaplica no login; a troca de perfil restaura a escolha do usuário.

## 8. Classic × Modern

Mesma identidade, duas densidades. Compartilham: paleta violeta, wallpaper padrão, splash, tipografia,
estados, componentes. Diferem **apenas** em: tema (claro/escuro), painel (sólido 44 px/flutuante 48 px),
posição do cluster, relógio e ícone do Iniciar (E × trono).

## 9. Proibido (critério “no-slop”)

Gradientes decorativos sem função · bordas roxas luminosas em tudo · sombras de 24 px+ · glassmorphism ·
cartões aninhados · rótulos “eyebrow” · animação em hover por transformação · ícones fora do conjunto do
tema · hex em componente · sobrepor logotipo a imagem movimentada.

## Gate 13.1 — estrutura de página do Settings
- Toda página herda `qml/components/SettingsPage.qml` (Kirigami.ScrollablePage com largura de leitura de 56 gridUnits,
  medida em gridUnits para acompanhar fonte/escala; barra de rolagem na borda da janela).
- `Main.qml` mostra um cabeçalho fixo (ícone + título nível 1) alinhado ao conteúdo; a barra global vazia do Kirigami foi removida.
- Hierarquia: título da página (H1) › nome do cartão de identidade (H2) › `SectionHeading` (H3, mais espaço acima que abaixo).
- `ModuleCard` não usa mais `opacity` para indicar indisponibilidade (reduzia o contraste); o botão desabilitado e a nota bastam.
- Ícones de aplicativo: Settings = E (`E Logo-2`), Welcome = trono (`Enthroned Throne-2`); a variante contornada
  (`E Logo`, `Enthroned Throne`) só funciona sobre um fundo e não é usada como ícone.

