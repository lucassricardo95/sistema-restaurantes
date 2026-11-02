-- Sementes NEUTRAS de um restaurante novo (nada de dados de outro restaurante). Idempotente.
insert into public.formas_pagamento (nome, ativa, visivel_cardapio, taxa_percentual, taxa_fixa, prazo_dias, permite_troco, ordem, acrescimo_percentual, acrescimo_fixo, preco_proprio, aceita_online, tipo_online)
select v.* from (values
  ('Dinheiro', true, true, 0.00, 0.00, 0, true, 1, 0, 0, false, false, null::text),
  ('Pix', true, true, 0.00, 0.00, 0, false, 2, 0, 0, false, true, 'pix'),
  ('Cartão de Débito', true, true, 0.00, 0.00, 0, false, 3, 0, 0, false, true, 'debito'),
  ('Cartão de Crédito', true, true, 0.00, 0.00, 0, false, 4, 0, 0, false, true, 'credito'),
  ('iFood', true, false, 0.00, 0.00, 0, false, 6, 0, 0, true, false, null),
  ('iFood (pagar na entrega)', false, false, 0.00, 0.00, 0, false, 99, 0, 0, false, false, null),
  ('iFood (pago no app)', false, false, 0.00, 0.00, 0, false, 99, 0, 0, false, false, null)
) as v(nome, ativa, visivel_cardapio, taxa_percentual, taxa_fixa, prazo_dias, permite_troco, ordem, acrescimo_percentual, acrescimo_fixo, preco_proprio, aceita_online, tipo_online)
where not exists (select 1 from public.formas_pagamento f where f.nome = v.nome);

insert into public.configuracoes_fotos (id, onde_guardar, destino_padrao_upload, drive_preferido, sincronizacao_drives, replicar_antigas, historico_fotos_ativo)
values (true, 'drive_apenas', 'ambos', 'auto', 'manual', 'ativas', true) on conflict (id) do nothing;
insert into public.contingencia_config (id, timeout_supabase_ms, falhas_para_planilha, timeout_planilha_ms, falhas_para_contingencia, reconciliacao_lote)
values (true, 8000, 3, 12000, 3, 50) on conflict (id) do nothing;
insert into public.integracoes_config (provedor, ligado, modo, checklist, config) values
  ('ifood', false, 'producao', '{"conta_dev": false}', '{"baixaEstoque": "confirmacao", "enviarPrecos": true, "pausarSemEstoque": true, "abrirFecharComCaixa": true, "retencaoClientesDias": 90, "confirmacaoAutomatica": true}'),
  ('mercadopago', false, 'homologacao', '{}', '{"pixValidadeMin": 15, "testeNoCardapio": false}'),
  ('nfce', false, 'homologacao', '{}', '{"canais": ["balcao"], "emitirQuando": "pagamento"}')
on conflict (provedor) do nothing;
insert into public.versoes_sync (grupo, n) values ('cad', 1), ('din', 1) on conflict (grupo) do nothing;
insert into public.sync_estado (id) values (true) on conflict (id) do nothing;
insert into public.ifood_loja (id, fechada_por_nos) values (true, false) on conflict (id) do nothing;
insert into public.fiscal_empresa (id, regime, serie, aliquota_simples) values (true, 'simples', 1, 0) on conflict (id) do nothing;
insert into public.ai_config (id) values (true) on conflict (id) do nothing;

-- linhas únicas que as telas esperam existir (sem elas a aba do iFood e o Caixa ficam em "Carregando…")
insert into public.caixa_config (id) values (true) on conflict (id) do nothing;
insert into public.ifood_estado (id) values (true) on conflict (id) do nothing;
insert into public.ifood_token (id) values (true) on conflict (id) do nothing;
