/* PAINEL DE REVENDA — cadastro e implantação dos restaurantes. Sem biblioteca externa. */
(function(){
'use strict';
const URL_ = window.REVENDA_URL, CHAVE_ = window.REVENDA_CHAVE;
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const BRL = v => 'R$ ' + (Number(v) || 0).toFixed(2).replace('.', ',').replace(/\B(?=(\d{3})+(?!\d))/g, '.');
const SIT = { implantacao:'Em implantação', teste:'Em teste', ativo:'Ativo', suspenso:'Suspenso', encerrado:'Encerrado' };
let S = { sess:null, lista:[], cob:[], rest:null, aba:'dados', cobR:[], hist:[], dono:null, erros:[], saude:{} };
let timerAviso = null;
function aviso(m, t){ const a = $('aviso'); a.textContent = m; a.className = 'aviso ' + (t || ''); a.hidden = false; clearTimeout(timerAviso); timerAviso = setTimeout(() => { a.hidden = true; }, t === 'erro' ? 9000 : 3500); }
const erro = m => aviso('⚠️ ' + m, 'erro');

/* ---------- acesso ao banco (REST puro) ---------- */
function sessLer(){ try{ return JSON.parse(localStorage.getItem('rv_sess') || 'null'); }catch(e){ return null; } }
function sessGravar(s){ S.sess = s; try{ if(s) localStorage.setItem('rv_sess', JSON.stringify(s)); else localStorage.removeItem('rv_sess'); }catch(e){} }
async function renovar(){
  if(!S.sess || !S.sess.refresh_token) return false;
  try{
    const r = await fetch(URL_ + '/auth/v1/token?grant_type=refresh_token', { method:'POST', headers:{ apikey:CHAVE_, 'Content-Type':'application/json' }, body:JSON.stringify({ refresh_token:S.sess.refresh_token }) });
    const j = await r.json(); if(!r.ok || !j.access_token) return false;
    sessGravar({ access_token:j.access_token, refresh_token:j.refresh_token, exp: Date.now() + (j.expires_in - 60) * 1000, email:(j.user && j.user.email) || S.sess.email }); return true;
  }catch(e){ return false; }
}
async function req(caminho, o){
  o = o || {};
  if(S.sess && Date.now() > S.sess.exp){ if(!await renovar()){ sessGravar(null); tela(); throw new Error('Sua sessão expirou. Entre de novo.'); } }
  const h = Object.assign({ apikey:CHAVE_, 'Content-Type':'application/json' }, o.headers || {});
  if(S.sess) h.Authorization = 'Bearer ' + S.sess.access_token;
  let r; try{ r = await fetch(URL_ + caminho, { method:o.method || 'GET', headers:h, body:o.body }); }catch(e){ throw new Error('Sem conexão com o banco central. Confira a internet e tente de novo.'); }
  const txt = await r.text(); let j = null; try{ j = txt ? JSON.parse(txt) : null; }catch(e){}
  if(!r.ok){ throw new Error((j && (j.message || j.msg || j.error_description || j.hint)) || ('Erro ' + r.status)); }
  return j;
}
const rest = (q, m, b, extra) => req('/rest/v1/' + q, { method:m, body: b ? JSON.stringify(b) : undefined, headers:Object.assign({ Prefer:'return=representation' }, extra || {}) });
const rpc = (fn, a) => req('/rest/v1/rpc/' + fn, { method:'POST', body:JSON.stringify(a || {}) });

async function entrar(email, senha, criar){
  if(!email || !senha) throw new Error('Preencha o e-mail e a senha' + (criar ? ' que você quer usar como dono e toque em "Criar a conta do dono".' : '.'));
  if(criar && senha.length < 8) throw new Error('Use uma senha de pelo menos 8 caracteres.');
  const r = await fetch(URL_ + (criar ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password'), { method:'POST', headers:{ apikey:CHAVE_, 'Content-Type':'application/json' }, body:JSON.stringify({ email, password:senha }) });
  const j = await r.json().catch(() => ({}));
  if(!r.ok) throw new Error(/invalid login/i.test(j.msg || j.error_description || j.message || '') ? 'E-mail ou senha incorretos.' : (j.msg || j.error_description || j.message || 'Não foi possível entrar.'));
  if(!j.access_token) throw new Error('Conta criada. Abra o e-mail de confirmação que o Supabase enviou, confirme e depois entre.');
  sessGravar({ access_token:j.access_token, refresh_token:j.refresh_token, exp: Date.now() + (j.expires_in - 60) * 1000, email });
}

/* ---------- dados ---------- */
async function carregar(){
  const [l, c] = await Promise.all([ rest('restaurantes?select=*&order=nome.asc'), rest('cobrancas?select=*&order=competencia.desc') ]);
  S.lista = l || []; S.cob = c || [];
  try{ S.erros = await rest('erros_app?select=*&resolvido=eq.false&order=ultimo_em.desc&limit=200') || []; }catch(e){ S.erros = []; }
  try{ S.saude = {}; (await rest('saude_app?select=*') || []).forEach(x => { S.saude[x.slug] = x; }); }catch(e){ S.saude = {}; }
}
/* ---------- saúde e uso do Supabase (enviados pelos restaurantes a cada 15 minutos) ---------- */
const SAUDE_COR = { ok:'#2f9e44', atencao:'#f0a500', problema:'#e5484d', sem:'#777' }, SAUDE_ROT = { ok:'Tudo certo', atencao:'Atenção', problema:'Precisa de cuidado', sem:'Sem sinal' };
function saudeDe(slug){ const h = S.saude && S.saude[slug]; if(!h) return { geral:'sem', min:null, h:null }; const min = Math.round((Date.now() - new Date(h.atualizado_em).getTime()) / 60000); return { geral: min > 45 ? 'sem' : (h.geral || 'ok'), min, h }; }
const haTempo = m => m == null ? 'nunca' : m < 1 ? 'agora' : m < 60 ? 'há ' + m + ' min' : m < 1440 ? 'há ' + Math.round(m / 60) + ' h' : 'há ' + Math.round(m / 1440) + ' d';
function usoDe(h){ return ((h && h.itens) || []).filter(i => /^Plano grátis:/i.test(i.titulo || '')).map(i => {
  const m = String(i.texto || '').match(/^(?:Cerca de\s+)?([\d.,]+(?:\s*[A-Za-z]+)?)(?:\s+por mês)?,?\s+de\s+([\d.,]+(?:\s*[A-Za-z]+)?)(?:\s*\(([\d.,]+)%\))?/i); if(!m) return null;
  const num = x => parseFloat(String(x).replace(/[^\d.,]/g, '').replace(/\.(?=\d{3}\b)/g, '').replace(',', '.')), uso = m[1].replace(/[.,]$/, ''), lim = m[2].replace(/[.,]$/, '');
  const pct = m[3] ? parseFloat(m[3].replace(',', '.')) : num(uso) / num(lim) * 100; if(!isFinite(pct)) return null;
  return { id:i.id, tit:String(i.titulo).replace(/^Plano grátis:\s*/i, '').replace(/^./, c => c.toUpperCase()), uso, lim, pct:Math.round(pct * 10) / 10 }; }).filter(Boolean); }
function barraUso(u){ const cor = u.pct >= 90 ? SAUDE_COR.problema : u.pct >= 70 ? SAUDE_COR.atencao : SAUDE_COR.ok;
  return '<div style="margin:10px 0 2px"><div class="linha" style="gap:8px"><b style="font-size:14px">' + esc(u.tit) + '</b><small>' + esc(u.uso) + ' de ' + esc(u.lim) + ' · <b style="color:' + cor + '">' + String(u.pct).replace('.', ',') + '%</b></small></div><div class="barra"><i style="width:' + Math.min(100, u.pct) + '%;background:' + cor + '"></i></div></div>'; }
const nEtapas = r => ETAPAS.filter(e => r.etapas && r.etapas[e.id] && r.etapas[e.id].feita).length;
const hoje = () => new Date().toISOString().slice(0, 10);
const atrasadas = id => S.cob.filter(c => (!id || c.restaurante_id === id) && !c.pago_em && c.vencimento && c.vencimento < hoje());
const refDe = r => (r.supabase_url || '').replace(/^https?:\/\//, '').split('.')[0] || '(ainda não criado)';

/* ---------- telas ---------- */
function tela(){
  if(!S.sess) return telaLogin();
  if(S.dono === null) return donoVerificar();
  if(!S.dono) return telaSemDono();
  S.rest ? telaRest() : telaLista();
}
async function donoVerificar(){
  $('app').innerHTML = '<div class="carregando">Carregando…</div>';
  try{
    const a = await rest('admins?select=user_id'); S.dono = !!(a && a.length);
    if(!S.dono){ const tem = await rpc('revenda_tem_dono'); if(!tem){ const r = await rpc('revenda_primeiro_acesso'); S.dono = !!(r && r.ok); } }
    if(S.dono){ await carregar(); }
    tela();
  }catch(e){ erro(e.message); $('app').innerHTML = '<div class="login card"><p>Não foi possível abrir o painel.</p><button onclick="location.reload()">Tentar de novo</button> <button onclick="rvSair()">Sair</button></div>'; }
}
function telaSemDono(){ $('app').innerHTML = '<div class="login card"><h2>Acesso negado</h2><p>Este painel já tem um dono e a sua conta não é essa.</p><button onclick="rvSair()">Sair</button></div>'; }
function telaLogin(){
  $('app').innerHTML = '<div class="login card"><h1>Painel de Revenda</h1><p class="mudo">Gerencie seus restaurantes e crie novos.</p>'
   + '<label for="lgE">E-mail</label><input id="lgE" type="email" autocomplete="username"><label for="lgS">Senha</label><input id="lgS" type="password" autocomplete="current-password">'
   + '<p style="margin-top:14px"><button class="principal" id="lgB" style="width:100%">Entrar</button></p>'
   + '<p class="mudo" style="font-size:13px">Primeiro acesso? <a href="#" id="lgC" style="color:var(--cor)">Criar a conta do dono</a> (só funciona enquanto o painel não tem dono).</p></div>';
  const go = async criar => { const b = $('lgB'); b.disabled = true; try{ await entrar($('lgE').value.trim(), $('lgS').value, criar); S.dono = null; tela(); }catch(e){ erro(e.message); } b.disabled = false; };
  $('lgB').onclick = () => go(false); $('lgC').onclick = ev => { ev.preventDefault(); go(true); };
  $('lgS').onkeydown = ev => { if(ev.key === 'Enter') go(false); };
}
window.rvSair = () => { sessGravar(null); S = { sess:null, lista:[], cob:[], rest:null, aba:'dados', cobR:[], hist:[], dono:null, erros:[], saude:{} }; tela(); };

function telaLista(){
  const at = S.lista.filter(r => r.situacao === 'ativo'), im = S.lista.filter(r => ['implantacao','teste'].includes(r.situacao));
  const mrr = at.reduce((s, r) => s + (Number(r.valor_mensal) || 0), 0), atr = atrasadas();
  $('app').innerHTML = '<div class="topo"><h1>Restaurantes</h1><div class="acoes"><button class="principal" onclick="rvNovo()">+ Novo restaurante</button><button onclick="rvSair()">Sair</button></div></div>'
   + '<div class="resumo"><div class="card"><small>Ativos</small><b>' + at.length + '</b></div><div class="card"><small>Em implantação / teste</small><b>' + im.length + '</b></div>'
   + '<div class="card"><small>Receita mensal</small><b>' + BRL(mrr) + '</b></div><div class="card"><small>Mensalidades em atraso</small><b style="color:' + (atr.length ? 'var(--erro)' : 'inherit') + '">' + atr.length + '</b></div></div>'
   + '<div class="card"><div class="linha"><b>Erros do sistema</b><span class="selo" style="' + (S.erros.length ? 'background:var(--erro);color:#000' : '') + '">' + (S.erros.length ? S.erros.length + ' aberto(s)' : 'nenhum') + '</span></div><small class="mudo">Erros que apareceram na tela dos restaurantes.</small><p style="margin:8px 0 0"><button class="mini' + (S.erros.length ? ' principal' : '') + '" onclick="rvErros()">Ver erros</button></p></div>'
   + (S.lista.length ? '<div class="grade">' + S.lista.map(r => {
      const n = nEtapas(r), p = Math.round(n / ETAPAS.length * 100), a = atrasadas(r.id).length;
      return '<div class="card"' + (r.bloqueado ? ' style="border-color:var(--erro)"' : '') + '><div class="linha"><b>' + esc(r.nome) + '</b>' + (r.bloqueado ? '<span class="selo" style="background:var(--erro);color:#000">⛔ Bloqueado</span>' : '<span class="selo ' + esc(r.situacao) + '">' + esc(SIT[r.situacao]) + '</span>') + '</div>'
       + '<small class="mudo">' + esc(r.dominio || r.slug) + '</small>'
       + '<div class="barra"><i style="width:' + p + '%"></i></div><small>Implantação ' + n + ' de ' + ETAPAS.length + ' · ' + p + '%</small>'
       + saudeHtml(r, true)
       + '<p class="mudo" style="margin:8px 0 10px;font-size:13px">' + (r.valor_mensal ? BRL(r.valor_mensal) + '/mês' : 'Sem mensalidade definida') + (a ? ' · <b style="color:var(--erro)">' + a + ' em atraso</b>' : '') + '</p>'
       + '<button class="mini principal" onclick="rvAbrir(\'' + r.id + '\')">Gerenciar</button> '
       + (r.site_url ? '<a class="btn mini" style="text-decoration:none;display:inline-block;padding:6px 10px" href="' + esc(r.site_url) + '" target="_blank" rel="noopener">Abrir site</a>' : '') + '</div>';
     }).join('') + '</div>' : '<div class="card">Nenhum restaurante ainda. Toque em "+ Novo restaurante".</div>');
  medirContingencia_(S.lista);
}
window.rvNovo = async () => {
  const nome = (prompt('Nome do restaurante:') || '').trim(); if(!nome) return;
  let slug = (prompt('Código do restaurante (letras minúsculas, números e hífen; vai no endereço):', nome.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40)) || '').trim().toLowerCase();
  if(!slug) return;
  try{
    const mod = {}; MODULOS.forEach(m => { mod[m.id] = m.pad; });
    const r = await rest('restaurantes', 'POST', { slug, nome, modulos:mod, marca:{ tema:'brasa', slogan:'', assistente:'Assistente', cores:{ destaque:TEMAS[0].destaque, botao:TEMAS[0].botao, fundo:TEMAS[0].fundo } }, etapas:{ cadastro:{ feita:true, em:new Date().toISOString() } } });
    await hist(r[0].id, 'Restaurante criado', nome); await carregar(); window.rvAbrir(r[0].id);
  }catch(e){ erro(/duplicate|unique/i.test(e.message) ? 'Já existe um restaurante com esse código.' : e.message); }
};
async function hist(id, acao, det){ try{ await rest('historico', 'POST', { restaurante_id:id, acao, detalhe:det || null }); }catch(e){} }
window.rvAbrir = async id => { S.rest = JSON.parse(JSON.stringify(S.lista.find(r => r.id === id))); const et0 = S.rest.etapas || {}; Object.keys(et0).forEach(k => { if(!et0[k] || typeof et0[k] !== 'object') et0[k] = { feita: !!et0[k] && et0[k] !== 'pendente' }; }); S.rest.etapas = et0; S.aba = 'dados'; S.res = {}; await carregarRest(); telaRest(); };
window.rvVoltar = async () => { S.rest = null; try{ await carregar(); }catch(e){ erro(e.message); } telaLista(); };
async function carregarRest(){ try{ S.cobR = await rest('cobrancas?restaurante_id=eq.' + S.rest.id + '&select=*&order=competencia.desc'); S.hist = await rest('historico?restaurante_id=eq.' + S.rest.id + '&select=*&order=em.desc&limit=40'); }catch(e){ erro(e.message); } }

const ABAS = [['dados','Dados'],['saude','Saúde'],['passo','Passo a passo'],['ligacoes','Ligações'],['marca','Marca'],['modulos','Módulos'],['cobranca','Cobrança'],['hist','Histórico']];
function telaRest(){
  const r = S.rest, n = nEtapas(r);
  $('app').innerHTML = '<div class="topo"><div><button class="mini" onclick="rvVoltar()">← Restaurantes</button></div><span class="selo ' + esc(r.situacao) + '">' + esc(SIT[r.situacao]) + '</span></div>'
   + '<h1>' + esc(r.nome) + '</h1><small class="mudo">' + esc(r.slug) + ' · implantação ' + n + ' de ' + ETAPAS.length + '</small><div class="barra"><i style="width:' + Math.round(n / ETAPAS.length * 100) + '%"></i></div>'
   + '<div class="abas">' + ABAS.map(a => '<button class="' + (S.aba === a[0] ? 'on' : '') + '" onclick="rvAba(\'' + a[0] + '\')">' + a[1] + '</button>').join('') + '</div><div id="corpo"></div>';
  ({ dados:abaDados, saude:abaSaude, passo:abaPasso, ligacoes:abaLig, marca:abaMarca, modulos:abaMod, cobranca:abaCob, hist:abaHist })[S.aba]();
}
window.rvAba = a => { S.aba = a; telaRest(); };
function campoTxt(rot, k, o){ o = o || {}; const v = o.path ? get(S.rest, o.path) : S.rest[k]; return '<label for="f_' + k + '">' + rot + '</label><input id="f_' + k + '" data-k="' + (o.path || k) + '" type="' + (o.tipo || 'text') + '" value="' + esc(v == null ? '' : v) + '" placeholder="' + esc(o.ph || '') + '">'; }
function get(o, p){ return p.split('.').reduce((a, k) => (a == null ? a : a[k]), o); }
function set(o, p, v){ const ks = p.split('.'); let a = o; ks.slice(0, -1).forEach(k => { a = a[k] = a[k] || {}; }); a[ks[ks.length - 1]] = v; }
function lerForm(){ document.querySelectorAll('#corpo [data-k]').forEach(el => { let v = el.type === 'checkbox' ? el.checked : el.value.trim(); if(el.type === 'number') v = v === '' ? null : Number(v); else if(v === '' && !el.type.match(/checkbox/) && !/^(marca|modulos)\./.test(el.dataset.k)) v = null; set(S.rest, el.dataset.k, v); }); }
const COLS = ['nome','situacao','dominio','site_url','supabase_url','supabase_chave','api_url','contingencia_url','push_chave_publica','marca','modulos','etapas','contato_nome','contato_telefone','contato_email','plano','valor_mensal','dia_vencimento','motor','inicio_em','observacoes'];
async function salvar(msg){
  lerForm();
  const corpo = {}; COLS.forEach(c => { corpo[c] = S.rest[c]; });
  ['dominio','site_url'].forEach(k => { if(corpo[k]) corpo[k] = String(corpo[k]).replace(/^https?:\/\//, k === 'dominio' ? '' : '$&').replace(/\/+$/, k === 'dominio' ? '' : '/'); });
  if(corpo.site_url && !/^https?:\/\//.test(corpo.site_url)) corpo.site_url = 'https://' + corpo.site_url;
  if(corpo.site_url && !corpo.site_url.endsWith('/')) corpo.site_url += '/';
  try{ const local = corpo.etapas; const r = await rest('restaurantes?id=eq.' + S.rest.id, 'PATCH', corpo); if(!r || !r[0]) throw new Error('O banco não confirmou a gravação (nenhuma linha alterada). Saia e entre de novo no painel.'); S.rest = r[0]; if(local){ const igual = (a, b) => Object.keys(local).every(k => !!(a && a[k] && a[k].feita) === !!(local[k] && local[k].feita) && ((a && a[k] && a[k].itens || []).length === (local[k].itens || []).length)); if(!igual(S.rest.etapas)){ S.rest.etapas = local; const conf = await rest('restaurantes?id=eq.' + S.rest.id + '&select=etapas'); if(!igual(conf && conf[0] && conf[0].etapas)) throw new Error('O banco recebeu mas NÃO guardou a etapa. Peça ao Claude para conferir a coluna etapas do banco do painel.'); } } const i = S.lista.findIndex(x => x.id === S.rest.id); if(i >= 0) S.lista[i] = S.rest; aviso(msg || 'Salvo.', 'ok'); return true; }
  catch(e){ S.ultimoErro = /unique|duplicate/i.test(e.message) ? 'Esse endereço já pertence a outro restaurante.' : e.message; erro(S.ultimoErro); return false; }
}
window.rvSalvar = async () => { if(await salvar()) { await hist(S.rest.id, 'Dados salvos', S.aba); telaRest(); } };
const botSalvar = '<p><button class="principal" onclick="rvSalvar()">Salvar</button></p>';

/* Bloco de saúde completo (igual à tela "Conexão e servidores" do app). Usado na lista e na aba Saúde. */
function saudeHtml(r, aninhado){
  const sd = saudeDe(r.slug), h = sd.h, sec = x => aninhado ? '<div style="margin-top:12px;padding-top:10px;border-top:1px solid #2a2a2a;overflow-wrap:anywhere">' + x + '</div>' : '<div class="card" style="overflow-wrap:anywhere">' + x + '</div>';
  const dot = c => '<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:' + c + ';margin-right:8px"></span>';
  if(!h) return sec('<b>' + dot(SAUDE_COR.sem) + 'Sem sinal ainda</b><p class="mudo" style="margin:6px 0 0;font-size:13px">Este restaurante ainda não enviou o resumo de saúde (ele envia sozinho a cada 15 minutos).</p>');
  const itens = h.itens || [], ruins = itens.filter(i => i.nivel !== 'ok' && !/^Plano grátis:/i.test(i.titulo || '')), uso = usoDe(h), srv = h.servidores || {};
  const outros = itens.filter(i => !/^Plano grátis:/i.test(i.titulo || '') || !uso.some(u => u.id === i.id));
  return sec('<div class="linha"><b>' + dot(SAUDE_COR[sd.geral]) + SAUDE_ROT[sd.geral] + '</b><small class="mudo">' + haTempo(sd.min) + '</small></div>'
      + (sd.geral === 'sem' ? '<p class="mudo" style="margin:6px 0 0;font-size:13px">Parou de enviar sinal. Confira se o Supabase dele está ativo (pode ter sido pausado).</p>' : '<small class="mudo">' + itens.length + ' verificações</small>'))
    + sec('<b>Servidores</b>' + linhaSrv_('Supabase', 'principal', srv.supabase) + linhaSrv_('Planilha principal', 'reserva', srv.planilha) + '<div id="srvCont_' + r.id + '">' + linhaSrv_('Planilha de contingência', 'último recurso', r.contingencia_url ? { estado:'sem_resposta' } : { estado:'nao_usa' }) + '</div>')
    + (srv.drive && (srv.drive.principal || srv.drive.contingencia) ? sec('<b>☁️ Google Drive</b>' + driveBarra_('Drive principal', srv.drive.principal) + driveBarra_('Drive da contingência', srv.drive.contingencia) + '<small class="mudo" style="display:block;margin-top:8px">Medido a cada 6 horas' + (srv.drive.principal && srv.drive.principal.medido_em ? ' · última medição ' + haTempo(Math.round((Date.now() - new Date(srv.drive.principal.medido_em).getTime()) / 60000)) : '') + '.</small>') : '')
    + (ruins.length ? sec('<b>Pede atenção</b>' + ruins.map(i => '<div style="border-left:3px solid ' + SAUDE_COR[i.nivel] + ';padding:4px 0 4px 10px;margin:8px 0"><b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.texto) + '</small></div>').join('')) : '')
    + (uso.length ? sec('<b>📊 Plano grátis do Supabase</b>' + uso.map(barraUso).join('') + '<small class="mudo" style="display:block;margin-top:8px">Chamadas às funções é estimativa pelas últimas 24 h. O número oficial está no Supabase (Settings → Usage).</small>') : '')
    + sec('<details><summary style="cursor:pointer"><b>Todas as verificações (' + outros.length + ')</b></summary>' + outros.map(i => '<div style="padding:6px 0">' + dot(SAUDE_COR[i.nivel] || SAUDE_COR.sem) + '<b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.texto) + '</small></div>').join('') + '</details>');
}
const fmtBytes_ = b => { b = Number(b) || 0; if(b <= 0) return '0 B'; const u = ['B','KB','MB','GB','TB']; let i = 0; while(b >= 1024 && i < u.length - 1){ b /= 1024; i++; } return b.toFixed(i ? 1 : 0).replace('.', ',') + ' ' + u[i]; };
function driveBarra_(titulo, d){
  if(!d || d.estado === 'sem_resposta') return '<div style="margin:10px 0 2px"><b style="font-size:14px">' + titulo + '</b><br><small class="mudo">Aguardando a primeira medição…</small></div>';
  if(d.estado !== 'ok') return '<div style="margin:10px 0 2px"><b style="font-size:14px">' + titulo + '</b><div class="res erro" style="margin-top:4px">⚠️ Não foi possível medir: ' + esc(d.mensagem || 'sem resposta') + '</div></div>';
  const total = (Number(d.usado) || 0) + (Number(d.livre) || 0), pct = d.percentual == null ? 0 : Number(d.percentual);
  const comp = Object.keys(d.categorias || {}).filter(k => (d.categorias[k].bytes || 0) > 0).map(k => esc(k) + ' ' + fmtBytes_(d.categorias[k].bytes)).join(' · ');
  return barraUso({ tit:titulo, uso:fmtBytes_(d.usado), lim:d.livre == null ? '—' : fmtBytes_(total), pct }) + (comp ? '<small class="mudo" style="display:block">' + comp + '</small>' : '') + (d.nivel === 'Crítico' ? '<small style="color:var(--erro);display:block">⚠️ Quase cheio: novos backups e fotos podem falhar.</small>' : '');
}
function linhaSrv_(nome, papel, o){ o = o || {}; const ok = o.estado === 'ok', c = ok ? SAUDE_COR.ok : (o.estado === 'nao_usa' || o.estado === 'sem_resposta') ? SAUDE_COR.sem : SAUDE_COR.problema;
  return '<div class="linha" style="padding:6px 0;gap:8px"><span><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:' + c + ';margin-right:8px"></span><b>' + nome + '</b> <small class="mudo">' + papel + '</small></span><small>' + (ok ? 'Online' + (o.ms != null ? ' · ' + o.ms + ' ms' : '') : o.estado === 'nao_usa' ? 'Não usada' : o.estado === 'sem_resposta' ? 'Medindo…' : 'Fora do ar' + (o.detalhe ? ' · ' + esc(o.detalhe) : '')) + '</small></div>'; }
function abaSaude(){ $('corpo').innerHTML = saudeHtml(S.rest, false); medirContingencia_([S.rest]); }
/* A planilha de contingência é medida aqui, pelo navegador (o banco do restaurante não guarda o endereço dela). */
function medirContingencia_(rests){
  (rests || []).forEach(async r => {
    if(!r.contingencia_url) return; const t0 = Date.now(); let est;
    try{ const x = await tempo(r.contingencia_url, {}); est = x.ok ? { estado:'ok', ms:Date.now() - t0 } : { estado:'fora', detalhe:'erro ' + x.status }; }catch(e){ est = { estado:'fora', detalhe:e.name === 'AbortError' ? 'sem resposta em 12 s' : 'sem conexão' }; }
    const box = $('srvCont_' + r.id); if(box) box.innerHTML = linhaSrv_('Planilha de contingência', 'último recurso', est);
  });
}
function abaDados(){
  const r = S.rest;
  $('corpo').innerHTML = '<div class="card"><div class="cols"><div>' + campoTxt('Nome do restaurante', 'nome') + '</div><div><label>Código (não muda)</label><input value="' + esc(r.slug) + '" disabled></div></div>'
   + '<label for="f_sit">Situação</label><select id="f_sit" data-k="situacao">' + Object.keys(SIT).map(k => '<option value="' + k + '"' + (r.situacao === k ? ' selected' : '') + '>' + SIT[k] + '</option>').join('') + '</select>'
   + '<p class="mudo" style="font-size:13px">"Suspenso" faz o app do restaurante mostrar o aviso de serviço suspenso. "Encerrado" tira o restaurante do ar.</p>'
   + '<div class="cols"><div>' + campoTxt('Nome do contato', 'contato_nome') + '</div><div>' + campoTxt('Telefone/WhatsApp', 'contato_telefone') + '</div></div>' + campoTxt('E-mail do contato', 'contato_email', { tipo:'email' })
   + '<div class="cols"><div>' + campoTxt('Plano', 'plano', { ph:'Ex.: Básico' }) + '</div><div>' + campoTxt('Mensalidade (R$)', 'valor_mensal', { tipo:'number' }) + '</div></div>'
   + '<div class="cols"><div>' + campoTxt('Dia do vencimento (1 a 28)', 'dia_vencimento', { tipo:'number' }) + '</div><div>' + campoTxt('Início do contrato', 'inicio_em', { tipo:'date' }) + '</div></div>'
   + '<label for="f_obs">Observações</label><textarea id="f_obs" data-k="observacoes">' + esc(r.observacoes || '') + '</textarea>' + botSalvar + '</div>';
}
function abaLig(){
  $('corpo').innerHTML = '<div class="card"><h2>Ligações do restaurante</h2><p class="mudo">É aqui que o app descobre com qual banco e planilhas falar. Só endereços e chaves PÚBLICAS: senhas e chaves secretas nunca entram aqui.</p>'
   + campoTxt('Endereço do banco (Project URL do Supabase)', 'supabase_url', { ph:'https://xxxx.supabase.co' }) + campoTxt('Chave pública (publishable)', 'supabase_chave', { ph:'sb_publishable_…' })
   + campoTxt('Planilha principal (endereço /exec do Apps Script) — opcional', 'api_url') + campoTxt('Planilha de contingência (endereço /exec) — opcional', 'contingencia_url')
   + campoTxt('Chave pública dos avisos no celular (push)', 'push_chave_publica')
   + campoTxt('Endereço (domínio) do site — só o nome', 'dominio', { ph:'churros.meusistema.com.br' }) + campoTxt('Endereço completo do site', 'site_url', { ph:'https://churros.meusistema.com.br/' }) + campoTxt('Versão do sistema (motor) — deixe em branco para acompanhar as atualizações', 'motor', { ph:'https://lucassricardo95.github.io/motor/estavel/' })
   + botSalvar + '<h3>Testes</h3><div class="linha" style="justify-content:flex-start"><button class="mini" onclick="rvTeste(\'supabase\')">Testar ligação</button><button class="mini" onclick="rvTeste(\'banco\')">Testar banco</button><button class="mini" onclick="rvTeste(\'funcoes\')">Testar funções</button><button class="mini" onclick="rvTeste(\'site\')">Testar site</button></div><div id="resTeste"></div>'
   + '<h3>Arquivo de configuração do restaurante</h3><p class="mudo" style="font-size:13px">Preencha tudo acima, salve e gere. Este arquivo vai para o GitHub do restaurante e é o único que muda de um restaurante para outro.</p><button class="mini principal" onclick="rvGerarConfig()">Gerar config-restaurante.js</button><div id="cfgGerado"></div></div>';
  mostrarRes('resTeste', ['supabase','banco','funcoes','site']);
}

/* ---------- arquivo de configuração do restaurante ---------- */
function configTexto(r){
  const m = r.marca || {}, mod = r.modulos || {}, c = m.cores || {}, lg = m.logos || {}, mo = (r.motor || 'https://lucassricardo95.github.io/motor/estavel/').replace(/texas-estavel\/$/, 'estavel/').replace(/texas-(v[\d.]+)\/$/, '$1/');
  const o = { motor:r.motor || 'https://lucassricardo95.github.io/motor/estavel/', slug:r.slug, nome:r.nome, siteUrl:r.site_url || '', supabaseUrl:r.supabase_url || '', supabaseChave:r.supabase_chave || '', apiUrl:mod.planilhas === false ? '' : (r.api_url || ''), contingenciaUrl:mod.planilhas === false ? '' : (r.contingencia_url || ''), pushChave:r.push_chave_publica || '',
    marca:{ slogan:m.slogan || '', assistente:m.assistente || 'Assistente', tema:m.tema || '', cores:{ destaque:c.destaque || '#d9a21b', botao:c.botao || '#8c1c13', fundo:c.fundo || '#14100c' }, logos:{ cardapio:lg.cardapio || mo + 'img/logo.png', impressao:lg.impressao || '', icone:lg.icone || mo + 'img/icon-512.png' } }, modulos:mod };
  return '/* CONFIGURAÇÃO DE ' + r.nome.replace(/\*\//g, '') + ' — gerado pelo Painel de Revenda em ' + new Date().toLocaleString('pt-BR') + '.\n   Só endereços e chaves PÚBLICAS. Para mudar, gere de novo no painel. */\nwindow.RESTAURANTE = ' + JSON.stringify(o, null, 2) + ';\n';
}
window.rvGerarConfig = async () => {
  lerForm(); const r = S.rest, falta = [];
  if(!r.supabase_url || !r.supabase_chave) falta.push('endereço e chave pública do Supabase'); if(!r.site_url) falta.push('endereço completo do site');
  if(falta.length) return erro('Antes de gerar, preencha: ' + falta.join(' e ') + '.');
  if(!await salvar('Salvo.')) return;
  const t = configTexto(S.rest); $('cfgGerado').innerHTML = '<div class="copiar" id="cfgTxt"></div><button class="mini" onclick="rvCopiar(\'cfgTxt\')">Copiar</button> <button class="mini" onclick="rvBaixarConfig()">Baixar arquivo</button>'; $('cfgTxt').textContent = t; window.__cfg = t;
  await hist(S.rest.id, 'Arquivo de configuração gerado', '');
};
window.rvBaixarConfig = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([window.__cfg || ''], { type:'text/javascript' })); a.download = 'config-restaurante.js'; a.click(); };

/* ---------- testes automáticos (feitos pelo seu navegador) ---------- */
async function tempo(url, o){ const c = new AbortController(); const t = setTimeout(() => c.abort(), 12000); try{ return await fetch(url, Object.assign({ signal:c.signal }, o)); } finally { clearTimeout(t); } }
const TESTES = {
  async supabase(r){ if(!r.supabase_url || !r.supabase_chave) return ['erro', 'Falta o endereço do banco e/ou a chave pública.'];
    const x = await tempo(r.supabase_url + '/auth/v1/health', { headers:{ apikey:r.supabase_chave } }); return x.ok ? ['ok', 'O banco responde. Chave aceita.'] : ['erro', 'O banco respondeu com erro ' + x.status + '. Confira a chave pública.']; },
  async banco(r){ if(!r.supabase_url) return ['erro', 'Preencha primeiro o endereço do banco.'];
    const x = await tempo(r.supabase_url + '/rest/v1/rpc/api_cardapio_promos', { method:'POST', headers:{ apikey:r.supabase_chave, 'Content-Type':'application/json' }, body:'{"p":{}}' });
    if(x.status === 404) return ['erro', 'O banco existe, mas as tabelas e funções do sistema ainda não foram criadas (etapa "Criar as tabelas").'];
    const j = await x.json().catch(() => null); return j && j.ok === true ? ['ok', 'Banco do sistema instalado e respondendo.'] : ['aviso', 'O banco respondeu, mas fora do esperado: ' + esc(JSON.stringify(j).slice(0, 120))]; },
  async funcoes(r){ if(!r.supabase_url) return ['erro', 'Preencha primeiro o endereço do banco.'];
    const x = await tempo(r.supabase_url + '/functions/v1/ping', { method:'POST', headers:{ apikey:r.supabase_chave, Authorization:'Bearer ' + r.supabase_chave, 'Content-Type':'application/json' }, body:'{}' });
    return x.status === 404 ? ['erro', 'As funções do servidor ainda não foram publicadas.'] : (x.ok ? ['ok', 'Funções do servidor respondendo.'] : ['aviso', 'A função "ping" respondeu com erro ' + x.status + '.']); },
  async site(r){ const u = r.site_url || (r.dominio ? 'https://' + r.dominio + '/' : ''); if(!u) return ['erro', 'Preencha o endereço do site.'];
    await tempo(u, { mode:'no-cors' }); return ['ok', 'O endereço ' + esc(u) + ' está no ar.']; }
};
window.rvTeste = async id => {
  lerForm(); S.res = S.res || {}; S.res[id] = ['aviso', 'Testando…']; mostrarRes('resTeste', Object.keys(S.res)); mostrarRes('res_' + id, [id]);
  try{ S.res[id] = await TESTES[id](S.rest); }catch(e){ S.res[id] = ['erro', e.name === 'AbortError' ? 'Demorou demais para responder.' : 'Não foi possível chegar lá (' + esc(e.message) + ').']; }
  mostrarRes('resTeste', Object.keys(S.res)); mostrarRes('res_' + id, [id]);
};
function mostrarRes(box, ids){ const b = $(box); if(!b) return; b.innerHTML = ids.filter(i => S.res && S.res[i]).map(i => '<div class="res ' + S.res[i][0] + '">' + ({ ok:'✅ ', erro:'❌ ', aviso:'⏳ ' }[S.res[i][0]]) + '<b>' + esc(i) + ':</b> ' + S.res[i][1] + '</div>').join(''); }

/* ---------- passo a passo ---------- */
function sub(t){ const r = S.rest; return String(t).replace(/\{nome\}/g, r.nome).replace(/\{slug\}/g, r.slug).replace(/\{ref\}/g, refDe(r)).replace(/\{supabase_url\}/g, r.supabase_url || '(URL do Supabase)').replace(/\{site_url\}/g, r.site_url || '(endereço do site)').replace(/\{site_origem\}/g, (r.site_url || '(endereço do site)').replace(/\/+$/, '')); }
const QUEM = { voce:'👤 Você faz', claude:'🤖 Peça ao Claude', cliente:'🍽️ O restaurante faz' };
function abaPasso(){
  const r = S.rest, e = r.etapas || {}; const prox = ETAPAS.find(x => !(e[x.id] && e[x.id].feita));
  $('corpo').innerHTML = (prox ? '<div class="card"><small class="mudo">Próxima etapa</small><br><b>' + esc(prox.titulo) + '</b></div>' : '<div class="card">✅ Implantação completa.</div>')
   + ETAPAS.map((x, i) => {
     const f = e[x.id] && e[x.id].feita, ck = (e[x.id] && e[x.id].itens) || [];
     return '<div class="card passo ' + (f ? 'feita' : '') + '"><div class="linha"><b>' + (i + 1) + '. ' + esc(x.titulo) + '</b><span>' + (f ? '✅' : '') + '</span></div><span class="quem">' + QUEM[x.quem] + '</span>'
      + '<ol>' + x.passos.map(p => '<li>' + esc(sub(p)) + '</li>').join('') + '</ol>'
      + (x.pedido ? '<small class="mudo">Copie e cole na conversa com o Claude:</small><div class="copiar" id="pd_' + x.id + '">' + esc(sub(x.pedido)) + '</div><button class="mini" onclick="rvCopiar(\'pd_' + x.id + '\')">Copiar pedido</button> ' : '')
      + (x.checklist ? x.checklist.map((c, k) => '<label style="display:flex;gap:8px;align-items:flex-start;font-weight:400;color:var(--txt);margin:6px 0"><input type="checkbox" ' + (ck.includes(k) ? 'checked ' : '') + 'onchange="rvItem(\'' + x.id + '\',' + k + ',this.checked)"> ' + esc(c) + '</label>').join('') : '')
      + (x.teste ? '<button class="mini" onclick="rvTeste(\'' + x.teste + '\')">Testar</button><div id="res_' + x.teste + '"></div> ' : '')
      + (x.campos ? '<button class="mini" onclick="rvAba(\'ligacoes\')">Ir para as ligações</button> ' : '')
      + (x.id === 'marca' ? '<button class="mini" onclick="rvAba(\'marca\')">Ir para a marca</button> ' : '') + (x.id === 'modulos' ? '<button class="mini" onclick="rvAba(\'modulos\')">Ir para os módulos</button> ' : '')
      + (x.id === 'entrega' ? '<button class="mini" onclick="rvAba(\'cobranca\')">Ir para a cobrança</button> ' : '')
      + '<button class="mini ' + (f ? '' : 'principal') + '" onclick="rvEtapa(\'' + x.id + '\',' + (!f) + ')">' + (f ? 'Desmarcar' : 'Marcar como feita') + '</button></div>';
   }).join('');
  Object.keys(S.res || {}).forEach(k => mostrarRes('res_' + k, [k]));
}
window.rvCopiar = async id => { try{ await navigator.clipboard.writeText($(id).textContent); aviso('Copiado.', 'ok'); }catch(e){ erro('Não deu para copiar. Selecione o texto e copie manualmente.'); } };
window.rvItem = (id, k, v) => { const e = S.rest.etapas = S.rest.etapas || {}; const x = e[id] = e[id] || {}; x.itens = (x.itens || []).filter(i => i !== k); if(v) x.itens.push(k); salvar('Anotado.'); };
window.rvEtapa = async (id, feita) => {
  const et = ETAPAS.find(x => x.id === id);
  if(feita && et.checklist){ const ck = ((S.rest.etapas || {})[id] || {}).itens || []; if(ck.length < et.checklist.length){ return erro('Marque todos os itens do teste antes de concluir.'); } }
  S.rest.etapas = S.rest.etapas || {}; const antes = JSON.parse(JSON.stringify(S.rest.etapas[id] || null)); S.rest.etapas[id] = Object.assign(S.rest.etapas[id] || {}, { feita, em:new Date().toISOString() });
  if(await salvar(feita ? 'Etapa concluída.' : 'Etapa reaberta.')){ await hist(S.rest.id, feita ? 'Etapa concluída' : 'Etapa reaberta', et.titulo); telaRest(); }
  else { if(antes) S.rest.etapas[id] = antes; else delete S.rest.etapas[id]; try{ telaRest(); }catch(e){} erro('NÃO foi salvo. Motivo: ' + (S.ultimoErro || 'sem resposta do banco') + ' — me mande este texto.'); }
};

/* ---------- marca ---------- */
function abaMarca(){
  const m = S.rest.marca = S.rest.marca || {}, c = m.cores = m.cores || {}, lg = m.logos = m.logos || {};
  $('corpo').innerHTML = '<div class="card"><h2>Marca inicial</h2><p class="mudo">Você define a primeira aparência; o dono do restaurante pode ajustar depois em Administrador → Sistema → Aparência.</p>'
   + '<h3>Tema pronto</h3><div class="temas">' + TEMAS.map(t => '<div class="tema ' + (m.tema === t.id ? 'on' : '') + '" onclick="rvTema(\'' + t.id + '\')" style="background:' + t.fundo + ';color:' + (parseInt(t.fundo.slice(1,3),16)*0.299 + parseInt(t.fundo.slice(3,5),16)*0.587 + parseInt(t.fundo.slice(5,7),16)*0.114 > 150 ? '#1b1b1b' : '#f5efe6') + '"><i style="background:' + t.destaque + '"></i><i style="background:' + t.botao + '"></i><br>' + t.nome + '</div>').join('') + '</div>'
   + '<h3>Ou ajuste as cores</h3><div class="cores">' + [['destaque','Destaque'],['botao','Botão principal'],['fundo','Fundo']].map(k => '<div class="cor-item"><input type="color" data-k="marca.cores.' + k[0] + '" value="' + esc(c[k[0]] || '#000000') + '" oninput="rvPrevia()"><br>' + k[1] + '</div>').join('') + '</div>'
   + '<div class="previa" id="previa"></div>'
   + '<div class="cols"><div>' + campoTxt('Slogan', 'slogan', { path:'marca.slogan' }) + '</div><div>' + campoTxt('Nome do assistente virtual', 'assist', { path:'marca.assistente' }) + '</div></div>'
   + '<h3>Logos</h3>' + [['cardapio','Logo principal (cardápio, login e cabeçalho)'],['impressao','Logo de impressão (comanda e recibo)'],['icone','Ícone do app (quadrado)']].map(l =>
      '<div class="logo-box" style="margin:10px 0"><div style="min-width:70px">' + (lg[l[0]] ? '<img src="' + esc(lg[l[0]]) + '" alt="">' : '<small class="mudo">sem imagem</small>') + '</div><div><b style="font-size:14px">' + l[1] + '</b><br><input type="file" accept="image/*" onchange="rvLogo(\'' + l[0] + '\',this)"></div></div>').join('')
   + botSalvar + '</div>';
  rvPrevia();
}
window.rvTema = id => { const t = TEMAS.find(x => x.id === id); lerForm(); const m = S.rest.marca; m.tema = id; m.cores = { destaque:t.destaque, botao:t.botao, fundo:t.fundo }; abaMarca(); };
window.rvPrevia = () => { const g = k => (document.querySelector('[data-k="marca.cores.' + k + '"]') || {}).value || '#000'; const p = $('previa'); if(!p) return;
  p.style.background = g('fundo'); p.innerHTML = '<b style="color:' + g('destaque') + ';font-size:18px">' + esc(S.rest.nome) + '</b><div style="color:#fff9">Prévia de um cartão do cardápio</div><span class="bt" style="background:' + g('botao') + ';color:#fff">Fazer pedido</span>'; };
function reduzir(arq, max){ return new Promise((ok, no) => { const im = new Image(), u = URL.createObjectURL(arq); im.onload = () => { const e = Math.min(1, max / Math.max(im.width, im.height)), cv = document.createElement('canvas'); cv.width = Math.round(im.width * e); cv.height = Math.round(im.height * e); cv.getContext('2d').drawImage(im, 0, 0, cv.width, cv.height); URL.revokeObjectURL(u); cv.toBlob(b => b ? ok(b) : no(new Error('Imagem inválida.')), 'image/png'); }; im.onerror = () => no(new Error('Não consegui ler essa imagem.')); im.src = u; }); }
window.rvLogo = async (tipo, inp) => {
  const f = inp.files[0]; if(!f) return;
  try{ lerForm(); const b = await reduzir(f, tipo === 'icone' ? 512 : 1024), cam = S.rest.slug + '/' + tipo + '-' + Date.now() + '.png';
    await req('/storage/v1/object/marcas/' + cam, { method:'POST', body:b, headers:{ 'Content-Type':'image/png', 'x-upsert':'true' } });
    S.rest.marca.logos = S.rest.marca.logos || {}; S.rest.marca.logos[tipo] = URL_ + '/storage/v1/object/public/marcas/' + cam;
    if(await salvar('Logo enviada.')) abaMarca();
  }catch(e){ erro(e.message); }
};

/* ---------- módulos ---------- */
function abaMod(){
  const m = S.rest.modulos = S.rest.modulos || {};
  $('corpo').innerHTML = '<div class="card"><h2>O que o restaurante contratou</h2><p class="mudo">Desligado = a tela some e o sistema funciona sem ele.</p>' + MODULOS.map(x => '<label style="display:flex;gap:10px;align-items:center;font-weight:400;color:var(--txt);font-size:15px;margin:10px 0"><input type="checkbox" data-k="modulos.' + x.id + '"' + (m[x.id] ? ' checked' : '') + '> ' + esc(x.nome) + '</label>').join('') + botSalvar + '</div>';
}

/* ---------- cobrança ---------- */
function abaCob(){
  const r = S.rest, h = hoje();
  const nAtr = atrasadas(r.id).length;
  const bloq = '<div class="card"' + (r.bloqueado ? ' style="border-color:var(--erro)"' : '') + '><h2>Acesso ao sistema</h2>'
    + (r.bloqueado
      ? '<p><b style="color:var(--erro)">⛔ Bloqueado' + (r.bloqueado_em ? ' em ' + esc(new Date(r.bloqueado_em).toLocaleDateString('pt-BR')) : '') + '.</b> O restaurante vê "Acesso suspenso" e não consegue usar o sistema (cardápio e equipe).' + (r.bloqueio_motivo ? '<br><small class="mudo">Mensagem mostrada: ' + esc(r.bloqueio_motivo) + '</small>' : '') + '</p><button class="principal" onclick="rvBloquear(false)">Liberar acesso</button>'
      : '<p class="mudo">' + (nAtr ? '<b style="color:var(--erro)">' + nAtr + ' mensalidade(s) em atraso.</b> ' : 'Nenhuma mensalidade em atraso. ') + 'O bloqueio nunca é automático: só vale depois que você tocar em "Bloquear acesso". Dá para liberar de novo a qualquer momento.</p>'
        + '<label class="mudo" style="font-size:13px">Mensagem para o restaurante (opcional)</label><textarea id="bloqMsg" rows="2" maxlength="200" placeholder="Ex.: Acesso suspenso por mensalidade em aberto. Fale com o suporte pelo WhatsApp (16) 9xxxx-xxxx."></textarea>'
        + '<button class="mini" style="margin-top:8px;border-color:var(--erro);color:var(--erro)" onclick="rvBloquear(true)">⛔ Bloquear acesso</button>')
    + '</div>';
  $('corpo').innerHTML = bloq + '<div class="card"><div class="linha"><h2>Mensalidades</h2><button class="principal mini" onclick="rvGerarCob()">Gerar a do mês</button></div><p class="mudo">' + (r.valor_mensal ? BRL(r.valor_mensal) + ' por mês, vence todo dia ' + (r.dia_vencimento || '—') + '.' : 'Defina o valor e o dia na aba Dados.') + '</p>'
   + (S.cobR.length ? '<table><tr><th>Mês</th><th>Valor</th><th>Vence</th><th></th></tr>' + S.cobR.map(c => { const at = !c.pago_em && c.vencimento && c.vencimento < h; return '<tr><td>' + esc(c.competencia.slice(5, 7) + '/' + c.competencia.slice(0, 4)) + '</td><td>' + BRL(c.valor) + '</td><td>' + esc(c.vencimento ? c.vencimento.split('-').reverse().join('/') : '—') + '</td><td>'
      + (c.pago_em ? '<span class="res ok">Pago ' + esc(c.pago_em.split('-').reverse().join('/')) + '</span> <button class="mini" onclick="rvPago(\'' + c.id + '\',false)">Desfazer</button>' : (at ? '<span class="res erro">Atrasada</span> ' : '') + '<button class="mini principal" onclick="rvPago(\'' + c.id + '\',true)">Marcar paga</button>') + '</td></tr>'; }).join('') + '</table>' : '<p>Nenhuma mensalidade gerada.</p>') + '</div>';
}
window.rvBloquear = async b => {
  const r = S.rest, msg = ((document.getElementById('bloqMsg') || {}).value || '').trim();
  if(!confirm(b ? 'Bloquear o acesso de "' + r.nome + '" agora?\n\nO cardápio e o sistema da equipe deixam de abrir para ele até você liberar.' : 'Liberar o acesso de "' + r.nome + '"?')) return;
  const dados = { bloqueado:b, bloqueado_em:b ? new Date().toISOString() : null, bloqueio_motivo:b ? (msg || null) : null };
  try{
    await rest('restaurantes?id=eq.' + r.id, 'PATCH', dados);
    Object.assign(r, dados);
    await hist(r.id, b ? 'Acesso BLOQUEADO' : 'Acesso liberado', b ? msg : '');
    aviso(b ? 'Acesso bloqueado.' : 'Acesso liberado.', 'ok'); abaCob();
  }catch(e){ erro(/bloqueado|bloqueio|column|schema/i.test(e.message) ? 'O banco ainda não tem o bloqueio. Rode o SQL "001-bloqueio.sql" no projeto revenda (peça ao Claude) e tente de novo.' : e.message); }
};
window.rvGerarCob = async () => {
  const r = S.rest; if(!r.valor_mensal) return erro('Defina a mensalidade na aba Dados e salve antes.');
  const d = new Date(), comp = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-01', dia = String(r.dia_vencimento || 10).padStart(2, '0');
  try{ await rest('cobrancas', 'POST', { restaurante_id:r.id, competencia:comp, valor:r.valor_mensal, vencimento:comp.slice(0, 8) + dia }); await hist(r.id, 'Mensalidade gerada', comp.slice(0, 7)); await carregar(); await carregarRest(); abaCob(); }
  catch(e){ erro(/duplicate|unique/i.test(e.message) ? 'A mensalidade deste mês já foi gerada.' : e.message); }
};
window.rvPago = async (id, pago) => { try{ await rest('cobrancas?id=eq.' + id, 'PATCH', { pago_em: pago ? hoje() : null }); await hist(S.rest.id, pago ? 'Mensalidade paga' : 'Pagamento desfeito', ''); await carregar(); await carregarRest(); abaCob(); }catch(e){ erro(e.message); } };

function telaErros(){
  const nome = s => (S.lista.find(r => r.slug === s) || {}).nome || s;
  $('app').innerHTML = '<div class="topo"><div><button class="mini" onclick="rvVoltar()">← Restaurantes</button></div></div><h1>Erros do sistema</h1>'
   + (S.erros.length ? S.erros.map(e => '<div class="card" style="overflow-wrap:anywhere"><div class="linha"><b>' + esc(nome(e.slug)) + '</b><span class="selo">' + e.ocorrencias + 'x</span></div>'
     + '<p style="margin:6px 0"><b>' + esc(e.mensagem) + '</b></p>'
     + '<small class="mudo">Tela: ' + esc(e.tela || '—') + ' · versão ' + esc(e.versao || '—') + '<br>' + esc(e.aparelho || '') + '<br>Último: ' + esc(new Date(e.ultimo_em).toLocaleString('pt-BR')) + ' · primeiro: ' + esc(new Date(e.primeiro_em).toLocaleString('pt-BR')) + '</small>'
     + (e.detalhe ? '<details style="margin-top:6px"><summary class="mudo">Detalhe técnico</summary><small class="mudo" style="white-space:pre-wrap">' + esc(e.detalhe) + '</small></details>' : '')
     + '<p style="margin:8px 0 0"><button class="mini" onclick="rvErroOk(' + e.id + ')">Marcar como resolvido</button></p></div>').join('') : '<div class="card">Nenhum erro aberto.</div>');
}
window.rvErros = async () => { try{ await carregar(); }catch(e){ erro(e.message); } telaErros(); };
window.rvErroOk = async id => { try{ await rest('erros_app?id=eq.' + id, 'PATCH', { resolvido:true, resolvido_em:new Date().toISOString() }); S.erros = S.erros.filter(e => e.id !== id); telaErros(); }catch(e){ erro('Não foi possível marcar como resolvido: ' + e.message); } };
function abaHist(){ $('corpo').innerHTML = '<div class="card"><h2>Histórico</h2>' + (S.hist.length ? '<table>' + S.hist.map(h => '<tr><td>' + esc(new Date(h.em).toLocaleString('pt-BR')) + '</td><td>' + esc(h.acao) + '</td><td class="mudo">' + esc(h.detalhe || '') + '</td></tr>').join('') + '</table>' : '<p>Sem registros.</p>') + '</div>'; }

S.sess = sessLer(); tela();
})();
