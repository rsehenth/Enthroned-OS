# Lote 4 — Configurações gerais

Estado: **SOURCE READY / STATIC VERIFIED**. Nada foi compilado, instalado ou
executado (sem build Qt, OCI, VM, commit ou push). Decisões: ADR-0007.

## Páginas

| Área | Arquivo | Conteúdo real |
| --- | --- | --- |
| Início | `HomePage.qml` | nome do computador, versão/canal, perfil visual ativo, rede, estado das atualizações, 6 atalhos frequentes, resumo de hardware |
| Sistema | `SystemPage.qml` | atalhos Tela/Som/Notificações/Energia/Áreas virtuais; política de atualização automática (uupd, somente leitura) |
| Bluetooth e dispositivos | `DevicesPage.qml` | Bluetooth, mouse, touchpad, teclado, impressoras, controles, mesa digitalizadora, mídia removível, KDE Connect (módulos KDE) |
| Rede e Internet | `NetworkPage.qml` | estado do NetworkManager (D-Bus, leitura), nome na rede, módulo de conexões |
| Personalização | `AppearancePage.qml` | perfis Classic/Modern (F2.1), tema claro/escuro, papel de parede, 8 atalhos KDE (cores, janelas, efeitos, ícones, cursor, fontes, tema global, splash) |
| Aplicativos | `AppsPage.qml` | padrões, notificações, inicialização, permissões Flatpak, Discover, Welcome, ArtCraft (inalterado) |
| Contas | `AccountsPage.qml` | usuário atual; módulo de usuários do KDE |
| Hora e idioma | `TimeLanguagePage.qml` | fuso e locale em uso; módulos de data/hora, idioma/região, teclado |
| Acessibilidade | `AccessibilityPage.qml` | módulos de acessibilidade, fontes, cores, cursor, lupa; Orca se instalado |
| Privacidade e segurança | `PrivacyPage.qml` | SELinux, `/usr` somente leitura; bloqueio de tela, carteira, recentes, Baloo, firewall, permissões Flatpak |
| Atualizações do sistema | `UpdatesPage.qml` | fluxo existente + versões, origem da imagem, motivo de bloqueio, listas separadas sistema/Flatpak |
| Sobre o dispositivo | `AboutPage.qml` | especificações reais, copiar especificações, detalhes avançados (base técnica, origem, deployments, SELinux), licenciamento |

## Funcionalidades reais integradas

- `DeviceInfoProvider` (CPU, RAM, GPU, volumes, modelo, SELinux, `/usr`), assíncrono.
- `PersonalizationController` (`plasma-apply-colorscheme`, `plasma-apply-wallpaperimage`), allowlist.
- Origem da imagem + motivo de bloqueio no `UpdateEngine`; `systemUpdates`/`appUpdates`.
- `KcmLauncher.available` (propriedade com notificação) corrige o estado dos cartões
  quando a listagem assíncrona termina depois da página; `launch()` só abre módulos listados.
- Busca local (`search.js` + `SearchIndex.qml`) com sinônimos, sem acento, AND de palavras.

## Navegação e acessibilidade

Ctrl+F foca a busca; ↓ vai aos resultados; Enter abre o primeiro/atual; Esc limpa.
Lista de áreas navegável por teclado com anel de foco; abaixo de ~42 unidades de
grade a navegação vira ícones (botão de menu/lupa a expande); janela mínima ≈ 28×24
unidades. Cores sempre do esquema ativo; nenhum asset de terceiros.

## Bloqueado / fora do escopo

Ver ADR-0007 §5: execução de atualização (portão fechado), unidade só-sistema,
versão disponível antes do download, cancelamento real, `expected_image_references`
vazio, renomear dispositivo, trocar imagem. Nenhum botão sugere esses recursos.

## Arquivos

Novos: `settings/src/{deviceinfoprovider,personalizationcontroller}.{h,cpp}`,
`settings/src/update/imageorigin.h`, `settings/qml/{SearchIndex.qml,search.js}`,
`settings/qml/components/{ModuleCard,ModuleList,ShortcutTile}.qml`,
`settings/qml/pages/{Network,Accounts,TimeLanguage,Accessibility,Privacy}Page.qml`,
este documento, ADR-0007 e `docs/validation/BATCH-4-STATIC-VALIDATION.md`.
Alterados: `main.cpp`, `CMakeLists.txt`, `kcmlauncher.{h,cpp}`,
`systemidentityprovider.{h,cpp}`, `update/updateengine.{h,cpp}`, `Main.qml`, as páginas
Home/System/Devices/Appearance/Apps/About/Updates, `tests/{run-tests.mjs,native-smoke.cpp}`,
`scripts/validate-settings.sh`, `release-channel.json` e os documentos de operação.
