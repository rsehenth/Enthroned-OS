# Aplicativos padrão — operações (F4)

Política vigente: **ADR-0006**. Este documento descreve o que é instalado,
de onde e como verificar/alterar.

## Matriz de aplicativos

| Papel | Aplicativo | Fonte | Método | Quando |
| --- | --- | --- | --- | --- |
| Navegador padrão | Brave (`com.brave.Browser`) | Flathub (editor: Brave Software) | Flatpak de sistema, provisionado em 1º boot | `enthroned-firstboot-flatpaks.service` |
| Loja de aplicativos | KDE Discover | RPM Fedora (base Aurora) | `dnf5 -y install discover` no build | Build da imagem |
| Suíte criativa (opcional) | ArtCraft Launcher (`ai.storyteller.artcraft-launcher`) | Releases oficiais no GitHub | Bundle Flatpak user-level, com SHA-256, sob portão | Somente com consentimento |
| Essenciais KDE | Dolphin, System Settings, sessão, rede, multimídia etc. | Base Aurora | Preservados — nenhuma remoção | Sempre |

Nenhum outro aplicativo é instalado automaticamente.

## Fluxo do navegador padrão

1. Build da imagem habilita `enthroned-firstboot-flatpaks.timer`.
2. Após o deploy, o timer dispara o serviço oneshot (após
   `network-online.target`).
3. O script `/usr/libexec/enthroned-firstboot-flatpaks`:
   - sai imediatamente se o flatpak ou o remote `flathub` não existirem;
   - pula apps já instalados; grava sucesso em
     `/var/lib/enthroned-os/firstboot-flatpaks.done`;
   - sem rede, registra WARN e sai 0 — o timer tenta de novo (boot + 6h).
4. `/etc/xdg/mimeapps.list` define os defaults `http`/`https`/`text/html`.
   Usuários com `~/.config/mimeapps.list` próprio não são afetados.
5. Enquanto o Brave não existe, o desktop usa o fallback padrão e o Welcome
   mostra o estado honesto ("ainda não instalado").

## Responsabilidades de atualização (sem duplicação)

- **Sistema (bootc) + Flatpaks:** uupd (infraestrutura da F3/F5). O
  provisionamento de 1º boot instala uma vez; atualizações correntes são do
  mecanismo automático da base.
- **Discover:** instala/remove/atualiza aplicativos sob demanda do usuário.
- **Enthroned Update Center (Settings):** apresenta informação; não cria um
  segundo processo de atualização (ADR-0005).
- **ArtCraft Launcher:** atualiza a si e aos apps da suíte dentro do próprio
  launcher (por design do projeto upstream); fora do escopo do uupd.

## Como alterar a lista de Flatpaks padrão

Editar `system_files/usr/share/enthroned-os/firstboot-flatpaks.txt` (um app ID
por linha, `#` para comentários). Requer ADR. O script instala apenas IDs
presentes na lista e não manipula remotes.

## Verificações operacionais (pós-deploy)

```bash
systemctl status enthroned-firstboot-flatpaks.service   # oneshot + timer
cat /var/lib/enthroned-os/firstboot-flatpaks.done       # apps provisionados
flatpak remotes --system                                # flathub presente
xdg-settings get default-web-browser                    # com.brave.Browser.desktop
```

Se o Brave não instalou (ex.: máquina sempre offline), o usuário instala pelo
Discover ("Brave") ou por `flatpak install --system com.brave.Browser`.
