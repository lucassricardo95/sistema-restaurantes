/* PASSO A PASSO PARA CRIAR UM RESTAURANTE NOVO — escrito para quem nunca fez isso.
   Cada etapa tem: para que serve, o que você vai precisar, quanto tempo leva e PARTES curtas (uma por vez na tela).
   quem: 'voce' (você faz sozinho) ou 'claude' (o painel faz quase tudo; o Claude é só uma alternativa).
   Em cada parte, "extra" diz o que aparece embaixo do texto: campos para preencher, códigos para copiar, botão de teste etc.
   {nome} {slug} {ref} {site_url} {site_origem} {supabase_url} são trocados pelos dados do restaurante. */
window.MODULOS = [
  { id:'ifood', nome:'iFood', pad:false, desc:'Recebe os pedidos do iFood direto no sistema.' },
  { id:'nfce', nome:'Nota fiscal (NFC-e)', pad:false, desc:'Emite a nota fiscal do consumidor.' },
  { id:'mercadopago', nome:'Mercado Pago (Pix e cartão no app)', pad:false, desc:'O cliente paga pelo cardápio.' },
  { id:'infinitepay', nome:'InfinitePay', pad:false, desc:'Outra opção de pagamento online.' },
  { id:'mesas', nome:'Mesas e garçom', pad:true, desc:'QR Code na mesa e tela do garçom.' },
  { id:'ponto', nome:'Ponto da equipe (com foto)', pad:true, desc:'Entrada e saída dos funcionários.' },
  { id:'eventos', nome:'Eventos e orçamentos', pad:true, desc:'Festas, contratos e recebimentos.' },
  { id:'planilhas', nome:'Planilhas Google de reserva', pad:false, desc:'Cópia em planilha caso o banco caia.' },
  { id:'ia', nome:'Assistente virtual (IA)', pad:true, desc:'Atendente automático no cardápio.' }
];
window.TEMAS = [
  { id:'brasa', nome:'Brasa', destaque:'#e0b53a', botao:'#d20807', fundo:'#0b0705' },
  { id:'classico', nome:'Clássico', destaque:'#d9a21b', botao:'#8c1c13', fundo:'#14100c' },
  { id:'verde', nome:'Verde', destaque:'#7ed957', botao:'#1f8f4e', fundo:'#07120b' },
  { id:'azul', nome:'Azul', destaque:'#5aa9ff', botao:'#1f5fbf', fundo:'#07101c' },
  { id:'roxo', nome:'Roxo', destaque:'#c58bff', botao:'#7b3fe4', fundo:'#10081c' },
  { id:'rosa', nome:'Rosa', destaque:'#ff8fb8', botao:'#d6336c', fundo:'#1a0a11' },
  { id:'laranja', nome:'Laranja', destaque:'#ffb347', botao:'#e8590c', fundo:'#160d05' },
  { id:'pb', nome:'Preto e branco', destaque:'#f2f2f2', botao:'#444444', fundo:'#0a0a0a' },
  { id:'creme', nome:'Creme (claro)', destaque:'#9a5b00', botao:'#b3261e', fundo:'#faf6ef' },
  { id:'branco', nome:'Branco (claro)', destaque:'#1f5fbf', botao:'#1f5fbf', fundo:'#ffffff' }
];

/* COMO DEVEM SER AS LOGOS (aparece na etapa "Marca" e na aba Marca). O "prompt" é o texto pronto para pedir a imagem ao ChatGPT. */
window.LOGOS = [
  { id:'cardapio', nome:'Logo principal', icone:'🖼️',
    onde:'Topo do cardápio, tela de entrada da equipe e tela de carregamento.',
    regras:['Arquivo PNG com FUNDO TRANSPARENTE (sem quadrado branco atrás).','Quadrada (1024 × 1024) ou deitada (1024 × 600). O painel reduz sozinho.','Feita para aparecer sobre fundo ESCURO: letras claras ou com contorno claro.','Nome do restaurante grande e fácil de ler. Nada de letra fina ou muito pequena.','Deixe uma margem vazia nas bordas (não encoste o desenho na borda).'],
    nao:['Fundo branco ou colorido atrás (aparece um quadrado feio no cardápio).','Foto de verdade, mockup (logo na parede, na camiseta) ou sombra fora do desenho.','Texto extra, endereço ou telefone dentro da logo.'],
    prompt:'Crie a logo do restaurante "{nome}"{tipo}. Quero um emblema moderno e marcante, com o nome "{nome}" bem grande e legível. Cores principais: {destaque} e {botao}. A logo vai aparecer sobre fundo escuro, então use letras claras ou com contorno claro. Entregue em PNG com fundo TRANSPARENTE, formato quadrado 1024x1024, com margem vazia nas bordas. Sem foto, sem mockup, sem sombra externa, sem moldura e sem nenhum outro texto além do nome{slogan_p}.' },
  { id:'impressao', nome:'Logo de impressão', icone:'🧾',
    onde:'Topo da comanda e do recibo, na impressora térmica (papel de 58 ou 80 mm). Sai em PRETO E BRANCO, com 3,5 a 5 cm de largura.',
    regras:['Arquivo PNG com fundo BRANCO (ou transparente).','Desenho só em PRETO PURO: sem cinza, sem degradê, sem cor.','Traços GROSSOS e simples. Detalhe fino some na impressora.','Deitada: o dobro de largura que de altura (ex.: 1024 × 512).','Nome do restaurante grande, ocupando boa parte da imagem.'],
    nao:['Foto, sombra, brilho, textura ou fundo escuro (vira um borrão preto).','Letra fina, pequena ou cursiva demais.','Logo colorida (a impressora transforma em cinza manchado).'],
    prompt:'Crie a versão para IMPRESSORA TÉRMICA da logo do restaurante "{nome}". Somente PRETO PURO sobre fundo BRANCO, sem nenhum tom de cinza, sem degradê, sem sombra e sem textura. Traços grossos e simples, estilo carimbo. Formato horizontal 1024x512 (o dobro de largura que de altura). O nome "{nome}" deve ser grande, em letras grossas e muito fáceis de ler. Sem foto, sem moldura fina e sem nenhum outro texto. Entregue em PNG.' },
  { id:'icone', nome:'Ícone do app', icone:'📱',
    onde:'Ícone do app na tela do celular, na aba do navegador e nos avisos.',
    regras:['Arquivo PNG QUADRADO: 512 × 512 (largura igual à altura).','Fundo PREENCHIDO com a cor do restaurante (sem transparência).','Um símbolo simples no centro, ocupando mais ou menos 60% do quadrado (o celular corta os cantos em círculo).','No máximo 1 ou 2 letras (ex.: as iniciais). Nome inteiro fica ilegível no ícone.'],
    nao:['Texto pequeno, frase ou o nome inteiro.','Desenho encostando nas bordas (vai ser cortado).','Fundo transparente (alguns celulares mostram preto ou branco atrás).'],
    prompt:'Crie o ícone de aplicativo do restaurante "{nome}". Formato QUADRADO 512x512, fundo totalmente preenchido com a cor {fundo}. No centro, um símbolo simples e marcante{tipo_icone} na cor {destaque}, ocupando cerca de 60% da imagem, com bastante espaço vazio nas bordas (o celular corta em círculo). No máximo as iniciais do nome, sem nenhum outro texto. Estilo plano (flat), sem foto, sem sombra e sem moldura. Entregue em PNG.' }
];

/* Contas que você vai criar para cada restaurante (aparece no Guia e na primeira etapa). */
window.CONTAS = [
  ['📧 E-mail Google (Gmail) do restaurante', 'Use um e-mail só do restaurante (ex.: nomedorestaurante@gmail.com). Ele abre o Supabase, o Google Cloud, o Drive e as IAs.'],
  ['🗄️ Supabase', 'O banco de dados (onde ficam produtos, pedidos, clientes). supabase.com → entrar com o Google.'],
  ['🐙 GitHub', 'Onde o site fica publicado. github.com → Sign up.'],
  ['☁️ Google Cloud', 'Para o "Entrar com o Google" e o backup no Drive. console.cloud.google.com (mesmo e-mail).'],
  ['🤖 IAs (opcional)', 'Groq, Gemini, Cloudflare e NVIDIA: chaves grátis para o assistente virtual.']
];

window.ETAPAS = [
 { id:'cadastro', titulo:'Dados do restaurante', curto:'Nome, dono e contrato', quem:'voce', tempo:'2 min',
   porque:'É a ficha do cliente: nome, quem é o dono, quanto ele paga e quando vence.',
   precisa:['Nome do restaurante','WhatsApp do dono','Valor da mensalidade'],
   partes:[
    { t:'Confira os dados do restaurante abaixo. O código (ex.: churros-de-proposito) vai no endereço do site e no nome dos projetos: anote, você vai usar nas próximas etapas.', extra:'cadastro' },
    { t:'Antes de seguir, crie (ou separe) um e-mail Google só deste restaurante. Ele vai abrir todas as contas das próximas etapas.', extra:'contas' }
   ] },
 { id:'supabase', titulo:'Criar o banco de dados', curto:'Projeto no Supabase', quem:'voce', tempo:'5 min', teste:'supabase', campos:['supabase_url','supabase_chave'],
   porque:'O Supabase é onde ficam guardados produtos, pedidos, clientes e caixa. Cada restaurante tem o seu.',
   precisa:['O e-mail Google do restaurante'],
   partes:[
    { t:'Abra supabase.com e entre com o e-mail do restaurante (botão "Continue with Google").', link:'https://supabase.com/dashboard' },
    { t:'Toque em "New project". Em Name escreva {slug}. Em "Database password" toque em "Generate a password" e GUARDE essa senha. Em Region escolha "South America (São Paulo)". Toque em "Create new project".' },
    { t:'Espere uns 2 minutos até aparecer "Healthy" (verde).' },
    { t:'Abra "Project Settings" (engrenagem) → "Data API" (ou "API"). Copie o "Project URL" e cole no primeiro campo abaixo. Depois abra "API Keys", copie a chave que começa com sb_publishable_ e cole no segundo campo. Toque em Salvar e depois em Testar.', extra:'campos' }
   ] },
 { id:'repositorio', titulo:'Criar o endereço do site', curto:'Repositório no GitHub', quem:'voce', tempo:'5 min', teste:'site', campos:['site_url','github_url'],
   porque:'O GitHub é quem coloca o site no ar, de graça. O endereço vai ser algo como usuario.github.io/{slug}.',
   precisa:['Conta no GitHub (pode ser a sua ou uma do restaurante)'],
   partes:[
    { t:'Entre em github.com. Toque no "+" lá em cima → "New repository". Em "Repository name" escreva {slug}. Marque "Public" e marque também "Add a README file" (cria a pasta principal, a "main"). Toque em "Create repository".', link:'https://github.com/new' },
    { t:'Dentro do repositório: "Settings" → "Pages". Em "Source" escolha "Deploy from a branch", em Branch escolha "main" e a pasta "/ (root)" e toque em Save.' },
    { t:'O endereço do site aparece no alto da página Pages (ex.: https://usuario.github.io/{slug}/). Cole abaixo o endereço do site e o endereço do repositório (ex.: https://github.com/usuario/{slug}) e toque em Salvar.', extra:'campos' },
    { t:'Se for usar o Claude para gravar arquivos: Settings → Applications → Installed GitHub Apps → Claude → Configure → libere este repositório. Se for fazer sozinho, pule esta parte.' }
   ] },
 { id:'banco', titulo:'Montar as tabelas do banco', curto:'Copiar e colar os códigos', quem:'voce', tempo:'20 min', teste:'banco',
   porque:'O banco vem vazio. Estes códigos criam todas as tabelas, regras de segurança e funções do sistema.',
   precisa:['O banco criado na etapa anterior','Paciência: são várias partes, uma de cada vez'],
   partes:[
    { t:'No Supabase do restaurante, abra "SQL Editor" (ícone de terminal no menu da esquerda) e toque em "New query".' },
    { t:'Agora é sempre igual: toque em Copiar no código abaixo, cole no SQL Editor (apague o que tiver lá antes), toque em "Run" e espere aparecer "Success". Volte aqui, marque "Já apliquei" e vá para o próximo. Se aparecer "already exists", essa parte já estava feita: só siga.', extra:'codigos' },
    { t:'Terminou todos? Toque em Testar. Tem que aparecer "Banco do sistema instalado".', extra:'teste' }
   ],
   pedido:'Aplique o banco completo do sistema no restaurante "{nome}" (código {slug}, projeto Supabase {ref}): estrutura, ajustes em ordem e conferência de segurança. Não use nenhum dado do Texas Burger.' },
 { id:'funcoes', titulo:'Publicar as funções do servidor', curto:'O GitHub publica para você (pelo celular)', quem:'voce', tempo:'10 min', teste:'funcoes',
   porque:'São os "robôs" do servidor: mandam avisos no celular, fazem backup, falam com o iFood e com as IAs. O próprio GitHub do restaurante publica as 33 funções: você só toca em um botão.',
   precisa:['O GitHub do restaurante (etapa "Criar o endereço do site")','O login do Supabase do restaurante'],
   partes:[
    { t:'No Supabase, crie uma chave de acesso: abra o link abaixo → "Generate new token" → nome: publicar-{slug} → validade: a maior que tiver → "Generate token". COPIE a chave (começa com sbp_). Ela só aparece agora.', link:'https://supabase.com/dashboard/account/tokens' },
    { t:'No GitHub, abra o repositório {slug} → "Settings" → "Secrets and variables" → "Actions" → "New repository secret". Em Name escreva exatamente o nome abaixo. Em Secret cole a chave sbp_ do passo anterior. Toque em "Add secret".', copiar:'SUPABASE_ACCESS_TOKEN', link:'{github_url}/settings/secrets/actions/new' },
    { t:'Ainda no repositório: "Add file" → "Create new file". No nome do arquivo cole o caminho abaixo (as barras criam as pastas sozinhas). No conteúdo cole o código abaixo. Toque em "Commit changes".', extra:'workflow', link:'{github_url}/new/main' },
    { t:'Abra a aba "Actions" do repositório → "Publicar funções do servidor" → "Run workflow" → "Run workflow" (verde). Espere 3 a 5 minutos até aparecer o ✓ verde. Se aparecer ✗ vermelho, toque nele e copie o erro para o Claude.', link:'{github_url}/actions' },
    { t:'Toque em Testar. Tem que aparecer "Funções do servidor respondendo". Sempre que o sistema tiver funções novas, é só repetir a parte 4 (Run workflow).', extra:'teste' }
   ],
   pedido:'Publique as 33 funções do servidor (edge functions) no projeto Supabase {ref} do restaurante "{nome}" ({site_url}), com verify_jwt desligado, e confira que a função ping responde.' },
 { id:'admin', titulo:'Criar o primeiro administrador', curto:'Login do dono', quem:'voce', tempo:'3 min',
   porque:'É o login que o dono vai usar para entrar na área de funcionários.',
   precisa:['Escolher um login e uma senha para o dono'],
   partes:[
    { t:'No SQL Editor do Supabase do restaurante, rode os dois códigos abaixo, na ordem. No segundo, troque o login e a senha de exemplo pelos que você escolheu antes de rodar.', extra:'codigos' },
    { t:'Anote o login e a senha para entregar ao dono. Ele pode trocar a senha depois.' }
   ],
   pedido:'Crie o primeiro Administrador do restaurante "{nome}" (projeto {ref}) com o login: ________ . Gere a senha e me entregue só a mim.' },
 { id:'entrada', titulo:'Entrar com o Google', curto:'Login do cliente com a conta Google', quem:'voce', tempo:'20 min',
   porque:'Deixa o cliente entrar no cardápio com a conta Google (para cupons e carimbos) e prepara o backup no Drive.',
   precisa:['O e-mail Google do restaurante','O endereço do site ({site_url})'],
   partes:[
    { t:'SUPABASE: Authentication → URL Configuration. Em "Site URL" cole {site_url}. Em "Redirect URLs" toque em "Add URL" e cole {site_url}** . Save.' },
    { t:'GOOGLE CLOUD: entre em console.cloud.google.com com o e-mail do restaurante. No alto, seletor de projeto → "Novo projeto" → nome {slug} → Criar. Confira que ele ficou selecionado.', link:'https://console.cloud.google.com/' },
    { t:'Menu ☰ → APIs e serviços → Tela de consentimento OAuth (ou "Google Auth Platform") → Começar. Nome do app: {nome}. E-mail de suporte: o do restaurante. Público: Externo. Aceite e Criar.' },
    { t:'O Google exige uma página de privacidade. O painel gera para você: toque no botão abaixo, baixe o privacidade.html e suba no GitHub do restaurante, NA RAIZ (mesmo lugar do index.html): "Add file" → "Upload files" → "Commit changes".', extra:'privacidade', link:'{github_url}/upload/main' },
    { t:'Em "Branding": página inicial = {site_url} ; política de privacidade = {site_url}privacidade.html ; domínio autorizado = só o domínio do site (ex.: usuario.github.io, sem https). Salve. Não clique em "Ver problemas".' },
    { t:'Em "Público-alvo": toque em "Publicar app" e confirme. Sem isso só e-mails de teste conseguem entrar.' },
    { t:'APIs e serviços → Credenciais → Criar credenciais → "ID do cliente OAuth" → tipo "Aplicativo da Web" → nome "Login do sistema".' },
    { t:'Em "Origens JavaScript autorizadas" cole SÓ: {site_origem}' , copiar:'{site_origem}' },
    { t:'Em "URIs de redirecionamento autorizados" adicione os dois endereços abaixo e toque em Criar.', copiar:'{supabase_url}/auth/v1/callback\n{supabase_url}/functions/v1/drive-oauth' },
    { t:'Copie o "ID do cliente" e a "Chave secreta do cliente" (a chave só aparece inteira agora). GUARDE os dois: a etapa do Drive usa os mesmos.' },
    { t:'Volte ao SUPABASE: Authentication → Sign In / Providers → Google → ligue "Enable", cole o ID e a chave secreta → Save.' },
    { t:'Teste: abra o site, toque em "Entrar" no cardápio e entre com um e-mail Google. Erro "redirect_uri_mismatch" = algum endereço da parte 9 foi colado diferente. "Acesso bloqueado" = falta publicar o app (parte 6).' },
    { t:'(Recomendado, tira o aviso "app não verificado") Abra o Search Console com o MESMO e-mail → Adicionar propriedade → "Prefixo do URL" → cole {site_url} → método "Arquivo HTML" → baixe o arquivo google….html → suba no GitHub NA RAIZ (igual ao privacidade.html) → volte e toque em Verificar. Nunca apague esse arquivo.', link:'https://search.google.com/search-console' }
   ],
   pedido:'Publique no site do restaurante "{nome}" ({site_url}) a página estática privacidade.html (Aviso de Privacidade completo com a seção dos dados do Google), gerada com ferramentas/gerar-privacidade.js a partir dos dados do banco (select public.api_aviso_privacidade()). Se eu mandar o arquivo google....html do Search Console, publique também na raiz do site.' },
 { id:'drive', titulo:'Backup no Google Drive', curto:'Cópias de segurança automáticas', quem:'voce', tempo:'10 min',
   porque:'O sistema guarda cópias de segurança no Drive do restaurante. Se algo der errado, dá para voltar.',
   precisa:['O ID do cliente e a chave secreta da etapa anterior'],
   partes:[
    { t:'Se o restaurante NÃO vai usar backup no Drive, toque em "Pular" lá embaixo.' },
    { t:'Google Cloud (mesmo projeto): ☰ → APIs e serviços → Biblioteca → procure "Google Drive API" → Ativar.' },
    { t:'Google Auth Platform → "Acesso a dados" → "Adicionar ou remover escopos" → filtre "drive" → marque .../auth/drive → Atualizar → Salvar. Ignore o aviso de "escopo não verificado".' },
    { t:'Rode o código abaixo no SQL Editor do Supabase, trocando o ID do cliente e a chave secreta. Copie os dois pelo botão de copiar do Google (nunca digite: l, I e 1 se confundem).', extra:'codigos' },
    { t:'Entre no sistema como Administrador → Sistema → Backup e espaço → cartão "Google Drive" → "Conectar o Drive principal". Escolha a conta do restaurante e aceite. Na tela "O Google não verificou este app": Avançado → Acessar.' }
   ],
   pedido:'Guarde no cofre (Vault) do Supabase do restaurante "{nome}" (projeto {ref}) as chaves google_client_id e google_client_secret. ID do cliente: ________  Chave secreta: ________  Depois confira que a função drive-api responde.' },
 { id:'ia', titulo:'Chaves do assistente virtual', curto:'IAs grátis para o atendente', quem:'voce', tempo:'15 min', modulo:'ia',
   porque:'O assistente responde os clientes no cardápio. Cada restaurante precisa das próprias chaves (grátis).',
   precisa:['O e-mail do restaurante','Login de Administrador do sistema'],
   partes:[
    { t:'Se o módulo "Assistente virtual" estiver desligado, toque em "Pular". O mínimo é GROQ + GEMINI; as outras são reserva.' },
    { t:'GROQ: console.groq.com/keys → "Create API Key" → copie a chave (começa com gsk_). Ela só aparece uma vez.', link:'https://console.groq.com/keys' },
    { t:'GEMINI: aistudio.google.com/apikey → "Criar chave de API" → copie (começa com AIza ou AQ.).', link:'https://aistudio.google.com/apikey' },
    { t:'(Opcional) CLOUDFLARE: dash.cloudflare.com → copie o código de 32 letras da barra de endereço (Account ID). Depois Profile → API Tokens → Create Token → modelo "Workers AI" → copie o token.', link:'https://dash.cloudflare.com/profile/api-tokens' },
    { t:'(Opcional) NVIDIA: build.nvidia.com → Settings → API Keys → Generate → copie (começa com nvapi-).', link:'https://build.nvidia.com/settings/api-keys' },
    { t:'Entre no sistema como Administrador → Sistema → Integrações e contas → "Chaves das IAs". Em cada uma: colar, digitar sua senha, salvar e tocar em "Testar" (tem que aparecer "Funcionando").' }
   ] },
 { id:'planilhas', titulo:'Planilhas Google de reserva', curto:'Opcional', quem:'voce', tempo:'20 min', opcional:true, modulo:'planilhas', campos:['api_url','contingencia_url'],
   porque:'Uma cópia do sistema em planilha, para continuar vendendo se o banco cair. É opcional.',
   precisa:['O e-mail do restaurante'],
   partes:[
    { t:'Se o restaurante não vai usar planilhas, desligue o módulo "Planilhas" na etapa Módulos e toque em "Pular".' },
    { t:'No Google Drive do restaurante crie duas planilhas: "Principal" e "Contingência". Em cada uma: Extensões → Apps Script → apague tudo e cole o código abaixo (o primeiro na principal, o segundo na contingência).', extra:'codigos' },
    { t:'Em cada Apps Script: Implantar → Nova implantação → "Aplicativo da Web" → Executar como: Eu → Quem tem acesso: Qualquer pessoa → Implantar. Copie o endereço que termina em /exec e cole abaixo.', extra:'campos' },
    { t:'O código 3 ("Cofre de chaves · parte 2") vai no SQL Editor do Supabase: troque o endereço /exec dentro dele pelo da planilha principal e rode. Ele mostra uma chave: no Apps Script da planilha principal → Configurações do projeto → Propriedades do script → adicione SB_CHAVE_SERVIDOR com essa chave. Depois Implantar → Gerenciar implantações → lápis → Nova versão.', extra:'codigos' }
   ] },
 { id:'push', titulo:'Avisos no celular', curto:'O painel gera as chaves para você', quem:'voce', tempo:'2 min', campos:['push_chave_publica'],
   porque:'Faz o celular da equipe apitar quando chega pedido, e avisa o cliente quando o pedido sai.',
   precisa:['Nada: o painel cria as chaves'],
   partes:[
    { t:'Toque em "Gerar chaves agora". O painel cria as duas chaves deste restaurante e já guarda a pública aqui.', extra:'push' },
    { t:'Copie o código que apareceu e rode no SQL Editor do Supabase do restaurante. Ele guarda as chaves no cofre do banco (a privada nunca fica no site). Pronto.' }
   ],
   pedido:'Gere as chaves de aviso no celular (VAPID) do restaurante "{nome}" (projeto {ref}), guarde-as no Vault (vapid_publica e vapid_privada) e me devolva a chave pública.' },
 { id:'marca', titulo:'Cores e logos', curto:'A cara do restaurante', quem:'voce', tempo:'10 min',
   porque:'Deixa o sistema com as cores e a logo do restaurante. Muda na hora, sem mexer no site.',
   precisa:['3 imagens: logo principal, logo de impressão e ícone (o painel ensina a pedir ao ChatGPT)'],
   partes:[
    { t:'Escolha um tema pronto ou ajuste as 3 cores. Escreva o slogan e o nome do atendente virtual.', extra:'marca' },
    { t:'Agora as logos. Cada uma tem um jeito certo. Toque em "Como deve ser" para ver as regras e o texto pronto para pedir ao ChatGPT.', extra:'logos' }
   ] },
 { id:'modulos', titulo:'Módulos contratados', curto:'Ligue só o que ele usa', quem:'voce', tempo:'1 min',
   porque:'Desligado, a tela some e não gasta nada do servidor. Dá para ligar depois.',
   precisa:['Saber o que o restaurante contratou'],
   partes:[ { t:'Ligue só o que o restaurante contratou e toque em Salvar. iFood e nota fiscal só funcionam depois que o restaurante cadastrar as chaves dele no sistema.', extra:'modulos' } ] },
 { id:'publicar', titulo:'Colocar o site no ar', curto:'4 arquivos no GitHub', quem:'voce', tempo:'5 min', teste:'site',
   porque:'O site do restaurante é só uma "porta" com 4 arquivos pequenos. O sistema em si vem do motor e se atualiza sozinho.',
   precisa:['Etapas do banco, endereço do site e marca feitas'],
   partes:[
    { t:'Baixe os 4 arquivos abaixo (um toque em cada). Eles já saem prontos para este restaurante. A coluna "Onde colocar" diz o lugar de cada um no GitHub.', extra:'publicar' },
    { t:'No GitHub, abra o repositório {slug} → "Add file" → "Upload files" → escolha os 4 arquivos de uma vez → "Commit changes". Eles ficam na RAIZ (a primeira página do repositório, sem pasta). Se já existirem, o GitHub troca pelos novos.', link:'{github_url}/upload/main' },
    { t:'Espere 1 a 2 minutos e toque em "Conferir o site". O painel abre cada arquivo no ar e diz se está certo. Depois abra o site: tem que aparecer o cardápio com o nome e as cores do restaurante.', extra:'conferir' }
   ],
   pedido:'Crie o repositório leve do restaurante "{nome}" ({slug}): grave os arquivos index.html, sw.js, manifest.webmanifest e config-restaurante.js que o painel gera para ele. Confirme se publicou e abriu sem erro.' },
 { id:'app', titulo:'App Android da equipe', curto:'Opcional', quem:'voce', tempo:'15 min', opcional:true,
   porque:'Um app que abre o sistema em tela cheia no celular da equipe (sem a barra do navegador).',
   precisa:['Site já no ar'],
   partes:[
    { t:'Entre em pwabuilder.com, cole {site_url} e toque em Start → Package for stores → Android → Generate Package. Em "Signing key" escolha "Create new". Baixe o zip.', link:'https://www.pwabuilder.com/' },
    { t:'GUARDE o signing.keystore e o signing-key-info.txt num lugar seguro e nunca publique: sem eles não dá para atualizar o app.' },
    { t:'No GitHub do restaurante crie a pasta downloads e suba o .apk com o nome equipe.apk. O assetlinks.json vai no repositório <usuario>.github.io, em .well-known/assetlinks.json (com um arquivo vazio .nojekyll). Ou mande o zip ao Claude.' },
    { t:'Instale o equipe.apk num Android e abra: tem que abrir em tela cheia.' }
   ],
   pedido:'Estou mandando o zip do PWABuilder do restaurante "{nome}". Coloque o APK como downloads/equipe.apk no repositório do site, publique o assetlinks.json em .well-known no repositório <usuario>.github.io (com .nojekyll) e confira que o app abre em tela cheia. Não guarde o keystore em nenhum repositório.' },
 { id:'contas', titulo:'Guardar as contas e senhas', curto:'Para o dono nunca perder um acesso', quem:'voce', tempo:'10 min',
   porque:'Tudo o que você criou (Supabase, GitHub, Google, IAs) fica anotado dentro do sistema do restaurante, com senha protegida.',
   precisa:['Login de Administrador do sistema'],
   partes:[
    { t:'Entre no sistema como Administrador → Sistema → Integrações e contas → "Contas e acessos".' },
    { t:'Crie um cartão para cada serviço: Supabase, GitHub, Google Cloud (ID do cliente na observação, chave secreta como senha), planilhas, app da equipe e IAs. As senhas ficam no cofre do banco, nunca no site.' }
   ] },
 { id:'teste', titulo:'Teste completo', curto:'Confira tudo antes de entregar', quem:'voce', tempo:'20 min',
   porque:'Garante que o cliente não vai encontrar nada quebrado.',
   precisa:['Um celular'],
   checklist:['Abrir o site no celular: nome, cores e logo certos (nada de outro restaurante)','Cadastrar um produto e ver no cardápio','Fazer um pedido pelo cardápio e ver na tela da cozinha','Imprimir uma comanda e conferir a logo','Entrar com o Google','Instalar o app na tela inicial e conferir ícone e nome','Receber um aviso no celular','Abrir e fechar o caixa','Gerar um backup em Backup e espaço','Apagar os dados de teste'],
   partes:[ { t:'Faça cada teste e marque. Só dá para concluir quando todos estiverem marcados.', extra:'checklist' } ] },
 { id:'entrega', titulo:'Entregar ao cliente', curto:'Equipe, termos e primeira cobrança', quem:'voce', tempo:'15 min',
   porque:'O restaurante começa a usar e você começa a receber.',
   precisa:['Dados do dono para os termos'],
   partes:[
    { t:'Crie os usuários da equipe (Operador, Cozinha, Entregador) no sistema e mostre ao dono onde fica a Ajuda.' },
    { t:'Marque como entregue: o dono vai ler e aceitar os termos de uso no primeiro acesso.', extra:'contrato' },
    { t:'Gere a taxa de implantação e a primeira mensalidade, mude a situação para "Ativo" e pronto!', extra:'cobranca' }
   ] }
];
window.FASES = [['Banco e site',['cadastro','supabase','repositorio','banco','funcoes','admin']],['Google e backup',['entrada','drive']],['Recursos',['ia','planilhas','push']],['Marca e site',['marca','modulos','publicar','app']],['Entrega',['contas','teste','entrega']]];
