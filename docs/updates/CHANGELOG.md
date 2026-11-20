# Enthroned OS - changelog de imagens do canal

Este arquivo alimenta a fase `notes` do pipeline de atualização
(`scripts/update-pipeline.sh`): a seção `## <tag>` mais recente entra no
`output/release-notes.json` de cada build. Escreva em linguagem simples,
sem travessos decorativos, descrevendo o que muda para quem usa.

## Unreleased (canal f1-dev)

- Lote 8: Central de Atualizações executando atualização real do sistema
  (bootc transacional), atualização separada de aplicativos Flatpak
  (instalações de usuário e sistema) e recuperação para a versão anterior
  (rollback protegido).
- Pipeline de reconstrução sobre a base Aurora Stable atualizada, com
  verificações estáticas, `bootc container lint` e versionamento de imagens.
- Publicação em registro e assinatura cosign continuam desligadas até
  configuração e aprovação humana (ADR-0002).
