-- 141) AVISO QUANDO O GOOGLE DRIVE DESCONECTA: a cada 6 horas o banco já confere os dois Drives (principal e contingência).
-- Agora, se o Google recusar o acesso (autorização vencida ou retirada), o Administrador recebe um aviso no celular
-- com o caminho para reconectar — no máximo 1 aviso por dia — em vez de só descobrir quando a cópia do backup falha.
-- Drive que nunca foi ligado neste restaurante não gera aviso. Pode rodar de novo sem erro.
create or replace function public._drive_avisar_se_caiu() returns void
language plpgsql security definer set search_path = public, extensions, net as $$
declare d record; a jsonb; b jsonb; v_msg text := ''; v_ult timestamptz;
begin
  select * into d from saude_drive where id;
  if not found then return; end if;
  a := public._saude_drive_ler(d.req_prin, d.pedido_em);
  b := public._saude_drive_ler(d.req_cont, d.pedido_em);
  if a->>'estado' = 'erro' and coalesce(a->>'mensagem', '') ~* '(google|autoriza|token|reconect|invalid_grant|401|403)' then v_msg := 'Drive principal'; end if;
  if b->>'estado' = 'erro' and coalesce(b->>'mensagem', '') ~* '(google|autoriza|token|reconect|invalid_grant|401|403)' then
    v_msg := case when v_msg = '' then 'Drive da contingência' else v_msg || ' e Drive da contingência' end;
  end if;
  if v_msg = '' then return; end if;
  select atualizado_em into v_ult from sistema where chave = 'DRIVE_AVISO_EM';
  if v_ult is not null and v_ult > now() - interval '20 hours' then return; end if;
  perform _cfg_gravar('DRIVE_AVISO_EM', to_jsonb(now()::text));
  perform _push_admins('⚠️ Google Drive desconectado', v_msg || ': o Google recusou o acesso. Toque em Reconectar em Administrador → Sistema → Backup e espaço.', 'drive-desconectado');
exception when others then null;   -- o aviso nunca atrapalha a medição
end $$;
revoke all on function public._drive_avisar_se_caiu() from public, anon, authenticated;

-- a medição de 6 em 6 horas olha antes o resultado da rodada anterior
do $$
declare d text;
begin
  if to_regprocedure('public.saude_drive_pedir()') is null then return; end if;
  d := pg_get_functiondef('public.saude_drive_pedir()'::regprocedure);
  if position('_drive_avisar_se_caiu' in d) = 0 then
    d := replace(d, 'begin
  select decrypted_secret into v_url', 'begin
  perform public._drive_avisar_se_caiu();
  select decrypted_secret into v_url');
    execute d;
  end if;
end $$;
