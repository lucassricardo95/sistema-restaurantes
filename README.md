# Painel de Revenda

Esta página (a raiz do repositório) é o **Painel de Revenda**: cadastro dos restaurantes, passo a passo de implantação, marca, módulos e mensalidades.

- `modelo/` — código-modelo do sistema do restaurante. Cada restaurante recebe uma cópia no próprio repositório, com o arquivo `config-restaurante.js` preenchido pelo painel. Não é publicado daqui.
- Banco central: projeto Supabase `revenda` (tabelas `restaurantes`, `cobrancas`, `historico`; ping automático a cada 2 dias).
