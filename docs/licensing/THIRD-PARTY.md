# Licenças de terceiros e atribuições

Este repositório constrói uma imagem derivada de projetos de terceiros.
Inventário do que é reutilizado e sob quais termos.

## Universal Blue — image-template

- **Fonte:** https://github.com/ublue-os/image-template (branch `main`,
  commit `e9c6420` — estado consultado em 2026-11-16)
- **Licença:** [Apache-2.0](../../LICENSES/Apache-2.0.txt), do arquivo
  [LICENSE da revisão usada](https://github.com/ublue-os/image-template/blob/e9c6420/LICENSE).
- **Reutilizado/adaptado:** estrutura do `Containerfile` (estágio `ctx`,
  execução de `build.sh`, `bootc container lint`), `build_files/build.sh`,
  `Justfile` (receitas build/check/lint/clean/BIB/VM, adaptadas),
  `image-template.env` (contrato de variáveis), `disk_config/disk.toml`,
  `disk_config/iso-kde.toml` → `iso.toml`, `build-disk.yml` (padrão de uso do
  bootc-image-builder-action e actions pinadas por SHA).

## Universal Blue — Aurora

- **Fonte:** https://github.com/ublue-os/aurora — **base da imagem**
  (`ghcr.io/ublue-os/aurora:stable`)
- **Licença:** o [repositório Aurora](https://github.com/ublue-os/aurora/blob/main/LICENSE)
  usa Apache-2.0. A imagem agrega componentes Fedora e Universal Blue sob
  suas respectivas licenças. O inventário da imagem distribuída deve
  identificar essas licenças pela versão efetivamente empacotada.
- **Documentação:** https://docs.getaurora.dev/

## bootc / bootc-image-builder

- **bootc:** https://github.com/bootc-dev/bootc — ferramenta central do
  modelo de imagem bootável, com licenças Apache-2.0 e MIT no upstream.
- **bootc-image-builder:** https://github.com/osbuild/bootc-image-builder
  — ferramenta usada como referência na integração inicial. O Justfile e o
  workflow de discos atuais usam o
  [Image Builder CLI](https://github.com/osbuild/image-builder-cli).

## Fedora Linux

A base final é Fedora (via Aurora); cada pacote RPM mantém sua licença própria
e seus arquivos de licença em `/usr/share/licenses/` na imagem.

## KDE Plasma, Dolphin, Discover e Qt

- A base fornece Plasma e Dolphin. As licenças e os avisos variam por
  componente e versão. Consulte as fontes upstream de
  [Plasma Workspace](https://github.com/KDE/plasma-workspace/tree/master/LICENSES)
  e [Dolphin](https://github.com/KDE/dolphin).
- As telas `org.kde.plasmasetup.prepare` e
  `org.kde.plasmasetup.finished` em `system_files/` usam
  [GPL-2.0-or-later](../../LICENSES/GPL-2.0-or-later.txt). Preserve a atribuição
  e marque as modificações.
  Confira a revisão de origem e os avisos específicos do
  [Plasma Setup](https://github.com/KDE/plasma-setup).
- Settings, Welcome e o plugin de ações do desktop usam módulos Qt 6 e KDE
  Frameworks. Verifique as condições dos módulos efetivamente empacotados,
  incluindo Qt Quick, Qt Quick Controls e Kirigami. Consulte as licenças do
  [Qt 6](https://doc.qt.io/qt-6/licensing.html) e do
  [Kirigami](https://github.com/KDE/kirigami/tree/master/LICENSES).

- **Fonte:** pacote Fedora `discover` instalado explicitamente em
  `build_files/build.sh`, com o backend Flatpak. Verifique as
  [licenças do Discover](https://github.com/KDE/discover/tree/master/LICENSES)
  e os avisos do pacote Fedora na imagem.

## Brave Browser (F4)

- **Fonte:** Flatpak `com.brave.Browser` do Flathub, publicado pela
  **Brave Software** (verificado em https://flathub.org/apps/com.brave.Browser;
  manifest oficial em https://github.com/flathub/com.brave.Browser).
- **Instalação:** provisionada por máquina em primeiro boot
  (`enthroned-firstboot-flatpaks.service`), pelo remote Flathub já configurado
  na base; nenhum binário do Brave é redistribuído ou baixado neste repositório.
- **Licença:** MPL-2.0 (componentes próprios) e licenças de terceiros
  empacotados; avisos mantidos dentro do aplicativo na imagem.

## ArtCraft Launcher (F4, opcional)

- **Fonte:** https://github.com/storytold/craft-launcher (repositório oficial,
  estado consultado em 2026-11-16: release 0.4.1, early alpha).
- **Licença do código:** MIT OU Apache-2.0, à escolha (LICENSE-MIT /
  LICENSE-APACHE verificados no upstream). Nenhum arquivo do projeto é
  redistribuído neste repositório; a instalação opcional baixa sempre do
  lançamento oficial no GitHub, com verificação SHA-256 (SHA256SUMS.txt).
- **Marcas:** o nome "ArtCraft", o logo e a marca "A" são trademarks do
  ArtCraft Team, **não** cobertos por MIT/Apache e não licenciados para forks;
  por isso o Enthroned Welcome cita o nome apenas factualmente (uso nominal),
  NÃO copia nenhum asset gráfico do projeto e aponta para a página oficial.

## Código Enthroned OS (nossa camada)

Decisão do titular (20/11/2026): o código próprio (C++/QML, scripts, unidades
systemd, regras polkit, configurações, workflows e documentação) usa
**Apache-2.0** ([LICENSE](../../LICENSE)). O [NOTICE](../../NOTICE) registra o
titular (`Enthroned OS Project`), os arquivos derivados do template e as telas
adaptadas do Plasma Setup.

- **Artes:** wallpapers, logotipos, wordmarks e as imagens e ícones derivados
  usam a [Enthroned OS Artwork License](../../LICENSES/LicenseRef-Enthroned-Artwork.txt)
  (`LicenseRef-Enthroned-Artwork`), **não** Apache-2.0. A lista de caminhos
  cobertos está nesse arquivo.
- **Marca:** nome e logotipos seguem [TRADEMARKS.md](../../TRADEMARKS.md).
- **GPL-2.0-or-later:** as duas telas do Plasma Setup e o catálogo de tradução
  `org.kde.plasmasetup.po` continuam GPL, nos próprios arquivos.
- O label `io.artifacthub.package.license` do template continua **removido**;
  reavalie-o se a imagem passar a ser publicada.
- Os arquivos derivados do template mantêm o Apache-2.0 do upstream, com as
  cópias dos textos em `LICENSES/`.
- **Titularidade:** em 20/11/2026 o titular confirmou deter a autoria e os
  direitos de distribuição dos originais em `assets/` e das derivações
  (veja `scripts/gen-brand-assets.py`). A licença das artes vale na medida
  dessa titularidade.

## Marcas

"Windows" e "Zorin" são marcas de terceiros; são citados apenas como
referência de inspiração de UX, sem qualquer relação oficial. Nenhum logo,
wallpaper, fonte ou ícone proprietário de terceiros é distribuído neste
repositório.
