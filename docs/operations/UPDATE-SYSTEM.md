# Sistema de Atualizações do Enthroned OS (Lote 8)

Como o Enthroned OS recebe atualizações reais sem terminal, preservando a
base Aurora Stable e o gerenciamento imutável do bootc. Documento irmão de
[ENTHRONED-UPDATE-ARCHITECTURE.md](../architecture/ENTHRONED-UPDATE-ARCHITECTURE.md)
(ADR-0005) e [UPDATE-PIPELINE.md](UPDATE-PIPELINE.md).

## Princípios

1. **Imagem, não sistema mutável.** O sistema inteiro (kernel, correções de
   segurança, KDE Plasma, bibliotecas, drivers, componentes de inicialização,
   aplicativos integrados e as personalizações do Enthroned) vive na imagem
   OCI reconstruída sobre a base Aurora. Nunca há `dnf upgrade` no sistema
   instalado e nunca há rebase para imagem genérica Fedora/Aurora.
2. **Mecanismos oficiais.** Verificação via `uupd update-check`
   (`bootc upgrade --check`, somente leitura); atualização via `bootc
   upgrade` transacional ou via uupd (Aurora upstream); aplicativos via
   Flatpak; rollback via `bootc rollback`. A Central de Atualizações orquestra
   essas ferramentas; não as substitui.
3. **Nada arbitrário.** Toda operação privilegiada roda em unidades systemd
   com comando fixo, sem argumentos da interface, autorizadas por polkit
   (usuários locais ativos do grupo wheel).
4. **Progresso real.** Percentuais só de eventos reais (progresso
   `--progress-fd` do bootc encaminhado pelo uupd ou escrito direto no
   journal). Sem fonte confiável, indicador indeterminado. Nada é simulado
   por cronômetro.
5. **Estado honesto.** Enquanto nenhuma verificação foi feita, o estado é
   "não verificado", nunca "atualizado". Sem origem Enthroned configurada, a
   interface explica isso explicitamente.

## Fluxos da Central de Atualizações

| Fluxo | Mecanismo | Unidade | Reinício? |
|---|---|---|---|
| Verificar | `uupd update-check` (somente leitura; exit 0 disponível / 77 sem atualização) | `enthroned-update-check.service` | Não |
| Atualizar tudo | uupd (bootc + Flatpak conforme `/etc/uupd/config.json`) | `uupd-manual.service` (upstream Aurora) | Sistema sim; apps não |
| Somente sistema | `bootc upgrade --progress-fd 9` (helper fixo) | `enthroned-system-update.service` | Sim (staging) |
| Somente aplicativos | `flatpak update --noninteractive --system` (unidade) + `flatpak update --user --noninteractive` (sessão, argv fixo) | `enthroned-flatpak-update.service` | Não |
| Recuperação (rollback) | `bootc rollback` | `enthroned-rollback.service` | Sim (troca no boot) |
| Reiniciar | logind `Reboot` com confirmação | (D-Bus direto) | O próprio |

Todos os caminhos mutáveis passam por um portão comum no `UpdateEngine`
(`mutatingFlowGate`): modo demo, política `ENTHRONED_SETTINGS_ALLOW_MUTATION`,
origem da imagem booted e staged (classificadas por `imageorigin.h`),
atualização automática uupd em execução e disponibilidade do systemd D-Bus.
Antes de iniciar há preflight de espaço (mínimo 2 GiB no sysroot `/ostree`
para o sistema; 1 GiB em `/var` para aplicativos; verificado apenas quando o
caminho existe). Execuções concorrentes são recusadas (`busy`,
`concurrent-operation-detected`); o bootc e o Flatpak mantêm seus próprios
locks.

## Progresso real por fonte

- **uupd (atualizar tudo):** o uupd encaminha as linhas JSON de progresso do
  bootc (`--progress-fd`) pelo journal como mensagens slog `Command output`;
  o `JournalParser` as converte em eventos com percentual pelas janelas
  `bootc_progress` da spec compartilhada (`settings/src/update/update-state-spec.json`).
- **Somente sistema:** o helper fixo `/usr/libexec/enthroned-system-update`
  executa `bootc upgrade --progress-fd 9 9>&2`; as linhas JSON brutas caem no
  journal e são parseadas pela regra `payloadFromMessage` da mesma spec.
  Se a versão instalada do bootc não suportar `--progress-fd`, o progresso
  fica indeterminado e o acompanhamento continua pelo estado da unidade.
  Confirme na VM com `just bootc-capabilities`.
- **Somente aplicativos:** percentuais parseados da saída do próprio
  `flatpak update` quando presentes; caso contrário indeterminado.

## Máquina de estados

A spec declarativa (`update-state-spec.json`) é fonte única consumida pelo
backend C++ e pelos testes node. Estados: `unknown`, `checking`, `upToDate`,
`updatesAvailable`, `updating`, `preparing`, `rollingBack`, `restartRequired`,
`failed`, `noNetwork`, `serviceUnavailable`. Eventos novos do Lote 8:
`flatpak-progress`, `flatpak-update-success`, `flatpak-update-failed`,
`engine-rollback-started`, `rollback-success`, `rollback-failed`,
`preflight-blocked`, `staged-origin-blocked` (além de formalizar
`update-rejected`, `concurrent-operation-detected` e `spec-error`).

O rollback exige guardas `mutationAllowed` e `rollbackAvailable` (deployment
anterior presente no `bootc status`); termina em `restartRequired`, e a
notificação informa que a próxima inicialização volta para a versão anterior.

## Origem e canal

`release-channel.json` declara `expected_image_references`; enquanto a lista
estiver vazia (canal de desenvolvimento), a origem é tratada como
`unverified` e imagens genéricas Fedora/CentOS continuam bloqueadas. A
referência da imagem **staged** também é classificada: se o deployment
pendente não vem da origem do canal, a Central emite
`staged-origin-blocked`, avisa na interface e recusa novas execuções até
resolução. Rebase/switch nunca são executados pela aplicação.

## Atualizações automáticas com o canal fechado

- O build remove a habilitação herdada de `uupd.timer` e mascara os timers
  e serviços de atualização do sistema identificados no
  [Gate 12.3](../validation/GATE-12-3-AUTO-UPDATE-SAFETY.md), incluindo
  `uupd-manual.service`. O preset do Enthroned mantém os timers desabilitados.
  Uma tentativa de início retorna `Unit … is masked`.
- O agendamento de componentes que compartilhavam o uupd fica suspenso junto
  com ele. Os serviços independentes do Flatpak, o Discover e as consultas
  de status continuam disponíveis.
- A ativação futura do timer Enthroned para preparar deployments depende
  da [política de publicação e validação](UPDATE-PIPELINE.md#depois-de-publicar-checklist).
  O reinício fica a cargo do usuário.

## Limitações conhecidas

- Nenhuma execução real foi observada ainda (estado do projeto:
  SOURCE READY / BUILD BLOCKED); os fluxos mutáveis exigem
  `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` em deployment validado.
- `expected_image_references` vazio até existir o registro oficial (ADR-0002);
  publicação e assinatura permanecem preparadas, não ativas.
- O parser do journal das linhas brutas do bootc precisa de confirmação na VM
  (formato exato do `--progress-fd` da versão instalada).
