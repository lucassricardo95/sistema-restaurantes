-- 155 · Nota fiscal (dados da empresa, perfis fiscais e planilha do contador) configurada PELO PAINEL DE REVENDA.
-- Função interna: o site não consegue chamar (só o conector do painel, com o token do Supabase do restaurante).
-- Reaproveita as MESMAS funções e regras das telas do restaurante (api_fiscal_*), agindo como o Administrador do restaurante só durante a chamada.
-- Ações (fn): empresa_ler · empresa_salvar · perfis · perfil_salvar · perfil_excluir · atribuir · sem_perfil · exportar · importar.
-- Pode rodar de novo sem erro. Nada é apagado.
create or replace function public._painel_fiscal(p jsonb) returns jsonb
 language plpgsql security definer set search_path to 'public' as $fn$
declare v_fn text := coalesce(p->>'fn', ''); v_uid uuid; v_res jsonb;
begin
  if v_fn not in ('empresa_ler', 'empresa_salvar', 'perfis', 'perfil_salvar', 'perfil_excluir', 'atribuir', 'sem_perfil', 'exportar', 'importar') then
    return jsonb_build_object('ok', false, 'message', 'Ação fiscal desconhecida.');
  end if;
  select id into v_uid from usuarios where ativo and nivel::text in ('Desenvolvedor', 'Admin') order by (nivel::text = 'Desenvolvedor') desc, criado_em limit 1;
  if v_uid is null then return jsonb_build_object('ok', false, 'message', 'Este restaurante ainda não tem um Administrador cadastrado.'); end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  execute format('select public.%I($1)', 'api_fiscal_' || v_fn) into v_res using coalesce(p->'dados', '{}'::jsonb);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(v_res, jsonb_build_object('ok', false, 'message', 'Sem resposta.'));
end $fn$;
revoke all on function public._painel_fiscal(jsonb) from public, anon, authenticated;
grant execute on function public._painel_fiscal(jsonb) to service_role;
