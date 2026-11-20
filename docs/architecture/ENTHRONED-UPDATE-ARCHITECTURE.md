# Arquitetura da Central de Configurações e Atualizações (F3)

- **Data:** 2026-11-16
- **Plataforma:** KDE Plasma 6.6+ / Qt 6 / Kirigami sobre Aurora Stable (Fedora, bootc/OCI)
- **Princípio:** observar e disparar os mecanismos REAIS do Aurora
  (uupd, bootc, systemd, polkit, Flatpak). Nenhum segundo atualizador,
  nenhum daemon residente, nenhum `sudo`/`pkexec` na aplicação.

## 1. Camadas

```
ENTHRONED OS
|
+-- Enthroned Settings (app Qt Quick/Kirigami: org.enthroned.settings)
|   |
|   +-- UI (QML): Início · Sistema · Bluetooth e dispositivos · Rede ·
|   |             Personalização · Aplicativos · Contas · Hora e idioma ·
|   |             Acessibilidade · Privacidade · Atualizações · Sobre
|   |             (Lote 4, ADR-0007; busca local em search.js)
|   |
|   +-- Update Center (QML): Dashboard · Detalhes · Progresso ·
|                            Histórico · Reinicialização · Recuperação
|   |
|   +-- Backend C++ (context properties)
|       |
|       +-- SystemIdentityProvider   identity.json / release-channel.json / QSysInfo
|       +-- DeviceInfoProvider       CPU/RAM/GPU/volumes/SELinux (thread de trabalho, leitura)
|       +-- PersonalizationController plasma-apply-colorscheme / -wallpaperimage (allowlist)
|       +-- BootcStatusProvider      bootc status --format=json (leitura)
|       +-- SystemdCalls             org.freedesktop.systemd1 (D-Bus)
|       +-- JournalProgressSource    journalctl -f/-o json + JournalParser
|       +-- ConnectivityMonitor      NetworkManager State (D-Bus, leitura)
|       +-- FlatpakUpdatesProvider   flatpak remote-ls --updates / history (leitura)
|       +-- ProfileController        /usr/bin/enthroned-profile (F2.1, user-level)
|       +-- KcmLauncher              kcmshell6 (módulos nativos, com detecção)
|       +-- HistoryLog               $XDG_STATE_HOME/enthroned-os/settings-history.jsonl
|       +-- NotificationPresenter    KNotification (eventos reais)
|       +-- UpdateEngine             orquestração + máquina de estados + portão de mutação
|
+-- Update Integration Layer (contratos no UpdateEngine + spec declarativa)
|   |
|   +-- enthroned-update-check.service  (NOVA, read-only: uupd update-check)
|   +-- uupd-manual.service             (upstream: execução mutável real)
|   +-- uupd.service / uupd.timer       (upstream: automação, apenas observados)
|   +-- polkit: regra própria (só a unidade de check) + uupd.rules upstream
|
+-- KDE Plasma / Qt / Kirigami
|
+-- Aurora / Fedora / bootc
```

## 2. Contratos (métodos conceituais → implementação)

| Contrato pedido | Implementação real |
| --- | --- |
| GetSystemStatus | `bootc status --format=json` + identity.json + QSysInfo |
| CheckForUpdates | systemd D-Bus `StartUnit("enthroned-update-check.service")` → `uupd update-check` (exit 0 = há, 77 = não há) |
| ListAvailableUpdates | resultado do check (sistema) + `flatpak remote-ls --updates` (apps) |
| GetUpdateDetails | lista acima + log de eventos da sessão (UI) |
| RequestUpdate | `StartUnit("uupd-manual.service")` — portão de mutação + confirmação |
| ObserveProgress | `journalctl -f -u uupd-manual.service -o json` (slog JSON + progresso bootc) + polling D-Bus do estado da unidade |
| GetUpdateHistory | journal uupd.service/uupd-manual.service + `flatpak history` + log local |
| GetRestartRequirement | `status.staged` presente → “Reinicialização necessária” |
| RollbackInfo | `status.rollback` (detecção; sem execução nesta fase) |

**Lacunas honestas:** uupd não expõe listagem consolidada pré-execução nem
API D-Bus própria; nada disso é simulado — o que a central mostra vem das
fontes acima e “Indisponível/Não verificado” quando a fonte não existe.

## 3. Especificação declarativa (spec executável)

`settings/src/update/update-state-spec.json` contém:

- **states** — os 10 estados da F3.4 (unknown, checking, upToDate,
  updatesAvailable, updating, preparing, restartRequired, failed, noNetwork,
  serviceUnavailable);
- **transitions** — tabela dirigida a eventos com guardas simples
  (`stagedDeployment`, `mutationAllowed`, `phaseDownloading`, …); primeira
  regra que casa vence; evento desconhecido mantém o estado;
- **journal_mapping** — regras msg/msgSuffix/level/field → eventos
  normalizados (ex.: `"<módulo> module has completed."` → `module-completed`);
- **bootc_progress** — janelas de porcentagem por tarefa do bootc
  (`pulling`→Download 0–80, `importing`→Preparando 80–90, `staging`→Aplicando
  90–100), espelhando o PROGRESS_STAGES do uupd.

Dois interpretadores implementam as MESMAS semânticas: C++
(`updatestatemachine.cpp`, `journalparser.cpp`) e o runner de testes node
(`settings/tests/run-tests.mjs`) — que executa a spec com fixtures
(cenários da F3.14) e provou a coerência do contrato (228 asserções).

## 4. Motor de progresso (F3.6)

- Fonte de eventos: journal em tempo real (linhas JSON do uupd com
  `--json --log-level=debug`) + estado da unidade systemd (polling 2 s) +
  eventos do engine (check iniciado, operação recusada, etc.).
- Evento normalizado `UpdateEvent`: source, operationId, rawType, phase,
  description, timestamp, severity, progressPercent (opcional, −1 =
  indisponível), bytes, currentItem, result.
- Tratamento de anomalias: linha não-JSON → `unknown-data` (nunca muda
  estado); unidade terminada com exit 0 → sucesso somente da unidade
  (uupd retorna erro em falhas de módulo; exit ≠ 0 → falha); journal
  indisponível → degrada para polling (progresso indeterminado); UI
  reiniciada no meio de operação → estado reconstituído a partir de
  eventos/estados reais (transições a partir de `unknown`); operação
  concorrente → recusada com evento explícito; uupd.service (automática)
  detectado → a central não inicia nada concorrente.
- **Nenhum cronômetro declara progresso.** Sem evento/porcentagem real →
  indicador indeterminado.

## 5. Segurança e autorização (F3.7)

- Portão de mutação: mutável **bloqueado por padrão**; habilita apenas com
  `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` fora do modo demo. A UI nunca define
  isso.
- `enthroned-update-check.service`: oneshot **não habilitada** (sem
  [Install]), `ConditionPathExists=/usr/bin/uupd`, executada via D-Bus sob
  regra polkit que exige `subject.local && subject.active &&
  isInGroup("wheel")` e cita **apenas** a unidade de check — mais restritiva
  que o uupd.rules upstream e sem conceder nada às unidades mutáveis.
- **Origem da imagem (Lote 4):** `update/imageorigin.h` classifica a imagem do
  `bootc status` (`enthroned`/`unverified`/`foreign`/`unknown`); imagens
  genéricas Fedora/CentOS e origens fora de `expected_image_references` são
  `foreign` e bloqueiam a atualização do sistema (`updateBlockReason`). O app não
  chama `bootc switch/rebase`, `dnf` nem `rpm-ostree`. Sistema e Flatpak têm listas
  separadas no backend (`systemUpdates`/`appUpdates`); a *execução* ainda é a do
  `uupd-manual.service` (todos os módulos) — ver ADR-0007 §5.
- A confirmação na UI é UX; a autorização real é polkit/systemd.
- SELinux, timers e configuração do uupd: intocados.
- Log local não grava tokens/credenciais/caminhos pessoais (só carimbo,
  fonte, tipo, título).

## 6. Modo de demonstração

- Ativação: `enthroned-settings --demo` (ou `ENTHRONED_SETTINGS_DEMO=1`),
  cenário via `--demo-scenario <nome>` ou `ENTHRONED_SETTINGS_DEMO_SCENARIO`.
- Banner permanente: “Modo de demonstração — nenhuma atualização será
  executada.”; seletor de cenário e “Cancelar (demo)”.
- Dados **fictícios exclusivamente dos mesmos fixtures** usados pelos
  testes; nunca misturados com fontes reais; ações mutáveis reais
  permanecem impossíveis no modo demo.

## 7. Integração à imagem (resumo)

- Hoje: `system_files/usr/lib/systemd/system/enthroned-update-check.service`
  + `system_files/usr/share/polkit-1/rules.d/10-org.enthroned.settings.rules`
  (arquivos de dados; sem binário, sem `.desktop`).
- Preparado (comentado) no Containerfile: stage `settings-builder`
  (CMake/Qt6/KF6) + COPYs para o estágio final. Detalhes:
  `docs/operations/SETTINGS-INTEGRATION.md`.
- Nenhum atalho para binário inexistente é registrado.
