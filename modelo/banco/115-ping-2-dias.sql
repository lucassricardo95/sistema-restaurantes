-- Mantém o projeto Supabase gratuito ativo: ping a cada 2 dias (pg_cron + pg_net).
-- Requer os segredos do vault: supabase_url e publishable_key (criados pelo instalador).
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

create table if not exists public.pings (
  id bigserial primary key,
  em timestamptz not null default now(),
  request_id bigint
);
alter table public.pings enable row level security;

create or replace function public.ping_projeto() returns void
language plpgsql security definer set search_path = public, extensions, vault as $$
declare v_url text; v_key text; v_id bigint;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'supabase_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'publishable_key';
  if v_url is null or v_key is null then return; end if;
  select net.http_get(url := v_url || '/auth/v1/health', headers := jsonb_build_object('apikey', v_key)) into v_id;
  insert into public.pings(request_id) values (v_id);
  delete from public.pings where em < now() - interval '60 days';
end $$;
revoke all on function public.ping_projeto() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('ping-2-dias') where exists (select 1 from cron.job where jobname = 'ping-2-dias');
  perform cron.schedule('ping-2-dias', '0 9 */2 * *', 'select public.ping_projeto()');
end $$;
