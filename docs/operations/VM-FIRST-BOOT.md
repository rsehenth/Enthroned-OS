# Primeiro boot do MVP

Estado: **NOT RUN**. Nenhuma imagem produzida e nenhuma VM inicializada.
Instalação de ferramentas, build e boot exigem autorizações separadas:
[BUILD.md](BUILD.md). Não aplicar a imagem ao Windows, ao WSL ou a discos físicos.

## VirtualBox no Windows

Após build QCOW2, conversão VDI e validação de formato/hash:

1. Criar VM Linux/Fedora 64-bit isolada, sem instalação automática do VirtualBox.
2. Firmware EFI/UEFI, quatro vCPUs, 8 GiB RAM, VMSVGA, 128 MB de memória de vídeo.
   Começar com aceleração 3D desativada; não fazer GPU passthrough.
3. Anexar `output/EnthronedOS-MVP.vdi` ao controlador SATA. Disco virtual: 64 GiB.
4. Rede NAT; sem pastas compartilhadas ou discos físicos anexados.
5. Iniciar somente após autorização de VM. Entrar como `enthroned` usando a senha
   definida localmente no blueprint privado.

A presença de Hyper-V/WSL2 pode afetar desempenho do VirtualBox. Não mudar
configurações globais do Windows ou WSL para contornar isso sem autorização.

## Smoke test e evidências

Registrar o SHA-256 do VDI, versão do VirtualBox e os resultados de cada item:

- Boot UEFI chega ao login; login abre sessão KDE e desktop utilizável.
- Launcher abre. Se falhar, botão direito → "Mostrar alternativas" → Kickoff (não há segundo botão Iniciar).
- Dolphin e Enthroned Settings abrem.
- Update Center mostra leituras reais ou indisponibilidade; demo claramente
  identificado. Não executar atualização, rollback ou reboot pelo atualizador.
- Welcome abre no primeiro login; Classic/Modern aplicam mediante ação explícita.
- ArtCraft continua desmarcado e não instala nada. Pular/Concluir encerram o fluxo.
- Discover abre com backend Flatpak. Brave abre quando de fato instalado.
- Sem internet: desktop abre, Welcome informa Brave ausente, provisioning pode
  aguardar. Com internet, consultar o journal do provisioning se Brave faltar.
- Reiniciar somente a VM para testar persistência e ausência de reabertura
  indevida do Welcome. A abertura manual continua disponível.

Leituras úteis dentro da VM:

```bash
enthroned-identity --summary
bootc status --format=json
systemctl status enthroned-firstboot-flatpaks.timer
journalctl -u enthroned-firstboot-flatpaks.service --no-pager
flatpak info --system com.brave.Browser
```

Registrar falhas P0/P1 e corrigi-las no escopo do MVP. Não instalar ArtCraft nem
executar upgrades como parte do smoke test. Manter a VM e os logs para revisão;
não apagar artefatos automaticamente.

Promover o estado somente com evidência: BUILD VERIFIED, BOOT VERIFIED e,
após todos os essenciais, MVP FUNCTIONAL. Até lá: SOURCE READY / BUILD BLOCKED.
