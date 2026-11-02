-- 126) Tela "Chaves das IAs" (Integrações e contas): a lista passa a seguir a MESMA ordem do circuito de IA
-- (Groq 1º, Groq 2 2º, Cloudflare 3º, Gemini 4º, NVIDIA 5º, Gemini 2 6º). Antes o banco devolvia NVIDIA em 3º e a tela, em cache velho, mostrava fora de ordem.
-- Só muda a ordem da lista. Pode rodar de novo sem erro.
create or replace function public.api_listar_chaves_ia(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok',true,
    'extrasPublico',coalesce((select extras_publico from ai_config limit 1),false),
    'chaves',coalesce((select jsonb_agg(jsonb_build_object(
      'provedor',v.prov,
      'temChave',length(coalesce(s.chave,''))>0 and (v.prov<>'cloudflare' or length(coalesce(c.chave,''))>0),
      'final',case when length(coalesce(s.chave,''))>8 then right(s.chave,4) else '' end,
      'temConta',length(coalesce(c.chave,''))>0,
      'descansando',_ia_provedor_descansando(v.prov),
      'atualizadoEm',s.atualizado_em
    ) order by v.ordem)
    from (values ('groq',1),('groq_2',2),('cloudflare',3),('gemini',4),('nvidia',5),('gemini_2',6)) v(prov,ordem)
    left join ai_segredos s on s.provedor=v.prov
    left join ai_segredos c on c.provedor='cloudflare_conta' and v.prov='cloudflare'),'[]'::jsonb));
end $$;
