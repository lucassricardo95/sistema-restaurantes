-- 147 · Desempenho: tira o aviso "Multiple Permissive Policies" do Supabase (duas regras de leitura na mesma tabela, o banco avalia as duas em toda consulta).
-- Não muda quem pode ler ou gravar: a regra do Administrador deixa de ser "tudo" e passa a ser inserir/alterar/apagar, e a leitura dele entra na regra de leitura da tabela.
-- Pode rodar de novo sem estragar.
do $mig$
declare p record; l record; v_to text; v_q text;
begin
  -- 1) tabelas com uma regra "tudo" do Administrador + uma regra só de leitura
  for p in select * from pg_policies where schemaname = 'public' and cmd = 'ALL' and permissive = 'PERMISSIVE'
             and tablename in ('adicionais','ai_ajuda','categorias','combo_itens','combo_precos','combos','estoque','formas_pagamento','produto_adicionais','produto_ingredientes','produto_precos','produtos','promocoes','sistema')
  loop
    v_to := array_to_string(p.roles, ',');
    select * into l from pg_policies where schemaname = 'public' and tablename = p.tablename and cmd = 'SELECT' and permissive = 'PERMISSIVE' and policyname <> p.policyname order by policyname limit 1;
    if l.policyname is null then continue; end if;
    execute format('alter policy %I on public.%I using ((%s) or (%s))', l.policyname, p.tablename, l.qual, p.qual);
    execute format('create policy %I on public.%I for insert to %s with check (%s)', p.policyname || '_ins', p.tablename, v_to, coalesce(p.with_check, p.qual));
    execute format('create policy %I on public.%I for update to %s using (%s) with check (%s)', p.policyname || '_alt', p.tablename, v_to, p.qual, coalesce(p.with_check, p.qual));
    execute format('create policy %I on public.%I for delete to %s using (%s)', p.policyname || '_del', p.tablename, v_to, p.qual);
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;

  -- 2) entregas e fechamentos: a regra "só Administrador" já está dentro da regra de Administrador/Operador
  drop policy if exists entregas_fechadas_ler_admin on public.entregas_fechadas;
  drop policy if exists fechamentos_entrega_ler_admin on public.fechamentos_entrega;

  -- 2b) entregas e fechamentos: Administrador/Operador e o próprio Entregador viram uma regra só
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'entregas_fechadas' and policyname = 'entregas_fechadas_ler_entregador') then
    alter policy entregas_fechadas_ler on public.entregas_fechadas using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso, 'Operador'::public.nivel_acesso]) or (public.tem_nivel(variadic array['Entregador'::public.nivel_acesso]) and entregador_id = (select auth.uid())));
    drop policy entregas_fechadas_ler_entregador on public.entregas_fechadas;
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'fechamentos_entrega' and policyname = 'fechamentos_entrega_ler_entregador') then
    alter policy fechamentos_entrega_ler on public.fechamentos_entrega using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso, 'Operador'::public.nivel_acesso]) or (public.tem_nivel(variadic array['Entregador'::public.nivel_acesso]) and entregador_id = (select auth.uid())));
    drop policy fechamentos_entrega_ler_entregador on public.fechamentos_entrega;
  end if;

  -- 3) perguntas frequentes: uma regra de leitura (ativas para todos, todas para o Administrador) e gravação separada
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'faq_publico' and policyname = 'faq_gravar_admin') then
    drop policy if exists faq_ler_admin on public.faq_publico;
    alter policy faq_ler_publico on public.faq_publico using (ativo or public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
    create policy faq_gravar_admin_ins on public.faq_publico for insert to authenticated with check (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
    create policy faq_gravar_admin_alt on public.faq_publico for update to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso])) with check (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
    create policy faq_gravar_admin_del on public.faq_publico for delete to authenticated using (public.tem_nivel(variadic array['Admin'::public.nivel_acesso]));
    drop policy faq_gravar_admin on public.faq_publico;
  end if;
end $mig$;
