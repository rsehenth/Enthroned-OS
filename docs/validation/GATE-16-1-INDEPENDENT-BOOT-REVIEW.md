# Enthroned OS — Gate 16.1: revisão independente das otimizações de boot

19 de novembro de 2026 · America/Sao_Paulo

**GO para integrar a versão corrigida do Gate 16 na próxima imagem de homologação.** A versão original recebeu **NO-GO** por remover a parada ordenada do input-remapper e por aceitar alterações não relacionadas no fragmento upstream do TuneD. A integração tem evidência de ordenação e proteção contra regressões no systemd da Aurora fixada. A validação de desempenho, energia e acessibilidade depende da homologação em boot real.

## 1. Base da revisão

Foram lidos os relatórios Gate 16, H6 e Gate 12.6 (internos, não publicados neste repositório) e o [Gate 12.7](GATE-12-7-INPUT-REMAPPER.md). As unidades, drop-ins, script de build, suíte do gate e arquivos dos RPMs foram conferidos diretamente. O teste usou a Aurora local `ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`, com systemd `262.1-1.fc45`, TuneD e tuned-ppd `2.28.0-1.fc45` e input-remapper `2.2.1-2.fc45`. Os contêineres Podman eram descartáveis, sem rede, com systemd como PID 1 em `basic.target`, código montado somente leitura e sem `/dev/input` ou `/dev/uinput`.

## 2. TuneD

**Aprovado para integração com o guard corrigido.** O [override](../../system_files/etc/systemd/system/tuned.service) remove a ordenação em relação a `network.target`. No systemd efetivo, o serviço mantém `After=` para sysctl, D-Bus e polkit. Mantém `Requires=` para o broker e, por `Type=dbus`, para `dbus.socket`. Sysctl e polkit são dependências de ordenação quando seus jobs estão na transação. As unidades retêm seus executáveis, nomes D-Bus, conflitos com outros gerenciadores e dependências padrão. `tuned-ppd.service` continua requerendo e esperando pelo TuneD. `multi-user.target` e `graphical.target` continuam esperando pela cadeia de energia. O fragmento de tuned-ppd declara `Before=display-manager.target`, e o grafo verificado carrega `plasmalogin.service` separadamente. A prontidão do target, do nome D-Bus e do greeter deve ser medida separadamente no boot.

Os perfis `balanced` e `balanced-battery` da Aurora fixada não têm diretivas de rede. O `ppd.conf` também mapeia `power-saver` para `powersave` e `performance` para `throughput-performance`, quando oferecido pelo hardware. O primeiro chama `enable_wifi_powersave` em seu `script.sh`, que enumera interfaces presentes e tenta `iw`, `iwpriv` ou sysfs. O segundo ajusta `net.core.somaxconn` via sysctl, um ajuste global. `network.target` indica que a pilha de gerenciamento de rede iniciou e não garante que uma NIC esteja configurada ou conectada. Antecipar o TuneD também retira a ordem inversa de parada em relação a esse target. Um adaptador ainda ausente na execução do script de economia ou uma configuração aplicada depois pelo NetworkManager pode afetar o estado final. O hotplug do plugin `net` cobre os ajustes desse plugin, e o script de Wi-Fi precisa de confirmação própria. O caminho comum `balanced` e os contratos D-Bus foram confirmados no escopo estático. Wi-Fi, Ethernet, docks, perfis de rede personalizados e transições AC/bateria exigem hardware. [Documentação de network.target](https://wiki.freedesktop.org/www/Software/systemd/NetworkTarget/), [código do TuneD](https://github.com/redhat-performance/tuned)

**Guard e bootc.** O guard anterior aceitava o fragmento com uma nova diretiva `ProtectSystem=full` porque `After=` continuava igual. Nesse caso o fragmento de `/etc` ocultaria o novo hardening. O [guard compartilhado entre build e teste](../../build_files/verify-tuned-unit.sh) reconstrói o fragmento esperado a partir do override, recoloca a aresta original e compara o arquivo inteiro com o RPM. O caso positivo aceita a Aurora fixada e o negativo rejeita a diretiva adicionada, sem modificar o RPM.

Um drop-in systemd pode acrescentar dependências, mas não apagar a entrada `After=network.target` do fragmento. A substituição inteira em `/etc/systemd/system/` tem a precedência esperada, preserva o arquivo do RPM e permite reversão do default pela imagem. O local é válido no bootc, com o custo de `/etc` passar por merge de três vias. Uma edição administrativa pode sobreviver a uma atualização e continuar prevalecendo. O guard cobre o fragmento principal no build. Mudanças em drop-ins upstream, perfis ou unidades associadas precisam da suíte e de nova revisão quando a base mudar. A checagem de precedência e reversão num deployment atualizado fica para a homologação. [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html), [configuração em imagens bootc](https://bootc.dev/bootc/building/guidance.html)

## 3. Input-remapper

**Aprovado para integração com as dependências restauradas.** A Aurora habilita a unit em `default.target.wants` e `default.target` é alias de `graphical.target`. O systemd adicionava `After=input-remapper.service` ao target e esperava por `inputremapper.Control` ou pelo timeout. A correção mantém `Wants=input-remapper.service` e retira essa espera implícita sem adiar o início do daemon para depois do target. [systemd.target(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.target.html)

| Propriedade efetiva | Aurora original | Gate 16 original | Gate 16.1 |
| --- | --- | --- | --- |
| `graphical.target` puxa o daemon | Sim | Sim | Sim |
| `graphical.target` espera o daemon | Sim | Ausente | Ausente |
| Daemon requer `sysinit.target` | Sim | Ausente direto | Sim |
| Daemon ordenado após `sysinit.target basic.target` | Sim | Arestas diretas ausentes | Sim |
| Daemon com `Before=shutdown.target` e `Conflicts=shutdown.target` | Sim | Ambas ausentes | Ambas restauradas |
| `TimeoutStartUSec` | 45 s | 90 s | 90 s |

O [drop-in corrigido](../../system_files/usr/lib/systemd/system/input-remapper.service.d/01-enthroned-default-deps.conf) recoloca as quatro diretivas que fornecem as cinco arestas padrão de inicialização e parada. O conflito enfileira a parada no shutdown e a ordenação faz o target esperar por ela. A unidade mantém a parada normal por grupo de controle, timeout de parada de 45 s e política Fedora preexistente. A dependência e a ordenação de `dbus.service` e `dbus.socket` também permanecem. Na Aurora fixada, `dbus.socket` está depois de `sysinit.target`, e o broker está antes de `basic.target`. Depender do broker preservava parte da cadeia indiretamente no Gate 16 original, mas não preservava `After=basic.target` nem a parada. [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)

O disparo de coldplug por `systemd-udev-trigger.service` vem antes de `sysinit.target`. O `udevadm trigger` da unit não usa `--settle`. Dispositivos e regras ainda podem aparecer depois. As regras de hotplug e de dispositivo virtual, o binário, o nome D-Bus e o [drop-in de 90 s](../../system_files/usr/lib/systemd/system/input-remapper.service.d/00-enthroned-start-timeout.conf) foram preservados. Não foi incluída uma espera global por udev. [udevadm(8)](https://www.freedesktop.org/software/systemd/man/latest/udevadm.html)

**Login e acessibilidade.** O greeter tem sua própria ordenação, sem dependência explícita do input-remapper antes ou depois desta alteração. A perda comprovada é a garantia de que o daemon já concluiu a partida quando `graphical.target` é atingido. Um login rápido pode executar o autostart com o daemon ainda em ativação. Foi confirmado no RPM que `input-remapper-autoload.desktop` executa `stop-all && autoload`, com `Daemon.connect(fallback=False)` no cliente. Se o primeiro comando falhar, o autoload da sessão é pulado e a entrada não agenda nova tentativa. A chegada posterior do nome pode deixar presets indisponíveis até uma nova ação de autoload. O teste de CLI no contêiner encontrou o barramento do sistema indisponível e não valida essa corrida com uma sessão KDE real. A H5 comprovou entrada básica de teclado e mouse com o daemon falho, sem presets configurados. Presets de acessibilidade, mouse e controles requerem validação no primeiro login, inclusive com dispositivos Bluetooth ou USB conectados depois. Fonte: Gate 12.6, seção 4 (relatório interno).

Um drop-in com `After=graphical.target` e dependências padrão é uma alternativa que suprime a espera implícita pelo sentido oposto de ordenação. Ele empurra a partida para depois do target, ampliando a janela em que um login rápido pode encontrar o daemon indisponível. A versão revisada restaura a ordenação de partida da base e preserva a execução em paralelo.

## 4. Segurança e limites de escopo

- O comparativo binário com `.backup-gate16` confirmou os mesmos arquivos de políticas polkit, presets e unidades de atualização, configuração do canal, primeiro boot, provisionamento Flatpak, Settings, Welcome, ações e personalização. O `Containerfile`, o layout de disco e a configuração de imagem coincidem com o snapshot. Os 516 hashes do manifesto do backup foram verificados.
- O teste executou `close-os-updates.sh` com `systemctl --root=/` no filesystem do contêiner, com as unidades próprias presentes. As **9/9** unidades retornaram `masked`, incluindo `uupd.timer`, `uupd.service`, `uupd-manual.service` e os pares `.timer/.service` de `bootc-fetch-apply-updates`, `enthroned-system-update` e `rpm-ostreed-automatic`. Não houve chamada de atualização.
- O patch não muda política, relabel ou configuração de SELinux, nem introduz escrita em `/usr` no sistema instalado. A H6 anterior às otimizações registrou SELinux Enforcing e `bootc status` funcional. O estado de runtime, os labels da imagem final e a montagem imutável exigem validação no novo deployment. Evidência: relatório interno da H6; [filesystem bootc](https://bootc.dev/bootc/bootc-filesystem.7.html)
- A retirada da espera muda o significado de `graphical.target`. O daemon segue habilitado, com seu timeout, logs e resultado próprios. Num target isolado, uma unit de teste carregou o mesmo drop-in de ordenação e permaneceu `activating` após o target ficar ativo. Ao expirar, `Result=timeout` e a unit apareceram em `systemctl --failed`.

## 5. Alterações e verificações

O [build](../../build_files/build.sh) invoca o guard de fragmento inteiro, o [override TuneD](../../system_files/etc/systemd/system/tuned.service) só teve o comentário atualizado e o [drop-in do input-remapper](../../system_files/usr/lib/systemd/system/input-remapper.service.d/01-enthroned-default-deps.conf) repõe as dependências padrão. A [suíte Gate 16](../../scripts/test-gate16-boot-order.sh) chama o guard real, testa drift fora de `After=`, confere a inicialização e a parada do input-remapper e torna fatal uma regressão de ordenação. A versão antiga registrava `PASS` após listas com `&&` e testes invertidos com `!`, nos quais o `errexit` do Bash podia ignorar falhas.

| Verificação | Resultado |
| --- | --- |
| Suíte Gate 16 original, em contêiner novo | 21/21, exit 0 |
| Novas asserções de dependências contra o drop-in original | 22 passaram, 4 falharam, exit 4 |
| Guard original com alteração em `[Service]` | Aceitou indevidamente. O guard corrigido rejeitou a mesma alteração. |
| `bash -n`, `systemd-analyze verify`, propriedades efetivas e suíte final | 26/26, exit 0 |
| Reinserção provisória de `graphical.target After=input-remapper.service` | 25 passaram, 1 falhou, exit 1 |
| Timeout injetado em unit isolada | Target ativo durante a ativação, falha visível depois |
| Máscaras e snapshot | 9/9 máscaras efetivas no filesystem, 516/516 hashes do backup |

A VM H6, os backups e as evidências de homologação, o Lote 15 e a preparação do GitHub foram preservados. Os dois contêineres foram removidos. A revisão usou a imagem local existente. Nenhuma imagem ou disco foi gerado e nenhum commit ou push foi feito.

A atualização de código do Graphify reaplicou os ignores atuais e arquivou o índice anterior no diretório datado `graphify-out/2026-11-19/`, que já existia. A atualização cobre a extração estrutural de código.

## 6. Desempenho e homologação

**Comprovado no systemd.** O TuneD pode sobrepor sua partida à do NetworkManager. O target gráfico pode concluir sem aguardar o nome D-Bus do input-remapper. O tamanho do ganho depende do restante da cadeia, da carga de I/O, da sessão e dos demais jobs concorrentes.

**Estimativa histórica.** A H6 registrou `graphical.target` em **72,413 s** e o total de **1 min 40,380 s** no boot 2. O Gate 16 projetou cerca de **10 s** a menos no target em condições equivalentes. Nem os **9,689 s** do NetworkManager nem os **30,560 s** do input-remapper são parcelas que se possam subtrair ou somar diretamente. O alvo do proprietário continua sendo **desktop utilizável em até 35 s**, com Aurora original como controle no mesmo hardware.

**Primeiro boot.** A H6 registrou **7 min 20,014 s** totais. A causa permanece indeterminada. O timer Enthroned `OnBootSec=8min` é posterior ao marco gráfico registrado de **6 min 50,649 s**. Ele é distinto da unit herdada `flatpak-preinstall.service` e, sozinho, não permite atribuir a lentidão a nenhuma delas. Falta uma cadeia crítica contemporânea do primeiro boot.

### Condições da homologação da próxima imagem

1. Medir primeiro boot e boots limpos comparáveis. Registrar cadeia crítica, monotônicos e journal. Cronometrar separadamente o target gráfico, o greeter, o login e o Plasma utilizável. Comparar Aurora e Enthroned no mesmo hardware com procedimento de login equivalente.
2. Em laptop, ligar em AC e bateria, trocar perfis no Plasma, verificar `tuned-adm active`, transição AC/bateria, Wi-Fi, Ethernet e dock/hotplug. Conferir o estado de economia de Wi-Fi com `powersave` ativo no boot, após conexão e após reconectar.
3. Testar um preset de acessibilidade no primeiro login e em login imediato, com teclado, mouse ou controle representativo. Registrar aquisição de `inputremapper.Control`, resultado do autoload, presença do preset, comportamento de fallback da entrada e parada em reboot/shutdown.
4. Confirmar as nove máscaras, SELinux Enforcing, `bootc status`, imutabilidade do deployment e precedência de `/etc`. Conferir a lista de units falhas também após a janela de 90 s e a partida do timer pós-boot.

