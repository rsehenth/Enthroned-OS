# F2 — Validação estática (trilha de evidências)

- **Data:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11
- **Escopo:** apenas verificações leves autorizadas — nenhuma instalação,
  nenhum build, nenhuma VM, nenhuma alteração no host.
- **Fontes de API:** código-fonte oficial KDE Plasma/6.6 (GitHub mirror
  KDE/plasma-workspace, KDE/plasma-desktop, KDE/breeze), consultado em
  2026-11-16 (lista completa em `docs/phases/F2-DESKTOP-EXPERIENCE.md`).

## 1. Execuções reais

| # | Verificação | Comando | Resultado |
| --- | --- | --- | --- |
| 1 | Camada desktop F2 (74 checagens) | `bash scripts/validate-desktop.sh` | **PASS 74/74** (exit 0) |
| 2 | Regressão de política F1 | `bash scripts/verify-source.sh` | PASS 14 / WARN 2 / FAIL 0 — igual ao baseline F1.1 |
| 3 | Sintaxe do validador | `bash -n scripts/validate-desktop.sh` | PASS |
| 4 | Sintaxe do build (não modificado) | `bash -n build_files/build.sh` | PASS |
| 5 | Sintaxe do gerador de wallpapers | `node --check scripts/enthroned-wallpapers.js` | PASS |
| 6 | Geração dos wallpapers (6 PNGs) | `node scripts/enthroned-wallpapers.js ...` | PASS — 65–186 KB por arquivo |
| 7 | Revisão visual dos PNGs 1920x1080 (light e dark) | leitura de imagem | PASS — gradientes suaves, sem artefatos |

Cobertura das 74 checagens do item 1 (todas PASS):

- JSON válido: identity, release-channel, design-tokens, 2× L&F metadata,
  2× wallpaper metadata (7 arquivos).
- Esquemas de cores: grupos obrigatórios presentes, nome/arquivo coerente,
  cor de seleção definida (2 arquivos).
- Look-and-feel: `KPackageStructure=Plasma/LookAndFeel`, `Id` = diretório,
  `X-Plasma-APIVersion=2`, `defaults` com esquema/wallpaper/auto-referência/
  tema de splash existentes (2 pacotes × 8 checagens).
- Layout scripts: balanceamento, apenas widgets nativos conhecidos, painel
  inferior, plugin de wallpaper, ícone referenciado existente (2 scripts).
- Splash: QML balanceado, tratamento de `stage`, imagens referenciadas
  existentes (2 pacotes).
- Wallpapers: `KPlugin.Id` = diretório, 3 resoluções, mágica PNG (2 × 4).
- XDG: dolphinrc/kdeglobals presentes, parseáveis, coerentes com o L&F
  enviado e com `GlobalViewProps`.
- Branding: arquivos referenciados nos tokens existem (4).
- Higiene: nenhum caminho `/home/` em arquivos distribuídos.

## 2. NÃO EXECUTADO (sem evidência — não afirmar funcionamento)

| Item | Motivo |
| --- | --- |
| Aplicação do L&F em sessão Plasma (`plasma-apply-lookandfeel`) | Sem KDE executável no ambiente |
| Primeiro boot plasmashell (defaults + layout script) | Depende de imagem inicializável |
| Splash screen renderizada | idem |
| Menu kickoff com ícone/favoritos/atalho Meta em execução | idem |
| Dolphin com `/etc/xdg/dolphinrc` ativo | idem |
| Multi-monitor / escalas de DPI | idem |
| Build OCI + bootc container lint | Bloqueio F1 (podman/just ausentes — decisão do usuário) |
| QCOW2/ISO + boot em VM | Depende da OCI |

## 3. Conclusão

- Estado da F2: **IMPLEMENTED + STATIC VERIFIED**.
- Nada da F1 foi alterado (`verify-source.sh` idêntico ao baseline; `build.sh`
  e `Containerfile` sem mudanças).
- Nenhum resultado de runtime é afirmado; a lista acima define exatamente o
  que precisa de homologação em VM.
