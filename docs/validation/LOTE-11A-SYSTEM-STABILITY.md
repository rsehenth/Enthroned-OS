# Lote 11A — Estabilidade, segurança e recuperação

Data: 2026-11-19 · Executor: Sol 6.2 (High) · Base: `H5-VM-HOMOLOGATION.md`
(P2-1, P2-2, P2-3, P2-4 e o gargalo `tuned`). Paralelo ao Lote 11B (UI;
`settings/`, `welcome/`, launcher — **não tocados aqui**).

Nada foi construído nem executado fora de um diretório temporário: sem imagem
OCI/ISO/QCOW2/VDI, sem VirtualBox, sem upgrade bootc/Flatpak, sem commit/push,
H4/H5 e builds anteriores intactos, canal de produção fechado (`f1-dev`).

## 1. Resumo

| Item | Causa | Estado |
| --- | --- | --- |
| P2-1 firstboot-flatpaks exit 0 em falha | **Provada** no código (`exit 0` incondicional + `SuccessExitStatus=0`) | **Corrigido e testado** |
| P2-2 Discover tenta atualização RPM | **Provada** no `build.log` H5 (origem: nossa própria `dnf5 install`) | **Corrigido na origem**; efeito real depende da próxima imagem |
| P2-3 `invalid_bootcinstall_testlabel_t` | **Não vem do Enthroned**; é a sonda do próprio bootc (fonte externa) | **Sem correção de origem** (não há origem nossa); guarda de regressão adicionada |
| P2-4 `/var` somente leitura | **Não provada** (sem evidência de quem remontou) | **Sem alteração**; coletor de evidência read-only |
| `tuned` ~22–29 s | Não há texto da unit nem `critical-chain` detalhado nas evidências | **Sem alteração**; coletor de evidência; hipótese documentada |

## 2. P2-1 — `enthroned-firstboot-flatpaks`

**Causa (provada):** o helper terminava sempre com `exit 0` (comentário
"always exits 0 so the timer can retry") e a unit declarava
`SuccessExitStatus=0`; o systemd registrava "Finished" mesmo com a instalação
do Brave falhando (journal H5 06:23/06:53).

**Correção** (`system_files/usr/libexec/enthroned-firstboot-flatpaks`,
`...firstboot-flatpaks.service`):

| Situação | Saída | Unit |
| --- | --- | --- |
| tudo instalado / sem `flatpak` | 0 | sucesso |
| sem rede, sem remote `flathub` ainda, ou outra execução em curso | **75** (adiado) | sucesso (`SuccessExitStatus=75`), motivo em `firstboot-flatpaks.status` |
| repositório inconsistente (ex.: `Couldn't find file object`, download interrompido) | **77** + mensagem "`flatpak repair --system`" | **falha** |
| qualquer outra falha de instalação | **1** | **falha** |
| SIGTERM/SIGINT | 143 | — |

- O erro original do `flatpak` é sempre reencaminhado ao journal (stderr).
- Idempotência: o marcador só recebe o app **depois** de `flatpak install`
  com sucesso **e** `flatpak info` confirmando; interrupção/falha não grava
  nada e o timer reexecuta do zero. Falha em um app não impede os demais.
- Concorrência: `flock -n` em `/run/enthroned-firstboot-flatpaks.lock`; o
  filho `flatpak` fecha o fd do lock (`9>&-`) para não sobreviver segurando-o
  (bug encontrado pelo próprio teste A10).
- Nunca roda `flatpak repair`, `uninstall` ou altera remotes; apps já
  instalados são preservados e apenas registrados.
- Novo `firstboot-flatpaks.status` (`result=ok|offline|corrupt|failed|interrupted`)
  escrito atomicamente — para diagnóstico/monitoramento.
- Heurística: classificação por texto de erro do flatpak. Erro não
  reconhecido cai em "falha" (1), nunca em "adiado" — o erro de classificação
  é sempre para o lado visível. Reparo corrompido é checado antes de rede.

**Decisão de projeto (documentada):** offline é "adiado" (75 = sucesso) para
não produzir unidade `failed` em todo boot sem rede; a verdade fica no
`.status` e no log. Se preferir `failed` também offline, basta remover 75 de
`SuccessExitStatus`.

## 3. P2-2 — Discover em sistema atomic

**Diagnóstico (distinguindo as três fontes):**

- **Aurora/configuração herdada:** a base **não** traz Discover. O
  `build.log` da H5 (linha 158) mostra `dnf5 -y install plasma-discover
  plasma-discover-flatpak glibc-langpack-pt` instalando 12 pacotes, incluindo
  **dependências fracas** `plasma-discover-packagekit` e
  `plasma-discover-offline-updates`, além de `PackageKit`/`PackageKit-glib`.
  O diálogo "Problema da atualização" vem, portanto, do backend PackageKit
  que **nossa** etapa de build trouxe.
- **Discover:** funciona (catálogo/categorias PASS na H5); o problema é o
  backend extra, não o app.
- **PackageKit:** o daemon é dependência dura de `plasma-discover-libs`
  (spec Fedora); está presente mas é ativado sob demanda por D-Bus. Sem o
  backend `-packagekit` o Discover não o consulta para atualizações.
- Referência de política: o spec Fedora do `plasma-discover` registra que o
  Kinoite "explicitamente exclui `-packagekit` e `-offline-updates`".

**Correção (`build_files/build.sh`):** `dnf5 install --exclude=plasma-discover-packagekit
--exclude=plasma-discover-offline-updates ...` + asserção que **falha o
build** se algum dos dois pacotes existir, e `rpm -q plasma-discover-flatpak`.
Preservados: pesquisa/catálogo/instalação Flatpak (backend flatpak),
PackageKit daemon (não mascarado nem removido), Update Center Enthroned,
canal fechado. Sem o pacote `plasma-discover-notifier` na transação não há
notificador de "atualizações do sistema" do Discover.
`verify-image.sh` ganhou a verificação equivalente na imagem pronta.

**Pendente (VM):** confirmar na próxima imagem que o diálogo não aparece e que
o Discover ainda lista/instala Flatpaks; `stability-audit-vm.sh` coleta
`rpm -qa 'plasma-discover*'` e o journal. Risco: se algum pacote tiver
dependência dura do backend (o spec indica só `Recommends`), o `dnf5` falhará
**alto** no build, nunca silenciosamente.

## 4. P2-3 — `invalid_bootcinstall_testlabel_t`

- Busca em `build_files/`, `system_files/`, `Containerfile`, `Justfile`,
  `disk_config/`, `scripts/`, `docs/` (fora das evidências H5): **o rótulo não
  existe em nenhum arquivo do Enthroned**; nada de SELinux é alterado em
  `build.sh`.
- Fonte externa: a sonda do `bootc` (`crates/lib/src/lsm.rs`) verifica a
  capacidade `mac_admin` tentando rotular com um contexto **propositalmente
  inválido**; a negação AVC é o resultado esperado da sonda (relatado também
  no empacotamento AlmaLinux do bootc, que marca o check de AVC como
  informativo). Nota: não consegui inspecionar o binário `bootc` da imagem
  (sem imagem local); o nome exato do rótulo foi **inferido** dessa fonte, não
  verificado no binário.
- **Nenhuma correção de configuração aplicada** (não há origem nossa); não
  se desabilitou SELinux nem se ocultou negação. Guardas: teste estático
  (`test-system-stability.sh` B3) garante que o rótulo não entre em
  `system_files`/`build_files`/`Containerfile` e que o build não use
  `setenforce`/`SELINUX=`; `verify-image.sh` varre `/etc`, `/usr/etc`,
  `/usr/lib/systemd`, `/usr/share/selinux` da imagem (o policy store binário
  não é varrido).

## 5. P2-4 — `/var` somente leitura após desligamento forçado

Evidência H5: `ro` em `/dev/sda4` (btrfs) no boot de recuperação, **sem**
erro btrfs no kernel (só replay de tree-log), **sem** "Remounting" no journal,
sem repetição em 3 boots limpos; `flatpak` escreveu até 05:59:44, `touch`
falhou às 06:08. Nada do Enthroned remonta `/var` (grep: nenhuma unit/script
nosso monta/remonta). Candidatos plausíveis (**não provados**): remontagem
feita pela cadeia ostree/bootc (`ostree-remount`, `ostree-finalize-staged`) ou
por `systemd-remount-fs` durante a recuperação do boot interrompido; um
remount para `ro` por erro de btrfs normalmente deixa log de kernel, que não
houve. Sem evidência de qual agente agiu, **nenhuma correção foi aplicada**
(não se tenta reproduzir com desligamento abrupto).
Monitoramento: `scripts/stability-audit-vm.sh` coleta opções de mount de
`/var`, traços de remount no boot atual/anterior e estado de
`ostree-remount`/`finalize-staged`. Critério existente mantido: se repetir em
boot **limpo**, promover a P1. Contorno inalterado: reboot limpo.

## 6. `tuned` e tempo de boot

Evidência H5: cadeia `tuned-ppd ← tuned (+22–29 s) ← NetworkManager (+8,8–22 s)
← basic.target`. Não há texto de `systemctl cat tuned` nem `systemd-analyze
critical-chain tuned` no acervo; H4 registrou uma falha transitória do tuned
sob carga. Hipótese (não provada): o `tuned.service` do Fedora é ordenado
depois de `network.target` (portanto após o NetworkManager) e o tempo de
partida do próprio daemon sob VM com host pressionado domina; remover essa
ordenação por drop-in poderia sobrepor os dois, mas **não há evidência** de
que a aresta seja essa nem de que seja segura em hardware real. Sem prova,
**nenhum ajuste, mask ou desativação** (gerenciamento de energia e
desempenho preservados). Próximo passo: rodar `stability-audit-vm.sh` na VM
(coleta `After=/Before=` resolvidos, `critical-chain`, `blame`, perfil ativo,
log do tuned) e decidir com números; qualquer drop-in deve ser medido também
em hardware real.

## 7. Testes executados

`wsl -d Ubuntu` (Linux isolado, diretório temporário, `flatpak` simulado;
nada instalado no Windows, nenhum serviço real tocado):

- `bash scripts/test-system-stability.sh` → **ALL PASS** (vermelho antes:
  19 falhas; verde depois). Cobre: sucesso; repetição idempotente; falha
  genuína + retry; offline (75); repo corrompido (77, sem repair/uninstall/
  remote); app pré-instalado preservado; falha parcial; sem remote flathub;
  execução concorrente recusada; SIGTERM no meio do download (sem marcador,
  lock liberado, retry OK); unit (75 sucesso, 77 não); build exclui backends
  RPM e falha se voltarem; rótulo SELinux ausente; canal `f1-dev`;
  `systemd-analyze verify` das units.
- `shellcheck -S warning` limpo em helper, build.sh, harness e auditor.
- Regressões vizinhas: `verify-source.sh` (15 pass, 0 fail),
  `test-desktop-helpers.sh` (ALL CHECKS PASSED). `test-diagnostics-ptbr.sh`
  falha apenas por falta do locale `pt_BR.UTF-8` no WSL (limitação ambiental
  preexistente; exige o container Aurora).
- Passo de CI adicionado em `validate.yml`.

## 8. Pendências dependentes de VM / imagem (não executáveis neste lote)

1. Nova imagem: confirmar ausência de `plasma-discover-packagekit` /
   `-offline-updates`, Discover listando e instalando Flatpak, sem o diálogo
   de atualização; `verify-image.sh` na imagem.
2. Primeiro boot offline → `status=offline`, unit "Finished"; boot online →
   Brave instalado; interrupção no meio do download → 77 + aviso de repair.
3. Rodar `stability-audit-vm.sh` (tuned, `/var`, SELinux, flatpak) e decidir
   P2-4 e `tuned` com dados.

## 9. Riscos

- Classificação por texto de erro do flatpak pode não cobrir mensagens
  futuras → cai em falha (visível), não em sucesso.
- `--exclude` do dnf5 não foi exercitado numa build real (proibido neste
  lote); falha de resolução seria visível e bloqueante.
- P2-3 e P2-4 e `tuned` permanecem como achados P2 sem correção de origem.
- Fora do escopo (Lote 11B): P2-5/P2-6 (copy do Update Center, retomada do
  Welcome).

## 10. Decisão

**GO para consolidação com o Lote 11B**, sujeito às verificações da imagem
(§8.1) no próximo gate de build: as duas correções de código (P2-1, P2-2)
estão provadas na causa e cobertas por testes negativos; os três itens sem
evidência foram deliberadamente deixados sem alteração, com coletor de
evidência pronto. Nenhum arquivo de 11B foi tocado, então não há conflito de
merge esperado (arquivos 11A: `build_files/build.sh`,
`system_files/usr/libexec/enthroned-firstboot-flatpaks`,
`system_files/usr/lib/systemd/system/enthroned-firstboot-flatpaks.service`,
`scripts/{test-system-stability,stability-audit-vm,verify-image}.sh`,
`.github/workflows/validate.yml`).
