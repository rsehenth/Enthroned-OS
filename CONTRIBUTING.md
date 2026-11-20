# Contribuindo (F1)

Regras mínimas para manter a fundação confiável:

1. **Antes de qualquer PR**, rode num ambiente Linux (WSL2 serve):
   ```bash
   just check && just lint && bash scripts/verify-source.sh
   ```
   CI deve ficar verde; `validate.yml` roda exatamente essas checagens.
2. **Mudanças pequenas e idempotentes.** Toda customização de imagem passa por
   `build_files/build.sh` + `system_files/`. Nada de pacotes supérfluos, COPR
   não habilitado, serviços não alterados sem ADR.
3. **Nunca versionar segredos** (`cosign.key`, chaves, `.env`). O
   `.gitignore` cobre; `verify-source.sh` falha se aparecer material de chave
   privada.
4. **Workflows**: sem gatilhos automáticos de build/publicação. Novos
   workflows precisam de `workflow_dispatch` e `permissions` mínimos; actions
   de terceiros sempre pinadas por SHA.
5. **Base da imagem**: só `ghcr.io/ublue-os/aurora:stable` (ou digest pinado
   futuro). Mudança de base exige novo ADR.
6. **Honestidade de estado**: não marcar PASS/executado sem evidência
   (estados: PASS / PARTIAL / BLOCKED / NOT RUN).
7. Idioma dos documentos: PT-BR; código e mensagens de script: inglês.

Pendências abertas vivem em `docs/phases/F1-FOUNDATION.md` e
`docs/operations/KNOWN-LIMITATIONS.md`.
