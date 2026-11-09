-- 154 · Integrações (iFood, nota fiscal, Mercado Pago, InfinityPay) configuradas PELO PAINEL DE REVENDA.
-- Quem configura e liga as integrações é o Desenvolvedor, no painel. O restaurante só usa no dia a dia (a tela dele esconde a parte técnica na atualização seguinte).
-- Nada aqui muda o que já funciona: são funções INTERNAS novas, que o site não consegue chamar (só o conector do painel, com o token do Supabase do restaurante).
-- As regras (o que pode ser salvo, valores aceitos, pendências antes de ligar) são as mesmas das telas do restaurante. Tudo fica na Auditoria do restaurante ("pelo painel").
-- Ações de _painel_integ: ler · modulo · segredo · ligar · desligar · config · marcar · ip_segredo.
-- Pode rodar de novo sem erro. Nada é apagado.

-- estado completo das 4 integrações (o mesmo que a tela do restaurante lê, sem exigir login de Admin)
create or replace function public._integ_status_dados() returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $fn$
declare v jsonb := '[]'::jsonb; r record; v_def jsonb; v_pend text[];
begin
  for r in select * from integracoes_config order by provedor loop
    v_def := _integ_checklist_def(r.provedor); v_pend := _integ_pendencias(r.provedor, r.modo);
    v := v || (jsonb_build_object('provedor', r.provedor, 'ligado', r.ligado, 'modo', r.modo, 'ligadoEm', r.ligado_em, 'config', r.config,
      'checklist', (select coalesce(jsonb_agg(jsonb_build_object('id', x->>'id', 'titulo', x->>'titulo', 'auto', coalesce((x->>'auto')::boolean, false),
          'feito', not ((x->>'titulo') = any (v_pend)))), '[]'::jsonb) from jsonb_array_elements(v_def) x),
      'pendencias', to_jsonb(v_pend), 'podeLigar', coalesce(array_length(v_pend, 1), 0) = 0,
      'segredos', (select coalesce(jsonb_object_agg(s.chave, jsonb_build_object('tem', true, 'final', case when length(s.valor) > 8 then right(s.valor, 4) else '' end, 'em', s.atualizado_em)), '{}'::jsonb)
                    from integracoes_segredos s where (r.provedor = 'ifood' and s.chave like 'ifood\_%') or (r.provedor = 'nfce' and s.chave like 'nfce\_%') or (r.provedor = 'mercadopago' and s.chave like 'mp\_%') or (r.provedor = 'infinitepay' and s.chave like 'ip\_%')))
      || case when r.provedor in ('mercadopago', 'infinitepay') then (
           select jsonb_build_object('pendenciasTeste', to_jsonb(a.t), 'pendenciasProducao', to_jsonb(a.p),
             'podeLigarTeste', coalesce(array_length(a.t, 1), 0) = 0, 'podeLigarProducao', coalesce(array_length(a.p, 1), 0) = 0)
             from (select _integ_pendencias(r.provedor, 'homologacao') as t, _integ_pendencias(r.provedor, 'producao') as p) a)
         else '{}'::jsonb end);
  end loop;
  return v;
end $fn$;
revoke all on function public._integ_status_dados() from public, anon, authenticated;
grant execute on function public._integ_status_dados() to service_role;

create or replace function public._painel_integ(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_acao text := coalesce(p->>'acao', 'ler'); v_prov text := p->>'provedor';
  v_mod text := lower(coalesce(p->>'modulo', '')); v_lib boolean := coalesce((p->>'liberado')::boolean, false);
  v_chave text := p->>'chave'; v_valor text := btrim(coalesce(p->>'valor', ''));
  v_modo text := coalesce(p->>'modo', 'producao'); v_pend text[];
  v_cfg jsonb := coalesce(p->'config', '{}'::jsonb); v_atual jsonb; v_novo jsonb := '{}'::jsonb; v_c text;
  v_re text := '^[^@\s]+@[^@\s]+\.[^@\s]+$'; v_msg text := null;
begin
  if v_acao not in ('ler', 'modulo', 'segredo', 'ip_segredo') and v_prov not in ('ifood', 'nfce', 'mercadopago', 'infinitepay') then return jsonb_build_object('ok', false, 'erro', 'Integração inválida.'); end if;

  if v_acao = 'modulo' then
    if v_mod not in ('events', 'order', 'merchant', 'catalog', 'review', 'financial', 'shipping', 'logistics', 'analytics') then return jsonb_build_object('ok', false, 'erro', 'Módulo desconhecido.'); end if;
    insert into ifood_modulos (modulo, liberado, liberado_em) values (v_mod, v_lib, case when v_lib then now() end)
      on conflict (modulo) do update set liberado = excluded.liberado, liberado_em = case when excluded.liberado then now() else ifood_modulos.liberado_em end,
        avisado_em = case when excluded.liberado then null else ifood_modulos.avisado_em end;
    begin perform _auditar('iFood: módulo ' || v_mod || (case when v_lib then ' liberado' else ' desligado' end), 'pelo painel'); exception when others then null; end;

  elsif v_acao = 'segredo' then
    if v_chave not in ('ifood_client_id', 'ifood_client_secret', 'ifood_merchant_id', 'ifood_bi_client_id', 'ifood_bi_client_secret', 'nfce_token_homologacao', 'nfce_token_producao', 'nfce_csc',
                       'mp_public_key_teste', 'mp_public_key_producao', 'mp_access_token_teste', 'mp_access_token_producao', 'mp_webhook_secret', 'ip_handle', 'ip_chave_checkout') then return jsonb_build_object('ok', false, 'erro', 'Campo desconhecido.'); end if;
    if v_chave = 'ip_handle' then v_valor := lower(regexp_replace(v_valor, '^[$@]+', '')); end if;
    if length(v_valor) < (case when v_chave = 'ip_handle' then 3 else 8 end) or length(v_valor) > 400 or v_valor ~ '\s' then return jsonb_build_object('ok', false, 'erro', 'Valor inválido. Copie inteiro, sem espaços.'); end if;
    if v_chave like 'mp\_%' then
      if v_valor !~ '^[A-Za-z0-9_-]+$' then return jsonb_build_object('ok', false, 'erro', 'Valor inválido. Use só letras, números, - e _ (copie inteiro, sem espaços).'); end if;
      if v_chave = 'mp_webhook_secret' and length(v_valor) < 16 then return jsonb_build_object('ok', false, 'erro', 'A chave secreta do aviso (webhook) é maior que isso. Copie inteira.'); end if;
      if v_chave like 'mp\_access\_token%' and length(v_valor) < 30 then return jsonb_build_object('ok', false, 'erro', 'O Access Token é maior que isso. Copie inteiro.'); end if;
    end if;
    insert into integracoes_segredos (chave, valor, atualizado_em) values (v_chave, v_valor, now())
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    begin perform _auditar('Integração: chave salva', v_chave || ' · pelo painel'); exception when others then null; end;
    v_msg := 'Guardado.';

  elsif v_acao = 'ip_segredo' then
    insert into integracoes_segredos (chave, valor, atualizado_em) values ('ip_webhook_segredo', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), now())
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    begin perform _auditar('InfinitePay: segredo do aviso gerado', 'pelo painel'); exception when others then null; end;
    v_msg := 'Segredo do aviso gerado.';

  elsif v_acao = 'ligar' then
    if v_prov in ('nfce', 'mercadopago', 'infinitepay') and (nullif(p->>'modo', '') is null or v_modo not in ('homologacao', 'producao')) then return jsonb_build_object('ok', false, 'erro', 'Escolha o ambiente: teste (homologação) ou produção.'); end if;
    if v_prov = 'ifood' then v_modo := 'producao'; end if;
    v_pend := _integ_pendencias(v_prov, v_modo);
    if coalesce(array_length(v_pend, 1), 0) > 0 then return jsonb_build_object('ok', false, 'erro', 'Ainda faltam passos: ' || array_to_string(v_pend, '; ')); end if;
    if v_prov = 'infinitepay' and not exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online in ('pix', 'credito') and provedor_online = 'infinitepay') then
      return jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos uma forma (Pix ou cartão de crédito) para pagar pela InfinitePay antes de ligar.');
    end if;
    if v_prov = 'mercadopago' and not exists (select 1 from formas_pagamento where ativa and visivel_cardapio and aceita_online and tipo_online is not null) then
      return jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos uma forma de pagamento online (Pix ou cartão de crédito) antes de ligar.');
    end if;
    update integracoes_config set ligado = true, modo = v_modo, ligado_em = now(), ligado_por = 'painel', atualizado_em = now() where provedor = v_prov;
    begin perform _auditar('Integração LIGADA', v_prov || ' · ' || v_modo || ' · pelo painel'); exception when others then null; end;
    perform _integ_log(v_prov, 'info', 'Integração ligada (' || v_modo || ') pelo painel');
    v_msg := 'Ligado.';

  elsif v_acao = 'desligar' then
    update integracoes_config set ligado = false, atualizado_em = now() where provedor = v_prov;
    begin perform _auditar('Integração DESLIGADA', v_prov || ' · pelo painel'); exception when others then null; end;
    perform _integ_log(v_prov, 'aviso', 'Integração desligada pelo painel');
    v_msg := 'Desligado.';

  elsif v_acao = 'marcar' then
    if not exists (select 1 from jsonb_array_elements(_integ_checklist_def(v_prov)) x where x->>'id' = p->>'item' and not coalesce((x->>'auto')::boolean, false)) then return jsonb_build_object('ok', false, 'erro', 'Passo inválido.'); end if;
    update integracoes_config set checklist = jsonb_set(coalesce(checklist, '{}'::jsonb), array[p->>'item'], to_jsonb(coalesce((p->>'feito')::boolean, false)), true), atualizado_em = now() where provedor = v_prov;
    begin perform _auditar('Integração: passo marcado', v_prov || ' · ' || (p->>'item') || ' · pelo painel'); exception when others then null; end;

  elsif v_acao = 'config' then
    select config into v_atual from integracoes_config where provedor = v_prov;
    for v_c in select jsonb_object_keys(v_cfg) loop
      if v_prov = 'ifood' and v_c in ('confirmacaoAutomatica', 'abrirFecharComCaixa', 'pausarSemEstoque', 'enviarPrecos', 'conferirRepasse', 'avaliacaoAlerta', 'avaliacaoSugestao', 'acompanharEntrega', 'modoHomologacao', 'homMerchant', 'homAvaliacoes', 'homFinanceiro', 'homCatalogo', 'homEntregador', 'homAnalytics', 'biHomologacao', 'comissaoFinanceiro') then v_novo := v_novo || jsonb_build_object(v_c, coalesce((v_cfg->>v_c)::boolean, false));
      elsif v_prov = 'ifood' and v_c = 'baixaEstoque' and (v_cfg->>v_c) in ('confirmacao', 'entrega') then v_novo := v_novo || jsonb_build_object(v_c, v_cfg->>v_c);
      elsif v_prov = 'ifood' and v_c = 'retencaoClientesDias' and (v_cfg->>v_c)::int between 7 and 365 then v_novo := v_novo || jsonb_build_object(v_c, (v_cfg->>v_c)::int);
      elsif v_prov = 'ifood' and v_c = 'limitePrecoPct' and (v_cfg->>v_c)::numeric between 0 and 100 then v_novo := v_novo || jsonb_build_object(v_c, (v_cfg->>v_c)::numeric);
      elsif v_prov = 'nfce' and v_c = 'emitirQuando' and (v_cfg->>v_c) in ('pagamento', 'entrega') then v_novo := v_novo || jsonb_build_object(v_c, v_cfg->>v_c);
      elsif v_prov = 'nfce' and v_c = 'canais' and jsonb_typeof(v_cfg->v_c) = 'array' then v_novo := v_novo || jsonb_build_object(v_c, (select coalesce(jsonb_agg(c), '[]'::jsonb) from jsonb_array_elements_text(v_cfg->v_c) c where c in ('balcao', 'cardapio', 'ifood', 'mesa')));
      elsif v_prov = 'mercadopago' and v_c = 'pixValidadeMin' then
        if coalesce(v_cfg->>v_c, '') !~ '^[0-9]{1,3}$' or (v_cfg->>v_c)::int not between 5 and 120 then return jsonb_build_object('ok', false, 'erro', 'A validade do Pix deve ficar entre 5 e 120 minutos.'); end if;
        v_novo := v_novo || jsonb_build_object(v_c, (v_cfg->>v_c)::int);
      elsif v_prov = 'infinitepay' and v_c = 'linkValidadeMin' then
        if coalesce(v_cfg->>v_c, '') !~ '^[0-9]{1,3}$' or (v_cfg->>v_c)::int not between 10 and 120 then return jsonb_build_object('ok', false, 'erro', 'A validade do link deve ficar entre 10 e 120 minutos.'); end if;
        v_novo := v_novo || jsonb_build_object(v_c, (v_cfg->>v_c)::int);
      elsif v_prov = 'infinitepay' and v_c = 'producaoSoTeste' then v_novo := v_novo || jsonb_build_object(v_c, coalesce((v_cfg->>v_c)::boolean, false));
      elsif v_prov in ('mercadopago', 'infinitepay') and v_c = 'testeNoCardapio' then v_novo := v_novo || jsonb_build_object(v_c, coalesce((v_cfg->>v_c)::boolean, false));
      elsif v_prov = 'mercadopago' and v_c = 'emailPagadorTeste' then
        if btrim(coalesce(v_cfg->>v_c, '')) <> '' and (lower(btrim(v_cfg->>v_c)) !~ v_re or length(v_cfg->>v_c) > 120) then return jsonb_build_object('ok', false, 'erro', 'E-mail do comprador de teste inválido.'); end if;
        v_novo := v_novo || jsonb_build_object(v_c, lower(btrim(coalesce(v_cfg->>v_c, ''))));
      elsif v_prov in ('mercadopago', 'infinitepay') and v_c = 'emailsTeste' and jsonb_typeof(v_cfg->v_c) = 'array' then
        if exists (select 1 from jsonb_array_elements_text(v_cfg->v_c) x where btrim(x) <> '' and lower(btrim(x)) !~ v_re) then return jsonb_build_object('ok', false, 'erro', 'Um dos e-mails de teste é inválido.'); end if;
        v_novo := v_novo || jsonb_build_object(v_c, (select coalesce(jsonb_agg(q.e), '[]'::jsonb) from (select distinct lower(btrim(x)) as e from jsonb_array_elements_text(v_cfg->v_c) x where btrim(x) <> '' limit 5) q));
      end if;
    end loop;
    update integracoes_config set config = coalesce(v_atual, '{}'::jsonb) || v_novo, atualizado_em = now() where provedor = v_prov;
    begin perform _auditar('Integração: ajustes salvos', v_prov || ' · pelo painel'); exception when others then null; end;
    v_msg := 'Ajustes salvos.';

  elsif v_acao <> 'ler' then
    return jsonb_build_object('ok', false, 'erro', 'Ação desconhecida.');
  end if;

  return jsonb_build_object('ok', true, 'message', v_msg,
    'ifood', (select jsonb_build_object('ligado', ligado, 'modo', modo) from integracoes_config where provedor = 'ifood'),
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('modulo', modulo, 'liberado', liberado, 'liberadoEm', liberado_em, 'ultimoOk', ultimo_ok, 'ultimoErroEm', ultimo_erro_em, 'status', ultimo_status, 'msg', ultima_msg) order by modulo) from ifood_modulos where modulo <> 'authentication'), '[]'::jsonb),
    'integracoes', _integ_status_dados());
end $fn$;
revoke all on function public._painel_integ(jsonb) from public, anon, authenticated;
grant execute on function public._painel_integ(jsonb) to service_role;
