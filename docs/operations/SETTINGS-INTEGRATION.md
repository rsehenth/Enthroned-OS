# Integração do Enthroned Settings

Estado: **SOURCE READY / BUILD BLOCKED**. Compilação e execução Qt ainda não realizadas.

O `Containerfile` usa `apps-builder` sobre o mesmo estágio Aurora `runtime`.
CMake compila Settings e executa seu teste nativo antes de instalar em `/out`.
A imagem final recebe somente essa instalação, incluindo executável, desktop,
metainfo, ícone e notifyrc. Os pacotes de desenvolvimento ficam no builder.

O portão `ENTHRONED_SETTINGS_ALLOW_MUTATION` permanece fechado por padrão.
Não habilitar atualização, rollback ou reinicialização sem homologação específica.
A verificação da imagem testa dependências e inicialização QML em modo demo,
sem rede e com diretórios temporários; isso não comprova uma sessão KDE.

Procedimento atual de build e autorizações: [BUILD.md](BUILD.md).

## Lote 4 (configurações gerais)

O app agora tem 12 áreas, busca local e informações reais do dispositivo
(ver `docs/phases/LOTE-4-CONFIGURACOES-GERAIS.md` e ADR-0007). Para a imagem:

- Nenhum pacote novo. Usa `kcmshell6`, `plasma-apply-colorscheme`,
  `plasma-apply-wallpaperimage` (Plasma) e, se presentes, `lspci`, `orca`.
  Ausentes → o recurso correspondente fica desabilitado com aviso.
- `release-channel.json` ganhou `expected_image_references` (vazio até existir o
  registro). Preenchê-lo faz qualquer outra origem bloquear atualização do
  sistema na central; imagens genéricas Fedora/CentOS já bloqueiam hoje.
- O app nunca executa `bootc switch/rebase`, `dnf` ou `rpm-ostree`.

## Como executar o app em desenvolvimento (fora da imagem)

- Ambiente com Qt6/KF6 (ex.: container Fedora ou a própria VM):
  ```
  cmake -S settings -B build -DCMAKE_BUILD_TYPE=Debug
  cmake --build build -j"$(nproc)"
  ./build/enthroned-settings --demo            # dados fictícios
  ./build/enthroned-settings                    # leitura real; mutáveis bloqueados
  ```

## Verificações locais (sem Qt)

```
just verify-settings      # checagens estáticas + testes node (ver docs/validation/BATCH-4-STATIC-VALIDATION.md)
just verify-desktop       # regressão F2 (116 checagens)
just verify-source        # regressão F1
```

## Módulos KCM (opcional, fase futura)

A F3 optou por app autônomo (ADR-0005 §5). Um KCM dedicado (ex.: painel
“Enthroned” dentro do System Settings) exigiria compilar plugin C++ contra
a API KCM do Plasma; permanece como opção futura — a Aparência já reaproveita
o `enthroned-profile` e as páginas Aplicativos/Dispositivos abrem módulos
nativos existentes via `kcmshell6`.
