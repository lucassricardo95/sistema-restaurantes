-- Cria o primeiro Administrador de um restaurante novo. Só o instalador/dono do banco executa (não é chamável pela API).
create or replace function public.instalar_admin_inicial(p_login text, p_senha text, p_nome text default 'Administrador')
returns text language plpgsql security definer set search_path to 'public', 'auth', 'extensions' as $$
declare v_id uuid := gen_random_uuid(); v_email text := _email_login(btrim(p_login));
begin
  if exists (select 1 from usuarios where nivel::text = 'Admin') then return 'ja_existe'; end if;
  if length(coalesce(p_senha, '')) < 8 then raise exception 'senha curta'; end if;
  perform _criar_login_auth(v_id, v_email, p_senha);
  insert into usuarios (id, login, nome, nivel, ativo) values (v_id, btrim(p_login), left(p_nome, 60), 'Admin', true);
  return 'criado';
end $$;
revoke all on function public.instalar_admin_inicial(text, text, text) from public, anon, authenticated;
grant execute on function public.instalar_admin_inicial(text, text, text) to service_role;
