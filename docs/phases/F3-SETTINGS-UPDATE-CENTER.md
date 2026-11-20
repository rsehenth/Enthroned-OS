# F3 — Settings & Update Center: estado da fase

- **Data do registro:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11
- **Fonte do escopo:** prompt mestre F3 (fornecido na sessão)
- **Base alvo:** KDE Plasma 6.6+ / Qt 6 / Kirigami sobre Aurora Stable

## Objetivos da fase

Primeira versão da Enthroned Settings & Update Center: aplicação gráfica
nativa (Qt/QML) com navegação lateral, página inicial, aparência integrada
à F2.1 (`enthroned-profile`), Central de Atualizações com estados reais,
progresso por eventos, histórico, reinicialização e infraestrutura de
rollback — sem builds, sem atualizações reais, sem tocar no host.

## Estados de conclusão (definições separadas)

| Estado | Valor | Evidência |
| --- | --- | --- |
| F3 IMPLEMENTED | **ATINGIDO** | App `settings/` completo em código (backend C++ + 10 QML), provedores reais, adaptadores com portão de mutação, integração de imagem preparada |
| F3 STATIC VERIFIED | **ATINGIDO** | `scripts/validate-settings.sh`: **210/210 PASS**; regressões: F2 **116/116**, F1 **14 PASS/2 WARN/0 FAIL**; `bash -n` em todos os scripts |
| F3 LOGIC RUNTIME VERIFIED (contrato, não Qt) | **ATINGIDO** | `settings/tests/run-tests.mjs` (node): **228 asserções PASS** executando a spec (máquina de estados, journal_mapping, bootc_progress) com 12 cenários fixtures |
| F3 BUILD VERIFIED | **NOT RUN** | Sem Qt6/KF6/cmake no ambiente; app é SOURCE IMPLEMENTED |
| F3 RUNTIME VERIFIED (UI/Qt) | **NOT RUN** | UI nunca carregada; KNotification nunca emitida |
| F3 INTEGRATION VERIFIED | **NOT RUN** | Unidade/polkit nunca executadas em systemd real; sem Enthroned OS inicializável |
| Atualizações reais | **BLOQUEADAS** | Portão de mutação desabilitado por padrão (ADR-0005); nenhuma atualização executada |

## O que foi construído

### Aplicação (settings/)
- **CMake + ECM**, Qt6 Quick/QuickControls2/DBus, KF6 Kirigami/I18n/Notifications;
  QML embutido via `qt_add_qml_module`; spec + 12 cenários embutidos como
  recursos; regras de instalação (binário, .desktop, appdata, notifyrc, ícone).
- **Navegação lateral** com busca (filtro real sobre páginas), 7 páginas,
  banner de demo, i18n via KLocalizedContext (`i18n()`), Accessible.* nos
  itens interativos, paleta exclusivamente do esquema ativo (checagem
  estática proíbe cores fixas).
- **Páginas**: Início (estado de atualização + categorias + resumo do
  computador), Sistema (identidade, upstream, kernel, deployments bootc,
  política de atualização automática — somente leitura), Aparência
  (perfis Classic/Modern via `enthroned-profile` com confirmação e
  restauração; prévia de papéis de parede com estado “não instalado”),
  Aplicativos/Dispositivos (abrem módulos KCM nativos com detecção;
  indisponível = desabilitado, nada simulado), Atualizações (ver §Central),
  Sobre (identidade/licenciamento).

### Central de Atualizações
- Os 10 estados da F3.4 com títulos/textos/ícones mapeados da spec;
  botões só habilitados com mecanismo real (Verificar sempre que livre;
  Atualizar agora exige portão + confirmação com escopo; Reinicializar
  exige staged + confirmação; sem botão funcional de rollback).
- Progresso por fonte (Sistema/Flatpak): `ProgressBar` somente com
  porcentagem real (eventos do bootc); caso contrário `BusyIndicator`
  indeterminado; nenhum cronômetro inventa progresso.
- Subviews: Detalhes (itens + log de eventos da sessão), Histórico
  (journal uupd + flatpak history + log local, com tipos distintos:
  iniciada/concluída/falha/staged/automática/manual), Recuperação
  (booted vs. rollback, o que rollback cobre e não cobre, aviso de que a
  execução não está disponível nesta fase).
- Modo demo com banner permanente, seletor de cenário e cancelamento
  (fluxo existente somente no demo).

### Backend C++
- `UpdateEvent` (modelo F3.6), `UpdateStateMachine` + `JournalParser`
  (dirigidos pela spec compartilhada), `SystemdCalls` (D-Bus systemd),
  `JournalProgressSource` (tail do journal), `ConnectivityMonitor`
  (NetworkManager), `BootcStatusProvider`, `FlatpakUpdatesProvider`,
  `ProfileController`, `KcmLauncher`, `HistoryLog`,
  `NotificationPresenter` (KNotification), `UpdateEngine` (orquestração,
  portão de mutação, observação de concorrência, reinicialização via logind).

### Integração de imagem
- `system_files/.../enthroned-update-check.service` (oneshot read-only,
  não habilitada) + regra polkit restritiva (wheel+local+active, só a
  unidade de check).
- Stage `settings-builder` preparado e **comentado** no Containerfile
  (nada é construído/copiado até homologação); nenhum `.desktop` morto.
- `just verify-settings` + `scripts/validate-settings.sh`.

## Verificações executadas (resumo)

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-settings.sh` | **210/210 PASS** (inclui os testes node) |
| `node settings/tests/run-tests.mjs` | **228/228 PASS** |
| `bash scripts/validate-desktop.sh` | 116/116 PASS (regressão F2) |
| `bash scripts/verify-source.sh` | 14 PASS / 2 WARN / 0 FAIL (regressão F1) |
| `bash -n` (todos os scripts) | PASS |

Defeitos reais encontrados pelos testes e corrigidos (ver
`docs/validation/F3-STATIC-VALIDATION.md`): estado órfão `idle`; transições
faltando a partir de `unknown`; interpretação do `journal_mapping` com
caminho errado em ambos os interpretadores; transição ausente de
`staged-deployment-detected` em `upToDate`.

## Bloqueios e limitações

1. **Build**: app não compilado (sem Qt6/KF6). Todo o código C++/QML é
   SOURCE IMPLEMENTED; risco de erros de compilação existe e será revelado
   no primeiro build (stage pronto no Containerfile).
2. **Runtime**: nada foi executado em Plasma real; KNotification, D-Bus e
   journal exigem um Enthroned OS inicializável.
3. **Mutáveis bloqueados por padrão**: “Atualizar agora”/“Reinicializar”
   exigem `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` em deploy validado
   (ADR-0005); sem isso a UI explica o bloqueio — comportamento deliberado.
4. uupd não expõe listagem consolidada pré-execução nem D-Bus próprio;
   lacunas registradas, não simuladas.

## Fontes oficiais consultadas (2026-11-16)

- uupd: `cmd/root.go`, `cmd/updateCheck.go`, `cmd/update.go`,
  `drv/system/system.go`, `uupd.service`, `uupd-manual.service`,
  `uupd.timer`, `uupd.rules` (github.com/ublue-os/uupd)
- bootc: man pages `bootc-upgrade` (`--check`), `bootc-status`
  (`--format=json`)
- Aurora: docs.getaurora.dev/guides/basic-usage (ujust update,
  toggle-updates, rollback)
- Flatpak: command reference (`remote-ls`, `history --columns`)
- systemd: D-Bus Manager/Unit/Timer (freedesktop)

## Próxima ação mínima

Compilar o app em ambiente Linux com Qt6/KF6 (container ou VM), abrir a UI
em um Enthroned OS inicializável, validar fluxos somente-leitura (status,
check via unidade, histórico, timer) e só então avaliar a habilitação do
portão de mutação — preenchendo BUILD VERIFIED / RUNTIME VERIFIED /
INTEGRATION VERIFIED.
