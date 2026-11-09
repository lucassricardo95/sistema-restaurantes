-- 156 · iFood: "Liberado pelo iFood" (painel) e as chaves antigas "homologado" passam a ser UMA coisa só.
-- Antes havia dois controles com o mesmo sentido (homMerchant, homFinanceiro... nos Ajustes do iFood, e o novo "Liberado" por módulo).
-- Agora, ao liberar ou desligar um módulo no painel, a chave de homologação correspondente acompanha sozinha (só para módulos que têm chave: Loja, Avaliações, Financeiro, Cardápio, Entregador, Indicadores).
-- Nada muda no que já existe: só vale para liberações feitas daqui para frente. Pode rodar de novo sem erro.
create or replace function public._ifood_liberado_espelha_hom() returns trigger
 language plpgsql security definer set search_path to 'public' as $fn$
declare v_chave text := case new.modulo when 'merchant' then 'homMerchant' when 'review' then 'homAvaliacoes' when 'financial' then 'homFinanceiro'
                                          when 'catalog' then 'homCatalogo' when 'shipping' then 'homEntregador' when 'analytics' then 'homAnalytics' end;
begin
  if v_chave is null then return new; end if;
  if tg_op = 'INSERT' and not coalesce(new.liberado, false) then return new; end if;
  if tg_op = 'UPDATE' and new.liberado is not distinct from old.liberado then return new; end if;
  update integracoes_config set config = coalesce(config, '{}'::jsonb) || jsonb_build_object(v_chave, coalesce(new.liberado, false)), atualizado_em = now() where provedor = 'ifood';
  return new;
end $fn$;
revoke all on function public._ifood_liberado_espelha_hom() from public, anon, authenticated;
drop trigger if exists ifood_liberado_espelha_hom on public.ifood_modulos;
create trigger ifood_liberado_espelha_hom after insert or update of liberado on public.ifood_modulos
  for each row execute function public._ifood_liberado_espelha_hom();
