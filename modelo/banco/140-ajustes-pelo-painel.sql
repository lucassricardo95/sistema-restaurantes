-- 140) AJUSTES PELO PAINEL DE REVENDA: o dono do painel lê e muda alguns ajustes do restaurante sem entrar no sistema dele.
-- Tudo continua podendo ser mudado também dentro do próprio restaurante (Administrador). Nada some de lá.
-- Quem chama: só a função "conector" do painel, pelo conector do Supabase deste restaurante (token guardado no cofre do painel).
-- A função NÃO pode ser chamada pelo site (sem permissão para anon e authenticated). Tudo fica na Auditoria do restaurante.
-- Ações: ler · ia_salvar (chaves das IAs) · dados_salvar (nome, endereço, WhatsApp, horário, redes) · comanda_salvar · senha (trocar a senha de um usuário).
-- Também: o NOME do restaurante passa a ser um só (Aparência e Dados do restaurante ficam sempre iguais), e a gravação da comanda
-- fica numa função só (_comanda_config_gravar), usada pela tela do restaurante e pelo painel.
-- Pode rodar de novo sem erro.

-- comanda: uma função só grava (tela Administrador → Sistema → Comanda e o painel usam a mesma regra)
create or replace function public._comanda_config_gravar(c jsonb, p_padrao boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_tam text := case when c->>'tamanho' in ('pequena', 'grande') then c->>'tamanho' else 'normal' end;
  v_logot text := case when c->>'logoTamanho' in ('pequeno', 'grande') then c->>'logoTamanho' else 'medio' end;
  v_topo text := btrim(coalesce(c->>'topo', '')); v_zap text := regexp_replace(coalesce(c->>'whatsapp', ''), '\D', '', 'g');
  v_agr text := btrim(coalesce(c->>'agradecimento', '')); v_vers text := btrim(coalesce(c->>'versiculo', ''));
  v_qrt text := btrim(coalesce(c->>'qrTitulo', '')); v_qrx text := btrim(coalesce(c->>'qrTexto', ''));
begin
  if p_padrao then delete from sistema where chave = 'ComandaConfig'; return jsonb_build_object('ok', true, 'message', 'Comanda original restaurada.'); end if;
  if char_length(v_topo) > 60 then return _falha('O texto do topo pode ter até 60 letras.'); end if;
  if char_length(v_agr) > 120 then return _falha('O agradecimento pode ter até 120 letras.'); end if;
  if char_length(v_vers) > 260 then return _falha('O versículo pode ter até 260 letras.'); end if;
  if char_length(v_qrt) > 40 then return _falha('O título do QR Code pode ter até 40 letras.'); end if;
  if char_length(v_qrx) > 140 then return _falha('O texto do QR Code pode ter até 140 letras.'); end if;
  if v_zap <> '' then
    if left(v_zap, 2) = '55' and char_length(v_zap) in (12, 13) then v_zap := substr(v_zap, 3); end if;
    if char_length(v_zap) not in (10, 11) then return _falha('O WhatsApp precisa ter DDD + número (10 ou 11 números). Ex.: (16) 99999-9999.'); end if;
  end if;
  insert into sistema (chave, valor, atualizado_em) values ('ComandaConfig', jsonb_build_object(
    'tamanho', v_tam, 'topo', v_topo,
    'mostrarLogo', coalesce((c->>'mostrarLogo')::boolean, true), 'logoTamanho', v_logot,
    'mostrarTelefone', coalesce((c->>'mostrarTelefone')::boolean, true), 'mostrarEntregador', coalesce((c->>'mostrarEntregador')::boolean, true),
    'mostrarHoraImpressa', coalesce((c->>'mostrarHoraImpressa')::boolean, true),
    'whatsapp', v_zap, 'mostrarWhatsapp', coalesce((c->>'mostrarWhatsapp')::boolean, true), 'agradecimento', v_agr,
    'mostrarVersiculo', coalesce((c->>'mostrarVersiculo')::boolean, true), 'versiculo', v_vers,
    'mostrarQr', coalesce((c->>'mostrarQr')::boolean, true), 'qrTitulo', v_qrt, 'qrTexto', v_qrx), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  return jsonb_build_object('ok', true, 'message', 'Comanda salva. Vale para todos os aparelhos na próxima impressão.');
end $fn$;
revoke all on function public._comanda_config_gravar(jsonb, boolean) from public, anon, authenticated;

create or replace function public.api_comanda_config_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  r := _comanda_config_gravar(coalesce(p->'config', '{}'::jsonb), coalesce((p->>'padrao')::boolean, false));
  if coalesce((r->>'ok')::boolean, false) then perform _auditar('Comanda', case when coalesce((p->>'padrao')::boolean, false) then 'voltou ao padrão' else 'ajustes da comanda salvos' end); end if;
  return r;
end $fn$;
revoke all on function public.api_comanda_config_salvar(jsonb) from public, anon;
grant execute on function public.api_comanda_config_salvar(jsonb) to authenticated;

-- nome do restaurante: um só. Mudou em "Dados do restaurante" → muda na Aparência; mudou na Aparência → muda nos Dados.
create or replace function public._sistema_nome_sincronizar() returns trigger
 language plpgsql security definer set search_path to 'public' as $fn$
declare v_nome text;
begin
  if pg_trigger_depth() > 1 then return null; end if;
  if new.chave = 'RestauranteNome' then
    v_nome := left(btrim(coalesce(new.valor #>> '{}', '')), 60);
    if v_nome <> '' then
      update sistema set valor = jsonb_set(valor, '{nome}', to_jsonb(v_nome)), atualizado_em = now()
       where chave = 'Marca' and jsonb_typeof(valor) = 'object' and valor ? 'nome' and valor->>'nome' is distinct from v_nome;
    end if;
  elsif new.chave = 'Marca' and jsonb_typeof(new.valor) = 'object' then
    v_nome := btrim(coalesce(new.valor->>'nome', ''));
    if v_nome <> '' then perform _cfg_gravar('RestauranteNome', to_jsonb(v_nome)); end if;
  end if;
  return null;
end $fn$;
revoke all on function public._sistema_nome_sincronizar() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'zz_sistema_nome_sincronizar' and tgrelid = 'public.sistema'::regclass) then
    create trigger zz_sistema_nome_sincronizar after insert or update on public.sistema for each row
      when (new.chave in ('RestauranteNome', 'Marca')) execute function public._sistema_nome_sincronizar();
  end if;
end $$;

create or replace function public._painel_ajustes(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'auth', 'extensions' as $$
declare
  a text := coalesce(p->>'acao', 'ler');
  v_prov text; v_chave text; k text; v text; i int; v_erro text; v_uid uuid; v_login text;
  chaves text[] := array['nome','endereco','telefone','horario','redes']; lim int[] := array[60,200,30,300,300];
begin
  if a = 'ler' then
    return jsonb_build_object('ok', true,
      'ia', coalesce((select jsonb_agg(jsonb_build_object('provedor', v.prov, 'tem', length(coalesce(s.chave, '')) > 0,
              'final', case when length(coalesce(s.chave, '')) > 8 then right(s.chave, 4) else '' end, 'em', s.atualizado_em) order by v.ordem)
            from (values ('groq',1),('groq_2',2),('cloudflare',3),('cloudflare_conta',4),('gemini',5),('nvidia',6),('gemini_2',7)) v(prov, ordem)
            left join ai_segredos s on s.provedor = v.prov), '[]'::jsonb),
      'dados', jsonb_build_object(
              'nome', coalesce((select valor #>> '{}' from sistema where chave = 'RestauranteNome'), ''),
              'endereco', coalesce((select valor #>> '{}' from sistema where chave = 'RestauranteEndereco'), ''),
              'telefone', coalesce((select valor #>> '{}' from sistema where chave = 'RestauranteTelefone'), ''),
              'horario', coalesce((select valor #>> '{}' from sistema where chave = 'RestauranteHorario'), ''),
              'redes', coalesce((select valor #>> '{}' from sistema where chave = 'RestauranteRedes'), '')),
      'usuarios', coalesce((select jsonb_agg(jsonb_build_object('login', u.login, 'nivel', u.nivel, 'ativo', u.ativo) order by u.nivel, u.login)
            from usuarios u where u.nivel::text <> 'Desenvolvedor'), '[]'::jsonb),
      'integracoes', coalesce((select jsonb_agg(jsonb_build_object('provedor', provedor, 'ligado', ligado, 'modo', modo) order by provedor) from integracoes_config), '[]'::jsonb),
      'comanda', coalesce((select valor from sistema where chave = 'ComandaConfig' and jsonb_typeof(valor) = 'object'), '{}'::jsonb));
  end if;

  if a = 'ia_salvar' then
    v_prov := p->>'provedor'; v_chave := btrim(coalesce(p->>'chave', ''));
    if v_prov is null or v_prov not in ('groq','groq_2','cloudflare','cloudflare_conta','gemini','gemini_2','nvidia') then return _falha('IA desconhecida.'); end if;
    if v_chave = '' then
      delete from ai_segredos where provedor = v_prov;
      perform _auditar('Painel de revenda: chave de IA apagada', v_prov);
      return jsonb_build_object('ok', true, 'message', 'Chave apagada.');
    end if;
    if char_length(v_chave) < 10 or char_length(v_chave) > 400 or v_chave ~ '\s' then return _falha('A chave parece incompleta. Copie de novo, sem espaços.'); end if;
    insert into ai_segredos (provedor, chave, atualizado_em) values (v_prov, v_chave, now())
      on conflict (provedor) do update set chave = excluded.chave, atualizado_em = now();
    perform _auditar('Painel de revenda: chave de IA trocada', v_prov);
    return jsonb_build_object('ok', true, 'message', 'Chave guardada. Vale na hora.');
  end if;

  if a = 'dados_salvar' then
    for i in 1..5 loop
      k := chaves[i];
      if p ? k then
        v := btrim(coalesce(p->>k, ''));
        if char_length(v) > lim[i] then return _falha('O campo "' || k || '" passou de ' || lim[i] || ' letras.'); end if;
        perform _cfg_gravar('Restaurante' || initcap(k), to_jsonb(v));
      end if;
    end loop;
    perform _auditar('Painel de revenda: dados do restaurante atualizados', null);
    return jsonb_build_object('ok', true, 'message', 'Dados do restaurante salvos.');
  end if;

  if a = 'comanda_salvar' then
    declare r jsonb; begin
      r := _comanda_config_gravar(coalesce(p->'config', '{}'::jsonb), coalesce((p->>'padrao')::boolean, false));
      if coalesce((r->>'ok')::boolean, false) then perform _auditar('Painel de revenda: comanda', case when coalesce((p->>'padrao')::boolean, false) then 'voltou ao padrão' else 'ajustes salvos' end); end if;
      return r;
    end;
  end if;

  if a = 'senha' then
    v_login := btrim(coalesce(p->>'login', ''));
    select u.id into v_uid from usuarios u where lower(u.login) = lower(v_login) and u.nivel::text <> 'Desenvolvedor';
    if v_uid is null then return _falha('Usuário não encontrado.'); end if;
    v_erro := _erro_senha_fraca(coalesce(p->>'novaSenha', ''), v_login);
    if v_erro <> '' then return _falha(v_erro); end if;
    update auth.users set encrypted_password = crypt(p->>'novaSenha', gen_salt('bf')), updated_at = now() where id = v_uid;
    delete from auth.sessions where user_id = v_uid;
    perform _auditar('Painel de revenda: senha trocada', v_login);
    return jsonb_build_object('ok', true, 'message', 'Senha trocada. Ele já pode entrar com a nova senha.');
  end if;

  return _falha('Ação desconhecida.');
end $$;
revoke all on function public._painel_ajustes(jsonb) from public, anon, authenticated;
grant execute on function public._painel_ajustes(jsonb) to service_role;
