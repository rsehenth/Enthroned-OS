# Lote 9 — Auditoria e otimização do boot (2026-11-18)

Status: **SOURCE READY / STATIC VERIFIED**. Nenhuma build, OCI, QCOW2, VDI, ISO
ou VM foi gerada/ligada nesta rodada (por contrato). **Nenhuma medição de boot
foi executada dentro de uma VM**: os números abaixo vêm de logs do VirtualBox
do lado do host e de evidências das Homologações 2 e 3. O comportamento real de
systemd/kernel/initramfs/sessão continua **PENDENTE DE COLETA IN-VM**
(Homologação 4).

Base de evidência: `output/homologacao-3-20261117/` (relatório H3,
`Logs/VBox.log`, `VBox-boot.log`, screenshots e `.time.txt`),
`output/homologacao-2-20261117/` (`vm-boot-01.png` com o console do boot),
`output/homologacao-3-20261117/aurora-base-before.json` (base Aurora),
leitura do código upstream (systemd `units/ldconfig.service`,
plasma-workspace `startkde/systemd/`) e dos arquivos do repositório.

## 1. Mapa da sequência de boot

| Estágio | Componente | Origem |
| --- | --- | --- |
| Firmware/UEFI | VirtualBox EFI + Secure Boot | VirtualBox (host) |
| Bootloader | shim/GRUB do Fedora | base Aurora (intocado, ADR-0003) |
| Kernel | Linux 7.2.11-300.fc45 | base Aurora; `kernel.append` do blueprint só na VM de teste (mascara uupd) |
| initramfs | dracut `--no-hostonly --reproducible` | **gerado pelo Enthroned** em `build_files/build.sh` (identidade Enthroned no `initrd-release` verificada na build) |
| Root prepare | ostree/bootc prepare-root | base bootc |
| sysinit | `ldconfig.service`, tmpfiles, binfmt, etc. | base Fedora — ver §2 (ldconfig) |
| Multi-user | serviços padrão; **nenhuma unidade Enthroned habilitada aqui** | — |
| graphical.target | `display-manager.service` (plasmalogin, pacote `plasma-login-manager` da base) | base; aparência por `etc/plasmalogin.conf.d/10-enthroned.conf` (Enthroned) |
| Sessão Plasma | kwin_wayland, plasmashell, splash (`ksplashrc`), kscreen | base; temas/wallpapers Enthroned |
| Unidade user Enthroned | `enthroned-desktop-actions.service` (`Before=plasma-plasmashell.service`, `WantedBy=plasma-core.target`) | Enthroned (Lote 7.1) — reescrita idempotente do menu de contexto antes do plasmashell |
| Autostart XDG | `org.enthroned.files-setup.desktop` (fase 2, one-shot); plasma-setup (só 1º boot, OOBE); Welcome upstream suprimido (`plasma-welcomerc`) | Enthroned / base |
| Pós-login opcional | `enthroned-firstboot-flatpaks.timer` (T+8 min, Nice=15, IO idle) | Enthroned — fora da cadeia do boot |

Todos os alvos e presets acima foram verificados estaticamente (§9): nenhuma
unidade Enthroned está ligada a `sysinit/basic/multi-user/graphical.target`;
todo o trabalho de fundo corre por timers (`timers.target`) ou unidade de
usuário.

## 2. Diagnóstico dos erros/ocorrências

| ID | Mensagem/ocorrência | Componente | Momento | Causa | Consequência | Classificação | Correção | Evidência |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B9-001 | `Job ldconfig.service/start running (11s / no limit)` | `ldconfig.service` (glibc/systemd, base) — NÃO é unidade Enthroned | sysinit (antes do multi-user), bloqueando o boot | Unidade upstream: `Before=sysinit.target` + `ConditionNeedsUpdate=\|/etc` + `ConditionFileNotEmpty=\|!/etc/ld.so.cache` → roda e BLOQUEIA o 1º boot após cada deployment (e após cada atualização bootc), reconstruindo `/etc/ld.so.cache`; custo dominado pelo I/O do disco virtual | +11 s no 1º boot (e 1× após cada update); **não deve aparecer no 2º boot** (condição falsa → job pulado) | Comportamento esperado do Fedora Atomic; máscara proibida (quebraria o cache do linker pós-update) | Nenhuma no código. Monitorar: no 2º boot NÃO pode aparecer no blame/critical-chain (se aparecer, investigar `systemd-update-done`/mtime de `/etc/.updated`) | `output/homologacao-2-20261117/vm-boot-01.png` (console H2); unidade upstream `systemd/units/ldconfig.service` |
| B9-002 | `ConditionPathExists` dentro de `[Service]` em 4 unidades Enthroned | `enthroned-update-check`, `enthroned-flatpak-update`, `enthroned-rollback`, `enthroned-system-update` | sob demanda (não no boot) | systemd só honra condições em `[Unit]`; em `[Service]` a chave é ignorada com warning — as unidades rodariam **desprotegidas** e falhariam com 203/EXEC se o binário da base faltasse | Erro visível em vez de "skipped" limpo se `uupd`/`bootc`/`flatpak` não existir | **Erro real, comprovado por leitura** (descoberto pelo novo validador) | **CORRIGIDO**: condição movida para `[Unit]` nas 4 unidades | diff deste lote; `systemd.unit(5)` |
| B9-003 | Boot "lento" observado na H3 (kernel ~36 s; sessão a partir de T+116 s; OOBE utilizável T+120–180 s) | kernel + initramfs + userspace + OOBE | todo o boot | **Sem journal do guest → diagnóstico INCONCLUSIVO.** Hipóteses (não comprovadas): I/O do VDI sobre WSL2/NTFS; initramfs `--no-hostonly` grande (portabilidade × descompressão); firmware UEFI+Secure Boot do VirtualBox; OOBE (plasma-setup) no 1º boot; `NetworkManager-wait-online`/plymouth (candidatos padrão, sem evidência) | Primeiro boot demorado; 2º boot não medido | Hipótese ainda não comprovada | Nenhuma alteração de boot sem medição (contrato dos Lotes 6/7 mantido) | `output/homologacao-3-20261117/` (VBox logs, `.time.txt`, relatório H3 §7) |
| B9-004 | "Mensagens de erro" visíveis no console | console systemd (plymouth não visível no display VBox) | boot | Saída normal de serviços `[OK]` (sysupdate, binfmt, ldconfig, audit, NFS/RPC) rolando rápido | Cosmético; nada foi mascarado | Informativa (avaliada desde o Lote 6) | Nenhuma (não usar `quiet`/`splash` para escondê-las) | `output/homologacao-2-20261117/vm-boot-01.png` |

Nenhum erro de serviço Enthroned foi comprovado nos logs disponíveis. As
unidades e scripts próprios revisados neste lote não executam trabalho
síncrono no boot (§9).

## 3. Tempos observados (origem dos dados)

| Marca | Tempo | Origem | Confiabilidade |
| --- | --- | --- | --- |
| H3 — EFI pronto (boot args) | T+5 s | `Logs/VBox.log` (host) | alta (timestamp do hipervisor) |
| H3 — kernel guest ativo (vboxguest carregado) | T+20 s (log da VM) / ~36 s (relatório H3, `VBox-boot.log` da sessão headless) | VBox logs (host) | alta para cada sessão; as duas sessões divergem (~15 s) — usar os números in-VM da H4 como padrão |
| H3 — 1º componente gráfico de sessão (VBoxDRMClient) | T+58 s (log VM) / T+116 s (relatório H3) | VBox logs (host) | idem |
| H3 — OOBE utilizável | T+120–180 s | screenshots `.time.txt` | média (amostragem por screenshot) |
| H2 — power-on → VBoxClient | ≈50 s | `VBox.log` (Lote 6 §15) | alta |
| H2 — ldconfig.service | 11 s | console do boot (`vm-boot-01.png`) | alta (texto do systemd) |
| systemd-analyze / blame / critical-chain / failed / journal | **NÃO COLETADOS** | — | pendente in-VM (sem SSH/Guest Additions por design) |

Comparação H2×H3 de boot total: **sem baseline numérica na H2** — nenhuma
afirmação de ganho/regressão é possível; a H4 coleta nas duas condições
(1º e 2º boot).

## 4. Serviços problemáticos comprovados

1. **`ldconfig.service` (base, não Enthroned)** — único serviço com atraso
   comprovado em evidência (11 s), e está **na cadeia crítica** (unidade
   upstream tem `Before=sysinit.target`). Roda 1× por deployment. Não foi
   mascarado nem alterado (não é por conveniência; quebraria o cache do
   linker após atualizações bootc). Verificação na H4: ausente no 2º boot.
2. **Condições systemd mal posicionadas (código Enthroned)** — 4 unidades
   com `ConditionPathExists` em `[Service]` (ignorada pelo systemd).
   Corrigidas para `[Unit]` (B9-002).
3. **Nenhum serviço Enthroned é bloqueante do boot** — verificado
   estaticamente: `firstboot-flatpaks` (timer T+8 min, Nice/idle, offline-safe,
   sai 0), `update-check`/`system-update`/`rollback`/`flatpak-update`
   (on-demand/manual, sem `[Install]` para alvos de boot), `desktop-actions`
   (unidade de usuário, `Before=plasmashell`, sai 0), `files-setup`
   (autostart one-shot com marker, milissegundos).

`systemd-analyze blame` não foi usado como prova de causalidade: a única
unidade tratada como gargalo (ldconfig) foi confirmada na cadeia crítica
pela unidade upstream, não pela posição no blame.

## 5. Correções implementadas

| # | Correção | Arquivo |
| --- | --- | --- |
| 1 | `ConditionPathExists` movida de `[Service]` para `[Unit]` (efeito real: unidade pulada limpa em vez de falha 203/EXEC se binário da base faltar) | `system_files/usr/lib/systemd/system/{enthroned-update-check,enthroned-flatpak-update,enthroned-rollback,enthroned-system-update}.service` |
| 2 | Coleta de diagnóstico de boot ampliada: `critical-chain graphical.target`, `journalctl -b -p err` (sistema e usuário), `journalctl -b -k`, candidatos de gating no blame (ldconfig/wait-online/plymouth/NM/fsck), estágio do boot (boot id/uptime/OOBE), status da unidade user `enthroned-desktop-actions` | `system_files/usr/bin/enthroned-diagnostics` (`collect`) |
| 3 | Novo script único de auditoria de boot para executar **dentro da VM** (read-only, cobre todos os itens de diagnóstico do lote; saída em `~/boot-audit-lote9.txt`; roda 1º e 2º boot) | `scripts/boot-audit-vm.sh` (novo) |
| 4 | Verificação estática de unidades systemd no validador: Description, Type válido, ExecStart presente e presente na imagem, binários da base exigindo `ConditionPathExists` equivalente em `[Unit]`, proibição de condições fora de `[Unit]`, proibição de wiring em alvos da cadeia de boot, timers apontando para unidade enviada e instalando só em `timers.target`, ordenação/instalação da unidade user, idempotência dos primeiros boots, permissões no build.sh | `scripts/validate-desktop.sh` |
| 5 | Falso positivo ShellCheck (SC2100) pré-existente eliminado (variável `qdbus` → `qdbustool`) | `system_files/usr/bin/enthroned-diagnostics` |

Nada foi desativado, mascarado ou movido "para acelerar": nenhuma unidade de
segurança/montagem/autenticação/rede/recuperação foi tocada; nenhum parâmetro
de kernel (`quiet`, `splash`, redirecionamento) foi alterado.

## 6. Arquivos modificados

- `system_files/usr/lib/systemd/system/enthroned-update-check.service`
- `system_files/usr/lib/systemd/system/enthroned-flatpak-update.service`
- `system_files/usr/lib/systemd/system/enthroned-rollback.service`
- `system_files/usr/lib/systemd/system/enthroned-system-update.service`
- `system_files/usr/bin/enthroned-diagnostics`
- `scripts/boot-audit-vm.sh` (novo)
- `scripts/validate-desktop.sh`
- `docs/validation/LOTE-9-BOOT-AUDIT.md` (novo, este arquivo)

Preservado sem alteração: initramfs/identidade do `build.sh`, `vm.local.toml`
(máscaras uupd só para VM de teste), layouts/temas, polkit, Update Center e
tudo dos Lotes 1–8 (verificações dos validadores cobrem a ausência de
regressão).

## 7. Riscos e bloqueios

- **Sem acesso à VM da H3** (sem SSH/Guest Additions por design; VM desligada;
  proibido ligar/recriar VMs nesta rodada): os diagnósticos in-VM dependem de
  ação manual do usuário. Diagnóstico de userspace permanece **inconclusivo**
  até a coleta.
- A VM H3 existente **não tem** o `enthroned-diagnostics` ampliado (imagem
  anterior). Para coletar nela: transferir `scripts/boot-audit-vm.sh`
  (ex.: habilitando o clipboard/USB da VM — decisão do usuário) ou usar o
  roteiro `DIAGNOSTICO-BOOT-IN-VM.md`. Na próxima build (H4), o
  `enthroned-diagnostics collect` já cobre tudo — um único comando.
- `ldconfig.service` no 1º boot é esperado; **não** tratar como regressão na
  H4. Persistência em TODOS os boots sim indicaria anomalia
  (`/etc/.updated`/`systemd-update-done`).
- Os 3 FAILs do validador na primeira execução (B9-002) são o próprio defeito
  corrigido; após a correção, ALL CHECKS PASSED.

## 8. Problemas que dependem de runtime (não fecháveis aqui)

| Item | Como fechar na H4 |
| --- | --- |
| Distribuição real do tempo (kernel/initramfs/userspace/display-manager/desktop utilizável) | `systemd-analyze`, `blame`, `critical-chain` (+ `graphical.target`) no 1º e 2º boot |
| Presença/ausência de ldconfig no 2º boot | blame/critical-chain do 2º boot |
| Erros/warnings reais do journal | `journalctl -b -p err`, `-p warning`, `-k`, `--user -p err` |
| Unidades falhas | `systemctl --failed` (sistema e usuário) |
| Renderização por software (VMSVGA, 3D off → llvmpipe?) | `graphics.txt` do collect (KWin supportInformation) |
| Peso do OOBE vs boot normal | comparar 1º (com plasma-setup) × 2º boot |
| Papel de NetworkManager-wait-online/plymouth | `critical-chain` + blame filtrado |
| Ganho de qualquer mudança de performance | medições comparativas na mesma VM, antes/depois, uma variável por rodada (roteiro de rodadas A–D em `NEXT-HOMOLOGATION.md` §1) |

## 9. Resultado das verificações (host, estáticas/leves)

| Verificação | Resultado |
| --- | --- |
| `bash scripts/validate-desktop.sh` | **ALL CHECKS PASSED** (inclui ~45 novos checks de unidades deste lote; os 3 FAILs iniciais eram o defeito B9-002, corrigido) |
| `bash scripts/verify-source.sh` | 15 pass / 1 warn pré-existente (placeholder ISO) / 0 fail |
| `bash scripts/validate-settings.sh` | PASS 444 / FAIL 0 |
| `bash scripts/validate-welcome.sh` | All welcome validation checks passed |
| `shellcheck -S warning` (WSL) | **CLEAN** em `scripts/boot-audit-vm.sh` e `system_files/usr/bin/enthroned-diagnostics` |
| `bash -n` nos scripts alterados | OK |
| `plasma-core.target` existe no plasma-workspace | confirmado no código upstream (`startkde/systemd/plasma-core.target`) — unidade user do Lote 7.1 válida |
| Sintaxe/semântica systemd in-VM (`systemd-analyze verify`) | **NOT RUN** (sem systemd no host Windows/WSL) — os checks são parsers próprios, não substituem o systemd-analyze verify |

## 10. Checklist de performance para a Homologação 4

Na VM (H4), rodar duas vezes: **A)** logo após o OOBE do 1º boot e **B)** após
um reboot normal. Usar `enthroned-diagnostics collect` (imagem nova) ou
`bash boot-audit-vm.sh` — salvar e comparar os dois arquivos.

- [ ] `systemd-analyze`: kernel, initramfs e userspace separados; registrar os 3 números em cada boot
- [ ] `blame` top 10: anotar unidades > 5 s; conferir se ldconfig aparece só no 1º boot
- [ ] `critical-chain`: identificar o caminho até `graphical.target` e a unidade dominante
- [ ] `systemctl --failed` (sistema e usuário): esperar vazio; registrar qualquer falha com `systemctl status`
- [ ] `journalctl -b -p err` / `-p warning` / `-k`: classificar por B9-001..004 e pelo formato do Lote 7 §2
- [ ] Renderizador: `graphics.txt` — se `llvmpipe`, registrar que a fluidez é limitação do VirtualBox (3D off), não do sistema; rodada B opcional (3D ligado) só por decisão do usuário
- [ ] Comparar 1º × 2º boot: diferença esperada = ldconfig + OOBE + criar perfil do usuário
- [ ] Nenhuma unidade Enthroned no `critical-chain` do 2º boot (contrato atual)
- [ ] Só depois de coletar: discutir otimizações (ex.: `NetworkManager-wait-online`, initramfs hostonly por artefato-VM) — cada uma com medição antes/depois e aprovação

## Estado do Git

Branch `main`, sem commits (como nas rodadas anteriores — commit só sob
instrução explícita). Nenhuma build, imagem, VM, publicação ou atualização
real executada. Evidências anteriores em `output/` intocadas.
