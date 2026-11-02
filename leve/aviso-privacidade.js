/* Gera a página privacidade.html de um restaurante (Aviso de Privacidade estático, exigido pelo Google). Usado pelo Painel de Revenda.
   Mesmo texto do app (textoAviso, copiado de app-27-conta-cliente.js) + seção dos dados do Google. */
window.gerarPrivacidade = function(d, site){
  var esc = function(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[c]; }); };
  var NOME_H_ = function(){ return esc(d.nome || 'Restaurante'); };
  function textoAviso(d){
    var nome = esc(d.nome || 'o restaurante');
    var ident = '<b>' + nome + '</b>' + (d.razaoSocial ? ' (' + esc(d.razaoSocial) + ')' : '') + (d.cnpj ? ', CNPJ ' + esc(d.cnpj) : '') + (d.endereco ? ', ' + esc(d.endereco) : '');
    var contato = d.telefone ? 'WhatsApp <b>' + esc(d.telefone) + '</b>' : 'os canais de contato do restaurante';
    var anos = Number(d.anos) || 3;
    return '<div class="ct-aviso">' +
      '<p class="sub">Versão ' + esc(d.versao || 1) + '. Este aviso explica, de forma simples, como cuidamos dos seus dados (Lei Geral de Proteção de Dados — LGPD, Lei 13.709/2018).</p>' +
      '<h3>1. Quem cuida dos seus dados</h3><p>O controlador dos dados é ' + ident + '. Para falar sobre privacidade, use ' + contato + '.</p>' +
      '<h3>2. Quais dados usamos</h3><ul><li><b>Da sua conta Google:</b> nome e e-mail (não recebemos a sua senha do Google).</li><li><b>Que você informa:</b> telefone, endereços de entrega e data de nascimento (opcional).</li><li><b>Do uso do app:</b> pedidos, itens, valores, forma de pagamento, cupons usados e carimbos do cartão fidelidade.</li><li><b>Técnicos:</b> endereço de IP e tipo de aparelho, para segurança e para evitar fraudes.</li></ul><p>Quem pede sem conta informa nome, telefone e endereço, que são tratados do mesmo jeito para entregar o pedido.</p>' +
      '<h3>3. Para que usamos (e em que base legal)</h3><ul><li>Receber, preparar, entregar e cobrar seu pedido — <i>execução do contrato</i>.</li><li>Manter sua conta, histórico, endereços e repetir pedidos — <i>execução do contrato / seu consentimento</i>.</li><li>Cartão fidelidade, cupons de boas-vindas, de aniversário e “indique e ganhe” — <i>seu consentimento ao criar a conta</i>.</li><li>Enviar novidades e promoções — <i>somente se você marcar essa opção</i>, e pode desmarcar quando quiser.</li><li>Guardar registros de vendas exigidos por lei (fiscais e contábeis) — <i>obrigação legal</i>.</li><li>Segurança do sistema e prevenção a fraudes — <i>legítimo interesse</i>.</li></ul>' +
      '<h3>4. Com quem compartilhamos</h3><p>Não vendemos seus dados. Eles ficam com provedores de tecnologia que o restaurante usa para funcionar (hospedagem do banco de dados e login — Supabase e Google) e, no que for necessário para a entrega, com o entregador (nome, endereço e telefone). Também usamos o Mercado Pago como operador de pagamento: quando você escolhe pagar pelo site, o e-mail da conta e, no caso de cartão, o CPF informado na tela de pagamento são enviados ao Mercado Pago somente para processar e verificar a transação. O ' + NOME_H_() + ' não recebe nem armazena o número completo do cartão. Também podemos informar autoridades quando a lei exigir.</p>' +
      '<h3>5. Por quanto tempo guardamos</h3><p>Enquanto você tiver a conta. Se ficar <b>' + anos + ' ' + (anos === 1 ? 'ano' : 'anos') + '</b> sem fazer pedidos, seus dados pessoais são <b>anonimizados</b>. Registros de venda exigidos por lei podem ser mantidos sem identificar você.</p>' +
      '<h3>6. Seus direitos</h3><p>Você pode, a qualquer momento: confirmar que tratamos seus dados, acessar, corrigir, <b>pedir uma cópia</b> dos seus dados, pedir anonimização ou eliminação (<b>apagar a conta</b>), saber com quem compartilhamos, retirar consentimentos (como o das promoções) e se opor a um tratamento. Para qualquer um desses pedidos, fale conosco por ' + contato + '.</p>' +
      '<h3>7. Segurança</h3><p>Usamos conexão protegida, acesso restrito e regras no banco de dados para que cada cliente veja somente os próprios dados. Nenhum sistema é 100% imune, mas trabalhamos para reduzir riscos.</p>' +
      '<h3>8. Dados guardados no seu aparelho</h3><p>Guardamos no aparelho o necessário para manter você conectado(a) e lembrar suas preferências (como nome, telefone e carrinho). Você pode limpar isso nos ajustes do navegador.</p>' +
      '<h3>9. Crianças e adolescentes</h3><p>A conta é para maiores de 18 anos. Menores devem pedir com o acompanhamento de um responsável.</p>' +
      '<h3>10. Mudanças neste aviso</h3><p>Se algo importante mudar, você verá a nova versão e será convidado(a) a aceitar de novo.</p></div>';
  }
  var nome = esc(d.nome || 'Restaurante');
  var google = '<h3>11. Dados da sua conta Google (login) e Google Drive</h3>' +
    '<p><b>Login com Google:</b> quando você entra com o Google, recebemos apenas o seu <b>nome</b> e o seu <b>e-mail</b>, para criar e identificar a sua conta neste restaurante. Não recebemos a sua senha do Google e não acessamos o seu Gmail, contatos, agenda ou arquivos.</p>' +
    '<p><b>Google Drive:</b> o sistema usa o Google Drive <u>somente da conta do próprio restaurante</u>, autorizada pelo administrador, para guardar cópias de segurança e arquivos do sistema (por exemplo, imagens de produtos e backups). Clientes não autorizam acesso ao Drive.</p>' +
    '<p><b>Uso limitado:</b> o uso e a transferência de informações recebidas das APIs do Google seguem a Política de Dados de Usuário dos Serviços de API do Google, incluindo os requisitos de Uso Limitado. Esses dados são usados apenas para o funcionamento do sistema, não são vendidos, não são usados para publicidade e não são compartilhados com terceiros, salvo o necessário para operar o serviço ou por obrigação legal.</p>' +
    '<p>Você pode revogar o acesso a qualquer momento em myaccount.google.com/permissions e pedir a exclusão da sua conta no próprio sistema (Minha conta → Meus dados).</p>';
  var local = '<p><b>Localização:</b> usamos a localização aproximada só para saber de onde vêm os pedidos. Ela é apagada ao fim do turno; fica guardada apenas a contagem de acessos por região (cerca de 500 m), sem identificar você nem o seu aparelho.</p>';
  
  var corpo = textoAviso(d).replace(/<\/div>$/, google + local + '</div>');
  var html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Aviso de Privacidade — ${nome}</title>
<meta name="description" content="Aviso de Privacidade de ${nome}: quais dados usamos, para que, com quem compartilhamos e como exercer seus direitos (LGPD).">
<style>
:root{--bg:#ffffff;--tx:#1d1d1f;--mut:#555;--ln:#ddd;--ac:#b3261e}
@media (prefers-color-scheme:dark){:root{--bg:#14100c;--tx:#f3ece2;--mut:#b9aea0;--ln:#3a2f25;--ac:#e0b53a}}
html,body{margin:0;background:var(--bg);color:var(--tx);font:16px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:26px;margin:0 0 4px}h3{font-size:18px;margin:22px 0 6px;color:var(--ac)}
.sub{color:var(--mut)}li{margin:4px 0}a{color:var(--ac)}
hr{border:0;border-top:1px solid var(--ln);margin:24px 0}
</style></head><body><main>
<h1>Aviso de Privacidade — ${nome}</h1>
<p class="sub">Página pública do aplicativo/sistema de pedidos de ${nome}. Endereço do sistema: <a href="${esc(site)}">${esc(site)}</a></p>
<hr>
${corpo}
<hr>
<p class="sub"><a href="${esc(site)}">← Voltar ao ${nome}</a></p>
</main></body></html>
`;
  return html;
};
