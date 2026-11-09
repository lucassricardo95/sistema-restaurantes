-- 153 · iFood: cada módulo só é consultado (e só gera aviso) depois que o Desenvolvedor marca "Liberado pelo iFood".
-- Por quê: enquanto o iFood não libera um módulo para o aplicativo, ele responde 403. Isso não é defeito do restaurante e não deve avisar o dono.
-- Como funciona: ifood_modulos ganha a coluna "liberado" (nasce DESLIGADA). A função do servidor "ifood-sync" só consulta módulos liberados;
-- ifood_modulos_registrar ignora (sem aviso, sem registro de erro) o que não está liberado. A chave é mexida só pelo painel de revenda
-- (função interna _painel_integ, que o site não consegue chamar) ou direto no SQL.
-- Proteção: ao rodar pela 1ª vez, módulo que JÁ respondeu OK ao iFood (último resultado bom) fica liberado, para nada que funciona parar.
-- Rodar de novo não desliga nem liga nada que você já mexeu. Nada é apagado.
do $$
declare v_novo boolean := not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ifood_modulos' and column_name = 'liberado');
begin
  if v_novo then
    alter table public.ifood_modulos add column liberado boolean not null default false;
    alter table public.ifood_modulos add column liberado_em timestamptz;
  end if;
  insert into public.ifood_modulos (modulo) select m from unnest(array['events', 'order', 'merchant', 'catalog', 'review', 'financial', 'shipping', 'logistics', 'analytics']) m on conflict (modulo) do nothing;
  if v_novo then
    update public.ifood_modulos set liberado = true, liberado_em = now()
      where modulo <> 'authentication' and ultimo_ok is not null and (ultimo_erro_em is null or ultimo_ok >= ultimo_erro_em);
  end if;
end $$;

-- registra o resumo da rodada: módulo NÃO liberado é ignorado por inteiro (sem registro de erro e sem aviso no celular do dono)
create or replace function public.ifood_modulos_registrar(p jsonb) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare k text; v jsonb; v_ant int; v_av timestamptz; v_st int;
begin
  for k, v in select * from jsonb_each(coalesce(p, '{}'::jsonb)) loop
    k := left(lower(k), 30);
    if k <> 'authentication' and not exists (select 1 from ifood_modulos where modulo = k and liberado) then continue; end if;
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

-- a tela "Estado dos módulos" passa a saber se o módulo está liberado
create or replace function public.api_ifood_modulos(p jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('modulo', modulo, 'ultimoOk', ultimo_ok, 'ultimoErroEm', ultimo_erro_em, 'status', ultimo_status, 'msg', ultima_msg, 'liberado', liberado) order by modulo) from ifood_modulos), '[]'::jsonb),
    'loja', (select jsonb_build_object('merchantValido', merchant_valido, 'lojas', coalesce(lojas, '[]'::jsonb), 'lojasEm', lojas_em, 'situacao', situacao, 'disponivel', disponivel, 'motivo', motivo, 'verificadoEm', verificado_em) from ifood_loja where id));
end $function$;
revoke all on function public.api_ifood_modulos(jsonb) from public, anon;
grant execute on function public.api_ifood_modulos(jsonb) to authenticated, service_role;

-- só o painel de revenda chama (pelo conector do Supabase do restaurante): o site não tem permissão
-- ações: ler · modulo {modulo, liberado}
create or replace function public._painel_integ(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $fn$
declare v_acao text := coalesce(p->>'acao', 'ler'); v_mod text := lower(coalesce(p->>'modulo', '')); v_lib boolean := coalesce((p->>'liberado')::boolean, false);
begin
  if v_acao = 'modulo' then
    if v_mod not in ('events', 'order', 'merchant', 'catalog', 'review', 'financial', 'shipping', 'logistics', 'analytics') then return jsonb_build_object('ok', false, 'erro', 'Módulo desconhecido.'); end if;
    insert into ifood_modulos (modulo, liberado, liberado_em) values (v_mod, v_lib, case when v_lib then now() end)
      on conflict (modulo) do update set liberado = excluded.liberado, liberado_em = case when excluded.liberado then now() else ifood_modulos.liberado_em end,
        avisado_em = case when excluded.liberado then null else ifood_modulos.avisado_em end;
    begin perform _auditar('iFood: módulo ' || v_mod || (case when v_lib then ' liberado' else ' desligado' end), 'pelo painel'); exception when others then null; end;
  elsif v_acao <> 'ler' then
    return jsonb_build_object('ok', false, 'erro', 'Ação desconhecida.');
  end if;
  return jsonb_build_object('ok', true,
    'ifood', (select jsonb_build_object('ligado', ligado, 'modo', modo) from integracoes_config where provedor = 'ifood'),
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('modulo', modulo, 'liberado', liberado, 'liberadoEm', liberado_em, 'ultimoOk', ultimo_ok, 'ultimoErroEm', ultimo_erro_em, 'status', ultimo_status, 'msg', ultima_msg) order by modulo) from ifood_modulos where modulo <> 'authentication'), '[]'::jsonb));
end $fn$;
revoke all on function public._painel_integ(jsonb) from public, anon, authenticated;
grant execute on function public._painel_integ(jsonb) to service_role;
