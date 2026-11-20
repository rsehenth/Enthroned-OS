# Gate 12.3 — Proteção das atualizações automáticas

19 de novembro de 2026 · America/Sao_Paulo

**GO para continuar a estabilização. NO-GO para abrir o canal de produção ou gerar a H6 sem autorização.** O build da próxima imagem removerá a habilitação herdada da Aurora e bloqueará as rotas systemd capazes de preparar ou aplicar uma atualização do sistema. O canal continua `f1-dev`, com `production_ready: false` e lista de origens vazia.

## 1. Rotas auditadas

Inventário na Aurora fixada `sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`, com systemd 262.1, uupd 1.5.7, bootc 1.17.1 e rpm-ostree 2026.3. Foram examinados units e drop-ins, links de dependência, presets, geradores, serviços D-Bus, autostarts, cron, receitas `ujust` e a integração do projeto. A investigação partiu dos Gates [12.2](GATE-12-2-POLKIT-UUPD.md), [12.1](GATE-12-1-SECURITY-REVIEW.md), do [Lote 12](LOTE-12-RELIABILITY.md) e do [Gate 11C](GATE-11C-INTEGRATION.md).

| Entrada | Ativação e efeito na base auditada |
| --- | --- |
| `uupd.timer` e `uupd.service` | Link herdado em `timers.target.wants` e `enable uupd.timer` em `89-aurora.preset`. O timer solicita `network-online.target` e dispara por nome às 04:00, com recuperação de horários perdidos e atraso aleatório de até 15 minutos. O serviço roda `uupd` como root, inclui a atualização do SO e pode tentar novamente após falha. A configuração Aurora desabilita apenas o módulo Distrobox. |
| `uupd-manual.service` | Unidade estática, sem ativador periódico encontrado. `StartUnit` da Central passa pelo polkit. Uma dependência ou um pedido de root também pode iniciá-la. Roda `uupd --hw-check=false` e pode tentar novamente após falha. |
| `enthroned-system-update.timer` e `enthroned-system-update.service` | Timer persistente de 06:30, sem link de habilitação no build anterior. Aponta explicitamente para o serviço que chama o helper fixo de `bootc upgrade` e prepara deployment. O serviço também é acionável via `StartUnit` ou dependência. |
| `bootc-fetch-apply-updates.timer` e serviço homônimo | Timer e preset desabilitados na base. Em sistema OSTree, o serviço chama `bootc upgrade --apply --quiet`, com aplicação e possível reinício. |
| `rpm-ostreed-automatic.timer` e serviço homônimo | Timer e preset desabilitados na base. Em sistema OSTree, o serviço aciona `rpm-ostree upgrade --trigger-automatic-update-policy`. A base configura `AutomaticUpdatePolicy=stage`. O daemon D-Bus é ativável, e não foi encontrado um chamador automático adicional da operação de atualização. |
| `enthroned-bootc-status.service` e `enthroned-update-check.service` | O primeiro é acionado por `graphical.target` e publica `bootc status --format=json`. O segundo executa `uupd update-check`, consulta somente leitura. Os `ExecStartPost` do Gate 12.1 republicam status após sucesso de um serviço de atualização. Nenhuma dessas leituras aciona um updater. |

O gerador bootc executado com um marcador OSTree sintético ligou sincronização de contas, monitor de status e alvo de mudança de status no boot. A cadeia `.path` aponta para um alvo que sinaliza mudança de status. A auditoria não encontrou ligação dela com os serviços de upgrade. O timer de `systemd-sysupdate` e o serviço de habilitação de componentes estavam desabilitados, sem definições de transferência instaladas. Os sockets de notificação não disparam a transferência. Não havia PackageKit nem cron habilitado para atualizar o SO. A política do Gate 11C continua excluindo os backends RPM do Discover. Finalização de deployment já preparado, manutenção local do bootloader via `bootupctl`, atualização de certificados e telemetria ficaram fora do bloqueio de novos deployments.

## 2. Risco comprovado e bloqueio

Em um boot mínimo com systemd real na base fixada, o timer herdado disparou `uupd.service` com UID 0 mesmo sem arquivo de canal. O teste encurtou o horário e substituiu o comando por uma marca inerte. O caminho automático contorna a política da Central e o polkit por construção, pois o próprio gerenciador inicia o serviço como root.

O preset `20-enthroned-os-updates.preset` desabilita os quatro timers por precedência. O build também executa `systemctl --root=/ disable` para remover links herdados imediatamente e `systemctl --root=/ mask` para os quatro timers e cinco serviços mutáveis da tabela. As máscaras em `/etc/systemd/system` apontam para `/dev/null`. Uma tentativa direta recebe `Unit … is masked`, um `Requires=` falha, e um `Wants=` pode prosseguir sem executar a unidade bloqueada. O helper de build opera no filesystem da imagem, sem iniciar unidades. As definições upstream e os comandos dos serviços continuam disponíveis para auditoria. [systemctl(1)](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html) · [systemd.preset(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.preset.html)

A decisão é fixa para a imagem de canal fechado. Arquivo de canal ausente, canal de desenvolvimento e metadados que se declarem prontos ou publiquem uma origem não removem a máscara. A política futura exige aprovação explícita, origem oficial publicada e assinada, verificação da assinatura pelo bootc e validação das origens booted e staged durante a execução privilegiada. Só então cabe liberar o par Enthroned de staging. [Política de ativação](../operations/UPDATE-PIPELINE.md#depois-de-publicar-checklist)

## 3. Testes e compatibilidade

Os testes rodaram em contêineres descartáveis da base fixada, com o código montado somente leitura. Os testes de ativação e do publicador ficaram sem rede. A rede foi usada para obter dependências de teste dentro de contêineres separados. Os comandos de atualização do teste de ativação foram substituídos por marcadores, conferidos no systemd antes da primeira partida.

| Verificação | Resultado |
| --- | --- |
| `test-auto-update-safety.sh`, systemd como PID 1 | **9 grupos passaram.** O timer pré-correção acionou seu serviço inerte como root. O preset Enthroned desabilitou o timer mesmo com o preset Aurora presente. Com a máscara, um preset de prioridade ainda maior foi recusado. As nove partidas falharam com diagnóstico. Um link `Wants=` restaurado e um `Requires=` direto não executaram o serviço. |
| Canal e controle futuro | Ausência de metadados, `f1-dev`, `production_ready=true` isolado e fixture com referência oficial fictícia mantiveram o bloqueio. Retirar apenas as duas máscaras Enthroned dentro do contêiner permitiu o disparo inerte desse par, com uupd ainda mascarado. O teste simula a decisão de ativação. Assinatura, registro e origem reais ficam para outro gate. |
| Gate 12.2, polkit | **83 passaram.** `pkcheck` real exige autenticação para usuário comum e `wheel` sem sessão. O harness com atributos de sessão conserva `YES` apenas para `start` do `wheel` local e ativo nos dois serviços uupd, com a exceção preexistente de `empower`. O teste de partida como root confirma que até um pedido autorizado encontra a máscara. A regra polkit permanece byte a byte igual. |
| Leitura bootc e Gate 12.1 | **28 passaram** em `test-bootc-status-helper.sh`. O bootc fictício recebeu apenas `status --format=json`. Foram exercitados publicação, bloqueio entre escritores, descarte de cache antigo após erro e preservação dos `ExecStartPost`. As duas unidades de consulta puderam iniciar no teste com marcadores. |
| Central de Atualizações | **6/6 CTest** em build nativo do Settings, incluindo leitor bootc, integração do UpdateEngine e ciclo Flatpak. A cobertura inclui cache anterior, eventos sem confirmação, staging que requer reinicialização e falhas que continuam visíveis. `validate-settings.sh` teve **348** linhas PASS e `test-update-engine.mjs` teve **59**. |
| Flatpak, Bash e systemd | As duas unidades independentes de Flatpak aceitaram partida inerte e o timer de primeiro boot aceitou habilitação. `test-system-stability.sh` teve **65** PASS. `bash -n` na Aurora, ShellCheck e `systemd-analyze verify` passaram. |
| Discover | Instalação de teste com as exclusões do build, em contêiner descartável. `plasma-discover --listbackends` carregou `flatpak-backend`. PackageKit e os dois backends RPM excluídos pelo build ficaram ausentes. |

Reprodução do teste com a Aurora fixada já presente no Podman. Execute na raiz do repositório em Bash.

```bash
base=ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92
cid=$(podman run -d --rm --pull=never --network=none --systemd=always \
    -v "$PWD:/src:ro" --entrypoint /bin/bash "$base" \
    /src/scripts/test-auto-update-safety.sh --init)
trap 'podman stop --time 2 "$cid" >/dev/null 2>&1 || true' EXIT
for attempt in {1..20}; do
    podman exec "$cid" systemctl is-active --quiet gate-12-3.target && break
    sleep .25
done
podman exec "$cid" bash /src/scripts/test-auto-update-safety.sh
```

## 4. Arquivos

- `build_files/build.sh` chama `build_files/close-os-updates.sh` após instalar os pacotes do runtime.
- `system_files/usr/lib/systemd/system-preset/20-enthroned-os-updates.preset` define o preset da distribuição. O comentário do timer Enthroned registra seu estado na imagem.
- `scripts/test-auto-update-safety.sh` cobre ativação, dependências e preset com systemd real.
- `docs/operations/UPDATE-SYSTEM.md`, `docs/operations/UPDATE-PIPELINE.md` e este relatório registram a política e as evidências.
- O Graphify atualizou o índice de código em `graphify-out/`.

## 5. Próxima imagem, VM e riscos residuais

- **Próxima imagem.** Os quatro timers de atualização do SO aparecerão como `masked`, sem os links de habilitação herdados. A Central continua exibindo a mensagem de indisponibilidade do canal oficial e pode ler versão, origem, histórico e resultados legítimos de consulta. A suspensão do uupd interrompe também o agendamento dos componentes que ele agregava. Discover e os fluxos independentes do Flatpak seguem separados.
- **VM autorizada.** Conferir os nove `LoadState=masked` após o boot e a mesclagem de `/etc` em uma instalação bootc, inclusive com configuração herdada. Verificar ausência de agendamento em `list-timers`, publicação e leitura de `/run/enthroned/bootc-status.json` com SELinux enforcing, a mensagem da Central em Plasma e a política polkit em sessões reais `wheel` e comum. O contrato de `ExecStartPost` em boot real, assinatura e staging com origem oficial ficam para homologação futura separadamente autorizada.
- **Limites.** A política cobre as rotas systemd inventariadas para a base fixada. Ferramentas administrativas explícitas, como `sudo bootc`, `sudo uupd`, o rebase e um `unmask` manual, continuam sob controle do administrador. A receita upstream `ujust toggle-updates` pode imprimir uma confirmação depois de o `systemctl` recusar a unidade mascarada. O estado do systemd é a fonte para diagnosticar esse caso. Uma nova base exige repetir o inventário de ativadores antes da homologação.

Nenhuma imagem ou disco foi gerado. Nenhuma atualização real foi executada. H4, H5, VirtualBox e o canal de produção ficaram fora da execução. Sem commit ou push. Aguardando autorização para qualquer próxima etapa.
