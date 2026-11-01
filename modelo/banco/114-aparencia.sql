-- 114) APARÊNCIA DO RESTAURANTE: nome, slogan, assistente, cores e logos ajustáveis pelo dono (Administrador → Sistema → Aparência).
-- Leitura pública (o cardápio abre já com a marca); gravação só do Admin, com a senha. Logos no bucket público "marca".
create or replace function public.api_marca_publica(p jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object('ok', true,
    'marca', coalesce((select valor from sistema where chave = 'Marca' and jsonb_typeof(valor) = 'object'), '{}'::jsonb));
$fn$;

create or replace function public.api_marca_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_err text; v_m jsonb := coalesce(p->'marca', '{}'::jsonb); v_k text; v_u text;
  v_nome text := btrim(coalesce(v_m->>'nome', '')); v_slogan text := btrim(coalesce(v_m->>'slogan', '')); v_ass text := btrim(coalesce(v_m->>'assistente', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_err := _senha_acao(p->>'senha'); if v_err <> '' then return _falha(v_err); end if;
  if coalesce((p->>'padrao')::boolean, false) then
    insert into sistema (chave, valor, atualizado_em) values ('Marca', '{}'::jsonb, now())
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    perform _auditar('Aparência', 'voltou ao padrão do restaurante');
    return jsonb_build_object('ok', true, 'message', 'Aparência original restaurada.');
  end if;
  if v_nome = '' or char_length(v_nome) > 60 then return _falha('O nome precisa ter de 1 a 60 letras.'); end if;
  if char_length(v_slogan) > 80 then return _falha('O slogan pode ter até 80 letras.'); end if;
  if char_length(v_ass) > 24 then return _falha('O nome do assistente pode ter até 24 letras.'); end if;
  foreach v_k in array array['destaque', 'botao', 'fundo'] loop
    if coalesce(v_m->'cores'->>v_k, '') !~ '^#[0-9a-fA-F]{6}$' then return _falha('Cor inválida: ' || v_k || '.'); end if;
  end loop;
  foreach v_k in array array['cardapio', 'impressao', 'icone'] loop
    v_u := coalesce(v_m->'logos'->>v_k, '');
    if v_u <> '' and (char_length(v_u) > 500 or v_u !~ '^(https://|img/)') then return _falha('Endereço de imagem inválido: ' || v_k || '.'); end if;
  end loop;
  insert into sistema (chave, valor, atualizado_em)
  values ('Marca', jsonb_build_object('nome', v_nome, 'slogan', v_slogan, 'assistente', coalesce(nullif(v_ass, ''), 'Assistente'),
          'tema', left(coalesce(v_m->>'tema', ''), 20), 'cores', v_m->'cores',
          'logos', jsonb_build_object('cardapio', coalesce(v_m->'logos'->>'cardapio', ''), 'impressao', coalesce(v_m->'logos'->>'impressao', ''), 'icone', coalesce(v_m->'logos'->>'icone', ''))), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  perform _auditar('Aparência', 'nome, cores e logos atualizados');
  return jsonb_build_object('ok', true, 'message', 'Aparência salva.');
end $fn$;

revoke all on function public.api_marca_publica(jsonb) from public;
revoke all on function public.api_marca_salvar(jsonb) from public, anon;
grant execute on function public.api_marca_publica(jsonb) to anon, authenticated;
grant execute on function public.api_marca_salvar(jsonb) to authenticated;

-- logos: bucket público, só o Admin grava
insert into storage.buckets (id, name, public) values ('marca', 'marca', true) on conflict (id) do nothing;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'marca_leitura') then
    create policy marca_leitura on storage.objects for select using (bucket_id = 'marca');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'marca_admin_grava') then
    create policy marca_admin_grava on storage.objects for insert to authenticated with check (bucket_id = 'marca' and public.tem_nivel('Admin'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'marca_admin_troca') then
    create policy marca_admin_troca on storage.objects for update to authenticated using (bucket_id = 'marca' and public.tem_nivel('Admin')) with check (bucket_id = 'marca' and public.tem_nivel('Admin'));
  end if;
end $$;
