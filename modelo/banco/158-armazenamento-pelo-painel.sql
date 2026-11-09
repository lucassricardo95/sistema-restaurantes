-- 158 · Armazenamento e backup pelo painel de revenda (só o Desenvolvedor mexe; o dono só vê o uso e faz "backup agora").
-- Função interna chamada só pelo conector do painel (não é aberta ao público). Ações: ler, backup_cfg, arq_cfg, plano, storage, testar_aviso.
create or replace function public._painel_arm(p jsonb) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare a text := coalesce(p->>'acao', 'ler'); v numeric; n int; v_ids uuid[]; v_dev int; v_eq int;
begin
  if a = 'ler' then
    return jsonb_build_object('ok', true,
      'backup', jsonb_build_object(
        'auto', coalesce((select valor = 'true'::jsonb from sistema where chave = 'BACKUP_AUTO_ATIVO'), false),
        'hora', coalesce((select (valor #>> '{}')::int from sistema where chave = 'BACKUP_HORA'), 4),
        'retDias', (select auto_retencao_dias from backup_config where id)),
      'arquivo', (select jsonb_build_object('ativo', arquivar_ativo, 'dias', arquivar_dias, 'emergAtivo', arquivar_emerg_ativo, 'emergPct', arquivar_emerg_pct) from backup_config where id),
      'plano', jsonb_build_object(
        'bancoMb', coalesce((select (valor #>> '{}')::numeric from sistema where chave = 'LIMITE_BANCO_MB'), 500),
        'storageMb', (select storage_limite_mb from backup_config where id)),
      'backups', coalesce((select jsonb_agg(x order by x->>'em' desc) from (select jsonb_build_object('em', data_hora, 'tipo', tipo::text, 'status', status, 'kb', round(coalesce(tamanho_bytes, 0) / 1024.0), 'drive', copia_drive_em is not null, 'erro', left(coalesce(erro, ''), 160)) x from backups order by data_hora desc limit 8) t), '[]'::jsonb));
  elsif a = 'backup_cfg' then
    n := coalesce((p->>'retDias')::int, 7);
    if (p->>'hora')::int not between 0 and 23 or n not in (3, 7, 14, 30) then return jsonb_build_object('ok', false, 'erro', 'Horário (0 a 23) ou prazo (3, 7, 14, 30 dias) inválido.'); end if;
    insert into sistema (chave, valor, atualizado_em) values ('BACKUP_AUTO_ATIVO', to_jsonb(coalesce((p->>'auto')::boolean, false)), now()), ('BACKUP_HORA', to_jsonb((p->>'hora')::int), now()), ('BACKUP_FREQ', to_jsonb('diario'::text), now())
      on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    update backup_config set auto_retencao_dias = n, atualizado_em = now() where id;
    return jsonb_build_object('ok', true, 'message', 'Backup automático salvo.');
  elsif a = 'arq_cfg' then
    n := (p->>'dias')::int;
    if n is null or n < 30 or n > 3650 then return jsonb_build_object('ok', false, 'erro', 'Informe de 30 a 3650 dias.'); end if;
    update backup_config set arquivar_ativo = coalesce((p->>'ativo')::boolean, true), arquivar_dias = n, atualizado_em = now() where id;
    return jsonb_build_object('ok', true, 'message', 'Arquivamento salvo.');
  elsif a = 'plano' then
    v := (p->>'limiteMb')::numeric;
    if v is null or v < 100 or v > 2000000 then return jsonb_build_object('ok', false, 'erro', 'Informe o tamanho do banco do plano em MB (100 a 2.000.000). Grátis: 500. Pro: 8192.'); end if;
    insert into sistema (chave, valor, atualizado_em) values ('LIMITE_BANCO_MB', to_jsonb(v), now()) on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
    return jsonb_build_object('ok', true, 'message', 'Limite do banco salvo.');
  elsif a = 'storage' then
    v := (p->>'limiteMb')::numeric;
    if v is null or v < 100 or v > 2000000 then return jsonb_build_object('ok', false, 'erro', 'Informe o limite do Storage em MB (mínimo 100).'); end if;
    update backup_config set storage_limite_mb = v::int, atualizado_em = now() where id;
    return jsonb_build_object('ok', true, 'message', 'Limite do Storage salvo.');
  elsif a = 'testar_aviso' then
    select coalesce(array_agg(u.id), '{}') into v_ids from usuarios u where u.ativo and u.nivel::text = 'Desenvolvedor' and exists (select 1 from push_inscricoes i where i.usuario_id = u.id);
    select count(*) into v_dev from push_inscricoes i join usuarios u on u.id = i.usuario_id where u.ativo and u.nivel::text = 'Desenvolvedor';
    select count(*) into v_eq from push_inscricoes i join usuarios u on u.id = i.usuario_id where u.ativo and u.nivel::text in ('Admin', 'Operador');
    if coalesce(array_length(v_ids, 1), 0) = 0 then
      return jsonb_build_object('ok', true, 'enviado', false, 'equipe', v_eq, 'message', 'Nenhum aparelho seu está ligado neste restaurante. Entre no sistema do restaurante pelo seu celular e ligue os avisos (só para teste).');
    end if;
    perform chamar_edge('push-enviar', jsonb_build_object('tipo', 'teste', 'titulo', 'Teste de aviso', 'texto', 'Se você viu isto, os avisos deste restaurante estão funcionando.', 'tag', 'teste-painel', 'usuarios', to_jsonb(v_ids)));
    return jsonb_build_object('ok', true, 'enviado', true, 'aparelhos', v_dev, 'equipe', v_eq, 'message', 'Aviso de teste enviado para ' || v_dev || ' aparelho(s) seu(s).');
  end if;
  return jsonb_build_object('ok', false, 'erro', 'Ação desconhecida.');
end $$;
revoke all on function public._painel_arm(jsonb) from public, anon, authenticated;
