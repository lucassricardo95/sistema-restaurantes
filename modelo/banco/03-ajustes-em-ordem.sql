-- Texas Burger · Supabase — 03-ajustes-em-ordem.sql
-- Todas as mudanças feitas depois da cópia completa de 18/10/2026, juntas e na ordem certa (antes eram 90 arquivos soltos, do 03 ao 92).
-- Rode DEPOIS do 01-estrutura.sql e do 02-dados.sql. Cada bloco pode ser rodado de novo sem erro.


-- ======================================================================
-- 03-agendamentos.sql
-- ======================================================================
-- =====================================================================
-- TEXAS BURGER · 03-agendamentos.sql  (26 tarefas do pg_cron, iguais às do Supabase em 18/10/2026)
-- Rode POR ÚLTIMO, depois de recriar os segredos do Vault (LEIA-ME-REFAZER.txt, passo 4): várias tarefas chamam as Edge Functions
-- por public.chamar_edge(), que usa o segredo 'service_key' do Vault.
-- =====================================================================
select cron.schedule('ai_limpeza', '15 6 * * *', '
  delete from public.ai_cache where expira_em < now();
  delete from public.ai_log where criado_em < now() - interval ''30 days'';
  delete from public.ai_uso where dia < current_date - 90;
');
select cron.schedule('arquivar-diario', '0 8 * * *', ' select public.chamar_edge(''arquivar-antigos'',''{}''::jsonb); ');
select cron.schedule('arquivar-emergencia-horario', '30 * * * *', ' select public.chamar_edge(''arquivar-antigos'',''{"emergencia":true}''::jsonb); ');
select cron.schedule('auditoria-ip-limpeza', '50 6 * * *', 'update public.auditoria set ip = null where ip is not null and data_hora < now() - interval ''90 days''');
select cron.schedule('backup-horario', '0 * * * *', ' select public.chamar_edge(''criar-backup'',''{"tipo":"Automático","cron":true}''); ');
select cron.schedule('chat-limpeza-diaria', '45 6 * * *', '
  delete from public.entregador_posicoes where atualizado_em < now() - interval ''12 hours'';
  delete from public.pedido_destinos d using public.vendas v
   where v.id = d.venda_id and (v.status_pedido::text in (''Entregue'', ''Retirada'', ''Servida'') or d.criado_em < now() - interval ''2 days'');
  delete from public.chat_conversas where estado = ''recepcao'' and atualizado_em < now() - interval ''2 days'';
');
select cron.schedule('contas-aniversarios', '10 9 * * *', 'select public._job_aniversarios()');
select cron.schedule('contas-campanhas', '20 9 * * *', 'select public._job_campanhas()');
select cron.schedule('contas-inativas', '50 4 * * 0', 'select public._job_contas_inativas()');
select cron.schedule('contas-sem-aceite', '40 4 * * 0', 'select public._job_contas_sem_aceite()');
select cron.schedule('contingencia-espelho-10min', '3,13,23,33,43,53 * * * *', ' select public.chamar_edge(''planilha-admin'', ''{"acao":"sincronizarContingencia","rapido":true}''::jsonb); ');
select cron.schedule('contingencia-espelho-diario', '0 6 * * *', ' select public.chamar_edge(''planilha-admin'', ''{"acao":"sincronizarContingencia"}''::jsonb); ');
select cron.schedule('erros_cliente_limpeza', '30 6 * * *', ' delete from public.erros_cliente where criado_em < now() - interval ''14 days'' ');
select cron.schedule('ifood-limpeza-diaria', '55 6 * * *', 'select public.ifood_limpar()');
select cron.schedule('ifood-sync-minuto', '* * * * *', 'select case when public._integracao_ligada(''ifood'') then public.chamar_edge(''ifood-sync'', ''{}''::jsonb) end');
select cron.schedule('integridade-diaria', '10 9 * * *', ' select public.chamar_edge(''conferir-integridade'',''{"cron":true}''::jsonb); ');
select cron.schedule('lgpd-anonimizar', '30 4 * * 0', 'select public._job_lgpd_anonimizar()');
select cron.schedule('mp-cancelar-pix', '* * * * *', 'select case when jsonb_array_length(public.mp_pendentes_cancelar()) > 0 then public.chamar_edge(''mp-cancelar'', ''{}''::jsonb) end');
select cron.schedule('mp-expirar-reservas', '* * * * *', 'select public.mp_expirar_reservas()');
select cron.schedule('mp-lgpd-diario', '30 5 * * *', 'select public._job_mp_lgpd()');
select cron.schedule('nfce-emitir-minuto', '* * * * *', 'select case when public._integracao_ligada(''nfce'') and (exists (select 1 from public.nfce_notas where estado in (''pendente'', ''duvida'', ''contingencia'', ''cancelando'') and emitir_apos <= now() and proxima_tentativa <= now()) or exists (select 1 from public.nfce_inutilizacoes where estado in (''pendente'', ''duvida''))) then public.chamar_edge(''nfce-emitir'', ''{}''::jsonb) end');
select cron.schedule('ping-2dias', '0 12 */2 * *', ' select public.chamar_edge(''ping'',''{}''::jsonb); ');
select cron.schedule('push-clientes-feedback', '*/5 * * * *', 'select public._push_clientes_feedback()');
select cron.schedule('sync-alerta-30min', '*/30 * * * *', ' select public.api_sync_verificar_alerta(); ');
select cron.schedule('sync-fila-2min', '*/2 * * * *', ' select public.chamar_edge(''sync-fila'',''{}''::jsonb); ');
select cron.schedule('sync-limpar-diario', '0 6 * * *', ' select public.api_sync_limpar(); ');


-- ======================================================================
-- 04-compras-v2.sql
-- ======================================================================
-- =====================================================================
-- TEXAS BURGER · Fase 3.1 — Entrada de compras (nota fiscal / cupom) · 18/10/2026
-- Evolui o módulo de Compras. Tudo ADITIVO: colunas novas com padrão, tabelas novas, funções substituídas
-- mantendo o mesmo nome e os mesmos parâmetros antigos (o app antigo continua funcionando).
-- Regras (decididas pelo dono): custo = ÚLTIMO custo pela data da nota, por unidade base; nº da nota e
-- anexo opcional; origem do dinheiro (caixa / conta / cartão / dinheiro do dono / a pagar); vários
-- pagamentos por nota; estorno completo; histórico de custos; embalagem lembrada por fornecedor;
-- despesa na categoria certa; despesa de compra só se mexe pela compra.
-- =====================================================================

-- ---------- 1. estrutura ----------
alter table public.compras
  add column if not exists numero_nota text not null default '',
  add column if not exists frete numeric(12,2) not null default 0,
  add column if not exists desconto numeric(12,2) not null default 0,
  add column if not exists anexo_path text,
  add column if not exists anexo_nome text,
  add column if not exists editada_de uuid,
  add column if not exists substituida_por uuid,
  add column if not exists estornada_em timestamptz,
  add column if not exists estornada_por uuid,
  add column if not exists estorno_motivo text,
  add column if not exists atualizada_em timestamptz;

-- (sem trocar as restrições antigas: "Estornada" = status Cancelada + estornada_em preenchido; "Parcial" = calculado na listagem)

alter table public.compra_itens
  add column if not exists categoria text,
  add column if not exists descricao_nota text,
  add column if not exists fator numeric,
  add column if not exists embalagem text,
  add column if not exists qtd_base numeric,
  add column if not exists valor_rateado numeric(12,2),
  add column if not exists custo_base numeric;

alter table public.despesas
  add column if not exists compra_id uuid,              -- sem FK de propósito (evita ciclo compras <-> despesas na restauração do backup)
  add column if not exists origem_pagamento text;
create index if not exists despesas_compra_idx on public.despesas (compra_id) where compra_id is not null;

create table if not exists public.compra_pagamentos (
  id uuid primary key default gen_random_uuid(),
  compra_id uuid not null,
  valor numeric(12,2) not null check (valor > 0),
  origem text not null check (origem = any (array['caixa','conta','cartao','dono','apagar'])),
  vencimento date,
  criado_em timestamptz not null default now()
);
create index if not exists compra_pagamentos_compra_idx on public.compra_pagamentos (compra_id);

create table if not exists public.compra_custos (
  id uuid primary key default gen_random_uuid(),
  ingrediente_id uuid not null,
  compra_id uuid,
  compra_item_id uuid,
  data_nota date not null,
  custo_unitario numeric not null,
  custo_anterior numeric,
  aplicado boolean not null default false,            -- virou o custo atual do ingrediente quando foi lançada
  ativo boolean not null default true,                -- false = a nota foi estornada
  criado_em timestamptz not null default now(),
  criado_por uuid
);
create index if not exists compra_custos_ing_idx on public.compra_custos (ingrediente_id, data_nota desc, criado_em desc);
create index if not exists compra_custos_compra_idx on public.compra_custos (compra_id);

create table if not exists public.compra_vinculos (
  fornecedor_id uuid not null,
  chave text not null,
  ingrediente_id uuid not null,
  unidade text not null,
  fator numeric,
  embalagem text,
  atualizado_em timestamptz not null default now(),
  primary key (fornecedor_id, chave)
);
create index if not exists compra_vinculos_ing_idx on public.compra_vinculos (ingrediente_id);

alter table public.compra_pagamentos enable row level security;
alter table public.compra_custos enable row level security;
alter table public.compra_vinculos enable row level security;
create policy compra_pagamentos_ler on public.compra_pagamentos for select to authenticated using (tem_nivel('Admin'));
create policy compra_custos_ler on public.compra_custos for select to authenticated using (tem_nivel('Admin'));
create policy compra_vinculos_ler on public.compra_vinculos for select to authenticated using (tem_nivel('Admin'));

-- histórico inicial: o custo atual de cada ingrediente vira a primeira linha (data de hoje), para o estorno saber voltar
insert into public.compra_custos (ingrediente_id, data_nota, custo_unitario, custo_anterior, aplicado, ativo, criado_em)
select e.id, (now() at time zone 'America/Sao_Paulo')::date - 3650, e.custo_unitario, null, true, true, now() - interval '10 years'
from public.estoque e
where coalesce(e.custo_unitario, 0) > 0 and not exists (select 1 from public.compra_custos h where h.ingrediente_id = e.id);

-- ---------- 2. funções auxiliares ----------
create or replace function public._compra_chave(t text) returns text language sql immutable set search_path to 'public' as $$
  select left(regexp_replace(lower(translate(coalesce(t, ''), 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '[^a-z0-9]+', ' ', 'g'), 80)
$$;
create or replace function public._compra_nota_norm(t text) returns text language sql immutable set search_path to 'public' as $$
  select ltrim(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '0')
$$;

-- origem das linhas de pagamento (aceita o formato antigo: pagamento + saiuDoCaixa + vencimento)
create or replace function public._compra_pags(p jsonb, p_total numeric) returns jsonb language plpgsql stable set search_path to 'public' as $$
declare v jsonb := '[]'::jsonb; x jsonb; v_o text;
begin
  if jsonb_typeof(p->'pagamentos') = 'array' and jsonb_array_length(p->'pagamentos') > 0 then
    for x in select value from jsonb_array_elements(p->'pagamentos') loop
      v_o := lower(btrim(coalesce(x->>'origem', '')));
      v_o := case v_o when 'cartão' then 'cartao' when 'a pagar' then 'apagar' when 'a_pagar' then 'apagar' else v_o end;
      v := v || jsonb_build_object('valor', round(_num(x->>'valor'), 2), 'origem', v_o, 'vencimento', x->>'vencimento');
    end loop;
    return v;
  end if;
  if p->>'pagamento' = 'A pagar' then
    return jsonb_build_array(jsonb_build_object('valor', p_total, 'origem', 'apagar', 'vencimento', p->>'vencimento'));
  end if;
  return jsonb_build_array(jsonb_build_object('valor', p_total, 'origem', case when coalesce(p->>'saiuDoCaixa', '') in ('true','t') then 'caixa' else 'conta' end));
end $$;

-- valida as linhas de pagamento contra o total da nota
create or replace function public._compra_pags_validar(p_pags jsonb, p_total numeric) returns text language plpgsql stable set search_path to 'public' as $$
declare x jsonb; v_soma numeric := 0; v_caixa uuid;
begin
  if jsonb_typeof(p_pags) <> 'array' or jsonb_array_length(p_pags) = 0 then return 'Informe como a compra foi paga.'; end if;
  if jsonb_array_length(p_pags) > 10 then return 'No máximo 10 pagamentos por nota.'; end if;
  for x in select value from jsonb_array_elements(p_pags) loop
    if not (x->>'origem' = any (array['caixa','conta','cartao','dono','apagar'])) then return 'Origem do pagamento inválida.'; end if;
    if _num(x->>'valor') <= 0 then return 'Cada pagamento precisa de valor maior que zero.'; end if;
    if x->>'origem' = 'apagar' and _data_iso(x->>'vencimento') is null then return 'Informe o vencimento do que vai ser pago depois.'; end if;
    if x->>'origem' = 'caixa' then
      select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;
      if v_caixa is null then return 'Para dizer que o dinheiro saiu do caixa, o caixa precisa estar aberto. Se foi pago com o caixa de outro dia, escolha outra origem e explique na observação.'; end if;
      if _caixa_vencido(v_caixa) then return _caixa_msg_vencido(); end if;
    end if;
    v_soma := v_soma + round(_num(x->>'valor'), 2);
  end loop;
  if round(v_soma, 2) <> round(p_total, 2) then
    return 'A soma dos pagamentos (R$ ' || _dinheiro(v_soma) || ') precisa ser igual ao total da nota (R$ ' || _dinheiro(p_total) || ').';
  end if;
  return null;
end $$;

-- recebe a compra: estoque, último custo + histórico, despesas por categoria e por pagamento
create or replace function public._compra_receber2(p_id uuid, p_pags jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c compras%rowtype; i record; e estoque%rowtype; v_q numeric; v_forn text; v_soma numeric; v_frete numeric; v_desc numeric; v_total numeric;
        v_acum numeric := 0; v_n int; v_k int := 0; v_rat numeric; v_custo numeric; v_mais_nova boolean; v_cat text; v_grupos jsonb := '{}'::jsonb;
        x jsonb; g record; v_parte numeric; v_resto numeric; v_maior text; v_desp uuid; v_primeira uuid; v_status text; v_pg text; v_tem_pago boolean := false; v_tem_apagar boolean := false;
        v_nota text; v_ids uuid[] := '{}'; v_prej jsonb;
begin
  if not tem_nivel('Admin') then raise exception '%', 'Seu perfil não tem permissão para esta ação.'; end if;
  select * into c from compras where id = p_id for update;
  if not found then raise exception '%', 'Compra não encontrada.'; end if;
  if c.status <> 'Pedido' then raise exception '%', 'Esta compra já foi ' || lower(c.status) || '.'; end if;
  select nome into v_forn from fornecedores where id = c.fornecedor_id;
  select coalesce(sum(valor_total), 0), count(*) into v_soma, v_n from compra_itens where compra_id = c.id;
  v_frete := coalesce(c.frete, 0); v_desc := coalesce(c.desconto, 0);
  v_total := round(v_soma + v_frete - v_desc, 2);
  if v_total < 0 then raise exception '%', 'O desconto não pode ser maior que a soma dos itens com o frete.'; end if;
  v_nota := case when coalesce(c.numero_nota, '') <> '' then ' (nota ' || c.numero_nota || ')' else '' end;

  -- itens: rateio de frete e desconto proporcional ao valor (o último item leva os centavos que sobram)
  for i in select * from compra_itens where compra_id = c.id order by id loop
    v_k := v_k + 1;
    if v_k = v_n then v_rat := round(v_total - v_acum, 2);
    elsif v_soma > 0 then v_rat := round(i.valor_total + (v_frete - v_desc) * i.valor_total / v_soma, 2);
    else v_rat := round((v_frete - v_desc) / v_n, 2); end if;
    v_acum := v_acum + v_rat;
    if i.ingrediente_id is not null then
      select * into e from estoque where id = i.ingrediente_id for update;
      if not found then raise exception '%', 'Ingrediente de "' || i.descricao || '" não existe mais no estoque.'; end if;
      v_q := _converter_unidade(i.quantidade, i.unidade, e.unidade::text);
      if v_q is null or v_q <= 0 then raise exception '%', 'A unidade "' || i.unidade || '" de ' || e.ingrediente || ' não combina com a do estoque (' || e.unidade || ').'; end if;
      v_custo := round(v_rat / v_q, 6);
      -- ÚLTIMO CUSTO pela data da nota: só troca o custo se não houver nota MAIS NOVA já lançada (empate: vale a lançada agora)
      v_mais_nova := exists (select 1 from compra_custos h where h.ingrediente_id = e.id and h.ativo and h.aplicado and h.data_nota > c.data);
      insert into compra_custos (ingrediente_id, compra_id, compra_item_id, data_nota, custo_unitario, custo_anterior, aplicado, criado_por)
      values (e.id, c.id, i.id, c.data, v_custo, e.custo_unitario, not v_mais_nova, auth.uid());
      update estoque set quantidade = e.quantidade + v_q, custo_unitario = case when v_mais_nova then custo_unitario else v_custo end where id = e.id;
      insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
      values (e.id, 'Entrada', v_q, e.quantidade, e.quantidade + v_q, 'Compra de ' || v_forn || v_nota || ' (R$ ' || _dinheiro(v_rat) || ')', auth.uid());
      update compra_itens set qtd_base = v_q, valor_rateado = v_rat, custo_base = v_custo, categoria = coalesce(categoria, 'Insumos') where id = i.id;
      v_ids := v_ids || e.id;
      v_cat := 'Insumos';
    else
      v_cat := _categoria_despesa(coalesce(i.categoria, 'Insumos'));
      update compra_itens set valor_rateado = v_rat, categoria = v_cat where id = i.id;
    end if;
    v_grupos := jsonb_set(v_grupos, array[v_cat], to_jsonb(coalesce((v_grupos->>v_cat)::numeric, 0) + v_rat));
  end loop;

  -- despesas: cada pagamento é repartido entre as categorias da nota (o DRE fica certo mesmo em nota mista)
  if v_total > 0 then
    select key into v_maior from jsonb_each_text(v_grupos) order by value::numeric desc, key limit 1;
    for x in select value from jsonb_array_elements(p_pags) loop
      v_resto := round((x->>'valor')::numeric, 2);
      for g in select key as cat, value::numeric as val from jsonb_each_text(v_grupos) order by (key = v_maior), key loop
        if g.cat = v_maior then v_parte := v_resto;
        else v_parte := round((x->>'valor')::numeric * g.val / v_total, 2); v_resto := v_resto - v_parte; end if;
        if v_parte <= 0 then continue; end if;
        insert into despesas (data_hora, descricao, valor, observacao, status, categoria, vencimento, situacao, competencia, saiu_do_caixa, compra_id, origem_pagamento)
        values (case when x->>'origem' = 'apagar' then _meio_dia(_data_iso(x->>'vencimento')) else now() end,
                'Compra: ' || v_forn || v_nota, v_parte,
                'Compra ' || to_char(c.data, 'DD/MM/YYYY') || case when coalesce(c.observacao, '') <> '' then ' - ' || c.observacao else '' end,
                (case when x->>'origem' = 'apagar' then 'A pagar' else 'Paga' end)::status_despesa, g.cat,
                case when x->>'origem' = 'apagar' then _data_iso(x->>'vencimento') end,
                case when x->>'origem' = 'apagar' then 'A pagar' else 'Paga' end,
                case when x->>'origem' = 'apagar' then to_char(_data_iso(x->>'vencimento'), 'YYYY-MM') end,
                (x->>'origem') = 'caixa', c.id, case when x->>'origem' = 'apagar' then null else x->>'origem' end)
        returning id into v_desp;
        if v_primeira is null then v_primeira := v_desp; end if;
      end loop;
      insert into compra_pagamentos (compra_id, valor, origem, vencimento) values (c.id, round((x->>'valor')::numeric, 2), x->>'origem', _data_iso(x->>'vencimento'));
      if x->>'origem' = 'apagar' then v_tem_apagar := true; else v_tem_pago := true; end if;
    end loop;
  end if;
  v_pg := case when v_tem_apagar then 'A pagar' else 'Pago' end;   -- "Parcial" é mostrado pela listagem (compra_pagamentos)
  update compras set status = 'Recebida', recebida_em = now(), total = v_total, pagamento = v_pg,
         vencimento = (select min(_data_iso(value->>'vencimento')) from jsonb_array_elements(p_pags) where value->>'origem' = 'apagar'),
         despesa_id = v_primeira, atualizada_em = now() where id = c.id;

  -- produtos e combos que passaram a dar prejuízo (preço abaixo do custo novo)
  select coalesce(jsonb_agg(distinct jsonb_build_object('produto', pr.nome, 'forma', fp.nome, 'preco', pp.preco, 'custo', pp.custo)), '[]'::jsonb) into v_prej
  from produto_precos pp join produtos pr on pr.id = pp.produto_id join formas_pagamento fp on fp.id = pp.forma_pagamento_id
  where pr.ativo and pp.custo > pp.preco and pp.produto_id in (select produto_id from produto_ingredientes where ingrediente_id = any (v_ids));
  return jsonb_build_object('total', v_total, 'prejuizo', v_prej);
end $$;

-- compatibilidade: a assinatura antiga continua existindo e passa pelo fluxo novo
create or replace function public._compra_receber(p_id uuid, p_pagamento text, p_venc date, p_saiu boolean) returns text language plpgsql security definer set search_path to 'public' as $$
declare v_t numeric;
begin
  if not tem_nivel('Admin') then raise exception '%', 'Seu perfil não tem permissão para esta ação.'; end if;
  select coalesce(sum(valor_total), 0) + coalesce(max(c.frete), 0) - coalesce(max(c.desconto), 0) into v_t from compras c left join compra_itens i on i.compra_id = c.id where c.id = p_id;
  perform _compra_receber2(p_id, _compra_pags(jsonb_build_object('pagamento', p_pagamento, 'vencimento', p_venc, 'saiuDoCaixa', p_saiu), round(v_t, 2)));
  return null;
end $$;

-- ---------- 3. registrar compra ----------
create or replace function public.api_registrar_compra(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_forn uuid; v_fnome text; x jsonb; v_n int := 0; v_soma numeric := 0; v_id uuid := gen_random_uuid();
        v_status text := case when p->>'status' = 'Pedido' then 'Pedido' else 'Recebida' end;
        v_data date := coalesce(_data_iso(p->>'data'), (now() at time zone 'America/Sao_Paulo')::date);
        v_org text := case when p->>'origem' = 'ia' then 'ia' else 'manual' end; v_ing uuid; v_ie estoque%rowtype; v_val numeric; v_qtd numeric; v_un text; v_desc text;
        v_nota text := left(btrim(coalesce(p->>'numeroNota', '')), 60); v_obs text := left(btrim(coalesce(p->>'observacao', '')), 300);
        v_frete numeric := round(_num(p->>'frete'), 2); v_descnota numeric := round(_num(p->>'desconto'), 2); v_total numeric; v_pags jsonb; v_erro text;
        v_anexo text := nullif(left(btrim(coalesce(p->>'anexoPath', '')), 300), ''); v_editada uuid := _uuid(p->>'editadaDe');
        v_conf boolean := coalesce(p->>'confirmar', '') in ('true','t'); v_dup jsonb; v_var jsonb := '[]'::jsonb; v_q numeric; v_cu numeric; v_res jsonb; v_cat text; v_dn text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_data > (now() at time zone 'America/Sao_Paulo')::date + 1 then return _falha('A data da nota não pode ser no futuro.'); end if;
  if v_frete < 0 or v_descnota < 0 then return _falha('Frete e desconto não podem ser negativos.'); end if;
  v_forn := _uuid(p->>'fornecedorId');
  if v_forn is null and btrim(coalesce(p->>'fornecedorNome', '')) <> '' then
    select id into v_forn from fornecedores where lower(btrim(nome)) = lower(btrim(p->>'fornecedorNome'));
    if v_forn is null then return _falha('Fornecedor "' || btrim(p->>'fornecedorNome') || '" não está cadastrado. Cadastre-o primeiro.'); end if;
  end if;
  select nome into v_fnome from fornecedores where id = v_forn and ativo;
  if v_fnome is null then return _falha('Escolha um fornecedor ativo.'); end if;
  if jsonb_typeof(p->'itens') <> 'array' or jsonb_array_length(p->'itens') = 0 then return _falha('Informe ao menos um item da compra.'); end if;
  if jsonb_array_length(p->'itens') > 40 then return _falha('No máximo 40 itens por nota.'); end if;
  -- rastro mínimo sem anexo: nº da nota ou observação (proposta da assistente: o registro diz quem confirmou)
  if v_anexo is null and v_nota = '' and v_obs = '' then
    if v_org = 'ia' then v_obs := 'Lançada pela assistente, confirmada por ' || coalesce(_login_de(auth.uid()), 'Admin');
    else return _falha('Sem foto da nota: informe o número da nota ou uma observação (para ficar o rastro).'); end if;
  end if;
  if v_editada is not null and not exists (select 1 from compras where id = v_editada and estornada_em is not null) then
    return _falha('A nota que está sendo corrigida precisa estar estornada antes.');
  end if;

  -- 1) só confere (nada é gravado se algo estiver errado)
  for x in select value from jsonb_array_elements(p->'itens') loop
    v_qtd := _num(x->>'quantidade'); v_val := round(_num(x->>'valorTotal'), 2); v_un := lower(btrim(coalesce(x->>'unidade', '')));
    v_ing := _uuid(x->>'ingredienteId'); v_desc := btrim(coalesce(x->>'descricao', x->>'ingrediente', ''));
    if v_ing is null and btrim(coalesce(x->>'ingrediente', '')) <> '' then select id into v_ing from estoque where lower(btrim(ingrediente)) = lower(btrim(x->>'ingrediente')) limit 1; end if;
    if v_ing is not null then
      select * into v_ie from estoque where id = v_ing;
      if not found then return _falha('Ingrediente não encontrado no estoque.'); end if;
      if v_un = '' then v_un := v_ie.unidade::text; end if;
      if _converter_unidade(1, v_un, v_ie.unidade::text) is null then return _falha('A unidade "' || v_un || '" não combina com a do estoque de ' || v_ie.ingrediente || ' (' || v_ie.unidade || ').'); end if;
      if v_qtd > 0 and v_val > 0 and coalesce(v_ie.custo_unitario, 0) > 0 then
        v_q := _converter_unidade(v_qtd, v_un, v_ie.unidade::text); v_cu := v_val / v_q;
        if abs(v_cu - v_ie.custo_unitario) / v_ie.custo_unitario > 0.30 then
          v_var := v_var || jsonb_build_object('ingrediente', v_ie.ingrediente, 'unidade', v_ie.unidade, 'anterior', round(v_ie.custo_unitario, 4), 'novo', round(v_cu, 4),
                   'pct', round((v_cu - v_ie.custo_unitario) / v_ie.custo_unitario * 100));
        end if;
      end if;
    elsif v_desc = '' then return _falha('Cada item precisa de um nome ou de um ingrediente do estoque.');
    elsif btrim(coalesce(x->>'ingrediente', '')) <> '' and btrim(coalesce(x->>'descricao', '')) = '' then
      return _falha('Ingrediente "' || btrim(x->>'ingrediente') || '" não está no estoque. Cadastre-o em Estoque antes, ou informe só a descrição do item.');
    end if;
    if v_qtd <= 0 then return _falha('Informe a quantidade de "' || coalesce(nullif(v_desc, ''), v_ie.ingrediente) || '" maior que zero.'); end if;
    if v_val <= 0 then return _falha('Informe o valor de "' || coalesce(nullif(v_desc, ''), v_ie.ingrediente) || '" (maior que zero).'); end if;
    if v_val > 9999999 then return _falha('Valor alto demais em "' || coalesce(nullif(v_desc, ''), v_ie.ingrediente) || '".'); end if;
    v_soma := v_soma + v_val; v_ie := null;
  end loop;
  v_total := round(v_soma + v_frete - v_descnota, 2);
  if v_total <= 0 then return _falha('O total da nota precisa ser maior que zero (confira o desconto).'); end if;
  if p ? 'totalNota' and nullif(btrim(coalesce(p->>'totalNota', '')), '') is not null and round(_num(p->>'totalNota'), 2) <> v_total then
    return _falha('A soma dos itens + frete − desconto dá R$ ' || _dinheiro(v_total) || ', mas o total da nota informado é R$ ' || _dinheiro(_num(p->>'totalNota')) || '. Confira antes de salvar.');
  end if;
  if v_status = 'Recebida' then
    v_pags := _compra_pags(p, v_total);
    v_erro := _compra_pags_validar(v_pags, v_total);
    if v_erro is not null then return _falha(v_erro); end if;
  end if;
  -- nota repetida e custo muito diferente: pede confirmação antes de gravar
  if _compra_nota_norm(v_nota) <> '' then
    select jsonb_build_object('data', to_char(c.data, 'DD/MM/YYYY'), 'total', c.total) into v_dup from compras c
     where c.fornecedor_id = v_forn and _compra_nota_norm(c.numero_nota) = _compra_nota_norm(v_nota) and c.status in ('Pedido','Recebida') limit 1;
  end if;
  if not v_conf and (v_dup is not null or jsonb_array_length(v_var) > 0) then
    return jsonb_build_object('ok', false, 'precisaConfirmar', true, 'duplicada', v_dup, 'variacoes', v_var,
      'message', concat_ws(' ', case when v_dup is not null then 'Já existe a nota ' || v_nota || ' deste fornecedor (' || (v_dup->>'data') || ', R$ ' || _dinheiro((v_dup->>'total')::numeric) || ').' end,
                                case when jsonb_array_length(v_var) > 0 then 'Há custo muito diferente do anterior (mais de 30%): confira se não houve erro de digitação.' end));
  end if;

  -- 2) grava
  insert into compras (id, fornecedor_id, data, status, pagamento, observacao, origem, requisicao_id, criado_por, numero_nota, frete, desconto, anexo_path, anexo_nome, editada_de, atualizada_em)
  values (v_id, v_forn, v_data, 'Pedido', case when p->>'pagamento' = 'A pagar' then 'A pagar' else 'Pago' end, v_obs, v_org, v_req, auth.uid(), v_nota, v_frete, v_descnota, v_anexo,
          nullif(left(btrim(coalesce(p->>'anexoNome', '')), 120), ''), v_editada, now());
  for x in select value from jsonb_array_elements(p->'itens') loop
    v_qtd := _num(x->>'quantidade'); v_val := round(_num(x->>'valorTotal'), 2); v_un := lower(btrim(coalesce(x->>'unidade', '')));
    v_ing := _uuid(x->>'ingredienteId'); v_desc := btrim(coalesce(x->>'descricao', x->>'ingrediente', '')); v_dn := left(btrim(coalesce(x->>'descricaoNota', '')), 80);
    if v_ing is null and btrim(coalesce(x->>'ingrediente', '')) <> '' then select id into v_ing from estoque where lower(btrim(ingrediente)) = lower(btrim(x->>'ingrediente')) limit 1; end if;
    if v_ing is not null then select * into v_ie from estoque where id = v_ing; if v_un = '' then v_un := v_ie.unidade::text; end if; if v_desc = '' then v_desc := v_ie.ingrediente; end if; v_cat := null;
    else v_cat := _categoria_despesa(coalesce(nullif(x->>'categoria', ''), 'Insumos')); end if;
    if v_un = '' then v_un := 'un'; end if;
    insert into compra_itens (compra_id, ingrediente_id, descricao, quantidade, unidade, valor_total, categoria, descricao_nota, fator, embalagem)
    values (v_id, v_ing, left(v_desc, 80), v_qtd, left(v_un, 10), v_val, v_cat, nullif(v_dn, ''), nullif(_num(x->>'fator'), 0), nullif(left(btrim(coalesce(x->>'embalagem', '')), 40), ''));
    -- lembra o vínculo "como vem na nota deste fornecedor" -> ingrediente / unidade / embalagem
    if v_ing is not null and _compra_chave(coalesce(nullif(v_dn, ''), v_desc)) <> '' then
      insert into compra_vinculos (fornecedor_id, chave, ingrediente_id, unidade, fator, embalagem, atualizado_em)
      values (v_forn, _compra_chave(coalesce(nullif(v_dn, ''), v_desc)), v_ing, v_un, nullif(_num(x->>'fator'), 0), nullif(left(btrim(coalesce(x->>'embalagem', '')), 40), ''), now())
      on conflict (fornecedor_id, chave) do update set ingrediente_id = excluded.ingrediente_id, unidade = excluded.unidade, fator = excluded.fator, embalagem = excluded.embalagem, atualizado_em = now();
    end if;
    v_n := v_n + 1; v_ie := null;
  end loop;
  update compras set total = v_total where id = v_id;
  if v_editada is not null then update compras set substituida_por = v_id where id = v_editada; end if;
  if v_status = 'Recebida' then v_res := _compra_receber2(v_id, v_pags); end if;
  perform _auditar(case when v_editada is not null then 'Compra corrigida (relançada)' else 'Compra registrada' end,
    v_fnome || case when v_nota <> '' then ' | nota ' || v_nota else '' end || ' | R$ ' || _dinheiro(v_total) || ' | ' || v_n || ' item(ns) | ' || v_status || ' | ' || v_org
    || case when v_anexo is null then ' | sem comprovante' else '' end);
  v_r := jsonb_build_object('ok', true, 'id', v_id, 'prejuizo', coalesce(v_res->'prejuizo', '[]'::jsonb),
    'message', case when v_status = 'Recebida' then 'Nota registrada: estoque, custos e despesas atualizados. Total R$ ' || _dinheiro(v_total) || '.' else 'Pedido de compra registrado: R$ ' || _dinheiro(v_total) || '.' end);
  if v_req is not null then perform _idem_gravar(v_req, 'registrarCompra', v_r); end if;
  return v_r;
exception when others then
  if sqlstate = 'P0001' then return _falha(sqlerrm); end if;
  raise;
end $$;

-- ---------- 4. receber pedido de compra (com a origem do dinheiro) ----------
create or replace function public.api_receber_compra(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'id'); c compras%rowtype; v_t numeric; v_pags jsonb; v_erro text; v_res jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from compras where id = v_id;
  if not found then return _falha('Compra não encontrada.'); end if;
  if c.status <> 'Pedido' then return _falha('Esta compra já foi ' || lower(c.status) || '.'); end if;
  select round(coalesce(sum(valor_total), 0) + c.frete - c.desconto, 2) into v_t from compra_itens where compra_id = v_id;
  v_pags := _compra_pags(p, v_t);
  v_erro := _compra_pags_validar(v_pags, v_t);
  if v_erro is not null then return _falha(v_erro); end if;
  v_res := _compra_receber2(v_id, v_pags);
  perform _auditar('Compra recebida', 'R$ ' || _dinheiro(v_t));
  return jsonb_build_object('ok', true, 'prejuizo', coalesce(v_res->'prejuizo', '[]'::jsonb), 'message', 'Compra recebida: estoque, custos e despesas atualizados.');
exception when others then
  if sqlstate = 'P0001' then return _falha(sqlerrm); end if;
  raise;
end $$;

-- ---------- 5. estorno de nota recebida ----------
create or replace function public.api_estornar_compra(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'id'); c compras%rowtype; v_m text := left(btrim(coalesce(p->>'motivo', '')), 200); i record; e estoque%rowtype; h record; v_prev numeric;
        v_neg jsonb := '[]'::jsonb; v_conf boolean := coalesce(p->>'confirmarNegativo', '') in ('true','t'); v_novo numeric; v_fech int := 0; v_forn text; d record; v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_m = '' then return _falha('Informe o motivo do estorno.'); end if;
  select * into c from compras where id = v_id for update;
  if not found then return _falha('Compra não encontrada.'); end if;
  if c.estornada_em is not null then return _falha('Esta compra já está estornada.'); end if;
  if c.status = 'Pedido' then return _falha('Este é só um pedido: use "Cancelar pedido".'); end if;
  if c.status <> 'Recebida' then return _falha('Esta compra já está ' || lower(c.status) || '.'); end if;
  select nome into v_forn from fornecedores where id = c.fornecedor_id;
  -- 1) estoque: avisa se algum ingrediente ficaria negativo (já foi consumido)
  for i in select ci.*, coalesce(ci.qtd_base, _converter_unidade(ci.quantidade, ci.unidade, es.unidade::text)) q, es.ingrediente nome, es.quantidade atual, es.unidade un
           from compra_itens ci join estoque es on es.id = ci.ingrediente_id where ci.compra_id = c.id loop
    if i.atual - i.q < -0.0000001 then v_neg := v_neg || jsonb_build_object('ingrediente', i.nome, 'atual', i.atual, 'tirar', round(i.q, 3), 'fica', round(i.atual - i.q, 3), 'unidade', i.un); end if;
  end loop;
  if jsonb_array_length(v_neg) > 0 and not v_conf then
    return jsonb_build_object('ok', false, 'precisaConfirmar', true, 'negativos', v_neg,
      'message', 'Parte desta compra já foi usada: o estorno vai deixar ' || jsonb_array_length(v_neg) || ' ingrediente(s) com estoque negativo. Confirme para estornar mesmo assim.');
  end if;
  for i in select ci.*, coalesce(ci.qtd_base, _converter_unidade(ci.quantidade, ci.unidade, es.unidade::text)) q from compra_itens ci join estoque es on es.id = ci.ingrediente_id where ci.compra_id = c.id order by ci.ingrediente_id loop
    select * into e from estoque where id = i.ingrediente_id for update;
    v_novo := round(e.quantidade - i.q, 3);
    update estoque set quantidade = v_novo where id = e.id;
    insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
    values (e.id, 'Ajuste', -i.q, e.quantidade, v_novo, 'Estorno de compra: ' || v_forn || case when c.numero_nota <> '' then ' (nota ' || c.numero_nota || ')' else '' end || ' — ' || v_m, auth.uid());
    if v_novo < 0 then perform _auditar('Estoque negativo', e.ingrediente || ': ' || v_novo || ' (estorno de compra, confirmado)'); end if;
  end loop;
  -- 2) custo: só volta ao anterior se esta nota era a fonte do custo atual
  for h in select * from compra_custos where compra_id = c.id and ativo loop
    update compra_custos set ativo = false where id = h.id;
    if h.aplicado and not exists (select 1 from compra_custos x where x.ingrediente_id = h.ingrediente_id and x.ativo and x.aplicado and x.id <> h.id
                                   and (x.data_nota, x.criado_em) > (h.data_nota, h.criado_em)) then
      select x.custo_unitario into v_prev from compra_custos x where x.ingrediente_id = h.ingrediente_id and x.ativo and x.id <> h.id
       order by x.data_nota desc, x.criado_em desc limit 1;
      update estoque set custo_unitario = coalesce(v_prev, h.custo_anterior, 0) where id = h.ingrediente_id;
    end if;
  end loop;
  -- 3) dinheiro: cancela as despesas da nota (o que saiu do caixa aberto volta para a gaveta; caixa já fechado não é mexido)
  for d in select * from despesas where compra_id = c.id and status <> 'Cancelada' loop
    if d.status = 'Paga' and d.saiu_do_caixa and not exists (select 1 from caixa_sessoes s where s.status = 'Aberto' and d.data_hora >= s.abertura) then v_fech := v_fech + 1; end if;
    update despesas set status = 'Cancelada', situacao = 'Cancelada', motivo_cancelamento = 'Estorno da compra: ' || v_m where id = d.id;
  end loop;
  update compras set status = 'Cancelada', motivo_cancelamento = 'Estornada: ' || v_m, estornada_em = now(), estornada_por = auth.uid(), estorno_motivo = v_m, atualizada_em = now() where id = c.id;
  perform _auditar('Compra estornada', v_forn || case when c.numero_nota <> '' then ' | nota ' || c.numero_nota else '' end || ' | R$ ' || _dinheiro(c.total) || ' | ' || v_m
    || case when jsonb_array_length(v_neg) > 0 then ' | estoque negativo confirmado' else '' end);
  return jsonb_build_object('ok', true, 'message', 'Compra estornada: estoque, custo e despesas desfeitos.'
    || case when v_fech > 0 then ' Atenção: parte do dinheiro saiu de um caixa que já foi fechado; aquele fechamento não foi alterado — se o valor voltou para a gaveta, lance a entrada pelo caixa de hoje.' else '' end);
end $$;

-- ---------- 6. editar só o que não tem efeito (nº, observação, anexo) ----------
create or replace function public.api_editar_compra_info(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'id'); c compras%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from compras where id = v_id for update;
  if not found then return _falha('Compra não encontrada.'); end if;
  update compras set
    numero_nota = case when p ? 'numeroNota' then left(btrim(coalesce(p->>'numeroNota', '')), 60) else numero_nota end,
    observacao = case when p ? 'observacao' then left(btrim(coalesce(p->>'observacao', '')), 300) else observacao end,
    anexo_path = case when p ? 'anexoPath' then nullif(left(btrim(coalesce(p->>'anexoPath', '')), 300), '') else anexo_path end,
    anexo_nome = case when p ? 'anexoNome' then nullif(left(btrim(coalesce(p->>'anexoNome', '')), 120), '') else anexo_nome end,
    atualizada_em = now()
  where id = v_id;
  perform _auditar('Compra: dados da nota editados', coalesce(nullif(p->>'numeroNota', ''), c.numero_nota) || case when p ? 'anexoPath' then ' | comprovante ' || case when coalesce(p->>'anexoPath', '') = '' then 'removido' else 'anexado' end else '' end);
  return jsonb_build_object('ok', true, 'message', 'Dados da nota atualizados.');
end $$;

-- ---------- 7. cancelar pedido (sem mudança de regra; mensagem nova para a recebida) ----------
create or replace function public.api_cancelar_compra(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'id'); c compras%rowtype; v_m text := left(btrim(coalesce(p->>'motivo', '')), 150);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from compras where id = v_id for update;
  if not found then return _falha('Compra não encontrada.'); end if;
  if c.status <> 'Pedido' then return _falha(case when c.status = 'Recebida' then 'Compra já recebida: use "Estornar nota" (desfaz estoque, custo e despesas).' else 'Esta compra já está ' || lower(c.status) || '.' end); end if;
  if v_m = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  update compras set status = 'Cancelada', motivo_cancelamento = v_m, atualizada_em = now() where id = c.id;
  perform _auditar('Compra cancelada', v_m);
  return jsonb_build_object('ok', true, 'message', 'Pedido de compra cancelado.');
end $$;

-- ---------- 8. listar ----------
create or replace function public.api_listar_compras(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'fornecedores', coalesce((select jsonb_agg(to_jsonb(f) order by lower(f.nome)) from fornecedores f), '[]'::jsonb),
    'vinculos', coalesce((select jsonb_agg(jsonb_build_object('fornecedorId', v.fornecedor_id, 'chave', v.chave, 'ingredienteId', v.ingrediente_id, 'unidade', v.unidade, 'fator', v.fator, 'embalagem', v.embalagem)) from compra_vinculos v), '[]'::jsonb),
    'custos', coalesce((select jsonb_agg(jsonb_build_object('ingredienteId', h.ingrediente_id, 'ingrediente', e.ingrediente, 'unidade', e.unidade, 'data', h.data_nota, 'custo', h.custo_unitario,
        'anterior', h.custo_anterior, 'aplicado', h.aplicado, 'ativo', h.ativo, 'compraId', h.compra_id, 'fornecedor', f.nome, 'nota', c.numero_nota, 'lancadoEm', h.criado_em) order by h.data_nota desc, h.criado_em desc)
        from (select * from compra_custos where compra_id is not null order by data_nota desc, criado_em desc limit 300) h join estoque e on e.id = h.ingrediente_id
        left join compras c on c.id = h.compra_id left join fornecedores f on f.id = c.fornecedor_id), '[]'::jsonb),
    'compras', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'fornecedorId', c.fornecedor_id, 'fornecedor', f.nome, 'data', c.data, 'status', case when c.estornada_em is not null then 'Estornada' else c.status end,
        'pagamento', case when exists (select 1 from compra_pagamentos g where g.compra_id = c.id and g.origem = 'apagar') and exists (select 1 from compra_pagamentos g where g.compra_id = c.id and g.origem <> 'apagar') then 'Parcial' else c.pagamento end,
        'vencimento', c.vencimento, 'total', c.total, 'observacao', c.observacao, 'origem', c.origem, 'motivoCancelamento', c.motivo_cancelamento,
        'numeroNota', c.numero_nota, 'frete', c.frete, 'desconto', c.desconto, 'anexoPath', c.anexo_path, 'anexoNome', c.anexo_nome, 'semComprovante', c.anexo_path is null,
        'editadaDe', c.editada_de, 'substituidaPor', c.substituida_por, 'estornadaEm', c.estornada_em, 'estornoMotivo', c.estorno_motivo,
        'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('valor', g.valor, 'origem', g.origem, 'vencimento', g.vencimento) order by g.criado_em) from compra_pagamentos g where g.compra_id = c.id), '[]'::jsonb),
        'despesas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'valor', d.valor, 'status', d.status, 'categoria', d.categoria, 'vencimento', d.vencimento, 'origem', d.origem_pagamento, 'saiuDoCaixa', d.saiu_do_caixa) order by d.data_hora) from despesas d where d.compra_id = c.id), '[]'::jsonb),
        'itens', coalesce((select jsonb_agg(jsonb_build_object('descricao', i.descricao, 'descricaoNota', i.descricao_nota, 'quantidade', i.quantidade, 'unidade', i.unidade, 'valorTotal', i.valor_total,
            'ingredienteId', i.ingrediente_id, 'categoria', i.categoria, 'fator', i.fator, 'embalagem', i.embalagem, 'valorRateado', i.valor_rateado, 'custoBase', i.custo_base) order by i.id) from compra_itens i where i.compra_id = c.id), '[]'::jsonb))
        order by c.data desc, c.criado_em desc) from (select * from compras order by data desc, criado_em desc limit 300) c join fornecedores f on f.id = c.fornecedor_id), '[]'::jsonb));
end $$;

-- ---------- 9. despesa nascida de compra só se mexe pela compra (editar/cancelar bloqueados; pagar guarda a origem) ----------
CREATE OR REPLACE FUNCTION public.api_editar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d despesas%rowtype; v_desc text := btrim(coalesce(p->>'descricao', '')); v_valor numeric := round(_num(p->>'valor'), 2);
        v_cat text; v_venc date; v_venc_txt text := btrim(coalesce(p->>'vencimento', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_desc = '' then return _falha('Informe a descrição da despesa.'); end if;
  if v_valor <= 0 then return _falha('Informe um valor maior que zero.'); end if;
  if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if _versao_conflita(p, 'despesas', d.id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  if d.status = 'Cancelada' then return _falha('Só é possível editar despesas confirmadas.'); end if;
  if d.categoria = 'Ajuste pós-venda' then return _falha('Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.'); end if;
  if d.compra_id is not null then return _falha('Esta despesa nasceu de uma compra. Para corrigir, use Compras → Estornar nota (ou Corrigir nota), assim estoque, custo e dinheiro continuam batendo.'); end if;
  v_cat := case when p ? 'categoria' then _categoria_despesa(p->>'categoria') else d.categoria end;
  v_venc := d.vencimento;
  if v_venc_txt <> '' then
    v_venc := _data_iso(v_venc_txt);
    if v_venc is null then return _falha('Vencimento inválido.'); end if;
  end if;
  if d.status = 'A pagar' and v_venc is null then return _falha('Conta a pagar precisa de vencimento.'); end if;
  update despesas set descricao = v_desc, valor = v_valor, observacao = coalesce(p->>'observacao', ''), categoria = v_cat,
         vencimento = v_venc,
         data_hora = case when v_venc is distinct from d.vencimento and d.status = 'A pagar' then _meio_dia(v_venc) else data_hora end
   where id = d.id;
  perform _auditar('Despesa editada', v_desc || ' | valor R$ ' || _dinheiro(d.valor) || ' → R$ ' || _dinheiro(v_valor)
    || case when v_venc is distinct from d.vencimento then ' | vencimento ' || coalesce(d.vencimento::text, '—') || ' → ' || coalesce(v_venc::text, '—') else '' end);
  return jsonb_build_object('ok', true, 'message', 'Despesa atualizada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d despesas%rowtype; v_aut text; v_motivo text := btrim(coalesce(p->>'motivo', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if d.categoria = 'Ajuste pós-venda' then return _falha('Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.'); end if;
  if d.compra_id is not null then return _falha('Esta despesa nasceu de uma compra. Para desfazer, use Compras → Estornar nota (assim estoque, custo e dinheiro continuam batendo).'); end if;
  if d.status = 'Cancelada' then return _falha('Esta despesa já está cancelada.'); end if;
  update despesas set status = 'Cancelada', motivo_cancelamento = v_motivo where id = d.id;
  perform _auditar('Despesa cancelada', d.descricao || ' = R$ ' || _dinheiro(d.valor) || ' | ' || v_motivo);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_pagar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d despesas%rowtype; v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_caixa boolean := (coalesce(p->>'saiuDoCaixa', '') = 'true'); v_valor numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if d.status = 'Cancelada' then return _falha('Essa despesa está cancelada.'); end if;
  if d.status <> 'A pagar' then return _falha('Essa despesa já foi paga.'); end if;
  if v_caixa and not exists (select 1 from caixa_sessoes where status = 'Aberto') then
    return _falha('Abra o caixa para registrar um pagamento que sai do caixa.');
  end if;
  v_valor := d.valor;
  if nullif(btrim(coalesce(p->>'valorPago', '')), '') is not null then
    v_valor := round(_num(p->>'valorPago'), 2);
    if v_valor <= 0 then return _falha('Informe um valor pago maior que zero.'); end if;
    if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  end if;
  if v_caixa and _caixa_vencido(_caixa_aberto_id()) then return _falha(_caixa_msg_vencido()); end if;
  update despesas set data_hora = now(), valor = v_valor, status = 'Paga', situacao = 'Paga', saiu_do_caixa = v_caixa,
         origem_pagamento = case when v_caixa then 'caixa' when lower(coalesce(p->>'origem', '')) in ('conta','cartao','dono') then lower(p->>'origem') else 'conta' end where id = d.id;
  perform _auditar('Conta paga', d.descricao || ' | previsto R$ ' || _dinheiro(d.valor) || ' | pago R$ ' || _dinheiro(v_valor) || ' | ' || case when v_caixa then 'saiu do caixa' else 'fora do caixa' end);
  v_r := jsonb_build_object('ok', true, 'message', 'Pagamento registrado: R$ ' || _dinheiro(v_valor));
  if v_req is not null then perform _idem_gravar(v_req, 'pagarDespesa', v_r); end if;
  return v_r;
end $function$;

-- ---------- 10. comprovantes das notas: bucket PRIVADO "notas" (só Admin/Desenvolvedor envia e abre; nada é apagado: o contador pode pedir) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('notas', 'notas', false, 3145728, array['image/webp','image/jpeg','image/png','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy notas_admin_ler on storage.objects for select to authenticated using (bucket_id = 'notas' and public.tem_nivel('Admin'));
create policy notas_admin_enviar on storage.objects for insert to authenticated with check (bucket_id = 'notas' and public.tem_nivel('Admin'));


-- ======================================================================
-- 05-receber-com-forma.sql
-- ======================================================================
-- Fase 5 (F5-1): ao confirmar o recebimento de pedido "A Receber", o operador informa a forma em que o cliente pagou de verdade
-- (antes ficava a forma escolhida no pedido: "Dinheiro" pago no Pix fazia o caixa esperar dinheiro na gaveta).
-- Sem "pagamentos" no corpo: comportamento antigo (mantém a forma do pedido).
create or replace function public.api_confirmar_recebimento_pedido(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare t record; v vendas; pg record; forma formas_pagamento; v_base numeric; v_soma numeric; v_acr numeric := 0; v_acr_p numeric; v_resumo text; v_troca boolean; v_i int; v_val numeric; v_taxa numeric; v_pid uuid;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v;
  if t.erro is not null then return case when v.status = 'Cancelada' then _falha('Este pedido foi cancelado — não dá para receber o pagamento.') else t.erro end; end if;
  if v.status_pagamento = 'Pago' then return jsonb_build_object('ok', true, 'duplicado', true, 'message', 'Este pedido já estava com o pagamento confirmado.'); end if;
  v_troca := jsonb_typeof(p->'pagamentos') = 'array' and jsonb_array_length(p->'pagamentos') > 0;
  if v_troca then
    if jsonb_array_length(p->'pagamentos') > 4 then return _falha('No máximo 4 formas de pagamento.'); end if;
    for pg in select value as e from jsonb_array_elements(p->'pagamentos') loop
      if btrim(coalesce(pg.e->>'forma','')) in ('', 'A Receber (Mesa)') then return _falha('Forma de pagamento inválida.'); end if;
      if not (_num(pg.e->>'valor', 0) > 0) then return _falha('Cada pagamento deve ter um valor maior que zero.'); end if;
      select * into forma from formas_pagamento where lower(nome) = lower(btrim(pg.e->>'forma')) limit 1;
      if not found then return _falha('Forma de pagamento não cadastrada: ' || btrim(pg.e->>'forma')); end if;
      if not forma.ativa then return _falha('A forma de pagamento está inativa: ' || btrim(pg.e->>'forma')); end if;
    end loop;
    v_base := round(v.valor_total - coalesce(v.acrescimo_forma, 0), 2);
    select round(coalesce(sum(_num(e->>'valor')), 0), 2) into v_soma from jsonb_array_elements(p->'pagamentos') e;
    if abs(v_soma - v_base) > 0.02 then return _falha('A soma dos pagamentos (R$ ' || _dinheiro(v_soma) || ') não bate com o valor do pedido (R$ ' || _dinheiro(v_base) || ').'); end if;
    -- reaproveita as linhas que já existem (sem apagar nada): linha i do pedido recebe o pagamento i;
    -- pagamento a mais vira linha nova; linha antiga que sobrar fica com valor zero na 1ª forma informada (não muda nenhuma soma).
    v_i := 0;
    for pg in select value as e, ordinality as n from jsonb_array_elements(p->'pagamentos') with ordinality loop
      v_acr_p := round(_acrescimo_pagamento(btrim(pg.e->>'forma'), _num(pg.e->>'valor')), 2);
      v_acr := v_acr + v_acr_p; v_i := pg.n;
      v_val := round(_num(pg.e->>'valor'), 2) + v_acr_p;
      v_taxa := coalesce((select round(v_val * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where lower(f.nome) = lower(btrim(pg.e->>'forma'))), 0);
      select id into v_pid from pagamentos_venda where venda_id = v.id order by id offset (pg.n - 1) limit 1;
      if v_pid is not null then
        update pagamentos_venda set forma_pagamento = btrim(pg.e->>'forma'), valor = v_val, taxa_aplicada = v_taxa, acrescimo = v_acr_p where id = v_pid;
      else
        insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada, acrescimo) values (v.id, btrim(pg.e->>'forma'), v_val, v_taxa, v_acr_p);
      end if;
      v_pid := null;
    end loop;
    update pagamentos_venda set valor = 0, taxa_aplicada = 0, acrescimo = 0, forma_pagamento = (select btrim(e->>'forma') from jsonb_array_elements(p->'pagamentos') e limit 1)
     where venda_id = v.id and id in (select id from pagamentos_venda where venda_id = v.id order by id offset v_i);
    select string_agg(btrim(e->>'forma'), ' + ') into v_resumo from jsonb_array_elements(p->'pagamentos') e;
    update vendas set status_pagamento = 'Pago', recebido_em = now(), forma_pagamento = v_resumo, valor_total = v_base + v_acr, acrescimo_forma = v_acr where id = v.id;
  else
    update vendas set status_pagamento = 'Pago', recebido_em = now() where id = v.id;
  end if;
  if nullif(v.telefone_cliente,'') is not null then perform _carimbar_fidelidade(v.telefone_cliente, v.cliente_nome); end if;
  perform _auditar('Pagamento confirmado', '#' || v.numero_pedido || case when v_troca and v_resumo is distinct from v.forma_pagamento then ' — forma: ' || coalesce(v.forma_pagamento,'?') || ' → ' || v_resumo else '' end, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $function$;


-- ======================================================================
-- 06-rls-sem-gravacao-direta.sql
-- ======================================================================
-- Fase 7 (F2-2): a equipe só grava vendas, itens, pagamentos, sangrias, despesas, clientes e status de mesa pelas funções do sistema
-- (que calculam preço, conferem caixa e registram auditoria). As políticas de gravação direta ficam fechadas (false).
-- Sem DROP: as políticas continuam existindo; para voltar, ver o arquivo DESFAZER.
alter policy vendas_criar on public.vendas with check (false);
alter policy vendas_alterar on public.vendas using (false) with check (false);
alter policy itens_venda_criar on public.itens_venda with check (false);
alter policy itens_venda_alterar on public.itens_venda using (false) with check (false);
alter policy pagamentos_venda_criar on public.pagamentos_venda with check (false);
alter policy pagamentos_venda_alterar on public.pagamentos_venda using (false) with check (false);
alter policy sangrias_criar on public.sangrias with check (false);
alter policy despesas_criar on public.despesas with check (false);
alter policy despesas_alterar on public.despesas using (false) with check (false);
alter policy clientes_criar on public.clientes with check (false);
alter policy clientes_alterar on public.clientes using (false) with check (false);
alter policy clientes_excluir on public.clientes using (false);
alter policy mesas_status on public.mesas using (false) with check (false);


-- ======================================================================
-- 07-alertas.sql
-- ======================================================================
-- =====================================================================
-- Fases 7.1 e 7.2 (auditoria 18/10/2026) — ALERTAS AUTOMÁTICOS. Só AVISAM: nunca mudam status, pagamento, estoque ou caixa.
-- 7.1: falhas do sistema e vencimentos → Admin (push + e-mail pela planilha principal).
-- 7.2: pedido parado no mesmo status → quem precisa agir (push com o app fechado; o app aberto toca o som e mostra a lista).
-- Tudo aditivo: 2 tabelas novas, funções novas, 2 agendamentos novos; api_push_inscrever passa a aceitar Cozinha e Garçom.
-- =====================================================================

create table if not exists public.alertas_config (
  id boolean primary key default true check (id),
  regras jsonb not null default '{}'::jsonb,         -- {"recebido":{"ligado":true,"min":3}, ...} (o que faltar usa o padrão)
  repetir_min int not null default 5,                 -- repetição do aviso enquanto continuar parado
  escalar_apos int not null default 3,                -- depois de N avisos sem ação, avisa também o Admin
  vencimentos jsonb not null default '[]'::jsonb,     -- [{"item":"Certificado digital","vence":"2027-03-01"}]
  email_ativo boolean not null default true,          -- alertas do sistema também por e-mail (dono da planilha principal)
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
insert into public.alertas_config (id) values (true) on conflict (id) do nothing;
alter table public.alertas_config enable row level security;

create table if not exists public.alertas_envios (
  chave text primary key,                -- 'ped:<venda>:<regra>' ou 'sis:<assunto>'
  tipo text not null,                    -- 'pedido' | 'sistema'
  venda_id uuid,
  regra text,
  titulo text, texto text,
  primeiro_em timestamptz not null default now(),
  ultimo_em timestamptz not null default now(),
  vezes int not null default 1,
  resolvido_em timestamptz,
  adiado_ate timestamptz,
  silenciado boolean not null default false,
  silenciado_por uuid
);
create index if not exists alertas_envios_ativos on public.alertas_envios (tipo) where resolvido_em is null;
alter table public.alertas_envios enable row level security;

-- ---------- padrão das 7 regras (o dono ajusta no Admin) ----------
create or replace function public._alertas_padrao() returns jsonb language sql immutable as $$
  select '{"recebido":{"ligado":true,"min":3},"preparo":{"ligado":true,"min":25},"pronta_retirada":{"ligado":true,"min":10},
           "pronta_entrega":{"ligado":true,"min":8},"pronta_mesa":{"ligado":true,"min":5},"saiu":{"ligado":true,"min":45},
           "a_receber":{"ligado":true,"min":15}}'::jsonb
$$;

create or replace function public._alertas_cfg() returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c alertas_config%rowtype; v_reg jsonb := _alertas_padrao(); k text;
begin
  select * into c from alertas_config where id;
  for k in select jsonb_object_keys(_alertas_padrao()) loop
    if c.regras ? k then v_reg := jsonb_set(v_reg, array[k], (v_reg->k) || (c.regras->k)); end if;
  end loop;
  return jsonb_build_object('regras', v_reg, 'repetirMin', coalesce(c.repetir_min, 5), 'escalarApos', coalesce(c.escalar_apos, 3),
                            'vencimentos', coalesce(c.vencimentos, '[]'::jsonb), 'emailAtivo', coalesce(c.email_ativo, true));
end $$;

-- ---------- 7.2: quais pedidos estão parados agora (hora do SERVIDOR) ----------
create or replace function public._alertas_pedidos_parados()
returns table (venda_id uuid, numero int, regra text, rotulo text, desde timestamptz, minutos int, niveis text[], tipo text)
language plpgsql stable security definer set search_path to 'public' as $$
declare v_cfg jsonb := _alertas_cfg()->'regras'; s caixa_sessoes%rowtype;
begin
  select * into s from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  if s.id is null then return; end if;                                  -- loja/caixa fechado: nada toca
  return query
  with base as (
    select v.id, v.numero_pedido, v.tipo::text tp, v.status_pedido::text sp, v.status_pagamento::text pg,
           v.data_hora, v.inicio_preparo_em, v.pronta_em, v.saiu_em, v.concluida_em,
           coalesce(v.observacoes_entrega, '') ilike '%AGENDADO%' agendado
      from vendas v
     where v.status = 'Confirmada'
       and (v.caixa_id = s.id or (v.caixa_id is null and v.data_hora >= s.abertura))   -- nada de caixa já fechado ou de dia anterior
       and coalesce(v.status_pedido::text, '') <> 'Suspenso'
       and not exists (select 1 from ocorrencias o where o.venda_id = v.id and o.status::text in ('Aberta', 'Em andamento'))
  ), r as (
    select id, numero_pedido, 'recebido' rg, 'Novo pedido sem aceite' rot, data_hora d, array['Cozinha','Operador'] nv, tp from base where sp = 'Recebido' and not agendado
    union all select id, numero_pedido, 'preparo', 'Em preparo há muito tempo', coalesce(inicio_preparo_em, data_hora), array['Cozinha','Operador'], tp from base where sp = 'Em preparo' and not agendado
    union all select id, numero_pedido, 'pronta_retirada', 'Pronta (retirada) sem marcar "Retirada"', coalesce(pronta_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Pronta' and tp = 'Retirada'
    union all select id, numero_pedido, 'pronta_entrega', 'Pronta (entrega) sem sair para entrega', coalesce(pronta_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Pronta' and tp = 'Entrega'
    union all select id, numero_pedido, 'pronta_mesa', 'Pronta (mesa) sem marcar "Servida"', coalesce(pronta_em, data_hora), array['Operador','Garçom'], tp from base where sp = 'Pronta' and tp = 'Mesa'
    union all select id, numero_pedido, 'saiu', 'Saiu para entrega e não foi concluído', coalesce(saiu_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Saiu para entrega'
    union all select id, numero_pedido, 'a_receber', 'Pagamento "a receber" com o pedido pronto', coalesce(concluida_em, pronta_em, data_hora), array['Operador','Admin'], tp
      from base where pg = 'A Receber' and tp <> 'Mesa' and sp in ('Pronta', 'Retirada', 'Servida', 'Entregue')
  )
  select r.id, r.numero_pedido, r.rg, r.rot, r.d, floor(extract(epoch from (now() - r.d)) / 60)::int, r.nv, r.tp
    from r
   where coalesce((v_cfg->r.rg->>'ligado')::boolean, true)
     and now() - r.d >= make_interval(mins => greatest(1, coalesce((v_cfg->r.rg->>'min')::int, 10)));
end $$;

-- ---------- envio (push com filtro de perfil; e-mail opcional pela planilha principal) ----------
create or replace function public._alertas_push(p_titulo text, p_texto text, p_tag text, p_niveis text[], p_usuarios uuid[] default null)
returns void language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  if not exists (select 1 from push_inscricoes limit 1) then return; end if;
  perform chamar_edge('push-enviar', jsonb_build_object('tipo', 'alerta', 'titulo', p_titulo, 'texto', p_texto, 'tag', p_tag,
          'niveis', to_jsonb(p_niveis), 'usuarios', to_jsonb(p_usuarios)));
exception when others then null;
end $$;

create or replace function public._alertas_email(p_assunto text, p_texto text) returns void
language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare v_url text; v_chave text;
begin
  if not coalesce((select email_ativo from alertas_config where id), true) then return; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'sheets_main_url';
  select decrypted_secret into v_chave from vault.decrypted_secrets where name = 'chave_servidor_planilha';
  if coalesce(v_url, '') = '' or coalesce(v_chave, '') = '' then return; end if;
  perform net.http_post(url := v_url, headers := '{"Content-Type":"text/plain"}'::jsonb,
          body := jsonb_build_object('chave', v_chave, 'action', 'sbAvisoEmail', 'assunto', left(p_assunto, 120), 'texto', left(p_texto, 1500)),
          timeout_milliseconds := 30000);
exception when others then null;   -- planilha sem a função nova: o push continua valendo
end $$;

-- ---------- 7.2: agendamento de 1 em 1 minuto ----------
create or replace function public.alertas_pedidos_cron() returns int
language plpgsql security definer set search_path to 'public' as $$
declare c jsonb := _alertas_cfg(); x record; e alertas_envios%rowtype; v_rep int := greatest(1, (c->>'repetirMin')::int);
        v_esc int := greatest(1, (c->>'escalarApos')::int); v_niv text[]; n int := 0; v_txt text; v_chaves text[] := '{}';
begin
  for x in select * from _alertas_pedidos_parados() loop
    v_chaves := array_append(v_chaves, 'ped:' || x.venda_id || ':' || x.regra);
    select * into e from alertas_envios where chave = 'ped:' || x.venda_id || ':' || x.regra for update;
    v_txt := x.rotulo || ' há ' || x.minutos || ' min';
    if e.chave is null or e.resolvido_em is not null then
      insert into alertas_envios (chave, tipo, venda_id, regra, titulo, texto) values ('ped:' || x.venda_id || ':' || x.regra, 'pedido', x.venda_id, x.regra, '⏰ Pedido #' || x.numero || ' parado', v_txt)
      on conflict (chave) do update set resolvido_em = null, primeiro_em = now(), ultimo_em = now(), vezes = 1, adiado_ate = null, silenciado = false, texto = excluded.texto;
      perform _alertas_push('⏰ Pedido #' || x.numero || ' parado', v_txt, 'parado-' || x.numero, x.niveis);
      n := n + 1;
    elsif not e.silenciado and coalesce(e.adiado_ate, '-infinity') <= now() and now() - e.ultimo_em >= make_interval(mins => v_rep) then
      v_niv := x.niveis; if e.vezes >= v_esc and not ('Admin' = any(v_niv)) then v_niv := array_append(v_niv, 'Admin'); end if;   -- escalada
      update alertas_envios set ultimo_em = now(), vezes = e.vezes + 1, texto = v_txt where chave = e.chave;
      perform _alertas_push('⏰ Pedido #' || x.numero || ' continua parado', v_txt || ' (' || (e.vezes + 1) || 'º aviso)', 'parado-' || x.numero, v_niv);
      n := n + 1;
    end if;
  end loop;
  -- resolveu (avançou o status, pagou, cancelou, suspendeu, abriu ocorrência, fechou o caixa): o aviso para
  update alertas_envios set resolvido_em = now() where tipo = 'pedido' and resolvido_em is null and not (chave = any(v_chaves));
  return n;
end $$;

-- ---------- 7.1: falhas do sistema e vencimentos (de 10 em 10 minutos) ----------
create or replace function public._alertas_sistema_avisar(p_chave text, p_titulo text, p_texto text, p_repetir interval default interval '6 hours')
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare e alertas_envios%rowtype;
begin
  select * into e from alertas_envios where chave = p_chave for update;
  if e.chave is not null and e.resolvido_em is null and (e.silenciado or now() - e.ultimo_em < p_repetir) then return false; end if;
  insert into alertas_envios (chave, tipo, titulo, texto) values (p_chave, 'sistema', p_titulo, p_texto)
  on conflict (chave) do update set ultimo_em = now(), vezes = case when alertas_envios.resolvido_em is null then alertas_envios.vezes + 1 else 1 end,
     resolvido_em = null, titulo = excluded.titulo, texto = excluded.texto, silenciado = false;
  insert into auditoria (usuario_login, acao, detalhes) values ('sistema', 'ALERTA: ' || left(p_titulo, 80), left(p_texto, 300));
  perform _alertas_push('⚠️ ' || p_titulo, p_texto, 'sis-' || left(p_chave, 40), array['Admin']);
  perform _alertas_email(coalesce(nullif((select valor ->> 'nome' from sistema where chave = 'Marca'), ''), 'Restaurante') || ' — ' || p_titulo, p_texto || E'\n\nAviso automático do sistema (' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ').');
  return true;
end $$;

create or replace function public.alertas_sistema_cron() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare ativos text[] := '{}'; v_n int; v_t timestamptz; v_txt text; r record; v_dias int; v_cx caixa_sessoes%rowtype; v_tam bigint;
begin
  -- 1) cópia para a planilha principal parada
  select count(*), min(criado_em) into v_n, v_t from fila_sync where principal_ok_em is null;
  if v_n > 0 and v_t < now() - interval '30 minutes' then
    ativos := array_append(ativos, ('sis:sync_principal')::text);
    perform _alertas_sistema_avisar('sis:sync_principal', 'Cópia para a planilha parada', v_n || ' registro(s) esperando há ' || floor(extract(epoch from now() - v_t) / 60) || ' min. O sistema continua funcionando; confira em Sistema → Sincronização e contingência.');
  end if;
  -- 2) espelho da contingência atrasado
  select count(*), min(criado_em) into v_n, v_t from fila_sync where contingencia_ok_em is null;
  if v_n > 0 and v_t < now() - interval '90 minutes' then
    ativos := array_append(ativos, ('sis:sync_contingencia')::text);
    perform _alertas_sistema_avisar('sis:sync_contingencia', 'Planilha de contingência atrasada', v_n || ' registro(s) sem chegar na contingência há mais de 1h30. Se o Supabase cair agora, a reserva estará desatualizada.');
  end if;
  -- 3) tarefas agendadas falhando em sequência
  for r in select j.jobname, count(*) n, max(left(d.return_message, 120)) msg from cron.job_run_details d join cron.job j on j.jobid = d.jobid
            where d.status = 'failed' and d.start_time > now() - interval '30 minutes' group by j.jobname having count(*) >= 3 loop
    ativos := array_append(ativos, (('sis:cron_' || r.jobname))::text);
    perform _alertas_sistema_avisar('sis:cron_' || r.jobname, 'Tarefa automática falhando', 'A tarefa "' || r.jobname || '" falhou ' || r.n || 'x em 30 min: ' || coalesce(r.msg, ''));
  end loop;
  -- 4) Edge Functions respondendo erro em sequência
  select count(*) into v_n from net._http_response where created > now() - interval '30 minutes' and (status_code >= 500 or (status_code is null and error_msg is not null));
  if v_n >= 10 then
    ativos := array_append(ativos, ('sis:edge')::text);
    perform _alertas_sistema_avisar('sis:edge', 'Funções do servidor com erro', v_n || ' chamadas com erro nos últimos 30 min (backup, cópia, iFood, nota ou avisos).');
  end if;
  -- 5) Mercado Pago: dinheiro esperando decisão / aviso que não chega
  if _integracao_ligada('mercadopago') then
    select count(*) into v_n from pagamentos_online where decisao_pendente and decisao is null and atualizado_em < now() - interval '10 minutes';
    if v_n > 0 then ativos := array_append(ativos, ('sis:mp_decidir')::text);
      perform _alertas_sistema_avisar('sis:mp_decidir', 'Pagamento online esperando decisão', v_n || ' pagamento(s) aprovado(s) aguardando você decidir (seguir com o pedido ou reembolsar). Veja em Pedidos.', interval '1 hour'); end if;
    select count(*) into v_n from pagamentos_online where status = 'aguardando' and criado_em < now() - interval '45 minutes';
    if v_n > 0 then ativos := array_append(ativos, ('sis:mp_aviso')::text);
      perform _alertas_sistema_avisar('sis:mp_aviso', 'Mercado Pago sem resposta', v_n || ' pagamento(s) sem resposta do Mercado Pago há mais de 45 min. Confira o webhook no painel do Mercado Pago.'); end if;
  end if;
  -- 6) iFood ligado e sem conversar com o iFood
  if _integracao_ligada('ifood') and exists (select 1 from caixa_sessoes where status = 'Aberto') then
    select ultima_consulta_ok into v_t from ifood_estado where id;
    if v_t is null or v_t < now() - interval '10 minutes' then
      ativos := array_append(ativos, ('sis:ifood')::text);
      perform _alertas_sistema_avisar('sis:ifood', 'iFood sem conexão', 'O sistema não consegue buscar pedidos do iFood há mais de 10 min. Use o Gestor de Pedidos do iFood e lance no Caixa.', interval '1 hour');
    end if;
  end if;
  -- 7) caixa vencido e ainda aberto
  select * into v_cx from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  if v_cx.id is not null and _caixa_vencido(v_cx.id) and now() > _caixa_vence_em(v_cx.abertura) + interval '3 hours' then
    ativos := array_append(ativos, ('sis:caixa_vencido')::text);
    perform _alertas_sistema_avisar('sis:caixa_vencido', 'Caixa vencido ainda aberto', 'O caixa aberto em ' || to_char(v_cx.abertura at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ' passou do horário. Feche em "Fechar caixa vencido" antes de vender.', interval '12 hours');
  end if;
  -- 8) espaço do banco (plano gratuito: 500 MB)
  v_tam := pg_database_size(current_database());
  if v_tam > 400 * 1024 * 1024 then
    ativos := array_append(ativos, ('sis:espaco')::text);
    perform _alertas_sistema_avisar('sis:espaco', 'Banco de dados quase cheio', 'Usando ' || round(v_tam / 1048576.0) || ' MB de 500 MB. Arquive vendas antigas em Sistema → Backup e espaço.', interval '24 hours');
  end if;
  -- 9) backup automático parado
  select max(data_hora) into v_t from backups where status = 'ok';
  if v_t is not null and v_t < now() - interval '26 hours' then
    ativos := array_append(ativos, ('sis:backup')::text);
    perform _alertas_sistema_avisar('sis:backup', 'Backup automático parado', 'O último backup que deu certo foi em ' || to_char(v_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '.', interval '12 hours');
  end if;
  -- 10) conferência diária achou diferença
  select status, criado_em into v_txt, v_t from integridade_checks order by criado_em desc limit 1;
  if v_txt is not null and v_txt <> 'ok' and v_t > now() - interval '24 hours' then
    ativos := array_append(ativos, ('sis:integridade')::text);
    perform _alertas_sistema_avisar('sis:integridade', 'Conferência diária achou diferença', 'Supabase e planilha não bateram na conferência de hoje. Veja em Sistema → Sincronização e contingência.', interval '24 hours');
  end if;
  -- 11) vencimentos cadastrados pelo dono (30, 15, 7 e 1 dia antes; e vencido)
  for r in select e->>'item' item, (e->>'vence')::date vence from jsonb_array_elements(coalesce((select vencimentos from alertas_config where id), '[]'::jsonb)) e
            where coalesce(e->>'item', '') <> '' and coalesce(e->>'vence', '') ~ '^\d{4}-\d{2}-\d{2}$' loop
    v_dias := r.vence - (now() at time zone 'America/Sao_Paulo')::date;
    if v_dias <= 30 then
      v_txt := 'sis:venc:' || md5(r.item) || ':' || case when v_dias < 0 then 'vencido' when v_dias <= 1 then '1' when v_dias <= 7 then '7' when v_dias <= 15 then '15' else '30' end;
      ativos := array_append(ativos, (v_txt)::text);
      perform _alertas_sistema_avisar(v_txt, case when v_dias < 0 then r.item || ' VENCEU' else r.item || ' vence em ' || v_dias || ' dia(s)' end,
              r.item || ': vencimento em ' || to_char(r.vence, 'DD/MM/YYYY') || '. Renove antes para o sistema não parar.', interval '7 days');
    end if;
  end loop;
  update alertas_envios set resolvido_em = now() where tipo = 'sistema' and resolvido_em is null and not (chave = any(ativos));
  return jsonb_build_object('ok', true, 'ativos', to_jsonb(ativos));
end $$;

-- ---------- chamadas do app ----------
-- lista do app aberto (hora do servidor): cada perfil vê o que é dele; Admin/Desenvolvedor veem tudo
create or replace function public.api_alertas_pedidos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_niv text := auth_nivel()::text; v_l jsonb;
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha', 'Garçom') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('vendaId', x.venda_id, 'numero', x.numero, 'regra', x.regra, 'rotulo', x.rotulo, 'minutos', x.minutos,
           'vezes', coalesce(e.vezes, 0)) order by x.minutos desc), '[]'::jsonb) into v_l
    from _alertas_pedidos_parados() x left join alertas_envios e on e.chave = 'ped:' || x.venda_id || ':' || x.regra and e.resolvido_em is null
   where (v_niv in ('Admin', 'Desenvolvedor') or v_niv = any(x.niveis) or (coalesce(e.vezes, 0) >= (_alertas_cfg()->>'escalarApos')::int and v_niv = 'Admin'))
     and not coalesce(e.silenciado, false) and coalesce(e.adiado_ate, '-infinity') <= now();
  return jsonb_build_object('ok', true, 'agora', now(), 'alertas', v_l);
end $$;

-- adiar 10 min ou silenciar o aviso de um pedido (não muda o pedido)
create or replace function public.api_alertas_pedido_adiar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'vendaId'); v_ac text := coalesce(p->>'acao', 'adiar'); v_num int; x record; n int := 0;
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha', 'Garçom') then return _negado(); end if;
  if v_ac not in ('adiar', 'silenciar') then return _falha('Ação inválida.'); end if;
  select numero_pedido into v_num from vendas where id = v_id; if v_num is null then return _falha('Pedido não encontrado.'); end if;
  for x in select * from _alertas_pedidos_parados() where venda_id = v_id loop
    insert into alertas_envios (chave, tipo, venda_id, regra, titulo, texto) values ('ped:' || v_id || ':' || x.regra, 'pedido', v_id, x.regra, '⏰ Pedido #' || v_num || ' parado', x.rotulo)
    on conflict (chave) do nothing;
    update alertas_envios set adiado_ate = case when v_ac = 'adiar' then now() + interval '10 minutes' else adiado_ate end,
           silenciado = (v_ac = 'silenciar') or silenciado, silenciado_por = case when v_ac = 'silenciar' then auth.uid() else silenciado_por end, resolvido_em = null
     where chave = 'ped:' || v_id || ':' || x.regra;
    n := n + 1;
  end loop;
  if v_ac = 'silenciar' and n > 0 then perform _auditar('Alerta de pedido silenciado', '#' || v_num || ' — ' || coalesce(nullif(left(btrim(coalesce(p->>'motivo', '')), 120), ''), 'sem motivo')); end if;
  return jsonb_build_object('ok', true, 'message', case when n = 0 then 'Este pedido não tem aviso agora.' when v_ac = 'adiar' then 'Aviso adiado por 10 minutos.' else 'Aviso deste pedido silenciado.' end);
end $$;

create or replace function public.api_alertas_config(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'padrao', _alertas_padrao()) || _alertas_cfg()
      || jsonb_build_object('ativos', coalesce((select jsonb_agg(jsonb_build_object('titulo', titulo, 'texto', texto, 'desde', primeiro_em, 'ultimo', ultimo_em, 'vezes', vezes) order by ultimo_em desc)
                                               from alertas_envios where tipo = 'sistema' and resolvido_em is null), '[]'::jsonb));
end $$;

create or replace function public.api_alertas_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_reg jsonb := '{}'::jsonb; k text; v_min int; v_ven jsonb := '[]'::jsonb; e jsonb; v_rep int; v_esc int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  for k in select jsonb_object_keys(_alertas_padrao()) loop
    if p->'regras' ? k then
      v_min := _num(p->'regras'->k->>'min', (_alertas_padrao()->k->>'min')::numeric)::int;
      if v_min < 1 or v_min > 240 then return _falha('Os tempos precisam ficar entre 1 e 240 minutos.'); end if;
      v_reg := v_reg || jsonb_build_object(k, jsonb_build_object('ligado', coalesce((p->'regras'->k->>'ligado')::boolean, true), 'min', v_min));
    end if;
  end loop;
  v_rep := _num(p->>'repetirMin', 5)::int; v_esc := _num(p->>'escalarApos', 3)::int;
  if v_rep < 1 or v_rep > 60 or v_esc < 1 or v_esc > 20 then return _falha('Repetição entre 1 e 60 min; escalada entre 1 e 20 avisos.'); end if;
  for e in select value from jsonb_array_elements(coalesce(p->'vencimentos', '[]'::jsonb)) loop
    if coalesce(btrim(e->>'item'), '') = '' then continue; end if;
    if coalesce(e->>'vence', '') !~ '^\d{4}-\d{2}-\d{2}$' then return _falha('Data inválida em "' || left(e->>'item', 40) || '".'); end if;
    v_ven := v_ven || jsonb_build_object('item', left(btrim(e->>'item'), 60), 'vence', e->>'vence');
  end loop;
  if jsonb_array_length(v_ven) > 20 then return _falha('No máximo 20 vencimentos.'); end if;
  update alertas_config set regras = v_reg, repetir_min = v_rep, escalar_apos = v_esc, vencimentos = v_ven,
         email_ativo = coalesce((p->>'emailAtivo')::boolean, email_ativo), atualizado_em = now(), atualizado_por = auth.uid() where id;
  perform _auditar('Alertas automáticos alterados', 'repetir ' || v_rep || ' min | escalar após ' || v_esc || ' | ' || jsonb_array_length(v_ven) || ' vencimento(s)');
  return jsonb_build_object('ok', true, 'message', 'Alertas salvos.');
end $$;

-- "Enviar aviso de teste": só para os aparelhos de quem pediu
create or replace function public.api_alertas_teste(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_n int;
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha', 'Garçom') then return _negado(); end if;
  select count(*) into v_n from push_inscricoes where usuario_id = auth.uid();
  if v_n = 0 then return jsonb_build_object('ok', true, 'semAparelho', true, 'message', 'Este usuário ainda não ligou os avisos com o app fechado. O som com o app aberto foi tocado neste aparelho.'); end if;
  perform _alertas_push('🔔 Aviso de teste', 'Se você recebeu, os avisos com o app fechado estão funcionando.', 'teste-alerta', null, array[auth.uid()]);
  return jsonb_build_object('ok', true, 'message', 'Aviso de teste enviado para ' || v_n || ' aparelho(s) deste usuário.');
end $$;

-- Cozinha e Garçom também podem ligar os avisos com o app fechado (antes: só Admin e Operador)
create or replace function public.api_push_inscrever(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_ep text := btrim(coalesce(p->>'endpoint','')); v_k text := btrim(coalesce(p->'keys'->>'p256dh','')); v_a text := btrim(coalesce(p->'keys'->>'auth',''));
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha', 'Garçom') then return _negado(); end if;
  if v_ep not like 'https://%' or char_length(v_ep) > 800 or v_k = '' or v_a = '' or char_length(v_k) > 200 or char_length(v_a) > 100 then return _falha('Inscrição inválida.'); end if;
  insert into push_inscricoes (usuario_id, endpoint, p256dh, auth) values (auth.uid(), v_ep, v_k, v_a)
  on conflict (endpoint) do update set usuario_id = excluded.usuario_id, p256dh = excluded.p256dh, auth = excluded.auth, falhas = 0;
  perform _auditar('Avisos com app fechado ativados', null);
  return jsonb_build_object('ok', true, 'message', 'Avisos com o app fechado ativados neste aparelho.');
end $function$;

-- agendamentos
select cron.schedule('alertas-pedidos-minuto', '* * * * *', 'select public.alertas_pedidos_cron()');
select cron.schedule('alertas-sistema-10min', '*/10 * * * *', 'select public.alertas_sistema_cron()');


-- ======================================================================
-- 08-acerto-entregador-por-turno.sql
-- ======================================================================
-- Acerto do entregador por TURNO DO CAIXA: a "data" do acerto (dataRef) é o dia em que o caixa abriu (horário de São Paulo).
-- Entrega concluída dentro de um caixa entra no acerto do dia da abertura desse caixa; sem caixa que a contenha, vale o dia do calendário (como antes).
create or replace function public._calc_fechamento_entrega(p_login text, p_data date, OUT qtd integer, OUT total_taxas numeric, OUT ajuda numeric, OUT total numeric, OUT ids uuid[])
 returns record language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; ja boolean; aj numeric;
begin
  select id into uid from usuarios where lower(login) = lower(p_login) and nivel::text = 'Entregador';
  select count(*)::int, coalesce(round(sum(v.taxa_entrega), 2), 0), coalesce(array_agg(v.id), '{}'::uuid[]) into qtd, total_taxas, ids
    from vendas v where v.status = 'Confirmada' and v.tipo = 'Entrega' and v.status_pedido::text = 'Entregue' and v.entregador_id = uid
     and v.fechamento_entrega_id is null
     and coalesce(
           (select (s.abertura at time zone 'America/Sao_Paulo')::date from caixa_sessoes s
             where v.concluida_em >= s.abertura and (s.fechamento is null or v.concluida_em <= s.fechamento)
             order by s.abertura desc limit 1),
           (v.concluida_em at time zone 'America/Sao_Paulo')::date) = p_data;
  select exists (select 1 from fechamentos_entrega where entregador_id = uid and data_ref = p_data) into ja;
  select coalesce(_num(valor #>> '{}'), 0) into aj from sistema where chave = 'AjudaDiariaEntregador';
  ajuda := case when qtd > 0 and not ja then coalesce(aj, 0) else 0 end;
  total := round(total_taxas + ajuda, 2);
end $$;


-- ======================================================================
-- 09-ajuda-assistente.sql
-- ======================================================================
-- Fase 11: base de conhecimento da assistente (ai_ajuda). Atualiza 2 textos antigos e acrescenta 4 verbetes. Sem remover nada.
-- Desfazer: sql/DESFAZER-2026-10-18-f11-ajuda-assistente.sql
begin;
update public.ai_ajuda set passos=$t$Compras e fornecedores (só Administrador): Administrador → Produtos → "Compras e fornecedores". Cadastre o fornecedor e registre a nota: em "O que você comprou?" digite e toque no ingrediente ou bebida da lista (aí dá entrada no estoque). Texto fora da lista vira só despesa (aviso laranja). Informe quantidade, unidade e o valor total pago. Bebida em fardo: "Embalagens" × "Unidades em cada".
Nota "Recebida" soma no estoque e o custo do ingrediente passa a ser o ÚLTIMO custo pago (o da nota mais recente, por kg, l ou un). Nota antiga lançada depois fica só no histórico. "Pedido" só guarda; marque como recebida quando chegar.
Informe o nº da nota e, se quiser, foto ou PDF do comprovante (opcional). O comprovante vai para o Google Drive (principal, contingência ou os dois) e fica privado: só o Admin abre, em "Ver comprovante". Frete e desconto são repartidos nos itens.
Em "Pagamento" diga de onde saiu o dinheiro (caixa, conta, cartão ou dinheiro do dono) ou "vou pagar depois" com o vencimento; dá para dividir. Se saiu do caixa, o caixa precisa estar aberto. Item que não é de estoque (gás, embalagem, limpeza) vai só como despesa.
Nota já recebida: "Editar dados da nota" muda só nº, observação e comprovante. Para mudar itens, valores ou pagamento use "Corrigir nota" (estorna e reabre) ou "Estornar nota" (desfaz estoque, custo e despesas). A despesa de uma compra só se corrige pela compra. Pedido ainda não recebido pode ser cancelado.
Assistente: diga "comprei 30kg de picanha do fornecedor X por R$ 900". A IA só monta um cartão (com origem do dinheiro); nada é gravado até tocar em "Confirmar e gravar". "Revisar na tela" ajusta antes. Fornecedor ou item não encontrado bloqueia o botão: cadastre antes.
Relatórios → "Análise avançada": margem líquida por forma de pagamento, vendas por dia da semana e comparação com o ano passado; períodos "Últimos 90 dias", "Últimos 12 meses" e "Uso real (desde 17/10/2026)".$t$, palavras_chave=$t$compra comprei fornecedor picanha estoque custo despesa recebida pedido margem forma de pagamento dia da semana ano passado 90 dias 12 meses fardo embalagens unidades em cada não entra no estoque aviso laranja digitar item compra bebida nota nota fiscal último custo comprovante drive estornar nota corrigir nota origem do dinheiro vou pagar depois uso real$t$, comuns=$t$Compras e a gravação pela IA são só do Administrador e do Desenvolvedor. Nota recebida não se apaga: estorne ou corrija a nota.$t$, atualizado_em=now() where id=257;
update public.ai_ajuda set passos=replace(passos, $t$Venda "A Receber": quando o cliente pagar, toque em "marcar como recebido".$t$, $t$Venda "A Receber": quando o cliente pagar, toque em "marcar como recebido" e escolha em que forma ele pagou (Dinheiro, Pix, cartão…; dá para dividir em duas). O padrão é a forma do pedido.$t$), atualizado_em=now() where id=45;
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values ($t$man-admin-120-alertas-pedido-parado$t$,$t$Alertas de pedido parado (faixa e notificação)$t$,$t$alerta pedido parado esquecido faixa pedidos parados som notificação adiar silenciar aviso tempo demorando sem aceite preparo demorado pronta sem retirar saiu entrega receber atrasado escalada$t$,$t$O sistema confere de minuto em minuto se algum pedido ficou parado: novo sem aceite (3 min), em preparo há muito tempo (25 min), pronto esperando retirada (10 min), entrega ainda sem sair (8 min), mesa pronta sem servir (5 min), saiu para entrega sem entregar (45 min) e "A receber" de pedido já concluído (15 min). Os tempos são o padrão; o Administrador muda.
Com o app aberto aparece a faixa "⏰ Pedidos parados" embaixo da tela, com som, e uma bolinha vermelha na aba Pedidos. Com o app fechado chega a notificação no celular, se os avisos (🔔) estiverem ligados no aparelho.
Em cada pedido: "Ver pedido" abre o pedido; "Adiar 10 min" some por 10 minutos; "Silenciar este pedido" pede o motivo, some e fica registrado na Auditoria. O X esconde a faixa até vir um aviso novo.
Quem recebe: Cozinha (novo sem aceite e preparo demorado), Caixa/Operador (todos os de pedido), Garçom (mesa pronta sem servir), Administrador (pronto sem retirar ou sair, saiu sem entregar e a receber; depois de 3 avisos sem resposta, também recebe os da Cozinha e do Garçom). O Entregador não recebe.
Só vale com o caixa aberto e só para pedidos do caixa aberto. Cancelado, suspenso ou com ocorrência não avisa. Quando o pedido avança, é pago ou o caixa fecha, o aviso some sozinho. O alerta só avisa: não muda status nem pagamento.
Administrador: tempos, liga/desliga e teste do aviso em Administrador → Sistema → Sincronização e contingência → cartão "⏰ Alertas automáticos".$t$,array['Admin','Operador','Garçom','Cozinha']::text[],true,'lista',120,$t$Não tocou som: ligue os avisos (🔔) e o som no aparelho; no iPhone o app precisa estar instalado na tela inicial. Aviso que não some: o pedido ainda está parado; avance o status, resolva ou silenciar com motivo.$t$) on conflict (slug) do nothing;
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values ($t$man-admin-121-turno-do-caixa$t$,$t$Turno do caixa: o "hoje" dos pedidos$t$,$t$turno caixa hoje meia-noite madrugada passou da meia noite concluídas retiradas entregas mesas histórico vendas do turno resumo dia virada$t$,$t$O "hoje" das listas de pedidos segue o TURNO DO CAIXA (do momento em que o caixa abriu até o fechamento), não a data do calendário. Assim, quem abre à noite e fecha na madrugada não vê a lista zerar à meia-noite.
Isso vale para: Retiradas concluídas, Entregas concluídas, Histórico das mesas, "Minhas entregas / Meu dia" do entregador, "Vendas do turno" no Início, a meta diária e o Resumo do turno no Financeiro.
Sem caixa aberto, mostram o último turno. Só se nunca existiu caixa é que valem o dia do calendário.
Relatórios por dia ("Vendas por dia") e a ajuda diária do entregador continuam pela data do calendário.$t$,array['Admin','Operador','Garçom','Cozinha','Entregador']::text[],true,'lista',121,$t$Lista vazia logo depois de abrir o caixa é normal: o turno novo começa vazio.$t$) on conflict (slug) do nothing;
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values ($t$man-admin-122-receber-forma-pagamento$t$,$t$Marcar pedido como recebido (forma de pagamento)$t$,$t$marcar como recebido a receber pagou forma de pagamento dinheiro pix cartão dividir ifood fiado receber pedido aguardando pagamento$t$,$t$Pedido "A Receber" (retirada ou entrega): quando o cliente pagar, toque em "marcar como recebido".
O app pergunta em que forma o cliente pagou (Dinheiro, Pix, cartão…). O padrão é a forma do pedido; pedido do iFood vem como Dinheiro. Dá para dividir em duas formas.
O valor entra no caixa pela forma escolhida (o dinheiro na gaveta do caixa aberto). Mesa tem outro caminho: "Fechar conta" da mesa.$t$,array['Admin','Operador']::text[],true,'lista',122,$t$O botão não aparece: o pedido já está pago ou é de mesa (feche a conta da mesa).$t$) on conflict (slug) do nothing;
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values ($t$man-admin-123-teste-x-real$t$,$t$Separar vendas de teste do uso real$t$,$t$teste real uso real 17/10/2026 vendas de teste separar relatório período dados de teste apagar vendas teste$t$,$t$As vendas feitas até 16/10/2026 (inclusive) são de teste e ficam guardadas no sistema; o uso real começa em 17/10/2026. Nada foi apagado.
Em Relatórios e na Visão geral, escolha o período "Uso real (desde 17/10/2026)" para ver só o que é real.
O estoque dos ingredientes se acerta pelo Inventário (Produtos → Estoque → inventário de cada ingrediente): informe a contagem real e o sistema registra uma movimentação sem apagar o histórico.$t$,array['Admin']::text[],true,'lista',123,$t$Os períodos fixos (7, 30, 90 dias, mês) misturam teste e real até passarem 7, 30 ou 90 dias de 17/10/2026.$t$) on conflict (slug) do nothing;
commit;


-- ======================================================================
-- 10-ajustes-18-10-noite.sql
-- ======================================================================
-- =====================================================================
-- 10 · Ajustes da auditoria (18/10/2026, noite). Pode rodar de novo sem erro.
-- Já estão aplicados no banco em uso; este arquivo serve para refazer o banco do zero.
-- Rode DEPOIS do 09. Contém: (a) fuso de Brasília no resumo do Mercado Pago e no painel de IA,
-- (b) conferência do valor pago no Mercado Pago, (c) fechar funções internas para visitantes.
-- =====================================================================

-- (a) F5-4: mês do resumo do Mercado Pago e "últimos 7 dias" da IA usam o horário de Brasília (antes cortavam às 21h)
CREATE OR REPLACE FUNCTION public.api_mp_resumo_operacional(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_ini timestamptz := date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
        v_fim timestamptz := (date_trunc('month', now() at time zone 'America/Sao_Paulo') + interval '1 month') at time zone 'America/Sao_Paulo';
        v_total numeric(12,2); v_taxas numeric(12,2); v_qtd integer;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select coalesce(sum(greatest(x.valor - x.valor_reembolsado, 0)),0), count(*)::int into v_total, v_qtd
    from pagamentos_online x where x.status in ('aprovado','reembolso_parcial','reembolsado') and x.aprovado_em >= v_ini and x.aprovado_em < v_fim;
  select coalesce(sum(pv.taxa_aplicada),0) into v_taxas
    from pagamentos_online x join pagamentos_venda pv on pv.venda_id = x.venda_id
    where x.status in ('aprovado','reembolso_parcial','reembolsado') and x.aprovado_em >= v_ini and x.aprovado_em < v_fim;
  return jsonb_build_object('ok', true, 'periodo', to_char(v_ini at time zone 'America/Sao_Paulo','MM/YYYY'),
    'quantidade', v_qtd, 'total', round(v_total,2), 'taxas', round(v_taxas,2),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('metodo', q.metodo, 'quantidade', q.quantidade, 'total', q.total, 'taxas', q.taxas) order by q.metodo), '[]'::jsonb)
      from (select x.metodo, count(*)::int as quantidade, round(coalesce(sum(greatest(x.valor - x.valor_reembolsado, 0)),0),2) as total,
                   round(coalesce(sum(pv.taxa_aplicada),0),2) as taxas
              from pagamentos_online x left join (select venda_id, sum(taxa_aplicada) as taxa_aplicada from pagamentos_venda group by venda_id) pv on pv.venda_id = x.venda_id
             where x.status in ('aprovado','reembolso_parcial','reembolsado') and x.aprovado_em >= v_ini and x.aprovado_em < v_fim
             group by x.metodo) q));
end $function$;

CREATE OR REPLACE FUNCTION public.ia_painel_uso()
 RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $function$
begin
  if not tem_nivel('Admin') then return jsonb_build_object('ok', false, 'message', 'Sem permissão.'); end if;
  return jsonb_build_object('ok', true,
    'hoje', coalesce((select jsonb_agg(jsonb_build_object('provedor', provedor, 'chamadas', c, 'erros', e)) from
        (select provedor, sum(chamadas) c, sum(erros) e from ai_uso where dia = (now() at time zone 'America/Sao_Paulo')::date group by 1) x), '[]'::jsonb),
    'ultimos_7_dias', coalesce((select sum(chamadas) from ai_uso where dia >= (now() at time zone 'America/Sao_Paulo')::date - 7), 0),
    'erros_24h', (select count(*) from ai_log where status = 'erro' and criado_em >= now() - interval '24 hours'),
    'cache_24h', (select count(*) from ai_log where status = 'cache' and criado_em >= now() - interval '24 hours'));
end $function$;

-- (b) F51-1: se o Mercado Pago informar ("valorPago") um valor MENOR que o cobrado, o pedido vai para "a decidir" em vez de virar venda sozinho.
-- (Hoje as Edge Functions ainda não enviam "valorPago"; quando enviarem, a regra passa a valer sem outra mudança no banco.)
DO $$
declare d text;
begin
  select pg_get_functiondef('public.mp_aplicar_status(jsonb)'::regprocedure) into d;
  if position('v_vp' in d) = 0 then
    d := replace(d, 'v_antes numeric;', 'v_antes numeric; v_vp numeric;');
    d := replace(d, 'if g.status not in (''reembolso_parcial'', ''reembolsado'') then v_res := _mp_confirmar_pagamento(g.id); end if;',
      'if g.status not in (''reembolso_parcial'', ''reembolsado'') then
      v_vp := _num(p->>''valorPago'', 0);
      if v_vp > 0 and v_vp < g.valor - 0.009 and g.venda_id is null and g.decisao is null and not g.decisao_pendente then
        update pagamentos_online set status = ''aprovado'', aprovado_em = coalesce(aprovado_em, now()), erro = '''', atualizado_em = now() where id = g.id;
        perform _mp_marcar_decidir(g.id, ''Valor pago (R$ '' || _dinheiro(v_vp) || '') menor que o cobrado (R$ '' || _dinheiro(g.valor) || '')'');
        v_res := jsonb_build_object(''ok'', true, ''decidir'', true, ''motivo'', ''valor_diferente'');
      else
        v_res := _mp_confirmar_pagamento(g.id);
      end if;
    end if;');
    execute d;
  end if;
end $$;

-- (c) F2-3: funções internas (alertas, entrada de compra, alíquota) deixam de ser chamáveis por visitantes e por logados pela API.
-- Quem as usa é o servidor (agendamentos, Edge Functions e outras funções do banco).
DO $$
declare r record;
begin
  for r in select p.oid::regprocedure as f from pg_proc p where p.pronamespace='public'::regnamespace
     and p.proname in ('_alertas_cfg','_alertas_email','_alertas_pedidos_parados','_alertas_push','_alertas_sistema_avisar','_compra_receber2','_imposto_pct')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.f);
    execute format('grant execute on function %s to service_role', r.f);
  end loop;
end $$;


-- ======================================================================
-- 11-ajustes-finais-18-10.sql
-- ======================================================================
-- 11 - Ajustes finais da auditoria de 18/10 (F4-1 e F6-1). Pode rodar de novo sem problema.
-- F4-1: ao trocar o entregador, avisa se outra pessoa já tinha trocado (a tela manda 'entregadorVisto'; telas antigas continuam funcionando).
-- F6-1: no histórico do estoque, a devolução de uma venda editada/cancelada aparece como 'Estorno da venda #...'.
CREATE OR REPLACE FUNCTION public.api_atribuir_entregador(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v vendas; u usuarios; lg text := btrim(coalesce(p->>'entregador','')); ant text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if lg <> '' then
    select * into u from usuarios where lower(login) = lower(lg);
    if not found or u.nivel::text <> 'Entregador' then return _falha('Esse usuário não é um entregador cadastrado.'); end if;
    if not u.ativo then return _falha('Esse entregador está inativo.'); end if;
  end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.tipo <> 'Entrega' then return _falha('Só pedidos de entrega têm entregador.'); end if;
  if v.status_pedido::text = 'Entregue' then return _falha('Esta entrega já foi concluída.'); end if;
  if v.status_pedido::text = 'Saiu para entrega' and lg = '' then return _falha('O pedido já saiu para entrega — troque o entregador, não remova.'); end if;
  -- conflito: a tela mostrava um entregador e, enquanto isso, outra pessoa já trocou (só confere se a tela informou quem viu)
  if p ? 'entregadorVisto' and lower(coalesce(_login_de(v.entregador_id), '')) <> lower(btrim(coalesce(p->>'entregadorVisto', ''))) then
    return _conflito('O entregador deste pedido foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e atribua de novo.');
  end if;
  ant := coalesce(_login_de(v.entregador_id), '(nenhum)');
  update vendas set entregador_id = case when lg = '' then null else u.id end where id = v.id;
  perform _auditar('Entregador atribuído', '#' || v.numero_pedido || ': ' || ant || ' → ' || coalesce(nullif(lg,''), '(nenhum)'));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public._ajustar_estoque(p_itens jsonb, p_dir integer, p_venda uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; e estoque%rowtype; v_delta numeric; v_novo numeric;
        v_ref text := case when p_venda is not null then (case when p_dir < 0 then 'Estorno da venda #' else 'Venda #' end) || left(p_venda::text, 8) else case when p_dir > 0 then 'Venda' else 'Estorno de venda' end end;
        v_uid uuid := (select u.id from usuarios u where u.id = auth.uid());  -- cliente com conta não é da equipe: a movimentação fica sem usuário
begin
  for r in select * from _consumo(p_itens) order by ingrediente_id loop
    select * into e from estoque where id = r.ingrediente_id for update;
    if not found then continue; end if;
    v_delta := p_dir * r.qtd;
    v_novo := round(e.quantidade - v_delta, 3);
    update estoque set quantidade = v_novo where id = e.id;
    if p_dir > 0 and v_novo < 0 then perform _auditar('Estoque negativo', e.ingrediente || ': ' || v_novo || ' (' || v_ref || ')'); end if;
    if v_delta <> 0 then
      insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
      values (e.id, (case when p_dir > 0 then 'Venda' else 'Saída' end)::tipo_mov_estoque, -v_delta, e.quantidade, v_novo, v_ref, v_uid);
    end if;
  end loop;
end $function$;


-- ======================================================================
-- 12-ajuda-assistente-2.sql
-- ======================================================================
-- 12 - Assistente: 2 verbetes novos (cadastro de produto: aviso de "falta para ficar completo", sugestão de preço e Duplicar; e prints da Ajuda). Pode rodar de novo.
-- Desfazer: delete from public.ai_ajuda where slug in ('man-admin-123-produto-duplicar-sugestao','man-admin-124-ajuda-com-prints');
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-123-produto-duplicar-sugestao$t$,$t$Produto: duplicar, "falta para ficar completo" e sugestão de preço$t$,$t$duplicar produto copiar produto parecido novo produto completo falta preço sugerido sugestão preço margem lucro 40% usar custo receita ficha técnica$t$,
$t$Administrador → Produtos. Para criar um produto parecido com outro, toque em ⋯ (três pontos) na linha do produto → "📄 Duplicar". Abre o formulário já preenchido, com a receita copiada; nada é salvo até você tocar em "Cadastrar".
No formulário (novo ou edição) aparece o aviso "Falta para ficar completo" listando o que ainda não foi preenchido (custo, receita, categoria…). É só um lembrete: você pode salvar mesmo assim.
Se a margem de lucro estiver abaixo de 40%, aparece a "Sugestão de preço" (para ~50% de lucro) com o botão "Usar", que preenche o preço. Você decide se usa ou não; o preço nunca muda sozinho.$t$,
ARRAY['Admin'],true,'secao',123,$t$$t$),
($t$man-admin-124-ajuda-com-prints$t$,$t$Ajuda com prints (onde clicar) e busca$t$,$t$ajuda prints imagens fotos onde clicar buscar busca pesquisar ajuda tutorial passo a passo celular pc$t$,
$t$Toque em ❓ (Ajuda). No campo de busca digite uma palavra (ex.: caixa, entrega, cupom): só aparecem os assuntos que têm esse texto e o primeiro já abre.
Vários assuntos (abrir e fechar caixa, clientes, produtos, mesas, alertas…) trazem prints reais da tela, com números vermelhos que correspondem aos passos. No celular aparece o print do celular; no computador, o do PC.
O cliente tem a própria Ajuda ("Como pedir / Ajuda", no rodapé do cardápio), também com prints do cardápio, do item e do carrinho.$t$,
ARRAY['Admin','Operador','Garçom','Cozinha','Entregador'],true,'secao',124,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();


-- ======================================================================
-- 13-fechamento-auditoria.sql
-- ======================================================================
-- 13 - Fechamento da auditoria de 18/10: fidelidade desfeita ao cancelar (F3-2), forma de pagamento da diferença na edição (F5-3),
-- hora original da contingência no histórico (F5-2) e histórico das alterações feitas direto no cadastro pelo Admin (F7-2).
-- Pode rodar de novo sem erro. Desfazer: voltar_atras/DESFAZER-13-fechamento-auditoria.sql (no pacote de auditoria).

-- ===== F3-2: vínculo entre venda e marca de fidelidade =====
create table if not exists public.fidelidade_marcas (
  venda_id uuid primary key references public.vendas(id) on delete cascade,
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  premios_resgatados int not null default 0,
  criado_em timestamptz not null default now(),
  desfeita boolean not null default false
);
alter table public.fidelidade_marcas add column if not exists desfeita boolean not null default false;
alter table public.fidelidade_marcas enable row level security;
revoke all on public.fidelidade_marcas from public, anon, authenticated;
grant all on public.fidelidade_marcas to service_role;

create or replace function public._carimbar_fidelidade(p_tel text, p_nome text, p_venda uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_cli uuid := _upsert_cliente(p_tel, p_nome); f fidelidade%rowtype; v_marcou boolean := false;
begin
  if v_cli is null then return; end if;
  -- a mesma venda nunca marca duas vezes
  if p_venda is not null and exists (select 1 from fidelidade_marcas where venda_id = p_venda) then return; end if;
  select * into f from fidelidade where cliente_id = v_cli for update;
  if found then
    if f.carimbos < 10 then
      update fidelidade set carimbos = f.carimbos + 1, atualizada_em = now() where cliente_id = v_cli;
      perform _auditar('Marca adicionada (fidelidade)', (f.carimbos + 1) || '/10', p_tel);
      v_marcou := true;
    end if;
  else
    insert into fidelidade (cliente_id, carimbos, atualizada_em) values (v_cli, 1, now());
    perform _auditar('Cliente novo no fidelidade', coalesce(p_nome, ''), p_tel);
    v_marcou := true;
  end if;
  if v_marcou and p_venda is not null then
    insert into fidelidade_marcas (venda_id, cliente_id, premios_resgatados)
    values (p_venda, v_cli, coalesce((select premios_resgatados from fidelidade where cliente_id = v_cli), 0)) on conflict do nothing;
  end if;
end $function$;
revoke all on function public._carimbar_fidelidade(text, text, uuid) from public, anon, authenticated;
grant execute on function public._carimbar_fidelidade(text, text, uuid) to service_role;

create or replace function public._carimbar_fidelidade(p_tel text, p_nome text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_id uuid;
begin
  -- chamadas sem o id da venda (fechamento de conta de mesa): usa a venda do mesmo cliente que foi paga nesta mesma transação
  select v.id into v_id from vendas v
   where v.status = 'Confirmada' and v.recebido_em = now()
     and regexp_replace(coalesce(v.telefone_cliente, ''), '\D', '', 'g') = regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')
     and not exists (select 1 from fidelidade_marcas m where m.venda_id = v.id)
   order by v.numero_pedido limit 1;
  perform public._carimbar_fidelidade(p_tel, p_nome, v_id);
end $function$;
revoke all on function public._carimbar_fidelidade(text, text) from public, anon, authenticated;
grant execute on function public._carimbar_fidelidade(text, text) to service_role;

-- chamadores que passam o id da venda (o fechamento de mesa usa a versão de 2 parâmetros acima)
CREATE OR REPLACE FUNCTION public.api_iniciar_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_nivel nivel_acesso := auth_nivel(); v_eu uuid := auth.uid(); v_login text;
  v_itens jsonb := p->'itens'; v_pags jsonb := p->'pagamentos'; v_tipo_in text := p->>'tipoEntrega';
  v_mesa_id uuid := _uuid(p->>'mesaId'); v_mesa mesas%rowtype; v_mesa_status text; v_mesa_garcom uuid;
  v_origem text := coalesce(nullif(p->>'origem', ''), 'Balcão'); v_status_pag text := p->>'statusPagamento';
  v_nome text := btrim(coalesce(p->>'clienteNome', '')); v_tel text := btrim(coalesce(p->>'clienteTelefone', ''));
  v_de jsonb := case when jsonb_typeof(p->'dadosEntrega') = 'object' then p->'dadosEntrega' else '{}'::jsonb end;
  v_desc jsonb := case when jsonb_typeof(p->'desconto') = 'object' then p->'desconto' else null end;
  v_req text := nullif(left(coalesce(p->>'requisicaoId', ''), 80), ''); v_ja uuid;
  it record; pg record; v_exige boolean; v_qtd numeric; v_v numeric; v_c numeric; v_nome_item text; v_extra numeric; v_n_ad int; v_n_ok int;
  v_orig numeric := 0; v_custo numeric := 0; v_total_item numeric; v_desc_val numeric := 0; v_desc_det text := ''; v_sol numeric; v_aut text;
  v_tipo venda_tipo; v_taxa numeric := 0; v_total numeric; v_soma numeric := 0; v_erro text; v_venda uuid := gen_random_uuid();
  v_pad numeric; v_t numeric; v_forma_row formas_pagamento%rowtype; v_resumo text; v_origem_final origem_venda; v_status_pedido_ini status_pedido;
  v_status_pag_final status_pagamento; v_numero int; v_msg_extra text := ''; v_caixa uuid; v_bloqueia boolean; r record; v_acr numeric := 0;
begin
  if v_nivel is null or v_nivel not in ('Admin','Operador','Garçom') then return _negado(); end if;
  if jsonb_typeof(v_itens) <> 'array' or jsonb_array_length(v_itens) = 0 then return _falha('Adicione ao menos um item à venda.'); end if;
  if jsonb_typeof(v_pags) <> 'array' or jsonb_array_length(v_pags) = 0 then return _falha('Informe ao menos uma forma de pagamento.'); end if;
  if v_tipo_in = 'Mesa' and v_mesa_id is null then return _falha('Informe a mesa.'); end if;
  if v_origem like 'Contingência%' then return _falha('Vendas da contingência entram pelo botão "Trazer vendas pendentes da contingência" (Administrador).'); end if;
  if coalesce(p->'promocaoValidada'->>'ok', '') = 'true' then return _falha('Cupom não é aceito no Caixa. Use o desconto por porcentagem.'); end if;
  select login into v_login from usuarios where id = v_eu;
  select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;
  if v_caixa is null then return _falha(case when v_nivel = 'Garçom' then 'O caixa está fechado — peça ao caixa para abrir.' else 'Abra o caixa antes de registrar uma venda.' end); end if;
  if _caixa_vencido(v_caixa) then return _falha(_caixa_msg_vencido()); end if;

  -- garçom: só mesa/entrega/retirada, sem desconto, sem receber pagamento; vale no servidor, não só na tela
  if v_nivel = 'Garçom' then
    if v_tipo_in not in ('Mesa','Entrega','Retirada') then return _falha('O garçom só lança pedidos de mesa, entrega ou retirada.'); end if;
    if v_tipo_in <> 'Mesa' and v_tel = '' then return _falha('Informe o cliente (nome e telefone) para pedidos por telefone.'); end if;
    if v_tipo_in = 'Mesa' then
      select * into v_mesa from mesas where id = v_mesa_id for update;
      if not found then return _falha('Mesa não encontrada.'); end if;
      if v_mesa.status not in ('Livre','Ocupada') then return _falha('A mesa ' || v_mesa.numero || ' está "' || v_mesa.status || '" — não aceita novos itens.'); end if;
      if v_mesa.status = 'Ocupada' and v_mesa.garcom_responsavel_id is not null and v_mesa.garcom_responsavel_id <> v_eu then
        return _falha('Esta mesa está sob responsabilidade de outro garçom.');
      end if;
    end if;
    v_origem := 'Garçom'; v_desc := null; v_status_pag := 'A Receber';
    if v_tipo_in = 'Mesa' then
      v_pags := jsonb_build_array(jsonb_build_object('forma', 'A Receber (Mesa)', 'valor', _num(v_pags->0->>'valor')));
    else
      v_pags := jsonb_build_array(jsonb_build_object('forma', btrim(coalesce(v_pags->0->>'forma', '')), 'valor', _num(v_pags->0->>'valor')));
    end if;
  elsif v_tipo_in = 'Mesa' then
    select * into v_mesa from mesas where id = v_mesa_id for update;
    if not found then return _falha('Mesa não encontrada.'); end if;
  end if;

  if v_tipo_in = 'Mesa' then v_mesa_status := v_mesa.status::text; v_mesa_garcom := v_mesa.garcom_responsavel_id; end if;

  -- idempotência: a mesma requisição (duplo toque, nova tentativa) nunca gera duas vendas
  if v_req is not null then
    perform pg_advisory_xact_lock(hashtext('venda:' || v_req));
    select id into v_ja from vendas where requisicao_id = v_req;
    if found then return jsonb_build_object('ok', true, 'duplicado', true, 'id', v_ja, 'message', 'Venda já registrada — requisição repetida ignorada.'); end if;
  end if;

  -- itens: quantidade, preço, custo e (para quem não é Admin) preço conferido com o cadastro
  v_exige := not (v_nivel = 'Admin' and v_origem <> 'Cardápio');
  for it in select value as e from jsonb_array_elements(v_itens) loop
    v_nome_item := coalesce(nullif(it.e->>'descricao', ''), 'item');
    v_qtd := _num(it.e->>'quantidade'); v_v := _num(it.e->>'valorUnitario', -1); v_c := _num(it.e->>'custoUnitario');
    if not (v_qtd > 0) or v_qtd > 200 or v_qtd <> floor(v_qtd) then return _falha('Quantidade inválida em "' || v_nome_item || '".'); end if;
    if v_v < 0 then return _falha('Preço inválido em "' || v_nome_item || '".'); end if;
    if v_c < 0 then return _falha('Custo inválido em "' || v_nome_item || '".'); end if;
    if v_exige then
      if (_uuid(it.e->>'produtoId') is null and _uuid(it.e->>'comboId') is null) or (_uuid(it.e->>'produtoId') is not null and _uuid(it.e->>'comboId') is not null) then
        return _falha('"' || v_nome_item || '" não é um item cadastrado de forma válida.');
      end if;
      select count(*), coalesce(sum(a.preco) filter (where a.ativo), 0), count(a.id) filter (where a.ativo and ((_uuid(it.e->>'produtoId') is not null and exists (select 1 from produto_adicionais pa where pa.produto_id = _uuid(it.e->>'produtoId') and pa.adicional_id = a.id)) or (_uuid(it.e->>'comboId') is not null and exists (select 1 from combo_itens ci join produto_adicionais pa on pa.produto_id = ci.produto_id where ci.combo_id = _uuid(it.e->>'comboId') and pa.adicional_id = a.id))))
        into v_n_ad, v_extra, v_n_ok
        from jsonb_array_elements_text(case when jsonb_typeof(it.e->'adicionaisIds') = 'array' then it.e->'adicionaisIds' else '[]'::jsonb end) x
        left join adicionais a on a.id = _uuid(x);
      if v_n_ad <> v_n_ok then return _falha('O adicional selecionado para "' || v_nome_item || '" não está disponível.'); end if;
      if _uuid(it.e->>'produtoId') is not null then
        if not exists (select 1 from produto_precos pp where pp.produto_id = _uuid(it.e->>'produtoId') and abs(pp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome_item || ' enviado a R$ ' || _dinheiro(v_v));
          return _falha('O preço de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
        if not exists (select 1 from produto_precos pp where pp.produto_id = _uuid(it.e->>'produtoId') and abs(pp.preco + v_extra - v_v) <= 0.011 and abs(pp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome_item || ' enviado com custo R$ ' || _dinheiro(v_c));
          return _falha('O custo de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
      else
        if not exists (select 1 from combo_precos cp where cp.combo_id = _uuid(it.e->>'comboId') and abs(cp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome_item || ' enviado a R$ ' || _dinheiro(v_v));
          return _falha('O preço de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
        if not exists (select 1 from combo_precos cp where cp.combo_id = _uuid(it.e->>'comboId') and abs(cp.preco + v_extra - v_v) <= 0.011 and abs(cp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome_item || ' enviado com custo R$ ' || _dinheiro(v_c));
          return _falha('O custo de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
      end if;
    end if;
    v_total_item := round(v_qtd * v_v, 2);
    v_orig := v_orig + v_total_item; v_custo := v_custo + v_qtd * v_c;
  end loop;
  v_orig := round(v_orig, 2); v_custo := round(v_custo, 2);

  -- estoque (só se a regra "bloquear venda sem estoque" estiver ligada)
  select coalesce((select (valor #>> '{}') = 'true' from sistema where chave = 'BLOQUEAR_ESTOQUE_NEGATIVO'), false) into v_bloqueia;
  if v_bloqueia then
    for r in select c.ingrediente_id, c.qtd, e.ingrediente, e.quantidade from _consumo(v_itens) c join estoque e on e.id = c.ingrediente_id loop
      if r.quantidade + 0.000000001 < r.qtd then
        if v_origem = 'Cardápio' then return _falha('Um dos itens do pedido acabou. Escolha outro item ou fale com o restaurante.'); end if;
        return _falha('Estoque insuficiente de "' || r.ingrediente || '" (tem ' || r.quantidade || ', a venda precisa de ' || round(r.qtd, 3) || ').');
      end if;
    end loop;
  end if;

  -- desconto manual (precisa da senha de Admin quando quem lança não é Admin)
  if v_desc is not null and v_desc->>'valor' is not null then
    v_sol := _num(v_desc->>'valor', -1);
    if v_sol <= 0 then return _falha('Valor de desconto inválido.'); end if;
    v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
    if v_aut is null then return _falha('Senha de administrador incorreta — desconto não aplicado.'); end if;
    if v_desc->>'tipo' = 'percentual' then
      if v_sol > 100 then return _falha('O desconto percentual não pode ser maior que 100%.'); end if;
      v_desc_val := round(v_orig * (v_sol / 100), 2);
      v_desc_det := v_sol || '% (R$ ' || _dinheiro(v_desc_val) || ')';
    elsif coalesce(v_desc->>'tipo', 'fixo') = 'fixo' then
      if v_sol > v_orig then return _falha('O desconto fixo não pode ser maior que o valor da venda.'); end if;
      v_desc_val := round(v_sol, 2);
      v_desc_det := 'R$ ' || _dinheiro(v_desc_val) || ' fixo';
    else
      return _falha('Tipo de desconto inválido.');
    end if;
    if v_desc_val <= 0 or v_desc_val >= v_orig then return _falha('O desconto não pode deixar a venda com valor zero ou negativo.'); end if;
  end if;

  -- tipo, taxa de entrega e total
  v_tipo := case v_tipo_in when 'Entrega' then 'Entrega' when 'Mesa' then 'Mesa' else 'Retirada' end::venda_tipo;
  if v_tipo = 'Entrega' and btrim(coalesce(v_de->>'endereco', '')) = '' then return _falha('Informe o endereço da entrega.'); end if;
  if v_tipo = 'Entrega' and coalesce(v_de->>'freteGratis', '') <> 'true' then
    select coalesce(_num(valor #>> '{}'), 0) into v_pad from sistema where chave = 'TaxaEntregaPadrao';
    v_taxa := coalesce(v_pad, 0);
    if v_nivel in ('Admin','Operador') and nullif(btrim(coalesce(v_de->>'taxa', '')), '') is not null then
      v_t := _num(v_de->>'taxa', -1);
      if v_t >= 0 and v_t <= 500 then v_taxa := round(v_t, 2); end if;
    end if;
  end if;
  v_total := round(v_orig - v_desc_val + v_taxa, 2);
  if v_total < 0.01 then return _falha('O total da venda precisa ser maior que zero.'); end if;
  if v_nivel = 'Garçom' and v_tipo_in <> 'Mesa' then
    v_pags := jsonb_build_array(jsonb_build_object('forma', v_pags->0->>'forma', 'valor', v_total));
  end if;

  -- pagamentos
  if exists (select 1 from jsonb_array_elements(v_pags) e where e->>'forma' = 'A Receber (Mesa)') then
    if jsonb_array_length(v_pags) <> 1 then return _falha('Forma de pagamento inválida para esta operação.'); end if;
    v_status_pag := 'A Receber';
  end if;
  for pg in select value as e from jsonb_array_elements(v_pags) loop
    if btrim(coalesce(pg.e->>'forma', '')) = '' then return _falha('Forma de pagamento não informada.'); end if;
    if not (_num(pg.e->>'valor', 0) > 0) then return _falha('Cada pagamento deve ter um valor maior que zero.'); end if;
    if btrim(pg.e->>'forma') = 'A Receber (Mesa)' then
      if v_nivel not in ('Admin','Operador','Garçom') or v_tipo_in <> 'Mesa' then return _falha('Forma de pagamento inválida para esta operação.'); end if;
      continue;
    end if;
    select * into v_forma_row from formas_pagamento where lower(nome) = lower(btrim(pg.e->>'forma')) limit 1;
    if not found then return _falha('Forma de pagamento não cadastrada: ' || btrim(pg.e->>'forma')); end if;
    if not v_forma_row.ativa then return _falha('A forma de pagamento está inativa: ' || btrim(pg.e->>'forma')); end if;
  end loop;
  select round(coalesce(sum(_num(e->>'valor')), 0), 2) into v_soma from jsonb_array_elements(v_pags) e;
  if abs(v_soma - v_total) > 0.02 then
    return _falha('A soma dos pagamentos (R$ ' || _dinheiro(v_soma) || ') não bate com o total da venda (R$ ' || _dinheiro(v_total) || ').');
  end if;

  -- acréscimo por forma de pagamento: os valores enviados são a parte do pedido paga em cada forma (sem acréscimo)
  for pg in select value as e from jsonb_array_elements(v_pags) loop
    if btrim(pg.e->>'forma') = 'A Receber (Mesa)' then continue; end if;
    v_acr := v_acr + _acrescimo_pagamento(pg.e->>'forma', round(_num(pg.e->>'valor') * (case when v_total > 0 then (v_total - v_taxa) / v_total else 1 end), 2));
  end loop;
  v_total := round(v_total + v_acr, 2);

  -- grava tudo
  v_status_pag_final := case when v_status_pag = 'A Receber' then 'A Receber' else 'Pago' end::status_pagamento;
  v_origem_final := (case when v_origem in ('Cardápio','Garçom') then v_origem else 'Balcão' end)::origem_venda;
  v_status_pedido_ini := (case when v_origem_final = 'Cardápio' then 'Recebido' else 'Em preparo' end)::status_pedido;
  select string_agg(btrim(e->>'forma'), ' + ') into v_resumo from jsonb_array_elements(v_pags) e;

  insert into vendas (id, cliente_nome, telefone_cliente, forma_pagamento, valor_total, custo_total, status, tipo, status_pedido,
                      endereco, complemento, referencia, observacoes_entrega, status_pagamento, recebido_em, valor_original, valor_desconto,
                      desconto_detalhe, origem, mesa_id, taxa_entrega, registrado_por, caixa_id, requisicao_id, acrescimo_forma)
  values (v_venda, v_nome, v_tel, v_resumo, v_total, v_custo, 'Confirmada', v_tipo, v_status_pedido_ini,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'endereco', '') else '' end,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'complemento', '') else '' end,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'referencia', '') else '' end,
          coalesce(v_de->>'observacoes', ''), v_status_pag_final, case when v_status_pag_final = 'Pago' then now() else null end,
          v_orig, v_desc_val, v_desc_det, v_origem_final, case when v_tipo = 'Mesa' then v_mesa_id else null end, v_taxa, v_eu, v_caixa, v_req, v_acr)
  returning numero_pedido into v_numero;

  insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)
  select v_venda, _uuid(e->>'produtoId'), _uuid(e->>'comboId'), e->>'descricao', _num(e->>'quantidade', 1)::int,
         _num(e->>'valorUnitario'), _num(e->>'custoUnitario'), round(_num(e->>'quantidade', 1) * _num(e->>'valorUnitario'), 2),
         coalesce((select array_agg(_uuid(x)) filter (where _uuid(x) is not null)
                   from jsonb_array_elements_text(case when jsonb_typeof(e->'adicionaisIds') = 'array' then e->'adicionaisIds' else '[]'::jsonb end) x), '{}')
  from jsonb_array_elements(v_itens) e;

  insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada, acrescimo)
  select v_venda, btrim(e->>'forma'), _num(e->>'valor') + _acrescimo_pagamento(e->>'forma', _num(e->>'valor')),
         coalesce((select round((_num(e->>'valor') + _acrescimo_pagamento(e->>'forma', _num(e->>'valor'))) * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where f.nome = btrim(e->>'forma')), 0),
         _acrescimo_pagamento(e->>'forma', _num(e->>'valor'))
  from jsonb_array_elements(v_pags) e;

  if v_tipo = 'Mesa' and v_mesa_status = 'Livre' then
    update mesas set status = 'Ocupada', garcom_responsavel_id = case when v_nivel = 'Garçom' then v_eu else garcom_responsavel_id end where id = v_mesa_id;
  elsif v_tipo = 'Mesa' and v_nivel = 'Garçom' and v_mesa_garcom is null then
    update mesas set garcom_responsavel_id = v_eu where id = v_mesa_id;
  end if;

  perform _ajustar_estoque(v_itens, 1, v_venda);

  if v_desc_val > 0 then
    perform _auditar('Desconto aplicado na venda', 'Autorizado por ' || coalesce(nullif(current_setting('app.autorizador', true), ''), v_login) || ' | Valor original: R$ ' || _dinheiro(v_orig)
      || ' → Desconto: ' || v_desc_det || ' → Valor final: R$ ' || _dinheiro(v_total), v_tel);
  end if;
  if v_tel <> '' then
    perform _upsert_cliente(v_tel, v_nome);
    if v_origem_final = 'Balcão' and v_status_pag_final = 'Pago' then
      perform _carimbar_fidelidade(v_tel, v_nome, v_venda);
      v_msg_extra := ' Marca de fidelidade adicionada para ' || v_nome || '.';
    end if;
  end if;
  perform _auditar('Venda registrada', 'Total R$ ' || _dinheiro(v_total) || ' via ' || v_resumo || ' (' || v_tipo || ', ' || v_status_pag_final || ')', v_tel);

  return jsonb_build_object('ok', true, 'message', 'Venda registrada: R$ ' || _dinheiro(v_total) || '.' || v_msg_extra,
                            'id', v_venda, 'numero', v_numero, 'valorTotal', v_total);
end $function$;

CREATE OR REPLACE FUNCTION public.api_confirmar_recebimento_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v vendas; pg record; forma formas_pagamento; v_base numeric; v_soma numeric; v_acr numeric := 0; v_acr_p numeric; v_resumo text; v_troca boolean; v_i int; v_val numeric; v_taxa numeric; v_pid uuid;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v;
  if t.erro is not null then return case when v.status = 'Cancelada' then _falha('Este pedido foi cancelado — não dá para receber o pagamento.') else t.erro end; end if;
  if v.status_pagamento = 'Pago' then return jsonb_build_object('ok', true, 'duplicado', true, 'message', 'Este pedido já estava com o pagamento confirmado.'); end if;
  v_troca := jsonb_typeof(p->'pagamentos') = 'array' and jsonb_array_length(p->'pagamentos') > 0;
  if v_troca then
    if jsonb_array_length(p->'pagamentos') > 4 then return _falha('No máximo 4 formas de pagamento.'); end if;
    for pg in select value as e from jsonb_array_elements(p->'pagamentos') loop
      if btrim(coalesce(pg.e->>'forma','')) in ('', 'A Receber (Mesa)') then return _falha('Forma de pagamento inválida.'); end if;
      if not (_num(pg.e->>'valor', 0) > 0) then return _falha('Cada pagamento deve ter um valor maior que zero.'); end if;
      select * into forma from formas_pagamento where lower(nome) = lower(btrim(pg.e->>'forma')) limit 1;
      if not found then return _falha('Forma de pagamento não cadastrada: ' || btrim(pg.e->>'forma')); end if;
      if not forma.ativa then return _falha('A forma de pagamento está inativa: ' || btrim(pg.e->>'forma')); end if;
    end loop;
    v_base := round(v.valor_total - coalesce(v.acrescimo_forma, 0), 2);
    select round(coalesce(sum(_num(e->>'valor')), 0), 2) into v_soma from jsonb_array_elements(p->'pagamentos') e;
    if abs(v_soma - v_base) > 0.02 then return _falha('A soma dos pagamentos (R$ ' || _dinheiro(v_soma) || ') não bate com o valor do pedido (R$ ' || _dinheiro(v_base) || ').'); end if;
    -- reaproveita as linhas que já existem (sem apagar nada): linha i do pedido recebe o pagamento i;
    -- pagamento a mais vira linha nova; linha antiga que sobrar fica com valor zero na 1ª forma informada (não muda nenhuma soma).
    v_i := 0;
    for pg in select value as e, ordinality as n from jsonb_array_elements(p->'pagamentos') with ordinality loop
      v_acr_p := round(_acrescimo_pagamento(btrim(pg.e->>'forma'), _num(pg.e->>'valor')), 2);
      v_acr := v_acr + v_acr_p; v_i := pg.n;
      v_val := round(_num(pg.e->>'valor'), 2) + v_acr_p;
      v_taxa := coalesce((select round(v_val * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where lower(f.nome) = lower(btrim(pg.e->>'forma'))), 0);
      select id into v_pid from pagamentos_venda where venda_id = v.id order by id offset (pg.n - 1) limit 1;
      if v_pid is not null then
        update pagamentos_venda set forma_pagamento = btrim(pg.e->>'forma'), valor = v_val, taxa_aplicada = v_taxa, acrescimo = v_acr_p where id = v_pid;
      else
        insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada, acrescimo) values (v.id, btrim(pg.e->>'forma'), v_val, v_taxa, v_acr_p);
      end if;
      v_pid := null;
    end loop;
    update pagamentos_venda set valor = 0, taxa_aplicada = 0, acrescimo = 0, forma_pagamento = (select btrim(e->>'forma') from jsonb_array_elements(p->'pagamentos') e limit 1)
     where venda_id = v.id and id in (select id from pagamentos_venda where venda_id = v.id order by id offset v_i);
    select string_agg(btrim(e->>'forma'), ' + ') into v_resumo from jsonb_array_elements(p->'pagamentos') e;
    update vendas set status_pagamento = 'Pago', recebido_em = now(), forma_pagamento = v_resumo, valor_total = v_base + v_acr, acrescimo_forma = v_acr where id = v.id;
  else
    update vendas set status_pagamento = 'Pago', recebido_em = now() where id = v.id;
  end if;
  if nullif(v.telefone_cliente,'') is not null then perform _carimbar_fidelidade(v.telefone_cliente, v.cliente_nome, v.id); end if;
  perform _auditar('Pagamento confirmado', '#' || v.numero_pedido || case when v_troca and v_resumo is distinct from v.forma_pagamento then ' — forma: ' || coalesce(v.forma_pagamento,'?') || ' → ' || v_resumo else '' end, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public._mp_criar_venda(p_reserva uuid, p_pag uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r pedidos_reserva%rowtype; f formas_pagamento%rowtype; v_caixa uuid; v_venda uuid := gen_random_uuid(); v_numero int; v_cli uuid;
        v_cod text; rec record; v_tipo venda_tipo; v_de jsonb; v_nome text; v_cc uuid;
begin
  select * into r from pedidos_reserva where id = p_reserva for update;
  if not found then raise exception 'Reserva não encontrada.'; end if;
  select * into f from formas_pagamento where id = r.forma_pagamento_id;
  v_nome := coalesce(f.nome, 'Pagamento online');
  select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;
  if v_caixa is null then raise exception 'Caixa fechado.'; end if;
  v_tipo := (case when r.tipo_entrega = 'Entrega' then 'Entrega' else 'Retirada' end)::venda_tipo;
  v_de := coalesce(r.dados_entrega, '{}'::jsonb);
  v_cod := coalesce(r.cupom->>'codigo', '');

  insert into vendas (id, cliente_nome, telefone_cliente, forma_pagamento, valor_total, custo_total, status, tipo, status_pedido,
                      endereco, complemento, referencia, observacoes_entrega, status_pagamento, recebido_em, valor_original, valor_desconto,
                      desconto_detalhe, origem, mesa_id, taxa_entrega, caixa_id, requisicao_id, acrescimo_forma)
  values (v_venda, r.cliente_nome, r.telefone, v_nome, r.valor_total, r.custo_total, 'Confirmada', v_tipo, 'Recebido',
          case when v_tipo = 'Entrega' then coalesce(v_de->>'endereco', '') else '' end, case when v_tipo = 'Entrega' then coalesce(v_de->>'complemento', '') else '' end,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'referencia', '') else '' end, r.observacoes, 'Pago', now(), r.valor_original, r.valor_desconto,
          case when v_cod <> '' then 'Cupom ' || v_cod else '' end, 'Cardápio', null, r.taxa_entrega, v_caixa, r.requisicao_id, r.acrescimo_forma)
  returning numero_pedido into v_numero;

  insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)
  select v_venda, _uuid(e->>'produtoId'), _uuid(e->>'comboId'), e->>'descricao', _num(e->>'quantidade', 1)::int, _num(e->>'valorUnitario'), _num(e->>'custoUnitario'),
         round(_num(e->>'quantidade', 1) * _num(e->>'valorUnitario'), 2),
         coalesce((select array_agg(_uuid(x)) filter (where _uuid(x) is not null) from jsonb_array_elements_text(e->'adicionaisIds') x), '{}')
  from jsonb_array_elements(r.itens) e;

  insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada, acrescimo)
  values (v_venda, v_nome, r.valor_total, round(r.valor_total * coalesce(f.taxa_percentual, 0) / 100 + coalesce(f.taxa_fixa, 0), 2), r.acrescimo_forma);

  if r.telefone <> '' then
    v_cli := _upsert_cliente(r.telefone, r.cliente_nome);
    perform _carimbar_fidelidade(r.telefone, r.cliente_nome, v_venda);   -- como no recebimento manual: pedido pago = marca no cartão fidelidade
  end if;
  insert into contas_pedidos (venda_id, user_id) values (v_venda, r.user_id) on conflict do nothing;

  if r.cupom_uso_id is not null then update cupons_usos set venda_id = v_venda, cliente_id = v_cli where id = r.cupom_uso_id; end if;
  v_cc := _uuid(r.cupom->>'concedidoId');
  if v_cc is not null then update cupons_concedidos set venda_id = v_venda where id = v_cc; end if;
  for rec in select value as e from jsonb_array_elements(r.beneficios) loop
    if _uuid(rec.e->>'id') is not null then update contas_beneficios set venda_id = v_venda where id = _uuid(rec.e->>'id'); end if;
  end loop;

  update pedidos_reserva set estado = 'confirmada', venda_id = v_venda, atualizado_em = now() where id = r.id;
  update pagamentos_online set venda_id = v_venda, atualizado_em = now() where id = p_pag;
  perform _auditar_publico('Pedido pago pelo site (Mercado Pago)', 'Nº ' || v_numero || ' | Total R$ ' || _dinheiro(r.valor_total), r.telefone);
  return jsonb_build_object('vendaId', v_venda, 'numero', v_numero);
end $function$;

CREATE OR REPLACE FUNCTION public._trg_conta_cancelada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid; bf record; mk record;
begin
  begin
    -- desfaz a marca de fidelidade que este pedido deu (vínculo guardado em fidelidade_marcas)
    for mk in select * from fidelidade_marcas where venda_id = new.id and not desfeita loop
      update fidelidade set carimbos = greatest(0, carimbos - 1), atualizada_em = now()
       where cliente_id = mk.cliente_id and carimbos > 0 and premios_resgatados = mk.premios_resgatados;
      if found then perform _auditar('Marca de fidelidade desfeita (venda cancelada)', 'Venda #' || new.numero_pedido); end if;
      update fidelidade_marcas set desfeita = true where venda_id = new.id;
    end loop;
    -- devolve o cupom recebido que foi usado neste pedido
    update cupons_concedidos set usado_em = null, venda_id = null where venda_id = new.id;
    update cupons_usos set user_id = null, telefone = '' where venda_id = new.id and cupom_id in (select id from cupons where automatico is not null);
    -- brindes usados neste pedido voltam: o de indicação fica disponível de novo e o cartão fidelidade reabre
    update contas_beneficios set status = 'Disponível', venda_id = null, usado_em = null, produto_id = null where venda_id = new.id and tipo = 'Indicação' and status = 'Usado';
    for bf in select b.id, cc.cliente_id from contas_beneficios b join contas_cliente cc on cc.user_id = b.user_id where b.venda_id = new.id and b.tipo = 'Fidelidade' and b.status = 'Usado' loop
      update fidelidade set carimbos = 10, premios_resgatados = greatest(0, premios_resgatados - 1), atualizada_em = now() where cliente_id = bf.cliente_id;
      update contas_beneficios set status = 'Anulado' where id = bf.id;
    end loop;
    -- indique e ganhe: se o pedido cancelado era o único concluído do indicado, o prêmio ainda não usado perde o efeito
    select user_id into u from contas_pedidos where venda_id = new.id;
    if u is not null and not exists (select 1 from contas_pedidos cp join vendas v on v.id = cp.venda_id
                                      where cp.user_id = u and v.id <> new.id and v.status = 'Confirmada' and v.status_pedido in ('Entregue', 'Retirada', 'Servida')) then
      update contas_beneficios set status = 'Anulado' where tipo = 'Indicação' and ref = u::text and status = 'Disponível';
      update cupons_concedidos set usado_em = now() where ref = u::text and origem in ('indicacao_indicador', 'indicacao_indicado') and usado_em is null and venda_id is null;
    end if;
  exception when others then null;
  end;
  return null;
end $function$;

-- F5-3: na edição da venda, a diferença a mais pode ser paga em outra forma (parâmetro opcional formaDiferenca; sem ele nada muda).
-- A função original passa a se chamar _editar_venda_base e api_editar_venda vira um envoltório que acerta os pagamentos depois dela.
do $$ begin
  if to_regprocedure('public._editar_venda_base(jsonb)') is null then
    alter function public.api_editar_venda(jsonb) rename to _editar_venda_base;
    revoke all on function public._editar_venda_base(jsonb) from public, anon, authenticated;
  end if;
end $$;

create or replace function public.api_editar_venda(p jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r jsonb; v_fdif text := nullif(btrim(coalesce(p->>'formaDiferenca', '')), ''); v_id uuid := _uuid(p->>'id');
  fd formas_pagamento%rowtype; pv pagamentos_venda%rowtype; v_antes numeric; v_npag int; v_novo numeric; v_acr_novo numeric; v_dif numeric; v_acr_d numeric; v_total numeric;
begin
  if v_fdif is null then return _editar_venda_base(p); end if;
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select * into fd from formas_pagamento where lower(nome) = lower(v_fdif) and ativa;
  if not found then return _falha('A forma de pagamento da diferença não está disponível.'); end if;
  select count(*) into v_npag from pagamentos_venda where venda_id = v_id;
  select valor_total into v_antes from vendas where id = v_id;
  select * into pv from pagamentos_venda where venda_id = v_id limit 1;
  r := _editar_venda_base(p);
  if v_npag <> 1 or coalesce(r->>'ok', '') <> 'true' or lower(fd.nome) = lower(coalesce(pv.forma_pagamento, '')) then return r; end if;
  select valor_total, coalesce(acrescimo_forma, 0) into v_novo, v_acr_novo from vendas where id = v_id;
  v_dif := round((v_novo - v_acr_novo) - (v_antes - coalesce(pv.acrescimo, 0)), 2);   -- quanto os itens aumentaram (sem acréscimo de forma)
  if v_dif <= 0.009 then return r; end if;
  v_acr_d := _acrescimo_forma(fd, greatest(0.01, v_dif));
  v_total := round((v_novo - v_acr_novo) + coalesce(pv.acrescimo, 0) + v_acr_d, 2);
  -- o pagamento original volta ao que era e a diferença vira um segundo pagamento
  update pagamentos_venda set valor = pv.valor, acrescimo = pv.acrescimo, taxa_aplicada = pv.taxa_aplicada where id = pv.id;
  insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada, acrescimo)
  values (v_id, fd.nome, round(v_dif + v_acr_d, 2), round((v_dif + v_acr_d) * fd.taxa_percentual / 100 + fd.taxa_fixa, 2), v_acr_d);
  update vendas set valor_total = v_total, acrescimo_forma = round(coalesce(pv.acrescimo, 0) + v_acr_d, 2) where id = v_id;
  perform _auditar('Venda editada: diferença em outra forma', 'R$ ' || _dinheiro(round(v_dif + v_acr_d, 2)) || ' em ' || fd.nome || ' (a venda era ' || coalesce(pv.forma_pagamento, '?') || ')');
  return r || jsonb_build_object('message', replace(coalesce(r->>'message', ''), 'Novo total: R$ ' || _dinheiro(v_novo), 'Novo total: R$ ' || _dinheiro(v_total)));
end $function$;
revoke all on function public.api_editar_venda(jsonb) from public, anon;
grant execute on function public.api_editar_venda(jsonb) to authenticated, service_role;

-- F5-2: o histórico da reconciliação guarda a hora em que a venda foi feita de verdade (a venda continua entrando no turno de hoje)
CREATE OR REPLACE FUNCTION public.api_reconciliar_venda_contingencia(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id text := nullif(left(btrim(coalesce(p->>'idFila','')), 120), '');
  d jsonb := p->'dados'; v_ja contingencia_reconciliada%rowtype; v_r jsonb; v_req text; v_venda uuid; v_origem text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_id is null or jsonb_typeof(d) <> 'object' or jsonb_typeof(d->'itens') <> 'array' then return _falha('Item da fila da contingência inválido.'); end if;
  perform pg_advisory_xact_lock(hashtext('recon:' || v_id));
  select * into v_ja from contingencia_reconciliada where id_fila = v_id;
  if found then return jsonb_build_object('ok', true, 'jaFeita', true, 'id', v_ja.venda_id); end if;

  v_origem := coalesce(d->>'origem', '');
  if v_origem = 'Cardápio' then
    -- mesmo caminho do pedido do cardápio; o id da fila vira requisicaoId (reenvio devolve o pedido já criado)
    v_r := _criar_pedido_publico((d - 'desconto' - 'senhaAdminConfirmacao') || jsonb_build_object('requisicaoId', v_id), null);
  elsif v_origem = 'Caixa' then
    -- usa o id da tentativa original: se o servidor chegou a gravar a venda antes de cair, não duplica
    v_req := coalesce(nullif(d->>'requisicaoOriginal', ''), v_id);
    v_r := api_iniciar_venda((d - 'desconto' - 'senhaAdminConfirmacao' - 'timestampOriginal' - 'requisicaoOriginal' - 'emergenciaOperador')
      || jsonb_build_object('origem', 'Balcão', 'requisicaoId', v_req));
  else
    return _falha('Origem desconhecida na fila: ' || left(v_origem, 40));
  end if;

  if coalesce(v_r->>'ok', '') <> 'true' then
    return jsonb_build_object('ok', false, 'message', coalesce(v_r->>'message', 'Não foi possível lançar a venda.'));
  end if;
  v_venda := nullif(v_r->>'id', '')::uuid;
  insert into contingencia_reconciliada (id_fila, venda_id, origem, usuario_id) values (v_id, v_venda, v_origem, auth.uid()) on conflict do nothing;
  perform _auditar('Venda da contingência reconciliada',
    'Fila ' || v_id || ' · origem ' || v_origem || ' · venda ' || left(coalesce(v_venda::text, ''), 8)
      || case when coalesce(d->>'timestampOriginal', '') <> '' then ' · feita em ' || left(d->>'timestampOriginal', 40) else '' end
      || case when coalesce(d->>'emergenciaOperador', '') <> '' then ' · feita em modo emergência por ' || left(d->>'emergenciaOperador', 40) else '' end, '');
  return jsonb_build_object('ok', true, 'id', v_venda, 'numero', v_r->'numero', 'duplicado', coalesce((v_r->>'duplicado')::boolean, false));
end $function$;

-- F7-2: o que o Admin altera direto nas telas de cadastro agora deixa registro no histórico (nome do item e quais campos mudaram; nunca o conteúdo).
-- Só registra pedidos feitos direto na tabela (PostgREST); mudanças feitas por funções do sistema já têm o próprio registro.
create or replace function public._trg_auditar_cadastro()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_path text := coalesce(current_setting('request.path', true), ''); n jsonb; o jsonb; v_nome text; v_campos text;
begin
  if auth.uid() is null or v_path = '' or v_path like '%/rpc/%' then return null; end if;
  n := to_jsonb(coalesce(new, old)); o := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  v_nome := left(coalesce(n->>'nome', n->>'ingrediente', n->>'chave', n->>'descricao', n->>'id', ''), 80);
  if tg_op = 'UPDATE' then
    select string_agg(k, ', ' order by k) into v_campos from jsonb_object_keys(n) k
     where n->k is distinct from o->k and k not in ('atualizado_em', 'updated_at', 'atualizada_em');
    if v_campos is null then return null; end if;
    if tg_table_name = 'estoque' and v_campos = 'quantidade' then return null; end if;   -- baixa por venda/compra tem histórico próprio
  end if;
  perform _auditar('Cadastro alterado direto (' || tg_table_name || ')', lower(tg_op) || ' · ' || v_nome || case when v_campos is not null then ' · campos: ' || left(v_campos, 200) else '' end);
  return null;
end $function$;
revoke all on function public._trg_auditar_cadastro() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['produtos','produto_precos','combos','combo_precos','adicionais','formas_pagamento','estoque','sistema','categorias'] loop
    if to_regclass('public.' || t) is not null then
      execute format('create or replace trigger trg_auditar_cadastro after insert or update or delete on public.%I for each row execute function public._trg_auditar_cadastro()', t);
    end if;
  end loop;
end $$;


-- ======================================================================
-- 14-alertas-repetem.sql
-- ======================================================================
-- =====================================================================
-- 14 · ALERTAS QUE SE REPETEM ATÉ O PROBLEMA SER RESOLVIDO (18/10/2026)
-- Antes: avisos do SISTEMA (caixa vencido, backup parado, planilha parada...) repetiam só a cada 6 h, 12 h, 24 h ou 7 dias.
-- Agora: repetem a cada "sistema_repetir_min" minutos (padrão 30, o Admin ajusta em Configurar avisos) enquanto o problema existir.
--   • e-mail: no máximo 1 a cada 6 h por problema (para não lotar a caixa); o push e o som seguem repetindo;
--   • vencimentos cadastrados: 1 vez por dia; no último dia e depois de vencido, a cada 6 h;
--   • o app aberto do Admin também mostra a faixa e toca o som a cada novo aviso do sistema.
-- Aviso de PEDIDO parado já repetia (a cada "repetirMin") até resolver, adiar ou silenciar; não muda.
-- Aditivo: 2 colunas novas e 4 funções recriadas. Nada é apagado.
-- =====================================================================

alter table public.alertas_config add column if not exists sistema_repetir_min int not null default 30;
alter table public.alertas_envios add column if not exists ultimo_email_em timestamptz;

create or replace function public._alertas_cfg() returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c alertas_config%rowtype; v_reg jsonb := _alertas_padrao(); k text;
begin
  select * into c from alertas_config where id;
  for k in select jsonb_object_keys(_alertas_padrao()) loop
    if c.regras ? k then v_reg := jsonb_set(v_reg, array[k], (v_reg->k) || (c.regras->k)); end if;
  end loop;
  return jsonb_build_object('regras', v_reg, 'repetirMin', coalesce(c.repetir_min, 5), 'escalarApos', coalesce(c.escalar_apos, 3),
                            'sistemaRepetirMin', coalesce(c.sistema_repetir_min, 30),
                            'vencimentos', coalesce(c.vencimentos, '[]'::jsonb), 'emailAtivo', coalesce(c.email_ativo, true));
end $$;

create or replace function public._alertas_sistema_avisar(p_chave text, p_titulo text, p_texto text, p_repetir interval default interval '6 hours')
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare e alertas_envios%rowtype; v_rep interval; v_mail boolean;
begin
  v_rep := make_interval(mins => greatest(5, coalesce((select sistema_repetir_min from alertas_config where id), 30)));
  if p_chave like 'sis:venc:%' then   -- vencimento cadastrado: 1x por dia; último dia e vencido: a cada 6 h
    v_rep := case when p_chave like '%:vencido' or p_chave like '%:1' then interval '6 hours' else interval '1 day' end;
  end if;
  select * into e from alertas_envios where chave = p_chave for update;
  if e.chave is not null and e.resolvido_em is null and (e.silenciado or now() - e.ultimo_em < v_rep) then return false; end if;
  v_mail := e.chave is null or e.resolvido_em is not null or e.ultimo_email_em is null or now() - e.ultimo_email_em >= interval '6 hours';
  insert into alertas_envios (chave, tipo, titulo, texto) values (p_chave, 'sistema', p_titulo, p_texto)
  on conflict (chave) do update set ultimo_em = now(), vezes = case when alertas_envios.resolvido_em is null then alertas_envios.vezes + 1 else 1 end,
     resolvido_em = null, titulo = excluded.titulo, texto = excluded.texto, silenciado = false,
     ultimo_email_em = case when v_mail then now() else alertas_envios.ultimo_email_em end;
  if e.chave is null or e.resolvido_em is not null or e.vezes < 3 or e.vezes % 12 = 0 then   -- auditoria: não enche o registro com cada repetição
    insert into auditoria (usuario_login, acao, detalhes) values ('sistema', 'ALERTA: ' || left(p_titulo, 80), left(p_texto, 300));
  end if;
  perform _alertas_push('⚠️ ' || p_titulo, p_texto || case when coalesce(e.vezes, 0) >= 1 and e.resolvido_em is null then ' (aviso ' || (e.vezes + 1) || ', continua sem resolver)' else '' end, 'sis-' || left(p_chave, 40), array['Admin']);
  if v_mail then
    perform _alertas_email(coalesce(nullif((select valor ->> 'nome' from sistema where chave = 'Marca'), ''), 'Restaurante') || ' — ' || p_titulo, p_texto || E'\n\nAviso automático do sistema (' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ').');
  end if;
  return true;
end $$;

create or replace function public.api_alertas_pedidos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_niv text := auth_nivel()::text; v_l jsonb; v_s jsonb := '[]'::jsonb;
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha', 'Garçom') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('vendaId', x.venda_id, 'numero', x.numero, 'regra', x.regra, 'rotulo', x.rotulo, 'minutos', x.minutos,
           'vezes', coalesce(e.vezes, 0)) order by x.minutos desc), '[]'::jsonb) into v_l
    from _alertas_pedidos_parados() x left join alertas_envios e on e.chave = 'ped:' || x.venda_id || ':' || x.regra and e.resolvido_em is null
   where (v_niv in ('Admin', 'Desenvolvedor') or v_niv = any(x.niveis) or (coalesce(e.vezes, 0) >= (_alertas_cfg()->>'escalarApos')::int and v_niv = 'Admin'))
     and not coalesce(e.silenciado, false) and coalesce(e.adiado_ate, '-infinity') <= now();
  if v_niv in ('Admin', 'Desenvolvedor') then   -- falhas do sistema e vencimentos ainda sem resolver
    select coalesce(jsonb_agg(jsonb_build_object('chave', chave, 'titulo', titulo, 'texto', texto, 'vezes', vezes) order by ultimo_em desc), '[]'::jsonb) into v_s
      from alertas_envios where tipo = 'sistema' and resolvido_em is null and not silenciado;
  end if;
  return jsonb_build_object('ok', true, 'agora', now(), 'alertas', v_l, 'sistema', v_s);
end $$;

create or replace function public.api_alertas_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_reg jsonb := '{}'::jsonb; k text; v_min int; v_ven jsonb := '[]'::jsonb; e jsonb; v_rep int; v_esc int; v_sis int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  for k in select jsonb_object_keys(_alertas_padrao()) loop
    if p->'regras' ? k then
      v_min := _num(p->'regras'->k->>'min', (_alertas_padrao()->k->>'min')::numeric)::int;
      if v_min < 1 or v_min > 240 then return _falha('Os tempos precisam ficar entre 1 e 240 minutos.'); end if;
      v_reg := v_reg || jsonb_build_object(k, jsonb_build_object('ligado', coalesce((p->'regras'->k->>'ligado')::boolean, true), 'min', v_min));
    end if;
  end loop;
  v_rep := _num(p->>'repetirMin', 5)::int; v_esc := _num(p->>'escalarApos', 3)::int;
  v_sis := _num(p->>'sistemaRepetirMin', coalesce((select sistema_repetir_min from alertas_config where id), 30))::int;
  if v_rep < 1 or v_rep > 60 or v_esc < 1 or v_esc > 20 then return _falha('Repetição entre 1 e 60 min; escalada entre 1 e 20 avisos.'); end if;
  if v_sis < 10 or v_sis > 240 then return _falha('A repetição dos avisos do sistema precisa ficar entre 10 e 240 minutos.'); end if;
  for e in select value from jsonb_array_elements(coalesce(p->'vencimentos', '[]'::jsonb)) loop
    if coalesce(btrim(e->>'item'), '') = '' then continue; end if;
    if coalesce(e->>'vence', '') !~ '^\d{4}-\d{2}-\d{2}$' then return _falha('Data inválida em "' || left(e->>'item', 40) || '".'); end if;
    v_ven := v_ven || jsonb_build_object('item', left(btrim(e->>'item'), 60), 'vence', e->>'vence');
  end loop;
  if jsonb_array_length(v_ven) > 20 then return _falha('No máximo 20 vencimentos.'); end if;
  update alertas_config set regras = v_reg, repetir_min = v_rep, escalar_apos = v_esc, sistema_repetir_min = v_sis, vencimentos = v_ven,
         email_ativo = coalesce((p->>'emailAtivo')::boolean, email_ativo), atualizado_em = now(), atualizado_por = auth.uid() where id;
  perform _auditar('Alertas automáticos alterados', 'repetir ' || v_rep || ' min | sistema ' || v_sis || ' min | escalar após ' || v_esc || ' | ' || jsonb_array_length(v_ven) || ' vencimento(s)');
  return jsonb_build_object('ok', true, 'message', 'Alertas salvos.');
end $$;


-- ======================================================================
-- 15-arquivo-sem-perda.sql
-- ======================================================================
-- =====================================================================
-- 15 · ARQUIVAMENTO SEM PERDA (18/10/2026)
-- Conferência do que acontece quando vendas e caixas saem do Supabase para a planilha (abas Arquivo_*). Ajustes:
--  1) Pedido com CONVERSA de chat (qualquer estado), OCORRÊNCIA (qualquer estado) ou NOTA FISCAL não é mais arquivado:
--     a conversa e a ocorrência são apagadas/desligadas junto com a venda e não vão para a planilha. Esses pedidos ficam no sistema.
--  2) Caixa com BRINDE ou LIBERAÇÃO registrada não é mais arquivado (o banco recusava a remoção e o arquivamento de caixas parava
--     toda noite no mesmo caixa). Fica no sistema.
--  3) Pagamento online (Mercado Pago) guarda o NÚMERO do pedido antes do vínculo com a venda ser desfeito.
--  4) "Simular" passa a seguir exatamente as mesmas regras.
-- Aditivo: 1 coluna nova, 3 funções recriadas, 1 função renomeada + função de passagem. Nada é apagado.
-- =====================================================================

alter table public.pagamentos_online add column if not exists venda_numero int;

create or replace function public.api_arquivar_lote_vendas(p_dias integer, p_limite integer default 200, p_min_dias integer default 30)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_corte timestamptz := now() - (greatest(p_dias, greatest(p_min_dias,1))||' days')::interval; v_ids uuid[];
begin
  select array_agg(id) into v_ids from (
    select v.id from vendas v
    where v.data_hora < v_corte
      and (v.status = 'Cancelada' or (v.status_pagamento = 'Pago' and coalesce(v.status_pedido::text,'Entregue') in ('Entregue','Retirada','Servida')))
      and not exists (select 1 from ajustes_pos_venda a where a.venda_id = v.id)
      and not exists (select 1 from entregas_fechadas e where e.venda_id = v.id)
      and not exists (select 1 from reembolsos r where r.venda_id = v.id)
      and not (v.status <> 'Cancelada' and v.tipo::text = 'Entrega' and v.entregador_id is not null and v.fechamento_entrega_id is null)
      and not exists (select 1 from ocorrencias o where o.venda_id = v.id)
      and not exists (select 1 from chat_conversas c where c.venda_id = v.id)
      and not exists (select 1 from nfce_notas n where n.venda_id = v.id)
    order by v.data_hora limit p_limite) x;
  return jsonb_build_object('ok',true,
    'ids', coalesce(to_jsonb(v_ids),'[]'::jsonb),
    'vendas', (select coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) from vendas v where v.id = any(coalesce(v_ids,'{}'))),
    'itens', (select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from itens_venda i where i.venda_id = any(coalesce(v_ids,'{}'))),
    'pagamentos', (select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from pagamentos_venda p where p.venda_id = any(coalesce(v_ids,'{}'))));
end $$;

create or replace function public.api_arquivar_lote_caixa(p_dias integer, p_limite integer default 100, p_min_dias integer default 30)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_corte timestamptz := now() - (greatest(p_dias, greatest(p_min_dias,1))||' days')::interval; v_ids uuid[];
begin
  select array_agg(id) into v_ids from (
    select c.id from caixa_sessoes c
    where c.status = 'Fechado' and c.fechamento < v_corte
      and not exists (select 1 from vendas v where v.caixa_id = c.id)
      and not exists (select 1 from brindes b where b.caixa_id = c.id)
      and not exists (select 1 from caixa_liberacoes l where l.caixa_id = c.id)
    order by c.fechamento limit p_limite) x;
  return jsonb_build_object('ok',true,
    'ids', coalesce(to_jsonb(v_ids),'[]'::jsonb),
    'caixas', (select coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb) from caixa_sessoes c where c.id = any(coalesce(v_ids,'{}'))),
    'sangrias', (select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from sangrias s where s.caixa_id = any(coalesce(v_ids,'{}'))));
end $$;

create or replace function public.api_simular_arquivamento(p_dias integer default 90)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_corte timestamptz := now() - (greatest(coalesce(p_dias, 90), 30) || ' days')::interval; r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select jsonb_build_object('ok', true, 'dias', greatest(coalesce(p_dias, 90), 30),
    'vendasAntigas', count(*),
    'vendasArquivaveis', count(*) filter (where ok),
    'vendasBloqueadas', count(*) filter (where not ok),
    'bloqReembolso', count(*) filter (where tem_reemb),
    'maisAntiga', min(data_hora) filter (where ok), 'maisNova', max(data_hora) filter (where ok)) into r
  from (
    select v.data_hora,
      exists (select 1 from reembolsos x where x.venda_id = v.id) tem_reemb,
      ((v.status = 'Cancelada' or (v.status_pagamento = 'Pago' and coalesce(v.status_pedido::text,'Entregue') in ('Entregue','Retirada','Servida')))
        and not exists (select 1 from ajustes_pos_venda a where a.venda_id = v.id)
        and not exists (select 1 from entregas_fechadas e where e.venda_id = v.id)
        and not exists (select 1 from reembolsos x where x.venda_id = v.id)
        and not (v.status <> 'Cancelada' and v.tipo::text = 'Entrega' and v.entregador_id is not null and v.fechamento_entrega_id is null)
        and not exists (select 1 from ocorrencias o where o.venda_id = v.id)
        and not exists (select 1 from chat_conversas c where c.venda_id = v.id)
        and not exists (select 1 from nfce_notas n where n.venda_id = v.id)) ok
      from vendas v where v.data_hora < v_corte) t;
  return r || jsonb_build_object(
    'caixasArquivaveis', (select count(*) from caixa_sessoes c where c.status = 'Fechado' and c.fechamento < v_corte and not exists (select 1 from vendas v where v.caixa_id = c.id)
                            and not exists (select 1 from brindes b where b.caixa_id = c.id) and not exists (select 1 from caixa_liberacoes l where l.caixa_id = c.id)),
    'resumoGuardado', (select count(*) from vendas_resumo_arquivo),
    'historicoArquivadas', (select count(*) from arquivo_historico where tabela = 'vendas'),
    'filaAnonimizacao', (select count(*) from anonimizar_arquivo_fila where feito_em is null));
end $$;

-- função de passagem: guarda o número do pedido nos pagamentos online e depois chama a rotina original (renomeada)
do $$ begin   -- só renomeia na primeira vez (rodar de novo não dá erro)
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'api_arquivar_confirmar_vendas' and p.prosrc not like '%_arquivar_confirmar_vendas_base%') then
    alter function public.api_arquivar_confirmar_vendas(uuid[]) rename to _arquivar_confirmar_vendas_base;
  end if;
end $$;
create or replace function public.api_arquivar_confirmar_vendas(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  update pagamentos_online po set venda_numero = v.numero_pedido from vendas v where v.id = po.venda_id and po.venda_id = any(p_ids) and po.venda_numero is null;
  return _arquivar_confirmar_vendas_base(p_ids);
end $$;
revoke all on function public.api_arquivar_confirmar_vendas(uuid[]) from public, anon, authenticated;
grant execute on function public.api_arquivar_confirmar_vendas(uuid[]) to service_role;
revoke all on function public._arquivar_confirmar_vendas_base(uuid[]) from public, anon, authenticated;
grant execute on function public._arquivar_confirmar_vendas_base(uuid[]) to service_role;


-- ======================================================================
-- 16-planilha-limites.sql
-- ======================================================================
-- =====================================================================
-- 16 · LIMITES DA PLANILHA (18/10/2026)
-- A planilha principal guarda o arquivo (Arquivo_*) e o Google limita cada planilha a 10 milhões de células. Medidas:
--  • o arquivamento passa a registrar quantas células a planilha já reserva (sistema.planilha_celulas);
--  • aviso ao Admin (repetindo até resolver) quando passar de 80% (8 milhões) e quando o arquivamento falhar;
--  • nada é apagado do Supabase sem a planilha confirmar (lê de volta), então falta de espaço na planilha só PARA o arquivamento, não perde dados.
-- Aditivo: 2 funções novas e 1 agendamento. Pode rodar de novo sem erro.
-- =====================================================================
create or replace function public.api_planilha_uso_registrar(p_celulas bigint) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(p_celulas, 0) <= 0 then return; end if;
  insert into sistema (chave, valor, atualizado_em) values ('planilha_celulas', to_jsonb(p_celulas), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
end $$;
revoke all on function public.api_planilha_uso_registrar(bigint) from public, anon, authenticated;
grant execute on function public.api_planilha_uso_registrar(bigint) to service_role;

create or replace function public.alertas_planilha_cron() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare ativos text[] := '{}'; v_cel bigint; v_pct int; r record;
begin
  -- 1) planilha principal ficando cheia (limite do Google: 10 milhões de células)
  select (valor #>> '{}')::bigint into v_cel from sistema where chave = 'planilha_celulas';
  if v_cel is not null then
    v_pct := round(v_cel / 100000.0);
    if v_pct >= 80 then
      ativos := array_append(ativos, 'sis:planilha_cheia');
      perform _alertas_sistema_avisar('sis:planilha_cheia', 'Planilha principal ficando cheia (' || v_pct || '%)',
        'A planilha já reserva ' || v_cel || ' de 10.000.000 células (limite do Google). Quando chegar a 100% o arquivamento para, mas nada se perde. Solução: criar uma planilha nova para o arquivo antigo (peça ajuda antes de passar de 90%).');
    end if;
  end if;
  -- 2) o último arquivamento (automático ou de emergência) terminou com erro
  select a.data_hora, a.detalhes into r from auditoria a
   where a.acao ilike 'Arquivamento%' and a.data_hora > now() - interval '26 hours' order by a.data_hora desc limit 1;
  if r.data_hora is not null and r.detalhes ~ '"erro":"' then
    ativos := array_append(ativos, 'sis:arquivo_falha');
    perform _alertas_sistema_avisar('sis:arquivo_falha', 'Arquivamento para a planilha falhou',
      'O último arquivamento terminou com erro: ' || left(substring(r.detalhes from '"erro":"([^"]*)"'), 200) || '. Nada foi apagado do Supabase. Veja em Sistema → Backup e espaço.');
  end if;
  update alertas_envios set resolvido_em = now() where tipo = 'sistema' and resolvido_em is null and chave in ('sis:planilha_cheia', 'sis:arquivo_falha') and not (chave = any(ativos));
  return jsonb_build_object('ok', true, 'ativos', to_jsonb(ativos));
end $$;
revoke all on function public.alertas_planilha_cron() from public, anon, authenticated;
grant execute on function public.alertas_planilha_cron() to service_role;

select cron.schedule('alertas-planilha-hora', '20 * * * *', 'select public.alertas_planilha_cron()');


-- ======================================================================
-- 17-ajuste-precos-lote.sql
-- ======================================================================
-- =====================================================================
-- 17 · AJUSTE DE PREÇOS DOS PRODUTOS EM LOTE (18/10/2026)
-- Admin escolhe um percentual (-50% a +100%) e, se quiser, uma categoria; todos os preços dos produtos ativos dessa categoria são ajustados
-- de uma vez (arredondado em centavos). O custo não muda. Fica na auditoria. Aditivo: 1 função nova.
-- =====================================================================
create or replace function public.api_ajustar_precos_produtos_lote(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_pct numeric := _num(p->>'percentual', 0); v_cat text := nullif(btrim(coalesce(p->>'categoria', '')), ''); v_n int; v_prod int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_pct = 0 or v_pct < -50 or v_pct > 100 then return _falha('Informe um percentual entre -50 e 100 (diferente de zero).'); end if;
  with alvo as (
    select pp.id from produto_precos pp join produtos pr on pr.id = pp.produto_id left join categorias c on c.id = pr.categoria_id
     where pr.ativo and pp.preco > 0 and (v_cat is null or c.nome = v_cat)
  ), up as (
    update produto_precos x set preco = round(x.preco * (1 + v_pct / 100), 2) from alvo where x.id = alvo.id returning x.produto_id
  ) select count(*), count(distinct produto_id) into v_n, v_prod from up;
  perform _auditar('Preços ajustados em lote', v_pct || '% | ' || coalesce(v_cat, 'todas as categorias') || ' | ' || coalesce(v_prod, 0) || ' produto(s)');
  return jsonb_build_object('ok', true, 'message', coalesce(v_prod, 0) || ' produto(s) com preço ajustado em ' || v_pct || '%.', 'produtos', coalesce(v_prod, 0));
end $$;

revoke all on function public.api_ajustar_precos_produtos_lote(jsonb) from public;
grant execute on function public.api_ajustar_precos_produtos_lote(jsonb) to authenticated, service_role;


-- ======================================================================
-- 18-ajuda-assistente-3.sql
-- ======================================================================
-- 18 - Assistente: 7 verbetes novos (escala da equipe, equipe e pagamentos, alertas que repetem, histórico de vendas arquivado, rascunho/ajuste de preços, mudanças na edição de venda). Pode rodar de novo.
-- Desfazer: delete from public.ai_ajuda where slug in ('man-admin-136-margem-historico-precos','man-admin-137-compra-sugerida','man-admin-138-fechamento-rendimento-contrato','man-admin-132-troca-turno-ponto','man-admin-133-reserva-peso-mao-de-obra','man-admin-134-eventos-calendario-orcamento','man-admin-135-crescimento-do-banco','man-admin-125-alertas-repetem','man-admin-126-historico-arquivado','man-admin-127-rascunho-ajuste-precos','man-admin-128-editar-venda-diferenca','man-admin-129-equipe-pagamentos','man-admin-130-escala-equipe','man-admin-131-central-eventos');
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-125-alertas-repetem$t$,$t$Avisos do sistema que se repetem até resolver$t$,$t$alertas avisos notificação repetir repete aviso sistema caixa vencido backup planilha parou configurar avisos intervalo minutos som$t$,
$t$Administrador → Loja e equipe → Configurar avisos → "Alertas automáticos". Os avisos de problema do sistema (caixa aberto há muito tempo, backup parado, planilha sem salvar, vencimentos) repetem a cada 30 minutos até o problema ser resolvido. Você muda esse tempo em "Repetir avisos do sistema a cada (min)" (10 a 240).
O e-mail sai no máximo a cada 6 horas por problema, para não lotar a caixa; o aviso no celular e o som continuam repetindo. Aviso de pedido parado repete no tempo "Repetir a cada" até o pedido andar, ser adiado ou silenciado.$t$,
ARRAY['Admin'],true,'secao',125,$t$$t$),
($t$man-admin-126-historico-arquivado$t$,$t$Dados antigos na planilha: o que continua acessível$t$,$t$arquivo arquivado planilha histórico vendas antigas cliente pedidos antigos reimprimir relatório mês perdi sumiu antigo$t$,
$t$Vendas e caixas antigos são copiados para a planilha e só depois saem do sistema, quando a planilha confirma que recebeu tudo. Mesmo assim continuam acessíveis: o histórico e os pedidos do cliente (com valores e total gasto), os relatórios por mês, o histórico de caixa e o "Histórico de vendas" de qualquer dia antigo, com reimpressão do comprovante.
Se algo parecer faltar, abra Relatórios e escolha o mês; o sistema avisa o Admin, repetindo, quando a planilha passa de 80% do limite do Google.$t$,
ARRAY['Admin'],true,'secao',126,$t$$t$),
($t$man-admin-127-rascunho-ajuste-precos$t$,$t$Produto: rascunho automático e ajuste de preços em lote$t$,$t$rascunho produto novo continuar fechei sem querer perdi ajustar preços porcentagem aumentar preço reajuste lote categoria$t$,
$t$Administrador → Produtos. Se você fechar o "Novo produto" no meio, o rascunho fica salvo no aparelho: ao tocar em "+ Novo produto" o sistema pergunta se quer continuar de onde parou.
Para reajustar preços, toque em "% Ajustar preços", digite o percentual (8 sobe 8%, -5 baixa 5%), escolha a categoria (ou todas) e confirme. O custo não muda e a ação fica na auditoria.$t$,
ARRAY['Admin'],true,'secao',127,$t$$t$),
($t$man-admin-128-editar-venda-diferenca$t$,$t$Editar venda: diferença, forma de pagamento e fidelidade ao cancelar$t$,$t$editar venda diferença pagamento forma pagar a mais a menos cancelar venda fidelidade pontos selo desfazer$t$,
$t$Caixa → venda → Editar. Se o total mudar, o sistema pede a forma de pagamento da diferença (cobrar ou devolver) e registra no caixa. Ao cancelar uma venda, os pontos de fidelidade ganhos nela são desfeitos.$t$,
ARRAY['Admin','Operador'],true,'secao',128,$t$$t$),
($t$man-admin-129-equipe-pagamentos$t$,$t$Equipe e pagamentos: salários, adiantamentos, encargos e recibo$t$,$t$funcionario funcionarios salario pagar pagamento folha adiantamento vale diaria comissao decimo terceiro 13 ferias encargos fgts inss recibo equipe registrar despesa salarios$t$,
$t$Administrador → Loja e equipe → Equipe e pagamentos. "+ Novo funcionário": nome, cargo, salário, dia do pagamento e % de encargos (o que o contador informar). Para pagar toque em "Pagar" na linha da pessoa: escolha o tipo (Salário, Adiantamento, Vale, Hora extra/diária, Comissão, 13º, Férias, Outro), o valor e se saiu do caixa ou fora dele. O pagamento vira despesa na categoria Salários e entra no lucro do mês.
Se tiver encargos e o tipo for Salário, dá para lançá-los como conta a pagar (vence dia 20 do mês seguinte). Em "Pagamentos do mês": "Recibo" imprime ou salva em PDF (com valor por extenso) e "Cancelar" (motivo + senha do Administrador) cancela o pagamento e a despesa. Passou do dia do pagamento e o mês não está quitado: o sistema avisa o Administrador uma vez por dia até você pagar. O custo mensal mostrado (com encargos e 13º/férias) é só estimativa.$t$,
ARRAY['Admin'],true,'secao',129,$t$$t$),
($t$man-admin-130-escala-equipe$t$,$t$Escala da equipe: turnos, folgas, padrão semanal e Minha escala$t$,$t$escala escalar turno horario folga ferias falta atestado quem trabalha semana padrao copiar semana imprimir whatsapp minha escala funcionario horas 44$t$,
$t$Administrador → Loja e equipe → Escala da equipe. "Importar acessos" transforma quem já tem login em funcionário. Mude de semana com as setas; "Por dia" (melhor no celular) ou "Por pessoa" (grade com total de horas e aviso acima de 44h). Toque em "+" para escalar: tipo (Trabalho, Folga, Férias, Falta, Atestado), entrada e saída (saída depois da meia-noite vale o dia seguinte) e função; toque num horário para mudar ou remover. O sistema barra turnos sobrepostos e pergunta antes de escalar quem está de folga, férias ou atestado.
Para ganhar tempo: botão "Padrão" da pessoa (horário de cada dia, em branco = folga) e "Aplicar padrão semanal" (várias semanas, só dias vazios); ou "Copiar semana anterior". "Imprimir" gera a folha e "WhatsApp" manda o texto da semana. Cada pessoa vê em Início o card "Minha escala" e o botão "Ver escala da equipe"; falta e atestado só o Admin vê. Para a pessoa ver a própria escala, o funcionário dela precisa estar ligado ao acesso (Importar acessos ou escolher o acesso na ficha em Equipe e pagamentos).$t$,
ARRAY['Admin'],true,'secao',130,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();

-- 22b - Assistente: verbete da Central de Eventos
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-131-central-eventos$t$,$t$Central de Eventos: festas, custos, recebimentos e resultado$t$,$t$evento eventos festa casamento aniversario contratante orcamento sinal receber recebimento custo resultado lucro duplicar evento whatsapp contratante imprimir resumo cancelar lancamento$t$,
$t$Administrador → Vendas e cardápio → Eventos. A lista separa Próximos (orçamento/confirmado), Em andamento e Concluídos e cancelados; cada cartão mostra A receber, Recebido e Resultado (verde = lucro, vermelho = prejuízo). Evento que já passou e ainda tem saldo fica com aviso vermelho. "+ Novo evento" abre os Dados; depois de salvar, as abas Custos e Recebimentos liberam.
Aba Custos: "+ Custo". Aba Recebimentos: "+ Recebimento" (não passa do que falta receber). Resultado = valor contratado − custos. Para corrigir um lançamento, toque em "Cancelar" ao lado dele e informe o motivo (pode pedir a senha de administrador): nada é apagado, só sai dos totais. Na aba Dados: "WhatsApp do contratante", "Imprimir resumo", "Duplicar evento" (novo Orçamento sem custos e recebimentos) e "Cancelar evento".$t$,
ARRAY['Admin'],true,'secao',131,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();

-- 25b - Assistente: verbetes de troca de turno/ponto, reserva e peso da mão de obra, extras de Eventos e histórico do banco
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-132-troca-turno-ponto$t$,$t$Escala: troca de turno, aviso no celular e ponto com horas extras$t$,$t$troca de turno trocar turno escala aviso celular notificação ponto bater ponto entrada saída horas extras relatório de ponto ajustar ponto esqueceu de bater$t$,
$t$Troca de turno: o funcionário, em Minha escala, toca em "Pedir troca" no turno e escolhe o colega. O colega aceita ou recusa; se aceitar, o dono aprova em Equipe → Escala (lista de trocas). A escala só muda depois da aprovação.
Aviso: em Equipe → Escala, o botão de avisar manda notificação no celular de quem trabalha (a pessoa precisa ter ativado as notificações). Salvar ou alterar um turno também avisa a pessoa.
Ponto: aba Ponto, o funcionário bate entrada e saída. O dono vê o relatório do mês com horas trabalhadas e extras e pode ajustar um registro esquecido. Se ficar sem saída, o sistema avisa no fim do dia.$t$,
ARRAY['Admin'],true,'secao',132,$t$$t$),
($t$man-admin-133-reserva-peso-mao-de-obra$t$,$t$Equipe: reserva de 13º e férias e peso da mão de obra nas vendas$t$,$t$reserva 13 salario décimo terceiro férias provisão peso mão de obra folha faturamento porcentagem equipe custo$t$,
$t$Em Administrador → Loja e equipe → Equipe e pagamentos há dois cartões. Reserva de 13º e férias: estimativa mensal do quanto separar (não lança nada no financeiro, serve para você guardar o dinheiro). Peso da mão de obra: compara folha mais encargos com o faturamento das vendas confirmadas dos últimos 6 meses e mostra a porcentagem.$t$,
ARRAY['Admin'],true,'secao',133,$t$$t$),
($t$man-admin-134-eventos-calendario-orcamento$t$,$t$Eventos: calendário, orçamento em PDF e a receber no financeiro$t$,$t$evento calendário mês orçamento pdf imprimir contratante eventos a receber contas a pagar saldo evento passado aviso$t$,
$t$Em Eventos, o botão Calendário mostra o mês com os eventos; toque no nome para abrir. Dentro do evento, "Orçamento (PDF)" pede o que está incluso e a forma de pagamento e abre a impressão/PDF para enviar ao contratante. Em Contas a pagar aparece o cartão "Eventos a receber" (só leitura): o dinheiro só entra no financeiro quando o recebimento é lançado no evento, e os custos ficam no evento para não contar em dobro. Evento que já passou com saldo gera aviso no celular e e-mail do dono.$t$,
ARRAY['Admin'],true,'secao',134,$t$$t$),
($t$man-admin-135-crescimento-do-banco$t$,$t$Crescimento do banco e previsão de espaço$t$,$t$crescimento banco espaço histórico previsão quando enche 95% mb por mês supabase uso$t$,
$t$Em Sistema → Backup e espaço, o bloco "Crescimento do banco" mostra o tamanho no fim de cada mês, quanto o banco cresce por dia e em quanto tempo deve chegar a 95% do plano. O sistema registra o tamanho todo dia; nos primeiros dias aparece "reunindo dados". Aos 70% e 85% o sistema avisa por notificação e e-mail.$t$,
ARRAY['Admin'],true,'secao',135,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();

-- 26b - Assistente: verbetes de margem, histórico de preços, compra sugerida, fechamento, rendimento e contrato
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-136-margem-historico-precos$t$,$t$Margem baixa e histórico de preços$t$,$t$margem baixa margem mínima margem por categoria ignorar produto preço sugerido produto histórico de preços reajuste quem mudou preço antigo aviso margem refrigerante bebida$t$,
$t$Em Administrador → Produtos há dois botões. "Margem baixa" mostra os produtos cuja margem (preço menos custo, dividido pelo preço) está abaixo do mínimo (começa em 50%) e o preço que leva cada um de volta ao mínimo. Categorias que têm margem naturalmente menor, como Bebidas, podem ter um mínimo próprio ("Mínimo por categoria"), e um produto pode ser ignorado ("Ignorar este produto"; dá para desfazer em "Ignorados"). O celular do dono só recebe aviso quando entra um produto novo abaixo do mínimo, sem repetir. "Histórico de preços" lista cada preço que mudou (edição, ajuste em lote), de quanto para quanto, quem mudou e quando; dá para buscar por produto. Para mudar um preço, edite o produto ou use "% Ajustar preços".$t$,
ARRAY['Admin'],true,'secao',136,$t$$t$),
($t$man-admin-137-compra-sugerida$t$,$t$Compra sugerida (estoque no mínimo)$t$,$t$compra sugerida lista de compra estoque mínimo ingredientes acabando fornecedor whatsapp pedido ao fornecedor$t$,
$t$Em Estoque, o botão "Compra sugerida" lista os ingredientes que chegaram no estoque mínimo ou abaixo, com a quantidade para voltar ao dobro do mínimo e o custo estimado. Eles vêm separados pelo fornecedor da última compra recebida. Cada grupo tem "Mandar no WhatsApp" (mensagem pronta) e "Copiar lista".$t$,
ARRAY['Admin','Operador'],true,'secao',137,$t$$t$),
($t$man-admin-138-fechamento-rendimento-contrato$t$,$t$Fechamento do mês, rendimento por hora e contrato do evento$t$,$t$fechamento do mês pdf contador relatório mensal rendimento por hora evento horas equipe contrato do evento contrato pdf cláusulas cancelamento sinal$t$,
$t$Relatórios → "Fechamento do mês (PDF)" usa o mês escolhido no DRE e gera uma folha com vendas, custos, despesas, eventos, folha paga e resultado, para guardar ou mandar ao contador. Eventos → "Rendimento por hora dos eventos" mostra quanto cada evento rendeu por hora de equipe (horas do Ponto no dia, ou informadas por você) e compara com as vendas por hora de um dia normal. Dentro do evento, "Contrato (PDF)" gera um contrato simples com cláusulas editáveis (sinal, cancelamento, remarcação); para valores altos, vale conferir com um advogado. Contas a pagar: o dono também recebe aviso no celular na véspera, no dia e quando vencidas.$t$,
ARRAY['Admin'],true,'secao',138,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();


-- ======================================================================
-- 19-visibilidade-lote.sql
-- ======================================================================
-- =====================================================================
-- 19 · MOSTRAR/ESCONDER VÁRIOS PRODUTOS DO CARDÁPIO DE UMA VEZ (18/10/2026)
-- Admin marca vários produtos e mostra ou esconde todos juntos (mesmo efeito do "Visível no cardápio" de cada produto). Fica na auditoria. Aditivo: 1 função nova.
-- =====================================================================
create or replace function public.api_visibilidade_lote_produtos(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_ids uuid[]; v_ativo boolean := coalesce(p->>'ativo', '') <> 'false'; v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(array_agg(_uuid(x)), '{}') into v_ids from jsonb_array_elements_text(coalesce(p->'ids', '[]'::jsonb)) x;
  if coalesce(array_length(v_ids, 1), 0) = 0 then return _falha('Marque pelo menos um produto.'); end if;
  if array_length(v_ids, 1) > 500 then return _falha('Marque no máximo 500 produtos por vez.'); end if;
  update produtos set ativo = v_ativo where id = any(v_ids) and ativo is distinct from v_ativo;
  get diagnostics v_n = row_count;
  perform _auditar('Cardápio em lote: ' || case when v_ativo then 'produtos mostrados' else 'produtos escondidos' end, v_n || ' produto(s) alterado(s)');
  return jsonb_build_object('ok', true, 'message', v_n || ' produto(s) ' || case when v_ativo then 'agora aparecem' else 'foram escondidos' end || ' no cardápio.', 'alterados', v_n);
end $$;

revoke all on function public.api_visibilidade_lote_produtos(jsonb) from public;
grant execute on function public.api_visibilidade_lote_produtos(jsonb) to authenticated, service_role;


-- ======================================================================
-- 20-equipe-pagamentos.sql
-- ======================================================================
-- =====================================================================
-- 20 · EQUIPE E PAGAMENTOS (folha simples) (18/10/2026)
-- Ficha do funcionário (nome, cargo, salário, dia de pagamento, % de encargos que o contador informar, provisão de 13º/férias),
-- botão "Pagar" que lança a despesa em "Salários" (e, se quiser, os encargos como conta a pagar), histórico por mês, cancelamento
-- (com senha do Admin) e aviso ao Admin quando o pagamento do mês passou do dia e ainda não foi registrado.
-- Só o Admin vê e mexe. Aditivo: 2 tabelas, 5 funções, 1 agendamento. Pode rodar de novo sem erro.
-- =====================================================================
create table if not exists public.funcionarios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cargo text,
  telefone text,
  admissao date,
  salario numeric(10,2) not null default 0 check (salario >= 0),
  dia_pagamento int not null default 5 check (dia_pagamento between 1 and 31),
  encargos_pct numeric(5,2) not null default 0 check (encargos_pct between 0 and 100),
  provisao boolean not null default false,
  ativo boolean not null default true,
  desligado_em date,
  observacao text,
  criado_em timestamptz not null default now()
);
create table if not exists public.funcionario_pagamentos (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  competencia text not null check (competencia ~ '^\d{4}-\d{2}$'),
  tipo text not null default 'Salário',
  valor numeric(10,2) not null check (valor > 0),
  encargos numeric(10,2) not null default 0,
  despesa_id uuid,
  despesa_encargos_id uuid,
  pago_em timestamptz not null default now(),
  observacao text,
  status text not null default 'Paga',
  motivo_cancelamento text,
  criado_em timestamptz not null default now()
);
create index if not exists funcionario_pagamentos_comp_idx on public.funcionario_pagamentos (competencia, funcionario_id);

alter table public.funcionarios enable row level security;
alter table public.funcionario_pagamentos enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'funcionarios' and policyname = 'funcionarios_ler_admin') then
    create policy funcionarios_ler_admin on public.funcionarios for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'funcionario_pagamentos' and policyname = 'funcionario_pagamentos_ler_admin') then
    create policy funcionario_pagamentos_ler_admin on public.funcionario_pagamentos for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
end $$;
revoke all on public.funcionarios, public.funcionario_pagamentos from anon, authenticated;
grant select on public.funcionarios, public.funcionario_pagamentos to authenticated;
grant all on public.funcionarios, public.funcionario_pagamentos to service_role;

-- 1) Tela: funcionários + pagamentos do mês + resumo
create or replace function public.api_equipe_folha(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_mes text := coalesce(nullif(p->>'mes', ''), to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')); v_f jsonb; v_p jsonb; v_prev numeric; v_pago numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_mes !~ '^\d{4}-\d{2}$' then return _falha('Mês inválido.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'nome', f.nome, 'cargo', f.cargo, 'telefone', f.telefone, 'admissao', f.admissao, 'salario', f.salario, 'diaPagamento', f.dia_pagamento,
      'encargosPct', f.encargos_pct, 'provisao', f.provisao, 'ativo', f.ativo, 'desligadoEm', f.desligado_em, 'observacao', f.observacao,
      'custoMensal', round(f.salario * (1 + f.encargos_pct / 100.0) + case when f.provisao then f.salario / 12.0 * (1 + 4.0 / 3) else 0 end, 2),
      'pagoSalario', coalesce(s.pago, 0), 'saldo', greatest(round(f.salario - coalesce(s.pago, 0), 2), 0)
    ) order by f.ativo desc, f.nome), '[]'::jsonb) into v_f
    from funcionarios f
    left join lateral (select sum(valor) pago from funcionario_pagamentos x where x.funcionario_id = f.id and x.competencia = v_mes and x.status = 'Paga' and x.tipo in ('Salário', 'Adiantamento', 'Vale')) s on true;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'funcionarioId', x.funcionario_id, 'nome', f.nome, 'cargo', f.cargo, 'competencia', x.competencia, 'tipo', x.tipo,
      'valor', x.valor, 'encargos', x.encargos, 'pagoEm', x.pago_em, 'observacao', x.observacao, 'status', x.status, 'motivo', x.motivo_cancelamento) order by x.pago_em desc), '[]'::jsonb) into v_p
    from funcionario_pagamentos x join funcionarios f on f.id = x.funcionario_id where x.competencia = v_mes;
  select coalesce(sum(salario), 0) into v_prev from funcionarios where ativo;
  select coalesce(sum(valor), 0) into v_pago from funcionario_pagamentos where competencia = v_mes and status = 'Paga';
  return jsonb_build_object('ok', true, 'mes', v_mes, 'funcionarios', v_f, 'pagamentos', v_p, 'previsto', v_prev, 'pago', v_pago);
end $$;

-- 2) Criar / editar funcionário
create or replace function public.api_salvar_funcionario(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_nome text := btrim(coalesce(p->>'nome', '')); v_sal numeric := round(_num(p->>'salario'), 2);
        v_dia int := coalesce(nullif(p->>'diaPagamento', '')::int, 5); v_enc numeric := _num(p->>'encargosPct', 0); v_ativo boolean := coalesce((p->>'ativo')::boolean, true);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do funcionário.'); end if;
  if v_sal < 0 or v_sal > 999999 then return _falha('Salário inválido.'); end if;
  if v_dia < 1 or v_dia > 31 then return _falha('O dia de pagamento precisa ficar entre 1 e 31.'); end if;
  if v_enc < 0 or v_enc > 100 then return _falha('Encargos entre 0 e 100%.'); end if;
  if v_id is null then
    insert into funcionarios (nome, cargo, telefone, admissao, salario, dia_pagamento, encargos_pct, provisao, ativo, observacao)
    values (left(v_nome, 80), left(nullif(btrim(coalesce(p->>'cargo', '')), ''), 60), left(nullif(btrim(coalesce(p->>'telefone', '')), ''), 30), nullif(p->>'admissao', '')::date,
            v_sal, v_dia, v_enc, coalesce((p->>'provisao')::boolean, false), true, left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 300));
    perform _auditar('Funcionário cadastrado', left(v_nome, 80) || ' | salário R$ ' || _dinheiro(v_sal));
    return jsonb_build_object('ok', true, 'message', 'Funcionário cadastrado.');
  end if;
  update funcionarios set nome = left(v_nome, 80), cargo = left(nullif(btrim(coalesce(p->>'cargo', '')), ''), 60), telefone = left(nullif(btrim(coalesce(p->>'telefone', '')), ''), 30),
         admissao = nullif(p->>'admissao', '')::date, salario = v_sal, dia_pagamento = v_dia, encargos_pct = v_enc, provisao = coalesce((p->>'provisao')::boolean, false),
         ativo = v_ativo, desligado_em = case when v_ativo then null else coalesce(nullif(p->>'desligadoEm', '')::date, current_date) end,
         observacao = left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 300)
   where id = v_id;
  if not found then return _falha('Funcionário não encontrado.'); end if;
  perform _auditar('Funcionário alterado', left(v_nome, 80) || ' | salário R$ ' || _dinheiro(v_sal) || case when v_ativo then '' else ' | desligado' end);
  return jsonb_build_object('ok', true, 'message', 'Funcionário salvo.');
end $$;

-- 3) Pagar: lança a despesa em "Salários" (e os encargos como conta a pagar, se pedido)
create or replace function public.api_pagar_funcionario(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare f funcionarios%rowtype; v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_tipo text := coalesce(nullif(p->>'tipo', ''), 'Salário');
        v_comp text := coalesce(nullif(p->>'competencia', ''), to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')); v_valor numeric := round(_num(p->>'valor'), 2);
        v_caixa boolean := coalesce(p->>'saiuDoCaixa', '') = 'true'; v_pago numeric; v_desp uuid; v_enc numeric := 0; v_desp_enc uuid; v_mm text; v_venc date; v_obs text := left(coalesce(p->>'observacao', ''), 300);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  select * into f from funcionarios where id = _uuid(p->>'funcionarioId') for update;
  if not found then return _falha('Funcionário não encontrado.'); end if;
  if v_tipo <> all (array['Salário', 'Adiantamento', 'Vale', 'Hora extra / diária', 'Comissão', '13º salário', 'Férias', 'Outro']) then return _falha('Tipo de pagamento inválido.'); end if;
  if v_comp !~ '^\d{4}-\d{2}$' then return _falha('Mês inválido.'); end if;
  if v_valor <= 0 then return _falha('Informe um valor maior que zero.'); end if;
  if v_valor > 999999 then return _falha('Valor alto demais.'); end if;
  if v_caixa and not exists (select 1 from caixa_sessoes where status = 'Aberto') then return _falha('Abra o caixa para registrar um pagamento que sai do caixa.'); end if;
  select coalesce(sum(valor), 0) into v_pago from funcionario_pagamentos where funcionario_id = f.id and competencia = v_comp and status = 'Paga' and tipo in ('Salário', 'Adiantamento', 'Vale');
  if v_tipo in ('Salário', 'Adiantamento', 'Vale') and f.salario > 0 and v_pago + v_valor > f.salario + 0.009 and coalesce(p->>'confirmado', '') <> 'true' then
    return jsonb_build_object('ok', false, 'confirmar', true, 'message', 'Em ' || right(v_comp, 2) || '/' || left(v_comp, 4) || ' já foram pagos R$ ' || _dinheiro(v_pago) || ' de R$ ' || _dinheiro(f.salario) || '. Com este pagamento passa do salário. Confirma?');
  end if;
  v_mm := right(v_comp, 2) || '/' || left(v_comp, 4);
  insert into despesas (data_hora, descricao, valor, observacao, status, categoria, situacao, competencia, saiu_do_caixa)
  values (now(), v_tipo || ' — ' || f.nome || ' (' || v_mm || ')', v_valor, v_obs, 'Paga', 'Salários', 'Paga', v_comp, v_caixa) returning id into v_desp;
  if coalesce(p->>'lancarEncargos', '') = 'true' and f.encargos_pct > 0 and v_tipo in ('Salário', '13º salário', 'Férias') then
    v_enc := round(v_valor * f.encargos_pct / 100.0, 2);
    v_venc := (date_trunc('month', to_date(v_comp || '-01', 'YYYY-MM-DD')) + interval '1 month' + interval '19 days')::date;   -- dia 20 do mês seguinte (ajuste na conta a pagar se for outro)
    insert into despesas (data_hora, descricao, valor, observacao, status, categoria, vencimento, situacao, competencia, saiu_do_caixa)
    values (_meio_dia(v_venc), 'Encargos — ' || f.nome || ' (' || v_mm || ')', v_enc, 'Encargos de ' || f.encargos_pct || '% sobre ' || v_tipo, 'A pagar', 'Impostos', v_venc, 'A pagar', v_comp, true) returning id into v_desp_enc;
  end if;
  insert into funcionario_pagamentos (funcionario_id, competencia, tipo, valor, encargos, despesa_id, despesa_encargos_id, observacao)
  values (f.id, v_comp, v_tipo, v_valor, v_enc, v_desp, v_desp_enc, nullif(v_obs, ''));
  perform _auditar('Pagamento de funcionário', v_tipo || ' — ' || f.nome || ' (' || v_mm || ') = R$ ' || _dinheiro(v_valor) || case when v_enc > 0 then ' | encargos R$ ' || _dinheiro(v_enc) || ' a pagar' else '' end || ' | ' || case when v_caixa then 'saiu do caixa' else 'fora do caixa' end);
  v_r := jsonb_build_object('ok', true, 'message', 'Pagamento registrado: R$ ' || _dinheiro(v_valor) || ' para ' || f.nome || case when v_enc > 0 then ' (encargos de R$ ' || _dinheiro(v_enc) || ' ficaram em Contas a pagar)' else '' end || '.');
  if v_req is not null then perform _idem_gravar(v_req, 'pagarFuncionario', v_r); end if;
  return v_r;
end $$;

-- 4) Cancelar um pagamento (pede a senha do Admin; cancela também a despesa e, se ainda não paga, a conta de encargos)
create or replace function public.api_cancelar_pagamento_funcionario(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare x funcionario_pagamentos%rowtype; v_motivo text := btrim(coalesce(p->>'motivo', '')); v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  select * into x from funcionario_pagamentos where id = _uuid(p->>'id') for update;
  if not found then return _falha('Pagamento não encontrado.'); end if;
  if x.status = 'Cancelada' then return _falha('Esse pagamento já está cancelado.'); end if;
  update funcionario_pagamentos set status = 'Cancelada', motivo_cancelamento = v_motivo where id = x.id;
  update despesas set status = 'Cancelada', motivo_cancelamento = v_motivo where id = x.despesa_id and status <> 'Cancelada';
  update despesas set status = 'Cancelada', motivo_cancelamento = v_motivo where id = x.despesa_encargos_id and status = 'A pagar';
  perform _auditar('Pagamento de funcionário cancelado', x.tipo || ' R$ ' || _dinheiro(x.valor) || ' (' || x.competencia || ') | ' || v_motivo);
  return jsonb_build_object('ok', true, 'message', 'Pagamento cancelado.' || case when x.despesa_encargos_id is not null and exists (select 1 from despesas where id = x.despesa_encargos_id and status = 'Paga') then ' Os encargos já estavam pagos: cancele-os à parte em Contas a pagar e despesas, se for o caso.' else '' end);
end $$;

-- 5) Aviso diário: pagamento do mês passou do dia combinado e ainda não foi registrado (repete 1x por dia até pagar)
create or replace function public.equipe_pendencias_cron() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare ativos text[] := '{}'; r record; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_comp text := to_char((now() at time zone 'America/Sao_Paulo'), 'YYYY-MM'); v_pago numeric; v_chave text;
begin
  for r in select * from funcionarios where ativo and salario > 0 and (admissao is null or admissao <= v_hoje)
             and least(dia_pagamento, extract(day from (date_trunc('month', v_hoje) + interval '1 month - 1 day'))::int) <= extract(day from v_hoje)::int loop
    select coalesce(sum(valor), 0) into v_pago from funcionario_pagamentos where funcionario_id = r.id and competencia = v_comp and status = 'Paga' and tipo in ('Salário', 'Adiantamento', 'Vale');
    if v_pago + 0.009 < r.salario then
      v_chave := 'sis:venc:func:' || r.id || ':' || v_comp;
      ativos := array_append(ativos, v_chave);
      perform _alertas_sistema_avisar(v_chave, 'Pagamento pendente: ' || r.nome,
        'O pagamento de ' || r.nome || ' (dia ' || r.dia_pagamento || ') ainda não foi registrado neste mês. Faltam R$ ' || _dinheiro(r.salario - v_pago) || '. Administrador → Loja e equipe → Equipe e pagamentos → Pagar.');
    end if;
  end loop;
  update alertas_envios set resolvido_em = now() where tipo = 'sistema' and resolvido_em is null and chave like 'sis:venc:func:%' and not (chave = any(ativos));
  return jsonb_build_object('ok', true, 'pendentes', to_jsonb(ativos));
end $$;
revoke all on function public.equipe_pendencias_cron() from public, anon, authenticated;
grant execute on function public.equipe_pendencias_cron() to service_role;

do $$ declare f text; begin
  foreach f in array array['api_equipe_folha(jsonb)', 'api_salvar_funcionario(jsonb)', 'api_pagar_funcionario(jsonb)', 'api_cancelar_pagamento_funcionario(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
end $$;

select cron.schedule('equipe-pendencias-dia', '30 12 * * *', 'select public.equipe_pendencias_cron()');


-- ======================================================================
-- 21-escala.sql
-- ======================================================================
-- =====================================================================
-- 21 · ESCALA DE TRABALHO DA EQUIPE (18/10/2026)
-- Escala semanal de todos os funcionários: turnos (trabalho, folga, férias, falta, atestado), padrão semanal por pessoa, copiar semana,
-- aplicar o padrão em várias semanas, total de horas por semana e "Minha escala" para cada pessoa ver o seu horário.
-- Cada funcionário pode ser ligado ao seu acesso (login). O Admin importa os acessos já existentes com um botão.
-- Falta e atestado só o Admin vê (os demais veem "Ausente"). Turno removido fica guardado como cancelado (histórico).
-- Aditivo: 2 tabelas, 1 coluna, 9 funções (2 recriadas). Pode rodar de novo sem erro. Rode DEPOIS do 20.
-- =====================================================================
alter table public.funcionarios add column if not exists usuario_id uuid;
create unique index if not exists funcionarios_usuario_uq on public.funcionarios (usuario_id) where usuario_id is not null;

create table if not exists public.escala_turnos (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  data date not null,
  tipo text not null default 'Trabalho' check (tipo in ('Trabalho', 'Folga', 'Férias', 'Falta', 'Atestado')),
  inicio time,
  fim time,
  funcao text,
  observacao text,
  cancelado boolean not null default false,
  criado_em timestamptz not null default now(),
  check (tipo <> 'Trabalho' or (inicio is not null and fim is not null and inicio <> fim))
);
create index if not exists escala_turnos_data_idx on public.escala_turnos (data, funcionario_id);
create table if not exists public.escala_padrao (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  dia_semana int not null check (dia_semana between 0 and 6),
  tipo text not null default 'Trabalho' check (tipo in ('Trabalho', 'Folga')),
  inicio time,
  fim time,
  funcao text,
  unique (funcionario_id, dia_semana),
  check (tipo = 'Folga' or (inicio is not null and fim is not null and inicio <> fim))
);
alter table public.escala_turnos enable row level security;
alter table public.escala_padrao enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'escala_turnos' and policyname = 'escala_turnos_ler_admin') then
    create policy escala_turnos_ler_admin on public.escala_turnos for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'escala_padrao' and policyname = 'escala_padrao_ler_admin') then
    create policy escala_padrao_ler_admin on public.escala_padrao for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
end $$;
revoke all on public.escala_turnos, public.escala_padrao from anon, authenticated;
grant select on public.escala_turnos, public.escala_padrao to authenticated;
grant all on public.escala_turnos, public.escala_padrao to service_role;

-- funções do 20 recriadas com a ligação ao acesso (login)
create or replace function public.api_equipe_folha(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_mes text := coalesce(nullif(p->>'mes', ''), to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')); v_f jsonb; v_p jsonb; v_prev numeric; v_pago numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_mes !~ '^\d{4}-\d{2}$' then return _falha('Mês inválido.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'usuarioId', f.usuario_id, 'nome', f.nome, 'cargo', f.cargo, 'telefone', f.telefone, 'admissao', f.admissao, 'salario', f.salario, 'diaPagamento', f.dia_pagamento,
      'encargosPct', f.encargos_pct, 'provisao', f.provisao, 'ativo', f.ativo, 'desligadoEm', f.desligado_em, 'observacao', f.observacao,
      'custoMensal', round(f.salario * (1 + f.encargos_pct / 100.0) + case when f.provisao then f.salario / 12.0 * (1 + 4.0 / 3) else 0 end, 2),
      'pagoSalario', coalesce(s.pago, 0), 'saldo', greatest(round(f.salario - coalesce(s.pago, 0), 2), 0)
    ) order by f.ativo desc, f.nome), '[]'::jsonb) into v_f
    from funcionarios f
    left join lateral (select sum(valor) pago from funcionario_pagamentos x where x.funcionario_id = f.id and x.competencia = v_mes and x.status = 'Paga' and x.tipo in ('Salário', 'Adiantamento', 'Vale')) s on true;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'funcionarioId', x.funcionario_id, 'nome', f.nome, 'cargo', f.cargo, 'competencia', x.competencia, 'tipo', x.tipo,
      'valor', x.valor, 'encargos', x.encargos, 'pagoEm', x.pago_em, 'observacao', x.observacao, 'status', x.status, 'motivo', x.motivo_cancelamento) order by x.pago_em desc), '[]'::jsonb) into v_p
    from funcionario_pagamentos x join funcionarios f on f.id = x.funcionario_id where x.competencia = v_mes;
  select coalesce(sum(salario), 0) into v_prev from funcionarios where ativo;
  select coalesce(sum(valor), 0) into v_pago from funcionario_pagamentos where competencia = v_mes and status = 'Paga';
  return jsonb_build_object('ok', true, 'mes', v_mes, 'funcionarios', v_f, 'pagamentos', v_p, 'previsto', v_prev, 'pago', v_pago);
end $$;

create or replace function public.api_salvar_funcionario(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_nome text := btrim(coalesce(p->>'nome', '')); v_sal numeric := round(_num(p->>'salario'), 2);
        v_dia int := coalesce(nullif(p->>'diaPagamento', '')::int, 5); v_enc numeric := _num(p->>'encargosPct', 0); v_ativo boolean := coalesce((p->>'ativo')::boolean, true); v_usr uuid := nullif(p->>'usuarioId', '')::uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do funcionário.'); end if;
  if v_sal < 0 or v_sal > 999999 then return _falha('Salário inválido.'); end if;
  if v_dia < 1 or v_dia > 31 then return _falha('O dia de pagamento precisa ficar entre 1 e 31.'); end if;
  if v_enc < 0 or v_enc > 100 then return _falha('Encargos entre 0 e 100%.'); end if;
  if v_usr is not null and exists (select 1 from funcionarios where usuario_id = v_usr and id is distinct from v_id) then return _falha('Esse acesso já está ligado a outro funcionário.'); end if;
  if v_id is null then
    insert into funcionarios (nome, cargo, telefone, admissao, salario, dia_pagamento, encargos_pct, provisao, ativo, observacao, usuario_id)
    values (left(v_nome, 80), left(nullif(btrim(coalesce(p->>'cargo', '')), ''), 60), left(nullif(btrim(coalesce(p->>'telefone', '')), ''), 30), nullif(p->>'admissao', '')::date,
            v_sal, v_dia, v_enc, coalesce((p->>'provisao')::boolean, false), true, left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 300), v_usr);
    perform _auditar('Funcionário cadastrado', left(v_nome, 80) || ' | salário R$ ' || _dinheiro(v_sal));
    return jsonb_build_object('ok', true, 'message', 'Funcionário cadastrado.');
  end if;
  update funcionarios set nome = left(v_nome, 80), cargo = left(nullif(btrim(coalesce(p->>'cargo', '')), ''), 60), telefone = left(nullif(btrim(coalesce(p->>'telefone', '')), ''), 30),
         admissao = nullif(p->>'admissao', '')::date, salario = v_sal, dia_pagamento = v_dia, encargos_pct = v_enc, provisao = coalesce((p->>'provisao')::boolean, false),
         ativo = v_ativo, desligado_em = case when v_ativo then null else coalesce(nullif(p->>'desligadoEm', '')::date, current_date) end,
         observacao = left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 300), usuario_id = v_usr
   where id = v_id;
  if not found then return _falha('Funcionário não encontrado.'); end if;
  perform _auditar('Funcionário alterado', left(v_nome, 80) || ' | salário R$ ' || _dinheiro(v_sal) || case when v_ativo then '' else ' | desligado' end);
  return jsonb_build_object('ok', true, 'message', 'Funcionário salvo.');
end $$;

-- Segunda-feira da semana de uma data
create or replace function public._escala_segunda(d date) returns date language sql immutable as $$ select d - ((extract(isodow from d)::int) - 1) $$;

-- Semana: Admin vê tudo; os demais perfis veem só horários de quem trabalha (sem falta/atestado e sem salário)
create or replace function public.api_escala_semana(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_ini date; v_fim date; v_adm boolean := tem_nivel('Admin'); v_f jsonb; v_t jsonb; v_p jsonb := '[]'::jsonb;
begin
  if auth_nivel() is null then return _negado(); end if;
  v_ini := _escala_segunda(coalesce(nullif(p->>'inicio', '')::date, (now() at time zone 'America/Sao_Paulo')::date));
  v_fim := v_ini + 6;
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'cargo', f.cargo, 'ativo', f.ativo, 'usuarioId', case when v_adm then f.usuario_id end) order by f.nome), '[]'::jsonb) into v_f
    from funcionarios f where f.ativo or (v_adm and exists (select 1 from escala_turnos t where t.funcionario_id = f.id and t.data between v_ini and v_fim and not t.cancelado));
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'funcionarioId', t.funcionario_id, 'data', t.data,
           'tipo', case when v_adm or t.tipo in ('Trabalho', 'Folga', 'Férias') then t.tipo else 'Ausente' end,
           'inicio', to_char(t.inicio, 'HH24:MI'), 'fim', to_char(t.fim, 'HH24:MI'), 'funcao', t.funcao,
           'observacao', case when v_adm then t.observacao end) order by t.data, t.inicio), '[]'::jsonb) into v_t
    from escala_turnos t where t.data between v_ini and v_fim and not t.cancelado;
  if v_adm then
    select coalesce(jsonb_agg(jsonb_build_object('funcionarioId', funcionario_id, 'dia', dia_semana, 'tipo', tipo, 'inicio', to_char(inicio, 'HH24:MI'), 'fim', to_char(fim, 'HH24:MI'), 'funcao', funcao)), '[]'::jsonb) into v_p from escala_padrao;
  end if;
  return jsonb_build_object('ok', true, 'inicio', v_ini, 'fim', v_fim, 'funcionarios', v_f, 'turnos', v_t, 'padrao', v_p, 'admin', v_adm);
end $$;

-- Criar / editar / cancelar um turno
create or replace function public.api_salvar_turno(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_f uuid := _uuid(p->>'funcionarioId'); v_data date := nullif(p->>'data', '')::date; v_tipo text := coalesce(nullif(p->>'tipo', ''), 'Trabalho');
        v_ini time := nullif(p->>'inicio', '')::time; v_fim time := nullif(p->>'fim', '')::time; v_nome text; v_ocupa text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select nome into v_nome from funcionarios where id = v_f;
  if v_nome is null then return _falha('Funcionário não encontrado.'); end if;
  if v_data is null then return _falha('Informe a data.'); end if;
  if coalesce(p->>'cancelar', '') = 'true' then
    update escala_turnos set cancelado = true where id = v_id and not cancelado;
    if not found then return _falha('Turno não encontrado.'); end if;
    perform _auditar('Escala: turno removido', v_nome || ' | ' || v_data);
    return jsonb_build_object('ok', true, 'message', 'Turno removido.');
  end if;
  if v_tipo <> all (array['Trabalho', 'Folga', 'Férias', 'Falta', 'Atestado']) then return _falha('Tipo inválido.'); end if;
  if v_tipo = 'Trabalho' then
    if v_ini is null or v_fim is null or v_ini = v_fim then return _falha('Informe o horário de entrada e de saída (diferentes).'); end if;
    if exists (select 1 from escala_turnos t where t.funcionario_id = v_f and t.data = v_data and t.tipo = 'Trabalho' and not t.cancelado and t.id is distinct from v_id
               and tsrange(v_data + t.inicio, v_data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end)
                && tsrange(v_data + v_ini, v_data + v_fim + case when v_fim <= v_ini then interval '1 day' else interval '0' end)) then
      return _falha(v_nome || ' já tem um turno que se sobrepõe a esse horário no dia ' || to_char(v_data, 'DD/MM') || '.');
    end if;
    select string_agg(distinct t.tipo, ', ') into v_ocupa from escala_turnos t where t.funcionario_id = v_f and t.data = v_data and t.tipo in ('Folga', 'Férias', 'Atestado') and not t.cancelado and t.id is distinct from v_id;
    if v_ocupa is not null and coalesce(p->>'confirmado', '') <> 'true' then
      return jsonb_build_object('ok', false, 'confirmar', true, 'message', v_nome || ' está marcado como ' || lower(v_ocupa) || ' em ' || to_char(v_data, 'DD/MM') || '. Escalar para trabalhar mesmo assim?');
    end if;
  else v_ini := null; v_fim := null; end if;
  if v_id is null then
    insert into escala_turnos (funcionario_id, data, tipo, inicio, fim, funcao, observacao)
    values (v_f, v_data, v_tipo, v_ini, v_fim, left(nullif(btrim(coalesce(p->>'funcao', '')), ''), 40), left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 200));
  else
    update escala_turnos set funcionario_id = v_f, data = v_data, tipo = v_tipo, inicio = v_ini, fim = v_fim, funcao = left(nullif(btrim(coalesce(p->>'funcao', '')), ''), 40), observacao = left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 200)
     where id = v_id and not cancelado;
    if not found then return _falha('Turno não encontrado.'); end if;
  end if;
  perform _auditar('Escala: turno salvo', v_nome || ' | ' || v_data || ' | ' || v_tipo || coalesce(' ' || to_char(v_ini, 'HH24:MI') || '-' || to_char(v_fim, 'HH24:MI'), ''));
  return jsonb_build_object('ok', true, 'message', 'Escala salva.');
end $$;

-- Padrão semanal de uma pessoa (7 dias: trabalho com horário, ou folga)
create or replace function public.api_escala_padrao_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_f uuid := _uuid(p->>'funcionarioId'); d jsonb; v_dia int; v_tipo text; v_ini time; v_fim time; v_nome text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select nome into v_nome from funcionarios where id = v_f;
  if v_nome is null then return _falha('Funcionário não encontrado.'); end if;
  for d in select value from jsonb_array_elements(coalesce(p->'dias', '[]'::jsonb)) loop
    v_dia := (d->>'dia')::int; v_tipo := case when d->>'tipo' = 'Trabalho' then 'Trabalho' else 'Folga' end;
    v_ini := nullif(d->>'inicio', '')::time; v_fim := nullif(d->>'fim', '')::time;
    if v_dia is null or v_dia < 0 or v_dia > 6 then return _falha('Dia da semana inválido.'); end if;
    if v_tipo = 'Trabalho' and (v_ini is null or v_fim is null or v_ini = v_fim) then return _falha('Informe entrada e saída (diferentes) nos dias de trabalho.'); end if;
    if v_tipo = 'Folga' then v_ini := null; v_fim := null; end if;
    insert into escala_padrao (funcionario_id, dia_semana, tipo, inicio, fim, funcao) values (v_f, v_dia, v_tipo, v_ini, v_fim, left(nullif(btrim(coalesce(d->>'funcao', '')), ''), 40))
    on conflict (funcionario_id, dia_semana) do update set tipo = excluded.tipo, inicio = excluded.inicio, fim = excluded.fim, funcao = excluded.funcao;
  end loop;
  perform _auditar('Escala: padrão semanal salvo', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Padrão semanal de ' || v_nome || ' salvo.');
end $$;

-- Aplicar o padrão semanal em N semanas (só preenche os dias que ainda não têm nada para a pessoa)
create or replace function public.api_escala_aplicar_padrao(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_ini date := _escala_segunda(coalesce(nullif(p->>'inicio', '')::date, current_date)); v_sem int := greatest(1, least(coalesce(nullif(p->>'semanas', '')::int, 1), 12)); v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  with dias as (select (v_ini + g)::date as dia from generate_series(0, v_sem * 7 - 1) g),
  novos as (
    insert into escala_turnos (funcionario_id, data, tipo, inicio, fim, funcao)
    select e.funcionario_id, d.dia, e.tipo, e.inicio, e.fim, e.funcao
      from dias d join escala_padrao e on e.dia_semana = extract(dow from d.dia)::int
      join funcionarios f on f.id = e.funcionario_id and f.ativo
     where not exists (select 1 from escala_turnos t where t.funcionario_id = e.funcionario_id and t.data = d.dia and not t.cancelado)
    returning 1)
  select count(*) into v_n from novos;
  perform _auditar('Escala: padrão aplicado', v_sem || ' semana(s) a partir de ' || v_ini || ' | ' || v_n || ' turno(s)');
  return jsonb_build_object('ok', true, 'message', v_n || ' turno(s) criados' || case when v_n = 0 then ' (nada novo: os dias já estavam preenchidos ou falta definir o padrão de cada pessoa).' else '.' end, 'criados', v_n);
end $$;

-- Copiar uma semana para outra (dias que ainda estão vazios; falta e atestado não são copiados)
create or replace function public.api_escala_copiar_semana(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_de date := _escala_segunda(nullif(p->>'de', '')::date); v_para date := _escala_segunda(nullif(p->>'para', '')::date); v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_de is null or v_para is null or v_de = v_para then return _falha('Escolha duas semanas diferentes.'); end if;
  with novos as (
    insert into escala_turnos (funcionario_id, data, tipo, inicio, fim, funcao, observacao)
    select t.funcionario_id, t.data + (v_para - v_de), t.tipo, t.inicio, t.fim, t.funcao, t.observacao
      from escala_turnos t join funcionarios f on f.id = t.funcionario_id and f.ativo
     where t.data between v_de and v_de + 6 and not t.cancelado and t.tipo in ('Trabalho', 'Folga', 'Férias')
       and not exists (select 1 from escala_turnos x where x.funcionario_id = t.funcionario_id and x.data = t.data + (v_para - v_de) and not x.cancelado)
    returning 1)
  select count(*) into v_n from novos;
  perform _auditar('Escala: semana copiada', v_de || ' para ' || v_para || ' | ' || v_n || ' turno(s)');
  return jsonb_build_object('ok', true, 'message', v_n || ' turno(s) copiados.', 'criados', v_n);
end $$;

-- Importar os acessos (logins) ativos que ainda não são funcionários
create or replace function public.api_equipe_importar_acessos(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  with novos as (
    insert into funcionarios (nome, cargo, telefone, salario, dia_pagamento, usuario_id)
    select left(u.nome, 80), u.nivel::text, left(u.telefone, 30), 0, 5, u.id from usuarios u
     where u.ativo and u.nivel::text <> 'Desenvolvedor' and not exists (select 1 from funcionarios f where f.usuario_id = u.id)
    returning 1)
  select count(*) into v_n from novos;
  perform _auditar('Equipe: acessos importados como funcionários', v_n || ' pessoa(s)');
  return jsonb_build_object('ok', true, 'message', v_n || ' pessoa(s) importadas. Complete salário e dia de pagamento de cada uma, se quiser controlar os pagamentos.', 'criados', v_n);
end $$;

-- Minha escala: os próximos dias de quem está ligado a um funcionário
create or replace function public.api_minha_escala(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_f uuid; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_t jsonb;
begin
  if auth_nivel() is null then return _negado(); end if;
  select id into v_f from funcionarios where usuario_id = auth.uid() and ativo;
  if v_f is null then return jsonb_build_object('ok', true, 'vinculado', false, 'turnos', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('data', t.data, 'tipo', case when t.tipo in ('Falta', 'Atestado') then 'Ausente' else t.tipo end,
           'inicio', to_char(t.inicio, 'HH24:MI'), 'fim', to_char(t.fim, 'HH24:MI'), 'funcao', t.funcao) order by t.data, t.inicio), '[]'::jsonb) into v_t
    from escala_turnos t where t.funcionario_id = v_f and t.data between v_hoje and v_hoje + 13 and not t.cancelado;
  return jsonb_build_object('ok', true, 'vinculado', true, 'turnos', v_t);
end $$;

do $$ declare f text; begin
  foreach f in array array['api_escala_semana(jsonb)', 'api_salvar_turno(jsonb)', 'api_escala_padrao_salvar(jsonb)', 'api_escala_aplicar_padrao(jsonb)', 'api_escala_copiar_semana(jsonb)', 'api_equipe_importar_acessos(jsonb)', 'api_minha_escala(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
end $$;


-- ======================================================================
-- 22-eventos-movimentos.sql
-- ======================================================================
-- =====================================================================
-- 22 · CENTRAL DE EVENTOS: lista de custos/recebimentos e cancelamento (18/10/2026)
-- Custos e recebimentos lançados podem ser cancelados (nada é apagado: fica marcado). Os totais ignoram os cancelados.
-- Aditivo: 2 colunas por tabela, 1 função ajustada, 2 funções novas.
-- =====================================================================
alter table public.eventos_custos add column if not exists cancelado boolean not null default false;
alter table public.eventos_custos add column if not exists motivo_cancelamento text;
alter table public.eventos_recebimentos add column if not exists cancelado boolean not null default false;
alter table public.eventos_recebimentos add column if not exists motivo_cancelamento text;

create or replace function public._recalcular_evento(p_id uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_contr numeric; v_custos numeric; v_rec numeric;
begin
  select valor_contratado into v_contr from eventos where id = p_id;
  if not found then return; end if;
  select coalesce(sum(valor), 0) into v_custos from eventos_custos where evento_id = p_id and not cancelado;
  select coalesce(sum(valor), 0) into v_rec from eventos_recebimentos where evento_id = p_id and not cancelado;
  update eventos set valor_recebido = v_rec, valor_a_receber = greatest(0, v_contr - v_rec), custo_total = v_custos,
         resultado = round(v_contr - v_custos, 2) where id = p_id;
end $$;

create or replace function public.api_evento_movimentos(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'eventoId');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from eventos where id = v_id) then return _falha('Evento não encontrado.'); end if;
  return jsonb_build_object('ok', true,
    'custos', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'descricao', c.descricao, 'categoria', coalesce(c.categoria, ''), 'valor', c.valor,
        'data', coalesce(c.data::text, ''), 'observacao', coalesce(c.observacao, '')) order by c.data desc nulls last, c.criado_em desc)
        from eventos_custos c where c.evento_id = v_id and not c.cancelado), '[]'::jsonb),
    'recebimentos', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'valor', r.valor, 'forma', coalesce(r.forma_pagamento, ''),
        'data', coalesce(r.data::text, ''), 'observacao', coalesce(r.observacao, '')) order by r.data desc nulls last, r.criado_em desc)
        from eventos_recebimentos r where r.evento_id = v_id and not r.cancelado), '[]'::jsonb));
end $$;

create or replace function public.api_cancelar_movimento_evento(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_tipo text := p->>'tipo'; v_id uuid := _uuid(p->>'id'); v_motivo text := left(btrim(coalesce(p->>'motivo', '')), 300); v_aut text; v_ev uuid; v_val numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  if v_tipo = 'custo' then
    update eventos_custos set cancelado = true, motivo_cancelamento = v_motivo where id = v_id and not cancelado returning evento_id, valor into v_ev, v_val;
  elsif v_tipo = 'recebimento' then
    update eventos_recebimentos set cancelado = true, motivo_cancelamento = v_motivo where id = v_id and not cancelado returning evento_id, valor into v_ev, v_val;
  else
    return _falha('Tipo inválido.');
  end if;
  if v_ev is null then return _falha('Lançamento não encontrado ou já cancelado.'); end if;
  perform _recalcular_evento(v_ev);
  perform _auditar('Lançamento de evento cancelado', v_tipo || ' R$ ' || _dinheiro(v_val) || ' | ' || v_motivo);
  return jsonb_build_object('ok', true, 'message', 'Lançamento cancelado.', 'evento', _evento_json(v_ev));
end $$;

revoke all on function public.api_evento_movimentos(jsonb) from public;
revoke all on function public.api_cancelar_movimento_evento(jsonb) from public;
grant execute on function public.api_evento_movimentos(jsonb) to authenticated, service_role;
grant execute on function public.api_cancelar_movimento_evento(jsonb) to authenticated, service_role;


-- ======================================================================
-- 23-espaco-arquivamento.sql
-- ======================================================================
-- =====================================================================
-- 23 · ESPAÇO DO BANCO E ARQUIVAMENTO CONFIGURÁVEL (18/10/2026)
--  1) Proteção dos 95% TRAVADA: sempre ligada e sempre em 95% (gatilho no banco; nem alteração direta consegue desligar).
--  2) "Tamanho do banco do meu plano" (500 MB grátis, 8 GB Pro, ou outro): api_espaco_plano_salvar. Porcentagens e proteção usam esse número.
--  3) Depois de cada arquivamento, o espaço é DEVOLVIDO de verdade: o banco só encolhe com "vacuum full"; uma tarefa de uso único é agendada
--     para 3 minutos depois do envio à planilha (sem isso o tamanho continuaria igual e a proteção nunca enxergaria o ganho).
--  4) Avisos de espaço aos 70% e 85% do limite do plano (antes: fixo em 400 MB).
-- Aditivo. Pode rodar de novo sem erro.
-- =====================================================================

-- 1) trava dos 95%
create or replace function public._backup_config_trava() returns trigger
language plpgsql set search_path to 'public' as $$
begin new.arquivar_emerg_ativo := true; new.arquivar_emerg_pct := 95; return new; end $$;
create or replace trigger backup_config_trava before insert or update on public.backup_config
  for each row execute function public._backup_config_trava();
update public.backup_config set arquivar_emerg_ativo = true, arquivar_emerg_pct = 95 where id;

-- 2) tamanho do banco do plano
create or replace function public.api_espaco_plano_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v numeric := _num(p->>'limiteMb', 0);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v < 100 or v > 2000000 then return _falha('Informe o tamanho do banco do seu plano em MB (entre 100 e 2.000.000). Grátis: 500. Pro: 8192.'); end if;
  insert into sistema (chave, valor, atualizado_em) values ('LIMITE_BANCO_MB', to_jsonb(v), now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('Tamanho do banco do plano alterado', v || ' MB');
  return jsonb_build_object('ok', true, 'message', 'Salvo: o sistema passa a considerar ' || v || ' MB como o limite do banco.', 'limiteMb', v);
end $$;
revoke all on function public.api_espaco_plano_salvar(jsonb) from public;
grant execute on function public.api_espaco_plano_salvar(jsonb) to authenticated, service_role;

-- 3) devolver o espaço depois de arquivar
create or replace function public._compactar_agendar() returns void
language plpgsql security definer set search_path to 'public', 'cron' as $$
declare r record; v_quando timestamptz := now() + interval '3 minutes'; v_pendente boolean := false;
begin
  for r in select jobname from cron.job where jobname like 'compactar-%' loop
    if coalesce(nullif(substring(r.jobname from 'compactar-(\d+)'), '')::bigint, 0) < extract(epoch from now() - interval '15 minutes') then
      perform cron.unschedule(r.jobname);
    else v_pendente := true; end if;
  end loop;
  if v_pendente then return; end if;
  perform cron.schedule('compactar-' || floor(extract(epoch from v_quando))::bigint,
    extract(minute from v_quando at time zone 'UTC')::int || ' ' || extract(hour from v_quando at time zone 'UTC')::int || ' ' ||
    extract(day from v_quando at time zone 'UTC')::int || ' ' || extract(month from v_quando at time zone 'UTC')::int || ' *',
    'vacuum full public.vendas, public.itens_venda, public.pagamentos_venda, public.caixa_sessoes, public.sangrias, public.vendas_resumo_arquivo, public.arquivo_historico');
end $$;
revoke all on function public._compactar_agendar() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'api_arquivar_confirmar_caixa' and p.prosrc not like '%_arquivar_confirmar_caixa_base%') then
    alter function public.api_arquivar_confirmar_caixa(uuid[]) rename to _arquivar_confirmar_caixa_base;
  end if;
end $$;
create or replace function public.api_arquivar_confirmar_caixa(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare r jsonb;
begin
  r := _arquivar_confirmar_caixa_base(p_ids);
  begin perform _compactar_agendar(); exception when others then null; end;
  return r;
end $$;
revoke all on function public.api_arquivar_confirmar_caixa(uuid[]) from public, anon, authenticated;
grant execute on function public.api_arquivar_confirmar_caixa(uuid[]) to service_role;
revoke all on function public._arquivar_confirmar_caixa_base(uuid[]) from public, anon, authenticated;

create or replace function public.api_arquivar_confirmar_vendas(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare r jsonb;
begin
  update pagamentos_online po set venda_numero = v.numero_pedido from vendas v where v.id = po.venda_id and po.venda_id = any(p_ids) and po.venda_numero is null;
  r := _arquivar_confirmar_vendas_base(p_ids);
  begin perform _compactar_agendar(); exception when others then null; end;
  return r;
end $$;
revoke all on function public.api_arquivar_confirmar_vendas(uuid[]) from public, anon, authenticated;
grant execute on function public.api_arquivar_confirmar_vendas(uuid[]) to service_role;

-- 4) avisos de espaço aos 70% e 85% do limite do plano (ajusta só o trecho do aviso dentro de alertas_sistema_cron)
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.alertas_sistema_cron'::regproc) into v_def;
  if v_def like '%400 * 1024 * 1024%' then
    v_def := replace(v_def, $q$if v_tam > 400 * 1024 * 1024 then$q$, $q$if v_tam > _limite_banco_mb() * 1048576 * 0.70 then$q$);
    v_def := replace(v_def, $q$'Usando ' || round(v_tam / 1048576.0) || ' MB de 500 MB. Arquive vendas antigas em Sistema → Backup e espaço.', interval '24 hours'$q$,
      $q$case when v_tam > _limite_banco_mb() * 1048576 * 0.85 then 'Usando ' || round(v_tam / 1048576.0) || ' MB de ' || round(_limite_banco_mb()) || ' MB (mais de 85%). Aos 95% o sistema arquiva sozinho o que for mais antigo. Se o seu plano não é mais o grátis, confira o tamanho em Sistema → Backup e espaço.' else 'Usando ' || round(v_tam / 1048576.0) || ' MB de ' || round(_limite_banco_mb()) || ' MB (mais de 70%). Arquive vendas antigas em Sistema → Backup e espaço. Se o seu plano não é mais o grátis, confira o tamanho informado lá.' end, case when v_tam > _limite_banco_mb() * 1048576 * 0.85 then interval '12 hours' else interval '24 hours' end$q$);
    execute v_def;
  end if;
end $$;

-- 23b - Assistente: verbete "Arquivamento e uso do banco" atualizado (modo automático/manual, tamanho do plano, proteção dos 95% travada)
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-admin-14-arquivamento-e-uso-do-banco$t$,$t$Arquivamento e uso do banco$t$,$t$arquivamento uso do banco espaço limite plano pago pro gratuito 500 mb 95% proteção automático manual desligar arquivar dias prazo planilha supabase cheio$t$,
$t$Administrador → Sistema → Backup e espaço → bloco "Uso do Supabase".
Em "Tamanho do banco do seu plano" informe o plano do Supabase: Grátis (500 MB), Pro (8 GB) ou outro tamanho (confira no painel do Supabase). A porcentagem de uso e a proteção usam esse número; se você pagar o Supabase, atualize aqui.
Em "Arquivamento por idade": Automático (todo dia de madrugada, vendas e caixas fechados com mais de X dias vão para a planilha, abas Arquivo_*) ou Só manual (o sistema não arquiva sozinho; você manda em "Mandar para a planilha agora"). O prazo é livre (mínimo 30 dias). "Simular" mostra o que sairia sem mover nada.
"Proteção de espaço" é sempre ligada e não dá para desligar nem mudar: ao chegar a 95% do tamanho do plano, o sistema manda para a planilha, aos poucos (até 1.000 vendas por hora), as vendas e caixas já encerrados, do mais antigo para o mais novo, e minutos depois devolve o espaço ao Supabase. O que tem menos de 1 dia, pedido em andamento e caixa aberto nunca saem; só remove do Supabase o que a planilha confirmou. Aos 70% e 85% você recebe aviso.
Relatórios e Visão Geral buscam o arquivo automaticamente quando o período pedido é antigo. Fotos ficam no Google Drive principal, com cópia no Drive da contingência. Ao anonimizar um cliente (LGPD), os pedidos dele arquivados na planilha também são limpos, de madrugada.$t$,
ARRAY['Admin'],true,'lista',14,$t$$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();


-- ======================================================================
-- 24-escala-trocas-ponto.sql
-- ======================================================================
-- =====================================================================
-- 24 · ESCALA: TROCA DE TURNO, AVISOS NO CELULAR E PONTO (18/10/2026)
--  1) Troca de turno: a pessoa pede para passar um turno a um colega; o colega aceita (ou recusa); o dono aprova (ou recusa).
--     Só aí o turno muda de pessoa. O dono também pode aprovar direto, sem esperar o colega.
--  2) Avisos no celular: "sua escala mudou" (turno salvo/removido nos próximos 14 dias) e botão "Avisar a equipe" (resumo da semana).
--  3) Ponto: cada pessoa bate entrada e saída pelo celular (Início); o dono vê horas feitas x escaladas, horas extras (acima de 44 h na semana)
--     e corrige/lança registros esquecidos. Registro cancelado fica guardado. Aviso ao dono quando alguém esquece de bater a saída.
-- Aditivo: 2 tabelas, 11 funções (2 ajustadas). Pode rodar de novo sem erro. Rode DEPOIS do 21.
-- =====================================================================

-- ---------- tabelas ----------
create table if not exists public.escala_trocas (
  id uuid primary key default gen_random_uuid(),
  turno_id uuid not null references public.escala_turnos(id),
  de_funcionario_id uuid not null references public.funcionarios(id),
  para_funcionario_id uuid not null references public.funcionarios(id),
  status text not null default 'Aguardando colega' check (status in ('Aguardando colega', 'Aguardando dono', 'Aprovada', 'Recusada', 'Cancelada')),
  motivo text,
  resposta text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists escala_trocas_status_idx on public.escala_trocas (status, criado_em desc);
create table if not exists public.ponto_registros (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  entrada timestamptz not null,
  saida timestamptz,
  origem text not null default 'app',
  observacao text,
  cancelado boolean not null default false,
  criado_em timestamptz not null default now(),
  check (saida is null or saida > entrada)
);
create index if not exists ponto_registros_func_idx on public.ponto_registros (funcionario_id, entrada desc);
alter table public.escala_trocas enable row level security;
alter table public.ponto_registros enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'escala_trocas' and policyname = 'escala_trocas_ler_admin') then
    create policy escala_trocas_ler_admin on public.escala_trocas for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'ponto_registros' and policyname = 'ponto_registros_ler_admin') then
    create policy ponto_registros_ler_admin on public.ponto_registros for select to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
  end if;
end $$;
revoke all on public.escala_trocas, public.ponto_registros from anon, authenticated;
grant select on public.escala_trocas, public.ponto_registros to authenticated;
grant all on public.escala_trocas, public.ponto_registros to service_role;

-- ---------- ajudantes ----------
create or replace function public._func_do_usuario() returns uuid language sql stable security definer set search_path to 'public' as $$
  select id from funcionarios where usuario_id = auth.uid() and ativo limit 1
$$;
create or replace function public._push_func(p_func uuid, p_titulo text, p_texto text, p_tag text) returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_u uuid;
begin
  select usuario_id into v_u from funcionarios where id = p_func;
  if v_u is null then return; end if;
  perform _alertas_push(p_titulo, p_texto, p_tag, array['Admin', 'Operador', 'Cozinha', 'Garçom'], array[v_u]);
exception when others then null;
end $$;
create or replace function public._push_admins(p_titulo text, p_texto text, p_tag text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  perform _alertas_push(p_titulo, p_texto, p_tag, array['Admin']);
exception when others then null;
end $$;
create or replace function public._escala_dia_texto(p_func uuid, p_data date) returns text
language sql stable security definer set search_path to 'public' as $$
  select coalesce(string_agg(case when t.tipo = 'Trabalho' then to_char(t.inicio, 'HH24:MI') || '–' || to_char(t.fim, 'HH24:MI') when t.tipo in ('Falta', 'Atestado') then 'Ausente' else t.tipo end, ', ' order by t.inicio), 'sem turno')
    from escala_turnos t where t.funcionario_id = p_func and t.data = p_data and not t.cancelado
$$;
create or replace function public._escala_avisar_pessoa(p_func uuid, p_data date) returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_data < v_hoje or p_data > v_hoje + 14 then return; end if;
  perform _push_func(p_func, '📅 Sua escala mudou', to_char(p_data, 'DD/MM') || ': ' || _escala_dia_texto(p_func, p_data), 'escala-' || p_func || '-' || p_data);
end $$;
revoke all on function public._func_do_usuario(), public._push_func(uuid, text, text, text), public._push_admins(text, text, text),
  public._escala_dia_texto(uuid, date), public._escala_avisar_pessoa(uuid, date) from public, anon, authenticated;

-- salvar/remover turno avisa a pessoa (ajusta as funções do 21 sem reescrevê-las)
do $$
declare v text;
begin
  select pg_get_functiondef('public.api_salvar_turno(jsonb)'::regprocedure) into v;
  if v not like '%_escala_avisar_pessoa%' then
    v := replace(v, $q$perform _auditar('Escala: turno removido', v_nome || ' | ' || v_data);$q$, $q$perform _auditar('Escala: turno removido', v_nome || ' | ' || v_data); perform _escala_avisar_pessoa(v_f, v_data);$q$);
    v := replace(v, $q$perform _auditar('Escala: turno salvo',$q$, $q$perform _escala_avisar_pessoa(v_f, v_data); perform _auditar('Escala: turno salvo',$q$);
    execute v;
  end if;
  select pg_get_functiondef('public.api_minha_escala(jsonb)'::regprocedure) into v;
  if v not like '%''id'', t.id%' then
    v := replace(v, $q$jsonb_build_object('data', t.data, 'tipo', case when t.tipo in ('Falta', 'Atestado')$q$, $q$jsonb_build_object('id', t.id, 'data', t.data, 'tipo', case when t.tipo in ('Falta', 'Atestado')$q$);
    execute v;
  end if;
end $$;

-- "Avisar a equipe": manda a cada pessoa (com acesso) o resumo da semana escolhida
create or replace function public.api_escala_avisar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_ini date; r record; v_txt text; v_n int := 0; d int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_ini := _escala_segunda(coalesce(nullif(p->>'inicio', '')::date, (now() at time zone 'America/Sao_Paulo')::date));
  for r in select f.id, f.nome from funcionarios f where f.ativo and f.usuario_id is not null
            and exists (select 1 from escala_turnos t where t.funcionario_id = f.id and t.data between v_ini and v_ini + 6 and not t.cancelado) loop
    v_txt := '';
    for d in 0..6 loop
      v_txt := v_txt || (array['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'])[d + 1] || ' ' || to_char(v_ini + d, 'DD/MM') || ' ' || _escala_dia_texto(r.id, v_ini + d) || E'\n';
    end loop;
    perform _push_func(r.id, '📅 Escala da semana', btrim(v_txt), 'escala-sem-' || r.id || '-' || v_ini);
    v_n := v_n + 1;
  end loop;
  perform _auditar('Escala: equipe avisada', v_ini || ' | ' || v_n || ' pessoa(s)');
  return jsonb_build_object('ok', true, 'avisados', v_n, 'message', case when v_n = 0 then 'Ninguém para avisar: só quem tem acesso ao sistema (e ativou os avisos no celular) recebe. Use "Importar acessos".' else 'Aviso enviado para ' || v_n || ' pessoa(s) com acesso ao sistema. Quem ainda não ativou os avisos no celular vê na tela Início.' end);
end $$;

-- ---------- troca de turno ----------
create or replace function public.api_troca_solicitar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); v_t escala_turnos%rowtype; v_para uuid := _uuid(p->>'paraFuncionarioId'); v_nome_eu text; v_nome_para text; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_id uuid;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return _falha('Seu acesso ainda não está ligado a um funcionário. Peça ao dono para usar "Importar acessos" na Escala.'); end if;
  select * into v_t from escala_turnos where id = _uuid(p->>'turnoId') and not cancelado;
  if v_t.id is null or v_t.funcionario_id <> v_eu then return _falha('Esse turno não é seu.'); end if;
  if v_t.tipo <> 'Trabalho' then return _falha('Só dá para trocar turno de trabalho.'); end if;
  if v_t.data < v_hoje then return _falha('Esse turno já passou.'); end if;
  select nome into v_nome_para from funcionarios where id = v_para and ativo;
  if v_nome_para is null or v_para = v_eu then return _falha('Escolha um colega.'); end if;
  if exists (select 1 from escala_trocas where turno_id = v_t.id and status in ('Aguardando colega', 'Aguardando dono')) then return _falha('Esse turno já tem um pedido de troca em andamento.'); end if;
  insert into escala_trocas (turno_id, de_funcionario_id, para_funcionario_id, motivo) values (v_t.id, v_eu, v_para, left(nullif(btrim(coalesce(p->>'motivo', '')), ''), 200)) returning id into v_id;
  select nome into v_nome_eu from funcionarios where id = v_eu;
  perform _push_func(v_para, '🔁 Pedido de troca de turno', v_nome_eu || ' pede para você assumir o turno de ' || to_char(v_t.data, 'DD/MM') || ' (' || to_char(v_t.inicio, 'HH24:MI') || '–' || to_char(v_t.fim, 'HH24:MI') || '). Abra o Início para responder.', 'troca-' || v_id);
  perform _auditar('Escala: troca solicitada', v_nome_eu || ' → ' || v_nome_para || ' | ' || v_t.data);
  return jsonb_build_object('ok', true, 'message', 'Pedido enviado para ' || v_nome_para || '. Se ele aceitar, o dono aprova e a escala muda.');
end $$;

create or replace function public.api_troca_responder(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); x escala_trocas%rowtype; v_acao text := p->>'acao'; v_t escala_turnos%rowtype; v_de text; v_para text;
begin
  if auth_nivel() is null then return _negado(); end if;
  select * into x from escala_trocas where id = _uuid(p->>'id') for update;
  if x.id is null then return _falha('Pedido não encontrado.'); end if;
  select * into v_t from escala_turnos where id = x.turno_id;
  select nome into v_de from funcionarios where id = x.de_funcionario_id; select nome into v_para from funcionarios where id = x.para_funcionario_id;
  if v_acao = 'cancelar' then
    if v_eu is distinct from x.de_funcionario_id or x.status not in ('Aguardando colega', 'Aguardando dono') then return _falha('Não dá para cancelar esse pedido.'); end if;
    update escala_trocas set status = 'Cancelada', atualizado_em = now() where id = x.id;
    return jsonb_build_object('ok', true, 'message', 'Pedido cancelado.');
  end if;
  if v_eu is distinct from x.para_funcionario_id or x.status <> 'Aguardando colega' then return _falha('Esse pedido não está esperando a sua resposta.'); end if;
  if v_acao = 'aceitar' then
    if exists (select 1 from escala_turnos t where t.funcionario_id = v_eu and t.data = v_t.data and t.tipo = 'Trabalho' and not t.cancelado
               and tsrange(t.data + t.inicio, t.data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end)
                && tsrange(v_t.data + v_t.inicio, v_t.data + v_t.fim + case when v_t.fim <= v_t.inicio then interval '1 day' else interval '0' end)) then
      return _falha('Você já tem um turno nesse horário em ' || to_char(v_t.data, 'DD/MM') || '.');
    end if;
    update escala_trocas set status = 'Aguardando dono', atualizado_em = now() where id = x.id;
    perform _push_admins('🔁 Troca de turno para aprovar', v_de || ' → ' || v_para || ' em ' || to_char(v_t.data, 'DD/MM') || ' (' || to_char(v_t.inicio, 'HH24:MI') || '–' || to_char(v_t.fim, 'HH24:MI') || '). Aprove em Loja e equipe → Escala.', 'troca-adm-' || x.id);
    perform _push_func(x.de_funcionario_id, '🔁 ' || v_para || ' aceitou a troca', 'Agora falta o dono aprovar.', 'troca-' || x.id);
    return jsonb_build_object('ok', true, 'message', 'Você aceitou. Agora o dono precisa aprovar.');
  elsif v_acao = 'recusar' then
    update escala_trocas set status = 'Recusada', resposta = 'Recusada pelo colega', atualizado_em = now() where id = x.id;
    perform _push_func(x.de_funcionario_id, '🔁 Troca recusada', v_para || ' não pôde assumir o turno de ' || to_char(v_t.data, 'DD/MM') || '.', 'troca-' || x.id);
    return jsonb_build_object('ok', true, 'message', 'Pedido recusado.');
  end if;
  return _falha('Ação inválida.');
end $$;

create or replace function public.api_troca_decidir(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare x escala_trocas%rowtype; v_t escala_turnos%rowtype; v_aprovar boolean := coalesce(p->>'aprovar', '') = 'true'; v_de text; v_para text; v_resp text := left(nullif(btrim(coalesce(p->>'motivo', '')), ''), 200);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into x from escala_trocas where id = _uuid(p->>'id') for update;
  if x.id is null or x.status not in ('Aguardando colega', 'Aguardando dono') then return _falha('Esse pedido não está mais em aberto.'); end if;
  select * into v_t from escala_turnos where id = x.turno_id;
  select nome into v_de from funcionarios where id = x.de_funcionario_id; select nome into v_para from funcionarios where id = x.para_funcionario_id;
  if not v_aprovar then
    update escala_trocas set status = 'Recusada', resposta = coalesce(v_resp, 'Recusada pelo dono'), atualizado_em = now() where id = x.id;
    perform _push_func(x.de_funcionario_id, '🔁 Troca não aprovada', 'O pedido de troca de ' || to_char(v_t.data, 'DD/MM') || ' não foi aprovado.', 'troca-' || x.id);
    perform _push_func(x.para_funcionario_id, '🔁 Troca não aprovada', 'O pedido de troca de ' || to_char(v_t.data, 'DD/MM') || ' não foi aprovado.', 'troca-' || x.id);
    return jsonb_build_object('ok', true, 'message', 'Troca recusada.');
  end if;
  if v_t.cancelado then return _falha('O turno foi removido da escala.'); end if;
  if exists (select 1 from escala_turnos t where t.funcionario_id = x.para_funcionario_id and t.data = v_t.data and t.tipo = 'Trabalho' and not t.cancelado and t.id <> v_t.id
             and tsrange(t.data + t.inicio, t.data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end)
              && tsrange(v_t.data + v_t.inicio, v_t.data + v_t.fim + case when v_t.fim <= v_t.inicio then interval '1 day' else interval '0' end)) then
    return _falha(v_para || ' já tem um turno nesse horário em ' || to_char(v_t.data, 'DD/MM') || '.');
  end if;
  update escala_turnos set funcionario_id = x.para_funcionario_id where id = v_t.id;
  update escala_trocas set status = 'Aprovada', resposta = v_resp, atualizado_em = now() where id = x.id;
  perform _push_func(x.de_funcionario_id, '✅ Troca aprovada', 'O turno de ' || to_char(v_t.data, 'DD/MM') || ' agora é de ' || v_para || '.', 'troca-' || x.id);
  perform _push_func(x.para_funcionario_id, '✅ Troca aprovada', 'Você assumiu o turno de ' || to_char(v_t.data, 'DD/MM') || ' (' || to_char(v_t.inicio, 'HH24:MI') || '–' || to_char(v_t.fim, 'HH24:MI') || ').', 'troca-' || x.id);
  perform _auditar('Escala: troca aprovada', v_de || ' → ' || v_para || ' | ' || v_t.data);
  return jsonb_build_object('ok', true, 'message', 'Troca aprovada: o turno passou para ' || v_para || '.');
end $$;

create or replace function public.api_trocas_lista(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); v_adm boolean := tem_nivel('Admin'); v_l jsonb;
begin
  if auth_nivel() is null then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'status', x.status, 'turnoId', x.turno_id, 'data', t.data, 'inicio', to_char(t.inicio, 'HH24:MI'), 'fim', to_char(t.fim, 'HH24:MI'),
      'de', fd.nome, 'para', fp.nome, 'deId', x.de_funcionario_id, 'paraId', x.para_funcionario_id, 'motivo', x.motivo, 'resposta', x.resposta,
      'euSolicitei', x.de_funcionario_id = v_eu, 'euSouColega', x.para_funcionario_id = v_eu) order by (x.status like 'Aguardando%') desc, x.criado_em desc), '[]'::jsonb) into v_l
    from escala_trocas x join escala_turnos t on t.id = x.turno_id join funcionarios fd on fd.id = x.de_funcionario_id join funcionarios fp on fp.id = x.para_funcionario_id
   where (v_adm or x.de_funcionario_id = v_eu or x.para_funcionario_id = v_eu) and (x.status like 'Aguardando%' or x.atualizado_em > now() - interval '7 days');
  return jsonb_build_object('ok', true, 'trocas', v_l, 'admin', v_adm, 'vinculado', v_eu is not null);
end $$;

-- ---------- ponto ----------
create or replace function public.api_ponto_estado(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_ini date; v_h numeric;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return jsonb_build_object('ok', true, 'vinculado', false); end if;
  v_ini := _escala_segunda(v_hoje);
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  select coalesce(round(sum(extract(epoch from coalesce(saida, now()) - entrada)) / 3600.0, 2), 0) into v_h from ponto_registros
   where funcionario_id = v_eu and not cancelado and (entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_ini + 6;
  return jsonb_build_object('ok', true, 'vinculado', true, 'aberto', r.id is not null, 'entrada', r.entrada, 'horasSemana', v_h);
end $$;

create or replace function public.api_ponto_bater(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return _falha('Seu acesso ainda não está ligado a um funcionário. Peça ao dono para usar "Importar acessos" na Escala.'); end if;
  perform pg_advisory_xact_lock(hashtext('ponto:' || v_eu));
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  if r.id is not null and r.entrada > now() - interval '20 seconds' then return jsonb_build_object('ok', true, 'message', 'Já registrado agora há pouco.', 'aberto', true); end if;
  if r.id is not null and r.entrada > now() - interval '20 hours' then
    update ponto_registros set saida = now() where id = r.id;
    return jsonb_build_object('ok', true, 'aberto', false, 'message', 'Saída registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '. Trabalhou ' || to_char(round(extract(epoch from now() - r.entrada) / 3600.0, 2), 'FM990.00') || ' h neste turno.');
  end if;
  insert into ponto_registros (funcionario_id, entrada) values (v_eu, now());
  return jsonb_build_object('ok', true, 'aberto', true, 'message', 'Entrada registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '.' || case when r.id is not null then ' (A saída anterior ficou sem registro; o dono pode corrigir.)' else '' end);
end $$;

create or replace function public.api_ponto_relatorio(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_ini date := coalesce(nullif(p->>'inicio', '')::date, _escala_segunda((now() at time zone 'America/Sao_Paulo')::date)); v_fim date := coalesce(nullif(p->>'fim', '')::date, v_ini + 6); v_l jsonb; v_r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_fim < v_ini or v_fim - v_ini > 62 then return _falha('Período inválido (máximo de 62 dias).'); end if;
  with reg as (
    select r.funcionario_id, r.id, r.entrada, r.saida, r.observacao, r.origem, (r.entrada at time zone 'America/Sao_Paulo')::date dia,
           extract(epoch from coalesce(r.saida, now()) - r.entrada) / 3600.0 h
      from ponto_registros r where not r.cancelado and (r.entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_fim),
  sem as (select funcionario_id, _escala_segunda(dia) semana, sum(h) h from reg group by 1, 2),
  extra as (select funcionario_id, sum(greatest(h - 44, 0)) ex from sem group by 1),
  esc as (select t.funcionario_id, sum(extract(epoch from (t.data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end) - (t.data + t.inicio)) / 3600.0) h
            from escala_turnos t where t.tipo = 'Trabalho' and not t.cancelado and t.data between v_ini and v_fim group by 1),
  tot as (select funcionario_id, sum(h) h from reg group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('funcionarioId', f.id, 'nome', f.nome, 'cargo', f.cargo,
      'horasFeitas', round(coalesce(tot.h, 0)::numeric, 2), 'horasEscaladas', round(coalesce(esc.h, 0)::numeric, 2),
      'diferenca', round((coalesce(tot.h, 0) - coalesce(esc.h, 0))::numeric, 2), 'horasExtras', round(coalesce(extra.ex, 0)::numeric, 2),
      'aberto', exists (select 1 from reg where reg.funcionario_id = f.id and reg.saida is null),
      'registros', coalesce((select jsonb_agg(jsonb_build_object('id', reg.id, 'dia', reg.dia, 'entrada', to_char(reg.entrada at time zone 'America/Sao_Paulo', 'HH24:MI'), 'saida', to_char(reg.saida at time zone 'America/Sao_Paulo', 'HH24:MI'),
          'horas', round(reg.h::numeric, 2), 'origem', reg.origem, 'observacao', reg.observacao) order by reg.entrada) from reg where reg.funcionario_id = f.id), '[]'::jsonb)
    ) order by f.nome), '[]'::jsonb) into v_l
    from funcionarios f left join tot on tot.funcionario_id = f.id left join esc on esc.funcionario_id = f.id left join extra on extra.funcionario_id = f.id
   where f.ativo or tot.h is not null;
  return jsonb_build_object('ok', true, 'inicio', v_ini, 'fim', v_fim, 'pessoas', v_l);
end $$;

-- lançar / corrigir / cancelar um registro (datas e horas no horário de Brasília)
create or replace function public.api_ponto_ajustar(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_f uuid := _uuid(p->>'funcionarioId'); v_ent timestamptz; v_sai timestamptz; v_nome text; v_obs text := left(nullif(btrim(coalesce(p->>'observacao', '')), ''), 200);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'cancelar', '') = 'true' then
    update ponto_registros set cancelado = true, observacao = coalesce(v_obs, observacao) where id = v_id and not cancelado returning funcionario_id into v_f;
    if v_f is null then return _falha('Registro não encontrado.'); end if;
    perform _auditar('Ponto: registro cancelado', (select nome from funcionarios where id = v_f));
    return jsonb_build_object('ok', true, 'message', 'Registro cancelado.');
  end if;
  begin
    v_ent := (p->>'entrada')::timestamp at time zone 'America/Sao_Paulo';
    v_sai := nullif(p->>'saida', '')::timestamp at time zone 'America/Sao_Paulo';
  exception when others then return _falha('Data ou hora inválida.'); end;
  if v_ent is null then return _falha('Informe a entrada.'); end if;
  if v_sai is not null and v_sai <= v_ent then return _falha('A saída precisa ser depois da entrada.'); end if;
  if v_sai is not null and v_sai - v_ent > interval '20 hours' then return _falha('Turno de mais de 20 horas: confira as datas.'); end if;
  if v_id is not null then select funcionario_id into v_f from ponto_registros where id = v_id; end if;
  select nome into v_nome from funcionarios where id = v_f;
  if v_nome is null then return _falha('Funcionário não encontrado.'); end if;
  if v_id is null then insert into ponto_registros (funcionario_id, entrada, saida, origem, observacao) values (v_f, v_ent, v_sai, 'dono', coalesce(v_obs, 'Lançado pelo dono'));
  else update ponto_registros set entrada = v_ent, saida = v_sai, origem = 'dono', observacao = coalesce(v_obs, observacao) where id = v_id and not cancelado;
    if not found then return _falha('Registro não encontrado.'); end if; end if;
  perform _auditar('Ponto: registro salvo', v_nome || ' | ' || v_ent || coalesce(' → ' || v_sai, ''));
  return jsonb_build_object('ok', true, 'message', 'Registro salvo.');
end $$;

-- aviso ao dono: saída esquecida (entrada aberta há mais de 14 horas)
create or replace function public.ponto_pendencias_cron() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare ativos text[] := '{}'; r record; v_chave text;
begin
  for r in select pr.id, f.nome, pr.entrada from ponto_registros pr join funcionarios f on f.id = pr.funcionario_id where pr.saida is null and not pr.cancelado and pr.entrada < now() - interval '14 hours' loop
    v_chave := 'sis:venc:ponto:' || r.id; ativos := array_append(ativos, v_chave);
    perform _alertas_sistema_avisar(v_chave, 'Ponto sem saída: ' || r.nome, r.nome || ' bateu a entrada em ' || to_char(r.entrada at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ' e não bateu a saída. Corrija em Loja e equipe → Ponto.', interval '1 day');
  end loop;
  update alertas_envios set resolvido_em = now() where tipo = 'sistema' and resolvido_em is null and chave like 'sis:venc:ponto:%' and not (chave = any(ativos));
  return jsonb_build_object('ok', true, 'pendentes', to_jsonb(ativos));
end $$;
select cron.schedule('ponto-pendencias-dia', '0 13 * * *', 'select public.ponto_pendencias_cron()');

do $$ declare f text; begin
  foreach f in array array['api_escala_avisar(jsonb)', 'api_troca_solicitar(jsonb)', 'api_troca_responder(jsonb)', 'api_troca_decidir(jsonb)', 'api_trocas_lista(jsonb)',
      'api_ponto_estado(jsonb)', 'api_ponto_bater(jsonb)', 'api_ponto_relatorio(jsonb)', 'api_ponto_ajustar(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
  revoke all on function public.ponto_pendencias_cron() from public, anon, authenticated;
end $$;


-- ======================================================================
-- 25-equipe-eventos-espaco.sql
-- ======================================================================
-- =====================================================================
-- 25 · PESO DA MÃO DE OBRA, RESERVA DE 13º/FÉRIAS, AVISO DE EVENTO A RECEBER E HISTÓRICO DO BANCO (18/10/2026)
--  1) api_equipe_peso_mao_obra: folha paga (+ encargos) de cada mês contra o faturamento do mês (vendas confirmadas + eventos), últimos 6 meses.
--  2) api_equipe_reserva: quanto já deveria estar reservado para 13º e férias de cada pessoa (estimativa; não lança nada no financeiro).
--  3) Aviso ao dono (celular e e-mail) quando um evento já passou e ainda tem valor a receber (dentro de alertas_sistema_cron).
--  4) Histórico do tamanho do banco (um registro por dia) com previsão de quando chega a 95% do plano.
-- Aditivo. Pode rodar de novo sem erro. Rode DEPOIS do 24.
-- =====================================================================

-- 1) peso da mão de obra
create or replace function public.api_equipe_peso_mao_obra(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_mes text := coalesce(nullif(p->>'mes', ''), to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')); v_ini date; v_l jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_mes !~ '^\d{4}-\d{2}$' then return _falha('Mês inválido.'); end if;
  v_ini := (v_mes || '-01')::date;
  select coalesce(jsonb_agg(x order by x->>'mes'), '[]'::jsonb) into v_l from (
    select jsonb_build_object('mes', m.mes, 'folha', m.folha, 'encargos', m.enc, 'faturamento', m.fat,
             'percentual', case when m.fat > 0 then round((m.folha + m.enc) / m.fat * 100, 1) end) x
      from (
        select to_char(d, 'YYYY-MM') mes,
          coalesce((select sum(valor) from funcionario_pagamentos fp where fp.competencia = to_char(d, 'YYYY-MM') and fp.status = 'Paga'), 0) folha,
          coalesce((select sum(encargos) from funcionario_pagamentos fp where fp.competencia = to_char(d, 'YYYY-MM') and fp.status = 'Paga'), 0) enc,
          coalesce((select sum(v.valor_total) from vendas v where v.status = 'Confirmada' and to_char(v.data_hora at time zone 'America/Sao_Paulo', 'YYYY-MM') = to_char(d, 'YYYY-MM')), 0)
          + coalesce((select sum(a.valor_total) from vendas_resumo_arquivo a where a.status = 'Confirmada' and to_char(a.data_hora at time zone 'America/Sao_Paulo', 'YYYY-MM') = to_char(d, 'YYYY-MM')), 0)
          + coalesce((select sum(e.valor_contratado) from eventos e where e.status <> 'Cancelado' and to_char(e.data, 'YYYY-MM') = to_char(d, 'YYYY-MM')), 0) fat
        from generate_series(v_ini - interval '5 months', v_ini, interval '1 month') d) m) s;
  return jsonb_build_object('ok', true, 'mes', v_mes, 'meses', v_l);
end $$;

-- 2) reserva de 13º e férias (estimativa)
create or replace function public.api_equipe_reserva(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_l jsonb; v_t13 numeric := 0; v_tf numeric := 0;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nome', q.nome, 'cargo', q.cargo, 'salario', q.salario, 'provisao', q.provisao, 'admissao', q.admissao,
      'mesesAno', q.meses_ano, 'decimoTerceiro', q.d13, 'mesesCiclo', q.ciclo, 'ferias', q.fer, 'periodosCompletos', q.periodos) order by q.nome), '[]'::jsonb),
    coalesce(sum(q.d13), 0), coalesce(sum(q.fer), 0) into v_l, v_t13, v_tf
  from (
    select f.*, m.meses_ano, round(f.salario / 12.0 * m.meses_ano, 2) d13,
           case when f.admissao is null then null else m.total % 12 end ciclo,
           case when f.admissao is null then null else round(f.salario / 12.0 * 4.0 / 3 * (m.total % 12), 2) end fer,
           case when f.admissao is null then null else m.total / 12 end periodos
      from funcionarios f
      cross join lateral (select
          least(12, greatest(0, (extract(year from v_hoje)::int * 12 + extract(month from v_hoje)::int)
             - (extract(year from greatest(coalesce(f.admissao, date_trunc('year', v_hoje)::date), date_trunc('year', v_hoje)::date))::int * 12
                + extract(month from greatest(coalesce(f.admissao, date_trunc('year', v_hoje)::date), date_trunc('year', v_hoje)::date))::int) + 1)) meses_ano,
          case when f.admissao is null then 0 else (extract(year from age(v_hoje, f.admissao))::int * 12 + extract(month from age(v_hoje, f.admissao))::int) end total) m
     where f.ativo and f.salario > 0) q;
  return jsonb_build_object('ok', true, 'pessoas', v_l, 'total13', v_t13, 'totalFerias', v_tf, 'total', v_t13 + v_tf);
end $$;

-- 3) aviso de evento já realizado com valor a receber (ajusta alertas_sistema_cron sem reescrevê-la)
do $$
declare v text;
begin
  select pg_get_functiondef('public.alertas_sistema_cron()'::regprocedure) into v;
  if v not like '%sis:evento_receber%' then
    v := replace(v, $q$select max(data_hora) into v_t from backups where status = 'ok';$q$,
      $q$for r in select e.id, e.nome, e.data, e.valor_a_receber from eventos e where e.status in ('Confirmado', 'Em andamento', 'Concluído') and e.valor_a_receber > 0.004 and e.data < (now() at time zone 'America/Sao_Paulo')::date loop
    ativos := array_append(ativos, ('sis:evento_receber:' || r.id)::text);
    perform _alertas_sistema_avisar('sis:evento_receber:' || r.id, 'Evento com valor a receber: ' || r.nome, 'O evento "' || r.nome || '" de ' || to_char(r.data, 'DD/MM') || ' já passou e ainda faltam R$ ' || _dinheiro(r.valor_a_receber) || ' a receber. Administrador → Vendas e cardápio → Eventos → Recebimentos.', interval '1 day');
  end loop;
  select max(data_hora) into v_t from backups where status = 'ok';$q$);
    execute v;
  end if;
end $$;

-- 4) histórico do tamanho do banco
create table if not exists public.espaco_historico (
  dia date primary key,
  db_bytes bigint not null,
  vendas_ativas integer
);
alter table public.espaco_historico enable row level security;
revoke all on public.espaco_historico from anon, authenticated;
grant all on public.espaco_historico to service_role;
create or replace function public._espaco_snapshot() returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  insert into espaco_historico (dia, db_bytes, vendas_ativas) values ((now() at time zone 'America/Sao_Paulo')::date, pg_database_size(current_database()), (select count(*) from vendas))
  on conflict (dia) do update set db_bytes = excluded.db_bytes, vendas_ativas = excluded.vendas_ativas;
end $$;
revoke all on function public._espaco_snapshot() from public, anon, authenticated;
select public._espaco_snapshot();
select cron.schedule('espaco-snapshot-dia', '5 7 * * *', 'select public._espaco_snapshot()');

create or replace function public.api_espaco_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_lim numeric := _limite_banco_mb(); v_atual numeric := pg_database_size(current_database()) / 1048576.0; v_n int; v_slope numeric; v_meses jsonb; v_dias jsonb; v_prev numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _espaco_snapshot();
  select coalesce(jsonb_agg(jsonb_build_object('mes', mes, 'mb', mb) order by mes), '[]'::jsonb) into v_meses
    from (select to_char(dia, 'YYYY-MM') mes, round(max(db_bytes) / 1048576.0, 1) mb from espaco_historico where dia >= date_trunc('month', current_date) - interval '11 months' group by 1) m;
  select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'mb', round(db_bytes / 1048576.0, 1)) order by dia), '[]'::jsonb) into v_dias from espaco_historico where dia >= current_date - 29;
  select count(*), regr_slope(db_bytes::double precision, extract(epoch from dia::timestamp)::double precision) * 86400 / 1048576.0 into v_n, v_slope from espaco_historico where dia >= current_date - 44;
  if v_n >= 5 and v_slope is not null and v_slope > 0.0001 then v_prev := greatest(0, (v_lim * 0.95 - v_atual) / v_slope); end if;
  return jsonb_build_object('ok', true, 'limiteMb', v_lim, 'atualMb', round(v_atual, 1), 'meses', v_meses, 'dias', v_dias, 'pontos', v_n,
    'crescimentoMbDia', case when v_n >= 5 then round(v_slope, 3) end, 'diasAte95', case when v_prev is not null then floor(v_prev) end);
end $$;
revoke all on function public.api_espaco_historico(jsonb) from public;
grant execute on function public.api_espaco_historico(jsonb) to authenticated, service_role;
do $$ declare f text; begin
  foreach f in array array['api_equipe_peso_mao_obra(jsonb)', 'api_equipe_reserva(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
end $$;


-- ======================================================================
-- 26-gestao-margem-estoque-eventos.sql
-- ======================================================================
-- =====================================================================
-- 26 · MARGEM, HISTÓRICO DE PREÇOS, COMPRA SUGERIDA, CONTAS NA VÉSPERA E RENDIMENTO DE EVENTOS (18/10/2026)
--  1) preco_historico: todo preço/custo que muda em produto_precos fica registrado (quem, quando, antes e depois) + api_preco_historico.
--  2) api_margem_alerta / api_margem_config_salvar: produtos com margem abaixo do mínimo que o dono define, com preço sugerido; aviso semanal no celular.
--  3) api_estoque_sugestao: ingredientes no mínimo ou abaixo, com quantidade sugerida, fornecedor habitual e custo estimado.
--  4) Aviso de contas a pagar que vencem amanhã, hoje ou já venceram (dentro de alertas_sistema_cron).
--  5) Eventos: horas da equipe (manual ou pelo ponto) e rendimento por hora (api_evento_horas_salvar, api_evento_rendimento).
-- Aditivo. Pode rodar de novo sem erro. Rode DEPOIS do 25.
-- =====================================================================

-- 1) histórico de preços
create table if not exists public.preco_historico (
  id uuid primary key default gen_random_uuid(),
  produto_id uuid not null,
  forma_pagamento_id uuid,
  preco_antigo numeric(10,2),
  preco_novo numeric(10,2),
  custo_antigo numeric(10,2),
  custo_novo numeric(10,2),
  usuario_login text,
  quando timestamptz not null default now()
);
create index if not exists preco_historico_quando_idx on public.preco_historico (quando desc);
create index if not exists preco_historico_prod_idx on public.preco_historico (produto_id, quando desc);
alter table public.preco_historico enable row level security;

create or replace function public._preco_historico_gravar() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_login text;
begin
  if tg_op = 'UPDATE' and new.preco is not distinct from old.preco and new.custo is not distinct from old.custo then return new; end if;
  select u.login into v_login from usuarios u where u.id = auth.uid();
  insert into preco_historico (produto_id, forma_pagamento_id, preco_antigo, preco_novo, custo_antigo, custo_novo, usuario_login)
  values (new.produto_id, new.forma_pagamento_id, case when tg_op = 'UPDATE' then old.preco end, new.preco, case when tg_op = 'UPDATE' then old.custo end, new.custo, coalesce(v_login, 'sistema'));
  return new;
end $$;
create or replace trigger produto_precos_historico after insert or update on public.produto_precos for each row execute function public._preco_historico_gravar();

create or replace function public.api_preco_historico(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_busca text := nullif(btrim(coalesce(p->>'busca', '')), ''); v_lim int := least(greatest(coalesce(nullif(p->>'limite', '')::int, 100), 1), 500); v_l jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(x order by (x->>'quando') desc), '[]'::jsonb) into v_l from (
    select jsonb_build_object('quando', h.quando, 'produto', pr.nome, 'forma', f.nome, 'precoAntigo', h.preco_antigo, 'precoNovo', h.preco_novo,
             'custoAntigo', h.custo_antigo, 'custoNovo', h.custo_novo, 'usuario', h.usuario_login,
             'percentual', case when coalesce(h.preco_antigo, 0) > 0 and h.preco_novo is not null then round((h.preco_novo - h.preco_antigo) / h.preco_antigo * 100, 1) end) x
      from preco_historico h join produtos pr on pr.id = h.produto_id left join formas_pagamento f on f.id = h.forma_pagamento_id
     where h.preco_antigo is not null and (v_busca is null or pr.nome ilike '%' || v_busca || '%')
     order by h.quando desc limit v_lim) s;
  return jsonb_build_object('ok', true, 'itens', v_l);
end $$;

-- 2) margem mínima
create or replace function public._margem_minima() returns numeric language sql stable security definer set search_path to 'public' as $$
  select coalesce((select (valor #>> '{}')::numeric from sistema where chave = 'MARGEM_MINIMA'), 50)
$$;

create or replace function public._margem_baixa() returns table (produto_id uuid, nome text, forma text, preco numeric, custo numeric, margem numeric, sugerido numeric)
language sql stable security definer set search_path to 'public' as $$
  select distinct on (pr.id) pr.id, pr.nome, f.nome, pp.preco, pp.custo,
         round((pp.preco - pp.custo) / pp.preco * 100, 1),
         ceil(pp.custo / (1 - _margem_minima() / 100.0) * 10) / 10
    from produtos pr join produto_precos pp on pp.produto_id = pr.id left join formas_pagamento f on f.id = pp.forma_pagamento_id
   where pr.ativo and pp.preco > 0 and pp.custo > 0 and (pp.preco - pp.custo) / pp.preco * 100 < _margem_minima()
   order by pr.id, (pp.preco - pp.custo) / pp.preco
$$;

create or replace function public.api_margem_alerta(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_l jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', m.produto_id, 'nome', m.nome, 'forma', m.forma, 'preco', m.preco, 'custo', m.custo, 'margem', m.margem, 'sugerido', m.sugerido) order by m.margem), '[]'::jsonb) into v_l from _margem_baixa() m;
  return jsonb_build_object('ok', true, 'margemMin', _margem_minima(), 'itens', v_l);
end $$;

create or replace function public.api_margem_config_salvar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v numeric := _num(p->>'margemMin', -1);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v < 1 or v > 95 then return _falha('Informe uma margem mínima entre 1% e 95%.'); end if;
  insert into sistema (chave, valor, atualizado_em) values ('MARGEM_MINIMA', to_jsonb(v), now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('Margem mínima alterada', v || '%');
  return jsonb_build_object('ok', true, 'margemMin', v, 'message', 'Margem mínima de ' || replace(v::text, '.', ',') || '% salva.');
end $$;

-- 3) compra sugerida
create or replace function public.api_estoque_sugestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_l jsonb;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nome', q.ingrediente, 'unidade', q.un, 'atual', q.quantidade, 'minimo', q.quantidade_minima,
           'sugerido', q.sug, 'custoEstimado', round(q.sug * coalesce(q.custo_unitario, 0), 2),
           'fornecedorId', q.forn_id, 'fornecedor', q.forn, 'telefone', q.fone) order by coalesce(q.forn, 'zzz'), q.ingrediente), '[]'::jsonb) into v_l
  from (
    select e.id, e.ingrediente, e.unidade::text un, e.quantidade, e.quantidade_minima, e.custo_unitario,
           round(greatest(e.quantidade_minima * 2 - e.quantidade, e.quantidade_minima), 2) sug,
           ult.forn_id, ult.forn, ult.fone
      from estoque e
      left join lateral (select fo.id forn_id, fo.nome forn, fo.telefone fone from compra_itens ci join compras c on c.id = ci.compra_id join fornecedores fo on fo.id = c.fornecedor_id
                          where ci.ingrediente_id = e.id and c.status = 'Recebida' order by c.data desc, c.criado_em desc limit 1) ult on true
     where e.status = 'Ativo' and e.quantidade_minima > 0 and e.quantidade <= e.quantidade_minima) q;
  return jsonb_build_object('ok', true, 'itens', v_l);
end $$;

-- 5) eventos: horas da equipe e rendimento por hora
alter table public.eventos add column if not exists horas_equipe numeric(6,2);

create or replace function public.api_evento_horas_salvar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_h numeric := case when coalesce(p->>'horas', '') = '' then null else _num(p->>'horas') end;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_h is not null and (v_h < 0 or v_h > 999) then return _falha('Horas inválidas.'); end if;
  update eventos set horas_equipe = v_h where id = v_id;
  if not found then return _falha('Evento não encontrado.'); end if;
  return jsonb_build_object('ok', true, 'message', case when v_h is null then 'Voltou a usar as horas do ponto.' else 'Horas da equipe salvas.' end);
end $$;

create or replace function public.api_evento_rendimento(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_l jsonb; v_fat numeric; v_h numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(x order by (x->>'data') desc), '[]'::jsonb) into v_l from (
    select jsonb_build_object('id', e.id, 'nome', e.nome, 'data', e.data, 'contratado', e.valor_contratado, 'resultado', e.resultado,
             'horas', h.horas, 'fonte', h.fonte,
             'resultadoHora', case when h.horas > 0 then round(e.resultado / h.horas, 2) end,
             'contratadoHora', case when h.horas > 0 then round(e.valor_contratado / h.horas, 2) end) x
      from eventos e
      cross join lateral (select coalesce(e.horas_equipe, nullif(pt.h, 0)) horas, case when e.horas_equipe is not null then 'manual' when coalesce(pt.h, 0) > 0 then 'ponto' end fonte
                            from (select sum(extract(epoch from (r.saida - r.entrada)) / 3600.0) h from ponto_registros r
                                   where not r.cancelado and r.saida is not null and (r.entrada at time zone 'America/Sao_Paulo')::date = e.data) pt) h
     where e.status in ('Confirmado', 'Em andamento', 'Concluído') and e.data <= v_hoje and e.data >= v_hoje - 365) s;
  -- referência: faturamento por hora trabalhada nos dias normais (sem evento) dos últimos 60 dias
  select coalesce(sum(r.h), 0) into v_h from (
    select sum(extract(epoch from (pr.saida - pr.entrada)) / 3600.0) h from ponto_registros pr
     where not pr.cancelado and pr.saida is not null and (pr.entrada at time zone 'America/Sao_Paulo')::date >= v_hoje - 60
       and not exists (select 1 from eventos e where e.data = (pr.entrada at time zone 'America/Sao_Paulo')::date and e.status <> 'Cancelado')) r;
  select coalesce(sum(v.valor_total), 0) into v_fat from vendas v
   where v.status = 'Confirmada' and (v.data_hora at time zone 'America/Sao_Paulo')::date >= v_hoje - 60
     and exists (select 1 from ponto_registros pr where not pr.cancelado and pr.saida is not null and (pr.entrada at time zone 'America/Sao_Paulo')::date = (v.data_hora at time zone 'America/Sao_Paulo')::date)
     and not exists (select 1 from eventos e where e.data = (v.data_hora at time zone 'America/Sao_Paulo')::date and e.status <> 'Cancelado');
  return jsonb_build_object('ok', true, 'eventos', v_l, 'horasNormais', round(v_h, 1), 'faturamentoHoraNormal', case when v_h > 0 then round(v_fat / v_h, 2) end);
end $$;

-- 2b + 4) avisos no celular: margem baixa (1x por semana) e contas a pagar (véspera, hoje, vencidas)
do $$
declare v text;
begin
  select pg_get_functiondef('public.alertas_sistema_cron()'::regprocedure) into v;
  if v not like '%sis:contas_amanha%' then
    v := replace(v, $q$select max(data_hora) into v_t from backups where status = 'ok';$q$,
      $q$declare v_c int; v_s numeric; v_hj date := (now() at time zone 'America/Sao_Paulo')::date;
  begin
    select count(*), coalesce(sum(valor), 0) into v_c, v_s from despesas where status = 'A pagar' and situacao = 'A pagar' and vencimento < v_hj;
    if v_c > 0 then ativos := array_append(ativos, 'sis:contas_vencidas'::text);
      perform _alertas_sistema_avisar('sis:contas_vencidas', v_c || ' conta(s) a pagar vencida(s)', 'Total de R$ ' || _dinheiro(v_s) || ' já passou do vencimento. Administrador → Dinheiro → Contas a pagar.', interval '12 hours'); end if;
    select count(*), coalesce(sum(valor), 0) into v_c, v_s from despesas where status = 'A pagar' and situacao = 'A pagar' and vencimento = v_hj;
    if v_c > 0 then ativos := array_append(ativos, 'sis:contas_hoje'::text);
      perform _alertas_sistema_avisar('sis:contas_hoje', v_c || ' conta(s) vence(m) hoje', 'Total de R$ ' || _dinheiro(v_s) || ' para pagar hoje. Administrador → Dinheiro → Contas a pagar.', interval '12 hours'); end if;
    select count(*), coalesce(sum(valor), 0) into v_c, v_s from despesas where status = 'A pagar' and situacao = 'A pagar' and vencimento = v_hj + 1;
    if v_c > 0 then ativos := array_append(ativos, ('sis:contas_amanha:' || (v_hj + 1))::text);
      perform _alertas_sistema_avisar('sis:contas_amanha:' || (v_hj + 1), v_c || ' conta(s) vence(m) amanhã', 'Total de R$ ' || _dinheiro(v_s) || ' vence amanhã. Administrador → Dinheiro → Contas a pagar.', interval '1 day'); end if;
    select count(*) into v_c from _margem_baixa();
    if v_c > 0 then ativos := array_append(ativos, 'sis:margem'::text);
      perform _alertas_sistema_avisar('sis:margem', v_c || ' produto(s) com margem baixa', 'Estão abaixo de ' || replace(_margem_minima()::text, '.', ',') || '% de margem. Administrador → Produtos → Margem baixa mostra o preço sugerido.', interval '7 days'); end if;
  end;
  select max(data_hora) into v_t from backups where status = 'ok';$q$);
    execute v;
  end if;
end $$;


-- ======================================================================
-- 27-margem-por-categoria.sql
-- ======================================================================
-- =====================================================================
-- 27 · MARGEM BAIXA MAIS INTELIGENTE (18/10/2026)
--  1) Margem mínima por categoria (ex.: Bebidas 25%) além da geral; produto pode ser ignorado (e voltar a ser vigiado).
--  2) O aviso no celular só toca quando entra produto NOVO abaixo do mínimo (não repete toda semana).
--  3) Repetição dos avisos novos: margem nunca repete; evento a receber e contas na véspera 1x por dia; contas do dia e vencidas a cada 6 h.
-- Aditivo. Pode rodar de novo sem erro. Rode DEPOIS do 26.
-- =====================================================================

create or replace function public._margem_min_cat(p_cat uuid) returns numeric language sql stable security definer set search_path to 'public' as $$
  select coalesce(nullif((select valor ->> p_cat::text from sistema where chave = 'MARGEM_POR_CATEGORIA'), '')::numeric, _margem_minima())
$$;

create or replace function public._margem_baixa() returns table (produto_id uuid, nome text, forma text, preco numeric, custo numeric, margem numeric, sugerido numeric)
language sql stable security definer set search_path to 'public' as $$
  select distinct on (pr.id) pr.id, pr.nome, f.nome, pp.preco, pp.custo,
         round((pp.preco - pp.custo) / pp.preco * 100, 1),
         ceil(pp.custo / (1 - _margem_min_cat(pr.categoria_id) / 100.0) * 10) / 10
    from produtos pr join produto_precos pp on pp.produto_id = pr.id left join formas_pagamento f on f.id = pp.forma_pagamento_id
   where pr.ativo and pp.preco > 0 and pp.custo > 0 and (pp.preco - pp.custo) / pp.preco * 100 < _margem_min_cat(pr.categoria_id)
     and not coalesce((select valor @> jsonb_build_array(pr.id::text) from sistema where chave = 'MARGEM_IGNORADOS'), false)
   order by pr.id, (pp.preco - pp.custo) / pp.preco
$$;

create or replace function public.api_margem_alerta(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_l jsonb; v_c jsonb; v_i jsonb; v_cfg jsonb := coalesce((select valor from sistema where chave = 'MARGEM_POR_CATEGORIA'), '{}'::jsonb);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', m.produto_id, 'nome', m.nome, 'forma', m.forma, 'preco', m.preco, 'custo', m.custo, 'margem', m.margem, 'sugerido', m.sugerido,
           'categoria', c.nome, 'minimo', _margem_min_cat(pr.categoria_id)) order by m.margem), '[]'::jsonb) into v_l
    from _margem_baixa() m join produtos pr on pr.id = m.produto_id left join categorias c on c.id = pr.categoria_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'minimo', nullif(v_cfg ->> c.id::text, '')::numeric) order by c.ordem, c.nome), '[]'::jsonb) into v_c from categorias c where c.ativa;
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', pr.id, 'nome', pr.nome) order by pr.nome), '[]'::jsonb) into v_i
    from produtos pr where coalesce((select valor @> jsonb_build_array(pr.id::text) from sistema where chave = 'MARGEM_IGNORADOS'), false);
  return jsonb_build_object('ok', true, 'margemMin', _margem_minima(), 'itens', v_l, 'categorias', v_c, 'ignorados', v_i);
end $$;

create or replace function public.api_margem_config_salvar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v numeric; r record; v_cats jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'margemMin', '') <> '' then
    v := _num(p->>'margemMin', -1);
    if v < 1 or v > 95 then return _falha('Informe uma margem mínima entre 1% e 95%.'); end if;
    insert into sistema (chave, valor, atualizado_em) values ('MARGEM_MINIMA', to_jsonb(v), now())
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  end if;
  if jsonb_typeof(p->'categorias') = 'object' then
    v_cats := coalesce((select valor from sistema where chave = 'MARGEM_POR_CATEGORIA'), '{}'::jsonb);
    for r in select key, value from jsonb_each(p->'categorias') loop
      if r.value = 'null'::jsonb or coalesce(r.value #>> '{}', '') = '' then v_cats := v_cats - r.key;
      else
        v := _num(r.value #>> '{}', -1);
        if v < 1 or v > 95 then return _falha('Cada margem mínima deve ficar entre 1% e 95%.'); end if;
        v_cats := v_cats || jsonb_build_object(r.key, v);
      end if;
    end loop;
    insert into sistema (chave, valor, atualizado_em) values ('MARGEM_POR_CATEGORIA', v_cats, now())
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  end if;
  perform _auditar('Margem mínima alterada', left(coalesce(p::text, ''), 300));
  return jsonb_build_object('ok', true, 'message', 'Margens mínimas salvas.');
end $$;

create or replace function public.api_margem_ignorar(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_id text := p->>'produtoId'; v_ign boolean := coalesce((p->>'ignorar')::boolean, true); v_l jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from produtos where id::text = v_id) then return _falha('Produto não encontrado.'); end if;
  v_l := coalesce((select valor from sistema where chave = 'MARGEM_IGNORADOS'), '[]'::jsonb);
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_l from jsonb_array_elements(v_l) x where x #>> '{}' <> v_id;
  if v_ign then v_l := v_l || jsonb_build_array(v_id); end if;
  insert into sistema (chave, valor, atualizado_em) values ('MARGEM_IGNORADOS', v_l, now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar(case when v_ign then 'Produto ignorado na margem baixa' else 'Produto voltou à margem baixa' end, v_id);
  return jsonb_build_object('ok', true, 'message', case when v_ign then 'Produto não será mais avisado.' else 'Produto voltou a ser vigiado.' end);
end $$;

-- repetição dos avisos novos (a função usa o intervalo geral para os demais)
do $$
declare v text;
begin
  select pg_get_functiondef('public._alertas_sistema_avisar(text,text,text,interval)'::regprocedure) into v;
  if v not like '%sis:margem:%' then
    v := replace(v, $q$if p_chave like 'sis:venc:%' then$q$,
      $q$if p_chave like 'sis:margem:%' then v_rep := interval '3650 days';
  elsif p_chave like 'sis:contas_amanha:%' or p_chave like 'sis:evento_receber:%' then v_rep := interval '1 day';
  elsif p_chave like 'sis:contas_%' then v_rep := interval '6 hours';
  end if;
  if p_chave like 'sis:venc:%' then$q$);
    if v not like '%sis:margem:%' then raise exception 'Não foi possível ajustar _alertas_sistema_avisar'; end if;
    execute v;
  end if;
end $$;

-- aviso de margem só para produto novo na lista
do $$
declare v text;
begin
  select pg_get_functiondef('public.alertas_sistema_cron()'::regprocedure) into v;
  if v not like '%MARGEM_AVISADOS%' then
    v := replace(v, $q$select count(*) into v_c from _margem_baixa();
    if v_c > 0 then ativos := array_append(ativos, 'sis:margem'::text);
      perform _alertas_sistema_avisar('sis:margem', v_c || ' produto(s) com margem baixa', 'Estão abaixo de ' || replace(_margem_minima()::text, '.', ',') || '% de margem. Administrador → Produtos → Margem baixa mostra o preço sugerido.', interval '7 days'); end if;$q$,
      $q$declare v_ids jsonb; v_old jsonb; v_novos jsonb; v_nomes text;
    begin
      select coalesce(jsonb_agg(produto_id order by produto_id), '[]'::jsonb) into v_ids from _margem_baixa();
      v_old := coalesce((select valor from sistema where chave = 'MARGEM_AVISADOS'), '[]'::jsonb);
      select coalesce(jsonb_agg(x), '[]'::jsonb) into v_novos from jsonb_array_elements(v_ids) x where not (v_old @> jsonb_build_array(x));
      v_c := jsonb_array_length(v_novos);
      if v_c > 0 then
        select string_agg(nome, ', ') into v_nomes from (select m.nome from _margem_baixa() m where v_novos @> jsonb_build_array(to_jsonb(m.produto_id)) order by m.nome limit 3) q;
        ativos := array_append(ativos, ('sis:margem:' || md5(v_novos::text))::text);
        perform _alertas_sistema_avisar('sis:margem:' || md5(v_novos::text), v_c || ' produto(s) com margem baixa', v_nomes || (case when v_c > 3 then ' e mais ' || (v_c - 3) else '' end) || ' ficou(aram) abaixo da margem mínima. Administrador → Produtos → Margem baixa mostra o preço sugerido.', interval '3650 days');
      end if;
      insert into sistema (chave, valor, atualizado_em) values ('MARGEM_AVISADOS', v_ids, now()) on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    end;$q$);
    if v not like '%MARGEM_AVISADOS%' then raise exception 'Não foi possível ajustar alertas_sistema_cron'; end if;
    execute v;
  end if;
end $$;

-- ponto de partida: Bebidas com mínimo próprio de 25% (o dono ajusta na tela) e lista atual já considerada "avisada" (sem aviso na hora de instalar)
do $$
declare v_b uuid;
begin
  select id into v_b from categorias where nome = 'Bebidas' limit 1;
  if v_b is not null then
    insert into sistema (chave, valor, atualizado_em) values ('MARGEM_POR_CATEGORIA', jsonb_build_object(v_b::text, 25), now()) on conflict (chave) do nothing;
  end if;
  insert into sistema (chave, valor, atualizado_em)
    select 'MARGEM_AVISADOS', coalesce(jsonb_agg(produto_id order by produto_id), '[]'::jsonb), now() from _margem_baixa()
    on conflict (chave) do nothing;
end $$;


-- ======================================================================
-- 28-margem-sugestao.sql
-- ======================================================================
-- =====================================================================
-- 28 · MARGEM POR CATEGORIA PRÉ-PREENCHIDA PELOS PREÇOS ATUAIS (18/10/2026)
--  api_margem_sugestao: para cada categoria, a pior margem hoje e um mínimo sugerido (5 pontos abaixo, em múltiplos de 5),
--  para o aviso só tocar se um produto ficar pior do que o dono já pratica. Botão "Preencher pelos meus preços atuais" usa isso.
--  Também preenche agora a configuração (só categorias que o dono ainda não definiu).
-- Aditivo. Pode rodar de novo sem erro. Rode DEPOIS do 27.
-- =====================================================================
create or replace function public._margem_pior_por_categoria() returns table (categoria_id uuid, nome text, pior numeric, sugerido numeric)
language sql stable security definer set search_path to 'public' as $$
  select c.id, c.nome, round(min(m.margem), 1), greatest(1, floor((min(m.margem) - 5) / 5) * 5)
    from categorias c
    join (select distinct on (pr.id) pr.id, pr.categoria_id, (pp.preco - pp.custo) / pp.preco * 100 margem
            from produtos pr join produto_precos pp on pp.produto_id = pr.id
           where pr.ativo and pp.preco > 0 and pp.custo > 0 order by pr.id, (pp.preco - pp.custo) / pp.preco) m on m.categoria_id = c.id
   where c.ativa group by c.id, c.nome
$$;

create or replace function public.api_margem_sugestao(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_l jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', categoria_id, 'nome', nome, 'pior', pior, 'sugerido', sugerido) order by nome), '[]'::jsonb) into v_l from _margem_pior_por_categoria();
  return jsonb_build_object('ok', true, 'categorias', v_l);
end $$;

do $$
declare v_cfg jsonb; r record;
begin
  v_cfg := coalesce((select valor from sistema where chave = 'MARGEM_POR_CATEGORIA'), '{}'::jsonb);
  -- a pré-configuração anterior (só Bebidas = 25) é substituída pelos valores calculados dos preços atuais
  if v_cfg = jsonb_build_object(coalesce((select id::text from categorias where nome = 'Bebidas' limit 1), '-'), 25) then v_cfg := '{}'::jsonb; end if;
  for r in select * from _margem_pior_por_categoria() loop
    if not (v_cfg ? r.categoria_id::text) then v_cfg := v_cfg || jsonb_build_object(r.categoria_id::text, r.sugerido); end if;
  end loop;
  insert into sistema (chave, valor, atualizado_em) values ('MARGEM_POR_CATEGORIA', v_cfg, now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  insert into sistema (chave, valor, atualizado_em) select 'MARGEM_AVISADOS', coalesce(jsonb_agg(produto_id order by produto_id), '[]'::jsonb), now() from _margem_baixa()
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
end $$;


-- ======================================================================
-- 29-ponto-localizacao.sql
-- ======================================================================
-- 29 · Ponto com localização (18/10/2026)
-- O funcionário só bate o ponto se estiver perto do restaurante. O dono define o local em Administrador > Loja e equipe > Ponto.
-- Chave em "sistema": PONTO_LOCAL = {"lat":..,"lng":..,"raio":150}. Sem essa chave, o ponto funciona como antes (só guarda a localização, se vier).

alter table ponto_registros add column if not exists lat double precision;
alter table ponto_registros add column if not exists lng double precision;
alter table ponto_registros add column if not exists dist_m integer;
alter table ponto_registros add column if not exists saida_dist_m integer;

create or replace function _dist_metros(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(least(1, sqrt(power(sin(radians(b_lat - a_lat) / 2), 2) + cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2))))
$$;

create or replace function api_ponto_local(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_lat double precision; v_lng double precision; v_raio int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'desligar', '') = 'true' then
    insert into sistema (chave, valor) values ('PONTO_LOCAL', 'null'::jsonb) on conflict (chave) do update set valor = excluded.valor;
    perform _auditar('Ponto: trava por localização desligada', '');
    return jsonb_build_object('ok', true, 'message', 'Trava por localização desligada.');
  end if;
  if nullif(p->>'lat', '') is not null then
    begin v_lat := (p->>'lat')::double precision; v_lng := (p->>'lng')::double precision; v_raio := coalesce(nullif(p->>'raio', '')::int, 150);
    exception when others then return _falha('Localização inválida.'); end;
    if v_lat not between -90 and 90 or v_lng not between -180 and 180 then return _falha('Localização inválida.'); end if;
    if v_raio < 30 or v_raio > 2000 then return _falha('O raio precisa ficar entre 30 e 2000 metros.'); end if;
    insert into sistema (chave, valor) values ('PONTO_LOCAL', jsonb_build_object('lat', v_lat, 'lng', v_lng, 'raio', v_raio))
      on conflict (chave) do update set valor = excluded.valor;
    perform _auditar('Ponto: local do restaurante definido', 'raio ' || v_raio || ' m');
    return jsonb_build_object('ok', true, 'message', 'Local salvo. O ponto só vale a até ' || v_raio || ' m daqui.');
  end if;
  select (valor->>'lat')::double precision, (valor->>'lng')::double precision, (valor->>'raio')::int into v_lat, v_lng, v_raio from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  return jsonb_build_object('ok', true, 'definido', v_lat is not null, 'raio', v_raio);
end $$;

create or replace function api_ponto_estado(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_ini date; v_h numeric;
        v_exige boolean := exists (select 1 from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object');
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return jsonb_build_object('ok', true, 'vinculado', false); end if;
  v_ini := _escala_segunda(v_hoje);
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  select coalesce(round(sum(extract(epoch from coalesce(saida, now()) - entrada)) / 3600.0, 2), 0) into v_h from ponto_registros
   where funcionario_id = v_eu and not cancelado and (entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_ini + 6;
  return jsonb_build_object('ok', true, 'vinculado', true, 'aberto', r.id is not null, 'entrada', r.entrada, 'horasSemana', v_h, 'exigeLocal', v_exige);
end $$;

create or replace function api_ponto_bater(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype; v_cfg jsonb; v_lat double precision; v_lng double precision; v_prec double precision; v_dist double precision; v_d int; v_raio int; v_nome text;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return _falha('Seu acesso ainda não está ligado a um funcionário. Peça ao dono para usar "Importar acessos" na Escala.'); end if;
  begin v_lat := nullif(p->>'lat', '')::double precision; v_lng := nullif(p->>'lng', '')::double precision; v_prec := coalesce(nullif(p->>'precisao', '')::double precision, 0);
  exception when others then v_lat := null; v_lng := null; end;
  select valor into v_cfg from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  if v_lat is not null and v_lng is not null and v_cfg is not null then
    v_dist := _dist_metros(v_lat, v_lng, (v_cfg->>'lat')::double precision, (v_cfg->>'lng')::double precision);
    v_d := round(v_dist);
  end if;
  if v_cfg is not null then
    v_raio := coalesce((v_cfg->>'raio')::int, 150);
    if v_lat is null or v_lng is null then
      return _falha('Para bater o ponto, ative a localização do celular e permita o acesso do navegador a ela. Depois tente de novo.');
    end if;
    if v_dist - least(v_prec, 100) > v_raio then
      select nome into v_nome from funcionarios where id = v_eu;
      perform _auditar('Ponto bloqueado: fora do restaurante', coalesce(v_nome, '') || ' | a ' || v_d || ' m');
      return _falha('Você está a cerca de ' || case when v_d >= 1000 then to_char(round(v_d / 1000.0, 1), 'FM990.0') || ' km' else v_d || ' m' end || ' do restaurante. O ponto só pode ser batido no local.');
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtext('ponto:' || v_eu));
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  if r.id is not null and r.entrada > now() - interval '20 seconds' then return jsonb_build_object('ok', true, 'message', 'Já registrado agora há pouco.', 'aberto', true); end if;
  if r.id is not null and r.entrada > now() - interval '20 hours' then
    update ponto_registros set saida = now(), saida_dist_m = v_d where id = r.id;
    return jsonb_build_object('ok', true, 'aberto', false, 'message', 'Saída registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '. Trabalhou ' || to_char(round(extract(epoch from now() - r.entrada) / 3600.0, 2), 'FM990.00') || ' h neste turno.');
  end if;
  insert into ponto_registros (funcionario_id, entrada, lat, lng, dist_m) values (v_eu, now(), v_lat, v_lng, v_d);
  return jsonb_build_object('ok', true, 'aberto', true, 'message', 'Entrada registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '.' || case when r.id is not null then ' (A saída anterior ficou sem registro; o dono pode corrigir.)' else '' end);
end $$;

create or replace function api_ponto_relatorio(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ini date := coalesce(nullif(p->>'inicio', '')::date, _escala_segunda((now() at time zone 'America/Sao_Paulo')::date)); v_fim date := coalesce(nullif(p->>'fim', '')::date, v_ini + 6); v_l jsonb; v_loc jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_fim < v_ini or v_fim - v_ini > 62 then return _falha('Período inválido (máximo de 62 dias).'); end if;
  select jsonb_build_object('definido', true, 'raio', (valor->>'raio')::int) into v_loc from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  with reg as (
    select r.funcionario_id, r.id, r.entrada, r.saida, r.observacao, r.origem, r.dist_m, r.saida_dist_m, (r.entrada at time zone 'America/Sao_Paulo')::date dia,
           extract(epoch from coalesce(r.saida, now()) - r.entrada) / 3600.0 h
      from ponto_registros r where not r.cancelado and (r.entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_fim),
  sem as (select funcionario_id, _escala_segunda(dia) semana, sum(h) h from reg group by 1, 2),
  extra as (select funcionario_id, sum(greatest(h - 44, 0)) ex from sem group by 1),
  esc as (select t.funcionario_id, sum(extract(epoch from (t.data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end) - (t.data + t.inicio)) / 3600.0) h
            from escala_turnos t where t.tipo = 'Trabalho' and not t.cancelado and t.data between v_ini and v_fim group by 1),
  tot as (select funcionario_id, sum(h) h from reg group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('funcionarioId', f.id, 'nome', f.nome, 'cargo', f.cargo,
      'horasFeitas', round(coalesce(tot.h, 0)::numeric, 2), 'horasEscaladas', round(coalesce(esc.h, 0)::numeric, 2),
      'diferenca', round((coalesce(tot.h, 0) - coalesce(esc.h, 0))::numeric, 2), 'horasExtras', round(coalesce(extra.ex, 0)::numeric, 2),
      'aberto', exists (select 1 from reg where reg.funcionario_id = f.id and reg.saida is null),
      'registros', coalesce((select jsonb_agg(jsonb_build_object('id', reg.id, 'dia', reg.dia, 'entrada', to_char(reg.entrada at time zone 'America/Sao_Paulo', 'HH24:MI'), 'saida', to_char(reg.saida at time zone 'America/Sao_Paulo', 'HH24:MI'),
          'horas', round(reg.h::numeric, 2), 'origem', reg.origem, 'observacao', reg.observacao, 'distEntrada', reg.dist_m, 'distSaida', reg.saida_dist_m) order by reg.entrada) from reg where reg.funcionario_id = f.id), '[]'::jsonb)
    ) order by f.nome), '[]'::jsonb) into v_l
    from funcionarios f left join tot on tot.funcionario_id = f.id left join esc on esc.funcionario_id = f.id left join extra on extra.funcionario_id = f.id
   where f.ativo or tot.h is not null;
  return jsonb_build_object('ok', true, 'inicio', v_ini, 'fim', v_fim, 'pessoas', v_l, 'local', coalesce(v_loc, jsonb_build_object('definido', false)));
end $$;


-- ======================================================================
-- 30-ponto-rosto.sql
-- ======================================================================
-- 30 · Ponto com reconhecimento facial e foto da batida (18/10/2026)
-- • O "código do rosto" (128 números, não é foto) é gravado na PRIMEIRA batida do funcionário, com o aceite (LGPD).
-- • A comparação é feita aqui no banco. Rosto confere = batida normal. Não confere = o funcionário pode mandar a selfie e a batida
--   fica marcada "pendente" para o dono aprovar ou cancelar (Administrador > Loja e equipe > Ponto).
-- • A foto de cada batida vai para o Drive principal e para o da contingência (pasta privada) e é apagada após 45 dias
--   (rotina diária ponto-fotos-45-dias, que chama a Edge Function ponto-foto com a ação "limpar").
-- • Chave em "sistema": PONTO_ROSTO = {"ligado":true,"limite":0.55}. Sem a chave vale ligado = true.

create table if not exists public.ponto_rosto (
  funcionario_id uuid primary key,
  descritor double precision[] not null,
  consentimento_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.ponto_rosto enable row level security;
revoke all on public.ponto_rosto from anon, authenticated;
grant all on public.ponto_rosto to service_role;

alter table public.ponto_registros add column if not exists rosto_ent text;
alter table public.ponto_registros add column if not exists rosto_sai text;
alter table public.ponto_registros add column if not exists rosto_dist_ent real;
alter table public.ponto_registros add column if not exists rosto_dist_sai real;
alter table public.ponto_registros add column if not exists foto_ent text;
alter table public.ponto_registros add column if not exists foto_sai text;

create or replace function public._dist_descritor(a double precision[], b double precision[])
returns double precision language sql immutable as $$
  select sqrt(coalesce(sum(power(x - y, 2)), 0)) from unnest(a, b) as t(x, y)
$$;

create or replace function public._ponto_rosto_cfg()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('ligado', coalesce((select (valor->>'ligado')::boolean from sistema where chave = 'PONTO_ROSTO' and jsonb_typeof(valor) = 'object'), true),
                            'limite', coalesce((select (valor->>'limite')::numeric from sistema where chave = 'PONTO_ROSTO' and jsonb_typeof(valor) = 'object'), 0.55))
$$;

create or replace function public.api_ponto_rosto_config(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c jsonb := _ponto_rosto_cfg(); v_lig boolean; v_lim numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if p ? 'ligado' or p ? 'limite' then
    v_lig := coalesce(nullif(p->>'ligado', '')::boolean, (c->>'ligado')::boolean);
    v_lim := coalesce(nullif(p->>'limite', '')::numeric, (c->>'limite')::numeric);
    if v_lim < 0.40 or v_lim > 0.70 then return _falha('O rigor precisa ficar entre 0,40 e 0,70.'); end if;
    insert into sistema (chave, valor) values ('PONTO_ROSTO', jsonb_build_object('ligado', v_lig, 'limite', v_lim))
      on conflict (chave) do update set valor = excluded.valor;
    perform _auditar('Ponto: reconhecimento facial ' || case when v_lig then 'ligado' else 'desligado' end, 'limite ' || v_lim);
    c := _ponto_rosto_cfg();
  end if;
  return jsonb_build_object('ok', true, 'ligado', (c->>'ligado')::boolean, 'limite', (c->>'limite')::numeric);
end $$;

create or replace function public.api_ponto_rosto_apagar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_f uuid := _uuid(p->>'funcionarioId'); v_n text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select nome into v_n from funcionarios where id = v_f;
  if v_n is null then return _falha('Funcionário não encontrado.'); end if;
  update ponto_rosto set descritor = '{}', atualizado_em = now() where funcionario_id = v_f;   -- sobrescreve o código do rosto por vazio (apaga o dado biométrico)
  perform _auditar('Ponto: rosto apagado', v_n);
  return jsonb_build_object('ok', true, 'message', 'Rosto de ' || v_n || ' apagado. Na próxima batida ele cadastra de novo.');
end $$;

create or replace function public.api_ponto_aprovar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_f uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  update ponto_registros set rosto_ent = case when rosto_ent = 'pendente' then 'aprovado' else rosto_ent end,
                             rosto_sai = case when rosto_sai = 'pendente' then 'aprovado' else rosto_sai end
   where id = v_id and not cancelado returning funcionario_id into v_f;
  if v_f is null then return _falha('Registro não encontrado.'); end if;
  perform _auditar('Ponto: batida aprovada pelo dono', (select nome from funcionarios where id = v_f));
  return jsonb_build_object('ok', true, 'message', 'Batida aprovada.');
end $$;

-- A foto só pode ser enviada pelo próprio funcionário, logo depois de bater o ponto, uma vez por lado.
create or replace function public.api_ponto_foto_pode(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); v_id uuid := nullif(p->>'registroId', '')::uuid; v_lado text := p->>'lado'; r ponto_registros%rowtype;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null or v_id is null or v_lado not in ('entrada', 'saida') then return _falha('Pedido inválido.'); end if;
  select * into r from ponto_registros where id = v_id and funcionario_id = v_eu and not cancelado;
  if r.id is null then return _falha('Registro não encontrado.'); end if;
  if v_lado = 'entrada' and (r.foto_ent is not null or r.criado_em < now() - interval '10 minutes') then return _falha('A foto da entrada já foi enviada ou passou do prazo.'); end if;
  if v_lado = 'saida' and (r.saida is null or r.foto_sai is not null or r.saida < now() - interval '10 minutes') then return _falha('A foto da saída já foi enviada ou passou do prazo.'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_ponto_foto_anexar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); v_id uuid := nullif(p->>'registroId', '')::uuid; v_lado text := p->>'lado'; v_path text := p->>'path'; v_ok jsonb;
begin
  v_ok := api_ponto_foto_pode(p);
  if not coalesce((v_ok->>'ok')::boolean, false) then return v_ok; end if;
  if v_path is null or v_path !~ '^(drive:[A-Za-z0-9_-]{10,80})?(\|)?(cont:[A-Za-z0-9_-]{10,80})?$' or v_path = '' then return _falha('Caminho da foto inválido.'); end if;
  if v_lado = 'entrada' then update ponto_registros set foto_ent = v_path where id = v_id and funcionario_id = v_eu;
  else update ponto_registros set foto_sai = v_path where id = v_id and funcionario_id = v_eu; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_ponto_estado(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_ini date; v_h numeric;
        v_exige boolean := exists (select 1 from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object');
        v_cfg jsonb := _ponto_rosto_cfg();
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return jsonb_build_object('ok', true, 'vinculado', false); end if;
  v_ini := _escala_segunda(v_hoje);
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  select coalesce(round(sum(extract(epoch from coalesce(saida, now()) - entrada)) / 3600.0, 2), 0) into v_h from ponto_registros
   where funcionario_id = v_eu and not cancelado and (entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_ini + 6;
  return jsonb_build_object('ok', true, 'vinculado', true, 'aberto', r.id is not null, 'entrada', r.entrada, 'horasSemana', v_h, 'exigeLocal', v_exige,
    'rostoLigado', (v_cfg->>'ligado')::boolean, 'temRosto', exists (select 1 from ponto_rosto where funcionario_id = v_eu and array_length(descritor, 1) = 128));
end $$;

create or replace function public.api_ponto_bater(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_eu uuid := _func_do_usuario(); r ponto_registros%rowtype; v_cfg jsonb; v_lat double precision; v_lng double precision; v_prec double precision; v_dist double precision; v_d int; v_raio int; v_nome text;
        v_rc jsonb := _ponto_rosto_cfg(); v_desc double precision[]; v_tpl double precision[]; v_rd double precision; v_st text; v_pend boolean := coalesce(p->>'pendente', '') = 'true'; v_novo uuid; v_lado text;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null then return _falha('Seu acesso ainda não está ligado a um funcionário. Peça ao dono para usar "Importar acessos" na Escala.'); end if;
  begin v_lat := nullif(p->>'lat', '')::double precision; v_lng := nullif(p->>'lng', '')::double precision; v_prec := coalesce(nullif(p->>'precisao', '')::double precision, 0);
  exception when others then v_lat := null; v_lng := null; end;
  select valor into v_cfg from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  if v_lat is not null and v_lng is not null and v_cfg is not null then
    v_dist := _dist_metros(v_lat, v_lng, (v_cfg->>'lat')::double precision, (v_cfg->>'lng')::double precision);
    v_d := round(v_dist);
  end if;
  if v_cfg is not null then
    v_raio := coalesce((v_cfg->>'raio')::int, 150);
    if v_lat is null or v_lng is null then
      return _falha('Para bater o ponto, ative a localização do celular e permita o acesso do navegador a ela. Depois tente de novo.');
    end if;
    if v_dist - least(v_prec, 100) > v_raio then
      select nome into v_nome from funcionarios where id = v_eu;
      perform _auditar('Ponto bloqueado: fora do restaurante', coalesce(v_nome, '') || ' | a ' || v_d || ' m');
      return _falha('Você está a cerca de ' || case when v_d >= 1000 then to_char(round(v_d / 1000.0, 1), 'FM990.0') || ' km' else v_d || ' m' end || ' do restaurante. O ponto só pode ser batido no local.');
    end if;
  end if;

  -- rosto
  if (v_rc->>'ligado')::boolean then
    begin select array_agg(x::double precision) into v_desc from jsonb_array_elements_text(p->'descritor') x; exception when others then v_desc := null; end;
    if v_desc is not null and (array_length(v_desc, 1) <> 128 or exists (select 1 from unnest(v_desc) z where z is null or z <> z)) then v_desc := null; end if;
    select descritor into v_tpl from ponto_rosto where funcionario_id = v_eu and array_length(descritor, 1) = 128;
    if v_tpl is null then
      if v_desc is not null and not v_pend then
        if coalesce(p->>'consentimento', '') <> 'true' then
          return jsonb_build_object('ok', false, 'rosto', 'consentimento', 'message', 'Para cadastrar seu rosto é preciso aceitar o termo.');
        end if;
        insert into ponto_rosto (funcionario_id, descritor) values (v_eu, v_desc) on conflict (funcionario_id) do update set descritor = excluded.descritor, consentimento_em = now(), atualizado_em = now();
        perform _auditar('Ponto: rosto cadastrado', coalesce((select nome from funcionarios where id = v_eu), ''));
        v_st := 'cadastro'; v_rd := 0;
      else
        v_st := 'pendente';
      end if;
    else
      if v_desc is not null then v_rd := _dist_descritor(v_tpl, v_desc); end if;
      if v_rd is not null and v_rd <= (v_rc->>'limite')::double precision then v_st := 'ok';
      elsif v_pend then v_st := 'pendente';
      else
        return jsonb_build_object('ok', false, 'rosto', case when v_desc is null then 'sem_rosto' else 'nao_reconhecido' end,
          'message', case when v_desc is null then 'Não consegui ver o seu rosto. Olhe para a câmera, com boa luz, e tente de novo.' else 'Não reconheci o seu rosto. Tente de novo com boa luz, sem boné ou óculos escuros.' end);
      end if;
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext('ponto:' || v_eu));
  select * into r from ponto_registros where funcionario_id = v_eu and saida is null and not cancelado order by entrada desc limit 1;
  if r.id is not null and r.entrada > now() - interval '20 seconds' then return jsonb_build_object('ok', true, 'message', 'Já registrado agora há pouco.', 'aberto', true); end if;
  if r.id is not null and r.entrada > now() - interval '20 hours' then
    update ponto_registros set saida = now(), saida_dist_m = v_d, rosto_sai = v_st, rosto_dist_sai = v_rd where id = r.id;
    return jsonb_build_object('ok', true, 'aberto', false, 'registroId', r.id, 'lado', 'saida', 'rosto', v_st,
      'message', 'Saída registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '. Trabalhou ' || to_char(round(extract(epoch from now() - r.entrada) / 3600.0, 2), 'FM990.00') || ' h neste turno.' || case when v_st = 'pendente' then ' O dono vai conferir a foto.' else '' end);
  end if;
  insert into ponto_registros (funcionario_id, entrada, lat, lng, dist_m, rosto_ent, rosto_dist_ent) values (v_eu, now(), v_lat, v_lng, v_d, v_st, v_rd) returning id into v_novo;
  return jsonb_build_object('ok', true, 'aberto', true, 'registroId', v_novo, 'lado', 'entrada', 'rosto', v_st,
    'message', case when v_st = 'cadastro' then 'Rosto cadastrado. ' else '' end || 'Entrada registrada às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || '.' || case when r.id is not null then ' (A saída anterior ficou sem registro; o dono pode corrigir.)' else '' end || case when v_st = 'pendente' then ' O dono vai conferir a foto.' else '' end);
end $$;

create or replace function public.api_ponto_relatorio(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ini date := coalesce(nullif(p->>'inicio', '')::date, _escala_segunda((now() at time zone 'America/Sao_Paulo')::date)); v_fim date := coalesce(nullif(p->>'fim', '')::date, v_ini + 6); v_l jsonb; v_loc jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_fim < v_ini or v_fim - v_ini > 62 then return _falha('Período inválido (máximo de 62 dias).'); end if;
  select jsonb_build_object('definido', true, 'raio', (valor->>'raio')::int) into v_loc from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  with reg as (
    select r.funcionario_id, r.id, r.entrada, r.saida, r.observacao, r.origem, r.dist_m, r.saida_dist_m, r.rosto_ent, r.rosto_sai, r.foto_ent, r.foto_sai, (r.entrada at time zone 'America/Sao_Paulo')::date dia,
           extract(epoch from coalesce(r.saida, now()) - r.entrada) / 3600.0 h
      from ponto_registros r where not r.cancelado and (r.entrada at time zone 'America/Sao_Paulo')::date between v_ini and v_fim),
  sem as (select funcionario_id, _escala_segunda(dia) semana, sum(h) h from reg group by 1, 2),
  extra as (select funcionario_id, sum(greatest(h - 44, 0)) ex from sem group by 1),
  esc as (select t.funcionario_id, sum(extract(epoch from (t.data + t.fim + case when t.fim <= t.inicio then interval '1 day' else interval '0' end) - (t.data + t.inicio)) / 3600.0) h
            from escala_turnos t where t.tipo = 'Trabalho' and not t.cancelado and t.data between v_ini and v_fim group by 1),
  tot as (select funcionario_id, sum(h) h from reg group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('funcionarioId', f.id, 'nome', f.nome, 'cargo', f.cargo,
      'horasFeitas', round(coalesce(tot.h, 0)::numeric, 2), 'horasEscaladas', round(coalesce(esc.h, 0)::numeric, 2),
      'diferenca', round((coalesce(tot.h, 0) - coalesce(esc.h, 0))::numeric, 2), 'horasExtras', round(coalesce(extra.ex, 0)::numeric, 2),
      'aberto', exists (select 1 from reg where reg.funcionario_id = f.id and reg.saida is null),
      'temRosto', exists (select 1 from ponto_rosto pr where pr.funcionario_id = f.id and array_length(pr.descritor, 1) = 128),
      'registros', coalesce((select jsonb_agg(jsonb_build_object('id', reg.id, 'dia', reg.dia, 'entrada', to_char(reg.entrada at time zone 'America/Sao_Paulo', 'HH24:MI'), 'saida', to_char(reg.saida at time zone 'America/Sao_Paulo', 'HH24:MI'),
          'horas', round(reg.h::numeric, 2), 'origem', reg.origem, 'observacao', reg.observacao, 'distEntrada', reg.dist_m, 'distSaida', reg.saida_dist_m,
          'rostoEntrada', reg.rosto_ent, 'rostoSaida', reg.rosto_sai, 'fotoEntrada', reg.foto_ent is not null, 'fotoSaida', reg.foto_sai is not null) order by reg.entrada) from reg where reg.funcionario_id = f.id), '[]'::jsonb)
    ) order by f.nome), '[]'::jsonb) into v_l
    from funcionarios f left join tot on tot.funcionario_id = f.id left join esc on esc.funcionario_id = f.id left join extra on extra.funcionario_id = f.id
   where f.ativo or tot.h is not null;
  return jsonb_build_object('ok', true, 'inicio', v_ini, 'fim', v_fim, 'pessoas', v_l, 'local', coalesce(v_loc, jsonb_build_object('definido', false)), 'rosto', _ponto_rosto_cfg());
end $$;

-- permissões das funções novas (as antigas mantêm as suas)
do $$
declare f text;
begin
  foreach f in array array['api_ponto_local(jsonb)', 'api_ponto_rosto_config(jsonb)', 'api_ponto_rosto_apagar(jsonb)', 'api_ponto_aprovar(jsonb)', 'api_ponto_foto_pode(jsonb)', 'api_ponto_foto_anexar(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
  revoke all on function public._dist_descritor(double precision[], double precision[]) from public, anon, authenticated;
  revoke all on function public._dist_metros(double precision, double precision, double precision, double precision) from public, anon, authenticated;
  revoke all on function public._ponto_rosto_cfg() from public, anon, authenticated;
end $$;

-- limpeza diária das fotos com mais de 45 dias (a Edge Function apaga nos dois Drives e limpa os caminhos)
select cron.schedule('ponto-fotos-45-dias', '40 6 * * *', $$select public.chamar_edge('ponto-foto', '{"acao":"limpar"}'::jsonb)$$);


-- ======================================================================
-- 31-fotos-registros.sql
-- ======================================================================
-- 31 · Fotos opcionais em três lançamentos (18/10/2026): perda de estoque, recebimento de compra e ocorrência de pedido
-- • A foto vai para o Drive principal e para o da contingência (pasta privada "Fotos de registros") pela Edge Function evidencia-foto.
-- • Até 3 fotos por registro, opcionais. Ficam 45 dias: rotina diária evidencias-45-dias apaga os arquivos dos dois Drives e as linhas.
-- • Quem pode anexar: só quem fez o lançamento, logo depois (30 minutos). Quem pode ver: Admin (perda, recebimento) e Admin/Operador (ocorrência).

create table if not exists public.evidencias_foto (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('perda', 'recebimento', 'ocorrencia')),
  ref_id uuid not null,
  path text not null,
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index if not exists evidencias_foto_ref_idx on public.evidencias_foto (tipo, ref_id);
create index if not exists evidencias_foto_data_idx on public.evidencias_foto (criado_em);
alter table public.evidencias_foto enable row level security;
revoke all on public.evidencias_foto from anon, authenticated;
grant all on public.evidencias_foto to service_role;

-- a perda de estoque passa a devolver o id da movimentação (para ligar a foto)
create or replace function public.api_registrar_perda_estoque(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e estoque%rowtype; v_qtd numeric := _num(p->>'quantidade'); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_depois numeric; v_motivo text := btrim(coalesce(p->>'motivo', '')); v_mid uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_qtd <= 0 then return _falha('Informe uma quantidade de perda maior que zero.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo da perda.'); end if;
  select * into e from estoque where id = _uuid(p->>'ingredienteId') for update;
  if not found then return _falha('Ingrediente não encontrado.'); end if;
  if v_qtd > e.quantidade then return _falha('A perda (' || v_qtd || ') é maior que o estoque atual de ' || e.ingrediente || ' (' || e.quantidade || '). Nada foi registrado.'); end if;
  v_depois := greatest(0, e.quantidade - v_qtd);
  update estoque set quantidade = v_depois where id = e.id;
  insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
  values (e.id, 'Perda', -v_qtd, e.quantidade, v_depois, v_motivo, auth.uid()) returning id into v_mid;
  perform _auditar('Perda de estoque', e.ingrediente || ': -' || v_qtd || ' (' || v_motivo || ')');
  v_r := jsonb_build_object('ok', true, 'message', 'Perda registrada.', 'id', v_mid);
  if v_req is not null then perform _idem_gravar(v_req, 'registrarPerdaEstoque', v_r); end if;
  return v_r;
end $$;

-- confere se esta pessoa pode anexar foto a este registro agora
create or replace function public._evidencia_pode(p_tipo text, p_ref uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ok boolean := false; v_n int;
begin
  if auth_nivel() is null then return _negado(); end if;
  if p_ref is null or p_tipo not in ('perda', 'recebimento', 'ocorrencia') then return _falha('Pedido inválido.'); end if;
  if p_tipo = 'perda' then
    v_ok := tem_nivel('Admin') and exists (select 1 from movimentacoes_estoque m where m.id = p_ref and m.tipo::text = 'Perda' and m.usuario_id = auth.uid() and m.data > now() - interval '30 minutes');
  elsif p_tipo = 'recebimento' then
    v_ok := tem_nivel('Admin') and exists (select 1 from compras c where c.id = p_ref and c.status = 'Recebida' and coalesce(c.recebida_em, c.criado_em) > now() - interval '60 minutes');
  else
    v_ok := exists (select 1 from ocorrencias o where o.id = p_ref and o.registrado_por = auth.uid() and o.data_hora > now() - interval '30 minutes');
  end if;
  if not v_ok then return _falha('Não foi possível anexar foto a este registro (ou já passou do prazo).'); end if;
  select count(*) into v_n from evidencias_foto where tipo = p_tipo and ref_id = p_ref;
  if v_n >= 3 then return _falha('Este registro já tem 3 fotos.'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.api_evidencia_pode(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  return _evidencia_pode(p->>'tipo', nullif(p->>'refId', '')::uuid);
exception when invalid_text_representation then return _falha('Pedido inválido.');
end $$;

create or replace function public.api_evidencia_anexar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_t text := p->>'tipo'; v_ref uuid; v_path text := p->>'path'; v_ok jsonb;
begin
  begin v_ref := nullif(p->>'refId', '')::uuid; exception when others then return _falha('Pedido inválido.'); end;
  v_ok := _evidencia_pode(v_t, v_ref);
  if not coalesce((v_ok->>'ok')::boolean, false) then return v_ok; end if;
  if v_path is null or v_path = '' or v_path !~ '^(drive:[A-Za-z0-9_-]{10,80})?(\|)?(cont:[A-Za-z0-9_-]{10,80})?$' then return _falha('Caminho da foto inválido.'); end if;
  insert into evidencias_foto (tipo, ref_id, path, usuario_id) values (v_t, v_ref, v_path, auth.uid());
  return jsonb_build_object('ok', true);
end $$;

-- quantas fotos cada registro tem (só para quem pode ver)
create or replace function public.api_evidencias_lista(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_t text := p->>'tipo'; v_ids uuid[]; v_m jsonb;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_t not in ('perda', 'recebimento', 'ocorrencia') then return _falha('Pedido inválido.'); end if;
  if not ((v_t = 'ocorrencia' and tem_nivel('Admin', 'Operador')) or (v_t <> 'ocorrencia' and tem_nivel('Admin'))) then return jsonb_build_object('ok', true, 'mapa', '{}'::jsonb); end if;
  begin select array_agg(x::uuid) into v_ids from (select jsonb_array_elements_text(p->'ids') x limit 150) s; exception when others then v_ids := null; end;
  select coalesce(jsonb_object_agg(ref_id::text, n), '{}'::jsonb) into v_m from (select ref_id, count(*) n from evidencias_foto where tipo = v_t and ref_id = any(coalesce(v_ids, '{}')) group by 1) q;
  return jsonb_build_object('ok', true, 'mapa', v_m);
end $$;

do $$
declare f text;
begin
  foreach f in array array['api_evidencia_pode(jsonb)', 'api_evidencia_anexar(jsonb)', 'api_evidencias_lista(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
  revoke all on function public._evidencia_pode(text, uuid) from public, anon, authenticated;
end $$;

-- limpeza diária: a Edge Function evidencia-foto apaga nos dois Drives e remove as linhas com mais de 45 dias
select cron.schedule('evidencias-45-dias', '50 6 * * *', $$select public.chamar_edge('evidencia-foto', '{"acao":"limpar"}'::jsonb)$$);


-- ======================================================================
-- 32-etiquetas-validade.sql
-- ======================================================================
-- 32 · Etiquetas de validade (18/10/2026)
-- • Cadastro de itens com os dias de validade (aberto, manipulado, descongelado, fechado) — o dono preenche; nada vem pronto.
-- • Admin cadastra e muda os itens; Admin, Operador e Cozinha imprimem. Cada impressão fica registrada (limpeza após 45 dias pela rotina diária da Edge Function evidencia-foto).

create table if not exists public.etiqueta_itens (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  dias jsonb not null default '{}'::jsonb,       -- {"aberto":3,"manipulado":2,"descongelado":1,"fechado":30} (só o que o dono preencher)
  conservacao text not null default 'Refrigerado' check (conservacao in ('Refrigerado', 'Congelado', 'Ambiente')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
create unique index if not exists etiqueta_itens_nome_uq on public.etiqueta_itens (lower(nome));
create table if not exists public.etiqueta_impressoes (
  id uuid primary key default gen_random_uuid(),
  item_nome text not null,
  tipo text not null,
  qtd int not null,
  manipulado_em timestamptz,
  validade date,
  conservacao text,
  lote text,
  usuario_id uuid,
  usuario_nome text,
  criado_em timestamptz not null default now()
);
create index if not exists etiqueta_impressoes_data_idx on public.etiqueta_impressoes (criado_em);
alter table public.etiqueta_itens enable row level security;
alter table public.etiqueta_impressoes enable row level security;
revoke all on public.etiqueta_itens, public.etiqueta_impressoes from anon, authenticated;
grant all on public.etiqueta_itens, public.etiqueta_impressoes to service_role;

create or replace function public.api_etiquetas_lista(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_todos boolean := coalesce((p->>'todos')::boolean, false) and tem_nivel('Admin');
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'itens', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'nome', i.nome, 'dias', i.dias, 'conservacao', i.conservacao, 'ativo', i.ativo) order by lower(i.nome))
    from etiqueta_itens i where v_todos or i.ativo), '[]'::jsonb));
end $$;

create or replace function public.api_etiqueta_salvar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_id uuid; v_dias jsonb := '{}'::jsonb; k text; n numeric; v_cons text := coalesce(nullif(p->>'conservacao', ''), 'Refrigerado');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' or length(v_nome) > 60 then return _falha('Informe o nome do item (até 60 letras).'); end if;
  if v_cons not in ('Refrigerado', 'Congelado', 'Ambiente') then return _falha('Conservação inválida.'); end if;
  foreach k in array array['aberto', 'manipulado', 'descongelado', 'fechado'] loop
    if nullif(btrim(coalesce(p->'dias'->>k, '')), '') is not null then
      begin n := (p->'dias'->>k)::numeric; exception when others then return _falha('Dias de validade inválidos.'); end;
      if n < 0 or n > 3650 or n <> trunc(n) then return _falha('Dias de validade devem ser um número inteiro entre 0 e 3650.'); end if;
      v_dias := v_dias || jsonb_build_object(k, n::int);
    end if;
  end loop;
  begin v_id := nullif(p->>'id', '')::uuid; exception when others then return _falha('Pedido inválido.'); end;
  if v_id is not null then
    update etiqueta_itens set nome = v_nome, dias = v_dias, conservacao = v_cons, ativo = coalesce((p->>'ativo')::boolean, true) where id = v_id;
    if not found then return _falha('Item não encontrado.'); end if;
  else
    if exists (select 1 from etiqueta_itens where lower(nome) = lower(v_nome)) then return _falha('Já existe um item com esse nome.'); end if;
    insert into etiqueta_itens (nome, dias, conservacao) values (v_nome, v_dias, v_cons) returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'message', 'Item salvo.');
exception when unique_violation then return _falha('Já existe um item com esse nome.');
end $$;

create or replace function public.api_etiqueta_importar_estoque(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  insert into etiqueta_itens (nome) select btrim(e.ingrediente) from estoque e where btrim(coalesce(e.ingrediente, '')) <> '' on conflict do nothing;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'novos', v_n, 'message', v_n || ' ingrediente(s) trazido(s) do estoque. Agora preencha os dias de validade de cada um.');
end $$;

create or replace function public.api_etiqueta_registrar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_tipo text := p->>'tipo'; v_qtd int; v_val date; v_man timestamptz; v_cons text := nullif(p->>'conservacao', ''); v_u text;
begin
  if not tem_nivel('Admin', 'Operador', 'Cozinha') then return _negado(); end if;
  if v_nome = '' or length(v_nome) > 60 then return _falha('Informe o nome do item.'); end if;
  if v_tipo not in ('Aberto', 'Manipulado', 'Descongelado', 'Fechado') then return _falha('Escolha o tipo da etiqueta.'); end if;
  begin v_qtd := (p->>'qtd')::int; v_val := (p->>'validade')::date; v_man := nullif(p->>'manipuladoEm', '')::timestamptz;
  exception when others then return _falha('Dados da etiqueta inválidos.'); end;
  if v_qtd is null or v_qtd < 1 or v_qtd > 100 then return _falha('A quantidade de etiquetas deve ficar entre 1 e 100.'); end if;
  if v_val is null then return _falha('Informe a validade.'); end if;
  select coalesce(nullif(u.nome, ''), u.login) into v_u from usuarios u where u.id = auth.uid();
  insert into etiqueta_impressoes (item_nome, tipo, qtd, manipulado_em, validade, conservacao, lote, usuario_id, usuario_nome)
  values (v_nome, v_tipo, v_qtd, v_man, v_val, left(v_cons, 20), left(nullif(btrim(coalesce(p->>'lote', '')), ''), 40), auth.uid(), v_u);
  return jsonb_build_object('ok', true, 'responsavel', v_u);
end $$;

do $$
declare f text;
begin
  foreach f in array array['api_etiquetas_lista(jsonb)', 'api_etiqueta_salvar(jsonb)', 'api_etiqueta_importar_estoque(jsonb)', 'api_etiqueta_registrar(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
end $$;


-- ======================================================================
-- 33-visitas-sem-equipe.sql
-- ======================================================================
-- 33 · Visitas ao cardápio: o aparelho de quem trabalha no sistema nunca conta (19/10/2026)
-- Quando alguém da equipe entra no sistema, o aparelho é registrado aqui. As visitas desse aparelho (inclusive as de antes do login,
-- como depois de limpar os dados do site) deixam de aparecer na contagem do Início.
create table if not exists public.cardapio_aparelhos_equipe (
  aparelho text primary key,
  criado_em timestamptz not null default now()
);
alter table public.cardapio_aparelhos_equipe enable row level security;
revoke all on public.cardapio_aparelhos_equipe from anon, authenticated;
grant all on public.cardapio_aparelhos_equipe to service_role;

create or replace function public.api_marcar_aparelho_equipe(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ap text := lower(btrim(coalesce(p->>'aparelho', '')));
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_ap !~ '^[a-z0-9]{16,40}$' then return jsonb_build_object('ok', false); end if;
  insert into cardapio_aparelhos_equipe (aparelho) values (v_ap) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.api_marcar_aparelho_equipe(jsonb) from public, anon;
grant execute on function public.api_marcar_aparelho_equipe(jsonb) to authenticated, service_role;

create or replace function public.api_visitas_cardapio_hoje(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'hoje', (select count(*) from cardapio_visitas v where v.dia = v_dia
    and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = v.aparelho)));
end $$;

create or replace function public.api_registrar_visita_cardapio(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ap text := lower(btrim(coalesce(p->>'aparelho', ''))); v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if v_ap !~ '^[a-z0-9]{16,40}$' then return jsonb_build_object('ok', false); end if;
  if exists (select 1 from cardapio_aparelhos_equipe where aparelho = v_ap) then return jsonb_build_object('ok', true); end if;
  if (select count(*) from cardapio_visitas where dia = v_dia) >= 20000 then return jsonb_build_object('ok', true); end if;
  insert into cardapio_visitas (dia, aparelho) values (v_dia, v_ap) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;


-- ======================================================================
-- 34-ifood-alertas.sql
-- ======================================================================
-- 34 · Alertas de pedido parado: entrega feita pelo próprio iFood não alerta "sem sair para entrega" (19/10/2026)
-- Quando o iFood entrega, a loja só deixa o pedido pronto; quem sai com ele é o entregador do iFood. Os demais alertas continuam valendo.
create or replace function public._alertas_pedidos_parados()
returns table (venda_id uuid, numero int, regra text, rotulo text, desde timestamptz, minutos int, niveis text[], tipo text)
language plpgsql stable security definer set search_path to 'public' as $$
declare v_cfg jsonb := _alertas_cfg()->'regras'; s caixa_sessoes%rowtype;
begin
  select * into s from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  if s.id is null then return; end if;
  return query
  with base as (
    select v.id, v.numero_pedido, v.tipo::text tp, v.status_pedido::text sp, v.status_pagamento::text pg,
           v.data_hora, v.inicio_preparo_em, v.pronta_em, v.saiu_em, v.concluida_em,
           coalesce(v.observacoes_entrega, '') ilike '%AGENDADO%' agendado,
           (v.canal = 'iFood' and coalesce(v.observacoes_entrega, '') ilike '%ENTREGA PELO iFOOD%') ent_ifood
      from vendas v
     where v.status = 'Confirmada'
       and (v.caixa_id = s.id or (v.caixa_id is null and v.data_hora >= s.abertura))
       and coalesce(v.status_pedido::text, '') <> 'Suspenso'
       and not exists (select 1 from ocorrencias o where o.venda_id = v.id and o.status::text in ('Aberta', 'Em andamento'))
  ), r as (
    select id, numero_pedido, 'recebido' rg, 'Novo pedido sem aceite' rot, data_hora d, array['Cozinha','Operador'] nv, tp from base where sp = 'Recebido' and not agendado
    union all select id, numero_pedido, 'preparo', 'Em preparo há muito tempo', coalesce(inicio_preparo_em, data_hora), array['Cozinha','Operador'], tp from base where sp = 'Em preparo' and not agendado
    union all select id, numero_pedido, 'pronta_retirada', 'Pronta (retirada) sem marcar "Retirada"', coalesce(pronta_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Pronta' and tp = 'Retirada'
    union all select id, numero_pedido, 'pronta_entrega', 'Pronta (entrega) sem sair para entrega', coalesce(pronta_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Pronta' and tp = 'Entrega' and not ent_ifood
    union all select id, numero_pedido, 'pronta_mesa', 'Pronta (mesa) sem marcar "Servida"', coalesce(pronta_em, data_hora), array['Operador','Garçom'], tp from base where sp = 'Pronta' and tp = 'Mesa'
    union all select id, numero_pedido, 'saiu', 'Saiu para entrega e não foi concluído', coalesce(saiu_em, data_hora), array['Operador','Admin'], tp from base where sp = 'Saiu para entrega' and not ent_ifood
    union all select id, numero_pedido, 'a_receber', 'Pagamento "a receber" com o pedido pronto', coalesce(concluida_em, pronta_em, data_hora), array['Operador','Admin'], tp
      from base where pg = 'A Receber' and tp <> 'Mesa' and sp in ('Pronta', 'Retirada', 'Servida', 'Entregue')
  )
  select r.id, r.numero_pedido, r.rg, r.rot, r.d, floor(extract(epoch from (now() - r.d)) / 60)::int, r.nv, r.tp
    from r
   where coalesce((v_cfg->r.rg->>'ligado')::boolean, true)
     and now() - r.d >= make_interval(mins => greatest(1, coalesce((v_cfg->r.rg->>'min')::int, 10)));
end $$;


-- ======================================================================
-- 35-ifood-extras.sql
-- ======================================================================
-- 35 · iFood: recursos opcionais (19/10/2026). TODOS nascem DESLIGADOS (Administrador › Sistema › Integrações e contas › iFood › Ajustes).
--  • conferirRepasse   : compara cada repasse do iFood com o que o sistema esperava receber dos mesmos pedidos (só mostra a diferença).
--  • avaliacaoAlerta   : avisa (push) também a avaliação nota 3 (sem isso, só nota 1 e 2).
--  • avaliacaoSugestao : botão "Sugerir resposta" nas avaliações (só tela; o dono revisa antes de enviar).
--  • acompanharEntrega : guarda a posição do entregador do iFood enquanto o pedido está pronto ou a caminho e mostra no pedido.
alter table public.ifood_pedidos add column if not exists rastreio jsonb;
alter table public.ifood_pedidos add column if not exists rastreio_em timestamptz;

-- 1) as novas chaves passam a ser aceitas em "Ajustes salvos"
do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_integracoes_config(jsonb)'::regprocedure);
  if d like '%''acompanharEntrega''%' then return; end if;
  d := replace(d, '''pausarSemEstoque'', ''enviarPrecos'')', '''pausarSemEstoque'', ''enviarPrecos'', ''conferirRepasse'', ''avaliacaoAlerta'', ''avaliacaoSugestao'', ''acompanharEntrega'')');
  if d not like '%''acompanharEntrega''%' then raise exception 'trecho não encontrado em api_integracoes_config'; end if;
  execute d;
end $$;

-- 2) avaliação nota 3 também avisa, se o ajuste estiver ligado
do $$
declare d text;
begin
  d := pg_get_functiondef('public.ifood_avaliacoes_gravar(jsonb)'::regprocedure);
  if d like '%avaliacaoAlerta%' then return; end if;
  d := replace(d, 'if v_nota <= 2 then perform _push_enviar', 'if v_nota <= 2 or (v_nota = 3 and coalesce((select (config->>''avaliacaoAlerta'')::boolean from integracoes_config where provedor = ''ifood''), false)) then perform _push_enviar');
  if d not like '%avaliacaoAlerta%' then raise exception 'trecho não encontrado em ifood_avaliacoes_gravar'; end if;
  execute d;
end $$;

-- 3) conferência de repasses (só leitura)
create or replace function public.api_ifood_conferencia(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_on boolean := coalesce((select (config->>'conferirRepasse')::boolean from integracoes_config where provedor = 'ifood'), false);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not v_on then return jsonb_build_object('ok', true, 'ligado', false); end if;
  return jsonb_build_object('ok', true, 'ligado', true,
    'repasses', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'pagoEm', r.pago_em, 'recebido', r.valor, 'esperado', q.esperado, 'pedidos', q.n, 'diferenca', round(r.valor - q.esperado, 2)) order by r.pago_em desc nulls last)
       from (select * from ifood_repasses order by coalesce(pago_em, (criado_em at time zone 'America/Sao_Paulo')::date) desc limit 15) r
       cross join lateral (select count(distinct i.pedido_ifood) n,
              coalesce(sum((select coalesce(sum(pv.valor - coalesce(pv.taxa_aplicada, 0)), 0) from pagamentos_venda pv where pv.venda_id = i.venda_id and pv.forma_pagamento = 'iFood (pago no app)')), 0) esperado
            from ifood_pedidos i where i.repasse_id = r.id and not i.simulado) q), '[]'::jsonb),
    'atrasados', coalesce((select jsonb_agg(jsonb_build_object('numero', i.numero_ifood, 'venda', v.numero_pedido, 'desde', v.data_hora) order by v.data_hora)
       from ifood_pedidos i join vendas v on v.id = i.venda_id
       where not i.simulado and v.status = 'Confirmada' and i.repassado_em is null and i.estado <> 'cancelado' and v.data_hora < now() - interval '10 days'
         and exists (select 1 from pagamentos_venda pv where pv.venda_id = v.id and pv.forma_pagamento = 'iFood (pago no app)')), '[]'::jsonb));
end $$;

-- 4) acompanhamento da entrega do iFood
create or replace function public.ifood_rastreio_pendentes() returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not coalesce((select (config->>'acompanharEntrega')::boolean from integracoes_config where provedor = 'ifood'), false) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(i.pedido_ifood) from (
    select i.pedido_ifood from ifood_pedidos i join vendas v on v.id = i.venda_id
     where not i.simulado and v.status = 'Confirmada' and v.tipo::text = 'Entrega' and v.status_pedido::text in ('Pronta', 'Saiu para entrega')
       and coalesce(v.observacoes_entrega, '') ilike '%ENTREGA PELO iFOOD%' order by v.data_hora limit 10) i), '[]'::jsonb);
end $$;
create or replace function public.ifood_rastreio_gravar(p_pedido text, p_dados jsonb) returns void language sql security definer set search_path to 'public' as $$
  update ifood_pedidos set rastreio = p_dados, rastreio_em = now() where pedido_ifood = p_pedido;
$$;
revoke all on function public.ifood_rastreio_pendentes() from public, anon, authenticated;
revoke all on function public.ifood_rastreio_gravar(text, jsonb) from public, anon, authenticated;
grant execute on function public.ifood_rastreio_pendentes() to service_role;
grant execute on function public.ifood_rastreio_gravar(text, jsonb) to service_role;

create or replace function public.api_ifood_rastreios(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if not coalesce((select (config->>'acompanharEntrega')::boolean from integracoes_config where provedor = 'ifood'), false) then return jsonb_build_object('ok', true, 'ligado', false); end if;
  return jsonb_build_object('ok', true, 'ligado', true, 'mapa', coalesce((select jsonb_object_agg(i.venda_id::text, jsonb_build_object('dados', i.rastreio, 'em', i.rastreio_em))
     from ifood_pedidos i join vendas v on v.id = i.venda_id
    where i.rastreio is not null and i.rastreio_em > now() - interval '30 minutes' and v.status_pedido::text in ('Pronta', 'Saiu para entrega')), '{}'::jsonb));
end $$;

do $$
declare f text;
begin
  foreach f in array array['api_ifood_conferencia(jsonb)', 'api_ifood_rastreios(jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated, service_role';
  end loop;
end $$;

-- 5) agendamento do acompanhamento: só chama a função ifood-rastreio se a integração estiver ligada E houver pedido para acompanhar
select cron.schedule('ifood-rastreio-minuto', '* * * * *', $c$select case when public._integracao_ligada('ifood') and jsonb_array_length(public.ifood_rastreio_pendentes()) > 0 then public.chamar_edge('ifood-rastreio', '{}'::jsonb) end$c$);


-- ======================================================================
-- 36-ifood-feedbacks.sql
-- ======================================================================
-- 36 · Avaliações do iFood dentro dos Feedbacks (19/10/2026)
-- • Responder uma avaliação do iFood pela tela de Feedbacks também envia a resposta ao iFood (só o Administrador; integração ligada; até 600 letras).
-- • Responder pela aba iFood marca o feedback correspondente como respondido, com o mesmo texto.
create or replace function public.api_responder_feedback(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := _uuid(p->>'id'); v_txt text := left(btrim(coalesce(p->>'resposta', '')), 1000); v_nome text; v_user uuid; v_av text; v_ifood text := null;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_txt = '' then return _falha('Escreva a resposta.'); end if;
  select nome into v_nome from usuarios where id = auth.uid();
  update feedbacks set resposta = v_txt, respondido_em = now(), respondido_por = coalesce(v_nome, ''), status = 'Respondido'
   where id = v_id returning user_id into v_user;
  if not found then return _falha('Feedback não encontrado.'); end if;
  select id into v_av from ifood_avaliacoes where feedback_id = v_id;
  if v_av is not null then
    if not tem_nivel('Admin') then v_ifood := 'so_admin';
    elsif not _integracao_ligada('ifood') then v_ifood := 'desligado';
    elsif length(v_txt) < 3 or length(v_txt) > 600 then v_ifood := 'tamanho';
    else
      update ifood_avaliacoes set resposta = v_txt, respondida_em = now() where id = v_av;
      insert into ifood_acoes (pedido_ifood, acao, dados) values ('LOJA', 'avaliacao_responder', jsonb_build_object('avaliacao', v_av, 'texto', v_txt)) on conflict do nothing;
      v_ifood := 'enviada';
    end if;
  end if;
  perform _auditar('Feedback respondido', 'Resposta enviada' || case when v_user is null then ' (cliente sem conta)' else '' end || case when v_ifood = 'enviada' then ' · enviada ao iFood' else '' end);
  return jsonb_build_object('ok', true, 'comConta', v_user is not null, 'ifood', v_ifood);
end $$;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_ifood_avaliacao_responder(jsonb)'::regprocedure);
  if d like '%update feedbacks%' then return; end if;
  d := replace(d, 'update ifood_avaliacoes set resposta = v_texto, respondida_em = now() where id = p->>''id'';',
    'update ifood_avaliacoes set resposta = v_texto, respondida_em = now() where id = p->>''id'';' || chr(10) ||
    '  update feedbacks set resposta = v_texto, respondido_em = now(), respondido_por = coalesce((select nome from usuarios where id = auth.uid()), ''''), status = ''Respondido'' where id = (select feedback_id from ifood_avaliacoes where id = p->>''id'');');
  if d not like '%update feedbacks%' then raise exception 'trecho não encontrado em api_ifood_avaliacao_responder'; end if;
  execute d;
end $$;

-- A IA do sistema (resumos e perguntas) passa a ver o iFood como origem própria, em vez de misturá-lo com "Balcão"
do $$
declare d text; v_old text; v_new text; r record;
begin
  for r in select * from (values
      ('public.ia_periodo_(date,date,boolean)', 'select origem::text k, count(*) n from vendas', 'select (case when canal = ''iFood'' then ''iFood'' else origem::text end) k, count(*) n from vendas'),
      ('public.ia_resumo_periodo(date,date)', 'select origem::text origem, count(*) n, sum(valor_total) v from vendas', 'select (case when canal = ''iFood'' then ''iFood'' else origem::text end) origem, count(*) n, sum(valor_total) v from vendas')
    ) t(fn, v_old, v_new) loop
    d := pg_get_functiondef(r.fn::regprocedure);
    if d like '%canal = ''iFood'' then ''iFood'' else origem::text%' then continue; end if;
    d := replace(d, r.v_old, r.v_new);
    if d not like '%canal = ''iFood'' then ''iFood'' else origem::text%' then raise exception 'trecho não encontrado em %', r.fn; end if;
    execute d;
  end loop;
end $$;


-- ======================================================================
-- 37-ifood-homologacao.sql
-- ======================================================================
-- 37 · Ajustes para a homologação do iFood (tudo continua DESLIGADO por padrão)
-- 1) opção "modoHomologacao" liberada na tela de ajustes; 2) consulta ao iFood a cada 30 s; 3) "Acompanhar entrega" passa a usar
--    os eventos oficiais de entrega (ADR, GTO, AAO, CLT, AAD, DRGO, DRDO) que já chegam pela consulta; 4) tira a consulta /tracking não verificada.
do $$
declare d text;
begin
  select pg_get_functiondef('public.api_integracoes_config'::regproc) into d;
  if position('modoHomologacao' in d) = 0 then
    if position('''acompanharEntrega'')' in d) = 0 then raise exception 'ponto de troca não encontrado em api_integracoes_config'; end if;
    d := replace(d, '''acompanharEntrega'')', '''acompanharEntrega'', ''modoHomologacao'')');
    execute d;
  end if;
end $$;

create or replace function public.api_ifood_rastreios(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if not coalesce((select (config->>'acompanharEntrega')::boolean from integracoes_config where provedor = 'ifood'), false) then return jsonb_build_object('ok', true, 'ligado', false); end if;
  return jsonb_build_object('ok', true, 'ligado', true, 'mapa', coalesce((
    select jsonb_object_agg(x.venda_id::text, jsonb_build_object('dados', jsonb_build_object('etapa', x.cod, 'em', x.quando), 'em', x.quando))
    from (
      select distinct on (i.venda_id) i.venda_id,
             upper(coalesce(nullif(e.codigo, ''), e.codigo_completo)) cod,
             coalesce(e.criado_ifood, e.recebido_em) quando
        from ifood_pedidos i
        join vendas v on v.id = i.venda_id
        join ifood_eventos e on e.pedido_ifood = i.pedido_ifood
       where v.status_pedido::text in ('Pronta', 'Saiu para entrega')
         and e.recebido_em > now() - interval '6 hours'
         and (upper(e.codigo) in ('ADR','GTO','AAO','CLT','AAD','DRGO','DRDO')
              or upper(e.codigo_completo) in ('ASSIGN_DRIVER','GOING_TO_ORIGIN','ARRIVED_AT_ORIGIN','COLLECTED','ARRIVED_AT_DESTINATION'))
       order by i.venda_id, coalesce(e.criado_ifood, e.recebido_em) desc
    ) x), '{}'::jsonb));
end $$;

do $$
begin
  perform cron.unschedule('ifood-rastreio-minuto');
exception when others then null;
end $$;
select cron.alter_job((select jobid from cron.job where jobname = 'ifood-sync-minuto'), schedule := '30 seconds');


-- ======================================================================
-- 38-nfce-campos-focus.sql
-- ======================================================================
-- 38 · Nota fiscal (NFC-e): ajusta o corpo enviado à Focus NFe ao exemplo oficial da Focus
--   • a lista de produtos se chama "items" (estava "itens": a Focus recusaria toda nota);
--   • totais da nota (valor_produtos, valor_desconto, valor_outras_despesas, valor_total) como no exemplo oficial;
--   • tipo_documento e finalidade_emissao explícitos (1 = saída, normal), como no exemplo oficial;
--   • cartão (crédito/débito): bandeira_operadora "99" (outras), como o exemplo oficial traz o campo.
-- Pode rodar de novo sem erro. A integração de nota fiscal continua desligada até você ligar.
do $$
declare d text;
begin
  select pg_get_functiondef('public.nfce_montar(bigint)'::regprocedure) into d;
  if position('''items'', v_itens' in d) = 0 then
    if position('''itens'', v_itens' in d) = 0 then raise exception 'trecho "itens" não encontrado em nfce_montar'; end if;
    d := replace(d, '''itens'', v_itens', '''items'', v_itens');
  end if;
  if position('''valor_produtos''' in d) = 0 then
    if position('''formas_pagamento'', v_pags)' in d) = 0 then raise exception 'trecho "formas_pagamento" não encontrado em nfce_montar'; end if;
    d := replace(d, '''formas_pagamento'', v_pags)',
      '''formas_pagamento'', v_pags, ''tipo_documento'', 1, ''finalidade_emissao'', 1, ''valor_produtos'', round(v_bruto, 2), ''valor_desconto'', round(v_desc, 2), ''valor_outras_despesas'', nullif(round(v_outras, 2), 0), ''valor_total'', v_total)');
  end if;
  if position('bandeira_operadora' in d) = 0 then
    if position('  v_cpf := coalesce(n.cpf, v.cpf_nota);' in d) = 0 then raise exception 'trecho "v_cpf" não encontrado em nfce_montar'; end if;
    d := replace(d, '  v_cpf := coalesce(n.cpf, v.cpf_nota);',
      '  select coalesce(jsonb_agg(case when x.e->>''forma_pagamento'' in (''03'', ''04'') then x.e || ''{"bandeira_operadora":"99"}''::jsonb else x.e end order by x.i), ''[]''::jsonb) into v_pags from jsonb_array_elements(v_pags) with ordinality as x(e, i);' || chr(10) || '  v_cpf := coalesce(n.cpf, v.cpf_nota);');
  end if;
  execute d;
end $$;


-- ======================================================================
-- 39-ifood-teste-conexao.sql
-- ======================================================================
-- 39 · iFood: botão "Testar conexão" (antes, o item "Teste de conexão deu certo" só era marcado depois de LIGAR, e só dava para ligar depois dele)
--   • api_ifood_testar: Administrador pede o teste; a Edge Function "ifood-teste" pede um acesso ao iFood com as chaves digitadas e confere a loja;
--   • o item da lista passa a valer quando o último teste/consulta deu certo DEPOIS da última troca de chaves.
-- Pode rodar de novo sem erro.
do $$
declare d text;
begin
  select pg_get_functiondef('public._integ_pendencias(text,text)'::regprocedure) into d;
  if position('''teste_conexao''' in d) = 0 then
    if position('        when ''chaves'' then (' in d) = 0 then raise exception 'ponto de troca não encontrado em _integ_pendencias'; end if;
    d := replace(d, '        when ''chaves'' then (',
      '        when ''teste_conexao'' then exists (select 1 from ifood_estado e where e.id and e.token_ok is true and e.ultimo_erro is null and e.ultima_consulta_ok is not null and e.ultima_consulta_ok >= coalesce((select max(atualizado_em) from integracoes_segredos where chave like ''ifood\_%''), ''-infinity''::timestamptz))' || chr(10) || '        when ''chaves'' then (');
    execute d;
  end if;
end $$;

create or replace function public.api_ifood_testar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare e ifood_estado%rowtype; v_desde timestamptz;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce((p->>'ler')::boolean, false) then
    v_desde := nullif(p->>'desde', '')::timestamptz;
    select * into e from ifood_estado where id;
    if v_desde is null or e.ultima_consulta is null or e.ultima_consulta < v_desde then return jsonb_build_object('ok', true, 'pronto', false); end if;
    return jsonb_build_object('ok', true, 'pronto', true, 'certo', (coalesce(e.token_ok, false) and e.ultimo_erro is null), 'erro', e.ultimo_erro);
  end if;
  if (select count(*) from integracoes_segredos where chave in ('ifood_client_id', 'ifood_client_secret', 'ifood_merchant_id')) < 3 then
    return _falha('Digite antes o Client ID, o Client Secret e o código da loja (Merchant ID).');
  end if;
  perform public.chamar_edge('ifood-teste', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'desde', now());
end $$;
revoke all on function public.api_ifood_testar(jsonb) from public, anon;
grant execute on function public.api_ifood_testar(jsonb) to authenticated, service_role;


-- ======================================================================
-- 40-ifood-pedido-agendado.sql
-- ======================================================================
-- 40 · iFood: pedido AGENDADO só é despachado a partir do início da janela de entrega.
-- Antes, o "despachar" saía na hora e o iFood reprovou na homologação ("despachado antes da janela de entrega agendada").
-- Agora a ação fica guardada (pendente) e é enviada sozinha quando a janela abre.
create or replace function public.ifood_acoes_pendentes() returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'pedido', a.pedido_ifood, 'acao', a.acao, 'dados', a.dados, 'tentativas', a.tentativas) order by a.id), '[]'::jsonb)
  from (
    select x.* from ifood_acoes x
    where x.estado = 'pendente'
      and not (
        x.acao = 'despachar'
        and exists (
          select 1 from ifood_pedidos p
          where p.pedido_ifood = x.pedido_ifood
            and upper(coalesce(p.bruto->>'orderTiming', '')) = 'SCHEDULED'
            and coalesce(p.bruto->'schedule'->>'deliveryDateTimeStart', '') ~ '^\d{4}-\d{2}-\d{2}T'
            and (p.bruto->'schedule'->>'deliveryDateTimeStart')::timestamptz > now()
        )
      )
    order by x.id limit 20
  ) a
$$;
revoke all on function public.ifood_acoes_pendentes() from public, anon, authenticated;
grant execute on function public.ifood_acoes_pendentes() to service_role;


-- ======================================================================
-- 41-cupom-combo.sql
-- ======================================================================
-- 41 · Cupom "Combo por preço fixo": vale só quando o carrinho tem os produtos certos (ex.: 3 Smash + 1 Guaraná 1L por R$ 65).
-- O desconto = (preço normal dos itens do combo) − (preço do combo). A entrega NÃO entra na conta (é somada depois).
-- Pode rodar de novo sem erro (cada trecho confere se já foi aplicado).

alter table public.cupons add column if not exists regra jsonb;

create or replace function pg_temp.rep(d text, a text, b text) returns text language plpgsql as $f$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 80); end if;
  return replace(d, a, b);
end $f$;

-- 1) _cupom_calcular ganha 2 argumentos (itens do carrinho e forma de pagamento) e o tipo "combo"
do $do$
declare d text; d2 text;
begin
  if exists (select 1 from pg_proc where proname = '_cupom_calcular' and pronamespace = 'public'::regnamespace and pronargs = 7) then return; end if;
  select pg_get_functiondef('public._cupom_calcular(text,text,numeric,text,uuid)'::regprocedure) into d;
  d2 := pg_temp.rep(d, 'p_tipo text, p_user uuid)', 'p_tipo text, p_user uuid, p_itens jsonb, p_forma uuid)');
  d2 := pg_temp.rep(d2, '  v_conta contas_cliente; v_cc cupons_concedidos;', '  v_conta contas_cliente; v_cc cupons_concedidos; g record; v_arr numeric[]; v_soma numeric; v_msg text;');
  d2 := pg_temp.rep(d2, E'  elsif c.tipo = ''frete'' then\n    v_desc := 0;',
$c$  elsif c.tipo = 'combo' then
    if p_itens is null or jsonb_typeof(p_itens) <> 'array' or c.regra is null then
      return _falha('Este cupom vale para um combo de produtos. Coloque os produtos no carrinho e aplique de novo.');
    end if;
    v_soma := 0;
    for g in select coalesce(nullif(x->>'qtd', '')::int, 1) q, x->'produtos' ps from jsonb_array_elements(c.regra->'grupos') x loop
      select coalesce(array_agg(u.preco order by u.preco), '{}'::numeric[]) into v_arr
        from (
          select coalesce(nullif(_num(i.e->>'precoBase'), 0), pp.preco, 0) preco, greatest(1, floor(_num(coalesce(i.e->>'quantidade', i.e->>'qtd')))::int) n
            from jsonb_array_elements(p_itens) i(e)
            left join produto_precos pp on pp.produto_id = coalesce(_uuid(i.e->>'produtoId'), case when i.e->>'tipo' = 'produto' then _uuid(i.e->>'id') end) and pp.forma_pagamento_id = p_forma
           where coalesce(_uuid(i.e->>'produtoId'), case when i.e->>'tipo' = 'produto' then _uuid(i.e->>'id') end) in (select _uuid(y->>'id') from jsonb_array_elements(g.ps) y)
             and (not (i.e ? 'valorUnitario') or _num(i.e->>'valorUnitario') > 0)
        ) u cross join lateral generate_series(1, u.n);
      if coalesce(array_length(v_arr, 1), 0) < g.q then
        select string_agg(coalesce(nullif(x->>'qtd', ''), '1') || ' ' || (select string_agg(y->>'nome', ' ou ') from jsonb_array_elements(x->'produtos') y), ' + ') into v_msg from jsonb_array_elements(c.regra->'grupos') x;
        return _falha('Para usar este cupom coloque no carrinho: ' || v_msg || '.');
      end if;
      v_soma := v_soma + (select coalesce(sum(z), 0) from unnest(v_arr[1:g.q]) z);   -- usa as unidades mais baratas
    end loop;
    v_desc := round(v_soma - c.valor, 2);
    if v_desc <= 0 then return _falha('Este cupom não gera desconto com os itens do carrinho.'); end if;
  elsif c.tipo = 'frete' then
    v_desc := 0;$c$);
  execute d2;
  execute 'revoke all on function public._cupom_calcular(text,text,numeric,text,uuid,jsonb,uuid) from public, anon, authenticated';
  execute 'grant execute on function public._cupom_calcular(text,text,numeric,text,uuid,jsonb,uuid) to service_role';
end $do$;

-- a versão de 5 argumentos passa a chamar a de 7 (sem itens: cupom combo pede os produtos)
create or replace function public._cupom_calcular(p_codigo text, p_tel text, p_subtotal numeric, p_tipo text, p_user uuid) returns jsonb
language sql security definer set search_path to 'public' as $$ select public._cupom_calcular(p_codigo, p_tel, p_subtotal, p_tipo, p_user, null::jsonb, null::uuid) $$;

-- 2) validação do cupom (admin): aceita o tipo "combo" e lê as linhas "3 x Produto A, Produto B"
do $do$
declare d text; d2 text;
begin
  select pg_get_functiondef('public._cupom_validar(jsonb,uuid)'::regprocedure) into d;
  if position('''combo''' in d) > 0 then return; end if;
  d2 := pg_temp.rep(d, 'declare v_fx jsonb', 'declare l record; nm record; pr record; v_q int; v_ps jsonb; v_rt text; v_reg jsonb; v_fx jsonb');
  d2 := pg_temp.rep(d2, 'array[''percentual'',''fixo'',''frete'',''progressivo'']', 'array[''percentual'',''fixo'',''frete'',''progressivo'',''combo'']');
  d2 := pg_temp.rep(d2, '  c.codigo := v_cod; c.nome',
$c$  if v_tipo = 'combo' then
    v_rt := btrim(coalesce(p->>'regraTexto', ''));
    if v_rt = '' then
      select regra into v_reg from cupons where id = p_id;
      if v_reg is null then erro := 'Informe os produtos do combo, uma linha por grupo (ex.: 3 x Smash Catupiry, Smash Cheddar).'; return; end if;
    else
      v_reg := '{"grupos":[]}'::jsonb;
      for l in select btrim(x) ln from unnest(regexp_split_to_array(v_rt, E'\n')) x where btrim(x) <> '' loop
        if l.ln !~ '^\d{1,2}\s*[xX×]\s*\S' then erro := 'Linha inválida do combo: "' || left(l.ln, 60) || '". Use o modelo: 3 x Produto A, Produto B'; return; end if;
        v_q := (substring(l.ln from '^(\d{1,2})'))::int;
        if v_q < 1 then erro := 'A quantidade do combo precisa ser 1 ou mais.'; return; end if;
        v_ps := '[]'::jsonb;
        for nm in select btrim(x) n from unnest(string_to_array(regexp_replace(l.ln, '^\d{1,2}\s*[xX×]\s*', ''), ',')) x where btrim(x) <> '' loop
          select id, nome into pr from produtos where lower(btrim(nome)) = lower(nm.n) and ativo limit 1;
          if pr.id is null then erro := 'Produto não encontrado (ou desativado): "' || nm.n || '". Escreva o nome igual ao do cadastro.'; return; end if;
          v_ps := v_ps || jsonb_build_array(jsonb_build_object('id', pr.id, 'nome', pr.nome));
        end loop;
        if jsonb_array_length(v_ps) = 0 then erro := 'Informe ao menos um produto na linha "' || left(l.ln, 60) || '".'; return; end if;
        v_reg := jsonb_set(v_reg, '{grupos}', (v_reg->'grupos') || jsonb_build_array(jsonb_build_object('qtd', v_q, 'produtos', v_ps)));
      end loop;
      if jsonb_array_length(v_reg->'grupos') = 0 or jsonb_array_length(v_reg->'grupos') > 6 then erro := 'O combo precisa de 1 a 6 grupos de produtos.'; return; end if;
    end if;
    v_reg := jsonb_set(v_reg, '{preco}', to_jsonb(round(v_val, 2)));
  end if;
  c.regra := case when v_tipo = 'combo' then v_reg else null end;
  c.codigo := v_cod; c.nome$c$);
  execute d2;
end $do$;

-- 3) salvar / editar cupom guardam a regra
do $do$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.api_salvar_cupom(jsonb)'::regprocedure) into d;
  if position('regra' in d) = 0 then
    d2 := pg_temp.rep(d, 'automatico, validade_dias)', 'automatico, validade_dias, regra)');
    d2 := pg_temp.rep(d2, '(v.c).automatico, (v.c).validade_dias)', '(v.c).automatico, (v.c).validade_dias, (v.c).regra)');
    execute d2;
  end if;
  select pg_get_functiondef('public.api_editar_cupom(jsonb)'::regprocedure) into d;
  if position('regra' in d) = 0 then
    d2 := pg_temp.rep(d, 'validade_dias = (v.c).validade_dias', 'validade_dias = (v.c).validade_dias, regra = (v.c).regra');
    execute d2;
  end if;
end $do$;

-- 4) pré-visualização do cupom no carrinho: manda os itens e a forma de pagamento
do $do$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.api_validar_cupom_cardapio(jsonb)'::regprocedure) into d;
  if position('p_itens' in d) > 0 or position('p->''itens''' in d) > 0 then return; end if;
  d2 := pg_temp.rep(d, 'p->>''tipoEntrega'', auth.uid())', 'p->>''tipoEntrega'', auth.uid(), p->''itens'', _uuid(p->>''formaPagamentoId''))');
  execute d2;
end $do$;

-- 5) criação do pedido: usa os itens reais (preço base, sem adicionais) e a forma escolhida
do $do$
declare d text; d2 text;
begin
  select pg_get_functiondef('public._criar_pedido_publico(jsonb,uuid,boolean)'::regprocedure) into d;
  if position('''precoBase''' in d) > 0 then return; end if;
  d2 := pg_temp.rep(d, '_cupom_calcular(v_cod, v_tel, v_orig, v_tipo::text, v_user)', '_cupom_calcular(v_cod, v_tel, v_orig, v_tipo::text, v_user, v_itens_ok, v_forma.id)');
  d2 := pg_temp.rep(d2, '''custoUnitario'', v_custo_u, ''adicionaisIds'', v_ads_ids)', '''custoUnitario'', v_custo_u, ''adicionaisIds'', v_ads_ids, ''precoBase'', v_preco)');
  execute d2;
end $do$;

-- 6) cupom SMASH65: 3 Smash (Catupiry, Cheddar ou Tasty) + 1 Guaraná 1L por R$ 65,00
do $do$
declare v_smash jsonb; v_guar jsonb;
begin
  select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) into v_smash from produtos where nome in ('Smash Catupiry', 'Smash Cheddar', 'Smash Tasty') and ativo;
  select jsonb_agg(jsonb_build_object('id', id, 'nome', nome)) into v_guar from produtos where nome = 'Guaraná 1L' and ativo;
  if jsonb_array_length(coalesce(v_smash, '[]'::jsonb)) = 3 and jsonb_array_length(coalesce(v_guar, '[]'::jsonb)) = 1 then
    update cupons set tipo = 'combo', valor = 65, valor_minimo = 0,
           regra = jsonb_build_object('preco', 65, 'grupos', jsonb_build_array(jsonb_build_object('qtd', 3, 'produtos', v_smash), jsonb_build_object('qtd', 1, 'produtos', v_guar)))
     where codigo = 'SMASH65' and tipo = 'fixo';
  end if;
end $do$;


-- ======================================================================
-- 42-ifood-fecha-com-cardapio.sql
-- ======================================================================
-- 42 · iFood: o botão de fechar/abrir o cardápio também fecha/abre a loja no iFood.
-- (Admin/Operador usam "Fechar cardápio" um pouco antes de fechar o caixa: o iFood fecha junto.)
-- Ao abrir o caixa, a loja do iFood só abre se o cardápio NÃO estiver fechado à mão.
-- Pode rodar de novo sem erro.
create or replace function pg_temp.rep(d text, a text, b text) returns text language plpgsql as $f$
begin
  if position(a in d) = 0 then raise exception 'Trecho não encontrado: %', left(a, 80); end if;
  return replace(d, a, b);
end $f$;

do $do$
declare d text; d2 text;
begin
  select pg_get_functiondef('public.api_salvar_cardapio_fechamento(jsonb)'::regprocedure) into d;
  if position('loja_fechar' in d) = 0 then
    d2 := pg_temp.rep(d, 'v_antes jsonb; v_n int := 0;', 'v_antes jsonb; v_n int := 0; v_ant_ativo boolean;');
    d2 := pg_temp.rep(d2, E'  perform _cfg_gravar(''CardapioFechadoManual'', jsonb_build_object(''ativo'', v_ativo, ''mensagem'', v_msg));',
$c$  v_ant_ativo := coalesce((select (valor->>'ativo')::boolean from sistema where chave = 'CardapioFechadoManual'), false);
  perform _cfg_gravar('CardapioFechadoManual', jsonb_build_object('ativo', v_ativo, 'mensagem', v_msg));
  -- iFood: fechar/abrir o cardápio também fecha/abre a loja no iFood (só quando o estado mudou)
  if v_ativo is distinct from v_ant_ativo and public._integracao_ligada('ifood') then
    if v_ativo then
      update ifood_loja set fechada_por_nos = true where id;
      perform public._ifood_enfileirar('LOJA', 'loja_fechar', '{}'::jsonb);
    else
      update ifood_loja set fechada_por_nos = false, pausada_ate = null where id;
      perform public._ifood_enfileirar('LOJA', 'loja_abrir', '{}'::jsonb);
    end if;
  end if;$c$);
    execute d2;
  end if;

  select pg_get_functiondef('public._ifood_trg_caixa()'::regprocedure) into d;
  if position('CardapioFechadoManual' in d) = 0 then
    d2 := pg_temp.rep(d, 'if tg_op = ''INSERT'' and new.status::text = ''Aberto'' then',
      'if tg_op = ''INSERT'' and new.status::text = ''Aberto'' and not coalesce((select (valor->>''ativo'')::boolean from sistema where chave = ''CardapioFechadoManual''), false) then');
    execute d2;
  end if;
end $do$;


-- ======================================================================
-- 43-ifood-ligar-todas-sugestoes.sql
-- ======================================================================
-- 43: "Ligar todos os itens com nome igual" (Itens do iFood). Liga de uma vez todos os itens do iFood sem ligação
-- que têm sugestão única (mesmo nome de produto, adicional ou combo ativo). O resto continua para tratar à mão.
create or replace function public.api_ifood_ligar_item(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public'
as $$
declare v_chave text := p->>'chave'; v_tipo text := p->>'tipo'; v_id uuid := nullif(p->>'id', '')::uuid; v_ignorar boolean := coalesce((p->>'ignorar')::boolean, false);
  v_todas boolean := coalesce((p->>'todasSugestoes')::boolean, false); r record; s jsonb; v_n int := 0; v_resta int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_todas then
    for r in select chave, nome, tipo from ifood_itens where produto_id is null and combo_id is null and adicional_id is null and not ignorar loop
      s := public._ifood_sugestao(r.nome, r.tipo);
      if s is null then continue; end if;
      if s->>'tipo' = 'produto' then update ifood_itens set produto_id = (s->>'id')::uuid, ligado_em = now() where chave = r.chave;
      elsif s->>'tipo' = 'combo' then update ifood_itens set combo_id = (s->>'id')::uuid, ligado_em = now() where chave = r.chave;
      elsif s->>'tipo' = 'adicional' then update ifood_itens set adicional_id = (s->>'id')::uuid, ligado_em = now() where chave = r.chave;
      else continue; end if;
      v_n := v_n + 1;
    end loop;
    select count(*) into v_resta from ifood_itens where produto_id is null and combo_id is null and adicional_id is null and not ignorar;
    perform _auditar('Itens do iFood ligados em lote', v_n || ' item(ns) pelo nome igual');
    return api_ifood_itens('{}') || jsonb_build_object('ligados', v_n, 'restam', v_resta, 'message',
      v_n || ' item(ns) ligado(s) pelo nome igual.' || case when v_resta > 0 then ' Faltam ' || v_resta || ' para você tratar.' else ' Nada pendente.' end);
  end if;
  if not exists (select 1 from ifood_itens where chave = v_chave) then return _falha('Item não encontrado.'); end if;
  if v_ignorar then
    update ifood_itens set ignorar = true, produto_id = null, combo_id = null, adicional_id = null, ligado_em = now() where chave = v_chave;
  elsif v_tipo = 'produto' and exists (select 1 from produtos where id = v_id) then
    update ifood_itens set ignorar = false, produto_id = v_id, combo_id = null, adicional_id = null, ligado_em = now() where chave = v_chave;
  elsif v_tipo = 'combo' and exists (select 1 from combos where id = v_id) then
    update ifood_itens set ignorar = false, produto_id = null, combo_id = v_id, adicional_id = null, ligado_em = now() where chave = v_chave;
  elsif v_tipo = 'adicional' and exists (select 1 from adicionais where id = v_id) then
    update ifood_itens set ignorar = false, produto_id = null, combo_id = null, adicional_id = v_id, ligado_em = now() where chave = v_chave;
  elsif v_tipo = 'desligar' then
    update ifood_itens set ignorar = false, produto_id = null, combo_id = null, adicional_id = null, ligado_em = null where chave = v_chave;
  else return _falha('Escolha um item válido do sistema.'); end if;
  perform _auditar('Item do iFood ligado', v_chave || ' → ' || coalesce(v_tipo, '') || case when v_ignorar then ' (ignorar)' else '' end);
  return api_ifood_itens('{}');
end $$;
revoke all on function public.api_ifood_ligar_item(jsonb) from public, anon;
grant execute on function public.api_ifood_ligar_item(jsonb) to authenticated, service_role;


-- ======================================================================
-- 44-ifood-horario-loja.sql
-- ======================================================================
-- 44: iFood Merchant — horário de funcionamento da loja (editar no sistema e enviar; ler do iFood).
alter table ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar','negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler','catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','avaliacao_responder']));

create or replace function public.api_ifood_horario(p jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'horario', coalesce((select config->'horarioLoja' from integracoes_config where provedor = 'ifood'), '{}'::jsonb),
    'ifood', (select config->'horarioIfood' from integracoes_config where provedor = 'ifood'),
    'ifoodEm', (select config->>'horarioIfoodEm' from integracoes_config where provedor = 'ifood'));
end $$;

create or replace function public.api_ifood_horario_salvar(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
declare v_h jsonb := coalesce(p->'horario', '{}'::jsonb); v_dia text; v_t jsonb; v_ini text; v_fim text; v_envia boolean := coalesce((p->>'enviar')::boolean, false);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if jsonb_typeof(v_h) <> 'object' then return _falha('Horário inválido.'); end if;
  for v_dia in select jsonb_object_keys(v_h) loop
    if v_dia not in ('MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY') then return _falha('Dia inválido.'); end if;
    if jsonb_typeof(v_h->v_dia) <> 'array' or jsonb_array_length(v_h->v_dia) > 3 then return _falha('Use no máximo 3 faixas por dia.'); end if;
    for v_t in select * from jsonb_array_elements(v_h->v_dia) loop
      v_ini := v_t->>'inicio'; v_fim := v_t->>'fim';
      if v_ini !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or v_fim !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return _falha('Horário deve ser HH:MM (ex.: 18:00).'); end if;
      if v_fim <= v_ini then return _falha('Em ' || v_dia || ' o fechamento precisa ser depois da abertura (no mesmo dia).'); end if;
    end loop;
  end loop;
  update integracoes_config set config = config || jsonb_build_object('horarioLoja', v_h) where provedor = 'ifood';
  if not found then return _falha('Cadastre a integração do iFood primeiro.'); end if;
  perform _auditar('Horário do iFood salvo', case when v_envia then 'e enviado ao iFood' else 'só no sistema' end);
  if v_envia then
    if not _integracao_ligada('ifood') then return _falha('Salvo, mas o iFood está desligado: nada foi enviado.'); end if;
    perform _ifood_enfileirar('LOJA', 'loja_horario_enviar', jsonb_build_object('horario', v_h, 'em', now()));
  end if;
  return jsonb_build_object('ok', true, 'message', case when v_envia then 'Salvo. Enviando ao iFood (confira em instantes com "Ler do iFood").' else 'Salvo no sistema.' end) || api_ifood_horario('{}');
end $$;

create or replace function public.api_ifood_horario_ler(p jsonb default '{}'::jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  perform _ifood_enfileirar('LOJA', 'loja_horario_ler', jsonb_build_object('em', now()));
  return jsonb_build_object('ok', true, 'message', 'Pedido enviado ao iFood. Toque em "Atualizar" em alguns segundos.') || api_ifood_horario('{}');
end $$;

create or replace function public.ifood_horario_gravar(p_turnos jsonb) returns void
  language sql security definer set search_path to 'public' as $$
  update integracoes_config set config = config || jsonb_build_object('horarioIfood', coalesce(p_turnos, '[]'::jsonb), 'horarioIfoodEm', now()::text) where provedor = 'ifood'
$$;

revoke all on function public.api_ifood_horario(jsonb), public.api_ifood_horario_salvar(jsonb), public.api_ifood_horario_ler(jsonb), public.ifood_horario_gravar(jsonb) from public, anon;
grant execute on function public.api_ifood_horario(jsonb), public.api_ifood_horario_salvar(jsonb), public.api_ifood_horario_ler(jsonb) to authenticated, service_role;
grant execute on function public.ifood_horario_gravar(jsonb) to service_role;


-- ======================================================================
-- 46-ifood-catalogo-gestao.sql
-- ======================================================================
-- 46: iFood Catalog — gestão do cardápio no iFood pelo sistema (categorias, itens, grupos de complementos, complementos,
-- preço/status em massa). O sistema guarda o modelo aqui e o envia ao iFood pela Edge Function ifood-sync.
create table if not exists public.ifood_cat_modelo (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('categoria','item','grupo','opcao')),
  nome text not null,
  dados jsonb not null default '{}'::jsonb,
  estado text not null default 'rascunho' check (estado in ('rascunho','pendente','enviado','erro')),
  erro text,
  atualizado_em timestamptz not null default now()
);
alter table public.ifood_cat_modelo enable row level security;
revoke all on public.ifood_cat_modelo from anon, authenticated;

alter table ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar','negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler','catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','catalogo_modelo_enviar','catalogo_lote_preco','catalogo_lote_status','catalogo_opcao_preco','catalogo_opcao_status','avaliacao_responder']));

create or replace function public.api_ifood_cat(p jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'itens', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'nome', nome, 'dados', dados - 'fotoPendente' || jsonb_build_object('temFotoPendente', dados ? 'fotoPendente'), 'estado', estado, 'erro', erro, 'em', atualizado_em) order by tipo, nome) from ifood_cat_modelo where coalesce(dados->>'oculto', 'false') <> 'true'), '[]'::jsonb));
end $$;

create or replace function public.api_ifood_cat_salvar(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_tipo text := p->>'tipo'; v_nome text := left(btrim(coalesce(p->>'nome', '')), 120); v_d jsonb := coalesce(p->'dados', '{}'::jsonb); v_old jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_tipo not in ('categoria','item','grupo','opcao') then return _falha('Tipo inválido.'); end if;
  if v_nome = '' then return _falha('Informe o nome.'); end if;
  if jsonb_typeof(v_d) <> 'object' then return _falha('Dados inválidos.'); end if;
  if length(coalesce(v_d->>'fotoPendente', '')) > 700000 then return _falha('Foto grande demais. Escolha outra.'); end if;
  if v_d ? 'preco' and (coalesce(nullif(v_d->>'preco', ''), '0'))::numeric < 0 then return _falha('Preço inválido.'); end if;
  if v_id is null then
    insert into ifood_cat_modelo (tipo, nome, dados) values (v_tipo, v_nome, v_d) returning id into v_id;
  else
    select dados into v_old from ifood_cat_modelo where id = v_id and tipo = v_tipo;
    if not found then return _falha('Registro não encontrado.'); end if;
    -- campos controlados pelo servidor (ids do iFood e último estado enviado) não vêm da tela
    v_d := coalesce(p->'dados', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('ifoodId', v_old->'ifoodId', 'productId', v_old->'productId', 'enviado', v_old->'enviado'));
    if not (v_d ? 'foto') and v_old ? 'foto' then v_d := v_d || jsonb_build_object('foto', v_old->'foto'); end if;
    update ifood_cat_modelo set nome = v_nome, dados = v_d, estado = 'rascunho', erro = null, atualizado_em = now() where id = v_id;
  end if;
  perform _auditar('Catálogo do iFood editado', v_tipo || ': ' || v_nome);
  return api_ifood_cat('{}') || jsonb_build_object('id', v_id);
end $$;

create or replace function public.api_ifood_cat_excluir(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  update ifood_cat_modelo set dados = dados || '{"oculto": true}'::jsonb, atualizado_em = now() where id = (p->>'id')::uuid;
  perform _auditar('Catálogo do iFood: registro escondido no sistema', coalesce(p->>'id', ''));
  return api_ifood_cat('{}') || jsonb_build_object('message', 'Removido da lista (no iFood nada foi apagado).');
end $$;

create or replace function public.api_ifood_cat_enviar(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := (p->>'id')::uuid; r ifood_cat_modelo%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  select * into r from ifood_cat_modelo where id = v_id;
  if not found then return _falha('Registro não encontrado.'); end if;
  if r.tipo not in ('categoria','item') then return _falha('Envie pela categoria ou pelo item: grupos e complementos vão junto com o item.'); end if;
  update ifood_cat_modelo set estado = 'pendente', erro = null where id = v_id;
  perform _ifood_enfileirar('LOJA', 'catalogo_modelo_enviar', jsonb_build_object('chave', v_id::text, 'id', v_id));
  perform _auditar('Catálogo do iFood enviado', r.tipo || ': ' || r.nome);
  return api_ifood_cat('{}') || jsonb_build_object('message', 'Enviando ao iFood. Toque em Atualizar em alguns segundos.');
end $$;

-- preço/status em massa (itens) e de complementos: p = { modo: 'preco'|'status'|'opcao_preco'|'opcao_status', itens: [{id, valor}] }
create or replace function public.api_ifood_cat_lote(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
declare v_modo text := p->>'modo'; v_l jsonb := coalesce(p->'itens', '[]'::jsonb); e jsonb; v_acao text; v_tipo text; v_n int := 0;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  if v_modo not in ('preco','status','opcao_preco','opcao_status') then return _falha('Modo inválido.'); end if;
  if jsonb_typeof(v_l) <> 'array' or jsonb_array_length(v_l) = 0 then return _falha('Escolha ao menos um item.'); end if;
  v_tipo := case when v_modo like 'opcao%' then 'opcao' else 'item' end;
  v_acao := case v_modo when 'preco' then 'catalogo_lote_preco' when 'status' then 'catalogo_lote_status' when 'opcao_preco' then 'catalogo_opcao_preco' else 'catalogo_opcao_status' end;
  for e in select value from jsonb_array_elements(v_l) loop
    if not exists (select 1 from ifood_cat_modelo where id = (e->>'id')::uuid and tipo = v_tipo and coalesce(dados->>'enviado', '') <> '') then
      return _falha('Todos precisam já ter sido enviados ao iFood.');
    end if;
    if v_modo in ('preco','opcao_preco') and (coalesce(nullif(e->>'valor', ''), '-1'))::numeric < 0 then return _falha('Preço inválido.'); end if;
    if v_modo in ('status','opcao_status') and (e->>'valor') not in ('AVAILABLE','UNAVAILABLE') then return _falha('Status inválido.'); end if;
    v_n := v_n + 1;
  end loop;
  perform _ifood_enfileirar('LOJA', v_acao, jsonb_build_object('chave', gen_random_uuid()::text, 'itens', v_l));
  perform _auditar('Catálogo do iFood em massa', v_modo || ': ' || v_n || ' item(ns)');
  return jsonb_build_object('ok', true, 'message', v_n || ' item(ns) enviados ao iFood em uma chamada. Toque em Atualizar em alguns segundos.');
end $$;

-- usadas só pela Edge Function (service_role)
create or replace function public.ifood_cat_arvore(p_id uuid) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $$
declare r ifood_cat_modelo%rowtype; v_cat ifood_cat_modelo%rowtype; v_grupos jsonb := '[]'::jsonb; v_opcoes jsonb := '[]'::jsonb; g ifood_cat_modelo%rowtype; o jsonb; x ifood_cat_modelo%rowtype;
begin
  select * into r from ifood_cat_modelo where id = p_id;
  if not found then return null; end if;
  if r.tipo = 'item' then
    select * into v_cat from ifood_cat_modelo where id = nullif(r.dados->>'categoriaId', '')::uuid;
    for o in select value from jsonb_array_elements(coalesce(r.dados->'grupos', '[]'::jsonb)) loop
      select * into g from ifood_cat_modelo where id = nullif(o->>'id', '')::uuid and tipo = 'grupo';
      if found then
        v_grupos := v_grupos || jsonb_build_array(jsonb_build_object('id', g.id, 'nome', g.nome, 'dados', g.dados, 'min', coalesce(nullif(o->>'min', '')::int, 0), 'max', coalesce(nullif(o->>'max', '')::int, 1)));
        for x in select m.* from ifood_cat_modelo m where m.tipo = 'opcao' and m.id in (select nullif(oo->>'id', '')::uuid from jsonb_array_elements(coalesce(g.dados->'opcoes', '[]'::jsonb)) oo) loop
          if not exists (select 1 from jsonb_array_elements(v_opcoes) q where q->>'id' = x.id::text) then
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('id', x.id, 'nome', x.nome, 'dados', x.dados));
          end if;
        end loop;
      end if;
    end loop;
  end if;
  return jsonb_build_object('registro', jsonb_build_object('id', r.id, 'tipo', r.tipo, 'nome', r.nome, 'dados', r.dados),
    'categoria', case when v_cat.id is not null then jsonb_build_object('id', v_cat.id, 'nome', v_cat.nome, 'dados', v_cat.dados) end,
    'grupos', v_grupos, 'opcoes', v_opcoes);
end $$;

create or replace function public.ifood_cat_resultado(p_id uuid, p_estado text, p_erro text default null, p_patch jsonb default '{}'::jsonb) returns void
  language sql security definer set search_path to 'public' as $$
  update ifood_cat_modelo set estado = p_estado, erro = left(p_erro, 400), dados = (dados - 'fotoPendente') || coalesce(p_patch, '{}'::jsonb), atualizado_em = now() where id = p_id
$$;
create or replace function public.ifood_cat_patch(p_id uuid, p_patch jsonb) returns void
  language sql security definer set search_path to 'public' as $$
  update ifood_cat_modelo set dados = case when coalesce(p_patch, '{}'::jsonb) ? 'foto' then dados - 'fotoPendente' else dados end || coalesce(p_patch, '{}'::jsonb), atualizado_em = now() where id = p_id
$$;

revoke all on function public.api_ifood_cat(jsonb), public.api_ifood_cat_salvar(jsonb), public.api_ifood_cat_excluir(jsonb), public.api_ifood_cat_enviar(jsonb), public.api_ifood_cat_lote(jsonb), public.ifood_cat_arvore(uuid), public.ifood_cat_resultado(uuid, text, text, jsonb), public.ifood_cat_patch(uuid, jsonb) from public, anon;
grant execute on function public.api_ifood_cat(jsonb), public.api_ifood_cat_salvar(jsonb), public.api_ifood_cat_excluir(jsonb), public.api_ifood_cat_enviar(jsonb), public.api_ifood_cat_lote(jsonb) to authenticated, service_role;
grant execute on function public.ifood_cat_arvore(uuid), public.ifood_cat_resultado(uuid, text, text, jsonb), public.ifood_cat_patch(uuid, jsonb) to service_role;


-- ======================================================================
-- 47-ifood-lacunas.sql
-- ======================================================================
-- 47 · iFood: varredura na volta do Supabase (queda/contingência)
-- Se a consulta ao iFood ficar parada por mais de 3 minutos e voltar, grava a "lacuna", varre os pedidos do iFood feitos
-- dentro dela (o iFood guarda os eventos não lidos e entrega tudo na volta) e avisa Admin e Operador.
create table if not exists public.ifood_lacunas (
  id bigserial primary key,
  inicio timestamptz not null,
  fim timestamptz not null,
  pedidos int not null default 0,
  cancelados int not null default 0,
  detalhe jsonb not null default '[]'::jsonb,
  visto_em timestamptz,
  criado_em timestamptz not null default now()
);
alter table public.ifood_lacunas enable row level security;
revoke all on table public.ifood_lacunas from public, anon, authenticated;
grant all on table public.ifood_lacunas to service_role;

-- Conta os pedidos do iFood cujo horário de criação (no iFood) caiu dentro da lacuna.
create or replace function public._ifood_lacuna_varrer(p_id bigint) returns void
  language plpgsql security definer set search_path to 'public' as $$
declare l ifood_lacunas%rowtype; v_n int; v_c int; v_det jsonb;
begin
  select * into l from ifood_lacunas where id = p_id; if l.id is null then return; end if;
  select count(*)::int,
         count(*) filter (where lower(coalesce(estado,'')) like '%cancel%')::int,
         coalesce(jsonb_agg(jsonb_build_object('numero', numero_ifood, 'estado', estado, 'em', p.em) order by p.em), '[]'::jsonb)
    into v_n, v_c, v_det
    from (select numero_ifood, estado, coalesce((bruto->>'createdAt')::timestamptz, criado_em) em
            from ifood_pedidos where not coalesce(simulado, false)) p
   where p.em >= l.inicio and p.em <= l.fim + interval '1 minute';
  update ifood_lacunas set pedidos = v_n, cancelados = v_c, detalhe = v_det where id = p_id;
end $$;

create or replace function public.ifood_marcar_consulta(p_ok boolean, p_erro text DEFAULT NULL::text, p_token_ok boolean DEFAULT NULL::boolean)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare v_ant timestamptz; v_id bigint;
begin
  select ultima_consulta_ok into v_ant from ifood_estado where id;
  update ifood_estado set ultima_consulta = now(),
    ultima_consulta_ok = case when p_ok then now() else ultima_consulta_ok end,
    token_ok = coalesce(p_token_ok, token_ok),
    ultimo_erro = case when p_ok then null else left(p_erro, 300) end,
    ultimo_erro_em = case when p_ok then ultimo_erro_em else now() end, atualizado_em = now() where id;
  if not p_ok and p_erro is not null then perform public._integ_log('ifood', 'erro', p_erro); end if;
  -- lacuna só conta se a última consulta boa foi DEPOIS de o iFood ser ligado (ligar de novo após desligar não é queda)
  if p_ok and v_ant is not null and now() - v_ant > interval '3 minutes' and now() - v_ant < interval '3 days'
     and v_ant >= coalesce((select ligado_em from integracoes_config where provedor = 'ifood'), '-infinity'::timestamptz) then
    insert into ifood_lacunas(inicio, fim) values (v_ant, now()) returning id into v_id;
    perform _ifood_lacuna_varrer(v_id);
    begin
      perform _alertas_push('iFood: sistema ficou fora do ar',
        'De ' || to_char(v_ant at time zone 'America/Sao_Paulo', 'HH24:MI') || ' às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || ' o iFood não conseguiu entregar pedidos. Confira no portal do iFood.',
        'ifood-lacuna', array['Admin', 'Operador']);
    exception when others then null; end;
  end if;
end $$;

create or replace function public.api_ifood_lacunas(p jsonb default '{}'::jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if coalesce((p->>'marcarVisto')::boolean, false) then
    update ifood_lacunas set visto_em = now() where visto_em is null;
  end if;
  return jsonb_build_object('ok', true, 'lacunas', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'inicio', inicio, 'fim', fim, 'pedidos', pedidos, 'cancelados', cancelados, 'detalhe', detalhe) order by inicio desc)
      from (select * from ifood_lacunas where visto_em is null order by inicio desc limit 10) x), '[]'::jsonb));
end $$;

revoke all on function public._ifood_lacuna_varrer(bigint), public.api_ifood_lacunas(jsonb) from public, anon;
grant execute on function public.api_ifood_lacunas(jsonb) to authenticated, service_role;
grant execute on function public._ifood_lacuna_varrer(bigint) to service_role;


-- ======================================================================
-- 48-ifood-produto-novo.sql
-- ======================================================================
-- 48 · iFood: produto novo cadastrado no sistema vai ao iFood PAUSADO (para revisar foto e ativar)
-- Só envia se o iFood estiver ligado, o ajuste "produtoNovoNoIfood" não for false (padrão: ligado) e o produto tiver preço do iFood.
-- O código do item no iFood é o id do produto: os pedidos desse item já chegam ligados ao produto.
-- A categoria é criada no iFood se ainda não existir (a Edge Function ifood-sync envia a categoria antes do item).
create or replace function public._ifood_produto_novo(p_id uuid) returns void
  language plpgsql security definer set search_path to 'public' as $$
declare v_p produtos%rowtype; v_cat text; v_preco numeric; v_cid uuid; v_cfg jsonb;
begin
  if not _integracao_ligada('ifood') then return; end if;
  select config into v_cfg from integracoes_config where provedor = 'ifood';
  if coalesce((v_cfg->>'produtoNovoNoIfood')::boolean, true) is not true then return; end if;
  select * into v_p from produtos where id = p_id; if v_p.id is null then return; end if;
  select pp.preco into v_preco from produto_precos pp where pp.produto_id = p_id and pp.forma_pagamento_id = _ifood_forma();
  if coalesce(v_preco, 0) <= 0 then return; end if;
  if exists (select 1 from ifood_cat_modelo where id = p_id) then return; end if;
  select nome into v_cat from categorias where id = v_p.categoria_id;
  v_cat := coalesce(nullif(btrim(v_cat), ''), 'Cardápio');
  select id into v_cid from ifood_cat_modelo where tipo = 'categoria' and lower(btrim(nome)) = lower(v_cat) and coalesce(dados->>'oculto', '') <> 'true' order by atualizado_em limit 1;
  if v_cid is null then
    insert into ifood_cat_modelo (tipo, nome, dados) values ('categoria', v_cat, '{"status":"AVAILABLE"}'::jsonb) returning id into v_cid;
  end if;
  insert into ifood_cat_modelo (id, tipo, nome, dados, estado)
  values (p_id, 'item', left(v_p.nome, 120), jsonb_build_object('descricao', left(coalesce(v_p.descricao, ''), 1000), 'preco', v_preco, 'status', 'UNAVAILABLE', 'categoriaId', v_cid, 'criadoPeloSistema', true), 'pendente');
  perform _ifood_enfileirar('LOJA', 'catalogo_modelo_enviar', jsonb_build_object('chave', p_id::text, 'id', p_id));
  perform _push_admins('Produto novo enviado ao iFood (pausado)', v_p.nome || ': revise a foto e ative em Integrações → iFood → Cardápio no iFood.', 'ifood-produto-novo');
exception when others then null;
end $$;
revoke all on function public._ifood_produto_novo(uuid) from public, anon, authenticated;
grant execute on function public._ifood_produto_novo(uuid) to service_role;

-- api_add_produto: mesma função de sempre, com a chamada _ifood_produto_novo ao final
CREATE OR REPLACE FUNCTION public.api_add_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_id uuid := gen_random_uuid(); v_cat uuid := _uuid(p->>'categoria');
        v_ordem int; v_proprio uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do produto.'); end if;
  if exists (select 1 from produtos where lower(btrim(nome)) = lower(v_nome)) then return _falha('Já existe um produto com esse nome.'); end if;
  v_proprio := _estoque_proprio(null, v_nome, p->'estoqueProprio');
  select coalesce(max(ordem_cardapio), 0) + 1 into v_ordem from produtos where categoria_id is not distinct from v_cat;
  insert into produtos (id, nome, descricao, categoria_id, ativo, destaque, estoque_proprio_ingrediente_id, ordem_cardapio)
  values (v_id, v_nome, coalesce(p->>'descricao', ''), v_cat, true, coalesce((p->>'destaque')::boolean, false), v_proprio, v_ordem);
  perform _produto_gravar_precos(v_id, _precos_ou_base(p));
  perform _produto_gravar_receita(v_id, p->'ingredientes', v_proprio);
  perform _produto_gravar_adicionais(v_id, p->'adicionaisIds');
  perform _auditar('Produto cadastrado', v_nome);
  perform _ifood_produto_novo(v_id);
  return jsonb_build_object('ok', true, 'message', 'Produto cadastrado.', 'id', v_id);
end $function$;


-- ======================================================================
-- 49-sem-desconto-cupom.sql
-- ======================================================================
-- 49 · "Não aceita desconto nem cupom" em produtos e combos (preço já promocional)
-- O que faz:
--   * produtos.sem_desconto e combos.sem_desconto (padrão: não)
--   * cupom do cardápio: o desconto é calculado só sobre os itens que aceitam desconto (frete grátis do cupom continua valendo)
--   * desconto manual do Caixa (pede senha): idem, só sobre os itens que aceitam desconto
--   * o cardápio público enxerga a marca (v_cardapio_produtos / v_cardapio_combos) para avisar o cliente
--   * api_editar_sem_desconto(p) liga/desliga a marca (só Administrador)
-- Rode depois do 48. Pode rodar mais de uma vez (não duplica nada).

alter table public.produtos add column if not exists sem_desconto boolean not null default false;
alter table public.combos   add column if not exists sem_desconto boolean not null default false;

create or replace view public.v_cardapio_produtos as
 select id, nome, descricao, categoria_id, destaque, ordem_cardapio, foto_id_principal, foto_id_contingencia,
        foto_url_principal, foto_url_contingencia, foto_preferida, sem_desconto
   from public.produtos where ativo;
create or replace view public.v_cardapio_combos as
 select id, nome, categoria_id, destaque, ordem_cardapio, foto_id_principal, foto_id_contingencia,
        foto_url_principal, foto_url_contingencia, foto_preferida, sem_desconto
   from public.combos where ativo;

create or replace function public.api_editar_sem_desconto(p jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_prod uuid := nullif(btrim(coalesce(p->>'produtoId','')),'')::uuid;
        v_comb uuid := nullif(btrim(coalesce(p->>'comboId','')),'')::uuid;
        v_val boolean := coalesce((p->>'semDesconto')::boolean, false);
begin
  if not public.tem_nivel('Admin') then return public._negado(); end if;
  if (v_prod is null) = (v_comb is null) then return public._falha('Informe um produto ou um combo.'); end if;
  if v_prod is not null then
    update public.produtos set sem_desconto = v_val where id = v_prod;
  else
    update public.combos set sem_desconto = v_val where id = v_comb;
  end if;
  if not found then return public._falha('Item não encontrado.'); end if;
  return jsonb_build_object('ok', true, 'message', case when v_val then 'Este item não aceita desconto nem cupom.' else 'Este item volta a aceitar desconto e cupom.' end);
end $f$;
revoke all on function public.api_editar_sem_desconto(jsonb) from public, anon;
grant execute on function public.api_editar_sem_desconto(jsonb) to authenticated, service_role;

-- troca de texto dentro de uma função já existente (cada trecho tem que aparecer exatamente 1 vez)
create or replace function pg_temp.tb_trocar(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception 'trecho encontrado % vez(es) (esperado 1): %', n, left(a, 80); end if;
  return replace(d, a, b);
end $f$;

do $do$
declare o oid; d text; n int := 0;
begin
  -- 1) cupom do tipo "combo de produtos": produto marcado não conta
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_cupom_calcular'
            and pg_get_functiondef(p.oid) like '%valorUnitario%' and pg_get_functiondef(p.oid) not like '%sem_desconto%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$and (not (i.e ? 'valorUnitario') or _num(i.e->>'valorUnitario') > 0)$a$,
      $b$and (not (i.e ? 'valorUnitario') or _num(i.e->>'valorUnitario') > 0)
             and not coalesce((select pr.sem_desconto from produtos pr where pr.id = coalesce(_uuid(i.e->>'produtoId'), case when i.e->>'tipo' = 'produto' then _uuid(i.e->>'id') end)), false)$b$);
    execute d; n := n + 1;
  end loop;

  -- 2) pedido do cardápio: cupom só sobre os itens que aceitam desconto
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_criar_pedido_publico'
            and pg_get_functiondef(p.oid) like '%_cupom_calcular(v_cod%' and pg_get_functiondef(p.oid) not like '%v_sem_desc%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$v_cod text := ''; v_cup jsonb; v_desc numeric := 0;$a$,
      $b$v_blq boolean := false; v_sem_desc numeric := 0; v_cod text := ''; v_cup jsonb; v_desc numeric := 0;$b$);
    d := pg_temp.tb_trocar(d, $a$select count(*), coalesce(sum(a.preco), 0),$a$,
      $b$v_blq := coalesce(case when v_prod_id is not null then (select sem_desconto from produtos where id = v_prod_id) else (select sem_desconto from combos where id = v_comb_id) end, false);
    select count(*), coalesce(sum(a.preco), 0),$b$);
    d := pg_temp.tb_trocar(d, $a$v_orig := v_orig + round(v_qtd * (v_preco + v_extra), 2); v_custo := v_custo + v_qtd * v_custo_u;$a$,
      $b$v_orig := v_orig + round(v_qtd * (v_preco + v_extra), 2); v_custo := v_custo + v_qtd * v_custo_u;
    if v_blq then v_sem_desc := v_sem_desc + round(v_qtd * (v_preco + v_extra), 2); end if;$b$);
    d := pg_temp.tb_trocar(d, $a$v_cup := _cupom_calcular(v_cod, v_tel, v_orig, v_tipo::text, v_user, v_itens_ok, v_forma.id);$a$,
      $b$v_cup := _cupom_calcular(v_cod, v_tel, greatest(0, round(v_orig - v_sem_desc, 2)), v_tipo::text, v_user, v_itens_ok, v_forma.id);$b$);
    d := pg_temp.tb_trocar(d, $a$v_desc := (v_cup->>'desconto')::numeric; v_frete := (v_cup->>'freteGratis')::boolean;$a$,
      $b$if round(v_orig - v_sem_desc, 2) <= 0 and not coalesce((v_cup->>'freteGratis')::boolean, false) then return _falha('Os itens deste pedido têm preço promocional e não aceitam cupom.'); end if;
      v_desc := (v_cup->>'desconto')::numeric; v_frete := (v_cup->>'freteGratis')::boolean;$b$);
    execute d; n := n + 1;
  end loop;

  -- 3) Caixa: desconto manual só sobre os itens que aceitam desconto
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'api_iniciar_venda'
            and pg_get_functiondef(p.oid) not like '%v_sem_desc%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$v_orig numeric := 0; v_custo numeric := 0; v_total_item numeric;$a$,
      $b$v_sem_desc numeric := 0; v_elig numeric; v_orig numeric := 0; v_custo numeric := 0; v_total_item numeric;$b$);
    d := pg_temp.tb_trocar(d, $a$v_orig := v_orig + v_total_item; v_custo := v_custo + v_qtd * v_c;$a$,
      $b$v_orig := v_orig + v_total_item; v_custo := v_custo + v_qtd * v_c;
    if coalesce((select sem_desconto from produtos where id = _uuid(it.e->>'produtoId')), (select sem_desconto from combos where id = _uuid(it.e->>'comboId')), false) then v_sem_desc := v_sem_desc + v_total_item; end if;$b$);
    d := pg_temp.tb_trocar(d, $a$v_sol := _num(v_desc->>'valor', -1);$a$,
      $b$v_sol := _num(v_desc->>'valor', -1); v_elig := round(v_orig - v_sem_desc, 2);
    if v_elig <= 0 then return _falha('Os itens desta venda têm preço promocional e não aceitam desconto.'); end if;$b$);
    d := pg_temp.tb_trocar(d, $a$v_desc_val := round(v_orig * (v_sol / 100), 2);$a$,
      $b$v_desc_val := round(v_elig * (v_sol / 100), 2);$b$);
    d := pg_temp.tb_trocar(d, $a$if v_sol > v_orig then return _falha('O desconto fixo não pode ser maior que o valor da venda.'); end if;$a$,
      $b$if v_sol > v_elig then return _falha('O desconto fixo não pode ser maior que o valor dos itens que aceitam desconto (R$ ' || _dinheiro(v_elig) || ').'); end if;$b$);
    execute d; n := n + 1;
  end loop;
  raise notice 'funções atualizadas: %', n;
end $do$;


-- ======================================================================
-- 50-combo-com-escolha.sql
-- ======================================================================
-- 50 · Combo com escolha ("3 Smash": o cliente escolhe 3 entre os sabores, podendo repetir)
-- O que faz:
--   * combo_itens.escolha  = o produto é uma OPÇÃO de escolha (e não um item fixo do combo)
--   * combos.escolha_qtd   = quantos itens o cliente escolhe entre as opções (0 = combo comum, sem escolha)
--   * itens_venda.escolhas = o que o cliente escolheu em cada item vendido ([{produtoId, quantidade, nome}])
--   * o servidor confere a escolha (soma exata, só opções do combo, produtos ativos) no cardápio e no Caixa
--   * estoque, custo e cancelamento seguem o que foi escolhido (vendas antigas continuam como eram)
--   * o preço do combo continua fixo
-- Rode depois do 49. Pode rodar mais de uma vez (não duplica nada).

alter table public.combo_itens add column if not exists escolha boolean not null default false;
alter table public.combos      add column if not exists escolha_qtd integer not null default 0;
alter table public.itens_venda add column if not exists escolhas jsonb;

create or replace view public.v_cardapio_combo_itens as
 select ci.combo_id, ci.produto_id, ci.quantidade, ci.escolha
   from public.combo_itens ci join public.combos c on c.id = ci.combo_id and c.ativo;
create or replace view public.v_cardapio_combos as
 select id, nome, categoria_id, destaque, ordem_cardapio, foto_id_principal, foto_id_contingencia,
        foto_url_principal, foto_url_contingencia, foto_preferida, sem_desconto, escolha_qtd
   from public.combos where ativo;

-- confere a escolha de um combo e devolve a versão "limpa" (nomes do cadastro), o texto e o custo real
create or replace function public._combo_escolhas_validar(p_combo uuid, p_escolhas jsonb) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $f$
declare c combos%rowtype; r record; v_tot numeric := 0; v_texto text := ''; v_custo numeric := 0; v_arr jsonb := '[]'::jsonb; v_fixo numeric;
begin
  select * into c from combos where id = p_combo;
  if not found then return jsonb_build_object('ok', false, 'message', 'Combo não encontrado.'); end if;
  if coalesce(c.escolha_qtd, 0) <= 0 then return jsonb_build_object('ok', true, 'escolhas', null); end if;
  if jsonb_typeof(p_escolhas) is distinct from 'array' or jsonb_array_length(p_escolhas) > 20 then
    return jsonb_build_object('ok', false, 'message', 'Escolha os ' || c.escolha_qtd || ' itens de "' || c.nome || '".');
  end if;
  for r in
    select a.pid, a.q, p.nome, p.ativo, (ci.produto_id is not null) as permitido,
           coalesce((select max(pp.custo) from produto_precos pp where pp.produto_id = a.pid), 0) as custo
      from (select _uuid(x->>'produtoId') as pid, sum(_num(x->>'quantidade')) as q from jsonb_array_elements(p_escolhas) x group by 1) a
      left join produtos p on p.id = a.pid
      left join combo_itens ci on ci.combo_id = p_combo and ci.produto_id = a.pid and ci.escolha
     order by p.nome
  loop
    if r.pid is null or r.permitido is not true or not coalesce(r.ativo, false) then
      return jsonb_build_object('ok', false, 'message', 'Uma das opções escolhidas não está disponível em "' || c.nome || '".');
    end if;
    if r.q <= 0 or r.q <> floor(r.q) then return jsonb_build_object('ok', false, 'message', 'Quantidade inválida na escolha de "' || c.nome || '".'); end if;
    v_tot := v_tot + r.q; v_custo := v_custo + r.q * r.custo;
    v_texto := v_texto || case when v_texto <> '' then ', ' else '' end || r.q::int || 'x ' || r.nome;
    v_arr := v_arr || jsonb_build_array(jsonb_build_object('produtoId', r.pid, 'quantidade', r.q::int, 'nome', r.nome));
  end loop;
  if v_tot <> c.escolha_qtd then
    return jsonb_build_object('ok', false, 'message', 'Escolha exatamente ' || c.escolha_qtd || ' itens em "' || c.nome || '".');
  end if;
  select coalesce(sum(ci.quantidade * coalesce((select max(pp.custo) from produto_precos pp where pp.produto_id = ci.produto_id), 0)), 0)
    into v_fixo from combo_itens ci where ci.combo_id = p_combo and not ci.escolha;
  return jsonb_build_object('ok', true, 'escolhas', v_arr, 'texto', v_texto, 'custo', round(v_fixo + v_custo, 2));
end $f$;

create or replace function public._combo_escolhas_canon(p_combo uuid, p_esc jsonb) returns jsonb
language sql stable security definer set search_path to 'public' as $f$
  select case when p_combo is null or jsonb_typeof(p_esc) is distinct from 'array' then null
              else nullif(_combo_escolhas_validar(p_combo, p_esc)->'escolhas', 'null'::jsonb) end
$f$;

-- confere, no cadastro do combo, se a configuração da escolha faz sentido (null = ok)
create or replace function public._combo_escolha_valida(p jsonb) returns text
language plpgsql stable security definer set search_path to 'public' as $f$
declare v_q int := greatest(0, floor(coalesce(_num(p->>'escolhaQtd'), 0))::int); v_n int;
begin
  if jsonb_typeof(p->'itens') is distinct from 'array' then return null; end if;
  select count(*) into v_n from jsonb_array_elements(p->'itens') e where coalesce(e->>'escolha', '') in ('true', 't');
  if v_q = 0 and v_n = 0 then return null; end if;
  if v_q = 0 then return 'Informe quantos itens o cliente escolhe.'; end if;
  if v_n < 2 then return 'Marque pelo menos 2 produtos como opção de escolha.'; end if;
  if v_q > 20 then return 'O cliente pode escolher no máximo 20 itens.'; end if;
  return null;
end $f$;

revoke all on function public._combo_escolhas_validar(uuid, jsonb), public._combo_escolhas_canon(uuid, jsonb), public._combo_escolha_valida(jsonb) from public, anon, authenticated;
grant execute on function public._combo_escolhas_validar(uuid, jsonb), public._combo_escolhas_canon(uuid, jsonb), public._combo_escolha_valida(jsonb) to service_role;

create or replace function public._combo_gravar_itens(p_combo uuid, p_itens jsonb) returns void
language plpgsql security definer set search_path to 'public' as $f$
begin
  delete from combo_itens where combo_id = p_combo;
  insert into combo_itens (combo_id, produto_id, quantidade, escolha)
  select p_combo, _uuid(e->>'produtoId'), _num(e->>'quantidade')::int, coalesce(e->>'escolha', '') in ('true', 't')
  from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  where _uuid(e->>'produtoId') is not null and _num(e->>'quantidade') > 0;
end $f$;

-- custo mostrado do combo: itens fixos + (quantos o cliente escolhe × a opção mais cara)
create or replace function public._custo_combo(p_combo uuid) returns numeric
language sql stable security definer set search_path to 'public' as $f$
  select case when count(*) = 0 then null else round(
           coalesce(sum(case when ci.escolha then 0 else ci.quantidade * coalesce((select max(pp.custo) from produto_precos pp where pp.produto_id = ci.produto_id), 0) end), 0)
           + coalesce((select c.escolha_qtd from combos c where c.id = p_combo), 0)
             * coalesce(max(case when ci.escolha then (select max(pp.custo) from produto_precos pp where pp.produto_id = ci.produto_id) end), 0), 2) end
  from combo_itens ci where ci.combo_id = p_combo
$f$;

-- baixa/estorno de estoque: itens fixos + o que o cliente escolheu (sem escolha registrada = comportamento antigo)
create or replace function public._consumo(p_itens jsonb) returns table(ingrediente_id uuid, qtd numeric)
language sql stable security definer set search_path to 'public' as $f$
  with it as (
    select _uuid(e->>'produtoId') as produto_id, _uuid(e->>'comboId') as combo_id,
           _num(e->>'quantidade') as q, e->'adicionaisIds' as ads, e->'escolhas' as esc
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  ), consumo as (
    select pi.ingrediente_id, pi.quantidade_por_unidade * it.q as qtd
      from it join produto_ingredientes pi on pi.produto_id = it.produto_id
    union all
    select pi.ingrediente_id, pi.quantidade_por_unidade * ci.quantidade * it.q
      from it join combo_itens ci on ci.combo_id = it.combo_id and (not ci.escolha or jsonb_typeof(it.esc) is distinct from 'array')
              join produto_ingredientes pi on pi.produto_id = ci.produto_id
    union all
    select pi.ingrediente_id, pi.quantidade_por_unidade * esc.q * it.q
      from it
      cross join lateral (select _uuid(x->>'produtoId') as pid, _num(x->>'quantidade') as q
                            from jsonb_array_elements(case when jsonb_typeof(it.esc) = 'array' then it.esc else '[]'::jsonb end) x) esc
      join combo_itens cp on cp.combo_id = it.combo_id and cp.produto_id = esc.pid and cp.escolha
      join produto_ingredientes pi on pi.produto_id = esc.pid
    union all
    select a.ingrediente_id, coalesce(nullif(a.quantidade_descontar, 0), 1) * it.q
      from it
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(it.ads) = 'array' then it.ads else '[]'::jsonb end) x
      join adicionais a on a.id = _uuid(x)
      where a.ingrediente_id is not null
  )
  select c.ingrediente_id, sum(c.qtd) from consumo c where c.ingrediente_id is not null group by c.ingrediente_id having sum(c.qtd) <> 0
$f$;

create or replace function public._itens_da_venda(p_venda uuid) returns jsonb
language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', i.produto_id, 'comboId', i.combo_id, 'quantidade', i.quantidade,
                                               'adicionaisIds', to_jsonb(i.adicionais_ids), 'escolhas', i.escolhas)), '[]'::jsonb)
  from itens_venda i where i.venda_id = p_venda
$f$;

-- troca de texto dentro de uma função já existente (cada trecho tem que aparecer exatamente 1 vez)
create or replace function pg_temp.tb_trocar(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception 'trecho encontrado % vez(es) (esperado 1): %', n, left(a, 80); end if;
  return replace(d, a, b);
end $f$;

do $do$
declare o oid; d text; n int := 0;
  ins_cab constant text := 'insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)';
  canon constant text := ', _combo_escolhas_canon(_uuid(e->>''comboId''), e->''escolhas'')';
begin
  -- cadastro do combo: validação e quantos o cliente escolhe
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'api_add_combo' and pg_get_functiondef(p.oid) not like '%escolha%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$if v_nome = '' then return _falha('Informe o nome do combo.'); end if;$a$,
      $b$if v_nome = '' then return _falha('Informe o nome do combo.'); end if;
  if _combo_escolha_valida(p) is not null then return _falha(_combo_escolha_valida(p)); end if;$b$);
    d := pg_temp.tb_trocar(d, $a$perform _combo_gravar_itens(v_id, p->'itens');$a$,
      $b$perform _combo_gravar_itens(v_id, p->'itens');
  update combos set escolha_qtd = greatest(0, floor(coalesce(_num(p->>'escolhaQtd'), 0))::int) where id = v_id;
  perform _recalc_combos(array[v_id]);$b$);
    execute d; n := n + 1;
  end loop;
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'api_editar_combo' and pg_get_functiondef(p.oid) not like '%escolha%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$if v_nome = '' then return _falha('Informe o nome do combo.'); end if;$a$,
      $b$if v_nome = '' then return _falha('Informe o nome do combo.'); end if;
  if _combo_escolha_valida(p) is not null then return _falha(_combo_escolha_valida(p)); end if;$b$);
    d := pg_temp.tb_trocar(d, $a$if jsonb_typeof(p->'itens') = 'array' then perform _combo_gravar_itens(v_id, p->'itens'); end if;$a$,
      $b$if jsonb_typeof(p->'itens') = 'array' then
    perform _combo_gravar_itens(v_id, p->'itens');
    update combos set escolha_qtd = greatest(0, floor(coalesce(_num(p->>'escolhaQtd'), 0))::int) where id = v_id;
    perform _recalc_combos(array[v_id]);
  end if;$b$);
    execute d; n := n + 1;
  end loop;

  -- pedido do cardápio
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_criar_pedido_publico'
            and pg_get_functiondef(p.oid) like '%v_sem_desc%' and pg_get_functiondef(p.oid) not like '%v_esc jsonb%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$v_blq boolean := false;$a$, $b$v_esc jsonb; v_ev jsonb; v_blq boolean := false;$b$);
    d := pg_temp.tb_trocar(d, $a$v_blq := coalesce(case when v_prod_id is not null then$a$,
      $b$v_esc := null; v_ev := null;
    if v_comb_id is not null then
      v_ev := _combo_escolhas_validar(v_comb_id, it.e->'escolhas');
      if not coalesce((v_ev->>'ok')::boolean, false) then return _falha(coalesce(v_ev->>'message', 'Escolha inválida no combo.')); end if;
      if jsonb_typeof(v_ev->'escolhas') = 'array' then v_esc := v_ev->'escolhas'; v_custo_u := (v_ev->>'custo')::numeric; end if;
    end if;
    v_blq := coalesce(case when v_prod_id is not null then$b$);
    d := pg_temp.tb_trocar(d, $a$'descricao', v_nome_item || v_ads || case when v_obs_item <> '' then ' — Obs: ' || v_obs_item else '' end,$a$,
      $b$'descricao', v_nome_item || coalesce(' (' || (v_ev->>'texto') || ')', '') || v_ads || case when v_obs_item <> '' then ' — Obs: ' || v_obs_item else '' end,$b$);
    d := pg_temp.tb_trocar(d, $a$'custoUnitario', v_custo_u, 'adicionaisIds', v_ads_ids, 'precoBase', v_preco));$a$,
      $b$'custoUnitario', v_custo_u, 'adicionaisIds', v_ads_ids, 'precoBase', v_preco, 'escolhas', v_esc));$b$);
    d := pg_temp.tb_trocar(d, ins_cab, replace(ins_cab, 'adicionais_ids)', 'adicionais_ids, escolhas)'));
    d := pg_temp.tb_trocar(d, E'\'{}\')\n  from jsonb_array_elements(v_itens_ok) e;', E'\'{}\')' || canon || E'\n  from jsonb_array_elements(v_itens_ok) e;');
    execute d; n := n + 1;
  end loop;

  -- venda do Caixa (e do garçom)
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'api_iniciar_venda'
            and pg_get_functiondef(p.oid) like '%v_sem_desc%' and pg_get_functiondef(p.oid) not like '%v_evc%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$v_sem_desc numeric := 0; v_elig numeric;$a$, $b$v_ev jsonb; v_evc numeric; v_sem_desc numeric := 0; v_elig numeric;$b$);
    d := pg_temp.tb_trocar(d, $a$v_nome_item := coalesce(nullif(it.e->>'descricao', ''), 'item');$a$,
      $b$v_nome_item := coalesce(nullif(it.e->>'descricao', ''), 'item');
    v_ev := null; v_evc := null;
    if _uuid(it.e->>'comboId') is not null then
      v_ev := _combo_escolhas_validar(_uuid(it.e->>'comboId'), it.e->'escolhas');
      if not coalesce((v_ev->>'ok')::boolean, false) then return _falha(coalesce(v_ev->>'message', 'Escolha inválida no combo.')); end if;
      if jsonb_typeof(v_ev->'escolhas') = 'array' then v_evc := (v_ev->>'custo')::numeric; end if;
    end if;$b$);
    d := pg_temp.tb_trocar(d, 'abs(cp.custo - v_c) <= 0.011', 'abs(coalesce(v_evc, cp.custo) - v_c) <= 0.011');
    d := pg_temp.tb_trocar(d, ins_cab, replace(ins_cab, 'adicionais_ids)', 'adicionais_ids, escolhas)'));
    d := pg_temp.tb_trocar(d, E'x), \'{}\')\n  from jsonb_array_elements(v_itens) e;', E'x), \'{}\')' || canon || E'\n  from jsonb_array_elements(v_itens) e;');
    execute d; n := n + 1;
  end loop;

  -- pagamento online (Mercado Pago): a venda nasce da reserva
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_mp_criar_venda' and pg_get_functiondef(p.oid) not like '%escolhas%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, ins_cab, replace(ins_cab, 'adicionais_ids)', 'adicionais_ids, escolhas)'));
    d := pg_temp.tb_trocar(d, E'\'{}\')\n  from jsonb_array_elements(r.itens) e;', E'\'{}\')' || canon || E'\n  from jsonb_array_elements(r.itens) e;');
    execute d; n := n + 1;
  end loop;

  -- edição de venda: mantém a escolha dos itens que já tinham
  for o in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_editar_venda_base' and pg_get_functiondef(p.oid) not like '%escolhas%' loop
    d := pg_get_functiondef(o);
    d := pg_temp.tb_trocar(d, $a$'custoUnitario', v_c, 'adicionaisIds', v_ads));$a$,
      $b$'custoUnitario', v_c, 'adicionaisIds', v_ads,
                                                                 'escolhas', coalesce(case when jsonb_typeof(it.e->'escolhas') = 'array' then it.e->'escolhas' end, (select iv.escolhas from itens_venda iv where iv.venda_id = v.id and iv.descricao = it.e->>'descricao' limit 1))));$b$);
    d := pg_temp.tb_trocar(d, ins_cab, replace(ins_cab, 'adicionais_ids)', 'adicionais_ids, escolhas)'));
    d := pg_temp.tb_trocar(d, E'\'{}\')\n  from jsonb_array_elements(v_novos) e;', E'\'{}\')' || canon || E'\n  from jsonb_array_elements(v_novos) e;');
    execute d; n := n + 1;
  end loop;
  raise notice 'funções atualizadas: %', n;
end $do$;


-- ======================================================================
-- 51-permissoes-e-limpeza-cron.sql
-- ======================================================================
-- =====================================================================
-- 51 - Permissões explícitas (mudança do Supabase de 30/10/2026) e
--      limpeza diária do histórico do agendador (cron)
-- ---------------------------------------------------------------------
-- POR QUE: a partir de 30/10/2026 o Supabase deixa de dar permissão
-- automática às tabelas novas do schema public. Este arquivo grava, de
-- forma explícita, exatamente as permissões que o banco tem hoje
-- (conferidas no banco ao vivo em 25/10/2026). Assim, se for preciso
-- refazer o banco do zero, nada fica sem acesso.
--
-- SEGURO para rodar no banco atual: só CONCEDE o que já existe (não
-- tira nada, não apaga dado). Pode rodar mais de uma vez.
-- Tabela/visão que não existir é pulada sem erro.
--
-- REGRA PARA O FUTURO: toda tabela nova criada nos próximos arquivos
-- (52 em diante) já vem com o seu próprio GRANT no mesmo arquivo.
-- =====================================================================

create or replace function pg_temp.tb_grant(p_tipo text, p_nome text, p_papel text, p_privs text)
returns void language plpgsql as $f$
declare v_privs text := p_privs;
begin
  if to_regclass('public.' || quote_ident(p_nome)) is null then
    raise notice 'pulado (não existe): %', p_nome;
    return;
  end if;
  -- MAINTAIN só existe a partir do Postgres 17
  if current_setting('server_version_num')::int < 170000 then
    v_privs := regexp_replace(regexp_replace(v_privs, 'MAINTAIN,\s*', ''), ',\s*MAINTAIN', '');
    if v_privs = 'MAINTAIN' then return; end if;
  end if;
  execute format('grant %s on %s public.%I to %I', v_privs,
                 case when p_tipo = 's' then 'sequence' else 'table' end, p_nome, p_papel);
end $f$;

grant usage on schema public to anon, authenticated, service_role;

do $$
begin
  perform pg_temp.tb_grant('t', 'adicionais', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'adicionais', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_ajuda', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_ajuda', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_cache', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_config', 'authenticated', 'MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_log', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_log', 'authenticated', 'MAINTAIN, REFERENCES, SELECT, TRIGGER');
  perform pg_temp.tb_grant('t', 'ai_segredos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_uso', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ai_uso', 'authenticated', 'MAINTAIN, REFERENCES, SELECT, TRIGGER');
  perform pg_temp.tb_grant('t', 'ajustes_pos_venda', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ajustes_pos_venda', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'alertas_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'alertas_config', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'alertas_envios', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'alertas_envios', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'anonimizar_arquivo_fila', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'arquivo_historico', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'arquivo_historico', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'auditoria', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'auditoria', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'backup_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'backup_config', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'backups', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'backups', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'brindes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'brindes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'caixa_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'caixa_liberacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'caixa_sessoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'caixa_sessoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'cardapio_aparelhos_equipe', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'cardapio_visitas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'categorias', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'categorias', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'chat_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'chat_config', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'chat_conversas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'chat_conversas', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'chat_ia_cotas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'chat_mensagens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'chat_mensagens', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'chat_tokens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'clientes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'clientes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'combo_itens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'combo_itens', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'combo_precos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'combo_precos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'combos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'combos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_custos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_custos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_itens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_pagamentos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_pagamentos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_vinculos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'compra_vinculos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'compras', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'configuracoes_fotos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'configuracoes_fotos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'contas_acessos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contas_beneficios', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contas_cliente', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contas_enderecos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contas_pedidos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contingencia_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contingencia_config', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'contingencia_reconciliada', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'contingencia_reconciliada', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'cupons', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'cupons', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'cupons_concedidos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'cupons_usos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'cupons_usos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'despesas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'despesas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'despesas_recorrentes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'despesas_recorrentes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'entrega_destinos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'entregador_posicoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'entregador_posicoes', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'entregas_fechadas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'entregas_fechadas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'erros_cliente', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'erros_cliente', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'escala_padrao', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'escala_padrao', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'escala_trocas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'escala_trocas', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'escala_turnos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'escala_turnos', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'espaco_historico', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'estoque', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'estoque', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'etiqueta_impressoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'etiqueta_itens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos_custos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos_custos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos_recebimentos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'eventos_recebimentos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'evidencias_foto', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'faq_publico', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'faq_publico', 'authenticated', 'DELETE, INSERT, SELECT, UPDATE');
  perform pg_temp.tb_grant('t', 'fechamentos_entrega', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fechamentos_entrega', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'feedbacks', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'feedbacks', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'fidelidade', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fidelidade', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'fidelidade_marcas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fila_sync', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fila_sync', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'fiscal_empresa', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fiscal_empresa', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'fiscal_perfis', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fiscal_perfis', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'formas_pagamento', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'formas_pagamento', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'fornecedores', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fotos_historico', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'fotos_historico', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'funcionario_pagamentos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'funcionario_pagamentos', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'funcionarios', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'funcionarios', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'ifood_acoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_acoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_avaliacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_avaliacoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_cat_modelo', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_estado', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_estado', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_eventos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_eventos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_itens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_itens', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_lacunas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_loja', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_loja', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_negociacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_negociacoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_pedidos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_pedidos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_precos_hist', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_precos_hist', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_repasses', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_repasses', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_token', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ifood_token', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'indicacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'indicacoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_config', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_log', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_log', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_segredos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'integracoes_segredos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'integridade_checks', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'integridade_checks', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'itens_venda', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'itens_venda', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'mesas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'mesas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'mesas_codigos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'mesas_codigos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'movimentacoes_estoque', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'movimentacoes_estoque', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'nfce_inutilizacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'nfce_inutilizacoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'nfce_notas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'nfce_notas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'ocorrencias', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ocorrencias', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'pagamentos_online', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'pagamentos_online_eventos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'pagamentos_venda', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'pagamentos_venda', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'pedido_destinos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'pedido_destinos', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'pedidos_reserva', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ponto_registros', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'ponto_registros', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'ponto_rosto', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'preco_historico', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'preco_historico', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_adicionais', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_adicionais', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_ingredientes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_ingredientes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_precos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'produto_precos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'produtos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'produtos', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'promocoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'promocoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'push_cliente_pedidos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'push_clientes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'push_inscricoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'reembolsos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'reembolsos', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'requisicoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'requisicoes', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'sangrias', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'sangrias', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'sistema', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'sistema', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'sync_estado', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'sync_estado', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'tentativas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'tentativas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'usuarios', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'usuarios', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'vendas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'vendas', 'authenticated', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, UPDATE');
  perform pg_temp.tb_grant('t', 'vendas_resumo_arquivo', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'versoes_sync', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'faq_publico', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_adicionais', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_adicionais', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_adicionais', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_categorias', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_categorias', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_categorias', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_combo_itens', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_combo_itens', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_combo_itens', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_combos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_combos', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_combos', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_config', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_config', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_config', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_esgotados', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_esgotados', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_esgotados', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_formas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_formas', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_formas', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_mais_pedidos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_mais_pedidos', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_mais_pedidos', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_precos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_precos', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_precos', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_produtos', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_produtos', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_produtos', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_status', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_cardapio_status', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_cardapio_status', 'anon', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_fidelidade', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_fidelidade', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_formas_operacional', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_formas_operacional', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_indicacoes', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_indicacoes', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_itens_venda', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_itens_venda', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_mesas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_mesas', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_ocorrencias', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_ocorrencias', 'authenticated', 'SELECT');
  perform pg_temp.tb_grant('t', 'v_sessao_aberta', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_sessao_aberta', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('t', 'v_vendas', 'service_role', 'DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE');
  perform pg_temp.tb_grant('t', 'v_vendas', 'authenticated', 'MAINTAIN, SELECT');
  perform pg_temp.tb_grant('s', 'ai_ajuda_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ai_ajuda_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ai_log_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ai_log_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'anonimizar_arquivo_fila_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'anonimizar_arquivo_fila_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'arquivo_historico_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'arquivo_historico_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'auditoria_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'auditoria_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'chat_mensagens_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'chat_mensagens_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'erros_cliente_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'erros_cliente_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'fila_sync_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'fila_sync_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'fotos_historico_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'fotos_historico_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_acoes_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_acoes_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_lacunas_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_lacunas_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_precos_hist_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ifood_precos_hist_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'integracoes_log_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'integracoes_log_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'integridade_checks_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'integridade_checks_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'nfce_inutilizacoes_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'nfce_inutilizacoes_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'nfce_notas_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'nfce_notas_id_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ocorrencias_numero_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'ocorrencias_numero_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'vendas_numero_pedido_seq', 'service_role', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'vendas_numero_pedido_seq', 'authenticated', 'SELECT, UPDATE, USAGE');
  perform pg_temp.tb_grant('s', 'pagamentos_online_eventos_id_seq', 'service_role', 'SELECT, UPDATE, USAGE');
end $$;

-- ---------------------------------------------------------------------
-- Limpeza diária do histórico do agendador (já ligada no banco ao vivo
-- desde 24/10/2026). Apaga execuções com sucesso com mais de 3 dias e
-- qualquer execução com mais de 14 dias. Só cria se ainda não existir.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'limpar-historico-cron') then
    perform cron.schedule('limpar-historico-cron', '35 6 * * *',
      $c$delete from cron.job_run_details
       where (status = 'succeeded' and start_time < now() - interval '3 days')
          or start_time < now() - interval '14 days'$c$);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Avisos de segurança do Supabase (25/10/2026)
-- - 5 funções auxiliares sem "search_path" fixo: fixa o caminho (não
--   muda o resultado, são cálculos simples).
-- - _zz_teste_delete: sobra de teste vazia (begin null; end), não é
--   usada em lugar nenhum. Removida.
-- (As visões do cardápio "security definer" são de propósito: mostram
--  ao cliente só o que pode ser público. Ficam como estão.)
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['public._alertas_padrao()', 'public._escala_segunda(date)',
    'public._dist_metros(double precision,double precision,double precision,double precision)',
    'public._dist_descritor(double precision[],double precision[])'] loop
    if to_regprocedure(f) is not null then
      execute format('alter function %s set search_path = pg_catalog, public', f);
    end if;
  end loop;
end $$;
drop function if exists public._zz_teste_delete();

-- ---------------------------------------------------------------------
-- Sobra de agendamento: "compactar-1792355920" foi uma compactação de
-- uma vez só (18/10/2026 às 20:38), mas ficou marcada para TODO ano no
-- dia 18/10. Ela trava as tabelas de vendas enquanto roda. Removida.
-- ---------------------------------------------------------------------
do $$
declare j record;
begin
  -- só a sobra anual (a compactação marcada para todo 18/10); compactações de uma vez, marcadas pelo arquivamento, ficam
  for j in select jobname from cron.job where jobname like 'compactar-%' and schedule ~ '^\d+ \d+ 18 10 \*$' and jobname = 'compactar-1792355920' loop
    perform cron.unschedule(j.jobname);
  end loop;
end $$;


-- ======================================================================
-- 52-erros-visiveis.sql
-- ======================================================================
-- =====================================================================
-- 52 - Nenhum erro discreto
-- ---------------------------------------------------------------------
-- 1) Os erros que acontecem no CARDÁPIO (cliente sem login) passam a ser
--    registrados também (antes só os da equipe logada). Sem nome, sem
--    telefone, sem IP aberto: só a mensagem, a tela e a versão do app.
--    O IP vira um código embaralhado (md5) só para limitar abuso.
-- 2) Além dos erros de programa ("error"/"promise"), passa a registrar
--    os AVISOS DE FALHA que a tela mostrou para a pessoa ("aviso"),
--    por exemplo "Não foi possível concluir agora (erro 500)".
-- 3) Admin/Desenvolvedor: lista dos erros dos últimos dias (tela
--    Conexão e servidores → Erros do sistema) e botão "Resolvido".
-- Tudo aditivo. Pode rodar mais de uma vez.
-- =====================================================================

alter table public.erros_cliente add column if not exists ip_hash text not null default '';
alter table public.erros_cliente add column if not exists resolvido_em timestamptz;

alter table public.erros_cliente drop constraint if exists erros_cliente_tipo_check;
alter table public.erros_cliente add constraint erros_cliente_tipo_check
  check (tipo = any (array['error'::text, 'promise'::text, 'aviso'::text]));

create index if not exists erros_cliente_ultima_idx on public.erros_cliente (ultima_em desc);

-- equipe logada (mesma função de antes, agora aceita "aviso")
create or replace function public.registrar_erro_cliente(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  uid uuid := auth.uid(); hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  tp text; msg text; ori text; pil text; h text; vezes int; novos int; total int;
begin
  if uid is null or auth_nivel() is null or p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false); end if;
  tp := case when p->>'tipo' in ('promise', 'aviso') then p->>'tipo' else 'error' end;
  msg := erro_limpa_(p->>'mensagem', 300); ori := erro_limpa_(p->>'origem', 120); pil := erro_limpa_(p->>'pilha', 600);
  if msg = '' then return jsonb_build_object('ok', false); end if;
  h := md5(tp || '|' || msg || '|' || ori);
  vezes := case when (p->>'vezes') ~ '^[0-9]{1,2}$' then greatest((p->>'vezes')::int, 1) else 1 end;
  update erros_cliente set ocorrencias = least(ocorrencias + vezes, 9999), ultima_em = now() where hash = h and dia = hoje;
  if found then return jsonb_build_object('ok', true, 'novo', false); end if;
  select count(*) into novos from erros_cliente where usuario_id = uid and criado_em > now() - interval '1 hour';
  select count(*) into total from erros_cliente where dia = hoje and usuario_id is not null;
  if novos >= 20 or total >= 300 then return jsonb_build_object('ok', false, 'motivo', 'limite'); end if;
  insert into erros_cliente (usuario_id, nivel, tipo, mensagem, origem, pilha, tela, versao, aparelho, hash, ocorrencias)
  values (uid, coalesce(ia_nivel_real(), '?'), tp, msg, ori, pil,
          left(regexp_replace(coalesce(p->>'tela', ''), '[^a-zA-Z0-9_-]', '', 'g'), 40),
          left(regexp_replace(coalesce(p->>'versao', ''), '[^a-zA-Z0-9._-]', '', 'g'), 30),
          erro_limpa_(p->>'aparelho', 80), h, vezes)
  on conflict (hash, dia) do update set ocorrencias = least(erros_cliente.ocorrencias + vezes, 9999), ultima_em = now();
  return jsonb_build_object('ok', true, 'novo', true);
end $function$;

-- cliente do cardápio (sem login). Limites: 10 novos por hora por IP, 300 novos por dia no total.
create or replace function public.registrar_erro_publico(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  tp text; msg text; ori text; pil text; h text; vezes int; novos int; total int; v_ip text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false); end if;
  tp := case when p->>'tipo' in ('promise', 'aviso') then p->>'tipo' else 'error' end;
  msg := erro_limpa_(p->>'mensagem', 300); ori := erro_limpa_(p->>'origem', 120); pil := erro_limpa_(p->>'pilha', 600);
  if msg = '' then return jsonb_build_object('ok', false); end if;
  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1);
  exception when others then v_ip := ''; end;
  v_ip := case when v_ip = '' then '' else left(md5('txb-erro|' || v_ip), 16) end;
  h := md5('cardapio|' || tp || '|' || msg || '|' || ori);
  vezes := case when (p->>'vezes') ~ '^[0-9]{1,2}$' then greatest((p->>'vezes')::int, 1) else 1 end;
  update erros_cliente set ocorrencias = least(ocorrencias + vezes, 9999), ultima_em = now() where hash = h and dia = hoje;
  if found then return jsonb_build_object('ok', true, 'novo', false); end if;
  if v_ip <> '' then
    select count(*) into novos from erros_cliente where usuario_id is null and ip_hash = v_ip and criado_em > now() - interval '1 hour';
    if novos >= 10 then return jsonb_build_object('ok', false, 'motivo', 'limite'); end if;
  end if;
  select count(*) into total from erros_cliente where dia = hoje and usuario_id is null;
  if total >= 300 then return jsonb_build_object('ok', false, 'motivo', 'limite'); end if;
  insert into erros_cliente (usuario_id, nivel, tipo, mensagem, origem, pilha, tela, versao, aparelho, hash, ocorrencias, ip_hash)
  values (null, 'Cardápio', tp, msg, ori, pil,
          left(regexp_replace(coalesce(p->>'tela', ''), '[^a-zA-Z0-9_-]', '', 'g'), 40),
          left(regexp_replace(coalesce(p->>'versao', ''), '[^a-zA-Z0-9._-]', '', 'g'), 30),
          erro_limpa_(p->>'aparelho', 80), h, vezes, v_ip)
  on conflict (hash, dia) do update set ocorrencias = least(erros_cliente.ocorrencias + vezes, 9999), ultima_em = now();
  return jsonb_build_object('ok', true, 'novo', true);
end $function$;

-- Admin/Desenvolvedor: lista e "resolvido"
create or replace function public.api_erros_sistema(p jsonb default '{}'::jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_dias int; v_onde text; v_hash text;
begin
  if not tem_nivel('Admin', 'Desenvolvedor') then return _negado(); end if;
  v_hash := nullif(left(coalesce(p->>'resolver', ''), 40), '');
  if v_hash is not null then
    update erros_cliente set resolvido_em = now() where hash = v_hash;
    perform _auditar('Erro do sistema marcado como resolvido', v_hash);
  end if;
  v_dias := least(greatest(coalesce(nullif(p->>'dias', '')::int, 7), 1), 14);
  v_onde := coalesce(p->>'onde', 'todos');
  return jsonb_build_object('ok', true,
    'resumo', jsonb_build_object(
      'cardapio', (select coalesce(sum(ocorrencias), 0) from erros_cliente where usuario_id is null and ultima_em >= now() - make_interval(days => v_dias) and (resolvido_em is null or ultima_em > resolvido_em)),
      'equipe', (select coalesce(sum(ocorrencias), 0) from erros_cliente where usuario_id is not null and ultima_em >= now() - make_interval(days => v_dias) and (resolvido_em is null or ultima_em > resolvido_em))),
    'itens', coalesce((
      select jsonb_agg(x order by x->>'ultima' desc) from (
        select jsonb_build_object('hash', hash, 'tipo', max(tipo), 'onde', case when bool_or(usuario_id is null) then 'cardapio' else 'equipe' end,
               'niveis', string_agg(distinct coalesce(nivel, '?'), ', '), 'mensagem', max(mensagem), 'origem', max(origem), 'tela', max(tela),
               'versao', max(versao), 'pilha', max(left(pilha, 400)), 'ocorrencias', sum(ocorrencias), 'pessoas', count(distinct coalesce(usuario_id::text, nullif(ip_hash, ''), id::text)),
               'primeira', min(criado_em), 'ultima', max(ultima_em), 'aparelho', max(aparelho)) x
          from erros_cliente
         where ultima_em >= now() - make_interval(days => v_dias)
           and (resolvido_em is null or ultima_em > resolvido_em)
           and (v_onde = 'todos' or (v_onde = 'cardapio' and usuario_id is null) or (v_onde = 'equipe' and usuario_id is not null))
         group by hash
         order by max(ultima_em) desc
         limit 80) t), '[]'::jsonb));
end $function$;

revoke all on function public.registrar_erro_publico(jsonb) from public;
grant execute on function public.registrar_erro_publico(jsonb) to anon, authenticated, service_role;
revoke all on function public.registrar_erro_cliente(jsonb) from public, anon;
grant execute on function public.registrar_erro_cliente(jsonb) to authenticated, service_role;
revoke all on function public.api_erros_sistema(jsonb) from public, anon;
grant execute on function public.api_erros_sistema(jsonb) to authenticated, service_role;


-- ======================================================================
-- 53-ifood-dia-a-dia.sql
-- ======================================================================
-- =====================================================================
-- 53 - iFood no dia a dia (P-01, P-02, P-03, P-06, P-10, P-11)
-- ---------------------------------------------------------------------
-- P-01 Fechar o caixa já fechava os entregadores, mas a entrega concluída
--      DEPOIS da meia-noite (caixa aberto à noite ou caixa vencido) ficava
--      de fora. Agora todas as entregas do caixa entram, sem corte por dia.
-- (achado) A lista de vendas da tela não trazia o "canal": o selo iFood,
--      o "entrega pelo iFood" e a contagem de pedidos externos não
--      funcionavam. Agora vem junto.
-- P-02 Código localizador do cliente do iFood (para ligar no 0800) e a
--      validade dele: gravados no pedido, na tela e na comanda.
-- P-03 Cliente do iFood vira cadastro em Clientes, pelo ID do cliente no
--      iFood (nunca pelo 0800, que é igual para todos). Retroativo.
-- P-06 Detector de pedidos devolve quais pedidos do iFood esperam aceite
--      (para a vinheta do iFood tocar só para esses).
-- P-10 "Cadastrar no sistema" um item do iFood sem produto: vira
--      pré-cadastro (rascunho inativo, fora do cardápio) já ligado.
-- P-11 Excluir de vez itens do iFood de teste (com senha) e marcar pedido
--      do iFood como teste: saem dos alertas e não voltam.
-- Tudo aditivo. Pode rodar mais de uma vez.
-- =====================================================================

-- troca exatamente 1 ocorrência de um trecho dentro do código de uma função
create or replace function pg_temp.tb_trocar(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception 'trecho encontrado % vez(es) (esperado 1): %', n, left(a, 80); end if;
  return replace(d, a, b);
end $f$;

-- ---------------------------------------------------------------------
-- Senha para ação sensível (usada aqui e nos próximos arquivos)
-- ---------------------------------------------------------------------
create or replace function public._senha_acao(p_senha text) returns text
 language plpgsql security definer set search_path to 'public' as $function$
declare v_login text; v_chave text; v_seg int;
begin
  select login into v_login from usuarios where id = auth.uid();
  v_chave := 'falhas_senha_propria_' || lower(coalesce(v_login, ''));
  if _excedeu(v_chave, 5) then
    select greatest(1, extract(epoch from (bloqueado_ate - now()))::int) into v_seg from tentativas where chave = v_chave;
    return 'Muitas tentativas erradas. Aguarde ' || ceil(coalesce(v_seg, 60) / 60.0)::int || ' min e tente de novo.';
  end if;
  if coalesce(p_senha, '') = '' or not _senha_confere(auth.uid(), p_senha) then
    perform _registrar_falha(v_chave);
    return 'Senha incorreta. Nada foi feito.';
  end if;
  perform _limpar_falhas(v_chave);
  return '';
end $function$;
revoke all on function public._senha_acao(text) from public, anon, authenticated;
grant execute on function public._senha_acao(text) to service_role;

-- ---------------------------------------------------------------------
-- P-01: fechamento automático do entregador pega o caixa inteiro
-- ---------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_fechar_caixa(jsonb)'::regprocedure);
  if position('(s.abertura at time zone ''America/Sao_Paulo'')::date as dia' in d) = 0 then
    d := pg_temp.tb_trocar(d,
      'select distinct v.entregador_id, u.login, (v.concluida_em at time zone ''America/Sao_Paulo'')::date as dia',
      'select distinct v.entregador_id, u.login, (s.abertura at time zone ''America/Sao_Paulo'')::date as dia');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Colunas novas
-- ---------------------------------------------------------------------
alter table public.vendas add column if not exists ifood_localizador text;
alter table public.vendas add column if not exists ifood_localizador_ate timestamptz;
alter table public.clientes add column if not exists ifood_id text;
alter table public.clientes add column if not exists origem text not null default '';
create unique index if not exists clientes_ifood_id_uq on public.clientes (ifood_id) where ifood_id is not null;
create index if not exists ix_vendas_cliente_id on public.vendas (cliente_id) where cliente_id is not null;
alter table public.produtos add column if not exists pre_cadastro boolean not null default false;
alter table public.produtos add column if not exists origem text not null default '';
alter table public.produtos add column if not exists ifood_chave text;

-- a tela passa a receber canal (iFood), cliente e o localizador (colunas novas sempre no fim)
create or replace view public.v_vendas as
 SELECT id,
    numero_pedido AS numero,
    data_hora,
    cliente_nome,
    telefone_cliente AS cliente_telefone,
    forma_pagamento,
    valor_total,
        CASE
            WHEN (auth_nivel() = ANY (ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) THEN custo_total
            ELSE NULL::numeric
        END AS custo_total,
    status,
    motivo_cancelamento,
    tipo AS tipo_entrega,
    status_pedido,
    endereco,
    complemento,
    referencia,
    observacoes_entrega,
    pronta_em,
    concluida_em,
    status_pagamento,
    recebido_em,
    valor_original,
    valor_desconto,
    desconto_detalhe,
    _login_de(entregador_id) AS entregador,
    saiu_em,
    origem,
    mesa_id,
    taxa_entrega,
    fechamento_entrega_id,
    _login_de(registrado_por) AS registrado_por,
    inicio_preparo_em,
    _mesa_numero_de(mesa_id) AS mesa_numero,
    acrescimo_forma,
    preferencias_cliente,
    canal,
    cliente_id,
    ifood_localizador,
    ifood_localizador_ate
   FROM vendas v;
grant select on public.v_vendas to authenticated;
grant all on public.v_vendas to service_role;

-- ---------------------------------------------------------------------
-- P-02 + P-03: localizador e cliente do iFood
-- ---------------------------------------------------------------------
create or replace function public._ifood_cliente(p_venda uuid, p_order jsonb) returns uuid
 language plpgsql security definer set search_path to 'public' as $function$
declare v_cid text; v_nome text; v_end text; ad jsonb; v_id uuid; v_loc text; v_ate timestamptz;
begin
  v_loc := nullif(btrim(coalesce(p_order->'customer'->'phone'->>'localizer', '')), '');
  begin v_ate := nullif(p_order->'customer'->'phone'->>'localizerExpiration', '')::timestamptz; exception when others then v_ate := null; end;
  if v_loc is not null then
    update vendas set ifood_localizador = left(regexp_replace(v_loc, '[^0-9A-Za-z]', '', 'g'), 20), ifood_localizador_ate = v_ate where id = p_venda;
  end if;
  v_cid := left(nullif(btrim(coalesce(p_order->'customer'->>'id', '')), ''), 80);
  if v_cid is null then return null; end if;
  v_nome := left(btrim(coalesce(p_order->'customer'->>'name', '')), 80);
  if v_nome = '' then v_nome := 'Cliente iFood'; end if;
  ad := coalesce(p_order->'delivery'->'deliveryAddress', '{}'::jsonb);
  v_end := left(coalesce(nullif(ad->>'formattedAddress', ''), btrim(concat_ws(', ', ad->>'streetName', ad->>'streetNumber', ad->>'neighborhood', ad->>'city'))), 300);
  select id into v_id from clientes where ifood_id = v_cid;
  if v_id is null then
    insert into clientes (nome, telefone, endereco, como_conheceu, primeiro_contato, observacoes, ifood_id, origem)
    values (v_nome, null, nullif(v_end, ''), 'iFood', now(), 'Cadastrado sozinho por pedido do iFood (sem telefone: o iFood usa 0800 + código).', v_cid, 'iFood')
    on conflict (ifood_id) where ifood_id is not null do nothing
    returning id into v_id;
    if v_id is null then select id into v_id from clientes where ifood_id = v_cid; end if;
  elsif nullif(v_end, '') is not null then
    update clientes set endereco = v_end where id = v_id and coalesce(endereco, '') <> v_end;
  end if;
  update vendas set cliente_id = v_id where id = p_venda and cliente_id is null;
  return v_id;
end $function$;
revoke all on function public._ifood_cliente(uuid, jsonb) from public, anon, authenticated;
grant execute on function public._ifood_cliente(uuid, jsonb) to service_role;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.ifood_criar_pedido(jsonb,boolean)'::regprocedure);
  if position('_ifood_cliente(v_venda' in d) = 0 then
    d := pg_temp.tb_trocar(d,
      '  returning numero_pedido into v_numero;',
      '  returning numero_pedido into v_numero;
  -- cliente do iFood (pelo ID do iFood) e código localizador; nunca impede o pedido de entrar
  if not p_simulado then
    begin perform public._ifood_cliente(v_venda, p_order);
    exception when others then perform _integ_log(''ifood'', ''aviso'', ''Pedido #'' || v_disp || '': cliente não cadastrado ('' || left(sqlerrm, 150) || '')''); end;
  end if;');
    execute d;
  end if;
end $$;

-- retroativo: pedidos do iFood que já existem
do $$
declare r record;
begin
  for r in select venda_id, bruto from ifood_pedidos where not coalesce(simulado, false) and venda_id is not null order by criado_em loop
    begin perform public._ifood_cliente(r.venda_id, r.bruto); exception when others then null; end;
  end loop;
end $$;

-- segmentos (Novo/Fiel/VIP/Em risco): cliente do iFood conta pelo cadastro dele, não pelo 0800
create or replace function public.api_clientes_segmentos(p_dias_risco integer default 45)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'diasRisco', greatest(coalesce(p_dias_risco,45),1), 'clientes', coalesce((
    with base as (
      select case when v.canal = 'iFood' then case when v.cliente_id is not null then 'ifood:' || v.cliente_id::text end
                  else _so_digitos(v.telefone_cliente) end tel, v.valor_total, v.data_hora
        from vendas v where v.status = 'Confirmada'
      union all
      select case when s.telefone like '0800%' then case when s.cliente_id is not null then 'ifood:' || s.cliente_id::text end
                  else s.telefone end, s.valor_total, s.data_hora
        from vendas_resumo_arquivo s where s.status = 'Confirmada'
    ),
    agg as (select tel, count(*)::int n, sum(valor_total) total, max(data_hora) ultimo from base
             where tel is not null and (tel like 'ifood:%' or length(tel) >= 8) group by tel)
    select jsonb_agg(jsonb_build_object(
             'telefone', a.tel, 'pedidos', a.n, 'total', a.total, 'ultimo', a.ultimo,
             'segmento', _segmento_cliente(a.n, a.total, a.ultimo, p_dias_risco),
             'temConta', a.tel not like 'ifood:%' and exists (select 1 from contas_cliente cc where cc.telefone <> '' and _so_digitos(cc.telefone) = a.tel),
             'aceitaPromocoes', a.tel not like 'ifood:%' and exists (select 1 from contas_cliente cc where cc.promo_ok and cc.telefone <> '' and _so_digitos(cc.telefone) = a.tel)))
      from agg a), '[]'::jsonb));
end $function$;

-- ---------------------------------------------------------------------
-- P-06: o detector diz quais pedidos do iFood esperam aceite
-- ---------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_detectar_novos_pedidos(jsonb)'::regprocedure);
  if position('''ifood''' in d) = 0 then
    d := pg_temp.tb_trocar(d,
      'return jsonb_build_object(''ok'', true, ''ids'', v_ids, ''recebidos'', v_rec, ''total'', jsonb_array_length(v_ids));',
      'return jsonb_build_object(''ok'', true, ''ids'', v_ids, ''recebidos'', v_rec, ''total'', jsonb_array_length(v_ids),
    ''ifood'', coalesce((select jsonb_agg(v.id::text) from (select * from vendas order by data_hora desc limit 300) v
                         where v.status = ''Confirmada'' and v.canal = ''iFood'' and v.status_pedido = ''Recebido''), ''[]''::jsonb));');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- P-11: itens do iFood descartados (excluídos de vez) e pedido de teste
-- ---------------------------------------------------------------------
create table if not exists public.ifood_itens_descartados (
  chave text primary key,
  nome text not null default '',
  tipo text not null default '',
  descartado_por uuid,
  descartado_em timestamptz not null default now()
);
alter table public.ifood_itens_descartados enable row level security;
revoke all on table public.ifood_itens_descartados from public, anon, authenticated;
grant all on table public.ifood_itens_descartados to service_role;

-- item descartado que voltar num pedido: não é recriado e conta como "ignorar"
create or replace function public._ifood_item_visto(p_chave text, p_nome text, p_tipo text)
 returns ifood_itens language plpgsql security definer set search_path to 'public' as $function$
declare r ifood_itens%rowtype; v_u uuid;
begin
  if exists (select 1 from ifood_itens_descartados where chave = p_chave) then
    r.chave := p_chave; r.nome := left(coalesce(nullif(p_nome, ''), p_chave), 200); r.tipo := p_tipo; r.ignorar := true;
    return r;
  end if;
  insert into ifood_itens (chave, nome, tipo) values (p_chave, left(coalesce(nullif(p_nome, ''), p_chave), 200), p_tipo)
    on conflict (chave) do update set nome = excluded.nome, visto_em = now() returning * into r;
  if r.produto_id is null and r.combo_id is null and r.adicional_id is null and not r.ignorar then
    v_u := case when p_chave ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p_chave::uuid end;
    if v_u is not null then
      if exists (select 1 from produtos where id = v_u) then update ifood_itens set produto_id = v_u, ligado_em = now() where chave = p_chave returning * into r;
      elsif exists (select 1 from combos where id = v_u) then update ifood_itens set combo_id = v_u, ligado_em = now() where chave = p_chave returning * into r;
      elsif p_tipo = 'opcao' and exists (select 1 from adicionais where id = v_u) then update ifood_itens set adicional_id = v_u, ligado_em = now() where chave = p_chave returning * into r;
      end if;
    end if;
  end if;
  return r;
end $function$;

-- recontagem dos itens sem ligação de um pedido (mesma regra de _ifood_gravar_itens, sem regravar nada)
create or replace function public._ifood_contar_sem_ligacao(p_order jsonb) returns int
 language plpgsql stable security definer set search_path to 'public' as $function$
declare it jsonb; v_chave text; v_n int := 0; i ifood_itens%rowtype;
begin
  for it in select value from jsonb_array_elements(coalesce(p_order->'items', '[]'::jsonb)) loop
    v_chave := coalesce(nullif(it->>'externalCode', ''), nullif(it->>'id', ''), 'sem-codigo-' || public._ifood_norm(it->>'name'));
    if exists (select 1 from ifood_itens_descartados where chave = v_chave) then continue; end if;
    select * into i from ifood_itens where chave = v_chave;
    if i.chave is null or (i.produto_id is null and i.combo_id is null and not coalesce(i.ignorar, false)) then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $function$;
revoke all on function public._ifood_contar_sem_ligacao(jsonb) from public, anon, authenticated;
grant execute on function public._ifood_contar_sem_ligacao(jsonb) to service_role;

-- alerta de saúde: pedido de teste não conta
do $$
declare d text;
begin
  d := pg_get_functiondef('public._saude_integracoes()'::regprocedure);
  if position('itens_sem_ligacao), 0) into v_sem from ifood_pedidos where estado <> ''cancelado'' and not coalesce(simulado, false)' in d) = 0 then
    d := pg_temp.tb_trocar(d,
      'select coalesce(sum(itens_sem_ligacao), 0) into v_sem from ifood_pedidos where estado <> ''cancelado'' and criado_em',
      'select coalesce(sum(itens_sem_ligacao), 0) into v_sem from ifood_pedidos where estado <> ''cancelado'' and not coalesce(simulado, false) and criado_em');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Tela "Itens do iFood": lista com pré-cadastros, descartados e categorias
-- ---------------------------------------------------------------------
create or replace function public.api_ifood_itens(p jsonb default '{}'::jsonb)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'itens', coalesce((select jsonb_agg(jsonb_build_object('chave', i.chave, 'nome', i.nome, 'tipo', i.tipo, 'ignorar', i.ignorar,
        'ligado', case when i.produto_id is not null then 'produto' when i.combo_id is not null then 'combo' when i.adicional_id is not null then 'adicional' end,
        'ligadoId', coalesce(i.produto_id, i.combo_id, i.adicional_id),
        'ligadoNome', coalesce((select nome from produtos where id = i.produto_id), (select nome from combos where id = i.combo_id), (select nome from adicionais where id = i.adicional_id)),
        'preCadastro', coalesce((select pr.pre_cadastro from produtos pr where pr.id = i.produto_id), false),
        'categoria', i.categoria, 'precoIfood', i.preco_ifood, 'vistoEm', i.visto_em,
        'sugestao', case when i.produto_id is null and i.combo_id is null and i.adicional_id is null and not i.ignorar then public._ifood_sugestao(i.nome, i.tipo) end)
        order by (i.produto_id is null and i.combo_id is null and i.adicional_id is null and not i.ignorar) desc, i.nome) from ifood_itens i), '[]'::jsonb),
    'produtos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) from produtos where ativo), '[]'::jsonb),
    'combos', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) from combos where ativo), '[]'::jsonb),
    'adicionais', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome) from adicionais where ativo), '[]'::jsonb),
    'categorias', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by ordem, nome) from categorias where ativa), '[]'::jsonb),
    'descartados', coalesce((select jsonb_agg(jsonb_build_object('chave', d.chave, 'nome', d.nome, 'tipo', d.tipo, 'em', d.descartado_em, 'por', _login_de(d.descartado_por)) order by d.descartado_em desc)
                               from (select * from ifood_itens_descartados order by descartado_em desc limit 100) d), '[]'::jsonb),
    'preCadastros', coalesce((select jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome, 'semPreco', not exists (select 1 from produto_precos pp where pp.produto_id = pr.id and pp.preco > 0),
                               'semFicha', not exists (select 1 from produto_ingredientes pi where pi.produto_id = pr.id), 'semFoto', coalesce(pr.foto_id_principal, '') = '',
                               'semCategoria', pr.categoria_id is null) order by pr.nome)
                               from produtos pr where pr.pre_cadastro), '[]'::jsonb));
end $function$;

-- Excluir de vez (com senha). Item ligado não pode. Também restaura um descartado.
create or replace function public.api_ifood_itens_excluir(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_err text; v_chaves text[]; v_lig int; v_n int; v_rest text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  v_rest := nullif(p->>'restaurar', '');
  if v_rest is not null then
    delete from ifood_itens_descartados where chave = v_rest;
    perform _auditar('Item do iFood restaurado (volta a aparecer quando vier num pedido)', v_rest);
    return api_ifood_itens('{}') || jsonb_build_object('message', 'Restaurado. Ele volta para a lista quando aparecer de novo num pedido.');
  end if;
  if coalesce((p->>'todosIgnorados')::boolean, false) then
    select coalesce(array_agg(chave), '{}') into v_chaves from ifood_itens where ignorar and produto_id is null and combo_id is null and adicional_id is null;
  else
    select coalesce(array_agg(x), '{}') into v_chaves from jsonb_array_elements_text(case when jsonb_typeof(p->'chaves') = 'array' then p->'chaves' else '[]'::jsonb end) x;
  end if;
  if coalesce(array_length(v_chaves, 1), 0) = 0 then return _falha('Nenhum item escolhido para excluir.'); end if;
  select count(*) into v_lig from ifood_itens where chave = any(v_chaves) and (produto_id is not null or combo_id is not null or adicional_id is not null);
  if v_lig > 0 then return _falha('Há ' || v_lig || ' item(ns) ligado(s) a produto do sistema. Desfaça a ligação antes de excluir. Nada foi excluído.'); end if;
  insert into ifood_itens_descartados (chave, nome, tipo, descartado_por)
    select chave, coalesce(nome, ''), coalesce(tipo, ''), auth.uid() from ifood_itens where chave = any(v_chaves)
    on conflict (chave) do nothing;
  delete from ifood_itens where chave = any(v_chaves);
  get diagnostics v_n = row_count;
  update ifood_pedidos set itens_sem_ligacao = public._ifood_contar_sem_ligacao(bruto) where itens_sem_ligacao > 0;
  perform _auditar('Itens do iFood excluídos de vez', v_n || ' item(ns): ' || left(array_to_string(v_chaves, ', '), 600));
  return api_ifood_itens('{}') || jsonb_build_object('message', v_n || ' item(ns) excluído(s) de vez. Se voltarem num pedido, não aparecem nem geram alerta.');
end $function$;

-- Marcar pedido do iFood como teste (com senha): sai dos alertas e dos relatórios do iFood
create or replace function public.api_ifood_marcar_teste(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_err text; v_num text := btrim(coalesce(p->>'numero', '')); v_id text; v_venda uuid; v_teste boolean := coalesce((p->>'teste')::boolean, true);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  select pedido_ifood, venda_id into v_id, v_venda from ifood_pedidos where numero_ifood = v_num or pedido_ifood = v_num order by criado_em desc limit 1;
  if v_id is null then return _falha('Pedido do iFood não encontrado (use o número que aparece como "iFood #...").'); end if;
  update ifood_pedidos set simulado = v_teste, itens_sem_ligacao = case when v_teste then 0 else public._ifood_contar_sem_ligacao(bruto) end where pedido_ifood = v_id;
  perform _auditar(case when v_teste then 'Pedido do iFood marcado como teste' else 'Pedido do iFood desmarcado como teste' end, 'iFood #' || v_num);
  return jsonb_build_object('ok', true, 'message', case when v_teste
    then 'Pedido iFood #' || v_num || ' marcado como TESTE: saiu dos alertas e dos relatórios do iFood. A venda continua no caixa; se ela não deveria existir, cancele a venda normalmente (pede senha).'
    else 'Pedido iFood #' || v_num || ' voltou a contar normalmente.' end);
end $function$;

-- ---------------------------------------------------------------------
-- P-10: pré-cadastro de item do iFood
-- ---------------------------------------------------------------------
create or replace function public.api_ifood_pre_cadastro(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare it ifood_itens%rowtype; v_nome text; v_desc text; v_preco numeric; v_cat uuid; v_catnova text; v_id uuid; v_dup record; v_forcar boolean := coalesce((p->>'forcar')::boolean, false); v_forma uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into it from ifood_itens where chave = p->>'chave';
  if it.chave is null then return _falha('Item do iFood não encontrado.'); end if;
  if it.produto_id is not null or it.combo_id is not null or it.adicional_id is not null then return _falha('Este item já está ligado a um produto do sistema.'); end if;
  v_nome := left(btrim(coalesce(nullif(p->>'nome', ''), it.nome, '')), 120);
  if v_nome = '' then return _falha('Informe o nome.'); end if;
  v_desc := left(btrim(coalesce(p->>'descricao', '')), 1000);
  v_preco := round(greatest(case when nullif(btrim(coalesce(p->>'preco', '')), '') is null then coalesce(it.preco_ifood, 0) else _num(p->>'preco') end, 0), 2);
  if it.tipo = 'opcao' then
    if not v_forcar then
      select id, nome into v_dup from adicionais where public._ifood_norm(nome) = public._ifood_norm(v_nome) limit 1;
      if v_dup.id is not null then
        return jsonb_build_object('ok', false, 'duplicado', true, 'existente', jsonb_build_object('id', v_dup.id, 'nome', v_dup.nome, 'tipo', 'adicional'),
          'message', 'Já existe um adicional com esse nome ("' || v_dup.nome || '"). Ligar a ele em vez de criar?');
      end if;
    end if;
    insert into adicionais (nome, preco, ativo) values (v_nome, v_preco, false) returning id into v_id;
    update ifood_itens set adicional_id = v_id, ignorar = false, ligado_em = now() where chave = it.chave;
    perform _auditar('Pré-cadastro do iFood (adicional)', v_nome || ' · ' || it.chave);
    return api_ifood_itens('{}') || jsonb_build_object('criadoId', v_id, 'message',
      'Adicional "' || v_nome || '" criado INATIVO e já ligado. Em Adicionais, informe o ingrediente que ele baixa e ative.');
  end if;
  if not v_forcar then
    select id, nome, 'produto' t into v_dup from produtos where public._ifood_norm(nome) = public._ifood_norm(v_nome)
    union all select id, nome, 'combo' from combos where public._ifood_norm(nome) = public._ifood_norm(v_nome) limit 1;
    if v_dup.id is not null then
      return jsonb_build_object('ok', false, 'duplicado', true, 'existente', jsonb_build_object('id', v_dup.id, 'nome', v_dup.nome, 'tipo', v_dup.t),
        'message', 'Já existe um ' || v_dup.t || ' parecido ("' || v_dup.nome || '"). Ligar a ele em vez de criar?');
    end if;
  end if;
  v_cat := case when coalesce(p->>'categoriaId', '') ~* '^[0-9a-f-]{36}$' then (p->>'categoriaId')::uuid end;
  if v_cat is not null and not exists (select 1 from categorias where id = v_cat) then v_cat := null; end if;
  v_catnova := left(btrim(coalesce(p->>'categoriaNova', '')), 60);
  if v_cat is null and v_catnova <> '' then
    select id into v_cat from categorias where lower(btrim(nome)) = lower(v_catnova) limit 1;
    if v_cat is null then insert into categorias (nome) values (v_catnova) returning id into v_cat; end if;
  end if;
  insert into produtos (nome, descricao, categoria_id, ativo, pre_cadastro, origem, ifood_chave)
  values (v_nome, nullif(v_desc, ''), v_cat, false, true, 'ifood', it.chave) returning id into v_id;
  v_forma := _ifood_forma();
  if v_forma is not null and v_preco > 0 then
    insert into produto_precos (produto_id, forma_pagamento_id, preco, custo) values (v_id, v_forma, v_preco, 0);
  end if;
  update ifood_itens set produto_id = v_id, ignorar = false, ligado_em = now() where chave = it.chave;
  perform _auditar('Pré-cadastro do iFood (produto)', v_nome || ' · ' || it.chave);
  return api_ifood_itens('{}') || jsonb_build_object('criadoId', v_id, 'message',
    '"' || v_nome || '" criado como RASCUNHO (fora do cardápio) e já ligado ao item do iFood.'
    || case when v_forma is not null and v_preco > 0 then ' Preço do iFood gravado na forma iFood.' else ' Sem preço: complete em Produtos.' end
    || ' Complete ficha técnica, preços das outras formas e foto em Produtos, e ative quando estiver pronto.');
end $function$;

-- ativou o produto: deixa de ser pré-cadastro
create or replace function public._trg_produto_pre_cadastro() returns trigger
 language plpgsql set search_path to 'public' as $function$
begin
  if new.ativo and not coalesce(old.ativo, false) and new.pre_cadastro then new.pre_cadastro := false; end if;
  return new;
end $function$;
drop trigger if exists produtos_pre_cadastro on public.produtos;
create trigger produtos_pre_cadastro before update of ativo on public.produtos for each row execute function public._trg_produto_pre_cadastro();

revoke all on function public.api_ifood_itens(jsonb), public.api_ifood_itens_excluir(jsonb), public.api_ifood_marcar_teste(jsonb), public.api_ifood_pre_cadastro(jsonb) from public, anon;
grant execute on function public.api_ifood_itens(jsonb), public.api_ifood_itens_excluir(jsonb), public.api_ifood_marcar_teste(jsonb), public.api_ifood_pre_cadastro(jsonb) to authenticated, service_role;
revoke all on function public._trg_produto_pre_cadastro() from public, anon, authenticated;


-- ======================================================================
-- 54-cupons-excluir.sql
-- ======================================================================
-- =====================================================================
-- 54 - Excluir cupom (P-05)
-- ---------------------------------------------------------------------
-- Admin → Cupons: botão Excluir (pede a senha).
-- - Cupom NUNCA usado: apagado de vez.
-- - Cupom já usado em pedido: ARQUIVADO (some da lista, da conta do
--   cliente e do cardápio; o histórico dos pedidos continua certo).
--   O código fica livre para um cupom novo. Dá para restaurar.
-- - Cupom que estiver no carrinho de alguém: na hora de enviar, o
--   cliente vê "Esse cupom não está mais disponível".
-- Tudo aditivo. Pode rodar mais de uma vez.
-- =====================================================================

alter table public.cupons add column if not exists excluido_em timestamptz;
alter table public.cupons add column if not exists excluido_por uuid;
alter table public.cupons add column if not exists codigo_original text;

create or replace function public.api_excluir_cupom(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_err text; c cupons%rowtype; v_usos int; v_novo text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  select * into c from cupons where id = _uuid(p->>'id') for update;
  if c.id is null then return _falha('Cupom não encontrado.'); end if;

  if coalesce((p->>'restaurar')::boolean, false) then
    if c.excluido_em is null then return _falha('Este cupom não está excluído.'); end if;
    v_novo := coalesce(c.codigo_original, c.codigo);
    if exists (select 1 from cupons where codigo = v_novo and id <> c.id) then
      return _falha('Já existe outro cupom com o código ' || v_novo || '. Mude o código dele antes de restaurar este.');
    end if;
    update cupons set excluido_em = null, excluido_por = null, codigo = v_novo, codigo_original = null where id = c.id;
    perform _auditar('Cupom restaurado (continua desativado)', v_novo);
    return jsonb_build_object('ok', true, 'message', 'Cupom ' || v_novo || ' restaurado. Ele volta DESATIVADO: ative quando quiser.');
  end if;

  if c.excluido_em is not null then return _falha('Este cupom já foi excluído.'); end if;
  if c.automatico is not null then return _falha('Cupom automático (boas-vindas, aniversário, indicação) não se exclui: use Desligar.'); end if;
  select count(*) into v_usos from cupons_usos where cupom_id = c.id and not coalesce(anulado, false);
  select v_usos + count(*) into v_usos from cupons_concedidos where cupom_id = c.id and usado_em is not null;

  if v_usos = 0 then
    delete from cupons where id = c.id;          -- cupons_usos (anulados) e concedidos não usados saem juntos (cascade)
    perform _auditar('Cupom excluído (nunca usado)', c.codigo);
    return jsonb_build_object('ok', true, 'apagado', true, 'message', 'Cupom ' || c.codigo || ' excluído de vez (nunca tinha sido usado).');
  end if;

  v_novo := left(c.codigo, 28) || '-EXC' || to_char(now() at time zone 'America/Sao_Paulo', 'YYMMDDHH24MI');
  update cupons set excluido_em = now(), excluido_por = auth.uid(), ativa = false, visivel_conta = false,
                    codigo_original = c.codigo, codigo = v_novo where id = c.id;
  delete from cupons_concedidos where cupom_id = c.id and usado_em is null;   -- sai da conta dos clientes
  perform _auditar('Cupom excluído (arquivado: já usado em ' || v_usos || ' pedido(s))', c.codigo);
  return jsonb_build_object('ok', true, 'arquivado', true, 'message',
    'Cupom ' || c.codigo || ' excluído. Como já foi usado em ' || v_usos || ' pedido(s), ele foi ARQUIVADO: some da lista, da conta dos clientes e do cardápio, e os pedidos antigos continuam certos. O código ' || c.codigo || ' fica livre para um cupom novo.');
end $function$;
revoke all on function public.api_excluir_cupom(jsonb) from public, anon;
grant execute on function public.api_excluir_cupom(jsonb) to authenticated, service_role;

-- ativar/desativar não mexe em cupom excluído
do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_alternar_cupom(jsonb)'::regprocedure);
  if position('excluido_em is null' in d) = 0 then
    if position('update cupons set ativa = v_on where id = _uuid(p->>''id'') returning codigo into v_cod;' in d) = 0 then raise exception '54: ponto de troca não encontrado em api_alternar_cupom'; end if;
    d := replace(d, 'update cupons set ativa = v_on where id = _uuid(p->>''id'') returning codigo into v_cod;',
                    'update cupons set ativa = v_on where id = _uuid(p->>''id'') and excluido_em is null returning codigo into v_cod;');
    execute d;
  end if;
end $$;

-- mensagem clara para quem estava com o cupom excluído no carrinho (o código antigo não existe mais)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.api_validar_cupom_cardapio(jsonb)'::regprocedure);
  if position('não está mais disponível' in d) = 0 and position(E'  return v_r;\nend' in d) > 0 then
    d := replace(d, E'  return v_r;\nend', E'  if coalesce(v_r->>''ok'', '''') <> ''true'' and exists (select 1 from cupons where excluido_em is not null\n       and codigo_original = upper(regexp_replace(btrim(coalesce(p->>''codigo'', '''')), ''\\s+'', '''', ''g''))) then\n    v_r := jsonb_build_object(''ok'', false, ''message'', ''Esse cupom não está mais disponível.'');\n  end if;\n  return v_r;\nend');
    execute d;
  end if;
end $$;


-- ======================================================================
-- 55-cardapio-funil-mapa.sql
-- ======================================================================
-- =====================================================================
-- 55 - Funil do cardápio + "CARDÁPIO HOJE" com mapa
-- ---------------------------------------------------------------------
-- Funil (por aparelho, sem nome nem telefone): entrou no cardápio →
-- abriu um item → pôs no carrinho → abriu o finalizar → enviou o pedido.
-- Mapa: localização APROXIMADA de quem entrou (arredondada em ~500 m),
-- só de quem já permitiu a localização no aparelho. É APAGADA ao fechar
-- o caixa e, de qualquer forma, depois de 24 horas.
-- Leitura: só Admin e Operador. Aparelho da equipe não conta.
-- Tudo aditivo. Pode rodar mais de uma vez.
-- =====================================================================

create table if not exists public.cardapio_funil (
  dia date not null,
  aparelho text not null,
  etapa text not null check (etapa in ('visita', 'item', 'carrinho', 'finalizar', 'pedido')),
  primeiro_em timestamptz not null default now(),
  primary key (dia, aparelho, etapa)
);
create index if not exists ix_cardapio_funil_em on public.cardapio_funil (primeiro_em);
alter table public.cardapio_funil enable row level security;
revoke all on table public.cardapio_funil from public, anon, authenticated;
grant all on table public.cardapio_funil to service_role;

create table if not exists public.cardapio_locais (
  aparelho text primary key,
  lat numeric(8,4) not null,
  lng numeric(8,4) not null,
  criado_em timestamptz not null default now()
);
create index if not exists ix_cardapio_locais_em on public.cardapio_locais (criado_em);
alter table public.cardapio_locais enable row level security;
revoke all on table public.cardapio_locais from public, anon, authenticated;
grant all on table public.cardapio_locais to service_role;

-- registrar uma etapa (cliente, sem login). Limite: 40 mil registros por dia no total.
create or replace function public.api_cardapio_funil(p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_ap text := lower(btrim(coalesce(p->>'aparelho', ''))); v_et text := lower(btrim(coalesce(p->>'etapa', '')));
        v_dia date := (now() at time zone 'America/Sao_Paulo')::date; v_lat numeric; v_lng numeric;
begin
  if v_ap !~ '^[a-z0-9]{16,40}$' or v_et not in ('visita', 'item', 'carrinho', 'finalizar', 'pedido') then return jsonb_build_object('ok', false); end if;
  if exists (select 1 from cardapio_aparelhos_equipe where aparelho = v_ap) then return jsonb_build_object('ok', true); end if;
  if (select count(*) from cardapio_funil where dia = v_dia) >= 40000 then return jsonb_build_object('ok', true); end if;
  insert into cardapio_funil (dia, aparelho, etapa) values (v_dia, v_ap, v_et) on conflict do nothing;
  if v_et = 'visita' then
    insert into cardapio_visitas (dia, aparelho) values (v_dia, v_ap) on conflict do nothing;   -- o contador antigo continua igual
  end if;
  -- localização aproximada (grade de ~500 m), só dentro do Brasil
  begin v_lat := (p->>'lat')::numeric; v_lng := (p->>'lng')::numeric; exception when others then v_lat := null; end;
  if v_lat is not null and v_lng is not null and v_lat between -34 and 6 and v_lng between -74 and -34 then
    insert into cardapio_locais (aparelho, lat, lng) values (v_ap, round(v_lat / 0.005) * 0.005, round(v_lng / 0.005) * 0.005)
      on conflict (aparelho) do update set lat = excluded.lat, lng = excluded.lng, criado_em = now();
  end if;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.api_cardapio_funil(jsonb) from public;
grant execute on function public.api_cardapio_funil(jsonb) to anon, authenticated, service_role;

-- "CARDÁPIO HOJE" (Admin e Operador): desde a abertura do caixa (turno); sem caixa aberto, últimas 24 horas
create or replace function public.api_cardapio_hoje(p jsonb default '{}'::jsonb)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_ini timestamptz; v_turno boolean;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select abertura into v_ini from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  v_turno := v_ini is not null;
  v_ini := coalesce(v_ini, now() - interval '24 hours');
  return jsonb_build_object('ok', true, 'desde', v_ini, 'turno', v_turno,
    'funil', (select jsonb_build_object(
        'visita',    count(distinct aparelho) filter (where etapa = 'visita'),
        'item',      count(distinct aparelho) filter (where etapa = 'item'),
        'carrinho',  count(distinct aparelho) filter (where etapa = 'carrinho'),
        'finalizar', count(distinct aparelho) filter (where etapa = 'finalizar'),
        'pedido',    count(distinct aparelho) filter (where etapa = 'pedido'))
      from cardapio_funil f where f.primeiro_em >= v_ini
       and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho)),
    'pedidosCardapio', (select count(*) from vendas where origem = 'Cardápio' and status = 'Confirmada' and data_hora >= v_ini),
    'pontos', coalesce((select jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'n', n)) from (
        select l.lat, l.lng, count(*)::int n from cardapio_locais l
         where l.criado_em >= v_ini and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = l.aparelho)
         group by l.lat, l.lng) x), '[]'::jsonb),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('lat', round((d.lat / 0.005)::numeric) * 0.005, 'lng', round((d.lng / 0.005)::numeric) * 0.005))
        from pedido_destinos d join vendas v on v.id = d.venda_id
       where v.data_hora >= v_ini and v.status = 'Confirmada'), '[]'::jsonb),
    'restaurante', (select jsonb_build_object('lat', (valor->>'lat')::numeric, 'lng', (valor->>'lng')::numeric) from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object'));
end $function$;
revoke all on function public.api_cardapio_hoje(jsonb) from public, anon;
grant execute on function public.api_cardapio_hoje(jsonb) to authenticated, service_role;

-- fechou o caixa: apaga as localizações (fim do turno)
create or replace function public._trg_caixa_fecha_apaga_locais() returns trigger
 language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.status::text = 'Fechado' and old.status::text is distinct from 'Fechado' then delete from cardapio_locais; end if;
  return new;
end $function$;
revoke all on function public._trg_caixa_fecha_apaga_locais() from public, anon, authenticated;
drop trigger if exists caixa_fecha_apaga_locais on public.caixa_sessoes;
create trigger caixa_fecha_apaga_locais after update of status on public.caixa_sessoes for each row execute function public._trg_caixa_fecha_apaga_locais();

-- de hora em hora: localização com mais de 24 h sai; funil guarda 90 dias
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'cardapio-funil-limpeza') then
    perform cron.schedule('cardapio-funil-limpeza', '17 * * * *',
      $c$delete from public.cardapio_locais where criado_em < now() - interval '24 hours';
         delete from public.cardapio_funil where dia < current_date - 90$c$);
  end if;
end $$;


-- ======================================================================
-- 56-arquivo-storage.sql
-- ======================================================================
-- =====================================================================
-- 56 - Arquivo no Storage do Supabase (P-08) + espaço liberado de verdade
--      + previsão de quando enche + tela Armazenamento
-- ---------------------------------------------------------------------
-- Caminho dos dados antigos:  banco → Storage (bucket privado "arquivo")
--                             → planilha (só quando o Storage passa de 95%).
-- Nada sai de um lugar sem o outro confirmar que recebeu tudo.
-- Compactação (VACUUM FULL, que devolve o espaço de verdade): só às 05:30
-- de Brasília (depois do backup das 4h e do arquivamento das 5h). Mede o
-- tamanho antes e depois e avisa o Admin se o espaço não diminuir.
-- Tudo aditivo. Pode rodar mais de uma vez.
-- =====================================================================

insert into storage.buckets (id, name, public) values ('arquivo', 'arquivo', false) on conflict (id) do nothing;

alter table public.backup_config add column if not exists storage_limite_mb integer not null default 1024;
alter table public.espaco_historico add column if not exists storage_bytes bigint;

create table if not exists public.arquivo_mapa (
  id bigserial primary key,
  tipo text not null check (tipo in ('vendas', 'caixa')),
  mes text not null check (mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  local text not null default 'storage' check (local in ('storage', 'planilha')),
  caminho text not null unique,
  qtd integer not null default 0,
  bytes bigint not null default 0,
  criado_em timestamptz not null default now(),
  movido_em timestamptz
);
create index if not exists ix_arquivo_mapa_mes on public.arquivo_mapa (tipo, mes);
alter table public.arquivo_mapa enable row level security;
revoke all on table public.arquivo_mapa from public, anon, authenticated;
grant all on table public.arquivo_mapa to service_role;
grant usage, select on sequence public.arquivo_mapa_id_seq to service_role;

create table if not exists public.arquivo_execucoes (
  id bigserial primary key,
  em timestamptz not null default now(),
  gatilho text not null,             -- idade | banco95 | storage95 | manual | autoteste | resumo
  origem text not null default '',
  destino text not null default '',
  qtd integer not null default 0,
  arquivos integer not null default 0,
  ms integer,
  erro text,
  db_bytes_antes bigint,
  db_bytes_depois bigint,
  liberado_bytes bigint,
  medido_em timestamptz
);
create index if not exists ix_arquivo_execucoes_em on public.arquivo_execucoes (em desc);
alter table public.arquivo_execucoes enable row level security;
revoke all on table public.arquivo_execucoes from public, anon, authenticated;
grant all on table public.arquivo_execucoes to service_role;
grant usage, select on sequence public.arquivo_execucoes_id_seq to service_role;

-- ---------------------------------------------------------------------
-- Tamanho do Storage
-- ---------------------------------------------------------------------
create or replace function public._storage_bytes(p_bucket text default null) returns bigint
 language sql stable security definer set search_path to 'public', 'storage' as $$
  select coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint from storage.objects o where p_bucket is null or o.bucket_id = p_bucket
$$;
revoke all on function public._storage_bytes(text) from public, anon, authenticated;
grant execute on function public._storage_bytes(text) to service_role;

create or replace function public.api_storage_percentual_servico() returns numeric
 language sql stable security definer set search_path to 'public' as $$
  select round(_storage_bytes() / 1048576.0 / greatest(coalesce((select storage_limite_mb from backup_config where id), 1024), 1) * 100, 1)
$$;
revoke all on function public.api_storage_percentual_servico() from public, anon, authenticated;
grant execute on function public.api_storage_percentual_servico() to service_role;

-- foto diária do tamanho: agora também do Storage
create or replace function public._espaco_snapshot() returns void
 language plpgsql security definer set search_path to 'public' as $function$
begin
  insert into espaco_historico (dia, db_bytes, vendas_ativas, storage_bytes)
  values ((now() at time zone 'America/Sao_Paulo')::date, pg_database_size(current_database()), (select count(*) from vendas), _storage_bytes())
  on conflict (dia) do update set db_bytes = excluded.db_bytes, vendas_ativas = excluded.vendas_ativas, storage_bytes = excluded.storage_bytes;
end $function$;

-- avisos do Storage (70% e 85%), no máximo um por dia por faixa
create or replace function public.api_storage_alerta_servico() returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare v_pct numeric := api_storage_percentual_servico(); v_faixa int; v_chave text; v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
begin
  v_faixa := case when v_pct >= 85 then 85 when v_pct >= 70 then 70 else 0 end;
  if v_faixa = 0 then return jsonb_build_object('ok', true, 'pct', v_pct); end if;
  v_chave := 'storage_alerta_' || v_faixa;
  if exists (select 1 from sistema where chave = v_chave and valor #>> '{}' = v_hoje) then return jsonb_build_object('ok', true, 'pct', v_pct, 'jaAvisado', true); end if;
  insert into sistema (chave, valor, atualizado_em) values (v_chave, to_jsonb(v_hoje), now()) on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  begin
    perform _push_admins('Storage do Supabase em ' || v_pct || '%',
      case when v_faixa = 85 then 'Perto do limite: a partir de 95% os arquivos mais antigos vão sozinhos para a planilha. Veja Administrador → Backup e espaço → Armazenamento.'
           else 'Acima de 70%. Nada a fazer agora; acompanhe em Administrador → Backup e espaço → Armazenamento.' end, 'storage-' || v_faixa);
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'pct', v_pct, 'avisado', v_faixa);
end $function$;
revoke all on function public.api_storage_alerta_servico() from public, anon, authenticated;
grant execute on function public.api_storage_alerta_servico() to service_role;

-- ---------------------------------------------------------------------
-- Compactação: só às 05:30 de Brasília (08:30 UTC), uma pendente por vez
-- ---------------------------------------------------------------------
create or replace function public._compactar_agendar() returns void
 language plpgsql security definer set search_path to 'public', 'cron' as $function$
declare r record; v_pendente boolean := false; v_quando timestamptz; v_base timestamp;
begin
  for r in select jobname from cron.job where jobname like 'compactar-%' loop
    if coalesce(nullif(substring(r.jobname from 'compactar-(\d+)'), '')::bigint, 0) < extract(epoch from now() - interval '15 minutes') then
      perform cron.unschedule(r.jobname);                        -- já rodou (ou ficou para trás): sai da lista
    else v_pendente := true; end if;
  end loop;
  if v_pendente then return; end if;
  -- próxima 05:30 em Brasília (= 08:30 UTC)
  v_base := date_trunc('day', now() at time zone 'UTC') + interval '8 hours 30 minutes';
  v_quando := (v_base at time zone 'UTC');
  if v_quando <= now() + interval '2 minutes' then v_quando := v_quando + interval '1 day'; end if;
  perform cron.schedule('compactar-' || floor(extract(epoch from v_quando))::bigint,
    extract(minute from v_quando at time zone 'UTC')::int || ' ' || extract(hour from v_quando at time zone 'UTC')::int || ' ' ||
    extract(day from v_quando at time zone 'UTC')::int || ' ' || extract(month from v_quando at time zone 'UTC')::int || ' *',
    'vacuum full public.vendas, public.itens_venda, public.pagamentos_venda, public.caixa_sessoes, public.sangrias, public.vendas_resumo_arquivo, public.arquivo_historico');
end $function$;
revoke all on function public._compactar_agendar() from public, anon, authenticated;
grant execute on function public._compactar_agendar() to service_role;

-- 06:00 de Brasília: mede quanto a compactação liberou e avisa se não diminuiu
create or replace function public._arquivo_medir_compactacao() returns void
 language plpgsql security definer set search_path to 'public', 'cron' as $function$
declare v_db bigint := pg_database_size(current_database()); e record; v_rodou boolean;
begin
  -- só tira da lista o agendamento que já rodou (NÃO marca outro: a próxima compactação só é marcada quando algo sair do banco)
  for e in select jobname from cron.job where jobname like 'compactar-%' loop
    if coalesce(nullif(substring(e.jobname from 'compactar-(\d+)'), '')::bigint, 0) < extract(epoch from now() - interval '15 minutes') then perform cron.unschedule(e.jobname); end if;
  end loop;
  v_rodou := exists (select 1 from cron.job_run_details d where d.command like 'vacuum full public.vendas%' and d.start_time > now() - interval '3 hours' and d.status = 'succeeded');
  if not v_rodou then return; end if;
  for e in select * from arquivo_execucoes where medido_em is null and db_bytes_antes is not null and qtd > 0 and em < now() - interval '20 minutes' order by em loop
    update arquivo_execucoes set db_bytes_depois = v_db, liberado_bytes = db_bytes_antes - v_db, medido_em = now() where id = e.id;
  end loop;
  if exists (select 1 from arquivo_execucoes where medido_em > now() - interval '5 minutes' and liberado_bytes <= 0) then
    begin
      perform _push_admins('Arquivamento: o espaço do banco não diminuiu',
        'Os dados antigos saíram do banco, mas o tamanho não caiu depois da compactação. Veja Administrador → Sistema → Armazenamento.', 'arquivo-sem-liberar');
    exception when others then null; end;
  end if;
end $function$;
revoke all on function public._arquivo_medir_compactacao() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'arquivo-medir-compactacao') then
    perform cron.schedule('arquivo-medir-compactacao', '0 9 * * *', 'select public._arquivo_medir_compactacao()');
  end if;
  -- a cada hora: proteção do Storage (95% → planilha) e avisos 70%/85%
  if not exists (select 1 from cron.job where jobname = 'arquivo-protecao-storage') then
    perform cron.schedule('arquivo-protecao-storage', '41 * * * *', $c$ select public.chamar_edge('arquivar-antigos', '{"storage":true}'::jsonb); $c$);
  end if;
  -- todo dia 1 às 06:15 de Brasília: autoteste do caminho banco → Storage → planilha (com dados de TESTE) e cópia mensal do resumo
  if not exists (select 1 from cron.job where jobname = 'arquivo-autoteste-mensal') then
    perform cron.schedule('arquivo-autoteste-mensal', '15 9 1 * *', $c$ select public.chamar_edge('arquivar-antigos', '{"autoteste":true,"resumoMensal":true}'::jsonb); $c$);
  end if;
end $$;

-- resumo de um mês (para a cópia de segurança mensal na planilha): por dia, pedidos e total (ativos + arquivados)
create or replace function public.api_resumo_mes_servico(p_mes text) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
declare v_ini date; v_fim date;
begin
  if p_mes !~ '^\d{4}-(0[1-9]|1[0-2])$' then return jsonb_build_object('ok', false, 'message', 'Mês inválido.'); end if;
  v_ini := (p_mes || '-01')::date; v_fim := (v_ini + interval '1 month')::date;
  return jsonb_build_object('ok', true, 'mes', p_mes, 'dias', coalesce((
    select jsonb_agg(jsonb_build_object('dia', dia, 'pedidos', n, 'total', tot, 'cancelados', canc) order by dia) from (
      select (data_hora at time zone 'America/Sao_Paulo')::date dia, count(*) filter (where status::text = 'Confirmada') n,
             coalesce(sum(valor_total) filter (where status::text = 'Confirmada'), 0) tot, count(*) filter (where status::text = 'Cancelada') canc
        from (select data_hora, status::text status, valor_total from vendas
              union all select data_hora, status, valor_total from vendas_resumo_arquivo) t
       where (data_hora at time zone 'America/Sao_Paulo')::date >= v_ini and (data_hora at time zone 'America/Sao_Paulo')::date < v_fim
       group by 1) x), '[]'::jsonb));
end $function$;
revoke all on function public.api_resumo_mes_servico(text) from public, anon, authenticated;
grant execute on function public.api_resumo_mes_servico(text) to service_role;

-- ---------------------------------------------------------------------
-- Tela "Armazenamento" (Admin)
-- ---------------------------------------------------------------------
create or replace function public.api_armazenamento_painel(p jsonb default '{}'::jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_lim_db numeric := _limite_banco_mb(); v_lim_st numeric; v_db numeric := pg_database_size(current_database()) / 1048576.0; v_st numeric;
        v_n int; v_sdb numeric; v_sst numeric; v_cel bigint; v_cel_em timestamptz; v_novo int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_novo := nullif(p->>'storageLimiteMb', '')::int;
  if v_novo is not null then
    if v_novo < 100 or v_novo > 10000000 then return _falha('Informe o limite do Storage em MB (entre 100 e 10.000.000). Grátis: 1024.'); end if;
    if coalesce((api_verificar_senha_admin(jsonb_build_object('senha', coalesce(p->>'senha', '')))->>'ok')::boolean, false) is not true then
      return _falha('Senha incorreta. O limite não foi alterado.');
    end if;
    update backup_config set storage_limite_mb = v_novo where id;
    perform _auditar('Limite do Storage alterado', v_novo || ' MB');
  end if;
  perform _espaco_snapshot();
  select storage_limite_mb into v_lim_st from backup_config where id;
  v_lim_st := coalesce(v_lim_st, 1024);
  v_st := _storage_bytes() / 1048576.0;
  select count(*), regr_slope(db_bytes::double precision, extract(epoch from dia::timestamp)::double precision) * 86400 / 1048576.0,
         regr_slope(storage_bytes::double precision, extract(epoch from dia::timestamp)::double precision) filter (where storage_bytes is not null) * 86400 / 1048576.0
    into v_n, v_sdb, v_sst from espaco_historico where dia >= current_date - 44;
  select (valor #>> '{}')::bigint, atualizado_em into v_cel, v_cel_em from sistema where chave = 'planilha_celulas';
  return jsonb_build_object('ok', true,
    'banco', jsonb_build_object('mb', round(v_db, 1), 'limiteMb', v_lim_db, 'pct', round(v_db / v_lim_db * 100, 1),
       'crescimentoMbDia', case when v_n >= 5 then round(v_sdb, 3) end,
       'diasAte95', case when v_n >= 5 and v_sdb > 0.0001 then floor(greatest(0, (v_lim_db * 0.95 - v_db) / v_sdb)) end,
       'maiores', coalesce((select jsonb_agg(jsonb_build_object('tabela', relname, 'mb', mb) order by mb desc)
          from (select c.relname, round(pg_total_relation_size(c.oid) / 1048576.0, 1) mb from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname in ('public', 'cron') and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 8) t), '[]'::jsonb)),
    'storage', jsonb_build_object('mb', round(v_st, 2), 'limiteMb', v_lim_st, 'pct', round(v_st / v_lim_st * 100, 1),
       'crescimentoMbDia', case when v_n >= 5 and v_sst is not null then round(v_sst, 3) end,
       'diasAte95', case when v_n >= 5 and v_sst > 0.0001 then floor(greatest(0, (v_lim_st * 0.95 - v_st) / v_sst)) end,
       'buckets', coalesce((select jsonb_agg(jsonb_build_object('bucket', b.id, 'arquivos', (select count(*) from storage.objects o where o.bucket_id = b.id), 'mb', round(_storage_bytes(b.id) / 1048576.0, 2)) order by b.id) from storage.buckets b), '[]'::jsonb)),
    'planilha', jsonb_build_object('celulas', v_cel, 'limite', 10000000, 'pct', case when v_cel is not null then round(v_cel / 100000.0, 1) end, 'medidoEm', v_cel_em),
    'arquivo', coalesce((select jsonb_agg(jsonb_build_object('mes', mes, 'tipo', tipo, 'storage', st, 'planilha', pl) order by mes desc, tipo)
        from (select mes, tipo, sum(qtd) filter (where local = 'storage') st, sum(qtd) filter (where local = 'planilha') pl from arquivo_mapa group by 1, 2) m), '[]'::jsonb),
    'execucoes', coalesce((select jsonb_agg(jsonb_build_object('em', em, 'gatilho', gatilho, 'origem', origem, 'destino', destino, 'qtd', qtd, 'arquivos', arquivos,
        'erro', erro, 'liberadoMb', round(liberado_bytes / 1048576.0, 1), 'medido', medido_em is not null) order by em desc)
        from (select * from arquivo_execucoes order by em desc limit 12) e), '[]'::jsonb),
    'compactacao', jsonb_build_object(
        'proxima', (select min(to_timestamp(substring(jobname from 'compactar-(\d+)')::bigint)) from cron.job where jobname like 'compactar-%'),
        'ultima', greatest((select max(end_time) from cron.job_run_details where command like 'vacuum full public.vendas%' and status = 'succeeded'),
                           (select max(medido_em) from arquivo_execucoes))),   -- o histórico do agendador é limpo depois de 3 dias
    'config', (select jsonb_build_object('arquivarAtivo', arquivar_ativo, 'arquivarDias', arquivar_dias, 'storageLimiteMb', storage_limite_mb) from backup_config where id));
end $function$;
revoke all on function public.api_armazenamento_painel(jsonb) from public, anon;
grant execute on function public.api_armazenamento_painel(jsonb) to authenticated, service_role;

-- usados pela função "arquivar-antigos": aviso ao Admin e tamanho do banco antes do arquivamento
create or replace function public.api_push_admins_servico(p_titulo text, p_corpo text, p_tag text default 'arquivo')
 returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  perform _push_admins(left(coalesce(p_titulo, 'Aviso do arquivo'), 120), left(coalesce(p_corpo, ''), 400), coalesce(p_tag, 'arquivo'));
end $function$;
revoke all on function public.api_push_admins_servico(text, text, text) from public, anon, authenticated;
grant execute on function public.api_push_admins_servico(text, text, text) to service_role;

create or replace function public.api_espaco_tamanho_servico()
 returns bigint language sql stable security definer set search_path to 'public' as $function$
  select pg_database_size(current_database())
$function$;
revoke all on function public.api_espaco_tamanho_servico() from public, anon, authenticated;
grant execute on function public.api_espaco_tamanho_servico() to service_role;


-- ======================================================================
-- 57-ifood-homologacao-2.sql
-- ======================================================================
-- =====================================================================
-- 57 · iFood — preparação para a homologação (parte 2). Tudo aditivo; pode rodar de novo sem erro.
--  C-08  Pedido: bandeira do cartão (e se é pago no app ou na entrega), quem paga o cupom (iFood ou loja)
--        e o horário de retirada agendada aparecem nas observações (tela e comanda).
--  C-06  Cancelar pedido do iFood: os motivos OFICIAIS do iFood são buscados antes e a equipe escolhe um.
--  C-07  Códigos: validar o código do entregador do iFood (coleta) e o código de entrega pedido pelo iFood.
--  C-02  Lista de lojas do app (GET /merchants): confere se o merchantId configurado pertence ao app.
--  D-01  Estado de cada módulo do iFood (OK / 401 / 403 / 429 / erro), último sucesso e último erro.
--  C-13  Aviso no celular quando um módulo passa a ser recusado (401/403) — no máximo 1 a cada 6 h por módulo.
-- =====================================================================

-- ---------- colunas novas ----------
alter table public.ifood_pedidos add column if not exists motivos_cancel jsonb;
alter table public.ifood_pedidos add column if not exists motivos_em timestamptz;
alter table public.ifood_pedidos add column if not exists motivo_escolhido jsonb;
alter table public.ifood_pedidos add column if not exists codigo_coleta_ok boolean;
alter table public.ifood_pedidos add column if not exists codigo_entrega_ok boolean;
alter table public.ifood_pedidos add column if not exists codigo_erro text;
alter table public.ifood_pedidos add column if not exists codigo_em timestamptz;
alter table public.ifood_loja add column if not exists lojas jsonb;
alter table public.ifood_loja add column if not exists merchant_valido boolean;
alter table public.ifood_loja add column if not exists lojas_em timestamptz;

-- ações novas na fila
alter table public.ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table public.ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar',
  'negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler',
  'catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','catalogo_modelo_enviar','catalogo_lote_preco','catalogo_lote_status','catalogo_opcao_preco',
  'catalogo_opcao_status','avaliacao_responder','motivos','codigo_coleta','codigo_entrega']));

-- ---------- estado por módulo (D-01) ----------
create table if not exists public.ifood_modulos (
  modulo text primary key,
  ultimo_ok timestamptz,
  ultimo_erro_em timestamptz,
  ultimo_status int,
  ultima_msg text,
  avisado_em timestamptz,
  atualizado_em timestamptz not null default now()
);
alter table public.ifood_modulos enable row level security;
revoke all on table public.ifood_modulos from public, anon, authenticated;
grant all on table public.ifood_modulos to service_role;

-- recebe um resumo da rodada: {"order":{"ok":true}, "review":{"ok":false,"status":403,"msg":"..."}}
create or replace function public.ifood_modulos_registrar(p jsonb) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare k text; v jsonb; v_ant int; v_av timestamptz; v_st int;
begin
  for k, v in select * from jsonb_each(coalesce(p, '{}'::jsonb)) loop
    k := left(lower(k), 30);
    if coalesce((v->>'ok')::boolean, false) then
      insert into ifood_modulos (modulo, ultimo_ok, ultimo_status, atualizado_em) values (k, now(), 200, now())
        on conflict (modulo) do update set ultimo_ok = now(), ultimo_status = 200, atualizado_em = now();
    else
      v_st := nullif(v->>'status', '')::int;
      select ultimo_status, avisado_em into v_ant, v_av from ifood_modulos where modulo = k;
      insert into ifood_modulos (modulo, ultimo_erro_em, ultimo_status, ultima_msg, atualizado_em) values (k, now(), v_st, left(v->>'msg', 300), now())
        on conflict (modulo) do update set ultimo_erro_em = now(), ultimo_status = excluded.ultimo_status, ultima_msg = excluded.ultima_msg, atualizado_em = now();
      if v_st in (401, 403) and (v_av is null or v_av < now() - interval '6 hours') and v_ant is distinct from v_st then
        update ifood_modulos set avisado_em = now() where modulo = k;
        perform _integ_log('ifood', 'erro', 'Módulo ' || k || ' do iFood recusado (' || v_st || '): ' || left(coalesce(v->>'msg', ''), 150));
        begin perform _push_admins('iFood: módulo ' || k || ' recusado (' || v_st || ')',
          case when v_st = 401 then 'O iFood não aceitou as credenciais. Confira Client ID e Client Secret.' else 'O iFood não liberou este módulo para o app. Veja Integrações → iFood → Estado dos módulos.' end, 'ifood-modulo-' || k);
        exception when others then null; end;
      end if;
    end if;
  end loop;
end $function$;
revoke all on function public.ifood_modulos_registrar(jsonb) from public, anon, authenticated;
grant execute on function public.ifood_modulos_registrar(jsonb) to service_role;

create or replace function public.api_ifood_modulos(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('modulo', modulo, 'ultimoOk', ultimo_ok, 'ultimoErroEm', ultimo_erro_em, 'status', ultimo_status, 'msg', ultima_msg) order by modulo) from ifood_modulos), '[]'::jsonb),
    'loja', (select jsonb_build_object('merchantValido', merchant_valido, 'lojas', coalesce(lojas, '[]'::jsonb), 'lojasEm', lojas_em, 'situacao', situacao, 'disponivel', disponivel, 'motivo', motivo, 'verificadoEm', verificado_em) from ifood_loja where id));
end $function$;
revoke all on function public.api_ifood_modulos(jsonb) from public, anon;
grant execute on function public.api_ifood_modulos(jsonb) to authenticated, service_role;

-- ---------- lojas do app (C-02) ----------
create or replace function public.ifood_lojas_gravar(p_lista jsonb, p_merchant text) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare v_ok boolean; v_ant boolean;
begin
  v_ok := exists (select 1 from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) x where x->>'id' = p_merchant or x->>'merchantId' = p_merchant);
  select merchant_valido into v_ant from ifood_loja where id;
  update ifood_loja set lojas = (select coalesce(jsonb_agg(jsonb_build_object('id', coalesce(x->>'id', x->>'merchantId'), 'nome', coalesce(x->>'name', x->>'corporateName', ''))), '[]'::jsonb)
                                   from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) x),
                        merchant_valido = v_ok, lojas_em = now(), atualizado_em = now() where id;
  if not v_ok and v_ant is distinct from false then
    perform _integ_log('ifood', 'erro', 'O merchantId configurado não está entre as lojas deste app no iFood.');
    begin perform _push_admins('iFood: loja configurada não pertence ao app', 'Confira o Merchant ID em Integrações → iFood.', 'ifood-merchant'); exception when others then null; end;
  end if;
  return jsonb_build_object('ok', true, 'valido', v_ok);
end $function$;
revoke all on function public.ifood_lojas_gravar(jsonb, text) from public, anon, authenticated;
grant execute on function public.ifood_lojas_gravar(jsonb, text) to service_role;

-- ---------- motivos oficiais de cancelamento (C-06) ----------
create or replace function public.ifood_motivos_gravar(p_pedido text, p_lista jsonb) returns void
 language sql security definer set search_path to 'public' as $function$
  update ifood_pedidos set motivos_cancel = (select coalesce(jsonb_agg(jsonb_build_object('codigo', coalesce(x->>'cancelCodeId', x->>'code', x->>'id'), 'descricao', coalesce(x->>'description', x->>'reason', ''))), '[]'::jsonb)
                                               from jsonb_array_elements(case when jsonb_typeof(p_lista) = 'array' then p_lista else '[]'::jsonb end) x),
         motivos_em = now(), atualizado_em = now() where pedido_ifood = p_pedido
$function$;
revoke all on function public.ifood_motivos_gravar(text, jsonb) from public, anon, authenticated;
grant execute on function public.ifood_motivos_gravar(text, jsonb) to service_role;

-- a tela pede os motivos: devolve o que tem e, se estiverem velhos (> 3 min), pede de novo ao iFood (na próxima rodada, até 30 s)
create or replace function public.api_ifood_motivos(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare r ifood_pedidos%rowtype; v_aguarda boolean := false; v_erro text;
begin
  if not tem_nivel('Admin', 'Operador', 'Garçom', 'Cozinha') then return _negado(); end if;
  select * into r from ifood_pedidos where venda_id = nullif(p->>'vendaId', '')::uuid;
  if not found then return jsonb_build_object('ok', true, 'ifood', false); end if;
  if r.simulado then return jsonb_build_object('ok', true, 'ifood', true, 'simulado', true, 'motivos', '[]'::jsonb); end if;
  if r.motivos_em is null or r.motivos_em < now() - interval '3 minutes' then
    if not exists (select 1 from ifood_acoes where pedido_ifood = r.pedido_ifood and acao = 'motivos' and estado = 'pendente') then
      perform _ifood_enfileirar(r.pedido_ifood, 'motivos', '{}'::jsonb);
    end if;
    v_aguarda := true;
  end if;
  select erro into v_erro from ifood_acoes where pedido_ifood = r.pedido_ifood and acao = 'motivos' and estado = 'erro' and criado_em > now() - interval '5 minutes' order by id desc limit 1;
  return jsonb_build_object('ok', true, 'ifood', true, 'motivos', coalesce(r.motivos_cancel, '[]'::jsonb), 'em', r.motivos_em, 'aguardando', v_aguarda,
    'erro', v_erro, 'escolhido', r.motivo_escolhido);
end $function$;
revoke all on function public.api_ifood_motivos(jsonb) from public, anon;
grant execute on function public.api_ifood_motivos(jsonb) to authenticated, service_role;

create or replace function public.api_ifood_motivo_escolher(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare r ifood_pedidos%rowtype; v_cod text := left(btrim(coalesce(p->>'codigo', '')), 40);
begin
  if not tem_nivel('Admin', 'Operador', 'Garçom', 'Cozinha') then return _negado(); end if;
  select * into r from ifood_pedidos where venda_id = nullif(p->>'vendaId', '')::uuid for update;
  if not found then return _falha('Pedido do iFood não encontrado.'); end if;
  if v_cod = '' or not exists (select 1 from jsonb_array_elements(coalesce(r.motivos_cancel, '[]'::jsonb)) x where x->>'codigo' = v_cod) then
    return _falha('Escolha um dos motivos do iFood.');
  end if;
  -- a descrição vem da lista guardada (a que o iFood mandou), não do navegador
  update ifood_pedidos set motivo_escolhido = jsonb_build_object('codigo', v_cod,
           'descricao', (select left(x->>'descricao', 200) from jsonb_array_elements(r.motivos_cancel) x where x->>'codigo' = v_cod limit 1), 'em', now()),
         atualizado_em = now() where pedido_ifood = r.pedido_ifood;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.api_ifood_motivo_escolher(jsonb) from public, anon;
grant execute on function public.api_ifood_motivo_escolher(jsonb) to authenticated, service_role;

-- o cancelamento leva o código escolhido para o iFood
do $$
declare d text;
begin
  select pg_get_functiondef('public._ifood_trg_status()'::regprocedure) into d;
  if position('motivo_escolhido' in d) = 0 then
    if (length(d) - length(replace(d, 'jsonb_build_object(''motivo'', new.motivo_cancelamento)', ''))) / length('jsonb_build_object(''motivo'', new.motivo_cancelamento)') <> 1 then
      raise exception '57: ponto de troca não encontrado em _ifood_trg_status';
    end if;
    d := replace(d, 'jsonb_build_object(''motivo'', new.motivo_cancelamento)',
      'jsonb_build_object(''motivo'', coalesce(nullif(r.motivo_escolhido->>''descricao'', ''''), new.motivo_cancelamento), ''codigo'', r.motivo_escolhido->>''codigo'')');
    execute d;
  end if;
end $$;

-- ---------- códigos de coleta e de entrega (C-07) ----------
-- coleta: entrega PELO iFood; o entregador do iFood chega à loja e diz o código (validatePickupCode)
-- entrega: entrega pela LOJA; o iFood pede o código ao entregar (evento de "código de entrega") e o entregador digita (verifyDeliveryCode)
create or replace function public.api_ifood_codigos_pendentes(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'lista', coalesce((
    select jsonb_agg(jsonb_build_object('vendaId', v.id, 'numero', v.numero_pedido, 'ifood', i.numero_ifood, 'tipo', x.tipo, 'cliente', v.cliente_nome,
             'erro', case when i.codigo_em > now() - interval '10 minutes' then i.codigo_erro end,
             'enviando', exists (select 1 from ifood_acoes a where a.pedido_ifood = i.pedido_ifood and a.acao = 'codigo_' || x.tipo and a.estado = 'pendente')) order by v.data_hora)
      from ifood_pedidos i join vendas v on v.id = i.venda_id
      cross join lateral (select case
          when upper(coalesce(i.bruto->'delivery'->>'deliveredBy', '')) = 'IFOOD' and v.status_pedido::text in ('Em preparo', 'Pronta') and i.codigo_coleta_ok is not true
               and exists (select 1 from ifood_eventos e where e.pedido_ifood = i.pedido_ifood and e.recebido_em > now() - interval '6 hours'
                            and (upper(e.codigo) in ('ADR', 'GTO', 'AAO') or e.codigo_completo ilike any (array['%ASSIGN_DRIVER%', '%GOING_TO_ORIGIN%', '%ARRIVED_AT_ORIGIN%', '%PICKUP_CODE%'])))
            then 'coleta'
          when upper(coalesce(i.bruto->'delivery'->>'deliveredBy', '')) <> 'IFOOD' and v.status_pedido::text = 'Saiu para entrega' and i.codigo_entrega_ok is not true
               and exists (select 1 from ifood_eventos e where e.pedido_ifood = i.pedido_ifood and e.recebido_em > now() - interval '6 hours'
                            and (e.codigo_completo ilike '%DROP_CODE%' or e.codigo_completo ilike '%DELIVERY_CODE%' or upper(e.codigo) = 'DDCR'))
            then 'entrega' end as tipo) x
     where not i.simulado and v.status = 'Confirmada' and x.tipo is not null), '[]'::jsonb));
end $function$;
revoke all on function public.api_ifood_codigos_pendentes(jsonb) from public, anon;
grant execute on function public.api_ifood_codigos_pendentes(jsonb) to authenticated, service_role;

create or replace function public.api_ifood_codigo(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare r ifood_pedidos%rowtype; v_tipo text := lower(coalesce(p->>'tipo', '')); v_cod text := regexp_replace(coalesce(p->>'codigo', ''), '\s', '', 'g');
begin
  if not tem_nivel('Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador') then return _negado(); end if;
  if v_tipo not in ('coleta', 'entrega') then return _falha('Tipo de código inválido.'); end if;
  if v_cod !~ '^[0-9A-Za-z]{3,12}$' then return _falha('Digite o código que o iFood mostrou (só letras e números).'); end if;
  select * into r from ifood_pedidos where venda_id = nullif(p->>'vendaId', '')::uuid;
  if not found then return _falha('Pedido do iFood não encontrado.'); end if;
  if r.simulado then return _falha('Pedido de simulação: não há código no iFood.'); end if;
  delete from ifood_acoes where pedido_ifood = r.pedido_ifood and acao = 'codigo_' || v_tipo and estado = 'pendente';
  perform _ifood_enfileirar(r.pedido_ifood, 'codigo_' || v_tipo, jsonb_build_object('codigo', v_cod));
  update ifood_pedidos set codigo_erro = null, codigo_em = now() where pedido_ifood = r.pedido_ifood;
  perform _auditar('Código do iFood enviado', 'iFood #' || r.numero_ifood || ' · código de ' || v_tipo, null);
  return jsonb_build_object('ok', true, 'message', 'Código enviado ao iFood. A resposta chega em até 30 segundos.');
end $function$;
revoke all on function public.api_ifood_codigo(jsonb) from public, anon;
grant execute on function public.api_ifood_codigo(jsonb) to authenticated, service_role;

create or replace function public.ifood_codigo_resultado(p_pedido text, p_tipo text, p_ok boolean, p_erro text default null) returns void
 language plpgsql security definer set search_path to 'public' as $function$
begin
  if p_tipo = 'coleta' then update ifood_pedidos set codigo_coleta_ok = case when p_ok then true else codigo_coleta_ok end, codigo_erro = case when p_ok then null else left(p_erro, 200) end, codigo_em = now() where pedido_ifood = p_pedido;
  else update ifood_pedidos set codigo_entrega_ok = case when p_ok then true else codigo_entrega_ok end, codigo_erro = case when p_ok then null else left(p_erro, 200) end, codigo_em = now() where pedido_ifood = p_pedido; end if;
  perform _integ_log('ifood', case when p_ok then 'info' else 'aviso' end, 'Código de ' || p_tipo || ' do pedido ' || right(p_pedido, 6) || case when p_ok then ' aceito pelo iFood' else ' recusado: ' || left(coalesce(p_erro, ''), 120) end);
end $function$;
revoke all on function public.ifood_codigo_resultado(text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.ifood_codigo_resultado(text, text, boolean, text) to service_role;

-- ---------- C-08: bandeira, quem paga o cupom e retirada agendada ----------
create or replace function public._ifood_extras_obs(p_order jsonb) returns text
 language plpgsql stable set search_path to 'public' as $function$
declare m jsonb; b jsonb; s jsonb; v_txt text := ''; v_tipo text; v_ifood numeric := 0; v_loja numeric := 0; v_outros numeric := 0; v_n numeric; v_ret text; v_t timestamptz;
begin
  -- cartão: tipo (crédito/débito/vale), bandeira e se foi pago no app ou será na entrega
  for m in select * from jsonb_array_elements(coalesce(p_order->'payments'->'methods', '[]'::jsonb)) loop
    v_tipo := upper(coalesce(m->>'method', ''));
    if v_tipo in ('CREDIT', 'DEBIT', 'MEAL_VOUCHER', 'FOOD_VOUCHER') or m ? 'card' then
      v_txt := v_txt || ' · Cartão ' || case v_tipo when 'CREDIT' then 'CRÉDITO' when 'DEBIT' then 'DÉBITO' when 'MEAL_VOUCHER' then 'VALE-REFEIÇÃO' when 'FOOD_VOUCHER' then 'VALE-ALIMENTAÇÃO' else v_tipo end
        || coalesce(' ' || upper(nullif(m->'card'->>'brand', '')), '')
        || case when upper(coalesce(m->>'type', '')) = 'OFFLINE' then ' (cobrar na entrega: levar maquininha)' else ' (pago no app)' end;
    end if;
  end loop;
  -- cupom/desconto: quem paga
  for b in select * from jsonb_array_elements(coalesce(p_order->'benefits', '[]'::jsonb)) loop
    for s in select * from jsonb_array_elements(coalesce(b->'sponsorshipValues', '[]'::jsonb)) loop
      v_n := coalesce(nullif(s->>'value', '')::numeric, 0);
      if upper(coalesce(s->>'name', '')) = 'IFOOD' then v_ifood := v_ifood + v_n;
      elsif upper(coalesce(s->>'name', '')) = 'MERCHANT' then v_loja := v_loja + v_n;
      else v_outros := v_outros + v_n; end if;
    end loop;
  end loop;
  if v_ifood + v_loja + v_outros > 0 then
    v_txt := v_txt || ' · Cupom: ' || concat_ws(' + ',
      case when v_ifood > 0 then 'R$ ' || replace(to_char(v_ifood, 'FM9999990.00'), '.', ',') || ' pago pelo iFood' end,
      case when v_loja > 0 then 'R$ ' || replace(to_char(v_loja, 'FM9999990.00'), '.', ',') || ' pago pela loja' end,
      case when v_outros > 0 then 'R$ ' || replace(to_char(v_outros, 'FM9999990.00'), '.', ',') || ' pago por parceiro' end);
  end if;
  -- retirada: horário combinado
  if upper(coalesce(p_order->>'orderType', '')) = 'TAKEOUT' then
    v_ret := coalesce(p_order->'takeout'->>'takeoutDateTime', '');
    begin v_t := nullif(v_ret, '')::timestamptz; exception when others then v_t := null; end;
    if v_t is not null then v_txt := v_txt || ' · RETIRADA ' || case when upper(coalesce(p_order->'takeout'->>'mode', '')) = 'SCHEDULED' then 'AGENDADA' else '' end || ' às ' || to_char(v_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'); end if;
  end if;
  return v_txt;
exception when others then return '';
end $function$;

do $$
declare d text; a text := 'if p_simulado then v_obs := v_obs || '' · TESTE (simulação)''; end if;';
begin
  select pg_get_functiondef('public.ifood_criar_pedido(jsonb,boolean)'::regprocedure) into d;
  if position('_ifood_extras_obs' in d) = 0 then
    if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception '57: ponto de troca não encontrado em ifood_criar_pedido'; end if;
    d := replace(d, a, 'v_obs := v_obs || public._ifood_extras_obs(p_order);   -- 57 (C-08)' || chr(10) || '  ' || a);
    execute d;
  end if;
end $$;

-- tarefas periódicas do ifood-sync: + "lojas" (1x por dia). Antes, qualquer tarefa diferente de "financeiro" mexia no relógio das avaliações.
alter table public.ifood_estado add column if not exists lojas_em timestamptz;
create or replace function public.ifood_precisa(p_tarefa text, p_minutos integer) returns boolean
 language plpgsql security definer set search_path to 'public' as $function$
declare v timestamptz;
begin
  if p_tarefa not in ('financeiro', 'avaliacoes', 'lojas') then return false; end if;
  select case p_tarefa when 'financeiro' then financeiro_em when 'avaliacoes' then avaliacoes_em when 'lojas' then lojas_em end into v from ifood_estado where id;
  if v is not null and v > now() - make_interval(mins => p_minutos) then return false; end if;
  if p_tarefa = 'financeiro' then update ifood_estado set financeiro_em = now() where id;
  elsif p_tarefa = 'avaliacoes' then update ifood_estado set avaliacoes_em = now() where id;
  else update ifood_estado set lojas_em = now() where id; end if;
  return true;
end $function$;
revoke all on function public.ifood_precisa(text, integer) from public, anon, authenticated;
grant execute on function public.ifood_precisa(text, integer) to service_role;


-- ======================================================================
-- 58-infinitepay.sql
-- ======================================================================
-- =====================================================================
-- 58 · InfinitePay como segundo provedor de pagamento online (plano, seção 10).
-- Cada forma paga pelo site (Pix, crédito) escolhe o provedor: Mercado Pago ou InfinitePay. Dá para usar os dois ao mesmo tempo.
-- A InfinitePay usa o "Checkout Integrado": o cliente vai ao site da InfinitePay pagar e volta. O aviso (webhook) da InfinitePay
-- NÃO tem assinatura, então nada é aprovado sem CONSULTAR a InfinitePay (payment_check) e conferir o valor.
-- "Simulação" (modo homologacao): link falso; Pagar / Recusar / Expirar pelos botões, sem a InfinitePay.
-- Reembolso: feito no app da InfinitePay e REGISTRADO aqui (valor, motivo, quem, quando).
-- Tudo DESLIGADO por padrão. Aditivo; pode rodar de novo sem erro.
-- ⚠️ Escrito pela documentação pública (api.checkout.infinitepay.io: /links e /payment_check), sem conta real para testar.
-- =====================================================================

-- troca de texto conferida: se o trecho não aparecer exatamente 1 vez na função ao vivo, PARA com erro (nada fica pela metade em silêncio)
create or replace function pg_temp.tb_trocar1(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception '58: trecho esperado apareceu % vez(es): %', n, left(a, 90); end if;
  return replace(d, a, b);
end $f$;

-- ---------- estrutura ----------
alter table public.integracoes_config drop constraint if exists integracoes_config_provedor_check;
alter table public.integracoes_config add constraint integracoes_config_provedor_check check (provedor = any (array['ifood', 'nfce', 'mercadopago', 'infinitepay']));
insert into public.integracoes_config (provedor, ligado, modo, checklist, config)
values ('infinitepay', false, 'homologacao', '{}'::jsonb, '{"linkValidadeMin": 30, "emailsTeste": [], "testeNoCardapio": false}'::jsonb)
on conflict (provedor) do nothing;

alter table public.formas_pagamento add column if not exists provedor_online text not null default 'mercadopago';
alter table public.formas_pagamento drop constraint if exists formas_pagamento_provedor_online_check;
alter table public.formas_pagamento add constraint formas_pagamento_provedor_online_check check (provedor_online in ('mercadopago', 'infinitepay'));

alter table public.pagamentos_online add column if not exists provedor text not null default 'mercadopago';
alter table public.pagamentos_online add column if not exists ip_link text;
alter table public.pagamentos_online add column if not exists ip_slug text;
alter table public.pagamentos_online add column if not exists ip_transacao text;
alter table public.pagamentos_online add column if not exists ip_recibo text;
alter table public.pagamentos_online add column if not exists ip_metodo_pago text;
alter table public.pagamentos_online add column if not exists ip_conferido_em timestamptz;
-- chaves guardadas: + InfiniteTag, chave do Checkout (se a conta pedir) e segredo do aviso. Mantém as que o banco já aceita.
do $$
declare v_def text; v_lista text[];
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conname = 'integracoes_segredos_chave_check' and conrelid = 'public.integracoes_segredos'::regclass;
  if v_def is not null and position('ip_handle' in v_def) = 0 then
    select array_agg(distinct m[1]) into v_lista from regexp_matches(v_def, '''([a-z0-9_]+)''', 'g') m;
    v_lista := v_lista || array['ip_handle', 'ip_chave_checkout', 'ip_webhook_segredo'];
    alter table public.integracoes_segredos drop constraint integracoes_segredos_chave_check;
    execute format('alter table public.integracoes_segredos add constraint integracoes_segredos_chave_check check (chave = any (%L::text[]))', v_lista);
  end if;
end $$;

create index if not exists ix_pagamentos_online_provedor on public.pagamentos_online (provedor, criado_em desc);
create unique index if not exists ux_pagamentos_online_ip_transacao on public.pagamentos_online (ip_transacao) where ip_transacao is not null;

create table if not exists public.pagamentos_reembolsos_manuais (
  id bigserial primary key,
  pagamento_id uuid not null references public.pagamentos_online(id),
  valor numeric(10,2) not null check (valor > 0),
  motivo text not null,
  registrado_por uuid,
  registrado_em timestamptz not null default now()
);
alter table public.pagamentos_reembolsos_manuais enable row level security;
revoke all on table public.pagamentos_reembolsos_manuais from public, anon, authenticated;
grant all on table public.pagamentos_reembolsos_manuais to service_role;
grant usage, select on sequence public.pagamentos_reembolsos_manuais_id_seq to service_role;

create or replace function public._pag_nome(p_prov text) returns text language sql immutable as $$
  select case when p_prov = 'infinitepay' then 'InfinitePay' else 'Mercado Pago' end
$$;

-- ---------- o que o cardápio vê: junta Mercado Pago e InfinitePay ----------
-- 1) a função antiga vira _mp_publico_mp (só as formas do Mercado Pago)
do $$
declare d text;
begin
  if to_regprocedure('public._mp_publico_mp(uuid)') is null then
    select pg_get_functiondef('public._mp_publico(uuid)'::regprocedure) into d;
    d := pg_temp.tb_trocar1(d, 'FUNCTION public._mp_publico(', 'FUNCTION public._mp_publico_mp(');
    if position('f.aceita_online and f.tipo_online is not null;' in d) = 0 then raise exception '58: ponto de troca não encontrado em _mp_publico'; end if;
    d := pg_temp.tb_trocar1(d, 'f.aceita_online and f.tipo_online is not null;', 'f.aceita_online and f.tipo_online is not null and f.provedor_online = ''mercadopago'';');
    execute d;
  end if;
end $$;
revoke all on function public._mp_publico_mp(uuid) from public, anon, authenticated;

create or replace function public._ip_publico(p_user uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
declare c integracoes_config%rowtype; v_sim boolean; v_visivel boolean; v_email text; v_formas jsonb;
begin
  select * into c from integracoes_config where provedor = 'infinitepay';
  if c.provedor is null or not c.ligado then return jsonb_build_object('ligado', false); end if;
  v_sim := c.modo <> 'producao';
  if v_sim then
    v_visivel := coalesce((c.config->>'testeNoCardapio')::boolean, false);
    if not v_visivel and p_user is not null and jsonb_typeof(c.config->'emailsTeste') = 'array' then
      select lower(email) into v_email from auth.users where id = p_user;
      v_visivel := v_email is not null and exists (select 1 from jsonb_array_elements_text(c.config->'emailsTeste') x where lower(btrim(x)) = v_email);
    end if;
    if not coalesce(v_visivel, false) then return jsonb_build_object('ligado', false); end if;
  elsif not exists (select 1 from integracoes_segredos where chave = 'ip_handle') then
    return jsonb_build_object('ligado', false);
  elsif coalesce((c.config->>'producaoSoTeste')::boolean, false) then   -- PRODUÇÃO só para os e-mails da lista (teste real de valor pequeno)
    select lower(email) into v_email from auth.users where id = p_user;
    if v_email is null or jsonb_typeof(c.config->'emailsTeste') <> 'array'
       or not exists (select 1 from jsonb_array_elements_text(c.config->'emailsTeste') x where lower(btrim(x)) = v_email) then
      return jsonb_build_object('ligado', false);
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo_online, 'provedor', 'infinitepay') order by f.ordem), '[]'::jsonb) into v_formas
    from formas_pagamento f where f.ativa and f.visivel_cardapio and f.aceita_online and f.tipo_online in ('pix', 'credito') and f.provedor_online = 'infinitepay';
  if jsonb_array_length(v_formas) = 0 then return jsonb_build_object('ligado', false); end if;
  return jsonb_build_object('ligado', true, 'modo', case when v_sim then 'simulacao' else 'producao' end, 'formas', v_formas,
    'linkValidadeMin', case when coalesce(c.config->>'linkValidadeMin', '') ~ '^[0-9]{1,3}$' then least(120, greatest(10, (c.config->>'linkValidadeMin')::int)) else 30 end);
end $function$;
revoke all on function public._ip_publico(uuid) from public, anon, authenticated;

create or replace function public._mp_publico(p_user uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
declare mp jsonb := public._mp_publico_mp(p_user); ip jsonb := public._ip_publico(p_user); v_formas jsonb := '[]'::jsonb;
begin
  if coalesce((mp->>'ligado')::boolean, false) then
    select coalesce(jsonb_agg(x || jsonb_build_object('provedor', 'mercadopago')), '[]'::jsonb) into v_formas from jsonb_array_elements(mp->'formas') x;
  end if;
  if coalesce((ip->>'ligado')::boolean, false) then v_formas := v_formas || (ip->'formas'); end if;
  if jsonb_array_length(v_formas) = 0 then return jsonb_build_object('ok', true, 'ligado', false); end if;
  return jsonb_build_object('ok', true, 'ligado', true,
    'modo', coalesce(mp->>'modo', case when ip->>'modo' = 'producao' then 'producao' else 'teste' end),
    'publicKey', mp->>'publicKey', 'formas', v_formas, 'pixValidadeMin', coalesce((mp->>'pixValidadeMin')::int, 15),
    'infinitepay', case when coalesce((ip->>'ligado')::boolean, false) then jsonb_build_object('modo', ip->>'modo', 'linkValidadeMin', ip->'linkValidadeMin') end);
end $function$;

-- 2) o Mercado Pago recusa forma que é da InfinitePay
do $$
declare d text; a text := 'if f.id is null or not f.aceita_online or f.tipo_online is null then return _falha(''Forma de pagamento inválida.''); end if;';
begin
  select pg_get_functiondef('public.mp_preparar_pagamento(jsonb)'::regprocedure) into d;
  if position('provedor_online' in d) = 0 then
    if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception '58: ponto de troca não encontrado em mp_preparar_pagamento'; end if;
    d := pg_temp.tb_trocar1(d, a, a || chr(10) || '  if f.provedor_online = ''infinitepay'' then return _falha(''Esta forma é paga pela InfinitePay.''); end if;');
    execute d;
  end if;
end $$;

-- 3) textos de reembolso com o nome do provedor certo
do $$
declare d text; t text[][] := array[
  array['''Reembolsado pelo Mercado Pago''', '''Reembolsado pelo '' || _pag_nome(g.provedor)'],
  array['v_vr, ''Mercado Pago'', ''Reembolso feito no painel do Mercado Pago''', 'v_vr, _pag_nome(g.provedor), ''Reembolso feito no painel/app de '' || _pag_nome(g.provedor)'],
  array['''Devolvido direto no painel do Mercado Pago; a venda continua ativa: decida se cancela.''', '''Devolvido direto no '' || _pag_nome(g.provedor) || ''; a venda continua ativa: decida se cancela.'''],
  array['''Reembolso feito no Mercado Pago''', '''Reembolso feito no '' || _pag_nome(g.provedor)'],
  array[''' devolvido direto no painel do Mercado Pago. A venda continua ativa: veja se cancela.''', ''' devolvido direto no '' || _pag_nome(g.provedor) || ''. A venda continua ativa: veja se cancela.'''],
  array['''Reembolso parcial no Mercado Pago''', '''Reembolso parcial no '' || _pag_nome(g.provedor)'],
  array[''' devolvido direto no painel do Mercado Pago.''', ''' devolvido direto no '' || _pag_nome(g.provedor) || ''.'''],
  array['''Reembolso Mercado Pago''', '''Reembolso '' || _pag_nome(g.provedor)']]; i int;
begin
  select pg_get_functiondef('public.mp_aplicar_status(jsonb)'::regprocedure) into d;
  if position('_pag_nome' in d) = 0 then
    for i in 1 .. array_length(t, 1) loop
      if (length(d) - length(replace(d, t[i][1], ''))) / length(t[i][1]) <> 1 then raise exception '58: texto % não encontrado uma vez em mp_aplicar_status', i; end if;
      d := pg_temp.tb_trocar1(d, t[i][1], t[i][2]);
    end loop;
    execute d;
  end if;
end $$;

-- 3b) InfinitePay: sem o valor pago informado pela InfinitePay, ou valor menor, nunca aprova direto (vai para "Pagamentos que precisam de decisão")
do $$
declare d text;
begin
  select pg_get_functiondef('public.mp_aplicar_status(jsonb)'::regprocedure) into d;
  if position('g.provedor = ''infinitepay'') and v_vp <' in d) = 0 then
    d := pg_temp.tb_trocar1(d, 'if v_vp > 0 and v_vp < g.valor - 0.009 and g.venda_id is null', 'if (v_vp > 0 or g.provedor = ''infinitepay'') and v_vp < g.valor - 0.009 and g.venda_id is null');
    execute d;
  end if;
  -- texto da auditoria do pedido pago pelo site com o nome do provedor certo
  select pg_get_functiondef('public._mp_criar_venda(uuid,uuid)'::regprocedure) into d;
  if position('_pag_nome' in d) = 0 then
    d := pg_temp.tb_trocar1(d, '''Pedido pago pelo site (Mercado Pago)''', '''Pedido pago pelo site ('' || _pag_nome((select provedor from pagamentos_online where id = p_pag)) || '')''');
    execute d;
  end if;
end $$;

-- 4) testes do Mercado Pago contam só pagamentos do Mercado Pago (a simulação da InfinitePay não pode marcar o passo dele)
do $$
declare d text;
begin
  select pg_get_functiondef('public.api_mp_pagamentos_recentes(jsonb)'::regprocedure) into d;
  if position('provedor = ''mercadopago''' in d) = 0 then
    if (length(d) - length(replace(d, 'where mp_modo = ''homologacao'' and metodo', ''))) / length('where mp_modo = ''homologacao'' and metodo') <> 3 then raise exception '58: api_mp_pagamentos_recentes diferente do esperado'; end if;
    d := replace(d, 'where mp_modo = ''homologacao'' and metodo', 'where provedor = ''mercadopago'' and mp_modo = ''homologacao'' and metodo');
    d := pg_temp.tb_trocar1(d, 'from (select * from pagamentos_online order by criado_em desc limit 15) x', 'from (select * from pagamentos_online where provedor = ''mercadopago'' order by criado_em desc limit 15) x');
    execute d;
  end if;
  select pg_get_functiondef('public._integ_pendencias(text,text)'::regprocedure) into d;
  if position('infinitepay' in d) = 0 then
    if position('g.mp_modo = ''homologacao''' in d) = 0 or position('when ''chaves_producao'' then' in d) = 0 then raise exception '58: pontos de troca não encontrados em _integ_pendencias'; end if;
    d := pg_temp.tb_trocar1(d, 'g.mp_modo = ''homologacao''', 'g.provedor = ''mercadopago'' and g.mp_modo = ''homologacao''');
    d := pg_temp.tb_trocar1(d, 'when ''chaves_producao'' then',
      'when ''ip_handle'' then exists (select 1 from integracoes_segredos where chave = ''ip_handle'')
        when ''ip_segredo'' then exists (select 1 from integracoes_segredos where chave = ''ip_webhook_segredo'')
        when ''ip_formas'' then exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online in (''pix'', ''credito'') and provedor_online = ''infinitepay'')
        when ''ip_simulacao'' then (select count(distinct status) from pagamentos_online where provedor = ''infinitepay'' and mp_modo = ''homologacao'' and status in (''aprovado'', ''recusado'', ''expirado'')) = 3
        when ''ip_real'' then (select count(distinct metodo) from pagamentos_online where provedor = ''infinitepay'' and mp_modo = ''producao'' and metodo in (''pix'', ''credito'') and status in (''aprovado'', ''reembolso_parcial'', ''reembolsado'')) = 2
        when ''chaves_producao'' then');
    d := pg_temp.tb_trocar1(d, 'if p_prov = ''mercadopago'' and p_modo = ''homologacao'' and',
      'if p_prov = ''infinitepay'' and p_modo = ''homologacao'' and (v_item->>''id'') in (''conta'', ''ip_handle'', ''ip_segredo'', ''ip_simulacao'', ''ip_real'', ''reembolso'') then continue; end if;
    if p_prov = ''infinitepay'' and p_modo = ''producao'' and (v_item->>''id'') in (''ip_real'', ''reembolso'') then continue; end if;
    if p_prov = ''mercadopago'' and p_modo = ''homologacao'' and');
    execute d;
  end if;
  select pg_get_functiondef('public._integ_checklist_def(text)'::regprocedure) into d;
  if position('infinitepay' in d) = 0 then
    d := pg_temp.tb_trocar1(d, '    else ''[]''::jsonb end', '    when ''infinitepay'' then ''[
      {"id":"conta","titulo":"Conta InfinitePay ativa, com o Checkout Integrado liberado"},
      {"id":"ip_handle","titulo":"InfiniteTag digitada aqui","auto":true},
      {"id":"ip_segredo","titulo":"Segredo do aviso gerado (botão Gerar)","auto":true},
      {"id":"ip_formas","titulo":"Pelo menos uma forma (Pix ou crédito) escolhida para pagar pela InfinitePay","auto":true},
      {"id":"ip_simulacao","titulo":"Simulação feita: um pagamento aprovado, um recusado e um expirado","auto":true},
      {"id":"ip_real","titulo":"Depois de ligar em PRODUÇÃO: teste real de valor pequeno, Pix e crédito aprovados","auto":true},
      {"id":"reembolso","titulo":"Reembolso manual testado (devolvido no app da InfinitePay e registrado aqui)"}]''::jsonb
    else ''[]''::jsonb end');
    execute d;
  end if;
end $$;

-- 5) telas de integração: InfinitePay entra nas mesmas funções (listar, ligar, desligar, ajustes, chaves)
do $$
declare r record; d text;
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' and p.proname in ('api_integracoes_desligar', 'api_integracoes_config', 'api_integracoes_ligar', 'api_integracoes_marcar') loop
    d := pg_get_functiondef(r.oid);
    if position('''infinitepay''' in d) = 0 and position('''ifood'', ''nfce'', ''mercadopago''' in d) > 0 then
      d := replace(d, '''ifood'', ''nfce'', ''mercadopago''', '''ifood'', ''nfce'', ''mercadopago'', ''infinitepay''');   -- todas as vezes (a guarda acima garante pelo menos 1)
      d := replace(d, 'if v_prov in (''nfce'', ''mercadopago'') and', 'if v_prov in (''nfce'', ''mercadopago'', ''infinitepay'') and');   -- só existe em api_integracoes_ligar (conferido no fim)
      d := replace(d, '  if v_prov = ''mercadopago'' and not exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online is not null) then',
        '  if v_prov = ''infinitepay'' and not exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online in (''pix'', ''credito'') and provedor_online = ''infinitepay'') then
    return _falha(''Escolha pelo menos uma forma (Pix ou cartão de crédito) para pagar pela InfinitePay antes de ligar.'');
  end if;
  if v_prov = ''mercadopago'' and not exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online is not null) then');
      execute d;
    end if;
  end loop;
  if position('provedor_online = ''infinitepay''' in pg_get_functiondef('public.api_integracoes_ligar(jsonb)'::regprocedure)) = 0
     or position('''infinitepay''' in pg_get_functiondef('public.api_integracoes_desligar(jsonb)'::regprocedure)) = 0
     or position('''infinitepay''' in pg_get_functiondef('public.api_integracoes_config(jsonb)'::regprocedure)) = 0 then
    raise exception '58: as telas de integração não ficaram preparadas para a InfinitePay';
  end if;

  select pg_get_functiondef('public.api_integracoes_status(jsonb)'::regprocedure) into d;
  if position('infinitepay' in d) = 0 then
    d := pg_temp.tb_trocar1(d, 'or (r.provedor = ''mercadopago'' and s.chave like ''mp\_%'')', 'or (r.provedor = ''mercadopago'' and s.chave like ''mp\_%'') or (r.provedor = ''infinitepay'' and s.chave like ''ip\_%'')');
    d := pg_temp.tb_trocar1(d, '''aceitaOnline'', f.aceita_online, ''tipoOnline'', f.tipo_online)', '''aceitaOnline'', f.aceita_online, ''tipoOnline'', f.tipo_online, ''provedorOnline'', f.provedor_online)');
    d := pg_temp.tb_trocar1(d, '         else ''{}''::jsonb end);', '         when r.provedor = ''infinitepay'' then (
           select jsonb_build_object(''pendenciasTeste'', to_jsonb(a.t), ''pendenciasProducao'', to_jsonb(a.p),
             ''podeLigarTeste'', coalesce(array_length(a.t, 1), 0) = 0, ''podeLigarProducao'', coalesce(array_length(a.p, 1), 0) = 0,
             ''formas'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', f.id, ''nome'', f.nome, ''aceitaOnline'', f.aceita_online, ''tipoOnline'', f.tipo_online, ''provedorOnline'', f.provedor_online) order by f.ordem), ''[]''::jsonb)
                          from formas_pagamento f where f.ativa and f.visivel_cardapio))
             from (select _integ_pendencias(''infinitepay'', ''homologacao'') as t, _integ_pendencias(''infinitepay'', ''producao'') as p) a)
         else ''{}''::jsonb end);');
    if position('''infinitepay'' then (' in d) = 0 then raise exception '58: ponto de troca não encontrado em api_integracoes_status'; end if;
    execute d;
  end if;

  select pg_get_functiondef('public.api_integracoes_salvar_segredo(jsonb)'::regprocedure) into d;
  if position('ip_handle' in d) = 0 then
    d := pg_temp.tb_trocar1(d, '''mp_access_token_producao'', ''mp_webhook_secret'')', '''mp_access_token_producao'', ''mp_webhook_secret'', ''ip_handle'', ''ip_chave_checkout'')');
    d := pg_temp.tb_trocar1(d, 'if length(v_valor) < 8 or', 'if v_chave = ''ip_handle'' then v_valor := lower(regexp_replace(v_valor, ''^[$@]+'', '''')); end if;
  if length(v_valor) < (case when v_chave = ''ip_handle'' then 3 else 8 end) or');
    if position('ip_handle' in d) = 0 then raise exception '58: ponto de troca não encontrado em api_integracoes_salvar_segredo'; end if;
    execute d;
  end if;
end $$;

-- pendências de decisão mostram o provedor (o reembolso da InfinitePay é registrado à mão)
do $$
declare d text;
begin
  select pg_get_functiondef('public.api_mp_pendencias_decisao(jsonb)'::regprocedure) into d;
  if position('''provedor'', x.provedor' in d) = 0 then
    d := pg_temp.tb_trocar1(d, '''pagamentoId'', x.id,', '''pagamentoId'', x.id, ''provedor'', x.provedor,');
    execute d;
  end if;
end $$;

-- ---------- forma × provedor (Admin) ----------
create or replace function public.api_pag_forma_provedor(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare f formas_pagamento%rowtype; v_prov text := lower(coalesce(p->>'provedor', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'senha', '') = '' or _exige_admin(p->>'senha') is null then return _falha('Senha de administrador incorreta. Nada foi mudado.'); end if;
  if v_prov not in ('mercadopago', 'infinitepay') then return _falha('Provedor inválido.'); end if;
  select * into f from formas_pagamento where id = _uuid(p->>'formaId');
  if not found then return _falha('Forma de pagamento não encontrada.'); end if;
  if v_prov = 'infinitepay' and (coalesce(f.tipo_online, '') = 'debito' or (f.tipo_online is null and translate(lower(f.nome), 'áàâãéêíóôõúç', 'aaaaeeiooouc') ~ 'debito')) then return _falha('A InfinitePay não faz débito pelo Checkout Integrado. Use o Mercado Pago ou "Só na entrega".'); end if;
  update formas_pagamento set provedor_online = v_prov where id = f.id;
  perform _auditar('Pagamento online: provedor da forma', f.nome || ' → ' || _pag_nome(v_prov), null);
  return api_integracoes_status('{}') || jsonb_build_object('message', f.nome || ': ' || _pag_nome(v_prov) || '.');
end $function$;
revoke all on function public.api_pag_forma_provedor(jsonb) from public, anon;
grant execute on function public.api_pag_forma_provedor(jsonb) to authenticated, service_role;

-- ---------- InfinitePay: preparar, credenciais, link, retorno ----------
create or replace function public.ip_credenciais() returns jsonb
 language sql stable security definer set search_path to 'public' as $function$
  select jsonb_build_object('ligado', c.ligado, 'modo', c.modo, 'config', c.config,
    'handle', (select valor from integracoes_segredos where chave = 'ip_handle'),
    'chave', (select valor from integracoes_segredos where chave = 'ip_chave_checkout'),
    'webhookSegredo', (select valor from integracoes_segredos where chave = 'ip_webhook_segredo'))
  from integracoes_config c where c.provedor = 'infinitepay'
$function$;
revoke all on function public.ip_credenciais() from public, anon, authenticated;
grant execute on function public.ip_credenciais() to service_role;

create or replace function public.ip_preparar_pagamento(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare r pedidos_reserva%rowtype; f formas_pagamento%rowtype; g pagamentos_online%rowtype; c integracoes_config%rowtype; v_novo uuid; v_email text; v_min int; v_ip jsonb;
begin
  select * into r from pedidos_reserva where id = _uuid(p->>'reservaId') for update;
  if not found or r.user_id is distinct from _uuid(p->>'userId') then return _falha('Pedido não encontrado.'); end if;
  if r.estado = 'confirmada' then return _falha('Este pedido já foi pago.'); end if;
  if r.estado <> 'ativa' or r.expira_em < now() then return _falha('O tempo deste pedido acabou. Faça o pedido de novo.'); end if;
  v_ip := public._ip_publico(r.user_id);
  if coalesce((v_ip->>'ligado')::boolean, false) is not true then return _falha('O pagamento pela InfinitePay não está disponível agora.'); end if;
  select * into f from formas_pagamento where id = r.forma_pagamento_id;
  if f.id is null or not f.aceita_online or f.tipo_online not in ('pix', 'credito') or f.provedor_online <> 'infinitepay' then return _falha('Forma de pagamento inválida.'); end if;
  if exists (select 1 from pagamentos_online where reserva_id = r.id and status = 'aprovado') then return _falha('Este pedido já foi pago.'); end if;
  if (select count(*) from pagamentos_online where reserva_id = r.id) >= 5 then return _falha('Muitas tentativas de pagamento. Faça o pedido de novo.'); end if;
  select * into c from integracoes_config where provedor = 'infinitepay';
  -- link ainda valendo para esta reserva: reaproveita (o cliente pode ter fechado a aba e voltado)
  select * into g from pagamentos_online where reserva_id = r.id and provedor = 'infinitepay' and status = 'aguardando' order by criado_em desc limit 1;
  if found and (g.ip_link is not null or c.modo <> 'producao') then
    return jsonb_build_object('ok', true, 'reaproveitar', true, 'pagamentoId', g.id, 'metodo', g.metodo, 'valor', g.valor, 'link', g.ip_link,
      'simulacao', g.mp_modo <> 'producao', 'expiraEm', r.expira_em);
  end if;
  update pagamentos_online set status = 'cancelado', status_detalhe = 'substituído por nova tentativa', atualizado_em = now() where reserva_id = r.id and status = 'aguardando';
  -- o link vale o tempo da InfinitePay (ajuste "Validade do link"): a reserva acompanha
  v_min := coalesce((v_ip->>'linkValidadeMin')::int, 30);
  update pedidos_reserva set expira_em = greatest(expira_em, now() + make_interval(mins => v_min)), atualizado_em = now() where id = r.id returning * into r;
  insert into pagamentos_online (reserva_id, user_id, metodo, mp_modo, valor, provedor)
  values (r.id, r.user_id, f.tipo_online, case when c.modo = 'producao' then 'producao' else 'homologacao' end, r.valor_total, 'infinitepay') returning id into v_novo;
  select email into v_email from auth.users where id = r.user_id;
  return jsonb_build_object('ok', true, 'pagamentoId', v_novo, 'metodo', f.tipo_online, 'simulacao', c.modo <> 'producao', 'valor', r.valor_total, 'expiraEm', r.expira_em,
    'email', v_email, 'nome', r.cliente_nome, 'telefone', r.telefone,
    'quantidade', (select coalesce(sum(_num(e->>'quantidade', 1)), 1) from jsonb_array_elements(r.itens) e));
end $function$;
revoke all on function public.ip_preparar_pagamento(jsonb) from public, anon, authenticated;
grant execute on function public.ip_preparar_pagamento(jsonb) to service_role;

-- guarda o link criado e, na volta do checkout / no aviso, os dados da transação (para a consulta payment_check)
create or replace function public.ip_registrar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare g pagamentos_online%rowtype; v_tr text;
begin
  select * into g from pagamentos_online where id = _uuid(p->>'pagamentoId') and provedor = 'infinitepay' for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'Pagamento não encontrado.'); end if;
  v_tr := nullif(left(regexp_replace(coalesce(p->>'transacao', ''), '[^A-Za-z0-9_-]', '', 'g'), 80), '');
  if v_tr is not null and exists (select 1 from pagamentos_online where ip_transacao = v_tr and id <> g.id) then
    perform _integ_log('infinitepay', 'erro', 'Transação ' || v_tr || ' já usada em outro pagamento: ignorada no pagamento ' || left(g.id::text, 8));
    return jsonb_build_object('ok', false, 'message', 'Transação já usada em outro pagamento.');
  end if;
  update pagamentos_online set
    ip_link = coalesce(nullif(left(p->>'link', 500), ''), ip_link),
    ip_slug = coalesce(nullif(left(regexp_replace(coalesce(p->>'slug', ''), '[^A-Za-z0-9_-]', '', 'g'), 80), ''), ip_slug),
    ip_transacao = coalesce(v_tr, ip_transacao),
    ip_recibo = coalesce(case when p->>'recibo' ~ '^https://' then left(p->>'recibo', 500) end, ip_recibo),
    ip_metodo_pago = coalesce(nullif(left(p->>'metodoPago', 30), ''), ip_metodo_pago),
    ip_conferido_em = case when (p->>'conferido')::boolean then now() else ip_conferido_em end,
    atualizado_em = now()
   where id = g.id;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.ip_registrar(jsonb) from public, anon, authenticated;
grant execute on function public.ip_registrar(jsonb) to service_role;

create or replace function public.ip_pagamento(p_id uuid) returns jsonb
 language sql stable security definer set search_path to 'public' as $function$
  select to_jsonb(g) - 'pix_qr_base64' from pagamentos_online g where g.id = p_id and g.provedor = 'infinitepay'
$function$;
revoke all on function public.ip_pagamento(uuid) from public, anon, authenticated;
grant execute on function public.ip_pagamento(uuid) to service_role;

-- ---------- simulação: Pagar / Recusar / Expirar (dono da reserva, só no modo SIMULAÇÃO; ou Admin) ----------
create or replace function public.api_ip_simular(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare g pagamentos_online%rowtype; c integracoes_config%rowtype; v_acao text := lower(coalesce(p->>'acao', '')); v_res jsonb; v_email text;
begin
  select * into g from pagamentos_online
   where provedor = 'infinitepay' and (id = _uuid(p->>'pagamentoId') or (reserva_id = _uuid(p->>'reservaId') and status = 'aguardando'))
   order by criado_em desc limit 1;
  if not found then return _falha('Pagamento não encontrado.'); end if;
  if g.user_id is distinct from auth.uid() and not tem_nivel('Admin') then return _negado(); end if;
  if g.mp_modo = 'producao' then return _falha('Simulação só funciona com a InfinitePay em SIMULAÇÃO.'); end if;
  select * into c from integracoes_config where provedor = 'infinitepay';
  if not coalesce(c.ligado, false) or c.modo = 'producao' then
    return _falha('A simulação da InfinitePay não está mais ligada. Este pagamento não vale; escolha outra forma.');
  end if;
  -- "Pagar" simulado cria pedido de verdade: só para quem está na lista de e-mails de teste (ou Admin), mesmo com "mostrar a todos"
  if v_acao = 'pagar' and not tem_nivel('Admin') then
    select lower(email) into v_email from auth.users where id = auth.uid();
    if v_email is null or jsonb_typeof(c.config->'emailsTeste') <> 'array'
       or not exists (select 1 from jsonb_array_elements_text(c.config->'emailsTeste') x where lower(btrim(x)) = v_email) then
      return _falha('Pagamento simulado só para os e-mails de teste cadastrados pelo restaurante. Escolha outra forma de pagamento.');
    end if;
  end if;
  if g.status <> 'aguardando' then return _falha('Este pagamento não está mais aguardando.'); end if;
  if v_acao = 'pagar' then
    perform public.ip_registrar(jsonb_build_object('pagamentoId', g.id, 'metodoPago', case when g.metodo = 'pix' then 'pix' else 'credit_card' end, 'conferido', true));
    v_res := public.mp_aplicar_status(jsonb_build_object('pagamentoId', g.id, 'status', 'aprovado', 'statusDetalhe', 'simulação: aprovado', 'valorPago', g.valor));
    -- marca a venda como TESTE (aparece na tela e na comanda)
    update vendas set observacoes_entrega = left(coalesce(nullif(observacoes_entrega, '') || ' · ', '') || 'TESTE: pago na SIMULAÇÃO da InfinitePay (nenhum dinheiro recebido)', 500)
     where id = (select venda_id from pagamentos_online where id = g.id) and coalesce(observacoes_entrega, '') not like '%SIMULAÇÃO da InfinitePay%';
  elsif v_acao = 'recusar' then
    v_res := public.mp_aplicar_status(jsonb_build_object('pagamentoId', g.id, 'status', 'recusado', 'statusDetalhe', 'simulação: recusado'));
  elsif v_acao = 'expirar' then
    v_res := public.mp_aplicar_status(jsonb_build_object('pagamentoId', g.id, 'status', 'expirado', 'statusDetalhe', 'simulação: link vencido'));
    if exists (select 1 from pedidos_reserva where id = g.reserva_id and estado = 'ativa') then perform _mp_soltar(g.reserva_id, 'expirada', 'Link de pagamento vencido (simulação)'); end if;
  else return _falha('Ação inválida.'); end if;
  perform _integ_log('infinitepay', 'info', 'Simulação: ' || v_acao || ' · pagamento ' || left(g.id::text, 8));
  return jsonb_build_object('ok', true, 'resultado', v_res);
end $function$;
revoke all on function public.api_ip_simular(jsonb) from public, anon;
grant execute on function public.api_ip_simular(jsonb) to authenticated, service_role;

-- ---------- reembolso manual (feito no app da InfinitePay) ----------
create or replace function public.api_ip_reembolso(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare g pagamentos_online%rowtype; v_uid text; v_val numeric := round(_num(p->>'valor', 0), 2); v_motivo text := btrim(coalesce(p->>'motivo', '')); v_total numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_uid := _exige_admin(p->>'senha');
  if coalesce(p->>'senha', '') = '' or v_uid is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into g from pagamentos_online where id = _uuid(p->>'pagamentoId') and provedor = 'infinitepay' for update;
  if not found then return _falha('Pagamento da InfinitePay não encontrado.'); end if;
  if g.status not in ('aprovado', 'reembolso_parcial') then return _falha('Só dá para registrar reembolso de pagamento aprovado.'); end if;
  if v_val <= 0 then return _falha('Informe o valor devolvido.'); end if;
  if length(v_motivo) < 3 then return _falha('Escreva o motivo do reembolso.'); end if;
  v_total := round(coalesce(g.valor_reembolsado, 0) + v_val, 2);
  if v_total > g.valor + 0.009 then return _falha('O total devolvido (R$ ' || _dinheiro(v_total) || ') passaria do valor pago (R$ ' || _dinheiro(g.valor) || ').'); end if;
  insert into pagamentos_reembolsos_manuais (pagamento_id, valor, motivo, registrado_por) values (g.id, v_val, left(v_motivo, 300), auth.uid());
  perform public.mp_aplicar_status(jsonb_build_object('pagamentoId', g.id, 'status', case when v_total >= g.valor - 0.009 then 'reembolsado' else 'reembolso_parcial' end, 'valorReembolsado', v_total));
  perform _auditar('InfinitePay: reembolso registrado', 'Pagamento ' || left(g.id::text, 8) || ' · R$ ' || _dinheiro(v_val) || ' (total devolvido R$ ' || _dinheiro(v_total) || ') · ' || left(v_motivo, 120), null);
  if g.mp_modo = 'producao' then
    update integracoes_config set checklist = coalesce(checklist, '{}'::jsonb) || '{"reembolso": true}'::jsonb where provedor = 'infinitepay';
  end if;
  return jsonb_build_object('ok', true, 'message', 'Reembolso registrado: R$ ' || _dinheiro(v_val) || '.');
end $function$;
revoke all on function public.api_ip_reembolso(jsonb) from public, anon;
grant execute on function public.api_ip_reembolso(jsonb) to authenticated, service_role;

-- segredo do aviso (vai no endereço do aviso de cada cobrança). Gerado pelo sistema; trocar invalida os avisos de links antigos.
create or replace function public.api_ip_gerar_segredo(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare v_uid text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_uid := _exige_admin(p->>'senha');
  if coalesce(p->>'senha', '') = '' or v_uid is null then return _falha('Senha de administrador incorreta.'); end if;
  insert into integracoes_segredos (chave, valor, atualizado_em) values ('ip_webhook_segredo', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('InfinitePay: segredo do aviso gerado', '', null);
  return api_integracoes_status('{}') || jsonb_build_object('message', 'Segredo do aviso gerado.');
end $function$;
revoke all on function public.api_ip_gerar_segredo(jsonb) from public, anon;
grant execute on function public.api_ip_gerar_segredo(jsonb) to authenticated, service_role;

-- lista do cartão da InfinitePay (teste guiado e reembolsos)
create or replace function public.api_ip_pagamentos(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'em', to_char(x.criado_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), 'modo', x.mp_modo, 'metodo', x.metodo,
                'pagoCom', x.ip_metodo_pago, 'status', x.status, 'valor', x.valor, 'reembolsado', coalesce(x.valor_reembolsado, 0), 'recibo', x.ip_recibo,
                'aDecidir', (x.decisao_pendente and x.decisao is null), 'detalhe', left(coalesce(nullif(x.erro, ''), x.status_detalhe, ''), 120),
                'reembolsos', (select coalesce(jsonb_agg(jsonb_build_object('valor', m.valor, 'motivo', m.motivo, 'em', to_char(m.registrado_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
                                 'por', (select login from usuarios u where u.id = m.registrado_por)) order by m.id), '[]'::jsonb) from pagamentos_reembolsos_manuais m where m.pagamento_id = x.id)) order by x.criado_em desc), '[]'::jsonb)
              from (select * from pagamentos_online where provedor = 'infinitepay' order by criado_em desc limit 20) x),
    'simAprovado', exists (select 1 from pagamentos_online where provedor = 'infinitepay' and mp_modo = 'homologacao' and status in ('aprovado', 'reembolso_parcial', 'reembolsado')),
    'simRecusado', exists (select 1 from pagamentos_online where provedor = 'infinitepay' and mp_modo = 'homologacao' and status = 'recusado'),
    'simExpirado', exists (select 1 from pagamentos_online where provedor = 'infinitepay' and mp_modo = 'homologacao' and status = 'expirado'),
    'realPix', exists (select 1 from pagamentos_online where provedor = 'infinitepay' and mp_modo = 'producao' and metodo = 'pix' and status in ('aprovado', 'reembolso_parcial', 'reembolsado')),
    'realCredito', exists (select 1 from pagamentos_online where provedor = 'infinitepay' and mp_modo = 'producao' and metodo = 'credito' and status in ('aprovado', 'reembolso_parcial', 'reembolsado')));
end $function$;
revoke all on function public.api_ip_pagamentos(jsonb) from public, anon;
grant execute on function public.api_ip_pagamentos(jsonb) to authenticated, service_role;

-- ajustes do cartão da InfinitePay (validade do link, e-mails da simulação, mostrar a todos) e o sinal "ligada" para o app
do $$
declare d text;
begin
  select pg_get_functiondef('public.api_integracoes_config(jsonb)'::regprocedure) into d;
  if position('linkValidadeMin' in d) = 0 then
    if position('elsif v_prov = ''mercadopago'' and v_chave = ''testeNoCardapio'' then' in d) = 0 then raise exception '58: ponto de troca não encontrado em api_integracoes_config'; end if;
    d := pg_temp.tb_trocar1(d, 'elsif v_prov = ''mercadopago'' and v_chave = ''testeNoCardapio'' then',
      'elsif v_prov = ''infinitepay'' and v_chave = ''linkValidadeMin'' then
      if coalesce(v_cfg->>v_chave, '''') !~ ''^[0-9]{1,3}$'' or (v_cfg->>v_chave)::int not between 10 and 120 then return _falha(''A validade do link deve ficar entre 10 e 120 minutos.''); end if;
      v_novo := v_novo || jsonb_build_object(v_chave, (v_cfg->>v_chave)::int);
    elsif v_prov = ''infinitepay'' and v_chave = ''producaoSoTeste'' then v_novo := v_novo || jsonb_build_object(v_chave, coalesce((v_cfg->>v_chave)::boolean, false));
    elsif v_prov in (''mercadopago'', ''infinitepay'') and v_chave = ''testeNoCardapio'' then');
    d := pg_temp.tb_trocar1(d, 'elsif v_prov = ''mercadopago'' and v_chave = ''emailsTeste''', 'elsif v_prov in (''mercadopago'', ''infinitepay'') and v_chave = ''emailsTeste''');
    execute d;
  end if;
  select pg_get_functiondef('public.api_integracoes_flags(jsonb)'::regprocedure) into d;
  if position('infinitepay' in d) = 0 then
    d := pg_temp.tb_trocar1(d, '''mercadopago'', _integracao_ligada(''mercadopago''),', '''mercadopago'', _integracao_ligada(''mercadopago''), ''infinitepay'', _integracao_ligada(''infinitepay''),');
    execute d;
  end if;
end $$;


-- ---------- conferência de pagamentos que ficaram sem resposta (o cliente pagou e fechou a página, o aviso não chegou) ----------
-- A cada 10 minutos a função ip-status (modo serviço) consulta na InfinitePay os pagamentos das últimas 48 h que têm os dados da transação.
-- Pago depois de a reserva vencer entra pela mesma porta de sempre: vira "Pagamento que precisa de decisão".
create or replace function public.ip_pendentes_conferir() returns jsonb
 language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'slug', g.ip_slug, 'transacao', g.ip_transacao, 'valor', g.valor) order by g.criado_em), '[]'::jsonb)
  from (select * from pagamentos_online
         where provedor = 'infinitepay' and mp_modo = 'producao' and status in ('aguardando', 'expirado', 'cancelado')
           and ip_slug is not null and ip_transacao is not null and criado_em > now() - interval '48 hours'
           and (ip_conferido_em is null or ip_conferido_em < now() - interval '9 minutes')
         order by criado_em limit 20) g
$function$;
revoke all on function public.ip_pendentes_conferir() from public, anon, authenticated;
grant execute on function public.ip_pendentes_conferir() to service_role;
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'ip-conferir-pendentes') then
    perform cron.schedule('ip-conferir-pendentes', '*/10 * * * *',
      $c$ select public.chamar_edge('ip-status', '{"servico":true}'::jsonb) where exists (select 1 from public.integracoes_config where provedor = 'infinitepay' and ligado and modo = 'producao'); $c$);
  end if;
end $$;


-- ======================================================================
-- 59-ajuda-assistente-115.sql
-- ======================================================================
-- 59 - Assistente (versão 1.15): verbetes novos para as novidades de 25/10/2026 (inclui financeiro do iFood e senha sempre). Pode rodar de novo (atualiza o texto).
-- Desfazer: delete from public.ai_ajuda where slug like 'man-115-%';
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-115-01-erros-visiveis$t$,$t$Erros do sistema: nada falha calado$t$,$t$erro falha travou deu errado aviso vermelho sem conexão servidor erros do sistema registro bug problema tela branca botão não funciona$t$,
$t$Quando algo dá errado aparece um aviso vermelho dizendo o que aconteceu e o que fazer (por 15 segundos; a tela rola até ele). No carrinho do cardápio o campo que falta fica vermelho.
Para ver tudo o que deu errado: bolinha colorida do topo → "Conexão e servidores" → "🐞 Erros do sistema". Filtre por cardápio (clientes) ou equipe e pelo período. Depois de corrigir, toque em "✓ Resolvido".$t$,
ARRAY['Admin','Operador'],true,'secao',140,$t$Vermelho = erro de programa; amarelo = falha que apareceu na tela (ex.: sem internet). Do cliente não é guardado nome, telefone nem IP.$t$),
($t$man-115-02-ifood-dia-a-dia$t$,$t$iFood no dia a dia: vinheta, código localizador e clientes do iFood$t$,$t$ifood vinheta som pedido novo localizador código telefone 0800 ligar cliente ifood cadastro clientes selo$t$,
$t$Pedido do iFood esperando aceite toca a vinheta do iFood (Admin, Operador e Cozinha) de 30 em 30 segundos, até alguém aceitar, recusar ou o iFood cancelar (no máximo 10 minutos); a faixa vermelha tem "Ver" e "🔇 Silenciar". O telefone do iFood é 0800: para falar com o cliente, ligue e digite o CÓDIGO LOCALIZADOR que aparece na tela do pedido, na comanda e na mensagem do entregador (com a validade).
O cliente do iFood é cadastrado sozinho pelo ID do iFood (nunca pelo 0800), com selo iFood na lista de clientes.$t$,
ARRAY['Admin','Operador','Garçom','Cozinha'],true,'secao',141,$t$Pedido sem código localizador (retirada, teste): use o chat do pedido no portal do iFood.$t$),
($t$man-115-03-ifood-itens$t$,$t$iFood: item sem produto (pré-cadastro) e excluir itens de teste$t$,$t$ifood item sem ligação pré-cadastro produto novo criar produto item teste homologação excluir apagar alerta item$t$,
$t$Integrações → iFood → "Itens do iFood". Item do iFood que não existe no sistema: "➕ Cadastrar no sistema" cria o produto já ligado, como RASCUNHO (fora do cardápio); complete em Produtos (marca "📝 pré-cadastro iFood") e ative. Itens de TESTE: "🗑️ Excluir de vez" (pede a senha) tira da lista e o alerta de "item sem ligação" cai na hora. "🧪 Marcar um pedido do iFood como teste" tira o pedido dos alertas e relatórios do iFood (a venda continua no caixa).$t$,
ARRAY['Admin'],true,'secao',142,$t$$t$),
($t$man-115-04-ifood-cancelar-codigos$t$,$t$iFood: motivo oficial ao cancelar e códigos do entregador e de entrega$t$,$t$ifood cancelar motivo oficial lista dourada código entregador coleta código entrega precisa de um código validar$t$,
$t$Cancelar pedido do iFood: no "Cancelar lançamento" aparece a lista com borda dourada com os motivos OFICIAIS do iFood; escolha um (obrigatório quando a lista aparece). Se o iFood não devolver a lista, dá para cancelar assim mesmo.
Códigos: quando aparecer "🔐 O iFood precisa de um código" no topo de Pedidos ou Entregas, peça o código ao entregador do iFood (coleta) ou ao cliente (entrega), digite e toque em Enviar. A resposta chega em até 30 segundos; se o iFood recusar, aparece em vermelho.$t$,
ARRAY['Admin','Operador','Garçom','Cozinha','Entregador'],true,'secao',143,$t$$t$),
($t$man-115-05-ifood-modulos$t$,$t$iFood: estado dos módulos (403, 401, homologação)$t$,$t$ifood módulo 403 401 forbidden não liberado homologação permissões estado dos módulos merchant catálogo financeiro avaliações$t$,
$t$Integrações → iFood → "🩺 Estado dos módulos": cada parte do iFood (pedidos, eventos, loja, cardápio, avaliações, financeiro) com 🟢 OK ou 🔴 recusado. "Não liberado para o app (403)": o iFood ainda não liberou o módulo; peça no Portal do Desenvolvedor (Permissões / homologação). "Credenciais recusadas (401)": confira Client ID e Client Secret. Também mostra se a loja configurada pertence ao app.
A comanda do iFood mostra bandeira do cartão (pago no app ou levar maquininha), quem pagou o cupom (iFood ou loja) e retirada agendada.$t$,
ARRAY['Admin'],true,'secao',144,$t$Quando um módulo passa a ser recusado chega aviso no celular do Admin (no máximo 1 a cada 6 h por módulo).$t$),
($t$man-115-06-cupom-excluir$t$,$t$Excluir cupom$t$,$t$cupom excluir apagar remover cupom cadastrado lixeira$t$,
$t$Promoções e cupons → cupom → "🗑️ Excluir" (pede a senha). Cupom nunca usado é apagado de vez. Cupom já usado é ARQUIVADO: some da lista, do cardápio e da conta dos clientes, mas os pedidos antigos continuam com o desconto certo, e o código fica livre. "🗑️ Cupons excluídos" (no fim da lista) permite Restaurar (volta desativado). Cupons automáticos não se excluem: use Desligar.$t$,
ARRAY['Admin'],true,'secao',145,$t$$t$),
($t$man-115-07-cardapio-funil-mapa$t$,$t$Cardápio hoje: funil e mapa de onde vêm os acessos$t$,$t$cardápio hoje funil visitas abriram item carrinho finalizar pedido mapa localização de onde vêm clientes conversão$t$,
$t$No Início, toque no quadro "Cardápio hoje" para ver, desde a abertura do caixa (ou nas últimas 24 h com o caixa fechado): quantos entraram no cardápio, abriram um item, puseram no carrinho, abriram o finalizar e enviaram o pedido, e onde a maioria parou. O mapa mostra de onde estão acessando (aproximado, ~500 m) e os pedidos com local de entrega.$t$,
ARRAY['Admin','Operador'],true,'secao',146,$t$A localização é apagada ao fechar o caixa e sempre depois de 24 horas. Aparelhos da equipe não contam.$t$),
($t$man-115-08-fotos-sem-uso$t$,$t$Limpar do Google Drive as fotos que o sistema não usa$t$,$t$fotos sem uso drive espaço limpar duplicadas lixeira restaurar desfazer$t$,
$t$Administrador → Sistema → Backup e espaço → card Google Drive → "🔍 Analisar fotos sem uso". Desmarque o que quiser manter e mande para a lixeira do Drive (pede a senha). "↩ Desfazer a última limpeza" tira da lixeira. O espaço volta de verdade quando você esvazia a lixeira no Google Drive.$t$,
ARRAY['Admin'],true,'secao',147,$t$Nunca entram: fotos em uso, do histórico, do Espelho da contingência, com menos de 7 dias, comprovantes e fotos do ponto.$t$),
($t$man-115-09-armazenamento$t$,$t$Armazenamento: banco, Storage e planilha (quanto falta para encher)$t$,$t$armazenamento storage espaço cheio banco planilha células arquivo arquivar compactação vacuum previsão encher quanto tempo liberou$t$,
$t$Administrador → Sistema → "Armazenamento". Três barras (banco, Storage e planilha) com quanto cresce por dia e quanto tempo falta para chegar a 95%. Pedidos e caixas antigos saem do banco para o Storage (comprimidos e conferidos). Se o Storage chegar a 95%, o arquivo mais antigo vai para a planilha, num arquivo por ano ("Arquivo AAAA"). Às 05:30 a compactação devolve o espaço; às 06:00 o sistema mede quanto liberou.
"🧪 Testar o caminho agora" faz uma ida e volta com dados de teste. Salvar o limite do Storage, testar e mandar arquivo para a planilha pedem a senha.$t$,
ARRAY['Admin'],true,'secao',148,$t$Os relatórios de meses antigos juntam tudo sozinhos (banco + Storage + planilha). A compactação só refaz as tabelas que cabem no espaço livre; se alguma não couber aparece aviso amarelo em "Compactação" e no celular (arquive mais ou aumente o plano).$t$),
($t$man-115-10-infinitepay$t$,$t$InfinitePay: pagamento online no checkout, junto com o Mercado Pago$t$,$t$infinitepay infinite tag checkout pagamento online pix crédito link simulação reembolso registrar provedor quem recebe mercado pago$t$,
$t$Integrações e contas → InfinitePay. O cliente sai do cardápio para pagar no site seguro da InfinitePay (Pix ou crédito; débito não existe lá) e volta. Para cada forma escolha "Só na entrega", "Online · Mercado Pago" ou "Online · InfinitePay" (dá para usar os dois juntos).
Chaves: InfiniteTag (sem o $) e, só se a conta mostrar, a chave do Checkout; o "Segredo do aviso" é gerado pelo sistema. Comece em SIMULAÇÃO (botões Pagar, Recusar e Expirar no cardápio, sem cobrar). O pedido só é aprovado depois de o sistema conferir com a InfinitePay. Reembolso: devolva no app da InfinitePay e toque em "Registrar reembolso" (valor, motivo e senha).$t$,
ARRAY['Admin'],true,'secao',149,$t$Vem DESLIGADA. Enquanto não houver teste real de Pix e crédito, o cartão avisa "Integração ainda não validada com conta real".$t$),
($t$man-115-11-jogos$t$,$t$Mini jogos do cliente no acompanhamento do pedido$t$,$t$jogos jogar enquanto espera mini jogo burger memória cobra chuva cliente acompanhamento$t$,
$t$No acompanhamento do pedido (cardápio), enquanto o pedido não foi entregue, o cliente vê "🎮 Jogar enquanto espera": Monte o Burger, Chuva de Ingredientes, Memória e Cobra Smash, com as fotos do cardápio. A barra de cima mostra o pedido; quando ele muda de etapa, o jogo pausa e avisa. O som começa desligado e o recorde fica só no aparelho do cliente.$t$,
ARRAY['Admin','Operador'],true,'secao',150,$t$$t$),
($t$man-115-12-ver-cardapio$t$,$t$Ver o cardápio sem sair da área da equipe$t$,$t$ver cardápio sem deslogar abrir cardápio cliente voltar área funcionários conferir preço$t$,
$t$No topo da área de funcionários, toque em "🛒 Cardápio": o cardápio aparece como o cliente vê e você continua logado. A faixa "Você está vendo como cliente" tem "↩ Voltar à área de funcionários" (volta para a mesma tela, sem senha). A busca de pedidos e a vinheta do iFood continuam funcionando; se chegar pedido, a faixa mostra "🔔 pedido novo!".$t$,
ARRAY['Admin','Operador','Garçom','Cozinha','Entregador'],true,'secao',151,$t$$t$),
($t$man-115-13-ifood-financeiro$t$,$t$iFood: vendas, comissões, repasses, antecipações e arquivo mensal$t$,$t$ifood financeiro repasse quanto vou receber liquidação comissão taxa antecipação d+1 d+7 boleto recebíveis conciliação arquivo csv lançamentos semana confere diferença 403 homologação financeiro$t$,
$t$Administrador → Dinheiro → "iFood: vendas e repasses" (ou botão "💰 Vendas e repasses" no cartão do iFood). Abas: Semana (confere lançamentos COM impacto × repasse do iFood), Vendas (bruto, comissão, taxas, promoções e líquido de cada pedido), Lançamentos (créditos e débitos, com e sem impacto), Repasses (títulos, status, data e banco), Antecipações (D+1/D+7: original, taxa, recebido) e Arquivo mensal (gera o CSV oficial; leva até 30 min; o mesmo mês só de novo após 6 h).
Busca sozinha a cada 6 h; para outro período escolha as datas e toque em "🔄 Buscar no iFood" (até 3 meses). Só mostra: não muda vendas nem caixa.$t$,
ARRAY['Admin'],true,'secao',152,$t$Antes da homologação do módulo Financeiro (chamado separado no Portal do Desenvolvedor, conta CNPJ) aparece "🔒 403" e a tela fica vazia. Diferença numa semana: busque de novo o período; cancelamentos podem cair em outra semana.$t$),
($t$man-115-14-senha-sempre$t$,$t$Senha sempre nas ações sensíveis (inclusive do Admin)$t$,$t$senha pedir senha cancelar excluir apagar estornar desconto editar venda ajuste admin confirmar digite a sua senha$t$,
$t$Cancelar, recusar, excluir, dar desconto, editar venda, estornar nota de compra e registrar ou cancelar ajuste pós-venda pedem SEMPRE a senha, inclusive do Administrador (Admin digita a própria; outros perfis digitam a de um Administrador). Também: excluir produto, combo, adicional, categoria, ingrediente, mesa, perfil fiscal, item do iFood, apagar rosto do ponto, cancelar evento ou pedido de compra e desfazer preço do iFood.$t$,
ARRAY['Admin','Operador'],true,'secao',153,$t$Fechou a janela sem digitar: nada é feito. "Digite a sua senha para confirmar" = veio sem senha (tela antiga): atualize o app e faça de novo.$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();


-- ======================================================================
-- 60-correcoes-auditoria.sql
-- ======================================================================
-- 60 · Correções da auditoria final da versão 1.15 (25/10/2026). Pode rodar de novo sem erro.
-- "Conferir a senha" com a senha VAZIA respondia ok para o Admin (o _exige_admin deixa o Admin passar sem senha em funções antigas).
-- Desde 20/10 toda ação sensível pede a senha, inclusive do Admin: a conferência agora recusa senha vazia.
create or replace function public.api_verificar_senha_admin(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
begin
  if auth_nivel() is null then return _negado(); end if;
  if coalesce(btrim(p->>'senha'), '') = '' then return jsonb_build_object('ok', false, 'message', 'Digite a senha.'); end if;
  return jsonb_build_object('ok', _exige_admin(p->>'senha') is not null);
end $function$;


-- ======================================================================
-- 61-senha-sempre-e-compactacao.sql
-- ======================================================================
-- 61 · Senha SEMPRE (inclusive do Admin) nas ações sensíveis + conferência de espaço antes da compactação das 05:30.
-- Versão 1.15 (25/10/2026). Pode rodar de novo sem erro (cada troca confere se já foi feita).
-- Se uma função ao vivo estiver diferente do esperado, o arquivo PARA com erro e nada fica pela metade.
--
-- 1) Funções antigas aceitavam a ação do Admin SEM senha quando a tela não mandava senha (o _exige_admin deixa o Admin passar
--    com senha vazia). Agora a senha vazia é recusada nelas; a tela sempre pede a senha (combinado de 20/10/2026).
-- 2) Exclusões e cancelamentos que não conferiam senha no banco passam a conferir (a tela também passa a pedir).
-- 3) A compactação (VACUUM FULL) precisa de espaço livre do tamanho da tabela enquanto roda: agora só entram na compactação
--    as tabelas que cabem no espaço livre; as outras ficam de fora (a limpeza automática do banco continua) e o Admin é avisado.

create or replace function pg_temp.tb_trocar1(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception '61: trecho esperado apareceu % vez(es): %', n, left(a, 90); end if;
  return replace(d, a, b);
end $f$;

-- ---------- ajuda: senha obrigatória (vazia = recusa; errada = recusa; o _exige_admin conta as tentativas) ----------
create or replace function public._exige_senha_sempre(p_senha text) returns text
 language plpgsql security definer set search_path to 'public' as $function$
begin
  if coalesce(btrim(p_senha), '') = '' then return null; end if;
  return _exige_admin(p_senha);
end $function$;
revoke all on function public._exige_senha_sempre(text) from public, anon, authenticated;

-- ---------- 1) funções que deixavam o Admin passar com senha vazia ----------
do $do$
declare f text; d text;
  marca constant text := '/*61:senha-sempre*/';
  antes constant text := 'v_aut := _exige_admin(p->>''senhaAdminConfirmacao'');';
  depois constant text := marca || ' if coalesce(btrim(p->>''senhaAdminConfirmacao''), '''') = '''' then return _falha(''Digite a sua senha para confirmar (a senha é pedida sempre, inclusive para o Admin).''); end if;
  v_aut := _exige_admin(p->>''senhaAdminConfirmacao'');';
begin
  foreach f in array array['_editar_venda_base', 'api_cancelar_ajuste_pos_venda', 'api_cancelar_despesa', 'api_cancelar_movimento_evento',
                           'api_cancelar_pagamento_funcionario', 'api_cancelar_venda', 'api_estornar_compra', 'api_excluir_cliente',
                           'api_iniciar_venda', 'api_registrar_ajuste_pos_venda'] loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = f and pg_get_function_identity_arguments(p.oid) = 'p jsonb';
    if d is null then raise exception '61: função % não encontrada', f; end if;
    if position(marca in d) > 0 then continue; end if;          -- já aplicado
    execute pg_temp.tb_trocar1(d, antes, depois);
  end loop;
end $do$;

-- ---------- 2) exclusões/cancelamentos que não conferiam a senha no banco ----------
do $do$
declare f text; d text; pos int;
  marca constant text := '/*61:senha-sempre*/';
  ins constant text := E'\n  ' || marca || ' if coalesce(btrim(p->>''senhaAdminConfirmacao''), '''') = '''' then return _falha(''Digite a sua senha para confirmar (a senha é pedida sempre, inclusive para o Admin).''); end if;'
                    || E'\n  if _exige_admin(p->>''senhaAdminConfirmacao'') is null then return _falha(''Senha de administrador incorreta. Nada foi mudado.''); end if;';
begin
  foreach f in array array['api_cancelar_compra', 'api_cancelar_evento', 'api_excluir_adicional', 'api_excluir_categoria', 'api_excluir_combo',
                           'api_excluir_ingrediente', 'api_excluir_mesa', 'api_excluir_produto', 'api_fiscal_perfil_excluir',
                           'api_ifood_cat_excluir', 'api_ifood_precos_desfazer', 'api_ponto_rosto_apagar'] loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
     where n.nspname = 'public' and p.proname = f and pg_get_function_identity_arguments(p.oid) = 'p jsonb' and l.lanname = 'plpgsql';
    if d is null then raise exception '61: função % não encontrada (ou não é plpgsql)', f; end if;
    if position(marca in d) > 0 then continue; end if;
    -- primeiro "begin" do corpo (logo depois do declare)
    pos := position(E'\nbegin' in lower(substr(d, position('$function$' in d))));
    if pos = 0 then raise exception '61: % sem "begin" no início de linha', f; end if;
    pos := position('$function$' in d) - 1 + pos + length(E'\nbegin');
    execute substr(d, 1, pos - 1) || ins || substr(d, pos);
  end loop;
end $do$;

-- ---------- 3) compactação: só o que cabe no espaço livre ----------
alter table public.backup_config add column if not exists compactacao_aviso text;
alter table public.backup_config add column if not exists compactacao_aviso_em timestamptz;

create or replace function public._compactar_agendar()
 returns void language plpgsql security definer set search_path to 'public', 'cron' as $function$
declare r record; v_pendente boolean := false; v_quando timestamptz; v_base timestamp;
  v_livre numeric; v_cabe text[] := '{}'; v_fora text[] := '{}'; v_t text; v_tam numeric;
  v_tabelas constant text[] := array['vendas', 'itens_venda', 'pagamentos_venda', 'caixa_sessoes', 'sangrias', 'vendas_resumo_arquivo', 'arquivo_historico'];
begin
  for r in select jobname from cron.job where jobname like 'compactar-%' loop
    if coalesce(nullif(substring(r.jobname from 'compactar-(\d+)'), '')::bigint, 0) < extract(epoch from now() - interval '15 minutes') then
      perform cron.unschedule(r.jobname);                        -- já rodou (ou ficou para trás): sai da lista
    else v_pendente := true; end if;
  end loop;
  if v_pendente then return; end if;
  -- espaço livre = limite do plano − tamanho atual do banco. A compactação refaz UMA tabela de cada vez:
  -- precisa de espaço livre do tamanho dela (com folga de 20%). Tabela maior que isso fica de fora desta vez.
  v_livre := _limite_banco_mb() * 1048576 - pg_database_size(current_database());
  foreach v_t in array v_tabelas loop
    if to_regclass('public.' || v_t) is null then continue; end if;
    v_tam := pg_total_relation_size(('public.' || v_t)::regclass);
    if v_tam * 1.2 < v_livre then v_cabe := v_cabe || ('public.' || v_t);
    else v_fora := v_fora || (v_t || ' (' || round(v_tam / 1048576.0, 1) || ' MB)'); end if;
  end loop;
  if cardinality(v_fora) > 0 then
    update backup_config set compactacao_aviso = 'Espaço livre (' || round(greatest(v_livre, 0) / 1048576.0, 1) || ' MB) não dá para compactar: '
        || array_to_string(v_fora, ', ') || '. Essas ficam de fora (a limpeza automática do banco continua). Para liberar: arquive mais pedidos antigos '
        || '(Armazenamento) ou aumente o plano do Supabase.', compactacao_aviso_em = now() where id;
    begin
      perform api_push_admins_servico('⚠️ Compactação incompleta', 'Falta espaço livre para compactar ' || array_to_string(v_fora, ', ') || '. Veja Sistema → Armazenamento.', 'compactacao');
    exception when others then null; end;
  else
    update backup_config set compactacao_aviso = null, compactacao_aviso_em = now() where id;
  end if;
  if cardinality(v_cabe) = 0 then return; end if;              -- nada cabe: não agenda (o aviso já ficou na tela)
  -- próxima 05:30 em Brasília (= 08:30 UTC)
  v_base := date_trunc('day', now() at time zone 'UTC') + interval '8 hours 30 minutes';
  v_quando := (v_base at time zone 'UTC');
  if v_quando <= now() + interval '2 minutes' then v_quando := v_quando + interval '1 day'; end if;
  perform cron.schedule('compactar-' || floor(extract(epoch from v_quando))::bigint,
    extract(minute from v_quando at time zone 'UTC')::int || ' ' || extract(hour from v_quando at time zone 'UTC')::int || ' ' ||
    extract(day from v_quando at time zone 'UTC')::int || ' ' || extract(month from v_quando at time zone 'UTC')::int || ' *',
    'vacuum full ' || array_to_string(v_cabe, ', '));
end $function$;
revoke all on function public._compactar_agendar() from public, anon, authenticated;

-- painel do Armazenamento: mostra o aviso e reconhece a compactação parcial como "feita"
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.api_armazenamento_painel(jsonb)'::regprocedure);
  if position('compactacaoAviso' in d) > 0 then return; end if;
  d := pg_temp.tb_trocar1(d, 'command like ''vacuum full public.vendas%''', 'command like ''vacuum full public.%''');
  d := pg_temp.tb_trocar1(d, '(select max(medido_em) from arquivo_execucoes))),',
     '(select max(medido_em) from arquivo_execucoes)),
        ''aviso'', (select compactacao_aviso from backup_config where id), ''avisoEm'', (select compactacao_aviso_em from backup_config where id), ''compactacaoAviso'', true),');
  execute d;
end $do$;


-- ======================================================================
-- 62-ifood-financeiro.sql
-- ======================================================================
-- 62 · iFood FINANCEIRO completo (módulo Financial do iFood, exigido na homologação). Versão 1.15 (25/10/2026).
-- Feito pela documentação oficial do iFood (PDFs do portal do desenvolvedor, 25/10/2026):
--   API Sales (vendas), API Financial Events (lançamentos), API Settlement (repasses/títulos), API Anticipation (antecipações D+1/D+7)
--   e API Reconciliation On-Demand (arquivo mensal de conciliação em CSV).
-- Como funciona: o ifood-sync (que já roda a cada 30 s) busca os dados aos poucos, por uma FILA de tarefas (no máximo algumas
-- chamadas por rodada: bem abaixo do limite de 1000/min do iFood), com paginação, limites de período (vendas: 7 dias por vez;
-- lançamentos: 7 dias por vez, máx. 33), renovação do token, espera em 429 e o cabeçalho de homologação quando ligado.
-- Tudo fica guardado aqui (só leitura no app) e a tela Administrador → Dinheiro → "iFood: vendas e repasses" mostra.
-- Pode rodar de novo sem erro. Desfazer: drop das tabelas ifood_fin_* e das funções *ifood_fin*.

create or replace function pg_temp.tb_trocar1(d text, a text, b text) returns text language plpgsql as $f$
declare n int := (length(d) - length(replace(d, a, ''))) / greatest(length(a), 1);
begin
  if n <> 1 then raise exception '62: trecho esperado apareceu % vez(es): %', n, left(a, 90); end if;
  return replace(d, a, b);
end $f$;

-- ---------------------------------------------------------------- tabelas
create table if not exists public.ifood_fin_tarefas (
  id bigserial primary key,
  api text not null check (api in ('vendas', 'eventos', 'repasses', 'antecipacoes', 'conciliacao_pedir', 'conciliacao_status')),
  ini date, fim date, competencia text,
  pagina int not null default 0,
  estado text not null default 'pendente' check (estado in ('pendente', 'ok', 'sem_dados', 'erro')),
  tentativas int not null default 0,
  proxima timestamptz not null default now(),
  status_http int, erro text,
  origem text not null default 'auto' check (origem in ('auto', 'manual')),
  lote uuid,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  feito_em timestamptz);
create index if not exists ix_ifood_fin_tarefas_pend on public.ifood_fin_tarefas (proxima) where estado = 'pendente';
create index if not exists ix_ifood_fin_tarefas_lote on public.ifood_fin_tarefas (lote);

create table if not exists public.ifood_fin_vendas (
  id text primary key,                         -- sales.id = id do pedido no iFood
  short_id text, criado_em timestamptz, dia date, status text, tipo text, categoria text, canal text,
  bruto_itens numeric not null default 0, taxa_entrega numeric not null default 0, taxa_servico numeric not null default 0,
  beneficios jsonb, entrega jsonb, pagamentos jsonb, lancamentos jsonb,
  saldo numeric,                               -- billingSummary.saleBalance: líquido desta venda
  saldo_confere boolean,                       -- saleBalance = soma dos billingEntries (± R$ 0,01)
  comissao numeric not null default 0, taxas numeric not null default 0, subsidios numeric not null default 0,
  venda_id uuid,
  atualizado_em timestamptz not null default now());
create index if not exists ix_ifood_fin_vendas_dia on public.ifood_fin_vendas (dia);

create table if not exists public.ifood_fin_eventos (
  chave text primary key,
  nome text, descricao text, produto text, gatilho text, data_hora timestamptz, dia date, competencia text,
  periodo_ini date, periodo_fim date, ref_tipo text, ref_id text, ref_data timestamptz,
  impacto boolean not null default false, valor numeric not null default 0, base numeric, percentual numeric,
  parcela text, parcela_data date, repasse_esperado date, metodo text, bandeira text, responsavel text,
  atualizado_em timestamptz not null default now());
create index if not exists ix_ifood_fin_eventos_dia on public.ifood_fin_eventos (dia);
create index if not exists ix_ifood_fin_eventos_periodo on public.ifood_fin_eventos (periodo_ini);
create index if not exists ix_ifood_fin_eventos_ref on public.ifood_fin_eventos (ref_id);

create table if not exists public.ifood_fin_liquidacoes (
  id text primary key,                         -- closingItems.id (título)
  periodo_ini date, periodo_fim date, tipo text, produto text, valor numeric not null default 0, status text,
  transacao text, banco jsonb, banco_ok boolean, data_pagamento date, origem jsonb,
  atualizado_em timestamptz not null default now());
create index if not exists ix_ifood_fin_liq_periodo on public.ifood_fin_liquidacoes (periodo_ini);

create table if not exists public.ifood_fin_antecipacoes (
  chave text primary key,
  periodo_ini date, periodo_fim date, tipo text, valor_original numeric, taxa_pct numeric, taxa_valor numeric,
  valor_antecipado numeric, status text, banco jsonb, data_original date, data_antecipada date,
  atualizado_em timestamptz not null default now());

create table if not exists public.ifood_fin_consultas (       -- cada busca no iFood (para a tela mostrar "atualizado há..." e o último erro)
  api text primary key, em timestamptz, ok_em timestamptz, ok boolean, status_http int, mensagem text, saldo numeric, qtd int, ini date, fim date);

create table if not exists public.ifood_fin_conciliacao (
  competencia text primary key check (competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  request_id text, estado text not null default 'solicitado' check (estado in ('solicitado', 'processando', 'pronto', 'erro')),
  pedido_em timestamptz not null default now(), pedido_por text, concluido_em timestamptz, erro text,
  arquivo_gz bytea, bytes int, linhas int, resumo jsonb);

create table if not exists public.ifood_fin_alertas (chave text primary key, em timestamptz not null default now());

alter table public.ifood_estado add column if not exists fin_rotas jsonb not null default '{}'::jsonb;

do $do$
declare t text;
begin
  foreach t in array array['ifood_fin_tarefas', 'ifood_fin_vendas', 'ifood_fin_eventos', 'ifood_fin_liquidacoes', 'ifood_fin_antecipacoes',
                           'ifood_fin_consultas', 'ifood_fin_conciliacao', 'ifood_fin_alertas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $do$;
grant usage, select on sequence public.ifood_fin_tarefas_id_seq to service_role;

-- ---------------------------------------------------------------- ajudas
create or replace function public._ifood_fin_d(t text) returns date language plpgsql immutable as $f$
begin
  if t is null or btrim(t) = '' then return null; end if;
  return left(btrim(t), 10)::date;
exception when others then return null; end $f$;
create or replace function public._ifood_fin_ts(t text) returns timestamptz language plpgsql stable as $f$
begin
  if t is null or btrim(t) = '' then return null; end if;
  return btrim(t)::timestamptz;
exception when others then return null; end $f$;
create or replace function public._ifood_fin_bool(j jsonb) returns boolean language sql immutable as $f$
  select case when j is null then false when jsonb_typeof(j) = 'boolean' then (j #>> '{}')::boolean
              else upper(coalesce(j #>> '{}', '')) in ('TRUE', 'SIM', 'S', 'YES', '1') end $f$;
create or replace function public._ifood_fin_hoje() returns date language sql stable as $f$ select (now() at time zone 'America/Sao_Paulo')::date $f$;
create or replace function public._ifood_fin_segunda(d date) returns date language sql immutable as $f$ select d - (extract(isodow from d)::int - 1) $f$;

-- Dados do banco: guarda só o necessário para conferir e mostrar (conta mascarada) e valida o formato (banco 3 dígitos, agência 1-5,
-- conta 1-20, dígito 1), como pede a documentação.
create or replace function public._ifood_fin_banco(a jsonb) returns jsonb language plpgsql immutable as $f$
declare n text := a->>'bankNumber'; ag text := a->>'branchCode'; c text := a->>'accountNumber'; dg text := a->>'accountDigit'; prob text[] := '{}';
begin
  if a is null or jsonb_typeof(a) <> 'object' or a = '{}'::jsonb then return null; end if;
  if coalesce(n, '') !~ '^\d{3}$' then prob := prob || 'banco'; end if;
  if coalesce(ag, '') !~ '^\d{1,5}$' then prob := prob || 'agência'; end if;
  if coalesce(c, '') !~ '^\d{1,20}$' then prob := prob || 'conta'; end if;
  if coalesce(dg, '') !~ '^[0-9Xx]$' then prob := prob || 'dígito'; end if;
  return jsonb_build_object('nome', a->>'bankName', 'numero', n, 'agencia', ag,
    'conta', case when c is null then null else '•••' || right(c, 4) || coalesce('-' || dg, '') end,
    'documento', case when a->>'documentNumber' is null then null else '•••' || right(a->>'documentNumber', 4) end,
    'ok', cardinality(prob) = 0, 'problemas', to_jsonb(prob));
end $f$;

-- ---------------------------------------------------------------- fila de tarefas
create or replace function public._ifood_fin_enfileirar(p_api text, p_ini date, p_fim date, p_comp text, p_origem text, p_lote uuid)
 returns void language plpgsql security definer set search_path to 'public' as $f$
begin
  if exists (select 1 from ifood_fin_tarefas where estado = 'pendente' and api = p_api and ini is not distinct from p_ini
               and fim is not distinct from p_fim and competencia is not distinct from p_comp) then
    if p_lote is not null then update ifood_fin_tarefas set lote = coalesce(lote, p_lote), origem = p_origem
      where estado = 'pendente' and api = p_api and ini is not distinct from p_ini and fim is not distinct from p_fim and competencia is not distinct from p_comp; end if;
    return;
  end if;
  insert into ifood_fin_tarefas (api, ini, fim, competencia, origem, lote, pagina)
  values (p_api, p_ini, p_fim, p_comp, p_origem, p_lote, case when p_api = 'vendas' then 0 else 1 end);
end $f$;

-- Divide um período em pedaços de até 7 dias (o iFood recomenda semanas; lançamentos aceitam no máximo 33 dias).
create or replace function public._ifood_fin_enfileirar_periodo(p_ini date, p_fim date, p_origem text, p_lote uuid)
 returns int language plpgsql security definer set search_path to 'public' as $f$
declare d date := p_ini; n int := 0;
begin
  while d <= p_fim loop
    perform _ifood_fin_enfileirar('vendas', d, least(d + 6, p_fim), null, p_origem, p_lote);
    perform _ifood_fin_enfileirar('eventos', d, least(d + 6, p_fim), null, p_origem, p_lote);
    n := n + 2; d := d + 7;
  end loop;
  perform _ifood_fin_enfileirar('repasses', p_ini, p_fim, null, p_origem, p_lote);
  perform _ifood_fin_enfileirar('antecipacoes', p_ini, p_fim, null, p_origem, p_lote);
  return n + 2;
end $f$;

-- Automático (a cada 6 h, pelo ifood-sync): últimas 2 semanas de apuração completas + a semana atual; repasses e antecipações de 5 semanas.
-- Também apaga o que tem mais de 13 meses (o arquivo mensal oficial fica no iFood) e tarefas antigas.
create or replace function public.ifood_fin_agendar_auto() returns int
 language plpgsql security definer set search_path to 'public' as $f$
declare h date := _ifood_fin_hoje(); s date := _ifood_fin_segunda(_ifood_fin_hoje()); n int;
begin
  n := _ifood_fin_enfileirar_periodo(s - 14, h, 'auto', null);
  perform _ifood_fin_enfileirar('repasses', s - 35, h, null, 'auto', null);
  perform _ifood_fin_enfileirar('antecipacoes', s - 35, h, null, 'auto', null);
  delete from ifood_fin_eventos where dia < h - interval '13 months';
  delete from ifood_fin_vendas where dia < h - interval '13 months';
  delete from ifood_fin_liquidacoes where periodo_fim < h - interval '13 months';
  delete from ifood_fin_antecipacoes where periodo_fim < h - interval '13 months';
  delete from ifood_fin_conciliacao where competencia < to_char(h - interval '13 months', 'YYYY-MM');
  delete from ifood_fin_tarefas where estado <> 'pendente' and criado_em < now() - interval '7 days';
  delete from ifood_fin_alertas where em < now() - interval '120 days';
  return n;
end $f$;

create or replace function public.ifood_fin_proximas(p_limite int default 6) returns jsonb
 language sql security definer set search_path to 'public' as $f$
  select jsonb_build_object('rotas', (select fin_rotas from ifood_estado where id), 'tarefas', coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'api', t.api, 'ini', t.ini, 'fim', t.fim, 'competencia', t.competencia, 'pagina', t.pagina,
           'tentativas', t.tentativas, 'dados', t.dados, 'requestId', nullif(c.request_id, ''), 'pedidoEm', c.pedido_em) order by t.proxima, t.id), '[]'::jsonb))
  from (select * from ifood_fin_tarefas where estado = 'pendente' and proxima <= now()
        order by (origem = 'manual') desc, proxima, id limit greatest(1, least(coalesce(p_limite, 6), 20))) t
  left join ifood_fin_conciliacao c on c.competencia = t.competencia
$f$;
-- (até a 1.15 de testes devolvia só a lista; agora devolve {rotas, tarefas})

-- Resultado de uma tarefa. p_estado: ok | sem_dados | erro | pendente (= tenta de novo daqui a p_espera_seg) | pagina (= próxima página já)
create or replace function public.ifood_fin_tarefa_fim(p_id bigint, p_estado text, p_status int default null, p_erro text default null,
   p_espera_seg int default 0, p_dados jsonb default null) returns void
 language plpgsql security definer set search_path to 'public' as $f$
begin
  if p_estado = 'pagina' then
    update ifood_fin_tarefas set pagina = pagina + 1, proxima = now(), status_http = p_status, erro = null, dados = dados || coalesce(p_dados, '{}') where id = p_id;
  elsif p_estado = 'pendente' then
    update ifood_fin_tarefas set tentativas = tentativas + 1, proxima = now() + make_interval(secs => greatest(10, coalesce(p_espera_seg, 60))),
      status_http = p_status, erro = left(p_erro, 400), dados = dados || coalesce(p_dados, '{}') where id = p_id;
  else
    update ifood_fin_tarefas set estado = case when p_estado in ('ok', 'sem_dados', 'erro') then p_estado else 'erro' end, feito_em = now(),
      status_http = p_status, erro = left(p_erro, 400), dados = dados || coalesce(p_dados, '{}') where id = p_id;
  end if;
end $f$;

create or replace function public.ifood_fin_consulta(p_api text, p_ok boolean, p_status int default null, p_msg text default null,
   p_saldo numeric default null, p_qtd int default null, p_ini date default null, p_fim date default null) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare v_ant boolean;
begin
  select ok into v_ant from ifood_fin_consultas where api = p_api;
  insert into ifood_fin_consultas (api, em, ok_em, ok, status_http, mensagem, saldo, qtd, ini, fim)
  values (p_api, now(), case when p_ok then now() end, p_ok, p_status, left(p_msg, 400), p_saldo, p_qtd, p_ini, p_fim)
  on conflict (api) do update set em = now(), ok_em = case when p_ok then now() else ifood_fin_consultas.ok_em end, ok = p_ok,
     status_http = p_status, mensagem = left(p_msg, 400), saldo = coalesce(p_saldo, ifood_fin_consultas.saldo),
     qtd = coalesce(p_qtd, ifood_fin_consultas.qtd), ini = coalesce(p_ini, ifood_fin_consultas.ini), fim = coalesce(p_fim, ifood_fin_consultas.fim);
  if not p_ok and v_ant is distinct from false then      -- registra só quando muda de "ok" para "erro" (sem encher o log a cada 6 h)
    perform _integ_log('ifood', 'aviso', 'Financeiro do iFood (' || p_api || ') não carregou: ' || coalesce(p_status::text, '') || ' ' || left(coalesce(p_msg, ''), 200));
  end if;
end $f$;

create or replace function public.ifood_fin_rota(p_api text, p_rota text) returns void
 language sql security definer set search_path to 'public' as $f$
  update ifood_estado set fin_rotas = fin_rotas || jsonb_build_object(p_api, p_rota) where id
$f$;

-- ---------------------------------------------------------------- gravação (vem do ifood-sync)
create or replace function public.ifood_fin_vendas_gravar(p_lista jsonb) returns int
 language plpgsql security definer set search_path to 'public' as $f$
declare s jsonb; n int := 0; v_soma numeric; v_saldo numeric; v_com numeric; v_tax numeric; v_sub numeric; v_venda uuid; v_usar boolean;
begin
  v_usar := coalesce((select (config->>'comissaoFinanceiro')::boolean from integracoes_config where provedor = 'ifood'), false);
  for s in select value from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) loop
    if nullif(s->>'id', '') is null then continue; end if;
    select coalesce(sum(_ifood_n(e->'value')), 0),
           coalesce(sum(abs(_ifood_n(e->'value'))) filter (where _ifood_n(e->'value') < 0 and upper(e->>'name') like '%COMMISSION%'), 0),
           coalesce(sum(abs(_ifood_n(e->'value'))) filter (where _ifood_n(e->'value') < 0 and upper(e->>'name') not like '%COMMISSION%'), 0),
           coalesce(sum(_ifood_n(e->'value')) filter (where upper(e->>'name') like '%SUBSID%'), 0)
      into v_soma, v_com, v_tax, v_sub
      from jsonb_array_elements(case when jsonb_typeof(s->'billingSummary'->'billingEntries') = 'array' then s->'billingSummary'->'billingEntries' else '[]'::jsonb end) e;
    v_saldo := case when s->'billingSummary' ? 'saleBalance' then _ifood_n(s->'billingSummary'->'saleBalance') end;
    select venda_id into v_venda from ifood_pedidos where pedido_ifood = s->>'id';
    insert into ifood_fin_vendas (id, short_id, criado_em, dia, status, tipo, categoria, canal, bruto_itens, taxa_entrega, taxa_servico,
       beneficios, entrega, pagamentos, lancamentos, saldo, saldo_confere, comissao, taxas, subsidios, venda_id, atualizado_em)
    values (s->>'id', s->>'shortId', _ifood_fin_ts(s->>'createdAt'), (_ifood_fin_ts(s->>'createdAt') at time zone 'America/Sao_Paulo')::date,
       s->>'currentStatus', s->>'type', s->>'category', s->>'salesChannel',
       _ifood_n(s->'saleGrossValue'->'bag'), _ifood_n(s->'saleGrossValue'->'deliveryFee'), _ifood_n(s->'saleGrossValue'->'serviceFee'),
       s->'benefits', jsonb_strip_nulls(jsonb_build_object('tipo', s->'delivery'->>'type', 'logistica', s->'delivery'->'deliveryParameters'->>'logisticProvider',
           'bruto', s->'delivery'->'prices'->'grossValue', 'desconto', s->'delivery'->'prices'->'discount', 'liquido', s->'delivery'->'prices'->'netValue')),
       (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('metodo', m->>'method', 'tipo', m->>'type', 'valor', m->'value', 'bandeira', m->'card'->>'brand',
           'carteira', m->'wallet'->>'name', 'responsavel', m->>'liability', 'parcelas', m->'installment'->'maxInstallments', 'troco', m->'cash'->'changeFor', 'reembolso', m->>'refundType')))
          from jsonb_array_elements(case when jsonb_typeof(s->'payments'->'methods') = 'array' then s->'payments'->'methods' else '[]'::jsonb end) m),
       s->'billingSummary'->'billingEntries', v_saldo,
       case when v_saldo is null then null else abs(v_saldo - v_soma) <= 0.011 end,
       v_com, v_tax, v_sub, v_venda, now())
    on conflict (id) do update set short_id = excluded.short_id, criado_em = excluded.criado_em, dia = excluded.dia, status = excluded.status,
       tipo = excluded.tipo, categoria = excluded.categoria, canal = excluded.canal, bruto_itens = excluded.bruto_itens, taxa_entrega = excluded.taxa_entrega,
       taxa_servico = excluded.taxa_servico, beneficios = excluded.beneficios, entrega = excluded.entrega, pagamentos = excluded.pagamentos,
       lancamentos = excluded.lancamentos, saldo = excluded.saldo, saldo_confere = excluded.saldo_confere, comissao = excluded.comissao,
       taxas = excluded.taxas, subsidios = excluded.subsidios, venda_id = coalesce(excluded.venda_id, ifood_fin_vendas.venda_id), atualizado_em = now();
    -- opção (desligada de fábrica): usar a comissão + taxas REAIS do iFood nas taxas da venda do sistema (relatórios e DRE)
    if v_usar and v_venda is not null and (v_com + v_tax) > 0 then
      update ifood_pedidos set comissao = v_com + v_tax where pedido_ifood = s->>'id';
      perform _ifood_aplicar_comissao(v_venda, v_com + v_tax);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

create or replace function public.ifood_fin_eventos_gravar(p_ini date, p_fim date, p_primeira boolean, p_lista jsonb) returns int
 language plpgsql security definer set search_path to 'public' as $f$
declare n int;
begin
  if p_primeira then delete from ifood_fin_eventos where dia between p_ini and p_fim; end if;   -- a busca refaz o período inteiro
  insert into ifood_fin_eventos (chave, nome, descricao, produto, gatilho, data_hora, dia, competencia, periodo_ini, periodo_fim, ref_tipo, ref_id, ref_data,
     impacto, valor, base, percentual, parcela, parcela_data, repasse_esperado, metodo, bandeira, responsavel, atualizado_em)
  select md5(x.e::text || '#' || x.ord), x.e->>'name', x.e->>'description', x.e->>'product', x.e->>'trigger', _ifood_fin_ts(x.e->>'dateTime'),
     coalesce((_ifood_fin_ts(x.e->>'dateTime') at time zone 'America/Sao_Paulo')::date, _ifood_fin_d(x.e->'period'->>'beginDate')),
     x.e->>'competence', _ifood_fin_d(x.e->'period'->>'beginDate'), _ifood_fin_d(x.e->'period'->>'endDate'),
     x.e->'reference'->>'type', x.e->'reference'->>'id', _ifood_fin_ts(x.e->'reference'->>'date'),
     _ifood_fin_bool(x.e->'hasTransferImpact'), _ifood_n(x.e->'amount'),
     case when x.e->'billing' ? 'baseValue' then _ifood_n(x.e->'billing'->'baseValue') end,
     case when x.e->'billing' ? 'feePercentage' then _ifood_n(x.e->'billing'->'feePercentage') end,
     x.e->'billing'->'installments'->>'reference', _ifood_fin_d(x.e->'billing'->'installments'->>'referenceDate'),
     _ifood_fin_d(x.e->'settlement'->>'expectedDate'), x.e->'payment'->>'method', x.e->'payment'->>'brand', x.e->'payment'->>'liability', now()
  from (select e, row_number() over (partition by e::text order by o) ord
          from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) with ordinality a(e, o) where jsonb_typeof(e) = 'object') x
  on conflict (chave) do update set atualizado_em = now(), impacto = excluded.impacto, valor = excluded.valor, repasse_esperado = excluded.repasse_esperado;
  get diagnostics n = row_count;
  return n;
end $f$;

-- Repasses (títulos). BOLETO = a loja deve ao iFood: entra NEGATIVO na conferência.
create or replace function public.ifood_fin_liquidacoes_gravar(p_resp jsonb) returns int
 language plpgsql security definer set search_path to 'public' as $f$
declare p jsonb; c jsonb; n int := 0; v_id text;
begin
  for p in select value from jsonb_array_elements(case when jsonb_typeof(p_resp->'settlements') = 'array' then p_resp->'settlements' else '[]'::jsonb end) loop
    for c in select value from jsonb_array_elements(case when jsonb_typeof(p->'closingItems') = 'array' then p->'closingItems' else '[]'::jsonb end) loop
      v_id := coalesce(nullif(c->>'id', ''), md5(p::text || c::text));
      insert into ifood_fin_liquidacoes (id, periodo_ini, periodo_fim, tipo, produto, valor, status, transacao, banco, banco_ok, data_pagamento, origem, atualizado_em)
      values (v_id, _ifood_fin_d(p->>'startDateCalculation'), _ifood_fin_d(p->>'endDateCalculation'), c->>'type', c->>'product', _ifood_n(c->'amount'),
              c->>'status', c->>'transactionId', _ifood_fin_banco(c->'accountDetails'), (_ifood_fin_banco(c->'accountDetails')->>'ok')::boolean,
              _ifood_fin_d(c->>'paymentDate'), nullif(c->'originDetails', 'null'::jsonb), now())
      on conflict (id) do update set periodo_ini = excluded.periodo_ini, periodo_fim = excluded.periodo_fim, tipo = excluded.tipo, produto = excluded.produto,
         valor = excluded.valor, status = excluded.status, transacao = excluded.transacao, banco = excluded.banco, banco_ok = excluded.banco_ok,
         data_pagamento = excluded.data_pagamento, origem = excluded.origem, atualizado_em = now();
      if upper(coalesce(c->>'status', '')) = 'FAILED' and not exists (select 1 from ifood_fin_alertas where chave = 'liq-' || v_id) then
        insert into ifood_fin_alertas (chave) values ('liq-' || v_id);
        begin perform _push_admins('iFood: repasse com FALHA', 'O título ' || v_id || ' (' || coalesce(c->>'type', '') || ', R$ ' || _ifood_n(c->'amount') || ') falhou. Veja Dinheiro → iFood: vendas e repasses.', 'ifood-fin');
        exception when others then null; end;
      end if;
      n := n + 1;
    end loop;
  end loop;
  -- compatibilidade: o quadro antigo "A receber / recebido do iFood" continua alimentado pelos repasses pagos
  begin
    perform ifood_repasses_gravar((select coalesce(jsonb_agg(jsonb_build_object('id', id, 'paymentDate', data_pagamento, 'periodStart', periodo_ini, 'periodEnd', periodo_fim, 'amount', valor, 'orders', '[]'::jsonb)), '[]'::jsonb)
                                   from ifood_fin_liquidacoes where upper(coalesce(tipo, '')) = 'REPASSE' and upper(coalesce(status, '')) = 'SUCCEED'));
  exception when others then null; end;
  return n;
end $f$;

create or replace function public.ifood_fin_antecipacoes_gravar(p_resp jsonb) returns int
 language plpgsql security definer set search_path to 'public' as $f$
declare p jsonb; c jsonb; n int := 0; v_k text;
begin
  for p in select value from jsonb_array_elements(case when jsonb_typeof(p_resp->'settlements') = 'array' then p_resp->'settlements' else '[]'::jsonb end) loop
    for c in select value from jsonb_array_elements(case when jsonb_typeof(p->'closingItems') = 'array' then p->'closingItems' else '[]'::jsonb end) loop
      v_k := coalesce(nullif(c->>'id', ''), md5(coalesce(p->>'startDateCalculation', '') || (c - 'accountDetails' - 'status')::text));
      insert into ifood_fin_antecipacoes (chave, periodo_ini, periodo_fim, tipo, valor_original, taxa_pct, taxa_valor, valor_antecipado, status, banco, data_original, data_antecipada, atualizado_em)
      values (v_k, _ifood_fin_d(p->>'startDateCalculation'), _ifood_fin_d(p->>'endDateCalculation'), c->>'type', _ifood_n(c->'originalPaymentAmount'),
              _ifood_n(c->'feePercentage'), _ifood_n(c->'feeAmount'), _ifood_n(c->'anticipatedPaymentAmount'), c->>'status',
              _ifood_fin_banco(c->'accountDetails'), _ifood_fin_d(c->>'originalPaymentDate'), _ifood_fin_d(c->>'anticipatedPaymentDate'), now())
      on conflict (chave) do update set status = excluded.status, banco = excluded.banco, valor_antecipado = excluded.valor_antecipado,
         taxa_valor = excluded.taxa_valor, taxa_pct = excluded.taxa_pct, data_antecipada = excluded.data_antecipada, atualizado_em = now();
      if upper(coalesce(c->>'status', '')) = 'FAILED' and not exists (select 1 from ifood_fin_alertas where chave = 'ant-' || v_k) then
        insert into ifood_fin_alertas (chave) values ('ant-' || v_k);
        begin perform _push_admins('iFood: antecipação com FALHA', 'Uma antecipação de R$ ' || _ifood_n(c->'originalPaymentAmount') || ' falhou. Veja Dinheiro → iFood: vendas e repasses.', 'ifood-fin');
        exception when others then null; end;
      end if;
      n := n + 1;
    end loop;
  end loop;
  return n;
end $f$;

create or replace function public.ifood_fin_conciliacao_estado(p_competencia text, p_estado text, p_request_id text default null, p_erro text default null) returns void
 language plpgsql security definer set search_path to 'public' as $f$
begin
  update ifood_fin_conciliacao set estado = p_estado, request_id = coalesce(p_request_id, request_id), erro = left(p_erro, 400),
     concluido_em = case when p_estado = 'erro' then now() else concluido_em end
   where competencia = p_competencia;
end $f$;

create or replace function public.ifood_fin_conciliacao_pronta(p_competencia text, p_b64 text, p_linhas int, p_resumo jsonb) returns void
 language plpgsql security definer set search_path to 'public' as $f$
begin
  update ifood_fin_conciliacao set estado = 'pronto', concluido_em = now(), erro = null, arquivo_gz = decode(p_b64, 'base64'),
     bytes = length(decode(p_b64, 'base64')), linhas = p_linhas, resumo = p_resumo
   where competencia = p_competencia;
end $f$;

do $do$
declare f text;
begin
  foreach f in array array['_ifood_fin_enfileirar(text,date,date,text,text,uuid)', '_ifood_fin_enfileirar_periodo(date,date,text,uuid)',
     'ifood_fin_agendar_auto()', 'ifood_fin_proximas(integer)', 'ifood_fin_tarefa_fim(bigint,text,integer,text,integer,jsonb)',
     'ifood_fin_consulta(text,boolean,integer,text,numeric,integer,date,date)', 'ifood_fin_rota(text,text)', 'ifood_fin_vendas_gravar(jsonb)',
     'ifood_fin_eventos_gravar(date,date,boolean,jsonb)', 'ifood_fin_liquidacoes_gravar(jsonb)', 'ifood_fin_antecipacoes_gravar(jsonb)',
     'ifood_fin_conciliacao_estado(text,text,text,text)', 'ifood_fin_conciliacao_pronta(text,text,integer,jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
    execute 'grant execute on function public.' || f || ' to service_role';
  end loop;
end $do$;

-- ---------------------------------------------------------------- conferência semanal (Vendas × Lançamentos × Repasse)
-- Regra do iFood: repasse da semana (seg–dom) = soma dos lançamentos COM impacto no repasse (tolerância 0,01%).
create or replace function public._ifood_fin_semanas(p_qtd int default 8) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare s date := _ifood_fin_segunda(_ifood_fin_hoje()); i int; d date; v jsonb := '[]'::jsonb;
  v_vendas numeric; v_nv int; v_ev numeric; v_ne int; v_sem numeric; v_liq numeric; v_nl int; v_tol numeric; v_situ text; v_dif numeric;
begin
  for i in 0..greatest(1, least(p_qtd, 26)) - 1 loop
    d := s - 7 * i;
    select sum(saldo), count(*) into v_vendas, v_nv from ifood_fin_vendas where dia between d and d + 6;
    select sum(valor) filter (where impacto), count(*), sum(valor) filter (where not impacto) into v_ev, v_ne, v_sem
      from ifood_fin_eventos where coalesce(periodo_ini, _ifood_fin_segunda(dia)) = d;
    select sum(case when upper(coalesce(tipo, '')) = 'BOLETO' then -abs(valor) else valor end), count(*) into v_liq, v_nl
      from ifood_fin_liquidacoes where periodo_ini = d;
    v_dif := null; v_situ := 'sem_dados';
    if v_ne > 0 and v_nl > 0 then
      v_dif := round(coalesce(v_ev, 0) - coalesce(v_liq, 0), 2);
      v_tol := greatest(0.01, abs(coalesce(v_liq, 0)) * 0.0001);
      v_situ := case when abs(v_dif) <= v_tol then 'confere' else 'diferenca' end;
    end if;
    -- semana ainda aberta (ou apurada hoje, segunda): o iFood só fecha a apuração na segunda-feira seguinte (dados completos à tarde)
    if d + 7 >= _ifood_fin_hoje() and v_situ <> 'confere' then v_situ := 'aberta';
    elsif v_situ = 'sem_dados' and v_ne > 0 then v_situ := 'sem_repasse'; end if;
    v := v || jsonb_build_object('ini', d, 'fim', d + 6, 'vendas', v_vendas, 'qtdVendas', v_nv, 'lancamentos', v_ev, 'semImpacto', v_sem, 'qtdLancamentos', v_ne,
                                 'repasse', v_liq, 'qtdTitulos', v_nl, 'diferenca', v_dif, 'situacao', v_situ,
                                 'vendasDif', case when v_nv > 0 and v_ne > 0 then round(coalesce(v_vendas, 0) - coalesce(v_ev, 0), 2) end);
  end loop;
  return v;
end $f$;

create or replace function public.ifood_fin_alertar_semanas() returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare w jsonb;
begin
  for w in select value from jsonb_array_elements(_ifood_fin_semanas(6)) loop
    if w->>'situacao' = 'diferenca' and abs((w->>'diferenca')::numeric) > greatest(1, abs(coalesce((w->>'repasse')::numeric, 0)) * 0.01)
       and not exists (select 1 from ifood_fin_alertas where chave = 'sem-' || (w->>'ini')) then
      insert into ifood_fin_alertas (chave) values ('sem-' || (w->>'ini'));
      perform _integ_log('ifood', 'aviso', 'Financeiro do iFood: semana ' || (w->>'ini') || ' com diferença de R$ ' || (w->>'diferenca') || ' entre lançamentos e repasse.');
      begin perform _push_admins('iFood: repasse não confere', 'Semana de ' || to_char((w->>'ini')::date, 'DD/MM') || ': diferença de R$ ' || replace((w->>'diferenca'), '.', ',') || ' entre os lançamentos e o repasse. Veja Dinheiro → iFood: vendas e repasses.', 'ifood-fin');
      exception when others then null; end;
    end if;
  end loop;
end $f$;
revoke all on function public.ifood_fin_alertar_semanas() from public, anon, authenticated;
grant execute on function public.ifood_fin_alertar_semanas() to service_role;
revoke all on function public._ifood_fin_semanas(int) from public, anon, authenticated;

-- ---------------------------------------------------------------- tela (Admin)
create or replace function public.api_ifood_fin_dados(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_aba text := coalesce(p->>'aba', 'painel'); v_ini date := coalesce(_ifood_fin_d(p->>'ini'), _ifood_fin_hoje() - 30);
  v_fim date := coalesce(_ifood_fin_d(p->>'fim'), _ifood_fin_hoje()); v_busca text := lower(btrim(coalesce(p->>'busca', '')));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_fim < v_ini then return _falha('A data final precisa ser depois da inicial.'); end if;
  if v_aba = 'painel' then
    return jsonb_build_object('ok', true,
      'ligado', _integracao_ligada('ifood'),
      'homologacao', coalesce((select (config->>'modoHomologacao')::boolean from integracoes_config where provedor = 'ifood'), false),
      'comissaoFinanceiro', coalesce((select (config->>'comissaoFinanceiro')::boolean from integracoes_config where provedor = 'ifood'), false),
      'modulo', (select jsonb_build_object('status', ultimo_status, 'ultimoOk', ultimo_ok, 'ultimoErroEm', ultimo_erro_em, 'msg', ultima_msg) from ifood_modulos where modulo = 'financial'),
      'consultas', coalesce((select jsonb_object_agg(api, jsonb_build_object('em', em, 'okEm', ok_em, 'ok', ok, 'status', status_http, 'msg', mensagem, 'saldo', saldo, 'qtd', qtd, 'ini', ini, 'fim', fim)) from ifood_fin_consultas), '{}'::jsonb),
      'pendentes', (select count(*) from ifood_fin_tarefas where estado = 'pendente'),
      'semanas', _ifood_fin_semanas(coalesce((p->>'semanas')::int, 8)),
      'totais', (select jsonb_build_object('vendas', count(*), 'semSaldoConferido', count(*) filter (where saldo_confere = false)) from ifood_fin_vendas where dia between v_ini and v_fim));
  elsif v_aba = 'vendas' then
    return jsonb_build_object('ok', true, 'ini', v_ini, 'fim', v_fim,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'numero', v.short_id, 'em', v.criado_em, 'status', v.status, 'canal', v.canal,
           'bruto', v.bruto_itens + v.taxa_entrega + v.taxa_servico, 'itens', v.bruto_itens, 'entrega', v.taxa_entrega, 'servico', v.taxa_servico,
           'comissao', v.comissao, 'taxas', v.taxas, 'subsidios', v.subsidios, 'liquido', v.saldo, 'confere', v.saldo_confere,
           'pagamentos', v.pagamentos, 'lancamentos', v.lancamentos, 'beneficios', v.beneficios, 'entregaInfo', v.entrega,
           'vendaId', v.venda_id, 'pedidoLocal', (select numero_pedido from vendas where id = v.venda_id)) order by v.criado_em desc)
         from (select * from ifood_fin_vendas where dia between v_ini and v_fim
                 and (v_busca = '' or lower(coalesce(short_id, '')) like '%' || v_busca || '%' or lower(id) like v_busca || '%')
               order by criado_em desc limit 400) v), '[]'::jsonb),
      'soma', (select jsonb_build_object('qtd', count(*), 'bruto', sum(bruto_itens + taxa_entrega + taxa_servico), 'comissao', sum(comissao), 'taxas', sum(taxas),
           'subsidios', sum(subsidios), 'liquido', sum(saldo)) from ifood_fin_vendas where dia between v_ini and v_fim));
  elsif v_aba = 'eventos' then
    return jsonb_build_object('ok', true, 'ini', v_ini, 'fim', v_fim,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'descricao', descricao, 'gatilho', gatilho, 'produto', produto, 'em', data_hora, 'dia', dia,
           'competencia', competencia, 'periodoIni', periodo_ini, 'periodoFim', periodo_fim, 'refTipo', ref_tipo, 'refId', ref_id, 'impacto', impacto, 'valor', valor,
           'base', base, 'percentual', percentual, 'parcela', parcela, 'repasseEsperado', repasse_esperado, 'metodo', metodo, 'bandeira', bandeira,
           'responsavel', responsavel, 'pedido', (select short_id from ifood_fin_vendas fv where fv.id = e.ref_id)) order by data_hora desc nulls last)
         from (select * from ifood_fin_eventos where dia between v_ini and v_fim
                 and (coalesce(p->>'impacto', '') = '' or impacto = (p->>'impacto')::boolean)
                 and (v_busca = '' or lower(coalesce(nome, '') || ' ' || coalesce(descricao, '') || ' ' || coalesce(ref_id, '')) like '%' || v_busca || '%')
               order by data_hora desc nulls last limit 600) e), '[]'::jsonb),
      'soma', (select jsonb_build_object('qtd', count(*), 'comImpacto', sum(valor) filter (where impacto), 'semImpacto', sum(valor) filter (where not impacto),
           'creditos', sum(valor) filter (where impacto and valor > 0), 'debitos', sum(valor) filter (where impacto and valor < 0))
         from ifood_fin_eventos where dia between v_ini and v_fim));
  elsif v_aba = 'repasses' then
    return jsonb_build_object('ok', true, 'ini', v_ini, 'fim', v_fim,
      'saldoUltimaConsulta', (select saldo from ifood_fin_consultas where api = 'repasses'),
      'itens', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'periodoIni', periodo_ini, 'periodoFim', periodo_fim, 'tipo', tipo, 'produto', produto, 'valor', valor,
           'status', status, 'transacao', transacao, 'banco', banco, 'bancoOk', banco_ok, 'pagamento', data_pagamento, 'origem', origem) order by periodo_ini desc, data_pagamento desc nulls last)
         from ifood_fin_liquidacoes where coalesce(data_pagamento, periodo_fim) between v_ini and v_fim + 60 and coalesce(periodo_ini, v_ini) <= v_fim), '[]'::jsonb));
  elsif v_aba = 'antecipacoes' then
    return jsonb_build_object('ok', true, 'ini', v_ini, 'fim', v_fim,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'periodoIni', periodo_ini, 'periodoFim', periodo_fim, 'original', valor_original, 'taxaPct', taxa_pct,
           'taxa', taxa_valor, 'antecipado', valor_antecipado, 'status', status, 'banco', banco, 'dataOriginal', data_original, 'dataAntecipada', data_antecipada,
           'diasAntes', data_original - data_antecipada) order by data_antecipada desc nulls last)
         from ifood_fin_antecipacoes where coalesce(data_antecipada, periodo_fim) between v_ini and v_fim + 60), '[]'::jsonb),
      'semPlano', (select status_http = 404 from ifood_fin_consultas where api = 'antecipacoes'));
  elsif v_aba = 'conciliacao' then
    return jsonb_build_object('ok', true,
      'itens', coalesce((select jsonb_agg(jsonb_build_object('competencia', competencia, 'estado', estado, 'pedidoEm', pedido_em, 'pedidoPor', pedido_por, 'concluidoEm', concluido_em,
           'erro', erro, 'bytes', bytes, 'linhas', linhas, 'resumo', resumo, 'temArquivo', arquivo_gz is not null,
           'eventosComImpacto', (select sum(valor) from ifood_fin_eventos e where e.impacto and coalesce(e.competencia, to_char(e.dia, 'YYYY-MM')) = c.competencia),
           'podePedirEm', case when estado in ('solicitado', 'processando') or pedido_em > now() - interval '6 hours' then pedido_em + interval '6 hours' end)
         order by competencia desc) from ifood_fin_conciliacao c), '[]'::jsonb),
      'meses', (select jsonb_agg(to_char(m, 'YYYY-MM') order by m desc) from generate_series(date_trunc('month', _ifood_fin_hoje()) - interval '12 months',
                 date_trunc('month', _ifood_fin_hoje()) - interval '1 month', interval '1 month') m));
  end if;
  return _falha('Aba desconhecida.');
end $f$;
revoke all on function public.api_ifood_fin_dados(jsonb) from public, anon;
grant execute on function public.api_ifood_fin_dados(jsonb) to authenticated, service_role;

create or replace function public.api_ifood_fin_acao(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_acao text := coalesce(p->>'acao', ''); v_ini date; v_fim date; v_lote uuid; n int; v_comp text; c record; v_eu text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select login into v_eu from usuarios where id = auth.uid();
  if v_acao = 'atualizar' then
    if not _integracao_ligada('ifood') then return _falha('A integração do iFood está desligada. Ligue em Integrações e contas → iFood.'); end if;
    v_ini := _ifood_fin_d(p->>'ini'); v_fim := least(coalesce(_ifood_fin_d(p->>'fim'), _ifood_fin_hoje()), _ifood_fin_hoje());
    if v_ini is null then return _falha('Escolha a data inicial.'); end if;
    if v_fim < v_ini then return _falha('A data final precisa ser depois da inicial.'); end if;
    if v_fim - v_ini > 92 then return _falha('Escolha no máximo 3 meses por vez (o iFood aceita até 90 dias nas vendas).'); end if;
    if (select count(*) from ifood_fin_tarefas where estado = 'pendente' and origem = 'manual') > 80 then return _falha('Já há muitas buscas na fila. Espere terminar.'); end if;
    v_lote := gen_random_uuid();
    n := _ifood_fin_enfileirar_periodo(v_ini, v_fim, 'manual', v_lote);
    return jsonb_build_object('ok', true, 'lote', v_lote, 'tarefas', n,
      'message', 'Buscando no iFood (' || n || ' consultas, de ' || to_char(v_ini, 'DD/MM') || ' a ' || to_char(v_fim, 'DD/MM') || '). Leva de 1 a ' || greatest(2, ceil(n / 10.0)::int) || ' minuto(s).');
  elsif v_acao = 'lote' then
    v_lote := nullif(p->>'lote', '')::uuid;
    return jsonb_build_object('ok', true,
      'total', (select count(*) from ifood_fin_tarefas where lote = v_lote),
      'feitas', (select count(*) from ifood_fin_tarefas where lote = v_lote and estado <> 'pendente'),
      'erros', coalesce((select jsonb_agg(jsonb_build_object('api', api, 'ini', ini, 'fim', fim, 'status', status_http, 'erro', erro)) from ifood_fin_tarefas where lote = v_lote and estado = 'erro'), '[]'::jsonb),
      'esperando', (select min(proxima) from ifood_fin_tarefas where lote = v_lote and estado = 'pendente'));
  elsif v_acao = 'conciliacao' then
    if not _integracao_ligada('ifood') then return _falha('A integração do iFood está desligada.'); end if;
    v_comp := p->>'competencia';
    if coalesce(v_comp, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then return _falha('Mês inválido (use AAAA-MM).'); end if;
    if to_date(v_comp || '-01', 'YYYY-MM-DD') >= date_trunc('month', _ifood_fin_hoje())::date then return _falha('O arquivo só existe para meses que já terminaram.'); end if;
    if to_date(v_comp || '-01', 'YYYY-MM-DD') < (date_trunc('month', _ifood_fin_hoje()) - interval '24 months')::date then return _falha('O iFood só gera arquivo dos últimos 24 meses.'); end if;
    select * into c from ifood_fin_conciliacao where competencia = v_comp;
    if found and c.estado in ('solicitado', 'processando') and c.pedido_em > now() - interval '35 minutes' then
      return jsonb_build_object('ok', true, 'message', 'Este mês já está sendo gerado pelo iFood. Aguarde.');
    end if;
    if found and c.pedido_em > now() - interval '6 hours' and c.estado = 'pronto' then
      return _falha('O iFood só gera de novo o mesmo mês 6 horas depois (pedido às ' || to_char(c.pedido_em at time zone 'America/Sao_Paulo', 'HH24:MI') || '). O arquivo atual continua disponível.');
    end if;
    insert into ifood_fin_conciliacao (competencia, estado, pedido_em, pedido_por, request_id, erro)
    values (v_comp, 'solicitado', now(), v_eu, null, null)
    on conflict (competencia) do update set estado = 'solicitado', pedido_em = now(), pedido_por = v_eu, erro = null,
       request_id = case when ifood_fin_conciliacao.pedido_em > now() - interval '6 hours' then nullif(ifood_fin_conciliacao.request_id, '') end;
    perform _ifood_fin_enfileirar(case when (select nullif(request_id, '') from ifood_fin_conciliacao where competencia = v_comp) is not null then 'conciliacao_status' else 'conciliacao_pedir' end,
                                  null, null, v_comp, 'manual', null);
    perform _auditar('iFood: arquivo de conciliação pedido', v_comp);
    return jsonb_build_object('ok', true, 'message', 'Pedido ao iFood. O arquivo de ' || v_comp || ' fica pronto em alguns minutos (até 30).');
  elsif v_acao = 'arquivo' then
    select * into c from ifood_fin_conciliacao where competencia = p->>'competencia';
    if not found or c.arquivo_gz is null then return _falha('Arquivo ainda não disponível.'); end if;
    perform _auditar('iFood: arquivo de conciliação baixado', c.competencia);
    return jsonb_build_object('ok', true, 'competencia', c.competencia, 'gz', encode(c.arquivo_gz, 'base64'), 'linhas', c.linhas);
  end if;
  return _falha('Ação desconhecida.');
end $f$;
revoke all on function public.api_ifood_fin_acao(jsonb) from public, anon;
grant execute on function public.api_ifood_fin_acao(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------- opção nova do iFood: comissão real nas vendas
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.api_integracoes_config(jsonb)'::regprocedure);
  if position('''comissaoFinanceiro''' in d) > 0 then return; end if;
  d := pg_temp.tb_trocar1(d, '''acompanharEntrega'', ''modoHomologacao'')', '''acompanharEntrega'', ''modoHomologacao'', ''comissaoFinanceiro'')');
  execute d;
end $do$;


-- ======================================================================
-- 63-ifood-loja-e-acesso.sql
-- ======================================================================
-- 63 · iFood: estado da loja e acesso, revisados pela documentação OFICIAL dos módulos Merchant e Authentication (PDFs do portal, 25/10/2026).
-- Versão 1.15. Pode rodar de novo sem erro.
-- 1) Estado da loja: o iFood devolve um estado por operação (DELIVERY, TAKEOUT…) com uma lista de validações.
--    Antes o motivo mostrado era o da 1ª validação (quase sempre "Conectado", que está OK). Agora mostra a validação com
--    problema, em português e com o que fazer; CLOSED (fora do horário) não é tratado como erro; ERROR que dura mais de
--    2 minutos avisa no celular (uma vez, até voltar ao normal); guarda se a loja pode ser reaberta (reopenable).
-- 2) Acesso recusado (401/403): o iFood pede para NÃO repetir sem parar. Agora, depois de uma recusa, o sistema espera
--    5 minutos antes de tentar de novo (ou tenta logo se alguém salvar Client ID / Client Secret / Merchant ID novos).

alter table public.ifood_loja add column if not exists erro_desde timestamptz;
alter table public.ifood_loja add column if not exists erro_avisado boolean not null default false;
alter table public.ifood_loja add column if not exists reabrir_pode boolean;
alter table public.ifood_loja add column if not exists problemas jsonb;

create or replace function public._ifood_validacao_txt(p_code text) returns text language sql immutable as $f$
  select case lower(coalesce(p_code, ''))
    when 'is-connected' then 'Sem conexão com o sistema: o iFood não recebeu a consulta dos últimos 30 s (o sistema consulta sozinho; confira se o iFood está ligado aqui).'
    when 'opening-hours' then 'Fora do horário de funcionamento cadastrado no iFood.'
    when 'unavailabilities' then 'Loja em PAUSA no iFood. Toque em "Retomar" (só remove as pausas feitas pelo sistema; as feitas no Portal do Parceiro saem por lá).'
    when 'radius-restriction' then 'Sem entregadores na área de entrega. Aumente a área no Portal do Parceiro ou aguarde.'
    when 'payout-blocked' then 'Pendência financeira com o iFood. Resolva no Portal do Parceiro → Financeiro.'
    when 'terms-service-violation' then 'Bloqueio por violação dos termos do iFood. Abra um chamado no Portal do Parceiro.'
    when 'logistics-blocked' then 'Problema logístico do iFood (externo). Aguarde a resolução.'
    when 'catalog-enabled' then 'Cardápio desabilitado no iFood. Ative um cardápio no Portal do Parceiro.'
    when 'delivery-area' then 'Sem área de entrega configurada. Configure no Portal do Parceiro.'
    else null end
$f$;

create or replace function public.ifood_loja_gravar(p_status jsonb, p_interrupcao text default null) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare v_lista jsonb; v_op jsonb; v_disp boolean; v_sit text; v_motivo text; v_prob jsonb; v_reab boolean; l ifood_loja%rowtype;
begin
  v_lista := case when jsonb_typeof(p_status) = 'array' then p_status when p_status is null then '[]'::jsonb else jsonb_build_array(p_status) end;
  -- a operação que importa: DELIVERY (entrega); se não houver, a primeira
  select x into v_op from jsonb_array_elements(v_lista) x order by (upper(coalesce(x->>'operation', '')) = 'DELIVERY') desc limit 1;
  v_op := coalesce(v_op, '{}'::jsonb);
  v_sit := upper(coalesce(v_op->>'state', v_op->>'status', ''));
  v_disp := coalesce((v_op->>'available')::boolean, v_sit in ('OK', 'AVAILABLE', 'OPEN'));
  -- validações com problema (WARNING / ERROR), com o texto do iFood e o nosso "o que fazer"
  select coalesce(jsonb_agg(jsonb_build_object('codigo', v->>'code', 'estado', v->>'state',
           'titulo', coalesce(v->'message'->>'title', v->>'message'), 'descricao', v->'message'->>'description',
           'oQueFazer', _ifood_validacao_txt(v->>'code'))), '[]'::jsonb)
    into v_prob
    from jsonb_array_elements(case when jsonb_typeof(v_op->'validations') = 'array' then v_op->'validations' else '[]'::jsonb end) v
   where upper(coalesce(v->>'state', 'OK')) not in ('OK', 'CLOSED');
  v_motivo := coalesce(
     (select string_agg(coalesce(p->>'oQueFazer', coalesce(p->>'titulo', p->>'codigo') || coalesce(': ' || (p->>'descricao'), '')), ' · ') from jsonb_array_elements(v_prob) p),
     case when v_sit = 'CLOSED' then 'Fechada no iFood: fora do horário de funcionamento (é o esperado).' end,
     nullif(coalesce(v_op->'message'->>'title', '') || coalesce(' — ' || (v_op->'message'->>'subtitle'), ''), ''),
     case when jsonb_typeof(v_op->'message') = 'string' then v_op->>'message' end, '');
  v_reab := case when v_op ? 'reopenable' then coalesce((v_op->'reopenable'->>'reopenable')::boolean, (v_op->>'reopenable')::boolean) end;
  if v_reab = false and v_sit = 'ERROR' then
    v_motivo := v_motivo || ' · A loja está sob penalidade automática do iFood (não dá para reabrir agora): veja a mensagem acima.';
  end if;
  select * into l from ifood_loja where id;
  update ifood_loja set situacao = left(v_sit, 60), disponivel = v_disp, motivo = left(v_motivo, 600), problemas = v_prob, reabrir_pode = v_reab,
    interrupcao_id = coalesce(p_interrupcao, interrupcao_id), verificado_em = now(), bruto = p_status, atualizado_em = now(),
    erro_desde = case when v_sit = 'ERROR' then coalesce(l.erro_desde, now()) else null end,
    erro_avisado = case when v_sit = 'ERROR' then l.erro_avisado else false end
   where id;
  if v_sit = 'ERROR' and l.erro_desde is null then
    perform _integ_log('ifood', 'aviso', 'Loja no iFood em ERRO: ' || left(v_motivo, 250));
  elsif v_sit = 'ERROR' and not l.erro_avisado and l.erro_desde < now() - interval '2 minutes' then
    update ifood_loja set erro_avisado = true where id;
    begin perform _push_admins('iFood: loja sem receber pedidos', left(v_motivo, 180), 'ifood-loja');
    exception when others then null; end;
  elsif v_sit <> 'ERROR' and l.erro_desde is not null then
    perform _integ_log('ifood', 'info', 'Loja no iFood voltou ao normal (' || coalesce(nullif(v_sit, ''), '?') || ').');
  end if;
end $function$;
revoke all on function public.ifood_loja_gravar(jsonb, text) from public, anon, authenticated;
grant execute on function public.ifood_loja_gravar(jsonb, text) to service_role;

-- 401/403: espera 5 min entre tentativas (o iFood pede para não repetir sem parar). Credencial nova salva = tenta já.
create or replace function public.ifood_pode_consultar() returns boolean
 language sql stable security definer set search_path to 'public' as $f$
  select not (coalesce(e.token_ok, true) = false
              and e.ultimo_erro_em > now() - interval '5 minutes'
              and coalesce((select max(atualizado_em) from integracoes_segredos where chave in ('ifood_client_id', 'ifood_client_secret', 'ifood_merchant_id')), '-infinity') < e.ultimo_erro_em)
  from ifood_estado e where e.id
$f$;
revoke all on function public.ifood_pode_consultar() from public, anon, authenticated;
grant execute on function public.ifood_pode_consultar() to service_role;


-- ======================================================================
-- 64-ifood-order-ajustes.sql
-- ======================================================================
-- 64 · iFood · Order: ajustes da homologação (Fase 1 do plano de 25/10/2026). Pode rodar de novo sem erro.
-- B3: o iFood só aceita "despachar" DEPOIS de "pronto para retirada". Se a equipe marcar "Saiu para entrega" sem ter marcado
--     "Pronta" antes, o sistema manda o "pronto" primeiro (a fila respeita a ordem de criação).
create or replace function public._ifood_trg_status() returns trigger
 language plpgsql security definer set search_path to 'public' as $function$
declare r ifood_pedidos%rowtype;
begin
  if new.canal is distinct from 'iFood' then return null; end if;
  if not public._integracao_ligada('ifood') then return null; end if;
  select * into r from ifood_pedidos where venda_id = new.id;
  if not found or r.simulado or r.estado in ('cancelado', 'concluido') then return null; end if;
  if new.status = 'Cancelada' and old.status is distinct from 'Cancelada' then
    perform public._ifood_enfileirar(r.pedido_ifood, 'cancelar', jsonb_build_object('motivo', coalesce(nullif(r.motivo_escolhido->>'descricao', ''), new.motivo_cancelamento), 'codigo', r.motivo_escolhido->>'codigo'));
  elsif new.status_pedido is distinct from old.status_pedido and new.status = 'Confirmada' then
    if new.status_pedido::text = 'Em preparo' then
      if r.estado = 'novo' then perform public._ifood_enfileirar(r.pedido_ifood, 'confirmar'); end if;
      perform public._ifood_enfileirar(r.pedido_ifood, 'iniciar_preparo');
    elsif new.status_pedido::text = 'Pronta' then
      perform public._ifood_enfileirar(r.pedido_ifood, 'pronto');
    elsif new.status_pedido::text = 'Saiu para entrega' and upper(coalesce(r.bruto->'delivery'->>'deliveredBy', '')) <> 'IFOOD' then
      if r.estado not in ('pronto', 'despachado')
         and not exists (select 1 from ifood_acoes a where a.pedido_ifood = r.pedido_ifood and a.acao = 'pronto' and a.estado in ('pendente', 'ok')) then
        perform public._ifood_enfileirar(r.pedido_ifood, 'pronto');
      end if;
      perform public._ifood_enfileirar(r.pedido_ifood, 'despachar');
    end if;
  end if;
  return null;
end $function$;


-- ===== B12 · Negociação do cliente (aceitar / recusar / contraproposta) conforme a documentação OFICIAL "Plataforma de negociação" =====
-- Guarda tudo que o iFood manda (ação, tipo, prazo e o que acontece se ninguém responder, fotos do cliente, motivos aceitos, itens, contrapropostas)
-- e o resultado final (HANDSHAKE_SETTLEMENT). A resposta exige o motivo oficial quando o iFood pede.
alter table public.ifood_negociacoes add column if not exists acao text;
alter table public.ifood_negociacoes add column if not exists grupo text;
alter table public.ifood_negociacoes add column if not exists mensagem text;
alter table public.ifood_negociacoes add column if not exists se_nao_responder text;
alter table public.ifood_negociacoes add column if not exists evidencias jsonb not null default '[]'::jsonb;
alter table public.ifood_negociacoes add column if not exists motivos_aceite jsonb not null default '[]'::jsonb;
alter table public.ifood_negociacoes add column if not exists itens jsonb not null default '[]'::jsonb;
alter table public.ifood_negociacoes add column if not exists resposta jsonb;
alter table public.ifood_negociacoes add column if not exists resultado text;
alter table public.ifood_negociacoes add column if not exists resultado_motivo text;
alter table public.ifood_negociacoes add column if not exists resultado_alternativa jsonb;
alter table public.ifood_negociacoes add column if not exists erro text;

create or replace function public.ifood_negociacao_registrar(p_evento jsonb, p_pedido text) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare m jsonb := coalesce(p_evento->'metadata', '{}'::jsonb); v_id text := coalesce(nullif(m->>'disputeId', ''), nullif(m->>'handshakeId', ''), nullif(p_evento->>'id', ''));
        v_exp timestamptz; v_num text; v_tipo text := coalesce(m->>'handshakeType', m->>'type'); v_acao text := m->>'action'; p_imagens jsonb := coalesce(p_evento->'_imagens', '[]'::jsonb);
begin
  begin v_exp := nullif(coalesce(m->>'expiresAt', m->>'expirationDate'), '')::timestamptz; exception when others then v_exp := null; end;
  insert into ifood_negociacoes (id, pedido_ifood, tipo, acao, grupo, mensagem, se_nao_responder, motivo, expira_em, alternativas, evidencias, motivos_aceite, itens, bruto)
  values (v_id, p_pedido, v_tipo, v_acao, m->>'handshakeGroup', left(coalesce(m->>'message', ''), 500), m->>'timeoutAction',
          left(coalesce(m->>'message', m->>'reason', m->>'handshakeGroup', ''), 300), coalesce(v_exp, now() + interval '5 minutes'),
          case when jsonb_typeof(m->'alternatives') = 'array' then m->'alternatives' else '[]'::jsonb end,
          case when jsonb_typeof(p_imagens) = 'array' then p_imagens else '[]'::jsonb end,
          case when jsonb_typeof(m->'acceptCancellationReasons') = 'array' then m->'acceptCancellationReasons' else '[]'::jsonb end,
          case when jsonb_typeof(m->'items') = 'array' then m->'items' when jsonb_typeof(m->'item') = 'array' then m->'item' else '[]'::jsonb end,
          p_evento)
  on conflict (id) do nothing;
  if found then
    select numero_ifood into v_num from ifood_pedidos where pedido_ifood = p_pedido;
    perform _push_enviar('pedido', '⚠️ iFood: cliente pediu ' || case upper(coalesce(v_tipo, '')) when 'DELAY' then 'cancelar por atraso' when 'PREPARATION_TIME' then 'cancelar durante o preparo'
        when 'AFTER_DELIVERY_PARTIALLY' then 'reembolso parcial' else 'cancelamento/reembolso' end || ' #' || coalesce(v_num, ''),
      'Responda no painel (Integrações → iFood) antes do prazo. Se ninguém responder: ' || case upper(coalesce(m->>'timeoutAction', '')) when 'ACCEPT_CANCELLATION' then 'o iFood CANCELA o pedido.' when 'REJECT_CANCELLATION' then 'o iFood recusa o pedido do cliente.' else 'o iFood decide.' end,
      'ifood-neg-' || v_id);
    perform _integ_log('ifood', 'aviso', 'Negociação de cancelamento no pedido #' || coalesce(v_num, p_pedido));
    perform _auditar('Negociação do iFood recebida', 'Pedido iFood #' || coalesce(v_num, p_pedido) || ' · ' || coalesce(v_tipo, '') || ' · ' || coalesce(v_acao, ''));
  end if;
  return jsonb_build_object('ok', true);
end $function$;
revoke all on function public.ifood_negociacao_registrar(jsonb, text) from public, anon, authenticated;
grant execute on function public.ifood_negociacao_registrar(jsonb, text) to service_role;

-- resultado final (HANDSHAKE_SETTLEMENT): ACCEPTED / REJECTED / EXPIRED / ALTERNATIVE_REPLIED
create or replace function public.ifood_negociacao_fim(p_evento jsonb, p_pedido text) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare m jsonb := coalesce(p_evento->'metadata', '{}'::jsonb); v_id text := coalesce(nullif(m->>'disputeId', ''), nullif(m->>'handshakeId', ''));
        v_st text := upper(coalesce(m->>'status', '')); v_n text; v_num text;
begin
  if v_id is null then select id into v_id from ifood_negociacoes where pedido_ifood = p_pedido order by criado_em desc limit 1; end if;
  update ifood_negociacoes set
      estado = case when v_st = 'EXPIRED' and estado = 'aberta' then 'expirada'
                    when estado = 'aberta' then case v_st when 'ACCEPTED' then 'aceita' when 'REJECTED' then 'recusada' when 'ALTERNATIVE_REPLIED' then 'alternativa' else 'encerrada' end
                    else estado end,
      resultado = nullif(v_st, ''), resultado_motivo = left(nullif(m->>'reason', ''), 300),
      resultado_alternativa = case when jsonb_typeof(m->'selectedDisputeAlternative') = 'object' then m->'selectedDisputeAlternative' else resultado_alternativa end,
      respondido_em = coalesce(respondido_em, now())
   where id = v_id;
  select numero_ifood into v_num from ifood_pedidos where pedido_ifood = p_pedido;
  perform _integ_log('ifood', case when v_st = 'EXPIRED' then 'aviso' else 'info' end,
    'Negociação do pedido #' || coalesce(v_num, p_pedido) || ' encerrada: ' || case v_st when 'ACCEPTED' then 'aceita' when 'REJECTED' then 'recusada' when 'EXPIRED' then 'prazo acabou (o iFood aplicou a ação automática)'
       when 'ALTERNATIVE_REPLIED' then 'contraproposta enviada' else coalesce(nullif(v_st, ''), '?') end);
end $function$;
revoke all on function public.ifood_negociacao_fim(jsonb, text) from public, anon, authenticated;
grant execute on function public.ifood_negociacao_fim(jsonb, text) to service_role;

-- a Edge Function avisa quando o iFood recusou a resposta (a pessoa precisa ver o motivo)
create or replace function public.ifood_negociacao_erro(p_id text, p_erro text) returns void
 language plpgsql security definer set search_path to 'public' as $f$
begin
  update ifood_negociacoes set erro = left(p_erro, 300),
         estado = case when estado in ('aceita', 'recusada', 'alternativa') and resultado is null then 'aberta' else estado end
   where id = p_id;
  perform _integ_log('ifood', 'erro', 'iFood recusou a resposta da negociação: ' || left(p_erro, 200));
end $f$;
revoke all on function public.ifood_negociacao_erro(text, text) from public, anon, authenticated;
grant execute on function public.ifood_negociacao_erro(text, text) to service_role;

create or replace function public.api_ifood_negociacao_responder(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare n ifood_negociacoes%rowtype; v_acao text := p->>'acao'; v_login text; v_mot text := upper(nullif(btrim(coalesce(p->>'motivo', '')), '')); v_alt jsonb; v_tipo text;
        v_max numeric; v_valor numeric; v_min int; v_dados jsonb;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select * into n from ifood_negociacoes where id = p->>'id' for update;
  if not found then return _falha('Negociação não encontrada.'); end if;
  if n.estado <> 'aberta' then return _falha('Esta negociação já foi respondida ou encerrada.'); end if;
  if n.expira_em < now() then return _falha('O prazo para responder acabou; o iFood aplica a ação automática (' ||
       case upper(coalesce(n.se_nao_responder, '')) when 'ACCEPT_CANCELLATION' then 'cancelar o pedido' when 'REJECT_CANCELLATION' then 'recusar o pedido do cliente' else 'o iFood decide' end || ').'); end if;
  if v_acao not in ('aceitar', 'recusar', 'alternativa') then return _falha('Resposta inválida.'); end if;
  v_dados := jsonb_build_object('disputa', n.id, 'detalhe', left(coalesce(p->>'detalhe', ''), 250));
  if v_acao = 'aceitar' then
    if jsonb_array_length(n.motivos_aceite) > 0 or upper(coalesce(n.tipo, '')) = 'DELAY' then
      if v_mot is null then return _falha('Escolha o motivo para aceitar o cancelamento.'); end if;
      if jsonb_array_length(n.motivos_aceite) > 0 and not exists (select 1 from jsonb_array_elements_text(n.motivos_aceite) x where upper(x) = v_mot) then
        return _falha('Esse motivo não é aceito pelo iFood nesta negociação. Escolha um da lista.'); end if;
    end if;
    v_dados := v_dados || jsonb_build_object('motivo', v_mot);
  elsif v_acao = 'recusar' then
    if v_mot is null or v_mot not in ('HIGH_STORE_DEMAND', 'UNKNOWN_ISSUE', 'CUSTOMER_SATISFACTION', 'INVENTORY_CHECK', 'SYSTEM_ISSUE', 'WRONG_ORDER', 'PRODUCT_QUALITY', 'LATE_DELIVERY') then
      return _falha('Escolha o motivo da recusa.'); end if;
    v_dados := v_dados || jsonb_build_object('motivo', v_mot);
  else
    select a into v_alt from jsonb_array_elements(n.alternativas) a where a->>'id' = p->>'alternativaId' limit 1;
    if v_alt is null then return _falha('Escolha uma contraproposta da lista.'); end if;
    v_tipo := upper(coalesce(v_alt->>'type', ''));
    if v_tipo in ('REFUND', 'BENEFIT') then
      v_max := nullif(coalesce(v_alt->'metadata'->'maxAmount'->>'value', v_alt->'metadata'->>'maxAmount'), '')::numeric;   -- o iFood manda em centavos
      begin v_valor := replace(coalesce(p->>'valor', ''), ',', '.')::numeric; exception when others then v_valor := null; end;
      if v_valor is null or v_valor <= 0 then return _falha('Informe o valor do reembolso (R$).'); end if;
      if v_max is not null and round(v_valor * 100) > v_max then return _falha('O valor passa do máximo permitido: R$ ' || to_char(v_max / 100, 'FM999990D00') || '.'); end if;
      v_dados := v_dados || jsonb_build_object('tipo', v_tipo, 'valorCentavos', round(v_valor * 100));
    elsif v_tipo = 'ADDITIONAL_TIME' then
      begin v_min := (p->>'minutos')::int; exception when others then v_min := null; end;
      if v_min is null or v_min <= 0 then return _falha('Escolha quantos minutos a mais.'); end if;
      if jsonb_typeof(v_alt->'metadata'->'allowedsAdditionalTimeInMinutes') = 'array'
         and not exists (select 1 from jsonb_array_elements_text(v_alt->'metadata'->'allowedsAdditionalTimeInMinutes') x where x::int = v_min) then
        return _falha('O iFood só aceita estes minutos: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_alt->'metadata'->'allowedsAdditionalTimeInMinutes') x) || '.'); end if;
      v_dados := v_dados || jsonb_build_object('tipo', v_tipo, 'minutos', v_min, 'motivo', coalesce(v_mot, 'HIGH_STORE_DEMAND'));
    else return _falha('Tipo de contraproposta não reconhecido: ' || coalesce(v_tipo, '?')); end if;
    v_dados := v_dados || jsonb_build_object('alternativaId', p->>'alternativaId');
  end if;
  select login into v_login from usuarios where id = auth.uid();
  update ifood_negociacoes set estado = case v_acao when 'aceitar' then 'aceita' when 'recusar' then 'recusada' else 'alternativa' end, respondido_em = now(), resposta_por = v_login, erro = null,
         resposta = jsonb_build_object('acao', v_acao) || v_dados where id = n.id;
  perform public._ifood_enfileirar(n.pedido_ifood, 'negociacao_' || v_acao, v_dados);
  perform _auditar('Negociação do iFood respondida', 'Pedido ' || n.pedido_ifood || ' · ' || v_acao || coalesce(' · ' || v_mot, '') || ' por ' || coalesce(v_login, ''));
  return jsonb_build_object('ok', true, 'message', 'Resposta enviada ao iFood. O resultado aparece aqui quando o iFood confirmar.') || api_ifood_negociacoes('{}');
end $function$;

create or replace function public.api_ifood_negociacoes(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'itens', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'pedido', i.numero_ifood, 'tipo', n.tipo, 'acao', n.acao, 'motivo', n.motivo, 'mensagem', n.mensagem,
      'expiraEm', n.expira_em, 'segundos', greatest(0, round(extract(epoch from (n.expira_em - now())))), 'estado', n.estado, 'alternativas', n.alternativas,
      'seNaoResponder', n.se_nao_responder, 'fotos', n.evidencias, 'motivosAceite', n.motivos_aceite, 'itens', n.itens,
      'resultado', n.resultado, 'resultadoMotivo', n.resultado_motivo, 'resultadoAlternativa', n.resultado_alternativa, 'erro', n.erro, 'respostaPor', n.resposta_por, 'em', n.criado_em) order by n.criado_em desc)
    from (select * from ifood_negociacoes order by criado_em desc limit 15) n left join ifood_pedidos i on i.pedido_ifood = n.pedido_ifood), '[]'::jsonb));
end $function$;


-- ======================================================================
-- 65-ifood-eventos-e-pedido.sql
-- ======================================================================
-- 65 · iFood: eventos e detalhes do pedido, revisados pela documentação OFICIAL dos módulos Order e Events (PDFs do portal, 25/10/2026).
-- Versão 1.16. Pode rodar de novo sem erro.
-- 1) AVISOS do iFood (tabela + painel): o iFood recusou o cancelamento (CARF), o cliente alterou o pedido (ORDER_PATCHED), mudou o endereço (DAR),
--    pediu código de devolução (DRCR), pedido voltando/voltou para a loja, "comece o preparo às HH:MM" (RPS), vaga de retirada (PICKUP_AREA_ASSIGNED).
--    Cada aviso também vai para o celular da equipe (push). Nada fica calado.
-- 2) Eventos processados na ORDEM em que o iFood os criou (createdAt), não na ordem em que chegaram.
-- 3) 5 falhas seguidas ao falar com o iFood = alerta no celular (uma vez) até voltar ao normal.
-- 4) Detalhes do pedido: pedido de teste do iFood, CPF/CNPJ, TURBO, código do entregador, vaga de retirada, taxas do iFood,
--    carteira digital; agendado: "comece o preparo às…"
--    e o prazo de 8 min para confirmar passa a contar do início do preparo.
-- 5) Rastreio do entregador (só entrega do iFood, depois de o entregador ser escalado, no máximo 1 vez a cada 30 s por pedido).

alter table public.ifood_estado add column if not exists falhas_seguidas integer not null default 0;
alter table public.ifood_estado add column if not exists falhas_avisado boolean not null default false;

create table if not exists public.ifood_avisos (
  id bigserial primary key,
  pedido_ifood text,
  numero text,
  tipo text not null,
  titulo text not null,
  mensagem text not null default '',
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  visto_em timestamptz,
  visto_por text
);
create index if not exists ifood_avisos_aberto_idx on public.ifood_avisos (criado_em desc) where visto_em is null;
alter table public.ifood_avisos enable row level security;
revoke all on table public.ifood_avisos from anon, authenticated;

create or replace function public.ifood_aviso_registrar(p_pedido text, p_tipo text, p_titulo text, p_msg text, p_dados jsonb default '{}'::jsonb) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare v_num text;
begin
  select numero_ifood into v_num from ifood_pedidos where pedido_ifood = p_pedido;
  insert into ifood_avisos (pedido_ifood, numero, tipo, titulo, mensagem, dados) values (p_pedido, v_num, p_tipo, left(p_titulo, 160), left(coalesce(p_msg, ''), 500), coalesce(p_dados, '{}'::jsonb));
  perform _integ_log('ifood', 'aviso', 'Pedido #' || coalesce(v_num, p_pedido, '?') || ': ' || left(p_titulo, 120));
  begin perform _push_enviar('pedido', left(p_titulo || case when v_num is not null then ' · #' || v_num else '' end, 120), left(coalesce(p_msg, 'Veja o painel do iFood'), 180), 'ifood-av-' || p_tipo || '-' || coalesce(p_pedido, '') || '-' || extract(epoch from now())::bigint);
  exception when others then null; end;
end $f$;
revoke all on function public.ifood_aviso_registrar(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.ifood_aviso_registrar(text, text, text, text, jsonb) to service_role;

create or replace function public.api_ifood_avisos(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'abertos', (select count(*) from ifood_avisos where visto_em is null and criado_em > now() - interval '7 days'),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'pedido', a.numero, 'tipo', a.tipo, 'titulo', a.titulo, 'mensagem', a.mensagem, 'dados', a.dados,
        'em', a.criado_em, 'visto', a.visto_em is not null, 'vistoPor', a.visto_por) order by a.criado_em desc)
      from (select * from ifood_avisos where criado_em > now() - interval '7 days' order by (visto_em is null) desc, criado_em desc limit 40) a), '[]'::jsonb));
end $f$;
grant execute on function public.api_ifood_avisos(jsonb) to authenticated;

create or replace function public.api_ifood_aviso_visto(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_login text;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select login into v_login from usuarios where id = auth.uid();
  if coalesce(p->>'todos', '') = 'true' then update ifood_avisos set visto_em = now(), visto_por = v_login where visto_em is null;
  else update ifood_avisos set visto_em = now(), visto_por = v_login where id = nullif(p->>'id', '')::bigint and visto_em is null; end if;
  return jsonb_build_object('ok', true) || api_ifood_avisos('{}');
end $f$;
grant execute on function public.api_ifood_aviso_visto(jsonb) to authenticated;

-- eventos na ordem de criação no iFood (a API entrega fora de ordem)
create or replace function public.ifood_eventos_pendentes() returns jsonb
 language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'codigo', coalesce(codigo_completo, codigo), 'pedido', pedido_ifood, 'tentativas', tentativas, 'bruto', bruto) order by coalesce(criado_ifood, recebido_em), recebido_em), '[]'::jsonb)
  from (select * from ifood_eventos where processado_em is null and recebido_em > now() - interval '1 day' order by coalesce(criado_ifood, recebido_em), recebido_em limit 50) x
$f$;

-- 5 falhas seguidas ao consultar o iFood: avisa a equipe (uma vez); volta ao normal = zera
create or replace function public.ifood_marcar_consulta(p_ok boolean, p_erro text default null, p_token_ok boolean default null) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare v_ant timestamptz; v_id bigint; v_f int; v_av boolean;
begin
  select ultima_consulta_ok into v_ant from ifood_estado where id;
  update ifood_estado set ultima_consulta = now(),
    ultima_consulta_ok = case when p_ok then now() else ultima_consulta_ok end,
    token_ok = coalesce(p_token_ok, token_ok),
    ultimo_erro = case when p_ok then null else left(p_erro, 300) end,
    ultimo_erro_em = case when p_ok then ultimo_erro_em else now() end,
    falhas_seguidas = case when p_ok then 0 else falhas_seguidas + 1 end,
    falhas_avisado = case when p_ok then false else falhas_avisado end,
    atualizado_em = now() where id
  returning falhas_seguidas, falhas_avisado into v_f, v_av;
  if not p_ok and p_erro is not null then perform public._integ_log('ifood', 'erro', p_erro); end if;
  if not p_ok and v_f >= 5 and not v_av then
    update ifood_estado set falhas_avisado = true where id;
    begin perform _alertas_push('iFood: sem conseguir falar com o iFood',
      '5 tentativas seguidas falharam: ' || left(coalesce(p_erro, 'sem detalhe'), 140) || '. Pedidos novos podem demorar a aparecer: confira no portal do iFood.', 'ifood-falhas', array['Admin', 'Operador']);
    exception when others then null; end;
  end if;
  -- lacuna só conta se a última consulta boa foi DEPOIS de o iFood ser ligado (ligar de novo após desligar não é queda)
  if p_ok and v_ant is not null and now() - v_ant > interval '3 minutes' and now() - v_ant < interval '3 days'
     and v_ant >= coalesce((select ligado_em from integracoes_config where provedor = 'ifood'), '-infinity'::timestamptz) then
    insert into ifood_lacunas(inicio, fim) values (v_ant, now()) returning id into v_id;
    perform _ifood_lacuna_varrer(v_id);
    begin
      perform _alertas_push('iFood: sistema ficou fora do ar',
        'De ' || to_char(v_ant at time zone 'America/Sao_Paulo', 'HH24:MI') || ' às ' || to_char(now() at time zone 'America/Sao_Paulo', 'HH24:MI') || ' o iFood não conseguiu entregar pedidos. Confira no portal do iFood.',
        'ifood-lacuna', array['Admin', 'Operador']);
    exception when others then null; end;
  end if;
end $function$;

-- endereço novo (cliente mudou a entrega): atualiza a venda e avisa para repassar ao entregador
create or replace function public.ifood_endereco_atualizar(p_order jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare r ifood_pedidos%rowtype; ad jsonb; v_end text;
begin
  select * into r from ifood_pedidos where pedido_ifood = p_order->>'id';
  if not found or r.venda_id is null then return jsonb_build_object('ok', true, 'ignorado', true); end if;
  ad := coalesce(p_order->'delivery'->'deliveryAddress', '{}'::jsonb);
  v_end := coalesce(nullif(ad->>'formattedAddress', ''), btrim(concat_ws(', ', ad->>'streetName', ad->>'streetNumber', ad->>'neighborhood', ad->>'city')));
  if coalesce(v_end, '') = '' then return jsonb_build_object('ok', true, 'ignorado', true); end if;
  update vendas set endereco = v_end, complemento = coalesce(ad->>'complement', ''), referencia = coalesce(ad->>'reference', '') where id = r.venda_id and tipo::text = 'Entrega';
  update ifood_pedidos set bruto = p_order, atualizado_em = now() where pedido_ifood = r.pedido_ifood;
  perform _auditar('Endereço do pedido do iFood mudou', 'iFood #' || coalesce(r.numero_ifood, '') || ' · ' || left(v_end, 150));
  return jsonb_build_object('ok', true, 'endereco', v_end);
end $f$;
revoke all on function public.ifood_endereco_atualizar(jsonb) from public, anon, authenticated;
grant execute on function public.ifood_endereco_atualizar(jsonb) to service_role;

-- detalhes extras do pedido que aparecem na observação (comanda): pagamento, cupom (quem paga), retirada, TURBO, código do entregador, CPF/CNPJ, taxas
create or replace function public._ifood_extras_obs(p_order jsonb) returns text
 language plpgsql stable set search_path to 'public' as $function$
declare m jsonb; b jsonb; s jsonb; f jsonb; v_txt text := ''; v_tipo text; v_ifood numeric := 0; v_loja numeric := 0; v_outros numeric := 0; v_n numeric; v_ret text; v_t timestamptz; v_doc text; v_nome text; v_taxas text := '';
begin
  if lower(coalesce(p_order->>'isTest', '')) = 'true' then v_txt := v_txt || ' · PEDIDO DE TESTE DO iFOOD'; end if;
  for m in select * from jsonb_array_elements(coalesce(p_order->'payments'->'methods', '[]'::jsonb)) loop
    v_tipo := upper(coalesce(m->>'method', ''));
    if v_tipo in ('CREDIT', 'DEBIT', 'MEAL_VOUCHER', 'FOOD_VOUCHER') or m ? 'card' then
      v_txt := v_txt || ' · Cartão ' || case v_tipo when 'CREDIT' then 'CRÉDITO' when 'DEBIT' then 'DÉBITO' when 'MEAL_VOUCHER' then 'VALE-REFEIÇÃO' when 'FOOD_VOUCHER' then 'VALE-ALIMENTAÇÃO' else v_tipo end
        || coalesce(' ' || upper(nullif(m->'card'->>'brand', '')), '')
        || case when upper(coalesce(m->>'type', '')) = 'OFFLINE' then ' (cobrar na entrega: levar maquininha)' else ' (pago no app)' end;
    elsif m ? 'wallet' or v_tipo in ('DIGITAL_WALLET', 'WALLET') then
      v_txt := v_txt || ' · Carteira digital' || coalesce(' ' || upper(nullif(m->'wallet'->>'name', '')), '') || ' (pago no app)';
    end if;
  end loop;
  for b in select * from jsonb_array_elements(coalesce(p_order->'benefits', '[]'::jsonb)) loop
    for s in select * from jsonb_array_elements(coalesce(b->'sponsorshipValues', '[]'::jsonb)) loop
      v_n := coalesce(nullif(s->>'value', '')::numeric, 0);
      if upper(coalesce(s->>'name', '')) = 'IFOOD' then v_ifood := v_ifood + v_n;
      elsif upper(coalesce(s->>'name', '')) = 'MERCHANT' then v_loja := v_loja + v_n;
      else v_outros := v_outros + v_n; end if;   -- EXTERNAL (indústria/parceiro) e CHAIN (rede): quem paga é outro, o iFood repassa
    end loop;
  end loop;
  if v_ifood + v_loja + v_outros > 0 then
    v_txt := v_txt || ' · Cupom: ' || concat_ws(' + ',
      case when v_ifood > 0 then 'R$ ' || replace(to_char(v_ifood, 'FM9999990.00'), '.', ',') || ' pago pelo iFood' end,
      case when v_loja > 0 then 'R$ ' || replace(to_char(v_loja, 'FM9999990.00'), '.', ',') || ' pago pela loja' end,
      case when v_outros > 0 then 'R$ ' || replace(to_char(v_outros, 'FM9999990.00'), '.', ',') || ' pago por parceiro/rede' end);
  end if;
  -- taxas do iFood (ex.: pedido pequeno): receita do iFood, não entra na nota fiscal
  for f in select * from jsonb_array_elements(case when jsonb_typeof(p_order->'additionalFees') = 'array' then p_order->'additionalFees' else '[]'::jsonb end) loop
    v_n := coalesce(nullif(f->>'value', '')::numeric, 0);
    if v_n > 0 then v_taxas := v_taxas || case when v_taxas = '' then '' else ' + ' end || coalesce(nullif(f->>'description', ''), nullif(f->>'type', ''), 'taxa') || ' R$ ' || replace(to_char(v_n, 'FM9999990.00'), '.', ','); end if;
  end loop;
  if v_taxas <> '' then v_txt := v_txt || ' · Taxa do iFood (paga pelo cliente ao iFood): ' || v_taxas; end if;
  -- CPF/CNPJ na nota (cliente pediu)
  v_doc := regexp_replace(coalesce(p_order->'customer'->>'documentNumber', ''), '[^0-9]', '', 'g');
  if length(v_doc) = 14 then v_txt := v_txt || ' · CNPJ na nota: ' || v_doc;
  elsif length(v_doc) = 11 then v_txt := v_txt || ' · CPF na nota: ' || v_doc; end if;
  -- entrega
  if upper(coalesce(p_order->'delivery'->>'mode', '')) = 'TURBO' then v_txt := v_txt || ' · ⚡ TURBO: preparar em até 7 minutos'; end if;
  if nullif(p_order->'delivery'->>'pickupCode', '') is not null then v_txt := v_txt || ' · Código do entregador: ' || (p_order->'delivery'->>'pickupCode'); end if;
  if upper(coalesce(p_order->>'orderType', '')) = 'TAKEOUT' then
    v_ret := coalesce(p_order->'takeout'->>'takeoutDateTime', '');
    begin v_t := nullif(v_ret, '')::timestamptz; exception when others then v_t := null; end;
    if v_t is not null then v_txt := v_txt || ' · RETIRADA ' || case when upper(coalesce(p_order->'takeout'->>'mode', '')) = 'SCHEDULED' then 'AGENDADA' else '' end || ' às ' || to_char(v_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'); end if;
    if upper(coalesce(p_order->'takeout'->>'mode', '')) = 'PICKUP_AREA' then v_txt := v_txt || ' · Retirada em vaga/área do cliente (a vaga chega em aviso)'; end if;
  end if;
  return v_txt;
exception when others then return '';
end $function$;

-- rastreio do entregador: só entrega do iFood, depois de o entregador ser escalado, no máximo 1 vez a cada 30 s por pedido (regra da documentação)
create or replace function public.ifood_rastreio_pendentes() returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not coalesce((select (config->>'acompanharEntrega')::boolean from integracoes_config where provedor = 'ifood'), false) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(i.pedido_ifood) from (
    select i.pedido_ifood from ifood_pedidos i join vendas v on v.id = i.venda_id
     where not i.simulado and v.status = 'Confirmada' and v.tipo::text = 'Entrega' and v.status_pedido::text in ('Pronta', 'Saiu para entrega')
       and coalesce(v.observacoes_entrega, '') ilike '%ENTREGA PELO iFOOD%'
       and (i.rastreio_em is null or i.rastreio_em < now() - interval '30 seconds')
       and exists (select 1 from ifood_eventos e where e.pedido_ifood = i.pedido_ifood and (upper(e.codigo) = 'ADR' or upper(e.codigo_completo) = 'ASSIGN_DRIVER'))
     order by v.data_hora limit 3) i), '[]'::jsonb);
end $function$;

-- pedido agendado: "comece o preparo às HH:MM" na observação; o prazo de 8 min para confirmar conta a partir do início do preparo (doc oficial)
create or replace function public.ifood_criar_pedido(p_order jsonb, p_simulado boolean default false) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare
  v_id text := p_order->>'id'; v_disp text := coalesce(nullif(p_order->>'displayId', ''), right(coalesce(p_order->>'id', ''), 4));
  v_venda uuid := gen_random_uuid(); v_tipo venda_tipo; v_nome text; v_tel text; v_end text; v_comp text; v_ref text; v_obs text;
  v_val jsonb; v_total numeric; v_sem int; v_caixa uuid; v_numero int; v_troco numeric; v_agend text; v_forma text; v_pend numeric; v_cash numeric; v_stpag status_pagamento; ad jsonb; v_cpf text; v_okdata timestamptz;
  v_prep timestamptz; v_expira timestamptz := now() + interval '8 minutes';
begin
  if v_id is null then return jsonb_build_object('ok', false, 'message', 'Pedido sem id.'); end if;
  if exists (select 1 from ifood_pedidos where pedido_ifood = v_id) then return jsonb_build_object('ok', true, 'duplicado', true); end if;
  if jsonb_typeof(p_order->'items') is distinct from 'array' or jsonb_array_length(p_order->'items') = 0 then return jsonb_build_object('ok', false, 'message', 'Pedido sem itens.'); end if;
  v_tipo := case when upper(coalesce(p_order->>'orderType', '')) in ('TAKEOUT', 'PICKUP', 'INDOOR') then 'Retirada' else 'Entrega' end::venda_tipo;
  v_nome := left(btrim(coalesce(p_order->'customer'->>'name', 'Cliente iFood')), 80) || ' (iFood)';
  v_tel := left(regexp_replace(coalesce(p_order->'customer'->'phone'->>'number', ''), '[^0-9]', '', 'g'), 20);
  ad := coalesce(p_order->'delivery'->'deliveryAddress', '{}'::jsonb);
  v_end := coalesce(nullif(ad->>'formattedAddress', ''), btrim(concat_ws(', ', ad->>'streetName', ad->>'streetNumber', ad->>'neighborhood', ad->>'city')));
  v_comp := coalesce(ad->>'complement', ''); v_ref := coalesce(ad->>'reference', '');
  v_cpf := regexp_replace(coalesce(p_order->'customer'->>'documentNumber', ''), '[^0-9]', '', 'g');
  if not public._cpf_valido(v_cpf) then v_cpf := null; end if;
  v_val := public._ifood_valores(p_order);
  v_total := (v_val->>'total')::numeric;
  v_pend := public._ifood_n(p_order->'payments'->'pending');
  v_cash := case when (v_val->>'entregaIfood')::boolean then 0 else round(least(greatest(v_pend, 0), v_total), 2) end;
  v_stpag := case when v_cash > 0.009 then 'A Receber' else 'Pago' end;
  v_forma := case when v_cash > 0.009 and v_total - v_cash > 0.009 then 'iFood (pago no app) + iFood (pagar na entrega)' when v_cash > 0.009 then 'iFood (pagar na entrega)' else 'iFood (pago no app)' end;
  v_obs := 'iFood #' || v_disp;
  if v_tipo = 'Entrega' and (v_val->>'entregaIfood')::boolean then v_obs := v_obs || ' · ENTREGA PELO iFOOD'; end if;
  select (m->'cash'->>'changeFor') into v_troco from jsonb_array_elements(coalesce(p_order->'payments'->'methods', '[]'::jsonb)) m where m->'cash'->>'changeFor' is not null limit 1;
  if v_troco is not null and public._ifood_n(to_jsonb(v_troco)) > 0 and upper(coalesce(p_order->'delivery'->>'deliveredBy', '')) = 'MERCHANT' then v_obs := v_obs || ' · levar troco para R$ ' || replace(to_char(public._ifood_n(to_jsonb(v_troco)), 'FM9999990.00'), '.', ','); end if;
  if upper(coalesce(p_order->>'orderTiming', '')) = 'SCHEDULED' then
    v_agend := coalesce(p_order->'schedule'->>'deliveryDateTimeStart', p_order->'delivery'->>'deliveryDateTime', p_order->>'preparationStartDateTime', '');
    begin v_okdata := nullif(v_agend, '')::timestamptz; exception when others then v_okdata := null; end;
    v_obs := v_obs || ' · AGENDADO' || case when v_okdata is not null then ' para ' || to_char(v_okdata at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') else '' end;
    begin v_prep := nullif(p_order->>'preparationStartDateTime', '')::timestamptz; exception when others then v_prep := null; end;
    if v_prep is not null then
      v_obs := v_obs || ' · COMECE O PREPARO ÀS ' || to_char(v_prep at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI');
      if v_prep > now() then v_expira := v_prep + interval '8 minutes'; end if;
    end if;
  end if;
  if nullif(btrim(coalesce(p_order->'delivery'->>'observations', '')), '') is not null then v_obs := v_obs || ' · ' || btrim(p_order->'delivery'->>'observations'); end if;
  v_obs := v_obs || public._ifood_extras_obs(p_order);
  if p_simulado then v_obs := v_obs || ' · TESTE (simulação)'; end if;
  select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;

  insert into vendas (id, cliente_nome, telefone_cliente, forma_pagamento, valor_total, custo_total, status, tipo, status_pedido, endereco, complemento, referencia, observacoes_entrega,
                      status_pagamento, cpf_nota, recebido_em, valor_original, valor_desconto, desconto_detalhe, origem, taxa_entrega, caixa_id, requisicao_id, canal)
  values (v_venda, v_nome, nullif(v_tel, ''), v_forma, v_total, 0, 'Confirmada', v_tipo, 'Recebido',
          case when v_tipo = 'Entrega' then coalesce(v_end, '') else '' end, case when v_tipo = 'Entrega' then v_comp else '' end, case when v_tipo = 'Entrega' then v_ref else '' end, v_obs,
          v_stpag, v_cpf, case when v_stpag = 'Pago' then now() end, (v_val->>'original')::numeric, (v_val->>'descontoLoja')::numeric,
          case when (v_val->>'descontoLoja')::numeric > 0 then 'Desconto/cupom iFood pago pela loja' else '' end, 'Balcão', (v_val->>'taxaEntrega')::numeric, v_caixa, 'ifood:' || v_id, 'iFood')
  returning numero_pedido into v_numero;
  if not p_simulado then
    begin perform public._ifood_cliente(v_venda, p_order);
    exception when others then perform _integ_log('ifood', 'aviso', 'Pedido #' || v_disp || ': cliente não cadastrado (' || left(sqlerrm, 150) || ')'); end;
  end if;

  v_sem := public._ifood_gravar_itens(v_venda, p_order, false);
  update vendas set custo_total = coalesce((select sum(custo_unitario * quantidade) from itens_venda where venda_id = v_venda), 0) where id = v_venda;

  perform public._ifood_gravar_pagamentos(v_venda, p_order, v_total, (v_val->>'entregaIfood')::boolean);

  insert into ifood_pedidos (pedido_ifood, venda_id, numero_ifood, estado, expira_em, itens_sem_ligacao, simulado, bruto)
  values (v_id, v_venda, v_disp, 'novo', v_expira, v_sem, p_simulado, p_order);
  update ifood_estado set ultimo_pedido_em = now(), atualizado_em = now() where id;
  perform _auditar('Pedido do iFood recebido', 'iFood #' || v_disp || ' → venda #' || v_numero || ' · R$ ' || replace(to_char(v_total, 'FM9999990.00'), '.', ',') || case when v_sem > 0 then ' · ' || v_sem || ' item(ns) sem ligação' else '' end || case when p_simulado then ' · SIMULAÇÃO' else '' end, null);
  perform _integ_log('ifood', case when v_sem > 0 then 'aviso' else 'info' end, 'Pedido #' || v_disp || ' recebido' || case when v_sem > 0 then ' (' || v_sem || ' item sem ligação)' else '' end);
  if upper(coalesce(p_order->'delivery'->>'mode', '')) = 'TURBO' then
    perform public.ifood_aviso_registrar(v_id, 'turbo', '⚡ Pedido TURBO: preparar em até 7 minutos', 'O iFood promete esse pedido rápido. Comece já.', '{}'::jsonb);
  end if;
  return jsonb_build_object('ok', true, 'vendaId', v_venda, 'numero', v_numero, 'semLigacao', v_sem);
end $function$;


-- ======================================================================
-- 66-ifood-catalogo-v2.sql
-- ======================================================================
-- 66 · iFood Catálogo v2 (v1.17) — revisado pela documentação oficial do módulo Catalog. Pode rodar de novo sem erro.
-- 1) Nova ação "catalogo_diagnostico": pergunta ao iFood por que itens NÃO aparecem no app (unsellableItems).
-- 2) Tabela ifood_cat_diag (guarda o último diagnóstico) + funções de leitura/pedido.
-- 3) Validações ao salvar: nome ≤ 100, descrição ≤ 500, preço do item > 0, mínimo ≤ máximo, tipo do grupo, combo.

alter table public.ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table public.ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar','negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler','catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','catalogo_modelo_enviar','catalogo_lote_preco','catalogo_lote_status','catalogo_opcao_preco','catalogo_opcao_status','catalogo_diagnostico','avaliacao_responder','motivos','codigo_coleta','codigo_entrega']));

create table if not exists public.ifood_cat_diag (
  id boolean primary key default true check (id),
  dados jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);
alter table public.ifood_cat_diag enable row level security;
revoke all on public.ifood_cat_diag from anon, authenticated;

create or replace function public.ifood_cat_diag_gravar(p jsonb) returns void
 language sql security definer set search_path to 'public' as $f$
  insert into ifood_cat_diag (id, dados, atualizado_em) values (true, coalesce(p, '{}'::jsonb), now())
  on conflict (id) do update set dados = excluded.dados, atualizado_em = now()
$f$;
revoke all on function public.ifood_cat_diag_gravar(jsonb) from public, anon, authenticated;
grant execute on function public.ifood_cat_diag_gravar(jsonb) to service_role;

-- texto em português para cada motivo do iFood
create or replace function public._ifood_inelegivel_txt(p_motivo text) returns text language sql immutable as $f$
  select case upper(coalesce(p_motivo, ''))
    when 'CATEGORY_PAUSED' then 'A categoria está pausada. Ative a categoria.'
    when 'ITEM_PAUSED' then 'O item está pausado. Ative o item.'
    when 'ITEM_PRICE_MISSING' then 'O item está sem preço. Informe o preço.'
    when 'OPTION_GROUP_WITHOUT_AVAILABLE_OPTIONS' then 'Um grupo obrigatório ficou sem nenhum complemento disponível. Ative ao menos um complemento do grupo.'
    when 'OPTION_PAUSED' then 'Um complemento está pausado.'
    else 'Motivo informado pelo iFood: ' || coalesce(p_motivo, '(sem motivo)') end
$f$;

create or replace function public.api_ifood_cat_diag(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare d ifood_cat_diag%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into d from ifood_cat_diag where id;
  if not found then return jsonb_build_object('ok', true, 'vazio', true); end if;
  return jsonb_build_object('ok', true, 'em', d.atualizado_em, 'itens', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(x->>'id', x->>'itemId', x->>'externalCode'),
      'nome', coalesce(x->>'name', (select m.nome from ifood_cat_modelo m where m.id::text = coalesce(x->>'externalCode', x->>'id', x->>'itemId') limit 1), x->>'externalCode', x->>'id'),
      'motivo', coalesce(x->>'reason', x->>'unsellableReason', x->>'cause'),
      'oQueFazer', _ifood_inelegivel_txt(coalesce(x->>'reason', x->>'unsellableReason', x->>'cause'))))
    from jsonb_array_elements(case when jsonb_typeof(d.dados->'itens') = 'array' then d.dados->'itens' else '[]'::jsonb end) x), '[]'::jsonb));
end $f$;

create or replace function public.api_ifood_cat_diag_pedir(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  perform _ifood_enfileirar('LOJA', 'catalogo_diagnostico', jsonb_build_object('chave', gen_random_uuid()::text));
  return jsonb_build_object('ok', true, 'message', 'Perguntando ao iFood. Toque em "Atualizar diagnóstico" em alguns segundos.');
end $f$;
revoke all on function public.api_ifood_cat_diag(jsonb), public.api_ifood_cat_diag_pedir(jsonb) from public, anon;
grant execute on function public.api_ifood_cat_diag(jsonb), public.api_ifood_cat_diag_pedir(jsonb) to authenticated, service_role;

-- salvar com as validações do iFood (nome ≤ 100, descrição ≤ 500, preço do item > 0, mínimo ≤ máximo, tipo do grupo, combo)
create or replace function public.api_ifood_cat_salvar(p jsonb) returns jsonb
  language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_tipo text := p->>'tipo'; v_nome text := btrim(coalesce(p->>'nome', '')); v_d jsonb := coalesce(p->'dados', '{}'::jsonb); v_old jsonb; g jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_tipo not in ('categoria','item','grupo','opcao') then return _falha('Tipo inválido.'); end if;
  if v_nome = '' then return _falha('Informe o nome.'); end if;
  if length(v_nome) > 100 then return _falha('O nome pode ter no máximo 100 letras (limite do iFood). Tem ' || length(v_nome) || '.'); end if;
  if jsonb_typeof(v_d) <> 'object' then return _falha('Dados inválidos.'); end if;
  if length(coalesce(v_d->>'descricao', '')) > 500 then return _falha('A descrição pode ter no máximo 500 letras (limite do iFood).'); end if;
  if length(coalesce(v_d->>'fotoPendente', '')) > 700000 then return _falha('Foto grande demais. Escolha outra.'); end if;
  if v_d ? 'preco' and (coalesce(nullif(v_d->>'preco', ''), '0'))::numeric < 0 then return _falha('Preço inválido.'); end if;
  if v_tipo = 'item' and (coalesce(nullif(v_d->>'preco', ''), '0'))::numeric <= 0 then return _falha('O preço do item precisa ser maior que zero (só complemento pode ser grátis).'); end if;
  if v_tipo = 'grupo' and coalesce(v_d->>'tipoGrupo', 'OFFER_UNIT') not in ('OFFER_UNIT','INGREDIENTS','SPECIFICATION','CUTLERY') then return _falha('Tipo de grupo inválido.'); end if;
  if v_tipo = 'item' then
    for g in select value from jsonb_array_elements(case when jsonb_typeof(v_d->'grupos') = 'array' then v_d->'grupos' else '[]'::jsonb end) loop
      if coalesce(nullif(g->>'min', '')::int, 0) > coalesce(nullif(g->>'max', '')::int, 1) then return _falha('Em um dos grupos o mínimo é maior que o máximo.'); end if;
    end loop;
    if coalesce(v_d->>'combo', 'false') = 'true' and jsonb_array_length(case when jsonb_typeof(v_d->'grupos') = 'array' then v_d->'grupos' else '[]'::jsonb end) = 0 then
      return _falha('Um combo precisa de ao menos um grupo de complementos (o primeiro marcado é o principal).');
    end if;
  end if;
  if v_id is null then
    insert into ifood_cat_modelo (tipo, nome, dados) values (v_tipo, v_nome, v_d) returning id into v_id;
  else
    select dados into v_old from ifood_cat_modelo where id = v_id and tipo = v_tipo;
    if not found then return _falha('Registro não encontrado.'); end if;
    v_d := coalesce(p->'dados', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('ifoodId', v_old->'ifoodId', 'productId', v_old->'productId', 'enviado', v_old->'enviado'));
    if not (v_d ? 'foto') and v_old ? 'foto' then v_d := v_d || jsonb_build_object('foto', v_old->'foto'); end if;
    update ifood_cat_modelo set nome = v_nome, dados = v_d, estado = 'rascunho', erro = null, atualizado_em = now() where id = v_id;
  end if;
  perform _auditar('Catálogo do iFood editado', v_tipo || ': ' || v_nome);
  return api_ifood_cat('{}') || jsonb_build_object('id', v_id);
end $$;


-- ======================================================================
-- 67-ifood-avaliacoes-v2.sql
-- ======================================================================
-- 67 · iFood Avaliações v2 (v1.18) — revisado pela documentação OFICIAL do módulo Review. Pode rodar de novo sem erro.
-- H1 resposta de 10 a 300 letras · H2 número do pedido (order.id / order.shortId) · H3 resposta da LOJA separada da reação do cliente
-- H4 recusa do iFood visível (a resposta volta a ficar "sem resposta" e a equipe é avisada) · H5 status, prazo de 5 dias, selos
-- H7 detalhe (nome do cliente e questionário) · H8 nota oficial (summary).

alter table public.ifood_avaliacoes add column if not exists pedido_curto text;
alter table public.ifood_avaliacoes add column if not exists status text;
alter table public.ifood_avaliacoes add column if not exists visibilidade text;
alter table public.ifood_avaliacoes add column if not exists descartada boolean not null default false;
alter table public.ifood_avaliacoes add column if not exists moderada boolean not null default false;
alter table public.ifood_avaliacoes add column if not exists publicada_em timestamptz;
alter table public.ifood_avaliacoes add column if not exists prazo_em timestamptz;
alter table public.ifood_avaliacoes add column if not exists prazo_avisado boolean not null default false;
alter table public.ifood_avaliacoes add column if not exists resposta_estado text;      -- enviando | aceita | recusada
alter table public.ifood_avaliacoes add column if not exists resposta_erro text;
alter table public.ifood_avaliacoes add column if not exists resposta_enviada_em timestamptz;
alter table public.ifood_avaliacoes add column if not exists resposta_cliente text;
alter table public.ifood_avaliacoes add column if not exists cliente_nome text;
alter table public.ifood_avaliacoes add column if not exists questionario jsonb;
alter table public.ifood_avaliacoes add column if not exists detalhe_em timestamptz;

create table if not exists public.ifood_aval_resumo (
  id boolean primary key default true check (id),
  dados jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);
alter table public.ifood_aval_resumo enable row level security;
revoke all on public.ifood_aval_resumo from anon, authenticated;

-- a resposta foi recusada: volta a ficar "sem resposta", o feedback volta a "Novo" e a equipe é avisada (nenhum erro discreto)
create or replace function public.ifood_aval_resposta_falhou(p_id text, p_erro text, p_pode_repetir boolean default true) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare a ifood_avaliacoes%rowtype;
begin
  select * into a from ifood_avaliacoes where id = p_id;
  if not found then return; end if;
  update ifood_avaliacoes set resposta = null, respondida_em = null, resposta_estado = 'recusada', resposta_erro = left(p_erro, 400) where id = p_id;
  if a.feedback_id is not null then update feedbacks set resposta = null, respondido_em = null, respondido_por = '', status = 'Novo' where id = a.feedback_id; end if;
  perform ifood_aviso_registrar(a.pedido_ifood, 'aval_recusada', '❌ O iFood não aceitou sua resposta à avaliação',
    left(p_erro, 400) || case when p_pode_repetir then ' Você pode escrever outra resposta.' else '' end, jsonb_build_object('avaliacao', p_id));
end $f$;
revoke all on function public.ifood_aval_resposta_falhou(text, text, boolean) from public, anon, authenticated;
grant execute on function public.ifood_aval_resposta_falhou(text, text, boolean) to service_role;

-- chamada pela Edge Function depois de enviar a resposta (201 = recebida para validação; 400/409/422 = recusada)
create or replace function public.ifood_aval_resposta_resultado(p_id text, p_http int, p_corpo text default null) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare v_msg text;
begin
  if p_http between 200 and 299 then
    update ifood_avaliacoes set resposta_estado = 'enviando', resposta_erro = null where id = p_id and coalesce(resposta_estado, '') <> 'aceita';
    return;
  end if;
  v_msg := case
    when p_http = 400 then 'O iFood recusou o tamanho da resposta (precisa ter de 10 a 300 letras).'
    when p_http = 409 then 'Esta avaliação não aceita mais resposta (já foi respondida ou o prazo de 5 dias passou).'
    when p_http = 422 then 'O iFood recusou o conteúdo: evite links, telefones, nomes e dados pessoais, e palavras impróprias.'
    when p_http = 404 then 'O iFood não encontrou esta avaliação.'
    when p_http = 429 then 'Muitas chamadas ao iFood ao mesmo tempo. Tente de novo em alguns minutos.'
    else 'O iFood não recebeu a resposta (erro ' || p_http || ').' end;
  perform ifood_aval_resposta_falhou(p_id, v_msg || coalesce(' (' || left(p_corpo, 120) || ')', ''), p_http not in (404, 409));
end $f$;
revoke all on function public.ifood_aval_resposta_resultado(text, int, text) from public, anon, authenticated;
grant execute on function public.ifood_aval_resposta_resultado(text, int, text) to service_role;

-- grava as avaliações da listagem (v2: order.id / order.shortId; replies com from = MERCHANT ou CUSTOMER)
create or replace function public.ifood_avaliacoes_gravar(p_lista jsonb) returns integer
 language plpgsql security definer set search_path to 'public' as $function$
declare e jsonb; v_n int := 0; v_fb uuid; v_venda uuid; v_nota int; v_ja boolean; v_num text; v_ord text; v_curto text; v_mer text; v_cli text; v_st text; v_old ifood_avaliacoes%rowtype; v_cri timestamptz; v_rep jsonb;
begin
  for e in select value from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) loop
    if nullif(e->>'id', '') is null then continue; end if;
    select * into v_old from ifood_avaliacoes where id = e->>'id'; v_ja := found;
    v_nota := round(public._ifood_n(coalesce(e->'score', e->'rating', e->'nota')))::int;
    v_ord := coalesce(nullif(e->'order'->>'id', ''), nullif(e->>'orderId', ''));
    v_curto := coalesce(nullif(e->'order'->>'shortId', ''), nullif(e->>'shortId', ''));
    v_rep := case when jsonb_typeof(e->'replies') = 'array' then e->'replies' else '[]'::jsonb end;
    select r->>'text' into v_mer from jsonb_array_elements(v_rep) r where upper(coalesce(r->>'from', 'MERCHANT')) = 'MERCHANT' and coalesce(r->>'text', '') <> '' order by r->>'createdAt' desc limit 1;
    select r->>'text' into v_cli from jsonb_array_elements(v_rep) r where upper(coalesce(r->>'from', '')) = 'CUSTOMER' and coalesce(r->>'text', '') <> '' order by r->>'createdAt' desc limit 1;
    v_mer := coalesce(v_mer, nullif(e->>'reply', ''));
    v_st := upper(nullif(e->>'status', ''));
    v_cri := nullif(e->>'createdAt', '')::timestamptz;
    select venda_id, numero_ifood into v_venda, v_num from ifood_pedidos where pedido_ifood = v_ord;
    insert into ifood_avaliacoes (id, pedido_ifood, pedido_curto, nota, comentario, criada_em, resposta, bruto, status, visibilidade, descartada, moderada, publicada_em, prazo_em, resposta_cliente, resposta_estado)
    values (e->>'id', v_ord, v_curto, v_nota, left(coalesce(e->>'comment', e->>'text', ''), 1000), v_cri, v_mer, e, v_st, upper(nullif(e->>'visibility', '')),
            coalesce((e->>'discarded')::boolean, false), coalesce((e->>'moderated')::boolean, false), nullif(e->>'published', '')::timestamptz,
            v_cri + interval '5 days', v_cli, case when v_mer is not null then 'aceita' end)
    on conflict (id) do update set
      pedido_ifood = coalesce(excluded.pedido_ifood, ifood_avaliacoes.pedido_ifood), pedido_curto = coalesce(excluded.pedido_curto, ifood_avaliacoes.pedido_curto),
      nota = excluded.nota, bruto = excluded.bruto, status = excluded.status, visibilidade = excluded.visibilidade, descartada = excluded.descartada, moderada = excluded.moderada,
      publicada_em = coalesce(excluded.publicada_em, ifood_avaliacoes.publicada_em), prazo_em = coalesce(ifood_avaliacoes.prazo_em, excluded.prazo_em), resposta_cliente = excluded.resposta_cliente,
      resposta = coalesce(excluded.resposta, ifood_avaliacoes.resposta),
      resposta_estado = case when excluded.resposta is not null then 'aceita' else ifood_avaliacoes.resposta_estado end,
      resposta_erro = case when excluded.resposta is not null then null else ifood_avaliacoes.resposta_erro end;
    -- a resposta ficou "enviando" mas o iFood continua sem a resposta depois de 20 min: a validação do iFood a recusou
    if v_ja and v_mer is null and v_old.resposta_estado = 'enviando' and v_old.resposta_enviada_em < now() - interval '20 minutes' and coalesce(v_st, 'NOT_REPLIED') = 'NOT_REPLIED' then
      perform ifood_aval_resposta_falhou(e->>'id', 'O iFood não publicou a resposta depois da validação dele (provavelmente tem link, telefone, dado pessoal ou palavra imprópria).', true);
    end if;
    -- liga o feedback à venda quando o pedido só apareceu agora
    if v_ja and v_old.feedback_id is not null and v_venda is not null then update feedbacks set venda_id = v_venda where id = v_old.feedback_id and venda_id is null; end if;
    if not v_ja then
      begin
        insert into feedbacks (venda_id, nota, comentario, data, status, origem) values (v_venda, greatest(least(v_nota, 5), 1), left(coalesce(e->>'comment', e->>'text', ''), 1000), coalesce(v_cri, now()), 'Novo', 'iFood') returning id into v_fb;
        update ifood_avaliacoes set feedback_id = v_fb where id = e->>'id';
      exception when others then null; end;
      if v_nota <= 2 or (v_nota = 3 and coalesce((select (config->>'avaliacaoAlerta')::boolean from integracoes_config where provedor = 'ifood'), false)) then perform _push_enviar('feedback', '⭐ Avaliação baixa no iFood (' || v_nota || ')', coalesce(left(e->>'comment', 100), 'Veja no painel'), 'ifood-aval-' || (e->>'id')); end if;
      v_n := v_n + 1;
    end if;
  end loop;
  -- falta 1 dia para o fim do prazo de resposta (5 dias): avisa uma vez
  for e in select jsonb_build_object('id', id, 'pedido', pedido_ifood) from ifood_avaliacoes
            where status = 'NOT_REPLIED' and not prazo_avisado and coalesce(resposta_estado, '') <> 'enviando' and nota < 5 and prazo_em between now() and now() + interval '1 day' loop
    update ifood_avaliacoes set prazo_avisado = true where id = e->>'id';
    perform ifood_aviso_registrar(e->>'pedido', 'aval_prazo', '⏰ Avaliação do iFood perde o prazo de resposta amanhã', 'Responda hoje: depois de 5 dias a avaliação é publicada sem a sua resposta.', jsonb_build_object('avaliacao', e->>'id'));
  end loop;
  return v_n;
end $function$;
revoke all on function public.ifood_avaliacoes_gravar(jsonb) from public, anon, authenticated;
grant execute on function public.ifood_avaliacoes_gravar(jsonb) to service_role;

create or replace function public.ifood_aval_detalhe_gravar(p_id text, p jsonb) returns void
 language sql security definer set search_path to 'public' as $f$
  update ifood_avaliacoes set cliente_nome = left(coalesce(p->>'customerName', cliente_nome), 80),
    questionario = case when jsonb_typeof(p->'questions') = 'array' then p->'questions' else questionario end, detalhe_em = now() where id = p_id
$f$;
create or replace function public.ifood_aval_resumo_gravar(p jsonb) returns void
 language sql security definer set search_path to 'public' as $f$
  insert into ifood_aval_resumo (id, dados, atualizado_em) values (true, coalesce(p, '{}'::jsonb), now())
  on conflict (id) do update set dados = excluded.dados, atualizado_em = now()
$f$;
-- avaliações novas sem detalhe (a Edge Function busca no máximo 5 por rodada)
create or replace function public.ifood_aval_detalhe_pendentes() returns jsonb
 language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(id), '[]'::jsonb) from (select id from ifood_avaliacoes where detalhe_em is null and criada_em > now() - interval '15 days' order by criada_em desc limit 5) x
$f$;
revoke all on function public.ifood_aval_detalhe_gravar(text, jsonb), public.ifood_aval_resumo_gravar(jsonb), public.ifood_aval_detalhe_pendentes() from public, anon, authenticated;
grant execute on function public.ifood_aval_detalhe_gravar(text, jsonb), public.ifood_aval_resumo_gravar(jsonb), public.ifood_aval_detalhe_pendentes() to service_role;

-- tela de avaliações (Admin): nota oficial + 30 dias, status, prazo, selos, questionário
create or replace function public.api_ifood_avaliacoes(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
declare v_so boolean := coalesce(p->>'semResposta', '') = 'true';
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'media30d', (select round(avg(nota), 2) from ifood_avaliacoes where coalesce(criada_em, visto_em) > now() - interval '30 days'),
    'oficial', (select dados || jsonb_build_object('em', atualizado_em) from ifood_aval_resumo where id),
    'semResposta', (select count(*) from ifood_avaliacoes where status = 'NOT_REPLIED' and nota < 5 and coalesce(resposta_estado, '') <> 'enviando' and prazo_em > now()),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nota', a.nota, 'comentario', a.comentario, 'em', a.criada_em, 'resposta', a.resposta,
        'pedido', coalesce(i.numero_ifood, a.pedido_curto), 'status', a.status, 'visibilidade', a.visibilidade, 'descartada', a.descartada, 'moderada', a.moderada,
        'prazoEm', a.prazo_em, 'podeResponder', (coalesce(a.status, 'NOT_REPLIED') = 'NOT_REPLIED' and coalesce(a.resposta_estado, '') not in ('enviando', 'aceita') and (a.prazo_em is null or a.prazo_em > now())),
        'respostaEstado', a.resposta_estado, 'respostaErro', a.resposta_erro, 'respostaCliente', a.resposta_cliente, 'cliente', a.cliente_nome, 'questionario', a.questionario)
        order by coalesce(a.criada_em, a.visto_em) desc)
      from (select * from ifood_avaliacoes where (not v_so or (status = 'NOT_REPLIED' and nota < 5)) order by coalesce(criada_em, visto_em) desc limit 50) a
      left join ifood_pedidos i on i.pedido_ifood = a.pedido_ifood), '[]'::jsonb));
end $function$;

-- responder (Admin): 10 a 300 letras, só quando o iFood ainda aceita; a tela mostra "enviando" até o iFood confirmar
create or replace function public.api_ifood_avaliacao_responder(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare v_texto text := btrim(coalesce(p->>'texto', '')); a ifood_avaliacoes%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if length(v_texto) < 10 or length(v_texto) > 300 then return _falha('A resposta ao iFood precisa ter de 10 a 300 letras (tem ' || length(v_texto) || ').'); end if;
  select * into a from ifood_avaliacoes where id = p->>'id';
  if not found then return _falha('Avaliação não encontrada.'); end if;
  if coalesce(a.status, 'NOT_REPLIED') <> 'NOT_REPLIED' then return _falha('O iFood não aceita mais resposta a esta avaliação (status ' || a.status || ').'); end if;
  if a.resposta_estado = 'enviando' then return _falha('A resposta anterior ainda está sendo validada pelo iFood. Aguarde alguns minutos.'); end if;
  if a.prazo_em is not null and a.prazo_em < now() then return _falha('O prazo de 5 dias para responder já passou.'); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  update ifood_avaliacoes set resposta = v_texto, respondida_em = now(), resposta_estado = 'enviando', resposta_erro = null, resposta_enviada_em = now() where id = a.id;
  update feedbacks set resposta = v_texto, respondido_em = now(), respondido_por = coalesce((select nome from usuarios where id = auth.uid()), ''), status = 'Respondido' where id = a.feedback_id;
  insert into ifood_acoes (pedido_ifood, acao, dados) values ('LOJA', 'avaliacao_responder', jsonb_build_object('avaliacao', a.id, 'texto', v_texto, 'chave', gen_random_uuid()::text)) on conflict do nothing;
  perform _auditar('Resposta a avaliação do iFood', left(v_texto, 100));
  return jsonb_build_object('ok', true, 'message', 'Enviando ao iFood. A resposta só vale depois que o iFood a validar (alguns minutos); se ele recusar, você será avisado.') || api_ifood_avaliacoes('{}');
end $function$;

-- tela Feedbacks: o aviso de tamanho agora diz claramente que NÃO foi para o iFood
create or replace function public.api_responder_feedback(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid := _uuid(p->>'id'); v_txt text := left(btrim(coalesce(p->>'resposta', '')), 1000); v_nome text; v_user uuid; v_av text; v_ifood text := null; v_ast text; v_prazo timestamptz; v_ares text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_txt = '' then return _falha('Escreva a resposta.'); end if;
  select id, status, prazo_em, resposta_estado into v_av, v_ast, v_prazo, v_ares from ifood_avaliacoes where feedback_id = v_id;
  -- avaliação do iFood: se o iFood não vai aceitar, a tela avisa ANTES de gravar como respondido
  if v_av is not null and tem_nivel('Admin') and _integracao_ligada('ifood') and (length(v_txt) < 10 or length(v_txt) > 300) then
    return jsonb_build_object('ok', false, 'message', 'Esta avaliação veio do iFood: a resposta precisa ter de 10 a 300 letras (tem ' || length(v_txt) || '). Ajuste o texto; nada foi enviado.');
  end if;
  if v_av is not null and tem_nivel('Admin') and _integracao_ligada('ifood') and coalesce(v_ast, 'NOT_REPLIED') <> 'NOT_REPLIED' then
    return jsonb_build_object('ok', false, 'message', 'O iFood não aceita mais resposta a esta avaliação (status ' || v_ast || ').');
  end if;
  select nome into v_nome from usuarios where id = auth.uid();
  update feedbacks set resposta = v_txt, respondido_em = now(), respondido_por = coalesce(v_nome, ''), status = 'Respondido'
   where id = v_id returning user_id into v_user;
  if not found then return _falha('Feedback não encontrado.'); end if;
  if v_av is not null then
    if not tem_nivel('Admin') then v_ifood := 'so_admin';
    elsif not _integracao_ligada('ifood') then v_ifood := 'desligado';
    elsif v_prazo is not null and v_prazo < now() then v_ifood := 'prazo';
    elsif v_ares = 'enviando' then v_ifood := 'aguardando';
    else
      update ifood_avaliacoes set resposta = v_txt, respondida_em = now(), resposta_estado = 'enviando', resposta_erro = null, resposta_enviada_em = now() where id = v_av;
      insert into ifood_acoes (pedido_ifood, acao, dados) values ('LOJA', 'avaliacao_responder', jsonb_build_object('avaliacao', v_av, 'texto', v_txt, 'chave', gen_random_uuid()::text)) on conflict do nothing;
      v_ifood := 'enviada';
    end if;
  end if;
  perform _auditar('Feedback respondido', 'Resposta enviada' || case when v_user is null then ' (cliente sem conta)' else '' end || case when v_ifood = 'enviada' then ' · enviada ao iFood' else '' end);
  return jsonb_build_object('ok', true, 'comConta', v_user is not null, 'ifood', v_ifood);
end $function$;


-- ======================================================================
-- 68-ifood-shipping.sql
-- ======================================================================
-- 68 · iFood Shipping (v1.19) — "entregador do iFood" (Sob Demanda). LIGA/DESLIGA na tela iFood › Entregador do iFood.
-- Pelos PDFs oficiais do módulo Shipping. Pode rodar de novo sem erro.
-- Modo A: pedido que VEIO do iFood com entrega própria → pede um entregador do iFood (cotação, chamar, cancelar a chamada).
-- Modo B: pedido FORA do iFood (cardápio próprio, balcão, WhatsApp) → cria o pedido de entrega Sob Demanda (cotação pelo endereço,
--         link de rastreio para o cliente, código de 4 dígitos, nível de confiança, troca de endereço, cancelamento com motivos do iFood).
-- Pré-requisito no iFood: contratar o serviço Sob Demanda no Portal do Parceiro › Serviços. Chamar e cancelar pedem a SENHA do Admin.

create table if not exists public.ifood_ship_config (
  id boolean primary key default true check (id),
  ligado boolean not null default false,
  cidade text not null default '',
  uf text not null default '',
  preparo_seg int not null default 900 check (preparo_seg between 60 and 3600),
  atualizado_em timestamptz not null default now()
);
insert into public.ifood_ship_config (id) values (true) on conflict do nothing;
alter table public.ifood_ship_config enable row level security;
revoke all on public.ifood_ship_config from anon, authenticated;

create table if not exists public.ifood_ship (
  id uuid primary key default gen_random_uuid(),
  modo text not null check (modo in ('A', 'B')),
  venda_id uuid not null,
  pedido_ifood text,                 -- modo A: id do pedido no iFood
  ship_id text,                      -- id do pedido no Shipping (A = o próprio pedido do iFood; B = o que o iFood devolve ao criar)
  endereco jsonb not null default '{}'::jsonb,
  quote_id text, quote jsonb, valor numeric(10,2), expira_em timestamptz,
  estado text not null default 'cotando' check (estado in ('cotando','cotada','erro_cotacao','solicitando','alocada','em_rota','entregue','falhou','cancelando','cancelada')),
  erro text, tracking_url text, codigo text, safe_score text, safe_regras jsonb, motivos jsonb, endereco_pendente jsonb, eventos jsonb not null default '[]'::jsonb,
  custo_lancado boolean not null default false,
  criado_por text, criado_em timestamptz not null default now(), atualizado_em timestamptz not null default now()
);
create index if not exists ifood_ship_venda_idx on public.ifood_ship (venda_id);
create index if not exists ifood_ship_shipid_idx on public.ifood_ship (ship_id);
alter table public.ifood_ship enable row level security;
revoke all on public.ifood_ship from anon, authenticated;

alter table public.ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table public.ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar','negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler','catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','catalogo_modelo_enviar','catalogo_lote_preco','catalogo_lote_status','catalogo_opcao_preco','catalogo_opcao_status','catalogo_diagnostico','avaliacao_responder','motivos','codigo_coleta','codigo_entrega','ship_cotar','ship_chamar','ship_cancelar','ship_motivos','ship_endereco','ship_safe']));

-- erros do iFood em português (G3)
create or replace function public._ifood_ship_erro_txt(p_codigo text) returns text language sql immutable as $f$
  select case coalesce(p_codigo, '')
    when 'DeliveryDistanceTooHigh' then 'O endereço fica a mais de ~10 km da loja: o iFood não entrega.'
    when 'ServiceAreaMismatch' then 'O endereço está fora da área de cobertura do entregador do iFood.'
    when 'OffOpeningHours' then 'Fora do horário de funcionamento da loja no iFood.'
    when 'HighDemand' then 'Muita demanda no iFood agora: não há entregador livre. Tente de novo em alguns minutos.'
    when 'MerchantEasyDeliveryDisabled' then 'O serviço Sob Demanda não está contratado para esta loja. Contrate no Portal do Parceiro › Serviços.'
    when 'MerchantStatusAvailability' then 'A conta da loja tem pendência no iFood. Veja no Portal do Parceiro.'
    when 'InvalidPaymentMethods' then 'Esta forma de pagamento não é aceita para entrega pelo iFood.'
    when 'SaturatedOfflinePayment' then 'Pagamento na entrega indisponível no iFood agora. Use um pedido já pago ou tente mais tarde.'
    when 'NRELimitExceeded' then 'Limite de entregadores do iFood atingido. Tente de novo mais tarde.'
    when 'UnavailableFleet' then 'Frota indisponível agora. Tente de novo em alguns minutos.'
    when 'OriginNotFound' then 'O iFood não encontrou a loja (confira o código da loja nas integrações).'
    when 'BadRequestMerchant' then 'A loja está indisponível no iFood (fechada ou pausada).'
    when 'BadRequestCustomer' then 'Os dados do cliente foram recusados (telefone ou nome inválido).'
    when 'BadRequest' then 'Dados inválidos na solicitação (confira endereço, CEP e coordenadas).'
    else null end
$f$;

-- ---------- configuração (liga/desliga) ----------
create or replace function public.api_ifood_ship_config(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare c ifood_ship_config%rowtype; v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'salvar', '') = 'true' then
    if coalesce(p->>'senhaAdminConfirmacao', '') = '' then return _falha('Informe a sua senha de administrador para confirmar.'); end if;
    v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
    if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
    if length(btrim(coalesce(p->>'uf', ''))) not in (0, 2) then return _falha('A UF precisa ter 2 letras (ex.: SP).'); end if;
    update ifood_ship_config set ligado = coalesce((p->>'ligado')::boolean, ligado), cidade = left(btrim(coalesce(p->>'cidade', cidade)), 80),
      uf = upper(btrim(coalesce(p->>'uf', uf))), preparo_seg = coalesce(nullif(p->>'preparoMin', '')::int * 60, preparo_seg), atualizado_em = now() where id;
    perform _auditar('Entregador do iFood: configuração', case when coalesce((p->>'ligado')::boolean, false) then 'ligado' else 'salvo' end);
  end if;
  select * into c from ifood_ship_config where id;
  return jsonb_build_object('ok', true, 'ligado', c.ligado, 'cidade', c.cidade, 'uf', c.uf, 'preparoMin', c.preparo_seg / 60);
end $f$;

-- ---------- lista (entregas pedidas + pedidos que podem chamar entregador) ----------
create or replace function public.api_ifood_ship_lista(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare c ifood_ship_config%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from ifood_ship_config where id;
  return jsonb_build_object('ok', true, 'config', jsonb_build_object('ligado', c.ligado, 'cidade', c.cidade, 'uf', c.uf, 'preparoMin', c.preparo_seg / 60),
    'gasto7d', (select coalesce(sum(valor), 0) from ifood_ship where estado in ('alocada','em_rota','entregue','cancelando') and criado_em > now() - interval '7 days'),
    'entregas', coalesce((select jsonb_agg(x order by (x->>'em') desc) from (
      select jsonb_build_object('id', s.id, 'modo', s.modo, 'pedido', v.numero_pedido, 'cliente', v.cliente_nome, 'estado', s.estado, 'erro', s.erro, 'valor', s.valor,
        'expiraEm', s.expira_em, 'tempoMin', (s.quote->'deliveryTime'->>'min'), 'tempoMax', (s.quote->'deliveryTime'->>'max'), 'distancia', s.quote->>'distance', 'rastreio', s.tracking_url, 'codigo', s.codigo,
        'confianca', s.safe_score, 'regras', s.safe_regras, 'motivos', s.motivos, 'enderecoPendente', s.endereco_pendente, 'eventos', s.eventos, 'em', s.criado_em,
        'pagamentos', s.quote->'paymentMethods') as x
      from ifood_ship s join vendas v on v.id = s.venda_id where s.criado_em > now() - interval '7 days' order by s.criado_em desc limit 40) q), '[]'::jsonb),
    'candidatas', coalesce((select jsonb_agg(jsonb_build_object('vendaId', v.id, 'pedido', v.numero_pedido, 'cliente', v.cliente_nome, 'telefone', v.telefone_cliente, 'endereco', v.endereco,
        'complemento', v.complemento, 'referencia', v.referencia, 'total', v.valor_total, 'forma', v.forma_pagamento, 'pagamento', v.status_pagamento::text, 'situacao', v.status_pedido::text,
        'modo', case when i.pedido_ifood is not null then 'A' else 'B' end, 'lat', d.lat, 'lng', d.lng) order by v.data_hora desc)
      from vendas v left join ifood_pedidos i on i.venda_id = v.id left join pedido_destinos d on d.venda_id = v.id
      where v.tipo::text = 'Entrega' and v.status::text = 'Confirmada' and v.status_pedido::text in ('Recebido', 'Em preparo', 'Pronta') and v.data_hora > now() - interval '1 day'
        and (i.pedido_ifood is null or (not i.simulado and coalesce(v.observacoes_entrega, '') not ilike '%ENTREGA PELO iFOOD%'))
        and not exists (select 1 from ifood_ship s where s.venda_id = v.id and s.estado not in ('cancelada', 'falhou', 'erro_cotacao'))), '[]'::jsonb));
end $f$;

-- ---------- cotar (grátis) ----------
create or replace function public.api_ifood_ship_cotar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare c ifood_ship_config%rowtype; v vendas%rowtype; i ifood_pedidos%rowtype; e jsonb := coalesce(p->'endereco', '{}'::jsonb); v_modo text; v_id uuid; v_login text; v_lat float; v_lng float;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from ifood_ship_config where id;
  if not c.ligado then return _falha('O entregador do iFood está desligado. Ligue em iFood › Entregador do iFood.'); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  select * into v from vendas where id = nullif(p->>'vendaId', '')::uuid;
  if not found then return _falha('Pedido não encontrado.'); end if;
  if v.tipo::text <> 'Entrega' or v.status::text <> 'Confirmada' then return _falha('Só pedido de ENTREGA confirmado pode chamar entregador.'); end if;
  if exists (select 1 from ifood_ship s where s.venda_id = v.id and s.estado not in ('cancelada', 'falhou', 'erro_cotacao')) then return _falha('Este pedido já tem uma entrega do iFood em andamento.'); end if;
  select * into i from ifood_pedidos where venda_id = v.id;
  if found then
    if i.simulado then return _falha('Pedido de teste do iFood: não chama entregador de verdade.'); end if;
    if coalesce(v.observacoes_entrega, '') ilike '%ENTREGA PELO iFOOD%' then return _falha('Este pedido já será entregue pelo próprio iFood.'); end if;
    v_modo := 'A';
  else
    v_modo := 'B';
    v_lat := nullif(e->>'lat', '')::float; v_lng := nullif(e->>'lng', '')::float;
    if v_lat is null or v_lng is null or abs(v_lat) > 90 or abs(v_lng) > 180 then return _falha('Informe as coordenadas do endereço (latitude e longitude). Dica: no Google Maps, toque e segure no endereço e copie os números.'); end if;
    if length(regexp_replace(coalesce(e->>'cep', ''), '\D', '', 'g')) <> 8 then return _falha('Informe o CEP com 8 números.'); end if;
    if coalesce(btrim(e->>'rua'), '') = '' or coalesce(btrim(e->>'numero'), '') = '' or coalesce(btrim(e->>'bairro'), '') = '' or coalesce(btrim(e->>'cidade'), '') = '' or length(btrim(coalesce(e->>'uf', ''))) <> 2 then
      return _falha('Preencha rua, número, bairro, cidade e UF (2 letras).');
    end if;
  end if;
  select login into v_login from usuarios where id = auth.uid();
  insert into ifood_ship (modo, venda_id, pedido_ifood, ship_id, endereco, estado, criado_por)
    values (v_modo, v.id, i.pedido_ifood, case when v_modo = 'A' then i.pedido_ifood end, e, 'cotando', v_login) returning id into v_id;
  perform _ifood_enfileirar('LOJA', 'ship_cotar', jsonb_build_object('chave', v_id::text, 'ship', v_id));
  return jsonb_build_object('ok', true, 'id', v_id, 'message', 'Pedindo a cotação ao iFood. Toque em Atualizar em alguns segundos.');
end $f$;

-- ---------- chamar (gasta dinheiro: pede a senha do Admin) ----------
create or replace function public.api_ifood_ship_chamar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; c ifood_ship_config%rowtype; v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into c from ifood_ship_config where id;
  if not c.ligado then return _falha('O entregador do iFood está desligado.'); end if;
  if coalesce(p->>'senhaAdminConfirmacao', '') = '' then return _falha('Informe a sua senha de administrador para confirmar.'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into s from ifood_ship where id = nullif(p->>'id', '')::uuid for update;
  if not found then return _falha('Entrega não encontrada.'); end if;
  if s.estado <> 'cotada' then return _falha('Peça uma cotação primeiro (estado atual: ' || s.estado || ').'); end if;
  if s.expira_em is not null and s.expira_em < now() then return _falha('A cotação venceu. Peça uma nova.'); end if;
  update ifood_ship set estado = 'solicitando', erro = null, atualizado_em = now() where id = s.id;
  perform _ifood_enfileirar('LOJA', 'ship_chamar', jsonb_build_object('chave', s.id::text || '-chamar', 'ship', s.id));
  perform _auditar('Entregador do iFood chamado', 'Pedido ' || (select numero_pedido from vendas where id = s.venda_id) || ' · R$ ' || coalesce(s.valor, 0));
  return jsonb_build_object('ok', true, 'message', 'Chamando o entregador. O iFood avisa quando alguém aceitar.');
end $f$;

-- ---------- motivos de cancelamento (modo B; nunca fixos no código) ----------
create or replace function public.api_ifood_ship_motivos(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into s from ifood_ship where id = nullif(p->>'id', '')::uuid;
  if not found then return _falha('Entrega não encontrada.'); end if;
  update ifood_ship set motivos = null where id = s.id;
  perform _ifood_enfileirar('LOJA', 'ship_motivos', jsonb_build_object('chave', gen_random_uuid()::text, 'ship', s.id));
  return jsonb_build_object('ok', true, 'message', 'Buscando no iFood os motivos permitidos.');
end $f$;

create or replace function public.api_ifood_ship_cancelar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; v_aut text; v_ok boolean;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(p->>'senhaAdminConfirmacao', '') = '' then return _falha('Informe a sua senha de administrador para confirmar.'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into s from ifood_ship where id = nullif(p->>'id', '')::uuid for update;
  if not found then return _falha('Entrega não encontrada.'); end if;
  if s.estado not in ('solicitando', 'alocada', 'em_rota', 'cotada') then return _falha('Esta entrega não pode ser cancelada agora (estado: ' || s.estado || ').'); end if;
  if s.estado = 'cotada' then
    update ifood_ship set estado = 'cancelada', atualizado_em = now() where id = s.id;
    return jsonb_build_object('ok', true, 'message', 'Cotação descartada.');
  end if;
  if s.modo = 'B' then
    select exists (select 1 from jsonb_array_elements(coalesce(s.motivos, '[]'::jsonb)) m where m->>'cancelCodeId' = p->>'codigo') into v_ok;
    if not v_ok then return _falha('Escolha um dos motivos de cancelamento trazidos do iFood.'); end if;
  end if;
  update ifood_ship set estado = 'cancelando', atualizado_em = now() where id = s.id;
  perform _ifood_enfileirar('LOJA', 'ship_cancelar', jsonb_build_object('chave', s.id::text || '-cancelar', 'ship', s.id, 'codigo', p->>'codigo',
    'motivo', left(coalesce((select m->>'description' from jsonb_array_elements(coalesce(s.motivos, '[]'::jsonb)) m where m->>'cancelCodeId' = p->>'codigo'), 'Cancelado pela loja'), 200)));
  perform _auditar('Entregador do iFood cancelado', 'Entrega ' || s.id);
  return jsonb_build_object('ok', true, 'message', 'Cancelamento enviado ao iFood. O resultado chega em instantes.');
end $f$;

-- ---------- endereço (modo B): confirmar o original, aceitar ou negar a troca pedida pelo cliente ----------
create or replace function public.api_ifood_ship_endereco(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; v_acao text := p->>'acao';
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if v_acao not in ('confirmar', 'aceitar', 'negar') then return _falha('Ação inválida.'); end if;
  select * into s from ifood_ship where id = nullif(p->>'id', '')::uuid;
  if not found or s.modo <> 'B' then return _falha('Entrega não encontrada.'); end if;
  if v_acao <> 'confirmar' and s.endereco_pendente is null then return _falha('Não há pedido de troca de endereço esperando resposta.'); end if;
  perform _ifood_enfileirar('LOJA', 'ship_endereco', jsonb_build_object('chave', gen_random_uuid()::text, 'ship', s.id, 'acao', v_acao));
  return jsonb_build_object('ok', true, 'message', 'Enviando a resposta ao iFood.');
end $f$;

create or replace function public.api_ifood_ship_safe(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select * into s from ifood_ship where id = nullif(p->>'id', '')::uuid;
  if not found or s.modo <> 'B' then return _falha('Entrega não encontrada.'); end if;
  perform _ifood_enfileirar('LOJA', 'ship_safe', jsonb_build_object('chave', gen_random_uuid()::text, 'ship', s.id));
  return jsonb_build_object('ok', true, 'message', 'Consultando o nível de confiança no iFood.');
end $f$;

revoke all on function public.api_ifood_ship_config(jsonb), public.api_ifood_ship_lista(jsonb), public.api_ifood_ship_cotar(jsonb), public.api_ifood_ship_chamar(jsonb),
  public.api_ifood_ship_motivos(jsonb), public.api_ifood_ship_cancelar(jsonb), public.api_ifood_ship_endereco(jsonb), public.api_ifood_ship_safe(jsonb) from public, anon;
grant execute on function public.api_ifood_ship_config(jsonb), public.api_ifood_ship_lista(jsonb), public.api_ifood_ship_cotar(jsonb), public.api_ifood_ship_chamar(jsonb),
  public.api_ifood_ship_motivos(jsonb), public.api_ifood_ship_cancelar(jsonb), public.api_ifood_ship_endereco(jsonb), public.api_ifood_ship_safe(jsonb) to authenticated, service_role;

-- ---------- só para a Edge Function (service_role) ----------
create or replace function public.ifood_ship_dados(p_id uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; c ifood_ship_config%rowtype;
begin
  select * into s from ifood_ship where id = p_id;
  if not found then return null; end if;
  select * into c from ifood_ship_config where id;
  return jsonb_build_object('id', s.id, 'modo', s.modo, 'shipId', s.ship_id, 'quoteId', s.quote_id, 'estado', s.estado, 'endereco', s.endereco, 'valor', s.valor,
    'ligado', c.ligado, 'preparoSeg', c.preparo_seg, 'pedidoIfood', s.pedido_ifood);
end $f$;

create or replace function public.ifood_ship_resultado(p_id uuid, p_estado text, p_patch jsonb default '{}'::jsonb, p_erro text default null) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype;
begin
  update ifood_ship set estado = coalesce(nullif(p_estado, ''), estado), erro = left(p_erro, 400),
    quote_id = coalesce(p_patch->>'quoteId', quote_id), quote = coalesce(p_patch->'quote', quote),
    valor = coalesce(nullif(p_patch->>'valor', '')::numeric, valor), expira_em = coalesce(nullif(p_patch->>'expiraEm', '')::timestamptz, expira_em),
    ship_id = coalesce(nullif(p_patch->>'shipId', ''), ship_id), tracking_url = coalesce(p_patch->>'trackingUrl', tracking_url),
    safe_score = coalesce(p_patch->>'safeScore', safe_score), safe_regras = coalesce(p_patch->'safeRegras', safe_regras), motivos = coalesce(p_patch->'motivos', motivos),
    endereco_pendente = case when p_patch ? 'limparEndereco' then null else endereco_pendente end,
    atualizado_em = now() where id = p_id returning * into s;
  if found and p_erro is not null and p_estado in ('erro_cotacao', 'falhou') then
    perform ifood_aviso_registrar(s.pedido_ifood, 'ship_erro', '🛵 Entregador do iFood: ' || case when p_estado = 'erro_cotacao' then 'sem cotação' else 'não foi possível chamar' end, left(p_erro, 400), jsonb_build_object('ship', p_id));
  end if;
end $f$;

-- eventos do Shipping (REQUEST_DRIVER_*, DELIVERY_*): atualiza a entrega e avisa a equipe. Devolve {achou:true} se o pedido é uma entrega nossa.
create or replace function public.ifood_ship_evento(p_codigo text, p_pedido text, p_meta jsonb default '{}'::jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; v_cod text := upper(coalesce(p_codigo, '')); v_num int; v_est text; v_tit text; v_msg text; v_tipo text := 'ship';
begin
  select * into s from ifood_ship where ship_id = p_pedido and estado <> 'cotando' order by criado_em desc limit 1;
  if not found then return jsonb_build_object('achou', false); end if;
  -- no modo A (pedido do iFood) só os eventos próprios do entregador passam por aqui; o resto segue o tratamento normal do pedido
  if s.modo = 'A' and v_cod !~ '^(REQUEST_DRIVER_|DELIVERY_CANCELLATION_)' then return jsonb_build_object('achou', true, 'avisou', false); end if;
  select numero_pedido into v_num from vendas where id = s.venda_id;
  update ifood_ship set eventos = (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(eventos || jsonb_build_array(jsonb_build_object('codigo', v_cod, 'em', now(), 'meta', coalesce(p_meta, '{}'::jsonb)))) x order by 1 desc limit 30) q) where id = s.id;
  if v_cod in ('REQUEST_DRIVER_SUCCESS') then v_est := 'alocada'; v_tit := '🛵 Entregador do iFood a caminho da loja'; v_msg := 'Um entregador aceitou o pedido #' || v_num || '.';
  elsif v_cod = 'REQUEST_DRIVER_FAILED' then v_est := 'falhou'; v_tit := '🛵 Nenhum entregador aceitou o pedido #' || v_num; v_msg := 'O iFood não conseguiu alocar um entregador. Tente chamar de novo ou use outro meio de entrega.';
  elsif v_cod = 'DELIVERY_DROP_CODE_REQUESTED' then update ifood_ship set codigo = coalesce(p_meta->>'CODE', codigo) where id = s.id; v_tit := '🔑 Código de entrega do pedido #' || v_num; v_msg := 'O entregador vai pedir este código ao cliente: ' || coalesce(p_meta->>'CODE', '(sem código)') || '. Avise o cliente.';
  elsif v_cod = 'DELIVERY_IN_TRANSIT' then v_est := 'em_rota'; v_tit := '🛵 Pedido #' || v_num || ' saiu para entrega'; v_msg := 'O entregador do iFood está a caminho do cliente.';
  elsif v_cod in ('DELIVERY_CONCLUDED') or (v_cod = 'CONCLUDED' and s.modo = 'B') then v_est := 'entregue'; v_tit := '✅ Pedido #' || v_num || ' entregue pelo iFood'; v_msg := 'Confira e marque o pedido como entregue no sistema, se ainda não marcou.';
  elsif v_cod in ('DELIVERY_CANCELLED', 'DELIVERY_CANCELLATION_ACCEPTED') or (v_cod = 'CANCELLED' and s.modo = 'B') then v_est := 'cancelada'; v_tit := '🛵 Entrega do iFood cancelada (pedido #' || v_num || ')'; v_msg := 'A entrega pelo entregador do iFood foi cancelada.';
  elsif v_cod in ('DELIVERY_CANCELLATION_REQUESTED', 'CANCELLATION_REQUESTED') then v_est := 'cancelando'; v_tit := '🛵 Cancelamento da entrega pedido'; v_msg := 'Aguardando o iFood confirmar o cancelamento do pedido #' || v_num || '.';
  elsif v_cod in ('DELIVERY_CANCELLATION_REJECTED', 'CANCELLATION_REQUEST_FAILED') then v_est := 'alocada'; v_tit := '❌ O iFood recusou cancelar a entrega do pedido #' || v_num; v_msg := 'O entregador provavelmente já saiu. A entrega continua.';
  elsif v_cod = 'DELIVERY_ADDRESS_CHANGE_REQUESTED' then update ifood_ship set endereco_pendente = coalesce(p_meta, '{}'::jsonb) where id = s.id; v_tit := '📍 Cliente pediu para mudar o endereço (pedido #' || v_num || ')'; v_msg := 'Responda em até 15 minutos em iFood › Entregador do iFood (aceitar ou negar). Sem resposta o iFood nega sozinho.';
  elsif v_cod in ('DELIVERY_ADDRESS_CHANGE_ACCEPTED', 'DELIVERY_ADDRESS_CHANGE_DENIED', 'DELIVERY_ADDRESS_CHANGE_USER_CONFIRMED') then update ifood_ship set endereco_pendente = null where id = s.id; v_tit := '📍 Endereço do pedido #' || v_num || ': ' || case v_cod when 'DELIVERY_ADDRESS_CHANGE_ACCEPTED' then 'troca aceita' when 'DELIVERY_ADDRESS_CHANGE_DENIED' then 'troca negada' else 'confirmado pelo cliente' end;
    v_msg := case when p_meta->>'action' = 'region-mismatch' then 'O novo endereço é de outra região: o iFood negou sozinho.' else 'Veja o resultado em iFood › Entregador do iFood.' end;
  else return jsonb_build_object('achou', true, 'avisou', false); end if;
  if v_est is not null then update ifood_ship set estado = v_est, atualizado_em = now(), erro = case when v_est = 'falhou' then left(v_msg, 400) else null end where id = s.id; end if;
  -- custo da entrega vira despesa (uma vez só, quando a entrega é concluída)
  if v_est = 'entregue' and not s.custo_lancado and coalesce(s.valor, 0) > 0 then
    begin
      insert into despesas (descricao, valor, categoria, observacao, status, situacao, saiu_do_caixa, competencia, requisicao_id, origem_pagamento)
      values ('Entregador do iFood · pedido #' || v_num, s.valor, 'Entregadores', 'Descontado pelo iFood no repasse (Sob Demanda).', 'Paga', 'Paga', false, to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM'), 'ifood-ship-' || s.id, 'iFood');
      update ifood_ship set custo_lancado = true where id = s.id;
    exception when others then null; end;
  end if;
  perform ifood_aviso_registrar(s.pedido_ifood, v_tipo, v_tit, v_msg, jsonb_build_object('ship', s.id, 'codigo', v_cod));
  return jsonb_build_object('achou', true, 'avisou', true);
end $f$;

revoke all on function public.ifood_ship_dados(uuid), public.ifood_ship_resultado(uuid, text, jsonb, text), public.ifood_ship_evento(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.ifood_ship_dados(uuid), public.ifood_ship_resultado(uuid, text, jsonb, text), public.ifood_ship_evento(text, text, jsonb) to service_role;

-- corpo do pedido Sob Demanda (modo B), montado a partir da venda
create or replace function public.ifood_ship_payload_b(p_id uuid) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare s ifood_ship%rowtype; v vendas%rowtype; c ifood_ship_config%rowtype; e jsonb; v_tel text; v_tipo text := 'CUSTOMER'; v_area text; v_num text; v_pag jsonb; v_itens jsonb; v_marca text; v_met text; v_total numeric;
begin
  select * into s from ifood_ship where id = p_id;
  select * into v from vendas where id = s.venda_id;
  select * into c from ifood_ship_config where id;
  e := s.endereco;
  v_tel := regexp_replace(coalesce(v.telefone_cliente, ''), '\D', '', 'g');
  if v_tel like '55%' and length(v_tel) >= 12 then v_tel := substr(v_tel, 3); end if;
  if length(v_tel) in (10, 11) and left(v_tel, 1) <> '0' then v_area := left(v_tel, 2); v_num := substr(v_tel, 3);
  else v_tipo := 'STORE'; v_area := '00'; v_num := '000000000'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', it.id, 'name', left(coalesce(it.descricao, 'Item'), 50), 'quantity', it.quantidade, 'unitPrice', it.valor_unitario,
      'price', round(it.quantidade * it.valor_unitario, 2), 'optionsPrice', greatest(round(it.valor_total_item - it.quantidade * it.valor_unitario, 2), 0),
      'totalPrice', round(it.quantidade * it.valor_unitario, 2) + greatest(round(it.valor_total_item - it.quantidade * it.valor_unitario, 2), 0))), '[]'::jsonb)
    into v_itens from itens_venda it where it.venda_id = v.id;
  v_total := v.valor_total;
  if v.status_pagamento::text = 'Pago' then v_pag := null;          -- pago (online/antecipado): o corpo NÃO leva "payments"
  else
    v_met := case when v.forma_pagamento ilike '%dinheiro%' then 'CASH' when v.forma_pagamento ilike '%cr%dito%' then 'CREDIT' when v.forma_pagamento ilike '%d%bito%' then 'DEBIT' else null end;
    if v_met is null then return jsonb_build_object('erro', 'A forma de pagamento "' || coalesce(v.forma_pagamento, '?') || '" não pode ser cobrada na entrega pelo iFood. Receba antes (pago) ou use dinheiro/cartão.'); end if;
    select coalesce(m->>'brand', 'Visa') into v_marca from jsonb_array_elements(coalesce(s.quote->'paymentMethods', '[]'::jsonb)) m where upper(m->>'method') = v_met limit 1;
    v_pag := jsonb_build_object('methods', jsonb_build_array(case v_met when 'CASH' then jsonb_build_object('method', 'CASH', 'type', 'OFFLINE', 'value', v_total, 'cash', jsonb_build_object('changeFor', v_total))
      else jsonb_build_object('method', v_met, 'type', 'OFFLINE', 'value', v_total, 'card', jsonb_build_object('brand', coalesce(v_marca, 'Visa'))) end));
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'customer', jsonb_build_object('name', left(coalesce(nullif(btrim(v.cliente_nome), ''), 'Cliente'), 50), 'phone', jsonb_build_object('countryCode', '55', 'areaCode', v_area, 'number', v_num, 'type', v_tipo)),
    'delivery', jsonb_build_object('merchantFee', s.valor, 'preparationTime', c.preparo_seg, 'quoteId', s.quote_id,
      'deliveryAddress', jsonb_build_object('postalCode', regexp_replace(coalesce(e->>'cep', ''), '\D', '', 'g'), 'streetNumber', e->>'numero', 'streetName', e->>'rua', 'complement', nullif(e->>'complemento', ''),
        'reference', nullif(e->>'referencia', ''), 'neighborhood', e->>'bairro', 'city', e->>'cidade', 'state', upper(e->>'uf'), 'country', 'BR',
        'coordinates', jsonb_build_object('latitude', (e->>'lat')::float, 'longitude', (e->>'lng')::float))),
    'items', v_itens, 'payments', v_pag, 'telefoneTipo', v_tipo));
end $f$;
revoke all on function public.ifood_ship_payload_b(uuid) from public, anon, authenticated;
grant execute on function public.ifood_ship_payload_b(uuid) to service_role;


-- ======================================================================
-- 69-ifood-analytics.sql
-- ======================================================================
-- 69 · iFood Analytics (v1.20) — indicadores D-1 (dia anterior) do módulo Analytics (API de KPIs). Pode rodar de novo sem erro.
-- O módulo Analytics exige um SEGUNDO aplicativo no Portal do Desenvolvedor (categoria BI, "por merchant") com Client ID e Secret PRÓPRIOS.
-- Esses dois valores são digitados em Integrações › iFood (campos "BI"), com a senha do Admin. O servidor busca os números, guarda aqui e a tela só lê.

-- 1) campos novos permitidos (Client ID / Secret do app BI)
alter table public.integracoes_segredos drop constraint if exists integracoes_segredos_chave_check;
alter table public.integracoes_segredos add constraint integracoes_segredos_chave_check check (chave = any (array['ifood_client_id','ifood_client_secret','ifood_merchant_id','ifood_bi_client_id','ifood_bi_client_secret','mp_access_token_producao','mp_access_token_teste','mp_public_key_producao','mp_public_key_teste','mp_webhook_secret','nfce_csc','nfce_token_homologacao','nfce_token_producao','ip_handle','ip_chave_checkout','ip_webhook_segredo']));

do $d$
declare d text;
begin
  d := pg_get_functiondef('public.api_integracoes_salvar_segredo(jsonb)'::regprocedure);
  if position('ifood_bi_client_id' in d) = 0 then
    d := replace(d, '''ifood_merchant_id'',', '''ifood_merchant_id'', ''ifood_bi_client_id'', ''ifood_bi_client_secret'',');
    execute d;
  end if;
  d := pg_get_functiondef('public.api_integracoes_config(jsonb)'::regprocedure);
  if position('biHomologacao' in d) = 0 then
    d := replace(d, '''modoHomologacao'',', '''modoHomologacao'', ''biHomologacao'',');
    execute d;
  end if;
end $d$;

-- 2) nova ação da fila
alter table public.ifood_acoes drop constraint if exists ifood_acoes_acao_check;
alter table public.ifood_acoes add constraint ifood_acoes_acao_check check (acao = any (array['confirmar','iniciar_preparo','pronto','despachar','cancelar','negociacao_aceitar','negociacao_recusar','negociacao_alternativa','loja_fechar','loja_abrir','loja_pausar','loja_retomar','loja_horario_enviar','loja_horario_ler','catalogo_importar','catalogo_preco','catalogo_pausar','catalogo_retomar','catalogo_modelo_enviar','catalogo_lote_preco','catalogo_lote_status','catalogo_opcao_preco','catalogo_opcao_status','catalogo_diagnostico','avaliacao_responder','motivos','codigo_coleta','codigo_entrega','ship_cotar','ship_chamar','ship_cancelar','ship_motivos','ship_endereco','ship_safe','analytics_buscar']));

-- 3) token do app BI e resultados guardados
create table if not exists public.ifood_bi_token (
  id boolean primary key default true check (id),
  token text, expira_em timestamptz
);
insert into public.ifood_bi_token (id) values (true) on conflict do nothing;
alter table public.ifood_bi_token enable row level security;
revoke all on public.ifood_bi_token from anon, authenticated;

create table if not exists public.ifood_bi_dados (
  chave text primary key,
  de date not null, ate date not null,
  dados jsonb, erro text, buscando_desde timestamptz, buscado_em timestamptz,
  atualizado_em timestamptz not null default now()
);
alter table public.ifood_bi_dados enable row level security;
revoke all on public.ifood_bi_dados from anon, authenticated;

-- 4) só para a Edge Function
create or replace function public.ifood_bi_credenciais() returns jsonb
 language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object('clientId', (select valor from integracoes_segredos where chave = 'ifood_bi_client_id'),
    'clientSecret', (select valor from integracoes_segredos where chave = 'ifood_bi_client_secret'),
    'merchantId', (select valor from integracoes_segredos where chave = 'ifood_merchant_id'),
    'homologacao', coalesce((select (config->>'biHomologacao')::boolean from integracoes_config where provedor = 'ifood'), false))
$f$;
create or replace function public.ifood_bi_token_ler() returns jsonb
 language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object('token', token, 'expiraEm', expira_em) from ifood_bi_token where id and token is not null and expira_em > now() + interval '2 minutes'
$f$;
create or replace function public.ifood_bi_token_gravar(p_token text, p_seg integer) returns void
 language sql security definer set search_path to 'public' as $f$
  update ifood_bi_token set token = p_token, expira_em = now() + make_interval(secs => greatest(p_seg, 60)) where id
$f$;
create or replace function public.ifood_bi_gravar(p_chave text, p_dados jsonb, p_erro text default null) returns void
 language sql security definer set search_path to 'public' as $f$
  update ifood_bi_dados set dados = coalesce(p_dados, dados), erro = left(p_erro, 500), buscando_desde = null,
    buscado_em = case when p_erro is null then now() else buscado_em end, atualizado_em = now() where chave = p_chave
$f$;
revoke all on function public.ifood_bi_credenciais(), public.ifood_bi_token_ler(), public.ifood_bi_token_gravar(text, integer), public.ifood_bi_gravar(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.ifood_bi_credenciais(), public.ifood_bi_token_ler(), public.ifood_bi_token_gravar(text, integer), public.ifood_bi_gravar(text, jsonb, text) to service_role;

-- 5) telas (Admin)
create or replace function public.api_ifood_bi_ler(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare v_ontem date := (now() at time zone 'America/Sao_Paulo')::date - 1; v_de date; v_ate date; r ifood_bi_dados%rowtype; v_tem boolean;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_ate := coalesce(nullif(p->>'ate', '')::date, v_ontem);
  v_de := coalesce(nullif(p->>'de', '')::date, v_ate - 6);
  select count(*) = 2 into v_tem from integracoes_segredos where chave in ('ifood_bi_client_id', 'ifood_bi_client_secret');
  select * into r from ifood_bi_dados where chave = v_de::text || '|' || v_ate::text;
  return jsonb_build_object('ok', true, 'ontem', v_ontem, 'de', v_de, 'ate', v_ate, 'chavesOk', v_tem,
    'buscando', coalesce(r.buscando_desde > now() - interval '3 minutes', false), 'erro', r.erro, 'buscadoEm', r.buscado_em, 'dados', r.dados);
end $f$;

create or replace function public.api_ifood_bi_buscar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_ontem date := (now() at time zone 'America/Sao_Paulo')::date - 1; v_de date; v_ate date; v_ch text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not _integracao_ligada('ifood') then return _falha('O iFood está desligado.'); end if;
  begin v_de := (p->>'de')::date; v_ate := (p->>'ate')::date; exception when others then return _falha('Datas inválidas.'); end;
  if v_de is null or v_ate is null then return _falha('Escolha a data inicial e a final.'); end if;
  if v_de > v_ate then return _falha('A data inicial não pode ser depois da final.'); end if;
  if v_ate > v_ontem then return _falha('O iFood só entrega números até ONTEM (dados D-1). Escolha a data final de ontem ou antes.'); end if;
  if v_ate - v_de > 92 then return _falha('Escolha no máximo 93 dias por vez.'); end if;
  if (select count(*) from integracoes_segredos where chave in ('ifood_bi_client_id', 'ifood_bi_client_secret')) < 2 then
    return _falha('Antes, digite o Client ID e o Client Secret do aplicativo BI (Analytics) em Integrações › iFood. Ele é um segundo aplicativo no Portal do Desenvolvedor.');
  end if;
  v_ch := v_de::text || '|' || v_ate::text;
  if exists (select 1 from ifood_bi_dados where chave = v_ch and buscando_desde > now() - interval '3 minutes') then return jsonb_build_object('ok', true, 'message', 'Já estou buscando. Aguarde alguns segundos.'); end if;
  insert into ifood_bi_dados (chave, de, ate, buscando_desde) values (v_ch, v_de, v_ate, now())
    on conflict (chave) do update set buscando_desde = now(), erro = null, atualizado_em = now();
  perform _ifood_enfileirar('LOJA', 'analytics_buscar', jsonb_build_object('chave', 'bi-' || v_ch || '-' || floor(extract(epoch from now()) / 60)::text, 'bi', v_ch, 'de', v_de, 'ate', v_ate));
  return jsonb_build_object('ok', true, 'message', 'Buscando os números no iFood. Isto leva alguns segundos.');
end $f$;
revoke all on function public.api_ifood_bi_ler(jsonb), public.api_ifood_bi_buscar(jsonb) from public, anon;
grant execute on function public.api_ifood_bi_ler(jsonb), public.api_ifood_bi_buscar(jsonb) to authenticated, service_role;


-- ======================================================================
-- 70-ajuda-assistente-116.sql
-- ======================================================================
-- 70 - Assistente (versão 1.16): verbetes novos para as novidades do iFood (avisos, cardápio, avaliações, entregador, indicadores, roteiro). Pode rodar de novo (atualiza o texto).
-- Desfazer: delete from public.ai_ajuda where slug like 'man-116-%';
insert into public.ai_ajuda (slug,titulo,palavras_chave,passos,perfis,ativo,grupo,ordem,comuns) values
($t$man-116-01-ifood-avisos$t$,$t$iFood: avisos (pedido alterado, cancelamento recusado, endereço, devolução)$t$,$t$ifood avisos aviso pedido alterado cliente mudou cancelamento recusado endereço devolvido devolução preparo hora ideal visto notificação$t$,
$t$Integrações → iFood → "Avisos" junta o que o iFood mandou e pede atenção: o cliente alterou o pedido, o iFood recusou um cancelamento, o cliente mudou o endereço, o pedido voltou para a loja, a hora ideal de começar o preparo e o prazo para responder uma avaliação.
Cada aviso também chega como notificação. Toque em "Marcar todos como vistos" para limpar. Cancelamento: o motivo real (origem, código e motivo) aparece no pedido, em português.$t$,
ARRAY['Admin','Operador'],true,'secao',160,$t$Aviso sem leitura fica com a borda laranja. Se um pedido foi alterado, confira os itens antes de preparar.$t$),
($t$man-116-02-ifood-cardapio$t$,$t$iFood: cardápio no iFood, limites e diagnóstico$t$,$t$ifood cardápio catálogo item não aparece diagnóstico combo grupo complemento nome 100 descrição 500 preço zero enviar lote pausar$t$,
$t$Integrações → iFood → "Cardápio no iFood". Nome do item até 100 letras e descrição até 500. O preço do item precisa ser maior que zero (só complemento pode ser grátis). Em grupo de complementos o mínimo não pode passar do máximo.
Combo: marque "combo" e deixe como PRIMEIRO grupo o do item principal. Escolha também o tipo do grupo (escolha, ingredientes, ponto da carne, talheres).
Item que não aparece no app do iFood: toque em "Diagnóstico". O sistema pergunta ao iFood e mostra o motivo e o que fazer (categoria pausada, item pausado, sem preço, grupo obrigatório sem complemento).$t$,
ARRAY['Admin'],true,'secao',161,$t$Foto: JPG ou PNG de até 5 MB. Se o iFood recusar, o motivo em português aparece no item.$t$),
($t$man-116-03-ifood-avaliacoes$t$,$t$iFood: avaliações e como responder$t$,$t$ifood avaliações avaliação nota comentário responder resposta prazo cliente estrelas$t$,
$t$Integrações → iFood → "Avaliações" mostra nota, comentário, nome do cliente e até quando dá para responder. Escreva a resposta (de 10 a 300 letras), toque em responder e digite a sua senha. A tela mostra se o iFood aceitou ou recusou, e por quê.
Nota baixa e prazo acabando geram aviso. A "Sugerir resposta" escreve um rascunho que você lê e ajusta antes de enviar.$t$,
ARRAY['Admin'],true,'secao',162,$t$Resposta curta demais ou longa demais é recusada antes de ir ao iFood.$t$),
($t$man-116-04-ifood-entregador$t$,$t$iFood: entregador do iFood (Sob Demanda): cotar, chamar, rastrear e cancelar$t$,$t$ifood entregador sob demanda shipping cotação chamar entregador rastreio rastrear código cancelar corrida confiança endereço troca balcão whatsapp cardápio próprio custo$t$,
$t$Está DESLIGADO por padrão. Contrate "Sob Demanda" no Portal do Parceiro, abra Integrações → iFood → "Entregador do iFood", informe cidade, UF e tempo de preparo e ligue (pede a sua senha).
Para cada pedido de ENTREGA: "Pedir cotação (grátis)" mostra valor, tempo e distância. "Chamar entregador" cobra a corrida e pede a senha. Pedido que não veio do iFood precisa de endereço completo, CEP e latitude/longitude (no Google Maps, toque e segure no endereço).
Depois: acompanhe o estado, copie o link de rastreio para o cliente, veja o código de 4 dígitos que o cliente fala ao entregador e o nível de confiança. Troca de endereço pedida pelo cliente: aceite ou negue em até 15 minutos. Cancelar pede a senha (em pedido de fora do iFood, escolha um dos motivos do iFood). O valor da corrida vira despesa "Entregadores".$t$,
ARRAY['Admin'],true,'secao',163,$t$Cotação vale cerca de 24 horas. Erro do iFood (fora da área, muita demanda, fora do horário) aparece em português.$t$),
($t$man-116-05-ifood-indicadores$t$,$t$iFood: indicadores (faturamento, ticket, cancelamento) até ontem$t$,$t$ifood indicadores analytics faturamento gmv ticket médio cancelamento canal pagamento dia hora tempo ontem d-1 bi aplicativo relatório$t$,
$t$Integrações → iFood → "Indicadores (até ontem)". Escolha o período (ou Ontem, 7 dias, 30 dias, Mês passado) e toque em "Buscar no iFood". Aparecem faturamento, pedidos concluídos, ticket médio, % de cancelamento, e quebras por situação, canal, quem entregou, pagamento, dia da semana, hora e tempos médios.
Os números do iFood chegam com 1 dia de atraso (D-1): hoje nunca aparece. Precisa do Client ID e do Secret de um SEGUNDO aplicativo (categoria BI) do Portal do Desenvolvedor, digitados em Integrações → iFood.$t$,
ARRAY['Admin'],true,'secao',164,$t$Servem para comparar dias e horários, não para fechar o caixa. Se der 403, o iFood ainda não liberou o Analytics para o aplicativo.$t$),
($t$man-116-06-ifood-roteiro$t$,$t$iFood: roteiro de homologação por módulo$t$,$t$ifood homologação roteiro módulo passos testar aprovar portal desenvolvedor checklist estado dos módulos$t$,
$t$Integrações → iFood → "📋 Roteiro de homologação": para cada módulo (acesso, eventos, pedidos, loja, cardápio, avaliações, financeiro, entrega e indicadores) mostra o que fazer, o que mostrar ao iFood e se o módulo já respondeu OK. Use junto com "🩺 Estado dos módulos".$t$,
ARRAY['Admin'],true,'secao',165,$t$As caixinhas do roteiro ficam só no aparelho em que foram marcadas.$t$)
on conflict (slug) do update set titulo=excluded.titulo, palavras_chave=excluded.palavras_chave, passos=excluded.passos, perfis=excluded.perfis, ativo=excluded.ativo, grupo=excluded.grupo, ordem=excluded.ordem, comuns=excluded.comuns, atualizado_em=now();


-- ======================================================================
-- 71-ifood-fechar-funcoes-internas.sql
-- ======================================================================
-- 71 · Segurança (auditoria final 25/10/2026) — funções internas do iFood só para o servidor. Pode rodar de novo sem erro.
-- Estas funções são usadas só pela Edge Function ifood-sync (chave de serviço). Antes, qualquer pessoa logada podia chamá-las pela API.
revoke all on function public.ifood_horario_gravar(jsonb), public.ifood_cat_arvore(uuid), public.ifood_cat_resultado(uuid, text, text, jsonb), public.ifood_cat_patch(uuid, jsonb), public._ifood_lacuna_varrer(bigint) from public, anon, authenticated;
grant execute on function public.ifood_horario_gravar(jsonb), public.ifood_cat_arvore(uuid), public.ifood_cat_resultado(uuid, text, text, jsonb), public.ifood_cat_patch(uuid, jsonb), public._ifood_lacuna_varrer(bigint) to service_role;

-- Auditoria geral (mesmo dia): funções internas de margem (mostravam preço, CUSTO e margem a quem não estava logado) e de alertas (disparo livre).
-- Só o servidor e as rotinas automáticas (donas das funções) usam estas funções.
revoke all on function public._margem_baixa(), public._margem_min_cat(uuid), public._margem_minima(), public._margem_pior_por_categoria(), public.alertas_pedidos_cron(), public.alertas_sistema_cron() from public, anon, authenticated;
grant execute on function public._margem_baixa(), public._margem_min_cat(uuid), public._margem_minima(), public._margem_pior_por_categoria(), public.alertas_pedidos_cron(), public.alertas_sistema_cron() to service_role;

-- Auditoria geral: funções auxiliares sem "search_path" fixo (aviso do Supabase).
do $d$ declare r record; begin
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.proname in ('_ifood_fin_banco','_ifood_fin_bool','_ifood_fin_d','_ifood_fin_hoje','_ifood_fin_segunda','_ifood_fin_ts','_ifood_inelegivel_txt','_ifood_ship_erro_txt','_ifood_validacao_txt','_pag_nome')
      and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))
  loop execute 'alter function ' || r.f || ' set search_path = public, pg_temp'; end loop;
end $d$;


-- ======================================================================
-- 72-ifood-saude-so-recente.sql
-- ======================================================================
-- 72 · Saúde do sistema: o iFood só fica amarelo por ação com erro/dúvida das ÚLTIMAS 2 HORAS
-- (antes era 1 dia, e erros antigos mantinham o alerta aceso à toa). Os erros continuam visíveis na tela do iFood. Idempotente.
do $$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname='_saude_integracoes';
  if d like '%ifood_acoes where estado in (''erro'', ''duvida'') and criado_em > now() - interval ''1 day''%' then
    d := replace(d, 'ifood_acoes where estado in (''erro'', ''duvida'') and criado_em > now() - interval ''1 day''', 'ifood_acoes where estado in (''erro'', ''duvida'') and criado_em > now() - interval ''2 hours''');
    execute d;
  end if;
end $$;


-- ======================================================================
-- 73-ifood-preco-automatico.sql
-- ======================================================================
-- 73 · Preço do iFood sincroniza sozinho: ao salvar o preço da forma "iFood" de um produto/combo ligado a um item do iFood,
-- o sistema envia o novo preço ao iFood (usa a trava de variação e o histórico que já existiam). Idempotente.
-- Acima do limite de variação NÃO envia: cria um aviso na tela do iFood. Só funciona com o iFood ligado e "enviarPrecos" ligado.
create or replace function public._ifood_preco_auto() returns trigger
 language plpgsql security definer set search_path to 'public' as $f$
declare r ifood_itens%rowtype; v_lim numeric; v_pct numeric; v_id bigint; v_ped bigint; v_prod uuid := nullif(to_jsonb(NEW)->>'produto_id', '')::uuid; v_combo uuid := nullif(to_jsonb(NEW)->>'combo_id', '')::uuid;
begin
  if NEW.forma_pagamento_id is distinct from public._ifood_forma() or NEW.preco is null or NEW.preco <= 0 then return NEW; end if;
  if tg_op = 'UPDATE' and OLD.preco is not distinct from NEW.preco then return NEW; end if;
  if not public._integracao_ligada('ifood') then return NEW; end if;
  if not coalesce((select (config->>'enviarPrecos')::boolean from integracoes_config where provedor = 'ifood'), false) then return NEW; end if;
  v_lim := coalesce((select (config->>'limitePrecoPct')::numeric from integracoes_config where provedor = 'ifood'), 30);
  for r in select * from ifood_itens where ifood_item_id is not null
           and ((v_prod is not null and produto_id = v_prod) or (v_combo is not null and combo_id = v_combo)) loop
    if r.preco_ifood is not null and r.preco_ifood > 0 and abs(r.preco_ifood - NEW.preco) < 0.005 then continue; end if;
    v_pct := case when coalesce(r.preco_ifood, 0) > 0 then abs(NEW.preco - r.preco_ifood) / r.preco_ifood * 100 else 0 end;
    if v_pct > v_lim then
      perform public.ifood_aviso_registrar(null, 'preco', 'Preço NÃO enviado ao iFood: ' || left(r.nome, 80),
        'O novo preço (R$ ' || to_char(NEW.preco, 'FM999990.00') || ') varia ' || round(v_pct) || '% em relação ao do iFood (R$ ' || to_char(r.preco_ifood, 'FM999990.00') || '), acima do limite de ' || v_lim || '%. Confira e envie manualmente em Preços do iFood.', jsonb_build_object('chave', r.chave));
      continue;
    end if;
    -- um envio pendente do mesmo item é atualizado em vez de duplicado
    select id into v_ped from ifood_acoes where acao = 'catalogo_preco' and estado = 'pendente' and dados->>'chave' = r.chave limit 1;
    insert into ifood_precos_hist (chave, nome, preco_antes, preco_depois, origem, usuario) values (r.chave, r.nome, r.preco_ifood, NEW.preco, 'enviar', 'automático') returning id into v_id;
    if v_ped is not null then
      update ifood_acoes set dados = jsonb_build_object('chave', r.chave, 'itemId', r.ifood_item_id, 'preco', NEW.preco, 'hist', v_id) where id = v_ped;
    else
      insert into ifood_acoes (pedido_ifood, acao, dados) values ('LOJA', 'catalogo_preco', jsonb_build_object('chave', r.chave, 'itemId', r.ifood_item_id, 'preco', NEW.preco, 'hist', v_id)) on conflict do nothing;
    end if;
  end loop;
  return NEW;
exception when others then
  -- nunca atrapalha o salvamento do preço; o motivo fica visível para a equipe
  begin perform public.ifood_aviso_registrar(null, 'preco', 'Falha ao enviar preço ao iFood', left(sqlerrm, 300), '{}'::jsonb); exception when others then null; end;
  return NEW;
end $f$;
revoke all on function public._ifood_preco_auto() from public, anon, authenticated;
grant execute on function public._ifood_preco_auto() to service_role;

drop trigger if exists ifood_preco_auto_p on public.produto_precos;
create trigger ifood_preco_auto_p after insert or update of preco on public.produto_precos for each row execute function public._ifood_preco_auto();
drop trigger if exists ifood_preco_auto_c on public.combo_precos;
create trigger ifood_preco_auto_c after insert or update of preco on public.combo_precos for each row execute function public._ifood_preco_auto();

update public.integracoes_config set config = coalesce(config, '{}'::jsonb) || '{"enviarPrecos": true}'::jsonb where provedor = 'ifood';


-- ======================================================================
-- 74-ifood-ligar-sozinho.sql
-- ======================================================================
-- 74 · Itens do iFood se ligam sozinhos quando o nome é EXATAMENTE igual ao de um produto, combo ou adicional ativo
-- (mesma regra da "sugestão"). Ficam marcados como "ligado automaticamente" e continuam com o botão Desfazer. Idempotente.
alter table public.ifood_itens add column if not exists ligado_auto boolean not null default false;

do $$
declare d text; n int;
begin
  -- 1) todo item visto (pedido ou cardápio) tenta a ligação pelo nome igual
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = '_ifood_item_visto' and p.pronamespace = 'public'::regnamespace;
  if d not like '%ligado_auto%' then
    d := replace(d, 'declare r ifood_itens%rowtype; v_u uuid;', 'declare r ifood_itens%rowtype; v_u uuid; s jsonb;');
    n := (length(d) - length(replace(d, E'  end if;\n  return r;\nend', ''))) / length(E'  end if;\n  return r;\nend');
    if n <> 1 then raise exception '_ifood_item_visto mudou (fim: %)', n; end if;
    d := replace(d, E'  end if;\n  return r;\nend', $x$  end if;
  if r.produto_id is null and r.combo_id is null and r.adicional_id is null and not r.ignorar then
    s := public._ifood_sugestao(r.nome, p_tipo);
    if s is not null then
      update ifood_itens set produto_id = case when s->>'tipo' = 'produto' then (s->>'id')::uuid end, combo_id = case when s->>'tipo' = 'combo' then (s->>'id')::uuid end,
        adicional_id = case when s->>'tipo' = 'adicional' then (s->>'id')::uuid end, ligado_em = now(), ligado_auto = true where chave = p_chave returning * into r;
    end if;
  end if;
  return r;
end$x$);
    execute d;
  end if;
  -- 2) a lista de itens informa quais foram ligados sozinhos
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'api_ifood_itens' and p.pronamespace = 'public'::regnamespace;
  if d not like '%ligado_auto%' then
    d := replace(d, '''ignorar'', i.ignorar,', '''ignorar'', i.ignorar, ''auto'', i.ligado_auto,'); execute d;
  end if;
  -- 3) ligar/desfazer à mão tira a marca de automático
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'api_ifood_ligar_item' and p.pronamespace = 'public'::regnamespace;
  if d not like '%ligado_auto%' then
    d := replace(replace(d, 'ligado_em = now()', 'ligado_em = now(), ligado_auto = false'), 'ligado_em = null where', 'ligado_em = null, ligado_auto = false where'); execute d;
  end if;
end $$;

-- 4) liga agora os que já estão esperando (nome exatamente igual)
do $$
declare r record; s jsonb; k int := 0;
begin
  for r in select chave, nome, tipo from ifood_itens where produto_id is null and combo_id is null and adicional_id is null and not ignorar loop
    s := public._ifood_sugestao(r.nome, r.tipo);
    if s is null then continue; end if;
    update ifood_itens set produto_id = case when s->>'tipo' = 'produto' then (s->>'id')::uuid end, combo_id = case when s->>'tipo' = 'combo' then (s->>'id')::uuid end,
      adicional_id = case when s->>'tipo' = 'adicional' then (s->>'id')::uuid end, ligado_em = now(), ligado_auto = true where chave = r.chave;
    k := k + 1;
  end loop;
  if k > 0 then perform public._auditar('Itens do iFood ligados automaticamente', k || ' item(ns) pelo nome igual'); end if;
end $$;


-- ======================================================================
-- 75-limpeza-registros-tecnicos.sql
-- ======================================================================
-- 75 · Registros técnicos guardados por menos tempo (o banco fica menor). Idempotente.
-- Histórico das tarefas automáticas: as que deram certo ficam 1 dia (antes 3); as com erro continuam 14 dias.
select cron.alter_job((select jobid from cron.job where jobname = 'limpar-historico-cron'), command := $c$delete from cron.job_run_details
       where (status = 'succeeded' and start_time < now() - interval '1 day')
          or start_time < now() - interval '14 days'$c$);
-- Fila de cópia para as planilhas: o que já foi copiado fica 7 dias (antes 30).
do $$ declare d text; begin
  select pg_get_functiondef('public.api_sync_limpar()'::regprocedure) into d;
  if d like '%interval ''30 days''%' then execute replace(d, 'interval ''30 days''', 'interval ''7 days'''); end if;
end $$;


-- ======================================================================
-- 76-clientes-unir-ifood.sql
-- ======================================================================
-- 76 · Cliente do iFood (sem telefone) se junta ao cadastro do sistema (com telefone) quando NOME e ENDEREÇO batem.
-- Mantém o cadastro do sistema (telefone, fidelidade, conta Google) e acrescenta o código do cliente no iFood.
-- Tudo fica registrado em clientes_unioes e pode ser desfeito. Nada é apagado: o cadastro do iFood fica escondido (unido_com). Idempotente.
alter table public.clientes add column if not exists ligado_auto boolean not null default false;
alter table public.clientes add column if not exists unido_com uuid;
create index if not exists clientes_unido_com_idx on public.clientes (unido_com) where unido_com is not null;

create table if not exists public.clientes_unioes (
  id bigserial primary key,
  quando timestamptz not null default now(),
  s_id uuid not null,            -- cadastro do sistema (fica)
  f_id uuid not null,            -- cadastro do iFood (escondido)
  f_ifood_id text,
  f_nome text,
  s_endereco_antes text,
  auto boolean not null default false,
  por text,
  movidos jsonb not null default '{}'::jsonb,
  fidelidade jsonb not null default '{}'::jsonb,
  desfeito_em timestamptz,
  desfeito_por text
);
alter table public.clientes_unioes enable row level security;
revoke all on public.clientes_unioes from public, anon, authenticated;
grant all on public.clientes_unioes to service_role;

-- chave do endereço: "rua|número" (sem Av/Rua, sem acento). Null se não der para ler rua e número.
create or replace function public._end_chave(p text) returns text
 language plpgsql immutable set search_path to 'public' as $f$
declare s text; num text; rua text;
begin
  s := lower(translate(coalesce(p, ''), 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç', 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc'));
  s := btrim(regexp_replace(regexp_replace(s, '[^a-z0-9,]', ' ', 'g'), '\s+', ' ', 'g'));
  if s = '' then return null; end if;
  num := coalesce((regexp_match(s, ',\s*(\d+)'))[1], (regexp_match(s, '\s(\d+)(?:\s|,|$)'))[1]);
  if num is null then return null; end if;
  rua := case when position(',' in s) > 0 then split_part(s, ',', 1) else regexp_replace(s, '\s+' || num || '(\s.*)?$', '') end;
  rua := btrim(regexp_replace(rua, '^(av|avenida|r|rua|al|alameda|tv|travessa|pca|praca|rod|rodovia|est|estrada|vl|vila)\s+', ''));
  if length(rua) < 3 then return null; end if;
  return rua || '|' || num;
end $f$;

create or replace function public._end_confere(a text, b text) returns boolean
 language plpgsql immutable set search_path to 'public' as $f$
declare ka text := public._end_chave(a); kb text := public._end_chave(b); ra text; rb text;
begin
  if ka is null or kb is null then return false; end if;
  if ka = kb then return true; end if;
  if split_part(ka, '|', 2) <> split_part(kb, '|', 2) then return false; end if;
  ra := split_part(ka, '|', 1); rb := split_part(kb, '|', 1);
  return (length(ra) >= 5 and position(ra in rb) > 0) or (length(rb) >= 5 and position(rb in ra) > 0);
end $f$;

-- o cliente do sistema (s) tem este endereço no cadastro ou em algum pedido de entrega anterior?
create or replace function public._cliente_tem_endereco(p_s uuid, p_end text) returns boolean
 language sql stable security definer set search_path to 'public' as $f$
  select exists (select 1 from clientes c where c.id = p_s and public._end_confere(c.endereco, p_end))
      or exists (select 1 from vendas v where v.cliente_id = p_s and v.endereco is not null and public._end_confere(v.endereco, p_end))
$f$;

-- junta o cadastro do iFood (p_f) ao cadastro do sistema (p_s)
create or replace function public._cliente_unir(p_f uuid, p_s uuid, p_auto boolean, p_por text) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare f clientes%rowtype; s clientes%rowtype; t record; ids jsonb; mov jsonb := '{}'::jsonb; fid jsonb := '{}'::jsonb;
  ff fidelidade%rowtype; fs fidelidade%rowtype; v_log bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('cliente-unir', 0));
  select * into f from clientes where id = p_f for update;
  select * into s from clientes where id = p_s for update;
  if f.id is null or s.id is null or f.id = s.id then return jsonb_build_object('ok', false, 'message', 'Cadastro não encontrado.'); end if;
  if f.ifood_id is null or f.unido_com is not null or btrim(coalesce(f.telefone, '')) <> '' then return jsonb_build_object('ok', false, 'message', 'O primeiro cadastro precisa ser de um cliente do iFood, sem telefone.'); end if;
  if s.ifood_id is not null or s.unido_com is not null or btrim(coalesce(s.telefone, '')) = '' then return jsonb_build_object('ok', false, 'message', 'O segundo cadastro precisa ser um cliente do sistema, com telefone, que ainda não esteja ligado ao iFood.'); end if;
  insert into clientes_unioes (s_id, f_id, f_ifood_id, f_nome, s_endereco_antes, auto, por) values (s.id, f.id, f.ifood_id, f.nome, s.endereco, p_auto, p_por) returning id into v_log;
  for t in select * from (values ('vendas','cliente_id','id'), ('cupons','cliente_id','id'), ('cupons_usos','cliente_id','id'), ('feedbacks','cliente_id','id'), ('brindes','cliente_id','id'),
      ('indicacoes','indicador_id','id'), ('indicacoes','indicado_id','id'), ('fidelidade_marcas','cliente_id','venda_id'), ('vendas_resumo_arquivo','cliente_id','venda_id'),
      ('anonimizar_arquivo_fila','cliente_id','id'), ('contas_cliente','cliente_id','user_id')) x(tab, col, pk) loop
    if t.tab = 'contas_cliente' and exists (select 1 from contas_cliente where cliente_id = s.id) then continue; end if;
    execute format('with m as (update public.%I set %I = $1 where %I = $2 returning %I::text k) select coalesce(jsonb_agg(k), ''[]''::jsonb) from m', t.tab, t.col, t.col, t.pk) into ids using s.id, f.id;
    if jsonb_array_length(ids) > 0 then mov := mov || jsonb_build_object(t.tab || '.' || t.col || '.' || t.pk, ids); end if;
  end loop;
  select * into ff from fidelidade where cliente_id = f.id; select * into fs from fidelidade where cliente_id = s.id;
  if ff.id is not null and fs.id is null then
    update fidelidade set cliente_id = s.id where id = ff.id; fid := jsonb_build_object('moveu', ff.id);
  elsif ff.id is not null and fs.id is not null then
    fid := jsonb_build_object('soma', jsonb_build_object('f_fid', ff.id, 's_fid', fs.id, 'carimbos', ff.carimbos, 'premios', ff.premios_resgatados));
    update fidelidade set carimbos = carimbos + ff.carimbos, premios_resgatados = premios_resgatados + ff.premios_resgatados, atualizada_em = now() where id = fs.id;
    update fidelidade set carimbos = 0, premios_resgatados = 0 where id = ff.id;
  end if;
  update clientes set ifood_id = null, unido_com = s.id where id = f.id;
  update clientes set ifood_id = f.ifood_id, ligado_auto = p_auto, endereco = coalesce(nullif(btrim(endereco), ''), f.endereco) where id = s.id;
  update clientes_unioes set movidos = mov, fidelidade = fid where id = v_log;
  perform _auditar(case when p_auto then 'Clientes unidos (automático: nome e endereço)' else 'Clientes unidos (manual)' end, f.nome || ' (iFood) → ' || s.nome || ' · ' || coalesce(s.telefone, ''));
  return jsonb_build_object('ok', true, 'sId', s.id, 'log', v_log);
end $f$;
revoke all on function public._cliente_unir(uuid, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public._cliente_unir(uuid, uuid, boolean, text) to service_role;

-- desfaz a última junção do cadastro do sistema (s)
create or replace function public._cliente_desunir(p_s uuid, p_por text) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare u clientes_unioes%rowtype; k text; ids jsonb; tab text; col text; pk text;
begin
  perform pg_advisory_xact_lock(hashtextextended('cliente-unir', 0));
  select * into u from clientes_unioes where s_id = p_s and desfeito_em is null order by id desc limit 1;
  if u.id is null then return jsonb_build_object('ok', false, 'message', 'Este cliente não tem uma junção para desfazer.'); end if;
  update clientes set ifood_id = null, ligado_auto = false, endereco = u.s_endereco_antes where id = u.s_id;
  update clientes set ifood_id = u.f_ifood_id, unido_com = null where id = u.f_id;
  for k, ids in select key, value from jsonb_each(u.movidos) loop
    tab := split_part(k, '.', 1); col := split_part(k, '.', 2); pk := split_part(k, '.', 3);
    execute format('update public.%I set %I = $1 where %I::text in (select jsonb_array_elements_text($2))', tab, col, pk) using u.f_id, ids;
  end loop;
  if u.fidelidade ? 'moveu' then
    update fidelidade set cliente_id = u.f_id where id = (u.fidelidade->>'moveu')::uuid;
  elsif u.fidelidade ? 'soma' then
    update fidelidade set carimbos = carimbos - (u.fidelidade->'soma'->>'carimbos')::int, premios_resgatados = premios_resgatados - (u.fidelidade->'soma'->>'premios')::int where id = (u.fidelidade->'soma'->>'s_fid')::uuid;
    update fidelidade set carimbos = (u.fidelidade->'soma'->>'carimbos')::int, premios_resgatados = (u.fidelidade->'soma'->>'premios')::int where id = (u.fidelidade->'soma'->>'f_fid')::uuid;
  end if;
  update clientes_unioes set desfeito_em = now(), desfeito_por = p_por where id = u.id;
  perform _auditar('Junção de clientes desfeita', coalesce(u.f_nome, '') || ' voltou a ser um cadastro do iFood');
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public._cliente_desunir(uuid, text) from public, anon, authenticated;
grant execute on function public._cliente_desunir(uuid, text) to service_role;

-- procura o ÚNICO cliente do sistema com o mesmo nome e endereço do cliente do iFood (f). Devolve o id dele ou null.
create or replace function public._cliente_par_do_ifood(p_f uuid) returns uuid
 language plpgsql stable security definer set search_path to 'public' as $f$
declare f clientes%rowtype; r uuid[];
begin
  select * into f from clientes where id = p_f;
  if f.id is null or f.ifood_id is null or f.unido_com is not null or btrim(coalesce(f.telefone, '')) <> '' then return null; end if;
  if public._end_chave(f.endereco) is null or length(public._ifood_norm(f.nome)) < 3 then return null; end if;
  select array_agg(c.id) into r from clientes c
   where c.ifood_id is null and c.unido_com is null and btrim(coalesce(c.telefone, '')) <> '' and public._ifood_norm(c.nome) = public._ifood_norm(f.nome)
     and public._cliente_tem_endereco(c.id, f.endereco)
     and not exists (select 1 from clientes_unioes u where u.f_id = f.id and u.s_id = c.id and u.desfeito_em is not null);
  return case when coalesce(array_length(r, 1), 0) = 1 then r[1] end;
end $f$;
revoke all on function public._cliente_par_do_ifood(uuid) from public, anon, authenticated;
grant execute on function public._cliente_par_do_ifood(uuid) to service_role;

-- quando um cliente do sistema é criado ou muda nome/telefone/endereço: procura o cadastro do iFood com o mesmo nome e endereço
create or replace function public._clientes_auto_unir() returns trigger
 language plpgsql security definer set search_path to 'public' as $f$
declare r uuid[]; v_f uuid;
begin
  if NEW.ifood_id is not null or NEW.unido_com is not null or btrim(coalesce(NEW.telefone, '')) = '' then return NEW; end if;
  if length(public._ifood_norm(NEW.nome)) < 3 then return NEW; end if;
  select array_agg(c.id) into r from clientes c
   where c.ifood_id is not null and c.unido_com is null and btrim(coalesce(c.telefone, '')) = '' and public._ifood_norm(c.nome) = public._ifood_norm(NEW.nome)
     and public._cliente_tem_endereco(NEW.id, c.endereco)
     and not exists (select 1 from clientes_unioes u where u.f_id = c.id and u.s_id = NEW.id and u.desfeito_em is not null);
  if coalesce(array_length(r, 1), 0) = 1 then v_f := r[1]; perform public._cliente_unir(v_f, NEW.id, true, 'automático'); end if;
  return NEW;
exception when others then
  begin perform public.ifood_aviso_registrar(null, 'cliente', 'Não consegui juntar um cliente do iFood automaticamente', left(sqlerrm, 300), '{}'::jsonb); exception when others then null; end;
  return NEW;
end $f$;
revoke all on function public._clientes_auto_unir() from public, anon, authenticated;
grant execute on function public._clientes_auto_unir() to service_role;
drop trigger if exists clientes_auto_unir on public.clientes;
create trigger clientes_auto_unir after insert or update of nome, telefone, endereco on public.clientes
  for each row when (pg_trigger_depth() < 2) execute function public._clientes_auto_unir();

-- pedido do iFood: tenta juntar o cliente ao cadastro do sistema e, se tiver telefone, coloca o telefone na comanda
do $$ declare d text;
begin
  select pg_get_functiondef('public._ifood_cliente(uuid, jsonb)'::regprocedure) into d;
  if d not like '%_cliente_par_do_ifood%' then
    if (length(d) - length(replace(d, E'  update vendas set cliente_id = v_id where id = p_venda and cliente_id is null;\n  return v_id;', ''))) = 0 then raise exception '_ifood_cliente mudou'; end if;
    d := replace(d, E'  update vendas set cliente_id = v_id where id = p_venda and cliente_id is null;\n  return v_id;',
$x$  declare v_par uuid; v_u jsonb;
  begin
    v_par := public._cliente_par_do_ifood(v_id);
    if v_par is not null then v_u := public._cliente_unir(v_id, v_par, true, 'automático'); if coalesce((v_u->>'ok')::boolean, false) then v_id := v_par; end if; end if;
  exception when others then
    begin perform public.ifood_aviso_registrar(null, 'cliente', 'Não consegui juntar o cliente do iFood ao cadastro', left(sqlerrm, 300), '{}'::jsonb); exception when others then null; end;
  end;
  update vendas set cliente_id = v_id where id = p_venda and cliente_id is null;
  declare v_tel text;
  begin
    select nullif(btrim(telefone), '') into v_tel from clientes where id = v_id;
    if v_tel is not null then update vendas set telefone_cliente = v_tel where id = p_venda; end if;
  end;
  return v_id;$x$);
    execute d;
  end if;
end $$;

-- a lista de fidelidade não mostra cadastros escondidos
create or replace view public.v_fidelidade as
 select c.nome, c.telefone, f.carimbos, f.premios_resgatados as premios, f.atualizada_em as atualizado, f.observacoes as observacao, f.cliente_id
   from public.fidelidade f join public.clientes c on c.id = f.cliente_id
  where c.unido_com is null;

-- telas: unir (manual, com senha) e desfazer
create or replace function public.api_unir_clientes(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_f uuid := _uuid(p->>'ifoodClienteId'); v_s uuid := _uuid(p->>'sistemaClienteId'); v_aut text; r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(btrim(p->>'senhaAdminConfirmacao'), '') = '' then return _falha('Digite a sua senha para confirmar (a senha é pedida sempre, inclusive para o Admin).'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  r := public._cliente_unir(v_f, v_s, false, v_aut);
  if not coalesce((r->>'ok')::boolean, false) then return _falha(coalesce(r->>'message', 'Não foi possível juntar.')); end if;
  return jsonb_build_object('ok', true, 'message', 'Cadastros juntados. O telefone, a fidelidade e o histórico agora são de um cliente só.');
end $f$;
create or replace function public.api_desunir_cliente(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_s uuid := _uuid(p->>'id'); v_aut text; r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce(btrim(p->>'senhaAdminConfirmacao'), '') = '' then return _falha('Digite a sua senha para confirmar (a senha é pedida sempre, inclusive para o Admin).'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  r := public._cliente_desunir(v_s, v_aut);
  if not coalesce((r->>'ok')::boolean, false) then return _falha(coalesce(r->>'message', 'Não foi possível desfazer.')); end if;
  return jsonb_build_object('ok', true, 'message', 'Junção desfeita: o cliente do iFood voltou a ser um cadastro separado.');
end $f$;
revoke all on function public.api_unir_clientes(jsonb), public.api_desunir_cliente(jsonb) from public, anon;
grant execute on function public.api_unir_clientes(jsonb), public.api_desunir_cliente(jsonb) to authenticated, service_role;

-- tela do cliente: (a) cliente do sistema → nomes com que ele aparece no iFood; (b) cliente do iFood → sugestões para unir (mostra o motivo)
create or replace function public.api_cliente_ifood_info(p jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare v_id uuid := _uuid(p->>'id'); c clientes%rowtype; un jsonb; sug jsonb;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into c from clientes where id = v_id;
  if c.id is null then return jsonb_build_object('ok', true, 'unioes', '[]'::jsonb, 'sugestoes', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('nomeIfood', u.f_nome, 'ifoodId', u.f_ifood_id, 'quando', u.quando, 'auto', u.auto, 'igual', public._ifood_norm(u.f_nome) = public._ifood_norm(c.nome)) order by u.id), '[]'::jsonb)
    into un from clientes_unioes u where u.s_id = c.id and u.desfeito_em is null;
  if c.ifood_id is not null and btrim(coalesce(c.telefone, '')) = '' and c.unido_com is null then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into sug from (
      select jsonb_build_object('id', s.id, 'nome', s.nome, 'telefone', s.telefone, 'endereco', s.endereco,
               'motivo', case when n and e then 'nome e endereço iguais' when e then 'mesmo endereço, nome diferente' else 'mesmo nome, endereço não confere' end) x
        from (select s.*, public._ifood_norm(s.nome) = public._ifood_norm(c.nome) n,
                (public._cliente_tem_endereco(s.id, c.endereco) or exists (select 1 from vendas v where v.cliente_id = c.id and v.endereco is not null and public._cliente_tem_endereco(s.id, v.endereco))) e
                from clientes s where s.ifood_id is null and s.unido_com is null and btrim(coalesce(s.telefone, '')) <> '') s
       where n or e order by (n and e) desc, e desc limit 5) q;
  end if;
  return jsonb_build_object('ok', true, 'unioes', un, 'sugestoes', coalesce(sug, '[]'::jsonb));
end $f$;
revoke all on function public.api_cliente_ifood_info(jsonb) from public, anon;
grant execute on function public.api_cliente_ifood_info(jsonb) to authenticated, service_role;


-- ======================================================================
-- 77-dono-sem-ponto-e-folha.sql
-- ======================================================================
-- 77 · "Dono": pessoa que não bate ponto e não entra na folha (hoje só o Jonatan). Qualquer outro Admin cadastrado continua batendo ponto e entrando na folha.
alter table public.funcionarios add column if not exists dono boolean not null default false;

do $$ declare x record; d text;
begin
  for x in select * from (values
    ('public.api_ponto_bater(jsonb)', E'  if v_eu is null then return _falha(''Seu acesso ainda', E'  if v_eu is not null and exists (select 1 from funcionarios where id = v_eu and dono) then return _falha(''Você é o dono: não precisa bater ponto.''); end if;\n  if v_eu is null then return _falha(''Seu acesso ainda'),
    ('public.api_ponto_estado(jsonb)', 'if v_eu is null then return jsonb_build_object(''ok'', true, ''vinculado'', false); end if;', 'if v_eu is null or exists (select 1 from funcionarios where id = v_eu and dono) then return jsonb_build_object(''ok'', true, ''vinculado'', false); end if;'),
    ('public.api_ponto_relatorio(jsonb)', 'where f.ativo or tot.h is not null;', 'where (f.ativo or tot.h is not null) and not f.dono;'),
    ('public.api_equipe_folha(jsonb)', 'x.tipo in (''Salário'', ''Adiantamento'', ''Vale'')) s on true;', 'x.tipo in (''Salário'', ''Adiantamento'', ''Vale'')) s on true where not f.dono;'),
    ('public.api_equipe_folha(jsonb)', 'into v_prev from funcionarios where ativo;', 'into v_prev from funcionarios where ativo and not dono;'),
    ('public.api_escala_semana(jsonb)', 'from funcionarios f where f.ativo or (v_adm and exists (select 1 from escala_turnos t where t.funcionario_id = f.id and t.data between v_ini and v_fim and not t.cancelado));', 'from funcionarios f where not f.dono and (f.ativo or (v_adm and exists (select 1 from escala_turnos t where t.funcionario_id = f.id and t.data between v_ini and v_fim and not t.cancelado)));'),
    ('public.api_equipe_reserva(jsonb)', 'where f.ativo and f.salario > 0) q;', 'where f.ativo and not f.dono and f.salario > 0) q;'),
    ('public.api_minha_escala(jsonb)', 'where usuario_id = auth.uid() and ativo;', 'where usuario_id = auth.uid() and ativo and not dono;'),
    ('public.equipe_pendencias_cron()', 'from funcionarios where ativo and salario > 0 and', 'from funcionarios where ativo and not dono and salario > 0 and'),
    ('public.ponto_pendencias_cron()', 'where pr.saida is null and not pr.cancelado', 'where not f.dono and pr.saida is null and not pr.cancelado')
  ) v(sig, a, b) loop
    d := pg_get_functiondef(x.sig::regprocedure);
    if position(x.b in d) > 0 then continue; end if;
    if (length(d) - length(replace(d, x.a, ''))) <> length(x.a) then raise exception 'trecho nao encontrado ou repetido em %: %', x.sig, left(x.a, 60); end if;
    execute replace(d, x.a, x.b);
  end loop;
end $$;


-- ======================================================================
-- 78-cardapio-hoje-entregas-no-mapa.sql
-- ======================================================================
-- 78 · Mapa do "Cardápio hoje": mostra também os pedidos ENTREGUES (sistema e iFood) em outra cor.
-- iFood: usa as coordenadas que o próprio pedido traz. Sistema: o endereço é localizado uma vez (pelo navegador, no OpenStreetMap) e guardado só como ponto aproximado (~500 m), sem o texto do endereço. Fica guardado (peso desprezível), não é apagado ao fechar o caixa.
create table if not exists public.geo_enderecos (
  chave text primary key,            -- md5 do endereço normalizado (não guarda o endereço)
  lat double precision, lng double precision,
  achou boolean not null default true,
  criado_em timestamptz not null default now()
);
alter table public.geo_enderecos enable row level security;
revoke all on public.geo_enderecos from public, anon, authenticated;
grant all on public.geo_enderecos to service_role;

create or replace function public.api_geo_endereco_salvar(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $f$
declare v_ch text := p->>'chave'; v_ok boolean := coalesce((p->>'achou')::boolean, true); v_lat double precision; v_lng double precision;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  if v_ch is null or v_ch !~ '^[0-9a-f]{32}$' then return _falha('Endereço inválido.'); end if;
  if v_ok then
    v_lat := round((nullif(p->>'lat', '')::double precision / 0.005)::numeric) * 0.005;
    v_lng := round((nullif(p->>'lng', '')::double precision / 0.005)::numeric) * 0.005;
    if v_lat is null or v_lng is null or v_lat not between -34 and 6 or v_lng not between -74 and -34 then return _falha('Localização fora do Brasil.'); end if;
  end if;
  insert into geo_enderecos (chave, lat, lng, achou) values (v_ch, v_lat, v_lng, v_ok) on conflict (chave) do update set lat = excluded.lat, lng = excluded.lng, achou = excluded.achou;
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public.api_geo_endereco_salvar(jsonb) from public, anon;
grant execute on function public.api_geo_endereco_salvar(jsonb) to authenticated, service_role;

-- fallback do mapa: se o endereço do sistema não é achado no OpenStreetMap, usa a posição de um pedido do iFood na mesma rua (o iFood traz coordenadas)
create or replace function public._geo_rua_ifood(p_rua text) returns table(lat double precision, lng double precision)
 language sql stable security definer set search_path to 'public' as $f$
  select avg(x.la), avg(x.ln) from (
    select (ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}')::double precision la, (ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}')::double precision ln
      from ifood_pedidos ip join vendas v on v.id = ip.venda_id
     where coalesce(p_rua, '') <> '' and split_part(public._end_chave(v.endereco), '|', 1) = p_rua
       and ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}' ~ '^-?[0-9.]+$' and ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}' ~ '^-?[0-9.]+$') x
$f$;
revoke all on function public._geo_rua_ifood(text) from public, anon, authenticated;
grant execute on function public._geo_rua_ifood(text) to service_role;

create or replace function public.api_cardapio_hoje(p jsonb DEFAULT '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $f$
declare v_ini timestamptz; v_turno boolean; v_h jsonb; v_ent jsonb; v_pend jsonb; v_nao int; v_enti jsonb;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select abertura into v_ini from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  v_turno := v_ini is not null;
  v_ini := coalesce(v_ini, now() - interval '24 hours');
  select coalesce(jsonb_agg(jsonb_build_object('lat',
           case when ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}' ~ '^-?[0-9.]+$' then (ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}')::double precision end,
         'lng', case when ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}' ~ '^-?[0-9.]+$' then (ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}')::double precision end,
         'chave', case when nullif(btrim(v.endereco), '') is not null then md5(coalesce(public._end_chave(v.endereco), public._ifood_norm(v.endereco))) end,
         'endereco', v.endereco, 'ifood', ip.venda_id is not null, 'rua', coalesce(split_part(public._end_chave(v.endereco), '|', 1), ''))), '[]'::jsonb) into v_h
    from vendas v left join ifood_pedidos ip on ip.venda_id = v.id
   where v.tipo = 'Entrega' and v.status_pedido = 'Entregue' and v.status = 'Confirmada' and v.data_hora >= v_ini;
  select coalesce(jsonb_agg(jsonb_build_object('lat', la, 'lng', ln, 'n', n)), '[]'::jsonb) into v_ent from (
    select round((coalesce(h.lat, g.lat, r.lat) / 0.005)::numeric) * 0.005 la, round((coalesce(h.lng, g.lng, r.lng) / 0.005)::numeric) * 0.005 ln, count(*)::int n
      from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave and g.achou
      left join lateral public._geo_rua_ifood(h.rua) r on h.lat is null and h.rua <> ''
     where coalesce(h.lat, g.lat, r.lat) is not null and not coalesce(h.ifood, false) group by 1, 2) x;
  select coalesce(jsonb_agg(jsonb_build_object('lat', la, 'lng', ln, 'n', n)), '[]'::jsonb) into v_enti from (
    select round((coalesce(h.lat, g.lat, r.lat) / 0.005)::numeric) * 0.005 la, round((coalesce(h.lng, g.lng, r.lng) / 0.005)::numeric) * 0.005 ln, count(*)::int n
      from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave and g.achou
      left join lateral public._geo_rua_ifood(h.rua) r on h.lat is null and h.rua <> ''
     where coalesce(h.lat, g.lat, r.lat) is not null and coalesce(h.ifood, false) group by 1, 2) x2;
  select coalesce(jsonb_agg(jsonb_build_object('chave', chave, 'endereco', endereco, 'ifood', coalesce(ifood, false))), '[]'::jsonb) into v_pend from (
    select distinct on (h.chave) h.chave, h.endereco, h.ifood from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave
      left join lateral public._geo_rua_ifood(h.rua) r on h.rua <> ''
     where h.lat is null and r.lat is null and h.chave is not null and g.chave is null limit 6) y;
  select count(*)::int into v_nao from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
   where h.lat is null and not exists (select 1 from public._geo_rua_ifood(h.rua) r where h.rua <> '' and r.lat is not null) and (h.chave is null or exists (select 1 from geo_enderecos g where g.chave = h.chave and not g.achou));
  return jsonb_build_object('ok', true, 'desde', v_ini, 'turno', v_turno,
    'funil', (select jsonb_build_object(
        'visita',    count(distinct aparelho) filter (where etapa = 'visita'),
        'item',      count(distinct aparelho) filter (where etapa = 'item'),
        'carrinho',  count(distinct aparelho) filter (where etapa = 'carrinho'),
        'finalizar', count(distinct aparelho) filter (where etapa = 'finalizar'),
        'pedido',    count(distinct aparelho) filter (where etapa = 'pedido'))
      from cardapio_funil f where f.primeiro_em >= v_ini
       and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho)),
    'pedidosCardapio', (select count(*) from vendas where origem = 'Cardápio' and status = 'Confirmada' and data_hora >= v_ini),
    'pontos', coalesce((select jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'n', n)) from (
        select l.lat, l.lng, count(*)::int n from cardapio_locais l
         where l.criado_em >= v_ini and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = l.aparelho)
         group by l.lat, l.lng) x), '[]'::jsonb),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('lat', round((d.lat / 0.005)::numeric) * 0.005, 'lng', round((d.lng / 0.005)::numeric) * 0.005))
        from pedido_destinos d join vendas v on v.id = d.venda_id
       where v.data_hora >= v_ini and v.status = 'Confirmada'), '[]'::jsonb),
    'entregues', v_ent, 'entreguesIfood', v_enti, 'entreguesTotal', jsonb_array_length(v_h), 'semCoord', v_pend, 'naoLocalizados', v_nao,
    'restaurante', (select jsonb_build_object('lat', (valor->>'lat')::numeric, 'lng', (valor->>'lng')::numeric) from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object'));
end $f$;


-- ======================================================================
-- 79-cliente-endereco-automatico.sql
-- ======================================================================
-- 79 · Endereço do cliente se preenche sozinho com o endereço de entrega mais usado (a partir da 1ª entrega; com várias, o mais repetido).
-- Só preenche quando o campo está vazio; nunca troca um endereço digitado. As entregas são ligadas ao cliente pelo id (iFood) ou pelo telefone (sistema).
create or replace function public._cliente_endereco_auto(p_cliente uuid) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare v_tel text;
begin
  if p_cliente is null then return; end if;
  select nullif(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), '') into v_tel from clientes where id = p_cliente;
  with g as (
    select (array_agg(endereco order by data_hora desc))[1] e, count(*) n, max(data_hora) ult
      from (select v.endereco, v.data_hora, coalesce(public._end_chave(v.endereco), public._ifood_norm(v.endereco)) k
              from vendas v where (v.cliente_id = p_cliente or (v_tel is not null and regexp_replace(coalesce(v.telefone_cliente, ''), '\D', '', 'g') = v_tel))
               and v.tipo = 'Entrega' and v.status = 'Confirmada' and nullif(btrim(v.endereco), '') is not null) q
     group by k having count(*) >= 1 order by count(*) desc, max(data_hora) desc limit 1)
  update clientes c set endereco = left(g.e, 300) from g where c.id = p_cliente and nullif(btrim(c.endereco), '') is null;
end $f$;
revoke all on function public._cliente_endereco_auto(uuid) from public, anon, authenticated;
grant execute on function public._cliente_endereco_auto(uuid) to service_role;

create or replace function public._vendas_endereco_cliente() returns trigger
 language plpgsql security definer set search_path to 'public' as $f$
declare v_id uuid; v_tel text := nullif(regexp_replace(coalesce(new.telefone_cliente, ''), '\D', '', 'g'), '');
begin
  if new.tipo = 'Entrega' and new.status = 'Confirmada' then
    if new.cliente_id is not null then perform public._cliente_endereco_auto(new.cliente_id); end if;
    if v_tel is not null then
      for v_id in select id from clientes where regexp_replace(coalesce(telefone, ''), '\D', '', 'g') = v_tel and id is distinct from new.cliente_id loop
        perform public._cliente_endereco_auto(v_id);
      end loop;
    end if;
  end if;
  return new;
exception when others then
  begin perform public.ifood_aviso_registrar(null, 'cliente', 'Não consegui preencher o endereço do cliente automaticamente', left(sqlerrm, 300), '{}'::jsonb); exception when others then null; end;
  return new;
end $f$;
revoke all on function public._vendas_endereco_cliente() from public, anon, authenticated;
grant execute on function public._vendas_endereco_cliente() to service_role;
drop trigger if exists vendas_endereco_cliente on public.vendas;
create trigger vendas_endereco_cliente after insert or update of status, endereco, cliente_id on public.vendas
  for each row when (pg_trigger_depth() < 2) execute function public._vendas_endereco_cliente();

-- clientes antigos com endereço vazio
select public._cliente_endereco_auto(c.id) from clientes c where nullif(btrim(c.endereco), '') is null and c.unido_com is null;


-- ======================================================================
-- 80-melhor-rota-entrega.sql
-- ======================================================================
-- 80 — Melhor rota de entrega: devolve ao aparelho as coordenadas exatas dos pedidos do iFood
-- e o local do restaurante (se definido em Equipe > Ponto). Só leitura; nada é gravado.
create or replace function public.api_rota_entrega(p jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_ids uuid[]; v_pts jsonb; v_rest jsonb; v_adm boolean;
begin
  if not tem_nivel('Admin', 'Operador', 'Entregador') then return _negado(); end if;
  v_adm := tem_nivel('Admin', 'Operador');
  begin
    select coalesce(array_agg(x::uuid), '{}') into v_ids from jsonb_array_elements_text(coalesce(p->'ids', '[]'::jsonb)) x;
  exception when others then return _falha('Pedidos inválidos.'); end;
  if cardinality(v_ids) > 12 then return _falha('Pedidos demais para uma rota.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', v.id,
           'lat', (i.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}')::double precision,
           'lng', (i.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}')::double precision)), '[]'::jsonb)
    into v_pts
    from vendas v join ifood_pedidos i on i.venda_id = v.id
   where v.id = any(v_ids) and (v_adm or v.entregador_id = auth.uid())
     and (i.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}') is not null;
  select jsonb_build_object('lat', (valor->>'lat')::double precision, 'lng', (valor->>'lng')::double precision)
    into v_rest from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object';
  return jsonb_build_object('ok', true, 'ifood', v_pts, 'restaurante', v_rest);
end $$;
revoke all on function public.api_rota_entrega(jsonb) from public, anon;
grant execute on function public.api_rota_entrega(jsonb) to authenticated, service_role;


-- ======================================================================
-- 81-nvidia-modelo-novo.sql
-- ======================================================================
-- 81 — NVIDIA: o modelo grátis antigo (nemotron-3-super-120b-a12b) ficou obsoleto; troca para o Nemotron 3.5 Bolt E4B.
update public.ai_config set modelo_nvidia = 'nvidia/nemotron-3.5-bolt-e4b';


-- ======================================================================
-- 82-gemini-modelo-36.sql
-- ======================================================================
-- 82 — Gemini: o modelo gemini-3.8-flash não respondia (travava 9 s antes de trocar). Passa a usar o gemini-3.6-flash como principal.
update public.ai_config set modelo_gemini = 'gemini-3.6-flash' where modelo_gemini = 'gemini-3.8-flash';


-- ======================================================================
-- 83-cliente-endereco-ao-criar.sql
-- ======================================================================
-- 83 — Endereço automático do cliente também quando o CLIENTE é criado depois do pedido (ex.: cardápio digital).
create or replace function public._clientes_endereco_auto()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._cliente_endereco_auto(new.id);
  return new;
exception when others then
  begin perform public.ifood_aviso_registrar(null, 'cliente', 'Não consegui preencher o endereço do cliente automaticamente', left(sqlerrm, 300), '{}'::jsonb); exception when others then null; end;
  return new;
end $$;
revoke all on function public._clientes_endereco_auto() from public, anon, authenticated;
grant execute on function public._clientes_endereco_auto() to service_role;
create or replace trigger clientes_endereco_auto after insert or update of telefone on public.clientes
  for each row when (nullif(btrim(coalesce(new.endereco, '')), '') is null and pg_trigger_depth() < 2) execute function public._clientes_endereco_auto();
-- preenche quem já estava sem endereço:
select public._cliente_endereco_auto(id) from public.clientes where nullif(btrim(coalesce(endereco,'')),'') is null and unido_com is null;


-- ======================================================================
-- 84-localizacao-no-pedido.sql
-- ======================================================================
-- 84 — Localização do cliente guardada junto do pedido (entrega_destinos) e usada pela "Melhor rota";
--      ao entregar, a posição vira ponto aproximado (~500 m) no mapa do "Cardápio hoje" e a posição exata é apagada (trigger já existente).
create or replace function public._venda_guardar_geo()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare d entrega_destinos%rowtype; v_ch text;
begin
  if nullif(btrim(coalesce(new.endereco, '')), '') is null then return new; end if;
  select * into d from entrega_destinos where venda_id = new.id;
  if d.venda_id is null then return new; end if;
  v_ch := md5(coalesce(public._end_chave(new.endereco), public._ifood_norm(new.endereco)));
  insert into geo_enderecos (chave, lat, lng, achou)
  values (v_ch, round((d.lat / 0.005)::numeric) * 0.005, round((d.lng / 0.005)::numeric) * 0.005, true)
  on conflict (chave) do update set lat = excluded.lat, lng = excluded.lng, achou = true, criado_em = now();
  return new;
exception when others then
  return new;
end $$;
revoke all on function public._venda_guardar_geo() from public, anon, authenticated;
grant execute on function public._venda_guardar_geo() to service_role;
create or replace trigger aa_venda_guardar_geo before update of status_pedido on public.vendas
  for each row when (new.status_pedido = 'Entregue'::status_pedido and old.status_pedido is distinct from new.status_pedido)
  execute function public._venda_guardar_geo();
-- api_rota_entrega (SQL 80) passou a devolver também "destinos" (entrega_destinos) — veja a versão atual no banco.
;


-- ======================================================================
-- 85-ponto-meus-registros.sql
-- ======================================================================
-- 85 — Ponto do funcionário: "Meus registros" por competência, pedido de correção e atestado (aprovação só do Admin).
-- Foto do atestado fica no banco (privado) e é apagada sozinha após 30 dias; o registro (dias/decisão) permanece.

insert into public.sistema (chave, valor) values ('PONTO_FECHAMENTO', '20'::jsonb) on conflict (chave) do nothing;

create table if not exists public.ponto_pedidos (
  id uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios(id),
  tipo text not null check (tipo in ('correcao','atestado')),
  data_ini date not null,
  data_fim date not null,
  batidas jsonb,
  motivo text,
  foto text,
  foto_expira_em timestamptz,
  status text not null default 'pendente' check (status in ('pendente','aprovado','recusado')),
  decidido_por text,
  decidido_em timestamptz,
  resposta text,
  criado_em timestamptz not null default now()
);
create index if not exists ponto_pedidos_func_idx on public.ponto_pedidos (funcionario_id, data_ini);
create index if not exists ponto_pedidos_status_idx on public.ponto_pedidos (status, criado_em);
alter table public.ponto_pedidos enable row level security;
revoke all on public.ponto_pedidos from public, anon, authenticated;
grant all on public.ponto_pedidos to service_role;

create or replace function public._ponto_fechamento() returns int language sql stable security definer set search_path to 'public' as $$
  select greatest(1, least(28, coalesce((select (valor #>> '{}')::int from sistema where chave = 'PONTO_FECHAMENTO' and jsonb_typeof(valor) = 'number'), 20)))
$$;
revoke all on function public._ponto_fechamento() from public, anon, authenticated;
grant execute on function public._ponto_fechamento() to service_role;

-- Fechamento: ler (qualquer logado) e alterar (Admin + senha)
create or replace function public.api_ponto_fechamento(p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if auth_nivel() is null then return _negado(); end if;
  return jsonb_build_object('ok', true, 'dia', _ponto_fechamento());
end $$;

create or replace function public.api_ponto_fechamento_salvar(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_dia int; v_err text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  begin v_dia := (p->>'dia')::int; exception when others then return _falha('Informe um dia de 1 a 28.'); end;
  if v_dia is null or v_dia < 1 or v_dia > 28 then return _falha('Informe um dia de 1 a 28.'); end if;
  insert into sistema (chave, valor, atualizado_em) values ('PONTO_FECHAMENTO', to_jsonb(v_dia), now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('Ponto: dia de fechamento', 'Dia ' || v_dia);
  return jsonb_build_object('ok', true, 'message', 'Fechamento do ponto: dia ' || v_dia || '.', 'dia', v_dia);
end $$;

-- Meus registros: competência = do dia (fechamento+1) do mês até o dia do fechamento do mês seguinte
create or replace function public.api_ponto_meus_registros(p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_eu uuid := _func_do_usuario(); v_f int := _ponto_fechamento();
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_atual date; v_ref date; v_ini date; v_fim date; v_comps jsonb := '[]'::jsonb; v_dias jsonb; v_tot int; v_ped jsonb; i int;
  v_meses text[] := array['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null or exists (select 1 from funcionarios where id = v_eu and dono) then return jsonb_build_object('ok', true, 'vinculado', false); end if;
  v_atual := date_trunc('month', v_hoje)::date;
  if v_hoje <= (v_atual + (v_f - 1)) then v_atual := (v_atual - interval '1 month')::date; end if;
  for i in 0..5 loop
    v_ref := (v_atual - make_interval(months => i))::date;
    v_comps := v_comps || jsonb_build_array(jsonb_build_object('ref', to_char(v_ref, 'YYYY-MM'), 'nome', v_meses[extract(month from v_ref)::int] || ' de ' || extract(year from v_ref)::int,
      'ini', v_ref + v_f, 'fim', (v_ref + (v_f - 1) + interval '1 month')::date));
  end loop;
  begin v_ref := to_date(coalesce(nullif(p->>'ref', ''), to_char(v_atual, 'YYYY-MM')) || '-01', 'YYYY-MM-DD'); exception when others then v_ref := v_atual; end;
  if v_ref > v_atual or v_ref < (v_atual - interval '24 months') then v_ref := v_atual; end if;
  v_ini := v_ref + v_f;
  v_fim := (v_ref + (v_f - 1) + interval '1 month')::date;
  select coalesce(jsonb_agg(d order by (d->>'data') desc), '[]'::jsonb), coalesce(sum((d->>'min')::int), 0) into v_dias, v_tot from (
    select jsonb_build_object('data', g.d, 'marcas', coalesce(m.marcas, '[]'::jsonb), 'min', coalesce(m.minutos, 0),
      'aberto', coalesce(m.aberto, false),
      'atestado', exists (select 1 from ponto_pedidos x where x.funcionario_id = v_eu and x.tipo = 'atestado' and x.status = 'aprovado' and g.d between x.data_ini and x.data_fim),
      'pedido', exists (select 1 from ponto_pedidos x where x.funcionario_id = v_eu and x.status = 'pendente' and g.d between x.data_ini and x.data_fim)) d
    from generate_series(v_ini, least(v_fim, v_hoje), interval '1 day') gs(dd)
    cross join lateral (select gs.dd::date d) g
    left join lateral (
      select jsonb_agg(to_char(t at time zone 'America/Sao_Paulo', 'HH24:MI') order by t) filter (where t is not null) marcas,
             (select coalesce(round(sum(extract(epoch from saida - entrada)) / 60), 0)::int from ponto_registros r2 where r2.funcionario_id = v_eu and not r2.cancelado and r2.saida is not null and (r2.entrada at time zone 'America/Sao_Paulo')::date = g.d) minutos,
             bool_or(aberto_) aberto
      from (select unnest(array[r.entrada, r.saida]) t, (r.saida is null) aberto_ from ponto_registros r
            where r.funcionario_id = v_eu and not r.cancelado and (r.entrada at time zone 'America/Sao_Paulo')::date = g.d) u
    ) m on true
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'ini', x.data_ini, 'fim', x.data_fim, 'status', x.status, 'resposta', x.resposta, 'motivo', x.motivo, 'batidas', x.batidas, 'criado', x.criado_em) order by x.criado_em desc), '[]'::jsonb)
    into v_ped from (select * from ponto_pedidos where funcionario_id = v_eu order by criado_em desc limit 30) x;
  return jsonb_build_object('ok', true, 'vinculado', true, 'fechamento', v_f, 'competencias', v_comps, 'ref', to_char(v_ref, 'YYYY-MM'),
    'nome', v_meses[extract(month from v_ref)::int] || ' de ' || extract(year from v_ref)::int, 'ini', v_ini, 'fim', v_fim, 'hoje', v_hoje, 'dias', v_dias, 'totalMin', v_tot, 'pedidos', v_ped);
end $$;

-- (as funções api_ponto_pedido_criar / api_ponto_pedidos_lista / api_ponto_pedido_foto / api_ponto_pedido_decidir / _ponto_atestados_limpar
--  e o agendamento 'ponto-atestados-30-dias' foram aplicados no banco; para refazer, copie-as de: select pg_get_functiondef('public.<nome>'::regproc);)
-- Permissões: authenticated + service_role nas api_ponto_*; _ponto_* só service_role.
-- Agendamento: select cron.schedule('ponto-atestados-30-dias', '50 6 * * *', 'select public._ponto_atestados_limpar()');


-- ======================================================================
-- 86-corrige-fechar-caixa.sql
-- ======================================================================
-- 86 — Fechar caixa dava "DELETE requires a WHERE clause": o gatilho que limpa os locais do cardápio ao fechar o caixa apagava sem WHERE.
create or replace function public._trg_caixa_fecha_apaga_locais() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.status::text = 'Fechado' and old.status::text is distinct from 'Fechado' then delete from cardapio_locais where true; end if;
  return new;
end $$;


-- ======================================================================
-- 87-seguranca-views-e-funcoes.sql
-- ======================================================================
-- 87 — Segurança (aviso do Supabase): 1) as telas v_vendas e v_fidelidade deixavam QUALQUER pessoa logada (inclusive cliente do cardápio) ler todas as vendas e a lista de fidelidade; agora só a equipe.
--      2) funções internas da equipe deixam de ser chamáveis sem login (já negavam, agora nem executam).
do $$ declare d text; begin
  d := regexp_replace(pg_get_viewdef('public.v_vendas'::regclass), ';\s*$', '');
  if d !~ 'auth_nivel\(\) IS NOT NULL' then execute 'create or replace view public.v_vendas as ' || d || ' WHERE auth_nivel() IS NOT NULL'; end if;
  d := regexp_replace(pg_get_viewdef('public.v_fidelidade'::regclass), ';\s*$', '');
  if d !~ 'auth_nivel\(\) IS NOT NULL' then execute 'create or replace view public.v_fidelidade as ' || d || ' AND auth_nivel() IS NOT NULL'; end if;
end $$;
do $$ declare f text; begin
  foreach f in array array['api_ajustar_precos_produtos_lote','api_alertas_config','api_alertas_pedido_adiar','api_alertas_pedidos','api_alertas_salvar','api_alertas_teste','api_cancelar_movimento_evento','api_cancelar_pagamento_funcionario','api_editar_compra_info','api_equipe_folha','api_equipe_importar_acessos','api_equipe_peso_mao_obra','api_equipe_reserva','api_escala_aplicar_padrao','api_escala_avisar','api_escala_copiar_semana','api_escala_padrao_salvar','api_escala_semana','api_espaco_historico','api_espaco_plano_salvar','api_estoque_sugestao','api_estornar_compra','api_evento_horas_salvar','api_evento_movimentos','api_evento_rendimento','api_margem_alerta','api_margem_config_salvar','api_margem_ignorar','api_margem_sugestao','api_minha_escala','api_pagar_funcionario','api_ponto_ajustar','api_ponto_bater','api_ponto_estado','api_ponto_relatorio','api_preco_historico','api_salvar_funcionario','api_salvar_turno','api_troca_decidir','api_troca_responder','api_troca_solicitar','api_trocas_lista','api_visibilidade_lote_produtos'] loop
    execute format('revoke execute on function public.%I(jsonb) from public, anon', f);
    execute format('grant execute on function public.%I(jsonb) to authenticated, service_role', f);
  end loop;
  revoke execute on function public._cliente_tem_endereco(uuid, text) from public, anon;
  grant execute on function public._cliente_tem_endereco(uuid, text) to authenticated, service_role;
end $$;


-- ======================================================================
-- 88-ifood-pedidos-com-caixa-fechado.sql
-- ======================================================================
-- 88 · Pedido do iFood que chega com o caixa fechado entra no próximo caixa que abrir (antes ficava sem caixa e fora do fechamento).
create or replace function public.api_abrir_caixa(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_fundo numeric := round(_num(p->>'fundoCaixa'), 2); v_id uuid; v_ult timestamptz; v_n int := 0;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_fundo < 0 then return _falha('O fundo de caixa não pode ser negativo.'); end if;
  if exists (select 1 from caixa_sessoes where status = 'Aberto') then return _falha('Já existe um caixa aberto. Feche-o antes de abrir outro.'); end if;
  select max(fechamento) into v_ult from caixa_sessoes;
  begin
    insert into caixa_sessoes (fundo_caixa, usuario_abertura, status) values (v_fundo, auth.uid(), 'Aberto') returning id into v_id;
  exception when unique_violation then
    return _falha('Já existe um caixa aberto. Feche-o antes de abrir outro.');
  end;
  update vendas set caixa_id = v_id
   where caixa_id is null and canal = 'iFood' and status = 'Confirmada'
     and data_hora > coalesce(v_ult, now() - interval '1 day');
  get diagnostics v_n = row_count;
  perform _auditar('Caixa aberto', 'Fundo de caixa: R$ ' || _dinheiro(v_fundo) || case when v_n > 0 then ' · ' || v_n || ' pedido(s) do iFood recebido(s) com o caixa fechado ligado(s) a este caixa' else '' end);
  return jsonb_build_object('ok', true, 'message', 'Caixa aberto.' || case when v_n > 0 then ' ' || v_n || ' pedido(s) do iFood recebidos com o caixa fechado entraram neste caixa.' else '' end);
end $function$;

-- A tela passa a saber a que caixa cada venda pertence (para contar no turno o pedido do iFood que chegou antes da abertura).
create or replace view public.v_vendas as
 select id, numero_pedido as numero, data_hora, cliente_nome, telefone_cliente as cliente_telefone, forma_pagamento, valor_total,
        case when auth_nivel() = any (array['Admin'::nivel_acesso,'Operador'::nivel_acesso]) then custo_total else null::numeric end as custo_total,
        status, motivo_cancelamento, tipo as tipo_entrega, status_pedido, endereco, complemento, referencia, observacoes_entrega, pronta_em, concluida_em,
        status_pagamento, recebido_em, valor_original, valor_desconto, desconto_detalhe, _login_de(entregador_id) as entregador, saiu_em, origem, mesa_id,
        taxa_entrega, fechamento_entrega_id, _login_de(registrado_por) as registrado_por, inicio_preparo_em, _mesa_numero_de(mesa_id) as mesa_numero,
        acrescimo_forma, preferencias_cliente, canal, cliente_id, ifood_localizador, ifood_localizador_ate, caixa_id
   from vendas v where auth_nivel() is not null;


-- ======================================================================
-- 89-avisos-do-dono-caixa.sql
-- ======================================================================
-- 89 · Avisos para todos os perfis Admin: caixa esquecido aberto, iFood com caixa fechado e resumo semanal do caixa.
create or replace function public._dono_avisar(p_chave text, p_titulo text, p_texto text, p_repetir interval default interval '6 hours')
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare e alertas_envios%rowtype;
begin
  select * into e from alertas_envios where chave = p_chave for update;
  if e.chave is not null and e.resolvido_em is null and (e.silenciado or now() - e.ultimo_em < p_repetir) then return false; end if;
  insert into alertas_envios (chave, tipo, titulo, texto) values (p_chave, 'dono', p_titulo, p_texto)
  on conflict (chave) do update set ultimo_em = now(), vezes = case when alertas_envios.resolvido_em is null then alertas_envios.vezes + 1 else 1 end,
     resolvido_em = null, titulo = excluded.titulo, texto = excluded.texto, silenciado = false;
  insert into auditoria (usuario_login, acao, detalhes) values ('sistema', 'AVISO AO ADMIN: ' || left(p_titulo, 80), left(p_texto, 300));
  perform _alertas_push('⚠️ ' || p_titulo, p_texto, 'dono-' || left(p_chave, 40), array['Admin']);
  return true;
end $$;

create or replace function public.alertas_dono_cron()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ativos text[] := '{}'; v_cx caixa_sessoes%rowtype; v_n int; v_h int := extract(hour from (now() at time zone 'America/Sao_Paulo'))::int;
begin
  select * into v_cx from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  if v_cx.id is not null and _caixa_vencido(v_cx.id) and now() > _caixa_vence_em(v_cx.abertura) + interval '1 hour' then
    ativos := array_append(ativos, 'dono:caixa_vencido');
    perform _dono_avisar('dono:caixa_vencido', 'Caixa esquecido aberto',
      'O caixa aberto em ' || to_char(v_cx.abertura at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ' passou do horário e ainda não foi fechado.', interval '6 hours');
  end if;
  if v_cx.id is null and v_h between 9 and 22 then
    select count(*) into v_n from vendas where canal = 'iFood' and caixa_id is null and status = 'Confirmada'
       and data_hora > now() - interval '3 days' and data_hora < now() - interval '10 minutes';
    if v_n > 0 then
      ativos := array_append(ativos, 'dono:ifood_sem_caixa');
      perform _dono_avisar('dono:ifood_sem_caixa', 'iFood com o caixa fechado',
        v_n || ' pedido(s) do iFood chegaram com o caixa fechado. Abra o caixa para eles entrarem nas vendas do dia.', interval '3 hours');
    end if;
  end if;
  update alertas_envios set resolvido_em = now() where tipo = 'dono' and resolvido_em is null and not (chave = any(ativos));
  return jsonb_build_object('ok', true, 'ativos', to_jsonb(ativos));
end $$;

create or replace function public.relatorio_dono_semanal()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_tot int; v_atr int; v_dif int; v_quem text; v_txt text;
begin
  select count(*), count(*) filter (where fechamento_atrasado), count(*) filter (where abs(coalesce(diferenca, 0)) > 0.009)
    into v_tot, v_atr, v_dif from caixa_sessoes where status = 'Fechado' and fechamento > now() - interval '7 days';
  select string_agg(distinct coalesce(u.login, '?'), ', ') into v_quem from caixa_sessoes c left join usuarios u on u.id = c.usuario_fechamento
    where c.status = 'Fechado' and c.fechamento > now() - interval '7 days' and c.fechamento_atrasado;
  v_txt := case when v_tot = 0 then 'Nenhum caixa foi fechado nesta semana.'
    when v_atr = 0 and v_dif = 0 then v_tot || ' caixa(s) na semana, todos fechados no prazo e sem diferença.'
    else v_tot || ' caixa(s) na semana: ' || v_atr || ' fechado(s) com atraso' || case when v_quem is not null then ' (' || v_quem || ')' else '' end || ', ' || v_dif || ' com diferença.' end;
  insert into auditoria (usuario_login, acao, detalhes) values ('sistema', 'RESUMO SEMANAL DO CAIXA', left(v_txt, 300));
  perform _alertas_push('📋 Caixa da semana', left(v_txt, 140), 'dono-semana', array['Admin']);
  return jsonb_build_object('ok', true, 'texto', v_txt);
end $$;

revoke all on function public._dono_avisar(text,text,text,interval), public.alertas_dono_cron(), public.relatorio_dono_semanal() from public, anon, authenticated;

select cron.schedule('alertas-dono-10min', '*/10 * * * *', 'select public.alertas_dono_cron()');
select cron.schedule('relatorio-dono-semanal', '0 12 * * 1', 'select public.relatorio_dono_semanal()');


-- ======================================================================
-- 90-drive-direto.sql
-- ======================================================================
-- Google Drive direto (sem Apps Script): contas autorizadas por OAuth. O refresh token fica no Vault.
-- Antes: guardar no Vault google_client_id e google_client_secret (Google Cloud › Credenciais).
set search_path = public, extensions, pg_catalog;

create table if not exists public.drive_contas (
  conta text primary key check (conta in ('principal','contingencia')),
  email text,
  conectado_em timestamptz not null default now(),
  conectado_por uuid
);
create table if not exists public.drive_oauth_estados (
  estado text primary key,
  conta text not null check (conta in ('principal','contingencia')),
  retorno text not null,
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
alter table public.drive_contas enable row level security;
alter table public.drive_oauth_estados enable row level security;   -- sem políticas: só a chave de serviço (funções do servidor)

create or replace function public.drive_guardar_token(p_conta text, p_email text, p_token text, p_por uuid)
returns void language plpgsql security definer set search_path = public, vault as $$
declare v_nome text := 'drive_token_' || p_conta; v_id uuid;
begin
  select id into v_id from vault.secrets where name = v_nome;
  if v_id is null then perform vault.create_secret(p_token, v_nome, 'Google Drive: refresh token (' || p_conta || ')');
  else perform vault.update_secret(v_id, p_token); end if;
  insert into public.drive_contas(conta, email, conectado_em, conectado_por) values (p_conta, p_email, now(), p_por)
  on conflict (conta) do update set email = excluded.email, conectado_em = now(), conectado_por = excluded.conectado_por;
end $$;

create or replace function public.drive_ler_token(p_conta text)
returns text language sql security definer set search_path = public, vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'drive_token_' || p_conta limit 1 $$;

create or replace function public.drive_desconectar(p_conta text)
returns void language plpgsql security definer set search_path = public, vault as $$
begin
  delete from vault.secrets where name = 'drive_token_' || p_conta;
  delete from public.drive_contas where conta = p_conta;
end $$;

revoke all on function public.drive_guardar_token(text,text,text,uuid), public.drive_ler_token(text), public.drive_desconectar(text) from public, anon, authenticated;
grant execute on function public.drive_guardar_token(text,text,text,uuid), public.drive_ler_token(text), public.drive_desconectar(text) to service_role;

-- as funções do servidor leem o ID e a chave do Google pelo mesmo caminho dos outros segredos
create or replace function public.api_segredo(p_nome text)
returns text language sql security definer set search_path to 'public','vault' as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = p_nome and p_nome in ('sheets_main_url','chave_servidor_planilha','publishable_key','service_key','vapid_privada','vapid_publica','google_client_id','google_client_secret') limit 1 $$;


-- ======================================================================
-- 91-atestado-no-drive.sql
-- ======================================================================
-- 29/10/2026 · Foto do atestado (Meus registros) passa a ficar no Google Drive (nunca no banco). Storage do Supabase só para backups e arquivo antigo.
-- ponto_pedidos.foto guarda "drive:<id>", "cont:<id>" ou "drive:<id>|cont:<id>" (atestados antigos em base64 continuam sendo lidos até vencerem).

create or replace function public.api_ponto_pedido_criar(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_eu uuid := _func_do_usuario(); v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_tipo text := coalesce(p->>'tipo', ''); v_mot text := left(nullif(btrim(coalesce(p->>'motivo', '')), ''), 300);
  v_ini date; v_fim date; v_bat jsonb := '[]'::jsonb; v_foto text; v_n int; v_nome text; v_b text; v_id uuid;
begin
  if auth_nivel() is null then return _negado(); end if;
  if v_eu is null or exists (select 1 from funcionarios where id = v_eu and dono) then return _falha('Seu usuário não está vinculado a um funcionário.'); end if;
  if (select count(*) from ponto_pedidos where funcionario_id = v_eu and status = 'pendente') >= 10 then return _falha('Você já tem 10 pedidos aguardando. Espere o administrador responder.'); end if;
  select nome into v_nome from funcionarios where id = v_eu;
  if v_tipo = 'correcao' then
    begin v_ini := (p->>'data')::date; exception when others then return _falha('Data inválida.'); end;
    if v_ini is null or v_ini > v_hoje or v_ini < v_hoje - 62 then return _falha('Escolha um dia dos últimos 60 dias.'); end if;
    if v_mot is null or length(v_mot) < 3 then return _falha('Conte o motivo da correção.'); end if;
    if jsonb_typeof(p->'batidas') <> 'array' or jsonb_array_length(p->'batidas') < 1 or jsonb_array_length(p->'batidas') > 8 then return _falha('Informe de 1 a 8 horários.'); end if;
    for v_b in select jsonb_array_elements_text(p->'batidas') loop
      if v_b !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return _falha('Horário inválido: ' || left(v_b, 10) || '. Use o formato 07:30.'); end if;
      v_bat := v_bat || to_jsonb(v_b);
    end loop;
    if jsonb_array_length(v_bat) % 2 = 1 and v_ini < v_hoje then return _falha('Informe entrada e saída de cada período (quantidade par de horários).'); end if;
    v_fim := v_ini;
  elsif v_tipo = 'atestado' then
    begin v_ini := (p->>'dataIni')::date; v_fim := coalesce(nullif(p->>'dataFim', '')::date, v_ini); exception when others then return _falha('Data inválida.'); end;
    if v_ini is null or v_fim < v_ini then return _falha('A data final precisa ser igual ou depois da inicial.'); end if;
    if v_ini < v_hoje - 62 or v_fim > v_hoje + 3 then return _falha('Datas fora do prazo (até 60 dias atrás).'); end if;
    if v_fim - v_ini > 30 then return _falha('O atestado pode ter no máximo 31 dias.'); end if;
    v_foto := nullif(p->>'fotoPath', '');
    if v_foto is null then return _falha('Envie a foto do atestado (atualize o app e tente de novo).'); end if;
    if v_foto !~ '^(drive:[A-Za-z0-9_-]{10,80}(\|cont:[A-Za-z0-9_-]{10,80})?|cont:[A-Za-z0-9_-]{10,80})$' then return _falha('A foto do atestado não é válida. Tire outra.'); end if;
    if exists (select 1 from ponto_pedidos where funcionario_id = v_eu and tipo = 'atestado' and status in ('pendente','aprovado') and daterange(data_ini, data_fim, '[]') && daterange(v_ini, v_fim, '[]')) then
      return _falha('Já existe um atestado seu nesses dias.');
    end if;
  else return _falha('Pedido inválido.'); end if;
  insert into ponto_pedidos (funcionario_id, tipo, data_ini, data_fim, batidas, motivo, foto, foto_expira_em)
    values (v_eu, v_tipo, v_ini, v_fim, case when v_tipo = 'correcao' then v_bat end, v_mot, v_foto, case when v_foto is not null then now() + interval '30 days' end) returning id into v_id;
  perform _push_admins(case when v_tipo = 'atestado' then '🩺 Atestado para aprovar' else '🕒 Correção de ponto para aprovar' end,
    v_nome || ' · ' || to_char(v_ini, 'DD/MM') || case when v_fim <> v_ini then ' a ' || to_char(v_fim, 'DD/MM') else '' end, 'ponto-pedido-' || v_id);
  return jsonb_build_object('ok', true, 'message', case when v_tipo = 'atestado' then 'Atestado enviado. O administrador vai analisar.' else 'Pedido de correção enviado. O administrador vai analisar.' end, 'id', v_id);
end $function$;

-- só limpa os atestados antigos que estavam no banco; os do Drive são apagados pela função ponto-foto (que remove também o arquivo)
create or replace function public._ponto_atestados_limpar() returns integer language plpgsql security definer set search_path to 'public' as $f$
declare n int;
begin
  update ponto_pedidos set foto = null where foto is not null and foto !~ '^(drive|cont):' and foto_expira_em < now();
  get diagnostics n = row_count; return n;
end $f$;

-- bucket "notas" (versão antiga dos comprovantes, vazio): sai; o Storage fica só com backups e arquivo
drop policy if exists notas_admin_ler on storage.objects;
drop policy if exists notas_admin_enviar on storage.objects;
-- (o bucket "notas" vazio se apaga pela tela Storage do Supabase: o SQL não deixa apagar bucket)
;


-- ======================================================================
-- 92-limpeza-revisao.sql
-- ======================================================================
-- 92 — Revisão geral (29/10/2026): limpeza de sobras e índices que faltavam.
-- Pode rodar mais de uma vez (tudo com "if exists" / "if not exists").

-- 1) Cópia antiga da tabela de ajuda (feita em 16/10, não é mais usada)
drop table if exists public.ai_ajuda_backup_20261016;

-- 2) Funções que nada no sistema chama (banco, página, funções do Supabase e planilhas conferidos)
drop function if exists public._compra_receber(uuid, text, date, boolean);
drop function if exists public._conta_atual();
drop function if exists public._exige_senha_sempre(text);
drop function if exists public._norm_cidade(text);
drop function if exists public.fiscal_obter_cnpj_empresa();
drop function if exists public.ifood_novos_sem_confirmar();
drop function if exists public.ip_pagamento(uuid);

-- 3) Índices nas ligações entre tabelas que estavam sem (o Supabase apontou: deixam consultas mais lentas)
create index if not exists ix_escala_trocas_de_funcionario   on public.escala_trocas (de_funcionario_id);
create index if not exists ix_escala_trocas_para_funcionario on public.escala_trocas (para_funcionario_id);
create index if not exists ix_escala_trocas_turno            on public.escala_trocas (turno_id);
create index if not exists ix_escala_turnos_funcionario      on public.escala_turnos (funcionario_id);
create index if not exists ix_fidelidade_marcas_cliente      on public.fidelidade_marcas (cliente_id);
create index if not exists ix_funcionario_pagamentos_func    on public.funcionario_pagamentos (funcionario_id);
create index if not exists ix_reembolsos_manuais_pagamento   on public.pagamentos_reembolsos_manuais (pagamento_id);

-- 4) Rotinas: nomes novos das limpezas de fotos (os prazos agora são editáveis em Backup e espaço), a limpeza mensal
--    do Drive (fotos sem uso) e a limpeza do registro das integrações, que existia mas nunca tinha sido agendada.
do $$ begin
  perform cron.unschedule(jobname) from cron.job where jobname in ('ponto-fotos-45-dias','evidencias-45-dias','ponto-atestados-30-dias');
end $$;
select cron.schedule('ponto-fotos-prazo','40 6 * * *', $c$select public.chamar_edge('ponto-foto', '{"acao":"limpar"}'::jsonb)$c$);
select cron.schedule('evidencias-prazo','50 6 * * *', $c$select public.chamar_edge('evidencia-foto', '{"acao":"limpar"}'::jsonb)$c$);
select cron.schedule('ponto-atestados-antigos','52 6 * * *', $c$select public._ponto_atestados_limpar()$c$);
select cron.schedule('drive-limpeza-diaria','10 7 * * *', $c$select public.chamar_edge('drive-direto','{"action":"limpezaDiaria"}'::jsonb)$c$);
select cron.schedule('integracoes-log-limpeza','25 6 * * *', $c$select public._integracoes_limpar()$c$);
-- backups automáticos guardados por 30 dias (mudável em Backup e espaço → Avançado → Quanto tempo guardar)
update public.backup_config set auto_retencao_dias = 30 where id = true and auto_retencao_dias < 30;


-- ======================================================================
-- 93-seguranca-funcoes-internas.sql (01/11/2026 · versão 1.24)
-- ======================================================================
-- Funções internas que não precisam ser chamadas de fora deixam de ficar abertas ao público.
-- As telas (views) chamam algumas delas com a permissão de quem consulta: essas continuam liberadas para quem precisa.
revoke all on function public._preco_historico_gravar(), public._cliente_tem_endereco(uuid, text) from public, anon, authenticated;
revoke all on function public._cardapio_bloqueio(), public._mesa_numero_de(uuid), public._caixa_vence_em(timestamptz),
  public._login_de(uuid), public._caixa_aberto_id(), public._caixa_vencido(uuid), public._caixa_msg_vencido() from public, anon;
grant execute on function public._cardapio_bloqueio() to anon, authenticated;
grant execute on function public._login_de(uuid), public._caixa_aberto_id(), public._caixa_vencido(uuid), public._caixa_msg_vencido(),
  public._mesa_numero_de(uuid), public._caixa_vence_em(timestamptz) to authenticated;
grant execute on function public._cardapio_bloqueio(), public._preco_historico_gravar(), public._cliente_tem_endereco(uuid, text),
  public._mesa_numero_de(uuid), public._caixa_vence_em(timestamptz), public._login_de(uuid), public._caixa_aberto_id(),
  public._caixa_vencido(uuid), public._caixa_msg_vencido() to service_role;
-- As telas v_cardapio_* e v_vendas/v_fidelidade/v_sessao_aberta/v_mesas/v_indicacoes continuam no modo "do dono" DE PROPÓSITO:
-- as do cardápio mostram ao público só colunas seguras (sem custo) e as internas já conferem o perfil da equipe dentro da própria tela.
comment on view public.v_vendas is 'Modo do dono de propósito: filtra auth_nivel() (só equipe). Não trocar para security_invoker sem rever as regras de Cozinha/Garçom/Entregador.';
comment on view public.v_cardapio_produtos is 'Modo do dono de propósito: expõe ao público só colunas sem custo.';


-- ======================================================================
-- 94-grants-tabelas-novas.sql
-- ======================================================================
-- Desde 30/10/2026 o Supabase não dá mais permissão automática às tabelas novas do public.
-- O gatilho que já liga a RLS em toda tabela nova passa a dar também as permissões de sempre (a RLS continua decidindo quem vê o quê).
create or replace function public.rls_auto_enable()
returns event_trigger language plpgsql security definer set search_path to 'pg_catalog' as $function$
declare cmd record;
begin
  for cmd in
    select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO') and object_type in ('table','partitioned table')
  loop
    if cmd.schema_name = 'public' then
      begin
        execute format('alter table if exists %s enable row level security', cmd.object_identity);
        execute format('grant select, insert, update, delete on table %s to authenticated', cmd.object_identity);
        execute format('grant all on table %s to service_role', cmd.object_identity);
        raise log 'rls_auto_enable: RLS + permissões em %', cmd.object_identity;
      exception when others then
        raise log 'rls_auto_enable: falhou em %', cmd.object_identity;
      end;
    end if;
  end loop;
end $function$;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges for role postgres in schema public grant all on tables to service_role;
alter default privileges for role postgres in schema public grant usage, select on sequences to authenticated, service_role;


-- ======================================================================
-- 96-funil-do-finalizar.sql
-- ======================================================================
-- Onde o cliente para DENTRO da tela de finalizar. Sem nome, sem telefone; cada aparelho conta uma vez por dia; equipe não conta.
create table if not exists public.cardapio_checkout (
  dia date not null,
  aparelho text not null,
  etapa text not null check (etapa in ('tentou','b_nome','b_telefone','b_endereco','b_numero','b_cidade','b_troco','b_login','b_fechado','b_erro','pag_online')),
  primeiro_em timestamptz not null default now(),
  primary key (dia, aparelho, etapa)
);
alter table public.cardapio_checkout enable row level security;   -- sem políticas: só pelas funções
grant select, insert, update, delete on public.cardapio_checkout to authenticated;
grant all on public.cardapio_checkout to service_role;
create index if not exists cardapio_checkout_primeiro_idx on public.cardapio_checkout (primeiro_em);

-- Admin/Operador: pop-up "Cardápio hoje" (turno aberto ou últimas 24 h) e últimos 30 dias
create or replace function public.api_cardapio_checkout(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_ini timestamptz; v_hoje jsonb; v_30 jsonb;
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  select abertura into v_ini from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  v_ini := coalesce(v_ini, now() - interval '24 hours');
  select coalesce(jsonb_object_agg(etapa, n), '{}'::jsonb) into v_hoje from (
    select etapa, count(distinct aparelho) n from cardapio_checkout c where c.primeiro_em >= v_ini
       and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = c.aparelho) group by etapa) x;
  select coalesce(jsonb_object_agg(etapa, n), '{}'::jsonb) into v_30 from (
    select etapa, count(*) n from cardapio_checkout c where c.primeiro_em >= now() - interval '30 days'
       and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = c.aparelho) group by etapa) x;
  return jsonb_build_object('ok', true, 'periodo', v_hoje, 'dias30', v_30,
    'funil30', (select jsonb_build_object('finalizar', count(*) filter (where etapa = 'finalizar'), 'pedido', count(*) filter (where etapa = 'pedido'))
                from cardapio_funil f where f.primeiro_em >= now() - interval '30 days'
                 and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho)),
    'desde30', (select min(primeiro_em) from cardapio_checkout));
end $function$;
revoke all on function public.api_cardapio_checkout(jsonb) from public, anon;
grant execute on function public.api_cardapio_checkout(jsonb) to authenticated, service_role;
select cron.schedule('cardapio-checkout-limpar', '35 6 * * *', $c$delete from public.cardapio_checkout where dia < (now() at time zone 'America/Sao_Paulo')::date - 90$c$);


-- ======================================================================
-- 97-cardapio-faixa-promo.sql
-- ======================================================================
create or replace view public.v_cardapio_config as
 select chave, valor from sistema
  where chave = any (array['CardapioKicker','CardapioFrase','CardapioTempoRetirada','CardapioTempoMesa','CardapioTempoEntrega','TaxaEntregaPadrao',
    'MANUTENCAO','RestauranteNome','RestauranteEndereco','RestauranteTelefone','RestauranteHorario','RestauranteRedes','CardapioFaixaPromo']);
grant select on public.v_cardapio_config to anon, authenticated;

create or replace function public.api_salvar_config_cardapio(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _cfg_gravar('CardapioKicker', to_jsonb(coalesce(p->>'kicker', '')));
  perform _cfg_gravar('CardapioFrase', to_jsonb(coalesce(p->>'frase', '')));
  if p ? 'tempoEntrega' then perform _cfg_gravar('CardapioTempoEntrega', to_jsonb(coalesce(p->>'tempoEntrega', ''))); end if;
  if p ? 'tempoRetirada' then perform _cfg_gravar('CardapioTempoRetirada', to_jsonb(coalesce(p->>'tempoRetirada', ''))); end if;
  if p ? 'tempoMesa' then perform _cfg_gravar('CardapioTempoMesa', to_jsonb(coalesce(p->>'tempoMesa', ''))); end if;
  if p ? 'faixaPromo' then perform _cfg_gravar('CardapioFaixaPromo', to_jsonb(left(btrim(coalesce(p->>'faixaPromo', '')), 120))); end if;
  perform _auditar('Configuração do Cardápio Digital atualizada');
  return jsonb_build_object('ok', true, 'message', 'Cardápio atualizado.');
end $function$;


-- ======================================================================
-- 98-resumo-do-turno.sql
-- ======================================================================
-- Ao fechar o caixa, os Admins recebem no celular: faturamento (sem taxa de entrega), pedidos, ticket médio, iFood, cancelados e se o caixa bateu.
alter table public.alertas_config add column if not exists resumo_turno boolean not null default true;

create or replace function public._brl(v numeric) returns text language sql immutable set search_path to 'public' as $$
  select 'R$ ' || replace(replace(replace(to_char(coalesce(v, 0), 'FM999,999,990.00'), ',', 'X'), '.', ','), 'X', '.') $$;

create or replace function public.resumo_turno_texto(p_caixa uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c caixa_sessoes%rowtype; v_n int; v_fat numeric; v_if int; v_canc int; v_tk numeric; v_txt text; v_dif text;
begin
  select * into c from caixa_sessoes where id = p_caixa;
  if c.id is null then return null; end if;
  select count(*) filter (where status = 'Confirmada'),
         coalesce(sum(valor_total - coalesce(taxa_entrega, 0)) filter (where status = 'Confirmada'), 0),
         count(*) filter (where status = 'Confirmada' and canal = 'iFood'),
         count(*) filter (where status = 'Cancelada')
    into v_n, v_fat, v_if, v_canc from vendas where caixa_id = p_caixa;
  v_tk := case when v_n > 0 then round(v_fat / v_n, 2) end;
  v_dif := case when c.diferenca is null then ''
                when abs(c.diferenca) < 0.01 then ' · caixa bateu'
                when c.diferenca > 0 then ' · sobrou ' || _brl(c.diferenca)
                else ' · faltou ' || _brl(abs(c.diferenca)) end;
  v_txt := case when v_n = 0 then 'Nenhuma venda neste turno' || v_dif || '.'
    else _brl(v_fat) || ' em ' || v_n || ' pedido' || case when v_n > 1 then 's' else '' end
      || ' · ticket ' || _brl(v_tk)
      || case when v_if > 0 then ' · iFood ' || v_if else '' end
      || case when v_canc > 0 then ' · ' || v_canc || ' cancelado' || case when v_canc > 1 then 's' else '' end else '' end
      || v_dif end;
  return jsonb_build_object('titulo', '📊 Turno fechado · ' || to_char(coalesce(c.abertura, now()) at time zone 'America/Sao_Paulo', 'DD/MM'),
    'texto', v_txt, 'pedidos', v_n, 'faturamento', v_fat, 'ticket', v_tk, 'ifood', v_if, 'cancelados', v_canc);
end $$;

create or replace function public._caixa_resumo_turno_trg()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare r jsonb;
begin
  begin
    if not coalesce((select resumo_turno from alertas_config limit 1), true) then return new; end if;
    r := resumo_turno_texto(new.id);
    if r is null then return new; end if;
    insert into auditoria (usuario_login, acao, detalhes) values ('sistema', 'RESUMO DO TURNO', left(r->>'texto', 300));
    perform _alertas_push(r->>'titulo', left(r->>'texto', 140), 'turno-' || left(new.id::text, 8), array['Admin']);
  exception when others then
    null;   -- o resumo nunca pode atrapalhar o fechamento do caixa
  end;
  return new;
end $$;

create or replace trigger caixa_resumo_turno after update of status on public.caixa_sessoes
  for each row when (old.status = 'Aberto' and new.status = 'Fechado') execute function public._caixa_resumo_turno_trg();

create or replace function public.api_resumo_turno_config(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ult uuid; r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if p ? 'ligado' then
    update alertas_config set resumo_turno = coalesce((p->>'ligado')::boolean, true), atualizado_em = now(), atualizado_por = auth.uid() where true;
    perform _auditar('Resumo do turno ' || case when (p->>'ligado')::boolean then 'ligado' else 'desligado' end);
  end if;
  select id into v_ult from caixa_sessoes where status = 'Fechado' order by fechamento desc nulls last limit 1;
  r := case when v_ult is not null then resumo_turno_texto(v_ult) end;
  if coalesce((p->>'testar')::boolean, false) then
    if r is null then return _falha('Ainda não há turno fechado para usar no teste.'); end if;
    perform _alertas_push(r->>'titulo' || ' (teste)', left(r->>'texto', 140), 'turno-teste', array['Admin']);
    return jsonb_build_object('ok', true, 'message', 'Aviso de teste enviado aos Admins com o último turno fechado.', 'ligado', (select resumo_turno from alertas_config limit 1), 'exemplo', r);
  end if;
  return jsonb_build_object('ok', true, 'message', case when p ? 'ligado' then 'Resumo do turno salvo.' else null end,
    'ligado', coalesce((select resumo_turno from alertas_config limit 1), true), 'exemplo', r);
end $$;
revoke all on function public.resumo_turno_texto(uuid), public._caixa_resumo_turno_trg() from public, anon, authenticated;
revoke all on function public.api_resumo_turno_config(jsonb) from public, anon;
grant execute on function public.api_resumo_turno_config(jsonb) to authenticated;
grant execute on function public.resumo_turno_texto(uuid), public.api_resumo_turno_config(jsonb), public._brl(numeric) to service_role;


-- ======================================================================
-- 99-cupom-por-forma-de-pagamento.sql
-- ======================================================================
-- Cupom que vale só em algumas formas (ex.: Pix e Dinheiro). Vazio = vale em qualquer forma.
-- As funções de cupom já existentes recebem só o trecho novo (troca de texto conferida; se não achar o ponto, PARA sem mudar nada).
alter table public.cupons add column if not exists formas_ids uuid[];

create or replace function public._cupom_formas_nomes(p_ids uuid[]) returns text language sql stable security definer set search_path to 'public' as $$
  select case when coalesce(cardinality(p_ids), 0) = 0 then ''
    else (select case when count(*) <= 1 then string_agg(nome, '') else
            string_agg(nome, ', ' order by ordem) filter (where rn < count_all) || ' ou ' || max(nome) filter (where rn = count_all) end
          from (select nome, ordem, row_number() over (order by ordem) rn, count(*) over () count_all from formas_pagamento where id = any (p_ids)) x) end $$;
revoke all on function public._cupom_formas_nomes(uuid[]) from public, anon, authenticated;
grant execute on function public._cupom_formas_nomes(uuid[]) to service_role;

do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public._cupom_validar(jsonb,uuid)'::regprocedure);
  if position('formas_ids' in d) = 0 then
    n := replace(d, $a$  c.validade_dias := least(365, greatest(1, floor(_num(p->>'validadeDias', 30))::int));$a$,
      $b$  c.validade_dias := least(365, greatest(1, floor(_num(p->>'validadeDias', 30))::int));
  c.formas_ids := (select array_agg(distinct fp.id) from formas_pagamento fp
                    where fp.ativa and fp.id::text in (select jsonb_array_elements_text(case when jsonb_typeof(p->'formasIds') = 'array' then p->'formasIds' else '[]'::jsonb end)));$b$);
    if n = d then raise exception '_cupom_validar: ponto de troca não encontrado'; end if;
    execute n;
  end if;

  d := pg_get_functiondef('public.api_salvar_cupom(jsonb)'::regprocedure);
  if position('formas_ids' in d) = 0 then
    n := replace(replace(d, 'validade_dias, regra)', 'validade_dias, regra, formas_ids)'), '(v.c).validade_dias, (v.c).regra);', '(v.c).validade_dias, (v.c).regra, (v.c).formas_ids);');
    if position('(v.c).formas_ids' in n) = 0 then raise exception 'api_salvar_cupom: ponto de troca não encontrado'; end if;
    execute n;
  end if;

  d := pg_get_functiondef('public.api_editar_cupom(jsonb)'::regprocedure);
  if position('formas_ids' in d) = 0 then
    n := replace(d, 'regra = (v.c).regra', 'regra = (v.c).regra, formas_ids = (v.c).formas_ids');
    if n = d then raise exception 'api_editar_cupom: ponto de troca não encontrado'; end if;
    execute n;
  end if;

  d := pg_get_functiondef('public._cupom_calcular(text,text,numeric,text,uuid,jsonb,uuid)'::regprocedure);
  if position('formas_ids' in d) = 0 then
    n := replace(d, $a$  if c.automatico is not null then
    select * into v_cc$a$, $b$  if coalesce(cardinality(c.formas_ids), 0) > 0 and (p_forma is null or not (p_forma = any (c.formas_ids))) then
    return jsonb_build_object('ok', false, 'motivo', 'forma', 'formasIds', to_jsonb(c.formas_ids), 'formasNomes', _cupom_formas_nomes(c.formas_ids),
      'message', 'O cupom ' || c.codigo || ' vale só para pagamento em ' || _cupom_formas_nomes(c.formas_ids) || '. '
        || case when cardinality(c.formas_ids) = 1 then 'Escolha essa forma' else 'Escolha uma dessas formas' end || ' de pagamento para ganhar o desconto.');
  end if;
  if c.automatico is not null then
    select * into v_cc$b$);
    n := replace(n, $a$'acumula', c.acumula,$a$, $b$'acumula', c.acumula, 'formasIds', to_jsonb(coalesce(c.formas_ids, '{}'::uuid[])), 'formasNomes', _cupom_formas_nomes(c.formas_ids),$b$);
    if position('motivo' in n) = 0 or position('''formasNomes'', _cupom_formas_nomes(c.formas_ids),' in n) = 0 then raise exception '_cupom_calcular: ponto de troca não encontrado'; end if;
    execute n;
  end if;

  -- Minha conta: o cupom mostra em quais formas vale
  d := pg_get_functiondef('public.api_conta_cupons()'::regprocedure);
  if position('formasNomes' in d) = 0 then
    n := replace(d, $a$'minimo', k.valor_minimo, 'validoAte'$a$, $b$'minimo', k.valor_minimo, 'formasNomes', _cupom_formas_nomes(k.formas_ids), 'validoAte'$b$);
    if n = d then raise exception 'api_conta_cupons: ponto de troca não encontrado'; end if;
    execute n;
  end if;
end $do$;


-- ======================================================================
-- 100-incentivo-conta.sql
-- ======================================================================
-- O cardápio mostra as vantagens de entrar com o Google que estão LIGADAS. Só textos públicos.
create or replace function public.api_conta_incentivo(p jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('ok', true,
    'boasVindas', (select jsonb_build_object('tipo', k.tipo, 'valor', k.valor, 'minimo', k.valor_minimo)
                     from cupons k where k.automatico = 'boas_vindas' and k.ativa and k.excluido_em is null limit 1),
    'fidelidade', (select beneficio from promocoes where ativa and tipo ilike 'Fidelidade%' order by nome limit 1),
    'indicacao', (select jsonb_build_object('tipo', k.tipo, 'valor', k.valor) from cupons k where k.automatico = 'indicacao_indicador' and k.ativa and k.excluido_em is null limit 1));
$$;
revoke all on function public.api_conta_incentivo(jsonb) from public;
grant execute on function public.api_conta_incentivo(jsonb) to anon, authenticated, service_role;


-- ======================================================================
-- 101-cardapio-por-periodo.sql
-- ======================================================================
-- Administrador → Cardápio: funil e mapa por PERÍODO. Os pontos de acesso continuam apagados ao fechar o caixa;
-- fica guardada só a CONTAGEM por região de ~500 m e por dia, sem identificar o aparelho (cardapio_regioes).
create table if not exists public.cardapio_regioes (
  dia date not null,
  lat numeric not null,
  lng numeric not null,
  n int not null default 0,
  primary key (dia, lat, lng)
);
alter table public.cardapio_regioes enable row level security;   -- sem políticas: só pelas funções
grant select, insert, update, delete on public.cardapio_regioes to authenticated;
grant all on public.cardapio_regioes to service_role;

create or replace function public.api_cardapio_funil(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_ap text := lower(btrim(coalesce(p->>'aparelho', ''))); v_et text := lower(btrim(coalesce(p->>'etapa', '')));
        v_dia date := (now() at time zone 'America/Sao_Paulo')::date; v_lat numeric; v_lng numeric;
begin
  if v_ap !~ '^[a-z0-9]{16,40}$' then return jsonb_build_object('ok', false); end if;
  if v_et in ('tentou','b_nome','b_telefone','b_endereco','b_numero','b_cidade','b_troco','b_login','b_fechado','b_erro','pag_online') then
    if exists (select 1 from cardapio_aparelhos_equipe where aparelho = v_ap) then return jsonb_build_object('ok', true); end if;
    if (select count(*) from cardapio_checkout where dia = v_dia) >= 40000 then return jsonb_build_object('ok', true); end if;
    insert into cardapio_checkout (dia, aparelho, etapa) values (v_dia, v_ap, v_et) on conflict do nothing;
    return jsonb_build_object('ok', true);
  end if;
  if v_et not in ('visita', 'item', 'carrinho', 'finalizar', 'pedido') then return jsonb_build_object('ok', false); end if;
  if exists (select 1 from cardapio_aparelhos_equipe where aparelho = v_ap) then return jsonb_build_object('ok', true); end if;
  if (select count(*) from cardapio_funil where dia = v_dia) >= 40000 then return jsonb_build_object('ok', true); end if;
  insert into cardapio_funil (dia, aparelho, etapa) values (v_dia, v_ap, v_et) on conflict do nothing;
  if v_et = 'visita' then
    insert into cardapio_visitas (dia, aparelho) values (v_dia, v_ap) on conflict do nothing;
  end if;
  begin v_lat := (p->>'lat')::numeric; v_lng := (p->>'lng')::numeric; exception when others then v_lat := null; end;
  if v_lat is not null and v_lng is not null and v_lat between -34 and 6 and v_lng between -74 and -34 then
    v_lat := round(v_lat / 0.005) * 0.005; v_lng := round(v_lng / 0.005) * 0.005;
    if not exists (select 1 from cardapio_locais where aparelho = v_ap and lat = v_lat and lng = v_lng
                    and (criado_em at time zone 'America/Sao_Paulo')::date = v_dia) then
      insert into cardapio_regioes (dia, lat, lng, n) values (v_dia, v_lat, v_lng, 1)
        on conflict (dia, lat, lng) do update set n = cardapio_regioes.n + 1;
    end if;
    insert into cardapio_locais (aparelho, lat, lng) values (v_ap, v_lat, v_lng)
      on conflict (aparelho) do update set lat = excluded.lat, lng = excluded.lng, criado_em = now();
  end if;
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.api_cardapio_periodo(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_de date; v_ate date; v_x date;
        v_ini timestamptz; v_fim timestamptz; v_h jsonb; v_ent jsonb; v_pend jsonb; v_nao int; v_enti jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_de := coalesce(_data_iso(btrim(coalesce(p->>'de', ''))), v_hoje - 6);
  v_ate := coalesce(_data_iso(btrim(coalesce(p->>'ate', ''))), v_hoje);
  if v_ate < v_de then v_x := v_de; v_de := v_ate; v_ate := v_x; end if;
  if v_ate - v_de > 366 then return _falha('Escolha um período de até 1 ano.'); end if;
  v_ini := v_de::timestamp at time zone 'America/Sao_Paulo';
  v_fim := (v_ate + 1)::timestamp at time zone 'America/Sao_Paulo';
  select coalesce(jsonb_agg(jsonb_build_object('lat',
           case when ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}' ~ '^-?[0-9.]+$' then (ip.bruto #>> '{delivery,deliveryAddress,coordinates,latitude}')::double precision end,
         'lng', case when ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}' ~ '^-?[0-9.]+$' then (ip.bruto #>> '{delivery,deliveryAddress,coordinates,longitude}')::double precision end,
         'chave', case when nullif(btrim(v.endereco), '') is not null then md5(coalesce(public._end_chave(v.endereco), public._ifood_norm(v.endereco))) end,
         'endereco', v.endereco, 'ifood', ip.venda_id is not null, 'rua', coalesce(split_part(public._end_chave(v.endereco), '|', 1), ''))), '[]'::jsonb) into v_h
    from vendas v left join ifood_pedidos ip on ip.venda_id = v.id
   where v.tipo = 'Entrega' and v.status_pedido = 'Entregue' and v.status = 'Confirmada' and v.data_hora >= v_ini and v.data_hora < v_fim;
  select coalesce(jsonb_agg(jsonb_build_object('lat', la, 'lng', ln, 'n', n)), '[]'::jsonb) into v_ent from (
    select round((coalesce(h.lat, g.lat, r.lat) / 0.005)::numeric) * 0.005 la, round((coalesce(h.lng, g.lng, r.lng) / 0.005)::numeric) * 0.005 ln, count(*)::int n
      from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave and g.achou
      left join lateral public._geo_rua_ifood(h.rua) r on h.lat is null and h.rua <> ''
     where coalesce(h.lat, g.lat, r.lat) is not null and not coalesce(h.ifood, false) group by 1, 2) x;
  select coalesce(jsonb_agg(jsonb_build_object('lat', la, 'lng', ln, 'n', n)), '[]'::jsonb) into v_enti from (
    select round((coalesce(h.lat, g.lat, r.lat) / 0.005)::numeric) * 0.005 la, round((coalesce(h.lng, g.lng, r.lng) / 0.005)::numeric) * 0.005 ln, count(*)::int n
      from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave and g.achou
      left join lateral public._geo_rua_ifood(h.rua) r on h.lat is null and h.rua <> ''
     where coalesce(h.lat, g.lat, r.lat) is not null and coalesce(h.ifood, false) group by 1, 2) x2;
  select coalesce(jsonb_agg(jsonb_build_object('chave', chave, 'endereco', endereco, 'ifood', coalesce(ifood, false))), '[]'::jsonb) into v_pend from (
    select distinct on (h.chave) h.chave, h.endereco, h.ifood from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
      left join geo_enderecos g on g.chave = h.chave
      left join lateral public._geo_rua_ifood(h.rua) r on h.rua <> ''
     where h.lat is null and r.lat is null and h.chave is not null and (g.chave is null or (not g.achou and g.criado_em < now() - interval '1 hour')) limit 6) y;
  select count(*)::int into v_nao from jsonb_to_recordset(v_h) h(lat double precision, lng double precision, chave text, endereco text, ifood boolean, rua text)
   where h.lat is null and not exists (select 1 from public._geo_rua_ifood(h.rua) r where h.rua <> '' and r.lat is not null) and (h.chave is null or exists (select 1 from geo_enderecos g where g.chave = h.chave and not g.achou and g.criado_em >= now() - interval '1 hour'));
  return jsonb_build_object('ok', true, 'de', v_de, 'ate', v_ate, 'periodo', true,
    'funil', (select jsonb_build_object(
        'visita',    count(*) filter (where etapa = 'visita'),
        'item',      count(*) filter (where etapa = 'item'),
        'carrinho',  count(*) filter (where etapa = 'carrinho'),
        'finalizar', count(*) filter (where etapa = 'finalizar'),
        'pedido',    count(*) filter (where etapa = 'pedido'))
      from cardapio_funil f where f.dia between v_de and v_ate
       and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho)),
    'checkout', (select coalesce(jsonb_object_agg(etapa, n), '{}'::jsonb) from (
        select etapa, count(*) n from cardapio_checkout c where c.dia between v_de and v_ate
           and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = c.aparelho) group by etapa) z),
    'checkoutDesde', (select min(dia) from cardapio_checkout),
    'regioesDesde', (select min(dia) from cardapio_regioes),
    'serie', (select coalesce(jsonb_agg(jsonb_build_object('dia', d::date, 'visitas', coalesce(fv.n, 0), 'pedidos', coalesce(fp.n, 0)) order by d), '[]'::jsonb)
        from generate_series(v_de, v_ate, interval '1 day') d
        left join (select dia, count(*) n from cardapio_funil f where etapa = 'visita' and dia between v_de and v_ate
                    and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho) group by dia) fv on fv.dia = d::date
        left join (select (data_hora at time zone 'America/Sao_Paulo')::date dia, count(*) n from vendas
                    where origem = 'Cardápio' and status = 'Confirmada' and data_hora >= v_ini and data_hora < v_fim group by 1) fp on fp.dia = d::date),
    'pedidosCardapio', (select count(*) from vendas where origem = 'Cardápio' and status = 'Confirmada' and data_hora >= v_ini and data_hora < v_fim),
    'pontos', coalesce((select jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng, 'n', n)) from (
        select lat, lng, sum(n)::int n from cardapio_regioes where dia between v_de and v_ate group by lat, lng) x), '[]'::jsonb),
    'pedidos', '[]'::jsonb,
    'entregues', v_ent, 'entreguesIfood', v_enti, 'entreguesTotal', jsonb_array_length(v_h), 'semCoord', v_pend, 'naoLocalizados', v_nao,
    'restaurante', (select jsonb_build_object('lat', (valor->>'lat')::numeric, 'lng', (valor->>'lng')::numeric) from sistema where chave = 'PONTO_LOCAL' and jsonb_typeof(valor) = 'object'));
end $function$;
revoke all on function public.api_cardapio_periodo(jsonb) from public, anon;
grant execute on function public.api_cardapio_periodo(jsonb) to authenticated, service_role;


-- ======================================================================
-- 102-custos-saches-embalagem-gas-energia.sql
-- ======================================================================
-- Valores ESTIMADOS (ajustáveis em Produtos → Estoque). Gás e energia são "só custo": entram no custo, não descontam estoque.
alter table public.estoque add column if not exists so_custo boolean not null default false;

-- "só custo" não desconta estoque na venda
create or replace function public._consumo(p_itens jsonb)
 returns table(ingrediente_id uuid, qtd numeric) language sql stable security definer set search_path to 'public' as $function$
  with it as (
    select _uuid(e->>'produtoId') as produto_id, _uuid(e->>'comboId') as combo_id,
           _num(e->>'quantidade') as q, e->'adicionaisIds' as ads, e->'escolhas' as esc
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  ), consumo as (
    select pi.ingrediente_id, pi.quantidade_por_unidade * it.q as qtd
      from it join produto_ingredientes pi on pi.produto_id = it.produto_id
    union all
    select pi.ingrediente_id, pi.quantidade_por_unidade * ci.quantidade * it.q
      from it join combo_itens ci on ci.combo_id = it.combo_id and (not ci.escolha or jsonb_typeof(it.esc) is distinct from 'array')
              join produto_ingredientes pi on pi.produto_id = ci.produto_id
    union all
    select pi.ingrediente_id, pi.quantidade_por_unidade * esc.q * it.q
      from it
      cross join lateral (select _uuid(x->>'produtoId') as pid, _num(x->>'quantidade') as q
                            from jsonb_array_elements(case when jsonb_typeof(it.esc) = 'array' then it.esc else '[]'::jsonb end) x) esc
      join combo_itens cp on cp.combo_id = it.combo_id and cp.produto_id = esc.pid and cp.escolha
      join produto_ingredientes pi on pi.produto_id = esc.pid
    union all
    select a.ingrediente_id, coalesce(nullif(a.quantidade_descontar, 0), 1) * it.q
      from it
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(it.ads) = 'array' then it.ads else '[]'::jsonb end) x
      join adicionais a on a.id = _uuid(x)
      where a.ingrediente_id is not null
  )
  select c.ingrediente_id, sum(c.qtd) from consumo c
   where c.ingrediente_id is not null
     and not exists (select 1 from estoque s where s.id = c.ingrediente_id and s.so_custo)
   group by c.ingrediente_id having sum(c.qtd) <> 0
$function$;

-- cardápio: item "só custo" nunca deixa produto esgotado
create or replace view public.v_cardapio_esgotados as
 with ligado as (
   select coalesce((select ((sistema.valor #>> '{}'::text[]) = any (array['true','Sim'])) from sistema where sistema.chave = 'BLOQUEAR_ESTOQUE_NEGATIVO'), false) as on_
 ), falta as (
   select pi.produto_id,
          bool_or(((pi.quantidade_por_unidade > 0) and ((e.quantidade + 0.000000001) < pi.quantidade_por_unidade))) as f1,
          min(case when pi.quantidade_por_unidade > 0 then e.quantidade / pi.quantidade_por_unidade else null end) as razao
     from produto_ingredientes pi join estoque e on e.id = pi.ingrediente_id and not e.so_custo
    group by pi.produto_id
 )
 select 'produto'::text as tipo, p.id
   from v_cardapio_produtos p join falta f on f.produto_id = p.id, ligado
  where ligado.on_ and f.f1
 union all
 select 'combo'::text as tipo, b.id
   from v_cardapio_combos b, ligado
  where ligado.on_ and exists (select 1 from combo_itens ci join produto_ingredientes pi on pi.produto_id = ci.produto_id
                                 join estoque e on e.id = pi.ingrediente_id and not e.so_custo
                                where ci.combo_id = b.id and pi.quantidade_por_unidade > 0
                                  and (e.quantidade + 0.000000001) < pi.quantidade_por_unidade * greatest(coalesce(ci.quantidade, 1), 1)::numeric);
grant select on public.v_cardapio_esgotados to anon, authenticated;


-- ======================================================================
-- 103-ifood-0800-sem-cadastro.sql
-- ======================================================================
-- Pedido do iFood criava cliente repetido "Nome (iFood)" com telefone 0800 (o telefone do iFood é 0800 + código, reaproveitado
-- entre clientes). Venda do iFood não carimba (decisão do dono, 27/10). Telefone 0800 nunca vira cadastro.
create or replace function public._upsert_cliente(p_tel text, p_nome text)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_dig text := _so_digitos(p_tel);
begin
  if v_dig = '' then return null; end if;
  if v_dig like '0800%' then return null; end if;   -- 0800 é número de central (ex.: iFood), nunca de um cliente
  perform pg_advisory_xact_lock(hashtextextended('cliente:' || v_dig, 0));
  select id into v_id from clientes where _so_digitos(telefone) = v_dig limit 1;
  if found then
    if btrim(coalesce(p_nome, '')) <> '' then update clientes set nome = btrim(p_nome) where id = v_id and btrim(coalesce(nome, '')) = ''; end if;
    return v_id;
  end if;
  begin
    v_id := gen_random_uuid();
    insert into clientes (id, nome, telefone, primeiro_contato) values (v_id, btrim(coalesce(p_nome, '')), btrim(p_tel), now());
  exception when unique_violation then
    select id into v_id from clientes where _so_digitos(telefone) = v_dig limit 1;
    if v_id is null then raise; end if;
  end;
  return v_id;
end $function$;

create or replace function public._carimbar_fidelidade(p_tel text, p_nome text, p_venda uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_cli uuid; f fidelidade%rowtype; v_marcou boolean := false;
begin
  if p_venda is not null and exists (select 1 from vendas where id = p_venda and (canal = 'iFood' or forma_pagamento ilike 'iFood%')) then return; end if;
  v_cli := _upsert_cliente(p_tel, p_nome);
  if v_cli is null then return; end if;
  if p_venda is not null and exists (select 1 from fidelidade_marcas where venda_id = p_venda) then return; end if;
  select * into f from fidelidade where cliente_id = v_cli for update;
  if found then
    if f.carimbos < 10 then
      update fidelidade set carimbos = f.carimbos + 1, atualizada_em = now() where cliente_id = v_cli;
      perform _auditar('Marca adicionada (fidelidade)', (f.carimbos + 1) || '/10', p_tel);
      v_marcou := true;
    end if;
  else
    insert into fidelidade (cliente_id, carimbos, atualizada_em) values (v_cli, 1, now());
    perform _auditar('Cliente novo no fidelidade', coalesce(p_nome, ''), p_tel);
    v_marcou := true;
  end if;
  if v_marcou and p_venda is not null then
    insert into fidelidade_marcas (venda_id, cliente_id, premios_resgatados)
    values (p_venda, v_cli, coalesce((select premios_resgatados from fidelidade where cliente_id = v_cli), 0)) on conflict do nothing;
  end if;
end $function$;
-- (no projeto atual também foram escondidos os 9 cadastros repetidos com 0800 e zerados os carimbos deles; os dados já vão no 02-dados de uma cópia nova)


-- ======================================================================
-- 105-custo-real-taxas-oleo-perdas-sacola.sql
-- ======================================================================
-- Valores ESTIMADOS (editáveis): taxas das formas, óleo/manteiga/temperos ("só custo"), perdas 4% sobre ingredientes, custo por pedido.
insert into public.sistema (chave, valor) values ('PerdaPercentual', '4'::jsonb) on conflict (chave) do nothing;
create or replace function public._perda_pct() returns numeric language sql stable security definer set search_path to 'public' as $$
  select least(30, greatest(0, coalesce((select (valor #>> '{}')::numeric from sistema where chave = 'PerdaPercentual'), 0))) $$;
create or replace function public._custo_receita(p_prod uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select round(sum(pi.quantidade_por_unidade * coalesce(e.custo_unitario, 0)
           * case when e.so_custo or e.ingrediente ilike 'Embalagem%'
                   or exists (select 1 from produtos b where b.id = p_prod and b.estoque_proprio_ingrediente_id is not null)
                  then 1 else 1 + public._perda_pct() / 100 end), 2)
  from produto_ingredientes pi join estoque e on e.id = pi.ingrediente_id
  where pi.produto_id = p_prod
$function$;
do $do$ declare d text; n text; begin
  d := pg_get_functiondef('public.api_simular_precificacao(jsonb)'::regprocedure);
  if position('_custo_receita' in d) = 0 then
    n := replace(d, $a$  select coalesce(sum(e.custo_unitario * pi.quantidade_por_unidade), 0) into v_tec
    from produto_ingredientes pi join estoque e on e.id = pi.ingrediente_id where pi.produto_id = pr.id;$a$,
      $b$  v_tec := coalesce(public._custo_receita(pr.id), 0);   -- mesmo custo do cadastro (inclui perdas e itens "só custo")$b$);
    if n = d then raise exception 'api_simular_precificacao: ponto de troca não encontrado'; end if;
    execute n;
  end if;
end $do$;

insert into public.sistema (chave, valor) values ('CustoPorPedido', '{"entrega":0.60,"retirada":0.40,"mesa":0}'::jsonb) on conflict (chave) do nothing;
alter table public.vendas add column if not exists custo_pedido numeric not null default 0;
create or replace function public._custo_por_pedido(p_tipo text) returns numeric language sql stable security definer set search_path to 'public' as $$
  select greatest(0, coalesce((select (valor ->> case p_tipo when 'Entrega' then 'entrega' when 'Retirada' then 'retirada' else 'mesa' end)::numeric
                                 from sistema where chave = 'CustoPorPedido'), 0)) $$;
create or replace function public._trg_vendas_custo_pedido() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_novo numeric;
begin
  if tg_op = 'INSERT' then
    new.custo_pedido := _custo_por_pedido(new.tipo::text);
    new.custo_total := round(coalesce(new.custo_total, 0) + new.custo_pedido, 2);
  elsif new.custo_total is distinct from old.custo_total or new.tipo is distinct from old.tipo then
    v_novo := case when new.tipo is distinct from old.tipo then _custo_por_pedido(new.tipo::text) else old.custo_pedido end;
    new.custo_total := round(case when new.custo_total is distinct from old.custo_total then coalesce(new.custo_total, 0)
                                  else coalesce(old.custo_total, 0) - old.custo_pedido end + v_novo, 2);
    new.custo_pedido := v_novo;
  end if;
  return new;
end $$;
create or replace trigger vendas_custo_pedido before insert or update of custo_total, tipo on public.vendas
  for each row execute function public._trg_vendas_custo_pedido();

create or replace function public.api_custos_gerais(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_p numeric; v_e numeric; v_r numeric; v_m numeric; v_antes numeric := _perda_pct();
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce((p->>'salvar')::boolean, false) then
    v_p := _num(p->>'perdaPct'); v_e := _num(p->>'entrega'); v_r := _num(p->>'retirada'); v_m := _num(p->>'mesa', 0);
    if v_p < 0 or v_p > 30 then return _falha('Perdas: use de 0 a 30%.'); end if;
    if v_e < 0 or v_r < 0 or v_m < 0 or v_e > 50 or v_r > 50 or v_m > 50 then return _falha('Custo por pedido inválido.'); end if;
    perform _cfg_gravar('PerdaPercentual', to_jsonb(round(v_p, 2)));
    perform _cfg_gravar('CustoPorPedido', jsonb_build_object('entrega', round(v_e, 2), 'retirada', round(v_r, 2), 'mesa', round(v_m, 2)));
    if round(v_p, 2) is distinct from v_antes then perform _recalc_produtos(array(select id from produtos)); end if;
    perform _auditar('Custos gerais alterados', 'perdas ' || round(v_p, 2) || '%', 'entrega R$ ' || round(v_e, 2) || ' · retirada R$ ' || round(v_r, 2) || ' · mesa R$ ' || round(v_m, 2));
  end if;
  return jsonb_build_object('ok', true, 'message', case when coalesce((p->>'salvar')::boolean, false) then 'Custos salvos. Os custos dos produtos foram recalculados.' end,
    'perdaPct', _perda_pct(), 'entrega', _custo_por_pedido('Entrega'), 'retirada', _custo_por_pedido('Retirada'), 'mesa', _custo_por_pedido('Mesa'),
    'taxas', (select jsonb_agg(jsonb_build_object('nome', nome, 'pct', taxa_percentual, 'fixa', taxa_fixa) order by ordem) from formas_pagamento where ativa));
end $$;
revoke all on function public.api_custos_gerais(jsonb), public._trg_vendas_custo_pedido() from public, anon;
grant execute on function public.api_custos_gerais(jsonb) to authenticated, service_role;
revoke all on function public._perda_pct(), public._custo_por_pedido(text) from public, anon;
grant execute on function public._perda_pct(), public._custo_por_pedido(text) to authenticated, service_role;
select public._recalc_produtos(array(select id from public.produtos));


-- ======================================================================
-- 106-preco-sugerido.sql
-- ======================================================================
-- Parâmetros do preço sugerido (a conta é feita na tela): custo ÷ custo-alvo, com travas (aumento máximo por vez, lucro mínimo).
insert into public.sistema (chave, valor) values ('PrecoSugeridoCfg', '{"lanche":35,"porcao":30,"bebida":60,"combo":40,"maxAumento":25,"margemMin":15,"final":0.90}'::jsonb)
on conflict (chave) do nothing;

create or replace function public.api_custos_gerais(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_p numeric; v_e numeric; v_r numeric; v_m numeric; v_antes numeric := _perda_pct(); v_cfg jsonb; k text; ps jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if coalesce((p->>'salvar')::boolean, false) then
    v_p := _num(p->>'perdaPct'); v_e := _num(p->>'entrega'); v_r := _num(p->>'retirada'); v_m := _num(p->>'mesa', 0);
    if v_p < 0 or v_p > 30 then return _falha('Perdas: use de 0 a 30%.'); end if;
    if v_e < 0 or v_r < 0 or v_m < 0 or v_e > 50 or v_r > 50 or v_m > 50 then return _falha('Custo por pedido inválido.'); end if;
    ps := p->'precoSugerido';
    if jsonb_typeof(ps) = 'object' then
      foreach k in array array['lanche','porcao','bebida','combo'] loop
        if _num(ps->>k) < 10 or _num(ps->>k) > 90 then return _falha('Custo-alvo do preço sugerido: use de 10% a 90%.'); end if;
      end loop;
      if _num(ps->>'maxAumento', 25) < 5 or _num(ps->>'maxAumento', 25) > 100 then return _falha('Aumento máximo por vez: use de 5% a 100%.'); end if;
      if _num(ps->>'margemMin', 15) < 0 or _num(ps->>'margemMin', 15) > 60 then return _falha('Lucro mínimo: use de 0% a 60%.'); end if;
      v_cfg := jsonb_build_object('lanche', round(_num(ps->>'lanche'), 1), 'porcao', round(_num(ps->>'porcao'), 1), 'bebida', round(_num(ps->>'bebida'), 1),
                                  'combo', round(_num(ps->>'combo'), 1), 'maxAumento', round(_num(ps->>'maxAumento', 25), 1), 'margemMin', round(_num(ps->>'margemMin', 15), 1), 'final', 0.90);
      perform _cfg_gravar('PrecoSugeridoCfg', v_cfg);
    end if;
    perform _cfg_gravar('PerdaPercentual', to_jsonb(round(v_p, 2)));
    perform _cfg_gravar('CustoPorPedido', jsonb_build_object('entrega', round(v_e, 2), 'retirada', round(v_r, 2), 'mesa', round(v_m, 2)));
    if round(v_p, 2) is distinct from v_antes then perform _recalc_produtos(array(select id from produtos)); end if;
    perform _auditar('Custos gerais alterados', 'perdas ' || round(v_p, 2) || '%', 'entrega R$ ' || round(v_e, 2) || ' · retirada R$ ' || round(v_r, 2) || ' · mesa R$ ' || round(v_m, 2)
      || coalesce(' · preço sugerido ' || v_cfg::text, ''));
  end if;
  return jsonb_build_object('ok', true, 'message', case when coalesce((p->>'salvar')::boolean, false) then 'Custos salvos. Os custos dos produtos foram recalculados.' end,
    'perdaPct', _perda_pct(), 'entrega', _custo_por_pedido('Entrega'), 'retirada', _custo_por_pedido('Retirada'), 'mesa', _custo_por_pedido('Mesa'),
    'precoSugerido', coalesce((select valor from sistema where chave = 'PrecoSugeridoCfg'), '{"lanche":35,"porcao":30,"bebida":60,"combo":40,"maxAumento":25,"margemMin":15,"final":0.90}'::jsonb),
    'taxas', (select jsonb_agg(jsonb_build_object('nome', nome, 'pct', taxa_percentual, 'fixa', taxa_fixa) order by ordem) from formas_pagamento where ativa));
end $$;


-- ======================================================================
-- 107-cardapio-turno-desde-fechamento.sql
-- ======================================================================
-- "Cardápio hoje" (quadro e pop-up) contam o TURNO = desde o fechamento do caixa anterior (no máximo 48 h).
create or replace function public._cardapio_turno_inicio() returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select greatest(coalesce((select max(fechamento) from caixa_sessoes where status = 'Fechado' and fechamento <= now()), now() - interval '24 hours'),
                  now() - interval '48 hours') $$;
revoke all on function public._cardapio_turno_inicio() from public, anon;
grant execute on function public._cardapio_turno_inicio() to authenticated, service_role;

create or replace function public.api_visitas_cardapio_hoje(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_ini timestamptz := _cardapio_turno_inicio();
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'desde', v_ini,
    'hoje', (select count(distinct f.aparelho) from cardapio_funil f where f.etapa = 'visita' and f.primeiro_em >= v_ini
              and not exists (select 1 from cardapio_aparelhos_equipe e where e.aparelho = f.aparelho)));
end $function$;

do $do$ declare d text; n text; begin
  d := pg_get_functiondef('public.api_cardapio_hoje(jsonb)'::regprocedure);
  if position('_cardapio_turno_inicio' in d) = 0 then
    n := replace(d, $a$  select abertura into v_ini from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  v_turno := v_ini is not null;
  v_ini := coalesce(v_ini, now() - interval '24 hours');$a$,
      $b$  v_turno := exists (select 1 from caixa_sessoes where status = 'Aberto');
  v_ini := _cardapio_turno_inicio();   -- desde o fechamento do caixa anterior (entra quem olhou antes de abrir)$b$);
    if n = d then raise exception 'api_cardapio_hoje: ponto de troca não encontrado'; end if;
    execute n;
  end if;
  d := pg_get_functiondef('public.api_cardapio_checkout(jsonb)'::regprocedure);
  if position('_cardapio_turno_inicio' in d) = 0 then
    n := replace(d, $a$  select abertura into v_ini from caixa_sessoes where status = 'Aberto' order by abertura desc limit 1;
  v_ini := coalesce(v_ini, now() - interval '24 hours');$a$, $b$  v_ini := _cardapio_turno_inicio();$b$);
    if n = d then raise exception 'api_cardapio_checkout: ponto de troca não encontrado'; end if;
    execute n;
  end if;
end $do$;


-- =====================================================================
-- VERSÃO 1.25 (01/11/2026) — blocos 108 a 111
-- =====================================================================
-- 108) RAIO-X DO NEGÓCIO (v1.25): um painel por período com o que os dados já guardados mostram.
-- Calor dia × hora, iFood × sistema próprio, clientes fiéis do iFood, tempos de cada etapa, cancelamentos,
-- pedidos parados, custos de fornecedor que subiram e perdas reais × estimadas. Só Admin.
-- Pedidos depois da meia-noite (até 5h59) contam na noite do dia anterior (o turno é um só).
create or replace function public.api_raio_x(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date; v_de date; v_ate date; v_x date;
  v_ini timestamptz; v_fim timestamptz; v_pct numeric := coalesce(_perda_pct(), 0); r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_de := coalesce(_data_iso(btrim(coalesce(p->>'de', ''))), v_hoje - 29);
  v_ate := coalesce(_data_iso(btrim(coalesce(p->>'ate', ''))), v_hoje);
  if v_ate < v_de then v_x := v_de; v_de := v_ate; v_ate := v_x; end if;
  if v_ate - v_de > 366 then return _falha('Escolha um período de até 1 ano.'); end if;
  v_ini := v_de::timestamp at time zone 'America/Sao_Paulo' + interval '6 hours';
  v_fim := (v_ate + 1)::timestamp at time zone 'America/Sao_Paulo' + interval '6 hours';
  r := jsonb_build_object('ok', true, 'de', v_de, 'ate', v_ate, 'perdaPct', v_pct);

  -- 1) calor: dia da semana (da noite) × hora
  r := r || jsonb_build_object(
    'calor', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'h', h, 'n', n, 'v', vt)), '[]'::jsonb) from (
        select extract(dow from (data_hora at time zone 'America/Sao_Paulo') - interval '6 hours')::int d,
               extract(hour from data_hora at time zone 'America/Sao_Paulo')::int h, count(*)::int n, round(sum(valor_total), 2) vt
          from vendas where status = 'Confirmada' and data_hora >= v_ini and data_hora < v_fim group by 1, 2) x),
    'diasSemana', (select jsonb_object_agg(d, n) from (
        select extract(dow from g)::int d, count(*)::int n from generate_series(v_de, v_ate, interval '1 day') g group by 1) y));

  -- 2) iFood × sistema próprio
  r := r || jsonb_build_object('canais', (
    with base as (
      select v.id, v.data_hora, v.valor_total, case when v.canal = 'iFood' then 'ifood' else 'proprio' end c,
             case when v.canal = 'iFood' then 'i:' || coalesce(ip.bruto #>> '{customer,id}', v.cliente_id::text)
                  else coalesce('c:' || v.cliente_id::text, 't:' || nullif(case when length(_so_digitos(v.telefone_cliente)) >= 8 then _so_digitos(v.telefone_cliente) end, '')) end k
        from vendas v left join ifood_pedidos ip on ip.venda_id = v.id
       where v.status = 'Confirmada' and v.data_hora < v_fim),
    hist as (select k, count(*) n from base where k is not null group by k),
    per as (select * from base where data_hora >= v_ini),
    tx as (select c, sum(case when c = 'ifood' and tx0 = 0 then vt * (select coalesce(max(taxa_percentual), 0) from formas_pagamento where nome ilike 'ifood%') / 100 else tx0 end) t
             from (select case when v.canal = 'iFood' then 'ifood' else 'proprio' end c, v.valor_total vt,
                          coalesce((select sum(coalesce(pv.taxa_aplicada, 0)) from pagamentos_venda pv where pv.venda_id = v.id), 0) tx0
                     from vendas v where v.status = 'Confirmada' and v.data_hora >= v_ini and v.data_hora < v_fim) q group by 1)
    select coalesce(jsonb_object_agg(c, jsonb_build_object('pedidos', pedidos, 'total', total, 'ticket', ticket, 'clientes', clientes, 'voltaram', voltaram, 'taxas', coalesce((select t from tx where tx.c = z.c), 0))), '{}'::jsonb)
      from (select per.c, count(*)::int pedidos, round(sum(per.valor_total), 2) total, round(avg(per.valor_total), 2) ticket,
                   count(distinct per.k)::int clientes,
                   count(distinct per.k) filter (where (select n from hist where hist.k = per.k) > 1)::int voltaram
              from per group by per.c) z));

  -- 3) clientes fiéis do iFood (todo o histórico). O iFood informa quantas vezes o cliente já comprou da loja.
  r := r || jsonb_build_object('fieisIfood', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'vezes', vezes, 'ultimo', ultimo, 'bairro', bairro, 'sumido', ultimo < now() - interval '30 days') order by vezes desc, ultimo desc), '[]'::jsonb) from (
      select * from (
      select max(ip.bruto #>> '{customer,name}') nome,
             greatest(count(*)::int, coalesce(max(case when ip.bruto #>> '{customer,ordersCountOnMerchant}' ~ '^[0-9]+$' then (ip.bruto #>> '{customer,ordersCountOnMerchant}')::int end), 0) + 1) vezes,
             max(v.data_hora) ultimo, mode() within group (order by ip.bruto #>> '{delivery,deliveryAddress,neighborhood}') bairro
        from ifood_pedidos ip join vendas v on v.id = ip.venda_id
       where not coalesce(ip.simulado, false) and v.status = 'Confirmada' and ip.bruto #>> '{customer,id}' is not null
       group by ip.bruto #>> '{customer,id}') f where vezes >= 2 order by vezes desc, ultimo desc limit 15) z),
    'ifoodClientesTotal', (select count(distinct ip.bruto #>> '{customer,id}') from ifood_pedidos ip join vendas v on v.id = ip.venda_id where not coalesce(ip.simulado, false) and v.status = 'Confirmada'));

  -- 4) tempos de cada etapa (minutos; ignora valores fora de 0 a 180 min, que são esquecimentos de tocar no status)
  r := r || jsonb_build_object('tempos', (
    with t as (
      select v.tipo, v.entregador_id, v.caixa_id, extract(hour from v.data_hora at time zone 'America/Sao_Paulo')::int h,
             extract(epoch from v.inicio_preparo_em - v.data_hora) / 60 aceitar,
             extract(epoch from v.pronta_em - v.inicio_preparo_em) / 60 preparo,
             case when v.tipo = 'Entrega' then extract(epoch from v.concluida_em - v.saiu_em) / 60 end rota,
             case when v.tipo = 'Entrega' then extract(epoch from v.concluida_em - v.data_hora) / 60 end total
        from vendas v where v.status = 'Confirmada' and v.mesa_id is null and v.data_hora >= v_ini and v.data_hora < v_fim),
    f as (select tipo, entregador_id, caixa_id, h,
                 case when aceitar between 0 and 180 then aceitar end aceitar, case when preparo between 0 and 180 then preparo end preparo,
                 case when rota between 0 and 180 then rota end rota, case when total between 0 and 180 then total end total from t)
    select jsonb_build_object(
      'aceitar', round(avg(aceitar)), 'preparo', round(avg(preparo)), 'rota', round(avg(rota)), 'total', round(avg(total)),
      'nPreparo', count(preparo), 'nTotal', count(total),
      'porHora', (select coalesce(jsonb_agg(jsonb_build_object('h', h, 'n', n, 'preparo', pr) order by (h + 18) % 24), '[]'::jsonb)
                    from (select h, count(preparo)::int n, round(avg(preparo)) pr from f group by h having count(preparo) > 0) x),
      'porEntregador', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'n', n, 'rota', ro) order by n desc), '[]'::jsonb)
                    from (select coalesce(u.nome, 'Entrega do iFood / sem entregador') nome, count(f.rota)::int n, round(avg(f.rota)) ro
                            from f left join usuarios u on u.id = f.entregador_id where f.rota is not null group by 1) x),
      'porTurno', (select coalesce(jsonb_agg(jsonb_build_object('abertura', abertura, 'n', n, 'preparo', pr, 'total', tt) order by abertura desc), '[]'::jsonb)
                    from (select cs.abertura, count(*)::int n, round(avg(f.preparo)) pr, round(avg(f.total)) tt
                            from f join caixa_sessoes cs on cs.id = f.caixa_id group by cs.abertura order by cs.abertura desc limit 14) x))
      from f));

  -- 5) cancelamentos (testes ficam de fora e são contados à parte)
  r := r || jsonb_build_object(
    'cancel', (select coalesce(jsonb_agg(jsonb_build_object('motivo', m, 'n', n) order by n desc), '[]'::jsonb) from (
        select coalesce(nullif(btrim(split_part(motivo_cancelamento, ' · ', 1)), ''), 'Sem motivo') m, count(*)::int n from vendas
         where status = 'Cancelada' and data_hora >= v_ini and data_hora < v_fim and coalesce(motivo_cancelamento, '') !~* 'teste'
         group by 1 order by 2 desc limit 10) x),
    'cancelTestes', (select count(*) from vendas where status = 'Cancelada' and data_hora >= v_ini and data_hora < v_fim and motivo_cancelamento ~* 'teste'),
    'pedidosTotal', (select count(*) from vendas where data_hora >= v_ini and data_hora < v_fim and not (status = 'Cancelada' and coalesce(motivo_cancelamento, '') ~* 'teste')));

  -- 6) pedidos parados (alertas automáticos que dispararam)
  r := r || jsonb_build_object(
    'parados', (select coalesce(jsonb_object_agg(coalesce(regra, '?'), n), '{}'::jsonb) from (
        select regra, count(*)::int n from alertas_envios where tipo = 'pedido' and primeiro_em >= v_ini and primeiro_em < v_fim group by 1) x),
    'paradosHora', (select coalesce(jsonb_agg(jsonb_build_object('h', h, 'n', n) order by (h + 18) % 24), '[]'::jsonb) from (
        select extract(hour from primeiro_em at time zone 'America/Sao_Paulo')::int h, count(*)::int n from alertas_envios
         where tipo = 'pedido' and primeiro_em >= v_ini and primeiro_em < v_fim group by 1) x));

  -- 7) custos de fornecedor que mudaram 5% ou mais nos 90 dias até o fim do período
  r := r || jsonb_build_object('custos', (select coalesce(jsonb_agg(jsonb_build_object('ingrediente', e.ingrediente, 'antes', z.ini, 'agora', z.fim, 'pct', z.pct, 'unidade', e.unidade::text,
        'produtos', (select coalesce(jsonb_agg(pr.nome order by pr.nome), '[]'::jsonb) from (select distinct pd.nome from produto_ingredientes pi join produtos pd on pd.id = pi.produto_id and pd.ativo where pi.ingrediente_id = z.ingrediente_id limit 6) pr),
        'nProdutos', (select count(distinct pi.produto_id) from produto_ingredientes pi join produtos pd on pd.id = pi.produto_id and pd.ativo where pi.ingrediente_id = z.ingrediente_id)) order by z.pct desc), '[]'::jsonb)
      from (select ingrediente_id, ini, fim, round((fim / ini - 1) * 100, 1) pct from (
              select ingrediente_id,
                     (array_agg(coalesce(nullif(custo_anterior, 0), custo_unitario) order by data_nota, criado_em))[1] ini,
                     (array_agg(custo_unitario order by data_nota desc, criado_em desc))[1] fim
                from compra_custos where ativo and data_nota > v_ate - 90 and data_nota <= v_ate group by 1) a
             where ini > 0 and abs(fim / ini - 1) >= 0.05) z join estoque e on e.id = z.ingrediente_id));

  -- 8) perdas reais registradas × estimativa usada no custo
  r := r || jsonb_build_object('perdas', (select jsonb_build_object(
      'real', coalesce((select round(sum(abs(m.quantidade) * coalesce(e.custo_unitario, 0)), 2) from movimentacoes_estoque m join estoque e on e.id = m.ingrediente_id
                         where m.tipo = 'Perda' and m.data >= v_ini and m.data < v_fim), 0),
      'registros', (select count(*) from movimentacoes_estoque m where m.tipo = 'Perda' and m.data >= v_ini and m.data < v_fim),
      'estimado', coalesce((select round(sum(custo_total) * v_pct / (100 + v_pct), 2) from vendas where status = 'Confirmada' and data_hora >= v_ini and data_hora < v_fim), 0),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'valor', vl) order by vl desc), '[]'::jsonb) from (
          select e.ingrediente nome, round(sum(abs(m.quantidade) * coalesce(e.custo_unitario, 0)), 2) vl from movimentacoes_estoque m join estoque e on e.id = m.ingrediente_id
           where m.tipo = 'Perda' and m.data >= v_ini and m.data < v_fim group by 1 order by 2 desc limit 6) x))));
  return r;
end $fn$;
revoke all on function public.api_raio_x(jsonb) from public, anon;
grant execute on function public.api_raio_x(jsonb) to authenticated;

-- 109a) "Perdi um produto pronto" (v1.25): baixa a receita inteira do estoque como Perda (cada ingrediente vira uma linha de Perda)
create or replace function public.api_registrar_perda_produto(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_q numeric := _num(p->>'quantidade'); v_mot text := btrim(coalesce(p->>'motivo', ''));
  v_pid uuid := _uuid(p->>'produtoId'); v_nome text; c record; e estoque%rowtype; v_n int := 0; v_valor numeric := 0; v_dep numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_q is null or v_q <= 0 or v_q > 100 then return _falha('Informe uma quantidade entre 1 e 100.'); end if;
  if v_mot = '' then return _falha('Informe o motivo da perda.'); end if;
  select nome into v_nome from produtos where id = v_pid;
  if v_nome is null then return _falha('Produto não encontrado.'); end if;
  for c in select * from _consumo(jsonb_build_array(jsonb_build_object('produtoId', v_pid, 'quantidade', v_q))) loop
    select * into e from estoque where id = c.ingrediente_id for update;
    if not found then continue; end if;
    v_dep := greatest(0, e.quantidade - c.qtd);
    update estoque set quantidade = v_dep where id = e.id;
    insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
    values (e.id, 'Perda', -c.qtd, e.quantidade, v_dep, left('Produto perdido: ' || v_nome || ' ×' || trim(to_char(v_q, 'FM999990.##')) || ' (' || v_mot || ')', 300), auth.uid());
    v_n := v_n + 1; v_valor := v_valor + c.qtd * coalesce(e.custo_unitario, 0);
  end loop;
  if v_n = 0 then return _falha(v_nome || ' não tem ingredientes na receita. Cadastre a receita ou registre a perda pelo ingrediente, no Estoque.'); end if;
  perform _auditar('Perda de produto pronto', v_nome || ' ×' || v_q || ' (' || v_mot || ') · ' || v_n || ' ingrediente(s) · ' || _brl(v_valor));
  v_r := jsonb_build_object('ok', true, 'message', 'Perda registrada: ' || v_nome || ' ×' || trim(to_char(v_q, 'FM999990.##')) || '. ' || v_n || ' ingrediente(s) saíram do estoque (cerca de ' || _brl(v_valor) || ').', 'valor', round(v_valor, 2));
  if v_req is not null then perform _idem_gravar(v_req, 'registrarPerdaProduto', v_r); end if;
  return v_r;
end $fn$;
revoke all on function public.api_registrar_perda_produto(jsonb) from public, anon;
grant execute on function public.api_registrar_perda_produto(jsonb) to authenticated;

-- 109b) alerta ao Admin: cozinha bem mais lenta que o normal no turno aberto (acrescenta a regra 3 em alertas_dono_cron)
do $do$
declare d text := pg_get_functiondef('public.alertas_dono_cron()'::regprocedure); a text; b text;
begin
  if position('dono:ritmo_lento' in d) > 0 then return; end if;
  a := 'v_h int := extract(hour from (now() at time zone ''America/Sao_Paulo''))::int;';
  if position(a in d) = 0 then raise exception 'âncora declare não achada'; end if;
  d := replace(d, a, a || ' v_med numeric; v_base numeric;');
  a := '  update alertas_envios set resolvido_em = now() where tipo = ''dono''';
  b := $b$  -- 3) ritmo lento: na última hora o preparo médio do turno passou bastante do normal dos últimos 30 dias (v1.25)
  if v_cx.id is not null then
    select count(*), avg(extract(epoch from pronta_em - inicio_preparo_em) / 60) into v_n, v_med from vendas
     where caixa_id = v_cx.id and status = 'Confirmada' and pronta_em > now() - interval '60 minutes' and inicio_preparo_em is not null
       and pronta_em - inicio_preparo_em between interval '0' and interval '180 minutes';
    select avg(extract(epoch from pronta_em - inicio_preparo_em) / 60) into v_base from vendas
     where status = 'Confirmada' and pronta_em > now() - interval '30 days' and pronta_em < now() - interval '1 hour' and inicio_preparo_em is not null
       and pronta_em - inicio_preparo_em between interval '0' and interval '180 minutes';
    if v_n >= 3 and coalesce(v_base, 0) > 0 and v_med > greatest(v_base * 1.4, v_base + 8) then
      ativos := array_append(ativos, 'dono:ritmo_lento');
      perform _dono_avisar('dono:ritmo_lento', 'Cozinha mais lenta que o normal',
        'Na última hora o preparo levou em média ' || round(v_med) || ' min (o normal é ' || round(v_base) || ' min). ' || v_n || ' pedido(s).', interval '2 hours');
    end if;
  end if;
$b$;
  if position(a in d) = 0 then raise exception 'âncora update não achada'; end if;
  d := replace(d, a, b || a);
  execute d;
end $do$;

-- 109c) cupom de aniversário ligado (pedido do dono em 01/11/2026), como ele mesmo configurou
update cupons set ativa = true where automatico = 'aniversario' and excluido_em is null;

-- 110) PROMOÇÕES POR AVISO (v1.25). Os aparelhos aceitaram "avisos dos pedidos"; promoção só vai para quem aceitar À PARTE.
--      Precisa da função push-enviar versão v1.25 (pasta funcoes/push-enviar), que entende { promo:true, campanhaId }.
alter table public.push_clientes add column if not exists promo_ok boolean not null default false;
alter table public.push_clientes add column if not exists promo_em timestamptz;
create table if not exists public.push_campanhas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null, texto text not null,
  criado_por uuid, criado_em timestamptz not null default now(),
  alvo int not null default 0, enviados int, falhas int, removidos int, concluida_em timestamptz);
alter table public.push_campanhas enable row level security;
revoke all on public.push_campanhas from anon;

create or replace function public.api_push_cliente_promo(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ep text := btrim(coalesce(p->>'endpoint', '')); v_on boolean := coalesce((p->>'promo')::boolean, false); v_ip text := _ip_cliente(); v_n int;
begin
  if v_ep not like 'https://%' or char_length(v_ep) > 800 then return _falha('Aparelho sem avisos ligados.'); end if;
  if _excedeu('pushpromo_ip_' || v_ip, 30) then return _falha('Muitas tentativas. Tente mais tarde.'); end if;
  perform _registrar_falha('pushpromo_ip_' || v_ip, 600);
  update push_clientes set promo_ok = v_on, promo_em = now() where endpoint = v_ep;
  get diagnostics v_n = row_count;
  if v_n = 0 then return _falha('Os avisos deste aparelho não estão ligados. Ligue os avisos primeiro.'); end if;
  return jsonb_build_object('ok', true, 'promo', v_on);
end $fn$;
revoke all on function public.api_push_cliente_promo(jsonb) from public;
grant execute on function public.api_push_cliente_promo(jsonb) to anon, authenticated;

create or replace function public.api_push_promo_resumo(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'promo', (select count(*) from push_clientes where promo_ok),
    'aparelhos', (select count(*) from push_clientes),
    'campanhas', (select coalesce(jsonb_agg(jsonb_build_object('titulo', c.titulo, 'texto', c.texto, 'em', c.criado_em, 'alvo', c.alvo, 'enviados', c.enviados, 'falhas', c.falhas, 'removidos', c.removidos, 'concluida', c.concluida_em is not null, 'por', u.nome) order by c.criado_em desc), '[]'::jsonb)
                    from (select * from push_campanhas order by criado_em desc limit 10) c left join usuarios u on u.id = c.criado_por));
end $fn$;
revoke all on function public.api_push_promo_resumo(jsonb) from public, anon;
grant execute on function public.api_push_promo_resumo(jsonb) to authenticated;

create or replace function public.api_push_promo_enviar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_t text := btrim(coalesce(p->>'titulo', '')); v_x text := btrim(coalesce(p->>'texto', '')); v_alvo int; v_id uuid; v_ult timestamptz;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if char_length(v_t) < 3 or char_length(v_t) > 60 then return _falha('O título precisa ter de 3 a 60 letras.'); end if;
  if char_length(v_x) < 3 or char_length(v_x) > 140 then return _falha('O texto precisa ter de 3 a 140 letras.'); end if;
  select max(criado_em) into v_ult from push_campanhas;
  if v_ult > now() - interval '6 hours' then
    return _falha('Já foi enviada uma promoção às ' || to_char(v_ult at time zone 'America/Sao_Paulo', 'HH24:MI') || '. Espere 6 horas entre uma e outra para o cliente não desligar os avisos.');
  end if;
  select count(*) into v_alvo from push_clientes where promo_ok;
  if v_alvo = 0 then return _falha('Ainda nenhum cliente aceitou receber promoções.'); end if;
  insert into push_campanhas (titulo, texto, criado_por, alvo) values (v_t, v_x, auth.uid(), v_alvo) returning id into v_id;
  perform chamar_edge('push-enviar', jsonb_build_object('promo', true, 'campanhaId', v_id, 'titulo', v_t, 'texto', v_x, 'tag', 'promo-' || left(v_id::text, 8)));
  perform _auditar('Promoção por aviso', v_t || ' — ' || v_x || ' (' || v_alvo || ' aparelho(s))');
  return jsonb_build_object('ok', true, 'message', 'Promoção enviada para ' || v_alvo || ' aparelho(s). O resultado aparece na lista em alguns segundos.', 'alvo', v_alvo);
end $fn$;
revoke all on function public.api_push_promo_enviar(jsonb) from public, anon;
grant execute on function public.api_push_promo_enviar(jsonb) to authenticated;

-- 111) api_conta_incentivo também diz se o presente de aniversário está ligado (a conta convida quem não informou a data)
create or replace function public.api_conta_incentivo(p jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object('ok', true,
    'boasVindas', (select jsonb_build_object('tipo', k.tipo, 'valor', k.valor, 'minimo', k.valor_minimo)
                     from cupons k where k.automatico = 'boas_vindas' and k.ativa and k.excluido_em is null limit 1),
    'fidelidade', (select beneficio from promocoes where ativa and tipo ilike 'Fidelidade%' order by nome limit 1),
    'indicacao', (select jsonb_build_object('tipo', k.tipo, 'valor', k.valor) from cupons k where k.automatico = 'indicacao_indicador' and k.ativa and k.excluido_em is null limit 1),
    'aniversario', (select jsonb_build_object('tipo', k.tipo, 'valor', k.valor) from cupons k where k.automatico = 'aniversario' and k.ativa and k.excluido_em is null limit 1));
$fn$;

-- 112) PROMOÇÕES CONFIGURÁVEIS PELO DONO (v1.26): preço por dia da semana e "compre e ganhe".
-- Valem só no cardápio online (entrega e retirada); mesa, balcão e iFood não mudam.
-- "Dia" segue o turno: pedido feito entre 0h e 5h59 conta na noite do dia anterior.
create table if not exists public.promo_dia (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  produto_id uuid references public.produtos(id) on delete cascade,
  combo_id uuid references public.combos(id) on delete cascade,
  dias int[] not null,
  hora_inicio time, hora_fim time,
  tipo text not null check (tipo in ('preco', 'percentual')),
  valor numeric not null check (valor > 0),
  acumula_cupom boolean not null default false,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  check ((produto_id is null) <> (combo_id is null)));
alter table public.promo_dia enable row level security;
revoke all on public.promo_dia from anon;

create table if not exists public.promo_compre_ganhe (
  id uuid primary key default gen_random_uuid(),
  nome text not null default '',
  valor_minimo numeric not null check (valor_minimo > 0),
  produto_id uuid not null references public.produtos(id) on delete cascade,
  quantidade int not null default 1 check (quantidade between 1 and 5),
  dias int[] not null default '{0,1,2,3,4,5,6}',
  ativa boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid);
alter table public.promo_compre_ganhe enable row level security;
revoke all on public.promo_compre_ganhe from anon;

-- dia da semana do turno (0 = domingo) e hora local
create or replace function public._promo_dia_semana()
returns int language sql stable set search_path to 'public' as $fn$
  select extract(dow from (now() at time zone 'America/Sao_Paulo') - interval '6 hours')::int
$fn$;

-- promoções de preço valendo agora
create or replace function public._promo_dia_ativas()
returns setof public.promo_dia language sql stable security definer set search_path to 'public' as $fn$
  select pd.* from promo_dia pd
   where pd.ativa and _promo_dia_semana() = any(pd.dias)
     and (pd.hora_inicio is null or pd.hora_fim is null
          or case when pd.hora_inicio <= pd.hora_fim
                  then (now() at time zone 'America/Sao_Paulo')::time between pd.hora_inicio and pd.hora_fim
                  else (now() at time zone 'America/Sao_Paulo')::time >= pd.hora_inicio or (now() at time zone 'America/Sao_Paulo')::time <= pd.hora_fim end)
     and (pd.produto_id is null or exists (select 1 from produtos p where p.id = pd.produto_id and p.ativo))
     and (pd.combo_id is null or exists (select 1 from combos c where c.id = pd.combo_id and c.ativo))
$fn$;

-- menor preço promocional para o item agora (null = sem promoção)
create or replace function public._promo_dia_preco(p_prod uuid, p_comb uuid, p_preco numeric, out preco numeric, out nome text, out acumula boolean)
language sql stable security definer set search_path to 'public' as $fn$
  select x.pr, x.nome, x.acumula_cupom from (
    select round(case when a.tipo = 'preco' then a.valor else p_preco * (1 - a.valor / 100) end, 2) pr, a.nome, a.acumula_cupom
      from _promo_dia_ativas() a
     where (p_prod is not null and a.produto_id = p_prod) or (p_comb is not null and a.combo_id = p_comb)) x
   where x.pr > 0 and x.pr < p_preco
   order by x.pr limit 1
$fn$;

-- regra de "compre e ganhe" que vale para este valor de produtos (a maior faixa alcançada), com o custo do brinde
create or replace function public._compre_ganhe_regra(p_subtotal numeric)
returns table (id uuid, nome text, produto_id uuid, produto_nome text, quantidade int, custo numeric, valor_minimo numeric)
language sql stable security definer set search_path to 'public' as $fn$
  select r.id, r.nome, r.produto_id, p.nome, r.quantidade,
         coalesce((select min(pp.custo) from produto_precos pp where pp.produto_id = r.produto_id), 0), r.valor_minimo
    from promo_compre_ganhe r join produtos p on p.id = r.produto_id and p.ativo
   where r.ativa and _promo_dia_semana() = any(r.dias) and r.valor_minimo <= p_subtotal
     and not exists (select 1 from v_cardapio_esgotados e where e.tipo = 'produto' and e.id = r.produto_id)
   order by r.valor_minimo desc limit 1
$fn$;
revoke all on function public._promo_dia_ativas() from public, anon, authenticated;
revoke all on function public._promo_dia_preco(uuid, uuid, numeric) from public, anon, authenticated;
revoke all on function public._compre_ganhe_regra(numeric) from public, anon, authenticated;

-- o cardápio pergunta o que vale agora (público; sem dados de cliente)
create or replace function public.api_cardapio_promos(p jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object('ok', true, 'dia', _promo_dia_semana(),
    'precos', coalesce((select jsonb_agg(jsonb_build_object('tipo', case when a.produto_id is not null then 'produto' else 'combo' end,
                 'id', coalesce(a.produto_id, a.combo_id), 'nome', a.nome, 'modo', a.tipo, 'valor', a.valor, 'acumula', a.acumula_cupom,
                 'ate', case when a.hora_fim is not null and a.hora_inicio is not null then to_char(a.hora_fim, 'HH24:MI') end)) from _promo_dia_ativas() a), '[]'::jsonb),
    'compreGanhe', coalesce((select jsonb_agg(jsonb_build_object('nome', r.nome, 'minimo', r.valor_minimo, 'produtoId', r.produto_id, 'produto', p.nome, 'quantidade', r.quantidade) order by r.valor_minimo)
                 from promo_compre_ganhe r join produtos p on p.id = r.produto_id and p.ativo
                where r.ativa and _promo_dia_semana() = any(r.dias)
                  and not exists (select 1 from v_cardapio_esgotados e where e.tipo = 'produto' and e.id = r.produto_id)), '[]'::jsonb))
$fn$;
revoke all on function public.api_cardapio_promos(jsonb) from public;
grant execute on function public.api_cardapio_promos(jsonb) to anon, authenticated;

-- pedido do cardápio: aplica o preço do dia e o brinde do "compre e ganhe" (no servidor; o celular só mostra)
do $do$
declare d text := pg_get_functiondef('public._criar_pedido_publico(jsonb,uuid,boolean)'::regprocedure); a text; b text;
begin
  if position('_promo_dia_preco' in d) > 0 then return; end if;
  a := '  v_res uuid; v_min int; v_cfg integracoes_config%rowtype; v_ja_res record;';
  if position(a in d) = 0 then raise exception '112: âncora declare'; end if;
  d := replace(d, a, a || E'\n  v_pp record; v_pblq boolean := false; v_cg record;');
  a := '    v_esc := null; v_ev := null;';
  if position(a in d) = 0 then raise exception '112: âncora preço'; end if;
  d := replace(d, a, $b$    -- v1.26: preço por dia da semana (só cardápio online; sem mesa)
    v_pblq := false;
    if not v_eh_mesa then
      select * into v_pp from _promo_dia_preco(v_prod_id, v_comb_id, v_preco);
      if v_pp.preco is not null and v_pp.preco < v_preco then
        v_preco := v_pp.preco; v_nome_item := v_nome_item || ' [' || v_pp.nome || ']'; v_pblq := not coalesce(v_pp.acumula, false);
      end if;
    end if;
$b$ || a);
  a := E'end, false);\n    select count(*), coalesce(sum(a.preco), 0),';
  if position(a in d) = 0 then raise exception '112: âncora sem desconto'; end if;
  d := replace(d, a, E'end, false) or v_pblq;\n    select count(*), coalesce(sum(a.preco), 0),');
  a := '  v_orig := round(v_orig, 2); v_custo := round(v_custo, 2);';
  if position(a in d) = 0 then raise exception '112: âncora compre e ganhe'; end if;
  d := replace(d, a, $b$  -- v1.26: compre e ganhe (pedido do cardápio que passa do valor mínimo dos produtos ganha o brinde configurado pelo dono)
  if not v_eh_mesa and v_orig > 0 then
    select * into v_cg from _compre_ganhe_regra(round(v_orig, 2));
    if v_cg.id is not null then
      v_itens_ok := v_itens_ok || jsonb_build_array(jsonb_build_object('produtoId', v_cg.produto_id, 'comboId', null,
        'descricao', '🎁 Brinde compre e ganhe — ' || v_cg.produto_nome, 'quantidade', v_cg.quantidade, 'valorUnitario', 0,
        'custoUnitario', v_cg.custo, 'adicionaisIds', '[]'::jsonb));
      v_custo := v_custo + v_cg.custo * v_cg.quantidade;
    end if;
  end if;
$b$ || a);
  execute d;
end $do$;

-- ADMIN: listar, salvar e excluir (excluir pede a senha)
create or replace function public.api_promos_listar(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'hoje', _promo_dia_semana(),
    'precos', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'produtoId', a.produto_id, 'comboId', a.combo_id,
        'item', coalesce(pr.nome, co.nome), 'dias', to_jsonb(a.dias), 'horaInicio', to_char(a.hora_inicio, 'HH24:MI'), 'horaFim', to_char(a.hora_fim, 'HH24:MI'),
        'tipo', a.tipo, 'valor', a.valor, 'acumula', a.acumula_cupom, 'ativa', a.ativa,
        'precoNormal', coalesce((select min(pp.preco) from produto_precos pp where pp.produto_id = a.produto_id), (select min(cp.preco) from combo_precos cp where cp.combo_id = a.combo_id)),
        'agora', exists (select 1 from _promo_dia_ativas() x where x.id = a.id)) order by a.ativa desc, a.nome)
      from promo_dia a left join produtos pr on pr.id = a.produto_id left join combos co on co.id = a.combo_id), '[]'::jsonb),
    'compreGanhe', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.nome, 'minimo', r.valor_minimo, 'produtoId', r.produto_id, 'produto', p.nome,
        'quantidade', r.quantidade, 'dias', to_jsonb(r.dias), 'ativa', r.ativa, 'produtoAtivo', p.ativo,
        'usos30', (select count(*) from itens_venda iv join vendas v on v.id = iv.venda_id where iv.descricao like '🎁 Brinde compre e ganhe — %' and iv.produto_id = r.produto_id and v.status = 'Confirmada' and v.data_hora > now() - interval '30 days')) order by r.ativa desc, r.valor_minimo)
      from promo_compre_ganhe r join produtos p on p.id = r.produto_id), '[]'::jsonb));
end $fn$;

create or replace function public.api_promo_dia_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', '')); v_prod uuid := _uuid(p->>'produtoId'); v_comb uuid := _uuid(p->>'comboId');
  v_dias int[]; v_hi time; v_hf time; v_tipo text := coalesce(p->>'tipo', ''); v_val numeric := _num(p->>'valor'); v_normal numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 40 then return _falha('Dê um nome de 3 a 40 letras (ex.: Terça do X Bacon). Ele aparece para o cliente.'); end if;
  if (v_prod is null) = (v_comb is null) then return _falha('Escolha um produto ou um combo.'); end if;
  if v_prod is not null and not exists (select 1 from produtos where id = v_prod) then return _falha('Produto não encontrado.'); end if;
  if v_comb is not null and not exists (select 1 from combos where id = v_comb) then return _falha('Combo não encontrado.'); end if;
  select coalesce(array_agg(distinct x::int order by x::int), '{}') into v_dias from jsonb_array_elements_text(case when jsonb_typeof(p->'dias') = 'array' then p->'dias' else '[]'::jsonb end) x where x ~ '^[0-6]$';
  if cardinality(v_dias) = 0 then return _falha('Escolha pelo menos um dia da semana.'); end if;
  if coalesce(p->>'horaInicio', '') ~ '^[0-2][0-9]:[0-5][0-9]$' and coalesce(p->>'horaFim', '') ~ '^[0-2][0-9]:[0-5][0-9]$' then
    v_hi := (p->>'horaInicio')::time; v_hf := (p->>'horaFim')::time;
  elsif coalesce(p->>'horaInicio', '') <> '' or coalesce(p->>'horaFim', '') <> '' then
    return _falha('Preencha as duas horas (início e fim) ou deixe as duas em branco para valer o dia todo.');
  end if;
  if v_tipo not in ('preco', 'percentual') then return _falha('Escolha "preço fixo" ou "% de desconto".'); end if;
  if v_tipo = 'percentual' and (v_val < 1 or v_val > 90) then return _falha('O desconto precisa ficar entre 1% e 90%.'); end if;
  v_normal := coalesce((select min(preco) from produto_precos where produto_id = v_prod), (select min(preco) from combo_precos where combo_id = v_comb));
  if v_tipo = 'preco' and (v_val is null or v_val <= 0) then return _falha('Informe o preço promocional.'); end if;
  if v_tipo = 'preco' and v_normal is not null and v_val >= v_normal then return _falha('O preço promocional (R$ ' || _dinheiro(v_val) || ') precisa ser menor que o preço normal (R$ ' || _dinheiro(v_normal) || ').'); end if;
  if v_id is null then
    insert into promo_dia (nome, produto_id, combo_id, dias, hora_inicio, hora_fim, tipo, valor, acumula_cupom, ativa, criado_por)
    values (v_nome, v_prod, v_comb, v_dias, v_hi, v_hf, v_tipo, v_val, coalesce((p->>'acumula')::boolean, false), coalesce((p->>'ativa')::boolean, true), auth.uid()) returning id into v_id;
  else
    update promo_dia set nome = v_nome, produto_id = v_prod, combo_id = v_comb, dias = v_dias, hora_inicio = v_hi, hora_fim = v_hf, tipo = v_tipo, valor = v_val,
           acumula_cupom = coalesce((p->>'acumula')::boolean, false), ativa = coalesce((p->>'ativa')::boolean, true) where id = v_id;
    if not found then return _falha('Promoção não encontrada.'); end if;
  end if;
  perform _auditar('Preço por dia da semana salvo', v_nome || ' · ' || v_tipo || ' ' || v_val || ' · dias ' || array_to_string(v_dias, ','));
  return jsonb_build_object('ok', true, 'id', v_id, 'message', 'Promoção salva.');
end $fn$;

create or replace function public.api_compre_ganhe_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_id uuid := _uuid(p->>'id'); v_min numeric := _num(p->>'minimo'); v_prod uuid := _uuid(p->>'produtoId'); v_q int := coalesce(nullif(p->>'quantidade', '')::int, 1); v_dias int[];
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_min is null or v_min <= 0 then return _falha('Informe o valor mínimo dos produtos.'); end if;
  if v_prod is null or not exists (select 1 from produtos where id = v_prod) then return _falha('Escolha o produto que vai de brinde.'); end if;
  if v_q < 1 or v_q > 5 then return _falha('A quantidade do brinde vai de 1 a 5.'); end if;
  select coalesce(array_agg(distinct x::int order by x::int), '{}') into v_dias from jsonb_array_elements_text(case when jsonb_typeof(p->'dias') = 'array' then p->'dias' else '[]'::jsonb end) x where x ~ '^[0-6]$';
  if cardinality(v_dias) = 0 then return _falha('Escolha pelo menos um dia da semana.'); end if;
  if v_id is null then
    insert into promo_compre_ganhe (nome, valor_minimo, produto_id, quantidade, dias, ativa, criado_por)
    values (left(btrim(coalesce(p->>'nome', '')), 40), v_min, v_prod, v_q, v_dias, coalesce((p->>'ativa')::boolean, true), auth.uid()) returning id into v_id;
  else
    update promo_compre_ganhe set nome = left(btrim(coalesce(p->>'nome', '')), 40), valor_minimo = v_min, produto_id = v_prod, quantidade = v_q, dias = v_dias,
           ativa = coalesce((p->>'ativa')::boolean, true) where id = v_id;
    if not found then return _falha('Regra não encontrada.'); end if;
  end if;
  perform _auditar('Compre e ganhe salvo', 'a partir de R$ ' || _dinheiro(v_min) || ' · brinde ' || (select nome from produtos where id = v_prod) || ' ×' || v_q);
  return jsonb_build_object('ok', true, 'id', v_id, 'message', 'Regra salva.');
end $fn$;

create or replace function public.api_promo_excluir(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_err text; v_nome text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  if p->>'tipo' = 'dia' then
    delete from promo_dia where id = _uuid(p->>'id') returning nome into v_nome;
  elsif p->>'tipo' = 'ganhe' then
    delete from promo_compre_ganhe where id = _uuid(p->>'id') returning 'a partir de R$ ' || _dinheiro(valor_minimo) into v_nome;
  else return _falha('Tipo inválido.'); end if;
  if v_nome is null then return _falha('Não encontrada (talvez já tenha sido excluída).'); end if;
  perform _auditar('Promoção excluída', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Excluída.');
end $fn$;
revoke all on function public.api_promos_listar(jsonb) from public, anon;
revoke all on function public.api_promo_dia_salvar(jsonb) from public, anon;
revoke all on function public.api_compre_ganhe_salvar(jsonb) from public, anon;
revoke all on function public.api_promo_excluir(jsonb) from public, anon;
grant execute on function public.api_promos_listar(jsonb), public.api_promo_dia_salvar(jsonb), public.api_compre_ganhe_salvar(jsonb), public.api_promo_excluir(jsonb) to authenticated;

-- 113) BILHETE NA SACOLA (v1.26): texto, cupom e QR do cardápio impressos junto da comanda (pedidos do iFood ou todas as entregas). Configurável pelo dono.
create or replace function public.api_bilhete_sacola(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare c jsonb := coalesce((select valor from sistema where chave = 'BilheteSacola' and jsonb_typeof(valor) = 'object'), '{}'::jsonb); v_cup text := upper(btrim(coalesce(c->>'cupom', '')));
begin
  if auth_nivel() is null then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'ligado', coalesce((c->>'ligado')::boolean, false),
    'titulo', coalesce(c->>'titulo', 'Peça direto com a gente!'),
    'texto', coalesce(c->>'texto', 'Aponte a câmera para o QR Code e peça pelo nosso cardápio. Mesmo lanche, sem taxa do aplicativo.'),
    'cupom', v_cup,
    'quando', case when c->>'quando' = 'entregas' then 'entregas' else 'ifood' end,
    'cupomOk', v_cup = '' or exists (select 1 from cupons k where k.codigo = v_cup and k.ativa and k.excluido_em is null and (k.data_fim is null or k.data_fim >= (now() at time zone 'America/Sao_Paulo')::date)),
    'cupomDesc', (select k.nome || ' · ' || case when k.tipo = 'percentual' then trim(to_char(k.valor, 'FM990.##')) || '% de desconto' when k.tipo = 'fixo' then 'R$ ' || _dinheiro(k.valor) || ' de desconto' else k.tipo end
                    || case when k.valor_minimo > 0 then ' (pedido mínimo R$ ' || _dinheiro(k.valor_minimo) || ')' else '' end
                    from cupons k where k.codigo = v_cup and k.excluido_em is null limit 1));
end $fn$;

create or replace function public.api_bilhete_sacola_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_t text := btrim(coalesce(p->>'titulo', '')); v_x text := btrim(coalesce(p->>'texto', '')); v_c text := upper(regexp_replace(btrim(coalesce(p->>'cupom', '')), '\s+', '', 'g'));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if char_length(v_t) > 50 then return _falha('O título pode ter até 50 letras.'); end if;
  if char_length(v_x) > 220 then return _falha('O texto pode ter até 220 letras.'); end if;
  if v_c <> '' and not exists (select 1 from cupons where codigo = v_c and excluido_em is null) then return _falha('O cupom ' || v_c || ' não existe. Crie em "Cupons" e depois escreva o código aqui (ou deixe em branco).'); end if;
  insert into sistema (chave, valor, atualizado_em) values ('BilheteSacola', jsonb_build_object('ligado', coalesce((p->>'ligado')::boolean, false), 'titulo', v_t, 'texto', v_x, 'cupom', v_c,
         'quando', case when p->>'quando' = 'entregas' then 'entregas' else 'ifood' end), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('Bilhete na sacola', case when coalesce((p->>'ligado')::boolean, false) then 'ligado' else 'desligado' end || coalesce(' · cupom ' || nullif(v_c, ''), ''));
  return jsonb_build_object('ok', true, 'message', 'Bilhete salvo.');
end $fn$;
revoke all on function public.api_bilhete_sacola(jsonb) from public, anon;
revoke all on function public.api_bilhete_sacola_salvar(jsonb) from public, anon;
grant execute on function public.api_bilhete_sacola(jsonb), public.api_bilhete_sacola_salvar(jsonb) to authenticated;
