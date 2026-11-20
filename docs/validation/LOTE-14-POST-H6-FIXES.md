# Enthroned OS — Lote 14: ajustes pós-H6

19 de novembro de 2026 · America/Sao_Paulo
Classificação: **SOURCE READY / STATIC VERIFIED / AURORA-QML VERIFIED** (Plasma real e VM: pendentes, ver §5).

## Resumo executivo

Três correções de código pequenas, uma atualização de assets, a investigação das lacunas da H6 e a
proposta técnica do Dolphin. Nada foi compilado como imagem: não há OCI, ISO, QCOW2, VDI nem H7. A VM H6,
os artefatos e as evidências da H6/H5, os backups anteriores e as políticas de update/bootc/polkit/systemd
não foram tocados. Sem commit e sem push.

| Item | Resultado |
| --- | --- |
| P1 — ícone do Menu Iniciar pequeno | Corrigido em `CompactRepresentation.qml` (causa: arredondamento do ícone, não os PNGs). Glifo 19–28 % maior; sem corte no hover. |
| P3 — relógio Modern mostrando data | Corrigido no layout Modern (causa: `showDate` gravado no grupo errado). Classic intacto. |
| `wall1.png` / `wall3.png` novos | Propagados para os pacotes `EnthronedSoberania` e `EnthronedVigilia` (bytes idênticos aos originais) e miniaturas regeneradas. |
| 3 unidades `masked-runtime` | Explicado e reproduzido: vem do `systemd.mask=` na linha de comando do kernel do disco da VM. A máscara persistente existe na imagem. |
| P4 — teclado no Plasma Setup | Investigado sem fork. Parte reproduzida, parte só confirmável na VM; texto de relato upstream em §4. |
| P2 — cor de pastas no Dolphin | Proposta (não implementada): o Dolphin da Aurora já traz a ação nativa. §6. |

## 1. Ícones do Menu Iniciar (P1)

**Diagnóstico.** Os PNGs hicolor (`org.enthroned.launcher-classic` = E Logo-2, `-modern` = Throne-2) já são
recortados rente ao alfa: nos tamanhos ≤ 32 px o glifo ocupa 94 % da altura da célula (ex.: 18×30 px em 32 px
para o E; 24×30 para o trono; 26×44 e 34×44 em 48 px). Não há padding interno a remover. O encolhimento
vinha do QML: o `Kirigami.Icon` do botão tinha margem de 4 px e `roundToIconSize`, então a célula de 40 px
(painel Modern, 48 px) ou 36 px (painel Classic, 44 px) virava um ícone de **32 px**. Os vizinhos
(`icontasks`) são ícones de aplicativo de 32 px que preenchem o quadrado; os glifos da marca são altos e
estreitos (o E tem proporção 0,58 e só ~15 % de pixels opacos; o trono, 0,76 e ~36 %).

**Correção** (`system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/CompactRepresentation.qml`):
margem do ícone `smallSpacing * 0.75` (3 px, ainda dentro da camada de estado de 2 px) e
`roundToIconSize: false`. O Kirigami escolhe o PNG de 48 px e reduz com suavização. Não foram alterados os
PNGs, a transparência, a lógica de perfis, o `main.qml` nem o nº de widgets; o Kickoff de recuperação segue
inalterado.

**Medição na Aurora fixada** (Qt 6.11.2, Kirigami real, `QT_QPA_PLATFORM=offscreen`, software; harness e
imagem em `docs/evidence/lote14/`). Caixa do glifo em px, antes → depois; vizinho (Dolphin 32 px): 30×26.

| Perfil / painel | Célula | Antes | Depois | Altura | Tinta (px) |
| --- | --- | --- | --- | --- | --- |
| Classic E, 44 px | 32 → 38 | 17×26 | 19×31 | +19 % | 216 → 272 |
| Modern trono, 48 px | 32 → 42 | 24×29 | 28×37 | +28 % | 341 → 516 |

Tamanhos fixos pedidos (célula = tamanho, PNG hicolor correspondente): 24 px → E 12×19 / trono 18×21;
32 px → 17×26 / 24×29; 48 px → 24×40 / 32×41. Todos nítidos e sem corte; a camada de hover (18 %) não
encosta no glifo. **Limite:** o E é intrinsecamente fino (tinta ≈ 1/3 do vizinho mesmo ampliado); igualar a
massa visual exigiria alterar o desenho, o que o lote proíbe. Falta conferir no Plasma real (§5).

## 2. Relógio Modern (P3)

**Causa.** `org.kde.plasma.digitalclock` lê `showDate`, `dateFormat`, `use24hFormat` etc. do grupo de
configuração **`Appearance`** (os scripts de atualização do próprio Plasma, `digitalclock_*.js`, e a página
`configAppearance.qml` usam esse grupo). O layout Modern gravava `["General"]/showDate=false`, que o applet
ignora; o padrão do Plasma mostrou a data. O Classic escreve no mesmo grupo errado (`showDate=true`), mas isso
coincide com o padrão e **não foi alterado**, como pedido.

**Correção** (`.../org.enthroned.modern/contents/layouts/org.kde.plasma.desktop-layout.js`):
`clock.currentConfigGroup = ["Appearance"]` antes de `writeConfig("showDate", false)`. Só essa chave é
gravada, então formato regional (pt_BR) e demais ajustes do relógio não são forçados. O teste estático
`scripts/validate-desktop.sh` ganhou a verificação "modern clock writes showDate in the Appearance group"
(inclui garantir que `use24hFormat`/`dateFormat` não sejam escritos).

**Limitações.** (a) A correção vale quando o layout roda: instalação nova ou `enthroned-profile apply modern`.
Sistemas já configurados não são migrados. (b) `--resetLayout` recria o painel e **perde ajustes pessoais do
relógio**; só o wallpaper é preservado por `enthroned-profile`. Isso é anterior ao lote; se o proprietário
quiser preservá-los, o caminho é o mesmo `evaluateScript` já usado para o wallpaper (item de backlog).
(c) Não pude ler o `main.xml` do applet (empacotado/compilado no Plasma 6.8.3 da Aurora); o grupo foi
confirmado pelos scripts de update e pelos nomes `cfg_showDate`/`cfg_dateDisplayFormat` da página de
configuração. Confirmar o resultado visual no Plasma real.

## 3. Wallpapers `wall1.png` e `wall3.png` atualizados

O proprietário alterou `assets/wall1.png` e `assets/wall3.png` (ambos continuam 1672×941; `wall2` não mudou).
Executado `scripts/gen-brand-assets.py` (cópia byte a byte + miniatura de 640×360). Antes e depois do script,
o hash de todos os arquivos de `system_files/`, `settings/` e `welcome/` foi comparado: **só 4 arquivos
mudaram**, nada mais foi reescrito.

| Pacote | Arquivo | SHA-256 antigo → novo |
| --- | --- | --- |
| `EnthronedSoberania` (wall1) | `contents/images/1672x941.png` | `5ee479e7…126986f` → `f1c01b6b…49614fc8f` |
| `EnthronedVigilia` (wall3, padrão) | `contents/images/1672x941.png` | `65880331…365ccd` → `b706c984…8db93c` |
| ambos | `contents/screenshot.png` | regenerados |

Cópia anterior preservada em `.backup-lote14/system_files/usr/share/wallpapers/`. `validate-desktop.sh`
confirma "byte-identical to assets/wall1.png / wall3.png". A próxima build já os inclui (o `build.sh` copia
`system_files/`). A H6 **não** os contém.

## 4. Lacunas de homologação

### 4.1 Executado agora (sem VM e sem reconstrução)

| Verificação | Onde | Resultado |
| --- | --- | --- |
| `scripts/validate-desktop.sh` | host | ALL CHECKS PASSED (inclui o novo check do relógio e os wallpapers) |
| `scripts/test-layouts.mjs` | host | 6 cenários OK (API do Plasma **simulada**; Plasma real NÃO executado) |
| `scripts/test-profile-wallpaper-preserve.sh` | host | PASS (snapshot/restauração do wallpaper, retries, sem cliente D-Bus) |
| `test-desktop-helpers.sh`, `test-launcher-*.mjs`, `test-profile-context-menu.mjs` | host | PASS |
| `welcome/tests/run-tests.mjs` (inclui Pular, Fechar, Retomar: cenários 03, 04, 05, 18, 19, 20) | host | 104 passaram, 0 falharam |
| `scripts/test-system-stability.sh` | WSL, cópia do workspace | ALL PASS (no host Windows falha por falta de Linux: esperado) |
| `qmllint` de `CompactRepresentation.qml` | Aurora fixada | exit 0; só os avisos antigos de `launcher` (id de `main.qml`), nenhum nas linhas alteradas |
| Medição do botão Iniciar (24/32/48 px e painéis 44/48 px) | Aurora fixada | §1 |

`scripts/verify-source.sh`: 14 pass, 2 warn (jq ausente; placeholder de namespace do `iso.toml`), 0 fail. Uma única
execução de `validate-desktop.sh` falhou em `node --check test-launcher-filter.mjs` com crash do próprio Node,
no momento em que o WSL era encerrado; quatro reexecuções seguintes passaram (ALL CHECKS PASSED), causa não
identificada e arquivo inalterado.

Não reexecutados: `test-auto-update-safety.sh` e `test-polkit-uupd.sh` (exigem systemd como PID 1 / rede e
cobrem política de update, área que este lote não tocou; passaram nos Gates 12.2/12.3). O CTest nativo do
Welcome (2/2 na H6) não foi refeito: o código do Welcome não mudou.

### 4.2 Unidades `masked-runtime`

A imagem mascara as 9 unidades de forma **persistente** (`build_files/close-os-updates.sh`: `systemctl
--root=/ mask`), gravando `/etc/systemd/system/<unidade> → /dev/null`. O disco da VM
(`disk_config/vm.local.toml`) ainda acrescenta `systemd.mask=uupd.timer systemd.mask=uupd.service
systemd.mask=uupd-manual.service` à linha de comando do kernel; o systemd cria então links em
`/run/systemd/generator.early/`, que têm precedência sobre `/etc` e fazem o `systemctl` informar
`masked-runtime` **somente para essas três**. Reproduzido com a imagem `localhost/enthroned-os:h6` em contêiner
descartável com systemd real (só leitura, nada gravado):

| Cenário | `uupd.*` | demais 6 unidades | `FragmentPath` do `uupd.timer` |
| --- | --- | --- | --- |
| Só a imagem | `masked` | `masked` | `/etc/systemd/system/uupd.timer` (→ `/dev/null`) |
| Imagem + `systemd.mask=` | `masked-runtime` | `masked` | `/run/systemd/generator.early/uupd.timer` |

**Persistência esperada.** A proteção real vem da imagem (`/etc`, versionada pelo bootc) e, numa instalação
sem a kernel arg, o estado é `masked`. A kernel arg é redundância apenas do disco de teste e não
persiste além do que está nos argumentos de boot. O preset `20-enthroned-os-updates.preset` também
desabilita os 4 timers. Observação lateral: `/etc/systemd/system/flatpak-add-fedora-repos.service` também é
máscara para `/dev/null` (origem fora deste lote; não é unidade de update).

### 4.3 Plasma Setup e teclado (P4)

Plasma Setup é o `plasma-setup 6.8.3` da Aurora; o Enthroned só sobrepõe os pacotes `finished` e `prepare`
(marca). A página de teclado (`org.kde.plasmasetup.keyboard`) é upstream e não foi alterada. Os módulos do
assistente são linkados em `/usr/libexec/plasma-setup`, então não carregam isolados; reproduzi o **mesmo padrão
estrutural** (SearchField com `forceActiveFocus` + dois `ScrollView{ListView keyNavigationEnabled,
activeFocusOnTab}` + botões de rodapé) com Qt 6.11.2/Kirigami reais da Aurora e teclas sintéticas (QtTest):

- Tab: SearchField → lista de layouts → lista de variantes → rodapé. **A lista está na cadeia de Tab**, ao
  contrário do relato da H6; a causa do "sem foco na lista" não está na estrutura do módulo (pode ser o
  indicador de foco no tema do Setup ou o contêiner do assistente: **não confirmado**).
- Setas movem o foco e o `currentIndex`, mas o layout só é aplicado em `onClicked`
  (`KeyboardUtil.layoutName = …; applyLayout()`): **navegar por teclado não aplica nada**, e Enter não
  seleciona (o Espaço não pôde ser confirmado no meu harness, controle inconclusivo).
- Hipótese para o Enter ir ao rodapé na H6: o foco saiu das listas porque nada o mantém lá.

**Decisão: sem fork.** Itens para um relato upstream (KDE `plasma-setup`): aplicar o layout/variante também
em `Keys.onReturnPressed/onEnterPressed` do delegate (ou ao mudar `currentIndex` por teclado) e garantir um
indicador de foco visível nas listas. Contorno já documentado: `localectl set-x11-keymap br`.
Teste de confirmação para a VM controlada: §5, item 6.

## 5. Roteiro controlado para a VM (NÃO executado; exige autorização para tocar a VM H6)

Use uma cópia/snapshot da VM ou a H7 futura; anotar no relatório da sessão.

1. **Wallpaper ≠ Vigília**: Configurações → Papel de parede → Soberania ou Ascensão no Classic; `enthroned-profile
   apply modern`, depois `apply classic`; o escolhido deve voltar em cada monitor, sem containment duplicado.
   Repetir com `wall1`/`wall3` novos só na build seguinte (a H6 tem os antigos). Registrar slideshow/cor sólida
   (limitação conhecida).
2. **Classic ↔ Modern**: trocar nos dois sentidos, fazer logout/login e reiniciar; perfil e painel persistem.
3. **Logout e reboot**: `systemctl reboot` e `loginctl terminate-user`; `graphical.target` sem unidades falhas.
4. **Welcome**: com estado inicial limpo (`~/.local/state/enthroned-os/welcome-state.json` ausente):
   - *Pular*: botão "Pular assistente" → `phase=dismissed`, janela fecha; no próximo login não abre sozinho.
   - *Fechar* no meio (página 2, no X da janela) → `interrupted`, página preservada.
   - *Retomar*: novo login abre na mesma página; `enthroned-welcome --reopen` abre sempre.
5. **Unidades `masked-runtime`**: `cat /proc/cmdline | tr ' ' '\n' | grep mask`; `systemctl is-enabled uupd.timer
   uupd.service uupd-manual.service`; `readlink /etc/systemd/system/uupd.timer`; `ls -l
   /run/systemd/generator.early`. Esperado: `masked-runtime` só com a kernel arg e `/etc` → `/dev/null` sempre.
   Em disco sem a kernel arg, `masked` nas 9.
6. **Plasma Setup (teclado)**: primeiro boot sem `localectl`: Tab até a lista, setas, Enter/Espaço; registrar
   onde o foco cai e se o layout é aplicado.
7. **Visual**: botão Iniciar (E e trono) em 100 %, 150 % e 200 %, hover e menu aberto; relógio Modern só com hora
   após `enthroned-profile apply modern`; relógio Classic com data.

## 6. Dolphin — cor por pasta (proposta, não implementada)

**Achado.** O Dolphin 26.08.3 da Aurora (pacote `dolphin-libs`) já inclui o plugin nativo
`kfileitemaction/setfoldericonitemaction.so`: ação **"Definir ícone da pasta"** no menu de contexto de
pastas, com cores nomeadas e opção "Padrão". O Breeze 6.32 fornece `folder-<cor>` (black, blue, brown, cyan,
green, grey, magenta, orange, red, violet, yellow; 88 variantes de pasta também no Breeze Dark). O plugin
grava `Icon=folder-<cor>` no `.directory` da pasta (via `KDesktopFile`); "Padrão" remove a chave. Nada no
Enthroned (`dolphinrc`, `enthroned-files-setup`, plugin de menu de contexto) oculta essa ação. Não testei a
ação em execução (precisa de Plasma/Dolphin reais).

| Critério | Avaliação |
| --- | --- |
| Compatibilidade | Nativa, sem código nosso. Só pastas locais/graváveis; Dolphin e apps KDE respeitam; outros gerenciadores ignoram. |
| Persistência | Por pasta, no `.directory` (acompanha a pasta ao mover/copiar; sobrevive a updates/bootc, pois vive em `/var/home`). `GlobalViewProps=true` não interfere (só afeta o modo de exibição). |
| Impacto visual | O tema Enthroned só sobrescreve `folder`, `folder-open`, 5 pastas especiais (Documentos, Downloads, Imagens, Música, Vídeos), `user-home` e `user-desktop`. As cores caem no **Breeze plano**, estilo diferente do âmbar Enthroned com glifo branco; "Padrão" volta ao Enthroned. Cada pasta colorida cria um `.directory` visível com "mostrar ocultos". |

**Proposta (pequena, por fases).** Fase 0: nada a codar; homologar a ação na VM e citar no Welcome/documentação.
Fase 1 (opcional): gerar `folder-<cor>.svg` no estilo Enthroned (derivado de `folder.svg`) em `Enthroned/` e
`EnthronedDark/` com `scripts/gen-brand-assets.py` ou script novo; 11 arquivos por tema, + checagem no
`validate-desktop.sh`. Risco: baixo (arquivos de tema), mas o glifo e a paleta precisam de decisão de marca (violeta
vs. cores livres). Não recomendado: interface própria de cor (duplica o que o KDE oferece e exige manter
sincronia com o `.directory`). **Decisão pendente do proprietário:** Fase 1 sim/não e paleta.

## 7. Arquivos alterados

| Arquivo | Mudança |
| --- | --- |
| `system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/CompactRepresentation.qml` | margem e `roundToIconSize` do ícone |
| `system_files/usr/share/plasma/look-and-feel/org.enthroned.modern/contents/layouts/org.kde.plasma.desktop-layout.js` | `showDate` no grupo `Appearance` |
| `scripts/validate-desktop.sh` | novo check do relógio Modern |
| `system_files/usr/share/wallpapers/EnthronedSoberania/`, `…/EnthronedVigilia/` | imagem e miniatura (de `assets/wall1.png`, `wall3.png`) |
| `docs/operations/START-MENU.md`, `docs/operations/NEXT-HOMOLOGATION.md` | notas do lote |
| `docs/evidence/lote14/` | harness QML, imagem e medições |
| `docs/validation/LOTE-14-POST-H6-FIXES.md` | este relatório |
| `.backup-lote14/` | pacotes de wallpaper anteriores (não rastreado) |

Não modificados: `assets/`, H6, H5 e seus `output/`, `.backup-gate13-1/`, `.backup-lote13/`, bootc, polkit,
systemd e políticas de update, `Containerfile`, `Justfile`.

## 8. GO / NO-GO

- **GO** para incluir as três correções e os wallpapers novos na próxima build: código fonte pronto, checagens
  estáticas e testes aplicáveis passam, medição de ícone feita no Qt/Kirigami reais da Aurora.
- **NO-GO** para declarar P1 e P3 "homologados" ou os wallpapers entregues: dependem de Plasma real (§5, itens 1, 7)
  numa próxima VM. Nada disso foi verificado em Plasma/KWin (não roda headless na Aurora do WSL).
- Itens que dependem de decisão ou da VM: P4 (relato upstream e teste), Dolphin Fase 1, preservação de ajustes
  pessoais do relógio ao trocar de perfil.
