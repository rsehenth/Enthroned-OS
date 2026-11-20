# Arquitetura da primeira experiência — Enthroned Welcome (F4)

## Visão geral

O Enthroned Welcome (`welcome/`) é um aplicativo Qt6/QML/Kirigami nativo que
acompanha o primeiro login gráfico de cada usuário. Ele não executa nada no
boot do kernel, não bloqueia o Plasma e não depende de internet.

```
Sessão gráfica (Plasma)
└── XDG autostart (/etc/xdg/autostart/org.enthroned.welcome.autostart.desktop)
    └── enthroned-welcome --autostart
        ├── QLockFile (single instance; 2ª instância sai silenciosamente)
        ├── WelcomeController (estado por usuário + política de abertura)
        │   ├── load()/save()  → $XDG_STATE_HOME/enthroned-os/welcome-state.json
        │   │                    (QSaveFile: temp + rename atômico)
        │   ├── applyEvent()   → welcome-state-spec.json (contrato declarativo)
        │   └── shouldShowOnLaunch(phase, fonte, manualReopen, alreadyRunning)
        ├── ProfileBridge      → /usr/bin/enthroned-profile (F2.1, look-and-feel)
        ├── AppAvailability    → detecção real de Brave/Discover/flatpak
        ├── ArtcraftInstaller  → instalação opcional com portão + SHA-256
        └── QML (5 telas, Kirigami, i18n pt-BR, sem cores fixas)
```

## Estado por usuário (F4.7)

Arquivo: `$XDG_STATE_HOME/enthroned-os/welcome-state.json` (nunca `/usr`).
Gravação atômica via `QSaveFile`. Campos: `version`, `phase`,
`currentPage`, `artcraftConsented`, `artcraftInstallState`, `manualReopen`,
`updatedAt`.

Fases (contrato compartilhado `welcome/src/welcome-state-spec.json`, espelhado
pelos testes `welcome/tests/run-tests.mjs`):

| Fase | Significado |
| --- | --- |
| `never-started` | Nunca iniciado |
| `started` | Sessão em andamento (também após encerramento anormal) |
| `interrupted` | Usuário fechou sem concluir — retomável |
| `completed` | Concluído — autostart nunca mais abre |
| `optional-pending` | ArtCraft consentido, instalação ainda não concluída |
| `optional-done` | Instalação opcional concluída |
| `optional-failed` | Instalação opcional falhou (retry possível) |

Eventos: `first-launch`, `resume`, `close`, `finish`, `artcraft-consent`,
`artcraft-decline`, `artcraft-success`, `artcraft-failure`, `artcraft-retry`.
Evento sem transição correspondente mantém a fase (semântica idêntica à F3).

### Política de abertura

`shouldShowOnLaunch(phase, fonte, manualReopen, jáEmExecução)`:

- `autostart`: abre a menos que `phase == completed` (`manualReopen` força);
- `manual` (`--reopen`): sempre abre (revisita, inclusive `completed`);
- segunda instância: nunca abre nada (sai silenciosamente se autostart).

A reabertura manual é feita por Enthroned Settings → Aplicativos →
"Reabrir Enthroned Welcome" (`launchApp("enthroned-welcome")`).

Sanitização: registro com `version` inválida, fase desconhecida ou JSON
corrompido é redefinido por inteiro para `never-started` — campos nunca são
misturados de "duas vidas" diferentes.

## Instalação opcional do ArtCraft (F4.6/F4.8)

Contrato de segurança (`artcraftinstaller.h/.cpp`):

1. Consentimento em duas etapas: checkbox **desmarcado por padrão** + diálogo
   de confirmação explícito; ausência de escolha nunca é consentimento;
   "Agora não" nunca instala.
2. Portão de execução: sem `ENTHRONED_WELCOME_ALLOW_INSTALL=1` o estado final
   é `blocked`, com mensagem honesta e **nenhum acesso à rede**.
3. Fonte única oficial: `api.github.com/repos/storytold/craft-launcher`
   (releases). Asset `artcraft-launcher-<ver>-linux-<arch>.flatpak`.
4. Verificação SHA-256 contra o `SHA256SUMS.txt` do mesmo release, casando o
   nome exato do asset; falha descarta o download.
5. Instalação: `flatpak install --user --noninteractive` — sem root, sem
   mutação do sistema, sem layering rpm-ostree, sem execução de scripts,
   sem `curl | bash`.
6. Verificação pós-instalação (`flatpak info --user
   ai.storyteller.artcraft-launcher`) antes do estado `done`.
7. Offline: falha com mensagem clara; o assistente segue utilizável e a opção
   permanece acessível (retry via Welcome reaberto ou Settings).

Estados do instalador (`idle/checking/downloading/verifying/installing/done/
failed/blocked`) fazem parte do contrato; `downloading` informa progresso real
(quando há `Content-Length`), nunca cronômetro inventado.

Modo demo (`--demo --demo-scenario <nome>`) reproduz cenários fixture de
`src/demo/scenarios/` sem rede nem instalação — mesmo padrão da F3.

## Perfis de aparência (tela 2)

A tela reutiliza exclusivamente `enthroned-profile` (F2.1), que aplica via
`plasma-apply-lookandfeel`. Nada é aplicado automaticamente ao abrir a tela:
aplicar exige ação explícita + confirmação; o texto informa que a reversão
integral de preferências individuais não é garantida pelo KDE.

## Integração com os perfis e o Launcher (F4.10)

- Favoritos do Enthroned Launcher/kickoff usam `preferred://browser`, que
  resolve para o navegador padrão real (Brave, via `/etc/xdg/mimeapps.list`).
  Nenhum favorito é fixado a um ID de navegador e nada é gravado em
  configurações de usuários existentes.
- Enthroned Welcome e Enthroned Settings são acessíveis pelo menu (desktop
  entries reais); `org.enthroned.welcome.desktop` é a entrada visível.

## Limites declarados

- Sem Qt6/KF6 no ambiente de desenvolvimento: SOURCE IMPLEMENTED,
  BUILD NOT RUN (estágio `welcome-builder` comentado no Containerfile).
- A instalação real do ArtCraft não foi executada nem homologada; o portão
  permanece fechado por padrão até avaliação de segurança com o sistema
  inicializável.
- Sem telemetria, sem contas, sem WebView, sem serviços systemd por usuário.
