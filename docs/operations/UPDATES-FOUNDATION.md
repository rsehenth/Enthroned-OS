# Fundação de atualizações (contrato preliminar — F1)

Estado: **fundação/contrato**. A Central de Atualizações gráfica (botão,
progresso dinâmico, consentimento, polkit) é escopo da **F3** e NÃO existe
aqui. Nada nesta F1 instala updater, aponta para registro fictício ou executa
rebase.

## Cadeia de atualização

```
Aurora/Fedora upstream (ghcr.io/ublue-os/aurora:stable)
        │  nova base disponível
        ▼
Build derivado Enthroned OS (just build; CI manual)
        │  'bootc container lint' + verify-image + registro de digest
        ▼
Verificações (validate.yml + verificação humana)
        │
        ▼
[PÓS-F1] Assinatura cosign + publicação no nosso registro (ghcr.io/<namespace>)
        │
        ▼
Usuário recebe atualização da NOSSA imagem:
        bootc upgrade (do ref Enthroned OS instalado)
```

## Regras fundamentais

1. **Rebase nunca deve apontar para Aurora genérico.** O sistema instalado
   referencia a imagem Enthroned OS publicada; `bootc upgrade` atualiza dentro
   do MESMO ref. `bootc switch` só é legítimo em: instalação inicial via ISO
   (`%post` do `iso.toml`) ou migração controlada documentada.
2. **Canais:** `f1-dev` (atual, `production_ready=false`) → futuro `stable`
   próprio. O canal vive em `release-channel.json` e na tag do registro.
   Nenhuma promessa de "stable" antes de validação completa.
3. **Versionamento:** imagem `0.1.0-dev` na F1; builds recebem
   `<tag>.<data>-<sha>` quando o git está limpo (receita `just build`).
   Changelog fiel por release — nunca listar item não implementado.
4. **Rollback:** o deployment anterior permanece no GRUB; `bootc rollback`
   restaura. Nossa camada pequena e sem mutação de kernel/partição mantém o
   rollback confiável.
5. **Imagem ≠ Flatpaks:** atualização de sistema via bootc (imagem OCI);
   aplicativos Flatpak atualizam via Flathub/usuário, separadamente. A Central
   da F3 deverá deixar isso explícito na UI.
6. **Segurança:** a partir da publicação real, toda imagem é assinada (cosign,
   por digest) e o rebase/upgrade valida a assinatura; sem chave configurada,
   não há publicação.

## Contrato preliminar para a F3 (sem implementação agora)

- Ação do usuário → consentimento explícito → `bootc upgrade` (ou `switch`
  somente para migração de canal) → progresso → reboot opt-in.
- Privilégio via **polkit**, sem daemon privilegiado paralelo.
- Fonte da verdade do estado: `bootc status` + `release-channel.json`.
- A Central NUNCA executa `bootc switch` para um ref não assinado/verificado.
