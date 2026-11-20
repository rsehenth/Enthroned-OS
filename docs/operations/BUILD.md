# Build do MVP Enthroned OS

Este registro descreve a preparação do MVP em 16/11/2026. Para o estado
atual do projeto e os comandos básicos, consulte o [README](../../README.pt-BR.md).

Estado em 16/11/2026: **SOURCE READY / BUILD BLOCKED**. Nenhum aplicativo Qt
compilado, nenhuma imagem OCI/disco produzida e nenhum boot observado nesta sessão.
A preparação abaixo está integrada; ainda depende de compilação e homologação.

## Integração preparada

- `Containerfile`: Aurora runtime comum; builder Qt/ECM separado; CTest nativo;
  instalação CMake via DESTDIR; imagem final sem os devel RPMs adicionados.
- Settings/Welcome: includes e contratos C++20/Qt corrigidos, imports QML locais,
  recursos no prefixo padrão `/qt/qml`; QApplication para o ambiente KDE.
- Welcome: autostart com TryExec, instância única, progresso por usuário,
  Pular conclui sem consentir ArtCraft; demo não altera o progresso real.
- Desktop: layouts com o nome exigido pelo Plasma, defaults em `/etc/xdg`;
  Um único botão Iniciar: o Kickoff só entra no painel se o launcher não puder ser criado; em falha tardia de QML a recuperação é "Mostrar alternativas" → Kickoff.
- Discover e backend Flatpak explícitos. Brave provisionado pelo timer em Flathub,
  com tentativa inicial após oito minutos e repetição a cada seis horas.
  Sem rede, Brave pode faltar; o desktop e o Welcome continuam independentes.
- Update Center: leitura bootc/systemd corrigida; demonstração identificada;
  portões de atualização/reboot e de instalação ArtCraft fechados por padrão.
- Git preservado: main sem commits, conteúdo não rastreado, sem remote.
  Nenhum reset, clean, stash, commit, push ou publicação executado.

## Ambiente e autorização pendente

Ubuntu WSL2 26.04.1, 20 CPUs visíveis, cerca de 15 GiB de RAM no WSL e 947 GiB
livres no filesystem Linux (também depende do espaço físico do Windows).
VirtualBox 7.2.22 presente. Podman, just, jq, qemu-img e shellcheck ausentes.
CMake/Qt/KF6 serão instalados somente no builder do container, não no Ubuntu.

As negativas anteriores continuam válidas. Aprovar separadamente antes de executar:

1. Instalação no WSL: `apt-get update` e
   `apt-get install --no-install-recommends podman just jq qemu-utils shellcheck`.
   Simulação local: 19 novos pacotes, nenhum removido ou atualizado;
   estimativa de 50–200 MB de download e 200–600 MB de disco, 2–10 minutos.
2. Build OCI, testes Qt, QCOW2 e conversão VDI: estimativa de 6–12 GB de download,
   40–70 GB livres para camadas/cache/discos, 30–120 minutos conforme rede/cache.
   Limites preparados: quatro CPUs, 10 GiB e quatro jobs de compilação.
3. Criação e boot da VM VirtualBox: quatro vCPUs, 8 GiB RAM, disco virtual de
   64 GiB, sem GPU passthrough; 20–40 minutos para o primeiro smoke test.

Estimativas não são medições de build. A consulta leve ao registry encontrou
3,59 GiB em camadas comprimidas da Aurora stable, digest
`sha256:5dc1c43489f3784a3f1ec66bc435d80f6190a5a8133eb12eb49133ff692c342b`.
Não foi feito pull dessas camadas. A tag pode mudar; registrar o digest real no build.

## Build local, somente após autorização

No Ubuntu WSL2, execute na raiz do checkout:

```bash
just doctor
just verify-source
just verify-desktop
just verify-settings
just verify-welcome
just build
just verify-image
```

`just build` usa Podman rootful para compartilhar o armazenamento com o gerador
de discos. O Containerfile executa CTest antes da instalação. `verify-image` testa
bibliotecas, arquivos instalados e inicialização QML em demo offscreen, sem rede;
isso não substitui o teste gráfico na VM.

Antes de atualizar a base ou finalizar um build, salvar evidências em `output/`:

```bash
mkdir -p output
sudo podman image inspect ghcr.io/ublue-os/aurora:stable > output/aurora-base.json
sudo podman image inspect localhost/enthroned-os:f1-dev > output/enthroned-image.json
```

O segundo digest é o da derivada; não usar como se fosse o digest da Aurora.

## QCOW2 e VDI, somente após autorização do build

O CLI atual `ghcr.io/osbuild/image-builder-cli` consome a imagem local no mesmo
armazenamento rootful. Não exige publicar em registry. A receita usa `build`,
`--bootc-ref`, `--blueprint` e saída explícita. O caminho MVP não gera ISO.

Criar a configuração privada de login antes do disco:

```bash
cp disk_config/vm.example.toml disk_config/vm.local.toml
openssl passwd -6
# Digitar uma senha local no prompt, sem colocá-la no histórico ou no chat.
# Colar o hash resultante no campo password de vm.local.toml.
chmod 600 disk_config/vm.local.toml
just build-qcow2
bash scripts/verify-artifacts.sh output/qcow2/disk.qcow2
qemu-img convert -f qcow2 -O vdi output/qcow2/disk.qcow2 output/EnthronedOS-MVP.vdi
bash scripts/verify-artifacts.sh output/EnthronedOS-MVP.vdi
```

Usuário da VM: `enthroned`. Nenhuma senha padrão é fornecida. `vm.local.toml`
é ignorado pelo Git; a receita bloqueia o placeholder. Não anexar esse arquivo
em relatórios ou artefatos públicos. A compatibilidade de criação do usuário
com a base Aurora ainda precisa ser confirmada no boot.

O `disk_config/disk.toml` e o `iso.toml` antigos ficam preservados como legado;
QCOW2/raw usam `vm.local.toml`. ISO permanece bloqueada no caminho MVP.

## GitHub Actions

Sem remote e sem commits, CI não pode executar este checkout. Alternativa B
exige autorização para preparar o repositório remoto/commit/push e disparar o build.
Os workflows permanecem sem publicação OCI automática. `build-preview.yml` exporta
OCI; `build-disk.yml` exige uma imagem já disponível em registry e não configura
login gráfico de usuário. Para o primeiro boot utilizável, preferir a rota local
com blueprint privado. Nenhum workflow foi disparado nesta sessão.

## Evidências e limites

Verificações leves executadas nesta sessão: 523 checagens estáticas
(118 desktop, 216 Settings, 189 Welcome), 313 asserções JavaScript (228 + 85),
seis cenários simulados do layout e quatro execuções do helper de perfil com
comandos KDE substituídos por fixtures isoladas. Tudo passou. Sintaxe Bash:
11 arquivos e 23 blocos do Justfile; parser `just` e shellcheck não disponíveis.
Política da fonte: 14 PASS, dois WARN (jq ausente e placeholder da ISO legado).

Verificações estáticas e modelos JavaScript não comprovam compilação C++ ou QML.
Os testes nativos preparados e o smoke offscreen ainda não foram executados.
Artefatos OCI/QCOW2/VDI/ISO e hashes de artefatos: **nenhum**.
Critérios de boot e uso: [VM-FIRST-BOOT.md](VM-FIRST-BOOT.md).
P2: ajustes cosméticos já conhecidos ficam para depois; nenhuma nova rodada visual.

Fontes oficiais consultadas:
[Aurora derivada](https://docs.getaurora.dev/guides/building/),
[Image Builder e armazenamento local](https://osbuild.org/docs/developer-guide/projects/image-builder/usage/),
[customizações QCOW2](https://osbuild.org/docs/user-guide/image-descriptions/bootc/qcow2/),
[filesystem bootc](https://bootc.dev/bootc/filesystem.html),
[layout Plasma 6](https://develop.kde.org/docs/plasma/theme/theme-porting-to-plasma6/),
[recursos QML](https://doc.qt.io/qt-6.8/qt-add-qml-module.html).
