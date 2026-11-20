# Integração do Enthroned Welcome

Estado: **SOURCE READY / BUILD BLOCKED**. Compilação e execução Qt ainda não realizadas.

O `apps-builder` do `Containerfile` compila o Welcome com Qt >= 6.7 (requisito
real de `GenericStateLocation`), executa o teste nativo do controlador e instala
em `/out`. Executável, recursos, desktop e autostart entram juntos na imagem.
O autostart inclui `TryExec`; uma falha do assistente não bloqueia o Plasma.

O botão Pular conclui o assistente sem consentir ArtCraft. O demo não lê nem
sobrescreve o progresso real. O portão de instalação ArtCraft permanece fechado
por padrão, e a opção continua desmarcada.

Procedimento atual de build e autorizações: [BUILD.md](BUILD.md).

Arquivos instalados (via CMake, prefixo `/usr`):

| Arquivo | Destino |
| --- | --- |
| `enthroned-welcome` | `/usr/bin/` |
| `org.enthroned.welcome.desktop` | `/usr/share/applications/` |
| `org.enthroned.welcome.appdata.xml` | `/usr/share/metainfo/` |
| `org.enthroned.welcome.autostart.desktop` | `/etc/xdg/autostart/` |
| `org.enthroned.welcome.png` (16–512 px, trono oficial `Throne-2`; Gate 13.1) | `/usr/share/icons/hicolor/<N>x<N>/apps/` |

## Comportamento em execução

- **Autostart:** `enthroned-welcome --autostart` em todo login gráfico KDE; o
  processo sai silenciosamente quando a fase persistida é `completed`
  (detalhes em `docs/architecture/ENTHRONED-FIRST-RUN-ARCHITECTURE.md`).
- **Instância única:** `QLockFile` em `$XDG_RUNTIME_DIR`; a 2ª instância sai
  sem janela (silenciosa no autostart, mensagem no stderr no manual).
- **Reabertura manual:** Enthroned Settings → Aplicativos → "Reabrir Enthroned
  Welcome" (`enthroned-welcome --reopen`); também direto pelo menu.
- **Reset de usuário (suporte):** remover
  `$XDG_STATE_HOME/enthroned-os/welcome-state.json` e encerrar o processo —
  o próximo login recomeça do zero.
- **Sem internet:** tudo funciona; apenas a instalação opcional do ArtCraft
  falha com mensagem clara (portão + rede ausente).

## Modo demonstração (desenvolvimento/homologação)

```bash
enthroned-welcome --demo                          # cenário install-complete
enthroned-welcome --demo --demo-scenario offline  # falha limpa sem rede
```

No modo demo nada é baixado ou instalado; o banner avisa na janela. Espelha o
modo demo da Enthroned Settings (F3) — mesmo contrato de segurança.

## Portão de instalação real do ArtCraft

A instalação real só executa com `ENTHRONED_WELCOME_ALLOW_INSTALL=1` no
ambiente do processo (padrão da F3: mutação controlada fora da UI). Antes de
abrir o portão em produção, homologar:

1. compilar o app (estágio habilitado) e executar em VM;
2. validar o download do release oficial + SHA-256 em rede real;
3. validar `flatpak install --user` com o runtime do bundle;
4. revisar `docs/licensing/THIRD-PARTY.md` (marca/licenças upstream).

Enquanto isso, a UI mostra o estado "bloqueada nesta fase" — honesto, sem
simulação de sucesso.

## Integração com Enthroned Settings (F4.9)

`settings/` ganhou, em `kcmlauncher.{h,cpp}`, os pontos de entrada reais
`hasExecutable()`, `hasFlatpakApp()` e `launchApp()`, e a AppsPage uma seção
"Experiência Enthroned": loja (Discover), reabrir Welcome e informações do
ArtCraft (estado honesto, sem atalho quando não instalado). As verificações
estáticas da F3 continuam válidas (`just verify-settings`).
