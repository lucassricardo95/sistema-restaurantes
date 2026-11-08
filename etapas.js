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
  ['📧 E-mail Google do restaurante (principal)', 'Um e-mail só do restaurante (ex.: nomedorestaurante@gmail.com). Ele abre o Supabase, o Google Cloud, o Drive, a planilha principal e as IAs.', 'https://accounts.google.com/signup'],
  ['📧 Segundo e-mail Google (para as planilhas de reserva)', 'Para a planilha de contingência, que precisa ficar em OUTRA conta Google.', 'https://accounts.google.com/signup'],
  ['🗄️ Supabase', 'O banco de dados (produtos, pedidos, clientes, caixa). Entra com o e-mail do restaurante.', 'https://supabase.com/dashboard/sign-in'],
  ['🐙 GitHub', 'Onde o site fica publicado, de graça. Pode ser a sua conta (o endereço terá o seu usuário).', 'https://github.com/signup'],
  ['☁️ Google Cloud', 'Para o "Entrar com o Google" e o backup no Drive. Mesmo e-mail do restaurante.', 'https://console.cloud.google.com/'],
  ['🤖 IAs (grátis)', 'Groq, Gemini, Cloudflare e NVIDIA: chaves do atendente virtual. Use o e-mail do restaurante.', 'https://console.groq.com/keys']
];

/* {ref} = projeto do Supabase · {github_url} = repositório · {gh_usuario} = usuário do GitHub · {site_url} = endereço do site */
const SB = 'https://supabase.com/dashboard/project/{ref}';
window.ETAPAS = [
 { id:'cadastro', titulo:'Dados do restaurante', curto:'Nome, dono e contrato', quem:'voce', tempo:'5 min',
   porque:'É a ficha do cliente: nome, quem é o dono, quanto ele paga e quando vence. Também é a hora de separar as contas que você vai usar.',
   precisa:['Nome do restaurante','WhatsApp do dono','Valor da mensalidade'],
   partes:[
    { t:'Confira os dados do restaurante abaixo e toque em Salvar. O código ({slug}) vai no endereço do site e no nome dos projetos.', extra:'cadastro' },
    { t:'Crie (ou separe) as contas abaixo. Anote cada e-mail e senha (a etapa "Ligar o GitHub e o Supabase" usa as contas do Supabase e do GitHub): na etapa "Guardar as contas e senhas" tudo vai para dentro do sistema do restaurante.', extra:'contas' }
   ] },

 { id:'supabase', titulo:'Criar o banco de dados', curto:'Projeto no Supabase', quem:'voce', tempo:'5 min', teste:'supabase', campos:['supabase_url','supabase_chave'],
   porque:'O Supabase é onde ficam guardados produtos, pedidos, clientes e caixa. Cada restaurante tem o seu, no plano grátis.',
   precisa:['O e-mail Google do restaurante'],
   partes:[
    { t:'Abra o Supabase e entre com o e-mail do restaurante (botão "Continue with Google"). Se pedir para criar uma organização, use o nome do restaurante e o plano "Free".', link:'https://supabase.com/dashboard/sign-in' },
    { t:'Toque em "New project". Name: {slug}. Database Password: toque em "Generate a password", COPIE e guarde (vai na etapa "Guardar as contas"). Region: "South America (São Paulo)". MARQUE a caixa "Enable automatic RLS" (RLS automático: protege as tabelas novas; fica na parte de baixo da janela, em opções de segurança). Só depois toque em "Create new project".', link:'https://supabase.com/dashboard/new', copiar:'{slug}' },
    { t:'Espere uns 2 minutos até o projeto ficar pronto (some o "Setting up project").' },
    { t:'Pegue o endereço: menu da esquerda → "Project Settings" (engrenagem) → "Data API" → copie o "Project URL" (https://….supabase.co) e cole no primeiro campo abaixo.', link:'https://supabase.com/dashboard/project/_/settings/api', extra:'campos:supabase_url' },
    { t:'Pegue a chave pública: "Project Settings" → "API Keys" → em "Publishable key" copie a chave que começa com sb_publishable_ e cole abaixo. Toque em "Salvar e testar".', link:'https://supabase.com/dashboard/project/_/settings/api-keys', extra:'campos:supabase_url,supabase_chave' },
    { t:'Bom saber: o plano grátis pausa o projeto depois de 7 dias sem uso. O sistema manda sinal a cada 15 minutos e isso o mantém vivo. Se um dia aparecer "Paused" no Supabase, abra o projeto e toque em "Restore project".' }
   ] },

 { id:'repositorio', titulo:'Criar o endereço do site', curto:'Repositório no GitHub', quem:'voce', tempo:'5 min', teste:'site', campos:['github_url','site_url'],
   porque:'O GitHub coloca o site no ar de graça. O endereço vai ser usuario.github.io/{slug}.',
   precisa:['Conta no GitHub (pode ser a sua)'],
   partes:[
    { t:'Entre no GitHub (ou crie a conta em github.com/signup). Toque no "+" lá em cima → "New repository".', link:'https://github.com/new' },
    { t:'Repository name: {slug}. Em "Choose visibility" deixe "Public". Role a tela e em "Add README" ligue a chave (de "Off" para "On"): é obrigatório, sem isso o repositório nasce vazio e o site não funciona. Toque em "Create repository".', copiar:'{slug}' },
    { t:'Copie o endereço da página do repositório que abriu (ex.: https://github.com/usuario/{slug}) e cole abaixo. Salve.', extra:'campos:github_url' },
    { t:'No repositório: no celular toque em "More" (menu à direita de "Actions") → "Settings" → "Pages". No computador, "Settings" já aparece na barra de cima. Em "Source" escolha "Deploy from a branch". Em "Branch" escolha "main" e a pasta "/ (root)". Toque em "Save".', link:'{github_url}/settings/pages' },
    { t:'Espere 1 minuto e atualize a página Pages: aparece "Your site is live at https://usuario.github.io/{slug}/". Copie esse endereço (com a barra no fim) e cole abaixo. Toque em "Salvar e testar".', link:'{github_url}/settings/pages', extra:'campos:github_url,site_url' },
    { t:'Só se for usar o Claude para gravar arquivos: GitHub → sua foto → Settings → Applications → "Claude" → Configure → libere o repositório {slug}. Fazendo sozinho, pule.', link:'https://github.com/settings/installations' }
   ] },

 { id:'conectar', titulo:'Ligar o GitHub e o Supabase', curto:'Os conectores: o painel faz o resto sozinho', opcional:true, quem:'voce', tempo:'5 min',
   porque:'Com os dois tokens do restaurante guardados no cofre do painel, o botão "Implantar tudo agora" monta o banco, publica as funções do servidor, cria os logins, gera as chaves de aviso e grava o site, tudo de uma vez (uns 6 a 10 minutos). Cada restaurante tem os seus tokens: ligar um não tira o outro. Se preferir, pule: todas as etapas seguintes continuam tendo o jeito manual.',
   precisa:['As contas do restaurante (etapa 1)','O projeto do Supabase e o repositório do GitHub já criados (etapas 2 e 3)','A função "conector" publicada no painel (Mais → Conectores → Preparar o painel, uma vez só)'],
   partes:[
    { t:'Siga o passo a passo abaixo: crie o token do Supabase e o do GitHub deste restaurante, cole cada um no seu campo e toque em Salvar. Depois toque em "Testar ligações": tem que aparecer ✅ nos dois.', extra:'conectar' },
    { t:'Com os dois ✅, preencha os 4 campos de "Implantar tudo" (login e senha do dono, o seu login e a sua senha de suporte) e toque em "⚡ Implantar tudo agora". Deixe a tela aberta até aparecer "Pronto". Depois da conferência automática, só faltam as etapas que dependem das suas contas: cores e logos, Entrar com o Google, Drive, chaves das IAs e planilhas (opcional).' }
   ] },

 { id:'banco', titulo:'Montar as tabelas do banco', curto:'Copiar e colar os códigos', quem:'voce', tempo:'25 min', teste:'banco',
   porque:'O banco vem vazio. Estes códigos criam todas as tabelas, regras de segurança e funções do sistema. ⚡ Se você tocar em "Implantar tudo agora" (etapa "Ligar o GitHub e o Supabase"), esta etapa é feita sozinha e já sai marcada.',
   precisa:['O banco criado (etapa 2)','A chave secreta do Supabase (a parte 2 mostra onde)','Paciência: são várias partes, uma de cada vez'],
   partes:[
    { t:'Com o Supabase ligado (etapa anterior), o painel monta tudo sozinho. Sem isso, pule esta parte e faça as seguintes à mão.', extra:'bancoauto' },
    { t:'Jeito manual: abra o SQL Editor do Supabase do restaurante (ícone de terminal no menu da esquerda) e toque em "New query". Deixe essa aba aberta: você vai voltar nela várias vezes.', link:SB + '/sql/new' },
    { t:'Um dos códigos (o "Cofre de chaves · parte 1") precisa da chave SECRETA do Supabase: "Project Settings" → "API Keys" → "Secret keys" → toque no olho ou em copiar (começa com sb_secret_; se não houver, toque em "New secret key"). Você cola ela no campo que aparece junto daquele código. Ela não fica guardada no painel.', link:SB + '/settings/api-keys' },
    { t:'Agora é sempre igual: toque em "Copiar código", vá ao SQL Editor, apague o que estiver lá, cole, toque em "Run" e espere "Success". Volte aqui e toque em "Já colei e rodei". Se aparecer "already exists", aquela parte já estava feita: só siga.', extra:'codigos' },
    { t:'Terminou todos? Toque em Testar. Tem que aparecer "Banco do sistema instalado".', extra:'teste' }
   ],
   pedido:'Aplique o banco completo do sistema no restaurante "{nome}" (código {slug}, projeto Supabase {ref}): estrutura, ajustes em ordem, cofre de chaves e conferência de segurança. Não use nenhum dado do Texas Burger.' },

 { id:'funcoes', titulo:'Publicar as funções do servidor', curto:'O painel publica sozinho (ou o GitHub)', quem:'voce', tempo:'10 min', teste:'funcoes',
   porque:'São os "robôs" do servidor: avisos no celular, backup, iFood, pagamentos e IAs. O próprio GitHub do restaurante publica as 33 funções: você só toca em um botão. ⚡ Se você tocar em "Implantar tudo agora" (etapa "Ligar o GitHub e o Supabase"), esta etapa é feita sozinha e já sai marcada.',
   precisa:['O repositório do GitHub (etapa 3)','O login do Supabase do restaurante'],
   partes:[
    { t:'Crie uma chave de acesso do Supabase: abra o link → "Generate new token" → nome: publicar-{slug} → validade: a maior que tiver → "Generate token". COPIE a chave (começa com sbp_). Ela só aparece uma vez.', link:'https://supabase.com/dashboard/account/tokens', copiar:'publicar-{slug}' },
    { t:'No GitHub: repositório {slug} → "More" (no celular) → "Settings" → "Secrets and variables" → "Actions" → "New repository secret". Em "Name" cole o nome abaixo. Em "Secret" cole a chave sbp_. Toque em "Add secret".', copiar:'SUPABASE_ACCESS_TOKEN', link:'{github_url}/settings/secrets/actions/new' },
    { t:'No repositório: "Add file" → "Create new file". No campo do nome cole o caminho abaixo (as barras criam as pastas sozinhas). No campo grande cole o conteúdo. Toque em "Commit changes" (duas vezes).', extra:'workflow', link:'{github_url}/new/main' },
    { t:'Abra a aba "Actions" do repositório. Se aparecer um botão verde "I understand my workflows, go ahead and enable them", toque nele. Depois toque em "Publicar funções do servidor" → "Run workflow" → "Run workflow" (verde).', link:'{github_url}/actions' },
    { t:'Espere 3 a 5 minutos até aparecer o ✓ verde. Se aparecer ✗ vermelho, toque nele → "publicar" → copie o erro e mande ao Claude. Depois toque em Testar: tem que aparecer "Funções do servidor respondendo". Quando o sistema ganhar funções novas, é só repetir a parte 4.', extra:'teste' }
   ],
   pedido:'Publique as 33 funções do servidor (edge functions) no projeto Supabase {ref} do restaurante "{nome}" ({site_url}), com verify_jwt desligado e o segredo SITE_URL, e confira que a função ping responde.' },

 { id:'admin', titulo:'Criar os logins', curto:'Administrador do dono e o seu de suporte', quem:'voce', tempo:'5 min',
   porque:'O Administrador é o login do dono. O Desenvolvedor é o SEU login de suporte: entra mesmo com o restaurante bloqueado e sem a tela dos termos. ⚡ Se você tocar em "Implantar tudo agora" (etapa "Ligar o GitHub e o Supabase"), esta etapa é feita sozinha e já sai marcada.',
   precisa:['Escolher login e senha do dono','Sua senha de Desenvolvedor'],
   partes:[
    { t:'Rode os 4 códigos abaixo no SQL Editor, na ordem. No 2º, escreva o login e a senha do dono nos campos (a senha precisa de 8 letras ou números) e o código já sai pronto. No 4º, escreva a SUA senha de Desenvolvedor. Nada disso fica guardado no painel.', extra:'codigos', link:SB + '/sql/new' },
    { t:'Teste: abra o site → "Área de Funcionários" (no rodapé do cardápio) → entre com o login do dono. Depois saia e entre com o login Lucas. Anote o login e a senha do dono para entregar a ele: ele pode trocar a senha depois.', link:'{site_url}' }
   ],
   pedido:'Crie o primeiro Administrador do restaurante "{nome}" (projeto {ref}) com o login: ________ e o meu login de Desenvolvedor (Lucas). Gere a senha do Administrador e me entregue só a mim.' },

 { id:'push', titulo:'Avisos no celular', curto:'O painel gera as chaves para você', quem:'voce', tempo:'3 min', campos:['push_chave_publica'],
   porque:'Faz o celular da equipe apitar quando chega pedido e avisa o cliente quando o pedido sai. ⚡ Se você tocar em "Implantar tudo agora" (etapa "Ligar o GitHub e o Supabase"), esta etapa é feita sozinha e já sai marcada.',
   precisa:['Nada: o painel cria as chaves'],
   partes:[
    { t:'Toque em "Gerar chaves agora". O painel cria as duas chaves deste restaurante e já guarda a pública.', extra:'push' },
    { t:'Copie o código que apareceu e rode no SQL Editor do Supabase do restaurante. Ele guarda as chaves no cofre do banco (a privada nunca fica no site). Se o site já estiver no ar, baixe de novo o config-restaurante.js e suba por cima.', link:SB + '/sql/new' }
   ],
   pedido:'Gere as chaves de aviso no celular (VAPID) do restaurante "{nome}" (projeto {ref}), guarde-as no Vault (vapid_publica e vapid_privada) e me devolva a chave pública.' },

 { id:'marca', titulo:'Cores e logos', curto:'A cara do restaurante', quem:'voce', tempo:'15 min',
   porque:'Deixa o sistema com as cores e a logo do restaurante. Muda na hora, sem mexer no site.',
   precisa:['3 imagens: logo principal, logo de impressão e ícone (o painel ensina a pedir ao ChatGPT)'],
   partes:[
    { t:'Escolha um tema pronto ou ajuste as 3 cores. Escreva o slogan e o nome do atendente virtual. Toque em Salvar.', extra:'marca' },
    { t:'Agora as logos. Cada uma tem um jeito certo: toque em "Como deve ser" para ver as regras e o texto pronto para pedir ao ChatGPT. Depois envie cada imagem.', extra:'logos' }
   ] },

 { id:'modulos', titulo:'Módulos contratados', curto:'Ligue só o que ele usa', quem:'voce', tempo:'1 min',
   porque:'Desligado, a tela some e não gasta nada do servidor. Dá para ligar depois, na hora.',
   precisa:['Saber o que o restaurante contratou'],
   partes:[ { t:'Ligue só o que o restaurante contratou e toque em Salvar. iFood, nota fiscal, Mercado Pago e InfinitePay só funcionam depois que o restaurante cadastrar as contas dele no sistema (Administrador → Sistema → Integrações e contas).', extra:'modulos' } ] },

 { id:'publicar', titulo:'Colocar o site no ar', curto:'4 arquivos no GitHub', quem:'voce', tempo:'5 min', teste:'site',
   porque:'O site do restaurante é só uma "porta" com 4 arquivos pequenos. O sistema em si vem do motor e se atualiza sozinho. ⚡ Se você tocar em "Implantar tudo agora" (etapa "Ligar o GitHub e o Supabase"), esta etapa é feita sozinha e já sai marcada.',
   precisa:['Banco, endereço do site e marca feitos'],
   partes:[
    { t:'Com o GitHub ligado, o painel grava os 4 arquivos sozinho. Sem isso, pule esta parte e use o jeito manual.', extra:'publicarauto' },
    { t:'Jeito manual: baixe os 4 arquivos abaixo (um toque em cada). Eles já saem prontos para este restaurante. "Onde colocar" diz o lugar de cada um no GitHub.', extra:'publicar' },
    { t:'No GitHub: repositório {slug} → "Add file" → "Upload files" → escolha os 4 arquivos de uma vez → "Commit changes". Eles ficam na RAIZ (a primeira página do repositório, sem pasta). Se já existirem, o GitHub troca pelos novos.', link:'{github_url}/upload/main' },
    { t:'Espere 1 a 2 minutos e toque em "Conferir o site": o painel abre cada arquivo no ar e diz se está certo. Depois abra o site: tem que aparecer o cardápio com o nome e as cores do restaurante.', extra:'conferir', link:'{site_url}' },
    { t:'Para o futuro: cores, logos e módulos mudam pelo painel, na hora. Se mudar endereço do Supabase, planilhas ou avisos, baixe de novo só o config-restaurante.js e suba por cima.' }
   ],
   pedido:'Grave no repositório do restaurante "{nome}" ({github_url}) os arquivos index.html, sw.js, manifest.webmanifest e config-restaurante.js que o painel gera para ele. Confirme se publicou e abriu sem erro.' },

 { id:'entrada', titulo:'Entrar com o Google', curto:'Login do cliente com a conta Google', quem:'voce', tempo:'25 min',
   porque:'Deixa o cliente entrar no cardápio com a conta Google (para cupons e carimbos) e prepara o backup no Drive.',
   precisa:['O e-mail Google do restaurante','O site já no ar (etapa anterior)'],
   partes:[
    { t:'SUPABASE → Authentication → URL Configuration. Em "Site URL" cole o primeiro endereço abaixo. Em "Redirect URLs" toque em "Add URL", cole o segundo e salve. Com o conector do Supabase ligado, basta tocar no botão abaixo.', link:SB + '/auth/url-configuration', copiar:'{site_url}\n{site_url}**', extra:'loginurls' },
    { t:'GOOGLE CLOUD: entre com o e-mail do restaurante e crie um projeto: nome {slug} → Criar. Confira no alto da tela que ele ficou selecionado.', link:'https://console.cloud.google.com/projectcreate', copiar:'{slug}' },
    { t:'Abra "Google Auth Platform" → "Começar". Nome do app: {nome}. E-mail de suporte: o do restaurante. Público: "Externo". E-mail de contato: o mesmo. Aceite e toque em "Criar".', link:'https://console.cloud.google.com/auth/overview', copiar:'{nome}' },
    { t:'O Google exige uma página de privacidade. O painel gera para você: toque no botão abaixo, baixe o privacidade.html e suba no GitHub do restaurante NA RAIZ (mesmo lugar do index.html): "Add file" → "Upload files" → escolha o arquivo → "Commit changes".', extra:'privacidade', link:'{github_url}/upload/main' },
    { t:'"Branding" (Identidade visual): preencha os 3 endereços abaixo (página inicial, política de privacidade e, em "Domínios autorizados", só o domínio, sem https). Salve. Não toque em "Ver problemas".', link:'https://console.cloud.google.com/auth/branding', copiar:'{site_url}\n{site_url}privacidade.html\n{dominio_site}' },
    { t:'"Público-alvo" (Audience): toque em "Publicar app" e confirme. Sem isso só e-mails de teste conseguem entrar.', link:'https://console.cloud.google.com/auth/audience' },
    { t:'"Clientes" → "Criar cliente": tipo "Aplicativo da Web", nome "Login do sistema".', link:'https://console.cloud.google.com/auth/clients/create', copiar:'Login do sistema' },
    { t:'Em "Origens JavaScript autorizadas" (campo de cima) adicione SÓ o endereço abaixo (sem barra no fim).', copiar:'{site_origem}' },
    { t:'Em "URIs de redirecionamento autorizados" (campo de baixo) adicione os DOIS endereços abaixo, um de cada vez. Toque em "Criar".', copiar:'{supabase_url}/auth/v1/callback\n{supabase_url}/functions/v1/drive-oauth' },
    { t:'Vai aparecer o "ID do cliente" (termina em .apps.googleusercontent.com) e a "Chave secreta do cliente" (começa com GOCSPX-). Copie os dois e GUARDE: a etapa do Drive usa os mesmos. A chave secreta só aparece inteira agora.' },
    { t:'Volte ao SUPABASE → Authentication → Sign In / Providers → Google → ligue "Enable Sign in with Google", cole o ID do cliente e a chave secreta → Save. Com o conector do Supabase ligado, use o jeito rápido abaixo (ele também guarda as credenciais para o Drive).', link:SB + '/auth/providers', extra:'googleauto' },
    { t:'Teste: abra o site, toque em "Entrar" no cardápio e entre com um e-mail Google. Erro "redirect_uri_mismatch" = algum endereço da parte 9 está diferente. "Acesso bloqueado" = falta publicar o app (parte 6).', link:'{site_url}' },
    { t:'(Recomendado, tira o aviso "app não verificado") Search Console com o MESMO e-mail → "Adicionar propriedade" → "Prefixo do URL" → cole {site_url} → método "Arquivo HTML" → baixe o google….html → suba NA RAIZ do GitHub (igual ao privacidade.html) → volte e toque em "Verificar". Depois, no Google Cloud → Branding → "Ver problemas" → "Corrigi os problemas". Nunca apague esse arquivo.', link:'https://search.google.com/search-console/welcome' }
   ],
   pedido:'Publique no site do restaurante "{nome}" ({site_url}) a página privacidade.html gerada pelo painel e, se eu mandar, o arquivo google….html do Search Console, os dois na raiz do repositório.' },

 { id:'drive', titulo:'Backup no Google Drive', curto:'Cópias de segurança automáticas', quem:'voce', tempo:'10 min',
   porque:'O sistema guarda cópias de segurança no Drive do restaurante. Se algo der errado, dá para voltar.',
   precisa:['O ID do cliente e a chave secreta (etapa anterior)','Login de Administrador do sistema'],
   partes:[
    { t:'Se o restaurante NÃO vai usar backup no Drive, toque em "Pular" lá embaixo.' },
    { t:'Google Cloud (mesmo projeto): ative a "Google Drive API" → toque em "Ativar".', link:'https://console.cloud.google.com/apis/library/drive.googleapis.com' },
    { t:'Google Auth Platform → "Acesso a dados" → "Adicionar ou remover escopos" → no filtro escreva drive → marque o que termina em /auth/drive → "Atualizar" → "Salvar". Ignore o aviso de "escopo não verificado".', link:'https://console.cloud.google.com/auth/scopes' },
    { t:'Cole o ID do cliente e a chave secreta nos campos do código abaixo (copie do Google pelo botão de copiar, nunca digite: l, I e 1 se confundem). Toque em "Copiar código" e rode no SQL Editor.', extra:'codigos', link:SB + '/sql/new' },
    { t:'Entre no sistema como Administrador → Sistema → Backup e espaço → cartão "Google Drive" → "Conectar o Drive principal". Escolha a conta do restaurante. Na tela "O Google não verificou este app": "Avançado" → "Acessar". Volta com "Drive principal conectado". Se usar contingência, repita em "Drive da contingência" com a OUTRA conta.', link:'{site_url}' }
   ],
   pedido:'Guarde no cofre (Vault) do Supabase do restaurante "{nome}" (projeto {ref}) as chaves google_client_id e google_client_secret. ID do cliente: ________  Chave secreta: ________  Depois confira que a função drive-api responde.' },

 { id:'ia', titulo:'Chaves do atendente virtual', curto:'IAs grátis do restaurante', quem:'voce', tempo:'15 min', modulo:'ia',
   porque:'O atendente responde os clientes no cardápio. Cada restaurante precisa das PRÓPRIAS chaves (cada chave grátis tem a sua cota).',
   precisa:['O e-mail do restaurante','Login de Administrador do sistema'],
   partes:[
    { t:'Se o módulo "Assistente virtual" estiver desligado, toque em "Pular". O mínimo é GROQ + GEMINI. As outras são reserva: entram quando uma falha ou acaba a cota. Copie cada chave assim que aparecer (algumas só aparecem uma vez).' },
    { t:'GROQ: entre com o e-mail do restaurante → "Create API Key" → nome {slug} → copie (começa com gsk_).', link:'https://console.groq.com/keys' },
    { t:'GROQ 2 (reserva): mesmo site, mas com OUTRA conta (outro e-mail) → crie e copie outra chave gsk_.', link:'https://console.groq.com/keys' },
    { t:'GEMINI: "Criar chave de API" → "Criar chave em um novo projeto" → copie (começa com AIza ou AQ.).', link:'https://aistudio.google.com/apikey' },
    { t:'GEMINI 2 (reserva): de novo "Criar chave de API", mas escolha criar em OUTRO projeto novo (assim tem cota própria).', link:'https://aistudio.google.com/apikey' },
    { t:'CLOUDFLARE (reserva, 2 dados): crie a conta, abra o painel e copie o código de 32 letras e números que aparece na barra de endereço (é o Account ID). Depois: perfil → "API Tokens" → "Create Token" → modelo "Workers AI" → "Continue to summary" → "Create Token" → copie (começa com cfut_).', link:'https://dash.cloudflare.com/profile/api-tokens' },
    { t:'NVIDIA (reserva mais lenta): crie a conta e confirme o e-mail → "Generate API Key" → copie (começa com nvapi-).', link:'https://build.nvidia.com/settings/api-keys' },
    { t:'Entre no sistema do restaurante como Administrador → Sistema → Integrações e contas → "Chaves das IAs". Em cada uma: colar, digitar a senha de administrador, salvar e tocar em "Testar" (tem que aparecer "Funcionando"). No Cloudflare cole o Account ID e o token.', link:'{site_url}' },
    { t:'Teste final: no cardápio, toque no botão do atendente e pergunte "qual o horário?". Se responder, está pronto.', link:'{site_url}' }
   ] },

 { id:'planilhas', titulo:'Planilhas Google de reserva', curto:'Obrigatório: reserva para vender se o banco cair', quem:'voce', tempo:'30 min', campos:['contingencia_url','contingencia_chave','api_url'],
   porque:'Uma cópia do sistema em planilhas do Google. Se o banco cair, o cardápio continua mostrando os produtos e recebendo pedidos numa fila. É OBRIGATÓRIO em todos os restaurantes: nenhum restaurante é entregue sem as planilhas funcionando.',
   precisa:['Duas contas Google: a do restaurante (principal) e OUTRA (contingência)','Um computador ajuda, mas dá pelo navegador do celular em modo "versão para computador"'],
   partes:[
    { t:'As planilhas são obrigatórias em todos os restaurantes. Comece pela CONTINGÊNCIA, na OUTRA conta Google.' },
    { t:'CONTINGÊNCIA (outra conta): crie uma planilha nova com o nome "Contingência {nome}". Menu "Extensões" → "Apps Script". Apague tudo, cole o código abaixo e toque no disquete (Salvar).', link:'https://sheets.new', extra:'cod:gs-modelo-contingencia' },
    { t:'Ainda na contingência: lá em cima, na lista de funções, escolha "setup" e toque em "Executar". Na primeira vez: "Revisar permissões" → escolha a conta → "Avançado" → "Acessar (não seguro)" → "Permitir".' },
    { t:'Escolha a função "gerarChaves" → "Executar". Embaixo, no "Registro de execução", aparecem 3 chaves. Cole a CONTINGENCIA_CHAVE_PUBLICA no campo abaixo e salve. Guarde as outras duas (SERVIDOR e INTERNA) para a parte 7.', extra:'campos:contingencia_chave' },
    { t:'"Implantar" → "Nova implantação" → engrenagem → "App da Web". Executar como: "Eu". Quem pode acessar: "Qualquer pessoa". "Implantar" → copie o endereço que termina em /exec e cole abaixo.', extra:'campos:contingencia_url' },
    { t:'PRINCIPAL (conta do restaurante): planilha nova "Principal {nome}" → "Extensões" → "Apps Script" → apague tudo e cole o código abaixo. Procure a linha  const CONTINGENCIA_API_URL = \'\';  e cole o endereço /exec da contingência entre as aspas. Salve.', link:'https://sheets.new', extra:'cod:gs-modelo-principal' },
    { t:'Na principal: rode a função "configurarIdPlanilha" (autorize igual à parte 3). Depois engrenagem "Configurações do projeto" → "Propriedades do script" → "Adicionar propriedade" duas vezes: CONTINGENCIA_CHAVE_SERVIDOR e CONTINGENCIA_CHAVE_INTERNA, com os valores da parte 4. Salve. Rode "conferirChavesContingencia": os 3 testes têm que dar OK.', copiar:'CONTINGENCIA_CHAVE_SERVIDOR\nCONTINGENCIA_CHAVE_INTERNA' },
    { t:'Na principal: "Implantar" → "Nova implantação" → "App da Web" (Executar como "Eu", acesso "Qualquer pessoa") → copie o /exec e cole abaixo. Salve.', extra:'campos:api_url' },
    { t:'No SQL Editor do Supabase rode o código abaixo (ele já vem com o /exec da principal). No resultado aparece uma chave: copie. Na principal → "Propriedades do script" → adicione SB_CHAVE_SERVIDOR com essa chave. Depois "Implantar" → "Gerenciar implantações" → lápis → Versão "Nova versão" → "Implantar".', extra:'cod:segredos2', copiar:'SB_CHAVE_SERVIDOR' },
    { t:'Os endereços e a chave pública vão no config-restaurante.js. Se o site já estiver no ar, baixe de novo só esse arquivo (etapa "Colocar o site no ar") e suba por cima no GitHub.' }
   ] },

 { id:'leitura', titulo:'Ligar o assistente do painel', curto:'Para a sua IA ler os dados dele', quem:'voce', tempo:'3 min',
   porque:'Deixa o assistente do SEU painel responder coisas como "quanto esse restaurante vendeu na semana?". É só leitura: nunca muda nada e não vê telefone nem endereço de cliente.',
   precisa:['Banco do restaurante pronto'],
   partes:[
    { t:'Rode no SQL Editor do Supabase do restaurante o código abaixo. Restaurantes novos já vêm com ele; rodar de novo não faz mal.', extra:'codigos', link:SB + '/sql/new' },
    { t:'Toque em "Gerar chave de leitura". Copie o código que aparecer, rode também no SQL Editor e toque em "Testar a leitura".', extra:'leitura' }
   ] },

 { id:'contas', titulo:'Guardar as contas e senhas', curto:'Para o dono nunca perder um acesso', quem:'voce', tempo:'10 min',
   porque:'Tudo o que foi criado fica anotado dentro do sistema do restaurante, com as senhas protegidas no cofre do banco.',
   precisa:['Login de Administrador do sistema'],
   partes:[
    { t:'Entre no sistema do restaurante como Administrador → Sistema → Integrações e contas → "Contas e acessos".', link:'{site_url}' },
    { t:'Crie um cartão para cada item da lista abaixo (e-mail, link e observação). As senhas você digita em "Editar": ficam no cofre do banco, nunca no site, e só o Administrador vê, com a senha dele.', extra:'listacontas' }
   ] },

 { id:'teste', titulo:'Teste completo', curto:'Confira tudo antes de entregar', quem:'voce', tempo:'25 min',
   porque:'Garante que o cliente não vai encontrar nada quebrado.',
   precisa:['Um celular (de preferência Android)'],
   checklist:['Abrir o site no celular: nome, cores e logo certos (nada de outro restaurante)','Cadastrar um produto com foto e ver no cardápio','Fazer um pedido pelo cardápio e ver na tela da cozinha','Imprimir uma comanda e conferir a logo de impressão','Entrar com o Google no cardápio','Instalar o app pelo navegador e conferir ícone e nome','Ativar os avisos e receber um aviso de pedido no celular','Perguntar algo ao atendente virtual no cardápio','Abrir e fechar o caixa','Gerar um backup em Backup e espaço','Abrir a Ajuda e ver as imagens','Entrar com o seu login de Desenvolvedor','Perguntar ao assistente do painel quanto este restaurante vendeu','Apagar os dados de teste (produto de teste, pedido, caixa)'],
   partes:[ { t:'Primeiro o painel confere sozinho o lado técnico (banco, funções, site, motor, GitHub e atualizações). Só lê, não muda nada.', extra:'testetudo' }, { t:'Agora faça cada teste no celular e marque. Só dá para concluir quando todos estiverem marcados.', extra:'checklist' } ] },

 { id:'entrega', titulo:'Entregar ao cliente', curto:'Equipe, mensagem, termos e cobrança', quem:'voce', tempo:'20 min',
   porque:'O restaurante começa a usar e você começa a receber.',
   precisa:['Seus dados preenchidos em Mais → Meus dados (vão nos termos)'],
   partes:[
    { t:'Com o dono, crie os usuários da equipe: Administrador → Loja e equipe → "Usuários e permissões" → "+ Novo acesso" (Operador para o caixa, Cozinha, Garçom e Entregador). Mostre onde fica a Ajuda.', link:'{site_url}' },
    { t:'Mande a mensagem de boas-vindas ao dono pelo WhatsApp (o painel monta). A senha mande separada, em outra mensagem.', extra:'boasvindas' },
    { t:'Marque como entregue: no primeiro acesso o dono lê e aceita os termos de uso (com foto e assinatura).', extra:'contrato' },
    { t:'Gere a taxa de implantação e a primeira mensalidade e mude a situação para "Ativo". Pronto! 🎉', extra:'cobranca' }
   ] }
];
window.FASES = [['Banco',['cadastro','supabase','repositorio','conectar','banco','funcoes','admin']],['Site no ar',['push','marca','modulos','publicar']],['Google',['entrada','drive','planilhas']],['Extras',['ia','leitura']],['Entrega',['contas','teste','entrega']]];
