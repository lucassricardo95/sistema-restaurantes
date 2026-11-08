-- CARDÁPIO DE EXEMPLO (opcional) para um restaurante novo: 3 categorias e 9 produtos com preço, para o dono ver
-- como o cardápio fica e já testar um pedido. Só entra se o cardápio estiver VAZIO (não mexe em cardápio de verdade).
-- Os produtos vêm marcados como exemplo (origem = 'exemplo'). Para tirar tudo depois, rode o bloco do fim deste arquivo.
do $$
declare c_lan uuid; c_por uuid; c_beb uuid; p uuid; x record;
begin
  if exists (select 1 from public.produtos) then raise notice 'O cardápio já tem produtos: nada foi feito.'; return; end if;
  insert into public.categorias (nome, ativa, ordem) values ('Lanches', true, 1) returning id into c_lan;
  insert into public.categorias (nome, ativa, ordem) values ('Porções', true, 2) returning id into c_por;
  insert into public.categorias (nome, ativa, ordem) values ('Bebidas', true, 3) returning id into c_beb;
  for x in select * from (values
    (c_lan, 'X-Burger (exemplo)', 'Pão, hambúrguer 120 g, queijo e molho da casa. Troque pelo seu produto.', 22.00, true, 1),
    (c_lan, 'X-Salada (exemplo)', 'Pão, hambúrguer 120 g, queijo, alface, tomate e maionese.', 25.00, false, 2),
    (c_lan, 'X-Bacon (exemplo)', 'Pão, hambúrguer 120 g, queijo e bacon crocante.', 28.00, false, 3),
    (c_por, 'Batata frita (exemplo)', 'Porção de 400 g. Serve 2 pessoas.', 24.00, true, 4),
    (c_por, 'Onion rings (exemplo)', 'Anéis de cebola empanados, 300 g.', 26.00, false, 5),
    (c_por, 'Fritas com cheddar e bacon (exemplo)', 'Porção de 400 g coberta com cheddar e bacon.', 32.00, false, 6),
    (c_beb, 'Refrigerante lata (exemplo)', 'Lata 350 ml.', 6.00, false, 7),
    (c_beb, 'Suco natural (exemplo)', 'Copo 400 ml. Sabores do dia.', 9.00, false, 8),
    (c_beb, 'Água mineral (exemplo)', 'Garrafa 500 ml.', 4.00, false, 9)
  ) v(cat, nome, descr, preco, dest, ordem) loop
    insert into public.produtos (nome, descricao, categoria_id, ativo, destaque, ordem_cardapio, origem)
      values (x.nome, x.descr, x.cat, true, x.dest, x.ordem, 'exemplo') returning id into p;
    insert into public.produto_precos (produto_id, forma_pagamento_id, preco, custo)
      select p, f.id, x.preco, round(x.preco * 0.4, 2) from public.formas_pagamento f where f.ativa
      on conflict (produto_id, forma_pagamento_id) do nothing;
  end loop;
end $$;

-- PARA TIRAR O CARDÁPIO DE EXEMPLO (quando o dono cadastrar o dele), rode só isto:
-- delete from public.produto_precos where produto_id in (select id from public.produtos where origem = 'exemplo');
-- delete from public.produtos where origem = 'exemplo';
-- delete from public.categorias c where c.nome in ('Lanches','Porções','Bebidas') and not exists (select 1 from public.produtos p where p.categoria_id = c.id);
