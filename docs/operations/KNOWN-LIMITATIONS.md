# Limitações conhecidas (o que NÃO existe nesta fase)

> **Estado atual (H7, 19/11/2026).** As seções abaixo registram o estado de
> F1 e do Lote 8 e foram preservadas como histórico. Várias afirmações de
> "nunca executado" já não valem: a imagem H7 foi construída e homologada
> numa VM VirtualBox, com o Settings e o Welcome compilados e um Plasma real
> em execução. Continuam valendo: não há ISO nem instalador público, o canal
> de atualizações está fechado por design, a reversão pelo bootc e a
> atualização a partir de uma origem publicada não foram exercitadas, o
> hardware físico não foi testado e o boot ficou em cerca de 80–83 s até
> `graphical.target` em VM (meta de 35 s não atingida; primeiro boot de cerca
> de 5 min por causa do `flatpak-preinstall.service` herdado). Veja o [README](../../README.md#status-and-known-limitations)
> e o [BUILD.md](BUILD.md).

> Lote de estabilidade 1 e roteiro da próxima homologação: [NEXT-HOMOLOGATION.md](NEXT-HOMOLOGATION.md).

Atualizado em: 2026-11-18 (Lote 8). Leia antes de qualquer expectativa.

## Não implementado (escopo de fases futuras)

| Item | Fase |
| --- | --- |
| Homologação em execução da camada desktop F2/F2.1 (Plasma real, VM) | F2/F3 — ver `docs/validation/F2-STATIC-VALIDATION.md` e `docs/phases/F2-1-DESKTOP-REFINEMENT.md` |
| Arrastar-e-soltar de itens no Enthroned Launcher (fixar/desafixar e reordenar pelo menu de contexto existem desde o Lote 3, só em código; ver `START-MENU.md`) | F3+ (o kickoff nativo permanece disponível como alternativa e cobre esse fluxo) |
| Compilação/instalação do Enthroned Settings na imagem (stage preparado, comentado no Containerfile) | F3+ — após build Qt + homologação |
| Execução de atualizações pela UI (`Atualizar agora`/`Reiniciar`) | BLOQUEADO por padrão (ADR-0005); habilita só com `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` em deploy validado |
| Execução REAL dos fluxos do Lote 8 (sistema via bootc, aplicativos via Flatpak, rollback): entregues em código + unidade fixa + polkit, mas nunca executados | BLOQUEADO até build + VM homologada (`ENTHRONED_SETTINGS_ALLOW_MUTATION=1`); auditoria do bootc real: `just bootc-capabilities` |
| Progresso percentual da atualização somente-sistema: depende do suporte a `--progress-fd` do bootc da imagem; sem suporte, fica indeterminado (honesto) | confirmar na VM |
| Cancelamento real da atualização em andamento, versão disponível antes do download, renomear o dispositivo | futuro — ver ADR-0007 §5 |
| Timer automático de staging (`enthroned-system-update.timer`): arquivo presente, NUNCA habilitado; exige canal publicado + homologação | pós-ADR-0002 |
| KCM próprio do Enthroned no System Settings (hoje: app autônomo + kcmshell6 nativo) | futuro |
| Tema de ícones completo e tema Plasma (`plasmarc`) próprios; artwork definitivo | F3+ (F2 entrega paleta, wallpapers, SVGs e perfis) |
| Navegador Brave pré-configurado | F4 |
| ArtCraft Launcher | F4 |
| Subsistema para aplicativos/drivers Windows (Wine/Proton ou equivalente) | futuro — **sem promessa de compatibilidade** |
| Homologação de hardware / testes físicos | F5+ |
| Distribuição pública / release estável | F6 |

## Não executado nesta F1/F1.1 (ambiente — decisão do usuário: sem instalações)

- **Build OCI**: NUNCA executado — podman/just ausentes no Windows e no WSL2
  Ubuntu; instalação de pacotes recusada pelo usuário em F1.1. Estado:
  NOT RUN / BLOCKED. WSL existente verificado como utilizável (ver
  `docs/phases/F1-1-VALIDATION.md`); alternativas de desbloqueio listadas lá.
- **bootc container lint**: não executado (roda dentro do build OCI).
- **QCOW2/ISO**: nunca geradas. Configuração pronta em `disk_config/`;
  rota de QCOW2 definida em ADR-0004.
- **shellcheck / just check / just --fmt / actionlint**: não executados
  (ferramentas ausentes); cobertos parcialmente no CI `validate.yml`.
- **Boot em VM**: nunca observado.
- **CI de disco**: o action `osbuild/bootc-image-builder-action` foi
  arquivado em 28/09/2026; `build-disk.yml` já usa o container oficial
  `image-builder-cli` (ADR-0004), mas nunca rodou.

## Restrições deliberadas (por design)

- Publicação em registro desabilitada (placeholder `SET_ME_BEFORE_PUBLISH`);
  assinatura cosign não configurada.
- Nenhum pacote extra instalado na imagem (a F3 adicionou apenas arquivos de
  dados: uma unidade systemd **não habilitada** e uma regra polkit
  restritiva); nenhum daemon residente.
- `/etc/os-release`, bootloader e partições permanecem do Aurora (ADR-0003).
- Identidade visual: apenas recursos próprios (paleta, wallpapers, SVGs,
  perfis de layout); nenhum uso de marcas/papéis de parede de terceiros.
- Ações mutáveis da Central de Atualizações bloqueadas por padrão
  (portão + confirmação + polkit; ver ADR-0005).
- Licença: código Apache-2.0 e artes sob licença própria (decisão de 20/11/2026;
  veja `LICENSE`, `NOTICE` e `docs/licensing/THIRD-PARTY.md`).

## Afirmações proibidas enquanto não houver evidência

- "ISO testada", "boot verificado", "imagem publicada", "atualização
  funcional", "compatível com Windows". Cada um exige evidência registrada
  (ver `docs/phases/F1-FOUNDATION.md`).
- "Desktop Enthroned validado em execução" / "menu testado" / "splash
  renderizada": a camada F2/F2.1 está IMPLEMENTED + STATIC VERIFIED
  (116 checagens estáticas); **nenhum** componente desktop — incluindo o
  Enthroned Launcher — foi executado no Plasma; exigem imagem inicializável
  + VM (ver `docs/validation/F2-STATIC-VALIDATION.md` e
  `docs/phases/F2-1-DESKTOP-REFINEMENT.md`).
- "Configurações/Central testadas", "atualização executada pela UI",
  "notificação exibida": a F3 está IMPLEMENTED + STATIC VERIFIED (210
  checagens) + **lógica executada em testes** (228 asserções node sobre a
  spec); o app nunca foi compilado nem carregado, e nenhum serviço
  systemd/D-Bus foi acionado — ver `docs/phases/F3-SETTINGS-UPDATE-CENTER.md`
  e `docs/validation/F3-STATIC-VALIDATION.md`.
- "Atualização do sistema/aplicativos executada", "rollback executado",
  "pipeline publicou imagem": o Lote 8 está IMPLEMENTED + STATIC VERIFIED
  (validador estendido) + **lógica executada em testes** (444 asserções
  node + smoke C++ estendido); nenhuma unidade nova rodou, nenhum bootc
  real foi observado, nenhuma imagem foi publicada — ver
  `docs/phases/LOTE-8-UPDATE-SYSTEM.md`, `docs/operations/UPDATE-SYSTEM.md`
  e `docs/operations/UPDATE-PIPELINE.md`.
