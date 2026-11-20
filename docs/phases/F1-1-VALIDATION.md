# F1.1 — Validação e fechamento técnico (trilha de evidências)

- **Data:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash)
- **Decisões de gate do usuário nesta fase:** NÃO instalar pacotes no WSL;
  NÃO executar build pesado; continuar desenvolvimento e verificações leves;
  registrar impedimentos e alternativas. Respeitado integralmente — nenhuma
  instalação, nenhuma alteração no Windows/WSL, nenhum build.

## 1. Baseline (sem alterações prévias)

- `git status`: branch `main`, **0 commits**, mesmas 12 entradas untracked da
  F1; mtimes (13:18–13:20) confirmam que nada foi alterado entre as fases.
- `scripts/verify-source.sh` re-executado: **14 PASS / 2 WARN / 0 FAIL**.

## 2. Revisão estática executada (real, com evidências)

| Item | Resultado | Evidência |
| --- | --- | --- |
| `bash -n` (6 scripts) | PASS 6/6 | Git Bash/bash 5.3.9 |
| YAML dos 4 workflows | PASS | PyYAML 6.0.3 (revalidado após reescrita do build-disk.yml) |
| `verify-artifacts.sh` — ISO sintética (CD001) | PASS | formato, tamanho, SHA-256 corretos |
| `verify-artifacts.sh` — VDI sintético | PASS (após correção) | bug real encontrado e corrigido (ver §3) |
| `enthroned-identity` — caminho de falha (sem metadados) | Comportamento correto | exit 1 + mensagem clara |
| `verify-image.sh` — caminho de falha (sem podman) | Comportamento correto | exit 2 BLOCKED |
| `doctor.sh` — executado | 5 PASS / 6 WARN / 2 BLOCKED | bloqueios reais (just/podman ausentes) |
| `just --fmt --check`, `just check`, `just lint` | **PENDENTE** | exigem `just`/`shellcheck` (gate do usuário) |
| actionlint | **PENDENTE** | não instalado; YAML validado só sintaticamente |

## 3. Defeitos reais encontrados e corrigidos nesta fase

1. **`verify-artifacts.sh` — detecção VDI**: contagem errada da mágica
   (31 chars, não 30) **e** `dd` do ambiente retornou 29 bytes com `count=30`.
   Correção: verificação por `head -c 64 | grep -aq 'Oracle VM VirtualBox Disk
   Image'` (sem aritmética de dd). Testado com arquivo sintético: PASS.
2. **`Justfile _build-bib`**: adicionado guard que **recusa gerar ISO** com o
   placeholder `SET_ME_BEFORE_PUBLISH` em `disk_config/iso.toml` (mídia apontaria
   para imagem inexistente — ADR-0002).
3. **`.github/workflows/build-disk.yml`**: usava
   `osbuild/bootc-image-builder-action`, **arquivado em 28/09/2026** (verificado
   na página oficial). Migrado para a invocação direta do container oficial
   `ghcr.io/osbuild/image-builder-cli:latest` documentada no aviso de deprecação
   (`--bootc-ref ... --bootc-default-fs btrfs build qcow2`). O novo
   `osbuild/image-builder-action` NÃO foi adotado porque **não possui tags
   publicadas** (verificado via API em 2026-11-16) — pinar `main` violaria a
   política de supply chain (ADR-0002/0004).
4. **Docs de rota**: `BUILD.md` (QCOW2 primária; ISO legada com guard; ponte
   `podman load` para consumir o artefato do build-preview sem publicar) e
   `VM-FIRST-BOOT.md` (QCOW2→VDI como rota primária para VirtualBox).
5. **ADR-0004** criado com a decisão de rota, evidências e gatilhos de migração.

## 4. Verificação read-only do WSL existente (sem alterar nada)

| Checagem | Resultado |
| --- | --- |
| Distro | Ubuntu 26.04.1 (WSL2, kernel 6.18), systemd **running** |
| Distros WSL | apenas `Ubuntu` (running) e `docker-desktop` (stopped) — **nenhuma nova distro é necessária** |
| subuid/subgid | `<usuário>:100000:65536` → rootless podman pronto |
| KVM | `/dev/kvm` presente (`crw-rw---- root:kvm`), VT-x ativo (40 flags vmx) → VM headless viável |
| Recursos | 20 vCPU, 15 GB RAM, **947 GB livres** no ext4, escrita OK |
| Ferramentas | `podman`, `just`, `jq`, `shellcheck`, `shfmt`, `qemu-img`, `skopeo`: **AUSENTES** |
| Simulação apt (sem instalar) | CORE 61 pacotes ~111 MB download / ~398 MB instalado; BOOT (qemu+ovmf) 81 pacotes ~83 MB / ~378 MB |

**Conclusão:** o WSL Ubuntu existente é tecnicamente utilizável para build OCI,
QCOW2 e boot headless **assim que os pacotes forem autorizados**. Nada além de
`apt-get install` é necessário (sem nova distro, sem reconfiguração).

## 5. Estados alcançados

| Estado | Valor |
| --- | --- |
| SOURCE READY | **MANTIDO E REFORÇADO** (revisão estática + 4 correções + ADR-0004) |
| OCI BUILT | **BLOCKED** — autorização (pacotes WSL ou CI) |
| DISK BUILT | **BLOCKED** — depende da OCI |
| VM BOOTED | **NOT RUN** — depende do disco + pacotes qemu |

## 6. Impedimentos registrados e alternativas para aprovação

**Impedimento único:** ausência de `podman`/`just`/`jq`/`shellcheck`/`qemu-utils`
no único ambiente Linux disponível; instalação negada pelo usuário nesta fase.

**Alternativas (qualquer uma desbloqueia):**

- **A — WSL (recomendado):** autorizar
  `sudo apt-get install -y podman just jq shellcheck qemu-utils`
  (~111 MB download, ~398 MB instalado, repo oficial Ubuntu 26.04). Com isso:
  `just doctor && just verify-source && just build && just verify-image`
  desbloqueia OCI BUILT; `qemu-system-x86 ovmf` (+83 MB) desbloqueia boot.
- **B — CI GitHub:** publicar o repo e rodar manualmente `Build preview image
  (no publish)`; requer conta/namespace GitHub e decisão de namespace (ADR-0002).
- **C — Outra máquina Linux:** copiar o repositório e seguir
  `docs/operations/BUILD.md` (comandos idênticos).

## 7. Comandos prontos para execução quando autorizado

```bash
# validação formal do Justfile e lint (pendentes de ferramenta):
just --fmt --check -f Justfile && just check && just lint

# build + verificação:
just doctor && just verify-source && just build && just verify-image

# disco e boot (após OCI BUILT):
just build-qcow2
bash scripts/verify-artifacts.sh output/qcow2/disk.qcow2
qemu-img convert -f qcow2 -O vdi output/qcow2/disk.qcow2 output/EnthronedOS-F1-dev.vdi
```
