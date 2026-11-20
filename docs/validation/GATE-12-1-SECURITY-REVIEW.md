# Enthroned OS — Gate 12.1: revisão de segurança e estabilidade

19 de novembro de 2026 · America/Sao_Paulo

**GO condicional para continuar as correções do sistema. NO-GO para abrir o canal de produção e para gerar a H6 enquanto a validação em VM dos itens da seção 8 não ocorrer.** A revisão encontrou **6 defeitos comprovados por teste** (nenhum é execução de código, escalada de privilégio ou vazamento). Todos foram corrigidos com a menor alteração segura. O Update Center não confirma uma operação nova com leitura antiga, e nenhuma falha aparece como atualização concluída. As lacunas restantes dependem de systemd, SELinux e Plasma em boot real.

Referências lidas: [Lote 12](LOTE-12-RELIABILITY.md), [Gate 11C](GATE-11C-INTEGRATION.md), H5 (`H5-VM-HOMOLOGATION.md`, evidência local).

## 1. Defeitos comprovados

| ID | Gravidade | Defeito | Prova antes da correção |
| --- | --- | --- | --- |
| F-01 | **Média** (segurança, disponibilidade) | O arquivo de lock `/run/enthroned/.bootc-status.lock` era criado `0644`. `flock(2)` não exige permissão de escrita, então qualquer usuário local podia segurar o lock e impedir a publicação do cache. O helper falhava com "could not lock" no boot e depois de cada atualização, e a Central ficava em "confirmação pendente" sem saída até uma nova atualização. | `T6a` e `T6b` falharam: processo `nobody` com `flock -x` bloqueou o helper (exit 1). |
| F-02 | Média-baixa (corretude) | O contrato do helper diz que toda falha de publicação descarta o cache. A falha de lock (`exit 1`) não descartava. A captura antiga seguia publicada como se fosse atual para quem reabrisse a Central. | `T7a` falhou: após timeout do lock o arquivo antigo permanecia. |
| F-03 | Média-baixa (corretude) | Um `SIGTERM` (por exemplo o `timeout 30s` do `ExecStartPost` ou a parada da unidade) deixava a captura anterior no lugar. | `T7b` falhou: após `timeout 3` o arquivo antigo permanecia. |
| F-04 | **Média** (funcional) | A base Aurora habilita `uupd.timer` (04:00 diário, `Persistent=true`) e `uupd.service` também prepara deployments. Só `uupd-manual.service` e `enthroned-system-update.service` republicavam o cache. Depois de uma atualização automática a Central continuava com o cache do boot e não mostrava **Reinicialização necessária**. | `T8` falhou: `uupd.service` sem drop-in. Inventário no contêiner: um `grep` por `ExecStart=` com `bootc upgrade` ou `uupd` devolve `uupd.service`, `uupd-manual.service` e `bootc-fetch-apply-updates.service` (esta última com timer desabilitado e `--apply`, que reinicia). |
| F-05 | Baixa-média (defesa em profundidade) | `build.sh` normaliza permissões só de `enthroned-*`. Os drop-ins `uupd-manual.service.d/` (Lote 12) e `uupd.service.d/` chegariam à imagem `0777`, executáveis, e rodariam como root no `ExecStartPost`. O `/usr` imutável do bootc impede a escrita em tempo de execução, mas o `systemd` já avisa "marked executable". | Contexto de build em `drvfs` mede `777`. Simulando o `chmod` do `build.sh` antigo: `777` nas duas pastas e nos dois arquivos. Com o novo: `755` e `644`. |
| F-06 | **Média** (estado após reabertura) | Ao abrir a Central com deployment staged válido no cache, o estado ficava em `unknown` em vez de **Reinicialização necessária**. O motor emite `staged-deployment-detected`, mas a spec só tinha transição de `bootc-status-ok[stagedDeployment]` a partir de `unknown`, que o motor nunca emite com staging. As transições `bootc-status-ok[staged]` de `unknown`, `failed`, `noNetwork` e `serviceUnavailable` são código morto. | Teste novo: `state=unknown avail=1 staged=1` com captura válida (reabertura). |

Não há defeito comprovado no Welcome. Os eixos de confirmação do Update Center resistiram a todos os cenários adversariais (seção 5).

## 2. Correções

| ID | Arquivo | Alteração |
| --- | --- | --- |
| F-01 | `system_files/usr/libexec/enthroned-bootc-status` | Lock criado com `umask 077` e `chmod 0600`. |
| F-02 | idem | Falha de lock chama `fail` (descarta o cache e sai com 1). |
| F-03 | idem | `trap 'fail "terminated"' TERM INT HUP`. |
| F-04 | `system_files/usr/lib/systemd/system/uupd.service.d/enthroned-bootc-status.conf` (novo) | Mesmo `ExecStartPost=-/usr/bin/timeout 30s /usr/libexec/enthroned-bootc-status` do drop-in de `uupd-manual`. Sem privilégio novo. |
| F-05 | `build_files/build.sh` | `find` com `chmod 0755` (diretórios) e `0644` (arquivos) para `uupd.service.d` e `uupd-manual.service.d`. |
| F-06 | `settings/src/update/update-state-spec.json` | Transição `unknown` + `staged-deployment-detected` → `restartRequired`. |
| F-06 | `settings/src/update/updateengine.cpp` | A notificação de reinício não dispara na descoberta inicial (`previous == unknown`). Sem isso, cada abertura do Settings com deployment staged notificaria de novo. A notificação segue para transições reais. |

Testes novos ou ampliados: `scripts/test-bootc-status-helper.sh` (novo, 28 verificações), `settings/tests/update-engine-integration-smoke.cpp` (+12), `settings/tests/bootc-status-smoke.cpp` (+14), `welcome/tests/native-smoke.cpp` (+17).

## 3. Arquivos

Modificados (cópias originais com SHA-256 em `output/gate-12-1-backup-20261119/`): `build_files/build.sh`, `settings/src/update/update-state-spec.json`, `settings/src/update/updateengine.cpp`, `settings/tests/bootc-status-smoke.cpp`, `settings/tests/update-engine-integration-smoke.cpp`, `system_files/usr/libexec/enthroned-bootc-status`, `welcome/tests/native-smoke.cpp`.

Novos: `scripts/test-bootc-status-helper.sh`, `system_files/usr/lib/systemd/system/uupd.service.d/enthroned-bootc-status.conf`, este relatório.

O backup do Lote 12 (`output/lote-12-backup-20261119`) foi conferido: 47 arquivos, 0 divergências. Nada foi alterado em backups, H4/H5, imagens, discos ou VMs. Sem Git, sem commit.

## 4. Testes executados e resultados reais

Base Aurora fixada `sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92` (systemd 262.1, bootc 1.17.1, polkit 127, jq 1.8.2, Qt 6.11.2), contêineres descartáveis do Podman no WSL (`g121-build` para compilar, contêineres `--rm --network=none` para o helper).

| Verificação | Resultado |
| --- | --- |
| Compilação Release (CMake/Ninja) de Settings e Welcome | Sem erros. |
| CTest Settings / Welcome | **6/6** e **2/2**, incluindo `settings-close-smoke` (encerramento sem SIGSEGV) e `flatpak-lifecycle-smoke`. |
| `update-engine-integration-smoke` | **74 passed, 0 failed** (62 + 12 novas). |
| `bootc-status-smoke` | **73 passed, 0 failed** (59 + 14 novas). |
| `welcome-native-smoke` | **82 passed, 0 failed** (17 novas). |
| Helper bootc (`test-bootc-status-helper.sh`) | **28 passed, 0 failed**. Antes das correções: T6a, T6b, T7a, T7b e dois itens de T8 falharam. |
| Welcome, binário real (Qt offscreen, `XDG_STATE_HOME` isolado) | **16 PASS, 0 FAIL**. |
| JavaScript | Settings **490**, Welcome **104**, espelho do UpdateEngine **59**, filtro do launcher **12**, deduplicação de fixados **11**, ações do launcher **41**, menu de contexto de perfis **2**, layouts Classic/Modern **6 cenários**. Zero falhas. |
| Validadores | `validate-settings`, `validate-welcome`, `validate-desktop` (352 PASS), `test-system-stability` (**65 PASS**, inclui Firstboot-flatpaks `0/75/77/1`), `test-diagnostics-ptbr` e `test-desktop-helpers`: todos com exit 0. |
| Bash e ShellCheck | `bash -n` e `shellcheck` com 0 no helper e no novo teste. |
| systemd | `systemd-analyze verify` das 4 unidades com os drop-ins: 0. Os avisos "marked executable" vieram da cópia a partir do `drvfs` e motivaram F-05. |
| Discover | `plasma-discover --listbackends`: `flatpak-backend`, `fwupd`, `kns`, `appstream-preview`. `plasma-discover-packagekit`, `plasma-discover-offline-updates`, `PackageKit` e `appstream-data` ausentes. Sem `packagekitd`. |

Não executei `qmllint`: nenhum QML foi alterado neste gate. As regressões de perfis, launcher e diagnósticos em pt_BR vêm da bateria JavaScript e dos validadores acima.

## 5. Update Center: o que foi auditado

| Ponto | Conclusão |
| --- | --- |
| Correlação systemd e snapshot | Conferida. A captura (`CLOCK_MONOTONIC`, µs, string decimal no JSON) é tirada **depois do lock**, antes da consulta. O motor exige `capture > ExecMainExitTimestampMonotonic` da execução correlacionada pelo job. Em ordem de lock, uma captura posterior nunca é sobrescrita por uma anterior (T5). |
| Unidades e `ExecStartPost` | `Type=oneshot` nas três. O `ExecStartPost` roda depois do `ExecStart`, antes de o job ser removido, e não altera `ExecMain*Timestamp`. `-` ignora a falha. Em `uupd*.service` com `Restart=on-failure` o post só roda no sucesso. |
| Compatibilidade | systemd 262.1 da base. A existência da propriedade `ExecMainExitTimestampMonotonic` não foi verificada em binário. Confirmar em VM (seção 8). |
| Sucesso, falha, timeout | Sucesso sem captura posterior fica pendente. Falha de unidade segue como falha, mesmo com cache que informa staging. Timestamp ausente, igual, anterior ou capturas malformadas mantêm a pendência. |
| Operações em sequência | Teste novo: a confirmação da operação 1 não confirma a 2. Uma operação sem timestamp não reaproveita o da anterior. |
| Cache ausente, antigo ou malformado | Capturas `"200"`, maior `uint64`, número JSON, negativo, estouro, lixo no fim, hexadecimal, expoente, vazio, `null`, array e booleano: só a string decimal válida vale, o resto lê como 0. Symlink, FIFO, permissões e tamanho já estavam cobertos. |
| Fechar e reabrir | O estado não é persistido. A Central reconstrói o estado só pelo cache. Com staging passa a mostrar **Reinicialização necessária** (F-06). Sem staging mostra `unknown`, sem afirmar atualização nem reinício. Cache malformado não afirma nada. |
| Consulta privilegiada que falha | O helper descarta o cache (T4: `bootc` falhando, vazio, sem booted, saída > 1 MiB). A Central fica pendente e honesta. |
| Reinício preservado | `restartRequired` não é rebaixado por captura sem staging. |

Não há cancelamento de operação no motor (nenhum `StopUnit`). Não se aplica.

## 6. Segurança do mecanismo privilegiado bootc

O helper continua sendo o único passo privilegiado do caminho de leitura. Resultado dos testes (T1–T9):

- **Escopo somente leitura:** todas as chamadas ao `bootc` fictício foram `status --format=json`. Nenhum argumento nem stdin é lido.
- **Diretório:** rejeita diretório gravável por grupo/outros, de dono não root e symlink (T2).
- **Destino:** symlink ou FIFO plantado no destino é substituído atomicamente por `mv` e nunca seguido (T3). O leitor usa `O_NOFOLLOW | O_NONBLOCK`, `fstat`, `S_ISREG`, dono root, sem escrita de grupo/outros e limite de 1 MiB.
- **Temporário e publicação:** criação exclusiva (`noclobber`), `chmod 0644`, renomeação atômica. Nenhum temporário restante (T1f).
- **Lock entre escritores:** agora `0600`. Dois escritores sobrepostos publicam em ordem de lock (T5).
- **Limites:** 1 MiB, 25 s no `bootc`, 30 s externos.
- **Superfície de polkit e systemd:** nenhuma regra nova, nenhuma ação nova, nenhum mecanismo genérico de execução. Os dois drop-ins só adicionam o mesmo `ExecStartPost`.
- **Observação sobre a base:** `/usr/share/polkit-1/rules.d/uupd.rules` (upstream Aurora) devolve `YES` para `uupd.service` e `uupd-manual.service` a **qualquer** sujeito, sem checagem de grupo ou sessão. Não alterei isso. Consequência: qualquer usuário local pode iniciar essas unidades e, portanto, o helper de leitura. O efeito é limitado a uma consulta de status por vez, serializada pelo lock. Ver seção 9.
- **SELinux:** não testável no contêiner (`getenforce` = Disabled). Seção 8.

## 7. Segurança da persistência do Welcome

Resultado: **sem defeito**. A política do Lote 12 se confirmou no código e no binário real.

- **Gravação atômica:** `QSaveFile`. Escritores intercalados (200 iterações, dois controladores) deixaram sempre um JSON legível e nenhum temporário.
- **Arquivos corrompidos:** 10 variações (vazio, raiz de tipo errado, `null`, versão como string ou desconhecida, fase não string ou desconhecida, fase ausente, truncado, 70 KB de lixo) voltam ao estado inicial completo. Página fora da faixa ou negativa, preferências com tipo errado e estado de instalação desconhecido são saneados sem perder uma dispensa válida.
- **Diretório no lugar do arquivo:** sem falha e sem tocar o diretório.
- **Migração:** `manualReopen` legado não reativa o autostart de quem concluiu. Interrupção legada retoma página e preferências.
- **Binário real:** primeiro login abre e grava `started`. Encerramento por `SIGTERM` retoma no próximo autostart. `completed` e `dismissed` suprimem o autostart antes e depois de uma revisita manual encerrada de forma abrupta. `--autostart --manual` se comporta como manual. A segunda instância sai com 0 enquanto a primeira roda.
- `finish()` antes da última página não conclui o assistente.

Limitações conhecidas, sem correção: com o diretório de estado sem escrita a gravação falha em silêncio e o assistente reaparece a cada login. A instalação opcional do ArtCraft pode ficar persistida como `pending` depois de um fechamento; a página oferece nova tentativa, mas o resumo final mostra o ícone de espera.

## 8. Dependem de uma VM real

Itens que dependem de VM e que **não** executei. Todos os comandos abaixo só leem; nenhum altera serviços, montagens ou arquivos, e nenhum provoca desligamento.

**8.1 Update Center e helper (após uma atualização real autorizada)**

```bash
systemctl show enthroned-system-update.service uupd-manual.service uupd.service \
  -p Type -p ExecStartPost -p ExecMainExitTimestampMonotonic -p ExecMainStatus -p Result
jq '.enthronedCaptureUsec, .status.staged != null' /run/enthroned/bootc-status.json
stat -c '%a %U:%G %n' /run/enthroned /run/enthroned/* /run/enthroned/.bootc-status.lock
ls -lZ /run/enthroned /usr/libexec/enthroned-bootc-status
journalctl -b --no-pager -u enthroned-bootc-status.service -u enthroned-system-update.service \
  -u uupd.service -u uupd-manual.service | grep -i -E 'enthroned-bootc-status|ExecStartPost'
sudo journalctl -b --no-pager -g 'avc:.*(enthroned|bootc-status)'
systemd-analyze security enthroned-bootc-status.service --no-pager
```

Critérios: `capture > ExecMainExitTimestampMonotonic` para a execução correlacionada; arquivo `644 root:root`, lock `600 root:root`; o rótulo SELinux de `/run/enthroned` permite a leitura pelo usuário gráfico; nenhuma negação AVC do helper; a propriedade `ExecMainExitTimestampMonotonic` existe no systemd 262; o `ExecStartPost` rodou antes da remoção do job; uma atualização automática de `uupd.service` passa a mostrar **Reinicialização necessária**.

**8.2 `/var` somente leitura após desligamento inesperado** (não provocar o desligamento; coletar após um evento que o operador já tenha tido): usar `scripts/stability-audit-vm.sh` (somente leitura) e, em complemento:

```bash
findmnt -no TARGET,SOURCE,FSTYPE,OPTIONS /var /sysroot
sudo journalctl -b -1 -k --no-pager -g 'remount|read-only|BTRFS|EXT4|error'
sudo journalctl -b 0 --no-pager -g 'remount|read-only' -u ostree-remount.service -u systemd-remount-fs.service
sudo btrfs device stats /var
```

Critério: identificar quem remontou `/var` como `ro` e por quê (erro do sistema de arquivos versus ação de unidade). Só promover a P1 se repetir em boot limpo.

**8.3 `tuned`:** `systemd-analyze critical-chain tuned.service; systemd-analyze blame | head -20; systemctl show tuned.service -p After -p Wants -p ExecStartPre; journalctl -b -u tuned --no-pager`. Critério: o tempo (22–29 s em H5) vem de ordenação ou de trabalho do daemon; só então avaliar um drop-in, medido em 3 boots.

**8.4 `input-remapper`:** `systemctl status input-remapper --no-pager; journalctl -b -u input-remapper --no-pager; systemctl show input-remapper -p TimeoutStartUSec -p Type -p Result`. Critério: o timeout é do serviço herdado (espera por dispositivo ou D-Bus) e ocorre sem relação com o Enthroned.

**8.5 KRunner:** `rpm -q plasma-workspace krunner; journalctl --user -b --no-pager -g krunner; kreadconfig6 --file krunnerrc --group Plugins --key webshortcutsEnabled`. Critério: reproduzir só com teclado real e anotar o estado (bloqueio de tela, popup de web shortcut).

**8.6 Dolphin "0 B livres":** `rpm -q dolphin kio; df -h /home /var; stat -f /home; findmnt -no TARGET,FSTYPE /home`. Critério: o valor correto em `df` e o valor mostrado no Dolphin divergem na mesma montagem (bug KDE 527197). Resolver com base mais nova, não com código do Enthroned.

**8.7 Plasma:** autostart entre logins, retomada, foco, aparência em Classic e Modern, Fixados e Discover/Flatpak sem PackageKit.

## 9. Decisões que precisam de autorização

1. **Restringir o polkit upstream de `uupd*.service`** (`YES` para qualquer sujeito) a usuários locais ativos do grupo `wheel`, por uma regra `10-` do Enthroned. Muda o comportamento da base (por exemplo `ujust` e fluxos remotos) e exige validação em VM.
2. **Endurecer `enthroned-bootc-status.service`** (`systemd-analyze security` = 9.0 UNSAFE). Opções como `ProtectHome`, `ProtectKernelModules` e `PrivateNetwork` (a unidade já tem `NoNewPrivileges` e `PrivateTmp`) precisam de teste em VM para não quebrar o `bootc status`. Não apliquei nada.
3. **Estado "Falha" versus "Reinicialização necessária":** uma segunda atualização que falha com um deployment já staged mostra **Falha** (o botão Reiniciar depende do estado, no `UpdatesPage.qml` linhas 208 e 412). Reabrir restaura **Reinicialização necessária** (teste). Corrigir exige decisão de UI.
4. **Janela de disputa de lock:** se o escritor do boot ainda está consultando o `bootc` (até 25 s) quando uma atualização termina, o helper do pós-atualização desiste em 2 s e descarta o cache (agora seguro). O escritor do boot então publica uma captura anterior à atualização. Ampliar a espera de lock ou o `timeout` das unidades altera o orçamento de 30 s e o `TimeoutStartSec` do serviço de boot. Medir o tempo real de `bootc status` em VM antes de decidir.

## 10. GO / NO-GO

- **GO** para continuar as correções do sistema. Não há P0 nem P1 aberto no escopo revisado.
- **NO-GO** para abrir o canal de produção (`f1-dev`, `production_ready: false`, lista de origens vazia, mantidos).
- **NO-GO** para gerar a H6 sem sua autorização e sem a coleta da seção 8.1, porque F-04, F-05 e F-06 só se confirmam em boot real.

Nada foi gerado: sem H6, OCI, ISO, QCOW2 ou VDI; sem VirtualBox; sem atualização real; sem commit ou push. Os contêineres descartáveis foram removidos ao final. Aguardando autorização.
