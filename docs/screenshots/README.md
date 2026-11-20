# Galeria do Enthroned OS

Capturas reais da imagem de desenvolvimento H7, usadas pelos dois READMEs ([English](../../README.md), [Português](../../README.pt-BR.md)).

| Arquivo | Tela |
| --- | --- |
| `desktop-classic.png` | Área de trabalho com o perfil Enthroned Classic. |
| `desktop-modern.png` | Área de trabalho com o perfil Enthroned Modern. |
| `start-menu.png` | Menu Iniciar aberto com busca, fixados e locais visíveis. |
| `settings-personalization.png` | Enthroned Settings na página Personalização. |
| `welcome.png` | Enthroned Welcome na primeira sessão (etapa 3 de 5, navegador e aplicativos). |
| `dolphin.png` | Dolphin com pastas e navegação visíveis. |
| `lock-screen.png` | Tela de bloqueio com a arte e a conta de demonstração. |

## Procedência

- **Build:** `localhost/enthroned-os:h7`, image id `007a63c5d3f71b2f6f7b726ec4ab40ee393a5e0396661e318d2107a3d36a89a1`, digest OCI `sha256:273f608813103f40c1844281bedd6a0997909d7f5743d6339e757868a6864099`.
- **Base:** Aurora Stable, `sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92`.
- **Ambiente:** VM VirtualBox da homologação H7, em 19/11/2026.
- **Sessão:** 1920×1080 a 100%, idioma pt-BR, usuário de demonstração `enthroned`, perfil Classic (exceto `desktop-modern.png`).
- **Formato:** PNG 1920×1080, 7 arquivos, cerca de 9,5 MB no total. Uma recompressão adicional foi testada sem ganho relevante, porque o conteúdo é fotográfico.

## Revisão de privacidade

Cada captura foi conferida em tamanho original, sem credenciais, notificações, dados pessoais ou diálogos de erro. Só a conta de demonstração `enthroned` aparece, em `start-menu.png` e `lock-screen.png`, e o caminho `/var/home/enthroned` aparece em `dolphin.png`. O campo de senha de `lock-screen.png` mostra um único caractere digitado, que não revela nenhum valor.

## Observações visuais

Detalhes cosméticos da VM que não foram retocados, para manter as capturas fiéis ao sistema: o ícone genérico do Brave na etapa 3 do Welcome e a coluna Tipo do Dolphin ainda em inglês ("Folder").

## Ao substituir uma captura

Use uma sessão de demonstração com dados fictícios e revise o arquivo em tamanho original para não expor nomes, notificações, endereços ou caminhos pessoais. Atualize a identificação da build, o idioma, a resolução e a escala acima, e mantenha o texto alternativo nos dois READMEs, no idioma de cada página. Para capturas localizadas, acrescente `-en` ou `-pt-br` ao nome antes de `.png`.
