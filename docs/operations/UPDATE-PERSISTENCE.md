# Persistência durante atualizações (Lote 8)

Garantias e pontos de atenção sobre o que a atualização do Enthroned OS
preserva. O modelo de dados segue as regras do bootc: `/usr` vem da imagem
(atômica), `/etc` faz merge de três vias no primeiro boot da nova imagem,
`/var` e `/home` nunca são tocados pela atualização.

## O que é preservado por design

| Dado | Onde vive | Comportamento na atualização |
|---|---|---|
| Usuários e contas | `/etc` (passwd, shadow, group), sssd/systemd-home | Merge de três vias do bootc; contas criadas no uso permanecem |
| Arquivos pessoais | `/home` | Nunca tocado (a Central de Atualizações não escreve em `$HOME`) |
| Configurações do KDE | `~/.config` (por usuário) e `/etc/xdg` (padrões) | Padrões atualizam via merge em `/usr/etc` + `/etc`; overrides do usuário vencem |
| Perfis Classic/Modern | pacotes look-and-feel em `/usr` + estado em `$XDG_STATE_HOME/enthroned-os` | Pacotes atualizam com a imagem; a escolha do usuário (plasmalookandfeelerc) permanece; `enthroned-profile restore` cobre recuperação |
| Favoritos e layout do painel | `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | Nunca tocado; o layout script do Enthroned só age no firstboot/ao pedido |
| Aplicativos Flatpak | `/var/lib/flatpak` (sistema), `~/.local/share/flatpak` (usuário) | Nunca tocados pela troca de imagem; atualizações de app são fluxo separado |
| Remotos Flatpak | `/etc/flatpak/remotes.d` (sistema), `~/.local/share/flatpak/repo` | Preservados; provisão firstboot é idempotente (arquivo marcador) |
| Preferências do Enthroned | `/etc/xdg/enthroned-os/preferences.conf` + overrides do usuário | Merge do bootc; mudanças locais vencem sobre os padrões da imagem |
| Dados de serviços | `/var` (bancos, journals, contêineres) | Nunca tocado |
| Origem de atualização | deployment bootc (`bootc status`) | A origem booted é mantida; a Central nunca rebaseia |

## Regras do bootc aplicadas

1. **`/usr` atômico:** a nova imagem substitui `/usr` inteira (rollback
   devolve a anterior).
2. **`/etc` merge de três vias:** arquivos enviados pela imagem
   (`/usr/etc`) são mesclados com o `/etc` local; mudanças locais do usuário
   e mudanças novas da imagem se combinam, conflitos explícitos são
   sinalizados no boot (`systemd-boot-check-no-failures`, journal).
3. **`/var` e `/home` persistentes:** nenhum fluxo de atualização os escreve.

## Conflitos possíveis e migrações

- **Padrões do KDE que mudaram na nova imagem:** se o usuário alterou o
  mesmo arquivo em `/etc`, vence a versão local; a partir daí a imagem não
  reaplica o padrão. Migração manual pode ser necessária (documentar caso a
  caso no changelog do canal).
- **Esquema de preferências do Enthroned (`preferences.conf`):** chaves
  novas chegam pela imagem; chaves removidas são ignoradas pelo leitor. O
  `personalizationcontroller` não apaga overrides do usuário.
- **Look-and-feel atualizado com perfil aplicado:** o pacote novo só vale no
  próximo `plasma-apply-lookandfeel`; o estado anterior em
  `$XDG_STATE_HOME/enthroned-os/previous-lookandfeel` continua válido para
  `enthroned-profile restore`.
- **Unidades systemd renomeadas entre versões:** unidades Enthroned
  desabilitadas por design (timers) não migram estado de habilitação; quem
  habilitou manualmente precisa reavaliar após upgrade (documentado no
  changelog).
- **Flatpak sem atualização automática esperada:** o uupd cuida da
  instalação de sistema; a instalação do usuário é atualizada via Central ou
  Discover. Nenhum fluxo remove aplicativos ou dados.

## Rollback e o que ele não desfaz

`bootc rollback` (unidade fixa `enthroned-rollback.service`) volta o
**deployment do sistema** apenas. Arquivos pessoais, Flatpaks, configurações
do usuário e dados em `/var` permanecem na versão mais recente. Se uma
migração de configuração escreveu em `/etc`, o rollback não reverte esse
merge automaticamente (regra do bootc); a Central avisa sobre esse limite na
tela de recuperação.

## Verificação (homologação na VM)

Roteiro resumido para validar persistência após um ciclo completo
(verificar → atualizar → reiniciar):

1. Criar marcador antes (arquivo em `$HOME`, atalho no desktop, perfil
   Classic aplicado, Flatpak do usuário instalado).
2. Aplicar atualização de sistema e reiniciar; conferir que o marcador,
   favoritos, perfil e Flatpaks sobreviveram.
3. Aplicar rollback e reiniciar; conferir que a versão anterior boota e que
   os dados do usuário permanecem.
4. Registrar evidências no relatório de validação do Lote 8.
