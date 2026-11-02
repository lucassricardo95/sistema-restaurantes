-- 125) LOGS: menos tarefas agendadas (plano grátis do Supabase: 1 GB de logs por mês).
-- Cada tarefa do pg_cron grava 2 linhas de log por rodada, mesmo sem fazer nada. Aqui:
--  a) as tarefas de 1 em 1 minuto (cancelar Pix, expirar reservas, nota fiscal, alertas de pedidos e envio da fila para a planilha)
--     passam a ser UMA só tarefa ("tarefas-minuto"): 2 linhas por minuto em vez de 10. Cada parte tem a sua proteção:
--     se uma falhar, as outras continuam e o erro aparece como aviso no log do banco (nunca silencioso).
--  b) o envio da fila para a planilha roda a cada 2 min só quando há algo na fila; com a fila vazia, só a cada 10 min (para manter o Apps Script acordado).
--  c) a tarefa do iFood só fica agendada enquanto o iFood estiver ligado em Integrações (liga e desliga sozinha).
-- Não muda nenhuma regra de negócio: chama as mesmas funções de antes. Pode rodar de novo sem erro.

create or replace function public.tarefas_minuto() returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_min int := extract(minute from now())::int;
begin
  begin
    if jsonb_array_length(public.mp_pendentes_cancelar()) > 0 then perform public.chamar_edge('mp-cancelar', '{}'::jsonb); end if;
  exception when others then raise warning 'tarefas-minuto: mp-cancelar falhou: %', sqlerrm; end;
  begin perform public.mp_expirar_reservas();
  exception when others then raise warning 'tarefas-minuto: mp-expirar falhou: %', sqlerrm; end;
  begin
    if public._integracao_ligada('nfce') and (
         exists (select 1 from public.nfce_notas where estado in ('pendente', 'duvida', 'contingencia', 'cancelando') and emitir_apos <= now() and proxima_tentativa <= now())
         or exists (select 1 from public.nfce_inutilizacoes where estado in ('pendente', 'duvida'))) then
      perform public.chamar_edge('nfce-emitir', '{}'::jsonb);
    end if;
  exception when others then raise warning 'tarefas-minuto: nfce falhou: %', sqlerrm; end;
  begin perform public.alertas_pedidos_cron();
  exception when others then raise warning 'tarefas-minuto: alertas falhou: %', sqlerrm; end;
  begin
    if (v_min % 2 = 0 and exists (select 1 from public.fila_sync where principal_ok_em is null)) or v_min % 10 = 0 then
      perform public.chamar_edge('sync-fila', '{}'::jsonb);
    end if;
  exception when others then raise warning 'tarefas-minuto: sync-fila falhou: %', sqlerrm; end;
end $$;
revoke all on function public.tarefas_minuto() from public, anon, authenticated;

-- iFood: agenda/desagenda a tarefa de 30 s conforme o interruptor em Integrações.
create or replace function public._ifood_agendar() returns void
language plpgsql security definer set search_path to 'public', 'cron' as $$
begin
  if public._integracao_ligada('ifood') then
    perform cron.schedule('ifood-sync-minuto', '30 seconds', $c$select case when public._integracao_ligada('ifood') then public.chamar_edge('ifood-sync-b', '{}'::jsonb) end$c$);
  else
    perform cron.unschedule(jobid) from cron.job where jobname = 'ifood-sync-minuto';
  end if;
end $$;
revoke all on function public._ifood_agendar() from public, anon, authenticated;

create or replace function public._ifood_agendar_trg() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.provedor = 'ifood' then perform public._ifood_agendar(); end if;
  return null;
end $$;
revoke all on function public._ifood_agendar_trg() from public, anon, authenticated;

drop trigger if exists ifood_agendar on public.integracoes_config;
create trigger ifood_agendar after insert or update of ligado on public.integracoes_config
  for each row execute function public._ifood_agendar_trg();

-- Troca as tarefas antigas pela nova.
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('mp-cancelar-pix', 'mp-expirar-reservas', 'nfce-emitir-minuto', 'alertas-pedidos-minuto', 'sync-fila-2min');
  perform cron.schedule('tarefas-minuto', '* * * * *', 'select public.tarefas_minuto()');
  perform public._ifood_agendar();
end $$;
