-- 129) BACKUPS NO DRIVE: o backup passa a morar no Google Drive (Drive direto), e o Storage do Supabase fica livre para dados antigos arquivados.
-- A coluna diz onde está cada arquivo: 'drive' (normal) ou 'storage' (backups antigos e os de segurança, quando nenhum Drive aceitou a cópia).
-- Depois de aplicar, republique as funções criar-backup, restaurar-backup e excluir-backup (implantar-funcoes.sh) e, UMA vez, mova os antigos:
--   select public.chamar_edge('criar-backup', '{"moverParaDrive":true}'::jsonb);
-- Pode rodar de novo sem erro.
alter table public.backups add column if not exists armazenado_em text not null default 'storage';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'backups_armazenado_em_check') then
    alter table public.backups add constraint backups_armazenado_em_check check (armazenado_em in ('storage', 'drive'));
  end if;
end $$;
