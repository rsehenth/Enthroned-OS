# LOTE 8 — Sistema de Atualizações Completo

**Status: IMPLEMENTED + STATIC VERIFIED + LOGIC TESTED.**
Nada executado em imagem/VM: build, boot, unidades e publicação continuam
bloqueados por autorização (estado geral em `docs/operations/BUILD.md`).

Data: 2026-11-18

## Objetivo atendido

Evoluir a Central de Atualizações (Lote 4/F3) para um atualizador real do
Enthroned OS sobre os mecanismos oficiais do ecossistema Fedora Atomic,
Aurora, bootc e Flatpak: atualização do sistema transacional, atualização
separada de aplicativos, rollback protegido, pipeline de reconstrução sobre a
base Aurora atualizada e preferências de automação preparadas (nunca
habilitadas por padrão).

## Arquitetura

- **Spec compartilhada** (`settings/src/update/update-state-spec.json`):
  + estado `rollingBack`; + eventos `flatpak-progress`,
    `flatpak-update-success`, `flatpak-update-failed`,
    `engine-rollback-started`, `rollback-success`, `rollback-failed`,
    `preflight-blocked`, `staged-origin-blocked`; formalização de
    `update-rejected`, `concurrent-operation-detected`, `spec-error`;
  + transições de rollback com guardas `mutationAllowed` +
    `rollbackAvailable`; apps-only termina em `upToDate` sem reinício;
    `check-no-update` sai de `updating` (bootc sem novidades);
  + regras de journal `payloadFromMessage` para as linhas JSON brutas do
    `bootc --progress-fd` (helper da unidade de sistema).
- **UpdateEngine**: gate único `mutatingFlowGate()` para todo fluxo mutável
  (demo, política, origem booted e staged, uupd automático, systemd) +
  preflight de armazenamento (`/ostree` ≥ 2 GiB para sistema; `/var` ≥ 1 GiB
  para apps) + modos `full | system | apps | rollback` (`updateMode`) +
  `canRollback` + `channelConfigured` + `stagedOriginBlocked`.
- **BootcStatusProvider**: expõe `stagedImageRef` (referência da imagem
  staged) usada para classificar a origem do deployment pendente.
- **FlatpakUpdatesProvider**: listagem por instalação (`--user` e `--system`,
  coluna `installation`) e `updateUserInstallations()` com argv fixo
  (`flatpak update --user --noninteractive`) + progresso parseado quando real.
- **SystemdCalls / polkit**: nenhuma mudança de API; a regra
  `10-org.enthroned.settings.rules` passa a autorizar exatamente quatro
  unidades (check, system-update, flatpak-update, rollback) para usuários
  locais ativos do grupo wheel.
- **Unidades novas (comandos fixos, sem `[Install]`)**:
  `enthroned-system-update.service` (helper fixo
  `/usr/libexec/enthroned-system-update`: `bootc upgrade --progress-fd 9`
  com fd 9 no journal), `enthroned-flatpak-update.service`
  (`flatpak update --noninteractive --system`), `enthroned-rollback.service`
  (`bootc rollback`); `enthroned-system-update.timer` presente e **não
  habilitado** (habilitação manual exige canal confiável; nunca reinicia).
- **Pipeline** (`scripts/update-pipeline.sh` + `just update-pipeline`):
  check-base (digest Aurora via skopeo) → build (`just build`, inclui
  `bootc container lint`) → verify (todos os validadores + verify-image) →
  version (tag `canal.data.sha`) → notes (`output/release-notes.json` a
  partir de `docs/updates/CHANGELOG.md`) → publish **com quatro portões**
  (namespace real, `publish_registry`, `ENTHRONED_PUBLISH_CONFIRM=1`,
  `ENTHRONED_COSIGN_KEY`); `cosign sign` por digest. Sem cron, sem login em
  CI, nenhum segredo no repositório.
- **UI (UpdatesPage.qml)**: versões instalada/preparada, última verificação,
  conexão, botões Verificar / Atualizar agora (tudo) / Somente o sistema /
  Somente os aplicativos / Reiniciar, progresso por fonte seguindo
  `updateMode`, mensagens honestas (canal não configurado, origem staged
  fora do canal, "Não verificado" quando nada foi checado), histórico com os
  novos tipos e tela de recuperação com rollback real e confirmação.

## Arquivos alterados/criados

- settings/src/update/: `update-state-spec.json`, `updateengine.{h,cpp}`,
  `journalparser.cpp`.
- settings/src/: `bootcstatusprovider.{h,cpp}`,
  `flatpakupdatesprovider.{h,cpp}`.
- settings/qml/pages/UpdatesPage.qml; settings/tests/native-smoke.cpp;
  settings/CMakeLists.txt (8 cenários novos; 20 no total).
- system_files/usr/lib/systemd/system/: `enthroned-system-update.service`,
  `enthroned-flatpak-update.service`, `enthroned-rollback.service`,
  `enthroned-system-update.timer`; system_files/usr/libexec/
  `enthroned-system-update`; polkit `10-org.enthroned.settings.rules`.
- build_files/build.sh (chmod do helper); build_files/l10n/pt_BR/
  `enthroned-settings.po` (+ ~70 traduções).
- scripts/: `update-pipeline.sh` (novo), `bootc-capabilities.sh` (novo),
  `validate-settings.sh` (validador estendido).
- Justfile (`update-pipeline`, `bootc-capabilities`, lint do helper).
- docs/: operations/UPDATE-SYSTEM.md, UPDATE-PIPELINE.md,
  UPDATE-PERSISTENCE.md (novos), updates/CHANGELOG.md (novo),
  operations/KNOWN-LIMITATIONS.md, README.md, este relatório.

## Testes realizados (estáticos/leves)

- **node** (`settings/tests/run-tests.mjs`): **444 asserções, 0 falhas**.
  Inclui os 20 fixtures (8 novos: system-update, apps-update,
  rollback-success, rollback-failed, preflight-blocked,
  download-interrupted, origin-unauthorized, staged-recovery), 19 checagens
  novos do Lote 8 (separação sistema/apps, guardas de rollback, preflight
  mantendo estado, parse das linhas `--progress-fd` brutas com janelas
  40% e 94,55%).
- **Validador estático** (`just verify-settings` →
  `scripts/validate-settings.sh`): todas as checagens passaram, incluindo ~18
  novas (spec Lote 8, gate único, unidades fixas sem `[Install]`, timer não
  habilitado no build.sh, helper sem rede/eval, polkit de 4 unidades,
  provider flatpak user/system, honesty flags).
- **Sintaxe bash**: `bash -n` nos scripts novos e no helper.
- **Não executado (ambiente)**: build Qt/CTest (`settings-native-smoke`
  atualizado mas só roda no build da imagem), bootc real, unidades systemd,
  polkit, pipeline com podman/skopeo/cosign.

## Pronto para build / exige registro / depende de VM

- **Pronto para build agora** (nada a fazer além de `just build`): código,
  spec, cenários, unidades, polkit, helper, chmod no build.sh, catálogo
  pt_BR, validadores. O stage `apps-builder` compila tudo com `ctest`.
- **Exige configuração de registro (ADR-0002) antes de funcionar de verdade**:
  namespace real (`REPO_ORGANIZATION`), `publish_registry` +
  `expected_image_references` em `release-channel.json`, par cosign,
  `ENTHRONED_PUBLISH_CONFIRM=1` e `ENTHRONED_COSIGN_KEY` para a fase
  publish. Sem isso, o modo de origem permanece `unverified` (dev) e a
  publicação falha com BLOCKED por design.
- **Depende de validação na VM homologada**:
  `just bootc-capabilities` (versão/argumentos reais do bootc, em especial
  `--progress-fd`), fluxo completo verificar → atualizar (bootc + uupd +
  flatpak) → reiniciar → rollback, merge de `/etc`, persistência (roteiro em
  UPDATE-PERSISTENCE.md), timer (somente depois de canal confiável).

## Limitações honestas

- Nenhuma unidade nova rodou; nenhum bootc real observado; nenhuma imagem
  publicada; nada foi commitado ou enviado.
- Atualizações mutáveis seguem bloqueadas por padrão
  (`ENTHRONED_SETTINGS_ALLOW_MUTATION=1` apenas em deployment validado).
- Percentual da atualização somente-sistema depende do `--progress-fd` do
  bootc da imagem; sem suporte, indicador indeterminado (honesto).
- Cancelamento de atualização em andamento e versão disponível antes do
  download permanecem fora do escopo (ADR-0007 §5).
- Não há dois serviços competindo: agendamento de Flatpak continua no
  `uupd.timer` upstream; o timer Enthroned é staging-only e não habilitado.
