-- 157 · Chaves de IA, integrações e cadastro fiscal só para o Desenvolvedor (também no servidor, não só na tela).
-- Quem NÃO é Desenvolvedor recebe "negado". Se o restaurante não tiver nenhum Desenvolvedor ativo, o Admin continua podendo (assim ninguém fica trancado).
-- O painel de revenda não passa por aqui: ele grava direto pelas funções _painel_*.
create or replace function public._pode_config_tecnica() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select auth.uid() is null
      or coalesce(auth_nivel()::text, '') = 'Desenvolvedor'
      or (coalesce(auth_nivel()::text, '') = 'Admin' and not exists (select 1 from usuarios where ativo and nivel::text = 'Desenvolvedor'))
$$;
revoke all on function public._pode_config_tecnica() from public;
grant execute on function public._pode_config_tecnica() to authenticated, service_role;

do $$
declare f text; d text; n int; nome text;
begin
  foreach f in array array['api_salvar_chave_ia','api_ver_chave_ia','api_integracoes_config','api_integracoes_ligar','api_integracoes_desligar','api_integracoes_salvar_segredo','api_integracoes_ver_segredo','api_ip_gerar_segredo','api_fiscal_empresa_salvar','api_fiscal_perfil_salvar','api_fiscal_perfil_excluir','api_fiscal_importar']
  loop
    for nome, d in select p.oid::regprocedure::text, pg_get_functiondef(p.oid) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = f and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
    loop
      if d like '%_pode_config_tecnica%' then continue; end if;
      n := position(E'\nbegin' in lower(d));
      if n = 0 then raise notice 'pulei % (sem begin)', nome; continue; end if;
      d := substr(d, 1, n + 5) || E'\n if not _pode_config_tecnica() then return _negado(); end if;' || substr(d, n + 6);
      execute d;
    end loop;
  end loop;
end $$;
