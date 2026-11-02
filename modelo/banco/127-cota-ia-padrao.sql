-- 127) Cota diária de IA: padrão igual ao do Texas Burger (1200 consultas por dia no restaurante; 300 por dia para o administrador/usuário).
-- Vale para os restaurantes que já existem e para os novos (muda também o valor de fábrica). Não mexe nos limites de operador nem por minuto.
-- Pode rodar de novo sem erro.
alter table public.ai_config alter column cota_diaria_global set default 1200;
alter table public.ai_config alter column cota_diaria_usuario set default 300;
update public.ai_config set cota_diaria_global = 1200, cota_diaria_usuario = 300, atualizado_em = now();
