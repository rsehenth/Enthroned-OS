# ADR-0006 — Política de aplicativos padrão e primeira experiência (F4)

- **Data:** 2026-11-16
- **Status:** Aceita (implementada em código; builds ainda não executados)
- **Contexto anterior:** ADR-0001 (upstream Aurora), ADR-0002 (segurança de
  build), ADR-0003 (identidade), ADR-0004 (artefato de imagem), ADR-0005
  (integração de atualizações)

## Contexto

A F4 define o que o usuário encontra ao instalar o Enthroned OS: navegador
padrão, loja de aplicativos e o assistente Enthroned Welcome. A base
(Aurora Stable, KDE Plasma) não define um navegador padrão próprio, os docs
oficiais do Aurora citam o Bazaar como instalador de Flatpaks (a presença do
KDE Discover no upstream não é garantida), e o bootc não comita `/var` na
imagem — o que impede embutir Flatpaks no build OCI.

## Decisões

1. **KDE Discover é a única loja de aplicativos gráfica.** Garantida
   explicitamente no build (`dnf5 -y install discover`, idempotente) em vez de
   presumida do upstream. O Enthroned não cria loja própria e não adiciona
   remotes Flatpak fora do Flathub já configurado pela base.
2. **Brave Browser é o aplicativo adicional padrão**, distribuído como
   **Flatpak de sistema do Flathub** (`com.brave.Browser`, publicado pela
   própria Brave Software — editor verificado). Motivos:
   - atualizações diárias pelo caminho Flatpak já integrado ao uupd
     (um navegador em RPM embutido no build só atualizaria quando o Enthroned
     reconstruísse a imagem);
   - sem layering RPM (`rpm-ostree install` é recurso de último recurso na
     base; o RPM oficial do Brave também exigiria um repositório de terceiros
     novo);
   - a alternativa de instalar no build (`flatpak install` durante
     `podman build`) não persiste, porque `/var/lib/flatpak` não é commitado.
3. **Provisionamento do Brave em primeiro boot, por máquina:** unidade
   `enthroned-firstboot-flatpaks.service` (oneshot, guardada por
   `ConditionPathExists`) + `…timer` (retry até obter sucesso; offline-safe).
   Instala apenas IDs da lista `/usr/share/enthroned-os/firstboot-flatpaks.txt`,
   não manipula remotes e grava marcador em `/var/lib/enthroned-os/`.
   Isto é provisionamento de aplicativos da distribuição (decisão de imagem,
   como o Firefox no Fedora), **não** um mecanismo de primeira execução por
   usuário — o Welcome continua sendo XDG autostart + estado por usuário.
4. **Navegador padrão por XDG defaults:** `/usr/etc/xdg/mimeapps.list` define
   `x-scheme-handler/http`, `x-scheme-handler/https` e `text/html` apontando
   para `com.brave.Browser.desktop`. Preferências por usuário
   (`~/.config/mimeapps.list`) sempre vencem: usuários existentes não são
   alterados. Com o Brave definido como padrão, os favoritos do Enthroned
   Launcher que usam `preferred://browser` resolvem para ele automaticamente
   (nenhum favorito é fixado a um ID de navegador).
5. **Enthroned Welcome é aplicativo próprio Qt6/QML/Kirigami** (`welcome/`),
   com estado por usuário em `$XDG_STATE_HOME/enthroned-os/welcome-state.json`
   (gravação atômica), XDG autostart (`/etc/xdg/autostart`, somente KDE) e
   instância única por `QLockFile`. Nenhum serviço de sistema controla a
   primeira execução individual.
6. **ArtCraft Launcher é opcional e nunca automático.** Fonte oficial
   verificada (GitHub `storytold/craft-launcher`, early alpha). O caminho de
   instalação implementado é o bundle Flatpak oficial via
   `flatpak install --user` (sem root, sem mutação do sistema, sem layering),
   com verificação SHA-256 do `SHA256SUMS.txt` do release. A execução real é
   controlada por portão de ambiente (`ENTHRONED_WELCOME_ALLOW_INSTALL=1`), no
   mesmo padrão do portão de mutação da F3; sem o portão, a ação reporta
   honestamente "bloqueada nesta fase" e não há acesso à rede. Nenhum asset
   gráfico do ArtCraft é redistribuído (marca não licenciada para forks).

## Consequências

- A contagem de aplicativos da imagem cresce pelo Brave (218 MiB Flatpak) e
  pelo Discover; aplicativos essenciais do KDE são preservados (nenhuma
  remoção indiscriminada).
- Sem conexão no primeiro boot: o Brave entra depois (timer/Discover) e o
  desktop continua funcional; o Welcome é 100% utilizável offline.
- O estágio `welcome-builder` do Containerfile segue **desabilitado** até
  homologação (mesma política do `settings-builder` da F3).
- Dois aplicativos Qt compartilham a mesma linguagem visual e padrões
  (controllers, spec declarativa, fixtures), sem segunda base de interface.

## Alternativas descartadas

- **RPM do Brave embutido no build:** atualizações lentas + repo de terceiros.
- **AppImage do Brave:** sem atualizações gerenciadas; Flathub oficial existe.
- **Instalar Flatpaks no build OCI:** não persiste (bootc não comita `/var`).
- **Instalar o ArtCraft via RPM/AppImage como caminho padrão:** RPM exige
  elevação e layering; AppImage exigiria gestão de desktop-entry própria. O
  bundle Flatpak user-level é o caminho sem root, removível pela loja.
