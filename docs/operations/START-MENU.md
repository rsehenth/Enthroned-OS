# Menu Iniciar do Enthroned OS (Lote 3)

Classificação: **SOURCE READY / STATIC VERIFIED**. Nada foi compilado nem
executado em Plasma/Qt/VM. Não há captura de tela nem medição de desempenho:
nenhum ganho de velocidade está provado, apenas previsto pelo código.

O `org.enthroned.launcher` continua sendo o mesmo plasmoid (modelos kicker do
Plasma 6.6, mesmo `metadata.json`, mesma configuração `main.xml`). O Lote 3
evoluiu a interface; não existe um segundo launcher.

## Base de API

Alvo: KDE Plasma 6.6 (`X-Plasma-API-Minimum-Version: 6.0`, Aurora/Fedora 44).
Os contratos usados foram conferidos no código-fonte de
`plasma-desktop/applets/kickoff` (branch `Plasma/6.6`) em 2026-11-17:

| Uso | Contrato conferido |
| --- | --- |
| Modelos | `Kicker.RootModel`, `RunnerModel`, `SystemModel` (já usados desde F2.1) |
| Linha do `SystemModel` | `favoriteId` (`lock-screen`, `suspend`, `reboot`, `shutdown`, `logout`…) e `trigger(row, "", null)` |
| Papel por nome | `model.KItemModels.KRoleNames.role("favoriteId")` (como em `LeaveButtons.qml`) |
| Favoritos | `favoritesModel.isFavorite / addFavorite / removeFavorite / moveRow(from, to)` |
| Ações do .desktop | papéis `hasActionList` e `actionList`; execução por `model.trigger(row, actionId, argument)` |
| Menu de contexto | `PlasmaExtras.Menu` como valor de propriedade + `Instantiator` irmão (padrão do `ActionMenu.qml` do kickoff) |
| Tamanho | `Screen.desktopAvailableWidth/Height` (mesmo anexo usado pelo kickoff) |

O escopo dinâmico do id `launcher` (definido em `main.qml`) é o mesmo padrão
que o kickoff usa com o id `kickoff` entre arquivos; foi mantido. Os delegates
deixaram de depender dele: recebem o `AppActions` por propriedade `required`.

## Layout final

```
+--------------------------------------------------------------+
| [logo] [ Pesquisar no computador                           ] |
+-------------+-----------------------------+------------------+
| Fixados     |  Título do painel           |  Locais          |
| Todos os    |  grade de fixados | lista   |   Pasta pessoal  |
|  aplicativos|  (ou resultados da busca)   |   Documentos     |
| ----------- |                             |   Downloads      |
| Categorias  |                             |   Imagens        |
|  (KDE menu) |                             |  Ferramentas     |
|             |                             |   Arquivos, ...  |
+-------------+-----------------------------+------------------+
| [avatar] Nome / Enthroned OS        [Bloquear] [Sessão e energia]
+--------------------------------------------------------------+
```

- **Cabeçalho:** ícone do launcher (recurso existente, sem logotipo novo) e
  campo de busca em destaque. Trocar a marca definitiva = trocar o recurso do
  ícone; não há código a mudar.
- **Barra lateral esquerda (Zorin):** "Fixados", "Todos os aplicativos" e, sob
  um separador, as categorias do menu do KDE.
- **Painel principal (Windows 11):** grade de blocos para os fixados; lista
  para "Todos os aplicativos", categorias e resultados da busca.
- **Coluna direita (Locais/Ferramentas):** pastas XDG e ferramentas, largura
  fixa de 9,5 gridUnits (`Layout.fillWidth: false`: o padrão de um layout é
  preencher e ela dividia com a lista o espaço que sobrava). Abaixo de 45
  gridUnits de popup vira só ícones com dica.
- **Rodapé:** conta (abre Contas de usuário), botão Bloquear e menu
  "Sessão e energia".

Tamanho (Lote 15): até 50 × 36 gridUnits, **limitado à área útil da tela** menos 2
gridUnits; mínimo 30 × 22. O painel central nunca fica abaixo de 14 gridUnits. A lista rola quando falta espaço (verificado só
por leitura do código; ver pendências).

## Organização das categorias

As categorias vêm de `rootModel` (menu de aplicativos do KDE, `flat`,
`sorted`): nomes traduzidos, ícones e arquivos `.desktop` reais. Não há lista
fixa de aplicativos. Linha 0 = Fixados, linha 1 = Todos os aplicativos,
linhas 2+ = categorias. "Todos os aplicativos" é uma lista única sem
repetição; um aplicativo só aparece em mais de uma categoria se o próprio menu
do KDE o classificar assim (o launcher não altera isso).

"Ferramentas" (Gerenciador de arquivos, Configurações, Loja de aplicativos,
Terminal) só aparecem se o `.desktop` correspondente existir em "Todos os
aplicativos" (`org.kde.dolphin`, `systemsettings`, `org.kde.discover`,
`org.kde.konsole`).

## Busca

- `RunnerModel` (KRunner) com `mergeResults`: usa os executores que o usuário
  tem habilitados (aplicativos, configurações, arquivos se o Baloo estiver
  ativo etc.). Nenhum índice próprio, nenhuma consulta de rede feita pelo menu.
  Executores como atalhos web só agem ao serem ativados pelo usuário.
- A ordem é a do KRunner (relevância dentro de cada grupo); os grupos viram
  cabeçalhos de seção. O launcher não reordena.
- Nome e descrição: a descrição aparece como segunda linha do resultado.
- Teclado: o foco permanece no campo; **↑/↓** movem a seleção da lista visível,
  **Enter** abre o item selecionado (o primeiro por padrão), **Esc** limpa a
  consulta e, com o campo vazio, fecha o menu. Ao abrir, o foco vai para o
  campo.
- Estados: "Pesquisando…" (enquanto o executor consulta), "Nenhum resultado" e,
  nos fixados, "Nenhum aplicativo fixado" com a orientação para fixar.
- O texto do campo é "Pesquisar no computador" de propósito: o que é
  encontrado depende dos executores habilitados.

## Fixados e personalização

- Armazenamento: `KActivitiesStats` por instância
  (`org.enthroned.launcher.favorites.instance-<id>`), o mesmo mecanismo do
  kickoff; persiste entre sessões. A lista inicial (`main.xml`) é portada uma
  única vez e só se o repositório de favoritos estiver vazio; escolhas do
  usuário nunca são sobrescritas. Sem favoritos o menu funciona (estado vazio).
- Menu de contexto (botão direito, **tecla Menu** ou toque longo) em qualquer
  aplicativo: ações do `.desktop` (ex.: nova janela), **Fixar/Desafixar** e, na
  grade de fixados, **Mover para o início / antes / depois**.
- Não suportado neste lote: arrastar e soltar para reordenar.

## Atalhos de teclado

| Tecla | Efeito |
| --- | --- |
| Meta | Abre/fecha o menu (atalho global gravado pelos layouts Classic e Modern; sem conflito conhecido com o Plasma) |
| Clique no botão do painel | Abre/fecha |
| Esc | Limpa a busca; com busca vazia fecha |
| ↑ ↓ (no campo) | Navega nos itens visíveis |
| Enter | Abre o item selecionado |
| → na barra lateral / ← na lista | Troca o foco entre barra e lista |
| Tab | Campo → barra → lista → locais → rodapé |
| Menu / botão direito | Menu de contexto do item |

## Integração com Classic e Modern

Uma única base de código. As duas identidades vêm dos tokens do Plasma: cores
do esquema ativo (`EnthronedLight`/`EnthronedDark`), raios derivados de
`Kirigami.Units.smallSpacing`, durações de `Kirigami.Units.shortDuration` (zero
quando o usuário desliga animações). O Classic ancora o popup no painel sólido;
o Modern o ancora no painel flutuante; quem posiciona é o Plasma. **Não há
código específico por perfil**: o launcher não detecta o perfil. Diferenças
visuais além do esquema de cores e do painel não foram implementadas.

## Estabilidade

- `Type FullRepresentation unavailable`: o único módulo opcional
  (`Qt.labs.platform`) foi isolado em `XdgFolders.qml`, carregado por `Loader`.
  Se faltar, somem os atalhos de pastas; o menu continua. O validador
  (`validate-desktop.sh`, seção "launcher L3") impede `Qt.labs` em
  `FullRepresentation.qml`.
- `Cannot assign object of type QQmlInstantiator…`: o menu de contexto
  (`AppActions.qml`) e o de energia usam `Instantiator` **irmão** do
  `PlasmaExtras.Menu`; o validador falha se alguém aninhar um dentro do outro.
- Fallback Kickoff: inalterado (layout script com `try/catch`; "Mostrar
  alternativas" no botão direito). Nenhum segundo botão foi adicionado.
- Ao fechar: a busca é limpa, a categoria volta para "Fixados", o menu de
  contexto é um popup do Qt (fecha com a janela). Nenhum processo residente,
  timer ou `Loader` ativo sem necessidade.

## Desempenho (previsto, não medido)

- Só a visão visível recebe modelo (grade de fixados ou lista); a outra fica
  sem delegates.
- Removido o `Loader` por linha de `AppListDelegate`; a lista usa
  `reuseItems`. Linhas simples em listas normais; segunda linha só na busca.
- A varredura de "Todos os aplicativos" (ferramentas) roda uma vez por
  `refreshed`, nunca ao digitar.
- Sem blur, sombras ou animações além das de estado de 1 retângulo.
  Ganho real: **não medido**.

## Limitações conhecidas

1. Nunca executado em Plasma; layout, foco e pop-up não foram vistos.
2. Textos em português do Brasil direto nas chamadas `i18n()`; não há
   catálogo `.po`, então outros idiomas verão português (nomes de categorias e
   de aplicativos continuam traduzidos pelo KDE). Dependem do KDE:
   nome de pasta XDG e rótulos do menu de energia.
3. Pastas XDG: `QStandardPaths` não verifica se o diretório existe; se o
   usuário apagou "Imagens", o atalho abre erro no gerenciador de arquivos.
4. Se o `Qt.labs.platform` não existir na imagem, não há atalhos de pastas
   (nem "Pasta pessoal").
5. Favoritos são por instância do applet: recriar o applet (reaplicar o perfil)
   gera um repositório vazio e a lista padrão é portada de novo.
6. Sem arrastar e soltar; sem "recentes".
7. Sem detecção de perfil Classic/Modern dentro do launcher.
8. `scripts/test-layouts.mjs` já estava falhando antes do Lote 3: espera um
   Kickoff de recuperação com `Alt+F1` que os layouts atuais não criam (ver
   relatório do lote). Não alterado.

## Ícone por perfil (Lote 13)

O botão Iniciar usa o **E** do Enthroned no Classic (`org.enthroned.launcher-classic`) e o **trono** no
Modern (`org.enthroned.launcher-modern`), ambos PNG hicolor (16–512 px) derivados dos assets originais.
O layout de cada perfil grava `General/icon` no applet a cada reset de layout (`enthroned-profile apply`),
inclusive no Kickoff de recuperação; o padrão do `main.xml` é o ícone Classic. O cabeçalho do menu aberto
(`FullRepresentation.qml`) mostra o mesmo ícone a 32 px. Teste estático: `scripts/test-layouts.mjs`.

**Lote 14:** o ícone do botão agora preenche o botão (margem de 3 px) e não é mais arredondado para baixo ao
tamanho padrão (antes: 40/36 px viravam 32 px); os PNGs não mudaram. Detalhes e medições em
`docs/validation/LOTE-14-POST-H6-FIXES.md`.
