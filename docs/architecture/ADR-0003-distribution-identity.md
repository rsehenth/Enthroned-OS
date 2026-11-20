# ADR-0003: Identidade de distribuição Enthroned OS sem quebrar a origem

- **Status:** Aceito
- **Data:** 2026-11-16
- **Fase:** F1 — Foundation

## Contexto

Enthroned OS precisa de identidade própria (nome, metadados, futura UX), mas a
imagem deriva do Aurora e os mecanismos de atualização dependem de a origem
permanecer íntegra. Também não é permitido usar marcas, papéis de parede,
fontes ou ícones de Windows/Zorin/Aurora sem verificação de licença e decisão
de produto.

## Decisão

### 1. Identidade técnica em namespace próprio (F1 — implementado)

- `/usr/share/enthroned-os/identity.json` — metadados do produto:
  `product_name`, `product_id`, `version` (0.1.0-dev), `base` (aurora),
  `channel` (f1-dev), `phase` e `upstream` (referência real da imagem base).
- `/usr/share/enthroned-os/release-channel.json` — canal, estado
  `production_ready=false` e política de publicação.
- `/usr/bin/enthroned-identity` — consulta sem root (`--summary`, `--json`,
  `--field`, `--about`).
- Entrada discreta no menu **"Sobre o Enthroned OS"**
  (`/usr/share/applications/enthroned-os-about.desktop`) que abre mensagem
  informativa via `kdialog` (fallback: stdout). Não duplica a Central de
  Configurações.

Todos os campos são verdadeiros; nenhum campo falso de versão/origem.

### 2. O que permanece do upstream (intocável)

- `/etc/os-release` (Aurora), identidade do bootloader, GRUB, partições,
  wallpapers e temas do Aurora, informações de fabricante.
- Justificativa: `os-release` e afins fazem parte do contrato de
  atualização/rollback e da proveniência do sistema. Renomeá-los cedo quebra
  ferramentas e induz falso correspondência com upstream.

### 3. Evolução futura (F2/F3 — não implementado)

- Identidade visual (tema, ícones, artwork) entra em fases próprias de
  produto, sempre em `system_files/` revisável e reversível via rollback.
- A escolha de licença do nosso código e de marcas próprias é uma decisão de
  produto pendente; nada é afirmado antes disso.

## Critérios objetivos para mudança de identidade de sistema (futuro)

Só considerar tocar `os-release`/bootloader quando TODAS as condições abaixo
forem verdadeiras:

1. Existe canal estável próprio, assinado e publicado em registro real.
2. Rebase/atualização testado ponta a ponta (instalação → update → rollback).
3. Decisão de produto registrada em novo ADR.
4. Inventário de licenças atualizado (`docs/licensing/THIRD-PARTY.md`).

## Consequências

- Ferramentas que leem `os-release` continuarão reportando a base Aurora —
  isso é intencional e honesto; a identidade Enthroned OS é consultável via
  `enthroned-identity`.
- Nenhum risco de "brand split" nas atualizações, pois a origem de update
  continua sendo a imagem Enthroned OS derivada (ver
  `docs/operations/UPDATES-FOUNDATION.md`).
