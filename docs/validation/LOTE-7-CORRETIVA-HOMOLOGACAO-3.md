# Lote 7 — Correções da homologação 3 (2026-11-18)

Status: **SOURCE READY / STATIC VERIFIED**. Nenhuma build, imagem, disco ou VM
foi gerada nesta rodada (por contrato do lote). Nada foi validado em execução:
todo item marcado como RUNTIME PENDING exige a próxima build/VM.

Base de evidência: relatório e checklist da Homologação 3
(`output/homologacao-3-20261117/`), inspeção da base Aurora
(`aurora-base-before.json`) e leitura do código-fonte do Plasma 6
(libplasma, plasma-workspace, plasma-welcome — branches master, nov/2026).

## 1. Correções aplicadas

| # | Item do lote | Correção | Arquivo |
| --- | --- | --- | --- |
| 1 | P0 — launcher quebrado (Classic/Modern) | `PlasmaCore.DataSource` (API removida do `org.kde.plasma.core` no Plasma 6) substituído por `P5Support.DataSource` do módulo `org.kde.plasma.plasma5support`. Esse era o único uso no repositório e a causa-raiz da cascata `AppActions unavailable → FullRepresentation unavailable → "PlasmaCore.DataSource is not a type"` ao abrir o menu | `system_files/.../org.enthroned.launcher/contents/ui/AppActions.qml` |
| 2 | P1 — Lixeira protegida | O widget da Lixeira passa por `trash.locked = true` no layout script — propriedade oficial de scripting (`Q_PROPERTY(bool locked READ locked WRITE setLocked)`, `shell/scripting/widget.h`), que grava `immutability` do applet (UserImmutable). O Plasma esconde "Remover"/"Configurar" desse widget mantendo Esvaziar/Abrir funcionais. Nos dois temas | `system_files/.../org.enthroned.classic/contents/layouts/org.kde.plasma.desktop-layout.js` e `org.enthroned.modern/...` |
| 3 | P1 — Configurações do Enthroned | O link "Settings" da coluna Ferramentas do launcher prefere `org.enthroned.settings.desktop` (app "Configurações do Enthroned", nome pt_BR já correto) e cai para `systemsettings.desktop` se o hub não estiver instalado | `system_files/.../org.enthroned.launcher/contents/ui/FullRepresentation.qml` |
| 4 | P0 — boot: config morta | `etc/xdg/kded5rc` removido: arquivo do Plasma 5, nunca lido pelo kded6. A supressão do Welcome Center upstream é feita por `/etc/xdg/plasma-welcomerc` (`LastSeenVersion=999.99.99`), mecanismo confirmado no código do daemon do plasma-welcome (`src/kded/daemon.cpp`: sem lastSeenVersion vazio nem upgrade significativo, não lança). Evidência adicional: kded6 lê `autoload` do kded6rc do usuário, não do de sistema — config de sistema seria ineficaz de qualquer forma | `system_files/etc/xdg/kded5rc` (removido) |
| 5 | P0 — branding Aurora (defesa) | `build.sh`: se o `kcm_ublue.desktop` (KCM da base Aurora, confirmado em `aurora-base-before.json`) um dia aparecer apesar de NoDisplay/Hidden, o nome exibido não pode ser "Aurora" — sed de `Name=Aurora*` → `Enthroned OS` (no-op se o nome upstream for outro) | `build_files/build.sh` |
| 6 | P2 — validadores | Novos checks estáticos: banimento de `PlasmaCore.DataSource` em todo QML do launcher + exigência do import `plasma5support`; `trash.locked = true` e ícones livres (`locked=false`/`sortMode=0`) nos layouts; varredura de "aurora" em strings visíveis dos arquivos entregues (chaves visíveis de .desktop, linhas não-comentário de configs, QML/JS sem comentários, Name/Description de metadata.json); ausência do kded5rc morto | `scripts/validate-desktop.sh` |

## 2. Análise executada sem alteração de código

- **Boot lento e com erros (P0-2)** — só inspeção, sem benchmark:
  - Evidência H3: kernel ativo ~36 s; componentes de sessão a partir de
    T+116 s; OOBE utilizável entre T+120–180 s (VirtualBox VMSVGA, 3D off).
    Primeiro boot roda o OOBE (plasma-setup) antes do desktop — custo esperado.
  - Unidades da imagem revisadas por inspeção: `enthroned-firstboot-flatpaks`
    (timer T+8 min, oneshot, Nice/idle-IO, offline-safe, sai 0 — não bloqueia
    boot), `enthroned-update-check.service` (sem [Install]; disparo sob demanda,
    read-only), autostart `enthroned-files-setup` (one-shot, fase 2),
    `plasma-welcomerc` (defesa do Welcome upstream), NM `hostname-mode=none`,
    plasmalogin/ksplash/kscreenlocker apontando para wallpapers Enthroned.
  - Nenhum serviço foi desativado "para acelerar" (contrato do lote e
    DIAGNOSTICO-BOOT-IN-VM.md proíbem otimização sem medição in-VM).
  - Candidatos a erro visível para verificar na próxima VM (roteiro na seção 4):
    uupd mascarado (intencional na imagem de teste), timer de flatpaks sem rede
    (exita 0, só registra), avisos herdados do dracut (symlink /root) e locale
    "C"→"C.UTF-8" (cosmético, restrito ao container).
- **Menu de contexto do desktop (P1-4)** — investigado no código do Plasma
  (`containmentactions/contextmenu/menu.cpp`):
  - O conjunto de ações do menu é FIXO em C++ (ids `_context`, `desktop edit
    mode`, `_wallpaper`, `configure`, `_display_settings`, etc.). Não existe
    slot configurável para adicionar "Configurações do Sistema" — exigiria um
    plugin ContainmentActions próprio (C++). Registrado no backlog (seção 5).
  - "Área de trabalho e papel de parede" (`_wallpaper`) abre a página de papel
    de parede do System Settings — que na imagem só lista os wallpapers
    Enthroned (build.sh removeu os pacotes Aurora, incluindo metadata.json).
    Se a homologação viu "Aurora" aí, o suspeito restante é o `kcm_ublue`
    (oculto desde o Lote 6, agora com nome blindado) ou nomes de tema do
    plasmalogin — verificação runtime na seção 4.
  - "Espaço vazio estranho" no menu: não reproduzível estaticamente; a config
    de ações do menu mora no `plasma-org.kde.plasma.desktop-appletsrc`
    (`[ActionPlugins][0]`, grupo da coroa aberto com SimpleConfig — defaults de
    `/etc/xdg` NÃO cascata para esse arquivo). Correção configurável adiada
    para o próximo lote com repro em runtime (seção 5).
- **Mover ícones livremente (P1-5)** — chaves conferidas no `main.xml` do
  Folder View (plasma-desktop): `locked` (default já é false), `sortMode`
  (0 = unsorted), `alignment`. Os layout scripts já escrevem explicitamente
  `locked=false`, `sortMode=0`, `alignment=0`; validador agora protege isso.
  Se na VM ainda exigir modo de edição, o diagnóstico runtime deve capturar o
  valor real de `[Containments][<desktop>][General] locked`.
- **Botões de janela (P1-8)** — nada a mudar: `kwinrc`/`breezerc` já aplicam
  Breeze com `ButtonsOnRight=IAX` (min/max/fechar à direita, sem botões à
  esquerda), `ButtonSize=ButtonLarge`, cantos arredondados, título à esquerda
  (config do Lote 6, refletida nos dois look-and-feel). Aproximação adicional
  do Windows 11 exigiria decoração Aurorae própria — backlog.
- **Temas (P1-10)** — repositório só contém `org.enthroned.classic/modern`
  (sem Aurora); build.sh remove `dev.getaurora.*` e wallpapers/logo Aurora.
  Novo check estático impede regressão de strings visíveis.

## 3. Verificações estáticas executadas (host, sem build)

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-desktop.sh` | **ALL CHECKS PASSED** (inclui os novos checks deste lote) |
| `bash scripts/validate-settings.sh` | PASS (testes de lógica node: NOT RUN — sem node no host, igual às rodadas anteriores) |
| `bash scripts/validate-welcome.sh` | PASS (testes de lógica node: NOT RUN) |
| `bash scripts/verify-source.sh` | 15 pass / 1 warn pré-existente (placeholder do namespace) / 0 fail |
| shellcheck do build.sh | NOT RUN no host (sem shellcheck no Windows; roda no WSL na próxima build) |

Observação honesta: os novos checks são estáticos (presença de API correta,
ausência de API removida, strings visíveis) — não substituem a execução do QML
na VM.

## 4. Roteiro para a próxima homologação (além do checklist H3)

1. **Launcher (P0-1)**: clicar em Iniciar nos dois temas; o popup deve abrir.
   Se falhar, capturar `journalctl --user -b | grep -iE "enthroned|launcher"`.
2. **Lixeira (P1-6)**: botão direito na Lixeira — não deve oferecer
   Remover/Configurar; Esvaziar e Abrir devem funcionar.
3. **Ícones (P1-5)**: arrastar ícone com botão esquerdo sem entrar em edição;
   se falhar, `kreadconfig6 --file plasma-org.kde.plasma.desktop-appletsrc
   --group Containments --group <id-do-desktop> --group General --key locked`.
4. **Branding (P0-3)**: System Settings → varredura in-VM:
   `grep -ri aurora /usr/share/applications/ | grep -v '^Binary'`;
   `grep -E 'NoDisplay|Hidden' /usr/share/applications/kcm_ublue.desktop`;
   Conferir Tela de Login (nomes de tema do plasmalogin) e a lista de
   papéis de parede (só Enthroned/Enthroned Nocturne).
5. **Boot (P0-2)**: executar `DIAGNOSTICO-BOOT-IN-VM.md` no 2º boot (sem OOBE)
   e salvar `~/boot-diagnostico.txt`; comparar com o 1º boot.
6. **Configurações (P1-9)**: Menu Iniciar → Ferramentas → Settings deve abrir
   "Configurações do Enthroned" (`enthroned-settings`).

## 5. Backlog (próximo lote — não bloqueia a build)

- Entrada "Configurações do Sistema" no menu de contexto do desktop: exige
  plugin ContainmentActions em C++ (evidência: menu.cpp); avaliar custo.
- Limpeza configurável das ações do menu de contexto via kconf_update
  (grava `[ActionPlugins][0]` no appletsrc do usuário, respeitando
  customização existente) — corrigir corrida de 1ª sessão documentada.
- Reproduzir/atenuar o "espaço vazio" do menu de contexto (pedir screenshot).
- Conferir nomes de tema do plasmalogin na tela de login.
- Avaliar decoração de janela mais próxima do Windows 11 (Aurorae próprio).

## 6. Estado do Git

Branch `main`, sem commits (como nas rodadas anteriores — commit só sob
instrução explícita). Alterações de fonte deste lote listadas na seção 1.
Nenhum arquivo de output/ ou VMs foi tocado; nenhuma imagem anterior foi
modificada.
