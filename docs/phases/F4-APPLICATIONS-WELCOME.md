# F4 — Default Applications & First-Run Experience: estado da fase

- **Data do registro:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11
- **Fonte do escopo:** prompt mestre F4 (fornecido na sessão)
- **Base alvo:** Aurora Stable (KDE Plasma) sobre bootc; apps Qt6/QML/Kirigami

## Objetivos da fase

Política de aplicativos padrão (Brave + Discover, ArtCraft opcional),
integração real de Brave e Discover à distribuição bootc e o assistente
próprio **Enthroned Welcome** (5 telas, persistência por usuário, autostart
controlado, consentimento explícito) — sem builds OCI, sem VM, sem tocar no
host.

## Estados de conclusão (definições separadas)

| Estado | Valor | Evidência |
| --- | --- | --- |
| F4 IMPLEMENTED (em código) | **ATINGIDO** | `welcome/` completo (backend C++ + 7 QML + contrato + fixtures), integração de imagem de Brave/Discover, integração Settings/Launcher |
| F4 STATIC VERIFIED | **ATINGIDO** | `scripts/validate-welcome.sh` (ver relatório em `docs/validation/F4-STATIC-VALIDATION.md`); regressões F2 e F3 continuam 100% |
| F4 LOGIC VERIFIED (contrato, não Qt) | **ATINGIDO** | `welcome/tests/run-tests.mjs` (node): 85 asserções PASS sobre a spec, com 18 cenários fixtures (F4.13.1–18) |
| F4 BUILD VERIFIED (Qt) | **NOT RUN** | Sem Qt6/KF6/cmake no ambiente; apps são SOURCE IMPLEMENTED |
| F4 KDE RUNTIME VERIFIED | **NOT RUN** | UI nunca carregada em Plasma |
| F4 INSTALLATION VERIFIED (Brave/ArtCraft reais) | **NOT RUN / BLOQUEADO** | Nenhuma imagem construída; portão de instalação do ArtCraft fechado por padrão |

## Política de aplicativos implementada

1. **Brave Browser** — navegador padrão; Flatpak de sistema `com.brave.Browser`
   do Flathub (editor verificado: Brave Software), provisionado por máquina em
   primeiro boot (service+timer offline-safe) + defaults XDG em
   `/usr/etc/xdg/mimeapps.list` (usuários existentes intocados).
2. **KDE Discover** — loja padrão; garantida no build (`dnf5 -y install
   discover`, idempotente), pois o upstream Aurora não assegura presença.
3. **ArtCraft Launcher** — opcional; checkbox desmarcado por padrão,
   consentimento em duas etapas, instalação user-level Flatpak com SHA-256,
   execução sob portão de ambiente (fechado por padrão).
4. **Nenhum outro app automático**; essenciais do KDE preservados (nenhuma
   remoção indiscriminada).

## O que foi construído

### Aplicativo Enthroned Welcome (welcome/)
- **CMake + ECM**, Qt6 Quick/QuickControls2/Network, KF6 Kirigami/I18n; QML
  embutido (`qt_add_qml_module`); spec + 4 cenários demo embutidos; regras de
  instalação (binário, `.desktop`, appdata, autostart, ícone).
- **Backend C++**: `WelcomeController` (contrato declarativo compartilhado com
  os testes, persistência atômica `QSaveFile` em
  `$XDG_STATE_HOME/enthroned-os/`, política de abertura, consentimento),
  `ProfileBridge` (reusa `enthroned-profile` da F2.1), `AppAvailability`
  (detecção real Brave/Discover/flatpak, ações apenas quando existem),
  `ArtcraftInstaller` (portão, GitHub oficial, SHA-256, `flatpak install
  --user`, verificação pós-instalação, modo demo por fixtures).
- **QML**: `Main` (janela + indicador de etapas + navegação por teclado) e as
  cinco telas — Bem-vindo, Seu estilo (aplicação de perfil apenas com
  confirmação), Navegador e aplicativos (estados honestos), ArtCraft
  (voluntário, "Agora não"/"Saber mais"), Tudo pronto (resumo honesto).
  i18n `i18n()` pt-BR, `Accessible.*`, nenhuma cor fixa, sem WebView.

### Integração de imagem (F4.11)
- `system_files/usr/etc/xdg/mimeapps.list` (defaults Brave).
- `system_files/usr/share/enthroned-os/firstboot-flatpaks.txt` + unidade
  `enthroned-firstboot-flatpaks.service` (oneshot guardado, sem `[Install]`)
  + `.timer` (retry 6h) + `usr/libexec/enthroned-firstboot-flatpaks`
  (idempotente, offline-safe, sem manipulação de remotes).
- `build_files/build.sh`: `dnf5 -y install discover` + habilita o timer +
  `chmod` do script (padrão dos helpers).
- `Containerfile`: estágio `welcome-builder` preparado e **comentado**.
- Favoritos do Launcher intocados: `preferred://browser` resolve para o
  navegador padrão; nada fixado a IDs de navegador.

### Integração Settings (F4.9)
- `kcmlauncher.{h,cpp}`: `hasExecutable()`, `hasFlatpakApp()`, `launchApp()`.
- `AppsPage.qml`: seção "Experiência Enthroned" (Discover, reabrir Welcome,
  informações do ArtCraft sem atalho morto).

### Documentação
- ADR-0006, arquitetura da primeira experiência, operações (apps padrão +
  integração Welcome), validação estática F4, THIRD-PARTY.md atualizado
  (Brave/Discover/ArtCraft com nota de marca).

## Decisões de fonte verificadas (pesquisa 2026-11-16)

- Flathub `com.brave.Browser` publicado pela Brave Software (manifest oficial
  `flathub/com.brave.Browser`); docs Aurora: Flatpak como via gráfica
  principal e Bazaar citado como instalador (por isso Discover é garantido).
- ArtCraft Launcher: repositório oficial `storytold/craft-launcher`
  (v0.4.1, early alpha; MIT/Apache-2.0; `.flatpak` user-level documentado;
  `SHA256SUMS.txt` em todo release; marca NÃO licenciada para forks → nenhum
  asset copiado, citação apenas nominal).

## Pendências (não executadas nesta fase)

- Compilar os dois apps Qt (estágios desabilitados por política de
  homologação) e homologar em Plasma real.
- Executar build OCI/VM e validar o provisionamento de primeiro boot.
- Homologar o download/instalação real do ArtCraft antes de abrir o portão
  (`ENTHRONED_WELCOME_ALLOW_INSTALL`).

## Riscos técnicos

- A presença do Bazaar no upstream pode gerar duas lojas; decisão pendente de
  produto (remover Bazaar ou aceitar coexistência) — fora do escopo F4.
- O runtime do bundle Flatpak do ArtCraft pode exigir download adicional
  (org.kde.Platform) na primeira instalação.
- `ujust install-system-flatpaks` do Aurora é mecanismo análogo; o
  provisionamento próprio foi mantido autocontido para não depender de
  caminhos upstream não verificados.
