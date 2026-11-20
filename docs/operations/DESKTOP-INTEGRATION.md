# Integração desktop à imagem (F2/F2.1)

- **Data:** 2026-11-16 (F2; atualizado em F2.1)
- **Público:** quem constrói a imagem (`docs/operations/BUILD.md`) e quem
  homologa a experiência desktop em VM.

## 1. Como os arquivos chegam à imagem

O `Containerfile` (F1) copia `system_files/` integralmente via
`build_files/build.sh` (`cp -avf /ctx/system_files/. /`). A camada F2 **não
exigiu nenhuma mudança** no `Containerfile` ou no `build.sh`: todos os novos
arquivos já entram na imagem porque vivem sob `system_files/usr/`.

### Mapa de caminhos (repositório → imagem → runtime)

| Repositório (`system_files/...`) | Na imagem | Papel |
| --- | --- | --- |
| `etc/xdg/kdeglobals` | `/etc/xdg/kdeglobals` → `/etc/xdg/kdeglobals` (merge bootc) | Default de sistema; aponta `LookAndFeelPackage=org.enthroned.classic` |
| `etc/xdg/dolphinrc` | `/etc/xdg/dolphinrc` → `/etc/xdg/dolphinrc` | Defaults do Dolphin (Enthroned File Experience) |
| `usr/libexec/enthroned-files-setup` + `etc/xdg/autostart/org.enthroned.files-setup.desktop` | idem | Provisionamento aditivo, 1×/usuário: Places, modo Detalhes, toolbar do Dolphin (ver `FILE-EXPERIENCE.md`) |
| `usr/share/color-schemes/Enthroned{Light,Dark}.colors` | idem | Esquemas de cores |
| `usr/share/icons/hicolor/<N>x<N>/apps/org.enthroned.{launcher-classic,launcher-modern,enthroned-os}.png` | idem | Ícones do menu (E roxo / trono) e marca. **Gate 13.1:** os ícones de aplicativo `org.enthroned.settings` (E) e `org.enthroned.welcome` (trono) vêm dos CMake de `settings/` e `welcome/` (`data/icons/hicolor/`), gerados por `scripts/gen-brand-assets.py` |
| `usr/share/wallpapers/Enthroned{Soberania,Ascensao,Vigilia}/` | idem | **Lote 13:** wallpapers oficiais (originais byte-idênticos, 1672×941) com nomes no seletor nativo do KDE; padrão: Vigília (`wall3.png`). `Enthroned/` e `EnthronedNocturne/` (procedurais) continuam instalados só por compatibilidade com configurações existentes |
| `usr/share/plasma/look-and-feel/org.enthroned.classic/` | idem | Perfil Classic (L&F KPackage) |
| `usr/share/plasma/look-and-feel/org.enthroned.modern/` | idem | Perfil Modern (L&F KPackage) |
| `usr/share/plasma/plasmoids/org.enthroned.launcher/` | idem | **Enthroned Launcher — menu Iniciar próprio (plasmoid nativo, modelos kicker)** |
| `usr/bin/enthroned-profile` | idem | CLI de troca de perfil (plasma-apply-lookandfeel; `chmod 0755` no build.sh) |
| `usr/share/enthroned-os/branding/design-tokens.json` | idem | Fonte única da identidade (documental) |

No container, os defaults são escritos diretamente em `/etc/xdg`. O bootc gerencia
`/etc` durante o deploy (merge 3-way em atualizações). Como o
`XDG_CONFIG_DIRS` padrão inclui `/etc/xdg`, esses arquivos funcionam como
camada de default para **todos** os usuários — sem scripts de first-boot e
sem tocar em `$HOME`. Configurações em `~/.config` sempre vencem.

## 2. Sequência de primeiro login (usuário novo)

1. plasmashell lê `kdeglobals`: `~/.config` vazio → usa `/etc/xdg`
   → `LookAndFeelPackage=org.enthroned.classic`.
2. O L&F é aplicado: mescla `contents/defaults`
   (`kdeglobals`: esquema/ícones/estilo; `kcminputrc`: cursor + **clique
   duplo**; `plasmarc`: tema Plasma Breeze; `kwinrc`: decorações; `Wallpaper`:
   papel de parede; `KSplash`) e executa
   `contents/layouts/org.kde.plasma.desktop-layout.js`.
3. O script cria o painel inferior com o **Enthroned Launcher** (atalho
   Meta), icontasks, bandeja e relógio; se o plasmoid do launcher não puder
   ser instanciado, aplica automaticamente o kickoff nativo com o mesmo
   ícone e favoritos curados (fallback). O desktop recebe o widget nativo
   da Lixeira (`org.kde.plasma.trash`) e permanece no Folder View nativo.

## 3. Troca de perfil (mecanismos oficiais)

```bash
# CLI Enthroned (registra o anterior para 'restore'):
enthroned-profile status
enthroned-profile list
enthroned-profile apply modern    # ou: apply classic
enthroned-profile restore

# Diretamente, sem a CLI:
plasma-apply-lookandfeel -a org.enthroned.modern
plasma-apply-lookandfeel -a org.enthroned.classic

# Reversibilidade total para o padrão KDE:
plasma-apply-lookandfeel -a org.kde.breeze.desktop   # ou outro L&F instalado
```

`plasma-apply-lookandfeel` é a ferramenta oficial do Plasma 6: aplica os
defaults do pacote e executa seu layout script (reorganiza painéis do
look-and-feel escolhido). A CLI `enthroned-profile` é uma camada fina sobre
ela (sem root, sem daemon): grava o look-and-feel anterior em
`$XDG_STATE_HOME/enthroned-os/previous-lookandfeel` para o `restore` (um
passo; não promete reversão de preferências individuais — o mecanismo KDE
não garante isso). O seletor nativo **System Settings → Colors & Themes →
Look and Feel** também lista os dois perfis. O Enthroned Launcher declara
`X-Plasma-Provides: org.kde.plasma.launchermenu`, portanto kickoff e
launcher são oferecidos como alternativas oficiais entre si (botão direito
no item do painel → "Mostrar alternativas").

## 4. Regras de propriedade (o que NÃO é tocado)

- `$HOME` de qualquer usuário existente: nunca escrito pela camada F2/F2.1.
- Configurações pessoais do KDE (`~/.config/*`): nunca sobrescritas; os
  defaults valem só para chaves que o usuário não definiu. A única escrita
  do `enthroned-profile` em `$HOME` é o registro de restore em
  `$XDG_STATE_HOME/enthroned-os/` (arquivo próprio do utilitário).
- Aurora upstream: `os-release`, bootloader, kernel, KWin, mecanismo atômico
  de atualização — intocados (ADR-0003).
- Confirmações destrutivas do Dolphin (exclusão, lixeira): preservadas.

## 5. Verificação local (sem KDE)

```bash
just verify-desktop   # scripts/validate-desktop.sh: 116 checagens estáticas
just verify-source    # regressão da política F1
```

## 6. Homologação pendente (requer imagem + VM)

1. `just build && just verify-image` (bloqueio F1: podman/just).
2. Em QCOW2 (VirtualBox): primeiro login → conferir Classic aplicado
   (cores, painel sólido, wallpaper, clique duplo), **Enthroned Launcher
   abrindo** (busca, categorias, favoritos, abertura de app, menu de
   energia), Meta abre o menu, Lixeira na área de trabalho.
3. Fallback do launcher: renomear o diretório
   `/usr/share/plasma/plasmoids/org.enthroned.launcher` num deploy de teste
   e reaplicar o L&F → o painel deve nascer com o kickoff configurado.
4. `enthroned-profile apply modern` → conferir perfil Modern (escuro, painel
   flutuante centralizado, ícone do trono, wallpaper Vigília, relógio sem data) e
   `enthroned-profile restore`.
5. Alternativa de menu: botão direito no launcher → "Mostrar alternativas"
   → kickoff (e o inverso).
6. Dolphin: caminho completo na barra/título, "Copiar para/Mover para" no
   menu de contexto, pasta aberta por outro app vira aba.
7. Comparar `/etc/xdg/kdeglobals` com o mesmo caminho na imagem Aurora
   pura (se existir) e mesclar chaves Aurora relevantes, se houver.
8. Telas multi-monitor e escalas de DPI diferentes (o layout script itera
   `desktopsForActivity`; o painel usa `screen` padrão).

## 7. Pontos de extensão futuros

- **F3 — Central de Atualizações:** novo plasmoid
  (`usr/share/plasma/plasmoids/org.enthroned.<id>/`) + inclusão no layout
  script dos dois perfis. Backend real (rpm-ostree/bootc) é pré-requisito
  para qualquer botão funcional.
- **F3 — UI gráfica de perfil:** evoluir o `enthroned-profile` para uma
  interface própria (KCM ou plasmoid) sem perder o caminho CLI.
- **Launcher v2 (Lote 3, em código):** menus de contexto (fixar/desafixar,
  mover), grade de fixados, locais e ferramentas — ver `START-MENU.md`.
  Pendente: drag-and-drop.
- **F4 — Brave/ArtCraft:** instalar via build; `preferred://browser` nos
  favoritos/fixados passa a resolver para o navegador padrão automaticamente.
- **Tema Plasma próprio (`plasmarc`) e tema de ícones completo:** fases
  futuras, se a identidade exigir mais que Breeze + paleta.
