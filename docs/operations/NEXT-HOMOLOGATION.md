# Próxima homologação manual (build única, VM)

Estado do código: **SOURCE READY / STATIC VERIFIED**. Nada deste lote foi
compilado nem executado (ver `docs/validation/STABILITY-BATCH-1.md` e
`docs/phases/LOTE-6-EXPERIENCIA-IDENTIDADE-ESTABILIDADE.md`). Esta página é o
roteiro para testar uma build inteira e registrar *todos* os problemas antes de
abrir outro lote de correções. Não execute antes de o fechamento do lote ser
aprovado.

## 0. Cenários novos do Lote 6 (executar antes do roteiro geral)

1. **Plasma Setup (primeiro boot)**: a saudação deve mostrar
   "Bem-vindo ao **Enthroned OS**" (catálogo pt_BR `org.kde.plasmasetup`;
   o texto-fonte em inglês permanece "Welcome to Plasma Desktop" em sessões
   en_US — limitação registrada). O botão deve ser "Começar configuração", o
   rodapé "Powered by Enthroned OS" e o fundo deve ser o wallpaper Enthroned
   (não a arte Plasma "Next"). As etapas de conta/hostname/idioma/fuso devem
   continuar funcionando sem alteração.
2. **Botões de janela**: em Dolphin/Settings/Welcome, minimizar (traço),
   maximizar (quadrado) e fechar (X) visíveis, à direita, maiores
   (`ButtonSize=ButtonLarge`).
3. **Área de trabalho**: selecionar com clique esquerdo, arrastar ícones para
   posições livres (sem modo de edição), duplo clique abre, posições
   persistem após logout/login; grade/alinhamento nativo em "Configurar área
   de trabalho". Se o arrastar ainda falhar, capturar `journalctl --user -b |
   grep -iE 'plasma|folder'` e a versão do plasma-desktop — é candidato a
   regressão upstream do Plasma 6.6 (AppletsLayout), não configuração nossa.
4. **Atalhos**: botão direito em um app do Menu Iniciar → "Adicionar à área
   de trabalho" cria o atalho na pasta Desktop real (nunca sobrescreve);
   instalar o ArtCraft pelo Welcome cria o atalho automaticamente
   (preferência em Settings > Aplicativos, desativável); atualização do Brave
   (provisionamento) NÃO cria atalho.
5. **Ícones de pastas**: Dolphin e área de trabalho com pastas âmbar Enthroned
   (tema `Enthroned` no Classic, `EnthronedDark` no Modern) e glifos especiais
   para Documentos, Downloads, Imagens, Música, Vídeos; demais ícones Breeze.
6. **Arquivos (Dolphin)**: entrada do Menu Iniciar como "Arquivos"; abri-la
   leva à pasta pessoal (sem abrir Downloads por engano; o atalho Downloads
   abre Downloads).
7. **Arquivos Flatpak**: abrir um `.flatpakref`/`.flatpak`/`.flatpakrepo`
   baixado deve abrir o KDE Discover diretamente (sem lista ambígua) e pedir
   confirmação lá.
8. **ArtCraft**: o Welcome oferece instalar (checkbox desmarcado, confirmação,
   barra de progresso e botão "Cancelar" durante o download/instalação).
   Cancelar deixa o sistema intacto.
9. **Configurações em dois modos**: por padrão apenas Início, Personalização,
   Tela e resolução, Som, Notificações e Atualizações do sistema; o controle
   "Mostrar configurações avançadas" (na base da navegação) revela todas as
   áreas; voltar para Modo Simples mantém o estado por usuário. A busca
   encontra áreas avançadas no Modo Simples com o selo "Avançado".
10. **Menu Iniciar**: favoritos iniciais = Boas-vindas ao Enthroned OS,
    navegador, Configurações, Arquivos, Terminal, Loja; desafixar Boas-vindas
    persiste (não volta); nenhuma entrada duplicada de Brave (dedupe por id);
    categoria Sistema com lista legível (popup mais largo + tooltip quando
    truncado), popup dentro da área útil em 1280×720.
11. **Roadmap**: card "Gerenciador de Dispositivos Inteligente" proporcional
    (sem espaço em branco), exemplo do headphone com áudio espacial e avisos
    de "Planejado" preservados.
12. **Idioma**: sessão padrão pt_BR (plasma-localerc); Launcher em português
    (catálogo); Settings/Welcome mantêm os textos atuais (migração para
    catálogos pendente, ver relatório do Lote 6). Mudança de idioma no System
    Settings respeitada na próxima sessão.
13. **Boot (§15)**: `enthroned-diagnostics collect` logo após o login; conferir
    em `boot.txt` o tempo de `ldconfig.service` (medimos ~11 s na captura da
    homologação 2, `vm-boot-01.png`), `systemd-analyze time` e unidades
    falhas. Nada foi alterado no boot sem essa evidência.

## 1. Preparação da VM (comparativo, não alterar sem decidir)

A VM anterior (4 vCPUs, 8 GiB, VMSVGA, 128 MB de vídeo, **3D desligado**) obriga
o KWin/Plasma a renderizar por software (llvmpipe) — lentidão em blur, sombras
e animações **não prova** defeito do Enthroned OS. Para separar as causas, mude
uma variável por rodada e repita o mesmo roteiro:

| Rodada | Configuração | Pergunta que responde |
| --- | --- | --- |
| A | igual à anterior (3D off) | linha de base com os logs novos |
| B | mesma VM com aceleração 3D ligada (decisão do usuário, no host) | quanto da lentidão é renderização por software? |
| C | A ou B + `AnimationDurationFactor=0` (ver §4) | peso das animações |
| D | A ou B + blur desligado (ver §4) | peso do blur do KWin |

Registre, em cada rodada, a linha `Compositing Type`/`OpenGL renderer` de
`graphics.txt` (se aparecer `llvmpipe`/software, a rodada é por software).
Não anote ganhos percentuais sem medir nas duas rodadas.

## 2. Coleta de diagnóstico (local, manual, somente leitura)

`enthroned-diagnostics` vem na imagem (`/usr/bin`). Não instala agentes, não usa
rede, não precisa de root, não muda configuração. Saída em
`~/.local/state/enthroned-os/diagnostics/<data-hora>/` (arquivos limitados a 300
linhas, com home, usuário, e-mails e valores de senha/token mascarados).
**Revise antes de compartilhar.**

```bash
enthroned-diagnostics collect          # sistema, boot, processos, gráficos, erros do journal
enthroned-diagnostics run settings     # abre o Settings com log + tempos + CPU/RSS (5 s e 20 s)
enthroned-diagnostics run welcome      # idem para o Welcome (--reopen)
```

- **Erros de QML** (Settings/Welcome): `run-*.log` guarda o stderr com
  `[+ms]`; o primeiro `QSG:` marca aproximadamente a janela pronta (tempo de
  abertura). Plasma/launcher: `journal.txt` filtra `plasmashell|kwin|qml|enthroned`
  com `error|TypeError|ReferenceError|Unable to assign…`.
- **Falhas de plasmashell/KWin**: `journal.txt` (+ `coredumpctl list`).
- **Erro após o assistente/launcher**: não deixe a tela fechar sozinha. Rode
  `collect` **imediatamente depois** (o journal da sessão guarda a mensagem) e
  anote o assistente exato: Plasma Setup (primeiro boot, página "Finalizar"),
  Enthroned Welcome (Concluir/Pular) ou o menu Enthroned Launcher.
- **CPU/RAM**: `processes.txt` (top CPU/RSS, processos duplicados) e
  `free -m` em `system.txt`.
- **Boot**: `boot.txt` (`systemd-analyze`, `blame`, `critical-chain`,
  `--failed`, timers Enthroned).
- **Renderização**: `graphics.txt` (KWin supportInformation filtrado, chaves
  do `kwinrc`, `eglinfo`/`glxinfo` se existirem).

## 3. Roteiro (marque e anote o que falhar; não corrija durante o teste)

1. **Boot**: tempo até o login (`systemd-analyze`), unidades falhas, splash.
2. **Login**: tempo até painel utilizável; só 1 assistente de boas-vindas
   aparece (Welcome); `processes.txt` sem `plasma-welcome` residente.
3. **Launcher** (detalhes do Lote 3 em `START-MENU.md`):
   1. Abrir pelo clique e por Meta; o campo de busca deve estar com foco; fechar
      pelo botão e por Esc (campo vazio). Conferir que existe um único botão
      Iniciar no painel.
   2. Resoluções 1280×720 e 1920×1080, escalas 100/150/200 % e fonte grande: o
      popup cabe na área útil, rola e não cobre/escapa do painel.
   3. Fixados: grade visível; botão direito → Desafixar / Mover (início, antes,
      depois); Esc; fechar e reabrir (a ordem persiste); fazer logout/login
      (persiste); sem favoritos o estado vazio aparece.
   4. Todos os aplicativos e cada categoria: lista sem duplicatas, ícones e
      nomes traduzidos, rolagem; botão direito → Fixar no menu Iniciar → conferir
      em Fixados.
   5. Busca: aplicativo por nome e por descrição, arquivo (se Baloo ativo),
      configuração; ↑/↓ + Enter; Enter direto abre o primeiro; "Nenhum
      resultado"; Esc limpa e depois fecha; digitar com o foco na lista.
   6. Locais: Pasta pessoal, Documentos, Downloads, Imagens abrem no Dolphin;
      Gerenciador de arquivos, Configurações, Loja, Terminal só aparecem se
      instalados; popup estreito mostra só ícones com dica.
   7. Rodapé: Bloquear; menu Sessão e energia (Suspender se disponível,
      Reiniciar, Desligar, Encerrar sessão) com as confirmações do Plasma —
      **em VM descartável**; conta abre Contas de usuário.
   8. Navegação por teclado completa (Tab, setas, Enter, tecla Menu) e foco
      visível; leitor de tela (Orca) lê nomes e papéis.
   9. Classic e Modern: aparência coerente nos dois esquemas de cores; abrir
      logo após o login e após trocar de perfil.
   10. `journalctl --user -b | grep -i qml`: nenhum `FullRepresentation
       unavailable`, `QQmlInstantiator`, `ReferenceError: launcher`, nem aviso
       de módulo `Qt.labs.platform` (se houver, só os atalhos de pastas somem).
   11. Medir (só então afirmar ganho): tempo da 1ª abertura e rolagem de
       "Todos os aplicativos" com `top`/`QSG_RENDER_TIMING=1`.
4. **Perfil Classic**: painel, relógio com data, cores claras.
5. **Perfil Modern**: aplicar pelo Settings (confirmar), painel flutuante
   centralizado, cores escuras; voltar para Classic.
6. **Settings (Lote 4, configurações gerais)**: medir a abertura e conferir que
   nenhum aviso QML novo aparece (`run-*.log`). Depois, por área:
   1. **Navegação**: as 12 áreas (Início, Sistema, Bluetooth e dispositivos, Rede e
      Internet, Personalização, Aplicativos, Contas, Hora e idioma, Acessibilidade,
      Privacidade e segurança, Atualizações do sistema, Sobre o dispositivo) abrem;
      Tab/↑/↓/Enter percorrem a lista com foco visível; Orca lê nome e papel.
   2. **Janela estreita** (arrastar até ~600 px e 1280×720 com escala 150/200 %):
      a navegação vira ícones com dica; o botão de menu e a lupa a expandem; nada
      é cortado; rolagem funciona em cada página.
   3. **Busca**: Ctrl+F foca; `wifi`, `wi-fi`, `bluetooth`, `resolução`/`resolucao`,
      `modo escuro`, `wallpaper`, `fuso`, `impressora`, `hostname`, `gpu`, `flatpak`,
      `senha`; `↓` + Enter; Enter direto abre o primeiro; Esc limpa; termo sem
      resultado mostra "Nenhuma configuração encontrada". Resultado com ícone de
      janela abre o módulo KDE; se o módulo não existir, só a página abre.
   4. **Início**: nome do computador = `hostname`; versão/canal = `identity.json`;
      perfil ativo = Classic/Modern real; rede e atualizações coerentes; cada
      atalho abre o módulo ou a página; resumo de hardware aparece sem travar a
      janela ("Coletando…" some).
   5. **Sobre o dispositivo** (comparar com `lscpu`, `free -h`, `lspci | grep -i
      vga`, `lsblk`/`df -h`, `uname -r`, `getenforce`): CPU, RAM, GPU,
      armazenamento (sem tmpfs/overlay; sem duplicar bind mounts), kernel,
      arquitetura, nome; "Copiar especificações" cola texto correto; "Detalhes
      avançados" mostra base técnica, imagem em execução, deployments e SELinux.
   6. **Personalização**: Classic ⇄ Modern (confirmação); Claro/Escuro altera o
      esquema (`kreadconfig6 --group General --key ColorScheme`), mantém o perfil;
      "Definir como papel de parede" muda o fundo; reabrir a página reflete o
      estado; reiniciar a sessão preserva; falha (ferramenta ausente) mostra
      mensagem e botão desabilitado.
   7. **Módulos KDE**: para cada página, anotar quais cartões aparecem
      habilitados/desabilitados/ocultos (ids variam com a versão do Plasma) e se o
      módulo abre na primeira tentativa. Registrar ids que não existem.
   8. **Rede/Contas/Hora/Acessibilidade/Privacidade**: valores exibidos
      (conexão, usuário, fuso, locale, SELinux, `/usr` somente leitura) batem com
      `nmcli`, `whoami`, `timedatectl`, `locale`, `getenforce`, `findmnt /usr`.
   9. **Sem terminal**: nenhuma operação abre terminal; atalhos que falham mostram
      aviso passivo.
   10. **Desempenho**: abrir/trocar de página com `QSG_RENDER_TIMING=1`; CPU do
       processo ocioso (sem polling novo além do existente).
7. **Update Center em modo seguro**: só verificar/ler estado (portão de
   mutação fechado); nada de atualizar/reiniciar. Conferir também (Lote 4):
   1. Estado e texto de cada situação alcançável sem mutar: desconhecido,
      verificando, atualizado, atualizações disponíveis, sem conexão (rede
      desligada na VM), serviço indisponível.
   2. "Atualizar agora" desabilitado com o motivo **"bloqueada por política"**;
      "Versão instalada" = `bootc status`; "Origem da imagem" coerente com
      `bootc status` (build local → "Não verificada").
   3. Lista "O que será atualizado" separada em *Sistema (imagem bootc)* e
      *Aplicativos (Flatpak)*; Flatpak desatualizado de teste aparece só no grupo
      de aplicativos.
   4. Origem estranha (imagem Fedora genérica): só a suíte nativa
      `settings-native-smoke` (roda no build) a exercita; não há como forçá-la na
      VM sem alterar a imagem. Registrar que o bloqueio não foi observado no app
      em execução.
   5. `--demo` com cada cenário (`up-to-date`, `update-available`, `downloading`,
      `preparing`, `restart-pending`, `failure`, `cancel`, `service-unavailable`):
      estados, progresso indeterminado/percentual e o banner de demonstração.
   6. Mutação **não** habilitada; nenhum terminal aberto; nenhum `dnf`/`bootc
      switch` no `journalctl` durante o teste.
8. **Welcome**: as 5 etapas, Voltar/Continuar, Pular e Concluir; fechar no
   meio e reabrir (retoma); **sem** `Unable to assign [undefined] to int`.
9. **Brave** (instalação em segundo plano ~8 min após o boot; sem rede = erro
   silencioso e nova tentativa): abrir, navegar, definido como padrão.
10. **Discover**: abre, lista Flathub, busca.
11. **Dolphin**: caminho completo na barra, abas, copiar/mover.
12. **Desempenho de janelas**: arrastar/redimensionar janela, maximizar,
    alternar Alt+Tab, abrir o launcher durante vídeo/animação.
13. **CPU/RAM**: `enthroned-diagnostics collect` ocioso (~2 min após o login)
    e de novo após o roteiro.
14. **Reinicialização e persistência**: reiniciar a VM; conferir perfil ativo,
    Welcome (`completed` não reabre), favoritos do launcher, estado do Settings
    (`~/.local/state/enthroned-os/`). Rodar `collect` de novo.

## 4. Sondas A/B opcionais (somente na VM, reversíveis, usuário decide)

```bash
# animações off / de volta
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --delete

# blur do KWin off / de volta (aplicar com: qdbus6 org.kde.KWin /KWin reconfigure)
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled --delete
```

## 5. Suspeitas não comprovadas (confirmar com os logs antes de mexer)

- **Plasma Setup (primeiro boot)**: `org.kde.plasmasetup.finished/main.qml` é
  uma cópia customizada e usa `InitialStartUtil` e `AccountController`; sem a
  fonte upstream e sem execução não dá para afirmar que o override é compatível.
  Candidato nº 1 se o erro aconteceu ao clicar em *Finalizar*.
- **Launcher**: `AppListDelegate.qml`/`FullRepresentation.qml` usam o id
  `launcher` de `main.qml` (escopo dinâmico entre arquivos). Se o journal
  mostrar `ReferenceError: launcher is not defined`, trocar por propriedade
  explícita (`Plasmoid`/propriedade `required`).
- **Custo do launcher**: o `Loader` por linha saiu no Lote 3; cada linha ainda
  usa `ItemBackground` (3 retângulos, 2 `Behavior`). Só otimizar mais se
  `QSG_RENDER_TIMING=1`/o `top` apontar o plasmashell durante a rolagem.
- **Launcher, Lote 3**: `Screen.desktopAvailableHeight` pode valer 0 até o
  popup ter janela (há valor de reserva) ou incluir o painel flutuante do
  Modern; `Qt.labs.platform` pode faltar na imagem; `modelForRow(1)` pode estar
  vazio antes do primeiro `refreshed` (os atalhos de ferramentas aparecem
  depois); `Keys.forwardTo` + Enter dependem do `TextField` não consumir Enter.
- **KWin**: `blurEnabled=true` e sombras grandes do Breeze custam caro sem GPU;
  `InputMethod=org.kde.plasma.keyboard` (herdado do Fedora) pode manter um
  processo extra do teclado virtual. Medir com as rodadas B/C/D antes de mudar.
- **`/etc/xdg/kded5rc`**: RESOLVIDO no Lote 7 — arquivo morto removido. A
  supressão real do Plasma Welcome é `plasma-welcomerc` (`LastSeenVersion`),
  confirmada no código do daemon (`plasma-welcome/src/kded/daemon.cpp`);
  adicionalmente o kded6 lê `autoload` do kded6rc do usuário, não do de
  sistema. Verificar em `processes.txt` (`autostart entries`) se algum
  `plasma-welcome` ainda sobe no login.
- **Primeiro login**: o Flatpak do Brave roda ~8 min após o boot (agora com
  `Nice=15`, I/O ocioso e timeout de 45 min); `systemd-analyze blame` deve
  confirmar que não pesa no boot.
- **Persistência pós-reboot** do Welcome/Settings/perfis: lógica coberta por
  testes node/spec, mas nunca observada em execução.

## 6. Lote 13 — identidade visual (pendente de VM; nada abaixo foi visto no Plasma real)

Relatório: `docs/validation/LOTE-13-VISUAL-INTEGRATION.md`. Marque e anote; não corrija durante o teste.

1. **Ícone do Iniciar:** Classic mostra o **E**, Modern o **trono**, nítidos no painel de 44/48 px.
   Alternar Classic ↔ Modern (Settings e `enthroned-profile apply …`) troca o ícone junto com o painel,
   sem widget duplicado; o ícone permanece após logout e reboot; botão direito no launcher segue normal.
2. **Wallpapers:** usuário novo (sem personalização) abre com **Vigília**. No seletor nativo do KDE aparecem
   “Enthroned — Soberania / Ascensão / Vigília” com miniatura; escolher outro, escolher uma imagem externa,
   logout, reboot: a escolha persiste. **Trocar de perfil não a reseta** (monitor único e com 2 monitores).
3. **API não verificada (crítica):** `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript`
   devolve o texto de `print()` e `desktop.screen` existe no Plasma 6.6? Se não, o snapshot de wallpaper de
   `enthroned-profile` não restaura nada (a troca continua funcionando, mas volta a Vigília).
4. **Settings/Welcome:** barra lateral (alvos de 38 px, barra de acento), cabeçalhos de seção, grade de
   wallpapers em janela estreita (sem corte), Sobre e Welcome com o logotipo completo, pt_BR e inglês,
   foco por teclado visível, escala 125/150/200 %.
5. **Cores:** contraste real nos dois esquemas (barra de progresso, switch, slider, seleção); decorações de
   janela; pastas violeta no Dolphin (tema claro e escuro).
6. **Splash** (Classic e Modern: fundo violeta + logotipo), página final do plasma-setup, tela de bloqueio,
   login e paisagem de entrada do plasma-setup (agora Vigília ampliada por Lanczos no build).
7. **Instalações já existentes (ex.: H5):** o plasmoid não tem o `icon` por perfil gravado — usuários do
   Modern verão o **E** (padrão) até reaplicar o perfil. Esperado; não é regressão da imagem nova.

## 7. Gate 13.1 — refinamento visual e wallpaper (pendente de Plasma real)
Detalhes e evidências em `docs/validation/GATE-13-1-VISUAL-NATIVE-REVIEW.md`. Conferir na VM:
1. **Ícones de aplicativo**: Settings mostra o E, Welcome mostra o trono (Menu Iniciar Classic = E roxo, Modern = poltrona),
   nítidos em 16/22/24/32/48 px no tema `Enthroned` e `EnthronedDark`, sem moldura nem fundo estranho.
2. **Troca Classic ↔ Modern com wallpaper escolhido** (`enthroned-profile apply modern|classic`): o wallpaper (imagem
   única) de cada monitor volta como estava; sem escolha prévia vale Vigília. `evaluateScript` responde, `desktops()`
   lista os monitores, `d.screen` coincide com a numeração do monitor, **nenhum containment/widget duplicado**.
   Com apresentação de slides ou cor sólida, o wallpaper **não** é preservado (limitação conhecida) — registrar o que ocorre.
3. **Settings**: cabeçalho de página, largura de leitura (1920×1080 e 125/150/200 %), sidebar, estados de foco
   (Tab), tema claro e escuro, Personalização com 2 colunas, Central de Atualizações sem regressão.
4. **Wallpapers legados** (`Enthroned`, `EnthronedNocturne`) ainda aparecem no seletor nativo: confirmar e decidir (ver relatório).

## 8. Lote 14 — ajustes pós-H6 (pendente de Plasma real)
Roteiro completo em `docs/validation/LOTE-14-POST-H6-FIXES.md` §5. Conferir na VM, em sessão controlada:
1. **Botão Iniciar** (E no Classic, trono no Modern) com presença próxima à dos ícones vizinhos em 100/150/200 %, sem corte no hover.
2. **Relógio Modern** só com hora após `enthroned-profile apply modern`; Classic mantém hora e data.
3. **Wallpapers novos** (`wall1` = Soberania, `wall3` = Vigília) presentes no seletor e como padrão; escolher um ≠ Vigília e trocar de perfil.
4. **Welcome**: Pular, Fechar e Retomar; **unidades `masked-runtime`** (kernel arg do disco de teste) e `masked` sem ela.
5. **Plasma Setup**: teclado na lista de layouts (hoje o layout só é aplicado ao clicar); **Dolphin**: ação nativa "Definir ícone da pasta".

## 9. Lote 15 — polimento visual final e Personalização (pendente de Plasma real)
Roteiro em `docs/validation/LOTE-15-FINAL-VISUAL-POLISH.md` §8. Conferir na VM:
1. **Menu Iniciar**: categoria **Sistema** (e Utilitários/Internet) com nomes completos legíveis; coluna Locais com largura fixa;
   100/150/200 %; ícones de Boas-vindas e Configurações (blocos de 56 px) mais presentes.
2. **Dolphin**: botão direito numa área vazia **sem** "Exibir estatísticas de uso do disco" e **sem** a faixa de cores/"Outros"; menu de arquivos,
   pastas selecionadas, Copiar/Colar, Propriedades e Terminal intactos.
3. **Personalização**: Claro/Escuro (agora com o id `EnthronedLight/Dark`), cor de destaque (aplicar, restaurar, persistir ao alternar tema e perfil),
   papel de parede próprio, tamanho dos ícones da área de trabalho e do painel, cor de pasta (e as cores no Dolphin), visão/ícones/ocultos/previews do Dolphin.
4. **Trocar Classic ↔ Modern**: tamanho dos ícones da área de trabalho e cor de destaque voltam como estavam; o tamanho do painel volta ao do perfil.

