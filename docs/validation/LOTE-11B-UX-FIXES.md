# LOTE 11B — CORREÇÕES DE UX, WELCOME E UPDATE CENTER

**Data:** 2026-11-19
**Executor:** GLM 5.3 (paralelo ao Lote 11A, de Sol 6.2 High)
**Referência:** `docs/validation/H5-VM-HOMOLOGATION.md`
**Status:** implementado e validado estaticamente; pendências de VM listadas na §7.

---

## 1. Problemas corrigidos

### 1.1 Welcome não reabria após interrupção (P2-6a)

Diagnóstico: a política de abertura em C++ (`shouldShowOnLaunch`) e a máquina de
estados já estavam corretas e cobertas por testes (autostart abre em qualquer
fase exceto `completed`). O elo fraco estava na **condição de retomada do
autostart**: `X-KDE-autostart-after=panel` adiava o início do Welcome até o painel
registrar-se no gerenciador de sessão; se esse registro não completar no boot, o
início adiado pode nunca disparar — o assistente não abre mesmo com o estado
persistido "iniciado, não concluído" (exatamente o sintoma da H5 nos logins
05:59/06:19).

Correção (arquivo do Welcome, sem tocar em serviços):

- Removido `X-KDE-autostart-after=panel` de
  `welcome/data/org.enthroned.welcome.autostart.desktop` (mantido
  `X-KDE-autostart-phase=2`). O Welcome não depende do painel para funcionar.
- Novo teste de contrato no validador: a condição de retomada deve ser
  autocontida (nada de `X-KDE-autostart-after`).
- Cobertura nova de retomada interrompida (ver §5): fixture de interrupção sem
  evento de fechamento (kill simulado), fixture de ciclo completo
  (primeiro login → interrupção → retomada → conclusão → nunca mais autostart)
  e `welcome/tests/native-smoke.cpp` reescrito com **round-trip real de
  persistência** (três instâncias do controlador, como três logins, em
  `XDG_STATE_HOME` temporário): interrupção lógica simulada, retomada na mesma
  página, conclusão, não-reabertura por autostart, reabertura manual sem reset e
  arquivo de estado corrompido → reset honesto ao estado inicial.

Regras da tarefa conferidas: nunca iniciado → abre (política de primeiro login);
iniciado/interrumpido → retoma com página e preferências preservadas; concluído
ou dispensado → não reabre por autostart (reabertura manual continua); estado
não é sobrescrito durante OOBE/login (nenhum evento é aplicado sem
`notifyLaunched`, e o estado só é reescrito por eventos reais do assistente).

**Limitação honesta:** a causa exata dentro da VM da H5 não é reprovável offline
(sem journal da H5). A correção remove o único fator de "autostart condicional"
existente no componente e adiciona regressão de contrato; a confirmação final é
item de teste em VM (§7).

### 1.2 Update Center exibia "Sistema atualizado" sem verificação (P2-5)

Causa raiz confirmada no código: `bootc-status-ok` (leitura do status do
deployment — não é uma verificação de atualizações) transicionava
`unknown → upToDate`; e após uma verificação falha, o `refreshAll()` disparado no
fim do check emitia outro `bootc-status-ok` que promovia `failed → upToDate`. A
UI mostrava "Sistema atualizado" enquanto a lista de eventos exibia o
`check-failed` vermelho — o comportamento exato da evidência
`evidence/boot2/s-update-center-after-fail.png`.

Correção no contrato declarativo (`settings/src/update/update-state-spec.json`,
compartilhado pelos dois interpretadores):

- `unknown/failed/noNetwork/serviceUnavailable` + `bootc-status-ok` (sem staged)
  → **mantêm o estado**. Só `check-no-update` (verificação real concluída) ou
  `update-success`/`flatpak-update-success` (operação real concluída) chegam a
  `upToDate`.
- `bootc-status-ok` com `stagedDeployment` → `restartRequired` permanece (fato
  observado real).
- O contrato está documentado no próprio spec (`honesty_contract`) e coberto por
  bloco de testes "lote11b" no runner.

Título honesto para verificação falha: novo `Q_PROPERTY lastOperationWasCheck`
no `UpdateEngine` (derivado dos eventos de ciclo de vida em `applyEvent`, cobre
fluxos reais e demo). `failed` + verificação → título **"Não foi possível
verificar atualizações"** com detalhe explícito ("NÃO se sabe se existem
atualizações; nada foi instalado nem alterado"), em vez do genérico "Falha".

### 1.3 Origem da imagem (P2-4b / P2-6b)

Antes: uma linha "Origem da imagem" mostrava apenas a classificação ("Não
verificada (canal de desenvolvimento)") — a referência real do deployment
não aparecia, e origem desconhecida renderizava linha vazia.

Agora (`UpdatesPage.qml`, leitura apenas; o serviço privilegiado do Lote 10.2
não foi alterado):

- **"Referência da imagem"** (linha técnica nova): `bootc.bootedImage` do cache
  (ex.: `localhost/enthroned-os:h5` + digest), com o **transport** do cache
  quando presente ("Transporte: registry").
- **"Origem da imagem"** (classificação de confiança/canal) separada da linha
  técnica; origem `unknown` agora exibe **"Desconhecida (não foi possível ler a
  origem)"** — nunca vazia, nunca apresentada como confiável.
- `BootcStatusProvider` expõe `bootedTransport` (parse tolerante: só aceita
  string; ausente → vazio; um campo puramente apresentável jamais invalida a
  captura).
- Versão e timestamp continuam legíveis nas linhas existentes (versão instalada
  + timestamp ISO do cache).

### 1.4 Launcher com strings em inglês (P2 herdado da H4/H5)

Causa raiz confirmada no upstream: o domínio de tradução de um plasmoid é
`"plasma_applet_" + KPlugin.Id`
(`Plasma::Applet::translationDomain()` em libplasma). O catálogo era compilado
como `org.enthroned.launcher.mo` — um domínio que o QML do launcher nunca
consulta, então todo `i18n()` caía no inglês ("Pinned", "All applications",
"Places", "Search this computer", "Session and power").

Correção (sem tocar no `build.sh`, que deriva o domínio do nome do arquivo):

- `build_files/l10n/pt_BR/org.enthroned.launcher.po` → renomeado para
  `plasma_applet_org.enthroned.launcher.po`. O conteúdo (todas as traduções)
  já existia e foi preservado.
- Guarda no `validate-desktop.sh`: o catálogo deve existir com o domínio
  `plasma_applet_` e o arquivo de domínio legado não pode voltar.
- Suporte a inglês e fallback a outros idiomas preservados (fontes QML seguem em
  inglês; nenhuma tradução fixa foi inserida nos componentes).

### 1.5 Brave duplicado nos Fixados (H4 P2)

O defeito existe no código atual: o proxy de dedupe do Lote 9.2 cobria a lista
de aplicativos/categorias, mas a visão **Fixados** usava o `favoritesModel` cru.

Correção:

- Novo proxy `pinnedDedupe` em `FullRepresentation.qml`: a grade de Fixados é
  deduplicada pela **identidade canônica do aplicativo** — o papel `url` do
  kicker (`AppEntry::url()`, arquivo `.desktop` resolvido, com symlink
  resolvido), com `favoriteId` como fallback. Assim:
  - alias `preferred://browser` e entrada fixada `applications:com.brave…`
    (mesmo arquivo resolvido) colapsam em um tile;
  - instalações genuinamente diferentes (Flatpak × desktop entry com arquivos
    distintos) permanecem — nenhum favorito diferente é removido;
  - é somente de exibição: a loja de favoritos (KActivitiesStats) mantém todas
    as entradas e a ordem (primeira ocorrência vence).
- `AppActions.qml` ciente do proxy: reordenar ("Mover para o início/antes/
  depois") mapeia linhas do proxy para linhas reais do modelo de favoritos
  (`moveRow`); desafixar continua por id; "Fixar"/"Adicionar à área de trabalho"
  inalterados; o menu de reordenação volta a aparecer com o proxy ativo.
- Teste novo `scripts/test-launcher-pinned-dedupe.mjs` extrai o callback REAL do
  QML e cobre: variantes Flatpak e desktop entry, alias + entrada direta,
  documentos, chaves vazias, ordem preservada, re-avaliação estável e
  pass-through sem papel `favoriteId`.

### 1.6 Dolphin "0 B livres" (H4 P2) — investigado, sem causa no projeto

Não há configuração Enthroned para a barra de status do Dolphin (o
`enthroned-files-setup` semente Places, modo de visualização e barra de
ferramentas — nada de espaço livre). É **bug upstream do KDE**, Bug 527197
("[dolphin] '0 B free' incorrectly shows for available space"): desde
"mountpointobservercache: Use Solid for determining mountpoint", a barra media o
montagem do dispositivo informado pelo Solid — em btrfs com subvolumes
(`/var/home`), dá "0 B". **Corrigido no upstream do Dolphin em 19/10/2026**
(commit "mountpointobservercache: measure the free space of the folder's mount").
Contorno proposto (fora do meu escopo, para o Sol/orquestrador): atualizar o
Dolphin/plasma-workspace da imagem para um snapshot que contenha a correção; no
lado Enthroned nenhuma mudança é necessária ou adequada.

### 1.7 KRunner popup (P2-7)

Investigado sem mudança: não há componente Enthroned no caminho do popup de
sugestão do KRunner (comportamento upstream); a H5 própria o classificou como
"incômodo só para a automação". Nenhuma modificação invasiva sem causa
comprovada, conforme a restrição da tarefa.

### 1.8 Correção de cheque obsoleto (não-regressão do Lote 11B)

`scripts/validate-welcome.sh` exigia o literal antigo
`dnf5 -y install plasma-discover`, que o `build.sh` já não usa desde o
encaminhamento do P2-2 (Discover garantido **com** `--exclude=plasma-discover-packagekit`
e `--exclude=plasma-discover-offline-updates`). A falha era preexistente (o
validador não tinha sido rodado após aquela mudança); o cheque foi atualizado
para o estado atual e intencional — Discover segue garantido, com os backends de
atualização RPM fora.

---

## 2. Arquivos modificados

**Welcome (`welcome/`)**
- `data/org.enthroned.welcome.autostart.desktop` — removido
  `X-KDE-autostart-after=panel` (condição de retomada autocontida).
- `tests/native-smoke.cpp` — reescrito: parte demo in-memory + round-trip real
  de persistência (interrupção sem close, retomada, conclusão, políticas de
  reabertura, corrupção → reset).
- `tests/scenarios/19-interrupcao-brusca.json` — novo (kill simulado).
- `tests/scenarios/20-ciclo-completo-retomada.json` — novo (ciclo completo).
- `tests/run-tests.mjs` — contador de fixtures 18 → 20.

**Settings / Update Center (`settings/`)**
- `src/update/update-state-spec.json` — 4 transições `bootc-status-ok`
  dessonestas corrigidas; `honesty_contract` documentado.
- `src/update/updateengine.h` / `updateengine.cpp` —
  `Q_PROPERTY lastOperationWasCheck` (derivado em `applyEvent`).
- `src/bootcstatusprovider.h` / `.cpp` — `bootedTransport` (opcional, tolerante,
  limpo no `markUnavailable`).
- `qml/pages/UpdatesPage.qml` — título/detalhe de "verificação falhou"; bloco da
  origem refeito ("Referência da imagem" técnica + "Origem da imagem"
  classificação, com "Desconhecida" honesta).
- `src/update/demo/scenarios/rollback-failed.json`,
  `rollback-success.json`, `staged-recovery.json` — agora começam com uma
  verificação real (`engine-check-started` → `check-no-update`), que é o caminho
  honesto para `upToDate`.
- `src/update/demo/scenarios/unexpected-data.json` — `finalState`/`expectState`
  `upToDate` → `unknown` (leitura de status não é verificação).
- `tests/run-tests.mjs` — bloco "lote11b" com o contrato de honestidade.
- `tests/bootc-status-smoke.cpp` — transporte lido (fixture real), captura sem
  `transport` segue válida.
- `tests/update-engine-integration-smoke.cpp` — expectativa atualizada: após
  `refreshAll()` sem verificação, a máquina descansa em `unknown` (antes
  esperava `upToDate`).

**Launcher (recursos de interface do launcher)**
- `system_files/usr/share/plasma/plasmoids/org.enthroned.launcher/contents/ui/FullRepresentation.qml`
  — proxy `pinnedDedupe` (identidade canônica por `url`), invalidação junto ao
  `modelRevision`.
- `…/contents/ui/AppActions.qml` — `sourceRowOf`/`isPinnedView`; `move()` mapeia
  proxy → modelo real; menu de reordenação ativo com o proxy.
- `build_files/l10n/pt_BR/plasma_applet_org.enthroned.launcher.po` — renomeado
  de `org.enthroned.launcher.po` (domínio correto do Plasma), conteúdo preservado.

**Catálogo do Settings**
- `build_files/l10n/pt_BR/enthroned-settings.po` — novas msgids:
  "Could not verify updates", detalhe da verificação não concluída,
  "Image reference", "Transport: %1", "Unknown (origin could not be read)".

**Validadores/scripts**
- `scripts/validate-welcome.sh` — 20 fixtures; cheque do autostart
  autocontido; cheque "discover guaranteed" atualizado ao build.sh atual.
- `scripts/validate-desktop.sh` — execução opcional dos testes JS do launcher
  (filtro, dedupe de fixados, app actions) + guardas do domínio de tradução.
- `scripts/test-launcher-pinned-dedupe.mjs` — novo teste de regressão.

**Não modificados (deliberadamente):** `build_files/build.sh`, `Containerfile`,
serviços systemd, `system_files` fora do plasmoid do launcher,
`docs/validation/H5-VM-HOMOLOGATION.md`. Nenhum commit/push, nenhuma imagem.

---

## 3. Testes executados e resultados reais

| Teste | Comando | Resultado |
| --- | --- | --- |
| Welcome (lógica, 20 cenários) | `node welcome/tests/run-tests.mjs` | **91 passed / 0 failed** |
| Settings (lógica: spec, cenários demo, busca, catálogo) | `node settings/tests/run-tests.mjs` | **465 PASS / 0 FAIL** (inclui 19 cheques novos "lote11b") |
| Launcher — filtro de categorias (Lote 9.2) | `node scripts/test-launcher-filter.mjs` | **ALL CHECKS PASSED** (23) |
| Launcher — dedupe de Fixados (novo) | `node scripts/test-launcher-pinned-dedupe.mjs` | **ALL CHECKS PASSED** (11) |
| Launcher — ações/atalhos | `node scripts/test-launcher-appactions.mjs` | **ALL CHECKS PASSED** (48) |
| Validador estático do Welcome | `bash scripts/validate-welcome.sh` | **All welcome validation checks passed** (inclui os 2 fixtures novos e o cheque do autostart) |
| Validador estático do Settings | `bash scripts/validate-settings.sh` | **All settings validation checks passed** |
| Validador estático do Desktop | `bash scripts/validate-desktop.sh` | **ALL CHECKS PASSED** (inclui as guardas novas do domínio `plasma_applet_`) |

Testes C++ não compiláveis neste host (sem Qt/CMake no Windows): o
`welcome-native-smoke.cpp` reescrito, `bootc-status-smoke.cpp` e
`update-engine-integration-smoke.cpp` atualizados compilam no CI
(`validate.yml`/`just verify-*` em Linux) e na VM — pendência de execução na §7.
Observação: os executáveis de smoke exigem binários Qt; o `validate.yml` atual
não os compila — a execução deles permanece no fluxo de imagem/VM já existente
(Lotes 9.x–10.x).

---

## 4. Pendências herdadas do KDE (documentadas, fora do escopo)

1. **Dolphin "0 B livres"** — Bug KDE 527197, corrigido no upstream em
   19/10/2026. Proposta: atualizar o Dolphin da imagem para uma versão com a
   correção (build_files — responsabilidade do Sol). Nenhuma ação Enthroned.
2. **KRunner popup de sugestões** (P2-7) — upstream; incomodou apenas a
   automação; sem mudança.
3. **Discover/backend RPM** (P2-2) — exclusões já presentes no `build.sh`
   (verificadas pelo validador atualizado); smoke visual na VM quando houver
   homologação.
4. Ruídos de journal herdados da H4 (udev `plugdev`, tmpfiles, logind,
   grub-boot-success, agetty) — inalterados, fora do escopo.

## 5. Pendências do próprio Lote 11B (para o Sol/orquestrador)

- Compilar e rodar os smokes C++ atualizados (welcome-native-smoke,
  bootc-status-smoke, update-engine-integration-smoke) no ambiente Linux/CI que
  já constrói os apps Qt.
- `flatpak preinstall`/`firstboot-flatpaks` (P2-1) e rótulo SELinux (P2-3)
  permanecem para o Lote 11A — nada foi alterado neles.

## 6. Funcionalidades que exigem teste na VM (próxima homologação)

1. **Retomada do Welcome**: abrir o assistente, fechar a janela (e, numa
   variação, encerrar a VM sem fechar), logar novamente e confirmar a reabertura
   com o banner de retomada e a página preservada; concluir e confirmar que não
   reabre por autostart; reabrir manualmente pelo Settings.
2. **Update Center**: na abertura, título "Ainda não verificado" (não "Sistema
   atualizado"); após verificação com falha, título "Não foi possível verificar
   atualizações" mesmo após reabrir a página/`refreshAll`; origem mostrando a
   referência real (`localhost/<imagem>:<tag>` + digest) com transporte quando
   presente; versão e timestamp legíveis; canal de produção permanece fechado
   (sem "Atualizar agora"; banner íntegro).
3. **Launcher pt_BR**: "Fixados", "Todos os aplicativos", "Locais",
   "Pesquisar no computador", "Sessão e energia" e demais strings do chrome em
   pt_BR; sessão en_US continua em inglês.
4. **Fixados sem duplicados**: com Brave instalado, nenhum tile duplicado nos
   Fixados; reordenação e desafixar funcionando sobre o proxy.
5. **Acessibilidade** nos componentes alterados: navegação por teclado no menu
   (reordenação via teclado), foco visível nos novos estados, textos pt_BR sem
   truncamento (referência da imagem longa quebra linha na InfoRow).

## 7. GO/NO-GO para integração com o Lote 11A

**GO.**

Fundamentos: todos os testes estáticos e de lógica disponíveis neste host passam
(3 validadores completos + 4 suítes Node, 0 falhas); as mudanças no contrato do
Update Center são regressão-protegidas por bloco dedicado e pelos cenários demo
atualizados; o Welcome ganha cobertura nova do fluxo exato da H5 (interrupção
sem evento de fechamento); o launcher recebe a correção de domínio com guarda de
regressão; nenhum arquivo do Lote 11A (build.sh, Containerfile, serviços,
systemd) foi alterado — exceto a renomeação do catálogo do launcher, que o
`build.sh` já suporta sem mudanças (deriva o domínio do nome do arquivo).

Ressalvas: a causa final da não-reabertura na VM da H5 é hipótese forte
(eliminação do único condicional de autostart do componente), não certeza
reprodutível offline — o teste nº 1 da §6 é obrigatório na próxima VM antes de
fechar o P2-6a definitivamente.
