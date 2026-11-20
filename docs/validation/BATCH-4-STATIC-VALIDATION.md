# Lote 4 — validação estática

Data: 2026-11-17. Classificação: **SOURCE READY / STATIC VERIFIED**.
Nada foi compilado nem executado (sem Qt/KF6, compilador, OCI, VM, commit ou push).

## Executado

| Verificação | Resultado |
| --- | --- |
| `scripts/validate-settings.sh` (estático + lógica node) | 284 PASS / 0 FAIL |
| `settings/tests/run-tests.mjs` (spec de atualização + busca/navegação) | 364 asserções PASS / 0 FAIL |
| `scripts/validate-desktop.sh` (regressão Lote 2/3, F2) | 163 PASS / 0 FAIL |
| `scripts/validate-welcome.sh` (regressão Welcome) | 190 PASS / 0 FAIL |
| `scripts/verify-source.sh` (regressão F1) | 14 PASS / 0 FAIL, exit 0 (jq ausente: aviso já existente) |

Novas checagens do Lote 4: 12 áreas na navegação; páginas/componentes/`search.js`
existem e estão no CMake; nenhum texto de hardware fixo nos QML; o app não chama
`bootc switch/rebase/upgrade`, `dnf`, `rpm-ostree`, `sudo`/`pkexec`; guarda de
origem aplicado pelo engine e por `canUpdate()`; listas sistema/Flatpak separadas;
`launch()` restrito a módulos listados; coleta de hardware em thread de trabalho;
personalização só com ferramentas do Plasma e allowlist; `release-channel.json`
declara `expected_image_references`. Busca testada com 18 consultas reais (acento,
sinônimo, `wi-fi`≡`wifi`, AND de palavras, limite). Consistência índice↔páginas↔
`Main.qml` testada por regex sobre o código-fonte.

## NÃO executado (limitações a validar em runtime)

- **Nenhuma compilação C++/QML.** Erros de sintaxe, de tipo QML ou de moc podem
  existir; o primeiro build (CMake + `ctest` no estágio `settings-builder`) é o
  teste real. O `settings-native-smoke` agora inclui a política de origem (8 casos).
- Ids de módulos KCM (ex.: `kcm_kscreen` × `kcm_displayconfiguration`,
  `kcm_kwallet`, `kcm_recentFiles`, `kcm_proxy`, `kcm_tablet`) foram escritos a
  partir do conhecimento do Plasma 6, sem consulta a um sistema real; a detecção em
  tempo de execução evita botões mortos, mas a homologação deve listar os que
  aparecem.
- `plasma-apply-colorscheme`/`plasma-apply-wallpaperimage` dentro do app, a
  atualização da paleta após aplicar o tema (re-leitura com atraso de 0,8 s) e a
  leitura de `kdeglobals` via `QSettings`.
- `lspci` presente na imagem? (senão a GPU vem de `/sys/class/drm`, só com IDs).
- Coleta em thread (`QThread::create` + `invokeMethod` enfileirado), `QStorageInfo`
  em ostree (filtro por `/dev/`, binds colapsados), SELinux e `/usr` somente leitura.
- Modo estreito, foco/teclado (`Ctrl+F`, ↓, Enter), leitores de tela e escalas.
- Atualização real: portão fechado; bloqueio por origem estranha só exercitado
  pelo teste nativo; unidade só-sistema, cancelamento real e versão disponível
  antes do download continuam bloqueados (ADR-0007 §5).
- O índice de busca está em português; as traduções dependem do catálogo
  `enthroned-settings`, que ainda não existe.

## Estado do Git

Repositório sem commits (`main` sem histórico); todos os arquivos do projeto
aparecem como não rastreados. Nada foi commitado nem enviado.
