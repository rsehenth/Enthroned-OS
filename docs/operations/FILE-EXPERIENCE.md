# Lote 2 — Janelas e Explorador de arquivos (Enthroned File Experience)

Classificação: **SOURCE READY / STATIC VERIFIED**. Nada foi compilado, instalado
nem executado em KDE/VM. Chaves e formatos foram conferidos no código-fonte
upstream (KIO `kfileplacesmodel.cpp`/`kfileplacesitem.cpp`, Dolphin
`dolphin_generalsettings.kcfg`, `dolphinui.rc`, `viewproperties.cpp`, master);
o comportamento em execução na versão da imagem (Plasma 6.6 / Fedora 44) **não**
foi observado.

## 1. Estratégia: configurar, não construir

Dolphin já traz abas, breadcrumb, busca, voltar/avançar/subir, painéis,
miniaturas, modos Ícones/Compacto/Detalhes e os atalhos do Windows (F2, Ctrl+C/X/V/Z,
Ctrl+T, Ctrl+W, Ctrl+Shift+N, Alt+←/→/↑, Ctrl+L). **Nenhum executável novo, fork,
serviço residente ou atalho global foi criado.**

| Camada | Onde fica | Mecanismo |
| --- | --- | --- |
| Comportamento geral | `/etc/xdg/dolphinrc` | Default de sistema; `~/.config/dolphinrc` sempre vence |
| Duplo clique | `/etc/xdg/kdeglobals` `[KDE] SingleClick=false` + L&F `defaults` | KDE lê essa chave em `kdeglobals` |
| Lugares (Places) | `~/.local/share/user-places.xbel` | `enthroned-files-setup` (aditivo, 1×/usuário) |
| Modo Detalhes global | `~/.local/share/dolphin/view_properties/global/.directory` | idem, só se o arquivo não existir |
| Barra de ferramentas | `~/.local/share/kxmlgui6/dolphin/dolphinui.rc` | idem; versão lida do `dolphinui.rc` instalado |
| Janelas | `breezerc`, `Enthroned{Light,Dark}.colors` | Decoração Breeze + esquema de cores |

### Por que um script de primeiro login

Places, modo de visualização e toolbar vivem na **home** do usuário, e o Places
contém caminhos absolutos e nomes localizados. Copiar um arquivo para `/etc/skel`
estaria errado para outros usuários e para pt-BR. `enthroned-files-setup`
(`/usr/libexec`, disparado por `/etc/xdg/autostart/org.enthroned.files-setup.desktop`,
termina em milissegundos, não é serviço):

- Lê as pastas XDG **reais** de `~/.config/user-dirs.dirs` (já localizadas pelo
  `xdg-user-dirs-update`; roda-o se ainda não existir). Nunca cria nem renomeia pastas.
- **Sem xbel**: grava o conjunto completo, versão 4 do formato do KIO:
  Início, Área de Trabalho, Downloads, Documentos, Imagens, Músicas, Vídeos, Rede, Lixeira.
- **Com xbel** (usuário existente/atualização): só acrescenta Imagens/Músicas/Vídeos
  se faltarem; nunca remove, reordena ou reescreve entradas. Reaparecer após o usuário
  remover é impedido pelo marcador `~/.local/state/enthroned-os/files-setup`.
- Dispositivos, discos removíveis, Rede e Lixeira são nativos (Solid/udisks/KIO):
  rótulos, pontos de montagem e nomes reais; **nenhuma letra C:/D: é inventada**.
- "Recentes": o KDE acrescenta sozinho *Arquivos recentes/Locais recentes* quando
  `kio-extras` está presente (não escrevemos esse trecho).
- Toolbar e `.directory`: criados só se ausentes. Uma toolbar escrita pelo script
  (marcada com comentário) é regravada apenas quando a versão da UI do Dolphin muda;
  uma edição do usuário nunca é tocada. Versão desatualizada é ignorada pelo KXmlGui
  (cai no padrão do Dolphin, sem erro).
- Falha em qualquer passo: log em stderr (journal do usuário), sessão segue, marcador
  não é gravado e o passo é repetido no próximo login.

## 2. Nativo × exigiu alteração

| Pedido | Situação |
| --- | --- |
| Abas, breadcrumb, busca, voltar/avançar/subir, modos de visualização, ordenação, painéis, miniaturas, atalhos | **Nativo do Dolphin** (apenas padrões ajustados) |
| Aba sempre visível, status bar de largura total, breadcrumb, ordenação natural | `dolphinrc` |
| Detalhes (Nome, Modificado, Tipo, Tamanho), pastas primeiro | `.directory` global (1º login) |
| Toolbar: ← → ↑ breadcrumb busca │ Novo, Recortar, Copiar, Colar, Renomear, Lixeira │ Visualização, Dividir, Menu | `dolphinui.rc` do usuário (1º login). Ações são as do próprio Dolphin |
| Lugares Imagens/Músicas/Vídeos | `enthroned-files-setup` |
| Duplo clique | **Correção**: `SingleClick` estava em `kcminputrc` (chave ignorada); movida para `kdeglobals` |
| Código novo | Somente o script acima (Python 3 stdlib, já presente no Fedora) |

## 3. Diferenças inevitáveis em relação ao Windows 11

- **Ordem do Places**: os grupos do KDE têm ordem fixa (Lugares → Recentes → Dispositivos →
  Rede/Remoto → Removíveis). Não é possível "Recentes" 2º, "Rede" antes da "Lixeira" etc.;
  a Lixeira fica no fim do grupo *Lugares*. Grupos permanecem intuitivos.
- "Início" aparece com o rótulo traduzido pelo KDE ("Pasta pessoal"). "Este Computador" =
  grupo *Dispositivos*.
- Dolphin tem **uma** barra de ferramentas (sem a segunda faixa "Novo / Classificar / Exibir"
  do Explorer); as ações rápidas foram colocadas ao lado do breadcrumb e excedentes vão ao menu `»`.
- **Painel de informações**: existe (*Informações*, **F11**) mas fica fechado por padrão: o
  estado dos painéis é salvo em `dolphinstaterc` (blob de estado da janela), frágil de semear.
- Miniaturas: ficam como o Dolphin decide (ligadas em Imagens/Vídeos etc., desligadas na raiz
  global por custo); documentos dependem de `kdegraphics-thumbnailers`/`kio-extras` na imagem.
- Mudar o idioma depois do 1º login **não** renomeia pastas XDG (comportamento do
  `xdg-user-dirs`; evita pastas duplicadas e quebra de referências). Valores `PUBLICSHARE`
  e `TEMPLATES` ficam como o `xdg-user-dirs` da imagem define.
- Ícones: Breeze (`breeze`/`breeze-dark`); nenhum asset do Windows foi usado.

## 4. Janelas e perfis

| Item | Classic (claro) | Modern (escuro) |
| --- | --- | --- |
| Esquema | `EnthronedLight` | `EnthronedDark` |
| Ícones | `breeze` | `breeze-dark` |
| Decoração | Breeze, borda *Tiny*, botões `IAX` à direita, cantos arredondados, título à esquerda | idem |
| Realce (Selection/highlight) | `#6F26A8` | `#9A3DD6` |

> Lote 13: paleta violeta derivada dos assets originais; ver `docs/architecture/ENTHRONED-DESIGN-SYSTEM.md`.

Correções de coerência (código-fonte, não verificadas visualmente):

- Barra de título e `[Colors:Header]` (que pinta a toolbar do Dolphin) agora usam **a mesma
  cor** nos dois esquemas, ativa e inativa; antes `[WM]` e *Header* divergiam (no escuro a
  janela inativa ficava *mais clara* que a ativa).
- `breezerc`: sombra `ShadowLarge`/180 → `ShadowMedium`/150 (menor custo em renderização por
  software). Blur do KWin e demais efeitos **não** foram alterados (hipótese de custo segue em
  `NEXT-HOMOLOGATION.md` §1/§4).
- Separação lateral/arquivos/cabeçalho vem dos papéis do esquema: Window (painel lateral),
  View (lista), Header (título + toolbar).

## 5. Checklist para a próxima homologação (não executar agora)

Usuário **novo** (pt-BR) e usuário **existente** com bookmarks próprios:

1. Dolphin abre em Detalhes, abas visíveis, toolbar ← → ↑ + breadcrumb + busca + ações rápidas.
2. Places mostra Início, Área de Trabalho, Downloads, Documentos, Imagens, Músicas, Vídeos.
3. Nomes de pastas em pt-BR, sem duplicatas em inglês (`ls ~`, `cat ~/.config/user-dirs.dirs`).
4. Dispositivos: discos internos/removíveis com rótulo e ponto de montagem reais (sem C:/D:).
5. Rede (`remote:/`) e Lixeira abrem e esvaziam; "Recentes" aparece (kio-extras).
6. Ctrl+T, Ctrl+W, clique-médio em pasta, arrastar aba; pasta aberta por outro app vira aba.
7. Breadcrumb (clique e Ctrl+L) e busca (Ctrl+F) funcionam.
8. Ícones / Compacto / Detalhes e ordenação por nome, tipo, tamanho, modificação.
9. F11 abre Informações; F3 divide a janela.
10. Copiar/Recortar/Colar/Desfazer, F2, Ctrl+Shift+N, Excluir pede confirmação, Shift+Del.
11. Duplo clique abre; clique simples apenas seleciona.
12. Classic × Modern: título/toolbar com a mesma cor, janela inativa mais escura que ativa,
    diálogos legíveis; trocar de perfil não perde Places/toolbar.
13. Sem lentidão perceptível ao abrir o Dolphin e rolar pastas com miniaturas (comparar 3D off/on).
14. Reboot: Places, modo Detalhes e toolbar persistem; `~/.local/state/enthroned-os/files-setup` = `1`.
15. Usuário existente: bookmarks e `dolphinrc` próprios intactos; só Imagens/Músicas/Vídeos
    acrescentados (se ausentes). Se a toolbar não aparecer, `journalctl --user | grep enthroned-files-setup`
    e conferir `~/.local/share/kxmlgui6/dolphin/dolphinui.rc` (versão = a de
    `/usr/share/kxmlgui6/dolphin/dolphinui.rc`).

Pontos de maior risco (formato não observado em execução): XBEL escrito à mão (se o
Dolphin regravar/ignorar, ele recria os padrões do KDE sem perda), `ShowStatusBar=FullWidth`
(enum por nome) e a toolbar via `kxmlgui6`.
