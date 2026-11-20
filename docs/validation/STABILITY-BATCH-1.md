# Lote 1 — estabilidade e desempenho (2026-11-17)

Classificação: **SOURCE READY / STATIC VERIFIED**. Não é BUILD VERIFIED: nada foi
compilado, instalado ou executado em Qt/KDE/VM. Sem benchmark; nenhum ganho de
desempenho está provado.

## Problemas reais (demonstráveis pelo código)

| # | Problema | Evidência | Correção |
| --- | --- | --- | --- |
| 1 | `Unable to assign [undefined] to int` em `WelcomePage.qml:45` | `Kirigami.MessageType.Info` não existe; o enum é `Information` (já usado corretamente em `UpdatesPage.qml`) | `Info` → `Information` nos 7 usos (Welcome: Welcome/Style/Apps/Artcraft; Settings: Apps/Appearance/Devices) |
| 2 | Welcome: controlador destruído antes do engine QML ao encerrar | `controller` é variável de pilha, `engine` pertence ao `app` (destruído depois); bindings em `welcome.*` reavaliam contra objeto morto na saída | `delete engine` logo após `app.exec()` (`welcome/src/main.cpp`) |
| 3 | `busy` preso para sempre se o processo auxiliar não inicia | só `QProcess::finished` era ligado; `FailedToStart` não o emite | handler de `errorOccurred` em `ProfileBridge`, `ProfileController`, `KcmLauncher`, `ArtcraftInstaller` |
| 4 | Settings bloqueia a UI na abertura | `ConnectivityMonitor::refresh()` criava `QDBusInterface` (introspecção) e chamava `call()` síncrono (até 25 s) em `refreshAll()` | chamada assíncrona (`asyncCall` + watcher, timeout 5 s) |
| 5 | Settings acessa a rede ao abrir | `flatpak remote-ls --updates` sem `--cached` (o comentário prometia metadados em cache) | `--cached` |
| 6 | Provisionamento Flatpak sem limites | unidade `oneshot` sem timeout e com prioridade normal, 8 min após o boot | `TimeoutStartSec=45min`, `Nice=15`, `IOSchedulingClass=idle` |

## Efeito esperado (sem métricas)

- 1: some o aviso; as mensagens informativas passam a ter o tipo certo.
- 2: possível fim de `TypeError` na saída do Welcome (hipótese coerente com o
  código; não reproduzida).
- 3: UI nunca fica travada em "Aplicando…"/"Instalando…" se a ferramenta falhar ao iniciar.
- 4/5: Settings não deve congelar nem depender de rede/NetworkManager ao abrir.
- 6: menos competição com a sessão durante o provisionamento do Brave.

## Consolidação (revisão do lote)

- `ConnectivityMonitor`: estado inicial agora é "desconhecido" (`nmAvailable=false`,
  a UI mostra "Não verificado" e `offlineDetected` fica falso); respostas
  atrasadas são descartadas por número de geração; `refresh(callback)` executa o
  callback quando a resposta mais recente chega (máx. 5 s, sem bloquear a UI).
- `updateengine.cpp`: os dois caminhos de falha da verificação (`:187`, `:248`)
  só aplicam o evento depois do refresh de conectividade, preservando o
  `offlineDetected` correto que a versão síncrona garantia (regressão evitada).
- `ProfileBridge`: o destrutor aguarda (até 15 s) um `enthroned-profile apply`
  em andamento; antes, Concluir logo após "Aplicar perfil" matava o
  `plasma-apply-lookandfeel` pela destruição do QProcess.
- Encerramento do Welcome: `finish()` → `quit` → fechamento da janela →
  `markClosed()` repete save/`requestQuit` (inofensivo: "close" não tem
  transição a partir de `completed`). Instalador ArtCraft encerrado no meio do
  download deixa o `QTemporaryDir` (alocação crua) sem remover — portão fechado
  por padrão, não corrigido.
- `enthroned-diagnostics`: `timeout` de 20 s por comando e 900 s no `run`,
  amostrador sem processo órfão, erro explícito se não puder criar a pasta.
- Serviço do Brave: acionado só pelo timer (sem `WantedBy`), 8 min após o boot;
  não bloqueia login, Plasma nem Welcome. `Nice`/I/O ocioso valem para o cliente
  `flatpak`; o trabalho do `flatpak-system-helper` (D-Bus) roda fora do cgroup da
  unidade e não é limitado por eles.

## Suspeitos (não comprovados) → `docs/operations/NEXT-HOMOLOGATION.md` §5

Erro desconhecido após o assistente (Plasma Setup *finished*, Welcome ou
launcher), custo de renderização por software (blur/sombras/animações), custo
por linha do launcher, escopo dinâmico do id `launcher`, `kded5rc` com nome do
Plasma 5, teclado virtual do KWin, persistência pós-reboot.

## Estratégia para o erro desconhecido

`enthroned-diagnostics collect` logo após o evento (journal da sessão guarda a
mensagem) e `enthroned-diagnostics run settings|welcome` para stderr com tempos.
Detalhes em `docs/operations/NEXT-HOMOLOGATION.md`.

## Verificações leves executadas

`validate-welcome.sh`, `validate-settings.sh`, `validate-desktop.sh` e
`verify-source.sh` passam (inclui testes de lógica node). `bash -n` no
`enthroned-diagnostics`; execução local do coletor no Windows/Git Bash apenas
para checar a sintaxe/quoting (saída em diretório temporário, somente leitura).
**Não verificado**: compilação C++/QML (sem Qt/KDE no host), `shellcheck`
(ausente), comportamento em execução.
