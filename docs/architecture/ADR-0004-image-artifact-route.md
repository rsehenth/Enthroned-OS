# ADR-0004: Rota de geração de artefatos de disco (BIB → image-builder)

- **Status:** Aceito
- **Data:** 2026-11-16
- **Fase:** F1.1 — Fechamento técnico
- **Fontes consultadas (2026-11-16):**
  - https://github.com/osbuild/bootc-image-builder (ativo; README: "The sources for bootc-image-builder are now located in the osbuild/image-builder repository")
  - https://github.com/osbuild/bootc-image-builder-action (**arquivado em 28/09/2026**, read-only, com aviso de deprecação apontando para osbuild/image-builder-action e receita de container direta)
  - https://github.com/osbuild/image-builder + https://raw.githubusercontent.com/osbuild/image-builder-action/main/README.md (contrato atual)
  - https://osbuild.org/docs/developer-guide/projects/image-builder/advanced/bootc/isos/ (generic-iso / ostree-iso; "anaconda-iso ... is not available in image-builder")

## Contexto

A F1 adotou o `bootc-image-builder` (BIB, `quay.io/centos-bootc/bootc-image-builder:latest`)
e o action `osbuild/bootc-image-builder-action`. O ecossistema osbuild migrou
as fontes para o novo CLI `image-builder` (`ghcr.io/osbuild/image-builder-cli`),
com tipos de imagem diferentes: `qcow2`/`raw` com `--bootc-ref`, `generic-iso`
e `ostree-iso`. O tipo `anaconda-iso` do BIB **não existe** no novo CLI; o
substituto (`bootc-generic-iso`) exige um container instalador dedicado
(Anaconda dentro do container) e usa contrato distinto — não é substituto
direto do nosso `disk_config/iso.toml`.

## Decisão

1. **QCOW2 (rota primária, local e CI):**
   - **Local (WSL/Linux):** `just build-qcow2` via BIB — contrato verificado do
     template upstream, consome a imagem LOCAL de `containers-storage` rootful
     (`--rootfs=btrfs`, igual ao F1), sem publicar nada.
   - **CI:** `build-disk.yml` migrado do action arquivado para a invocação
     direta do container oficial documentada no aviso de deprecação
     (`sudo podman run --privileged ... ghcr.io/osbuild/image-builder-cli:latest
     --bootc-ref <ref> --bootc-default-fs btrfs build qcow2`). Não usamos o
     `osbuild/image-builder-action` porque ele ainda não possui tags publicadas
     (o README cita `@v1`, mas o repositório não tem nenhuma tag — verificação
     via API em 2026-11-16); pinar `main` de um action sem release viola nossa
     política de supply chain.
2. **ISO (legado, opcional, somente local):** permanece a rota BIB
   (`just build-iso`, tipo `iso`/anaconda-iso), com guard no `_build-bib` que
   **recusa gerar mídia** enquanto `disk_config/iso.toml` contiver o
   placeholder `SET_ME_BEFORE_PUBLISH`. A ISO **não é** a rota primária do
   primeiro boot: prioridade é QCOW2 → VDI (qemu-img convert) → VM descartável.
   Nenhuma ISO é gerada em CI (sem equivalente direto no novo CLI; exigiria
   construir um container instalador — futuro, fora da F1.1).
3. **Fallback local para QCOW2**, caso o BIB falhe em build real: a mesma
   receita de container do image-builder CLI apontando `--bootc-ref
   localhost/enthroned-os:f1-dev` (mesma monta de storage rootful).

## Trade-offs e riscos

- BIB continua funcional (imagens publicadas), mas é caminho legado: quando o
  `image-builder-action` publicar tags estáveis, migrar o CI para o action
  (contrato mais limpo) — gatilho registrado.
- O builder do CI usa tag `:latest` do container oficial (igual ao template
  upstream); para release reproduzível, pinar por digest (ADR-0002).
- `iso.toml` (formato BIB) fica obsoleto no dia em que sairmos do BIB; sua
  conversão para `bootc-generic-iso` exige um container instalador dedicado e
  novo ADR.
- Output do novo builder difere do BIB; o workflow já localiza o artefato por
  `find output -name '*.qcow2'` em vez de caminho fixo.

## Compatibilidade verificada

- `bootc_default_fs: btrfs` é exemplo oficial do novo action (contrato suportado).
- `--bootc-default-fs btrfs` mantém coerência com o `--rootfs=btrfs` do BIB local.
- Nenhum build foi executado ainda nesta F1.1 até o gate de autorização; a
  decisão é de rota/contrato, não de resultado.
