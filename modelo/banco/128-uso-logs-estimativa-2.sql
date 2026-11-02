-- 128) Estimativa de logs mais fiel (painel e tela "Conexão e servidores"). Antes: toda chamada ao banco valia 1,5 linha de log, o que passou a
-- superestimar depois que as tarefas agendadas foram juntadas (125). Agora a conta separa as duas fontes de log, com o que foi medido nos logs reais:
--   a) pedidos à API (app, funções): ~0,9 linha de log por chamada, média das últimas 24 h (usa os registros "api" de uso_snapshots);
--   b) tarefas agendadas (pg_cron): 2,2 linhas por execução, contando as execuções da última hora (cron.job_run_details) vezes 24.
-- Cada linha = ~530 bytes. Continua sendo estimativa: o número oficial está em Supabase → Settings → Usage → Log Ingestion. Pode rodar de novo sem erro.
create or replace function public._uso_logs_estimado() returns jsonb
language plpgsql stable security definer set search_path to 'public', 'extensions', 'cron' as $$
declare v_ult record; v_ref record; v_dia numeric; v_horas numeric; v_reset timestamptz; v_base text; v_agora bigint; v_cron numeric := 0;
begin
  v_agora := public._uso_api_total();
  select * into v_ult from uso_snapshots where api is not null order by em desc limit 1;
  if v_ult.em is not null then
    select * into v_ref from uso_snapshots where api is not null and em <= now() - interval '24 hours' order by em desc limit 1;
    if v_ref.em is null then select * into v_ref from uso_snapshots where api is not null order by em asc limit 1; end if;
    v_horas := extract(epoch from (now() - v_ref.em)) / 3600;
    if v_horas >= 1 and v_agora >= v_ref.api then
      v_dia := (v_agora - v_ref.api) / (v_horas / 24);
      v_base := 'últimas ' || round(least(v_horas, 24))::int || ' h';
    end if;
  end if;
  if v_dia is null then
    begin select stats_reset into v_reset from pg_stat_statements_info; exception when others then return null; end;
    if v_reset is null then return null; end if;
    v_dia := v_agora / greatest(1, extract(epoch from (now() - v_reset)) / 86400);
    v_base := 'média desde o início';
  end if;
  begin select count(*) * 24 into v_cron from cron.job_run_details where start_time > now() - interval '1 hour'; exception when others then v_cron := 0; end;
  return jsonb_build_object('gb_mes', (v_dia * 0.9 + v_cron * 2.2) * 530 * 30 / 1073741824.0, 'base', v_base);
end $$;
