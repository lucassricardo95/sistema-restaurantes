try{ document.addEventListener('gesturestart', function(e){ e.preventDefault(); }); }catch(e){}

/* =========================================================
   PLANILHAS (opcionais): os endereços vêm de config-restaurante.js
   ========================================================= */
const API_URL = (window.RESTAURANTE && window.RESTAURANTE.apiUrl) || "";   // planilha principal (opcional): vem de config-restaurante.js
const CONTINGENCIA_API_URL = (window.RESTAURANTE && window.RESTAURANTE.contingenciaUrl) || "";   // planilha de contingência (opcional)

/* ===================== VERSÃO DO APP ===================== */
const APP_VERSAO = '1.26';
const APP_ATUALIZADO_EM = '01/11/2026';
window.APP_VERSAO = APP_VERSAO;

/* ===================== NOVIDADES POR PERFIL =====================
   Rotina de cada publicação:
     1. Trocar APP_VERSAO e APP_ATUALIZADO_EM acima.
     2. Adicionar UMA entrada nova no TOPO de cada perfil afetado (mesmo 'v' e 'em').
     3. Não mexer nas entradas antigas — viram "Versões anteriores" sozinhas.
   A seção "🆕 O que mudou" do manual é gerada daqui. */
const APP_NOVIDADES = {
  Admin: [
    { v:'1.26', em:'01/11/2026', itens:[
      'Promoções e cupons · Cartão novo "🏷️ Preço por dia da semana": escolha um produto ou combo, os dias, o horário (opcional) e o preço fixo ou % de desconto; marque se aceita cupom. No cardápio aparece o preço antigo riscado e a etiqueta. Vale só no cardápio online (entrega e retirada), não em mesa, balcão nem iFood. Pedido entre 0h e 5h59 conta na noite anterior.',
      'Promoções e cupons · Cartão novo "🎁 Compre e ganhe": a partir de R$ X em produtos (sem a taxa de entrega), o cliente ganha o brinde que você escolher. O carrinho mostra "Faltam R$ X para ganhar…" e o brinde entra no pedido a R$ 0, com custo e baixa no estoque.',
      'Promoções e cupons · Cartão novo "🧾 Bilhete na sacola": sai impresso junto da comanda dos pedidos do iFood (ou de todas as entregas) com título, texto, QR Code do cardápio e um cupom. Você escreve tudo, vê a prévia, testa a impressão e liga ou desliga.',
      'Tudo isso é configurado por você; excluir uma promoção pede a senha.' ] },
    { v:'1.25', em:'01/11/2026', itens:[
      'Tela nova · Administrador → Vendas e cardápio → "Raio-X do negócio": escolha o período e veja, com os dados que o sistema já guardava, quando vende mais (quadro dia × hora e média de pedidos por noite), iFood × seu cardápio (pedidos, valor médio, quem voltou, comissão e taxas), os clientes fiéis do iFood, os tempos de cada etapa (geral, por horário, por entregador e por turno), os cancelamentos por motivo (sem os testes), onde os pedidos ficam parados, os custos de fornecedor que mudaram nos últimos 90 dias e as perdas registradas comparadas com a estimativa.',
      'Promoções e cupons · Cartão novo "📣 Promoção por aviso no celular": escreva título e texto, veja a prévia e envie para os clientes que aceitaram receber promoções. No cardápio, quem tem os avisos ligados é convidado uma vez a aceitar; cada aviso de promoção tem "Não quero mais". Uma promoção a cada 6 horas, no máximo.',
      'Estoque · Botão novo "🗑️ Perdi um produto pronto": escolha o produto (lanche que caiu, voltou ou saiu errado), a quantidade e o motivo; todos os ingredientes da receita saem do estoque como perda e o valor aparece no Raio-X.',
      'Aviso novo ao Admin: se na última hora a cozinha ficar bem mais lenta que o normal (3 pedidos ou mais), chega um aviso no celular.',
      'Cupom de aniversário (ANIVERSARIO) foi ligado: quem tem conta com a data de nascimento ganha o cupom no dia. Quem tem conta sem a data vê um convite para informar. Para desligar, use Promoções e cupons → Cupons automáticos.' ] },
    { v:'1.24', em:'01/11/2026', itens:[
      'Cardápio hoje · Parte nova "🧾 No finalizar": de quem abriu a tela de finalizar, quantos tocaram em "Enviar pedido", quantos saíram sem tocar e o que segurou quem tocou (faltou o número da casa, rua, cidade, nome ou telefone, troco menor que o total, pagar pelo site pediu login, cardápio fechado ou erro ao enviar). Dá para ver o período atual ou os últimos 30 dias. Sem nome nem telefone do cliente, igual ao funil.',
      'Tela nova · Administrador → Vendas e cardápio → "Cardápio: funil e mapa": o funil, o detalhe do finalizar e o mapa por PERÍODO (Hoje, 7 dias, 30 dias, Este mês, Mês passado ou datas à escolha), com as visitas por dia. O funil e as entregas aparecem desde o começo; os pontos de acesso passam a ser guardados a partir de hoje como contagem por região, sem identificar o aparelho.',
      'Cupons · Novo campo "Vale só nestas formas de pagamento" (ex.: só Pix e Dinheiro). No cardápio o cliente vê em quais formas o cupom vale; se escolher outra, o desconto sai e aparece a mensagem com botões "Pagar com Pix"/"Pagar com Dinheiro", e ao voltar para uma forma que vale o cupom volta sozinho.',
      'Cardápio do cliente · A forma de pagamento agora é escolhida em botões (no lugar da lista). A lista falhava em alguns celulares, principalmente no navegador do Instagram no iPhone, e o cliente não conseguia trocar a forma depois de aplicar o cupom. Trocar a forma também confere o cupom de novo.',
      'Conta do cliente · O cardápio convida a entrar com o Google mostrando as vantagens que estão ligadas (cupom de boas-vindas, cartão fidelidade, endereços e repetir pedido), no topo, no carrinho e depois de enviar o pedido.',
      'Cardápio do cliente · Tocar em qualquer parte do cartão do produto (nome, descrição, preço) já abre o item, não só o botão "+".',
      'Cardápio do cliente · Faixa de promoção opcional logo abaixo do banner: escreva em Cardápio Digital → Personalizar → "Faixa de promoção" (em branco não aparece).',
      'Cardápio do cliente · Quem abre o link pelo Instagram, Facebook ou TikTok vê um aviso para abrir no navegador do celular (lá o Google bloqueia o login). Ao tocar em "Continuar com o Google" dentro dessas redes, o cliente é avisado antes. Pedir sem conta continua funcionando ali mesmo.',
      'Avisos · Cartão novo "📊 Resumo do turno" em Loja e equipe → Configurar avisos: ao fechar o caixa, todos os Admins recebem no celular o faturamento do turno (sem a taxa de entrega), pedidos, ticket médio, iFood, cancelados e se o caixa bateu. Vem ligado; tem botão de teste.',
      'Custos · Todo lanche passou a ter no custo 2 sachês de ketchup, 2 de maionese e 2 de mostarda; todo produto preparado tem a embalagem (lanche, hot dog, porção, batata recheada) e o gás e a energia do preparo. Valores estimados: ajuste em Produtos → Estoque. Gás e energia aparecem com a etiqueta "só custo": entram no custo, mas não descontam estoque. A fritadeira é elétrica: porções (fritas) contam só energia, sem gás, e lanches com item frito (frango crocante, anel de cebola, mussarela empanada, batata frita) têm energia a mais.',
      'Clientes · Filtro novo "iFood": mostra só os clientes que pediram pelo iFood. Corrigido: pedido do iFood criava um cadastro repetido "Nome (iFood)" com telefone 0800 (o 0800 é do iFood e é reaproveitado entre clientes) e dava carimbo de fidelidade. Os 9 repetidos foram escondidos e ligados ao cliente do iFood certo, e os carimbos deles voltaram a zero.',
      'Custo real · Taxas das formas de pagamento preenchidas (estimadas: Débito 1,5%, Crédito 3,5%, Alelo 6,5%, iFood 15,2%; Pix e Dinheiro 0%) — confira com o contrato da maquininha em Formas de pagamento. Entraram no custo o óleo da fritadeira, a manteiga para chapear o pão e os temperos.',
      'Custo real · Card novo "Custos gerais" em Custos e precificação: % de perdas e desperdício (padrão 4%, sobre os ingredientes) e custo por pedido (sacola/lacre: R$ 0,60 na entrega e R$ 0,40 na retirada), que entra no custo de cada venda nova.',
      'Preço sugerido · Em cada produto e combo aparece, numa linha logo abaixo do item, o preço sugerido (ou "Preço atual ok"), o ideal e o preço para o iFood; no cadastro aparece a explicação e com botão "Usar" no cadastro e o preço sugerido para o iFood. Regra: custo ÷ custo-alvo (lanches 35%, porções 30%, bebidas 60%, combos 40%), terminando em ,90. Travas: nunca sugere baixar um preço que já está bom, sobe no máximo 25% de uma vez (mostra o ideal junto) e nunca fica abaixo do mínimo que cobre custo, imposto, taxa e 15% de lucro. Tudo ajustável em Custos e precificação → Custos gerais.',
      'Cardápio hoje · O quadro do Início e o pop-up passaram a contar o mesmo período: o turno, desde o fechamento do caixa anterior (entra quem olhou o cardápio à tarde, antes de abrir). Antes o quadro contava desde a meia-noite e o pop-up desde a abertura do caixa, e os números não batiam.',
      'Segurança e velocidade · Ajustes no banco: funções internas fechadas ao público, toda tabela nova já nasce com as permissões certas (mudança do Supabase de 30/10).' ] },
    { v:'1.23', em:'29/10/2026', itens:[
      'Visual · A área da equipe ficou com cara de sistema profissional: títulos em letra comum, cartões lisos, dourado só no que é ação principal ou destaque, ícones de linha no lugar dos emojis e três tipos de botão (principal dourado, secundário de contorno e perigo). O cardápio do cliente continua com a cara do Texas.',
      'Celular · Topo compacto (logo pequena e ícones numa linha só), sobrando mais tela para o trabalho. A faixa "Sem conexão com o servidor principal" agora aparece no alto e não cobre mais a barra de baixo. O Tex fica menor e sai da frente quando você rola a página para baixo.',
      'Computador · Uma barra única no topo com a marca, o menu e as ferramentas; o menu do Administrador na lateral virou uma lista limpa; a tela usa a largura toda.',
      'Cliente · Em Minha conta → Meus dados voltaram os botões "Baixar uma cópia dos meus dados" e "Apagar minha conta", que o Aviso de Privacidade promete.',
      'Limpeza · Código sem uso removido da página e do banco; a rotina que limpa o registro das integrações passou a rodar todo dia (antes o registro crescia sem parar).' ] },
    { v:'1.22', em:'29/10/2026', itens:[
      'Backup e espaço · A tela abre só com o essencial: Uso do espaço, Backup, Google Drive (status de cada Drive e a última limpeza automática) e Cópias de segurança. "Quanto tempo guardar" e "O que fica em cada Drive" foram para o Avançado, e as opções do Drive (abrir pastas, limpar fotos sem uso, reconectar, desconectar) ficam recolhidas em "Opções". Se um Drive tiver problema, o botão para resolver aparece na hora.',
      'Backup e espaço · As barras dos dois Drives abrem mais rápido: o que ocupa cada Drive é guardado por 30 minutos (o espaço usado é sempre o atual) e é refeito logo depois de qualquer limpeza.' ] },
    { v:'1.21', em:'29/10/2026', itens:[
      'Google Drive · Os dois Drives agora somam espaço, em vez de guardar a mesma coisa: o principal fica com as fotos do cardápio, as notas de compra e os backups; a contingência fica com as fotos do ponto, de perdas, recebimentos, ocorrências e os atestados, mais uma cópia das fotos do cardápio e dos backups. Acabou o espelhamento de fotos entre os Drives.',
      'Backup e espaço · Cartão novo "☁️ Google Drive": status de cada Drive, abrir pastas e "🧹 Limpar fotos sem uso" direto na linha do Drive (pede a senha, vai para a lixeira do Drive e dá para desfazer). Sai o bloco de fotos sem uso do Avançado. As barras do "Uso do espaço" mostram o que ocupa cada Drive.',
      'Backup e espaço · A limpeza de fotos sem uso agora roda sozinha uma vez por mês; o resultado (ou o erro) aparece no cartão do Drive.',
      'Backup e espaço · Cartão novo "🗓️ Quanto tempo guardar", com os dias editáveis (pede a senha). Novos padrões: fotos do ponto, perdas, recebimentos e ocorrências 90 dias; atestados 90 dias; backups automáticos 30 dias; notas de compra 13 meses (antes nunca eram apagadas).' ] },
    { v:'1.20', em:'29/10/2026', itens:[
      'Fotos · A foto do atestado (Meus registros) agora fica no Google Drive, nos dois (principal e contingência), e é apagada sozinha após 30 dias. Nenhuma foto vai mais para o banco. O Storage do Supabase fica só com os backups e os arquivos antigos do banco.' ] },
    { v:'1.19', em:'29/10/2026', itens:[
      'Google Drive · Tudo que lia ou gravava no Drive pela planilha agora vai primeiro direto pelo Supabase (mais rápido) e, se não der, pela planilha como segundo caminho: fotos do cardápio (enviar, trocar, remover, copiar para a contingência), comprovantes de nota, fotos do ponto e de perdas/recebimentos/ocorrências, e a leitura do Uso do espaço. Continuam só pela planilha: limpeza de fotos sem uso, meses arquivados e a fila da contingência. Na tela Uso do espaço, o tamanho de "Arquivos do sistema" é atualizado a cada 12 horas.' ] },
    { v:'1.18', em:'29/10/2026', itens:[
      'Backup e espaço · Novo cartão "☁️ Google Drive direto": conecte o Drive principal e o Drive da contingência (cada um com a sua conta Google, com senha) e acesse os dois sem passar pelo Apps Script: navegar nas pastas, baixar, enviar arquivos (senha) e criar pastas. O backup agora também é copiado por esse caminho: se o Apps Script falhar, a cópia no Drive sai mesmo assim, e o Drive da contingência recebe uma cópia independente. O Apps Script continua funcionando como antes.' ] },
    { v:'1.17', em:'28/10/2026', itens:[
      'Conexão e servidores · Tela mais curta e bonita: um resumo grande no topo (tudo certo ou o que pede atenção), servidores em uma linha cada, o que está com problema logo em cima, "Plano grátis do Supabase" em barras (X de Y · %), as outras verificações recolhidas e o botão Verificar agora sempre visível embaixo.' ] },
    { v:'1.16', em:'25/10/2026', itens:[
      'Ponto · Meus registros: o funcionário vê as batidas do período (do dia seguinte ao fechamento até o fechamento do mês seguinte), pede correção de ponto e envia atestado com foto. Você aprova ou recusa em Equipe → Ponto, com senha, e o funcionário recebe um aviso. O dia de fechamento (hoje 20) você muda no mesmo lugar. A foto do atestado é apagada sozinha após 30 dias.',
      'Administrador → Sistema: "Backup e cópias" e "Espaço e arquivamento" viraram uma tela só, "Backup e espaço". No topo, "Uso do espaço" com cinco barras (banco, Storage, planilha, Drive principal e Drive da contingência); depois Backup, Cópia na planilha, Contingência e Conferência. Plano, arquivamento e fotos sem uso ficam em "Avançado", recolhido no fim. O botão "Saúde do sistema" saiu do menu (ela abre pela bolinha do topo) e os menus foram reordenados pelo uso.',
      'iFood · Preço automático: ao salvar o preço da forma "iFood" de um produto ou combo ligado ao iFood, o novo preço vai sozinho para o iFood. Acima do limite de variação não envia e cria um aviso para você conferir.',
      'Cardápio · A localização do cliente agora é guardada junto do pedido: se ele já permitiu a localização, ela é puxada sozinha e o botão "Usar minha localização" some; se não permitiu, o botão continua aparecendo. Mesmo sem GPS, o endereço digitado é localizado no mapa. A Melhor rota usa essa posição exata. A posição é apagada quando o pedido é entregue.',
      'Entregas · Nova "🧭 Melhor rota": quando um entregador sai com 2 ou mais entregas, toque em "Ver melhor rota" e o sistema sugere a ordem mais rápida (saindo e voltando ao restaurante), com o tempo até cada entrega e botão para abrir no Google Maps. Vale para pedidos do sistema, do cardápio digital e do iFood. É só uma sugestão.',
      'Clientes · O endereço do cliente se preenche sozinho com o endereço de entrega mais usado (já na 1ª entrega), só quando o campo está vazio.',
      'Tela · Não amplia mais com o gesto de pinça nem com toque duplo.',
      'Cardápio hoje · O mapa agora mostra as entregas feitas, com localização aproximada: verde = pedidos do sistema, vermelho = iFood.',
      'iFood · Clientes unidos: cliente do iFood (sem telefone) se junta sozinho ao cadastro do sistema quando NOME e ENDEREÇO batem; o telefone passa a sair na comanda e a fidelidade vale. Endereço igual com nome diferente vira sugestão no perfil (botão Unir, com senha) e o nome do iFood fica sempre visível, com Desfazer.',
      'iFood · Ligação automática: item do iFood com nome exatamente igual ao de um produto, combo ou adicional se liga sozinho e aparece marcado "🤖 ligado sozinho"; se estiver errado, toque em Desfazer.',
      'iFood · Avisos: nova tela "Avisos" em Integrações › iFood. Junta o que o iFood mandou e pede atenção: pedido alterado pelo cliente, cancelamento recusado, troca de endereço, pedido devolvido, hora ideal de começar o preparo e prazo de avaliação. Cada aviso também chega como notificação. Tem "Marcar como visto".',
      'iFood · Pedido completo: o sistema agora lê todos os eventos do iFood (alteração do pedido, cancelamento pedido pelo cliente, recusa do iFood, devolução, retirada em área) e mostra o motivo real do cancelamento em português (origem, código e motivo). Itens e valores vêm do pedido completo do iFood.',
      'iFood · Cardápio no iFood: nome até 100 e descrição até 500 letras, combo, tipo de grupo de complementos, código separado por produto e envio em lote conferido até o fim. Novo "Diagnóstico": pergunta ao iFood por que um item NÃO aparece no app e diz o que fazer.',
      'iFood · Avaliações: lista das últimas avaliações com nota, comentário, nome do cliente e prazo para responder; responder (10 a 300 letras) pede a senha e mostra se o iFood aceitou. Aviso para nota baixa e para prazo acabando.',
      'iFood · Entregador do iFood (Sob Demanda), DESLIGADO por padrão (Integrações › iFood › Entregador do iFood). Pedido do iFood com entrega sua, ou pedido do cardápio/balcão/WhatsApp: peça a cotação (grátis), veja valor e tempo, chame o entregador (cobra; pede a senha), acompanhe, compartilhe o link de rastreio e o código de 4 dígitos, veja o nível de confiança, responda troca de endereço e cancele com os motivos do iFood. O custo da corrida vira despesa. Erros do iFood aparecem em português.',
      'iFood · Indicadores (até ontem): faturamento, pedidos, ticket médio, cancelamento, canal, pagamento, quem entregou, dia, hora e tempos médios, por período. Os números do iFood chegam com 1 dia de atraso (D-1). Usa um segundo aplicativo (BI) do iFood: digite o Client ID e o Secret dele em Integrações › iFood.',
      'iFood · Homologação: o painel de homologação agora tem o Roteiro por módulo, com o que fazer e mostrar ao iFood em cada módulo (pedidos, eventos, loja, cardápio, avaliações, financeiro, entrega e indicadores).' ] },
    { v:'1.15', em:'25/10/2026', itens:[
      'Ajuda (no Android): quando o app da equipe estiver publicado, aparece o cartão "📲 App da equipe" com o botão para baixar e instalar. Só a equipe vê; o cliente continua usando a página.',
      'Administrador → Sistema reorganizado em 4 telas: Backup e cópias (backup, cópia na planilha, contingência e conferência), Espaço e arquivamento (abas Uso, Arquivamento e Drive e fotos), Integrações e contas e Auditoria. A Saúde do sistema virou um botão no topo do menu Sistema.',
      'Compactação das 05:30: antes de agendar, confere se há espaço livre; tabela que não cabe fica de fora e aparece aviso em Armazenamento (e no celular).',
      'Senha SEMPRE, inclusive do Admin, também ao excluir produto, combo, adicional, categoria, ingrediente, mesa e perfil fiscal, ao estornar nota, ao registrar ou cancelar ajuste pós-venda, ao cancelar evento ou pedido de compra e ao desfazer preço do iFood. O banco também recusa sem senha.',
      'iFood: vendas e repasses (Administrador → Dinheiro): o financeiro oficial do iFood — vendas com comissão e taxas, lançamentos, repasses com status e banco, antecipações D+1/D+7, conferência da semana (lançamentos × repasse) e o arquivo mensal de conciliação em CSV. Funciona depois que o iFood liberar o módulo Financeiro (homologação).',
      'Nova integração: InfinitePay (Sistema → Integrações e contas → InfinitePay). Pix e crédito pagos no site da InfinitePay, junto ou no lugar do Mercado Pago: cada forma escolhe quem recebe. Tem SIMULAÇÃO (Pagar/Recusar/Expirar sem cobrar), confere cada pagamento com a InfinitePay antes de aprovar e permite registrar o reembolso feito no app dela. Vem DESLIGADA.',
      'iFood (preparação para a homologação): ao cancelar um pedido do iFood você escolhe o motivo oficial do iFood; aviso "🔐 O iFood precisa de um código" em Pedidos e Entregas para o código do entregador e o de entrega; a comanda mostra bandeira do cartão, quem pagou o cupom e retirada agendada; novo "🩺 Estado dos módulos" no cartão do iFood.',
      'Nova tela em Sistema: "📦 Armazenamento". Mostra o banco, o Storage e as planilhas, quanto cresce por dia e quanto tempo falta para encher. Os pedidos antigos agora vão para o Storage (comprimidos e conferidos antes de sair do banco); se o Storage encher, o mais antigo vai para a planilha, num arquivo por ano. Cada arquivamento mostra quanto espaço liberou de verdade (medido às 06:00, depois da compactação das 05:30). Ações dessa tela pedem a senha.',
      'Cardápio do cliente mais fácil: busca também no celular; o "+" de item simples já põe no carrinho; carrinho com − e + e resumo (subtotal, entrega, cupom, total); "Como quer receber?" em dois botões grandes com taxa e tempo; botão "📍 Usar minha localização"; foto do item no topo também no celular; taxa e tempo à vista no topo. A rolagem para o lado continua igual.',
      'Início → "Cardápio hoje" agora abre o pop-up CARDÁPIO HOJE: o funil do turno (entraram no cardápio → abriram um item → puseram no carrinho → abriram o finalizar → enviaram o pedido, com quantos pararam em cada etapa) e um mapa de onde estão acessando (localização aproximada de quem permitiu, ~500 m) e dos pedidos com local de entrega. A localização é apagada ao fechar o caixa e sempre depois de 24 horas. Aparelho da equipe não conta.',
      'Backup e espaço → Google Drive → "🧹 Fotos sem uso": analisa o Drive principal e o da contingência e lista as fotos que nenhum produto ou combo usa (e as duplicadas), com quanto espaço libera. Marque e mande para a lixeira do Drive (pede a senha). "Desfazer a última limpeza" tira tudo da lixeira. Fotos com menos de 7 dias nunca entram.',
      'Novo botão "🛒 Cardápio" no topo: mostra o cardápio digital como o cliente vê, SEM sair da área de funcionários. Faixa no topo: "Voltar à área de funcionários" (sem senha), com aviso se chegar pedido novo. Pedidos, som e vinheta continuam funcionando por trás.',
      'Cupons: botão "🗑️ Excluir" (pede a senha). Cupom nunca usado é apagado de vez; cupom já usado é ARQUIVADO (some da lista, da conta dos clientes e do cardápio, e os pedidos antigos continuam certos) e o código fica livre. "Cupons excluídos" lista os arquivados, com Restaurar. Quem estiver com ele no carrinho vê "Esse cupom não está mais disponível".',
      'Fechar o caixa: o fechamento automático do entregador agora pega TODAS as entregas do caixa, inclusive as concluídas depois da meia-noite (antes ficavam de fora). E o selo "iFood" nos pedidos voltou a aparecer.',
      'iFood → Itens do iFood: "➕ Cadastrar no sistema" cria o produto como RASCUNHO (fora do cardápio), já ligado, com o nome e o preço do iFood; a lista "Pré-cadastros do iFood" mostra o que falta (ficha técnica, preço, foto, categoria). "🗑️ Excluir de vez" (pede a senha) tira itens de TESTE: param de gerar alerta e não voltam. Também dá para marcar um pedido do iFood como teste.',
      'iFood: pedido do iFood esperando aceite toca a VINHETA DO iFOOD (Admin, Operador e Cozinha), de 30 em 30 segundos até alguém aceitar, por até 10 minutos. Aparece uma faixa vermelha com "Ver" e "🔇 Silenciar". Teste em Alertas de pedido → "🛵 Testar som do iFood".',
      'iFood: cada cliente do iFood vira cadastro em Clientes (selo "iFood"), separado pelo ID do iFood — nunca pelo 0800, que é igual para todos. Os pedidos antigos do iFood já foram ligados aos clientes. Histórico, Perfil 360 e Novo/Fiel/VIP funcionam para eles.',
      'iFood: o pedido mostra o telefone 0800 do iFood junto com o CÓDIGO LOCALIZADOR do cliente (e até que horas ele vale). O código também sai na comanda e na mensagem para o entregador.',
      'Novo: Conexão e servidores → "🐞 Erros do sistema". Mostra tudo o que deu errado para a equipe E para os clientes do cardápio (antes, só a equipe logada), quantas vezes e em qual tela. Toque em "Resolvido" depois de corrigir; se acontecer de novo, volta para a lista.',
      'Nenhum erro fica escondido: quando algo dá errado (sem internet, servidor com problema, botão que travou, foto que não subiu), aparece um aviso vermelho dizendo o que aconteceu e o que fazer. Mensagens de erro ficam 15 segundos na tela e, se estiverem fora da vista, a tela rola até elas.'
    ]},
    { v:'1.14', em:'21/10/2026', itens:[
      'Combo com escolha: no cadastro do combo (Editar), marque em cada produto "opção de escolha do cliente" e diga quantos itens o cliente escolhe (ex.: 3 Smash entre Cheddar, Tasty e Catupiry, podendo repetir). No cardápio e no Caixa o cliente/atendente escolhe os sabores antes de adicionar; o preço do combo continua fixo e o estoque baixa conforme o que foi escolhido. O combo "3 Smash + Guaraná 1L" já está assim.'
    ]},
    { v:'1.13', em:'21/10/2026', itens:[
      'Preço promocional: em Produtos e em Combos (Editar) há a caixinha "Preço promocional: não aceita desconto nem cupom". Item marcado fica de fora de cupom do cardápio e de desconto do Caixa: o desconto vale só para os outros itens do pedido (o frete grátis de cupom continua valendo). Se o pedido só tem itens marcados, o cupom e o desconto são recusados. Na lista aparece "🏷️ sem desconto/cupom".'
    ]},
    { v:'1.12', em:'19/10/2026', itens:[
      'Senha sempre: recusar pedido, excluir cliente, cancelar pagamento de funcionário, cancelar movimento de evento, dar desconto no Caixa e editar venda agora pedem a sua senha também para o Admin.',
      'Login: nova caixinha "Lembrar login e senha neste aparelho" — marcando, o celular oferece salvar a senha no próprio cofre de senhas (o sistema não guarda). Só vale no aparelho em que você marcar.',
      'iFood → produto novo: ao cadastrar um produto que tem preço do iFood, ele é enviado ao iFood já PAUSADO (com a categoria, se faltar) e você recebe um aviso para revisar a foto e ativar em Cardápio no iFood. Os pedidos desse item já chegam ligados ao produto.',
      'Queda do sistema com iFood ligado: a faixa laranja agora avisa que os pedidos do iFood NÃO entram enquanto o sistema estiver fora (fique de olho no tablet/portal do iFood). Na volta o sistema varre sozinho os pedidos do período, avisa Admin e Operador e mostra quantos chegaram e quantos o iFood já cancelou.',
      'iFood → Cardápio no iFood: crie e edite categorias, itens (nome, descrição, preço, foto, pausa), grupos de complementos e complementos direto no iFood, e mude preço e status em massa. Pedido do iFood para a homologação do Catalog.',
      'Cancelar venda ou despesa agora pede a sua senha sempre, também para o Admin.',
      'iFood → Horário da loja: edite o horário de funcionamento de cada dia, envie ao iFood e leia de volta o que está lá.',
      'iFood → Itens do iFood: novo botão "Ligar todos os itens com nome igual". Liga de uma vez os itens do iFood que têm um único produto, adicional ou combo de mesmo nome no sistema; o resto fica para você tratar (Usar sugestão, Escolher ou Ignorar).',
      'iFood: o botão de fechar/abrir o cardápio também fecha/abre a loja no iFood (dá para fechar um pouco antes de fechar o caixa). Ao abrir o caixa com o cardápio fechado à mão, a loja do iFood continua fechada. Precisa da integração do iFood ligada e do módulo Merchant liberado pelo iFood.',
      'Novo tipo de cupom em Promoções: "Combo por preço fixo" (ex.: 3 Smash + 1 Guaraná 1L por R$ 65). Só vale se o carrinho tiver os produtos do combo; o desconto é a diferença para o preço normal deles e a taxa de entrega nunca entra na conta. O cupom SMASH65 já está assim.',
      'iFood, pedido AGENDADO: o "despachar" só segue para o iFood quando a janela de entrega abre (antes saía na hora e o iFood reprovou na homologação). O pedido continua com o aviso "AGENDADO para dia/hora".',
      'Pedidos: novo botão "✖ Cancelar pedido" nos pedidos já aceitos (em preparo ou pronto, ao lado de Suspender; antes do aceite use Rejeitar). Abre a mesma janela de cancelamento do Histórico, com motivo e a pergunta da mercadoria perdida. Em pedido do iFood, o cancelamento segue para o iFood sozinho.',
      'As avaliações do iFood aparecem em Feedbacks com o selo "iFood". Responder por ali envia a resposta ao iFood (só o Administrador, integração ligada, até 600 letras); responder pela aba iFood também marca o feedback como respondido. O selo do iFood também aparece na busca de pedidos e nas ocorrências, e a IA do sistema passa a contar o iFood como origem própria.',
      'iFood, 4 recursos EXTRAS, todos DESLIGADOS (em Integrações › iFood › Ajustes, os marcados com EXTRA): conferir repasses com as vendas, avisar também avaliação nota 3, botão "Sugerir resposta" nas avaliações e mostrar no pedido a etapa da entrega feita pelo iFood (e um modo homologação, só para os testes). Cada um explica o que faz; ligue só o que quiser.',
      'Pedidos do iFood agora aparecem com um selo discreto "iFood" no número do pedido (Pedidos, Entregas, Cozinha, comanda e linha do tempo). Quando o iFood faz a entrega, o pedido não vai para o entregador, não entra no acerto e não gera aviso de "pronta sem sair". Pedido novo do iFood conta como aguardando aceite. A integração continua desligada até você ligar.',
      'Visitas ao cardápio: o aparelho de quem entra no sistema não conta mais como visita de cliente.',
    ]},
    { v:'1.11', em:'18/10/2026', itens:[
      'Novo: etiqueta de validade para a vigilância sanitária. O botão da etiqueta no topo (Admin, Operador de caixa e Cozinha) imprime na térmica (58 ou 80 mm) com nome, tipo (aberto, manipulado, descongelado ou fechado), data e hora, validade, conservação, lote e responsável. Em "Itens e validades" você cadastra os dias de cada item; o sistema mostra uma sugestão só como dica e nunca preenche sozinho.',
      'Novo: fotos opcionais (guardadas por 45 dias nos dois Drives) ao lançar uma perda de estoque, receber uma compra ou registrar uma ocorrência. Depois de lançar, o sistema pergunta se você quer tirar até 3 fotos; é só tocar em Pular se não quiser. Depois, o botão 📷 no próprio lançamento mostra a foto.',
      'Novo: botão de relógio no topo com a escala e a batida do ponto. O ponto agora confere a localização (só vale perto do restaurante), o rosto do funcionário (cadastrado na primeira batida) e guarda a foto por 45 dias nos dois Drives. Se o rosto não conferir, a batida fica para você aprovar em Loja e equipe → Ponto.',
      'Tudo segue o turno do caixa: os relatórios "Vendas por dia", o gráfico diário e o acerto do entregador agora agrupam pelo dia em que o caixa abriu, mesmo quando o turno passa da meia-noite.',
      'Novo em Sistema → Backup e espaço: você informa o tamanho do banco do seu plano do Supabase (grátis, Pro ou outro) e pode deixar o arquivamento por idade em Automático ou Só manual, com prazo livre em dias. A proteção dos 95% continua sempre ligada (não dá para desligar): ela arquiva aos poucos, devolve o espaço ao Supabase e avisa aos 70% e 85%.',
      'Novo: em Produtos há "Margem baixa" (produtos abaixo da margem mínima, geral ou por categoria, com o preço sugerido; dá para ignorar um produto; o celular só avisa quando entra um produto novo abaixo do mínimo) e "Histórico de preços" (todo preço que mudou, quem mudou e quando). Em Estoque, "Compra sugerida" monta a lista do que está no mínimo, por fornecedor, pronta para o WhatsApp. Em Eventos: "Rendimento por hora", "Contrato (PDF)" e, em Relatórios, "Fechamento do mês (PDF)". O celular do dono agora também avisa das contas a pagar na véspera, no dia e vencidas.',
      'Novo: Eventos ganhou Calendário (botão ao lado de Lista), Orçamento (PDF) para mandar ao contratante e o cartão "Eventos a receber" em Contas a pagar. Na Equipe: troca de turno com aprovação do dono, aviso no celular quando a escala muda, Ponto com horas extras, reserva de 13º e férias e o peso da mão de obra nas vendas. Em Backup e espaço: gráfico de crescimento do banco com previsão. Também arrumei o "Ajustar preços" (nomes das categorias e botões).',
      'Novo: a Central de Eventos ficou mais simples. Em Administrador → Vendas e cardápio → Eventos, a lista vem separada em Próximos, Em andamento e Concluídos, cada um com A receber, Recebido e Resultado. Toque no evento para ver as abas Dados, Custos e Recebimentos (dá para cancelar um lançamento errado), mandar WhatsApp ao contratante, duplicar o evento e imprimir o resumo.',
      'Novo: Administrador → Loja e equipe → Escala da equipe. Monte a escala de todos (turnos, folgas, férias), use o padrão semanal, copie semanas, imprima ou mande por WhatsApp. Cada pessoa vê a própria escala em Início → Minha escala.',
      'Novo: Administrador → Loja e equipe → Equipe e pagamentos. Cadastre funcionários (salário, dia de pagamento, encargos), toque em Pagar para lançar o salário em Despesas, imprima o recibo e receba aviso quando o pagamento do mês passar do dia.',
      'Novo produto: se você sair no meio, o sistema guarda o rascunho e pergunta se quer continuar. Em Produtos há também "% Ajustar preços" (reajuste de uma categoria de uma vez) e "👁 Mostrar/esconder" (vários produtos do cardápio de uma vez). O rascunho guarda também receita, adicionais e preços.',
      'Cadastro de produto: aviso "falta algo para ficar completo", sugestão de preço quando o lucro está baixo e o novo "📄 Duplicar" no menu ⋯ do produto.',
      'Os botões do topo ficaram mais fáceis de acertar com o dedo (a aparência continua a mesma). O campo de busca da Ajuda ficou na largura certa.',
      'A Ajuda ganhou prints de Abrir e Fechar caixa, Clientes, Cadastro de produto e Mesas do Garçom.',
      'Os avisos de falha do sistema (planilha parada, backup, caixa vencido…) agora se repetem a cada 30 minutos até o problema ser resolvido (muda em Loja e equipe → Configurar avisos, onde o cartão de alertas passou a ficar). Com o app aberto o Admin também vê a faixa e ouve o som.',
      'Histórico de vendas: dias antigos, cujos pedidos já foram para a planilha, agora aparecem na própria tela (com reimpressão do comprovante). Pedidos com chat, ocorrência ou nota fiscal não são mais arquivados, ficam no sistema.'
    ]},
    { v:'1.10', em:'18/10/2026', itens:[
      'Novo: aviso de pedido parado. Aparece a faixa "⏰ Pedidos parados" (com som) quando um pedido do seu perfil fica sem avançar. Toque em Ver pedido, Adiar 10 min ou Silenciar este pedido. Os tempos e as regras ficam em Loja e equipe → Configurar avisos → ⏰ Alertas automáticos. Avisos de falha do sistema (backup, planilha parada, caixa vencido…) agora se repetem a cada 30 minutos até o problema ser resolvido.',
      'O "hoje" dos pedidos agora segue o turno do caixa (do abrir ao fechar, mesmo passando da meia-noite). Em Relatórios há o período novo "Uso real (desde 17/10/2026)".',
      '"Marcar como recebido" agora pergunta em que forma o cliente pagou.',
      'O comprovante da nota de compra é guardado no Google Drive (você escolhe qual dos dois), não mais no Supabase.',
      'A Ajuda ganhou campo de busca e prints reais com a marcação de onde clicar, em versão para celular e para computador.'
    ]},
    { v:'1.7', em:'17/10/2026', itens:[
      'Adicionais e receitas de produto agora pedem a quantidade em gramas (ou ml) do jeito que você pensa: o campo mostra a unidade (g), tem atalhos (10, 20, 30, 50, 100 g) e, embaixo, um resumo ao vivo com quanto baixa do estoque (ex.: 30 g = 0,03 kg) e o custo. A lista de adicionais mostra o que cada um baixa do estoque. Quantidade zerada ou pequena demais agora avisa em vez de gravar 1.'
    ]},
    { v:'1.6', em:'16/10/2026', itens:[
      'Ajuda atualizada: novas seções “Caixa vencido”, “Entregadores: taxa e fechamento” e “Mercado Pago (pagamento online)”, e “No computador” e “Onde fica cada coisa” reescritas com o menu atual (6 grupos e campo “Ir para…”).'
    ]},
    { v:'1.5', em:'16/10/2026', itens:[
      'Novo em Clientes › perfil: \"Preferências fixas\" (ex.: sem cebola, alergias). Cada pedido novo do cliente guarda uma cópia, para a comanda mostrar. As preferências aparecem na tela da cozinha, na comanda impressa e nos detalhes do pedido. O cliente com conta também edita as suas em Minha conta › Meus dados e as vê no checkout antes de pedir. Quem está em Em risco ou VIP agora também recebe um aviso (push) junto com o cupom automático, se tiver o aviso ligado no aparelho.'
    ]},
    { v:'1.4', em:'16/10/2026', itens:[
      'Novo em Promoções › Cupons automáticos: "Sentimos sua falta" (cliente em risco, mais de 45 dias sem pedir) e "Cliente VIP". Já vêm DESLIGADOS: ajuste o valor e ligue. Só recebe quem tem conta Google e aceitou promoções; o cupom aparece em Minha conta.'
    ]},
    { v:'1.3', em:'16/10/2026', itens:[
      'Novo em Clientes: Perfil 360 no topo do perfil (segmento Novo, Fiel, VIP ou Em risco, gasto total, ticket médio, frequência, itens favoritos e se tem conta Google) e selo do segmento na lista, com filtros Em risco, VIP, Fiéis e Novos. Os pedidos antigos arquivados entram na conta, pelo telefone do cliente.',
      'Novo em Backup e espaço: botão "Simular" no arquivamento. Mostra quantos pedidos e caixas sairiam do Supabase, quantos ficam e se o resumo guardado confere com o que há na planilha, sem mover nada. Ao anonimizar um cliente (LGPD), os pedidos dele arquivados na planilha também são limpos, de madrugada.'
    ]},
    { v:'1.2', em:'16/10/2026', itens:[
      'Menu do Administrador reorganizado em 6 grupos: Hoje, Dinheiro, Produtos, Vendas e cardápio, Loja e equipe e Sistema. Nenhuma tela foi retirada; só mudaram de grupo ou de nome (por exemplo, \"Contas e acessos\" agora é \"Integrações e contas\" e \"Ajustes pós-venda\" é \"Reembolsos e ajustes\").',
      'Novo no menu do Administrador: campo \"Ir para…\". Digite uma palavra (cupom, estoque, iFood, reembolso) e toque na tela que aparece.',
      'Cada tela do menu do Administrador agora traz uma linha explicando o que ela faz.',
      'Formas de pagamento agora fica numa tela só, com duas abas: \"Taxas e prazos\" e \"No cardápio\" (antes estava também em Cardápio Digital → Pagamentos).',
      'No Cardápio Digital, as abas agora dizem \"... no cardápio\" (o que o cliente vê) e cada uma tem o botão \"Editar cadastro\", que abre Produtos já na aba certa.',
      'Em Backup e espaço e em Sincronização e contingência há o botão \"Ver saúde do sistema\", que abre o painel de conexão e servidores.'
    ]},
    { v:'1.1', em:'13/10/2026', itens:[
      'Mercado Pago — preparação do checkout e da operação: Pix/cartão online, painel de pagamentos que precisam de decisão, resumo mensal de recebimentos e taxas. A integração continua desligada até ser configurada e testada. SQL e Edge Functions ainda precisam ser aplicados/implantados pelo responsável.',
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'Novo: feedback ligado à conta do cliente e com resposta. Em Painel → Feedbacks cada feedback mostra "👤 com conta" ou "sem conta" e tem o botão "💬 Responder": o cliente com conta vê a sua resposta em Minha conta › Pedidos. Sem conta, o botão "WhatsApp" abre a conversa com o telefone dele. O botão de feedback do rodapé do cardápio continua igual e aceita anônimos.',
      'Novo: brindes na conta do cliente. Os produtos marcados como prêmio de fidelidade ou de indicação (Editar produto › Mais opções) viram brindes: o cliente escolhe o prêmio na Minha conta ou no carrinho, junto com um pedido ou sozinho. O brinde vai a R$ 0,00 (aparece nos relatórios com o custo e baixa o estoque) e a entrega continua sendo cobrada. Quem indica ganha o produto-prêmio e/ou o cupom "quem indicou" quando o amigo conclui o 1º pedido: cada um vale se estiver marcado/ligado, e dá para ter os dois (o do indicado continua). Pedido cancelado devolve o brinde.',
      'Novo: conta do cliente com login Google (opcional). O cliente vê pedidos e repete com um toque, guarda endereços, recebe cupons e vê o cartão fidelidade e o link do "indique e ganhe". Tem Aviso de Privacidade (LGPD), "baixar meus dados" e "apagar conta". Sem conta, tudo continua igual.',
      'Novo em Promoções: botão Editar em todo cupom, cupom "só para quem tem conta", "só para um cliente", texto para o cliente e 4 cupons automáticos (boas-vindas, aniversário, indique e ganhe) que já vêm desligados — ajuste e ligue. Cupom de pedido cancelado volta para o cliente. Cartão "Privacidade" para razão social/CNPJ, prazo de anonimização e nova versão do Aviso.',
      'Corrigido: ao abrir o sistema já logado, o cardápio do cliente não aparece mais por um instante antes da tela do sistema (aparece só a logo).',
      'Novo: no Início, "Cardápio hoje" mostra quantos clientes abriram o cardápio eletrônico hoje (cada aparelho conta 1 vez por dia; aparelhos da equipe não contam). O alerta virou uma faixa fina no topo e a conta das mesas foi para dentro do cartão Mesas.',
      'No computador: o topo ficou numa linha só e as abas ficam sempre à vista; o Administrador ganhou um menu ao lado com todas as telas (um clique); os pedidos ficam lado a lado; o Caixa mostra carrinho e pagamento à direita; nos relatórios, os títulos das colunas ficam em cima dos números e o gráfico do DRE ficou do tamanho certo. No celular nada muda.',
      'Valores com ponto de milhar e o sinal de negativo na frente: R$ 1.475,90 e −R$ 3.691,11.',
      'Novo: imposto sobre vendas estimado, com ou sem nota fiscal. Em Painel → Relatórios, no cartão DRE, informe a alíquota do mês que o contador passar (vale para os meses seguintes até mudar). O imposto aparece no DRE, na Visão Geral, nos relatórios e na margem do produto, do combo e da Calculadora; o custo do produto não muda. Nova categoria de despesa "Imposto das vendas (DAS)": com alíquota cadastrada, o DAS não conta duas vezes. O DRE também mostra a taxa de entrega cobrada e corrige os eventos do mês.',
      'iFood (ainda desligado) revisado: a venda grava o que fica para a loja (cupom pago pelo iFood, taxa de serviço do iFood e entrega feita pelo iFood ficam fora), a comissão entra nas taxas (estimada pela taxa % da forma "iFood" em Pagamentos e trocada pela real no repasse), "a receber do iFood" já vem sem a comissão, pedido cancelado não cria reembolso e "Saiu para entrega" só avisa o iFood quando a loja entrega.',
      'Mais simples: entrada, perda e inventário do estoque, suspender e recusar pedido, receber e cancelar compra, meta de vendas, fechar o cardápio e marcar reembolso agora abrem uma janela só, com motivos prontos para tocar. Ao receber uma compra, escolha "Já paguei" ou "Vou pagar depois" (com calendário).',
      'Novo: produto novo já vem com os adicionais que os outros produtos da mesma categoria têm. Bebida e item comprado pronto vêm sem adicionais.',
      'Mudou: em Sistema, "Backup" e "Espaço e fotos" viraram uma tela só, "Backup e espaço". Saíram o botão "Importar cardápio inicial", a escolha de onde salvar a foto (agora vai sempre para os dois Drives) e a caixinha do espelho das 3h (o espelho já se atualiza sozinho a cada 10 minutos). "Fazer backup agora" começa sem pergunta.',
      'Por dentro: a planilha principal e a contingência ficaram enxutas (só o que o sistema usa hoje). A planilha recebe só o cardápio, os clientes e as vendas; as abas que não são mais usadas podem ser apagadas.',
      'Visual: as listas de Estoque, Produtos, Combos e Usuários ficaram compactas. Toque na linha (ou no ⋯) para ver as ações. O botão do Assistente virou só o rosto do Tex, para não cobrir botões, e a página ganhou espaço no fim. A Visão Geral avisa quando falta custo nos produtos (lucro e margem ficariam maiores que a realidade).',
      'Novo: cadastro de produto mais fácil. Em "Como é feito?" escolha Preparado aqui (receita), Comprado pronto (bebidas) ou Sem controle. Na receita você digita o ingrediente, cria um novo ali mesmo e pode copiar a receita de outro produto. Ingrediente por kg/litro pede gramas/ml.',
      'Novo: o custo dos produtos e combos se atualiza sozinho quando o preço de um ingrediente muda (edição, "💲 Preços em lote" ou compra recebida). Ingrediente: "Paguei R$ __ por __" calcula o custo. Aviso "Cadastro incompleto" mostra o que falta.',
      'Novo: o Estoque tem as abas Ingredientes e Bebidas e itens prontos. Na compra, digite o item e toque nele na lista; se não for da lista, aparece aviso de que não entra no estoque. Bebida em fardo: "Embalagens" × "Unidades em cada".',
      'Novo: reembolso de venda cancelada. Quando uma venda já paga é cancelada, o sistema cria sozinho um reembolso pendente (valor, forma de pagamento, motivo e quem cancelou). Em Administrador → Financeiro → Ajustes pós-venda aparece a lista "Reembolsos de vendas canceladas"; depois de devolver o dinheiro ao cliente, o Administrador toca em "marcar devolvido".',
      'Novo: o Assistente (chat) agora também registra despesa, pagamento de conta, entrada/perda/contagem de estoque, ingrediente, cliente, ocorrência, sangria, ajuste pós-venda, brinde e recebimento/cancelamento de compra. Ele nunca grava sozinho: mostra um cartão e só grava ao tocar em "Confirmar e gravar". Cancelar despesa e ajuste pós-venda pedem a sua senha de administrador. Excluir, mexer em venda/caixa/usuários/preços ele não faz.',
      'Novo: conheça o Tex, o mascote do Assistente. Ele aparece no botão, no título e nas respostas do chat da equipe.',
      'Novo: a Saúde do sistema agora mostra o uso do plano gratuito do Supabase (tamanho do banco, arquivos, usuários ativos e chamadas às funções, esta última estimada). Fica verde até 70%, amarela a partir de 70% e rosa a partir de 90%. Banda e mensagens em tempo real só aparecem no painel do Supabase (Settings → Usage).',
      'Melhorado: os botões de Nota fiscal e de iFood (Dados fiscais, Perfis fiscais, Conferência, Pedidos do iFood etc.) agora abrem em janela (pop-up) com botão de fechar, em vez de alongar a página. Salvar e conferir funcionam igual.',
      'Novo: botão "Testar" em cada IA (Gemini, Gemini 2, Groq, Groq 2, NVIDIA, Cloudflare), em Contas e acessos e na tela "Assistente de IA" (toque na bolinha das estrelas). Mostra se a chave responde e, se não, o motivo em português. Não gasta as consultas do dia.',
      'Novo: a bolinha do topo agora também avisa a Saúde do sistema — fica amarela quando algo pede atenção e rosa quando precisa de cuidado (a conexão com problema continua vermelha/laranja). Toque nela para ver o que é.',
      'Mudou: a "Saúde do sistema" saiu do Painel e agora fica só dentro de "Conexão e servidores" (toque na bolinha colorida do topo), junto com os servidores.',
      'Novo: o cliente pode receber no celular os avisos do pedido (confirmado, pronto, saiu para entrega, entregue) e, 30 min depois da entrega, "Como foi seu pedido?". Saem sozinhos quando a equipe muda o status. Em Feedbacks aparece se veio pelo aviso ou pelo chat.',
      'Nada abre sozinho: a Ajuda e os avisos do Assistente vêm fechados (toque no título para abrir) e, ao entrar no Admin, aparecem só os grupos — toque no grupo e depois na tela.',
      'Cardápio do cliente: no fim da página aparecem nome, cidade, telefone e Instagram (edite em Cardápio Digital → Dados do restaurante) e o versículo 1 Coríntios 10:31.',
      'Novo: preço próprio por produto para o iFood. Em Pagamentos, a forma iFood está marcada como "preço próprio por produto"; em cada produto e combo aparece o campo "Preço no iFood" (em branco = preço base). Os preços do iFood de antes foram recolocados. No Caixa, ao escolher iFood, os itens usam o preço do iFood.',
      'Novo: nota fiscal — cancelamento automático da nota (até 30 min), conferência Vendas × Notas, numeração pulada (inutilizar), pacote do contador por mês e aviso do limite de 500 notas do plano (tudo ainda desligado).',
      'Novo: emissão da nota fiscal (NFC-e) pela Focus NFe (ainda desligada): a nota sai sozinha após a venda, com lista de notas, reemissão, DANFE, CPF na nota e treino para o Desenvolvedor.',
      'Novo: cadastro da Nota fiscal (ainda desligada): dados fiscais da empresa, perfis fiscais (NCM/CFOP/CSOSN) por produto ou categoria e planilha para o contador preencher. Com a nota ligada, o Resultado (DRE) mostra o imposto estimado.',
      'Novo: preços do iFood (importar/enviar), pausa por estoque, financeiro, avaliações e relatório por canal, ainda desligados.',
      'Novo: negociação de cancelamento e controle da loja no iFood (pausar, abrir, fechar), ainda desligados.',
      'Novo: integração com o iFood pronta no sistema (desligada): pedidos entram como venda, itens ligados aos produtos, status avisado ao iFood. Só funciona depois de ligada em Contas e acessos → Integrações.',
      'Novo em Contas e acessos: campos das IAs de reserva (NVIDIA e Cloudflare) e o cartão "Integrações" (iFood e Nota fiscal), ainda desligados.',
      'Contas e acessos agora mostra também as chaves das IAs (Gemini e Groq): ver e trocar pedem a senha de administrador.',
      'Novo: Administrador → Sistema → Contas e acessos, com e-mails, links e senhas das contas do sistema. A senha fica no cofre e só aparece com a sua senha de administrador.',
      'Primeira versão estável do sistema. O servidor principal é o Supabase; a planilha principal é a reserva e a planilha de contingência é o último recurso.',
      'Toque na bolinha colorida do topo para ver o estado de cada servidor.',
      'Impressão: não pergunta mais "Saiu no papel?". Fica um botão "🔁 Não saiu? Reimprimir" por 10 minutos.',
      'Com só um entregador ativo, toda entrega já fica no nome dele.',
      'O Assistente guarda a conversa; "Nova conversa" começa do zero.',
      'Acréscimo por forma de pagamento: em Pagamentos, cada forma pode cobrar % ou valor fixo a mais (ex.: iFood). O preço do produto agora é um só. O cliente é avisado no cardápio, e o Caixa e o fechamento de mesa somam o acréscimo sozinhos.',
      'Novo: Compras e fornecedores (Catálogo): registre compras, atualize estoque e custo e gere a despesa. No Assistente, "comprei 30kg de picanha por R$ 900" vira um cartão para você confirmar; a IA nunca grava sozinha.',
      'Novo: no cardápio, número da casa e cidade em campos separados e obrigatórios na entrega; a cidade chega junto com o endereço do pedido.',
      'Correções: pop-ups não ficam mais cortados no fim da tela nem atrás do menu de baixo. Preço base único: todo produto e combo tem um só preço; iFood/Alelo cobram a mais pelo acréscimo da forma em Pagamentos. A senha de administrador agora é conferida de verdade ao criar, excluir ou mudar perfil/senha de usuário. Corrigidos: mensagem de erro falsa ao registrar ajuste pós-venda, cortesia fora do lucro, ordem dos feedbacks, exclusão de ingrediente e status da contingência. O cliente do cardápio não vê mais a faixa interna do modo reserva nem tem a página recarregada quando a internet oscila; o chat do cliente não trava sem internet; toque repetido em sangria, estoque e prêmios não grava duas vezes.',
      'Novo: menu fixo embaixo no celular (Início, Caixa, Pedidos e "Mais"), com bolinha vermelha nos avisos. No computador continua no topo.',
      'Novo visual do cardápio do cliente: cabeçalho menor com a situação (aberto/fechado), produtos rolando para o lado com botão "+", fotos mais baixas e Atendimento como ícone redondo. Pop-ups sem corte no fim da tela.',
      'Novo: botão discreto "🌐 Cardápio aberto" em Início e no Caixa para fechar e reabrir o cardápio dos clientes em um toque. Correção: o cardápio podia aparecer "fechado" com o caixa aberto.',
      'Novo: modo reserva mais claro (a faixa laranja diz o que funciona e o que espera) e cartão "Saúde do sistema" em Visão geral, com backup, conferência diária de vendas e tarefas automáticas.',
      'Novo: avisos com o app fechado. No 🔔 do topo, toque em "Ligar avisos com o app fechado": o celular passa a avisar "Novo pedido" do cardápio e "Cliente no atendimento", mesmo com o app fechado. No iPhone, instale o app na tela inicial antes.',
      'Novo: Auditoria com IP de origem (apagado após 90 dias), registro de entradas no sistema e de tentativas de login erradas, com busca e filtro de período. Em Sistema → Usuários, cada sessão mostra o IP.',
      'Novo em Relatórios: margem por forma de pagamento, vendas por dia da semana, comparação com o ano passado e períodos de 90 dias e 12 meses.',
      'Novo: cupom progressivo (desconto maior por faixa de valor do pedido), CEP que preenche rua e bairro e filtros no histórico do cliente.',
      'Novo: busca 🔍 no topo (clientes, pedidos e produtos). A busca de cliente por nome voltou a funcionar, sem precisar de acento.',
      'Novo: "Dados do restaurante" (nome, endereço, telefone, horário, redes) aparecem no rodapé do cardápio.',
      'Novo: Linha do tempo do pedido (em "ver pedido completo") e botões para baixar relatórios e dados em CSV para o Excel.',
      'Cupom não é aceito no Caixa: use o desconto por porcentagem.'
    ]}
  ],
  Operador: [
    { v:'1.24', em:'01/11/2026', itens:[
      'Cardápio hoje · Parte nova "🧾 No finalizar": mostra quantos clientes tocaram em "Enviar pedido" e o que segurou o pedido (campo faltando, troco, login, cardápio fechado ou erro).',
      'Cardápio do cliente · Tocar em qualquer parte do cartão do produto já abre o item.' ] },
    { v:'1.15', em:'25/10/2026', itens:[
      'Ações sensíveis (cancelar, excluir, desconto, estorno, ajuste pós-venda) pedem sempre a senha de um Administrador.',
      'iFood: ao cancelar um pedido do iFood, escolha o motivo oficial na lista com borda dourada. Quando aparecer "🔐 O iFood precisa de um código" em Pedidos/Entregas, peça o código ao entregador (ou ao cliente) e envie.',
      'Início → "Cardápio hoje": toque para ver o funil do turno (quantos entraram, abriram item, puseram no carrinho e pediram) e o mapa de onde estão acessando.',
      'Novo botão "🛒 Cardápio" no topo: vê o cardápio digital como o cliente, sem sair. "Voltar à área de funcionários" volta na mesma tela, sem senha.',
      'iFood: o pedido mostra o 0800 do iFood com o CÓDIGO LOCALIZADOR do cliente (para ligar), também na comanda. Pedido do iFood esperando aceite toca a vinheta do iFood a cada 30 s até ser aceito, com botão "🔇 Silenciar".',
      'Nenhum erro fica escondido: quando algo dá errado (sem internet, servidor com problema, botão que travou, foto que não subiu), aparece um aviso vermelho dizendo o que aconteceu e o que fazer. Mensagens de erro ficam 15 segundos na tela e, se estiverem fora da vista, a tela rola até elas.'
    ]},
    { v:'1.11', em:'18/10/2026', itens:[
      'Os botões do topo ficaram mais fáceis de acertar com o dedo (a aparência continua a mesma). A Ajuda ganhou prints de Abrir e Fechar caixa e de Clientes.'
    ]},
    { v:'1.10', em:'18/10/2026', itens:[
      'Novo: aviso de pedido parado. Aparece a faixa "⏰ Pedidos parados" (com som) quando um pedido do seu perfil fica sem avançar. Toque em Ver pedido, Adiar 10 min ou Silenciar este pedido.',
      'O "hoje" dos pedidos agora segue o turno do caixa (do abrir ao fechar, mesmo passando da meia-noite).',
      '"Marcar como recebido" agora pergunta em que forma o cliente pagou.',
      'A Ajuda ganhou campo de busca e prints reais com a marcação de onde clicar, em versão para celular e para computador.'
    ]},
    { v:'1.6', em:'16/10/2026', itens:[
      'Ajuda atualizada: nova seção “Caixa vencido” (como fechar o caixa vencido) e “No computador” com o menu atual.'
    ]},
    { v:'1.3', em:'16/10/2026', itens:[
      'Novo em Clientes: Perfil 360 no topo do perfil (segmento Novo, Fiel, VIP ou Em risco, gasto total, ticket médio, itens favoritos) e selo do segmento na lista, com filtros Em risco, VIP, Fiéis e Novos.'
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'Novo: você pode responder feedbacks. Em Operação → Feedbacks cada feedback mostra "👤 com conta" ou "sem conta" e tem o botão "💬 Responder": o cliente com conta vê a sua resposta em Minha conta › Pedidos. Sem conta, o botão "WhatsApp" abre a conversa com o telefone dele. O botão de feedback do rodapé do cardápio continua igual e aceita anônimos.',
      'Novo: no Início, "Cardápio hoje" mostra quantos clientes abriram o cardápio eletrônico hoje (cada aparelho conta 1 vez por dia; aparelhos da equipe não contam). O alerta virou uma faixa fina no topo e a conta das mesas foi para dentro do cartão Mesas.',
      'No computador: o topo ficou numa linha só e as abas ficam sempre à vista; os pedidos ficam lado a lado e o Caixa mostra carrinho e pagamento à direita. No celular nada muda.',
      'Valores com ponto de milhar: R$ 1.475,90.',
      'Mais simples: suspender e recusar pedido agora abrem uma janela com motivos prontos para tocar (ex.: "Cliente não atende", "Sem estoque").',
      'Novo: quando a nota fiscal for ligada, o Caixa ganha o campo "CPF na nota (só se o cliente pedir)". Enquanto estiver desligada, nada muda.',
      'Novo: o cliente que aceitou os avisos recebe no celular cada mudança de status que você faz no pedido (confirmado, pronto, saiu para entrega, entregue). Em Feedbacks aparece se veio pelo aviso ou pelo chat.',
      'Nada abre sozinho: a Ajuda e os avisos do Assistente vêm fechados (toque no título para abrir) e, ao entrar no Admin, aparecem só as telas para você escolher.',
      'Novo: menu fixo embaixo no celular (Início, Caixa, Pedidos e "Mais"), com bolinha vermelha nos avisos. No computador continua no topo.',
      'Novo visual do cardápio do cliente: cabeçalho menor, produtos rolando para o lado com botão "+", fotos mais baixas e Atendimento como ícone redondo. Pop-ups sem corte no fim da tela.',
      'Novo: botão discreto "🌐 Cardápio aberto" em Início e no Caixa para fechar e reabrir o cardápio dos clientes em um toque.',
      'Novo: modo reserva mais claro. A faixa laranja no topo diz o que funciona (Caixa e pedidos do cardápio) e o que espera a volta do sistema.',
      'Novo: avisos com o app fechado. No 🔔 do topo, toque em "Ligar avisos com o app fechado" para o celular avisar "Novo pedido" e "Cliente no atendimento" mesmo com o app fechado. No iPhone, instale o app na tela inicial antes.',
      'Primeira versão estável do sistema.',
      'Toque na bolinha colorida do topo para ver o estado dos servidores.',
      'Impressão: fica um botão "🔁 Não saiu? Reimprimir" por 10 minutos; não precisa confirmar quando saiu certo.',
      'Com só um entregador ativo, toda entrega já fica no nome dele.',
      'Acréscimo por forma de pagamento: em Pagamentos, cada forma pode cobrar % ou valor fixo a mais (ex.: iFood). O preço do produto agora é um só. O cliente é avisado no cardápio, e o Caixa e o fechamento de mesa somam o acréscimo sozinhos.',
      'Novo: CEP no Caixa preenche rua e bairro da entrega; filtros no histórico do cliente (período, entrega/retirada, pago/a receber).',
      'Novo: busca 🔍 no topo (clientes, pedidos e produtos). A busca de cliente por nome voltou a funcionar, sem precisar de acento.',
      'Novo: Linha do tempo do pedido, em "ver pedido completo".',
      'Cupom não é aceito no Caixa: use o desconto por porcentagem.'
    ]}
  ],
  'Garçom': [
    { v:'1.15', em:'25/10/2026', itens:[
      'Quando algo dá errado (sem internet, servidor com problema, botão que travou), aparece um aviso vermelho dizendo o que aconteceu e o que fazer. Nada falha calado.'
    ]},
    { v:'1.10', em:'18/10/2026', itens:[
      'Novo: aviso de pedido parado. Aparece a faixa "⏰ Pedidos parados" (com som) quando um pedido do seu perfil fica sem avançar. Toque em Ver pedido, Adiar 10 min ou Silenciar este pedido. Você recebe os avisos de mesa pronta esperando ser servida, e pode ligar os avisos com o app fechado.',
      'O "hoje" dos pedidos agora segue o turno do caixa (do abrir ao fechar, mesmo passando da meia-noite).',
      'A Ajuda ganhou campo de busca e prints reais com a marcação de onde clicar, em versão para celular e para computador.'
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'A Ajuda vem com os tópicos fechados: toque no título para abrir.',
      'Primeira versão estável do sistema.',
      'Toque na bolinha colorida do topo para ver se o sistema está online.',
      'Novo: busca 🔍 no topo (cliente, pedido ou produto). A busca de cliente por nome voltou a funcionar.'
    ]}
  ],
  Cozinha: [
    { v:'1.15', em:'25/10/2026', itens:[
      'Pedido do iFood esperando aceite toca a vinheta do iFood a cada 30 s até ser aceito, com botão "🔇 Silenciar" neste aparelho. Os outros pedidos continuam com o som de sempre.',
      'Quando algo dá errado (sem internet, servidor com problema, botão que travou), aparece um aviso vermelho dizendo o que aconteceu e o que fazer. Nada falha calado.'
    ]},
    { v:'1.10', em:'18/10/2026', itens:[
      'Novo: aviso de pedido parado. Aparece a faixa "⏰ Pedidos parados" (com som) quando um pedido do seu perfil fica sem avançar. Toque em Ver pedido, Adiar 10 min ou Silenciar este pedido. Você recebe os avisos de pedido novo sem aceite e de preparo demorado, e pode ligar os avisos com o app fechado.',
      'O "hoje" dos pedidos agora segue o turno do caixa (do abrir ao fechar, mesmo passando da meia-noite).',
      'A Ajuda ganhou campo de busca e prints reais com a marcação de onde clicar, em versão para celular e para computador.'
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'A Ajuda vem com os tópicos fechados: toque no título para abrir.',
      'Primeira versão estável do sistema.',
      'Impressão da comanda: fica um botão "🔁 Não saiu? Reimprimir" por 10 minutos; não precisa confirmar quando saiu certo.',
      'Comanda e "Imprimir novos" em 58mm, 80mm e A4.',
      'Novo: busca 🔍 no topo para achar um pedido pelo número, nome do cliente ou produto.'
    ]}
  ],
  Entregador: [
    { v:'1.15', em:'25/10/2026', itens:[
      'iFood: quando o iFood pedir o código de entrega, aparece "🔐 O iFood precisa de um código" no topo de Entregas. Peça o código ao cliente, digite e toque em Enviar.',
      'Na entrega do iFood, a mensagem e a comanda trazem o telefone 0800 do iFood com o CÓDIGO LOCALIZADOR do cliente, para você ligar se precisar.',
      'Quando algo dá errado (sem internet, servidor com problema, botão que travou), aparece um aviso vermelho dizendo o que aconteceu e o que fazer. Nada falha calado.'
    ]},
    { v:'1.10', em:'18/10/2026', itens:[
      '"Meu dia" e as entregas concluídas agora contam pelo turno do caixa (do abrir ao fechar), sem zerar na meia-noite.',
      'A Ajuda ganhou campo de busca e prints reais com a marcação de onde clicar, em versão para celular e para computador.'
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'A Ajuda vem com os tópicos fechados: toque no título para abrir.',
      'Primeira versão estável do sistema.',
      'Quem marca o pedido como "Pronta" é a Cozinha.',
      'Enquanto você tem entrega "Saiu para entrega", o app envia sua localização a cada ~18 s (só nesse período, sem histórico).'
    ]}
  ],
  Cliente: [
    { v:'1.26', em:'01/11/2026', itens:[
      'Alguns lanches têm preço especial em certos dias: o preço antigo aparece riscado e a etiqueta mostra a promoção.',
      'Em algumas compras, ao chegar a um valor você ganha um brinde. O carrinho mostra quanto falta.' ] },
    { v:'1.25', em:'01/11/2026', itens:[
      'Com os avisos do pedido ligados, você pode escolher receber também as promoções do Texas no celular. Para parar, toque num aviso de promoção e escolha "Não quero mais".',
      'Informe seu aniversário em Minha conta → Meus dados e ganhe um presente no dia.' ] },
    { v:'1.24', em:'01/11/2026', itens:[
      'Toque em qualquer parte do cartão do produto para abrir e escolher.',
      'Abriu o cardápio pelo Instagram ou Facebook? Para entrar com o Google e pagar pelo site, use "Abrir no navegador". Pedir sem conta funciona ali mesmo.' ] },
    { v:'1.15', em:'25/10/2026', itens:[
      'Novo em Minha conta: a aba "🎮 Jogos" com os 4 joguinhos, para jogar quando quiser (o recorde fica guardado no seu aparelho).',
      'Algumas formas de pagamento pelo site podem abrir a página segura da InfinitePay: pague lá e volte ao cardápio; a tela confere sozinha.',
      'Novo: enquanto espera o pedido, toque em "🎮 Jogar enquanto espera" no acompanhamento. São 4 joguinhos com os lanches do cardápio, e o jogo pausa e avisa quando o seu pedido muda de etapa.',
      'Privacidade: usamos sua localização aproximada só para saber de onde vêm os pedidos. Ela é apagada ao fim do turno.',
      'Ficou mais fácil pedir: busca no celular, o "+" de item simples já coloca no carrinho, dá para mudar a quantidade no carrinho com − e +, o resumo mostra subtotal, entrega e cupom, e "Como quer receber?" virou dois botões com a taxa e o tempo. Na entrega, "📍 Usar minha localização" preenche rua e bairro.',
      'Se algo der errado (sem internet, sistema do restaurante com problema), aparece um aviso dizendo o que aconteceu e que o pedido NÃO foi enviado, com o WhatsApp para pedir.',
      'No carrinho, se faltar algum dado da entrega (rua, número, cidade) ou do troco, o campo fica vermelho, a tela vai até ele e o motivo aparece logo abaixo.'
    ]},
    { v:'1.6', em:'16/10/2026', itens:[
      'Ajuda atualizada: pagamento pelo site (Pix e cartão), botão “Acompanhar agora”, voltar para “Todos os pedidos” e convite para instalar o app no cartão “Pedido enviado”.'
    ]},
    { v:'1.0', em:'09/10/2026', itens:[
      'Novo: em Minha conta › Pedidos, cada pedido tem o botão "⭐ Feedback". Quando o restaurante responder, a resposta aparece no próprio pedido. O botão de feedback do rodapé continua funcionando sem login.',
      'Novo: brindes! Com o cartão fidelidade completo ou um brinde de indicação, escolha seu prêmio na Minha conta ou no carrinho, junto com um pedido ou sozinho. Ele sai por R$ 0,00 e a entrega, se houver, é cobrada.',
      'O botão Entrar/Minha conta agora fica numa faixa logo abaixo do banner, o calendário da data de nascimento ficou visível e o cartão fidelidade da conta ficou igual ao do cardápio.',
      'Novo: avisos do pedido no celular (confirmado, pronto, saiu para entrega e entregue) e, depois da entrega, "Como foi seu pedido?". Toque em "Quero receber" no topo do cardápio. No iPhone, instale o app antes.',
      'O atendente do chat agora oferece registrar o seu elogio ou sugestão como feedback.',
      'A Ajuda vem com os tópicos fechados: toque no título para abrir.',
      'Novo: seu nome e telefone voltam preenchidos nos próximos pedidos neste aparelho. O endereço continua vindo pela sua localização.',
      'Novo: conheça o Tex, o atendente virtual! Ele agora aparece no botão redondo do canto da tela e responde com o rosto dele.',
      'Atendente virtual no balão "💬 Atendimento": tira dúvidas do cardápio, preços e promoções, e mostra o andamento do seu pedido pelo seu celular.',
      '"📦 Acompanhe seu pedido" mostra todos os pedidos feitos neste aparelho; dá para cancelar nos primeiros 3 minutos, antes de o restaurante aceitar.',
      'Cupom de desconto direto no carrinho, cálculo de troco e mesa por QR Code.',
      'Se a forma de pagamento tem acréscimo, o carrinho avisa quanto você paga a mais e em quais formas não há acréscimo.',
      'Na entrega, digite o CEP para preencher rua e bairro. O carrinho fica guardado neste aparelho por 24 horas. Alguns cupons dão mais desconto em pedidos maiores.'
    ]}
  ]
};
const CONTINGENCIA_CHAVE_PUBLICA = "txbpub-7be6640269f54d5db1bff1a474d76a417758957a"; // so permite enviar pedido validado e ler o catalogo publico (sem custos/clientes)
const CONTINGENCIA_CHAVE_KEY = 'txbContChaveInterna'; // chave interna (clientes): guardada so depois do login, apagada ao sair
let modoContingenciaAtivo = false;

const CACHE_KEY = 'texasBurgerCache_v2';
/* SEGURANÇA: escape único para todo texto vindo de cliente/planilha antes de entrar em innerHTML */
function escH(s){ return String(s==null?'':s).replace(/[&<>"'`]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;','`':'&#96;'}[c])); }
const SESSAO_KEY = 'texasBurgerSessao_v2';

let currentUser = null; // {login, nivel}
let clientes = [], promocoes = [], cupons = [], eventos = [], indicacoes = [], fidelidadeClientes = [];
let formasPagamento = [], categorias = [];
let produtos = [], produtoPrecos = [], produtoIngredientes = [], estoque = [], combos = [], comboPrecos = [], comboItens = [];
let adicionais = [], produtoAdicionais = [], feedbacks = [], ocorrencias = [], configCardapio = { kicker:'', frase:'' }, movimentacoesEstoque = [], maisPedidos = [], mesas = [];
let vendas = [], itensVenda = [], pagamentosVenda = [], despesas = [], sangrias = [];
let categoriasDespesa = [], despesasRecorrentes = [], ajustesPosVenda = [];
let configEstoque = { bloquear:false };
let configEntrega = { taxaPadrao:0, ajudaDiaria:0 }, fechamentosEntrega = [], entregasFechadas = [];
let configNotificacoes = null; // ITENS 64/65: {evento:{ativo, perfis[]}} vindo do backend (null = usa o padrão)
let sistemaAlertas_ = { backup:'', drive:'', driveCont:'', copiaBackup:'' }; // preenchido quando o Admin abre Armazenamento
let metas = { mensal: 0, diaria: 0 }, sessaoCaixa = null, historicoCaixa = [];
let usuarios = [], logRecentes = [];

let modalClienteId = null;
let modoCliente = 'com';
let tipoEntregaAtual = 'Retirada';
let modoItem = 'produto';
let formaPrecoAtual = null; // ID da forma de pagamento usada pra precificar os itens do carrinho
let clienteVendaSelecionado = null;
let clienteMesaCarregadoDe_ = null; // id da mesa de onde o cliente foi mantido após lançar (null = cliente escolhido na mão)
let carrinhoAtual = [];
let pagamentosAtuais = [];
let cancelarContexto = null;
let calcExpr = '';
let ultimoRelatorioTexto = '';
let ingredientesProdutoNovo = [];
let ingredientesProdutoEdicao = [];
let itensComboNovo = [];
let itensComboEdicao = [];
let produtoEditandoId = null;
let comboEditandoId = null;
let vendaEditandoId = null;
let itensEdicaoVenda = [];
let senhaAdminCallback = null;

function normTel(t){ return (t===undefined||t===null?'':t).toString().replace(/\D/g,''); }
/* v1.15 — chave do cliente. Cliente do iFood não tem telefone (o iFood manda um 0800 igual para todos):
   ele é identificado pelo cadastro ("ifood:<id do cliente>"). Os demais continuam pelo telefone. */
function chaveCliente_(c){ return c && c.ifoodId && !normTel(c.telefone) ? 'ifood:' + c.id : normTel(c && c.telefone); }
function chaveVendaCliente_(v){
  if(v && v.canal === 'iFood') return v.clienteId ? 'ifood:' + v.clienteId : '';
  return normTel(v && v.clienteTelefone);
}
function chaveNorm_(k){ k = String(k == null ? '' : k); return /^ifood:/.test(k) ? k : normTel(k); }
/* telefone para ligar num pedido do iFood: 0800 + código localizador (com validade) */
function ifoodContato_(v){
  if(!v || v.canal !== 'iFood') return null;
  const vencido = !!(v.ifoodLocalizadorAte && Date.now() > v.ifoodLocalizadorAte);
  const ate = v.ifoodLocalizadorAte ? new Date(v.ifoodLocalizadorAte).toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }) : '';
  return { telefone: v.clienteTelefone || '', codigo: v.ifoodLocalizador || '', vencido, ate };
}
/* Busca de cliente por nome (sem diferenciar maiúscula/acento) OU por telefone. O telefone só entra na comparação quando o termo tem dígitos:
   antes, um nome digitado virava texto vazio no telefone e "casava" com todos os clientes. */
function semAcento_(t){ return (t===undefined||t===null?'':t).toString().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim(); }
function clienteCombinaBusca_(c, termo){
  const t = semAcento_(termo); if(!t) return true;
  if(semAcento_(c.nome).includes(t)) return true;
  const d = normTel(termo);
  return d.length > 0 && normTel(c.telefone).includes(d);
}
function formatarMoeda(v){ const n = Math.round((Number(v)||0)*100)/100, p = Math.abs(n).toFixed(2).split('.'); return (n < 0 ? '−R$ ' : 'R$ ') + p[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ',' + p[1]; }
/* Converte o que vier da planilha em número: aceita número, "51", "51,5", "R$ 51,50", "1.234,56", "1,234.56", "(51,5)" e "-51,5".
   Vazio, texto que não é número, data e booleano viram 0. Ponto sozinho: "1.234" / "1.234.567" = milhar; "0.250" e "51.5" = decimal.
   Vírgula sozinha é decimal ("51,5"), a não ser que se repita ("1,234,567" = milhar). Mesma regra do backend (numPlanilha_). */
function numPlanilha_(v, padrao){
  const pad = (padrao === undefined) ? 0 : padrao;
  if(typeof v === 'number') return isFinite(v) ? v : pad;
  if(typeof v !== 'string') return pad;
  let s = v.replace(/[\s\u00a0]/g, '').replace(/%$/, '');
  let neg = false;
  if(/^\(.*\)$/.test(s)){ neg = true; s = s.slice(1, -1); }
  if(s.charAt(0) === '-'){ neg = true; s = s.slice(1); }
  s = s.replace(/^R\$/i, '');
  if(!/^[\d.,]+$/.test(s) || !/\d/.test(s)) return pad;
  const temV = s.indexOf(',') !== -1, temP = s.indexOf('.') !== -1;
  if(temV && temP){
    if(s.lastIndexOf(',') > s.lastIndexOf('.')) s = s.replace(/\./g, '').replace(',', '.');
    else s = s.replace(/,/g, '');
  } else if(temV){
    s = ((s.match(/,/g) || []).length > 1) ? s.replace(/,/g, '') : s.replace(',', '.');
  } else if(temP){
    if(/^[1-9]\d{0,2}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
  }
  const n = Number(s);
  if(!isFinite(n)) return pad;
  return neg ? -n : n;
}
/* Garante que os campos numéricos dos dados recebidos (servidor ou cache antigo) sejam número de verdade, para as somas não virarem texto/NaN. */
const NUM_CAMPOS_DADOS_ = {
  vendas:['valorTotal','custoTotal','valorOriginal','valorDesconto','taxaEntrega'],
  itensVenda:['quantidade','valorUnitario','custoUnitario','valorTotalItem'],
  pagamentosVenda:['valor','taxa'],
  produtoPrecos:['preco','custo'], comboPrecos:['preco','custo'],
  estoque:['quantidade','minimo','custo'],
  movimentacoesEstoque:['quantidade','qtdAntes','qtdDepois'],
  comboItens:['quantidade'],
  sangrias:['valor'],
  fidelidade:['carimbos','premios'],
  historicoCaixa:['fundoCaixa','totalVendas','totalDespesas','saldoFinal'],
  despesas:['valor'], despesasRecorrentes:['valor'], ajustesPosVenda:['valor'],
  formasPagamento:['taxaPct','taxaFixa','prazoDias'],
  adicionais:['preco']
};
function normalizarNumerosDados_(d){
  if(!d || typeof d !== 'object') return d;
  Object.keys(NUM_CAMPOS_DADOS_).forEach(function(chave){
    const lista = d[chave]; if(!Array.isArray(lista)) return;
    const campos = NUM_CAMPOS_DADOS_[chave];
    lista.forEach(function(o){
      if(!o || typeof o !== 'object') return;
      campos.forEach(function(k){ if(k in o && typeof o[k] !== 'number') o[k] = numPlanilha_(o[k]); });
    });
  });
  if(d.sessaoCaixa && typeof d.sessaoCaixa === 'object' && 'fundoCaixa' in d.sessaoCaixa && typeof d.sessaoCaixa.fundoCaixa !== 'number') d.sessaoCaixa.fundoCaixa = numPlanilha_(d.sessaoCaixa.fundoCaixa);
  return d;
}
function apiConfigurada(){ return typeof SUPABASE_URL_ === 'string' && SUPABASE_URL_.indexOf('http') === 0; }   // o servidor principal é o Supabase; as planilhas são reserva opcional
/* TURNO DO CAIXA: o "hoje" das listas de pedidos segue o caixa (abre num dia, fecha no outro), não a data do calendário.
   Caixa aberto → do momento da abertura até agora. Sem caixa aberto → o último turno (abertura até fechamento). Sem nenhum registro → o dia do calendário. */
function turnoCaixa_(){
  try{
    if(typeof sessaoCaixa !== 'undefined' && sessaoCaixa && sessaoCaixa.aberturaTimestamp) return { ini: sessaoCaixa.aberturaTimestamp, fim: Infinity, aberto: true };
    const h = (typeof historicoCaixa !== 'undefined' && historicoCaixa || []).filter(c=>c && c.aberturaTimestamp);
    if(h.length){ const u = h.reduce((a,b)=> b.aberturaTimestamp > a.aberturaTimestamp ? b : a); return { ini: u.aberturaTimestamp, fim: u.fechamentoTimestamp || Infinity, aberto: false }; }
  }catch(e){}
  const d = new Date(); const ini = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  return { ini, fim: ini + 864e5 - 1, aberto: false, calendario: true };
}
function noTurnoCaixa_(ts, v){ const t = turnoCaixa_(); /* venda ligada ao caixa aberto (ex.: pedido do iFood que chegou antes da abertura) conta no turno, mesmo com horário anterior */ try{ if(v && v.caixaId && t.aberto && typeof sessaoCaixa!=='undefined' && sessaoCaixa && v.caixaId===sessaoCaixa.id) return true; }catch(e){} ts = Number(ts) || 0; return ts >= t.ini && ts <= t.fim; }
/* Dia (AAAA-MM-DD) do TURNO a que um horário pertence = dia em que aquele caixa abriu. Sem caixa que o contenha, vale o dia do calendário.
   Usado no acerto do entregador e em "Vendas por dia" (o turno atravessa a meia-noite e continua sendo o mesmo dia). Mesma regra do banco (_calc_fechamento_entrega). */
function diaDoTurno_(ts){ ts = Number(ts) || 0; try{ const lista = (historicoCaixa||[]).slice(); if(typeof sessaoCaixa!=='undefined' && sessaoCaixa && sessaoCaixa.aberturaTimestamp) lista.push({aberturaTimestamp:sessaoCaixa.aberturaTimestamp, fechamentoTimestamp:0});
  let ach = null; lista.forEach(c=>{ if(!c || !c.aberturaTimestamp) return; const fim = c.fechamentoTimestamp || Infinity; if(ts >= c.aberturaTimestamp && ts <= fim && (!ach || c.aberturaTimestamp > ach.aberturaTimestamp)) ach = c; });
  if(ach) return dataLocalISO(new Date(ach.aberturaTimestamp)); }catch(e){} return dataLocalISO(new Date(ts)); }
function diaTurnoAtual_(){ const t = turnoCaixa_(); return dataLocalISO(new Date(t.calendario ? Date.now() : t.ini)); }
function dataLocalISO(date){ const y=date.getFullYear(), m=String(date.getMonth()+1).padStart(2,'0'), d=String(date.getDate()).padStart(2,'0'); return `${y}-${m}-${d}`; }
function parseDataBR(str){
  if(!str) return null;
  const [datePart, timePart] = str.split(' ');
  if(!datePart) return null;
  const [d,m,y] = datePart.split('/').map(Number);
  const [hh,mm] = (timePart||'00:00').split(':').map(Number);
  if(!d||!m||!y) return null;
  return new Date(y, m-1, d, hh||0, mm||0).getTime();
}
/* FASE 11 (ITEM 79) — toda operação que não pode se repetir ganha um requisicaoId automático (lista SB_IDEM_NOVAS_).
   O id é ligado à "intenção" (ação + dados, via hash — nenhuma senha é guardada): se a internet cair no
   meio e o usuário tocar de novo, o id é o mesmo e o backend ignora a repetição. Some após qualquer
   resposta definitiva do servidor. Guardado na sessionStorage para sobreviver a um recarregar da página. */
const IDEM_KEY = 'texasBurgerIdem_v1';
let _idemMapa = {};
try{ _idemMapa = JSON.parse(sessionStorage.getItem(IDEM_KEY) || '{}') || {}; }catch(e){ _idemMapa = {}; }
function idemPersistir_(){ try{ sessionStorage.setItem(IDEM_KEY, JSON.stringify(_idemMapa)); }catch(e){} }
function idemHash_(s){ let x = 5381; for(let i=0;i<s.length;i++) x = ((x<<5)+x+s.charCodeAt(i))|0; return (x>>>0).toString(36); }
function idemChave_(action, payload){ return action + '|' + idemHash_(JSON.stringify(payload||{})); }
function idemId_(chave){
  if(!_idemMapa[chave]){
    const chaves = Object.keys(_idemMapa); if(chaves.length > 60) delete _idemMapa[chaves[0]];
    _idemMapa[chave] = novaRequisicao_(); idemPersistir_();
  }
  return _idemMapa[chave];
}
function idemLimpar_(chave){ if(chave && _idemMapa[chave]){ delete _idemMapa[chave]; idemPersistir_(); } }
/* controle de versão: toda edição leva a versão (_v) do registro que a pessoa estava vendo.
   Se outra pessoa alterou o mesmo registro no meio tempo, o servidor recusa (conflito) e o app puxa o estado real. */
const VERSAO_FRONT_ = { editarProduto:()=>produtos, editarCombo:()=>combos, editarAdicional:()=>adicionais, editarFormaPagamento:()=>formasPagamento,
  editarCategoria:()=>categorias, editarDespesa:()=>despesas, editarDespesaRecorrente:()=>despesasRecorrentes, salvarCliente:()=>clientes,
  editarVenda:()=>vendas, editarUsuario:()=>usuarios, salvarEvento:()=>eventos };
/* ---- Aviso de carregamento (#15) ----
   Toda ação que fala com a planilha mostra um aviso se demorar mais de ~0,4 s. Ações de gravação importantes (venda, pedido, caixa,
   conta da mesa, pagamento...) também travam a tela por trás, para evitar toque duplo. Atualizações em segundo plano ficam de fora. */
/* ITEM 19 — estado da sincronização por versão (var: precisa existir antes de qualquer chamada) */
var _dadosBrutos = null, _versoesLocais = null, _ultimoFullMs = 0;
const API_SILENCIOSAS_ = new Set(['getVersoes','getDadosGrupo','getAll','detectarNovosPedidos','getCardapio','getStatusPedidoPublico','autenticar','verificarSenhaAdmin','getMesaPublica','obterArmazenamentoContingencia','obterChaveContingencia','listarSessoes']);
const API_ROTULOS_ = {
  iniciarVenda:'Registrando a venda…', criarPedidoCardapio:'Enviando seu pedido…', fecharCaixa:'Fechando o caixa…', caixaLiberar:'Liberando o caixa…', abrirCaixa:'Abrindo o caixa…',
  pontoPedidoCriar:'Enviando o pedido…', pontoPedidoDecidir:'Salvando a decisão…', pontoFechamentoSalvar:'Salvando…',
  fecharContaMesa:'Fechando a conta da mesa…', cancelarVenda:'Cancelando a venda…', editarVenda:'Salvando a venda…', pagarDespesa:'Registrando o pagamento…', pagarFuncionario:'Registrando o pagamento…', cancelarMovimentoEvento:'Cancelando o lançamento…', trocaDecidir:'Salvando a decisão…', pontoAjustar:'Salvando o registro…',
  avancarStatusPedido:'Atualizando o pedido…', aceitarPedido:'Aceitando o pedido…', rejeitarPedido:'Recusando o pedido…', fazerBackupAgora:'Fazendo o backup…',
  restaurarBackup:'Restaurando o backup…', fecharPeriodoEntregador:'Fechando o período…', atribuirEntregador:'Atribuindo o entregador…',
  uploadFotoProduto:'Enviando a foto…', uploadFotoCombo:'Enviando a foto…', sincronizarContingenciaAgora:'Sincronizando…', reconciliarContingenciaAgora:'Reconciliando…'
};
const API_TRAVAM_TELA_ = new Set(['iniciarVenda','criarPedidoCardapio','fecharCaixa','abrirCaixa','fecharContaMesa','cancelarVenda','editarVenda','pagarDespesa','pagarFuncionario',
  'avancarStatusPedido','aceitarPedido','rejeitarPedido','fazerBackupAgora','restaurarBackup','fecharPeriodoEntregador','addSangria','resgatarPremioFidelidade','registrarBrinde']);
let _apiAtivas = 0, _apiTravaTela = 0, _apiRotulo = '', _apiTimerAviso = null;
function _carregandoAtualizar_(){
  let el = document.getElementById('apiCarregando');
  if(!el){
    el = document.createElement('div'); el.id = 'apiCarregando';
    el.innerHTML = '<div class="api-car-caixa" role="status" aria-live="polite"><span class="api-car-spin"></span><span id="apiCarregandoTxt">Salvando…</span></div>';
    document.body.appendChild(el);
  }
  const txt = document.getElementById('apiCarregandoTxt'); if(txt) txt.textContent = _apiRotulo || 'Salvando…';
  el.classList.toggle('trava', _apiTravaTela > 0);
  el.classList.toggle('show', _apiAtivas > 0);
}
function _carregandoInicio_(action){
  _apiAtivas++; if(API_TRAVAM_TELA_.has(action)) _apiTravaTela++;
  { const _novoRot = API_ROTULOS_[action] || 'Salvando…'; _apiRotulo = (_apiAtivas > 1 && _apiRotulo && _apiRotulo !== _novoRot) ? 'Salvando…' : _novoRot; } // MELHORIA 6: várias chamadas ao mesmo tempo mostram um rótulo genérico
  if(_apiAtivas === 1){ clearTimeout(_apiTimerAviso); _apiTimerAviso = setTimeout(_carregandoAtualizar_, 400); } else _carregandoAtualizar_();
}
function _carregandoFim_(action){
  _apiAtivas = Math.max(0,_apiAtivas-1); if(API_TRAVAM_TELA_.has(action)) _apiTravaTela = Math.max(0,_apiTravaTela-1);
  if(_apiAtivas === 0){ clearTimeout(_apiTimerAviso); const el = document.getElementById('apiCarregando'); if(el) el.classList.remove('show','trava'); }
  else _carregandoAtualizar_();
}
/* BLOCO 1.2 — "servidor lento" (preventivo). Contava os atrasos da planilha antiga; com o Supabase ele fica desligado
   (servidorLento_ responde sempre "não") e a queda do servidor é tratada pelo modo reserva (app-18). Mantido porque o Caixa e o
   cardápio ainda consultam servidorLento_. */
let _timeoutsApi_ = [], _contPreventivoAte_ = 0, _statusPreventivo_ = false;
function _desligarPreventivo_(){ _contPreventivoAte_ = 0; _timeoutsApi_ = []; if(_statusPreventivo_){ _statusPreventivo_ = false; if(conexaoAtual==='contingencia') setConexaoStatus('online'); } }
function servidorLento_(){ if(_contPreventivoAte_ && Date.now() > _contPreventivoAte_) _desligarPreventivo_(); return Date.now() < _contPreventivoAte_; }
/* Contingência com limite de tempo. O servidor da contingência já descarta id repetido ("Já estava na fila"), então o envio da venda/pedido
   pode ser repetido com o mesmo id. A leitura do espelho e o status não repetem: se falharem, o chamador usa o cache ou avisa. */
const TIMEOUT_CONT_ENVIO_MS_ = 20000, TIMEOUT_CONT_LEITURA_MS_ = 15000, TIMEOUT_CONT_REPETICOES_ = 2;
async function fetchContingencia_(opts, ms, repeticoes){
  if(!CONTINGENCIA_API_URL) throw new Error('A planilha de contingência não está configurada neste restaurante.');
  for(let t = 0; ; t++){
    const ctl = new AbortController(); const to = setTimeout(()=>ctl.abort(), ms);
    try{
      const resp = await fetch(CONTINGENCIA_API_URL, Object.assign({}, opts, { signal: ctl.signal }));
      return await resp.json();
    }catch(e){
      if(e && e.name === 'AbortError'){
        if(t < (repeticoes||0)){ await new Promise(r=>setTimeout(r, 1000)); continue; }
        const te = new Error('A contingência demorou para responder'); te.timeout = true; throw te;
      }
      throw e;
    }finally{ clearTimeout(to); }
  }
}
/* ===================================================================================================
   SERVIDOR PRINCIPAL (Supabase): login, leituras, gravações, pedido público do cardápio, mesa (QR), feedback,
   cupons, eventos, fidelidade, ocorrências e precificação. As regras e os limites ficam no banco (funções api_*).
   Reserva: planilha principal (Apps Script). Último recurso: planilha de contingência.
   =================================================================================================== */
const USAR_SUPABASE_ = true;
const SUPABASE_URL_ = (window.RESTAURANTE && window.RESTAURANTE.supabaseUrl) || '';
const SUPABASE_CHAVE_ = (window.RESTAURANTE && window.RESTAURANTE.supabaseChave) || ''; // chave PÚBLICA por desenho (a segurança está nas regras do banco)
const SB_SESSAO_KEY_ = 'texasBurgerSb_v1';
const SB_DOMINIO_ = '@usuarios.texasburger.app';
const SB_DRIVE_FOTO_ = 'https://drive.google.com/uc?export=view&id=';
function sbEmail_(login){ return String(login||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim() + SB_DOMINIO_; }
function sbSessaoLer_(){ try{ return JSON.parse(localStorage.getItem(SB_SESSAO_KEY_)||'null'); }catch(e){ return null; } }
function sbSessaoGravar_(s){ try{ if(s) localStorage.setItem(SB_SESSAO_KEY_, JSON.stringify(s)); else localStorage.removeItem(SB_SESSAO_KEY_); }catch(e){} }
function sbFotoUrl_(id){ return id ? (SB_DRIVE_FOTO_ + id) : ''; }
/* Estado do servidor principal: _sbNivelOk_ fica falso quando o Supabase para de responder (faixa vermelha/laranja). */
let _sbNivelOk_ = true, _sbFaixaBase_ = '';
function sbNivelMarcar_(ok){
  if(_sbNivelOk_ === ok) return; _sbNivelOk_ = ok; sbFaixaTexto_();
}
function sbFaixaTexto_(){
  const d = document.getElementById('sbFaixa'); if(!d) return;
  if(_sbNivelOk_){ d.style.display = 'none'; d.textContent = ''; return; }   // tudo normal: sem faixa
  d.style.background = '#991b1b';
  d.textContent = '⚠️ Sem conexão com o servidor principal' + (_sbFaixaBase_ ? ' · ' + _sbFaixaBase_ : '');
  d.style.display = 'block';
}
/* repetir = nº de novas tentativas em falha de rede/timeout/erro 5xx. Só é usado em LEITURAS (repetir uma gravação poderia duplicar). */
async function sbJson_(url, opts, ms, repetir){
  for(let t = 0; ; t++){
    const ctl = new AbortController(); const to = setTimeout(()=>ctl.abort(), ms || 30000);
    try{
      const r = await fetch(url, Object.assign({}, opts, { signal: ctl.signal }));
      if(r.status >= 500 && t < (repetir||0)){ await new Promise(x=>setTimeout(x, 800 * (t+1))); continue; }
      sbNivelMarcar_(r.status < 500); return r;
    }catch(e){
      if(t < (repetir||0)){ await new Promise(x=>setTimeout(x, 800 * (t+1))); continue; }
      sbNivelMarcar_(false);
      if(e && e.name === 'AbortError'){ const te = new Error('O servidor demorou para responder'); te.timeout = true; throw te; }
      throw e;
    }finally{ clearTimeout(to); }
  }
}
async function sbTokenPassword_(email, senha){
  const r = await sbJson_(SUPABASE_URL_ + '/auth/v1/token?grant_type=password', { method:'POST', headers:{ 'apikey': SUPABASE_CHAVE_, 'Content-Type':'application/json' }, body: JSON.stringify({ email, password: senha }) }, 20000);
  return { status: r.status, corpo: await r.json().catch(()=>({})) };
}
function sbGuardarTokens_(c){ sbSessaoGravar_({ access_token: c.access_token, refresh_token: c.refresh_token, expira: Date.now() + ((c.expires_in||3600) - 60) * 1000 }); try{ if(typeof rtEnviarToken_ === 'function') rtEnviarToken_(c.access_token); }catch(e){} }
let _sbRenovando_ = null;
async function sbRenovar_(){
  if(_sbRenovando_) return _sbRenovando_;
  _sbRenovando_ = (async ()=>{
    const s = sbSessaoLer_(); if(!s || !s.refresh_token) return false;
    try{
      const r = await sbJson_(SUPABASE_URL_ + '/auth/v1/token?grant_type=refresh_token', { method:'POST', headers:{ 'apikey': SUPABASE_CHAVE_, 'Content-Type':'application/json' }, body: JSON.stringify({ refresh_token: s.refresh_token }) }, 20000);
      if(!r.ok) return false;
      sbGuardarTokens_(await r.json()); return true;
    }catch(e){ return false; }
  })().finally(()=>{ _sbRenovando_ = null; });
  return _sbRenovando_;
}
class SbSessaoExpirada_ extends Error {}
/* diagnóstico: registra de onde veio uma "sessão expirada" (no console: diagSessaoLog()). Não altera o comportamento. */
function sbDiagSessao_(origem, action){
  try{
    const log = JSON.parse(sessionStorage.getItem('diagSessaoLog')||'[]');
    log.push({ t:new Date().toISOString(), origem:origem, action:action||'', temSessao:!!sbSessaoLer_() });
    sessionStorage.setItem('diagSessaoLog', JSON.stringify(log.slice(-50)));
    console.warn('[DIAG sessão expirada]', origem, action||'');
  }catch(e){}
}
window.diagSessaoLog = function(){ try{ console.table(JSON.parse(sessionStorage.getItem('diagSessaoLog')||'[]')); }catch(e){} };
/* GET no banco. Com sessao=true usa o login do funcionário; senão, a chave pública (visitante). Páginas de 1000 linhas. */
async function sbSelecionar_(tabela, consulta, sessao){
  const itens = []; let de = 0; const TAM = 1000;
  for(;;){
    let s = sessao ? sbSessaoLer_() : null;
    if(sessao){
      if(!s) throw new SbSessaoExpirada_();
      if(Date.now() > s.expira){ if(!(await sbRenovar_())) throw new SbSessaoExpirada_(); s = sbSessaoLer_(); }
    }
    const url = SUPABASE_URL_ + '/rest/v1/' + tabela + '?' + (consulta ? consulta + '&' : '') + 'select=*' ;
    const cab = { 'apikey': SUPABASE_CHAVE_, 'Authorization': 'Bearer ' + (s ? s.access_token : SUPABASE_CHAVE_), 'Range-Unit': 'items', 'Range': de + '-' + (de + TAM - 1) };
    let r = await sbJson_(url, { headers: cab }, 30000, 2);
    if(r.status === 401 && sessao){ if(!(await sbRenovar_())) throw new SbSessaoExpirada_(); s = sbSessaoLer_(); cab.Authorization = 'Bearer ' + s.access_token; r = await sbJson_(url, { headers: cab }, 30000, 2); if(r.status === 401) throw new SbSessaoExpirada_(); }
    if(!r.ok && r.status !== 206) throw new Error('Falha ao ler ' + tabela + ' (' + r.status + ')');
    const pag = await r.json();
    if(!Array.isArray(pag)) throw new Error('Resposta inesperada do servidor ao ler ' + tabela + '.');   // v1.15: antes, uma resposta que não fosse lista repetia a leitura sem parar
    itens.push.apply(itens, pag);
    if(pag.length < TAM) break; de += TAM;
  }
  return itens;
}
const SB_NOTIF_PADRAO_ = { pedido:['Admin','Operador'], entrega:['Admin','Operador'], estoque:['Admin','Operador','Cozinha'], financeiro:['Admin'], ocorrencia:['Admin','Operador'], sistema:['Admin'], fidelidade:['Admin','Operador'], indicacao:['Admin','Operador'], aniversario:['Admin','Operador'], inativos:['Admin','Operador'] };
const SB_CATEGORIAS_DESPESA_ = ['Insumos','Aluguel','Energia','Água','Gás','Internet/Telefone','Salários','Impostos','Imposto das vendas (DAS)','Manutenção','Marketing','Embalagens','Entregadores','Brindes','Outros'];
function sbDataBr_(iso){ if(!iso) return ''; const d = new Date(iso); if(isNaN(d)) return ''; const p = n=>String(n).padStart(2,'0'); return p(d.getDate())+'/'+p(d.getMonth()+1)+'/'+d.getFullYear()+' '+p(d.getHours())+':'+p(d.getMinutes()); }
function sbCfg_(sistema, chave, padrao){ const x = sistema.find(i=>i.chave===chave); if(!x || x.valor===null || x.valor==='' || x.valor===undefined) return padrao; return x.valor; }
/* Lê tudo que o perfil pode ver (as regras do banco já filtram por perfil) e devolve no MESMO formato que a planilha devolvia. */
async function sbMontarDados_(nivel, chaves){
  const DEPS = { formasPagamento:['formas_pagamento','v_formas_operacional'], categorias:['categorias'], produtos:['produtos'], produtoPrecos:['produto_precos'], produtoIngredientes:['produto_ingredientes','estoque'],
    combos:['combos'], comboPrecos:['combo_precos'], comboItens:['combo_itens'], adicionais:['adicionais'], produtoAdicionais:['produto_adicionais'],
    configCardapio:['sistema'], categoriasDespesa:[], configEntrega:['sistema'], configEstoque:['sistema'], configNotificacoes:['sistema'], metas:['sistema'],
    usuarios:['usuarios'], clientes:['clientes'], promocoes:['promocoes'], estoque:['estoque'], movimentacoesEstoque:['movimentacoes_estoque','estoque','usuarios'], mesas:['v_mesas'],
    sangrias:['sangrias','usuarios'], vendas:['v_vendas'], itensVenda:['v_itens_venda'], pagamentosVenda:['pagamentos_venda'], fidelidade:['v_fidelidade'],
    sessaoCaixa:['v_sessao_aberta'], historicoCaixa:['caixa_sessoes','usuarios'], fechamentosEntrega:['fechamentos_entrega','usuarios'], entregasFechadas:['entregas_fechadas','usuarios'],
    despesas:['despesas'], despesasRecorrentes:['despesas_recorrentes'], ajustesPosVenda:['ajustes_pos_venda','despesas'],
    cupons:['cupons'], eventos:['eventos'], indicacoes:['v_indicacoes'], feedbacks:['feedbacks'], ocorrencias:['v_ocorrencias'], maisPedidos:['v_cardapio_mais_pedidos'] };
  const quer = chaves ? new Set([].concat.apply([], chaves.map(k=>DEPS[k]||[]))) : null;
  const ORDEM = { v_vendas:'order=data_hora,id', v_fidelidade:'order=cliente_id', sistema:'order=chave', movimentacoes_estoque:'order=id', sangrias:'order=id', despesas:'order=data_hora,id', despesas_recorrentes:'order=criada_em,id', ajustes_pos_venda:'order=data_hora,id', cupons:'order=criado_em,id', eventos:'order=data,id', v_indicacoes:'order=data,id', feedbacks:'order=data,id', v_ocorrencias:'order=numero,id', v_cardapio_mais_pedidos:'order=posicao' };
  let _lote = null; // resposta única do banco (api_ler_tabelas); se faltar ou falhar, cai na leitura antiga, tabela por tabela
  const L = (t, q)=> (!quer || quer.has(t) || t === 'usuarios')
    ? ((_lote && _lote[t] !== undefined) ? Promise.resolve(_lote[t]) : sbSelecionar_(t, q || ORDEM[t] || 'order=id', true))
    : Promise.resolve([]);
  // versões dos registros lidas ANTES dos dados: se algo mudar no meio, a versão fica mais antiga que o dado e o pior caso é um aviso de conflito (nunca uma edição perdida)
  let verReg = {};
  if(nivel === 'Admin' || nivel === 'Operador' || nivel === 'Garçom'){
    const todas = SB_CHAVES_VERSAO_.cad.concat(SB_CHAVES_VERSAO_.din), pedir = chaves ? todas.filter(k=>chaves.indexOf(k) !== -1) : todas;
    if(pedir.length){ try{ const rv = await sbRpc_('api_versoes_registros', { p:{ chaves: pedir } }); if(rv && rv.ok === true && rv.versoes) verReg = rv.versoes; }catch(e){ if(e instanceof SbSessaoExpirada_) throw e; } }
  }
  const gestor = (nivel === 'Admin' || nivel === 'Operador'), admin = nivel === 'Admin', operacional = (nivel === 'Garçom' || nivel === 'Cozinha' || nivel === 'Entregador');
  try{ // UMA chamada traz todas as tabelas que este perfil precisa (antes: ~36 requisições)
    const _todas = ['formas_pagamento','v_formas_operacional','categorias','produtos','produto_precos','produto_ingredientes','combos','combo_precos','combo_itens','adicionais','produto_adicionais','sistema','usuarios','promocoes','estoque','v_mesas','clientes','movimentacoes_estoque','sangrias','v_vendas','v_itens_venda','pagamentos_venda','v_fidelidade','v_sessao_aberta','caixa_sessoes','fechamentos_entrega','entregas_fechadas','despesas','despesas_recorrentes','ajustes_pos_venda','cupons','eventos','v_indicacoes','feedbacks','v_ocorrencias','v_cardapio_mais_pedidos'];
    const _lista = _todas.filter(t => (!quer || quer.has(t) || t === 'usuarios') && !(t === 'formas_pagamento' && !gestor) && !(t === 'v_formas_operacional' && gestor));
    const rl = await sbRpc_('api_ler_tabelas', { p:{ tabelas:_lista } });
    if(rl && rl.ok === true && rl.dados) _lote = rl.dados;
  }catch(e){ if(e instanceof SbSessaoExpirada_) throw e; }
  const [formas, formasOp, cats, prods, pprec, ping, combos, cprec, citens, adic, padic, sistema, usuarios, promos, estoque, mesas, clientes, movs, sangrias, vendasDb, itensDb, pagDb, fidDb, sessAb, caixaDb, fechDb, entFechDb, despDb, recDb, ajDb, cupDb, evDb, indDb, fbDb, ocDb, maisEqDb] = await Promise.all([
    (gestor ? L('formas_pagamento') : Promise.resolve([])), (gestor ? Promise.resolve([]) : L('v_formas_operacional','order=ordem')), L('categorias'), L('produtos'), L('produto_precos'), L('produto_ingredientes'), L('combos'), L('combo_precos'),
    L('combo_itens'), L('adicionais'), L('produto_adicionais'), L('sistema'), L('usuarios'), L('promocoes'), L('estoque'), L('v_mesas'), L('clientes'), L('movimentacoes_estoque'), L('sangrias'),
    L('v_vendas'), L('v_itens_venda'), L('pagamentos_venda'), L('v_fidelidade'), L('v_sessao_aberta'), L('caixa_sessoes','order=abertura.desc,id'), L('fechamentos_entrega','order=fechado_em,id'), L('entregas_fechadas','order=id'),
    L('despesas'), L('despesas_recorrentes'), L('ajustes_pos_venda'),
    L('cupons'), L('eventos'), L('v_indicacoes'), L('feedbacks'), L('v_ocorrencias'), L('v_cardapio_mais_pedidos')
  ]);
  if(!usuarios.length){ // quem está logado sempre enxerga ao menos a si mesmo; lista vazia só encerra a sessão se o banco também recusar o token
    let vivo = false;
    try{
      const sv = sbSessaoLer_();
      if(sv){
        const rv = await sbJson_(SUPABASE_URL_ + '/rest/v1/usuarios?select=login&limit=1', { headers:{ apikey:SUPABASE_CHAVE_, Authorization:'Bearer ' + sv.access_token } }, 8000);
        vivo = rv.ok;
      }
    }catch(e){ vivo = false; }
    if(!vivo){ sbDiagSessao_('sbMontarDados_:usuarios-vazio'); throw new SbSessaoExpirada_(); }
  }
  const nomeIng = {}; estoque.forEach(e=>{ nomeIng[e.id] = e.ingrediente; });
  const loginDe = {}; usuarios.forEach(u=>{ loginDe[u.id] = u.login; });
  const semCusto = x=>{ if(!gestor) delete x.custo; return x; };
  const cad = {
    formasPagamento: (formas.length ? formas : formasOp).map((f,i)=>({ id:f.id, nome:f.nome, ativa:f.ativa !== false, visivelCardapio:f.visivel_cardapio !== false, taxaPct:Number(f.taxa_percentual)||0, taxaFixa:Number(f.taxa_fixa)||0, prazoDias:Number(f.prazo_dias)||0, permiteTroco:f.permite_troco, acrescimoPct:Number(f.acrescimo_percentual)||0, acrescimoFixo:Number(f.acrescimo_fixo)||0, precoProprio:f.preco_proprio===true, ordem:Number(f.ordem)||(i+1) })).sort((a,b)=>a.ordem-b.ordem)
      .map(f=> operacional ? { id:f.id, nome:f.nome, ativa:f.ativa, permiteTroco:f.permiteTroco, acrescimoPct:f.acrescimoPct, acrescimoFixo:f.acrescimoFixo, ordem:f.ordem } : f),
    categorias: cats.map(c=>({ id:c.id, nome:c.nome, ativa:c.ativa, ordem:Number(c.ordem)||0 })).sort((a,b)=>a.ordem-b.ordem),
    produtos: prods.map(p=>({ id:p.id, nome:p.nome, descricao:p.descricao||'', categoria:p.categoria_id||'', ativo:p.ativo, fotoId:p.foto_id_principal||'', fotoUrl:sbFotoUrl_(p.foto_id_principal), destaque:p.destaque, premioFidelidade:!!p.premio_fidelidade, premioIndicacao:!!p.premio_indicacao, semDesconto:!!p.sem_desconto, estoqueProprioIngredienteId:p.estoque_proprio_ingrediente_id||'', ordemCardapio:Number(p.ordem_cardapio)||0, preCadastro:!!p.pre_cadastro, origemCadastro:p.origem||'' })),
    produtoPrecos: pprec.map(x=>semCusto({ id:x.id, produtoId:x.produto_id, formaPagamentoId:x.forma_pagamento_id, preco:Number(x.preco), custo:Number(x.custo) })),
    produtoIngredientes: ping.map(x=>({ id:x.id, produtoId:x.produto_id, ingredienteId:x.ingrediente_id, ingredienteNome:nomeIng[x.ingrediente_id]||'', quantidadePorUnidade:Number(x.quantidade_por_unidade) })),
    combos: combos.map(c=>({ id:c.id, nome:c.nome, categoria:c.categoria_id||'', ativo:c.ativo, fotoId:c.foto_id_principal||'', fotoUrl:sbFotoUrl_(c.foto_id_principal), destaque:c.destaque, semDesconto:!!c.sem_desconto, escolhaQtd:Number(c.escolha_qtd)||0, ordemCardapio:Number(c.ordem_cardapio)||0 })),
    comboPrecos: cprec.map(x=>semCusto({ id:x.id, comboId:x.combo_id, formaPagamentoId:x.forma_pagamento_id, preco:Number(x.preco), custo:Number(x.custo) })),
    comboItens: citens.map(x=>({ id:x.id, comboId:x.combo_id, produtoId:x.produto_id, quantidade:Number(x.quantidade), escolha:!!x.escolha })),
    adicionais: adic.map(a=>({ id:a.id, nome:a.nome, preco:Number(a.preco)||0, ativo:a.ativo, ingredienteId:a.ingrediente_id||'', quantidadeDesconto:Number(a.quantidade_descontar)||1 })),
    produtoAdicionais: padic.map(x=>({ id:x.id, produtoId:x.produto_id, adicionalId:x.adicional_id })),
    configCardapio: { kicker: sbCfg_(sistema,'CardapioKicker',kickerPadrao_()), frase: sbCfg_(sistema,'CardapioFrase','Peça pelo cardápio — rápido, sem complicação.'), tempoEntrega: sbCfg_(sistema,'CardapioTempoEntrega','40-60 min'), tempoRetirada: sbCfg_(sistema,'CardapioTempoRetirada','20-30 min'), tempoMesa: sbCfg_(sistema,'CardapioTempoMesa','20-30 min'), faixaPromo: sbCfg_(sistema,'CardapioFaixaPromo',''), precoSugerido: sbCfg_(sistema,'PrecoSugeridoCfg',null),
      fechamento: { ativo: !!(sbCfg_(sistema,'CardapioFechadoManual',{})||{}).ativo, mensagem: (sbCfg_(sistema,'CardapioFechadoManual',{})||{}).mensagem || '', periodos: Array.isArray(sbCfg_(sistema,'CardapioPeriodosFechado',[])) ? sbCfg_(sistema,'CardapioPeriodosFechado',[]) : [] },
      restaurante: { nome: sbCfg_(sistema,'RestauranteNome',''), endereco: sbCfg_(sistema,'RestauranteEndereco',''), telefone: sbCfg_(sistema,'RestauranteTelefone',''), horario: sbCfg_(sistema,'RestauranteHorario',''), redes: sbCfg_(sistema,'RestauranteRedes','') } },
    categoriasDespesa: SB_CATEGORIAS_DESPESA_,
    configEntrega: { taxaPadrao: Number(sbCfg_(sistema,'TaxaEntregaPadrao',0))||0, ajudaDiaria: Number(sbCfg_(sistema,'AjudaDiariaEntregador',0))||0 },
    configEstoque: { bloquear: sbCfg_(sistema,'BLOQUEAR_ESTOQUE_NEGATIVO',false) === true },
    configNotificacoes: (()=>{ const salvo = sbCfg_(sistema,'NotificacoesConfig',null) || {}, o = {}; Object.keys(SB_NOTIF_PADRAO_).forEach(id=>{ const s = salvo[id]; o[id] = { ativo: s ? s.ativo !== false : true, perfis: (s && Array.isArray(s.perfis)) ? s.perfis.filter(p=>['Admin','Operador','Cozinha'].indexOf(p)!==-1) : SB_NOTIF_PADRAO_[id].slice() }; }); return o; })()
  };
  const din = {
    usuarios: usuarios.map(u=>({ login:u.login, nivel:u.nivel, ativo:u.ativo, criadoEm:sbDataBr_(u.criado_em), nome:u.nome||'', telefone:u.telefone||'', id:u.id })),
    logRecentes: [], clientes: clientes.filter(x=>!x.unido_com).map(x=>{ const y = { id:x.id, nome:x.nome, telefone:x.telefone||'', dataNascimento:x.data_nascimento||'', endereco:x.endereco||'', comoConheceu:x.como_conheceu||'', primeiroContato:sbDataBr_(x.primeiro_contato), observacao:x.observacoes||'', preferencias:x.preferencias||'', ifoodId:x.ifood_id||'', origemCadastro:x.origem||'' }; if(nivel==='Garçom') delete y.observacao; return y; }), promocoes: nivel==='Garçom' ? [] : promos.map(p=>({ nome:p.nome, tipo:p.tipo, regra:p.regra_duplicidade, beneficio:p.beneficio, ativa:p.ativa })),
    cupons: cupDb.map(c=>({ id:c.id, codigo:String(c.codigo||'').toUpperCase(), nome:c.nome||'', tipo:c.tipo||'percentual', valor:Number(c.valor)||0, faixas:Array.isArray(c.faixas)?c.faixas:[], regra:(c.regra&&typeof c.regra==='object')?c.regra:null, freteGratis:!!c.frete_gratis, dataInicio:c.data_inicio||'', dataFim:c.data_fim||'', horaInicio:String(c.hora_inicio||'').slice(0,5), horaFim:String(c.hora_fim||'').slice(0,5), limiteTotal:Number(c.limite_total)||0, limitePorCliente:Number(c.limite_por_cliente)||0, valorMinimo:Number(c.valor_minimo)||0, ativa:c.ativa!==false, acumula:!!c.acumula, somenteConta:!!c.somente_conta, clienteId:c.cliente_id||'', mensagem:c.mensagem||'', visivelConta:!!c.visivel_conta, automatico:c.automatico||'', validadeDias:Number(c.validade_dias)||30, criadoEm:sbDataBr_(c.criado_em), excluido:!!c.excluido_em, codigoOriginal:c.codigo_original||'', formasIds:Array.isArray(c.formas_ids)?c.formas_ids.map(String):[] })),
    eventos: evDb.map(e=>({ id:e.id, nome:e.nome||'', tipo:e.tipo||'', data:e.data||'', horaInicio:String(e.hora_inicio||'').slice(0,5), horaFim:String(e.hora_fim||'').slice(0,5), local:e.local||'', contratante:e.contratante||'', telefone:e.telefone||'', status:e.status||'Orçamento', valorContratado:Number(e.valor_contratado)||0, valorRecebido:Number(e.valor_recebido)||0, valorAReceber:Number(e.valor_a_receber)||0, custoTotal:Number(e.custo_total)||0, resultado:Number(e.resultado)||0, observacoes:e.observacoes||'' })),
    indicacoes: indDb.map(i=>({ nomeIndicador:i.nome_indicador||'', telIndicador:i.telefone_indicador||'', nomeIndicado:i.nome_indicado||'', telIndicado:i.telefone_indicado||'', data:sbDataBr_(i.data), resgatado:i.status==='Resgatado', observacao:i.observacoes||'', idIndicador:i.indicador_id||'', idIndicado:i.indicado_id||'' })),
    fidelidade: fidDb.map(f=>({ nome:f.nome||'', telefone:f.telefone||'', carimbos:Number(f.carimbos)||0, premios:Number(f.premios)||0, atualizado:f.atualizado||'', observacao:f.observacao||'', clienteId:f.cliente_id||'' })),
    estoque: estoque.map(e=>{ const y = { id:e.id, nome:e.ingrediente, quantidade:Number(e.quantidade), minimo:Number(e.quantidade_minima), unidade:e.unidade||'un', custo:Number(e.custo_unitario)||0, ativo:e.status!=='Inativo', soCusto:!!e.so_custo }; if(!gestor) delete y.custo; return y; }),
    movimentacoesEstoque: movs.map(m=>({ id:m.id, ingredienteNome:nomeIng[m.ingrediente_id]||'', tipo:m.tipo, quantidade:Number(m.quantidade), qtdAntes:Number(m.qtd_antes), qtdDepois:Number(m.qtd_depois), motivo:m.motivo_referencia||'', usuario:loginDe[m.usuario_id]||'', data:m.data })).sort((a,b)=>new Date(b.data)-new Date(a.data)),
    mesas: mesas.map(m=>({ id:m.id, numero:m.numero, status:m.status||'Livre', capacidade:m.capacidade||'', observacao:m.observacao||'', garcomResponsavel:m.garcom_responsavel||'', chamadoEm: m.chamado_em ? (Date.parse(m.chamado_em)||0) : 0 })).sort((a,b)=>Number(a.numero)-Number(b.numero)),
    feedbacks: fbDb.map(f=>({ id:f.id, vendaId:f.venda_id||'', telefone:f.telefone_cliente||'', nota:Number(f.nota)||0, comentario:f.comentario||'', data:sbDataBr_(f.data), status:f.status||'Novo', clienteId:f.cliente_id||'', origem:f.origem||'formulario', userId:f.user_id||'', resposta:f.resposta||'', respondidoEm:f.respondido_em?sbDataBr_(f.respondido_em):'', respondidoPor:f.respondido_por||'' })),
    ocorrencias: ocDb.map(o=>({ id:o.id, numero:Number(o.numero)||0, data:sbDataBr_(o.data_hora), tipo:o.tipo||'', setor:o.setor||'', vendaId:o.venda_id||'', clienteNome:o.cliente||'', clienteTelefone:o.telefone||'', registradoPor:o.registrado_por||'', responsavel:o.responsavel||'', descricao:o.descricao||'', solucao:o.solucao||'', status:o.status||'Aberta', atualizada:sbDataBr_(o.atualizada_em), historico:Array.isArray(o.historico)?o.historico.join('\n'):String(o.historico||'') })),
    maisPedidos: maisEqDb.map(m=>({ tipo:m.tipo, id:m.id })),
    vendas: vendasDb.map(v=>({ id:v.id, data:sbDataBr_(v.data_hora), timestamp:Date.parse(v.data_hora)||0, clienteNome:v.cliente_nome||'', clienteTelefone:v.cliente_telefone||'', formaPagamento:v.forma_pagamento||'',
      valorTotal:Number(v.valor_total)||0, custoTotal:Number(v.custo_total)||0, status:v.status, motivoCancelamento:v.motivo_cancelamento||'', tipoEntrega:v.tipo_entrega||'Retirada', statusPedido:v.status_pedido||'',
      endereco:v.endereco||'', complemento:v.complemento||'', referencia:v.referencia||'', observacoesEntrega:v.observacoes_entrega||'', preferenciasCliente:v.preferencias_cliente||'',
      timestampPronta:v.pronta_em?Date.parse(v.pronta_em):null, timestampConcluida:v.concluida_em?Date.parse(v.concluida_em):null,
      statusPagamento:v.status_pagamento||'Pago', timestampRecebimento:v.recebido_em?Date.parse(v.recebido_em):null,
      valorOriginal:Number(v.valor_original)||Number(v.valor_total)||0, valorDesconto:Number(v.valor_desconto)||0, acrescimoForma:Number(v.acrescimo_forma)||0, descontoDetalhe:v.desconto_detalhe||'', entregador:v.entregador||'',
      timestampSaiu:v.saiu_em?Date.parse(v.saiu_em):null, origem:v.origem||'Balcão', canal:v.canal||'', mesaId:v.mesa_id||'', mesaNumero:(v.mesa_numero!=null?String(v.mesa_numero):''), taxaEntrega:Number(v.taxa_entrega)||0, fechamentoEntregaId:v.fechamento_entrega_id||'', caixaId:v.caixa_id||'',
      registradoPor:v.registrado_por||'', numero:Number(v.numero)||0, timestampInicioPreparo:v.inicio_preparo_em?Date.parse(v.inicio_preparo_em):null,
      clienteId:v.cliente_id||'', ifoodLocalizador:v.ifood_localizador||'', ifoodLocalizadorAte:v.ifood_localizador_ate?Date.parse(v.ifood_localizador_ate):null }))
      .map(v=>{ if(nivel==='Entregador'||nivel==='Garçom'||nivel==='Cozinha') delete v.custoTotal; if(nivel==='Cozinha'){ delete v.clienteTelefone; delete v.endereco; delete v.complemento; delete v.referencia; } return v; }),
    itensVenda: itensDb.map(i=>{ const y = { id:i.id, vendaId:i.venda_id, produtoId:i.produto_id||'', comboId:i.combo_id||'', descricao:i.descricao||'', quantidade:Number(i.quantidade), valorUnitario:Number(i.valor_unitario), custoUnitario:Number(i.custo_unitario)||0, valorTotalItem:Number(i.valor_total_item), adicionaisIds:i.adicionais_ids||[] }; if(!gestor) delete y.custoUnitario; return y; }),
    pagamentosVenda: pagDb.map(p=>({ id:p.id, vendaId:p.venda_id, forma:p.forma_pagamento, valor:Number(p.valor), taxa:Number(p.taxa_aplicada)||0 })),
    despesas: despDb.map(d=>({ id:d.id, data:sbDataBr_(d.data_hora), timestamp:Date.parse(d.data_hora)||0, descricao:d.descricao||'', valor:Number(d.valor)||0, observacao:d.observacao||'',
      status: d.status==='Cancelada' ? 'Cancelada' : 'Confirmada', motivoCancelamento:d.motivo_cancelamento||'', categoria:d.categoria||'Outros', vencimento:d.vencimento?String(d.vencimento):'',
      situacao: (d.status==='A pagar' || d.situacao==='A pagar') ? 'A pagar' : 'Paga', recorrenteId:d.recorrente_id||'', competencia:d.competencia||'', saiuDoCaixa:d.saiu_do_caixa!==false })),
    despesasRecorrentes: recDb.map(r=>({ id:r.id, descricao:r.descricao||'', categoria:r.categoria||'Outros', valor:Number(r.valor)||0, diaVencimento:Number(r.dia_vencimento)||1, periodicidade:r.periodicidade||'Mensal',
      ativa:r.ativa!==false, observacao:r.observacao||'', inicio:r.inicio?String(r.inicio).slice(0,7):'', termino:r.termino?String(r.termino).slice(0,7):'' })),
    ajustesPosVenda: ajDb.map(a=>{ const dp = despDb.find(x=>x.id===a.despesa_id); return { id:a.id, data:sbDataBr_(a.data_hora), timestamp:Date.parse(a.data_hora)||0, vendaId:a.venda_id, numero:Number(a.pedido_numero)||0,
      clienteNome:a.cliente||'', clienteTelefone:a.telefone||'', tipo:a.tipo, valor:Number(a.valor)||0, motivo:a.motivo||'', detalhe:a.detalhe||'',
      saida: !a.saida ? 'Sem saída de dinheiro' : ((dp && dp.saiu_do_caixa===false) ? 'Fora do caixa' : 'Do caixa'), despesaId:a.despesa_id||'', status:a.status==='Cancelado'?'Cancelado':'Ativo',
      autorizadoPor:loginDe[a.autorizado_por]||'', registradoPor:loginDe[a.registrado_por]||'', motivoCancelamento:a.motivo_cancelamento||'' }; }),
    sangrias: sangrias.map(s=>({ id:s.id, data:sbDataBr_(s.data_hora), timestamp:Date.parse(s.data_hora)||0, valor:Number(s.valor), motivo:s.motivo||'', usuario:loginDe[s.usuario_id]||'' })),
    metas: admin || nivel==='Operador' ? { mensal: Number(sbCfg_(sistema,'MetaMensal',0))||0, diaria: Number(sbCfg_(sistema,'MetaDiaria',0))||0 } : { mensal:0, diaria:0 },
    sessaoCaixa: sessAb.length ? { id:sessAb[0].id, abertura:sbDataBr_(sessAb[0].abertura), aberturaTimestamp:Date.parse(sessAb[0].abertura)||0, fundoCaixa:Number(sessAb[0].fundo_caixa)||0, status:'Aberto', usuarioAbertura:sessAb[0].usuario_abertura||'',
      venceEm:Date.parse(sessAb[0].vence_em)||0, avisoHoras:Number(sessAb[0].aviso_horas)||2, liberadoAte:Date.parse(sessAb[0].liberado_ate)||0, liberadoPor:sessAb[0].liberado_por||'', liberadoMotivo:sessAb[0].liberado_motivo||'' } : null,
    historicoCaixa: caixaDb.map(r=>({ id:r.id, abertura:sbDataBr_(r.abertura), aberturaTimestamp:Date.parse(r.abertura)||0, fundoCaixa:Number(r.fundo_caixa)||0, fechamento:r.fechamento?sbDataBr_(r.fechamento):'', fechamentoTimestamp:r.fechamento?Date.parse(r.fechamento):null,
      totalVendas:Number(r.total_vendas)||0, totalDespesas:Number(r.total_despesas)||0, saldoFinal:Number(r.saldo_final)||0, status:r.status, usuarioAbertura:loginDe[r.usuario_abertura]||'', usuarioFechamento:loginDe[r.usuario_fechamento]||'',
      valorContado:r.valor_contado===null||r.valor_contado===undefined?null:Number(r.valor_contado), diferenca:r.diferenca===null||r.diferenca===undefined?null:Number(r.diferenca), reconciliadasQtd:0, reconciliadoDinheiro:0, fechamentoAtrasado:r.fechamento_atrasado===true, fechamentoMotivo:r.fechamento_motivo||'' })), fechamentosEntrega: fechDb.map(f=>({ id:f.id, dataRef:String(f.data_ref), entregador:loginDe[f.entregador_id]||'', qtd:Number(f.qtd_entregas)||0, totalTaxas:Number(f.total_taxas)||0, ajudaDiaria:Number(f.ajuda_diaria)||0, totalDevido:Number(f.total_devido)||0, valorPago:Number(f.valor_pago)||0, diferenca:Number(f.diferenca)||0, fechadoEm:sbDataBr_(f.fechado_em), fechadoPor:loginDe[f.fechado_por]||'', observacao:f.observacao||'', requisicaoId:f.requisicao_id||'', formaPagamento:f.forma_pagamento||'' })), entregasFechadas: entFechDb.map(f=>({ id:f.id, fechamentoId:f.fechamento_id, vendaId:f.venda_id, dataRef:String(f.data_ref), entregador:loginDe[f.entregador_id]||'', taxa:Number(f.taxa)||0 }))
  };
  [['cad', cad], ['din', din]].forEach(([g, obj])=>{ SB_CHAVES_VERSAO_[g].forEach(k=>{ const m = verReg[k]; if(m && Array.isArray(obj[k])) obj[k].forEach(x=>{ if(x && m[x.id]) x._v = m[x.id]; }); }); });
  return { cad, din };
}
/* FASE 3 / itens 4 e 5 do plano de correção — VERSÕES
   1) O banco mantém 2 carimbos (cad = cadastros, din = movimento) que sobem a cada gravação confirmada; a sincronização em segundo plano só baixa quando eles mudam.
   2) Cada registro editável recebe _v (carimbo do conteúdo); toda edição devolve a _v que a pessoa estava vendo e o banco recusa se outra pessoa mexeu antes. */
async function sbVersoes_(){
  try{ const r = await sbRpc_('api_versoes', {}); if(r && r.ok === true && r.cad !== undefined && r.din !== undefined) return { cad:String(r.cad), din:String(r.din) }; }
  catch(e){ if(e instanceof SbSessaoExpirada_) throw e; }
  return null;
}
function sbVersoesDesconhecidas_(){ const x = 'x' + Date.now(); return { cad:x, din:x }; } // banco não respondeu: valor sempre diferente, força baixar tudo (seguro)
const SB_CHAVES_VERSAO_ = { cad:['produtos','combos','adicionais','formasPagamento','categorias'], din:['clientes','cupons','eventos','despesas','despesasRecorrentes','usuarios','vendas'] };
/* ações que mudam dados "filhos" (preços, adicionais) e, por isso, a versão de um registro que a resposta não devolve: a tela se atualiza sozinha logo depois */
const SB_REFRESH_APOS_ = new Set(['addFormaPagamento','vincularAdicionaisEmLote','desvincularAdicionaisEmLote','excluirAdicional','aplicarPrecoCalculadora']);
function sbAnexarVersao_(action, payload){ // como a planilha fazia: a edição leva a versão (_v) que a pessoa estava vendo
  try{
    if(!VERSAO_FRONT_[action] || !payload || payload.versaoEsperada !== undefined) return payload;
    const chave = payload.id || (action === 'editarUsuario' ? payload.loginAlvo : '');
    if(!chave) return payload;
    const atual = (VERSAO_FRONT_[action]() || []).find(x=>(payload.id ? x.id === payload.id : String(x.login).toLowerCase() === String(chave).toLowerCase()));
    if(atual && atual._v) return Object.assign({}, payload, { versaoEsperada: atual._v });
  }catch(e){}
  return payload;
}
async function sbCardapioPublico_(){
  const P = (t, ordem)=>sbSelecionar_(t, 'order=' + ordem, false); // ordem fixa: a leitura em páginas não pode repetir nem pular linhas
  const [cats, prods, combos, formas, citens, precos, adic, cfg, st, maisDb, esgDb] = await Promise.all([
    P('v_cardapio_categorias','id'), P('v_cardapio_produtos','id'), P('v_cardapio_combos','id'), P('v_cardapio_formas','id'), P('v_cardapio_combo_itens','combo_id,produto_id'),
    P('v_cardapio_precos','tipo,item_id,forma_pagamento_id'), P('v_cardapio_adicionais','produto_id,adicional_id'), P('v_cardapio_config','chave'),
    P('v_cardapio_status','caixa_aberto').catch(()=>sbSelecionar_('v_cardapio_status','order=caixa_aberto',false)).catch(()=>[{ caixa_aberto:true }]),   // se a leitura do status falhar, não finge "fechado": o servidor confere o caixa quando o pedido é enviado
   
    P('v_cardapio_mais_pedidos','posicao').catch(()=>[]), P('v_cardapio_esgotados','tipo,id').catch(()=>[])
  ]);
  const cfgv = {}; cfg.forEach(c=>{ cfgv[c.chave] = c.valor; });
  if(cfgv.MANUTENCAO) return { ok:false, manutencao:true, message: String(cfgv.MANUTENCAO.mensagem || cfgv.MANUTENCAO) };
  const vistos = {}, adicionais = [], produtoAdicionais = [];
  adic.forEach(a=>{ if(!vistos[a.adicional_id]){ vistos[a.adicional_id] = 1; adicionais.push({ id:a.adicional_id, nome:a.nome, preco:Number(a.preco) }); } produtoAdicionais.push({ produtoId:a.produto_id, adicionalId:a.adicional_id }); });
  return {
    ok: true,
    categorias: cats.map(c=>({ id:c.id, nome:c.nome, ativa:true, ordem:Number(c.ordem)||0 })).sort((a,b)=>a.ordem-b.ordem),
    produtos: prods.sort((a,b)=>(a.ordem_cardapio||0)-(b.ordem_cardapio||0)).map(p=>({ id:p.id, nome:p.nome, descricao:p.descricao||'', categoria:p.categoria_id||'', fotoUrl:sbFotoUrl_(p.foto_id_principal), destaque:p.destaque, semDesconto:!!p.sem_desconto })),
    combos: combos.sort((a,b)=>(a.ordem_cardapio||0)-(b.ordem_cardapio||0)).map(c=>({ id:c.id, nome:c.nome, categoria:c.categoria_id||'', fotoUrl:sbFotoUrl_(c.foto_id_principal), destaque:c.destaque, semDesconto:!!c.sem_desconto, escolhaQtd:Number(c.escolha_qtd)||0 })),
    formasPagamento: formas.sort((a,b)=>(a.ordem||0)-(b.ordem||0)).map(f=>({ id:f.id, nome:f.nome, ativa:true, visivelCardapio:true, acrescimoPct:Number(f.acrescimo_percentual)||0, acrescimoFixo:Number(f.acrescimo_fixo)||0 })),
    produtoPrecos: precos.filter(x=>x.tipo==='produto').map(x=>({ produtoId:x.item_id, formaPagamentoId:x.forma_pagamento_id, preco:Number(x.preco) })),
    comboPrecos: precos.filter(x=>x.tipo==='combo').map(x=>({ comboId:x.item_id, formaPagamentoId:x.forma_pagamento_id, preco:Number(x.preco) })),
    adicionais, produtoAdicionais,
    comboItens: citens.map(x=>({ comboId:x.combo_id, produtoId:x.produto_id, quantidade:Number(x.quantidade)||1, escolha:!!x.escolha })),
    config: { kicker: cfgv.CardapioKicker || kickerPadrao_(), frase: cfgv.CardapioFrase || 'Peça pelo cardápio — rápido, sem complicação.', tempoEntrega: cfgv.CardapioTempoEntrega || '40-60 min', tempoRetirada: cfgv.CardapioTempoRetirada || '20-30 min', tempoMesa: cfgv.CardapioTempoMesa || '20-30 min', faixaPromo: cfgv.CardapioFaixaPromo || '', taxaEntrega: Number(cfgv.TaxaEntregaPadrao)||0, restaurante: { nome: cfgv.RestauranteNome||'', endereco: cfgv.RestauranteEndereco||'', telefone: cfgv.RestauranteTelefone||'', horario: cfgv.RestauranteHorario||'', redes: cfgv.RestauranteRedes||'' } },
    maisPedidos: maisDb.map(m=>({ tipo:m.tipo, id:m.id })), caixaAberto: !!(st[0] && st[0].caixa_aberto), cardapioBloqueio: (st[0] && st[0].cardapio_bloqueio) || '',
    esgotados: { produtos: esgDb.filter(x=>x.tipo==='produto').map(x=>x.id), combos: esgDb.filter(x=>x.tipo==='combo').map(x=>x.id) }
  };
}

/* ---------- GRAVAÇÕES (3b): chamam as funções api_* do banco e devolvem as listas atualizadas, como a planilha fazia ---------- */
const SB_ESCRITAS_ = {
  addFormaPagamento:['formasPagamento','produtoPrecos','comboPrecos'], editarFormaPagamento:['formasPagamento'],
  addCategoria:['categorias'], editarCategoria:['categorias'], excluirCategoria:['categorias'],
  addIngrediente:['estoque','movimentacoesEstoque'], editarIngrediente:['estoque','movimentacoesEstoque','produtoPrecos','comboPrecos','produtoIngredientes'], excluirIngrediente:['estoque'],
  pagarFuncionario:['despesas'], cancelarPagamentoFuncionario:['despesas'], ajustarPrecosProdutosLote:['produtos','produtoPrecos','comboPrecos'], visibilidadeLoteProdutos:['produtos'],
  salvarPrecosLote:['estoque','produtoPrecos','comboPrecos','produtoIngredientes','adicionais'],
  addAdicional:['adicionais'], editarAdicional:['adicionais'], excluirAdicional:['adicionais','produtoAdicionais'], vincularAdicionaisEmLote:['produtoAdicionais'], desvincularAdicionaisEmLote:['produtoAdicionais'],
  registrarBrinde:['fidelidade','indicacoes','estoque','movimentacoesEstoque'], editarPremioProduto:['produtos'], editarSemDesconto:['produtos','combos'],
  addProduto:['produtos','produtoPrecos','produtoIngredientes','produtoAdicionais','estoque','comboPrecos'], editarProduto:['produtos','produtoPrecos','produtoIngredientes','produtoAdicionais','estoque','comboPrecos'],
  excluirProduto:['produtos','produtoPrecos','produtoIngredientes'], editarVisibilidadeCardapioProduto:['produtos'], editarOrdemCardapioProduto:['produtos'],
  addCombo:['combos','comboPrecos','comboItens'], editarCombo:['combos','comboPrecos','comboItens'], excluirCombo:['combos','comboPrecos','comboItens'],
  editarVisibilidadeCardapioCombo:['combos'], editarOrdemCardapioCombo:['combos'],
  addMesa:['mesas'], editarStatusMesa:['mesas'], excluirMesa:['mesas'], atenderChamadoMesa:['mesas'],
  salvarConfigNotificacoes:{ config:'configNotificacoes' }, salvarConfigEstoque:{ configEstoque:'configEstoque' }, salvarConfigCardapio:{ config:'configCardapio' }, salvarCardapioFechamento:{ config:'configCardapio' }, salvarDadosRestaurante:{ config:'configCardapio' },
  salvarConfigEntrega:{ configEntrega:'configEntrega' }, salvarMeta:{ metas:'metas' }, salvarCliente:['clientes'],
  criarUsuario:['usuarios'], editarUsuario:['usuarios'], excluirUsuario:['usuarios'], excluirCliente:['clientes'], unirClientes:['clientes','fidelidade','vendas','indicacoes'], desunirCliente:['clientes','fidelidade','vendas','indicacoes'],
  registrarEntradaEstoque:['estoque','movimentacoesEstoque','produtoPrecos','comboPrecos'], registrarPerdaEstoque:['estoque','movimentacoesEstoque'], registrarPerdaProduto:['estoque','movimentacoesEstoque'], registrarInventarioEstoque:['estoque','movimentacoesEstoque'],
  addSangria:['sangrias'],
  fecharContaMesa:['vendas','itensVenda','pagamentosVenda','mesas','fidelidade','clientes'], fecharPeriodoEntregador:['vendas','fechamentosEntrega','entregasFechadas','despesas'],
  abrirCaixa:['sessaoCaixa'], cancelarVenda:['vendas','estoque'], editarVenda:['vendas','itensVenda','pagamentosVenda'],
  iniciarVenda:['vendas','itensVenda','pagamentosVenda','fidelidade','clientes','estoque','mesas'],
  aceitarPedido:['vendas','itensVenda','pagamentosVenda'], iniciarPreparoPedido:['vendas','itensVenda','pagamentosVenda'], avancarStatusPedido:['vendas','itensVenda','pagamentosVenda'], suspenderPedido:['vendas','itensVenda','pagamentosVenda'], retomarPedido:['vendas','itensVenda','pagamentosVenda'],
  atribuirEntregador:['vendas','itensVenda','pagamentosVenda'], confirmarRecebimentoPedido:['vendas','itensVenda','pagamentosVenda','fidelidade','clientes'], rejeitarPedido:['vendas','itensVenda','pagamentosVenda','estoque'],
  addDespesa:['despesas'], editarDespesa:['despesas'], pagarDespesa:['despesas'], cancelarDespesa:['despesas'], gerarDespesasMes:['despesas'],
  addDespesaRecorrente:['despesasRecorrentes','despesas'], editarDespesaRecorrente:['despesasRecorrentes','despesas'],
  registrarAjustePosVenda:['ajustesPosVenda','despesas'], cancelarAjustePosVenda:['ajustesPosVenda','despesas'],
  salvarCupom:['cupons'], editarCupom:['cupons'], alternarCupom:['cupons'],
  registrarCompra:['estoque','movimentacoesEstoque','despesas','produtoPrecos','comboPrecos'], receberCompra:['estoque','movimentacoesEstoque','despesas','produtoPrecos','comboPrecos'], estornarCompra:['estoque','movimentacoesEstoque','despesas','produtoPrecos','comboPrecos'],
  salvarEvento:['eventos'], cancelarEvento:['eventos'], adicionarCustoEvento:['eventos'], adicionarRecebimentoEvento:['eventos'],
  addOrStampFidelidade:['fidelidade'], resgatarPremioFidelidade:['fidelidade'], indicarNovoCliente:['clientes','indicacoes','fidelidade'], toggleResgateIndicacao:['indicacoes'],
  registrarOcorrencia:['ocorrencias'], atualizarOcorrencia:['ocorrencias'], editarStatusFeedback:['feedbacks'], responderFeedback:['feedbacks'],
  aplicarPrecoCalculadora:['produtoPrecos']
};
/* chamadas que só pedem ao banco e devolvem a resposta dele como está (sem reler as listas) */
const SB_RPC_DIRETO_ = ['pontoMeusRegistros','pontoPedidoCriar','pontoPedidosLista','pontoPedidoFoto','pontoPedidoDecidir','pontoFechamento','pontoFechamentoSalvar','rotaEntrega','ifoodFinDados','ifoodFinAcao','ipPagamentos','ipReembolso','ipGerarSegredo','pagFormaProvedor','ifoodModulos','ifoodMotivos','ifoodMotivoEscolher','ifoodCodigosPendentes','ifoodCodigo','armazenamentoPainel','cardapioHoje','excluirCupom','errosSistema','ifoodItensExcluir','ifoodMarcarTeste','ifoodPreCadastro','ifoodTestar','ifoodConferencia','ifoodRastreios','marcarAparelhoEquipe','margemSugestao','margemIgnorar','precoHistorico','margemAlerta','margemConfigSalvar','estoqueSugestao','eventoHorasSalvar','eventoRendimento','escalaAvisar','trocaSolicitar','trocaResponder','trocaDecidir','trocasLista','pontoEstado','pontoLocal','pontoRostoConfig','pontoRostoApagar','pontoAprovar','evidenciasLista','etiquetasLista','etiquetaSalvar','etiquetaImportarEstoque','etiquetaRegistrar','pontoBater','pontoRelatorio','pontoAjustar','equipePesoMaoObra','equipeReserva','espacoHistorico','eventoMovimentos','cancelarMovimentoEvento','escalaSemana','salvarTurno','escalaPadraoSalvar','escalaAplicarPadrao','escalaCopiarSemana','equipeImportarAcessos','minhaEscala','equipeFolha','salvarFuncionario','editarCompraInfo','lgpdConfig','listarReembolsos','confirmarReembolso','listarChavesIa','verChaveIa','salvarChaveIa','salvarIaExtras','integracoesFlags','integracoesStatus','integracoesMarcar','integracoesConfig','integracoesSalvarSegredo','integracoesVerSegredo','integracoesLigar','integracoesDesligar','integracoesLog','mpFormaOnline','mpPagamentosRecentes','mpPendenciasDecisao','mpResumoOperacional','mpDecidirPagamento','fiscalEmpresaLer','fiscalEmpresaSalvar','fiscalPerfis','fiscalPerfilSalvar','fiscalPerfilExcluir','fiscalAtribuir','fiscalSemPerfil','fiscalExportar','fiscalImportar','nfceLista','nfceReemitir','nfceEmitirVenda','nfceCpf','nfceSimular','nfceConferencia','nfceInutilizar','nfcePacote','ifoodPedidos','ifoodItens','ifoodPrecos','ifoodPrecosPedirCatalogo','ifoodPrecosAplicar','ifoodPrecosEnviar','ifoodPrecosDesfazer','ifoodFinanceiro','ifoodAvaliacoes','ifoodAvaliacaoResponder','ifoodRelatorio','ifoodLoja','ifoodLojaAcao','ifoodNegociacoes','ifoodNegociacaoResponder','ifoodAvisos','ifoodAvisoVisto','ifoodCatDiag','ifoodCatDiagPedir','ifoodShipConfig','ifoodShipLista','ifoodShipCotar','ifoodShipChamar','ifoodShipMotivos','ifoodShipCancelar','ifoodShipEndereco','ifoodShipSafe','ifoodBiLer','ifoodBiBuscar','ifoodLigarItem','clienteIfoodInfo','geoEnderecoSalvar','ifoodHorario','ifoodHorarioSalvar','ifoodHorarioLer','ifoodCat','ifoodCatSalvar','ifoodCatExcluir','ifoodCatEnviar','ifoodCatLote','ifoodLacunas','ifoodReprocessar','ifoodSimular','listarContas','salvarConta','excluirConta','verSenhaConta','saudeSistema','pushInscrever','pushCancelar','listarAuditoria','listarCompras','salvarFornecedor','cancelarCompra','listarSessoes','encerrarSessaoRemota','verificarSenhaAdmin','trocarMinhaSenha','fecharCaixa','caixaLiberar','caixaSalvarConfig','caixaConfig','previewFechamentoEntrega','getQrMesas','gerarNovoCodigoMesa','detectarNovosPedidos','simularPrecificacao','salvarAliquotaMes','visitasCardapioHoje'];
function sbNomeFuncao_(action){ return 'api_' + action.replace(/[A-Z]/g, m=>'_' + m.toLowerCase()); }
async function sbRpc_(fn, corpo){
  let s = sbSessaoLer_(); if(!s) throw new SbSessaoExpirada_();
  if(Date.now() > s.expira){ if(!(await sbRenovar_())) throw new SbSessaoExpirada_(); s = sbSessaoLer_(); }
  const chamar = ()=>sbJson_(SUPABASE_URL_ + '/rest/v1/rpc/' + fn, { method:'POST', headers:{ 'apikey': SUPABASE_CHAVE_, 'Authorization': 'Bearer ' + s.access_token, 'Content-Type':'application/json' }, body: JSON.stringify(corpo) }, 30000);
  let r = await chamar();
  if(r.status === 401){ if(!(await sbRenovar_())) throw new SbSessaoExpirada_(); s = sbSessaoLer_(); r = await chamar(); if(r.status === 401) throw new SbSessaoExpirada_(); }
  const j = await r.json().catch(()=>null);
  if(!r.ok) return { ok:false, message:'Não foi possível salvar' + (j && j.message ? ' (' + j.message + ')' : ' (erro ' + r.status + ')') + '. Nada foi gravado.' };
  return j && typeof j === 'object' ? j : { ok:false, message:'Resposta inesperada do servidor.' };
}
const SB_IDEM_NOVAS_ = ['pagarFuncionario','registrarCompra','addDespesa','pagarDespesa','registrarAjustePosVenda','cancelarAjustePosVenda','registrarBrinde','addSangria','registrarEntradaEstoque','registrarPerdaEstoque','registrarPerdaProduto','registrarInventarioEstoque','resgatarPremioFidelidade','toggleResgateIndicacao']; // o banco já devolve a resposta guardada se o mesmo pedido chegar duas vezes
async function sbEscrever_(action, payload){
  const mapa = SB_ESCRITAS_[action];
  let chaveIdem = '';
  if(SB_IDEM_NOVAS_.indexOf(action) !== -1 && !(payload && payload.requisicaoId)){ try{ chaveIdem = idemChave_(action, payload); payload = Object.assign({}, payload, { requisicaoId: idemId_(chaveIdem) }); }catch(e){ chaveIdem = ''; } }
  payload = sbAnexarVersao_(action, payload);
  const r = await sbRpc_(sbNomeFuncao_(action), { p: payload || {} });
  if(chaveIdem && r && (r.ok === true || r.ok === false)) idemLimpar_(chaveIdem);
  if(!r || (r.ok !== true && !r.conflito)) return r; // no conflito também devolve o estado atual (como a planilha fazia)
  const { cad, din } = await sbMontarDados_(currentUser ? currentUser.nivel : '', Array.isArray(mapa) ? mapa : Object.keys(mapa).map(k=>mapa[k]));
  const todos = Object.assign({}, cad, din);
  if(Array.isArray(mapa)) mapa.forEach(k=>{ r[k] = todos[k]; });
  else Object.keys(mapa).forEach(k=>{ r[k] = todos[mapa[k]]; });
  return r;
}
/* 4a — AÇÕES PÚBLICAS DO CARDÁPIO (sem login): o cliente fala com o banco só pela chave pública; preços, total, cupom e limites são decididos no servidor. */
const SB_PUBLICAS_ = { criarPedidoCardapio:'api_criar_pedido_cardapio', getStatusPedidoPublico:'api_get_status_pedido_publico', cancelarPedidoCardapioPublico:'api_cancelar_pedido_cardapio_publico', validarCupomCardapio:'api_validar_cupom_cardapio',
  getMesaPublica:'api_get_mesa_publica', criarPedidoMesa:'api_criar_pedido_mesa', cancelarPedidoMesa:'api_cancelar_pedido_mesa', pedirContaMesa:'api_pedir_conta_mesa', chamarGarcomMesa:'api_chamar_garcom_mesa', addFeedback:'api_add_feedback' };
/* chat público: falha de rede vira resposta de erro (antes travava todos os botões do chat) */
function chatRpcSeguro_(fn, corpo){ return sbRpcPublico_(fn, corpo).catch(()=>({ ok:false, message:'Sem conexão agora. Confira a internet e tente de novo.' })); }
async function sbRpcPublico_(fn, corpo){
  /* as RPCs chat_* do banco recebem um único parâmetro jsonb chamado "p": sem esse envelope o PostgREST responde 404 */
  if(/^chat_/.test(fn) && corpo && typeof corpo === 'object' && !Array.isArray(corpo) && !('p' in corpo)) corpo = { p: corpo };
  /* cliente com conta: o pedido e o cupom vão com a sessão dele (o banco sabe quem é). Se a sessão não valer mais, repete como visitante. */
  let bearer = SUPABASE_CHAVE_, comConta = false;
  if((fn === 'api_criar_pedido_cardapio' || fn === 'api_validar_cupom_cardapio' || fn === 'api_add_feedback') && window.contaTokenOuNull_){ try{ const t = await window.contaTokenOuNull_(); if(t){ bearer = t; comConta = true; } }catch(e){} }
  const enviar = ()=>sbJson_(SUPABASE_URL_ + '/rest/v1/rpc/' + fn, { method:'POST', headers:{ 'apikey': SUPABASE_CHAVE_, 'Authorization': 'Bearer ' + bearer, 'Content-Type':'application/json' }, body: JSON.stringify(corpo) }, 30000);
  let r = await enviar();
  if(r.status === 401 && comConta){ try{ window.contaDesativarSessao_(); }catch(e){} bearer = SUPABASE_CHAVE_; comConta = false; r = await enviar(); }
  const j = await r.json().catch(()=>null);
  if(!r.ok) return { ok:false, message:'Não foi possível concluir agora (erro ' + r.status + '). Tente novamente em instantes.' };
  return j && typeof j === 'object' ? j : { ok:false, message:'Resposta inesperada do servidor.' };
}
const SB_NAO_MIGRADA_ = 'Esta ação não está disponível. Nada foi gravado.';
/* Roteador: devolve a resposta no formato antigo, ou undefined se a ação não for tratada aqui (não acontece com o Supabase ligado). */
let _sbDespMes_ = '';
async function sbGarantirDespesasMes_(){ // faz o papel do gatilho diário da planilha: o banco só gera 1x por mês, então a chamada é barata
  const mes = new Date().toISOString().slice(0,7); if(_sbDespMes_ === mes) return;
  const r = await sbRpc_('api_garantir_despesas_do_mes', { p:{} }); if(r && r.ok === true) _sbDespMes_ = mes;
}
async function sbRotear_(action, payload){
  try{
    if(action === 'autenticar'){
      const login = String(payload.login||'').trim();
      const t = await sbTokenPassword_(sbEmail_(login), payload.senha);
      if(t.status === 400 || t.status === 401 || t.status === 422){ sbRpcPublico_('api_registrar_falha_login', { p:{ login } }).catch(()=>{}); }   // registra a tentativa (com o IP, no servidor)
      if(t.status !== 200 || !t.corpo.access_token) return { ok:false, message: (t.status===429 ? 'Muitas tentativas erradas. Aguarde alguns minutos e tente de novo.' : 'Login ou senha incorretos.') };
      sbGuardarTokens_(t.corpo);
      const r = await sbJson_(SUPABASE_URL_ + '/rest/v1/usuarios?select=login,nivel,ativo&id=eq.' + encodeURIComponent(t.corpo.user.id), { headers:{ 'apikey': SUPABASE_CHAVE_, 'Authorization': 'Bearer ' + t.corpo.access_token } }, 20000);
      const linhas = r.ok ? await r.json() : [];
      if(!linhas.length){ sbSessaoGravar_(null); return { ok:false, message:'Login ou senha incorretos.' }; }
      if(!linhas[0].ativo){ sbSessaoGravar_(null); return { ok:false, message:'Este acesso está desativado.' }; }
      sbRpc_('api_registrar_acesso', { p:{} }).catch(()=>{}); pushReinscreverSilencioso_();   // registra o acesso (IP e aparelho são lidos no servidor)
      return { ok:true, login: linhas[0].login, nivel: linhas[0].nivel, token: t.corpo.access_token };
    }
    if(action === 'encerrarSessao'){
      const s = sbSessaoLer_(); if(s) pushSairLocal_(s); sbSessaoGravar_(null);
      if(s) sbJson_(SUPABASE_URL_ + '/auth/v1/logout', { method:'POST', headers:{ 'apikey': SUPABASE_CHAVE_, 'Authorization': 'Bearer ' + s.access_token } }, 8000).catch(()=>{});
      return { ok:true };
    }
    if(SB_PUBLICAS_[action]) return await sbRpcPublico_(SB_PUBLICAS_[action], { p: payload || {} });
    if(action === 'getCardapio') return await sbCardapioPublico_();
    if(action === 'getVersoes') return Object.assign({ ok:true }, (await sbVersoes_()) || sbVersoesDesconhecidas_());
    if(action === 'getAll' || action === 'getDadosGrupo'){
      const nivel = currentUser ? currentUser.nivel : '';
      { const s0 = sbSessaoLer_(); if(s0 && Date.now() > s0.expira){ await sbRenovar_(); } } // renova antes, para as duas chamadas abaixo não renovarem ao mesmo tempo
      const [, verAntesBruto] = await Promise.all([
        (nivel === 'Admin' || nivel === 'Operador') ? sbGarantirDespesasMes_().catch(e=>{ if(e instanceof SbSessaoExpirada_) throw e; }) : Promise.resolve(),
        sbVersoes_()
      ]);
      const verAntes = verAntesBruto || sbVersoesDesconhecidas_(); // carimbo lido ANTES dos dados: se algo mudar no meio, a próxima checagem baixa de novo
      const { cad, din } = await sbMontarDados_(nivel);
      const gestor = (nivel === 'Admin' || nivel === 'Operador');
      const grupo = (gestor && action === 'getDadosGrupo') ? (payload.grupo === 'cad' ? 'cad' : 'din') : '';
      const dados = Object.assign({ ok:true }, grupo === 'din' ? {} : cad, grupo === 'cad' ? {} : din);
      dados.versoes = Object.assign({}, verAntes); if(grupo) dados.grupo = grupo;
      return dados;
    }
    if(SB_ESCRITAS_[action]) return await sbEscrever_(action, payload);
    if(SB_RPC_DIRETO_.indexOf(action) !== -1){
      const r = await sbRpc_(sbNomeFuncao_(action), { p: payload || {} });
      if(action === 'trocarMinhaSenha' && r && r.ok){ const s = sbSessaoLer_(); if(s) r.token = s.access_token; }
      return r;
    }
    if(action === 'uploadFotoProduto' || action === 'uploadFotoCombo') return await sbUploadFoto_(action, payload);   // (Edge Function → Drive)
    if(action === 'excluirFotoProduto' || action === 'excluirFotoCombo') return await sbRemoverFoto_(action, payload);   // Edge Function remover-foto
    // Contingência e Drive: Edge Function planilha-admin (Admin/Operador logado) → Apps Script da planilha principal
    if(action === 'obterArmazenamento') return await sb410Edge_('planilha-admin', { acao:'armazenamento' }, 90000);
    if(action === 'obterArmazenamentoContingencia') return await sb410Edge_('planilha-admin', { acao:'armazenamentoContingencia' }, 90000);
    if(action === 'sincronizarContingenciaAgora') return await sb410Edge_('planilha-admin', { acao:'sincronizarContingencia' }, 150000);
    if(action === 'reconciliarContingenciaAgora') return await sb410Edge_('planilha-admin', { acao:'reconciliarContingencia' }, 150000);
    if(action === 'obterChaveContingencia') return await sb410Edge_('planilha-admin', { acao:'chaveContingencia' }, 30000);
    return { ok:false, naoMigrada:true, message: SB_NAO_MIGRADA_ };
  }catch(e){
    if(e instanceof SbSessaoExpirada_){ sbDiagSessao_('sbRotear_', action); sbSessaoGravar_(null); return { ok:false, sessaoExpirada:true, message:'Sessão expirada.' }; }
    throw e;
  }
}
function sbFaixa_(){
  if(!USAR_SUPABASE_ || document.getElementById('sbFaixa')) return;
  const d = document.createElement('div'); d.id = 'sbFaixa';
  d.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:9999;background:#b45309;color:#fff;font:600 12px/1.3 system-ui,sans-serif;text-align:center;padding:4px 8px;pointer-events:none;';
  _sbFaixaBase_ = '';
  document.body.appendChild(d); sbFaixaTexto_();
}

async function apiCall(action, payload, _tentativa, _idemChave){
  if(_tentativa !== undefined || API_SILENCIOSAS_.has(action)) return _apiCallRaw(action, payload, _tentativa, _idemChave);
  _carregandoInicio_(action);
  try{ return await _apiCallRaw(action, payload, _tentativa, _idemChave); }
  finally{ _carregandoFim_(action); }
}
/* ITEM 2.8 — tela de manutenção (restauração de backup). O servidor responde { manutencao:true } a todos menos o Admin;
   aqui bloqueamos a tela e perguntamos de tempos em tempos se já voltou. Quando volta, recarrega para pegar os dados restaurados. */
let _manutTimer_ = null;
function mostrarManutencao_(msg){
  if(currentUser && currentUser.nivel === 'Admin') return;
  let ov = document.getElementById('manutencaoOverlay');
  if(!ov){
    ov = document.createElement('div'); ov.id = 'manutencaoOverlay';
    ov.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(11,7,5,.97);display:flex;align-items:center;justify-content:center;text-align:center;padding:24px;';
    ov.innerHTML = '<div style="max-width:360px;"><div style="font-size:48px;">🛠️</div><h2 style="margin:10px 0 6px;color:var(--gold);">Sistema em manutenção</h2><p style="color:var(--cream);margin:0 0 8px;">Estamos restaurando os dados. Aguarde alguns minutos.</p><p class="txt-muted fs-sm sem-margem">Nada foi perdido. Esta tela some sozinha quando terminar.</p></div>';
    document.body.appendChild(ov);
  }
  ov.style.display = 'flex';
  if(!_manutTimer_){
    _manutTimer_ = setInterval(async ()=>{
      try{
        const r = await apiCall(currentUser ? 'getVersoes' : 'getCardapio', {});
        if(r && !r.manutencao){ clearInterval(_manutTimer_); _manutTimer_ = null; location.reload(); }
      }catch(e){ /* sem internet: continua tentando */ }
    }, 12000);
  }
}
/* MODO RESERVA: funções que só existem no Supabase (sem equivalente na planilha). Com o Supabase fora, respondem NA HORA, sem esperar tempo esgotar. */
const RESERVA_INDISPONIVEL_ = { ifoodFinDados:'iFood: vendas e repasses', ifoodFinAcao:'iFood: vendas e repasses', ipPagamentos:'InfinitePay', ipReembolso:'InfinitePay', ipGerarSegredo:'InfinitePay', pagFormaProvedor:'Pagamentos online', ifoodModulos:'Integrações', ifoodMotivos:'Cancelar pedido do iFood', ifoodMotivoEscolher:'Cancelar pedido do iFood', ifoodCodigosPendentes:'Códigos do iFood', ifoodCodigo:'Códigos do iFood', armazenamentoPainel:'Armazenamento', cardapioHoje:'Cardápio hoje', excluirCupom:'Cupons', errosSistema:'Erros do sistema', ifoodItensExcluir:'Integrações', ifoodMarcarTeste:'Integrações', ifoodPreCadastro:'Integrações', editarSemDesconto:'Marcar item sem desconto', salvarIaExtras:'Integrações e contas', visitasCardapioHoje:'Visitas ao cardápio', salvarAliquotaMes:'Imposto sobre vendas', integracoesFlags:'Integrações', integracoesStatus:'Integrações', integracoesMarcar:'Integrações', integracoesConfig:'Integrações', integracoesSalvarSegredo:'Integrações', integracoesVerSegredo:'Integrações', integracoesLigar:'Integrações', integracoesDesligar:'Integrações', integracoesLog:'Integrações', mpFormaOnline:'Integrações', mpPagamentosRecentes:'Integrações', mpPendenciasDecisao:'Caixa e pagamentos online', mpResumoOperacional:'Relatórios de pagamentos online', mpDecidirPagamento:'Caixa e pagamentos online', fiscalEmpresaLer:'Integrações', fiscalEmpresaSalvar:'Integrações', fiscalPerfis:'Integrações', fiscalPerfilSalvar:'Integrações', fiscalPerfilExcluir:'Integrações', fiscalAtribuir:'Integrações', fiscalSemPerfil:'Integrações', fiscalExportar:'Integrações', fiscalImportar:'Integrações', nfceLista:'Integrações', nfceReemitir:'Integrações', nfceEmitirVenda:'Integrações', nfceCpf:'Integrações', nfceSimular:'Integrações', nfceConferencia:'Integrações', nfceInutilizar:'Integrações', nfcePacote:'Integrações', ifoodPedidos:'Integrações', ifoodPrecos:'Integrações', ifoodPrecosPedirCatalogo:'Integrações', ifoodPrecosAplicar:'Integrações', ifoodPrecosEnviar:'Integrações', ifoodPrecosDesfazer:'Integrações', ifoodFinanceiro:'Integrações', ifoodAvaliacoes:'Integrações', ifoodAvaliacaoResponder:'Integrações', ifoodRelatorio:'Integrações', ifoodLoja:'Integrações', ifoodLojaAcao:'Integrações', ifoodNegociacoes:'Integrações', ifoodAvisos:'Integrações', ifoodCatDiag:'Integrações', ifoodCatDiagPedir:'Integrações',ifoodShipConfig:'Integrações',ifoodShipLista:'Integrações',ifoodShipCotar:'Integrações',ifoodShipChamar:'Integrações',ifoodShipMotivos:'Integrações',ifoodShipCancelar:'Integrações',ifoodShipEndereco:'Integrações',ifoodShipSafe:'Integrações',ifoodBiLer:'Integrações',ifoodBiBuscar:'Integrações', ifoodAvisoVisto:'Integrações', ifoodNegociacaoResponder:'Integrações', ifoodItens:'Integrações', ifoodLigarItem:'Integrações', ifoodHorario:'Integrações', ifoodHorarioSalvar:'Integrações', ifoodHorarioLer:'Integrações', ifoodCat:'Integrações', ifoodCatSalvar:'Integrações', ifoodCatExcluir:'Integrações', ifoodCatEnviar:'Integrações', ifoodCatLote:'Integrações', ifoodLacunas:'Aviso de queda do iFood', ifoodReprocessar:'Integrações', ifoodSimular:'Integrações', listarChavesIa:'Contas e acessos', verChaveIa:'Contas e acessos', salvarChaveIa:'Contas e acessos', listarContas:'Contas e acessos', salvarConta:'Contas e acessos', excluirConta:'Contas e acessos', verSenhaConta:'Contas e acessos', saudeSistema:'Saúde do sistema', salvarCardapioFechamento:'Abrir ou fechar o cardápio', listarCompras:'Compras e fornecedores', registrarCompra:'Compras e fornecedores', receberCompra:'Compras e fornecedores', cancelarCompra:'Compras e fornecedores', estornarCompra:'Compras e fornecedores', editarCompraInfo:'Compras e fornecedores', salvarFornecedor:'Compras e fornecedores',
  pontoMeusRegistros:'Meus registros de ponto', pontoPedidoCriar:'Pedido de ponto', pontoPedidosLista:'Pedidos de ponto', pontoPedidoFoto:'Foto do atestado', pontoPedidoDecidir:'Decisão do pedido de ponto', pontoFechamento:'Fechamento do ponto', pontoFechamentoSalvar:'Fechamento do ponto',
  ifoodTestar:'Teste de conexão do iFood', ifoodConferencia:'Conferência dos repasses do iFood', ifoodRastreios:'Entregador do iFood', marcarAparelhoEquipe:'Aparelho da equipe', listarReembolsos:'Reembolsos', confirmarReembolso:'Reembolsos', salvarPrecosLote:'Preços em lote', ajustarPrecosProdutosLote:'Ajuste de preços em lote', precoHistorico:'Histórico de preços', margemAlerta:'Margem baixa', margemConfigSalvar:'Margem baixa', margemIgnorar:'Margem baixa', margemSugestao:'Margem baixa', estoqueSugestao:'Compra sugerida', eventoHorasSalvar:'Eventos', eventoRendimento:'Eventos', equipeFolha:'Equipe e pagamentos', escalaSemana:'Escala', salvarTurno:'Escala', escalaPadraoSalvar:'Escala', escalaAplicarPadrao:'Escala', escalaCopiarSemana:'Escala', equipeImportarAcessos:'Equipe e pagamentos', minhaEscala:'Escala', salvarFuncionario:'Equipe e pagamentos', pagarFuncionario:'Equipe e pagamentos', eventoMovimentos:'Central de Eventos', cancelarMovimentoEvento:'Central de Eventos', escalaAvisar:'Escala da equipe', trocaSolicitar:'Escala da equipe', trocaResponder:'Escala da equipe', trocaDecidir:'Escala da equipe', trocasLista:'Escala da equipe', pontoEstado:'Ponto', pontoBater:'Ponto', pontoLocal:'Ponto', pontoRostoConfig:'Ponto', pontoRostoApagar:'Ponto', pontoAprovar:'Ponto', evidenciasLista:'Fotos dos lançamentos', etiquetasLista:'Etiquetas', etiquetaSalvar:'Etiquetas', etiquetaImportarEstoque:'Etiquetas', etiquetaRegistrar:'Etiquetas', pontoRelatorio:'Ponto', pontoAjustar:'Ponto', equipePesoMaoObra:'Equipe e pagamentos', equipeReserva:'Equipe e pagamentos', espacoHistorico:'Backup e espaço', armazenamentoPainel:'Armazenamento', cancelarPagamentoFuncionario:'Equipe e pagamentos', visibilidadeLoteProdutos:'Cardápio em lote', pushInscrever:'Avisos com o app fechado', pushCancelar:'Avisos com o app fechado', listarAuditoria:'Auditoria', listarSessoes:'Sessões abertas', encerrarSessaoRemota:'Sessões abertas', simularPrecificacao:'Calculadora de preço', salvarCupom:'Cupons', salvarEvento:'Eventos' };
async function _apiCallRaw(action, payload, _tentativa, _idemChave){
  if(RESERVA_INDISPONIVEL_[action] && typeof _sb5Reserva_ !== 'undefined' && _sb5Reserva_) return { ok:false, reserva:true, message:'Modo reserva: "' + RESERVA_INDISPONIVEL_[action] + '" fica indisponível até o Supabase voltar. Nada foi gravado.' };
  if(currentUser && currentUser.emergencia) throw new Error('Modo emergência: este aparelho não fala com a planilha principal'); // BLOCO 1.3 (age como falha de rede: nada é gravado nem apagado)
  payload = payload || {};
  if(USAR_SUPABASE_){ const _rsb = await sbRotear_(action, payload); if(_rsb !== undefined){ if(_rsb && _rsb.sessaoExpirada){ try{ _fila.forEach(i=>{ if(i.estado==='pendente' || i.estado==='retry' || i.estado==='enviando'){ i.estado='erro'; i.erro='Sessão expirada — entre de novo e toque em "Tentar de novo"'; } }); filaSalvar_(); }catch(e){} localStorage.removeItem(SESSAO_KEY); localStorage.removeItem(CONTINGENCIA_CHAVE_KEY); localStorage.removeItem(CACHE_KEY); currentUser = null; avisar('Sua sessão expirou. Faça login novamente.'); location.reload(); } if(_rsb && (_rsb.conflito || _rsb.duplicado)) atualizarAposDuplicado_(); else if(_rsb && _rsb.ok === true && SB_REFRESH_APOS_.has(action)) setTimeout(atualizarAposDuplicado_, 400); return _rsb; } }
  // O caminho antigo (envio direto para a planilha) foi retirado: com o Supabase ligado, sbRotear_ sempre responde.
  return { ok:false, naoMigrada:true, message: SB_NAO_MIGRADA_ };
}
/* O servidor recusou uma repetição: o dado local pode estar defasado, então puxa o estado real. */
async function atualizarAposDuplicado_(){
  try{
    const d = await apiCall('getAll', {});
    aplicarDadosRecebidos(d); salvarCache();
    if(seguroParaSincronizar()) renderizarTudo();
  }catch(e){ /* sem problema: a sincronização automática pega depois */ }
}
/* POP-UPS DE CADASTRO: abrir/fechar. Fechar pelo ✕ guarda o que foi digitado (rascunho), exceto senhas, que sempre são apagadas.
   Enquanto um pop-up está aberto a tela não é atualizada em segundo plano (ver regra de ".modal-overlay.open"). */
function abrirFormModal(id){ const m = document.getElementById(id); if(m){ m.classList.add('open'); const box = m.querySelector('.modal-box'); if(box) box.scrollTop = 0; m.scrollTop = 0; } }
function fecharFormModal(id){ const m = document.getElementById(id); if(!m) return; m.classList.remove('open'); m.querySelectorAll('input[type=password]').forEach(i=>{ i.value=''; }); }
function showMsg(id, text, type){
  const el = document.getElementById(id);
  el.textContent = text; el.className = 'msg ' + type;
  clearTimeout(el._t); el._t = setTimeout(()=>{ el.className='msg'; }, 6000);
}
function setBotoesOcupados(ocupado){
  ['pBtn','vBtn','despBtn','koBtn','eBtn'].forEach(id=>{ const el=document.getElementById(id); if(el) el.disabled = ocupado; });
  if(!ocupado) atualizarBloqueioVendaOffline(); // vBtn continua travado se estiver sem conexão
}
function ativarMascaraTelefone(id){
  const el = document.getElementById(id);
  if(!el) return;
  el.addEventListener('input', ()=>{
    const d = el.value.replace(/\D/g,'').slice(0,11);
    let f = d;
    if(d.length<=2) f = d.replace(/^(\d*)/, '($1');
    else if(d.length<=6) f = d.replace(/^(\d{2})(\d*)/, '($1) $2');
    else if(d.length<=10) f = d.replace(/^(\d{2})(\d{4})(\d*)/, '($1) $2-$3');
    else f = d.replace(/^(\d{2})(\d{5})(\d*)/, '($1) $2-$3');
    el.value = f;
  });
}
['mTelefone','ndTelefone'].forEach(ativarMascaraTelefone);

/* ---------- CÓPIA COM FALLBACK (2 métodos) ---------- */
function copiarTextoComFallback(texto, msgElId){
  if(navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(texto).then(()=>{ showMsg(msgElId, 'Copiado!', 'ok'); }).catch(()=>{ copiarViaTextarea(texto, msgElId); });
  } else { copiarViaTextarea(texto, msgElId); }
}
function copiarViaTextarea(texto, msgElId){
  try{
    const ta = document.getElementById('copyHelperTextarea');
    ta.value = texto; ta.style.top = '0'; ta.style.left = '0'; ta.focus(); ta.select();
    const ok = document.execCommand('copy');
    ta.style.top = '-1000px'; ta.style.left = '-1000px';
    showMsg(msgElId, ok ? 'Copiado!' : 'Não foi possível copiar automaticamente — selecione o texto acima e copie manualmente.', ok ? 'ok' : 'warn');
  } catch(e){ showMsg(msgElId, 'Não foi possível copiar automaticamente — selecione o texto acima e copie manualmente.', 'warn'); }
}

/* ============================================================
   LOGIN / SESSÃO / PERMISSÕES
   ============================================================ */
/* ITEM 2.1 — identificação do aparelho. O deviceId fica no localStorage (sobrevive a logout) e vai junto no login;
   o servidor guarda na sessão para o Admin ver "quem está logado onde". Não é segurança forte (o usuário pode limpar o
   armazenamento) — é rastro e visibilidade. */
function deviceId_(){
  try{
    let d = localStorage.getItem('tb_device_id');
    if(!d || !/^[A-Za-z0-9-]{8,40}$/.test(d)){
      d = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : ('d' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
      localStorage.setItem('tb_device_id', d);
    }
    return d;
  }catch(e){ return ''; }
}
function resumoNavegador_(){
  const u = navigator.userAgent || '';
  const so = /Android/i.test(u) ? 'Android' : /iPhone|iPad|iPod/i.test(u) ? 'iOS' : /Windows/i.test(u) ? 'Windows' : /Mac OS X/i.test(u) ? 'macOS' : /Linux/i.test(u) ? 'Linux' : 'SO?';
  const nav = /Edg\//.test(u) ? 'Edge' : /OPR\/|Opera/.test(u) ? 'Opera' : /Firefox\//.test(u) ? 'Firefox' : /Chrome\//.test(u) ? 'Chrome' : /Safari\//.test(u) ? 'Safari' : 'Navegador?';
  return nav + ' · ' + so;
}
/* ============================================================
   BLOCO 1.3 — ACESSO DE EMERGÊNCIA (planilha principal fora do ar)
   Quem entrou com sucesso (Admin/Operador) deixa neste aparelho, por 30 dias, uma "credencial de emergência":
   só uma verificação da senha (PBKDF2, nunca a senha), a chave interna da contingência e uma cópia do catálogo
   (produtos, preços, formas de pagamento) — SEM clientes, vendas ou financeiro. Ela sobrevive ao "Sair".
   Se a planilha estiver fora do ar na hora do login, a senha é conferida aqui mesmo e o aparelho entra em MODO EMERGÊNCIA:
   só a venda do Caixa pela contingência (sem desconto, sem mesa), nenhuma chamada à planilha. Assim que a planilha responde,
   a sessão de emergência é encerrada e o login normal é exigido. Cada login normal renova o prazo; um login recusado
   ("desativado" / senha incorreta) apaga a credencial. */
const EMERGENCIA_KEY_ = 'txbEmergencia_v1', EMERGENCIA_FALHAS_KEY_ = 'txbEmergenciaFalhas_v1';
const EMERGENCIA_TTL_MS_ = 30*24*3600*1000, EMERGENCIA_PBKDF2_ = 150000, EMERGENCIA_CATALOGO_MS_ = 10*60*1000;
function emergenciaSuportada_(){ return !!(window.crypto && crypto.subtle && crypto.getRandomValues && window.TextEncoder); }
function emergenciaLer_(){
  let o = null;
  try{ o = JSON.parse(localStorage.getItem(EMERGENCIA_KEY_) || 'null'); }catch(e){}
  if(!o || o.v !== 1 || !o.usuarios || typeof o.usuarios !== 'object') o = { v:1, usuarios:{}, chave:'', catalogo:null, catalogoEm:0 };
  Object.keys(o.usuarios).forEach(k=>{ if(!o.usuarios[k] || Number(o.usuarios[k].expira) < Date.now()) delete o.usuarios[k]; }); // vencidas somem
  return o;
}
function emergenciaGravar_(o){ try{ localStorage.setItem(EMERGENCIA_KEY_, JSON.stringify(o)); return true; }catch(e){ return false; } }
function emergenciaB64_(buf){ let t = ''; new Uint8Array(buf).forEach(b=>{ t += String.fromCharCode(b); }); return btoa(t); }
function emergenciaB64Bytes_(t){ return Uint8Array.from(atob(t), c=>c.charCodeAt(0)); }
async function emergenciaHash_(senha, saltB64){
  const km = await crypto.subtle.importKey('raw', new TextEncoder().encode(String(senha)), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name:'PBKDF2', hash:'SHA-256', salt: emergenciaB64Bytes_(saltB64), iterations: EMERGENCIA_PBKDF2_ }, km, 256);
  return emergenciaB64_(bits);
}
/* chamada depois de um login NORMAL bem-sucedido (e depois de trocar a própria senha): cria/renova a credencial deste usuário */
async function emergenciaRegistrar_(login, senha, nivel){
  if(!emergenciaSuportada_() || ['Admin','Operador'].indexOf(nivel) === -1) return;
  try{
    const salt = emergenciaB64_(crypto.getRandomValues(new Uint8Array(16)));
    const hash = await emergenciaHash_(senha, salt);
    const o = emergenciaLer_();
    o.usuarios[String(login).toLowerCase()] = { login: String(login), nivel: nivel, salt: salt, hash: hash, expira: Date.now() + EMERGENCIA_TTL_MS_ };
    const k = localStorage.getItem(CONTINGENCIA_CHAVE_KEY); if(k) o.chave = k;
    emergenciaGravar_(o);
  }catch(e){}
}
function emergenciaGuardarChave_(chave){
  try{ const o = emergenciaLer_(); if(chave && o.chave !== chave){ o.chave = chave; emergenciaGravar_(o); } }catch(e){}
}
function emergenciaRemover_(login){
  try{ const o = emergenciaLer_(); delete o.usuarios[String(login).toLowerCase()]; emergenciaGravar_(o); }catch(e){}
}
/* cópia do catálogo para o modo emergência; chamada pelo salvarCache() de quem tem credencial registrada, no máximo a cada 10 min */
function emergenciaSalvarCatalogo_(){
  if(!currentUser || currentUser.emergencia || !currentUser.login || ['Admin','Operador'].indexOf(currentUser.nivel) === -1) return;
  try{
    const o = emergenciaLer_();
    if(!o.usuarios[String(currentUser.login).toLowerCase()]) return;
    const k = localStorage.getItem(CONTINGENCIA_CHAVE_KEY); if(k) o.chave = k;
    if(Date.now() - (o.catalogoEm || 0) < EMERGENCIA_CATALOGO_MS_ && o.catalogo){ emergenciaGravar_(o); return; }
    if(!produtos.length && !combos.length) return; // nada útil para guardar (ex.: dados ainda não chegaram)
    o.catalogo = { produtos, produtoPrecos, combos, comboPrecos, comboItens, adicionais, produtoAdicionais, formasPagamento, categorias, configCardapio, configEntrega, sessaoCaixa };
    o.catalogoEm = Date.now();
    emergenciaGravar_(o);
  }catch(e){}
}
function emergenciaAplicarCatalogo_(){
  const c = emergenciaLer_().catalogo; if(!c) return false;
  normalizarNumerosDados_(c);
  produtos = c.produtos||[]; produtoPrecos = c.produtoPrecos||[]; combos = c.combos||[]; comboPrecos = c.comboPrecos||[]; comboItens = c.comboItens||[];
  adicionais = c.adicionais||[]; produtoAdicionais = c.produtoAdicionais||[]; formasPagamento = c.formasPagamento||[]; categorias = c.categorias||[];
  if(c.configCardapio) configCardapio = c.configCardapio;
  if(c.configEntrega) configEntrega = c.configEntrega;
  sessaoCaixa = c.sessaoCaixa || null; // o último estado conhecido do caixa; sem caixa aberto, o próprio Caixa recusa a venda
  if(!formaPrecoAtual && formasPagamento.length) formaPrecoAtual = (formasPagamento.find(f=>f.ativa) || formasPagamento[0]).id;
  return true;
}
function emergenciaFalhas_(){ try{ return JSON.parse(localStorage.getItem(EMERGENCIA_FALHAS_KEY_) || '{}') || {}; }catch(e){ return {}; } }
/* Devolve 'ok' (entrou), 'cancelou', 'senha' (não confere), 'bloqueado' (5 erros = 5 min) ou 'indisponivel' (não há credencial/chave/catálogo) */
async function emergenciaTentarEntrar_(login, senha){
  if(!emergenciaSuportada_()) return 'indisponivel';
  const o = emergenciaLer_(), rec = o.usuarios[String(login).toLowerCase()];
  if(!rec || !o.chave || !o.catalogo) return 'indisponivel';
  const fa = emergenciaFalhas_();
  if(fa.ate && fa.ate > Date.now()) return 'bloqueado';
  let h = '';
  try{ h = await emergenciaHash_(senha, rec.salt); }catch(e){ return 'indisponivel'; }
  if(h !== rec.hash){
    const n = (fa.ate && fa.ate <= Date.now() ? 0 : (fa.n || 0)) + 1;
    try{ localStorage.setItem(EMERGENCIA_FALHAS_KEY_, JSON.stringify(n >= 5 ? { n:0, ate: Date.now() + 300000 } : { n:n, ate:0 })); }catch(e){}
    return 'senha';
  }
  try{ localStorage.removeItem(EMERGENCIA_FALHAS_KEY_); }catch(e){}
  if(!await confirmarTxt_('O servidor (Supabase) está fora do ar.\n\nEntrar em MODO EMERGÊNCIA como ' + rec.login + '?\n\n• Só dá para registrar vendas do Caixa (retirada/entrega, sem desconto), pela contingência.\n• Preços e produtos são os da última vez que este aparelho falou com o servidor.\n• Quando o servidor voltar, o app pede seu login de novo.', 'Entrar em emergência', false, 'Servidor fora do ar')) return 'cancelou';
  localStorage.setItem(CONTINGENCIA_CHAVE_KEY, o.chave);
  currentUser = { login: rec.login, nivel: rec.nivel, token: '', emergencia: true }; // nunca vai para o SESSAO_KEY: recarregar a página exige entrar de novo
  entrarNoApp();
  return 'ok';
}
function emergenciaBanner_(txt){
  let b = document.getElementById('emergenciaBanner');
  if(!b){
    b = document.createElement('div'); b.id = 'emergenciaBanner';
    b.style.cssText = 'position:sticky;top:0;z-index:9000;background:#b45309;color:#fff;font-weight:700;font-size:13px;text-align:center;padding:8px 10px;';
    document.body.insertBefore(b, document.body.firstChild);
  }
  b.textContent = txt;
}
function emergenciaEncerrar_(){
  try{ localStorage.removeItem(CONTINGENCIA_CHAVE_KEY); }catch(e){}
  currentUser = null;
  confirmar({ titulo:'O servidor voltou', texto:'Por segurança, entre de novo com seu login e senha.', ok:'Entrar de novo', somenteOk:true }).then(()=>location.reload());
}
/* a cada 30 s pergunta à planilha (ação pública, sem sessão) se ela voltou; com carrinho em andamento só avisa e espera a venda terminar */
let _emergVigiaTimer_ = null;
function emergenciaVigiar_(){
  if(_emergVigiaTimer_) return;
  _emergVigiaTimer_ = setInterval(async ()=>{
    if(!currentUser || !currentUser.emergencia) return;
    /* o modo emergência abre quando o SUPABASE cai — então é ele que precisa ter voltado (antes conferia a planilha) */
    try{ if(typeof sb5Sondar_ === 'function' && !(await sb5Sondar_())) return; }catch(e){ return; }
    if(carrinhoAtual.length){ emergenciaBanner_('🟢 O servidor voltou — termine esta venda; depois o app pedirá seu login de novo'); return; }
    emergenciaEncerrar_();
  }, 30000);
}
/* "Lembrar neste aparelho": com a caixinha marcada o navegador/celular passa a oferecer salvar o login e a senha no gerenciador de senhas
   do próprio aparelho (cofre com digital/PIN). O sistema NÃO guarda a senha. Desmarcada (padrão) = como sempre foi. */
function loginLembrarAlternar_(){
  const cb = document.getElementById('loginLembrar'), u = document.getElementById('loginUsuario'), s = document.getElementById('loginSenha'), f = document.getElementById('formLogin');
  if(!cb || !u || !s) return;
  const on = !!cb.checked;
  u.setAttribute('autocomplete', on ? 'username' : 'off'); s.setAttribute('autocomplete', on ? 'current-password' : 'off');
  if(f) f.setAttribute('autocomplete', on ? 'on' : 'off');
  try{ localStorage.setItem('txbLembrarLogin', on ? '1' : '0'); }catch(e){}
}
(function(){ try{ const cb = document.getElementById('loginLembrar'); if(cb && localStorage.getItem('txbLembrarLogin') === '1'){ cb.checked = true; loginLembrarAlternar_(); } }catch(e){} })();
async function tentarLogin(){
  try{ desbloquearAudio_(); if('Notification' in window && Notification.permission==='default') Notification.requestPermission(); }catch(e){}
  const login = document.getElementById('loginUsuario').value.trim();
  const senha = document.getElementById('loginSenha').value;
  if(!login || !senha){ document.getElementById('lockErro').textContent='Preencha login e senha.'; document.getElementById('lockErro').style.display='block'; return; }
  if(!apiConfigurada()){ document.getElementById('lockErro').textContent='Página ainda não conectada ao servidor.'; document.getElementById('lockErro').style.display='block'; return; }
  const erroLogin_ = (t)=>{ const el = document.getElementById('lockErro'); el.textContent = t; el.style.display = 'block'; };
  let r = null, semPlanilha = false;
  try{
    r = await apiCall('autenticar', { login, senha, deviceId: deviceId_(), ua: resumoNavegador_() });
    if(r && r.timeout) semPlanilha = true;
  } catch(e){ semPlanilha = true; }
  if(semPlanilha){ // BLOCO 1.3: planilha fora do ar -> tenta a credencial de emergência guardada neste aparelho
    const res = await emergenciaTentarEntrar_(login, senha);
    if(res === 'ok' || res === 'cancelou') return;
    erroLogin_(res === 'senha' ? 'Servidor fora do ar e a senha não confere com a guardada neste aparelho.'
      : res === 'bloqueado' ? 'Muitas tentativas erradas. Aguarde 5 minutos.'
      : 'Não foi possível conectar ao servidor.');
    return;
  }
  if(r.ok){
    currentUser = { login: r.login, nivel: (r.nivel === 'Desenvolvedor' ? 'Admin' : r.nivel), nivelReal: r.nivel, token: r.token };
    localStorage.setItem(SESSAO_KEY, JSON.stringify(currentUser));
    emergenciaRegistrar_(r.login, senha, r.nivel); // BLOCO 1.3: cria/renova o acesso de emergência por 30 dias
    entrarNoApp();
  } else {
    if(/desativado|Login ou senha incorretos/i.test(r.message || '')) emergenciaRemover_(login); // acesso recusado pela planilha: apaga a credencial de emergência
    erroLogin_(r.message);
  }
}
function entrarNoApp(){
  try{ localStorage.setItem('cdAparelhoEquipe', '1'); }catch(e){}   // aparelho da equipe: não conta visita ao cardápio
  try{ const ap_ = localStorage.getItem('cdAparelhoId'); if(ap_) setTimeout(()=>{ try{ apiCall('marcarAparelhoEquipe',{aparelho:ap_}); }catch(e){} }, 2500); }catch(e){}   // avisa o banco: visitas deste aparelho não contam
  garantirChaveContingencia_();
  garantirChaveLeitura_();
  document.getElementById('lockScreen').classList.add('hidden');
  document.getElementById('cardapioPublico').classList.add('hidden');
  document.getElementById('cdFabCarrinho').classList.remove('show');
  document.getElementById('mainWrap').classList.add('unlocked');
  document.getElementById('userbarTexto').textContent = rotuloBarraUsuario_();
  aplicarPermissoesNivel();
  try{ rtIniciar_(); }catch(e){}
  if(currentUser.emergencia){ // BLOCO 1.3: modo emergência = só o Caixa
    document.querySelectorAll('.tab-btn').forEach(b=>b.classList.toggle('hidden-tab', b.dataset.tab !== 'caixa'));
    document.querySelectorAll('.atalho-btn').forEach(b=>{ b.style.display = 'none'; });
    const bc = document.querySelector('.tab-btn[data-tab="caixa"]'); if(bc) bc.click();
    emergenciaBanner_('🟠 MODO EMERGÊNCIA — servidor fora do ar. Só vendas do Caixa, pela contingência.');
  }
  sbFaixa_();
  init();
  try{ if(!currentUser.emergencia && typeof carregarIntegFlags_==='function') carregarIntegFlags_(); }catch(e){}
  try{ if(typeof sb410IniciarAlertaBackup_==='function') sb410IniciarAlertaBackup_(); }catch(e){}
  setTimeout(oferecerRecuperarCarrinho_, 800);  // ITEM 2.7
  try{ requestAnimationFrame(()=>requestAnimationFrame(()=>{ if(window.txbSplashFim_) window.txbSplashFim_(); })); }catch(e){ if(window.txbSplashFim_) window.txbSplashFim_(); }   // tira a tela de abertura (logo) só depois do sistema desenhado
}
/* abas visíveis por perfil (a barra continua sendo a mesma de 7 abas; o backend valida cada ação de qualquer forma) */
const NAV_POR_PERFIL_ = { 'Cozinha':['inicio','pedidos','notificacoes'], 'Garçom':['inicio','caixa','pedidos','clientes'], 'Entregador':['inicio','pedidos','meusganhos'] };
function aplicarPermissoesNivel(){
  const ehDesenvolvedor = !!(currentUser && currentUser.nivelReal === 'Desenvolvedor');
  const admin = currentUser && currentUser.nivel === 'Admin';
  const entregador = currentUser && currentUser.nivel === 'Entregador';
  let primeiroVisivel = null;
  const nivelAtual = currentUser ? currentUser.nivel : '';
  const abasDoPerfil = NAV_POR_PERFIL_[nivelAtual];
  document.body.classList.toggle('perfil-cozinha', nivelAtual==='Cozinha');
  document.body.classList.toggle('perfil-garcom', nivelAtual==='Garçom');
  document.body.classList.toggle('perfil-entregador', nivelAtual==='Entregador');
  document.querySelectorAll('.tab-btn').forEach(btn=>{
    let visivel;
    if(abasDoPerfil) visivel = abasDoPerfil.indexOf(btn.dataset.tab) !== -1;
    else if(entregador) visivel = btn.dataset.entregadorOk === '1';
    else { const restrito = btn.dataset.admin === '1'; visivel = !restrito || admin || (nivelAtual==='Operador' && btn.dataset.tab==='administrador'); }
    if(btn.dataset.tab === 'meusganhos') visivel = (nivelAtual === 'Entregador');
    if(btn.dataset.tab === 'notificacoes') visivel = (nivelAtual === 'Cozinha');   /* Admin/Operador/Dev: os avisos ficam dentro do Assistente (aba "🔔 Avisos") */
    btn.classList.toggle('hidden-tab', !visivel);
    if(visivel && !primeiroVisivel) primeiroVisivel = btn;
  });
  const ativoAtual = document.querySelector('.tab-btn.active');
  if((!ativoAtual || ativoAtual.classList.contains('hidden-tab')) && primeiroVisivel) primeiroVisivel.click();
  document.querySelectorAll('.atalho-btn').forEach(b=>{
    const m = (b.getAttribute('onclick')||'').match(/data-tab=(\w+)/);
    if(m){ const t = document.querySelector('[data-tab='+m[1]+']'); b.style.display = (t && t.classList.contains('hidden-tab')) ? 'none' : ''; }
  });
  const ROT_ = { 'Garçom':{caixa:'Atendimento'}, 'Cozinha':{pedidos:'Cozinha'}, 'Entregador':{pedidos:'Minhas entregas'}, 'Operador':{administrador:'Operação'} };
  document.querySelectorAll('.tab-btn').forEach(btn=>{
    const tn = btn.firstChild && btn.firstChild.nodeType===3 ? btn.firstChild : null; if(!tn) return;
    if(btn.dataset.rotOrig===undefined) btn.dataset.rotOrig = tn.textContent;
    tn.textContent = (ROT_[nivelAtual]||{})[btn.dataset.tab] || btn.dataset.rotOrig;
  });
  if(nivelAtual==='Cozinha' || nivelAtual==='Entregador'){ const bp = document.querySelector('.tab-btn[data-tab="pedidos"]'); if(bp && !bp.classList.contains('hidden-tab')) bp.click(); }
  if(nivelAtual==='Garçom'){ setTipoEntrega('Mesa'); setModoCliente('sem'); mudarPainelCaixa('cliente'); }
  if(['Cozinha','Admin','Operador','Garçom','Entregador'].indexOf(nivelAtual)!==-1 && !currentUser.emergencia) iniciarDetectorCozinha();
  const bgb = document.getElementById('buscaGlobalBtn'); if(bgb) bgb.style.display = bgPodeBuscar_() ? '' : 'none';
  pedidosPainel_(nivelAtual==='Entregador' ? 'entregas' : 'pedidos');
  atualizarCardAvisos_();
  const barra = document.getElementById('devBar');
  if(barra){
    barra.style.display = ehDesenvolvedor ? 'block' : 'none';
    const sel = document.getElementById('devVerComo');
    if(sel && ehDesenvolvedor) devPopularVisoes_();
    if(ehDesenvolvedor){
      const trocado = currentUser.nivel !== 'Admin';
      barra.style.borderColor = trocado ? '#e0b53a' : '#4caf50';
      barra.style.background = trocado ? '#241d0d' : '#122213';
    }
  }
}
function loginVisao_(){ return currentUser ? (currentUser.verComo || currentUser.login) : ''; }
function rotuloBarraUsuario_(){
  if(!currentUser) return '';
  if(currentUser.nivelReal !== 'Desenvolvedor') return currentUser.login + ' · ' + currentUser.nivel;
  if(!currentUser.verComo) return currentUser.login + ' · Desenvolvedor';
  const u = (typeof usuarios !== 'undefined' ? usuarios : []).find(x=>String(x.login).toLowerCase()===String(currentUser.verComo).toLowerCase());
  return currentUser.login + ' · Desenvolvedor (vendo como ' + currentUser.nivel + ' — ' + ((u && u.nome) || currentUser.verComo) + ')';
}
/* Seletor do modo Desenvolvedor: lista as PESSOAS (ex.: Entregador — João), não só os perfis. */
function devPopularVisoes_(){
  const sel = document.getElementById('devVerComo'); if(!sel || !currentUser || currentUser.nivelReal !== 'Desenvolvedor') return;
  const ordem = ['Operador','Garçom','Cozinha','Entregador'], rot = { 'Operador':'Operador de caixa', 'Garçom':'Garçom', 'Cozinha':'Cozinha', 'Entregador':'Entregador' };
  const lista = (typeof usuarios !== 'undefined' ? usuarios : []).filter(u=>u.ativo && ordem.indexOf(u.nivel)!==-1)
    .sort((a,b)=>ordem.indexOf(a.nivel)-ordem.indexOf(b.nivel) || String(a.login).localeCompare(String(b.login)));
  const html = '<option value="Admin">Admin (visão normal)</option>' + lista.map(u=>'<option value="'+escH(u.login)+'">'+rot[u.nivel]+' — '+escH(u.nome||u.login)+'</option>').join('');
  if(sel.dataset.sig !== html){ sel.innerHTML = html; sel.dataset.sig = html; }
  sel.value = currentUser.verComo || 'Admin';
}
function devMudarVisao(valor){
  if(!currentUser || currentUser.nivelReal !== 'Desenvolvedor') return;
  let nivel = 'Admin', quem = '';
  if(valor && valor !== 'Admin'){
    const u = (typeof usuarios !== 'undefined' ? usuarios : []).find(x=>String(x.login).toLowerCase()===String(valor).toLowerCase());
    if(!u || ['Operador','Garçom','Cozinha','Entregador'].indexOf(u.nivel) === -1) return;
    nivel = u.nivel; quem = u.login;
  }
  currentUser.nivel = nivel; currentUser.verComo = quem;
  document.getElementById('userbarTexto').textContent = rotuloBarraUsuario_();
  aplicarPermissoesNivel();
  try{ renderizarTudo(); }catch(e){ if(window.erroTela_) erroTela_(e); }
  const primeiro = document.querySelector('.tab-btn:not(.hidden-tab)');
  if(primeiro) primeiro.click();
}
/* quem fez login (Admin, Operador, Garçom) recebe da planilha principal a chave INTERNA da contingência
   e a guarda neste aparelho, para conseguir ler a parte interna do espelho (clientes) se a principal cair.
   Cozinha e Entregador não recebem. A chave é apagada ao sair ou quando a sessão expira. */
function garantirChaveContingencia_(){
  try{
    if(!currentUser || currentUser.emergencia || ['Admin','Operador'].indexOf(currentUser.nivel)===-1) return;
    if(localStorage.getItem(CONTINGENCIA_CHAVE_KEY)) return;
    apiCall('obterChaveContingencia', {}).then(r=>{ if(r && r.ok && r.chave){ localStorage.setItem(CONTINGENCIA_CHAVE_KEY, r.chave); emergenciaGuardarChave_(r.chave); } }).catch(()=>{});
  } catch(e){}
}
/* troca da própria senha (qualquer perfil). O servidor devolve um token novo; sem ele este aparelho cairia no login. */
let spOcupado = false;
function abrirModalTrocarSenha(){
  ['spAtual','spNova','spConfirma'].forEach(id=>{ const el=document.getElementById(id); el.value=''; el.type='password'; });
  document.getElementById('spMostrar').checked = false;
  const msg = document.getElementById('spMsg'); msg.textContent = ''; msg.className = 'msg';
  document.getElementById('spBtn').disabled = false; spOcupado = false;
  document.getElementById('senhaPropriaModal').classList.add('open');
}
function fecharModalTrocarSenha(){
  ['spAtual','spNova','spConfirma'].forEach(id=>{ document.getElementById(id).value=''; });
  document.getElementById('senhaPropriaModal').classList.remove('open');
}
function spAlternarVisivel(){
  const t = document.getElementById('spMostrar').checked ? 'text' : 'password';
  ['spAtual','spNova','spConfirma'].forEach(id=>{ document.getElementById(id).type = t; });
}
async function confirmarTrocarSenha(){
  if(spOcupado) return;
  const atual = document.getElementById('spAtual').value, nova = document.getElementById('spNova').value, conf = document.getElementById('spConfirma').value;
  const msg = document.getElementById('spMsg'), btn = document.getElementById('spBtn');
  const erro = (t)=>{ msg.textContent = t; msg.className = 'msg warn'; };
  if(!atual || !nova || !conf){ erro('Preencha os três campos.'); return; }
  if(nova.length < 8){ erro('A nova senha precisa ter ao menos 8 caracteres.'); return; }
  if(nova !== conf){ erro('A confirmação não é igual à nova senha.'); return; }
  if(nova === atual){ erro('A nova senha precisa ser diferente da atual.'); return; }
  spOcupado = true; btn.disabled = true; msg.textContent = 'Salvando...'; msg.className = 'msg';
  try{
    const r = await apiCall('trocarMinhaSenha', { senhaAtual: atual, novaSenha: nova });
    if(r && r.ok && r.token){
      currentUser.token = r.token;
      localStorage.setItem(SESSAO_KEY, JSON.stringify(currentUser));
      emergenciaRegistrar_(currentUser.login, nova, currentUser.nivel); // BLOCO 1.3: a senha de emergência acompanha a nova senha
      msg.textContent = r.message; msg.className = 'msg ok';
      ['spAtual','spNova','spConfirma'].forEach(id=>{ document.getElementById(id).value=''; });
      setTimeout(fecharModalTrocarSenha, 1500);
    } else { erro((r && r.message) || 'Não foi possível trocar a senha.'); spOcupado = false; btn.disabled = false; }
  } catch(e){ erro('Sem conexão com o servidor. Tente de novo.'); spOcupado = false; btn.disabled = false; }
}
async function sair(){
  if(sessaoCaixa){
    if(!await confirmarTxt_('O caixa ainda está aberto. Tem certeza que quer sair?', 'Sair mesmo assim', true, 'Caixa aberto')) return;
  }
  /* A fila offline fica neste aparelho (cadastro de cliente, fidelidade, feedback e ocorrência que ainda não chegaram à planilha).
     Antes de sair, oferece enviar; se não der, deixa o funcionário escolher entre sair mesmo assim ou ficar. */
  if(typeof _fila !== 'undefined' && _fila.length){
    if(await confirmarTxt_('Há ' + _fila.length + ' item(ns) salvo(s) neste aparelho que ainda não chegaram ao servidor.\n\nTentar enviar agora antes de sair?', 'Enviar agora', false, 'Itens sem enviar', 'Não enviar')){
      try{ await filaProcessar(); }catch(e){}
      filaRenderLista_();
    }
    if(_fila.length && !await confirmarTxt_('Ainda há ' + _fila.length + ' item(ns) sem enviar.\n\nSe sair agora, eles ficam guardados neste aparelho e só serão enviados quando alguém entrar nele de novo (aparecem no botão "na fila").\n\nSair mesmo assim?', 'Sair mesmo assim', true, 'Itens ainda na fila')) return;
  }
  rtParar_();
  if(currentUser && currentUser.token) apiCall('encerrarSessao', {}).catch(()=>{});
  try{ sessionStorage.removeItem(CARRINHO_RASCUNHO_KEY); }catch(e){}  // ITEM 2.7: saiu de propósito = não oferecer o carrinho de volta
  localStorage.removeItem(SESSAO_KEY); localStorage.removeItem(CONTINGENCIA_CHAVE_KEY); localStorage.removeItem(CACHE_KEY); // SEGURANÇA: não deixa clientes/vendas/financeiro guardados no aparelho depois de sair
  currentUser = null;
  location.reload();
}

/* ---------- CONFIRMAÇÃO DE SENHA DE ADMIN (para operador) ---------- */
/* Desde 20/10/2026 TODA ação sensível (recusar pedido, excluir cliente, cancelar pagamento/movimento, desconto, editar venda) pede a senha, inclusive para o Admin. */
function precisaConfirmarAdmin(){ return true; }
function abrirModalSenhaAdmin(callback){
  senhaAdminCallback = callback;
  try{ const ehAdmin = currentUser && currentUser.nivel === 'Admin'; const sub = document.querySelector('#senhaAdminModal .sub'), lb = document.querySelector('label[for="senhaAdminInput"]'); if(sub) sub.textContent = ehAdmin ? 'Digite a sua senha para confirmar esta ação.' : 'Essa ação exige a senha de um administrador.'; if(lb) lb.textContent = ehAdmin ? 'Sua senha' : 'Senha do administrador'; }catch(e){}
  document.getElementById('senhaAdminInput').value = '';
  document.getElementById('senhaAdminMsg').className = 'msg';
  document.getElementById('senhaAdminModal').classList.add('open');
}
/* Pede a senha (confere no servidor pelo próprio modal) e devolve a senha, ou null se a pessoa fechou. Senha SEMPRE, inclusive do Admin. */
function pedirSenha_(){
  return new Promise(res => {
    let feito = false; const fim = v => { if(!feito){ feito = true; res(v); } };
    abrirModalSenhaAdmin(s => fim(s));
    const m = document.getElementById('senhaAdminModal');
    if(!m){ fim(null); return; }
    const obs = new MutationObserver(() => { if(!m.classList.contains('open')){ obs.disconnect(); setTimeout(() => fim(null), 50); } });
    obs.observe(m, { attributes:true, attributeFilter:['class'] });
  });
}
function fecharModalSenhaAdmin(){ document.getElementById('senhaAdminModal').classList.remove('open'); senhaAdminCallback = null; }
async function confirmarSenhaAdminGenerica(){
  const senha = document.getElementById('senhaAdminInput').value;
  if(!senha){ showMsg('senhaAdminMsg','Informe a senha.','warn'); return; }
  try{
    const r = await apiCall('verificarSenhaAdmin', { senha });
    if(r.ok){ const cb = senhaAdminCallback; fecharModalSenhaAdmin(); if(cb) cb(senha); }
    else showMsg('senhaAdminMsg','Senha de administrador incorreta.','warn');
  } catch(e){ showMsg('senhaAdminMsg','Não foi possível verificar.','warn'); }
}

