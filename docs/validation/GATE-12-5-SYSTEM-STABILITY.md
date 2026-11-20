# Gate 12.5 — Estabilidade do sistema e desempenho de inicialização

19 de novembro de 2026 · America/Sao_Paulo

**GO para continuar a estabilização com coleta dirigida em homologação autorizada.** `/var` somente leitura, o atraso do TuneD e o timeout do input-remapper continuam abertos. **NO-GO para mudanças de montagem, ordenação ou ativação com a evidência atual.** Este gate não autoriza H6 ou produção.

Foram consultados H5 (`H5-VM-HOMOLOGATION.md`, evidência local), [Gate 12.4](GATE-12-4-UPDATE-STATE-CONSISTENCY.md), [Gate 12.3](GATE-12-3-AUTO-UPDATE-SAFETY.md), [Gate 11C](GATE-11C-INTEGRATION.md) e [Lote 11A](LOTE-11A-SYSTEM-STABILITY.md). Os nomes `boot*/s-*.png` e `VBox-*.log` abaixo são relativos a `output/homologacao-5-20261119/evidence/`. As capturas são recortes do journal convidado. A H5 registra `~/err.txt` e `~/err1.txt` dentro da VM. Esses arquivos e os journals binários ficaram fora da análise, que usou o acervo já exportado.

## 1. `/var` somente leitura

- **Confirmado na H5.** O primeiro boot foi interrompido pelo host durante o provisionamento. Na retomada, o kernel registrou `start tree-log replay` em `/dev/sda4`. `flatpak-preinstall.service` concluiu a instalação de sistema às 05:59:44. Às 06:08 a gravação falhou e o mount de `/var` aparecia como Btrfs `ro`, `subvolid=256`, `subvol=/root`, `space_cache=v2`. Às 06:10:43 o Podman também recebeu `read-only file system` ao abrir o lock em `/var/home`. A escrita voltou no boot 2 após o reboot limpo. Os boots 3 e 4 não registraram recorrência. A instalação bem-sucedida às 05:59:44 e o mount posterior delimitam observações distintas. Faltam flags de montagem no instante da gravação e no namespace do serviço para determinar quando ou como o estado mudou. Evidências `boot1-restart/s-kernel-btrfs.png`, `s-remounting.png`, `s-mount-check.png`, `s-ostree-status.png` e `boot2/s-critical-chain.png`.
- **Comportamento esperado de recuperação.** O replay do tree-log é compatível com a interrupção e pode ocorrer mesmo em montagem Btrfs `ro`. O recorte Btrfs não contém abort de transação ou erro de I/O do dispositivo. A busca por `Remounting` vazia não exclui mensagens `Remounted`, falhas fora do filtro ou um remount sem mensagem equivalente. Os `Input/output error` recorrentes de `agetty` referem-se ao terminal serial. A imutabilidade de `/usr` e a configuração da base `composefs.enabled=yes` com `sysroot.readonly=true` são esperadas. No deployment OSTree, `/var` deve ficar gravável para o estado persistente. A leitura exclusiva observada após a inicialização segue sem explicação. [Manual Btrfs](https://btrfs.readthedocs.io/en/stable/btrfs-man5.html#mount-options), [Deployments OSTree](https://ostreedev.github.io/ostree/deployment/)
- **Layout e integração herdada.** A receita H5 usou `image-builder-cli` com `--bootc-default-fs btrfs`. A configuração local declara tamanho mínimo de `/` e nenhuma montagem separada de `/var`. A captura de `/etc/fstab` mostra a entrada de `/boot` em `ro` e nenhuma entrada de `/var`. A linha de kernel contém `rootflags=subvol=/root`, `rw` e `ostree=…`. A montagem observada é compatível com o bind da área persistente do stateroot no Btrfs da raiz. A captura não inclui `FSROOT` nem as flags VFS e do superbloco em colunas separadas. Na base, `ostree-remount.service` é habilitado por `local-fs.target`, condicionado a `ostree=` e ordenado depois de `var.mount` e `systemd-remount-fs.service`, antes de `local-fs.target` e do flush do journal. O código upstream do remount tenta manter `/var` gravável e pode emitir `Remounted`. `systemd-remount-fs` atua sobre `/`, `/usr` e filesystems de API do kernel. `ostree-finalize-staged.service` depende de um boot OSTree e chama a finalização em `ExecStop`. O acervo não vincula nenhuma dessas rotas ao incidente. Evidências `boot1-restart/s-fstab-tail.png`, `s-cmdline.png` e `s-mount-check.png`. Receita H5 (`../../output/homologacao-5-20261119/build-disks-h5.sh`, evidência local), [Layout local](../../disk_config/disk.toml), [Remount do systemd](https://www.freedesktop.org/software/systemd/man/latest/systemd-remount-fs.service.html), [Código upstream do OSTree](https://github.com/ostreedev/ostree/blob/main/src/switchroot/ostree-remount.c)
- **Flatpak e atribuição.** `flatpak-preinstall.service` é herdado da Aurora, chama `flatpak preinstall -y` após `network-online.target` e consumiu 2min43,586s na cadeia do boot de retomada. É distinto do serviço `enthroned-firstboot-flatpaks.service`. No boot 2, com escrita restabelecida, faltava um objeto do repositório Flatpak de sistema durante o checkout do runtime exigido pelo Brave. A H5 documenta o reparo administrativo autorizado. O objeto ausente é uma consequência compatível com a interrupção e explica a falha do checkout, sem evidência de que o Flatpak tenha alterado o mount. O defeito do Enthroned que registrava sucesso diante dessa falha já foi tratado nos Lotes 11A e 11C. O serviço Enthroned de status bootc consulta o deployment após o alvo gráfico e publica em `/run`. A busca no build, unidades, scripts e layout locais não encontrou uma regra de montagem de `/var`. **Classificação do `ro`**. Há evidência insuficiente para atribuir a causa à recuperação normal, à Aurora ou ao Enthroned. Evidências `boot1-restart/s-critical-chain.png`, `s-readonly-grep.png`, `boot2/s-firstboot-journal.png` e `s-repair-done.png`. [Gate 11C, seções 3 e 8](GATE-11C-INTEGRATION.md)

## 2. TuneD e tempo de inicialização

| H5 | `NetworkManager.service` | `tuned.service` | `tuned-ppd.service` | `graphical.target` |
| --- | ---: | ---: | ---: | ---: |
| Boot 2 | 22,007 s | 28,575 s | 4,820 s | 97,005 s |
| Boot 3 | 8,782 s | 22,149 s | 0,471 s | 61,047 s |
| Boot 4 | Sem medida da unit | Sem medida da unit | Sem medida da unit | 57,481 s |

- **Ordenação demonstrada.** Nos boots 2 e 3, a cadeia passa por `NetworkManager.service` → `network.target` → `tuned.service` → `tuned-ppd.service` → `multi-user.target` → `graphical.target`. A base inclui TuneD e tuned-ppd 2.28.0 habilitados. `NetworkManager` é `Type=dbus`, ordenado antes de `network.target`. `tuned` é `Type=dbus`, requer D-Bus e começa após `network.target`, `systemd-sysctl`, D-Bus e polkit quando essas unidades participam da transação. `tuned-ppd` é `Type=dbus`, requer `tuned`, inicia depois dele e se ordena antes de `multi-user.target`. Também declara `Before=display-manager.target` e tem entrada D-Bus para a API de perfis de energia. `NetworkManager-wait-online.service` espera `network-online.target` ser demandado para entrar nessa transação de rede e aparece no caminho do Flatpak no boot de retomada. A cadeia do TuneD nos boots limpos passa por `network.target`. Os 22–29 s correspondem à ativação da própria unit até a prontidão D-Bus. O tempo de NetworkManager vem antes. Nenhuma das duas medidas identifica o trabalho interno que consumiu o intervalo ou o ganho de uma reordenação. Evidências `boot2/s-critical-chain.png`, `boot3/s-chain-failed.png` e `boot4/s-analyze2.png`. [Limites de `systemd-analyze`](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html)
- **Perfil e VirtualBox.** No contêiner, `/etc/tuned/active_profile` e `profile_mode` estão vazios. As regras automáticas incluem `atomic-guest` para sistema atomic reconhecido em VM e `virtual-guest` como regra genérica de VM. O padrão da interface PPD é `balanced`, com mapeamento `balanced-battery` em bateria. O perfil efetivo usado na H5 não foi capturado. Os rótulos Classic e Modern na H5 são do desktop. A base desativa a espera inicial explícita de settle do TuneD com `startup_udev_settle_wait=0`. A H5 usava E1000 em NAT, 4 vCPU e 8 GiB. Os logs do host mostram 7.888 MiB disponíveis na abertura do primeiro log e 20.220 MiB na abertura do arquivo que contém a retomada e os três reboots. Esses números são instantâneos, com cobertura diferente das estimativas do relatório H5. Contenção, disco, rede virtual e seleção/aplicação de perfil seguem variáveis a medir. Não há atribuição dos atrasos a uma delas. Evidências `VBox-boot3-boot2-restart.log` e `VBox-boot4-actual.log`, linhas 2, 11 e 998, e configuração da H5 (`H5-VM-HOMOLOGATION.md`, evidência local).
- **Conclusão.** A ordenação e a integração PPD vêm da base Aurora/Fedora. O custo observado pertence aos boots medidos na H5. A causa do custo interno e uma otimização segura seguem sem comprovação. Alterar ordem ou política via drop-in poderia afetar a aplicação de perfis em NICs físicas, o controle de energia no Plasma e as transições AC/bateria. Manter as units e medir primeiro em VM controlada e em hardware representativo.

## 3. Input-remapper

- **Falha e origem.** A captura `boot2/s-failed-blame.png` registra 45,012 s e `boot2/s-failed.png` mostra `input-remapper.service` como `failed`. `boot2/s-journal-noagetty.png` mostra a falha do serviço e, cerca de 11 s antes, um `udevadm` com timeout de fila. Não há correlação de PID, invocação ou dispositivo que ligue os dois eventos. A H5 registrou zero units falhas na retomada e nos boots 3 e 4. O caminho crítico mostrado pelo systemd não permite descartar impacto de um job que expirou. H5, métricas dos boots (`H5-VM-HOMOLOGATION.md`, evidência local), [Limites de `critical-chain`](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html)
- **Ativação e timeout.** O RPM `input-remapper-2.2.1-2.fc45` é pré-instalado na base. `89-aurora.preset` e `default.target.wants/input-remapper.service` confirmam habilitação Aurora. A unit exige D-Bus, inicia depois dele, usa `Type=dbus` e aguarda `inputremapper.Control`. O código do pacote registra esse nome após construir o daemon. A unit de fornecedor não tem timeout próprio nem `Condition*` de hardware ou virtualização. A configuração do gerenciador no contêiner mostra 45 s como padrão compilado, valor compatível com o episódio. O timeout efetivo com todos os drop-ins do convidado e o ponto da espera precisam de captura. O pacote também tem autoload via regra udev e via XDG no login. [Uso e autoload do input-remapper](https://github.com/sezanzeb/input-remapper/blob/main/readme/usage.md)
- **Necessidade e alcance.** A busca no projeto e as consultas RPM de dependência direta e recomendação não encontraram consumidor obrigatório do Enthroned. Teclado e mouse básicos funcionaram na H5 para login e interação mesmo com a falha no boot 2. O pacote mantém presets opcionais de teclados, mouse e controles com injeção via `uinput`. Retirá-lo ou condicionar sua partida pode quebrar perfis existentes, inclusive de acessibilidade. O tablet USB virtual da H5 e os eventos de udev são candidatos a correlação. A falha também pode ocorrer em hardware real se houver espera de dispositivo, permissões, disputa na inicialização ou atraso no D-Bus. Esses mecanismos precisam ser distinguidos por journal e inventário de dispositivos. **Classificação**. Origem e habilitação herdadas comprovadas. Causa do timeout e dependência do VirtualBox em aberto.

## 4. Verificações e alterações

- Leitura das quatro referências solicitadas, consulta do grafo existente pelo `graphify query` instalado, busca dirigida nas receitas de imagem, scripts e units do projeto, inspeção das capturas por OCR e correlação com os logs do VirtualBox. A chamada inicial pelo `uv` encontrou bloqueio de escrita no cache. O executável local consultou o grafo com sucesso. A verificação do relatório conferiu os destinos de 10 links locais e os nomes de 17 arquivos de evidência.
- Podman no Ubuntu WSL2 inspecionou a Aurora local `ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92` em contêineres descartáveis com `--rm --read-only --pull=never --network=none`. As consultas cobriram propriedade de units via RPM, habilitação via `systemctl --root=/ is-enabled`, presets, dependências, defaults, scripts dos daemons, configuração de perfis e regras udev. A base registra systemd 262.1, OSTree 2026.4, bootc 1.17.1, NetworkManager 1.58.1 e Flatpak efetivo 1.18.4. O contêiner conferiu os artefatos da imagem, sem boot OSTree, PID 1 do convidado ou dispositivos do VirtualBox. O inventário final do Podman estava vazio, e Ubuntu e Docker Desktop apareciam parados no WSL.
- Nenhum defeito novo recebeu correção de código. O bloco de coleta passou por `bash -n` na Aurora fixada, que também confirmou os executáveis e as opções de `findmnt` e `busctl` usadas. Sua execução em Linux convidado segue pendente. A comparação de conteúdo no projeto encontrou somente este relatório novo, e a conferência de tamanho e `mtime` dos 814 arquivos do diretório H5 coincidiu com o inventário anterior à edição. Sem build da distribuição, regressão de código, suíte do Update Center, execução do VirtualBox, modificação de discos, atualização real, commit ou push.

## 5. Coleta somente leitura para a próxima homologação

Use uma VM de teste que tenha autorização própria. Preserve a H5. Execute o bloco em Bash numa sessão com acesso de leitura ao journal do sistema. Capture a saída do terminal no host autorizado. Colete logo após um boot limpo e, se o sintoma reaparecer espontaneamente, ainda no boot afetado e antes de um reboot normal. Anote o ID do boot, fase do provisionamento e condição do host. `journalctl --list-boots` identifica quais boots sobreviveram e o relógio monotônico permite ordenar eventos dentro de cada boot. Revise hostnames, UUIDs, nomes de redes e dispositivos antes de compartilhar.

```bash
export LC_ALL=C
boot_id=$(cat /proc/sys/kernel/random/boot_id)
printf '\nBoot atual: %s\n' "$boot_id"
uname -r
systemd-detect-virt
cat /proc/cmdline /etc/fstab
rpm -q systemd ostree bootc tuned tuned-ppd NetworkManager input-remapper flatpak

printf '\nMontagens e flags VFS e de superbloco\n'
for path in / /sysroot /var /var/lib/flatpak /var/home /boot; do
    printf '\n%s\n' "$path"
    findmnt --target "$path" -o TARGET,SOURCE,FSTYPE,FSROOT,VFS-OPTIONS,FS-OPTIONS
done
cat /proc/self/mountinfo /proc/1/mountinfo
if [ "$(findmnt -n -o FSTYPE -T /var)" = btrfs ]; then
    btrfs device stats /var
    btrfs subvolume show /var
fi
bootc status --format=json

printf '\nUnits, tempos monotônicos e dependências efetivas\n'
units=(var.mount sysroot.mount systemd-remount-fs.service ostree-prepare-root.service
       ostree-remount.service ostree-finalize-staged.service systemd-journal-flush.service
       NetworkManager.service NetworkManager-wait-online.service tuned.service
       tuned-ppd.service input-remapper.service systemd-udevd.service
       flatpak-preinstall.service enthroned-firstboot-flatpaks.service)
systemctl cat "${units[@]}"
systemctl show "${units[@]}" -p Id -p FragmentPath -p DropInPaths -p SourcePath \
    -p LoadState -p UnitFileState -p ActiveState -p Result -p InvocationID \
    -p After -p Before -p Wants -p Requires -p ConditionResult -p Type -p BusName \
    -p TimeoutStartUSec -p TimeoutStartFailureMode -p ExecMainCode -p ExecMainStatus \
    -p InactiveExitTimestampMonotonic -p ExecMainStartTimestampMonotonic \
    -p ActiveEnterTimestampMonotonic -p ExecMainExitTimestampMonotonic
systemctl show -p DefaultTimeoutStartUSec
systemctl --failed --no-pager
systemd-analyze time
systemd-analyze critical-chain graphical.target tuned.service tuned-ppd.service input-remapper.service
systemd-analyze blame

printf '\nPerfil de energia, atividade dos daemons e dispositivos de entrada\n'
for path in /etc/tuned/{active_profile,profile_mode,ppd_base_profile,ppd.conf} \
            /var/lib/enthroned-os/firstboot-flatpaks.status; do
    if [ -r "$path" ]; then
        printf '\n%s\n' "$path"
        cat "$path"
    fi
done
if [ -r /var/log/tuned/tuned.log ]; then tail -n 200 /var/log/tuned/tuned.log; fi
busctl --system --no-pager --acquired list
ls -l /dev/uinput /dev/input/event* /dev/input/by-path/
cat /proc/bus/input/devices

printf '\nJournals preservados e sequência de boot\n'
journalctl --list-boots --no-pager
for boot in "$boot_id" -1; do
    printf '\nBoot %s\n' "$boot"
    journalctl -b "$boot" -k --no-pager -o short-monotonic
    journalctl -b "$boot" --no-pager -o short-monotonic \
        -u var.mount -u sysroot.mount -u 'initrd*' -u 'ostree-*' -u 'bootc-*' \
        -u systemd-remount-fs.service -u 'systemd-fsck*' -u systemd-journald.service \
        -u systemd-journal-flush.service -u systemd-tmpfiles-setup.service \
        -u 'NetworkManager*' -u 'tuned*' -u input-remapper.service \
        -u 'systemd-udev*' -u dbus.service -u 'dbus-broker*' \
        -u flatpak-preinstall.service -u enthroned-firstboot-flatpaks.service
    journalctl -b "$boot" --no-pager -o short-monotonic --case-sensitive=no \
        -g 'remount|read.only|transaction abort|I/O error|uinput|input.remapper|udev.*timed out'
done
```

- **`/var`**. Compare flags em um boot limpo e em eventual incidente. `ro` apenas em `VFS-OPTIONS` aponta para o mount individual. `ro` também em `FS-OPTIONS` exige correlacionar o filesystem e o journal do kernel. Use `FSROOT`, fstab e `SourcePath` para localizar a origem da montagem. Compare mensagens do initrd, OSTree e journald antes do primeiro `EROFS`. Para atribuir à Aurora, compare com uma VM descartável da base fixada usando a mesma rota de instalação e o mesmo layout, se autorizada. Se houver `ro` em boot limpo, reclassifique como P1. O impacto também vale para hardware físico, onde a montagem pode impedir gravações de aplicativos, dados em `/var/home` e a persistência do próprio journal. Um evento espontâneo sem logs suficientes permanece inconclusivo. Evite remount, reparo, zeragem de contadores e desligamento forçado durante a coleta.
- **TuneD**. Colete ao menos três boots limpos comparáveis, com a mesma imagem, recursos, NIC, condição de host e estado do provisionamento. Registre cold boot ou reboot e compare medianas e amplitude do alvo gráfico e dos intervalos monotônicos das três units. Separe a duração de `NetworkManager` do intervalo entre `ExecMainStart` e prontidão D-Bus de cada daemon. Use os logs do TuneD para associar o atraso a seleção de perfil, plugin ou detecção de dispositivo. Compare com Aurora equivalente se o atraso persistir. Qualquer proposta de mudança de ordem deve demonstrar ganho com a mesma configuração e preservar perfis no Plasma, NIC física e perfis AC/bateria em hardware real.
- **Input-remapper**. Correlacione o `Result` e a invocação com o journal de D-Bus e udev. Verifique a presença do tablet, do teclado e de `/dev/uinput` e se `inputremapper.Control` chega a aparecer. Compare boots válidos e falhos com os mesmos dispositivos. Em hardware real, verifique teclado e mouse básicos, hotplug e um preset já configurado em teclado, mouse ou controle. Uma falha de remapeamento com impacto funcional merece prioridade mesmo quando a sessão gráfica abre.

O fechamento dos três diagnósticos depende dessas medições no convidado. O acervo atual sustenta a origem das units e os sintomas observados, sem demonstrar uma mudança de implementação segura.
