# Gate 12.7 — Timeout de inicialização do input-remapper

19 de novembro de 2026 · America/Sao_Paulo

**GO para integrar a correção. NO-GO para homologação de boot, geração de H6 ou liberação para produção neste gate.** O systemd da Aurora fixada confirmou o limite efetivo de 90 s. A próxima VM autorizada deve confirmar o comportamento durante o boot e o funcionamento dos remapeamentos.

## Configuração

A Aurora herdava o padrão global de **45 s**. Na H5, cinco dos seis boots iniciaram o serviço e um excedeu o limite antes de o daemon adquirir `inputremapper.Control`. Nos boots lentos bem-sucedidos, a inicialização levou entre 26,9 e 32 s. Gate 12.6, seção 4 (`GATE-12-6-H5-DIAGNOSTICS.md`, evidência local), [Gate 12.5, seção 3](GATE-12-5-SYSTEM-STABILITY.md#3-input-remapper)

A imagem instala `/usr/lib/systemd/system/input-remapper.service.d/00-enthroned-start-timeout.conf` pela cópia existente de `system_files/`. O arquivo define uma diretiva da seção `[Service]`.

```ini
[Service]
TimeoutStartSec=90s
```

O drop-in `00-enthroned-start-timeout.conf` é lido antes de `service.d/10-timeout-abort.conf`, que define `TimeoutStopFailureMode=abort`. O padrão global continua em 45 s. Em `/etc/systemd/system/input-remapper.service.d/`, um arquivo de mesmo nome substitui o da imagem. Para nomes distintos, a última atribuição em ordem lexicográfica prevalece. O nome `override.conf` usado por padrão em `systemctl edit` é lido depois do arquivo Enthroned. [Manual systemd.unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)

## Arquivos

- Novo [drop-in de timeout](../../system_files/usr/lib/systemd/system/input-remapper.service.d/00-enthroned-start-timeout.conf).
- [build_files/build.sh](../../build_files/build.sh) normaliza o modo do diretório para `0755` e o do drop-in para `0644`. O contexto Windows apresentou modo `0777` no contêiner de teste.
- Este relatório e os artefatos gerados pela atualização do índice de código em `graphify-out/`.

O backup pontual em `output/gate-12-7-backup-20261119/` contém o script de build original e as versões anteriores dos arquivos preexistentes do índice alterados pela atualização. Os hashes SHA-256 das cópias correspondem às versões anteriores.

## Verificações

Aurora local `ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`, systemd `262.1-1.fc45`. Os contêineres Podman foram descartáveis, com `--rm --pull=never --network=none`, código montado somente leitura e sem `/dev/input` ou `/dev/uinput`. Para medir as propriedades efetivas, o systemd iniciou como PID 1 em um target de teste isolado. O input-remapper permaneceu inativo, com `ExecMainPID=0`.

| Verificação | Resultado |
| --- | --- |
| Sintaxe e integração da cópia | `bash -n build_files/build.sh` e `systemd-analyze --man=no --recursive-errors=no verify input-remapper.service` passaram. O teste executou a cópia e os dois comandos de permissões do build com o drop-in no estágio simulado. Modos finais `0755` e `0644`, ambos de `root:root`. |
| Timeout e precedência | `systemctl show` reportou `TimeoutStartUSec=45s` na base e `1min 30s` com o drop-in. A lista efetiva inclui o arquivo Enthroned e `10-timeout-abort.conf`. O modo de falha na parada permaneceu `abort`. |
| Configuração administrativa | Um `override.conf` com 77 s venceu o valor da imagem. Um arquivo de mesmo nome em `/etc` também produziu 77 s e substituiu o caminho de fornecedor na lista efetiva. Remover o override de teste restaurou 90 s. |
| Unit e habilitação | `Type=dbus`, `BusName=inputremapper.Control`, fragmento original e conjuntos de dependências e ordenação coincidiram antes e depois. `UnitFileState=enabled` e `UnitFilePreset=enabled`. O link de `default.target.wants`, os presets systemd e as regras udev permaneceram idênticos. |
| TuneD, Btrfs e montagens | O comparativo encontrou os mesmos parâmetros das units TuneD, arquivos de perfil, inventário RPM de TuneD/Btrfs e tabela de montagens do contêiner. O comparativo por hash no projeto confirmou a preservação do layout de disco. |
| Gate 12.1 | `test-bootc-status-helper.sh` passou 28 verificações com bootc simulado, incluindo publicação, exclusão de cache antigo e preservação dos drop-ins do publicador. `test-system-stability.sh` saiu com código 0. |
| Gate 12.2 | 20 consultas passaram com `pkcheck` e polkit real, usando o D-Bus da Aurora em contêiner. Outras 63 passaram no harness de atributos de sessão executado no Node do host sobre os 26 arquivos de regras da Aurora e do Enthroned, com zero erros de carga. |
| Gate 12.3 | Os nove grupos de `test-auto-update-safety.sh` passaram com o novo drop-in presente. Os nove bloqueios de units impediram as partidas previstas. O teste usou marcadores inertes no lugar dos comandos de atualização. |
| Gate 12.4 | `validate-settings.sh` registrou 354 linhas PASS na primeira execução e 357 após as edições paralelas do Settings. Como a base local não traz Node, a suíte do Settings rodou no host com 517 PASS e 0 FAIL em ambas as rodadas. O espelho do UpdateEngine passou 59 verificações. |

A comparação por SHA-256 confirmou a preservação dos arquivos preexistentes de política, do backend e dos testes dos Gates 12.1–12.4. Edições paralelas em QML e no CMake do Settings foram preservadas. A validação repetiu a suíte do Settings e o espelho do UpdateEngine sobre os arquivos atuais. Os 881 arquivos do diretório H5 coincidiram em tamanho e horário de modificação com o inventário inicial. Os contêineres do Gate 12.7 foram removidos, o digest permaneceu igual e o contêiner paralelo `gate131` foi preservado. A validação ficou sem build integral, atualização real, execução do VirtualBox, commit ou push.

## Trade-off e homologação

O limite maior permite que uma inicialização lenta adquira o nome D-Bus depois de 45 s. Se o daemon travar, a espera da unit pelo timeout pode durar até 90 s, até 45 s a mais. O contêiner verifica a configuração carregada. A próxima VM autorizada precisa confirmar tempo de partida, `Result`, aquisição de `inputremapper.Control` e funcionamento de um preset de remapeamento, inclusive de acessibilidade. Os CTests nativos ficaram fora desta rodada.
