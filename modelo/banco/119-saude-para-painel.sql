-- 119) SAÚDE E USO DO SUPABASE NO PAINEL DE REVENDA
-- A cada 15 minutos o restaurante envia ao Painel o mesmo que a tela "Conexão e servidores" mostra
-- (verificações, plano grátis e a planilha principal). Só informação de estado: nada de dados de clientes ou vendas.
-- ANTES de rodar, guarde o código do restaurante no cofre (uma vez só; troque pelo código do restaurante no painel):
--   select vault.create_secret('codigo-do-restaurante', 'restaurante_slug');
-- Pode rodar de novo sem erro.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

-- cópia da "Saúde do sistema" que não exige login (quem chama é o agendador do banco, nunca a API)
do $$
declare d text;
begin
  select pg_get_functiondef('public.api_saude_sistema(jsonb)'::regprocedure) into d;
  d := replace(d, 'public.api_saude_sistema(', 'public._saude_montar(');
  d := regexp_replace(d, 'if not tem_nivel\(''Admin''\) then return _negado\(\); end if;', '', 'g');
  execute d;
  execute 'revoke all on function public._saude_montar(jsonb) from public, anon, authenticated';
end $$;

create table if not exists public.saude_sonda (
  id boolean primary key default true check (id),
  req_id bigint,
  enviado_em timestamptz
);
alter table public.saude_sonda enable row level security;

-- passo 1: pergunta à planilha principal se está de pé (a resposta é lida no passo 2)
create or replace function public.saude_sondar() returns void
language plpgsql security definer set search_path = public, extensions, vault as $$
declare v_u text; v_id bigint;
begin
  select decrypted_secret into v_u from vault.decrypted_secrets where name = 'sheets_main_url';
  if coalesce(v_u, '') = '' then
    insert into saude_sonda (id, req_id, enviado_em) values (true, null, null) on conflict (id) do update set req_id = null, enviado_em = null;
    return;
  end if;
  select net.http_get(url := v_u || case when v_u like '%?%' then '&' else '?' end || 'ping=1', timeout_milliseconds := 12000) into v_id;
  insert into saude_sonda (id, req_id, enviado_em) values (true, v_id, now()) on conflict (id) do update set req_id = excluded.req_id, enviado_em = excluded.enviado_em;
end $$;
revoke all on function public.saude_sondar() from public, anon, authenticated;

-- passo 2: monta o resumo e envia ao Painel
create or replace function public.saude_enviar_painel() returns void
language plpgsql security definer set search_path = public, extensions, vault, net as $$
declare v_slug text; v_s jsonb; v_pl jsonb; r record; x record;
begin
  select decrypted_secret into v_slug from vault.decrypted_secrets where name = 'restaurante_slug';
  if coalesce(v_slug, '') = '' then return; end if;
  v_s := public._saude_montar('{}'::jsonb);
  select * into r from saude_sonda where id;
  if r.req_id is null then v_pl := jsonb_build_object('estado', 'nao_usa');
  else
    select status_code, timed_out, error_msg, created into x from net._http_response where id = r.req_id;
    if not found then v_pl := jsonb_build_object('estado', 'sem_resposta');
    elsif coalesce(x.timed_out, false) or x.status_code is null or x.status_code >= 400 then v_pl := jsonb_build_object('estado', 'fora', 'detalhe', left(coalesce(x.error_msg, 'erro ' || coalesce(x.status_code::text, '')), 120));
    else v_pl := jsonb_build_object('estado', 'ok', 'ms', round(extract(epoch from (x.created - r.enviado_em)) * 1000));
    end if;
  end if;
  perform net.http_post(
    url := 'https://shbhclxhlffdusikjeqp.supabase.co/rest/v1/rpc/registrar_saude',
    headers := jsonb_build_object('apikey', 'sb_publishable_0u_j3zKFnJDkhN57KRJ9Ng_7uN24jl4', 'Content-Type', 'application/json'),
    body := jsonb_build_object('p', jsonb_build_object('slug', v_slug, 'geral', v_s->>'geral', 'itens', v_s->'itens',
              'servidores', jsonb_build_object('supabase', jsonb_build_object('estado', 'ok'), 'planilha', v_pl))),
    timeout_milliseconds := 10000);
end $$;
revoke all on function public.saude_enviar_painel() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('saude-sondar') where exists (select 1 from cron.job where jobname = 'saude-sondar');
  perform cron.unschedule('saude-painel') where exists (select 1 from cron.job where jobname = 'saude-painel');
  perform cron.schedule('saude-sondar', '*/15 * * * *', 'select public.saude_sondar()');
  perform cron.schedule('saude-painel', '1-59/15 * * * *', 'select public.saude_enviar_painel()');
end $$;
