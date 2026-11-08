-- 148 · Leva para o modelo as melhorias que o Texas já tinha e igualava só nele:
--   1) endereço não achado no mapa é tentado de novo depois de 1 hora (api_cardapio_hoje + api_geo_endereco_salvar)
--   2) rota de entrega devolve também os destinos dos pedidos próprios (api_rota_entrega)
--   3) duas variáveis sobrando no modelo (_ifood_extras_obs, ifood_negociacao_fim) que o Texas não tem
-- Cada ajuste só acontece se ainda não estiver feito: pode rodar de novo, e no Texas (que já tem) não muda nada.
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.api_geo_endereco_salvar'::regproc);
  if d like '%achou = excluded.achou;%' and d not like '%criado_em = now()%' then
    execute replace(d, 'achou = excluded.achou;', 'achou = excluded.achou, criado_em = now();');
  end if;

  d := pg_get_functiondef('public.api_cardapio_hoje'::regproc);
  if d not like '%interval ''1 hour''%' then
    if (length(d) - length(replace(d, 'and g.chave is null limit 6) y;', ''))) / length('and g.chave is null limit 6) y;') <> 1
       or (length(d) - length(replace(d, 'and not g.achou));', ''))) / length('and not g.achou));') <> 1 then
      raise exception 'api_cardapio_hoje: trechos não encontrados uma vez só';
    end if;
    d := replace(d, 'and g.chave is null limit 6) y;', 'and (g.chave is null or (not g.achou and g.criado_em < now() - interval ''1 hour'')) limit 6) y;');
    d := replace(d, 'and not g.achou));', 'and not g.achou and g.criado_em >= now() - interval ''1 hour''));');
    execute d;
  end if;

  d := pg_get_functiondef('public.api_rota_entrega'::regproc);
  if d not like '%v_dst%' then
    d := replace(d, 'v_pts jsonb; v_rest jsonb;', 'v_pts jsonb; v_dst jsonb; v_rest jsonb;');
    d := replace(d, E'  select jsonb_build_object(''lat'', (valor->>''lat'')',
      E'  select coalesce(jsonb_agg(jsonb_build_object(''id'', v.id, ''lat'', d.lat, ''lng'', d.lng)), ''[]''::jsonb)\n    into v_dst\n    from vendas v join entrega_destinos d on d.venda_id = v.id\n   where v.id = any(v_ids) and (v_adm or v.entregador_id = auth.uid());\n  select jsonb_build_object(''lat'', (valor->>''lat'')');
    d := replace(d, '''ifood'', v_pts, ''restaurante'', v_rest', '''ifood'', v_pts, ''destinos'', v_dst, ''restaurante'', v_rest');
    if d not like '%destinos%' then raise exception 'api_rota_entrega: não achei onde colocar'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public._ifood_extras_obs'::regproc);
  if d like '%v_doc text; v_taxas text%' and d not like '%v_nome text%' then
    execute replace(d, 'v_doc text; v_taxas text', 'v_doc text; v_nome text; v_taxas text');
  end if;
  d := pg_get_functiondef('public.ifood_negociacao_fim'::regproc);
  if d like '%; v_num text;%' and d not like '%v_n text;%' then
    execute replace(d, '; v_num text;', '; v_n text; v_num text;');
  end if;
end $m$;
