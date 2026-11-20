# Validação estática F4 — registro (2026-11-16)

Executor: `bash scripts/validate-welcome.sh` (ou `just verify-welcome`).
Ambiente: host Windows 11 (Git Bash + Node 26 + Python 3.14), sem Qt/KDE,
sem build OCI, sem rede além do necessário às pesquisas de fonte (não faz
parte da validação).

## Resultado

| Suíte | Resultado |
| --- | --- |
| `welcome/tests/run-tests.mjs` (node, lógica do contrato) | **85 asserções PASS / 0 FAIL** |
| `scripts/validate-welcome.sh` (estática F4) | **PASS total** (ver contagem abaixo) |
| Regressão F3 `scripts/validate-settings.sh` | **PASS total** (node: 228/228) |
| Regressão F2 `scripts/validate-desktop.sh` | **PASS total** |
| `bash -n` (build.sh, helpers, provisioning, validadores) | **OK** |

Categorias da validação estática F4 (~190 verificações):

1. **Contrato** — spec coerente (7 fases, 12 transições, gate declarado,
   consentimento obrigatório, checkbox padrão desmarcado, política de apps
   honesta, política de perfis explícita).
2. **Fixtures** — 18 cenários F4.13 coerentes + nomes únicos; 4 cenários demo
   do instalador dentro dos estados do contrato.
3. **QML** — 7 arquivos: chaves balanceadas, nenhuma cor fixa, todo `text:`
   via `i18n()`, sem WebView, cinco telas presentes, fechamento marca a
   passagem, checkbox de consentimento existente e NÃO pré-marcado, diálogo
   de confirmação antes de instalar, ação "Agora não" honesta.
4. **C++** — 9 arquivos: proibidos `sudo`/`pkexec`/`system(`/`popen(`/`curl`;
   persistência atômica (`QSaveFile`), sanitização reset-to-initial, política
   de abertura, portão `ENTHRONED_WELCOME_ALLOW_INSTALL` com estado `blocked`
   sem rede, fonte única oficial (1 URL), SHA-256 obrigatório, flatpak
   apenas `--user` (sem `--system`, sem rpm-ostree), User-Agent declarado,
   verificação pós-instalação, `QLockFile`, autostart respeitado, demo.
5. **Empacotamento** — CMake declara todos os QML + spec + 4 cenários;
   `.desktop` válido com Exec/ícone reais; autostart com `--autostart` e
   `OnlyShowIn=KDE;`; appdata XML válido; nenhum atalho morto em
   `system_files`.
6. **Imagem** — unidade oneshot guardada (sem `[Install]`), timer instalável,
   script provisioning idempotente/offline-safe sem execução de scripts e sem
   manipulação de remotes, lista com apenas `com.brave.Browser`, mimeapps
   apenas com defaults, `build.sh` garante Discover + habilita timer +
   chmod, estágio `welcome-builder` comentado, favoritos do Launcher
   resolvíveis (`preferred://browser`, sem ID fixo de navegador).
7. **Integrações** — Settings com Discover/reabrir Welcome/informação ArtCraft
   sem atalhos mortos; documentação F4 completa.

## Defeitos encontrados e corrigidos durante a fase

1. **Contrato:** cenários de instalação não propagavam o resultado do
   instalador para a fase (`optional-done/failed` inalcançáveis) — fixtures e
   semântica corrigidos.
2. **Contrato:** sanitização mantinha campos de registros com fase inválida —
   agora o registro é confiável só como um todo (reset integral).
3. **Instalador:** progresso de download apagava o estado corrente; checksum
   agora casa o nome exato do asset (o release tem um bundle por arquitetura).
4. **`validate-settings.sh` (F3):** falso positivo no Windows — `rel` com
   `\` impedia a isenção de `/components/` no check de i18n.
5. **Resolução de Python** nos validadores: stubs da Microsoft Store em PATH
   quebravam a execução no Windows — resolução por sonda (python3/python/py).

## Não executado (sem homologação — não reportar como verificado)

- Nenhuma compilação Qt; nenhuma execução em Plasma; nenhum build OCI;
  nenhuma instalação real (Brave, Discover, ArtCraft) — BLOCKED por
  restrições de ambiente e pela política de homologação (portão fechado).
