# ADR-0002: Segurança de build, supply chain e assinatura

- **Status:** Aceito (publicação permanece bloqueada até configuração humana)
- **Data:** 2026-11-16
- **Fase:** F1 — Foundation

## Contexto

A imagem deriva de um upstream móvel e será, no futuro, distribuída a usuários.
Isso exige rastreabilidade (o que exatamente foi construído e a partir de quê),
integridade (o artefato não foi alterado) e autenticidade (foi NÓS que
construímos). Na F1 não existem namespace de registro, chaves de assinatura nem
infraestrutura de publicação — e nada disso pode ser inventado.

## Decisões

### 1. Política de versões e digests

- **F1:** a base flutuante `ghcr.io/ublue-os/aurora:stable` é aceita, mas todo
  build real deve **registrar o digest resolvido da base** no relatório do
  build (comando documentado em `docs/operations/BUILD.md`).
- **Futuro (pós-F1):** releases publicados passam a referenciar a base **por
  digest** (`...@sha256:...`), pinado no momento da release; a tag `stable`
  continua usada para builds de desenvolvimento.
- **Não afirmamos reprodutibilidade bit a bit.** A rastreabilidade é:
  digest OCI do resultado + `image-digest.txt` + `SHA256SUMS` dos artefatos.

### 2. Segredos e chaves

- Nenhuma chave privada ou segredo é versionado. `.gitignore` bloqueia
  `cosign.key`, `*.key`, `*.pem`, `.env*` (com exceção documentada para
  `cosign.pub`, que é público por definição).
- `REPO_ORGANIZATION` usa o placeholder `SET_ME_BEFORE_PUBLISH` no
  `image-template.env` e no `disk_config/iso.toml`: builds com o placeholder
  pulam metadados de publicação e a ISO de instalação não aponta para
  registro real. `scripts/verify-source.sh` reporta o estado.
- A futura chave de assinatura será criada por humano via
  `cosign generate-key-pair`, com a privada inserida como secret
  `SIGNING_SECRET` no GitHub. Este repositório nunca contém a chave.

### 3. Assinatura (preparada, bloqueada)

- O fluxo planejado é o do template upstream: `cosign sign` por digest, com
  `COSIGN_PRIVATE_KEY` vindo do secret `SIGNING_SECRET`, apenas em builds
  explicitamente autorizados.
- Nenhum workflow da F1 instala cosign nem assina nada; nenhum updater é
  configurado contra registro fictício.

### 4. CI

- `validate.yml` (push/PR): lint + política — **sem build, sem publish**.
- `build-preview.yml` (`workflow_dispatch`): build + verificação + artefato
  OCI via upload de workflow — **sem login, sem push**.
- `build-disk.yml` (`workflow_dispatch`): exige `image_ref` de registro já
  existente; produz QCOW2/ISO como artefatos de workflow — sem S3, sem push.
- Sem gatilhos `schedule`/cron na F1; sem `permissions` de escrita
  (`contents: read`; `packages: read` apenas para puxar imagem no
  build-disk).
- Actions de terceiros **pinadas por SHA** herdadas do template upstream
  (commit `e9c6420`); Dependabot monitora as atualizações.

### 5. Privilégios

- Builds OCI: rootless podman (runner).
- Disk images (bootc-image-builder): exigem `--privileged` + storage rootful
  (`sudo`) — aceito apenas em ambiente de build Linux/CI controlado, nunca no
  desktop em uso.

## Consequências

- Publicar uma imagem exige, nesta ordem: definir namespace real, gerar par
  cosign, configurar `SIGNING_SECRET`, habilitar passo de publicação em
  workflow dedicado com aprovação humana explícita.
- A tag `f1-dev` nunca deve ser prometida como estável; o canal
  `production_ready=false` está declarado em `release-channel.json`.
