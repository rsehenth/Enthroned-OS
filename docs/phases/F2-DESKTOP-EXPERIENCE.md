# F2 — Desktop Experience Foundation: estado da fase

- **Data do registro:** 2026-11-16
- **Executor:** sessão Command Code (GLM 5.3 Flash), host Windows 11
- **Fonte do escopo:** prompt mestre F2 (fornecido na sessão)
- **Base alvo de API:** KDE Plasma 6.6 (Aurora stable = Fedora 44 desde a
  atualização Spring 2026; Plasma 6.6 publicado em fev/2026). Toda API usada
  foi verificada no código-fonte oficial dos branches `Plasma/6.6` de
  `plasma-workspace` e `plasma-desktop` (fontes listadas no final).

## Objetivos da fase

Primeira camada real de experiência do usuário do Enthroned OS sobre o KDE
Plasma: identidade visual própria, menu Iniciar, barra de tarefas, área de
trabalho com ícones, perfil Dolphin, dois perfis de layout e integração à
estrutura da imagem Aurora/bootc — sem builds e sem executar o KDE.

## Estados de conclusão (definições separadas)

| Estado | Valor | Evidência |
| --- | --- | --- |
| F2 IMPLEMENTED | **ATINGIDO** | Todos os componentes existem em código (inventário em ENTHRONED-DESKTOP-ARCHITECTURE.md) |
| F2 STATIC VERIFIED | **ATINGIDO** | `scripts/validate-desktop.sh`: 74/74 PASS; `verify-source.sh` 14 PASS/2 WARN/0 FAIL (regressão F1 zero); `bash -n` OK; `node --check` OK |
| F2 RUNTIME VERIFIED | **NOT RUN** | Nenhum Plasma executável no ambiente (Windows; WSL sem instalações autorizadas) |
| F2 INTEGRATED BUILD VERIFIED | **NOT RUN** | Nenhum build OCI executado (bloqueio herdado da F1: podman/just ausentes) |
| F2 BOOT VERIFIED | **NOT RUN** | Depende da imagem + VM |

## Entregas por item do escopo

- F2.1 Identidade visual — **feito em código** (2 esquemas de cores completos
  no formato oficial KConfig, design tokens, 3 SVGs próprios, 2 pacotes de
  papel de parede com 6 PNGs gerados por script reproducível).
- F2.2 Menu Iniciar — **feito via widget nativo configurado** (`org.kde.plasma.kickoff`
  do Plasma 6.6, que permanece o menu padrão upstream; confirmação no
  CMakeLists de `plasma-desktop/applets/kickoff`). Ícone Enthroned, favoritos
  curados, atalho Meta, busca/favoritos/energia nativos. **Decisão documentada:**
  sem fork/plasmoid próprio nesta fase (motivos em
  [arquitetura](../architecture/ENTHRONED-DESKTOP-ARCHITECTURE.md)).
- F2.3 Barra de tarefas — **feita** (layout script com `org.kde.plasma.icontasks`,
  `systemtray`, `digitalclock`; agrupamento e alternância nativos).
- F2.4 Área de trabalho com ícones — **feita via mecanismo nativo** (o desktop
  padrão do Plasma 6 é o Folder View; nenhum containment é trocado).
- F2.5 Explorador de arquivos — **feito** (`/usr/etc/xdg/dolphinrc` com padrões
  familiares; sem fork do Dolphin; confirmações destrutivas preservadas).
- F2.6 Perfis — **feitos** (`org.enthroned.classic` e `org.enthroned.modern`,
  mesma base técnica; troca via `plasma-apply-lookandfeel`, ferramenta oficial).
- F2.7 Integração à imagem — **feita em estrutura** (arquivos sob
  `system_files/usr/...`; `Containerfile`/`build.sh` já copiavam
  `system_files/` integralmente — **nenhuma mudança de build foi necessária**).
- F2.8 Desempenho — **respeitado por construção** (só widgets nativos; zero
  serviços/daemons novos; zero dependências novas; critérios de medição
  registrados na documentação de operação).
- F2.9 Preparação F3/F4 — **pontos de integração documentados** (nenhum botão
  de atualização fictício; nenhum ícone de app inexistente).

## Verificações executadas nesta sessão

| Verificação | Resultado | Observação |
| --- | --- | --- |
| `scripts/validate-desktop.sh` (74 checagens: JSON, INI/KConfig, QML/JS balanceamento, referências cruzadas, mágica PNG, higiene de caminhos) | **PASS 74/74** | python do shell do host; script somente-leitura |
| `scripts/verify-source.sh` (regressão F1) | PASS 14/2/0 | idêntico ao baseline F1.1 — nada da F1 foi alterado |
| `bash -n scripts/validate-desktop.sh` | PASS | |
| `bash -n build_files/build.sh` | PASS | arquivo não modificado; conferência |
| `node --check scripts/enthroned-wallpapers.js` | PASS | |
| Revisão visual dos PNGs gerados (1920x1080, light+dark) | PASS | 74–78 KB por imagem; gradiente suave, sem artefatos |
| Wallpapers 2560x1440 / 3840x2160 inspecionados visualmente | NOT RUN | mesma pipeline determinística dos 1080p revisados |
| Splash/layout no Plasma em execução | **NOT RUN** | sem KDE disponível |
| `plasma-apply-lookandfeel` | **NOT RUN** | idem |
| Build OCI / bootc container lint | **NOT RUN** | bloqueio F1 mantido (decisão do usuário) |

## Bloqueios e limitações registradas

1. **Runtime:** nenhuma validação em execução do Plasma foi possível — todos
   os componentes estão STATIC VERIFIED, não RUNTIME VERIFIED.
2. **Conflito potencial de `kdeglobals`:** se o Aurora upstream também
   publicar `/usr/etc/xdg/kdeglobals`, o nosso arquivo o substitui (o
   `build.sh` copia por último). Na primeira build real, comparar com o
   arquivo upstream e mesclar se houver chaves Aurora relevantes.
3. **Sem tema de ícones próprio:** a identidade usa Breeze/Breeze-dark
   (upstream) + 3 ícones Enthroned; um tema de ícones completo ficou para
   fase futura.
4. **Splash do gerenciador de login:** o wallpaper do greeter (Plasma Login)
   não é configurado nesta fase (mecanismo novo no Plasma 6.6+; a definir).
5. **context-mode (MCP):** permaneceu indisponível; pesquisa feita por fetch
   direto das fontes oficiais (conforme F1.1).
6. **Propriedades de painel além da amostra oficial:** `panel.floating` e
   `panel.hiding` são usados nos layout scripts por serem parte da API de
   scripting do Plasma documentada e amplamente usada por distribuições, mas
   não aparecem no `defaultPanel/layout.js` oficial consultado (que só usa
   `height`, `alignment`, `minimumLength`, `maximumLength`, `addWidget`);
   confirmar na homologação em VM.

## Fontes oficiais consultadas (Plasma/6.6, 2026-11-16)

- `plasma-desktop/applets/kickoff/` — menu Iniciar (CMakeLists + main.xml):
  confirma que `org.kde.plasma.kickoff` existe e suas chaves de configuração.
- `plasma-desktop/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js`
  — API de scripting de painel (`new Panel`, `addWidget`, `alignment`,
  `height`).
- `plasma-workspace/lookandfeel/org.kde.breeze/` — formato de
  `metadata.json` (`KPackageStructure`, `X-Plasma-APIVersion`), `contents/defaults`
  e `contents/layouts/*.js` dos pacotes look-and-feel.
- `plasma-workspace/applets/digital-clock/main.xml` — chaves do relógio.
- `plasma-workspace/lookandfeel/org.kde.breeze/contents/splash/Splash.qml` —
  estrutura da splash screen.
- `breeze/colors/BreezeLight.colors` — formato completo de esquema de cores.
- `breeze/wallpapers/Next/metadata.json` — formato de pacote de wallpaper.

## Próxima ação mínima

Homologação em ambiente Linux: com podman autorizado (WSL ou CI),
`just build && just verify-image` e, numa VM QCOW2, observar primeiro boot
(aplicação do L&F Classic), troca para Modern e Dolphin — preenchendo os
estados RUNTIME VERIFIED / INTEGRATED BUILD VERIFIED.
