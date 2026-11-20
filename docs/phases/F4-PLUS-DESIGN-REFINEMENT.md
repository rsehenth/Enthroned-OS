# F4+ — Refinamento visual do desktop

Fase exclusivamente de apresentação. Nenhuma lógica funcional, backend, consentimento, permissão ou serviço foi alterado.

**Estado:** DESIGN IMPLEMENTED · STATIC VERIFIED · **NOT RUN** (sem Qt/KDE nesta máquina) · **VISUAL REVIEWED: não** · **KDE RUNTIME VERIFIED: não**

## Estado encontrado

F1–F4 presentes no código: esquemas Light/Dark, Enthroned Launcher (plasmoid), perfis Classic/Modern, Settings, Update Center e Welcome (5 etapas). Nada foi executado em KDE; nenhuma captura de tela existe.

## Design system (consolidado, não substituído)

A paleta e a identidade F2 foram mantidas. Mudanças:

| Item | Antes | Agora |
|---|---|---|
| Contraste de texto | Light: `Inactive` 4,10 / 3,68, `Positive` 3,20, `Negative` 3,99, `Neutral` 2,55 (abaixo de AA); alguns pares do Dark < 4,5 | **208 pares** fg/bg (Window, View, Button, Header, Tooltip, Selection) medidos: todos ≥ 4,5:1 |
| Texto secundário | `disabledTextColor` (= `ForegroundInactive` no Kirigami) abaixo de AA no Light | Corrigido na raiz, vale para todas as páginas |
| Tokens | cores, espaçamento, alturas | + raios, elevação, movimento, papéis tipográficos, estados (hover/pressed/selected/focus), mapeamento semântico |
| Painéis | Classic 40 px · Modern 44 px | Classic **44 px** · Modern **48 px** (alvos ≥ 44 px) |

Regras: sem cor fixa em QML (validadores continuam exigindo); raios derivados de `Kirigami.Units.smallSpacing`; durações de `Kirigami.Units.shortDuration`, que Plasma zera quando o usuário desativa animações (equivale a reduzir movimento). Detalhes em `design-tokens.json`.

## Componentes refinados

**Launcher** — botão com camada de estado (hover/pressed/menu aberto); `ItemBackground.qml` (novo, uma camada de estado única para sidebar e lista); barra de acento + negrito na categoria atual; anel de foco por teclado; título do painel (categoria ou "Resultados da pesquisa"); estado vazio com orientação; separador de rodapé; rodapé com nome do usuário e botão "Sessão e energia" com rótulo visível; itens desabilitados atenuados; linha separadora que antes tinha altura zero.

**Settings** — navegação lateral com hover/seleção/foco e barra de acento; largura em `gridUnit`; `InfoRow` e `EmptyState` sem largura rígida nem itálico; cartões da Início navegáveis por teclado (Tab/Enter/Espaço) com anel de foco; `StatusIcon.qml` (novo) com tom semântico; `ProfilePreview.qml` (novo) em Aparência; larguras de diálogos e listas escaláveis.

**Update Center** — disco de estado com tom (positivo = atualizado; informativo = verificando/atualizando/disponível; neutro âmbar = reinicialização; negativo = falha; cinza = desconhecido/sem rede/serviço indisponível, que nunca sugere atualização); chip "Modo de demonstração" junto ao estado; mensagens calmas para reinicialização e falha com ação possível. Nenhum botão, porcentagem ou binding de estado foi tocado.

**Welcome** — indicador de etapas em segmentos (era ponto de 4 px); largura de leitura limitada e centralizada; separador acima do rodapé; prévia de perfil nos cartões; resumo final com rótulos estáveis e ícones só para estados reais detectados; ArtCraft: "Saber mais" discreto (flat), escolha numa superfície própria, caixa continua **desmarcada por padrão**.

## Correções de defeitos latentes encontrados

- `UpdatesPage`/`HomePage`: `BusyIndicator` e `ProgressBar` sem prefixo `QQC2.` (não resolvem com `import QtQuick.Controls as QQC2`).
- `HomePage`: `QQC2.MouseArea` não existe; agora `MouseArea` (QtQuick).
- `AppearancePage`: miniaturas apontavam para `640x360.png`, inexistente; agora `1920x1080.png`.

Estas três podiam impedir o carregamento ou deixar miniaturas vazias; **não confirmado em execução**.

## Fora do escopo / dependências técnicas

- Atalho "Configurações" no launcher: exigiria uma nova ação de lançamento (lógica); não implementado.
- Densidade de ícones do `icontasks` e formato do relógio: chaves de configuração não verificadas na documentação; não alteradas.
- `ProfilePreview.qml` existe em duas cópias idênticas (Settings e Welcome são binários separados, sem módulo QML compartilhado).
- Pré-visualização usa o esquema de cores **atual**, não as cores do perfil mostrado; o texto do cartão informa o esquema.

## Verificação

Executadas: `validate-desktop.sh` (todos OK), `validate-settings.sh` (228/0), `validate-welcome.sh` (todos OK; contador de QML 7→8), `verify-source.sh` (14 ok/2 avisos preexistentes/0 falhas), `settings/tests` e `welcome/tests` (228 e 85, 0 falhas), contraste dos `.colors` (script de análise).
Não executadas: `qmllint`, `cmake`/Qt (ausentes), build OCI, VM, sessão KDE.

## Pendências para homologação visual

1. Abrir Settings, Welcome e o launcher em Plasma 6.6 nos dois esquemas e conferir hover/foco/seleção.
2. Conferir `ProfilePreview` (proporção, cantos, painel flutuante) e miniaturas de papel de parede.
3. Medir painéis 44/48 px com escala 100–200 % e fontes grandes; ajustar se o cluster Modern ficar apertado.
4. Confirmar que `Kirigami.Separator`, `T.ItemDelegate` e `explanation` do `PlaceholderMessage` carregam sem avisos.
5. Teste de teclado completo (Tab, setas, Enter, Espaço) e leitor de tela.
