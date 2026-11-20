# Gate 11C — Consolidação dos Lotes 11A (Sol 6.2) e 11B (GLM 5.3)

Data: 2026-11-19 · Executor: Sonnet 5.5 (High) · Base: `H5-VM-HOMOLOGATION.md`

Escopo cumprido: nenhuma imagem OCI/ISO/QCOW2/VDI, nenhum `podman build` do
Containerfile, nenhum VirtualBox, nenhum commit/push, H4/H5 e evidências
intactos, nenhuma atualização real, canal de produção fechado (`f1-dev`,
`production_ready: false`, `expected_image_references: []`).

## 1. Arquivos consolidados e conflitos

O repositório **não tem nenhum commit** (`git log` vazio, tudo untracked), então
o inventário foi feito por data de modificação (hoje) e conferido contra as
listas de arquivos dos dois relatórios.

- 36 arquivos alterados hoje = união exata das listas do 11A (8) e do 11B (28).
  Nenhum arquivo extra, nenhum ausente.
- **Interseção real entre os lotes: nenhuma.** `build.sh`, serviços, `verify-image.sh`
  são do 11A; `settings/`, `welcome/`, plasmoide do launcher, `validate-*.sh` do
  11B. A única dependência cruzada (`validate-welcome.sh` ↔ asserções do
  `build.sh`) está coerente: o validador exige `--exclude=plasma-discover-packagekit`
  e `--exclude=plasma-discover-offline-updates`, que o `build.sh` contém.
- `verify-image.sh` (11A) verifica `! rpm -q plasma-discover-packagekit` e
  `! rpm -q plasma-discover-offline-updates`, mesmas condições do `build.sh`.
- Sem referências órfãs: a única menção a `org.enthroned.launcher.po` é a guarda
  intencional de `validate-desktop.sh` (arquivo legado não pode voltar). O
  `build.sh` deriva o domínio do nome do arquivo, então a renomeação funciona
  sem mudanças (confirmado em §6).
- Testes novos integrados: `test-system-stability.sh` em `validate.yml`;
  `test-launcher-pinned-dedupe.mjs` em `validate-desktop.sh`.
- Gates 10.2/10.3: `release-channel.json` e testes do Update Center (465) seguem
  verdes; nenhum arquivo dessas correções foi tocado por 11C além dos listados em §3.
- Limitação: sem baseline Git, "nenhum lote sobrescreveu o outro" é conclusão por
  disjunção de arquivos, não por diff. `H5-VM-HOMOLOGATION.md` tem data de hoje
  (pré-existente ao 11C; não foi editado aqui).

## 2. Correções dos lotes integradas e verificadas

| Lote | Item | Situação após o 11C |
| --- | --- | --- |
| 11A | firstboot-flatpaks honesto (0/75/77/1/143) | Verificado; 1 lacuna real corrigida (§3, F2) |
| 11A | Discover sem backends RPM | Resolução provada no container (§5); uma afirmação do 11A estava errada (F3) |
| 11A | Guardas SELinux/`/var`/tuned | Mantidas; rótulo agora **confirmado no binário** (§8) |
| 11B | Update Center não afirma "atualizado" sem check | Verificado por CTest + 465 testes JS; 1 risco latente documentado (O1) |
| 11B | Welcome: autostart sem `after=panel`, round-trip | **Não compilava** (F1); corrigido, 2/2 CTest |
| 11B | Launcher: domínio `plasma_applet_…` | Verificado com KI18n real (§6) |
| 11B | Fixados deduplicados | Teste JS verde; QML real só na VM |

## 3. Falhas encontradas e correções aplicadas

**F1 — `welcome/tests/native-smoke.cpp` não compilava (11B, provado por compilação).**
O Qt da base usa `QT_NO_CAST_FROM_ASCII`; quatro `"literal"` viravam
`QString(const char*)` (linhas 71, 72, 95, 96). O GLM não pôde compilar (sem Qt
no Windows). Corrigido com `QStringLiteral`. Recompilado: `welcome-native-smoke`
passa (CTest 2/2). Era exatamente o risco apontado no pedido (C++ do GLM nunca
compilado). Os demais C++ do GLM (settings: `updateengine`, `bootcstatusprovider`,
os dois smokes) compilaram sem erro e passam.

**F2 — Classificação de "sem rede" do firstboot-flatpaks incompleta (11A, provado empiricamente).**
No flatpak real da base (flatpak 1.18.4, libcurl 8.21.0) sem rede, o erro é
`[6] Could not resolve hostname` (coberto), mas `[7] Could not connect to server`
e `[28] Timeout was reached` (mensagens do libcurl, confirmadas em `libcurl.so.4`)
**não** casavam com `network_re` e caíam em "falha" (exit 1). A direção do erro é
a segura (visível), mas produziria unit `failed` em boots com rede degradada.
Corrigido em `system_files/usr/libexec/enthroned-firstboot-flatpaks` (regex) e
coberto por testes novos (A5b: `connect`, `timeout` → 75; 77 → reparo manual →
próxima execução do timer sai 0 com `result=ok`; falha mista: 77 prevalece e os
dois erros ficam no log; sem arquivos `.status.*` residuais; timer mantém
`OnUnitActiveSec` e a unit não tem `Restart=` escondendo a falha).

**F3 — Premissa incorreta do 11A sobre o PackageKit (corrigida só no comentário).**
O 11A afirmava que o daemon PackageKit é dependência dura de `plasma-discover-libs`
e "permanece". Na resolução real (dnf5 5.4.8, repositórios fc45 `updates`):
`PackageKit`, `PackageKit-glib` e `appstream-data` só entravam via
`plasma-discover-packagekit`; com as exclusões **não são mais instalados**
(transação cai de 12 para 5 pacotes). Nenhum pacote da imagem requer PackageKit
(`rpm -q --whatrequires`). Efeito funcional: nenhum identificado (backend flatpak
presente), mas o relatório 11A e o comentário do `build.sh` estavam errados.
Comentário corrigido; relatório 11A não foi reescrito.

**F4 — Contagens do relatório 11B.** Execução real: filtro de categorias 12 checks
(11B declarou 23), appactions 41 (declarou 48), dedupe 11 (confere). Todos
passam; só os números do relatório estavam inflados.

Alterados no 11C: `welcome/tests/native-smoke.cpp`,
`system_files/usr/libexec/enthroned-firstboot-flatpaks`,
`scripts/test-system-stability.sh`, `build_files/build.sh` (somente comentário).

## 4. Compilações e testes efetivamente executados

Ambiente: WSL2 Ubuntu → Podman (root; o modo rootless não tem `newuidmap`) →
`ghcr.io/ublue-os/aurora:stable`, digest aprovado
`sha256:95996804…32ae92` (conferido), `--pull=never` para a imagem, `--rm`,
`--network=host` (netavark exige `nft`), código-fonte montado **somente leitura**,
árvores de build dentro do container (descartadas). Pacotes de desenvolvimento
instalados apenas nos containers. Nada instalado no Windows nem no Ubuntu do WSL.
Ao fim: 0 containers, as mesmas 3 imagens locais.

| Alvo | Resultado |
| --- | --- |
| `desktop-actions` configure + build | OK |
| `settings` configure + build (Ninja, Release) | OK; avisos pré-existentes (`flatpakupdatesprovider.cpp:95` unused-parameter ×3; `KLocalizedContext` deprecated) |
| `settings` CTest | **6/6**: appstreamtest, settings-close-smoke, settings-native-smoke, flatpak-lifecycle-smoke, bootc-status-smoke, update-engine-integration-smoke |
| `welcome` build (1ª vez) | **FALHA** (F1) |
| `welcome` build + CTest (após F1) | OK, **2/2**: appstreamtest, welcome-native-smoke; `enthroned-welcome --help` roda |
| Testes JS | welcome 91 passed / 0 failed; settings **465 PASS / 0 FAIL**; launcher filtro 12, dedupe 11, appactions 41 — 0 falhas |
| `test-system-stability.sh` | **65 PASS, ALL PASS** (inclui `systemd-analyze verify` das units) |
| Validadores | `validate-welcome`, `validate-settings`, `validate-desktop` (todos OK, incluindo testes JS do launcher), `verify-source` 15 pass / 1 warn / 0 fail |
| `bash -n` + `shellcheck -S warning` | build.sh, firstboot helper, harness, auditor, verify-image: limpo |
| `qmllint` | `FullRepresentation.qml`, `AppActions.qml`: sem erro de sintaxe; `UpdatesPage.qml` só avisos |

Não executado: `verify-image.sh` (exige imagem), `bootc container lint`, teste
da UI QML dentro de um plasmashell real.

## 5. Discover sem backend RPM (dnf5, base Aurora aprovada)

Dentro do container, com o `dnf5 install` do `build.sh`:

1. Sintaxe `--exclude=` aceita (dnf5 5.4.8).
2. Sem exclusões (reproduz a H5): 12 pacotes, incluindo `plasma-discover-packagekit`
   e `plasma-discover-offline-updates` como dependências fracas.
3. Com as exclusões: resolve sem conflito, **5 pacotes** (`plasma-discover`,
   `plasma-discover-flatpak`, `plasma-discover-kns`, `plasma-discover-libs`,
   `glibc-langpack-pt`). Instalação real (só no container) rc 0.
4. Nenhum requisito obrigatório incompatível: `plasma-discover` só exige
   `plasma-discover-libs`; os backends são `Recommends`.
5. Asserções do `build.sh`: `rpm -q` dos dois excluídos → não instalados;
   `plasma-discover-flatpak` presente. Equivalentes em `verify-image.sh`.
6. `plasma-discover --listbackends` (offscreen): `flatpak-backend`,
   `appstream-preview-backend`, `fwupd-backend`, `kns-backend`.

Fica para a VM: catálogo/instalação Flatpak na GUI, ausência do diálogo de
atualização, e se a falta de `appstream-data` (catálogo RPM) afeta algo visível.

## 6. Update Center, Welcome, Launcher

**Update Center.** Os nove casos pedidos têm transição definida e cobertura
(spec + 465 testes + integração C++): nunca verificado (`unknown` + `bootc-status-ok`
fica `unknown`), check iniciado (`checking`), sem atualização (`upToDate` só via
`check-no-update`), disponível, falha (`failed`/`noNetwork`), serviço indisponível,
staged (`restartRequired`) e retorno do cache após falha (mantém o estado). A
referência da imagem (`bootedImage` + transporte) é exibida separada da
classificação de origem; `unknown` mostra "Desconhecida". Canal fechado preservado.

**O1 — risco latente (não corrigido, de design):** o cache `bootc-status.json` é
publicado **uma vez por boot** (`RemainAfterExit=yes`) e nada o republica após um
update. Depois de `update-success`, `refreshAll()` lê o cache obsoleto sem
`stagedDeployment` e a spec tem `update-success → upToDate` (sem staged) e
`restartRequired + bootc-status-ok → upToDate`; um update real poderia exibir
"atualizado" em vez de "reiniciar". Hoje é inalcançável: o canal de produção
fechado bloqueia mutações. **Deve ser resolvido antes de abrir o canal** (republicar
o cache após a operação, ou ler o status por via privilegiada). Não alterei: exige
decisão de arquitetura.

**Welcome.** `X-KDE-autostart-after` removido (0 ocorrências); estado em
`XDG_STATE_HOME/enthroned-os/welcome-state.json` com `QSaveFile` (atômico);
política: autostart abre em qualquer fase ≠ `completed`; `manual` sempre abre;
estado corrompido/versão errada → reset ao inicial. O smoke nativo agora
compila e executa o round-trip real em diretório temporário (três
"logins"). **O2 — política a decidir:** não existe estado "dispensado"; fechar a
janela vira `interrupted` e o Welcome reabre em **todo** login até concluir
(o texto do 11B diz "concluído ou dispensado"). A causa original da não-retomada
na H5 continua **hipótese**; confirmação só em sessão real.

**Launcher.** `.mo` compilado com o código exato do `build.sh` e resolvido com
KI18n real: `pt_BR` → "Fixados", "Todos os aplicativos", "Locais", "Pesquisar no
computador", "Sessão e energia"; `en_US` → inglês; domínio legado
`org.enthroned.launcher` com `pt_BR` → inglês (confirma a causa raiz do 11B). Os
32 `i18n()` do QML têm msgid no catálogo (33 msgids). `kf6-kitemmodels` 6.32.0 e o
módulo QML `org.kde.kitemmodels` existem na base; o QML do plasmoide usa
`KSortFilterProxyModel` e `KRoleNames`. Nota: no teste, `LANGUAGE=de` com
`LANG=pt_BR` caiu em pt_BR (fallback do locale do sistema), artefato do teste.
Não verificado em plasmashell: o prefixo `plasma_applet_<Id>` do libplasma (a base
traz `plasma_applet_org.kde.plasma.kickoff.mo`, consistente), o proxy de Fixados
e os mapeamentos de índice na UI.

## 7. Segurança e canal de produção

`release-channel.json`: `f1-dev`, `production_ready: false`, sem referências
esperadas. `SELinux`/`tuned`/serviços não foram alterados ou desligados. Firstboot
helper nunca roda `flatpak repair`/`uninstall`/`remote-*` (testado) e usa `flock`
com o fd fechado no filho. Nenhuma atualização real, nenhum push.

## 8. Pendências (classificação)

| Item | Situação |
| --- | --- |
| firstboot-flatpaks exit 0 em falha | **Corrigido** (11A) + lacuna de rede **corrigida** (F2); VM: boot offline/online |
| Discover/backend RPM | **Corrigido na origem; resolução verificada**; efeito na GUI depende da VM |
| Rótulo `invalid_bootcinstall_testlabel_t` | **Causa confirmada**: a string está literalmente em `/usr/bin/bootc` 1.17.1 da base (sonda do bootc); **sem origem Enthroned**, não é correção, é conhecimento; guarda de regressão mantida |
| `/var` somente leitura após desligamento forçado | **Investigado sem causa confirmada**; depende da VM (`stability-audit-vm.sh`) |
| Tempo do `tuned` | **Investigado sem causa confirmada**; depende de medição na VM |
| Dolphin "0 B livres" | **Não é do projeto** (bug KDE 527197); base tem `dolphin 26.08.3` e a H5 exibiu o sintoma, então não há prova de que a correção upstream esteja nesta versão; requer base mais nova |
| KRunner captura teclado | **Investigado sem causa confirmada** (sem componente Enthroned no caminho) |
| Welcome retoma na VM | **Mitigado** (remoção do condicional + teste compilado); **depende da VM** |
| Update Center "atualizado" sem check | **Corrigido** (11B); O1 pendente antes do canal de produção |
| Launcher pt_BR / Fixados | **Corrigido** (tradução verificada com KI18n); Fixados depende da VM |

## 9. Backlog antes da próxima imagem

1. **P1 (antes de abrir o canal):** O1 — cache bootc obsoleto após update.
2. Decidir a política do Welcome (O2: reabrir a cada login até concluir, ou
   "dispensar").
3. Reconciliar o relatório 11A (PackageKit) e as contagens do 11B com este gate.
4. Avaliar Dolphin/plasma-workspace mais novos na base (Bug 527197).
5. Na VM: `stability-audit-vm.sh`; Welcome (fechar/encerrar/relogar); launcher em
   pt_BR; Fixados sem duplicata; Update Center (título após check falho, referência
   da imagem); Discover lista/instala Flatpak sem diálogo; firstboot offline→online.
6. Opcional: `qmltestrunner` ou carga headless dos QML com os módulos Plasma, para
   cobrir o que `qmllint` não prova.

## 10. Decisão

**GO para continuar o desenvolvimento (e para gerar a próxima imagem de homologação,
quando autorizado), com NO-GO para abrir o canal de produção.**

Motivo do GO: os dois lotes são disjuntos e coerentes; todos os alvos nativos
compilam e passam depois de **uma** correção de compilação (F1) e **uma** de
classificação (F2); a resolução do Discover foi provada na base aprovada. Motivo
do NO-GO de produção: O1, e itens que só a VM confirma (Welcome, Discover na GUI,
`/var`, `tuned`). Nenhuma nova imagem foi criada; aguardando autorização para o
próximo lote.
