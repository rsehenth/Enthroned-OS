# ADR-0007 — Enthroned Settings como centro geral de configurações (Lote 4)

- **Data:** 2026-11-17
- **Estado:** Aceito (implementação em código; execução real pendente de homologação)
- **Contexto:** Lote 4 — evolui o app existente (`org.enthroned.settings`); não cria um segundo aplicativo.
- **Relacionados:** ADR-0005 (integração de atualizações), `ENTHRONED-UPDATE-ARCHITECTURE.md`.

## Decisões

### 1. Doze áreas, um único app

Início · Sistema · Bluetooth e dispositivos · Rede e Internet · Personalização ·
Aplicativos · Contas · Hora e idioma · Acessibilidade · Privacidade e segurança ·
Atualizações do sistema · Sobre o dispositivo.

Regra de conteúdo: cada controle ou cartão tem uma fonte real. Se a configuração
pertence a um módulo do KDE (`kcmshell6`), a página oferece o botão **Abrir**
(`ModuleCard`), que só habilita quando `kcmshell6 --list` reporta o módulo. Ids
de módulo variam entre versões do Plasma, por isso cada cartão aceita uma lista de
candidatos (o primeiro reportado vence). Módulos que dependem de pacotes opcionais
(`optional: true`) somem em vez de aparecer desabilitados. Nenhuma página simula
um recurso: onde o Settings não pode agir (ex.: renomear o computador, que exige
privilégios), a página diz isso.

Páginas são instanciadas sob demanda (`Loader` + `Component`); os dados de
hardware são coletados fora da thread de interface.

### 2. Busca local

`qml/search.js` (funções puras) sobre `qml/SearchIndex.qml` (lista em memória de
páginas + configurações reais com sinônimos PT/EN). Casamento sem acento e sem
caixa; todas as palavras da consulta precisam casar; título > sinônimo > página.
Sem indexador, serviço, rede ou arquivo de índice. Resultados com módulo KDE
abrem o módulo direto (e mostram a página relacionada); se o módulo não existe, a
página explica. Testada por `settings/tests/run-tests.mjs`.

### 3. Informações do dispositivo (dados reais)

`DeviceInfoProvider` (thread de trabalho + entrega enfileirada): CPU/RAM
(`/proc`), GPU (`lspci -mm`, com fallback `/sys/class/drm`), volumes de blocos
(`QStorageInfo`, binds do mesmo dispositivo colapsados), modelo (DMI), SELinux
(`/sys/fs/selinux/enforce`) e `/usr` somente leitura. Valor ausente fica vazio e
a UI mostra "Indisponível"; durante a coleta, "Coletando…".

### 4. Personalização com mecanismos do Plasma

- Perfis Classic/Modern: inalterado (`enthroned-profile`, F2.1).
- Tema claro/escuro: `plasma-apply-colorscheme "Enthroned Light|Dark"`.
- Papel de parede: `plasma-apply-wallpaperimage <arquivo Enthroned>`.
- Allowlist fixa no C++ (`PersonalizationController`): a UI passa um id, nunca um
  caminho ou argumento livre. Sem privilégios, sem shell.

### 5. Atualizações: estado do backend

O Update Center (ADR-0005) já cobre o fluxo verificar → listar → atualizar →
progresso → resultado → reinicialização, com portão de mutação **fechado por
padrão**. O Lote 4 acrescenta:

| Item | Implementação |
| --- | --- |
| Origem da imagem | `update/imageorigin.h` classifica o `bootc status` em `enthroned` / `unverified` / `foreign` / `unknown` a partir de `expected_image_references` (release-channel.json). Imagens genéricas Fedora/CentOS são sempre `foreign`. |
| Bloqueio | `UpdateEngine::updateBlockReason()` (`demo`, `policy`, `origin-foreign`, `origin-unknown`); `canUpdate()` e `requestUpdate()` o respeitam. O botão mostra o motivo real. |
| Sem troca de imagem | O app não executa `bootc switch/rebase/upgrade`, `dnf` ou `rpm-ostree`; o uupd atualiza a partir da origem já instalada. Verificado por checagem estática. |
| Sistema × Flatpak | `systemUpdates` e `appUpdates` são listas separadas no backend (fontes: `bootc status` e `flatpak remote-ls --updates`); a página as exibe em grupos. |
| Um só `bootc status` | O contexto QML `bootc` agora é a instância do engine (antes havia duas, e a da UI não era atualizada). |

#### Bloqueios que permanecem (contrato para revisão técnica)

1. **Mutação desligada por padrão.** `ENTHRONED_SETTINGS_ALLOW_MUTATION=1` só em
   deploy validado; a UI nunca o define. Nada foi habilitado porque a interface
   ficou pronta.
2. **Escopo do `uupd-manual.service`.** Ele executa *todos* os módulos habilitados
   do uupd (bootc, Flatpak, Brew, Distrobox). Não há hoje unidade que atualize só
   o sistema ou só os aplicativos; separar a *execução* exige uma unidade
   dedicada (ex.: `enthroned-system-update.service` com módulos restritos) e regra
   polkit própria — **não criada** aqui por ser serviço privilegiado que precisa de
   revisão. Até lá, a separação é de listagem/estado e o diálogo declara o escopo.
3. **Versão disponível do sistema.** `uupd update-check` só devolve código de saída
   (0/77); a versão exata só é conhecida depois que o bootc prepara o deployment
   (staged). A UI não inventa versão.
4. **Cancelamento real.** Não há `StopUnit` exposto: interromper `uupd-manual`
   no meio do `bootc upgrade` não tem semântica de rollback comprovada. O
   cancelamento só existe no modo demo; em operação real, uma unidade encerrada
   pelo systemd aparece como falha.
5. **`expected_image_references` vazio.** Sem namespace de registro definido
   (ADR-0002), a origem fica `unverified` (atualização permitida pela política,
   ainda sujeita ao portão). Quando o registro existir, preenchê-lo faz qualquer
   outra origem bloquear.
6. **Renomear o dispositivo / trocar canal de imagem**: exigem `hostnamectl` /
   `bootc switch` privilegiados; fora do escopo e não oferecidos.

## Consequências

- Mais superfície de UI, mas toda ela é leitura local ou atalho para módulo KDE,
  salvo o tema/papel de parede (Plasma, nível de usuário) e perfis (F2.1).
- Ids de KCM dependem da versão do Plasma; a detecção em tempo de execução evita
  botões mortos, e a homologação deve registrar quais módulos aparecem na imagem.
