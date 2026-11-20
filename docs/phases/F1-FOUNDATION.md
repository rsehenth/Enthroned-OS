# F1 — Foundation: estado da fase

> **Atualização F1.1 (2026-11-16):** revisão estática executada com correções
> (guard de ISO, workflow de disco migrado do action arquivado, detecção VDI),
> ADR-0004 criado e verificação read-only do WSL concluída. Trilha completa de
> evidências e alternativas de desbloqueio em
> [F1-1-VALIDATION.md](F1-1-VALIDATION.md). Estados de build continuam
> NOT RUN/BLOCKED (decisão do usuário: sem instalações no WSL nesta fase).

- **Data do registro:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11 com WSL2
- **Fonte do escopo:** prompt mestre F1 (fornecido na sessão; o arquivo
  `ENTHRONED_OS_F1_PROMPT_GLM_5_3_FLASH.md` não estava presente no workspace)
- **Arquitetura de referência:** `ARQUITETURA_SISTEMA_AURORA_UX_v0.2.md` não
  estava presente no workspace; requisitos centrais usados conforme fornecidos

## Objetivos da fase

Fundação técnica real da distribuição: repositório, imagem bootc derivada do
Aurora Stable, identidade técnica, scripts de diagnóstico, CI segura,
documentação operacional e caminho demonstrado até OCI → disco → primeira
inicialização em VM.

## Estados de conclusão (definições separadas)

| Estado | Valor | Evidência |
| --- | --- | --- |
| F1 SOURCE READY | **ATINGIDO** | Estrutura completa: Containerfile, build_files, system_files, disk_config, scripts, workflows, docs (ver README) |
| F1 OCI BUILT | **NOT RUN (BLOCKED)** | Sem podman/just no host Windows nem no WSL2 Ubuntu; instalação de pacotes depende de autorização |
| F1 DISK ARTIFACT READY | **NOT RUN** | Depende da imagem OCI e do bootc-image-builder (Linux + sudo) |
| F1 BOOT VERIFIED | **NOT RUN** | Depende de artefato de disco + VM descartável + autorização específica |

## Verificações executadas nesta sessão (Passo D)

| Verificação | Resultado | Observação |
| --- | --- | --- |
| `bash -n` (6 scripts, incluindo enthroned-identity) | PASS 6/6 | bash 5.3.9 (x86_64-pc-linux-gnu) |
| `scripts/verify-source.sh` executado | PASS — 14 PASS / 2 WARN / 0 FAIL | WARNs esperadas: jq ausente no ambiente; placeholder da ISO (por design) |
| `scripts/doctor.sh` executado | BLOCKED (comportamento correto) | 5 PASS / 6 WARN / 2 BLOCKED — just+podman ausentes; KVM e ~1765 GB livres detectados |
| `scripts/verify-artifacts.sh` executado com ISO sintética (CD001) | PASS | formato/tamanho/SHA-256 detectados; arquivo de teste removido |
| JSON válido (identity.json, release-channel.json) | PASS | python json.tool |
| TOML válido (disk.toml, iso.toml) | PASS | python tomllib |
| YAML (3 workflows + dependabot) parseável | PASS | PyYAML 6.0.3 |
| shellcheck completo | **NOT RUN** | shellcheck não instalado no ambiente |
| `just check` / `just lint` | **NOT RUN** | just não instalado |
| `just build` (OCI) | **NOT RUN** | podman não instalado |
| bootc container lint | **NOT RUN** | executa dentro do build OCI |

## Bloqueios registrados

1. **Build OCI/Disk:** podman/just ausentes no Windows e no WSL2 Ubuntu
   (Ubuntu 26.04.1). Instalar (`sudo apt install podman just jq shellcheck`)
   é uma mudança no ambiente do usuário — aguarda autorização.
2. **context-mode (MCP):** indisponível nesta sessão (erro de configuração
   `Project source --agent is missing` também em `ctx_doctor`). Fontes
   oficiais foram consultadas via fetch direto.
3. **Publicação:** bloqueada por design (ADR-0002) até namespace + cosign.

## Entregas por item do escopo

- F1.1 Inventário e ADRs — **feito** (ADRs 0001–0003 + este documento).
- F1.2 Estrutura — **feito** (sem arquivos vazios de preenchimento).
- F1.3 Base OCI Aurora — **feito em fonte**; build NOT RUN.
- F1.4 Identidade técnica — **feito** (identity.json, release-channel.json,
  enthroned-identity, entrada "Sobre").
- F1.5 Scripts — **feito** (doctor/verify-source/verify-image/verify-artifacts).
- F1.6 Pipeline — **feito** (validate/build-preview/build-disk; publicação
  bloqueada por design).
- F1.7 ISO/QCOW2 — **configuração pronta** (disk.toml, iso.toml com namespace
  placeholder; nomenclatura EnthronedOS-F1-dev-<sha>-<data> no workflow);
  geração NOT RUN.
- F1.8 Política de atualizações — **feito**
  (docs/operations/UPDATES-FOUNDATION.md).
- F1.9 Documentação — **feito** (README, BUILD, VM-FIRST-BOOT,
  KNOWN-LIMITATIONS, THIRD-PARTY, CONTRIBUTING).

## Próxima ação mínima

Ver "Próxima ação mínima" no relatório da F1 / README: provisionar um
ambiente Linux com podman+just (WSL2 autorizado ou CI) e rodar
`just doctor && just verify-source && just build && just verify-image`.
