# Pipeline de Atualização Enthroned (Lote 8)

Infraestrutura para reconstruir e publicar a imagem Enthroned sempre que a
base Aurora Stable avançar. Preparada, automatizável e **desligada por
padrão**: nada publica, assina ou ativa CI sem configuração e aprovação
humana (ADR-0002).

```
Aurora:stable (novo digest) ──► rebuild Enthroned ──► verificações ──► imagem OCI versionada
        (check-base)                (build)             (verify)          (version + notes)
                                                        bootc container lint
                                                        (última RUN do build)
                                                             │
                                              publicação + assinatura cosign
                                              (GATED: nunca implícita)
```

## Uso

```bash
just update-pipeline check-base   # novo digest da base? (somente leitura)
just update-pipeline all          # check-base + build + verify + version + notes
just update-pipeline publish      # GATED; exige todos os portões abaixo
just bootc-capabilities           # auditoria read-only do bootc real (na VM)
```

Fases equivalentes via `bash scripts/update-pipeline.sh <fase>`.

## O que cada fase faz

1. **check-base** — `skopeo inspect docker://ghcr.io/ublue-os/aurora:stable`;
   grava o digest em `output/aurora-base.json` e compara com
   `output/last-release.json`. A base é a tag flutuante `stable` no F1; o
   digest resolvido de cada build real é registrado (ADR-0002).
2. **build** — `just build`: reconstrói a imagem sobre a base atual
   (`build_files/build.sh` aplica as personalizações, o stage `apps-builder`
   compila Settings/Welcome/Desktop Actions com `ctest`, e a última RUN do
   Containerfile executa `bootc container lint`).
3. **verify** — `verify-source.sh` (política: base Aurora, identidade,
   segredos, CI), `validate-desktop.sh`, `validate-settings.sh` (inclui os
   testes node), `validate-welcome.sh` e, se a imagem existir localmente,
   `just verify-image`.
4. **version** — tag versionada `<canal>.<data>.<sha>` (ex.:
   `f1-dev.20261118.abc1234`) além da tag de canal.
5. **notes** — `output/release-notes.json` com versão, digests (base e
   imagem), SHA da fonte e o trecho mais recente de
   [docs/updates/CHANGELOG.md](../updates/CHANGELOG.md). Marca
   `signed: false, published: false` até que de fato sejam.
6. **publish** — só executa com TODOS os portões:
   - `REPO_ORGANIZATION` real (não `SET_ME_BEFORE_PUBLISH`);
   - `publish_registry` configurado em `release-channel.json`;
   - `ENTHRONED_PUBLISH_CONFIRM=1` no ambiente (aprovação humana explícita);
   - chave cosign via `ENTHRONED_COSIGN_KEY` (arquivo local, nunca no repo).
   Faz `podman push` das duas tags e `cosign sign` **por digest**. Sem os
   portões, a fase falha com BLOCKED antes de qualquer rede.

## CI (sem ativação)

Nenhum workflow novo é adicionado. `build-preview.yml` (manual,
workflow_dispatch) já cobre build + verificação sem publicar;
`validate.yml` cobre lint e política a cada push/PR e continua proibindo
cron, login e push. A publicação automatizada futura é um workflow dedicado
com aprovação humana, conforme a ordem obrigatória do ADR-0002: namespace
real → par cosign → secret `SIGNING_SECRET` → workflow com approval.

## Depois de publicar (checklist)

1. Preencher `expected_image_references` em `release-channel.json` com o
   repositório publicado (sem tag). Isso torna a origem `enthroned`
   (verificada) na Central de Atualizações.
2. Ajustar `publish_registry` e `production_ready` conforme o canal.
3. Registrar o release em `output/last-release.json` (base digest + tag)
   para o `check-base` comparar.
4. Antes de retirar a máscara, exigir no fluxo privilegiado uma consulta
   atual dos deployments booted e staged (se houver) e validar suas origens
   exatas contra a lista oficial. Exigir que o bootc verifique a assinatura
   ao consumir a imagem. Origem desconhecida, assinatura inválida ou erro
   na consulta bloqueiam a operação. `production_ready=true` é metadado e
   não autoriza mutações.
5. Homologar em VM o fluxo fixo de staging, o status fresco, a reinicialização
   por decisão do usuário e o rollback. Só com aprovação explícita revisar a
   política de build e preset para liberar apenas o par
   `enthroned-system-update.timer`/`enthroned-system-update.service`.
   Manter os caminhos paralelos bloqueados. Consultar o
   [Gate 12.3](../validation/GATE-12-3-AUTO-UPDATE-SAFETY.md).

## Testes de capacidade do bootc

`scripts/bootc-capabilities.sh` (ou `just bootc-capabilities`) audita, em
leitura pura, a versão real do bootc da imagem: `status --format=json`,
`upgrade --check`, suporte a `--progress-fd`/`--apply` e `rollback`. Rode
dentro da VM homologada e registre o resultado no relatório de validação.
