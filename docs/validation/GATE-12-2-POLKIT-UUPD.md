# Enthroned OS — Gate 12.2: regra polkit do uupd

19 de novembro de 2026 · America/Sao_Paulo

**Risco comprovado e corrigido.** A regra da base Aurora liberava, sem autenticação, o início, a parada, o reinício e a morte de `uupd.service` e `uupd-manual.service` para **qualquer** conta local. A correção é uma regra nova, só de restrição, que mantém o início sem senha para o usuário `wheel` local e ativo (o caminho do Update Center) e exige autenticação de administrador para todo o resto. Nada foi desabilitado nem ampliado. 83 verificações de autorização passaram, 54 das quais reprovavam antes da correção. O canal continua fechado.

## 1. O que a regra atual autoriza

Arquivo `/usr/share/polkit-1/rules.d/uupd.rules`, do pacote `uupd-1.5.7-2.fc45` (upstream, não é do Enthroned):

```js
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units") {
        switch(action.lookup("unit")) {
            case "uupd.service":        return polkit.Result.YES;
            case "uupd-manual.service": return polkit.Result.YES;
        }
    }
})
```

| Dimensão | Alcance |
| --- | --- |
| Ação | `org.freedesktop.systemd1.manage-units`. Cobre **todos** os verbos do systemd: `start`, `stop`, `restart`, `kill`, `reload`, `reset-failed`, `set-property`. |
| Serviços | `uupd.service` (atualização automática, disparada por `uupd.timer`) e `uupd-manual.service` (atualização completa sob demanda). |
| Usuários | **Todos.** A regra não verifica grupo, sessão local, sessão ativa nem verbo. |
| Resultado | `YES`, sem senha. |

Como o polkit encerra no primeiro resultado e `uupd.rules` vem por último na ordem de nomes (depois de `empower.rules`), nenhuma regra da base restringe esse `YES`. As outras regras da base não tocam esses serviços: `22-ublue-rebase-systemd.rules` só cobre `ublue-rebase@*` e exige `wheel`; `21-ublue-rebase`, `20-privileged-*` e `org.projectatomic.rpmostree1` cobrem outras ações.

## 2. Quem precisa dela

| Chamador | Usa polkit? | Conclusão |
| --- | --- | --- |
| `uupd.timer` (preset `89-aurora.preset`: `enable uupd.timer`, 04:00 diário) | Não. O systemd inicia a unidade como root. | Não depende da regra. |
| `sudo uupd`, `ujust update`, `ujust toggle-updates` (`update.just`) | Não. Usam `sudo` e só consultam `systemctl is-active/is-enabled`. | Não dependem da regra. |
| Bazaar (`/etc/bazaar/bazaar.yaml`) | Não. Só declara `hide-auto-update-options: true`. | Não depende. |
| `enthroned-update-check.service` | Não. Roda `uupd update-check` como root. | Não depende. |
| **Update Center** (`UpdateEngine`, `StartUnit("uupd-manual.service", "replace")`) | **Sim.** O cabeçalho de `systemdcalls.h` registra que o início "is authorized by upstream uupd.rules". Nenhuma regra do Enthroned cobre `uupd-manual.service`. | **Depende.** Sem a regra o usuário veria um pedido de senha a cada atualização. |

Não achei outro chamador sem privilégio na base (busca textual em `/usr/share`, `/usr/lib`, `/usr/libexec`, `/usr/bin` e `/etc`). O Update Center só inicia (`StartUnit`), nunca para, reinicia nem mata.

## 3. Risco real

**Comprovado com o polkitd real** (contêiner descartável da base fixada, `dbus-daemon` + `polkitd` + `pkcheck`). Antes da correção:

| Sujeito (sem sessão de login) | Pedido | Resultado |
| --- | --- | --- |
| `bob` (nenhum grupo) | `start uupd-manual.service` | **`yes`** (rc 0) |
| `bob` | `stop uupd.service` | **`yes`** |
| `alice` (wheel, sem sessão) | `start uupd-manual.service`, `restart`, `kill` | **`yes`** |
| `bob` | `start sshd.service` (controle) | `auth_admin` (rc 2) |

**Impacto**, por ordem de relevância:

1. **Contorno da porta de atualização do Enthroned.** O Update Center só muta com `ENTHRONED_SETTINGS_ALLOW_MUTATION` e checagem de origem. Qualquer conta local podia iniciar `uupd-manual.service` e rodar `uupd --hw-check=false` (que ignora a verificação de hardware) fora da interface.
2. **Interrupção de uma atualização em andamento.** Qualquer conta podia parar ou matar `uupd*.service` enquanto o `bootc` prepara um deployment. O bootc é transacional, então o efeito é de disponibilidade, não de corrupção comprovada.
3. **Reinício repetido em laço.** `start` em sequência mantém o serviço, o helper de status e o bootc ocupados.

Não encontrei escalada de privilégio. As definições das unidades pertencem ao root e ficam em `/usr` imutável. `set-property` do systemd só aceita propriedades de controle de recursos, segundo a documentação, e não troca `ExecStart`. Gravidade: **média** (disponibilidade e contorno de política local). Não há vazamento de dados nem execução de código por conta sem privilégio.

## 4. Correção

Novo arquivo `system_files/usr/share/polkit-1/rules.d/10-org.enthroned.uupd.rules`. Ele ordena antes de `uupd.rules`, decide e encerra a avaliação:

| Sujeito e pedido | Resultado |
| --- | --- |
| `start` de `uupd-manual.service` ou `uupd.service` por usuário **local, ativo e do grupo `wheel`** | `YES` (igual ao upstream, só para esta classe e este verbo) |
| `stop`, `restart`, `kill`, `reload`, `reset-failed`, `set-property`, qualquer outro verbo, ou verbo ausente | `AUTH_ADMIN` |
| Qualquer outro sujeito (não `wheel`, sessão remota ou inativa, sem sessão) | `AUTH_ADMIN` |
| Usuário do grupo `empower` (`run0 --empower`) | Não tratado aqui: segue para `empower.rules`, que já devolve `YES` para tudo (sem mudança) |

- Não nega nada: `AUTH_ADMIN` mantém a via de administrador (a regra `50-default.rules` aponta o grupo `wheel` como administrador).
- Não amplia nada: o que passa a ter `YES` é um subconjunto do que o upstream já concedia.
- Não desabilita o polkit nem toca outras unidades. Só duas unidades são mencionadas, e só na ação `manage-units`.
- A regra existente `10-org.enthroned.settings.rules` (quatro unidades do Enthroned) ficou intacta.
- Por que uma regra nova e não editar a do upstream: `uupd.rules` pertence ao RPM e seria sobrescrita em cada atualização. Um arquivo de mesmo nome em `/etc` também esconderia mudanças futuras do upstream sem aviso. A regra nova só estreita e continua válida se o upstream mudar.
- O `build.sh` já normaliza `/usr/share/polkit-1/rules.d` (`0755`/`0644`), então o arquivo novo é coberto.
- `scripts/validate-settings.sh` ganhou 6 verificações da regra nova (existência, ordem, só as duas unidades, único `YES` com `start` e `wheel`/local/ativo, sem `NO`, carve-out de `empower`). Rodei dois testes negativos do validador: com a regra removida e com a regra ampliada para `YES`, ele reprova.

Canal de produção: `f1-dev`, `production_ready: false` e lista de origens vazia, mantidos.

## 5. Testes

Base Aurora fixada `sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`, contêineres descartáveis (`--rm`), polkit 127. Nenhuma unidade foi iniciada ou parada: os testes só perguntam a autorização.

`scripts/test-polkit-uupd.sh`, com duas partes:

- **A. polkitd real** (`pkcheck`) para sujeitos sem sessão logind: 20 verificações. Quatro verbos × duas unidades × (usuário sem grupo, usuário `wheel` sem sessão), mais `empower` e dois controles.
- **B. As regras reais da base e do Enthroned** avaliadas por `scripts/polkit-rules-harness.js` (semântica documentada do polkit: ordem de nomes, primeiro resultado vence, `/etc` esconde `/usr/share`), para o que exige sessão (local, ativa, grupos): 63 verificações. A parte B concordou com o polkitd real em todos os casos que os dois cobrem.

| Execução | Resultado |
| --- | --- |
| Sem a regra nova (reprodução do estado anterior) | **54 reprovações de autorização** (16 na parte A, 38 na parte B). Duas reprovações adicionais foram falha de preparo do teste (grupo `empower`) e foram corrigidas no teste. |
| Com a regra nova | **83 passed, 0 failed** (20 na parte A, 63 na parte B). 26 arquivos de regras carregados, 0 erros de carga. |

Casos positivos: usuário `wheel` local e ativo inicia `uupd-manual.service` e `uupd.service` com `YES`; usuário `empower` mantém `YES`; as quatro unidades do Enthroned continuam com `YES` para `wheel` local ativo e sem concessão para os demais; a regra `ublue-rebase@` segue intacta.

Casos negativos: todos os verbos além de `start` pedem autenticação para o usuário confiável; usuário `wheel` remoto, inativo ou sem sessão, não `wheel` local ativo, não `wheel` remoto e conta sem grupo nem sessão pedem autenticação para `start` e `stop` nas duas unidades; verbo ausente ou com caixa diferente (`START`) falha fechado; nomes parecidos (`uupd.service `, ` uupd.service`, `UUPD.service`, `uupd.service\n`, `uupd-manual.service.d`, `uupd.timer`, `../uupd.service`, `uupd.service@x`, NUL embutido) não recebem nada; outra ação do systemd (`reload-daemon`) não é afetada.

Regressões: `validate-settings` (exit 0, 346 linhas PASS), `validate-welcome`, `validate-desktop`, `test-system-stability` (65 PASS), `test-diagnostics-ptbr` e `test-desktop-helpers`, todos com exit 0. Nenhum código C++, QML nem a spec foram alterados neste gate; a bateria nativa do Gate 12.1 continua válida. Não repeti o CTest.

## 6. Arquivos

Novos: `system_files/usr/share/polkit-1/rules.d/10-org.enthroned.uupd.rules`, `scripts/test-polkit-uupd.sh`, `scripts/polkit-rules-harness.js`, este relatório.
Modificado: `scripts/validate-settings.sh` (+6 verificações). Cópia original com SHA-256 em `output/gate-12-2-backup-20261119/`.

Nada foi alterado em H4/H5, backups, imagens, discos ou VMs. Sem H6, sem VM, sem commit nem push.

## 7. O que falta confirmar em uma VM

Não consegui subir um systemd real com `dbus-broker` e `polkitd` em contêiner (o `dbus-broker` não inicia sem auditoria no contêiner), então a prova de ponta a ponta com `logind` fica para a VM. Todos os comandos abaixo só perguntam a autorização; nenhum inicia atualização.

Como usuário `wheel`, em uma sessão gráfica real:

```bash
for verb in start stop restart kill; do
  pkcheck --action-id org.freedesktop.systemd1.manage-units --process $$ \
    --detail unit uupd-manual.service --detail verb "$verb"; echo "$verb rc=$?"
done
```

Critério: `start` com rc 0; `stop`, `restart` e `kill` com rc 2 (autenticação). Repetir como usuário sem `wheel`: todos com rc 2.

Critério do Update Center: o botão de atualização inicia `uupd-manual.service` sem pedir senha. Confirmar no journal (`journalctl -b -u polkit`) que o pedido chega com os detalhes `unit` e `verb=start`. Se o systemd 262 não enviar `verb=start`, a regra falha fechada (pede senha) e o ajuste será só na regra.

## 8. Observações fora do escopo, sem alteração

- **`uupd.timer` fica habilitado por preset** e atualiza a partir da origem configurada, com ou sem o Update Center. Isso não passa pela regra polkit e não é afetado por ela. Se a intenção é manter o canal fechado também para atualizações automáticas, a decisão é separada (por exemplo, não habilitar o timer ou fornecer `/etc/uupd/config.json` restritivo) e exige sua autorização.
- `22-ublue-rebase-systemd.rules` concede `YES` para `wheel` em `ublue-rebase@*` sem exigir sessão local e ativa. É restrito a administradores e fora do fluxo de atualização. Não toquei.
- Os comentários de `systemdcalls.h` e `updateengine.h` ainda dizem que o início é "authorized by upstream uupd.rules". Continua verdade para a classe confiável; os comentários podem ser ajustados numa passada de documentação.

Aguardando sua autorização para a próxima etapa.
