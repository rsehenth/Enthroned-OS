# ADR-0001: Aurora Stable como base da imagem Enthroned OS

- **Status:** Aceito
- **Data:** 2026-11-16
- **Fase:** F1 — Foundation
- **Fontes consultadas:** https://github.com/ublue-os/image-template (commit `e9c6420`, branch `main`), https://github.com/ublue-os/aurora, https://docs.getaurora.dev/guides/building/

## Contexto

Enthroned OS é uma distribuição Linux própria futura. É necessário escolher uma
base de imagem real, mantida por terceiros, sobre a qual construiremos nossa
camada. A experiência final (F2+) será inspirada na simplicidade do Zorin OS e
na familiaridade do Windows 11, com identidade e código próprios — mas a base
técnica precisa ser sólida, atualizável e reversível desde o primeiro dia.

O estado do arquivo `ARQUITETURA_SISTEMA_AURORA_UX_v0.2.md` não estava
disponível no workspace durante a F1; os requisitos centrais usados aqui foram
fornecidos diretamente (Aurora Stable/Fedora/KDE, identidade própria, sem
comprometer upstream).

## Decisão

A base da imagem Enthroned OS é **Universal Blue Aurora, tag `stable`**
(`ghcr.io/ublue-os/aurora:stable`), declarada explicitamente no `Containerfile`.
A cadeia de derivação é:

```
Fedora Linux (bootc)  →  Universal Blue Aurora (KDE Plasma, kernel/drivers via akmods)
                      →  Enthroned OS (camada própria: identidade, defaults, UX futura)
```

A estrutura do repositório deriva do template oficial **image-template**
(Apache-2.0), adaptado explicitamente de Bazzite para Aurora.

## Justificativas

1. **KDE Plasma nativo** — alinhado à visão de desktop familiar/Windows-like;
   o Aurora já entrega o desktop completo com integração Universal Blue.
2. **Manutenção herdada** — kernel, firmware, drivers (akmods), codecs e
   configurações de desktop são mantidos pelo upstream; nossa camada fica
   pequena e auditável.
3. **Modelo bootc/OCI** — a imagem é um contêiner OCI bootável: build
   reproduzível por pipeline, atualização atômica com rollback por
   deployment (ostree/bootc), sem mutação do sistema em execução.
4. **Caminho documentado** — a documentação da Aurora recomenda
   explicitamente derivar via `FROM ghcr.io/ublue-os/aurora:stable` usando o
   image-template (consultado em docs.getaurora.dev/guides/building/).

## Limites de customização

- **Não modificar** `/etc/os-release`, identidade do bootloader, layout de
  partições ou metadados de fabricante da base — isso preserva o mecanismo de
  atualização e a procedência do sistema.
- Identidade Enthroned OS vive em **nosso próprio namespace**
  (`/usr/share/enthroned-os/`, comando `enthroned-identity`), ver ADR-0003.
- Toda modificação de sistema passa por `build_files/build.sh` +
  `system_files/`, minimalista e idempotente (política da F1: nenhum pacote
  extra, nenhum serviço novo).
- SELinux, o modelo de atualizações e os mecanismos de recuperação do Aurora
  permanecem intocados.

## Modelo de rollback

O bootc mantém múltiplos deployments; um `bootc rollback` (ou seleção do
deployment anterior no GRUB) restaura a imagem anterior atômica. Como nossa
camada é um subconjunto pequeno e sem mutações de kernel/partições, o rollback
cobre também as nossas mudanças.

## Consequências e riscos

- **`stable` é uma tag móvel**: dois builds na mesma semana podem partir de
  bases diferentes. Política de pinning e registro de digest: ADR-0002.
- **Dependência de upstream**: quebras no Aurora chegam ao nosso build; o
  monitoramento acontece naturalmente na reconstrução (CI).
- **Não é reprodutibilidade bit a bit**: builds não são determinísticos;
  a rastreabilidade é por digest OCI + SHA-256 de artefatos, não por
  igualdade de bytes.
- Base não é Bazzite nem Fedora puro — `scripts/verify-source.sh` falha se a
  referência de base divergir.
