-- 124) IFOOD: UMA rodada de 30 s com 2 chamadas ao banco (antes ~10; no começo eram ~22).
-- Cada chamada ao banco vira uma linha de log (plano grátis: 1 GB/mês). Aqui a abertura da rodada já devolve tudo o que o sincronizador precisa
-- (eventos pendentes, ações da equipe, rastreio, reforços e tarefas financeiras) e o fechamento também registra o resultado da consulta.
-- Não muda nenhuma regra: chama as mesmas funções. Se faltarem, o sincronizador usa o jeito anterior. Pode rodar de novo sem erro. Precisa da 121.
create or replace function public.ifood_abrir2(p_dono text, p_seg integer) returns jsonb
language plpgsql security definer set search_path to 'public' as $f$
declare v_ab jsonb; v_cfg jsonb; v_prox jsonb;
begin
  v_ab := public.ifood_abrir(p_dono, p_seg);
  if coalesce((v_ab->>'trava')::boolean, false) is not true then return v_ab; end if;
  v_ab := v_ab || jsonb_build_object(
    'eventos',  coalesce(public.ifood_eventos_ciclo(), '[]'::jsonb),
    'acoes',    coalesce(public.ifood_acoes_pendentes(), '[]'::jsonb),
    'rastreio', coalesce(public.ifood_rastreio_pendentes(), '[]'::jsonb),
    'reforcos', public.ifood_reforcos(),
    'fin',      public.ifood_fin_proximas(6));
  return v_ab;
end $f$;
revoke all on function public.ifood_abrir2(text, integer) from public, anon, authenticated;
grant execute on function public.ifood_abrir2(text, integer) to service_role;

create or replace function public.ifood_fechar2(p_dono text, p_modulos jsonb default null, p_consulta jsonb default null) returns void
language plpgsql security definer set search_path to 'public' as $f$
begin
  if p_consulta is not null then
    begin perform public.ifood_marcar_consulta((p_consulta->>'ok')::boolean, p_consulta->>'erro', (p_consulta->>'token_ok')::boolean); exception when others then null; end;
  end if;
  perform public.ifood_fechar(p_dono, p_modulos);
end $f$;
revoke all on function public.ifood_fechar2(text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.ifood_fechar2(text, jsonb, jsonb) to service_role;
