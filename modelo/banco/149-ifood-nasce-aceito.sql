-- 149 · iFood: com "Confirmar pedidos do iFood automaticamente" LIGADO, o pedido já nasce ACEITO (em preparo).
-- Sem botão "Aceitar" para clicar: o sistema confirma com o iFood sozinho e já manda o pedido para a cozinha.
-- Se o iFood RECUSAR a confirmação, o pedido volta a "aguardando aceite" e um aviso grande chega no celular: aí a equipe aceita à mão.
-- Com a opção DESLIGADA nada muda (botão "Aceitar" e vinheta repetida, como antes).
-- Pedido AGENDADO cujo preparo só começa mais tarde continua "aguardando": o preparo é decisão da equipe na hora certa.
-- Pode rodar de novo sem problema.

create or replace function public.ifood_criar_pedido(p_order jsonb, p_simulado boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_id text := p_order->>'id'; v_disp text := coalesce(nullif(p_order->>'displayId', ''), right(coalesce(p_order->>'id', ''), 4));
  v_venda uuid := gen_random_uuid(); v_tipo venda_tipo; v_nome text; v_tel text; v_end text; v_comp text; v_ref text; v_obs text;
  v_val jsonb; v_total numeric; v_sem int; v_caixa uuid; v_numero int; v_troco numeric; v_agend text; v_forma text; v_pend numeric; v_cash numeric; v_stpag status_pagamento; ad jsonb; v_cpf text; v_okdata timestamptz;
  v_prep timestamptz; v_expira timestamptz := now() + interval '8 minutes'; v_auto boolean;
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
  -- nasce aceito: com a confirmação automática ligada o pedido já entra em preparo (o gatilho enfileira "confirmar" e "iniciar preparo" no iFood, nessa ordem)
  begin v_auto := coalesce((select (config->>'confirmacaoAutomatica')::boolean from integracoes_config where provedor = 'ifood'), true); exception when others then v_auto := true; end;
  if v_auto and not (v_prep is not null and v_prep > now()) then
    update vendas set status_pedido = 'Em preparo', inicio_preparo_em = coalesce(inicio_preparo_em, now()) where id = v_venda;
    perform _auditar('Pedido aceito automaticamente', 'iFood #' || v_disp || ' → venda #' || v_numero || ' · em preparo', null);
  end if;
  return jsonb_build_object('ok', true, 'vendaId', v_venda, 'numero', v_numero, 'semLigacao', v_sem);
end $function$;

create or replace function public.ifood_acao_resultado(p_id bigint, p_estado text, p_erro text default null::text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare a ifood_acoes%rowtype; v_venda uuid; v_num text;
begin
  update ifood_acoes set estado = p_estado, tentativas = tentativas + 1, erro = left(p_erro, 300), executado_em = now() where id = p_id returning * into a;
  if a.id is null then return; end if;
  if p_estado = 'ok' then
    if a.acao = 'confirmar' then update ifood_pedidos set estado = 'confirmado', confirmado_em = coalesce(confirmado_em, now()), atualizado_em = now() where pedido_ifood = a.pedido_ifood and estado = 'novo'; end if;
    perform public._integ_log('ifood', 'info', 'Ação enviada ao iFood: ' || a.acao || ' (pedido ' || a.pedido_ifood || ')');
  elsif p_estado in ('erro', 'duvida') then
    perform public._integ_log('ifood', 'erro', 'Ação NÃO confirmada no iFood: ' || a.acao || ' — ' || coalesce(p_erro, ''));
    -- o iFood RECUSOU a confirmação: o pedido não pode parecer aceito. Volta a "aguardando aceite" e avisa a equipe (o prazo de ~8 min continua valendo)
    if p_estado = 'erro' and a.acao = 'confirmar' then
      select i.venda_id, i.numero_ifood into v_venda, v_num from ifood_pedidos i where i.pedido_ifood = a.pedido_ifood and i.estado = 'novo' and not i.simulado;
      if v_venda is not null then
        update vendas set status_pedido = 'Recebido', inicio_preparo_em = null where id = v_venda and status_pedido::text = 'Em preparo';
        update ifood_acoes set estado = 'pulada', erro = 'a confirmação falhou' where pedido_ifood = a.pedido_ifood and acao = 'iniciar_preparo' and estado = 'pendente';
        perform public.ifood_aviso_registrar(a.pedido_ifood, 'confirmacao_falhou', '❌ O iFood não aceitou a confirmação do pedido', 'Aceite o pedido à mão em Pedidos agora. Se passar de ~8 min o iFood cancela sozinho.', '{}'::jsonb);
      end if;
    end if;
  end if;
end $function$;
