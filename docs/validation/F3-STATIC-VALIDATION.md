# Validação estática F3 — Configurações & Central de Atualizações

- **Data:** 2026-11-16
- **Ambiente:** host Windows 11 (WSL bash 5.3, node 26.13, python 3.14)
- **Escopo:** sem Qt/KDE, sem build OCI, sem VM, sem rede (além da pesquisa
  de contratos), sem alterações no host.

## Resultados executados nesta sessão

| Verificação | Comando | Resultado |
| --- | --- | --- |
| Checagens estáticas F3 (JSON/XML/QML/C++/empacotamento/polkit/unidade) | `bash scripts/validate-settings.sh` | **210 PASS / 0 FAIL** |
| Testes de lógica (spec executada com fixtures: máquina de estados, journal_mapping, bootc_progress, 12 cenários) | `node settings/tests/run-tests.mjs` | **228 PASS / 0 FAIL** |
| Regressão F2 (camada desktop) | `bash scripts/validate-desktop.sh` | **116/116 PASS** (exit 0) — baseline intacto |
| Regressão F1 (política de origem) | `bash scripts/verify-source.sh` | **14 PASS / 2 WARN / 0 FAIL** — baseline intacto |
| Sintaxe bash (todos os scripts, incl. novos) | `bash -n` | PASS em todos |

## O que os testes de lógica executam de fato

- **Máquina de estados**: cada evento de cada um dos 12 cenários fixtures é
  aplicado à tabela declarativa (`update-state-spec.json`); checkpoints por
  passo + estado final. Semânticas espelham o interpretador C++
  (primeira regra que casa vence; guardas exigem contexto verdadeiro).
- **journal_mapping**: linhas reais de journal (envelope `MESSAGE` com slog
  JSON do uupd) → eventos normalizados, incluindo linhas inválidas
  (→ `unknown-data`, nunca mudam estado) e mensagem ignorada.
- **bootc_progress**: janelas de porcentagem idênticas ao PROGRESS_STAGES do
  uupd (ex.: `pulling` 50/100 bytes → 40%; `staging` 5/10 steps → ~94,55%)
  e emissão de `bootc-download-finished` na transição saindo de `pulling`.
- Casos cobertos pelos cenários: sistema atualizado; atualização disponível;
  download; preparação; falha; reinicialização pendente; serviço
  indisponível; progresso sem porcentagem; dois provedores; dados
  inesperados; cancelamento (só demo); operação concorrente.

## Defeitos reais encontrados pelos testes (e corrigidos)

1. Estado `idle` referenciado na spec mas inexistente na lista de estados.
2. Faltavam transições a partir de `unknown` para eventos de progresso e
   conclusão (caso real: UI reiniciada durante operação).
3. Os dois interpretadores (C++ e node) liam os campos de correspondência
   do journal_mapping no nível errado do JSON — detectado porque a regra
   “module-completed” capturava todas as linhas.
4. `staged-deployment-detected` não tinha transição saindo de `upToDate`.

## Não executado (NOT RUN / BLOCKED)

- Compilação C++/QML do app (sem Qt6/KF6 no ambiente) — SOURCE IMPLEMENTED.
- Carregamento da UI em plasmashell/QML runtime — RUNTIME NOT RUN.
- Execução real de `uupd update-check`, `uupd-manual.service`, bootc,
  Flatpak, D-Bus systemd/logind — BLOQUEADO (sem Enthroned OS inicializável;
  nenhuma atualização real autorizada).
- Build OCI (`just build`) e `bootc container lint` — BLOQUEADO (herdado da F1).
- KNotification em sessão Plasma real — RUNTIME NOT RUN.
