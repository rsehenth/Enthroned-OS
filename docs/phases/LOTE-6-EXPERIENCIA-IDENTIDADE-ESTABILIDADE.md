# Lote 6 — Experiência, identidade e estabilidade

Estado: **SOURCE READY / STATIC VERIFIED**. Nada foi compilado, instalado,
executado em VM, commitado ou publicado. Verificações executadas neste
ambiente (host Windows, sem Qt/KDE): `validate-desktop.sh`,
`validate-settings.sh`, `validate-welcome.sh`, `verify-source.sh`,
`node settings/tests/run-tests.mjs` (370/370) e
`node welcome/tests/run-tests.mjs` (85/85). Toda validação de comportamento
real fica para a próxima homologação (roteiro na seção 0 de
`docs/operations/NEXT-HOMOLOGATION.md`).

Os problemas da homologação 2 foram tratados item a item. Para cada um,
o estado abaixo usa quatro rótulos: **Corrigido no código**, **Parcial**,
**Bloqueado** (dependência/segurança) ou **Pendente de homologação**.

## 1. Identidade da configuração inicial — Corrigido no código (visual pendente)

- Causa comprovada: a saudação "Welcome to Plasma Desktop" e o botão
  "Begin Setup" são textos-fonte **compilados no binário plasma-setup**
  (`src/qml/LandingComponent.qml`, `ki18nd("org.kde.plasmasetup", ...)`). A via
  suportada de personalização é o catálogo de tradução do domínio
  `org.kde.plasmasetup` — não há pacote/override para a landing (confirmado no
  `CUSTOM_MODULES.md` e no `CMakeLists.txt` upstream; a landing vai em qrc).
- Implementado: `/etc/xdg/plasma-localerc` com `LANGUAGE=pt_BR` e
  `LANG=pt_BR.UTF-8` (mecanismo padrão lido pelo `startplasma`, respeita a
  escolha do usuário) + catálogo `build_files/l10n/pt_BR/org.kde.plasmasetup.po`
  compilado no build e **mesclado** ao catálogo pt_BR upstream (quando existir),
  cobrindo a saudação ("Bem-vindo ao Enthroned OS", inclusive as variantes com
  e sem marcação), "Começar configuração" e os textos de conclusão da página
  final (override `org.kde.plasmasetup.finished`).
- `glibc-langpack-pt_BR` instalado para o locale funcionar de fato.
- Rodapé "Powered by Enthroned OS" já vinha do os-release (sem alteração);
  fundo da landing: o build substitui as imagens usadas pelo plasma-setup
  (`/usr/share/wallpapers/Next/...`) pelos wallpapers Enthroned/Nocturne
  (5120×2880 e 1440×2960). Sem mascotes/Aurora.
- **Bloqueado**: saudação em sessões **en_US**. O Ki18n trata `en_US` como
  idioma-fonte e nunca consulta catálogos `en_US` (comprovado no
  `klocalizedstring.cpp`, `translateRaw()` retorna o msgid ao atingir
  `en_US`). Um override em inglês exigiria patch do binário upstream — fora do
  escopo e contrário à diretriz "não modificar componentes internos". Registrado
  como limitação; o restante do wizard segue em inglês nas sessões en_US.

## 2. Botões de janela — Corrigido no código (visual pendente)

`kwinrc` já definiava `ButtonsOnRight=IAX` (min/max/fechar à direita) e os
perfis reaplicam isso; reforço: `breezerc ButtonSize=ButtonLarge` para os
ícones (traço/quadrado/X) ficarem claramente visíveis. Decoração nativa
Breeze/KDecoration3 — sem substituir o KWin e sem controles falsos. Ícones e
esquemas validados (`[WM]` = `[Colors:Header]`, checagem estática).

## 3. Área de trabalho — Parcial

- Arrastar/selecionar/abrir: os layouts Classic e Modern agora escrevem a
  configuração nativa do Folder View do containment: `locked=false`,
  `sortMode=0` (não ordenado = Positioner ativo = posições livres) e
  `alignment=0`. Grade/alinhamento e outros ajustes continuam nativos
  ("Configurar área de trabalho"). Duplo clique já era o padrão
  (`SingleClick=false`).
- **Pendente de homologação**: se o arrastar ainda exigir modo de edição, a
  suspeita principal migra para o gerenciador de leiaute do Plasma 6.6
  (`ContainmentLayoutManager.AppletsLayout`, `ItemGeometries-<WxH>`) —
  regressão upstream, não configuração do Enthroned. O roteiro pede captura de
  journal + versão do plasma-desktop antes de qualquer mudança.
- Atalhos pós-instalação: novo `/usr/bin/enthroned-desktop-shortcut`
  (sem daemon, roda uma vez por atalho): resolve o launcher real nos diretórios
  XDG (incl. exports de Flatpak), recusa `NoDisplay`/`Hidden` e entradas sem
  `Name`, grava na pasta Desktop real (`xdg-user-dir DESKTOP`), **nunca
  sobrescreve** arquivo existente e marca como confiável (`gio metadata::trusted`,
  best-effort) por vir de aplicativo instalado.
  - Fluxos integrados hoje: ArtCraft pelo Welcome (automático, respeita a
    preferência `CreateDesktopShortcuts`, padrão **true**, com novo cartão em
    Settings > Aplicativos; preferência em
    `~/.config/enthroned-os/preferences.conf`, padrão de sistema em
    `/etc/xdg/enthroned-os/preferences.conf`).
  - Ação manual "Adicionar à área de trabalho" no menu de contexto do Menu
    Iniciar (qualquer app real) — cobre apps instalados fora dos fluxos
    integrados (Discover não expõe sinal confiável de "instalação concluída";
    nada monitora instalações).
  - Atualizações de apps já instalados não criam nem duplicam atalhos (o
    auxiliar sai se o arquivo existe).

## 4. Ícones de pastas — Corrigido no código (visual pendente)

Novo tema de ícones **Enthroned** (`/usr/share/icons/Enthroned`) herdando
Breeze, com a família de pastas própria: pasta âmbar de dois tons (identidade
da marca), pasta aberta, e glifos brancos de alto contraste para
`folder-documents`, `folder-download`, `folder-pictures`, `folder-music`,
`folder-videos`, `user-desktop` e `user-home`. Variante **EnthronedDark**
(herda Breeze Dark) com os mesmos desenhos. Perfis: Classic → `Enthroned`,
Modern → `EnthronedDark` (`kdeglobals` + `defaults` dos dois look-and-feel).
Nada de material proprietário do Windows; os demais ícones continuam Breeze.
Correção associada: o atalho "Downloads" do Dolphin usava o nome de ícone
inexistente `folder-downloads` (`enthroned-files-setup`).

## 5. Dolphin como "Arquivos" — Corrigido no código (visual pendente)

O build renomeia **apenas o nome de exibição** da entrada
`org.kde.dolphin.desktop` para `Name=Files` / `Name[pt_BR]=Arquivos`
(binários, storage id e associações MIME intocados). A entrada "Arquivos" do
Menu Iniciar lança o Dolphin sem argumentos → abre a pasta pessoal; o atalho
específico "Downloads" continua abrindo Downloads. Não foi encontrado nenhum
atalho genérico apontando para Downloads no código próprio; a confusão provável
era a proximidade do atalho "Downloads" com a coluna "Ferramentas" — nomes
agora inequívocos ("Arquivos").

## 6. Arquivos Flatpak — Corrigido no código (visual pendente)

O Discover (com backend Flatpak, garantido no build) já se registra para
`application/vnd.flatpak`, `.ref` e `.repo` (comprovado no CMake upstream). O
que faltava era o **padrão**: `/etc/xdg/mimeapps.list` agora define os três
como padrão do sistema (sem seção de associações adicionais, conforme a
política F4). Abrir um arquivo baixado abre o Discover, que mantém sua própria
confirmação/origem/permissões; nada é instalado automaticamente e a associação
continua trocável pelo usuário.

## 7. ArtCraft no Welcome — Corrigido no código (visual pendente)

O bloqueio era o portão de fase `ENTHRONED_WELCOME_ALLOW_INSTALL`. Todos os
requisitos do lote foram verificados e atendidos: origem oficial confirmada
(GitHub `storytold/craft-launcher`, releases assinados + `SHA256SUMS.txt`,
pacote `.flatpak` por arquitetura), formato suportado, instalação
`flatpak install --user` (sem root), consentimento duplo (checkbox desmarcado +
diálogo), progresso e falhas reais. Implementado neste lote:
- novo **cancelamento** (`ArtcraftInstaller.cancel()`: aborta download ou
  termina o flatpak; estado "cancelled" com mensagem clara e sistema intacto)
  e botão "Cancelar" na página;
- portão por **política** `/usr/share/enthroned-os/install-policy.json`
  (`allowArtcraftInstall: true`, registrando as verificações feitas; a variável
  de ambiente continua como override de teste; basta desligar no arquivo para
  rebloquear);
- após instalar com sucesso, cria o atalho na área de trabalho conforme a
  preferência (item 3). ArtCraft continua opcional e desmarcado por padrão.

## 8. Configurações em dois modos — Corrigido no código (visual pendente)

- **Modo Simples (padrão)**: Início, Personalização, Tela e resolução, Som,
  Notificações, Atualizações do sistema.
- Tela/Som/Notificações são páginas novas de foco (`FocusPage.qml`, um
  componente único para as três — nenhuma página duplicada) que abrem os
  módulos nativos do KDE (`kcm_kscreen`, `kcm_pulseaudio`, `kcm_notifications`)
  com detecção honesta de disponibilidade.
- Controle "Mostrar configurações avançadas" na base da navegação (e botão no
  modo colapsado) revela todas as áreas; a escolha persiste por usuário
  (`preferencemanager.{h,cpp}` novo, arquivo
  `enthroned-os/preferences.conf`); voltar ao Modo Simples com uma área
  avançada aberta leva ao Início.
- Busca: sempre cobre tudo; resultados de áreas avançadas no Modo Simples
  ganham o selo "Avançado" (o sinalizador vem da página de destino, fonte
  única). Nenhum módulo KDE foi alterado.

## 9. Update Center visível — Corrigido no código (visual pendente)

"Atualizações do sistema" agora aparece: no Modo Simples (entrada própria), na
página Início (cartão de estado com "Verificar" + novo atalho "Atualizações do
sistema" que substitui o de "Aplicativos padrão", que segue na busca/página) e
na busca (palavras-chave pt/en ampliadas). A página em si já mostrava estado,
última verificação, versão, origem da imagem, progresso real e motivo de
bloqueio; **nada** foi liberado: portão de mutação fechado, origem confiável do
Lote 4 preservada, `expected_image_references` segue declarado (vazio) e
honesto, sem progresso fictício.

## 10. Aurora Preferences — Parcial

- Causa do nome na interface: a renomeação anterior só alterava o `Name` do
  `.desktop`; a entrada continua listada como "Aurora Preferences" onde o
  System Settings não usa esse arquivo (a varredura de módulos do Plasma 6 usa
  os metadados do KCM). Sem a imagem em execução não dá para confirmar qual
  caminho o System Settings 6.x usa para esse módulo.
- Implementado: o build marca `kcm_ublue.desktop` com `NoDisplay=true` +
  `Hidden=true` (créditos/proveniência preservados; nenhum pacote removido,
  nenhum serviço essencial tocado, drivers intocados) e o Enthroned Settings
  (Área avançada > Aplicativos) oferece o cartão "Ajustes da imagem do sistema
  (avançado)" que abre o módulo via `kcmshell6 kcm_ublue` **só se ele existir**,
  com aviso explícito. Controles de atualização não foram duplicados — o cartão
  apenas abre o módulo do fornecedor.
- Pendente: confirmar na homologação que a entrada desapareceu da barra lateral
  do System Settings; se o Plasma a listar pelos metadados do .so, a solução
  completa exigirá decisão de empacotamento (lote seguinte).

## 11. Temas Enthroned — Corrigido no código (visual pendente)

A experiência principal continua oferecendo apenas Classic (claro) e Modern
(escuro); os temas herdados do Aurora seguem removidos no build (look-and-feel,
desktop files, wallpapers, splash). Com este lote os dois perfis também
definem o tema de ícones Enthroned/EnthronedDark coerente com cada esquema de
cores e wallpaper, sem duplicar configuração (mesmo mecanismo
`plasma-apply-lookandfeel`). `verify-source` e `validate-desktop` continuam
passando (sem referência ativa ao Aurora; o nome de caminho upstream
`aurora-banner.svg` contém arte Enthroned e foi mantido por ser caminho
consumido pela base).

## 12. Menu Iniciar — Corrigido no código (visual pendente)

- **Brave duplicado**: causa não reproduzível fora da VM (instalação dupla, dois
  `.desktop` ou entrada repetida favoritos×lista — as hipóteses estão no
  roteiro). Correção estrutural implementada: proxy de deduplicação por
  `favoriteId` sobre o modelo de aplicativos/categorias do launcher (primeira
  ocorrência vence, reconstruído a cada `refreshed`), com mapeamento
  proxy→modelo-fonte no `AppActions` para os `trigger()` continuarem oficiais.
- **Categoria Sistema estreita**: popup padrão ampliado de 42 para 46 unidades
  de grade (continua limitado à área útil), e nomes truncados agora têm tooltip
  no delegado da lista.
- **Boas-vindas fixado**: `kicker-extra-favoritesrc` inclui
  `org.enthroned.welcome.desktop` primeiro. Mecânica confirmada no código do
  Plasma (commit 9ef4cbc): o `Prepend` semeia os favoritos **uma única vez**
  (KAStats); depois que o usuário desafixa, nada é recriado, e listas
  personalizadas nunca são sobrescritas.

## 13. Roadmap — Corrigido no código (visual pendente)

O card "Gerenciador de Dispositivos Inteligente" tinha caixas com altura
derivada de conteúdo **ancorado em `anchors.fill`** (dependência circular com a
altura da linha da grade → espaço em branco). Corrigido nos dois pontos
(exemplo do headphone e pílulas do topo): ancoragem superior/lateral apenas, a
altura passa a seguir o conteúdo. O exemplo do headphone com áudio espacial e
os avisos de "Planejado"/compatibilidade real foram preservados, como o Motor de
Compatibilidade como visão futura.

## 14. Internacionalização — Parcial

- Infraestrutura completa e funcionando por design: idioma padrão da sessão
  pt_BR via `plasma-localerc` (mecanismo oficial, respeita a escolha do
  usuário), catálogos GNU gettext pt_BR compilados e instalados pelo
  `build.sh` para os domínios próprios, com ferramenta de merge para o
  domínio do plasma-setup (validada por teste de round-trip .po/.mo).
- **Enthroned Launcher**: 100% migrado — msgids em inglês + catálogo pt_BR
  (`build_files/l10n/pt_BR/org.enthroned.launcher.po`); sessões en_US e pt_BR
  corretas. O atalho "Gerenciador de arquivos" virou "Files"/"Arquivos".
- **Plasma Setup**: strings de identidade cobertas por catálogo (item 1).
- **Enthroned Settings (493 strings) e Welcome (160 strings)**: migradas para
  msgids apenas as strings NOVAS do Lote 6. A migração completa dos textos
  existentes foi **registrada como pendente de execução** (sem risco para a
  sessão pt_BR padrão, que já exibe os textos atuais; uma sessão en_US mostraria
  esses aplicativos em português até a migração). O swap mecânico de ~650
  strings sem build Qt disponível neste ambiente tinha risco alto de regressão
  de QML pouco antes da homologação — prioridade dada à estabilidade, conforme
  a ordem final do lote.
- `.desktop` próprios: nomes com `Name[pt_BR]` (Welcome, Settings, OOBE);
  Dolphin renomeado com traduções (item 5).
- Guia de redação aplicado nos textos novos (frases diretas, sem jargão, erros
  com ação sugerida — ex.: mensagens do instalador e do FocusPage).

## 15. Performance e erros de boot — Investigado (somente leitura)

- Evidência disponível analisada (homologação 2): `vm-boot-01.png` (console de
  boot) e `VBox.log` da VM.
- **Nenhum erro de serviço** no console capturado — todas as linhas `[OK]`
  (systemd-sysupdate, bootc-update-ca-trust, bootc-update-crypto-polic, binfmt,
  tmpfiles, ldconfig, audit, NFS/RPC...). As "mensagens rápidas" relatadas são
  provavelmente essa saída de console normal (a VM não exibe splash do Plymouth
  no console serial/VBox).
- **Gargalo medido**: `Job ldconfig.service/start running (11s / no limit)` —
  ~11 s em um serviço de reconstrução de cache do linker em root imutável.
  Candidato nº 1 para `systemd-analyze blame` na próxima homologação; nenhuma
  unidade foi mascarada sem essa confirmação (não é serviço de segurança/rede,
  mas mexer no boot sem medição violaria o lote).
- **Linha de base**: VM power-on → VBoxClient (sessão gráfica) ≈ 50 s
  (timestamps do `VBox.log`), com 3D desligado (VMSVGA/llvmpipe) — a fluidez
  continua confundida com renderização por software; roteiro A/B preservado.
- Base identificada no log: **Fedora 45** (kernel `7.2.11-300.fc45`).
- A coleta para a próxima homologação já existe (`enthroned-diagnostics
  collect`: `systemd-analyze time/blame/critical-chain`, `systemctl --failed`,
  `journalctl -b`); o roteiro do Lote 6 manda coletar logo após o login e
  conferir `ldconfig`. Nada foi "silenciado" no boot.

## 16. Preservações verificadas

Bootc/base Aurora (`verify-source` 15 PASS/1 WARN conhecido), Welcome, perfis
Classic/Modern, Update Center e portão de segurança (todos os checks de
segurança dos validadores passaram), ferramentas de diagnóstico, integração
Dolphin/KDE, Menu Iniciar, usuários, correções dos lotes anteriores (testes de
lógica 370+85 passando), grafo e `.gitignore` intocados. Nenhum aplicativo
duplicado, nenhum mecanismo KDE substituído.

## 17. Verificações executadas neste lote

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-desktop.sh` | ALL CHECKS PASSED |
| `bash scripts/validate-settings.sh` | ALL CHECKS PASSED (testes de lógica rodados à parte) |
| `bash scripts/validate-welcome.sh` | ALL CHECKS PASSED (idem) |
| `node settings/tests/run-tests.mjs` | PASS 370 / FAIL 0 |
| `node welcome/tests/run-tests.mjs` | 85 passed, 0 failed |
| `bash scripts/verify-source.sh` | 15 pass, 1 warn (placeholder ISO, esperado) |
| Round-trip .po/.mo (ferramenta do build) | OK (teste dedicado em `output/lote6/`) |
| ShellCheck | Não executado neste host (sem shellcheck no Windows); `build.sh` e `enthroned-desktop-shortcut` seguem o estilo dos existentes — rodar no WSL antes da build |

Os checks atualizados junto com o código: contagem de áreas de navegação
(12 → 15 com Tela/Som/Notificações), `FocusPage` na lista de páginas, semântica
do mimeapps mantida. **Nada foi declarado aprovado por teste de texto**: os
itens marcados "visual pendente" dependem da homologação na VM.

## 18. Arquivos alterados/criados (resumo)

- **system_files**: `etc/xdg/{plasma-localerc,kdeglobals,kicker-extra-favoritesrc,mimeapps.list,breezerc}`;
  `etc/xdg/enthroned-os/preferences.conf` (novo); `usr/bin/enthroned-desktop-shortcut` (novo);
  `usr/share/icons/Enthroned{,Dark}/` (novos, 10 arquivos); `usr/share/enthroned-os/install-policy.json` (novo);
  `usr/libexec/enthroned-files-setup` (ícone `folder-download`); layouts e `defaults` dos perfis.
- **build_files**: `build.sh` (catálogos, merge plasma-setup, wallpapers Next, Dolphin=Arquivos,
  kcm_ublue oculto, langpack/gettext, chmods) e `l10n/pt_BR/*.po` (2 novos).
- **settings**: `src/preferencemanager.{h,cpp}` e `src/main.cpp` (novo contexto `preferences`),
  `qml/Main.qml` (Modo Simples/Avançado, toggle, selo), `qml/pages/FocusPage.qml` (novo),
  `qml/SearchIndex.qml`, `qml/pages/{HomePage,AppsPage}.qml`, `CMakeLists.txt`,
  `tests/run-tests.mjs` (15 áreas).
- **welcome**: `src/artcraftinstaller.{h,cpp}` (política, cancelamento, atalho pós-instalação),
  `qml/pages/{ArtcraftPage,RoadmapPage}.qml`.
- **docs**: `operations/NEXT-HOMOLOGATION.md` (seção 0 do Lote 6) e este arquivo.

## 19. Pendências explícitas para a próxima build

1. Homologação dos itens "visual pendente" (roteiro na seção 0 de
   `NEXT-HOMOLOGATION.md`), com coleta `enthroned-diagnostics collect`.
2. Migração completa dos msgids de Settings e Welcome para catálogos (§14).
3. Confirmar a ocultação do kcm_ublue no System Settings 6.x (§10).
4. `ldconfig.service` no `systemd-analyze blame` (§15) antes de qualquer
   ajuste de boot.
5. ShellCheck no WSL dos scripts alterados antes da build.
6. Confirmar o cenário do Brave duplicado na VM (se persistir após o dedupe,
   é instalação dupla — o roteiro cobre como separar).
