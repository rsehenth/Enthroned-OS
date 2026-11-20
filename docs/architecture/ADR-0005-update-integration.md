# ADR-0005 — Integração com atualizações do Aurora (Central da F3)

- **Data:** 2026-11-16
- **Estado:** Aceito (implementação em código; execução real pendente de homologação)
- **Contexto:** F3 — Enthroned Settings & Update Center

## Contexto e problema

A F3 precisa dar ao usuário uma experiência gráfica de atualização
(familiar, tipo Windows Update), sem criar um segundo atualizador e sem
competir com o mecanismo real do Aurora. O Aurora já traz:

- **uupd** (`/usr/bin/uupd`) — o atualizador oficial (sucessor do arquivado
  `ublue-update`), que orquestra bootc/rpm-ostree, Flatpak, Brew e Distrobox;
- **uupd.service / uupd-manual.service / uupd.timer** — atualização
  automática diária (04:00) e execução manual;
- **uupd.rules** (polkit) — autoriza qualquer usuário a gerenciar
  `uupd.service` e `uupd-manual.service` via systemd D-Bus;
- **bootc** — deployments atômicos (booted/staged/rollback) com
  `bootc status --format=json` documentado como interface de consulta.

## Decisão

1. **A Central NÃO substitui nem envolve o uupd.** Ela **observa e dispara**
   os mecanismos existentes por interfaces oficiais:

   | Operação na UI | Mecanismo real | Natureza |
   | --- | --- | --- |
   | Estado do sistema/deployments | `bootc status --format=json` | leitura |
   | Verificar atualizações | unidade oneshot **read-only** `enthroned-update-check.service` (nova, Enthroned) executando `uupd update-check`; iniciada via systemd D-Bus e autorizada por regra polkit própria (wheel + local + active) | leitura (ver §Evidência) |
   | Atualizar agora | **`uupd-manual.service` existente** (do upstream), iniciado via systemd D-Bus, autorizado pelo **uupd.rules upstream** | mutável |
   | Progresso | journal (`journalctl -f -u uupd-manual.service -o json`): linhas slog JSON do uupd + progresso JSON do bootc (`--progress-fd`) | leitura |
   | Histórico | journal do uupd + `flatpak history` + log local mínimo ($XDG_STATE_HOME) | leitura |
   | Atualizações automáticas (F3.8) | propriedades D-Bus de `uupd.timer` + `uupd config.json` (leitura) | leitura |
   | Reinicializar | logind D-Bus `Reboot` (confirmação na UI; nunca automático) | mutável |
   | Rollback (F3.10) | somente **detecção** (`status.rollback`); execução fica para fase futura | — |

2. **Verificação não-mutável comprovada.** `uupd update-check` (fonte
   `cmd/updateCheck.go`) apenas chama `driver.Check()`; no driver bootc isso
   executa `bootc upgrade --check`, que o manual oficial descreve como
   “Check if an update is available **without applying it**” (baixa apenas
   manifest/config, kilobytes); no fallback rpm-ostree usa
   `rpm-ostree upgrade --check` (consulta). Convenção de saída: 0 = há
   atualização; **77 = nenhuma**.

3. **Portão de mutação bloqueado por padrão.** Ações mutáveis só são
   habilitadas quando: (a) fora do modo demo e (b)
   `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` no ambiente — variável definida em
   um deploy validado, nunca pela própria UI. Sem isso, o botão “Atualizar
   agora” fica desabilitado com mensagem honesta; a rota manual suportada
   continua sendo o uupd/ujust do Aurora.

4. **Sem sudo/pkexec na aplicação.** Nenhum processo privilegiado é criado
   pela UI; toda ação privilegiada é uma unidade systemd pré-definida
   acionada por D-Bus (a confirmação visual do usuário não substitui a
   autorização de sistema — polkit decide).

5. **Aplicação própria em vez de KCM nesta fase.** App Qt Quick/Kirigami
   (`org.enthroned.settings`, binário `enthroned-settings`) com backend C++:
   reutiliza o stack presente no Aurora, evita compilar plugin KCM (API
   maior e build mais pesado) e permite empacotamento posterior. KCM fica
   como opção futura (ver SETTINGS-INTEGRATION).

6. **Contrato único executável.** A máquina de estados de atualização e o
   mapeamento journal→evento vivem em um JSON declarativo
   (`settings/src/update/update-state-spec.json`) consumido pelo backend C++
   e pelos testes node (`settings/tests/run-tests.mjs`) — a lógica é
   realmente executada em teste, não apenas inspecionada.

## Consequências

- Progresso percentual **somente** quando o bootc fornece (`ProgressBytes`/
  `ProgressSteps`); caso contrário, indicador indeterminado. Nada é
  simulado por cronômetro.
- A regra polkit nova é **mais restritiva** que a do uupd (wheel + local +
  active, apenas a unidade de verificação) e não adiciona nada para unidades
  mutáveis.
- `uupd.service` em execução (atualização automática) é detectado e a
  central se recusa a iniciar operação concorrente (o uupd também tem
  lockfile próprio).
- Enquanto o app não for compilado/homologado em um Enthroned OS
  inicializável, nada de `.desktop`/binário entra na imagem (stage builder
  preparado e comentado no Containerfile).

## Fontes verificadas

- https://github.com/ublue-os/uupd (`cmd/root.go`, `cmd/updateCheck.go`,
  `cmd/update.go`, `drv/system/system.go`, `uupd.service`,
  `uupd-manual.service`, `uupd.timer`, `uupd.rules`)
- https://bootc.dev/bootc/man/bootc-upgrade.8.html (`--check`),
  https://bootc.dev/bootc/man/bootc-status.8.html (`--format=json`,
  `status.booted` não nulo)
- https://docs.getaurora.dev/guides/basic-usage/ (ujust update /
  toggle-updates; rollback via deployment anterior)
- https://docs.flatpak.org/en/latest/flatpak-command-reference.html
  (`remote-ls`, `history --columns`)
- https://www.freedesktop.org/wiki/Software/systemd/ (D-Bus Manager/Unit/Timer)
