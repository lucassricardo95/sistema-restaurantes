/* PAINEL DE REVENDA — seus restaurantes, a criação de restaurantes novos, a saúde de todos e o seu dinheiro. Sem biblioteca externa. */
(function(){
'use strict';
const URL_ = window.REVENDA_URL, CHAVE_ = window.REVENDA_CHAVE;
const MOTOR_PADRAO = 'https://lucassricardo95.github.io/motor/estavel/';
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const BRL = v => 'R$ ' + (Number(v) || 0).toFixed(2).replace('.', ',').replace(/\B(?=(\d{3})+(?!\d))/g, '.');
const num = v => { if(v == null || v === '') return null; const n = Number(String(v).replace(/\s/g, '').replace(/\.(?=\d{3}(\D|$))/g, '').replace(',', '.')); return isFinite(n) ? n : null; };
const pad = n => String(n).padStart(2, '0');
const hoje = () => { const d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); };
const mesDe = d => String(d || '').slice(0, 7);
const dataBr = d => d ? String(d).slice(0, 10).split('-').reverse().join('/') : '—';
const MESES = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
const mesNome = m => { const [a, b] = m.split('-'); return MESES[Number(b) - 1] + ' de ' + a; };
const mesCurto = m => MESES[Number(m.slice(5, 7)) - 1].slice(0, 3);
const somaMes = (m, k) => { const d = new Date(Number(m.slice(0, 4)), Number(m.slice(5, 7)) - 1 + k, 1); return d.getFullYear() + '-' + pad(d.getMonth() + 1); };
const SIT = { implantacao:'Em implantação', teste:'Em teste', ativo:'Ativo', suspenso:'Suspenso', encerrado:'Encerrado' };
const CAT_DESP = ['Supabase / servidores','Domínio e site','Ferramentas e IA','Marketing','Impostos','Transporte','Equipamentos','Outros'];
const ST_PROP = { novo:'Novo contato', conversando:'Conversando', proposta:'Proposta enviada', fechado:'Fechou ✅', perdido:'Perdido' };
const FORMAS = ['Pix','Dinheiro','Transferência','Cartão','Boleto','Outro'];
const SAUDE_COR = { ok:'#3ccf7a', atencao:'#f0b429', problema:'#ff5c5c', sem:'#7d7480', impl:'#6ea8fe' }, SAUDE_ROT = { ok:'Tudo certo', atencao:'Atenção', problema:'Com problema', sem:'Sem sinal', impl:'Em montagem' };
let S = novoEstado();
function novoEstado(){ return { sess:null, dono:null, view:'inicio', lista:[], cob:[], desp:[], prop:[], aj:{}, termos:null, prom:[], erros:[], saude:{}, rest:null, aba:'passo', cobR:[], hist:[], aceite:null, res:{}, parte:{}, cdIdx:{}, filtro:'todos', busca:'', mes:hoje().slice(0, 7), filtroProp:'abertas', tudoAberto:{} }; }
let timerAviso = null, timerAuto = null;
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
  let r; try{ r = await fetch(URL_ + caminho, { method:o.method || 'GET', headers:h, body:o.body }); }catch(e){ throw new Error('Sem conexão com o banco do painel. Confira a internet e tente de novo.'); }
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
const tenta = async (f, pad) => { try{ return (await f()) || pad; }catch(e){ return pad; } };
async function carregar(){
  const [l, c] = await Promise.all([ rest('restaurantes?select=*&order=nome.asc'), rest('cobrancas?select=*&order=vencimento.desc.nullslast') ]);
  S.lista = (l || []).map(normalizar); S.cob = c || [];
  const [d, p, a, t, pr] = await Promise.all([
    tenta(() => rest('despesas_revenda?select=*&order=data.desc'), []), tenta(() => rest('propostas?select=*&order=atualizado_em.desc'), []),
    tenta(() => rest('revenda_ajustes?select=dados'), []), tenta(() => rest('termos_uso?select=id,versao,fornecedor_nome,fornecedor_doc,foro,contato,atualizado_em'), []),
    tenta(() => rest('promessas?select=*&order=criada_em.desc'), []) ]);
  S.desp = d; S.prop = p; S.aj = (a[0] && a[0].dados) || {}; S.termos = t[0] || null; S.prom = pr;
  S.segs = await tenta(() => rpc('revenda_segredos_status'), {});
  S.atz = await tenta(() => rest('atualizador_estado?select=*'), []);   // o que o atualizador automático NÃO conseguiu subir
  S.painelAl = ((await tenta(() => rest('painel_alerta_estado?select=problemas'), [])) || [])[0] || null;   // vigia do próprio painel
  await carregarSaude();
}
async function carregarSaude(){
  const er = await tenta(() => rest('erros_app?select=*&resolvido=eq.false&order=ultimo_em.desc&limit=300'), null);
  if(er) S.erros = er; else if(!S.erros) S.erros = [];
  const vg = await tenta(() => rest('vigia_estado?select=*'), null); if(vg){ S.vigia = {}; vg.forEach(x => { S.vigia[x.slug] = x; }); }
  const vgG = await tenta(() => rest('vigia_geral?select=*'), null); if(vgG && vgG[0]) S.vigiaG = vgG[0];
  const sa = await tenta(() => rest('saude_app?select=*'), null);   // se a leitura falhar, mantém o que já tinha (não vira "sem sinal" por engano)
  if(sa){ S.saude = {}; sa.forEach(x => { S.saude[x.slug] = x; }); S.saudeEm = Date.now(); }
  else if(!S.saude) S.saude = {};
}
/* ao voltar para o painel (celular que estava em segundo plano), atualiza a saúde na hora em vez de mostrar sinal velho */
if(!window._saudeVisOn){ window._saudeVisOn = true; document.addEventListener('visibilitychange', async () => {
  if(document.hidden || !S.saudeEm || Date.now() - S.saudeEm < 60000) return;
  try{ await carregarSaude(); if(['inicio','saude'].includes(S.view) && !document.querySelector('.modal')) desenhar(); }catch(e){} }); }
function normalizar(r){ const e = r.etapas || {}; Object.keys(e).forEach(k => { if(!e[k] || typeof e[k] !== 'object') e[k] = { feita: !!e[k] && e[k] !== 'pendente' }; }); r.etapas = e; r.marca = r.marca || {}; r.modulos = r.modulos || {}; return r; }
async function hist(id, acao, det){ try{ await rest('historico', 'POST', { restaurante_id:id, acao, detalhe:det || null }); }catch(e){} }
async function salvarAjustes(novo, msg){ try{ const d = Object.assign({}, S.aj, novo); await rest('revenda_ajustes?id=eq.true', 'PATCH', { dados:d, atualizado_em:new Date().toISOString() }); S.aj = d; aviso(msg || 'Salvo.', 'ok'); return true; }catch(e){ erro(e.message); return false; } }

/* ---------- contas: implantação, saúde e dinheiro ---------- */
const etapaFeita = (r, id) => !!(r.etapas && r.etapas[id] && r.etapas[id].feita);
const nEtapas = r => ETAPAS.filter(e => etapaFeita(r, e.id)).length;
const proxEtapa = r => ETAPAS.find(e => !etapaFeita(r, e.id));
const refDe = r => (r.supabase_url || '').replace(/^https?:\/\//, '').split('.')[0] || '';
const nomeRest = id => (S.lista.find(r => r.id === id) || {}).nome || '—';
/* restaurante em implantação: o site ainda não está pronto, então falhas e erros não são "problema" (não alertam, não contam no sino) */
const emImpl = slug => (S.lista.find(r => r.slug === slug) || {}).situacao === 'implantacao';
function saudeDe(slug){ const h = S.saude && S.saude[slug], im = emImpl(slug); if(!h) return { geral: im ? 'impl' : 'sem', min:null, h:null }; const min = Math.round((Date.now() - new Date(h.atualizado_em).getTime()) / 60000), g = min > 45 ? 'sem' : (h.geral || 'ok'); return { geral: im && g !== 'ok' ? 'impl' : g, min, h }; }
const haTempo = m => m == null ? 'nunca' : m < 1 ? 'agora' : m < 60 ? 'há ' + m + ' min' : m < 1440 ? 'há ' + Math.round(m / 60) + ' h' : 'há ' + Math.round(m / 1440) + ' d';
function usoDe(h){ return ((h && h.itens) || []).filter(i => /^Plano grátis:/i.test(i.titulo || '')).map(i => {
  const m = String(i.texto || '').match(/^(?:Cerca de\s+)?([\d.,]+(?:\s*[A-Za-z]+)?)(?:\s+por mês)?,?\s+de\s+([\d.,]+(?:\s*[A-Za-z]+)?)(?:\s*\(([\d.,]+)%\))?/i); if(!m) return null;
  const nn = x => parseFloat(String(x).replace(/[^\d.,]/g, '').replace(/\.(?=\d{3}\b)/g, '').replace(',', '.')), uso = m[1].replace(/[.,]$/, ''), lim = m[2].replace(/[.,]$/, '');
  const pct = m[3] ? parseFloat(m[3].replace(',', '.')) : nn(uso) / nn(lim) * 100; if(!isFinite(pct)) return null;
  return { id:i.id, tit:String(i.titulo).replace(/^Plano grátis:\s*/i, '').replace(/^./, c => c.toUpperCase()), uso, lim, pct:Math.round(pct * 10) / 10 }; }).filter(Boolean); }
const corPct = p => p >= 90 ? SAUDE_COR.problema : p >= 70 ? SAUDE_COR.atencao : SAUDE_COR.ok;
function barraUso(u){ return '<div class="uso"><div class="linha"><b>' + esc(u.tit) + '</b><small>' + esc(u.uso) + ' de ' + esc(u.lim) + ' · <b style="color:' + corPct(u.pct) + '">' + String(u.pct).replace('.', ',') + '%</b></small></div><div class="barra"><i style="width:' + Math.min(100, u.pct) + '%;background:' + corPct(u.pct) + '"></i></div></div>'; }
const ponto = c => '<span class="ponto" style="background:' + c + '"></span>';
const errosDe = slug => S.erros.filter(e => e.slug === slug);
const errosAlerta = () => S.erros.filter(e => !emImpl(e.slug));   // os que contam como alerta (fora dos restaurantes em implantação)
const pagoValor = c => Number(c.valor_pago != null ? c.valor_pago : c.valor) || 0;
const atrasadas = id => S.cob.filter(c => (!id || c.restaurante_id === id) && !c.pago_em && c.vencimento && c.vencimento < hoje());
const mrr = () => S.lista.filter(r => r.situacao === 'ativo').reduce((s, r) => s + (Number(r.valor_mensal) || 0), 0);
function finMes(m){
  const cob = S.cob.filter(c => mesDe(c.vencimento || c.competencia) === m), rec = S.cob.filter(c => mesDe(c.pago_em) === m);
  const desp = S.desp.filter(d => mesDe(d.data) === m);
  const recebido = rec.reduce((s, c) => s + pagoValor(c), 0), aReceber = cob.filter(c => !c.pago_em).reduce((s, c) => s + (Number(c.valor) || 0), 0);
  const despPagas = desp.filter(d => d.pago).reduce((s, d) => s + (Number(d.valor) || 0), 0), despAbertas = desp.filter(d => !d.pago).reduce((s, d) => s + (Number(d.valor) || 0), 0);
  return { cob, rec, desp, recebido, aReceber, despPagas, despAbertas, despTotal:despPagas + despAbertas, lucro:recebido - despPagas };
}
const waLink = (tel, txt) => { let d = String(tel || '').replace(/\D/g, ''); if(!d) return ''; if(d.length <= 11) d = '55' + d; return 'https://wa.me/' + d + (txt ? '?text=' + encodeURIComponent(txt) : ''); };
/* Pix copia e cola (BR Code estático do Banco Central) com o valor da cobrança já preenchido */
function pixChave(k){ k = String(k || '').trim(); if(!k) return '';
  if(k.includes('@')) return k.toLowerCase(); if(/^\+/.test(k)) return '+' + k.replace(/\D/g, '');
  if(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(k)) return k.toLowerCase();
  const d = k.replace(/\D/g, ''); if(/^[\d\s().\/-]+$/.test(k)){ if(/[()]/.test(k) || (d.length === 13 && d.startsWith('55'))) return '+' + (d.length <= 11 ? '55' + d : d); return d; }
  return k; }
const pixTxt = (t, n) => String(t || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Za-z0-9 ]/g, '').trim().toUpperCase().slice(0, n);
function pixCopiaCola(valor, txid){
  const a = S.aj || {}, chave = pixChave(a.pix); if(!chave) return '';
  const f = (id, v) => id + String(v.length).padStart(2, '0') + v;
  const cidade = pixTxt(a.pix_cidade || String((S.termos || {}).foro || '').split('/')[0], 15) || 'BRASIL', nome = pixTxt(a.pix_nome, 25) || 'RECEBEDOR';
  let p = f('00', '01') + f('26', f('00', 'br.gov.bcb.pix') + f('01', chave)) + f('52', '0000') + f('53', '986') + (Number(valor) > 0 ? f('54', Number(valor).toFixed(2)) : '') + f('58', 'BR') + f('59', nome) + f('60', cidade) + f('62', f('05', (String(txid || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 25)) || '***')) + '6304';
  let crc = 0xFFFF; for(let i = 0; i < p.length; i++){ crc ^= p.charCodeAt(i) << 8; for(let j = 0; j < 8; j++) crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF; }
  return p + crc.toString(16).toUpperCase().padStart(4, '0');
}
const pixDe = c => pixCopiaCola(c.valor, 'C' + String(c.id || '').replace(/-/g, '').slice(0, 20));
window.rvPixCopiar = async id => { const c = S.cob.find(x => x.id === id); const t = c && pixDe(c); if(!t) return erro('Cadastre a sua chave Pix em Mais → Meus dados e Pix.'); if(await copiarTxt(t)) aviso('Pix copia e cola copiado (' + BRL(c.valor) + ').', 'ok'); };
function msgCobranca(c){
  const r = S.lista.find(x => x.id === c.restaurante_id) || {}, a = S.aj;
  const mod = a.msg_cobranca || 'Olá{contato}! Tudo bem? Passando para lembrar da {tipo} do sistema do {restaurante}: {valor}, com vencimento em {vencimento}.{pix}\nQualquer dúvida, estou à disposição. Obrigado!';
  return mod.replace(/\{contato\}/g, r.contato_nome ? ' ' + r.contato_nome.split(' ')[0] : '').replace(/\{restaurante\}/g, r.nome || '').replace(/\{valor\}/g, BRL(c.valor)).replace(/\{vencimento\}/g, dataBr(c.vencimento))
    .replace(/\{tipo\}/g, c.tipo === 'implantacao' ? 'taxa de implantação' : c.tipo === 'avulsa' ? (c.descricao || 'cobrança') : 'mensalidade de ' + mesNome(mesDe(c.competencia)))
    .replace(/\{pix\}/g, a.pix ? '\nPix: ' + a.pix + (a.pix_nome ? ' (' + a.pix_nome + ')' : '') + '\n\nPix copia e cola (já com o valor):\n' + pixDe(c) : '');
}

/* ---------- telas ---------- */
function tela(){
  clearInterval(timerAuto);
  if(!S.sess) return telaLogin();
  if(S.dono === null) return donoVerificar();
  if(!S.dono) return telaSemDono();
  desenhar();
}
async function donoVerificar(){
  $('app').innerHTML = '<div class="carregando"><div class="giro"></div>Carregando…</div>';
  try{
    const a = await rest('admins?select=user_id'); S.dono = !!(a && a.length);
    if(!S.dono){ const tem = await rpc('revenda_tem_dono'); if(!tem){ const r = await rpc('revenda_primeiro_acesso'); S.dono = !!(r && r.ok); } }
    if(S.dono) await carregar();
    tela();
    if(S.dono) setTimeout(() => { sincronizarServidor_().catch(() => {}); }, 3000);   // leva o código das atualizações para o servidor (atualização automática)
    if(S.dono) setTimeout(() => { carregadorAuto_().catch(() => {}); }, 4000);   // em segundo plano: mantém o carregador dos restaurantes em dia
  }catch(e){ erro(e.message); $('app').innerHTML = '<div class="login card"><p>Não foi possível abrir o painel.</p><button onclick="location.reload()">Tentar de novo</button> <button onclick="rvSair()">Sair</button></div>'; }
}
function telaSemDono(){ $('app').innerHTML = '<div class="login card"><h2>Acesso negado</h2><p>Este painel já tem um dono e a sua conta não é essa.</p><button onclick="rvSair()">Sair</button></div>'; }
function telaLogin(){
  $('app').innerHTML = '<div class="login"><div class="marca-painel">🍽️</div><h1>Painel de Revenda</h1><p class="mudo">Seus restaurantes, num lugar só.</p><div class="card">'
   + '<label for="lgE">E-mail</label><input id="lgE" type="email" autocomplete="username"><label for="lgS">Senha</label><input id="lgS" type="password" autocomplete="current-password">'
   + '<p style="margin-top:14px"><button class="principal grande" id="lgB">Entrar</button></p>'
   + '<p class="mudo pequeno">Primeiro acesso? <a href="#" id="lgC">Criar a conta do dono</a> (só funciona enquanto o painel não tem dono).</p></div></div>';
  const go = async criar => { const b = $('lgB'); b.disabled = true; try{ await entrar($('lgE').value.trim(), $('lgS').value, criar); S.dono = null; tela(); }catch(e){ erro(e.message); } b.disabled = false; };
  $('lgB').onclick = () => go(false); $('lgC').onclick = ev => { ev.preventDefault(); go(true); };
  $('lgS').onkeydown = ev => { if(ev.key === 'Enter') go(false); };
}
window.rvSair = () => { sessGravar(null); S = novoEstado(); tela(); };

const NAV = [['inicio','🏠','Início'],['restaurantes','🍽️','Restaurantes'],['saude','🩺','Saúde'],['dinheiro','💰','Dinheiro'],['mais','☰','Mais']];
/* no PC (tela larga) o menu vira uma barra lateral e mostra também estes atalhos, que no celular ficam em "Mais" */
const NAV_PC = [['vendas','🤝','Vendas e propostas'],['conectores','🔌','Conectores'],['assistente','✨','Assistente (IA)'],['guia','📘','Como criar'],['ajustes','⚙️','Meus dados e Pix']];
function desenhar(){
  clearInterval(timerAuto);
  const v = S.view, alertaSaude = errosAlerta().length + S.lista.filter(r => r.situacao !== 'encerrado' && ['problema'].includes(saudeDe(r.slug).geral)).length;
  const corpo = { inicio:vInicio, restaurantes:vRestaurantes, rest:vRest, novo:vNovo, saude:vSaude, dinheiro:vDinheiro, mais:vMais, vendas:vVendas, ajustes:vAjustes, guia:vGuia, assistente:vAssistente, conectores:vConectores, usuarios:vUsuarios }[v] || vInicio;
  const navOn = { rest:'restaurantes', novo:'restaurantes', vendas:'mais', ajustes:'mais', guia:'mais', assistente:'mais', conectores:'mais', usuarios:'mais' }[v] || v;
  $('app').innerHTML = '<header class="cab"><div class="cab-t" onclick="rvIr(\'inicio\')">🍽️ <b>Revenda</b></div><div class="cab-a">' + (v === 'rest' || v === 'novo' ? '<button class="mini" onclick="rvChat()" title="Assistente">✨</button> ' : '') + '<button class="mini" onclick="rvRecarregar()" title="Atualizar">⟳</button></div></header>'
    + '<main id="tela"></main>'
    + '<nav class="nav" aria-label="Menu"><div class="nav-marca" onclick="rvIr(\'inicio\')">🍽️ <b>Revenda</b></div>' + NAV.map(n => '<button class="' + (navOn === n[0] && !(n[0] === 'mais' && NAV_PC.some(x => x[0] === v)) ? 'on' : '') + (n[0] === 'mais' ? ' nav-mais' : '') + '" onclick="rvIr(\'' + n[0] + '\')"><span>' + n[1] + '</span>' + n[2] + (n[0] === 'saude' && alertaSaude ? '<i class="bolha">' + alertaSaude + '</i>' : '') + '</button>').join('')
    + '<div class="nav-sep"></div>' + NAV_PC.map(n => '<button class="nav-pc' + (v === n[0] ? ' on' : '') + '" onclick="rvIr(\'' + n[0] + '\')"><span>' + n[1] + '</span>' + n[2] + '</button>').join('') + '</nav>' + (v === 'rest' || v === 'novo' ? '' : '<button id="bAssist" class="b-assist" onclick="rvChat()" title="Assistente" aria-label="Abrir o assistente">✨</button>');
  corpo();
  if(['inicio','saude'].includes(v)) timerAuto = setInterval(async () => { if(document.hidden) return; await carregarSaude(); if(['inicio','saude'].includes(S.view) && !document.querySelector('.modal')) desenhar(); }, 120000);
  window.scrollTo(0, 0);
}
window.rvIr = v => { S.view = v; if(v !== 'rest') S.rest = null; desenhar(); };
window.rvRecarregar = async () => { try{ await carregar(); if(S.rest){ S.rest = normalizar(JSON.parse(JSON.stringify(S.lista.find(r => r.id === S.rest.id) || S.rest))); await carregarRest(); } aviso('Atualizado.', 'ok'); desenhar(); }catch(e){ erro(e.message); } };
const T = h => { $('tela').innerHTML = h; };

/* ---------- INÍCIO ---------- */
function alertas(){
  const L = [], h = hoje(), em3 = new Date(Date.now() + 3 * 864e5).toISOString().slice(0, 10);
  S.lista.filter(r => r.situacao !== 'encerrado').forEach(r => {
    const sd = saudeDe(r.slug), er = r.situacao === 'implantacao' ? 0 : errosDe(r.slug).length;
    if(er) L.push([3, '🐞', r.nome + ': ' + er + (er === 1 ? ' erro aberto' : ' erros abertos'), 'Erros que apareceram na tela do restaurante.', "rvIr('saude')"]);
    if(sd.geral === 'problema') L.push([3, '🔴', r.nome + ': sistema com problema', 'Veja o que está errado na Saúde.', "rvIr('saude')"]);
    else if(sd.geral === 'sem' && nEtapas(r) >= 8) L.push([2, '📡', r.nome + ': sem sinal ' + (sd.h ? haTempo(sd.min) : 'ainda'), 'O banco dele pode estar pausado ou o site fora do ar.', "rvIr('saude')"]);
    usoDe(sd.h).filter(u => u.pct >= 70).forEach(u => L.push([u.pct >= 90 ? 3 : 2, '📊', r.nome + ': ' + u.tit + ' em ' + String(u.pct).replace('.', ',') + '%', 'Plano grátis do Supabase perto do limite.', "rvIr('saude')"]));
    const av = (S.avCache || {})[r.id]; if(av && av.d.projeto && av.d.projeto.estado === 'INACTIVE' && r.situacao !== 'implantacao') L.push([3, '⏸️', r.nome + ': banco PAUSADO pelo Supabase', 'O site dele não funciona. Toque para reativar.', "rvAbrir('" + r.id + "','saude')"]);
    const vg = (S.vigia || {})[r.slug]; if(vg && vg.ligado && r.situacao !== 'implantacao') (vg.problemas || []).filter(p => p.id !== 'erros').forEach(p => L.push([p.nivel === 'alto' ? 3 : p.nivel === 'medio' ? 2 : 1, '🛡️', r.nome + ': ' + p.texto, 'Vigia · ' + (p.acao === 'atualizar_banco' ? 'toque para abrir Conectores e tocar em Atualizar' : 'toque para ver'), p.acao === 'atualizar_banco' ? "rvIr('conectores')" : p.acao === 'conectores' ? "rvAbrir('" + r.id + "','passo')" : "rvAbrir('" + r.id + "','saude')"]));
    if(r.bloqueado) L.push([1, '⛔', r.nome + ': acesso bloqueado', 'Libere quando ele pagar.', "rvAbrir('" + r.id + "','dinheiro')"]);
    const px = proxEtapa(r); if(px && ['implantacao','teste'].includes(r.situacao)) L.push([1, '🛠️', r.nome + ': próximo passo', px.titulo, "rvAbrir('" + r.id + "','passo')"]);
  });
  (S.atz || []).forEach(a => { const r = S.lista.find(x => x.id === a.restaurante_id); if(r) L.push([3, '⚠️', r.nome + ': atualização ' + ({ banco:'do banco', site:'do site', funcoes:'das funções', revisao:'do banco (precisa de você)' }[a.tipo] || a.tipo) + ' não subiu', (a.erro || '') + (a.detalhe ? ' — ' + a.detalhe : '') + ' Toque para tentar de novo.', "rvAtzTentar('" + r.id + "')"]); });
  ((S.painelAl || {}).problemas || []).forEach(p => L.push([p.nivel === 'alto' ? 3 : 2, '🩺', 'Painel: ' + p.texto, 'Veja em Mais > Saúde do painel.', "rvIr('mais')"]));
  const atr = atrasadas(); if(atr.length) L.push([3, '💸', atr.length + (atr.length === 1 ? ' cobrança atrasada' : ' cobranças atrasadas') + ' · ' + BRL(atr.reduce((s, c) => s + (Number(c.valor) || 0), 0)), 'Toque para cobrar pelo WhatsApp.', "rvIr('dinheiro')"]);
  const vence = S.cob.filter(c => !c.pago_em && c.vencimento >= h && c.vencimento <= em3); if(vence.length) L.push([2, '📅', vence.length + ' vence(m) nos próximos 3 dias', vence.map(c => nomeRest(c.restaurante_id)).join(', '), "rvIr('dinheiro')"]);
  const pp = (S.prom || []).filter(x => x.status === 'pendente'); if(pp.length) L.push([3, '🤝', pp.length + ' pedido(s) de promessa de pagamento', 'Aprove ou recuse.', "rvAbrir('" + pp[0].restaurante_id + "','dinheiro')"]);
  const dv = S.desp.filter(d => !d.pago && d.data <= h); if(dv.length) L.push([2, '🧾', dv.length + ' despesa(s) sua(s) a pagar', BRL(dv.reduce((s, d) => s + Number(d.valor), 0)), "rvIr('dinheiro')"]);
  const pa = S.prop.filter(p => !['fechado','perdido'].includes(p.status) && p.proxima_acao && p.proxima_acao <= h); if(pa.length) L.push([2, '📞', pa.length + ' proposta(s) para retornar hoje', pa.map(p => p.nome).join(', '), "rvIr('vendas')"]);
  return L.sort((a, b) => b[0] - a[0]);
}
function vInicio(){
  const m = hoje().slice(0, 7), f = finMes(m), A = alertas(), meta = Number(S.aj.meta) || 0, hr = new Date().getHours();
  const ativos = S.lista.filter(r => r.situacao === 'ativo').length, impl = S.lista.filter(r => ['implantacao','teste'].includes(r.situacao)).length;
  T('<h1 class="ola">' + (hr < 12 ? 'Bom dia' : hr < 18 ? 'Boa tarde' : 'Boa noite') + ' 👋</h1><p class="mudo">' + new Date().toLocaleDateString('pt-BR', { weekday:'long', day:'numeric', month:'long' }) + '</p>'
   + (S.aj.bemvindo_ok ? '' : boasPainel())
   + '<button class="principal grande acao-novo" onclick="rvNovo()">＋ Criar restaurante novo</button>'
   + '<div class="ini"><div class="ini-a">'
   + '<h2 class="sec-t">Precisa de você ' + (A.length ? '<span class="selo erro">' + A.length + '</span>' : '') + '</h2>'
   + (A.length ? '<div class="lista-alertas">' + A.slice(0, 12).map(a => '<button class="alerta n' + a[0] + '" onclick="' + a[4] + '"><span class="ic">' + a[1] + '</span><span><b>' + esc(a[2]) + '</b><small>' + esc(a[3]) + '</small></span><span class="seta">›</span></button>').join('') + '</div>'
      : '<div class="card vazio">✅ Tudo em dia. Nada pede a sua atenção agora.</div>')
   + '</div><div class="ini-b">'
   + '<div class="kpis">' + kpi('Recebido em ' + MESES[Number(m.slice(5)) - 1], BRL(f.recebido), 'ok') + kpi('Falta receber', BRL(f.aReceber), f.aReceber ? 'aviso' : '') + kpi('Lucro do mês', BRL(f.lucro), f.lucro < 0 ? 'erro' : 'ok') + kpi('Receita mensal fixa', BRL(mrr()), '') + '</div>'
   + (meta ? '<div class="card"><div class="linha"><b>🎯 Meta do mês</b><small>' + BRL(f.recebido) + ' de ' + BRL(meta) + '</small></div><div class="barra grossa"><i style="width:' + Math.min(100, f.recebido / meta * 100) + '%;background:var(--ok)"></i></div></div>' : '')
   + '<div class="kpis tres">' + kpi('Restaurantes ativos', ativos, '') + kpi('Em implantação', impl, '') + kpi('Erros abertos', errosAlerta().length, errosAlerta().length ? 'erro' : '') + '</div>'
   + '<div class="card"><div class="linha"><b>Últimos 6 meses</b><button class="mini" onclick="rvIr(\'dinheiro\')">Ver dinheiro ›</button></div>' + grafico(6) + '</div>'
   + '</div></div>');
  S.lista.filter(r => r.situacao !== 'encerrado' && temSb(r) && !(S.avCache || {})[r.id]).forEach(aoVivoMini);   // pausado aparece em "Precisa de você"
}
window.rvBemvindoOk = async () => { if(await salvarAjustes({ bemvindo_ok:true }, 'Pronto! Você pode rever o guia em Mais → Guia.')) vInicio(); };
function boasPainel(){
  return '<div class="card bem-vindo"><h2>👋 Bem-vindo ao seu Painel de Revenda</h2><p>Aqui você cria e cuida dos sistemas dos seus restaurantes. No menu (embaixo no celular, do lado no computador) ficam as 5 partes:</p><ul class="lista-bv">'
   + '<li><b>🏠 Início</b>: o que precisa de você hoje e como está o mês.</li><li><b>🍽️ Restaurantes</b>: cada cliente. Lá dentro, o <b>passo a passo</b> que monta um restaurante novo do zero, uma parte por vez.</li>'
   + '<li><b>🩺 Saúde</b>: se os sistemas estão funcionando e os erros que aparecem nas telas.</li><li><b>💰 Dinheiro</b>: mensalidades, quem pagou, suas despesas e o lucro.</li><li><b>☰ Mais</b>: propostas de venda, seus dados, Pix, planos e o assistente.</li></ul>'
   + '<p>O botão <b>✨</b> é o seu assistente: pergunte qualquer coisa ou peça para ele preparar uma cobrança.</p>'
   + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvIr(\'guia\')">📘 Como criar um restaurante</button><button class="mini" onclick="rvBemvindoOk()">Entendi</button></div></div>';
}
const dica = t => '<p class="dica">💡 ' + t + '</p>';
const kpi = (t, v, c) => '<div class="kpi ' + (c ? 'k-' + c : '') + '"><small>' + esc(t) + '</small><b>' + v + '</b></div>';
function grafico(n){
  const atual = hoje().slice(0, 7), ms = []; for(let k = n - 1; k >= 0; k--) ms.push(somaMes(atual, -k));
  const d = ms.map(m => { const f = finMes(m); return { m, a:f.recebido, b:f.despTotal }; }), mx = Math.max(1, ...d.map(x => Math.max(x.a, x.b)));
  const W = 320, H = 130, bw = W / n;
  return '<svg class="graf" viewBox="0 0 ' + W + ' ' + (H + 22) + '" role="img" aria-label="Recebido e despesas por mês">' + d.map((x, i) => { const ha = x.a / mx * H, hb = x.b / mx * H, x0 = i * bw + bw * .18;
      return '<rect x="' + x0 + '" y="' + (H - ha) + '" width="' + bw * .3 + '" height="' + ha + '" rx="3" fill="var(--ok)"><title>' + mesNome(x.m) + ': recebido ' + BRL(x.a) + '</title></rect><rect x="' + (x0 + bw * .33) + '" y="' + (H - hb) + '" width="' + bw * .3 + '" height="' + hb + '" rx="3" fill="var(--erro)" opacity=".8"><title>despesas ' + BRL(x.b) + '</title></rect><text x="' + (i * bw + bw / 2) + '" y="' + (H + 16) + '" text-anchor="middle" font-size="11" fill="var(--mudo)">' + mesCurto(x.m) + '</text>'; }).join('')
    + '</svg><div class="legenda"><span><i style="background:var(--ok)"></i>Recebido</span><span><i style="background:var(--erro)"></i>Despesas</span></div>';
}

/* ---------- RESTAURANTES ---------- */
function vRestaurantes(){
  const F = { todos:'Todos', ativo:'Ativos', implantacao:'Em implantação', atencao:'Com alerta', atraso:'Em atraso' };
  const q = (S.busca || '').toLowerCase(), passa = r => {
    if(q && !(r.nome + ' ' + r.slug + ' ' + (r.contato_nome || '') + ' ' + (r.cidade || '')).toLowerCase().includes(q)) return false;
    if(S.filtro === 'ativo') return r.situacao === 'ativo'; if(S.filtro === 'implantacao') return ['implantacao','teste'].includes(r.situacao);
    if(S.filtro === 'atencao') return r.situacao !== 'implantacao' && (saudeDe(r.slug).geral !== 'ok' || errosDe(r.slug).length); if(S.filtro === 'atraso') return atrasadas(r.id).length > 0; return true; };
  const L = S.lista.filter(passa);
  T('<div class="topo"><h1>Restaurantes</h1><button class="principal" onclick="rvNovo()">＋ Novo</button></div>'
   + dica('Toque num restaurante para ver o passo a passo, a saúde, o cadastro, a marca e as cobranças dele.') + '<input type="search" placeholder="🔎 Buscar por nome, dono ou cidade" value="' + esc(S.busca) + '" oninput="rvBusca(this.value)">'
   + '<div class="chips">' + Object.keys(F).map(k => '<button class="chip ' + (S.filtro === k ? 'on' : '') + '" onclick="rvFiltro(\'' + k + '\')">' + F[k] + '</button>').join('') + '</div>'
   + '<div id="listaR" class="grade">' + (L.length ? listaAgrupada_(L) : '<div class="card vazio">' + (S.lista.length ? 'Nenhum restaurante neste filtro.' : 'Nenhum restaurante ainda. Toque em "＋ Novo" para criar o primeiro.') + '</div>') + '</div>');
}
window.rvBusca = v => { S.busca = v; const a = document.activeElement, p = a && a.selectionStart; vRestaurantes(); const i = document.querySelector('input[type=search]'); if(i){ i.focus(); try{ i.setSelectionRange(p, p); }catch(e){} } };
window.rvFiltro = f => { S.filtro = f; vRestaurantes(); };
function listaAgrupada_(L){
  const feito = {}, out = [];
  L.forEach(r => {
    const g = r.cliente_id ? S.lista.filter(x => x.cliente_id === r.cliente_id) : [];
    if(g.length < 2) return out.push(cartaoRest(r));
    if(feito[r.cliente_id]) return; feito[r.cliente_id] = 1;
    const ls = L.filter(x => x.cliente_id === r.cliente_id);
    out.push('<div class="card" style="grid-column:1/-1"><div class="linha"><b>👥 ' + esc(r.contato_nome || r.nome) + '</b><small class="mudo">' + g.length + ' lojas</small></div><div class="grade" style="margin-top:8px">' + ls.map(cartaoRest).join('') + '</div><button class="mini" style="margin-top:8px" onclick="rvOutraLoja(\'' + r.id + '\')">＋ Adicionar outra loja</button></div>');
  });
  return out.join('');
}
window.rvOutraLoja = id => {
  const r = S.lista.find(x => x.id === id); if(!r) return;
  const cid = r.cliente_id || r.id, n = S.lista.filter(x => (x.cliente_id || x.id) === cid).length + 1;
  rvNovo({ nome:r.nome.replace(/\s*[-–]\s*loja\s*\d+$/i, '') + ' - Loja ' + n, contato_nome:r.contato_nome, telefone:r.contato_telefone, email:r.contato_email, cidade:r.cidade, plano:r.plano, valor_mensal:r.valor_mensal, taxa_implantacao:r.taxa_implantacao, modulos:r.modulos });
  S.novo.cliente_id = cid; S.novo.base = r; S.novo.dia_vencimento = r.dia_vencimento || S.novo.dia_vencimento; vNovo();
};
function cartaoRest(r){
  const n = nEtapas(r), p = Math.round(n / ETAPAS.length * 100), sd = saudeDe(r.slug), er = errosDe(r.slug).length, at = atrasadas(r.id), px = proxEtapa(r);
  return '<div class="card cr' + (r.bloqueado ? ' bloq' : '') + '" onclick="rvAbrir(\'' + r.id + '\')"><div class="linha"><b class="cr-n">' + esc(r.nome) + '</b><span class="selo ' + esc(r.situacao) + '">' + (r.bloqueado ? '⛔ Bloqueado' : esc(SIT[r.situacao] || r.situacao)) + '</span></div>'
   + '<small class="mudo">' + esc([r.contato_nome, r.cidade].filter(Boolean).join(' · ') || r.slug) + '</small>'
   + '<div class="cr-s">' + ponto(SAUDE_COR[sd.geral]) + '<b>' + SAUDE_ROT[sd.geral] + '</b><small class="mudo"> · ' + (sd.h ? haTempo(sd.min) : 'sem sinal ainda') + '</small>' + (er ? ' <span class="selo' + (r.situacao === 'implantacao' ? '' : ' erro') + '">🐞 ' + er + '</span>' : '') + '</div>'
   + (n < ETAPAS.length ? '<div class="barra"><i style="width:' + p + '%"></i></div><small>Implantação ' + p + '% · próximo: <b>' + esc(px.titulo) + '</b></small>' : '')
   + '<div class="linha cr-d"><small>' + (r.valor_mensal ? BRL(r.valor_mensal) + '/mês' : 'Sem mensalidade') + '</small>' + (at.length ? '<small class="txt-erro">💸 ' + at.length + ' em atraso</small>' : '') + '</div></div>';
}

/* ---------- NOVO RESTAURANTE (assistente de 3 perguntas) ---------- */
const slugDe = t => String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40);
window.rvNovo = (prop) => { const p = prop || {}; S.novo = { passo:0, nome:p.nome || '', slug:slugDe(p.nome), slugMexido:false, contato_nome:p.contato_nome || '', contato_telefone:p.telefone || '', contato_email:p.email || '', cidade:p.cidade || '', plano:p.plano || '', valor_mensal:p.valor_mensal || '', taxa_implantacao:p.taxa_implantacao || '', dia_vencimento:S.aj.dia_padrao || 10, modulos:Object.keys(p.modulos || {}).length ? p.modulos : null, proposta:p.id || null }; S.view = 'novo'; desenhar(); };
function vNovo(){
  const n = S.novo, P = ['Como se chama o restaurante?','Quem é o dono?','Quanto ele vai pagar?'], planos = S.aj.planos || [];
  let c = '';
  if(n.passo === 0) c = '<label for="nNome">Nome do restaurante</label><input id="nNome" value="' + esc(n.nome) + '" placeholder="Ex.: Pizzaria do João" oninput="rvNovoNome(this.value)" autofocus>'
    + '<label for="nSlug">Código (vai no endereço do site)</label><input id="nSlug" value="' + esc(n.slug) + '" oninput="S_novoSlug(this.value)"><small class="mudo">Só letras minúsculas, números e hífen. Ex.: pizzaria-do-joao</small>';
  if(n.passo === 1) c = '<label for="nCn">Nome do dono</label><input id="nCn" value="' + esc(n.contato_nome) + '" placeholder="Ex.: João Silva">'
    + '<label for="nCt">WhatsApp</label><input id="nCt" type="tel" value="' + esc(n.contato_telefone) + '" placeholder="(16) 99999-9999">'
    + '<label for="nCe">E-mail (opcional)</label><input id="nCe" type="email" value="' + esc(n.contato_email) + '">'
    + '<label for="nCi">Cidade</label><input id="nCi" value="' + esc(n.cidade) + '" placeholder="Ex.: Jaboticabal/SP">';
  if(n.passo === 2) c = (planos.length ? '<p class="mudo">Escolha um dos seus planos:</p><div class="planos">' + planos.map((p, i) => '<button class="plano ' + (n.plano === p.nome ? 'on' : '') + '" onclick="rvNovoPlano(' + i + ')"><b>' + esc(p.nome) + '</b><span>' + BRL(p.valor) + '/mês</span>' + (p.implantacao ? '<small>+ ' + BRL(p.implantacao) + ' implantação</small>' : '') + '</button>').join('') + '</div>' : '<p class="mudo pequeno">Dica: cadastre seus planos em Mais → Planos e preços para escolher com um toque.</p>')
    + '<div class="cols"><div><label for="nVm">Mensalidade (R$)</label><input id="nVm" inputmode="decimal" value="' + esc(n.valor_mensal) + '"></div><div><label for="nTx">Taxa de implantação (R$)</label><input id="nTx" inputmode="decimal" value="' + esc(n.taxa_implantacao) + '"></div></div>'
    + '<label for="nDv">Dia do vencimento (1 a 28)</label><input id="nDv" type="number" min="1" max="28" value="' + esc(n.dia_vencimento) + '">';
  T('<div class="topo"><button class="mini" onclick="rvIr(\'restaurantes\')">✕ Cancelar</button><small class="mudo">Pergunta ' + (n.passo + 1) + ' de 3</small></div>'
   + '<div class="pontos">' + P.map((x, i) => '<i class="' + (i <= n.passo ? 'on' : '') + '"></i>').join('') + '</div>'
   + '<div class="card wizard"><h1>' + P[n.passo] + '</h1>' + c + '</div>'
   + '<div class="rodape-acoes">' + (n.passo ? '<button onclick="rvNovoPasso(-1)">← Voltar</button>' : '<span></span>') + '<button class="principal grande" onclick="rvNovoPasso(1)">' + (n.passo < 2 ? 'Continuar →' : '✅ Criar restaurante') + '</button></div>');
}
window.rvNovoNome = v => { S.novo.nome = v; if(!S.novo.slugMexido){ S.novo.slug = slugDe(v); const s = $('nSlug'); if(s) s.value = S.novo.slug; } };
window.S_novoSlug = v => { S.novo.slug = v; S.novo.slugMexido = true; };
window.rvNovoPlano = i => { lerNovo(); const p = S.aj.planos[i]; Object.assign(S.novo, { plano:p.nome, valor_mensal:p.valor, taxa_implantacao:p.implantacao || '', modulos:p.modulos || null }); vNovo(); };
function lerNovo(){ const n = S.novo, v = id => ($(id) || {}).value; if(n.passo === 0){ n.nome = (v('nNome') || '').trim(); n.slug = slugDe(v('nSlug')); } if(n.passo === 1){ n.contato_nome = (v('nCn') || '').trim(); n.contato_telefone = (v('nCt') || '').trim(); n.contato_email = (v('nCe') || '').trim(); n.cidade = (v('nCi') || '').trim(); } if(n.passo === 2){ n.valor_mensal = v('nVm'); n.taxa_implantacao = v('nTx'); n.dia_vencimento = v('nDv'); } }
window.rvNovoPasso = async d => {
  lerNovo(); const n = S.novo;
  if(d > 0 && n.passo === 0){ if(!n.nome) return erro('Escreva o nome do restaurante.'); if(!n.slug || n.slug.length < 3) return erro('O código precisa de pelo menos 3 letras.'); if(S.lista.some(r => r.slug === n.slug)) return erro('Já existe um restaurante com esse código. Mude o código.'); }
  if(d > 0 && n.passo === 1 && !n.contato_nome) return erro('Escreva o nome do dono (pode mudar depois).');
  if(d > 0 && n.passo === 2) return criarRest();
  n.passo = Math.max(0, n.passo + d); vNovo();
};
async function criarRest(){
  const n = S.novo, mod = {}; MODULOS.forEach(m => { mod[m.id] = n.modulos && n.modulos[m.id] != null ? !!n.modulos[m.id] : m.pad; });
  const t = TEMAS.find(x => x.id === 'classico');
  const marcaBase = n.base && n.base.marca ? JSON.parse(JSON.stringify(n.base.marca)) : null;
  const dia = Math.min(28, Math.max(1, parseInt(n.dia_vencimento, 10) || 10));
  try{
    const r = await rest('restaurantes', 'POST', { slug:n.slug, nome:n.nome, situacao:'implantacao', contato_nome:n.contato_nome || null, contato_telefone:n.contato_telefone || null, contato_email:n.contato_email || null, cidade:n.cidade || null, plano:n.plano || null, valor_mensal:num(n.valor_mensal), taxa_implantacao:num(n.taxa_implantacao), dia_vencimento:dia, inicio_em:hoje(), motor:MOTOR_PADRAO, modulos:mod,
      cliente_id:n.cliente_id || null, marca:marcaBase || { tema:t.id, slogan:'', assistente:'Assistente', jogos:{ tema:'generico' }, cores:{ destaque:t.destaque, botao:t.botao, fundo:t.fundo }, logos:{} }, etapas:{ cadastro:{ feita:true, em:new Date().toISOString() } } });
    if(n.base && !n.base.cliente_id){ try{ await rest('restaurantes?id=eq.' + n.base.id, 'PATCH', { cliente_id:n.cliente_id }); }catch(e){} }
    await hist(r[0].id, 'Restaurante criado', n.nome + (n.base ? ' (outra loja de ' + n.base.nome + ')' : ''));
    if(n.proposta){ try{ await rest('propostas?id=eq.' + n.proposta, 'PATCH', { status:'fechado', restaurante_id:r[0].id, atualizado_em:new Date().toISOString() }); }catch(e){} }
    await carregar(); aviso('Restaurante criado! Agora é seguir o passo a passo.', 'ok'); window.rvAbrir(r[0].id, 'passo');
  }catch(e){ erro(/duplicate|unique/i.test(e.message) ? 'Já existe um restaurante com esse código.' : e.message); }
}

/* ---------- UM RESTAURANTE ---------- */
window.rvAbrir = async (id, aba) => {
  const r = S.lista.find(x => x.id === id); if(!r) return;
  S.rest = normalizar(JSON.parse(JSON.stringify(r))); S._snap = snapSite_(S.rest); S.view = 'rest'; S.aba = aba || (nEtapas(S.rest) < ETAPAS.length ? 'passo' : 'saude'); S.passoVer = null; S.res = {};
  await carregarRest(); desenhar();
};
async function carregarRest(){ try{ S.cobR = await rest('cobrancas?restaurante_id=eq.' + S.rest.id + '&select=*&order=vencimento.desc.nullslast'); S.hist = await rest('historico?restaurante_id=eq.' + S.rest.id + '&select=*&order=em.desc&limit=60'); S.aceite = (await tenta(() => rest('aceites_termos?restaurante_id=eq.' + S.rest.id + '&select=*&order=aceito_em.desc&limit=1'), []))[0] || null; S.dono_link = (await tenta(() => rest('dono_links?restaurante_id=eq.' + S.rest.id + '&select=*'), []))[0] || null; }catch(e){ erro(e.message); } }
const ABAS = [['passo','🛠️ Passo a passo'],['saude','🩺 Saúde'],['ajustes','⚙️ Ajustes'],['dados','📋 Cadastro'],['marca','🎨 Marca'],['dinheiro','💰 Cobrança'],['contrato','📄 Contrato']];
function vRest(){
  const r = S.rest, n = nEtapas(r), sd = saudeDe(r.slug), sb = refDe(r);
  T('<div class="topo"><button class="mini" onclick="rvIr(\'restaurantes\')">← Restaurantes</button><span class="selo ' + esc(r.situacao) + '">' + esc(SIT[r.situacao] || r.situacao) + '</span></div>'
   + '<h1>' + esc(r.nome) + '</h1><div class="linha" style="justify-content:flex-start;gap:6px"><small class="mudo">' + ponto(SAUDE_COR[sd.geral]) + SAUDE_ROT[sd.geral] + ' · implantação ' + n + ' de ' + ETAPAS.length + '</small></div>'
   + '<div class="atalhos">' + (r.site_url ? '<a class="btn mini" href="' + esc(r.site_url) + '" target="_blank" rel="noopener">🌐 Site</a>' : '') + (r.contato_telefone ? '<a class="btn mini" href="' + esc(waLink(r.contato_telefone)) + '" target="_blank" rel="noopener">💬 WhatsApp</a>' : '')
     + (sb ? '<a class="btn mini" href="https://supabase.com/dashboard/project/' + esc(sb) + '" target="_blank" rel="noopener">🗄️ Supabase</a>' : '') + (r.github_url ? '<a class="btn mini" href="' + esc(r.github_url) + '" target="_blank" rel="noopener">🐙 GitHub</a>' : '') + '</div>'
   + '<div class="atalhos"><button class="btn mini" onclick="rvOutraLoja(\'' + r.id + '\')">＋ Adicionar outra loja deste cliente</button></div>'
   + '<div class="abas">' + ABAS.map(a => '<button class="' + (S.aba === a[0] ? 'on' : '') + '" onclick="rvAba(\'' + a[0] + '\')">' + a[1] + '</button>').join('') + '</div><div id="corpo"></div>');
  ({ passo:abaPasso, saude:abaSaude, ajustes:abaAjustesRest, dados:abaDados, marca:abaMarcaTudo, dinheiro:abaCobranca, contrato:abaContrato })[S.aba]();
}
window.rvAba = a => { S.aba = a; vRest(); };
const C = h => { $('corpo').innerHTML = h; };

/* formulário do restaurante */
function get(o, p){ return p.split('.').reduce((a, k) => (a == null ? a : a[k]), o); }
function set(o, p, v){ const ks = p.split('.'); let a = o; ks.slice(0, -1).forEach(k => { a = a[k] = a[k] || {}; }); a[ks[ks.length - 1]] = v; }
const ROT = { nome:'Nome do restaurante', contato_nome:'Nome do dono', contato_telefone:'WhatsApp do dono', contato_email:'E-mail do dono', cidade:'Cidade', documento:'CPF ou CNPJ do cliente', plano:'Plano', valor_mensal:'Mensalidade (R$)', taxa_implantacao:'Taxa de implantação (R$)', dia_vencimento:'Dia do vencimento (1 a 28)', inicio_em:'Início do contrato',
  supabase_url:'Endereço do banco (Project URL)', supabase_chave:'Chave pública (começa com sb_publishable_)', site_url:'Endereço do site', github_url:'Endereço do repositório no GitHub', dominio:'Domínio próprio (opcional, só o nome)', api_url:'Planilha principal (endereço /exec)', contingencia_url:'Planilha de contingência (endereço /exec)', contingencia_chave:'Chave pública da contingência (CONTINGENCIA_CHAVE_PUBLICA)', push_chave_publica:'Chave pública dos avisos', motor:'Versão do sistema (deixe em branco para receber as atualizações)' };
const PH = { supabase_url:'https://xxxx.supabase.co', supabase_chave:'sb_publishable_…', site_url:'https://usuario.github.io/codigo/', github_url:'https://github.com/usuario/codigo', contato_telefone:'(16) 99999-9999', dominio:'cardapio.meurestaurante.com.br', motor:MOTOR_PADRAO, api_url:'https://script.google.com/…/exec', contingencia_url:'https://script.google.com/…/exec' };
const NUMS = ['valor_mensal','taxa_implantacao','dia_vencimento'];
function campo(k, o){ o = o || {}; const v = get(S.rest, k); const tipo = k === 'inicio_em' ? 'date' : k === 'contato_email' ? 'email' : k === 'contato_telefone' ? 'tel' : 'text';
  return '<label for="f_' + k.replace(/\./g, '_') + '">' + esc(o.rot || ROT[k] || k) + '</label><input id="f_' + k.replace(/\./g, '_') + '" data-k="' + k + '" type="' + tipo + '"' + (NUMS.includes(k) ? ' inputmode="decimal"' : '') + ' value="' + esc(v == null ? '' : v) + '" placeholder="' + esc(PH[k] || o.ph || '') + '">'; }
function lerForm(){ document.querySelectorAll('#tela [data-k]').forEach(el => { const k = el.dataset.k; let v = el.type === 'checkbox' ? el.checked : el.value.trim(); if(NUMS.includes(k)) v = num(v); else if(v === '' && el.type !== 'checkbox' && !/^(marca|modulos)\./.test(k)) v = null; set(S.rest, k, v); }); }
const COLS = ['cliente_id','nome','situacao','dominio','site_url','github_url','supabase_url','supabase_chave','api_url','contingencia_url','contingencia_chave','push_chave_publica','marca','modulos','etapas','contato_nome','contato_telefone','contato_email','cidade','documento','plano','valor_mensal','taxa_implantacao','dia_vencimento','motor','inicio_em','observacoes'];
async function salvar(msg){
  const _antesSite = S._snap;
  lerForm();
  { const r = S.rest, m = /^https:\/\/([a-z0-9-]+)\.github\.io\/([^/]+)\/?$/i.exec(r.site_url || ''); if(m && !r.github_url) r.github_url = 'https://github.com/' + m[1] + '/' + m[2]; }   // site no GitHub Pages: o repositório sai do endereço
  const corpo = {}; COLS.forEach(c => { if(S.rest[c] !== undefined) corpo[c] = S.rest[c]; });
  if(corpo.dominio) corpo.dominio = String(corpo.dominio).replace(/^https?:\/\//, '').replace(/\/.*$/, '');
  ['site_url','github_url','supabase_url'].forEach(k => { if(corpo[k]){ let u = String(corpo[k]).trim(); if(!/^https?:\/\//.test(u)) u = 'https://' + u; if(k === 'site_url' && !u.endsWith('/')) u += '/'; if(k !== 'site_url') u = u.replace(/\/+$/, ''); corpo[k] = u; } });
  if(corpo.dia_vencimento != null) corpo.dia_vencimento = Math.min(28, Math.max(1, Math.round(corpo.dia_vencimento)));
  try{
    const r = await rest('restaurantes?id=eq.' + S.rest.id, 'PATCH', corpo);
    if(!r || !r[0]) throw new Error('O banco não confirmou a gravação. Saia e entre de novo no painel.');
    const etLocal = S.rest.etapas; S.rest = normalizar(r[0]);
    const igual = (a, b) => Object.keys(b || {}).every(k => !!(a && a[k] && a[k].feita) === !!(b[k] && b[k].feita));
    if(!igual(S.rest.etapas, etLocal)) throw new Error('O banco recebeu, mas não guardou a etapa. Tente de novo.');
    const i = S.lista.findIndex(x => x.id === S.rest.id); if(i >= 0) S.lista[i] = JSON.parse(JSON.stringify(S.rest));
    aviso(msg || 'Salvo.', 'ok');
    try{ await autoSite_(_antesSite); }catch(e){ /* a publicação automática nunca atrapalha o salvar */ }
    return true;
  }catch(e){ S.ultimoErro = /unique|duplicate/i.test(e.message) ? 'Esse endereço já pertence a outro restaurante.' : e.message; erro(S.ultimoErro); return false; }
}
window.rvSalvar = async (aba) => { if(await salvar()){ await hist(S.rest.id, 'Dados salvos', aba || S.aba); vRest(); } };
const botSalvar = (txt) => '<p><button class="principal" onclick="rvSalvar()">' + (txt || '💾 Salvar') + '</button></p>';

/* ---------- PASSO A PASSO (uma parte por vez) ---------- */
function sub(t, link){ const r = S.rest, so = (r.site_url || '').replace(/\/+$/, ''), host = (r.site_url || '').replace(/^https?:\/\//, '').split('/')[0];
  const gh = ghUsuario(r);
  return String(t).replace(/\{nome\}/g, r.nome).replace(/\{slug\}/g, r.slug).replace(/\{ref\}/g, refDe(r) || (link ? '_' : '(projeto do Supabase)')).replace(/\{supabase_url\}/g, r.supabase_url || '(endereço do Supabase)')
    .replace(/\{site_url\}/g, r.site_url || (link ? 'https://github.com' : '(endereço do site)')).replace(/\{site_origem\}/g, so ? so.replace(/^(https?:\/\/[^/]+).*$/, '$1') : '(endereço do site)')
    .replace(/\{github_url\}/g, r.github_url || (link ? 'https://github.com' : '(endereço do repositório)')).replace(/\{gh_usuario\}/g, gh || (link ? 'new' : 'seu-usuario')).replace(/\{dominio_site\}/g, host || '(domínio do site)'); }
function ghUsuario(r){ const a = (r.github_url || '').replace(/^https?:\/\/(www\.)?github\.com\//, '').split('/')[0]; if(a && !/^https?:/.test(a)) return a; const h = (r.site_url || '').replace(/^https?:\/\//, '').split('/')[0]; return /\.github\.io$/.test(h) ? h.replace(/\.github\.io$/, '') : ''; }
const moduloDesligado = e => e.modulo && S.rest.modulos && S.rest.modulos[e.modulo] === false;
/* "Pronto para entregar?": confere sozinho o que costuma faltar antes de entregar o sistema ao dono */
function prontoChecks(r){
  const sd = saudeDe(r.slug), h = sd.h, itens = (h && h.itens) || [], cobs = S.cob.filter(c => c.restaurante_id === r.id).concat((S.cobR || []).filter(c => c.restaurante_id === r.id)), t = S.termos || {};
  const ruins = itens.filter(i => i.nivel === 'problema' && !/^Plano grátis:/i.test(i.titulo || ''));
  return [
    [!!(r.contato_nome && r.contato_telefone), 'Nome e WhatsApp do dono', 'aba Cadastro'],
    [!!r.site_url, 'Endereço do site', 'etapa Colocar o site no ar'],
    [!!refDe(r) && !!r.supabase_chave, 'Banco ligado ao site (endereço e chave)', 'etapa Criar o banco de dados'],
    [!!(h && sd.min != null && sd.min <= 45), 'O sistema manda o sinal de saúde', h ? 'último sinal ' + haTempo(sd.min) : 'ainda não mandou: confira o banco e as tarefas agendadas'],
    [!!h && !ruins.length, 'Saúde sem problema grave', ruins.length ? ruins.slice(0, 2).map(i => i.titulo).join(', ') : (h ? '' : 'sem sinal ainda')],
    [!!(r.marca && (r.marca.nome || r.marca.cor || r.marca.logo)), 'Marca (nome, cor, logo)', 'aba Marca'],
    [!!(t.fornecedor_nome && t.fornecedor_doc && t.foro), 'Seus dados nos termos de uso', 'Mais → Meus dados e Pix'],
    [!!S.aceite, 'Dono aceitou os termos', 'ele aceita no primeiro acesso ao sistema'],
    [!!(r.valor_mensal && r.dia_vencimento), 'Mensalidade e vencimento', 'aba Cadastro'],
    [cobs.length > 0, 'Primeira cobrança gerada', 'aba Cobrança'],
    [temSb(r), 'Conector do Supabase (para ajustes e atualizações)', 'etapa Ligar o GitHub e o Supabase']
  ];
}
function prontoHtml(r){
  if(r.situacao === 'ativo') return '';
  const L = prontoChecks(r), ok = L.filter(x => x[0]).length;
  return '<details class="card pronto"' + (ok === L.length || nEtapas(r) >= ETAPAS.length - 2 ? ' open' : '') + '><summary><b>📦 Pronto para entregar?</b> <span class="selo' + (ok === L.length ? ' ativo' : '') + '">' + ok + ' de ' + L.length + '</span></summary>'
   + L.map(x => '<div class="pronto-i">' + (x[0] ? '✅' : '⬜') + ' <span><b>' + esc(x[1]) + '</b>' + (!x[0] && x[2] ? '<br><small class="mudo">' + esc(x[2]) + '</small>' : '') + '</span></div>').join('')
   + (ok === L.length ? '<p><button class="principal" onclick="rvAtivar()">🎉 Tudo certo: mudar para Ativo</button></p>' : '<small class="mudo">Confere sozinho. O que estiver ⬜ ainda falta.</small>') + '</details>';
}
function abaPasso(){
  const r = S.rest, prox = proxEtapa(r), atual = ETAPAS.find(x => x.id === S.passoVer) || prox;
  const fases = FASES.map((x, k) => { const n = x[1].filter(id => etapaFeita(r, id)).length, ok = n === x[1].length, alvo = x[1].find(id => !etapaFeita(r, id)) || x[1][0], on = atual && x[1].includes(atual.id);
    return '<button class="fase ' + (on ? 'on' : '') + (ok ? ' ok' : '') + '" onclick="rvVerPasso(\'' + alvo + '\')"><b>' + (ok ? '✓' : k + 1) + '</b><span>' + x[0] + '</span><small>' + n + '/' + x[1].length + '</small></button>'; }).join('');
  if(!atual){ C('<div class="fases">' + fases + '</div><div class="card vazio grande-ok">🎉<h2>Implantação completa!</h2><p class="mudo">Acompanhe a saúde dele na aba Saúde e as cobranças na aba Cobrança.</p></div>' + prontoHtml(r) + listaEtapas()); return; }
  const i = ETAPAS.indexOf(atual), f = etapaFeita(r, atual.id), N = atual.partes.length, todas = !!S.tudoAberto[atual.id];
  let k = S.parte[atual.id]; if(k == null || k >= N) k = 0;
  const parteHtml = (p, j) => '<div class="parte"><div class="parte-n">' + (j + 1) + '</div><div class="parte-t"><p>' + esc(sub(p.t)) + '</p>'
     + (p.link ? '<a class="btn mini abrir" href="' + esc(sub(p.link, true)) + '" target="_blank" rel="noopener">Abrir ↗</a>' : '')
     + (p.copiar ? '<div class="tabela-copia">' + sub(p.copiar).split('\n').map((l, n) => '<div class="linha-copia"><div class="linha"><code id="cp_' + atual.id + '_' + j + '_' + n + '">' + esc(l) + '</code><button class="mini" onclick="rvCopiar(\'cp_' + atual.id + '_' + j + '_' + n + '\')">📋 Copiar</button></div></div>').join('') + '</div>' : '')
     + (p.extra ? '<div class="extra" id="ex_' + atual.id + '_' + j + '"></div>' : '') + '</div></div>';
  C('<div class="fases">' + fases + '</div><div class="passo-grid"><div class="passo-main">'
   + '<div class="card etapa' + (f ? ' feita' : '') + '"><div class="linha"><small class="mudo">Etapa ' + (i + 1) + ' de ' + ETAPAS.length + (atual.opcional ? ' · opcional' : '') + ' · ⏱️ ' + esc(atual.tempo || '') + '</small>' + (f ? '<span class="selo ativo">✓ Feita</span>' : '') + '</div>'
   + '<h2 class="etapa-t">' + esc(atual.titulo) + '</h2>'
   + '<div class="porque">💡 <b>Para que serve:</b> ' + esc(sub(atual.porque)) + '</div>'
   + (atual.precisa ? '<div class="precisa"><b>Você vai precisar:</b><ul>' + atual.precisa.map(x => '<li>' + esc(sub(x)) + '</li>').join('') + '</ul></div>' : '')
   + (moduloDesligado(atual) ? '<div class="res aviso">Este módulo está desligado para este restaurante: pode tocar em "Pular".</div>' : '')
   + '<div class="partes-cab"><b>' + (todas ? 'Todas as partes' : 'Parte ' + (k + 1) + ' de ' + N) + '</b>' + (N > 1 ? '<button class="mini" onclick="rvTodas(\'' + atual.id + '\')">' + (todas ? 'Uma por vez' : 'Ver todas') + '</button>' : '') + '</div>'
   + (todas ? atual.partes.map(parteHtml).join('') : '<div class="pontos">' + atual.partes.map((p, j) => '<i class="' + (j <= k ? 'on' : '') + '" onclick="rvParte(\'' + atual.id + '\',' + j + ')"></i>').join('') + '</div>' + parteHtml(atual.partes[k], k))
   + (atual.pedido ? '<details class="claude"><summary>🤖 Prefere que o Claude faça? Toque aqui</summary><p class="mudo pequeno">Copie e cole na conversa com o Claude. Ele faz e te avisa.</p><div class="copiar" id="pd_' + atual.id + '">' + esc(sub(atual.pedido)) + '</div><button class="mini" onclick="rvCopiar(\'pd_' + atual.id + '\')">📋 Copiar pedido</button></details>' : '')
   + '<div class="rodape-acoes">'
   + (!todas && k > 0 ? '<button onclick="rvParte(\'' + atual.id + '\',' + (k - 1) + ')">← Parte anterior</button>' : (i > 0 ? '<button onclick="rvVerPasso(\'' + ETAPAS[i - 1].id + '\')">← Etapa anterior</button>' : '<span></span>'))
   + (!todas && k < N - 1 ? '<button class="principal grande" onclick="rvParte(\'' + atual.id + '\',' + (k + 1) + ')">Próxima parte →</button>'
      : f ? '<span class="dir"><button class="mini" onclick="rvEtapa(\'' + atual.id + '\',false)">Desmarcar</button>' + (i < ETAPAS.length - 1 ? ' <button class="principal" onclick="rvVerPasso(\'' + ETAPAS[i + 1].id + '\')">Próxima etapa →</button>' : '') + '</span>'
      : '<span class="dir">' + (atual.opcional || moduloDesligado(atual) || atual.id === 'drive' || atual.id === 'ia' ? '<button class="mini" onclick="rvEtapa(\'' + atual.id + '\',true,true)">Pular</button> ' : '') + '<button class="principal grande" onclick="rvEtapa(\'' + atual.id + '\',true)">✅ Fiz esta etapa</button></span>')
   + '</div></div></div><aside class="passo-lado">' + prontoHtml(r) + listaEtapas(atual.id) + '</aside></div>');
  (todas ? atual.partes.map((p, j) => [p, j]) : [[atual.partes[k], k]]).forEach(([p, j]) => { if(p.extra) desenharExtra(atual, p.extra, $('ex_' + atual.id + '_' + j)); });
}
function listaEtapas(atualId){
  return '<details class="card lista-etapas"' + (innerWidth >= 1024 ? ' open' : '') + '><summary><b>📋 Ver todas as etapas</b> <small class="mudo">(' + nEtapas(S.rest) + ' de ' + ETAPAS.length + ' feitas)</small></summary>'
   + ETAPAS.map((x, k) => { const e = S.rest.etapas[x.id], f = e && e.feita; return '<button class="item-etapa' + (x.id === atualId ? ' on' : '') + '" onclick="rvVerPasso(\'' + x.id + '\')"><span>' + (f ? (e.pulada ? '⏭️' : '✅') : '⬜') + '</span><span><b>' + (k + 1) + '. ' + esc(x.titulo) + '</b><small>' + esc(x.curto || '') + '</small></span><span class="seta">›</span></button>'; }).join('') + '</details>';
}
window.rvVerPasso = id => { S.passoVer = id; abaPasso(); window.scrollTo(0, 0); };
window.rvParte = (id, k) => { S.parte[id] = k; abaPasso(); const e = document.querySelector('.etapa'); if(e) e.scrollIntoView({ behavior:'smooth', block:'start' }); };
window.rvTodas = id => { S.tudoAberto[id] = !S.tudoAberto[id]; abaPasso(); };
window.rvCopiar = async id => { const el = $(id); if(!el) return; const t = el.dataset.txt != null ? el.dataset.txt : el.textContent; if(await copiarTxt(t)) aviso('Copiado! Agora é só colar.', 'ok'); else erro('Não deu para copiar. Toque e segure no texto para copiar manualmente.'); };
async function copiarTxt(t){ try{ await navigator.clipboard.writeText(t); return true; }catch(e){ try{ const a = document.createElement('textarea'); a.value = t; a.style.position = 'fixed'; a.style.opacity = '0'; document.body.appendChild(a); a.select(); const ok = document.execCommand('copy'); a.remove(); return ok; }catch(e2){ return false; } } }
/* etapas sem as quais o restaurante não pode ser entregue (as planilhas de reserva são obrigatórias) */
const FALTA_ENTREGA = ['banco','funcoes','publicar','entrada','drive','planilhas','teste'];
window.rvItem = (id, k, v) => { const e = S.rest.etapas, x = e[id] = e[id] || {}; x.itens = (x.itens || []).filter(i => i !== k); if(v) x.itens.push(k); return salvar(v ? 'Anotado ✓' : 'Desmarcado.'); };
window.rvEtapa = async (id, feita, pulada) => {
  const et = ETAPAS.find(x => x.id === id);
  if(feita && id === 'entrega'){ const falta = FALTA_ENTREGA.filter(k => k !== 'entrega' && !((S.rest.etapas[k] || {}).feita && !(S.rest.etapas[k] || {}).pulada)).map(k => (ETAPAS.find(x => x.id === k) || {}).titulo || k); if(falta.length) return erro('Ainda não dá para entregar. Falta concluir: ' + falta.join(', ') + '.'); }
  if(feita && !pulada && et.checklist){ const ck = (S.rest.etapas[id] || {}).itens || []; if(ck.length < et.checklist.length) return erro('Marque todos os testes antes de concluir (' + ck.length + ' de ' + et.checklist.length + ').'); }
  const antes = JSON.parse(JSON.stringify(S.rest.etapas[id] || null));
  S.rest.etapas[id] = Object.assign(S.rest.etapas[id] || {}, { feita, pulada:!!pulada, em:new Date().toISOString() });
  if(await salvar(feita ? (pulada ? 'Etapa pulada.' : '🎉 Etapa concluída!') : 'Etapa reaberta.')){ await hist(S.rest.id, feita ? (pulada ? 'Etapa pulada' : 'Etapa concluída') : 'Etapa reaberta', et.titulo); if(feita){ S.passoVer = null; } abaPasso(); window.scrollTo(0, 0); }
  else { if(antes) S.rest.etapas[id] = antes; else delete S.rest.etapas[id]; abaPasso(); erro('NÃO foi salvo. Motivo: ' + (S.ultimoErro || 'sem resposta do banco') + '.'); }
};

/* o que aparece embaixo de cada parte */
function desenharExtra(et, tipo, box){
  if(!box) return; const r = S.rest;
  if(/^campos:/.test(tipo)){ const L = tipo.slice(7).split(','); box.innerHTML = L.map(k => campo(k)).join('') + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvSalvarTestar(\'' + et.id + '\')">💾 Salvar' + (et.teste ? ' e testar' : '') + '</button></div><div id="res_' + (et.teste || 'x') + '"></div>'; Object.keys(S.res || {}).forEach(t => mostrarRes('res_' + t, [t])); return; }
  if(/^cod:/.test(tipo)){ box.innerHTML = codUnico(tipo.slice(4), et.id); return; }
  const ex = {
    cadastro: () => '<div class="cols">' + ['nome','contato_nome','contato_telefone','cidade','plano','valor_mensal','taxa_implantacao','dia_vencimento'].map(k => '<div>' + campo(k) + '</div>').join('') + '</div>' + botSalvar(),
    contas: () => '<div class="contas">' + CONTAS.map(c => '<div><b>' + esc(c[0]) + '</b><small>' + esc(c[1]) + '</small>' + (c[2] ? '<a class="btn mini" href="' + c[2] + '" target="_blank" rel="noopener">Abrir ↗</a>' : '') + '</div>').join('') + '</div>',
    boasvindas: () => boasHtml(),
    listacontas: () => listaContasHtml(),
    campos: () => (et.campos || []).map(k => campo(k)).join('') + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvSalvarTestar(\'' + et.id + '\')">💾 Salvar' + (et.teste ? ' e testar' : '') + '</button></div><div id="res_' + (et.teste || 'x') + '"></div>',
    testetudo: () => '<button class="principal" onclick="rvTesteTudo()">🧪 Testar tudo com um clique</button><div id="res_tudo"></div>',
    teste: () => '<button class="principal" onclick="rvTeste(\'' + et.teste + '\')">▶️ Testar agora</button><div id="res_' + et.teste + '"></div>',
    codigos: () => codigosHtml(et.id),
    conectar: () => conectarEtapaHtml() + '<div class="res" style="margin-top:12px"><b>🌐 Ligar o site (GitHub Pages)</b><br><small>O painel liga o Pages e já preenche o endereço do site. Pode pular as partes 4 e 5 da etapa "Criar o endereço do site".</small><div class="linha" style="justify-content:flex-start;margin-top:8px"><button class="mini principal" onclick="rvLigarPages()">Ligar o site agora</button></div><div id="pages_' + S.rest.id + '"></div></div>' + '<div class="res ok" style="margin-top:12px"><b>⚡ Fazer tudo de uma vez</b><br><small>Com os dois tokens salvos e testados, o painel monta o banco, publica as funções, cria os logins e grava o site, numa tela só.</small><div class="cols" style="margin-top:8px"><label>Login do dono<input id="tdLogin" autocomplete="off" placeholder="ex.: maria" maxlength="30"></label><label>Senha do dono<input id="tdSenha" type="password" autocomplete="new-password" placeholder="mínimo 8, letras e números"></label><label>O seu login de suporte<input id="tdDLogin" autocomplete="off" value="Lucas" maxlength="30"></label><label>A sua senha de suporte<input id="tdDSenha" type="password" autocomplete="new-password" placeholder="mínimo 8, letras e números"></label></div><small class="mudo">As senhas só passam direto para o banco do restaurante: o painel não guarda nenhuma.</small><br><button class="principal" style="margin-top:8px" onclick="rvImplantarTudo()">⚡ Implantar tudo agora</button><div id="con_tudo_' + r.id + '"></div><div id="con_tudo_' + r.id + '_f"></div></div>',
    bancoauto: () => bancoAutoHtml(),
    googleauto: () => temSb(r) ? '<div class="res ok"><b>⚡ Jeito rápido:</b> cole os dois e toque no botão. O painel liga o "Entrar com o Google" no Supabase e já guarda as credenciais no cofre (a etapa do Drive usa as mesmas).'
      + '<label for="gaId">ID do cliente (termina em .apps.googleusercontent.com)</label><input id="gaId" autocomplete="off" value="' + esc((window.CD_VALS || {}).gid || '') + '"><label for="gaSec">Chave secreta do cliente (começa com GOCSPX-)</label><input id="gaSec" type="password" autocomplete="off">'
      + '<button class="principal" style="margin-top:8px" onclick="rvGoogleAuto()">⚡ Ligar o Google agora</button><div id="con_ga_' + r.id + '"></div></div>' : '',
    loginurls: () => temSb(r) ? '<div class="res ok"><b>⚡ Jeito rápido:</b> o painel grava os dois endereços no Supabase sozinho.<br><button class="principal" style="margin-top:8px" onclick="rvLoginUrls()">⚡ Configurar os endereços agora</button><div id="con_lu_' + r.id + '"></div></div>' : '',
    publicarauto: () => publicarAutoHtml(),
    push: () => pushHtml(),
    marca: () => marcaHtml(),
    logos: () => logosHtml(),
    modulos: () => modulosHtml(),
    publicar: () => publicarHtml(),
    checklist: () => et.checklist.map((c, j) => { const ck = ((r.etapas[et.id] || {}).itens || []).includes(j); return '<label class="check"><input type="checkbox" ' + (ck ? 'checked ' : '') + 'onchange="rvItem(\'' + et.id + '\',' + j + ',this.checked)"><span>' + esc(c) + '</span></label>'; }).join(''),
    contrato: () => '<button class="mini" onclick="rvAba(\'contrato\')">📄 Abrir a aba Contrato</button>',
    workflow: () => workflowHtml(),
    leitura: () => leituraHtml(),
    privacidade: () => '<button class="principal" onclick="rvPrivacidade()">⬇️ Gerar e baixar privacidade.html</button><p class="pequeno mudo">Onde colocar: <b>na raiz do repositório</b> (junto do index.html). Endereço depois de subir: <code class="quebra">' + esc((r.site_url || '(site)') + 'privacidade.html') + '</code></p><div id="privRes"></div>',
    conferir: () => '<button class="principal" onclick="rvConferir()">🔎 Conferir o site</button><div id="confRes"></div>',
    cobranca: () => '<div class="linha" style="justify-content:flex-start">' + (r.taxa_implantacao ? '<button class="mini" onclick="rvCobRest(\'implantacao\')">Gerar taxa de implantação (' + BRL(r.taxa_implantacao) + ')</button>' : '') + '<button class="mini" onclick="rvCobRest(\'mensalidade\')">Gerar mensalidade deste mês</button>' + (r.situacao !== 'ativo' ? '<button class="principal mini" onclick="rvAtivar()">Mudar para Ativo</button>' : '<span class="selo ativo">✓ Ativo</span>') + '</div>'
  };
  box.innerHTML = (ex[tipo] || (() => ''))();
  if(tipo === 'marca') rvPrevia();
  Object.keys(S.res || {}).forEach(t => mostrarRes('res_' + t, [t]));
}
window.rvSalvarTestar = async id => { const et = ETAPAS.find(x => x.id === id); if(await salvar()){ await hist(S.rest.id, 'Dados salvos', et.titulo); if(et.teste) await rvTeste(et.teste); } };
window.rvAtivar = async () => { S.rest.situacao = 'ativo'; if(await salvar('Restaurante ativo! 🎉')){ await hist(S.rest.id, 'Situação: Ativo', ''); abaPasso(); } };

/* códigos: um de cada vez */
function codigosHtml(etapa){
  const L = (window.CODIGOS || {})[etapa] || [], r = S.rest; if(!L.length) return '';
  const feitos = (r.etapas[etapa] || {}).itens || [];
  ctxCod(r, feitos);
  let k = S.cdIdx[etapa]; if(k == null){ k = L.findIndex(c => !feitos.includes('cd:' + c.id)); if(k < 0) k = L.length - 1; }
  const c = L[k], f = feitos.includes('cd:' + c.id), nf = L.filter(x => feitos.includes('cd:' + x.id)).length;
  if(c.subRef && !refDe(r)) return '<div class="res erro">Antes, preencha o endereço do Supabase na etapa "Criar o banco de dados".</div>';
  return '<div class="cod"><div class="linha"><b>Código ' + (k + 1) + ' de ' + L.length + '</b><small class="mudo">' + nf + ' aplicado(s)</small></div>'
   + '<div class="barra"><i style="width:' + Math.round(nf / L.length * 100) + '%;background:var(--ok)"></i></div>'
   + '<h3>' + esc(c.titulo) + (f ? ' <span class="selo ativo">✓ aplicado</span>' : '') + '</h3><p class="pequeno">' + esc(c.desc) + '</p>' + (c.cuidado ? '<p class="pequeno mudo">⚠️ ' + esc(c.cuidado) + '</p>' : '')
   + camposCod(c) + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvCdCopiar(\'' + c.id + '\')">📋 Copiar código</button><button class="mini" onclick="cdVer(\'' + c.id + '\')">Ver</button><button class="mini" onclick="cdBaixar(\'' + c.id + '\')">Baixar</button></div><div id="cd-ver-' + c.id + '"></div>'
   + '<div class="linha cod-nav">' + (k > 0 ? '<button class="mini" onclick="rvCod(\'' + etapa + '\',' + (k - 1) + ')">← Anterior</button>' : '<span></span>')
   + (f ? (k < L.length - 1 ? '<button class="mini" onclick="rvCod(\'' + etapa + '\',' + (k + 1) + ')">Próximo →</button>' : '<span class="selo ativo">Todos aplicados 🎉</span>') : '<button class="principal" onclick="rvCodFeito(\'' + etapa + '\',' + k + ')">✅ Já colei e rodei' + (k < L.length - 1 ? ', próximo →' : '') + '</button>') + '</div></div>';
}
window.rvCod = (etapa, k) => { S.cdIdx[etapa] = k; abaPasso(); };
function ctxCod(r, feitos){ if(window.cdCtx) cdCtx({ ref:/^[a-z0-9]{20}$/.test(refDe(r)) ? refDe(r) : '', cod:r.slug, chave:r.supabase_chave || '', exec:r.api_url || '', feitos:feitos || [] }); }
/* campos que preenchem o código na hora (NÃO são guardados: ficam só nesta tela) */
const CAMPOS_COD = { segredos1:[['service','Chave secreta do Supabase (começa com sb_secret_)','password']], google:[['gid','ID do cliente (termina em .apps.googleusercontent.com)','text'],['gsec','Chave secreta do cliente (começa com GOCSPX-)','password']],
  adm2:[['alogin','Login do dono (ex.: o primeiro nome, sem espaço)','text'],['asenha','Senha do dono (mínimo 8)','password']], dev2:[['dsenha','Sua senha de Desenvolvedor (mínimo 8)','password']] };
function camposCod(c){ const L = CAMPOS_COD[c.id]; if(!L) return c.id === 'segredos2' && !S.rest.api_url ? '<div class="res aviso">Antes, cole o endereço /exec da planilha principal (parte anterior): ele entra sozinho neste código.</div>' : '';
  const V = window.CD_VALS = window.CD_VALS || {};
  return '<div class="cod-campos"><small class="mudo">Preencha e o código já sai pronto. Nada disso fica guardado no painel.</small>' + L.map(x => '<label for="cv_' + x[0] + '">' + esc(x[1]) + '</label><input id="cv_' + x[0] + '" type="' + x[2] + '" autocomplete="off" value="' + esc(V[x[0]] || '') + '" oninput="rvCdVal(\'' + x[0] + '\',this.value)">').join('') + '</div>'; }
window.rvCdVal = (k, v) => { (window.CD_VALS = window.CD_VALS || {})[k] = String(v || '').trim(); };
window.rvCdCopiar = id => { const L = CAMPOS_COD[id] || [], V = window.CD_VALS || {};
  const falta = L.filter(x => !V[x[0]]); if(falta.length) return erro('Preencha antes: ' + falta.map(x => x[1].split(' (')[0]).join(' e ') + '.');
  if(L.some(x => /senha/.test(x[0]) && V[x[0]].length < 8)) return erro('A senha precisa de pelo menos 8 caracteres.');
  if(id === 'segredos1' && !/^sb_secret_|^eyJ/.test(V.service)) return erro('Essa não parece a chave secreta: ela começa com sb_secret_.');
  if(id === 'google' && !/\.apps\.googleusercontent\.com$/.test(V.gid)) return erro('O ID do cliente termina com .apps.googleusercontent.com. Confira se copiou inteiro.');
  ctxCod(S.rest, (S.rest.etapas[(achaCod(id) || {}).etapa] || {}).itens); cdCopiar(id); };
function achaCod(id){ for(const k in (window.CODIGOS || {})) for(const c of CODIGOS[k]) if(c.id === id) return c; return null; }
function codUnico(id, etapa){ const c = achaCod(id); if(!c) return '<div class="res erro">Código não encontrado (' + esc(id) + ').</div>';
  const feitos = (S.rest.etapas[etapa] || {}).itens || [], f = feitos.includes('cd:' + c.id); ctxCod(S.rest, feitos);
  return '<div class="cod"><h3>' + esc(c.titulo) + (f ? ' <span class="selo ativo">✓ aplicado</span>' : '') + '</h3><p class="pequeno">' + esc(c.desc || '') + '</p>' + (c.cuidado ? '<p class="pequeno mudo">⚠️ ' + esc(c.cuidado) + '</p>' : '') + camposCod(c)
   + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvCdCopiar(\'' + c.id + '\')">📋 Copiar código</button><button class="mini" onclick="cdVer(\'' + c.id + '\')">Ver</button><button class="mini" onclick="cdBaixar(\'' + c.id + '\')">Baixar</button></div><div id="cd-ver-' + c.id + '"></div>'
   + '<label class="check"><input type="checkbox"' + (f ? ' checked' : '') + ' onchange="rvItem(\'' + etapa + '\',\'cd:' + c.id + '\',this.checked)"><span>Já colei e usei este código</span></label></div>'; }
window.rvCodFeito = async (etapa, k) => { const L = CODIGOS[etapa]; if(await rvItem(etapa, 'cd:' + L[k].id, true)){ S.cdIdx[etapa] = Math.min(k + 1, L.length - 1); abaPasso(); } };

/* avisos no celular: o painel gera as chaves */
const b64url = u8 => btoa(String.fromCharCode.apply(null, Array.from(u8))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
function pushHtml(){
  const r = S.rest;
  return (r.push_chave_publica ? '<div class="res ok">✓ Este restaurante já tem chave pública: <code class="quebra">' + esc(r.push_chave_publica.slice(0, 24)) + '…</code></div>' : '')
   + (temSb(r) ? '<div class="res ok"><b>⚡ Jeito rápido:</b> o servidor cria as chaves e já guarda no cofre do banco (a privada nunca passa por aqui). Não precisa rodar código.<br><button class="principal" style="margin-top:8px" onclick="rvPushAuto()">🔑 ' + (r.push_chave_publica ? 'Gerar chaves novas e guardar' : 'Gerar e guardar agora') + '</button><div id="con_pa_' + r.id + '"></div></div><details class="como"><summary>Jeito manual</summary>' : '')
   + '<button class="principal" onclick="rvGerarPush()">🔑 ' + (r.push_chave_publica ? 'Gerar chaves novas' : 'Gerar chaves agora') + '</button>'
   + (S.pushSQL && S.pushSQL.id === r.id ? '<p class="pequeno">Copie e rode no SQL Editor do Supabase do restaurante (só aparece agora; se perder, gere de novo):</p><div class="copiar" id="pushSql">' + esc(S.pushSQL.sql) + '</div><button class="principal" onclick="rvCopiar(\'pushSql\')">📋 Copiar código</button>' : '') + (temSb(r) ? '</details>' : '');
}
window.rvPushAuto = async () => {
  const r = S.rest; if(r.push_chave_publica && !confirm('Gerar chaves NOVAS? Os celulares já cadastrados vão precisar ativar os avisos de novo.')) return;
  conMsg('pa_' + r.id, '<small class="mudo">Gerando…</small>');
  try{ const a = await gerarChavesAviso_(r); if(!a.ok){ conMsg('pa_' + r.id, conLinha(false, esc(a.erro))); return; } abaPasso(); }catch(e){ conMsg('pa_' + r.id, conLinha(false, esc(e.message))); }
};
window.rvGerarPush = async () => {
  const r = S.rest; if(r.push_chave_publica && !confirm('Gerar chaves NOVAS? Os celulares já cadastrados vão precisar ativar os avisos de novo.')) return;
  try{
    const kp = await crypto.subtle.generateKey({ name:'ECDSA', namedCurve:'P-256' }, true, ['sign', 'verify']);
    const pub = b64url(new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey))), priv = (await crypto.subtle.exportKey('jwk', kp.privateKey)).d;
    const q = (n, v) => "  select id into v_id from vault.secrets where name = '" + n + "';\n  if v_id is null then perform vault.create_secret('" + v + "', '" + n + "'); else perform vault.update_secret(v_id, '" + v + "'); end if;\n";
    S.pushSQL = { id:r.id, sql:'-- Chaves dos avisos no celular de ' + r.nome + ' (gerado pelo Painel de Revenda)\ndo $$ declare v_id uuid; begin\n' + q('vapid_publica', pub) + q('vapid_privada', priv) + 'end $$;' };
    r.push_chave_publica = pub;
    if(await salvar('Chaves geradas. Agora copie e rode o código.')){ await hist(r.id, 'Chaves de aviso geradas', ''); abaPasso(); }
  }catch(e){ erro('Este navegador não conseguiu gerar as chaves (' + e.message + '). Use o Chrome atualizado ou peça ao Claude.'); }
};

/* site: os 4 arquivos prontos */
function publicarHtml(){
  const r = S.rest, falta = [];
  if(!r.supabase_url || !r.supabase_chave) falta.push('endereço e chave do Supabase'); if(!r.site_url) falta.push('endereço do site');
  if(falta.length) return '<div class="res erro">Falta preencher: ' + falta.join(' e ') + '. Volte às etapas do banco e do site.</div>';
  return '<div class="arquivos">' + ARQS_SITE.filter(a => a[3]).map(a => '<button class="arquivo" onclick="rvBaixarArq(\'' + a[0] + '\')"><span>⬇️</span><span><b>' + a[0] + '</b><small>' + a[1] + '</small><small class="onde">📁 Onde colocar: ' + (a[2] === 'raiz' ? 'na raiz do repositório (sem pasta)' : 'na ' + a[2]) + '</small></span></button>').join('') + '</div>'
   + '<details class="como"><summary>🗺️ Mapa completo do GitHub deste restaurante</summary><p class="pequeno mudo">Tudo o que fica no repositório {slug}, e em que lugar:</p>'.replace('{slug}', esc(r.slug))
   + ARQS_SITE.map(a => '<div class="mapa"><code>' + esc(a[2] === 'raiz' ? a[0] : a[2].replace(/^pasta /, '') + '/' + a[0]) + '</code><small>' + esc(a[1]) + (a[4] ? ' · ' + esc(a[4]) : '') + '</small></div>').join('') + '</details>';
}
/* arquivo, para que serve, onde colocar, baixa aqui?, de onde vem */
const ARQS_SITE = [
  ['index.html','A porta do site (abre o sistema)','raiz',true,'etapa Colocar o site no ar'],
  ['config-restaurante.js','Os dados deste restaurante','raiz',true,'etapa Colocar o site no ar'],
  ['sw.js','Deixa abrir sem internet e instalar','raiz',true,'etapa Colocar o site no ar'],
  ['manifest.webmanifest','Nome e ícone do app instalado','raiz',true,'etapa Colocar o site no ar'],
  ['privacidade.html','Aviso de privacidade (o Google exige)','raiz',false,'etapa Entrar com o Google'],
  ['google….html','Verificação do Google (opcional)','raiz',false,'baixado no Search Console'],
  ['README.md','Criado pelo GitHub','raiz',false,'pode deixar'],
  ['publicar-funcoes.yml','Publica as funções do servidor','pasta .github/workflows',false,'etapa Publicar as funções']
];
function workflowTexto(r){
  return 'name: Publicar funções do servidor\n# Publica as 33 funções do sistema no Supabase de ' + r.nome + '. Rode em Actions → Run workflow.\non: workflow_dispatch\njobs:\n  publicar:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          repository: lucassricardo95/sistema-restaurantes\n          path: sr\n      - uses: supabase/setup-cli@v1\n        with:\n          version: latest\n      - name: Publicar as funções\n        env:\n          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}\n        run: |\n          cd sr/modelo/banco\n          chmod +x implantar-funcoes.sh\n          ./implantar-funcoes.sh ' + refDe(r) + ' ' + r.site_url + '\n';
}
function workflowHtml(){
  const r = S.rest; if(!refDe(r) || !r.site_url) return '<div class="res erro">Antes, preencha o endereço do Supabase e o endereço do site (etapas anteriores).</div>';
  const direto = temSb(r) ? '<div class="res ok"><b>⚡ Jeito rápido:</b> o Supabase deste restaurante está ligado, então o painel publica as funções sozinho.<br><button class="principal" style="margin-top:8px" onclick="rvConPublicarFuncoes(\'' + r.id + '\',\'wf_' + r.id + '\')">⬆️ Publicar as funções agora</button><div id="con_wf_' + r.id + '"></div></div><details class="como"><summary>Jeito manual (GitHub Actions)</summary>' : '';
  return direto + '<p class="pequeno"><b>1) Nome do arquivo</b> (cole no campo do nome):</p><div class="copiar" id="wfNome">.github/workflows/publicar-funcoes.yml</div><button class="mini" onclick="rvCopiar(\'wfNome\')">📋 Copiar nome</button>'
   + '<p class="pequeno"><b>2) Conteúdo</b> (cole no campo grande):</p><div class="copiar" id="wfTxt">' + esc(workflowTexto(r)) + '</div><button class="principal" onclick="rvCopiar(\'wfTxt\')">📋 Copiar conteúdo</button> <button class="mini" onclick="rvBaixarWf()">⬇️ Baixar</button>' + (direto ? '</details>' : '');
}
window.rvBaixarWf = () => baixar('publicar-funcoes.yml', workflowTexto(S.rest), 'text/yaml');
window.rvPrivacidade = async () => {
  const r = S.rest, box = $('privRes'); if(!r.supabase_url || !r.supabase_chave || !r.site_url) return erro('Preencha antes o Supabase e o endereço do site.');
  try{
    if(!window.gerarPrivacidade) await new Promise((ok, no) => { const s = document.createElement('script'); s.src = 'leve/aviso-privacidade.js?v=1'; s.onload = ok; s.onerror = () => no(new Error('não carregou o modelo do aviso')); document.head.appendChild(s); });
    const x = await tempo(r.supabase_url + '/rest/v1/rpc/api_aviso_privacidade', { method:'POST', headers:{ apikey:r.supabase_chave, 'Content-Type':'application/json' }, body:'{}' });
    if(!x.ok) throw new Error(x.status === 404 ? 'o banco ainda não tem as tabelas (faça a etapa do banco)' : 'o banco respondeu ' + x.status);
    const d = await x.json(); if(!d.nome) d.nome = r.nome;
    baixar('privacidade.html', gerarPrivacidade(d, r.site_url), 'text/html'); await hist(r.id, 'privacidade.html gerado', '');
    if(box) box.innerHTML = '<div class="res ok">✅ Baixado. Agora suba na raiz do GitHub do restaurante.' + (!d.cnpj && !d.endereco ? ' Dica: quando o dono preencher CNPJ e endereço no sistema (Administrador → Sistema → Aparência/Dados), gere de novo para a página ficar completa.' : '') + '</div>';
  }catch(e){ if(box) box.innerHTML = '<div class="res erro">❌ Não deu: ' + esc(e.message) + '.</div>'; }
};
window.rvConferir = async () => {
  const r = S.rest, box = $('confRes'); if(!r.site_url) return erro('Preencha o endereço do site.');
  box.innerHTML = '<div class="res aviso">⏳ Conferindo…</div>';
  const L = [['index.html','index.html', t => t.includes('config_restaurante') ? '' : 'não é o arquivo do painel'], ['config-restaurante.js','config-restaurante.js', t => t.includes("'" + r.slug + "'") || t.includes('"' + r.slug + '"') ? '' : 'é de outro restaurante'], ['sw.js','sw.js', t => t.includes('sw-motor') ? '' : 'não é o arquivo do painel'], ['manifest.webmanifest','manifest.webmanifest', t => t.includes(r.nome) ? '' : 'está com outro nome'], ['privacidade.html','privacidade.html', t => /Privacidade/.test(t) ? '' : 'conteúdo estranho']];
  const out = await Promise.all(L.map(async a => { try{ const x = await tempo(r.site_url + a[1] + '?t=' + Date.now(), { cache:'no-store' }); if(!x.ok){ if(a[0] === 'privacidade.html' && x.status === 404) return [a[0], 'aviso', 'ainda não está lá: isso é normal, ele só entra na etapa "Entrar com o Google"']; return [a[0], 'erro', x.status === 404 ? 'não encontrado (falta subir na raiz)' : 'erro ' + x.status]; } const p = a[2](await x.text()); return [a[0], p ? 'aviso' : 'ok', p || 'ok']; }catch(e){ return [a[0], 'erro', 'não abriu']; } }));
  box.innerHTML = out.map(o => '<div class="res ' + o[1] + '">' + ({ ok:'✅', aviso:'⚠️', erro:'❌' }[o[1]]) + ' <b>' + o[0] + '</b>: ' + esc(o[2]) + '</div>').join('') + (out.filter(o => o[0] !== 'privacidade.html').every(o => o[1] === 'ok') ? '<div class="res ok">🎉 Site completo! Os 4 arquivos do sistema estão no ar.</div>' : '');
};
function manifestTexto(r){
  const m = r.marca || {}, c = m.cores || {}, ic = (m.logos || {}).icone, mo = r.motor || MOTOR_PADRAO, fundo = c.fundo || '#14100c';
  const icons = ic ? [{ src:ic, sizes:'512x512', type:'image/png', purpose:'any' }, { src:ic, sizes:'512x512', type:'image/png', purpose:'maskable' }] : [{ src:mo + 'img/icon-192.png', sizes:'192x192', type:'image/png', purpose:'any' }, { src:mo + 'img/icon-512.png', sizes:'512x512', type:'image/png', purpose:'any' }, { src:mo + 'img/icon-maskable-512.png', sizes:'512x512', type:'image/png', purpose:'maskable' }];
  return JSON.stringify({ id:'./', name:r.nome, short_name:r.nome.length > 12 ? r.nome.split(' ')[0].slice(0, 12) : r.nome, description:'Cardápio digital e pedidos', lang:'pt-BR', start_url:'./', scope:'./', display:'standalone', orientation:'any', background_color:fundo, theme_color:fundo, icons }, null, 2);
}
function configTexto(r){
  const m = r.marca || {}, mod = r.modulos || {}, c = m.cores || {}, lg = m.logos || {}, mo = r.motor || MOTOR_PADRAO;
  const o = { motor:mo, slug:r.slug, nome:r.nome, siteUrl:r.site_url || '', supabaseUrl:r.supabase_url || '', supabaseChave:r.supabase_chave || '', apiUrl:r.api_url || '', contingenciaUrl:r.contingencia_url || '', contingenciaChave:r.contingencia_chave || '', pushChave:r.push_chave_publica || '',
    marca:{ slogan:m.slogan || '', assistente:m.assistente || 'Assistente', tema:m.tema || '', jogos:{ tema:(m.jogos && m.jogos.tema) || 'generico' }, cores:{ destaque:c.destaque || '#d9a21b', botao:c.botao || '#8c1c13', fundo:c.fundo || '#14100c' }, logos:{ cardapio:lg.cardapio || mo + 'img/logo.png', impressao:lg.impressao || '', icone:lg.icone || mo + 'img/icon-512.png' } }, modulos:mod };
  return '/* CONFIGURAÇÃO DE ' + r.nome.replace(/\*\//g, '') + ' — gerado pelo Painel de Revenda em ' + new Date().toLocaleString('pt-BR') + '.\n   Só endereços e chaves PÚBLICAS. Marca e módulos também vêm do painel na hora; para mudar o resto, gere de novo. */\nwindow.RESTAURANTE = ' + JSON.stringify(o, null, 2) + ';\n';
}
function baixar(nome, txt, tipo){ const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([txt], { type:tipo || 'text/plain' })); a.download = nome; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 2000); }
window.rvBaixarArq = async nome => {
  const r = S.rest;
  try{
    if(nome === 'config-restaurante.js') baixar(nome, configTexto(r), 'text/javascript');
    else if(nome === 'manifest.webmanifest') baixar(nome, manifestTexto(r), 'application/manifest+json');
    else { const x = await fetch('leve/' + nome + '?t=' + Date.now(), { cache:'no-store' }); if(!x.ok) throw new Error('erro ' + x.status); baixar(nome, await x.text(), nome.endsWith('.html') ? 'text/html' : 'text/javascript'); }
    aviso('Baixado: ' + nome, 'ok'); hist(r.id, 'Arquivo do site baixado', nome);
  }catch(e){ erro('Não consegui preparar ' + nome + ' (' + e.message + ').'); }
};

/* testes automáticos */
async function tempo(url, o){ const c = new AbortController(); const t = setTimeout(() => c.abort(), 12000); try{ return await fetch(url, Object.assign({ signal:c.signal }, o)); } finally { clearTimeout(t); } }
const TESTES = {
  async supabase(r){ if(!r.supabase_url || !r.supabase_chave) return ['erro', 'Falta o endereço do banco e/ou a chave pública.'];
    const x = await tempo(r.supabase_url + '/auth/v1/health', { headers:{ apikey:r.supabase_chave } }); return x.ok ? ['ok', 'O banco responde e a chave foi aceita.'] : ['erro', 'O banco respondeu com erro ' + x.status + '. Confira a chave pública.']; },
  async banco(r){ if(!r.supabase_url) return ['erro', 'Preencha primeiro o endereço do banco.'];
    const x = await tempo(r.supabase_url + '/rest/v1/rpc/api_cardapio_promos', { method:'POST', headers:{ apikey:r.supabase_chave, 'Content-Type':'application/json' }, body:'{"p":{}}' });
    if(x.status === 404) return ['erro', 'O banco existe, mas as tabelas ainda não foram criadas. Continue colando os códigos.'];
    const j = await x.json().catch(() => null); return j && j.ok === true ? ['ok', 'Banco do sistema instalado e respondendo.'] : ['aviso', 'O banco respondeu, mas fora do esperado: ' + esc(JSON.stringify(j).slice(0, 120))]; },
  async funcoes(r){ if(!r.supabase_url) return ['erro', 'Preencha primeiro o endereço do banco.'];
    const x = await tempo(r.supabase_url + '/functions/v1/ping', { method:'POST', headers:{ apikey:r.supabase_chave, Authorization:'Bearer ' + r.supabase_chave, 'Content-Type':'application/json' }, body:'{}' });
    return x.status === 404 ? ['erro', 'As funções do servidor ainda não foram publicadas.'] : (x.ok ? ['ok', 'Funções do servidor respondendo.'] : ['aviso', 'A função "ping" respondeu com erro ' + x.status + '.']); },
  async pages(r){ const u = r.site_url || ''; if(!u) return r.github_url ? ['aviso', 'Endereço do GitHub salvo ✓. Cole abaixo o endereço do site que o Pages mostrou.'] : ['erro', 'Preencha o endereço do site.'];
    if(!/^https:\/\/[^\/]+\.github\.io\/[^\/]+\/?$/i.test(u.trim())) return ['aviso', 'Confira o endereço: deve ser parecido com https://usuario.github.io/nome/ (com a barra no fim).'];
    try{ const x = await tempo(u.replace(/\/?$/, '/') + '?t=' + Date.now(), { cache:'no-store' }); if(x.ok) return ['ok', 'Site no ar ✓. Os arquivos do restaurante entram na etapa "Colocar o site no ar".']; return ['aviso', 'O GitHub Pages ainda está publicando. Espere 1 a 2 minutos e toque em Salvar e testar de novo.']; }
    catch(e){ return ['aviso', 'Não consegui abrir agora. Espere 1 a 2 minutos e tente de novo.']; } },
  async site(r){ const u = r.site_url || (r.dominio ? 'https://' + r.dominio + '/' : ''); if(!u) return r.github_url ? ['aviso', 'Endereço do GitHub salvo ✓. O endereço do site você preenche mais adiante (parte 5), depois de ligar o Pages.'] : ['erro', 'Preencha o endereço do site.'];
    try{ const x = await tempo(u + 'config-restaurante.js?t=' + Date.now(), { cache:'no-store' }); if(x.status === 404) return ['erro', 'O endereço existe, mas os 4 arquivos ainda não estão lá (ou o GitHub Pages ainda está publicando: espere 2 minutos).']; if(x.ok){ const t = await x.text(); return t.includes(r.slug) ? ['ok', 'Site no ar com os arquivos deste restaurante.'] : ['aviso', 'O site está no ar, mas o config-restaurante.js é de outro restaurante. Baixe de novo e suba.']; } }catch(e){}
    await tempo(u, { mode:'no-cors' }); return ['ok', 'O endereço ' + esc(u) + ' está no ar.']; }
};
const NOME_T = { supabase:'Banco', banco:'Tabelas', funcoes:'Funções', site:'Site', pages:'Site' };
/* TESTE COMPLETO EM UM CLIQUE: confere banco, funções, site, motor, GitHub e atualizações e dá o veredito. Só lê; não muda nada. */
window.rvTesteTudo = async () => {
  const r = S.rest, box = 'res_tudo'; if(!r) return; lerForm();
  const pinta = h => { const b = $(box); if(b) b.innerHTML = h; };
  pinta('<div class="res"><small class="mudo">⏳ Testando… (uns 20 segundos)</small></div>');
  const L = []; const add = (ok, t) => L.push([ok, t]);
  for(const k of ['supabase', 'banco', 'funcoes', 'site']){
    try{ const x = await TESTES[k](r); add(x[0] === 'ok', '<b>' + NOME_T[k] + ':</b> ' + x[1]); }catch(e){ add(false, '<b>' + NOME_T[k] + ':</b> não consegui chegar (' + esc(e.message) + ').'); }
  }
  if(temSb(r)){
    try{ const f = await updsFeitas_(r), falta = UPDS.filter(u => !f.has(u[0])); add(!falta.length, '<b>Atualizações do banco:</b> ' + (falta.length ? 'faltam ' + falta.length + '. Abra Conectores e toque em Atualizar banco.' : 'todas aplicadas.')); }catch(e){ add(false, '<b>Atualizações do banco:</b> ' + esc(e.message)); }
    try{ const a = await chamarConector({ acao:'sb_conferir', restaurante_id:r.id }); if(a.ok && !a.referencia){ const n = a.faltamTabelas.length + a.faltamColunas.length + a.faltamFuncoes.length + (a.edgeFaltam || []).length; add(!n, '<b>Igual ao modelo:</b> ' + (n ? 'faltam ' + n + ' item(ns) no banco/funções. Rode a conferência em Conectores.' : 'tabelas, colunas e funções iguais.')); } }catch(e){ /* a linha de cima já mostra o problema */ }
  } else add(false, '<b>Conector do Supabase:</b> ainda não ligado. Ligue na etapa "Ligar o GitHub e o Supabase".');
  if(temGh(r)){
    try{ const g = await chamarConector({ acao:'gh_conferir', restaurante_id:r.id }); const faltam = g.ok ? g.arquivos.filter(x => !x.existe).length : 1; add(g.ok && !faltam && g.motorOk, '<b>Site no GitHub:</b> ' + (!g.ok ? esc(g.erro || 'não consegui conferir') : faltam ? 'faltam arquivos.' : !g.motorOk ? 'o motor não respondeu.' : 'arquivos e motor em ordem.')); }catch(e){ add(false, '<b>Site no GitHub:</b> ' + esc(e.message)); }
  } else add(false, '<b>Conector do GitHub:</b> ainda não ligado.');
  const ruins = L.filter(x => !x[0]).length;
  pinta(L.map(x => '<div class="res ' + (x[0] ? 'ok' : 'erro') + '">' + (x[0] ? '✅ ' : '❌ ') + x[1] + '</div>').join('')
    + '<div class="res ' + (ruins ? 'erro' : 'ok') + '"><b>' + (ruins ? '❌ ' + ruins + ' ponto(s) para resolver antes de entregar.' : '✅ Tudo em ordem pelo lado técnico. Agora faça o teste no celular (a lista abaixo).') + '</b></div>');
  hist(r.id, 'Teste completo automático', ruins ? ruins + ' ponto(s) a resolver' : 'tudo em ordem');
};
window.rvTeste = async id => {
  lerForm(); S.res[id] = ['aviso', 'Testando…']; mostrarRes('res_' + id, [id]);
  try{ S.res[id] = await TESTES[id](S.rest); }catch(e){ S.res[id] = ['erro', e.name === 'AbortError' ? 'Demorou demais para responder.' : 'Não foi possível chegar lá (' + esc(e.message) + ').']; }
  mostrarRes('res_' + id, [id]); mostrarRes('resTeste', Object.keys(S.res));
};
function mostrarRes(box, ids){ const b = $(box); if(!b) return; b.innerHTML = ids.filter(i => S.res && S.res[i]).map(i => '<div class="res ' + S.res[i][0] + '">' + ({ ok:'✅ ', erro:'❌ ', aviso:'⏳ ' }[S.res[i][0]]) + '<b>' + (NOME_T[i] || i) + ':</b> ' + S.res[i][1] + '</div>').join(''); }

/* ---------- MARCA E LOGOS ---------- */
const lum = h => { h = String(h || '#000').replace('#', ''); return parseInt(h.slice(0, 2), 16) * .299 + parseInt(h.slice(2, 4), 16) * .587 + parseInt(h.slice(4, 6), 16) * .114; };
function marcaHtml(){
  const m = S.rest.marca, c = m.cores = m.cores || {};
  return '<h3>Tema pronto</h3><div class="temas">' + TEMAS.map(t => '<button class="tema ' + (m.tema === t.id ? 'on' : '') + '" onclick="rvTema(\'' + t.id + '\')" style="background:' + t.fundo + ';color:' + (lum(t.fundo) > 150 ? '#1b1b1b' : '#f5efe6') + '"><i style="background:' + t.destaque + '"></i><i style="background:' + t.botao + '"></i><br>' + t.nome + '</button>').join('') + '</div>'
   + '<h3>Ou escolha as cores</h3><div class="cores">' + [['destaque','Destaque'],['botao','Botões'],['fundo','Fundo']].map(k => '<div class="cor-item"><input type="hidden" data-k="marca.cores.' + k[0] + '" id="mc_' + k[0] + '" value="' + esc(c[k[0]] || '#000000') + '"><button type="button" class="cor-bt" id="mcb_' + k[0] + '" style="background:' + esc(c[k[0]] || '#000000') + '" onclick="rvPaleta(\'' + k[0] + '\',\'' + k[1] + '\')" aria-label="Escolher a cor"></button><span>' + k[1] + '</span></div>').join('') + '</div>'
   + '<div class="previa" id="previa"></div>'
   + '<div class="cols"><div>' + campo('marca.slogan', { rot:'Slogan (frase curta)', ph:'Ex.: Feito com carinho' }) + '</div><div>' + campo('marca.assistente', { rot:'Nome do atendente virtual', ph:'Ex.: Atendente da Pizzaria' }) + '</div></div>'
   + '<label for="f_jogos">Jogos do cliente (enquanto espera o pedido)</label><select id="f_jogos" data-k="marca.jogos.tema">' + [['generico','Comida em geral'],['burger','Hambúrguer'],['churros','Churros e doces']].map(o => '<option value="' + o[0] + '"' + (((m.jogos || {}).tema || 'generico') === o[0] ? ' selected' : '') + '>' + o[1] + '</option>').join('') + '</select>'
   + botSalvar('💾 Salvar cores');
}
/* paleta: escolher a cor tocando, sem código de cor */
function hslHex(h, sa, l){ sa /= 100; l /= 100; const f = n => { const k = (n + h / 30) % 12, a = sa * Math.min(l, 1 - l), c = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)); return Math.round(255 * c).toString(16).padStart(2, '0'); }; return '#' + f(0) + f(8) + f(4); }
const PALETA = [['Vermelho',0,78],['Laranja',24,85],['Amarelo',44,90],['Verde-limão',80,65],['Verde',140,60],['Turquesa',175,65],['Azul',210,75],['Anil',235,60],['Roxo',270,60],['Rosa',330,70],['Marrom',22,40]]
  .map(t => ({ nome:t[0], cores:[86, 72, 58, 46, 34, 22, 12].map(l => hslHex(t[1], t[2], l)) })).concat([{ nome:'Cinzas', cores:[100, 90, 74, 55, 36, 18, 7].map(l => hslHex(0, 0, l)) }]);
window.rvPaleta = (k, rot) => { const at = ((($('mc_' + k) || {}).value) || '').toLowerCase();
  fecharJanela(); const d = document.createElement('div'); d.className = 'modal';
  d.innerHTML = '<div class="modal-c"><div class="linha"><h2>Cor: ' + esc(rot) + '</h2><button class="mini" onclick="rvFecharJ()">✕</button></div><p class="mudo pequeno">Toque numa cor. Em cada linha, do mais claro ao mais escuro.</p>'
    + PALETA.map(g => '<div class="pal-linha">' + g.cores.map(c => '<button class="pal-cor' + (c === at ? ' on' : '') + '" style="background:' + c + '" aria-label="' + g.nome + '" onclick="rvEscolherCor(\'' + k + '\',\'' + c + '\')"></button>').join('') + '</div>').join('') + '</div>';
  d.addEventListener('click', e => { if(e.target === d) fecharJanela(); }); document.body.appendChild(d); };
window.rvEscolherCor = (k, c) => { const i = $('mc_' + k), b = $('mcb_' + k); if(i) i.value = c; if(b) b.style.background = c; const m = S.rest.marca; m.cores = m.cores || {}; m.cores[k] = c; m.tema = ''; document.querySelectorAll('.tema.on').forEach(x => x.classList.remove('on')); fecharJanela(); rvPrevia(); };
window.rvTema = id => { const t = TEMAS.find(x => x.id === id); lerForm(); const m = S.rest.marca; m.tema = id; m.cores = { destaque:t.destaque, botao:t.botao, fundo:t.fundo }; refazerMarca(); };
function refazerMarca(){ if(S.aba === 'marca') abaMarcaTudo(); else abaPasso(); }
window.rvPrevia = () => { const g = k => (document.querySelector('[data-k="marca.cores.' + k + '"]') || {}).value || '#000'; const p = $('previa'); if(!p) return; const lg = (S.rest.marca.logos || {}).cardapio;
  p.style.background = g('fundo'); const tx = lum(g('fundo')) > 150 ? '#222' : '#fffc';
  p.innerHTML = (lg ? '<img src="' + esc(lg) + '" alt="" style="max-height:70px;max-width:60%;display:block;margin:0 auto 8px">' : '') + '<b style="color:' + g('destaque') + ';font-size:18px">' + esc(S.rest.nome) + '</b><div style="color:' + tx + '">Prévia de um cartão do cardápio</div><span class="bt" style="background:' + g('botao') + ';color:#fff">Fazer pedido</span>'; };
function promptLogo(L){
  const r = S.rest, m = r.marca || {}, c = m.cores || {}, tipo = (S.aj.tipoComida || {})[r.id] || '';
  return L.prompt.replace(/\{nome\}/g, r.nome).replace(/\{destaque\}/g, c.destaque || '#d9a21b').replace(/\{botao\}/g, c.botao || '#8c1c13').replace(/\{fundo\}/g, c.fundo || '#14100c')
    .replace(/\{tipo\}/g, tipo ? ', que vende ' + tipo : '').replace(/\{tipo_icone\}/g, tipo ? ' que lembre ' + tipo : '').replace(/\{slogan_p\}/g, m.slogan ? ' (se quiser, o slogan "' + m.slogan + '" pequeno embaixo)' : '');
}
function logosHtml(){
  const lg = S.rest.marca.logos = S.rest.marca.logos || {}, tipo = (S.aj.tipoComida || {})[S.rest.id] || '';
  return '<label for="f_tipo">O que o restaurante vende? (ajuda o ChatGPT a desenhar)</label><input id="f_tipo" value="' + esc(tipo) + '" placeholder="Ex.: pizza, hambúrguer, churros, açaí" onchange="rvTipoComida(this.value)">'
   + LOGOS.map(L => '<div class="logo-card"><div class="logo-topo"><div class="logo-img' + (L.id === 'impressao' ? ' branco' : '') + '">' + (lg[L.id] ? '<img src="' + esc(lg[L.id]) + '" alt=""' + (L.id === 'impressao' ? ' class="termica"' : '') + '>' : '<span>' + L.icone + '</span>') + '</div><div><b>' + L.nome + '</b><small>' + esc(L.onde) + '</small>' + (lg[L.id] ? '<span class="selo ativo">✓ enviada</span>' : '<span class="selo aviso">falta</span>') + '</div></div>'
     + '<details class="como"><summary>📏 Como deve ser · 🤖 pedir ao ChatGPT</summary><ul class="regras">' + L.regras.map(x => '<li>✅ ' + esc(x) + '</li>').join('') + L.nao.map(x => '<li>❌ ' + esc(x) + '</li>').join('') + '</ul>'
     + '<p class="pequeno"><b>Texto pronto para o ChatGPT</b> (copie, cole no ChatGPT e peça a imagem):</p><div class="copiar" id="pr_' + L.id + '">' + esc(promptLogo(L)) + '</div><button class="mini" onclick="rvCopiar(\'pr_' + L.id + '\')">📋 Copiar texto</button> <a class="btn mini" href="https://chatgpt.com/" target="_blank" rel="noopener">Abrir o ChatGPT ↗</a></details>'
     + '<label class="enviar"><input type="file" accept="image/png,image/webp,image/jpeg" onchange="rvLogo(\'' + L.id + '\',this)"><span>📤 ' + (lg[L.id] ? 'Trocar imagem' : 'Enviar imagem') + '</span></label>' + (lg[L.id] && L.id === 'impressao' ? '<small class="mudo">A prévia acima mostra como sai na impressora (preto e branco).</small>' : '') + '<div id="lgres_' + L.id + '"></div></div>').join('');
}
window.rvTipoComida = v => { const t = Object.assign({}, S.aj.tipoComida || {}); t[S.rest.id] = v.trim(); salvarAjustes({ tipoComida:t }, 'Anotado.').then(refazerMarca); };
function abrirImg(arq){ return new Promise((ok, no) => { const im = new Image(), u = URL.createObjectURL(arq); im.onload = () => ok({ im, u }); im.onerror = () => no(new Error('Não consegui ler essa imagem. Use PNG ou JPG.')); im.src = u; }); }
function analisar(im){ const cv = document.createElement('canvas'), w = cv.width = Math.min(200, im.width), h = cv.height = Math.round(im.height * w / im.width), x = cv.getContext('2d'); x.drawImage(im, 0, 0, w, h);
  const d = x.getImageData(0, 0, w, h).data, px = (i, j) => { const o = (j * w + i) * 4; return [d[o], d[o + 1], d[o + 2], d[o + 3]]; }, cantos = [px(1, 1), px(w - 2, 1), px(1, h - 2), px(w - 2, h - 2)];
  let cor = 0, n = 0; for(let o = 0; o < d.length; o += 16){ if(d[o + 3] < 40) continue; n++; const mx = Math.max(d[o], d[o + 1], d[o + 2]), mn = Math.min(d[o], d[o + 1], d[o + 2]); if(mx - mn > 50) cor++; }
  const lumP = p => p[0] * .299 + p[1] * .587 + p[2] * .114;
  return { transp:cantos.some(p => p[3] < 200), fundoBranco:cantos.every(p => p[3] > 240 && lumP(p) > 225), fundoEscuro:cantos.every(p => p[3] > 240 && lumP(p) < 70), colorido:n ? cor / n > .15 : false, ratio:im.width / im.height }; }
function prepararImg(L, im){ const cv = document.createElement('canvas'), x = cv.getContext('2d');
  if(L === 'icone'){ cv.width = cv.height = 512; x.fillStyle = (S.rest.marca.cores || {}).fundo || '#14100c'; x.fillRect(0, 0, 512, 512); const e = Math.min(512 / im.width, 512 / im.height); const w = im.width * e, h = im.height * e; x.drawImage(im, (512 - w) / 2, (512 - h) / 2, w, h); }
  else { const e = Math.min(1, 1024 / Math.max(im.width, im.height)); cv.width = Math.round(im.width * e); cv.height = Math.round(im.height * e); x.drawImage(im, 0, 0, cv.width, cv.height); }
  return new Promise((ok, no) => cv.toBlob(b => b ? ok(b) : no(new Error('Imagem inválida.')), 'image/png')); }
window.rvLogo = async (tipo, inp) => {
  const f = inp.files[0]; if(!f) return; const box = $('lgres_' + tipo);
  try{
    lerForm(); const { im, u } = await abrirImg(f), a = analisar(im), avisos = [];
    if(tipo === 'cardapio'){ if(a.fundoBranco) avisos.push('Parece ter FUNDO BRANCO: no cardápio escuro vai aparecer um quadrado. Peça ao ChatGPT "com fundo transparente".'); if(!a.transp && !a.fundoBranco) avisos.push('A imagem não tem fundo transparente. Se ficar um quadrado no cardápio, peça de novo com fundo transparente.'); }
    if(tipo === 'impressao'){ if(a.fundoEscuro) avisos.push('Fundo ESCURO vira um borrão preto na impressora. Use fundo branco.'); if(a.colorido) avisos.push('A logo é colorida: na impressora vira cinza manchado. O ideal é só preto.'); if(a.ratio < 1.2) avisos.push('O ideal é deitada (mais larga que alta).'); }
    if(tipo === 'icone' && Math.abs(a.ratio - 1) > .03) avisos.push('A imagem não era quadrada: o painel encaixou num quadrado com a cor de fundo do restaurante.');
    const b = await prepararImg(tipo, im); URL.revokeObjectURL(u);
    const cam = S.rest.slug + '/' + tipo + '-' + Date.now() + '.png';
    await req('/storage/v1/object/marcas/' + cam, { method:'POST', body:b, headers:{ 'Content-Type':'image/png', 'x-upsert':'true' } });
    S.rest.marca.logos = S.rest.marca.logos || {}; S.rest.marca.logos[tipo] = URL_ + '/storage/v1/object/public/marcas/' + cam;
    if(await salvar('Logo enviada ✓')){ await hist(S.rest.id, 'Logo enviada', tipo); refazerMarca(); const bx = $('lgres_' + tipo); if(bx && avisos.length) bx.innerHTML = avisos.map(x => '<div class="res aviso">⚠️ ' + esc(x) + '</div>').join(''); }
  }catch(e){ if(box) box.innerHTML = '<div class="res erro">❌ ' + esc(e.message) + '</div>'; erro(e.message); }
};
function modulosHtml(){ const m = S.rest.modulos; return MODULOS.map(x => '<label class="modulo"><input type="checkbox" data-k="modulos.' + x.id + '"' + (m[x.id] ? ' checked' : '') + '><span><b>' + esc(x.nome) + '</b><small>' + esc(x.desc || '') + '</small></span></label>').join('') + botSalvar(); }
function abaMarcaTudo(){ C('<div class="card"><h2>🎨 Cores e textos</h2><p class="mudo pequeno">Muda no site do restaurante na hora (o dono também pode ajustar em Administrador → Sistema → Aparência).</p>' + marcaHtml() + '</div><div class="card"><h2>🖼️ Logos</h2>' + logosHtml() + '</div>'); rvPrevia(); }

/* ---------- SAÚDE ---------- */
function saudeHtml(r, aninhado){
  const sd = saudeDe(r.slug), h = sd.h, sec = x => aninhado ? '<div class="sub-sec">' + x + '</div>' : '<div class="card">' + x + '</div>';
  if(!h) return sec('<b>' + ponto(SAUDE_COR.sem) + 'Sem sinal ainda</b><p class="mudo pequeno">Este restaurante ainda não enviou o resumo de saúde (ele envia sozinho a cada 15 minutos, depois que o banco e o site estão prontos).</p>');
  const itens = h.itens || [], ruins = itens.filter(i => i.nivel !== 'ok' && !/^Plano grátis:/i.test(i.titulo || '')), uso = usoDe(h), srv = h.servidores || {}, im = sd.geral === 'impl';
  const outros = itens.filter(i => !/^Plano grátis:/i.test(i.titulo || '') || !uso.some(u => u.id === i.id));
  return sec('<div class="linha"><b>' + ponto(SAUDE_COR[sd.geral]) + SAUDE_ROT[sd.geral] + '</b><small class="mudo">' + haTempo(sd.min) + '</small></div>' + (im ? '<p class="mudo pequeno">Ainda em implantação: o que falta aparece abaixo só como lista do que ligar, sem alarme.</p>' : sd.geral === 'sem' ? '<p class="mudo pequeno">Parou de enviar sinal. Confira se o Supabase dele está ativo (pode ter sido pausado por falta de uso).</p>' : '<small class="mudo">' + itens.length + ' verificações</small>'))
    + sec('<b>Servidores</b>' + linhaSrv_('Supabase', 'principal', srv.supabase) + linhaSrv_('Planilha principal', 'reserva', srv.planilha) + '<div id="srvCont_' + r.id + '">' + linhaSrv_('Planilha de contingência', 'último recurso', r.contingencia_url ? { estado:'sem_resposta' } : { estado:'nao_usa' }) + '</div>')
    + (srv.drive && (srv.drive.principal || srv.drive.contingencia) ? sec('<b>☁️ Google Drive</b>' + driveBarra_('Drive principal', srv.drive.principal, im) + driveBarra_('Drive da contingência', srv.drive.contingencia, im)) : '')
    + (ruins.length ? sec('<b>' + (im ? 'Falta ligar' : 'Pede atenção') + '</b>' + ruins.map(i => '<div class="item-ruim" style="border-color:' + (im ? SAUDE_COR.impl : SAUDE_COR[i.nivel]) + '"><b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.texto) + '</small></div>').join('')) : '')
    + (uso.length ? sec('<b>📊 Plano grátis do Supabase</b>' + uso.map(barraUso).join('') + '<small class="mudo">Estimativa. O número oficial está no Supabase (Settings → Usage).</small>') : '')
    + sec('<details><summary><b>Todas as verificações (' + outros.length + ')</b></summary>' + outros.map(i => '<div style="padding:6px 0">' + ponto(SAUDE_COR[i.nivel] || SAUDE_COR.sem) + '<b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.texto) + '</small></div>').join('') + '</details>');
}
const fmtBytes_ = b => { b = Number(b) || 0; if(b <= 0) return '0 B'; const u = ['B','KB','MB','GB','TB']; let i = 0; while(b >= 1024 && i < u.length - 1){ b /= 1024; i++; } return b.toFixed(i ? 1 : 0).replace('.', ',') + ' ' + u[i]; };
function driveBarra_(titulo, d, im){
  if(!d || d.estado === 'sem_resposta') return '<div class="uso"><b>' + titulo + '</b><br><small class="mudo">Aguardando a primeira medição…</small></div>';
  if(d.estado !== 'ok' && (im || /invalid url|não configurad|nao configurad/i.test(d.mensagem || ''))) return '<div class="uso"><b>' + titulo + '</b><br><small class="mudo">Ainda não ligado.</small></div>';
  if(d.estado !== 'ok') return '<div class="uso"><b>' + titulo + '</b><div class="res erro">⚠️ Não foi possível medir: ' + esc(d.mensagem || 'sem resposta') + '</div></div>';
  const total = (Number(d.usado) || 0) + (Number(d.livre) || 0), pct = d.percentual == null ? 0 : Number(d.percentual);
  return barraUso({ tit:titulo, uso:fmtBytes_(d.usado), lim:d.livre == null ? '—' : fmtBytes_(total), pct }) + (d.nivel === 'Crítico' ? '<small class="txt-erro">⚠️ Quase cheio: novos backups e fotos podem falhar.</small>' : '');
}
function linhaSrv_(nome, papel, o){ o = o || {}; const ok = o.estado === 'ok', c = ok ? SAUDE_COR.ok : (o.estado === 'nao_usa' || o.estado === 'sem_resposta') ? SAUDE_COR.sem : SAUDE_COR.problema;
  return '<div class="linha srv"><span>' + ponto(c) + '<b>' + nome + '</b> <small class="mudo">' + papel + '</small></span><small>' + (ok ? 'Online' + (o.ms != null ? ' · ' + o.ms + ' ms' : '') : o.estado === 'nao_usa' ? 'Não usada' : o.estado === 'sem_resposta' ? 'Medindo…' : 'Fora do ar' + (o.detalhe ? ' · ' + esc(o.detalhe) : '')) + '</small></div>'; }
function medirContingencia_(rests){
  (rests || []).forEach(async r => {
    if(!r.contingencia_url) return; const t0 = Date.now(); let est;
    try{ const x = await tempo(r.contingencia_url, {}); est = x.ok ? { estado:'ok', ms:Date.now() - t0 } : { estado:'fora', detalhe:'erro ' + x.status }; }catch(e){ est = { estado:'fora', detalhe:e.name === 'AbortError' ? 'sem resposta em 12 s' : 'sem conexão' }; }
    const box = $('srvCont_' + r.id); if(box) box.innerHTML = linhaSrv_('Planilha de contingência', 'último recurso', est);
  });
}
function errosHtml(lista, comNome){
  return lista.map(e => '<div class="erro-item"><div class="linha"><b>' + (comNome ? esc(nomeSlug(e.slug)) + ' · ' : '') + esc(e.mensagem) + '</b><span class="selo">' + e.ocorrencias + 'x</span></div>'
    + '<small class="mudo">Tela: ' + esc(e.tela || '—') + ' · versão ' + esc(e.versao || '—') + ' · último ' + esc(new Date(e.ultimo_em).toLocaleString('pt-BR')) + '</small>'
    + triagemHtml(e)
    + (e.detalhe || e.aparelho ? '<details><summary class="mudo pequeno">Detalhe técnico</summary><small class="mudo pre">' + esc((e.aparelho || '') + '\n' + (e.detalhe || '')) + '</small></details>' : '')
    + '<div class="linha" style="justify-content:flex-start"><button class="mini" onclick="rvErroOk(' + e.id + ')">✓ Resolvido</button><button class="mini" onclick="rvErroClaude(' + e.id + ')">🤖 Copiar para o Claude</button></div></div>').join('');
}
const TRI_ROTULO = { cache_antigo:['🟢','Provavelmente já corrigido (aparelho com versão antiga)'], conexao:['📶','Falha de conexão do aparelho'], falha_real:['🔴','Falha real do sistema'], outro:['🟡','Erro a investigar'] };
function triagemHtml(e){ const t = e.triagem; if(!t || !t.resumo) return '<small class="mudo">🔎 Ainda sem explicação do vigia (ele analisa os erros novos a cada 6 horas).</small>';
  const k = TRI_ROTULO[t.classe] || TRI_ROTULO.outro;
  return '<div class="tri"><b>' + k[0] + ' ' + k[1] + '</b><br><small>' + esc(t.resumo) + (t.causa ? ' <span class="mudo">Causa provável: ' + esc(t.causa) + '</span>' : '') + (t.acao ? ' <b>O que fazer:</b> ' + esc(t.acao) : '') + '</small>' + (t.solucao ? '<br><small>🛠️ <b>Solução proposta:</b> ' + esc(t.solucao) + '</small>' : '') + (t.pedido ? '<br><button class="mini" onclick="rvCopiarPedido(this)" data-t="' + esc(t.pedido) + '">📋 Copiar pedido pronto para o Claude</button>' : '') + '</div>'; }
window.rvCopiarPedido = b => { const t = b.getAttribute('data-t') || ''; (navigator.clipboard ? navigator.clipboard.writeText(t) : Promise.reject()).then(() => aviso('Copiado. Cole numa conversa com o Claude.', 'ok'), () => prompt('Copie o texto:', t)); };
function vigiaCard(){
  const G = S.vigiaG || {}, V = S.vigia || {}, L = S.lista.filter(r => ['ativo','teste'].includes(r.situacao));
  const quando = G.executou_em ? haTempo(Math.round((Date.now() - new Date(G.executou_em).getTime()) / 60000)) : 'ainda não rodou';
  const usos = G.ia_dia === hoje() ? Number(G.ia_usos) || 0 : 0;
  return '<div class="card"><div class="linha"><b>🛡️ Vigia</b><button class="principal mini" onclick="rvVigiaRodar()">Rodar agora</button></div>'
   + '<small class="mudo">Confere sozinho, de 6 em 6 horas, só os restaurantes ativos: projeto no ar, atualizações do banco que faltam, tarefas que falharam, fila da planilha e tamanho do banco. Só lê, nunca muda nada. Avisa no celular quando algo muda. Última conferência: ' + quando + '.</small>'
   + '<div class="linha"><small class="mudo">Uso da IA hoje</small><small>' + usos + ' de 10 · só gasta com problema novo</small></div><div class="barra"><i style="width:' + Math.min(100, usos * 10) + '%"></i></div>'
   + L.map(r => { const v = V[r.slug] || {}, lig = v.ligado !== false && !(r.slug === 'texas-burger' && !V[r.slug]); const P = v.problemas || [];
      return '<div class="linha vg-l"><div><b>' + esc(r.nome) + '</b><br><small class="mudo">' + (!lig ? 'Desligado: o vigia não se conecta ao banco dele.' : !v.verificado_em ? 'Ainda não conferido.' : P.length ? esc(v.resumo || P.map(p => p.texto).join(' ')) + P.filter(p => p.solucao).map(p => '<br>🛠️ ' + esc(p.solucao)).join('') : '✅ Tudo em ordem.') + '</small></div>'
        + '<label class="mini-sw"><input type="checkbox" ' + (lig ? 'checked ' : '') + 'onchange="rvVigiaLigar(\'' + esc(r.slug) + '\', this.checked)"> ligado</label></div>'; }).join('')
   + '</div>';
}
window.rvVigiaLigar = async (slug, on) => {
  const r = S.lista.find(x => x.slug === slug); if(!r) return;
  if(on && slug === 'texas-burger' && !confirm('Ligar o vigia no Texas Burger?\n\nEle vai se conectar ao banco do Texas só para LER (a cada 6 horas). Nada é alterado.')){ desenhar(); return; }
  try{ await rest('vigia_estado?on_conflict=slug', 'POST', { slug, ligado:on }, { Prefer:'resolution=merge-duplicates,return=representation' }); (S.vigia = S.vigia || {})[slug] = Object.assign(S.vigia[slug] || { slug, problemas:[] }, { ligado:on }); aviso(on ? 'Vigia ligado em ' + r.nome + '.' : 'Vigia desligado em ' + r.nome + '.', 'ok'); }catch(e){ erro('Não salvou: ' + e.message); }
  desenhar();
};
/* depois de atualizar o banco, o vigia reconfere sozinho (sem esperar as 6 horas) */
async function vigiaReconferir(){ try{ if(S.sess && Date.now() > S.sess.exp && !await renovar()) return; await fetch(URL_ + '/functions/v1/vigia', { method:'POST', headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:'{"acao":"rodar"}' }); await carregarSaude(); desenhar(); }catch(e){} }
window.rvVigiaRodar = async () => {
  aviso('O vigia está conferindo…', 'ok');
  try{
    if(S.sess && Date.now() > S.sess.exp && !await renovar()) throw new Error('Sua sessão expirou. Entre de novo.');
    const c = new AbortController(), t = setTimeout(() => c.abort(), 120000);
    const r = await fetch(URL_ + '/functions/v1/vigia', { method:'POST', signal:c.signal, headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:'{"acao":"rodar"}' }); clearTimeout(t);
    if(r.status === 404) throw new Error('A função "vigia" ainda não foi publicada no servidor do painel.');
    const j = await r.json().catch(() => null); if(!j || !j.ok) throw new Error((j && j.erro) || 'O vigia não respondeu.');
    await carregarSaude(); aviso('Conferido: ' + j.resumo + (j.erros_explicados ? ' · ' + j.erros_explicados + ' erro(s) explicado(s)' : ''), 'ok');
  }catch(e){ erro(e.name === 'AbortError' ? 'O vigia demorou demais.' : e.message); }
  desenhar();
};
const nomeSlug = s => (S.lista.find(r => r.slug === s) || {}).nome || s;
function abaSaude(){ const r = S.rest, er = errosDe(r.slug); C(aoVivoCaixa(r) + saudeHtml(r, false) + '<div class="card"><div class="linha"><h2>🐞 Erros abertos</h2>' + (er.length ? '<button class="mini" onclick="rvErrosOk(\'' + esc(r.slug) + '\')">Marcar todos resolvidos</button>' : '') + '</div>' + (er.length ? errosHtml(er, false) : '<p class="mudo">Nenhum erro aberto. 👍</p>') + '</div>'); medirContingencia_([r]); aoVivoCarregar(r); }
/* ---------- AO VIVO pelo conector do Supabase: estado do projeto, serviços, plano grátis, tarefas, erros, login e segurança ---------- */
const AV_LIM = { banco:500 * 1048576, storage:1073741824, logins:50000, funcoesMes:500000 };
const avEstado = { ACTIVE_HEALTHY:['No ar','ok'], ACTIVE_UNHEALTHY:['No ar, com falha','problema'], INACTIVE:['PAUSADO','problema'], PAUSING:['Pausando…','atencao'], RESTORING:['Voltando…','atencao'], COMING_UP:['Ligando…','atencao'], GOING_DOWN:['Desligando…','atencao'], UPGRADING:['Atualizando…','atencao'] };
function aoVivoCaixa(r){
  if(!temSb(r)) return '<div class="card"><div class="linha"><b>📡 Ao vivo</b><button class="mini" onclick="rvAba(\'passo\')">Ligar o conector</button></div><small class="mudo">Com o conector do Supabase ligado, aqui aparecem na hora: se o banco está no ar ou pausado, o uso do plano grátis, tarefas que falharam, erros das últimas 24 h, o login e os alertas de segurança do Supabase.</small></div>';
  return '<div class="card av"><div class="linha"><b>📡 Ao vivo (direto do Supabase)</b><button class="mini" onclick="aoVivoCarregar(S.rest, true)">↻ Medir agora</button></div><div id="av_' + r.id + '"><small class="mudo">Medindo…</small></div></div>';
}
async function aoVivoCarregar(r, forcar){
  if(!r || !temSb(r)) return; const box = () => $('av_' + r.id);
  const c = (S.avCache || {})[r.id]; if(c && !forcar && Date.now() - c.t < 60000){ if(box()) box().innerHTML = aoVivoHtml(r, c.d); return; }
  if(box() && forcar) box().innerHTML = '<small class="mudo">Medindo…</small>';
  let d; try{ d = await chamarConector({ acao:'sb_ao_vivo', restaurante_id:r.id }); }catch(e){ d = { ok:false, erro:e.message }; }
  if(d.ok) (S.avCache = S.avCache || {})[r.id] = { t:Date.now(), d };
  if(box()) box().innerHTML = d.ok ? aoVivoHtml(r, d) : conLinha(false, esc(d.erro || 'Não consegui medir.'));
  clearTimeout(S.avTimer); S.avTimer = setTimeout(() => { if(S.view === 'rest' && S.aba === 'saude' && S.rest && S.rest.id === r.id && !document.hidden) aoVivoCarregar(r, true); }, 180000);
}
window.aoVivoCarregar = aoVivoCarregar;
/* linha curta do "ao vivo" na tela Saúde (todos os restaurantes) */
async function aoVivoMini(r){
  const c = (S.avCache || {})[r.id]; let d = c && Date.now() - c.t < 60000 ? c.d : null;
  if(!d){ try{ d = await chamarConector({ acao:'sb_ao_vivo', restaurante_id:r.id }); }catch(e){ d = { ok:false, erro:e.message }; } if(d.ok) (S.avCache = S.avCache || {})[r.id] = { t:Date.now(), d }; }
  const box = $('avr_' + r.id); if(!box) return; if(!d.ok){ box.innerHTML = '<small class="txt-erro">📡 ' + esc(d.erro || 'sem resposta') + '</small>'; return; }
  const p = d.projeto || {}, b = d.banco || {}, f = d.funcoes24h || {}, est = avEstado[p.estado] || [p.estado || '—', 'sem'];
  box.innerHTML = '<small>📡 <b style="color:' + SAUDE_COR[r.situacao === 'implantacao' && est[1] !== 'ok' ? 'impl' : est[1]] + '">' + esc(est[0]) + '</b>'
    + (b.banco != null ? ' · banco ' + fmtBytes_(b.banco) + ' de 500 MB' : '') + (b.tarefas_falhas ? ' · <b class="txt-erro">' + b.tarefas_falhas + ' tarefa(s) falharam</b>' : '') + (f.erros ? ' · <b class="txt-erro">' + f.erros + ' erro(s) nas funções</b>' : '')
    + (d.seguranca && d.seguranca.erro ? ' · <b class="txt-erro">' + d.seguranca.erro + ' alerta(s) de segurança</b>' : '') + '</small>';
  if(p.estado === 'INACTIVE' && S.view === 'inicio') desenhar();
}
function aoVivoHtml(r, d){
  const im = r.situacao === 'implantacao', p = d.projeto || {}, est = avEstado[p.estado] || [p.estado || (p.erro ? 'Sem resposta' : '—'), p.erro ? 'problema' : 'sem'];
  const cor = k => SAUDE_COR[im && k !== 'ok' ? 'impl' : k] || SAUDE_COR.sem, n = v => Number(v || 0).toLocaleString('pt-BR'), b = d.banco || {}, f = d.funcoes24h, a = d.api24h, lg = d.login;
  const pct = (x, y) => Math.round(Math.min(100, (Number(x) || 0) / y * 100) * 10) / 10, it = (ok, t, sub) => '<div class="av-i">' + ponto(cor(ok === null ? 'sem' : ok ? 'ok' : 'atencao')) + '<span><b>' + t + '</b>' + (sub ? '<br><small class="mudo">' + sub + '</small>' : '') + '</span></div>';
  let h = '<div class="av-topo">' + ponto(cor(est[1])) + '<b>' + esc(est[0]) + '</b><small class="mudo"> · ' + esc(p.regiao || '') + (b.postgres ? ' · Postgres ' + esc(b.postgres) : '') + ' · medido ' + new Date(d.em).toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }) + '</small></div>';
  if(p.estado === 'INACTIVE') h += '<div class="res erro">O Supabase pausou este banco (plano grátis sem uso). O site do restaurante não funciona até reativar.<br><button class="principal" style="margin-top:8px" onclick="rvReativar()">▶️ Reativar o banco agora</button></div>';
  if(d.servicos) h += '<div class="av-chips">' + d.servicos.map(s => '<span class="av-chip">' + ponto(cor(s.ok ? 'ok' : 'problema')) + esc({ db:'Banco', rest:'API', auth:'Login', storage:'Arquivos', realtime:'Tempo real' }[s.nome] || s.nome) + '</span>').join('') + '</div>';
  h += '<div class="av-sec"><b>📊 Plano grátis (agora)</b>';
  if(b.banco != null) h += barraUso({ tit:'Tamanho do banco', uso:fmtBytes_(b.banco), lim:'500 MB', pct:pct(b.banco, AV_LIM.banco) });
  if(b.storage != null) h += barraUso({ tit:'Arquivos (Storage)', uso:fmtBytes_(b.storage) + ' · ' + n(b.storage_arquivos) + ' arq.', lim:'1 GB', pct:pct(b.storage, AV_LIM.storage) });
  if(f) h += barraUso({ tit:'Funções do servidor (24 h × 30)', uso:n(f.total * 30) + '/mês', lim:'500 mil', pct:pct(f.total * 30, AV_LIM.funcoesMes) });
  if(b.logins != null) h += barraUso({ tit:'Logins cadastrados', uso:n(b.logins), lim:'50 mil', pct:pct(b.logins, AV_LIM.logins) });
  h += '<small class="mudo">Medido agora no Supabase. Funções: estimativa do mês pelo uso das últimas 24 h.</small></div>';
  h += '<div class="av-sec"><b>🩺 Últimas 24 horas</b>'
    + (b.tarefas != null ? it(!b.tarefas_falhas, n(b.tarefas) + ' tarefas agendadas · ' + n(b.tarefas_rodadas) + ' execuções', b.tarefas_falhas ? n(b.tarefas_falhas) + ' falharam: ' + (b.falhas_lista || []).map(x => esc(x.tarefa) + ' (' + esc(x.msg || '') + ')').join('; ') : 'nenhuma falhou') : '')
    + (f ? it(!f.erros, n(f.total) + ' chamadas às funções do servidor', f.erros ? n(f.erros) + ' com erro (500)' : 'nenhuma com erro') : '')
    + (d.erros_banco24h != null ? it(!d.erros_banco24h, n(d.erros_banco24h) + ' erros no banco', d.erros_banco24h ? 'veja em Supabase → Logs → Postgres' : '') : '')
    + (b.chamadas_saida != null ? it(!b.chamadas_saida_erro, n(b.chamadas_saida) + ' chamadas do banco para fora', b.chamadas_saida_erro ? n(b.chamadas_saida_erro) + ' falharam (planilha, avisos, IA…)' : 'nenhuma falhou') : '')
    + (a ? it(null, n(a.rest + a.auth + a.storage + a.realtime) + ' pedidos à API', 'dados ' + n(a.rest) + ' · login ' + n(a.auth) + ' · arquivos ' + n(a.storage) + ' · tempo real ' + n(a.realtime)) : '')
    + (b.fila_planilha != null ? it(!b.fila_planilha, n(b.fila_planilha) + ' itens esperando para a planilha', '') : '')
    + (b.pedidos_hoje != null ? it(null, n(b.pedidos_hoje) + ' pedidos hoje', n(b.conexoes) + ' conexões abertas no banco') : '') + '</div>';
  if(f && f.top && f.top.length) h += '<details class="av-sec"><summary><b>⚙️ Funções mais chamadas (24 h)</b></summary>' + f.top.map(x => '<div class="linha av-l"><span>' + esc(x.nome) + '</span><small>' + n(x.n) + '</small></div>').join('') + '</details>';
  if(b.tabelas && b.tabelas.length) h += '<details class="av-sec"><summary><b>🗄️ Maiores tabelas</b></summary>' + b.tabelas.map(x => '<div class="linha av-l"><span>' + esc(x.nome) + ' <small class="mudo">' + n(x.linhas) + ' linhas</small></span><small>' + fmtBytes_(x.bytes) + '</small></div>').join('') + '</details>';
  if(lg){ const site = (r.site_url || '').replace(/\/?$/, '/'), siteOk = !!r.site_url && lg.site === site, redOk = !!r.site_url && lg.redirecionos.some(u => u.indexOf(site) === 0);
    h += '<div class="av-sec"><b>🔑 Login</b>' + it(siteOk && redOk, 'Endereços do login', siteOk && redOk ? esc(lg.site) : 'Site URL: ' + esc(lg.site || '(vazio)') + (r.site_url ? ' · esperado ' + esc(site) : ''))
      + it(lg.google, 'Entrar com o Google', lg.google ? 'ligado' : 'desligado (etapa Entrar com o Google)')
      + (!(siteOk && redOk) && r.site_url ? '<button class="mini" onclick="rvLoginUrls(true)">⚡ Arrumar os endereços do login</button><div id="con_lu_' + r.id + '"></div>' : '') + '</div>'; }
  const adv = (x, t) => x ? '<div class="av-sec"><div class="linha"><b>' + t + '</b><small>' + (x.erro ? '<span class="selo erro">' + x.erro + ' grave(s)</span> ' : '') + (x.aviso ? '<span class="selo aviso">' + x.aviso + ' aviso(s)</span>' : '') + (!x.erro && !x.aviso ? '<span class="selo ativo">✓ ok</span>' : '') + (x.aceitos ? ' <span class="selo" title="Alertas que são decisão do sistema (cardápio público, funções liberadas). Não precisam de ação.">' + x.aceitos + ' por desenho</span>' : '') + '</small></div>'
    + (x.itens.length ? '<details><summary class="pequeno">Ver</summary>' + x.itens.map(i => '<div class="item-ruim" style="border-color:' + (i.nivel === 'ERROR' ? SAUDE_COR.problema : SAUDE_COR.atencao) + '"><b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.detalhe) + '</small></div>').join('') + '</details>' : '') + '</div>' : '';
  h += adv(d.seguranca, '🛡️ Segurança (Supabase)') + adv(d.desempenho, '🚀 Desempenho (Supabase)');
  h += '<div class="av-sec"><div class="linha"><b>🧩 Funções do servidor</b><small>' + (d.funcoes || []).length + ' publicadas</small></div>' + ((d.funcoes || []).length ? '<small class="mudo">Última atualização: ' + esc(new Date(Math.max(...d.funcoes.map(x => Number(x.em) || Date.parse(x.em) || 0))).toLocaleString('pt-BR')) + '</small>' : '') + '<p style="margin:6px 0 0"><button class="mini" onclick="rvConPublicarFuncoes(\'' + r.id + '\',\'avf_' + r.id + '\')">⬆️ Publicar / atualizar as funções</button></p><div id="con_avf_' + r.id + '"></div></div>';
  return h;
}
/* o que precisa de atenção num resultado "ao vivo" (lista de textos; vazio = tudo certo) */
function avProblemas(r, d){
  const L = [], p = d.projeto || {}, b = d.banco || {}, f = d.funcoes24h || {}, lg = d.login, im = r.situacao === 'implantacao';
  if(p.estado === 'INACTIVE') L.push([3, 'Banco PAUSADO pelo Supabase: o site não funciona']);
  else if(p.estado && p.estado !== 'ACTIVE_HEALTHY') L.push([2, 'Projeto: ' + ((avEstado[p.estado] || [p.estado])[0])]);
  (d.servicos || []).filter(x => !x.ok).forEach(x => L.push([2, 'Serviço com falha: ' + ({ db:'Banco', rest:'API', auth:'Login', storage:'Arquivos', realtime:'Tempo real' }[x.nome] || x.nome)]));
  if(b.banco > AV_LIM.banco * 0.7) L.push([b.banco > AV_LIM.banco * 0.9 ? 3 : 2, 'Banco em ' + Math.round(b.banco / AV_LIM.banco * 100) + '% do plano grátis']);
  if(b.storage > AV_LIM.storage * 0.7) L.push([2, 'Arquivos em ' + Math.round(b.storage / AV_LIM.storage * 100) + '% do plano grátis']);
  if(f.total * 30 > AV_LIM.funcoesMes * 0.7) L.push([2, 'Funções do servidor: ~' + Math.round(f.total * 30 / AV_LIM.funcoesMes * 100) + '% do mês']);
  if(b.tarefas_falhas) L.push([2, b.tarefas_falhas + ' tarefa(s) agendada(s) falharam: ' + (b.falhas_lista || []).map(x => x.tarefa).filter((x, i, a) => a.indexOf(x) === i).join(', ')]);
  if(f.erros) L.push([2, f.erros + ' erro(s) nas funções do servidor']);
  if(d.erros_banco24h) L.push([1, d.erros_banco24h + ' erro(s) no banco']);
  if(b.chamadas_saida_erro) L.push([1, b.chamadas_saida_erro + ' chamada(s) para fora falharam']);
  if(b.fila_planilha > 50) L.push([1, b.fila_planilha + ' itens presos na fila da planilha']);
  if(d.seguranca && d.seguranca.erro) L.push([3, d.seguranca.erro + ' alerta(s) grave(s) de segurança do Supabase']);
  if(lg && r.site_url && lg.site !== r.site_url.replace(/\/?$/, '/')) L.push([2, 'Endereços do login diferentes do site']);
  if(lg && !lg.google && !im) L.push([1, '"Entrar com o Google" desligado']);
  return im ? L.filter(x => x[1].indexOf('PAUSADO') >= 0 || x[0] === 3).map(x => [1, x[1]]) : L;
}
window.rvConferirTodos = async () => {
  const L = S.lista.filter(r => r.situacao !== 'encerrado' && temSb(r)), box = $('avTodos'); if(!box) return;
  box.innerHTML = '<small class="mudo">Medindo ' + L.length + ' restaurante(s)…</small>';
  const res = await Promise.all(L.map(async r => { let d; try{ d = await chamarConector({ acao:'sb_ao_vivo', restaurante_id:r.id }); }catch(e){ d = { ok:false, erro:e.message }; } if(d.ok) (S.avCache = S.avCache || {})[r.id] = { t:Date.now(), d }; return [r, d]; }));
  let h = '', ok = 0;
  res.forEach(([r, d]) => { const P = d.ok ? avProblemas(r, d) : [[3, 'Não consegui medir: ' + (d.erro || 'sem resposta')]];
    if(!P.length){ ok++; return; }
    h += '<div class="av-sec"><div class="linha"><b>' + esc(r.nome) + '</b><button class="mini" onclick="rvAbrir(\'' + r.id + '\',\'saude\')">Abrir ›</button></div>'
      + P.sort((a, b) => b[0] - a[0]).map(x => '<div class="av-i">' + ponto(x[0] >= 3 ? SAUDE_COR.problema : x[0] === 2 ? SAUDE_COR.atencao : SAUDE_COR.sem) + '<span>' + esc(x[1]) + '</span></div>').join('') + '</div>'; });
  box.innerHTML = (ok ? conLinha(true, ok + ' de ' + L.length + ' sem nada para resolver.') : '') + h + '<small class="mudo">Medido às ' + new Date().toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }) + '.</small>';
  L.forEach(aoVivoMini);
};
window.rvReativar = async () => { const r = S.rest; const nome = prompt('Reativar o banco de "' + r.nome + '"? Leva uns minutos.\n\nPara confirmar, digite o nome do restaurante:'); if(nome === null) return; if(nome !== r.nome) return erro('O nome não confere.');
  try{ const a = await chamarConector({ acao:'sb_reativar', restaurante_id:r.id, confirmar:r.nome }); if(!a.ok) return erro(a.erro || 'Não consegui reativar.'); hist(r.id, 'Banco reativado pelo painel', ''); aviso('Pedido enviado. Em alguns minutos o banco volta; toque em Medir agora.', 'ok'); }catch(e){ erro(e.message); } };
function vSaude(){
  const L = S.lista.filter(r => r.situacao !== 'encerrado'), cont = { ok:0, atencao:0, problema:0, sem:0, impl:0 }; L.forEach(r => cont[saudeDe(r.slug).geral]++);
  const ordem = { problema:0, atencao:1, sem:2, ok:3, impl:4 }, Ls = L.slice().sort((a, b) => ordem[saudeDe(a.slug).geral] - ordem[saudeDe(b.slug).geral] || errosDe(b.slug).length - errosDe(a.slug).length);
  T('<div class="topo"><h1>Saúde</h1><small class="mudo">atualiza sozinho · ' + haTempo(Math.round((Date.now() - (S.saudeEm || Date.now())) / 60000)) + '</small></div>'
   + dica('Cada restaurante manda um resumo a cada 15 minutos. Erros que aparecem nas telas deles chegam aqui; toque em "Copiar para o Claude" para pedir a correção.') + '<div class="kpis quatro">' + kpi('🟢 Tudo certo', cont.ok, 'ok') + kpi('🟡 Atenção', cont.atencao, cont.atencao ? 'aviso' : '') + kpi('🔴 Problema', cont.problema, cont.problema ? 'erro' : '') + kpi('⚪ Sem sinal', cont.sem, '') + '</div>'
   + vigiaCard()
   + (L.some(temSb) ? '<div class="card"><div class="linha"><b>📡 Conferir todos agora</b><button class="principal mini" onclick="rvConferirTodos()">Conferir</button></div><small class="mudo">Mede ao vivo, pelo conector, todos os restaurantes ligados e junta aqui só o que precisa de atenção.</small><div id="avTodos"></div></div>' : '')
   + Ls.map(r => { const sd = saudeDe(r.slug), er = errosDe(r.slug), uso = usoDe(sd.h), pior = uso.slice().sort((a, b) => b.pct - a.pct)[0], ruins = sd.h && sd.geral !== 'impl' ? (sd.h.itens || []).filter(i => i.nivel !== 'ok' && !/^Plano grátis:/i.test(i.titulo || '')) : [];
      return '<div class="card saude-r"><div class="linha"><b>' + ponto(SAUDE_COR[sd.geral]) + esc(r.nome) + '</b><small class="mudo">' + (sd.h ? haTempo(sd.min) : 'sem sinal') + '</small></div>'
       + '<div class="linha" style="justify-content:flex-start;gap:6px">' + '<span class="selo">' + SAUDE_ROT[sd.geral] + '</span>' + (er.length ? '<span class="selo' + (sd.geral === 'impl' ? '' : ' erro') + '">🐞 ' + er.length + ' erro(s)</span>' : '') + (ruins.length ? '<span class="selo aviso">' + ruins.length + ' alerta(s)</span>' : '') + '</div>'
       + (ruins.length ? ruins.slice(0, 3).map(i => '<div class="item-ruim" style="border-color:' + SAUDE_COR[i.nivel] + '"><b>' + esc(i.titulo) + '</b><br><small class="mudo">' + esc(i.texto) + '</small></div>').join('') : '')
       + (pior ? (pior.pct >= 70 ? barraUso(pior) : '<small class="mudo">✅ Plano grátis folgado · maior uso: ' + esc(String(pior.tit).replace(/^Plano grátis:\s*/i, '')) + ' ' + String(pior.pct).replace('.', ',') + '%</small>') : '') + (er.length ? '<details><summary class="pequeno"><b>Ver os erros</b></summary>' + errosHtml(er, false) + '</details>' : '')
       + (temSb(r) ? '<div class="av-mini" id="avr_' + r.id + '"><small class="mudo">📡 medindo ao vivo…</small></div>' : '')
       + '<details><summary class="pequeno"><b>Ver tudo</b></summary>' + saudeHtml(r, true) + '</details><p style="margin:8px 0 0"><button class="mini" onclick="rvAbrir(\'' + r.id + '\',\'saude\')">Abrir restaurante ›</button></p></div>'; }).join('')
   + (S.erros.filter(e => !S.lista.some(r => r.slug === e.slug)).length ? '<div class="card"><h2>Erros de sites sem cadastro</h2>' + errosHtml(S.erros.filter(e => !S.lista.some(r => r.slug === e.slug)), true) + '</div>' : '')
   + (!L.length ? '<div class="card vazio">Nenhum restaurante ainda.</div>' : ''));
  medirContingencia_(L); L.filter(temSb).forEach(aoVivoMini);
}
window.rvErroOk = async id => { try{ await rest('erros_app?id=eq.' + id, 'PATCH', { resolvido:true, resolvido_em:new Date().toISOString() }); S.erros = S.erros.filter(e => e.id !== id); aviso('Marcado como resolvido.', 'ok'); S.view === 'rest' ? abaSaude() : desenhar(); }catch(e){ erro('Não foi possível marcar: ' + e.message); } };
window.rvErrosOk = async slug => { if(!confirm('Marcar todos os erros deste restaurante como resolvidos?')) return; try{ await rest('erros_app?slug=eq.' + encodeURIComponent(slug) + '&resolvido=eq.false', 'PATCH', { resolvido:true, resolvido_em:new Date().toISOString() }); S.erros = S.erros.filter(e => e.slug !== slug); aviso('Pronto.', 'ok'); abaSaude(); }catch(e){ erro(e.message); } };
window.rvErroClaude = async id => { const e = S.erros.find(x => x.id === id); if(!e) return; const t = 'Erro no sistema do restaurante "' + nomeSlug(e.slug) + '" (' + e.slug + '), ' + e.ocorrencias + ' vez(es), último em ' + new Date(e.ultimo_em).toLocaleString('pt-BR') + '.\nMensagem: ' + e.mensagem + '\nTela: ' + (e.tela || '—') + ' · versão ' + (e.versao || '—') + '\nAparelho: ' + (e.aparelho || '—') + '\nDetalhe: ' + (e.detalhe || '—') + '\nDescubra a causa e corrija em todos os restaurantes.'; if(await copiarTxt(t)) aviso('Copiado. Cole na conversa com o Claude.', 'ok'); };

/* ---------- CADASTRO DO RESTAURANTE ---------- */
function abaDados(){
  const r = S.rest;
  C('<div class="card"><h2>📋 Cliente e contrato</h2><div class="cols">' + ['nome','contato_nome','contato_telefone','contato_email','cidade','documento','plano','valor_mensal','taxa_implantacao','dia_vencimento','inicio_em'].map(k => '<div>' + campo(k) + '</div>').join('') + '<div><label>Código (não muda)</label><input value="' + esc(r.slug) + '" disabled></div></div>'
   + '<label for="f_sit">Situação</label><select id="f_sit" data-k="situacao">' + Object.keys(SIT).map(k => '<option value="' + k + '"' + (r.situacao === k ? ' selected' : '') + '>' + SIT[k] + '</option>').join('') + '</select><small class="mudo">"Encerrado" tira o restaurante do ar.</small>'
   + '<label for="f_obs">Anotações</label><textarea id="f_obs" data-k="observacoes">' + esc(r.observacoes || '') + '</textarea>' + botSalvar() + '</div>'
   + '<div class="card"><h2>🔌 Ligações (banco, site, planilhas)</h2><p class="mudo pequeno">Só endereços e chaves PÚBLICAS. Senhas nunca entram aqui.</p>' + ['supabase_url','supabase_chave','site_url','github_url','dominio','api_url','contingencia_url','contingencia_chave','push_chave_publica','motor'].map(k => campo(k)).join('') + botSalvar()
   + '<h3>Testes</h3><div class="linha" style="justify-content:flex-start">' + Object.keys(TESTES).map(t => '<button class="mini" onclick="rvTeste(\'' + t + '\')">' + NOME_T[t] + '</button>').join('') + '</div><div id="resTeste"></div>'
   + '<h3>Arquivos do site</h3>' + publicarHtml() + '</div>'
   + '<div class="card"><h2>🧩 Módulos contratados</h2>' + modulosHtml() + '</div>'
   + '<div class="card"><h2>🤖 Leitura do assistente</h2><p class="mudo pequeno">Deixa o seu assistente ler vendas, produtos, estoque e caixa deste restaurante (só leitura). O código da consulta fica na etapa "Ligar o assistente do painel".</p>' + leituraHtml() + '<p><button class="mini" onclick="rvAba(\'passo\');rvVerPasso(\'leitura\')">Abrir a etapa</button></p></div>'
   + '<details class="card"><summary><b class="txt-erro">🗑️ Excluir restaurante</b></summary>' + excluirHtml() + '</details>');
  mostrarRes('resTeste', Object.keys(S.res));
}
function excluirHtml(){
  const r = S.rest;
  return (S.lista.find(x => x.id === r.id) || {}).situacao === 'encerrado'
    ? '<p class="mudo pequeno">Apaga do painel este restaurante e tudo ligado a ele (etapas, cobranças, histórico). <b>Não tem como desfazer.</b> O Supabase, o GitHub e as planilhas dele continuam existindo: apague à mão.</p>'
      + '<label for="exNome">Digite o nome: <b>' + esc(r.nome) + '</b></label><input id="exNome" autocomplete="off"><label for="exSenha">Sua senha do painel</label><input id="exSenha" type="password" autocomplete="current-password">'
      + '<p><button class="perigo-forte" onclick="rvExcluir()">Excluir permanentemente</button></p><div id="exRes"></div>'
    : '<p class="mudo pequeno">Para excluir, mude a situação para "Encerrado" e salve.</p>';
}
window.rvExcluir = async () => {
  const r = S.rest, nome = ($('exNome').value || '').trim(), senha = $('exSenha').value || '';
  if(!nome || !senha) return erro('Digite o nome do restaurante e a sua senha.');
  if(!confirm('Excluir "' + r.nome + '" para sempre? Não tem como desfazer.')) return;
  try{ const x = await rpc('revenda_excluir_restaurante', { p_id:r.id, p_nome:nome, p_senha:senha });
    if(!x || !x.ok){ $('exRes').innerHTML = '<div class="res erro">⚠️ ' + esc((x && x.erro) || 'Não foi possível excluir.') + '</div>'; return; }
    S.rest = null; await carregar(); S.view = 'restaurantes'; desenhar(); aviso('Restaurante excluído do painel.', 'ok');
  }catch(e){ $('exRes').innerHTML = '<div class="res erro">⚠️ ' + esc(e.message) + '</div>'; }
};

/* ---------- COBRANÇA DE UM RESTAURANTE ---------- */
function linhaCob(c, comNome){
  const h = hoje(), at = !c.pago_em && c.vencimento && c.vencimento < h, r = S.lista.find(x => x.id === c.restaurante_id) || {};
  const tit = c.tipo === 'implantacao' ? 'Taxa de implantação' : c.tipo === 'avulsa' ? (c.descricao || 'Cobrança avulsa') : 'Mensalidade ' + mesCurto(mesDe(c.competencia)) + '/' + String(c.competencia).slice(2, 4);
  return '<div class="cob ' + (c.pago_em ? 'paga' : at ? 'atrasada' : '') + '"><div class="cob-i"><b>' + (comNome ? esc(r.nome || '—') + ' · ' : '') + esc(tit) + '</b><small>' + (c.pago_em ? '✅ Pago em ' + dataBr(c.pago_em) + (c.forma ? ' · ' + esc(c.forma) : '') : (at ? '⚠️ Atrasada · venceu ' : 'Vence ') + dataBr(c.vencimento)) + '</small></div><b class="cob-v">' + BRL(c.pago_em ? pagoValor(c) : c.valor) + '</b>'
   + '<div class="cob-a">' + (c.pago_em ? '<button class="mini" onclick="rvPago(\'' + c.id + '\',false)">Desfazer</button>'
      : '<button class="mini principal" onclick="rvReceber(\'' + c.id + '\')">💵 Recebi</button>' + (r.contato_telefone ? '<a class="btn mini" target="_blank" rel="noopener" href="' + esc(waLink(r.contato_telefone, msgCobranca(c))) + '">💬 Cobrar</a>' : '') + (S.aj.pix ? '<button class="mini" onclick="rvPixCopiar(\'' + c.id + '\')" title="Copiar o Pix copia e cola com o valor">📋 Pix</button>' : '') + '<button class="mini" onclick="rvCobApagar(\'' + c.id + '\')" title="Apagar">🗑️</button>') + '</div></div>';
}
/* LINK DO DONO: página só de leitura (vendas do mês, sistema no ar, mensalidade) para o dono do restaurante, sem login. Você gera e cancela. */
const donoUrl = l => new URL('dono.html?t=' + l.token, location.href).href;
function donoLinkHtml(){
  const l = S.dono_link; if(!S.rest || ['encerrado'].includes(S.rest.situacao)) return '';
  const corpo = !l || !l.ativo
    ? '<p class="mudo pequeno">O dono vê, no celular dele e sem senha: se o sistema está no ar, as vendas do mês e a mensalidade. Só leitura, ele não muda nada.</p><button class="mini principal" onclick="rvDonoGerar()">🔗 Gerar link do dono</button>'
    : '<p class="mudo pequeno">Link ativo' + (l.ultimo_acesso ? ' · último acesso ' + esc(new Date(l.ultimo_acesso).toLocaleDateString('pt-BR')) : ' · ainda não foi aberto') + '.</p>'
      + '<div class="linha" style="justify-content:flex-start;flex-wrap:wrap;gap:6px"><button class="mini principal" onclick="rvDonoCopiar()">📋 Copiar link</button>'
      + (S.rest.contato_telefone ? '<a class="btn mini" target="_blank" rel="noopener" href="' + esc(waLinkDono()) + '">💬 Mandar pelo WhatsApp</a>' : '')
      + '<a class="btn mini" target="_blank" rel="noopener" href="' + esc(donoUrl(l)) + '">👁️ Ver como o dono vê</a><button class="mini" onclick="rvDonoCancelar()">🚫 Cancelar link</button></div>';
  return '<div class="card"><h2>🔗 Página do dono</h2>' + corpo + '</div>';
}
function waLinkDono(){ const r = S.rest, tel = String(r.contato_telefone || '').replace(/\D/g, '').replace(/^55/, ''); return 'https://wa.me/55' + tel + '?text=' + encodeURIComponent('Olá' + (r.contato_nome ? ' ' + r.contato_nome.split(' ')[0] : '') + '! Esse é o link para você acompanhar o seu sistema (vendas do mês, mensalidade e se está tudo no ar). Só leitura, pode abrir quando quiser:\n' + donoUrl(S.dono_link)); }
window.rvDonoGerar = async () => { try{ const l = S.dono_link; if(l) await rest('dono_links?restaurante_id=eq.' + S.rest.id, 'PATCH', { token:Array.from(crypto.getRandomValues(new Uint8Array(16))).map(b => b.toString(16).padStart(2, '0')).join(''), ativo:true });
  else await rest('dono_links', 'POST', { restaurante_id:S.rest.id }); hist(S.rest.id, 'Link do dono gerado', ''); await carregarRest(); desenhar(); aviso('Link gerado.', 'ok'); }catch(e){ erro(e.message); } };
window.rvDonoCopiar = async () => { if(S.dono_link && await copiarTxt(donoUrl(S.dono_link))) aviso('Link copiado.', 'ok'); else erro('Não consegui copiar.'); };
window.rvDonoCancelar = async () => { if(!confirm('Cancelar o link? Quem tiver o link antigo deixa de ver a página.')) return; try{ await rest('dono_links?restaurante_id=eq.' + S.rest.id, 'PATCH', { ativo:false }); hist(S.rest.id, 'Link do dono cancelado', ''); await carregarRest(); desenhar(); aviso('Link cancelado.', 'ok'); }catch(e){ erro(e.message); } };
function abaCobranca(){
  const r = S.rest, nAtr = atrasadas(r.id).length, total = S.cobR.filter(c => c.pago_em).reduce((s, c) => s + pagoValor(c), 0);
  const pm = (S.prom || []).filter(x => x.restaurante_id === r.id), ROTP = { pendente:'Aguardando você', aprovada:'Aprovada', recusada:'Recusada', encerrada:'Encerrada' };
  C('<div class="kpis tres">' + kpi('Mensalidade', r.valor_mensal ? BRL(r.valor_mensal) : '—', '') + kpi('Já recebido', BRL(total), 'ok') + kpi('Em atraso', nAtr, nAtr ? 'erro' : '') + '</div>'
   + '<div class="card"><div class="linha"><h2>💰 Cobranças</h2><span><button class="mini principal" onclick="rvCobRest(\'mensalidade\')">＋ Mensalidade do mês</button> <button class="mini" onclick="rvNovaCob(\'' + r.id + '\')">＋ Outra</button></span></div>'
   + (r.valor_mensal ? '<p class="mudo pequeno">' + BRL(r.valor_mensal) + ' por mês, vence todo dia ' + (r.dia_vencimento || 10) + '.</p>' : '<p class="txt-erro pequeno">Defina a mensalidade na aba Cadastro.</p>')
   + (S.cobR.length ? S.cobR.map(c => linhaCob(c, false)).join('') : '<p class="mudo">Nenhuma cobrança ainda.</p>') + '</div>'
   + donoLinkHtml()
   + (pm.length ? '<div class="card' + (pm.some(x => x.status === 'pendente') ? ' destaque-aviso' : '') + '"><h2>🤝 Promessas de pagamento</h2><p class="mudo pequeno">Só valem se você aprovar. Aprovada, o acesso volta sozinho em até 4 minutos; passada a data, o bloqueio volta sozinho.</p>'
      + pm.slice(0, 8).map(x => '<div class="cob"><div class="cob-i"><b>Pagar em ' + dataBr(x.data_prometida) + '</b><small>Pedido em ' + esc(new Date(x.criada_em).toLocaleDateString('pt-BR')) + (x.contato ? ' · ' + esc(x.contato) : '') + (x.status === 'aprovada' ? ' · liberado até ' + dataBr(x.liberado_ate) : '') + '</small></div><span class="selo">' + ROTP[x.status] + '</span>'
        + (x.status === 'pendente' ? '<div class="cob-a"><button class="mini principal" onclick="rvPromessa(\'' + x.id + '\',true)">Aprovar</button><button class="mini" onclick="rvPromessa(\'' + x.id + '\',false)">Recusar</button></div>' : '') + '</div>').join('') + '</div>' : '')
   + '<div class="card' + (r.bloqueado ? ' destaque-erro' : '') + '"><h2>🔒 Acesso ao sistema</h2>'
   + (r.bloqueado ? '<p><b class="txt-erro">⛔ Bloqueado' + (r.bloqueado_em ? ' em ' + esc(new Date(r.bloqueado_em).toLocaleDateString('pt-BR')) : '') + '.</b> A equipe vê "Acesso suspenso" (o cardápio do cliente continua funcionando).' + (r.bloqueio_motivo ? '<br><small class="mudo">Mensagem: ' + esc(r.bloqueio_motivo) + '</small>' : '') + '</p><button class="principal" onclick="rvBloquear(false)">🔓 Liberar acesso</button>'
      : '<p class="mudo pequeno">' + ((S.aj.bloqueio_auto || {}).ligado !== false ? '🤖 O bloqueio automático está ligado: bloqueia ' + ((S.aj.bloqueio_auto || {}).dias || 1) + ' dia(s) depois do vencimento se houver mensalidade em aberto (só com mensalidade preenchida). ' : 'O bloqueio automático está desligado em Mais > Meus dados: só vale o botão Bloquear. ') + 'Dá para bloquear ou liberar na mão a qualquer momento.</p>' + togHtml_('bloqueio_auto', 'Bloquear este restaurante automaticamente se atrasar', r) + '<label for="bloqMsg">Mensagem para o restaurante (opcional)</label><textarea id="bloqMsg" rows="2" maxlength="200" placeholder="Ex.: Acesso suspenso por mensalidade em aberto. Fale comigo pelo WhatsApp."></textarea><button class="mini perigo" onclick="rvBloquear(true)">⛔ Bloquear acesso</button>') + '</div>');
}
window.rvCobRest = async tipo => {
  const r = S.rest, v = tipo === 'implantacao' ? r.taxa_implantacao : r.valor_mensal; if(!v) return erro('Defina o valor na aba Cadastro e salve antes.');
  const comp = hoje().slice(0, 8) + '01', dia = pad(r.dia_vencimento || 10);
  try{ await rest('cobrancas', 'POST', { restaurante_id:r.id, tipo, competencia:comp, valor:v, vencimento:tipo === 'implantacao' ? hoje() : comp.slice(0, 8) + dia, descricao:tipo === 'implantacao' ? 'Taxa de implantação' : null });
    await hist(r.id, tipo === 'implantacao' ? 'Taxa de implantação gerada' : 'Mensalidade gerada', comp.slice(0, 7)); await carregar(); await carregarRest(); aviso('Cobrança gerada.', 'ok'); S.aba === 'passo' ? abaPasso() : abaCobranca(); }
  catch(e){ erro(/duplicate|unique/i.test(e.message) ? 'A mensalidade deste mês já foi gerada.' : e.message); }
};
window.rvBloquear = async b => {
  const r = S.rest, msg = (($('bloqMsg') || {}).value || '').trim();
  if(!confirm(b ? 'Bloquear o acesso de "' + r.nome + '" agora?\n\nA equipe dele deixa de usar o sistema até você liberar.' : 'Liberar o acesso de "' + r.nome + '"?')) return;
  const dados = { bloqueado:b, bloqueado_em:b ? new Date().toISOString() : null, bloqueio_motivo:b ? (msg || null) : null };
  try{ await rest('restaurantes?id=eq.' + r.id, 'PATCH', dados); Object.assign(r, dados); const x = S.lista.find(z => z.id === r.id); if(x) Object.assign(x, dados); await hist(r.id, b ? 'Acesso BLOQUEADO' : 'Acesso liberado', b ? msg : ''); aviso(b ? 'Acesso bloqueado.' : 'Acesso liberado.', 'ok'); vRest(); }catch(e){ erro(e.message); }
};
window.rvPromessa = async (id, ok) => {
  const x = (S.prom || []).find(z => z.id === id); if(!x) return; let ate = null;
  if(ok){ const v = prompt('Liberar o acesso até que dia? (dd/mm/aaaa)', dataBr(x.data_prometida)); if(v === null) return; const m = v.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/); if(!m) return erro('Data inválida. Use dd/mm/aaaa.'); ate = m[3] + '-' + pad(m[2]) + '-' + pad(m[1]); if(ate < hoje()) return erro('Essa data já passou.'); }
  else if(!confirm('Recusar o pedido de promessa?')) return;
  try{ await rpc('decidir_promessa', { p_id:id, p_aprovar:ok, p_ate:ate }); await carregar(); await carregarRest(); aviso(ok ? 'Promessa aprovada. O acesso volta em até 4 minutos.' : 'Promessa recusada.', 'ok'); vRest(); }catch(e){ erro(e.message); }
};

/* janelas (receber, despesa, cobrança, proposta) */
function janela(titulo, html, ok, txtOk){
  fecharJanela(); const d = document.createElement('div'); d.className = 'modal'; d.innerHTML = '<div class="modal-c"><div class="linha"><h2>' + esc(titulo) + '</h2><button class="mini" onclick="rvFecharJ()">✕</button></div>' + html + '<div class="rodape-acoes"><button onclick="rvFecharJ()">Cancelar</button><button class="principal" id="jOk">' + (txtOk || 'Salvar') + '</button></div></div>';
  d.addEventListener('click', e => { if(e.target === d) fecharJanela(); }); document.body.appendChild(d);
  $('jOk').onclick = async () => { const b = $('jOk'); b.disabled = true; try{ if(await ok() !== false) fecharJanela(); }catch(e){ erro(e.message); } if($('jOk')) $('jOk').disabled = false; };
  const p = d.querySelector('input,select,textarea'); if(p) setTimeout(() => p.focus(), 50);
}
function fecharJanela(){ document.querySelectorAll('.modal').forEach(m => m.remove()); }
window.rvFecharJ = fecharJanela;
const jv = id => (($(id) || {}).value || '').trim();
async function recarregarTudo(){ await carregar(); if(S.rest){ const x = S.lista.find(r => r.id === S.rest.id); if(x) S.rest = normalizar(JSON.parse(JSON.stringify(x))); await carregarRest(); } desenhar(); }
window.rvReceber = id => {
  const c = S.cob.find(x => x.id === id) || S.cobR.find(x => x.id === id); if(!c) return;
  janela('Registrar recebimento', '<p class="mudo">' + esc(nomeRest(c.restaurante_id)) + '</p><div class="cols"><div><label for="jD">Data</label><input id="jD" type="date" value="' + hoje() + '"></div><div><label for="jV">Valor recebido (R$)</label><input id="jV" inputmode="decimal" value="' + String(c.valor).replace('.', ',') + '"></div></div>'
    + '<label for="jF">Forma</label><select id="jF">' + FORMAS.map(f => '<option>' + f + '</option>').join('') + '</select><label for="jO">Observação</label><input id="jO">',
    async () => { const v = num(jv('jV')); if(v == null) throw new Error('Valor inválido.'); await rest('cobrancas?id=eq.' + id, 'PATCH', { pago_em:jv('jD') || hoje(), valor_pago:v, forma:jv('jF'), observacao:jv('jO') || null }); await hist(c.restaurante_id, 'Pagamento recebido', BRL(v) + ' · ' + jv('jF')); aviso('Recebimento registrado 💵', 'ok'); await recarregarTudo(); }, '💵 Registrar');
};
window.rvPago = async (id, pago) => { if(!pago && !confirm('Desfazer este recebimento?')) return; try{ const c = S.cob.find(x => x.id === id); await rest('cobrancas?id=eq.' + id, 'PATCH', { pago_em:null, valor_pago:null, forma:null }); if(c) await hist(c.restaurante_id, 'Pagamento desfeito', ''); await recarregarTudo(); }catch(e){ erro(e.message); } };
window.rvCobApagar = async id => { if(!confirm('Apagar esta cobrança?')) return; try{ await req('/rest/v1/cobrancas?id=eq.' + id, { method:'DELETE' }); aviso('Cobrança apagada.', 'ok'); await recarregarTudo(); }catch(e){ erro(e.message); } };
window.rvNovaCob = rid => {
  const opts = S.lista.filter(r => r.situacao !== 'encerrado').map(r => '<option value="' + r.id + '"' + (r.id === rid ? ' selected' : '') + '>' + esc(r.nome) + '</option>').join('');
  janela('Nova cobrança', '<label for="jR">Restaurante</label><select id="jR">' + opts + '</select><label for="jT">Tipo</label><select id="jT"><option value="avulsa">Avulsa (serviço extra)</option><option value="implantacao">Taxa de implantação</option><option value="mensalidade">Mensalidade</option></select>'
    + '<label for="jDs">Descrição</label><input id="jDs" placeholder="Ex.: Cardápio impresso, visita técnica"><div class="cols"><div><label for="jV">Valor (R$)</label><input id="jV" inputmode="decimal"></div><div><label for="jVc">Vencimento</label><input id="jVc" type="date" value="' + hoje() + '"></div></div>',
    async () => { const v = num(jv('jV')); if(!v) throw new Error('Informe o valor.'); const venc = jv('jVc') || hoje(); await rest('cobrancas', 'POST', { restaurante_id:jv('jR'), tipo:jv('jT'), descricao:jv('jDs') || null, valor:v, vencimento:venc, competencia:venc.slice(0, 8) + '01' }); await hist(jv('jR'), 'Cobrança criada', jv('jT') + ' ' + BRL(v)); aviso('Cobrança criada.', 'ok'); await recarregarTudo(); });
};

/* ---------- CONTRATO (termos, entrega, histórico) ---------- */
function abaContrato(){
  const r = S.rest, t = S.termos || {}, a = S.aceite, fmt = d => esc(new Date(d).toLocaleString('pt-BR')), completo = !!(t.fornecedor_nome && t.fornecedor_doc && t.foro);
  let ent;
  if(!r.entregue_em) ent = '<p class="mudo">Em <b>desenvolvimento</b>: você mexe livremente e o cliente não vê tela de termos.</p>' + (completo ? '' : '<p class="txt-erro">Preencha seus dados em Mais → Meus dados antes de entregar.</p>') + '<button class="principal"' + (completo ? '' : ' disabled') + ' onclick="rvEntregar(true)">📦 Marcar como entregue</button><p class="mudo pequeno">Depois disso, o Admin do restaurante lê, aceita, tira uma foto e assina para usar a área administrativa. A equipe e o cardápio continuam funcionando.</p>';
  else if(!a) ent = '<p><b class="txt-aviso">⏳ Entregue em ' + fmt(r.entregue_em) + '. Aguardando o aceite do cliente.</b></p><button class="mini" onclick="rvEntregar(false)">Voltar para desenvolvimento</button>';
  else ent = '<p><b class="txt-ok">✅ Termos aceitos em ' + fmt(a.aceito_em) + '</b> (versão ' + esc(a.versao) + ')</p><p class="pequeno">' + esc(a.nome) + ' · ' + esc(a.cargo || '—') + ' · CPF/CNPJ ' + esc(a.documento) + '<br><small class="mudo">IP ' + esc(a.ip || '—') + '</small></p><div class="linha" style="justify-content:flex-start"><img src="' + esc(a.foto) + '" alt="Foto" class="foto-aceite"><img src="' + esc(a.assinatura) + '" alt="Assinatura" class="ass-aceite"></div><p><button class="principal mini" onclick="rvComprovante()">🖨️ Comprovante (PDF)</button></p>';
  C('<div class="card"><h2>📄 Entrega e termos de uso</h2>' + ent + '<p><button class="mini" onclick="rvVerTermos()">Ver o texto dos termos</button></p></div>'
   + '<div class="card"><h2>🕑 Histórico</h2>' + (S.hist.length ? S.hist.map(h => '<div class="hist"><small class="mudo">' + esc(new Date(h.em).toLocaleString('pt-BR')) + '</small><b>' + esc(h.acao) + '</b>' + (h.detalhe ? '<small class="mudo">' + esc(h.detalhe) + '</small>' : '') + '</div>').join('') : '<p class="mudo">Sem registros.</p>') + '</div>');
}
window.rvVerTermos = async () => {
  try{ const t = (await rest('termos_uso?select=texto,versao,fornecedor_nome,fornecedor_doc,foro,contato') || [])[0] || {};
    const txt = String(t.texto || '').replace(/\{\{FORNECEDOR\}\}/g, t.fornecedor_nome || '[preencher]').replace(/\{\{DOCUMENTO\}\}/g, t.fornecedor_doc || '[preencher]').replace(/\{\{FORO\}\}/g, t.foro || '[preencher]').replace(/\{\{CONTATO\}\}/g, t.contato || '[preencher]').replace(/\{\{RESTAURANTE\}\}/g, S.rest ? S.rest.nome : '[restaurante]');
    const w = window.open('', '_blank'); if(!w) return erro('Libere pop-ups para ver o texto.');
    w.document.write('<meta charset="utf-8"><title>Termos de uso</title><body style="font:15px/1.5 system-ui;max-width:760px;margin:20px auto;padding:0 16px">' + htmlTermos(txt) + '</body>'); w.document.close();
  }catch(e){ erro(e.message); }
};
function htmlTermos(txt){ return String(txt).split('\n').map(l => /^## /.test(l) ? '<h3 style="margin:18px 0 6px">' + esc(l.slice(3)) + '</h3>' : (l.trim() ? '<p style="margin:0 0 8px">' + esc(l) + '</p>' : '')).join(''); }
window.rvEntregar = async on => {
  const r = S.rest;
  if(on){ const falta = FALTA_ENTREGA.filter(id => { const e = r.etapas[id]; return !(e && e.feita && !e.pulada); }).map(id => (ETAPAS.find(x => x.id === id) || {}).titulo || id); if(falta.length) return erro('Ainda não dá para entregar. Falta concluir: ' + falta.join(', ') + '.'); }
  if(!confirm(on ? 'Marcar "' + r.nome + '" como ENTREGUE?\n\nO Admin do restaurante vai precisar aceitar os termos para usar a área administrativa.' : 'Voltar "' + r.nome + '" para desenvolvimento?')) return;
  const d = { entregue_em: on ? new Date().toISOString() : null };
  try{ await rest('restaurantes?id=eq.' + r.id, 'PATCH', d); Object.assign(r, d); const x = S.lista.find(z => z.id === r.id); if(x) Object.assign(x, d); await hist(r.id, on ? 'Marcado como ENTREGUE (termos exigidos)' : 'Voltou para desenvolvimento', ''); aviso(on ? 'Entregue. O Admin verá os termos ao entrar.' : 'De volta ao desenvolvimento.', 'ok'); S.aba === 'passo' ? abaPasso() : abaContrato(); }catch(e){ erro(e.message); }
};
window.rvComprovante = () => {
  const r = S.rest, a = S.aceite; if(!a) return; const w = window.open('', '_blank'); if(!w) return erro('Libere pop-ups para imprimir.');
  w.document.write('<meta charset="utf-8"><title>Comprovante de aceite - ' + esc(r.nome) + '</title><body style="font:14px/1.5 system-ui;max-width:780px;margin:20px auto;padding:0 16px"><h2>Comprovante de aceite dos termos de uso</h2>'
    + '<table style="border-collapse:collapse;width:100%"><tr><td><b>Estabelecimento</b></td><td>' + esc(r.nome) + '</td></tr><tr><td><b>Signatário</b></td><td>' + esc(a.nome) + ' (' + esc(a.cargo || '—') + ')</td></tr><tr><td><b>CPF/CNPJ</b></td><td>' + esc(a.documento) + '</td></tr><tr><td><b>Contato</b></td><td>' + esc(a.email || '') + ' ' + esc(a.telefone || '') + '</td></tr>'
    + '<tr><td><b>Data e hora</b></td><td>' + esc(new Date(a.aceito_em).toLocaleString('pt-BR')) + '</td></tr><tr><td><b>IP</b></td><td>' + esc(a.ip || '—') + '</td></tr><tr><td><b>Aparelho</b></td><td>' + esc(a.aparelho || '') + '</td></tr><tr><td><b>Versão dos termos</b></td><td>' + esc(a.versao) + '</td></tr><tr><td><b>SHA-256 do texto</b></td><td style="word-break:break-all">' + esc(a.hash_texto) + '</td></tr></table>'
    + '<p><b>Confirmações marcadas:</b> ' + esc(Object.keys(a.marcas || {}).filter(k => a.marcas[k]).join(', ')) + '</p>'
    + '<div style="display:flex;gap:16px;align-items:center"><img src="' + esc(a.foto) + '" style="width:150px;height:150px;object-fit:cover;border-radius:8px"><img src="' + esc(a.assinatura) + '" style="width:260px;height:120px;object-fit:contain;border:1px solid #ccc"></div>'
    + '<h3 style="page-break-before:always">Texto aceito</h3>' + htmlTermos(a.texto_aceito) + '<script>setTimeout(function(){window.print()},400)<\/script></body>');
  w.document.close();
};

/* ---------- DINHEIRO ---------- */
function vDinheiro(){
  const m = S.mes, f = finMes(m), atr = atrasadas(), atrV = atr.reduce((s, c) => s + (Number(c.valor) || 0), 0), meta = Number(S.aj.meta) || 0;
  const ativos = S.lista.filter(r => r.situacao === 'ativo'), semCob = ativos.filter(r => r.valor_mensal && !S.cob.some(c => c.restaurante_id === r.id && c.tipo === 'mensalidade' && mesDe(c.competencia) === m));
  const ultimos = []; for(let k = 11; k >= 0; k--) ultimos.push(somaMes(hoje().slice(0, 7), -k));
  const ano = ultimos.map(finMes), totAno = ano.reduce((s, x) => s + x.recebido, 0), lucAno = ano.reduce((s, x) => s + x.lucro, 0);
  const ticket = ativos.length ? mrr() / ativos.length : 0, venc = S.cob.filter(c => c.vencimento && c.vencimento < hoje()), inad = venc.length ? atr.length / venc.length * 100 : 0;
  const cats = {}; f.desp.forEach(d => { cats[d.categoria] = (cats[d.categoria] || 0) + Number(d.valor); });
  T('<div class="topo"><h1>Dinheiro</h1><button class="mini" onclick="rvCsv()">⬇️ Planilha</button></div>'
   + dica('Use as setas para trocar o mês. "Gerar mensalidades" cria a cobrança do mês de todos os ativos; "Recebi" marca como pago; "Cobrar" abre o WhatsApp com a mensagem e o seu Pix.') + '<div class="mes-nav"><button onclick="rvMes(-1)">‹</button><b>' + mesNome(m) + '</b><button onclick="rvMes(1)">›</button></div>'
   + '<div class="kpis">' + kpi('Recebido', BRL(f.recebido), 'ok') + kpi('Falta receber', BRL(f.aReceber), f.aReceber ? 'aviso' : '') + kpi('Despesas', BRL(f.despTotal), f.despTotal ? 'erro' : '') + kpi('Lucro', BRL(f.lucro), f.lucro < 0 ? 'erro' : 'ok') + '</div>'
   + (meta ? '<div class="card"><div class="linha"><b>🎯 Meta</b><small>' + BRL(f.recebido) + ' de ' + BRL(meta) + ' · ' + Math.round(f.recebido / meta * 100) + '%</small></div><div class="barra grossa"><i style="width:' + Math.min(100, f.recebido / meta * 100) + '%;background:var(--ok)"></i></div></div>' : '')
   + (atr.length ? '<div class="card destaque-erro"><div class="linha"><h2>⚠️ Atrasadas (todas)</h2><b class="txt-erro">' + BRL(atrV) + '</b></div>' + atr.map(c => linhaCob(c, true)).join('') + '</div>' : '')
   + '<div class="card"><div class="linha"><h2>💵 Recebimentos do mês</h2><span><button class="mini principal" onclick="rvGerarTodas()"' + (semCob.length ? '' : ' disabled') + '>＋ Gerar mensalidades' + (semCob.length ? ' (' + semCob.length + ')' : '') + '</button> <button class="mini" onclick="rvNovaCob()">＋ Outra</button></span></div>'
   + (f.cob.length ? f.cob.slice().sort((a, b) => !!a.pago_em - !!b.pago_em || String(a.vencimento).localeCompare(String(b.vencimento))).map(c => linhaCob(c, true)).join('') : '<p class="mudo">Nenhuma cobrança vence neste mês.' + (semCob.length ? ' Toque em "Gerar mensalidades".' : '') + '</p>') + '</div>'
   + '<div class="card"><div class="linha"><h2>🧾 Suas despesas do mês</h2><span><button class="mini principal" onclick="rvDespesa()">＋ Despesa</button>' + (S.desp.some(d => d.recorrente) ? ' <button class="mini" onclick="rvRepetir()">↻ Repetir fixas</button>' : '') + '</span></div>'
   + (f.desp.length ? f.desp.map(d => '<div class="cob desp' + (d.pago ? '' : ' aberta') + '"><div class="cob-i"><b>' + esc(d.descricao) + (d.recorrente ? ' <small>↻</small>' : '') + '</b><small>' + esc(d.categoria) + ' · ' + dataBr(d.data) + (d.restaurante_id ? ' · ' + esc(nomeRest(d.restaurante_id)) : '') + (d.pago ? '' : ' · a pagar') + '</small></div><b class="cob-v">' + BRL(d.valor) + '</b><div class="cob-a">' + (d.pago ? '' : '<button class="mini principal" onclick="rvDespPaga(\'' + d.id + '\')">Paguei</button>') + '<button class="mini" onclick="rvDespesa(\'' + d.id + '\')">✏️</button><button class="mini" onclick="rvDespApagar(\'' + d.id + '\')">🗑️</button></div></div>').join('')
      + '<div class="cats">' + Object.keys(cats).sort((a, b) => cats[b] - cats[a]).map(k => '<div class="linha"><small>' + esc(k) + '</small><small><b>' + BRL(cats[k]) + '</b></small></div><div class="barra"><i style="width:' + (cats[k] / f.despTotal * 100) + '%;background:var(--erro)"></i></div>').join('') + '</div>' : '<p class="mudo">Nenhuma despesa lançada neste mês. Lance o que você gasta (Supabase Pro, domínio, IA, transporte) para ver o lucro de verdade.</p>') + '</div>'
   + '<div class="card"><h2>📈 Últimos 12 meses</h2>' + grafico(12) + '<div class="kpis tres">' + kpi('Recebido em 12 meses', BRL(totAno), 'ok') + kpi('Lucro em 12 meses', BRL(lucAno), lucAno < 0 ? 'erro' : 'ok') + kpi('Média por mês', BRL(totAno / 12), '') + '</div></div>'
   + '<div class="card"><h2>📊 Indicadores</h2><div class="kpis">' + kpi('Receita mensal fixa', BRL(mrr()), '') + kpi('Clientes ativos', ativos.length, '') + kpi('Ticket médio', BRL(ticket), '') + kpi('Inadimplência', Math.round(inad) + '%', inad > 10 ? 'erro' : '') + '</div>'
   + '<p class="mudo pequeno">Previsão do próximo mês: <b>' + BRL(mrr()) + '</b> em mensalidades' + (S.desp.some(d => d.recorrente) ? ' menos <b>' + BRL(S.desp.filter(d => d.recorrente && mesDe(d.data) === m).reduce((s, d) => s + Number(d.valor), 0)) + '</b> de despesas fixas' : '') + '.</p></div>');
}
window.rvMes = k => { S.mes = somaMes(S.mes, k); vDinheiro(); };
window.rvGerarTodas = async () => {
  const m = S.mes, alvo = S.lista.filter(r => r.situacao === 'ativo' && r.valor_mensal && !S.cob.some(c => c.restaurante_id === r.id && c.tipo === 'mensalidade' && mesDe(c.competencia) === m));
  if(!alvo.length) return aviso('Todas as mensalidades do mês já foram geradas.', 'ok');
  if(!confirm('Gerar a mensalidade de ' + mesNome(m) + ' para ' + alvo.length + ' restaurante(s)?\n\n' + alvo.map(r => r.nome + ': ' + BRL(r.valor_mensal)).join('\n'))) return;
  let ok = 0; for(const r of alvo){ try{ await rest('cobrancas', 'POST', { restaurante_id:r.id, tipo:'mensalidade', competencia:m + '-01', valor:r.valor_mensal, vencimento:m + '-' + pad(r.dia_vencimento || 10) }); await hist(r.id, 'Mensalidade gerada', m); ok++; }catch(e){} }
  aviso(ok + ' mensalidade(s) gerada(s).', 'ok'); await recarregarTudo();
};
window.rvDespesa = id => {
  const d = S.desp.find(x => x.id === id) || { data:S.mes === hoje().slice(0, 7) ? hoje() : S.mes + '-01', pago:true, categoria:'Outros' };
  janela(id ? 'Editar despesa' : 'Nova despesa', '<label for="jDs">O que foi</label><input id="jDs" value="' + esc(d.descricao || '') + '" placeholder="Ex.: Supabase Pro, domínio, gasolina">'
    + '<div class="cols"><div><label for="jV">Valor (R$)</label><input id="jV" inputmode="decimal" value="' + (d.valor != null ? String(d.valor).replace('.', ',') : '') + '"></div><div><label for="jD">Data</label><input id="jD" type="date" value="' + esc(d.data) + '"></div></div>'
    + '<label for="jC">Categoria</label><select id="jC">' + CAT_DESP.map(c => '<option' + (d.categoria === c ? ' selected' : '') + '>' + c + '</option>').join('') + '</select>'
    + '<label for="jR">É de algum restaurante? (opcional)</label><select id="jR"><option value="">Não, é geral</option>' + S.lista.map(r => '<option value="' + r.id + '"' + (d.restaurante_id === r.id ? ' selected' : '') + '>' + esc(r.nome) + '</option>').join('') + '</select>'
    + '<label class="check"><input type="checkbox" id="jP"' + (d.pago ? ' checked' : '') + '><span>Já paguei</span></label><label class="check"><input type="checkbox" id="jRc"' + (d.recorrente ? ' checked' : '') + '><span>Repete todo mês (despesa fixa)</span></label>',
    async () => { const v = num(jv('jV')); if(!jv('jDs') || v == null) throw new Error('Preencha o que foi e o valor.'); const corpo = { descricao:jv('jDs'), valor:v, data:jv('jD') || hoje(), categoria:jv('jC'), restaurante_id:jv('jR') || null, pago:$('jP').checked, recorrente:$('jRc').checked };
      if(id) await rest('despesas_revenda?id=eq.' + id, 'PATCH', corpo); else await rest('despesas_revenda', 'POST', corpo); aviso('Despesa salva.', 'ok'); await recarregarTudo(); });
};
window.rvDespPaga = async id => { try{ await rest('despesas_revenda?id=eq.' + id, 'PATCH', { pago:true }); await recarregarTudo(); }catch(e){ erro(e.message); } };
window.rvDespApagar = async id => { if(!confirm('Apagar esta despesa?')) return; try{ await req('/rest/v1/despesas_revenda?id=eq.' + id, { method:'DELETE' }); await recarregarTudo(); }catch(e){ erro(e.message); } };
window.rvRepetir = async () => {
  const m = S.mes, ant = somaMes(m, -1), fixas = S.desp.filter(d => d.recorrente && mesDe(d.data) === ant && !S.desp.some(x => x.recorrente && mesDe(x.data) === m && x.descricao === d.descricao));
  if(!fixas.length) return aviso('Nenhuma despesa fixa de ' + mesNome(ant) + ' para repetir.', 'ok');
  if(!confirm('Lançar em ' + mesNome(m) + ' as despesas fixas do mês anterior?\n\n' + fixas.map(d => d.descricao + ': ' + BRL(d.valor)).join('\n'))) return;
  for(const d of fixas){ try{ await rest('despesas_revenda', 'POST', { descricao:d.descricao, valor:d.valor, categoria:d.categoria, restaurante_id:d.restaurante_id, recorrente:true, pago:false, data:m + d.data.slice(7) }); }catch(e){} }
  aviso('Despesas fixas lançadas.', 'ok'); await recarregarTudo();
};
window.rvCsv = () => {
  const q = v => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"', L = [['Tipo','Data','Restaurante','Descrição','Categoria/forma','Valor','Situação'].map(q).join(';')];
  S.cob.forEach(c => L.push(['Receita', c.pago_em || c.vencimento, nomeRest(c.restaurante_id), c.tipo === 'mensalidade' ? 'Mensalidade ' + mesDe(c.competencia) : (c.descricao || c.tipo), c.forma || '', String(c.pago_em ? pagoValor(c) : c.valor).replace('.', ','), c.pago_em ? 'Recebido' : (c.vencimento < hoje() ? 'Atrasado' : 'A receber')].map(q).join(';')));
  S.desp.forEach(d => L.push(['Despesa', d.data, d.restaurante_id ? nomeRest(d.restaurante_id) : '', d.descricao, d.categoria, String(d.valor).replace('.', ','), d.pago ? 'Pago' : 'A pagar'].map(q).join(';')));
  baixar('financeiro-revenda-' + hoje() + '.csv', '﻿' + L.join('\n'), 'text/csv'); aviso('Planilha baixada (abre no Excel ou Google Planilhas).', 'ok');
};

/* ---------- VENDAS (propostas) ---------- */
function vVendas(){
  const F = { abertas:'Em aberto', novo:'Novos', conversando:'Conversando', proposta:'Proposta enviada', fechado:'Fechados', perdido:'Perdidos' };
  const L = S.prop.filter(p => S.filtroProp === 'abertas' ? !['fechado','perdido'].includes(p.status) : p.status === S.filtroProp);
  const abertas = S.prop.filter(p => !['fechado','perdido'].includes(p.status)), potencial = abertas.reduce((s, p) => s + (Number(p.valor_mensal) || 0), 0), fech = S.prop.filter(p => p.status === 'fechado').length, conv = S.prop.length ? Math.round(fech / S.prop.length * 100) : 0;
  T('<div class="topo"><button class="mini" onclick="rvIr(\'mais\')">← Mais</button><button class="principal" onclick="rvProp()">＋ Nova proposta</button></div><h1>Vendas</h1>'
   + '<div class="kpis tres">' + kpi('Em negociação', abertas.length, '') + kpi('Potencial por mês', BRL(potencial), 'aviso') + kpi('Conversão', conv + '%', '') + '</div>'
   + '<div class="chips">' + Object.keys(F).map(k => '<button class="chip ' + (S.filtroProp === k ? 'on' : '') + '" onclick="rvFiltroProp(\'' + k + '\')">' + F[k] + ' <small>' + (k === 'abertas' ? abertas.length : S.prop.filter(p => p.status === k).length) + '</small></button>').join('') + '</div>'
   + (L.length ? L.map(p => { const atrasa = p.proxima_acao && p.proxima_acao <= hoje() && !['fechado','perdido'].includes(p.status);
      return '<div class="card"><div class="linha"><b>' + esc(p.nome) + '</b><span class="selo ' + (p.status === 'fechado' ? 'ativo' : p.status === 'perdido' ? 'encerrado' : 'teste') + '">' + ST_PROP[p.status] + '</span></div>'
       + '<small class="mudo">' + esc([p.contato_nome, p.cidade, p.origem].filter(Boolean).join(' · ')) + '</small>'
       + '<p class="pequeno">' + (p.valor_mensal ? BRL(p.valor_mensal) + '/mês' : 'Sem valor') + (p.taxa_implantacao ? ' + ' + BRL(p.taxa_implantacao) + ' implantação' : '') + (p.plano ? ' · ' + esc(p.plano) : '') + '</p>'
       + (p.proxima_acao ? '<p class="pequeno ' + (atrasa ? 'txt-erro' : 'mudo') + '">📅 Retornar em ' + dataBr(p.proxima_acao) + (atrasa ? ' (hoje ou atrasado)' : '') + '</p>' : '')
       + (p.observacoes ? '<p class="pequeno mudo">' + esc(p.observacoes) + '</p>' : '')
       + '<div class="linha" style="justify-content:flex-start">' + (p.telefone ? '<a class="btn mini" target="_blank" rel="noopener" href="' + esc(waLink(p.telefone)) + '">💬 WhatsApp</a>' : '') + '<button class="mini" onclick="rvPropTexto(\'' + p.id + '\')">📋 Texto da proposta</button><button class="mini" onclick="rvProp(\'' + p.id + '\')">✏️ Editar</button>'
       + (p.restaurante_id ? '<button class="mini" onclick="rvAbrir(\'' + p.restaurante_id + '\')">Abrir restaurante ›</button>' : p.status !== 'perdido' ? '<button class="mini principal" onclick="rvPropFechar(\'' + p.id + '\')">🎉 Fechou! Criar restaurante</button>' : '') + '</div></div>'; }).join('')
     : '<div class="card vazio">Nenhuma proposta aqui. Anote cada restaurante com quem você conversar para não perder nenhum.</div>'));
}
window.rvFiltroProp = f => { S.filtroProp = f; vVendas(); };
window.rvProp = id => {
  const p = S.prop.find(x => x.id === id) || { status:'novo', modulos:{} }, planos = S.aj.planos || [];
  janela(id ? 'Editar proposta' : 'Nova proposta', '<label for="jN">Restaurante</label><input id="jN" value="' + esc(p.nome || '') + '"><div class="cols"><div><label for="jCn">Contato</label><input id="jCn" value="' + esc(p.contato_nome || '') + '"></div><div><label for="jT">WhatsApp</label><input id="jT" type="tel" value="' + esc(p.telefone || '') + '"></div></div>'
    + '<div class="cols"><div><label for="jCi">Cidade</label><input id="jCi" value="' + esc(p.cidade || '') + '"></div><div><label for="jO">Como conheceu</label><input id="jO" value="' + esc(p.origem || '') + '" placeholder="Indicação, Instagram…"></div></div>'
    + '<label for="jS">Situação</label><select id="jS">' + Object.keys(ST_PROP).map(k => '<option value="' + k + '"' + (p.status === k ? ' selected' : '') + '>' + ST_PROP[k] + '</option>').join('') + '</select>'
    + (planos.length ? '<label for="jPl">Plano</label><select id="jPl" onchange="rvPropPlano(this.value)"><option value="">—</option>' + planos.map((x, i) => '<option value="' + i + '"' + (p.plano === x.nome ? ' selected' : '') + '>' + esc(x.nome) + ' · ' + BRL(x.valor) + '</option>').join('') + '</select>' : '')
    + '<div class="cols"><div><label for="jV">Mensalidade (R$)</label><input id="jV" inputmode="decimal" value="' + (p.valor_mensal != null ? String(p.valor_mensal).replace('.', ',') : '') + '"></div><div><label for="jTx">Implantação (R$)</label><input id="jTx" inputmode="decimal" value="' + (p.taxa_implantacao != null ? String(p.taxa_implantacao).replace('.', ',') : '') + '"></div></div>'
    + '<label for="jPa">Retornar em</label><input id="jPa" type="date" value="' + esc(p.proxima_acao || '') + '"><label for="jOb">Anotações</label><textarea id="jOb">' + esc(p.observacoes || '') + '</textarea>',
    async () => { if(!jv('jN')) throw new Error('Escreva o nome do restaurante.'); const pl = planos[jv('jPl')];
      const corpo = { nome:jv('jN'), contato_nome:jv('jCn') || null, telefone:jv('jT') || null, cidade:jv('jCi') || null, origem:jv('jO') || null, status:jv('jS'), plano:pl ? pl.nome : (p.plano || null), modulos:pl ? (pl.modulos || {}) : (p.modulos || {}), valor_mensal:num(jv('jV')), taxa_implantacao:num(jv('jTx')), proxima_acao:jv('jPa') || null, observacoes:jv('jOb') || null, atualizado_em:new Date().toISOString() };
      if(id) await rest('propostas?id=eq.' + id, 'PATCH', corpo); else await rest('propostas', 'POST', corpo); aviso('Proposta salva.', 'ok'); await recarregarTudo(); });
};
window.rvPropPlano = i => { const p = (S.aj.planos || [])[i]; if(!p) return; $('jV').value = String(p.valor).replace('.', ','); $('jTx').value = p.implantacao ? String(p.implantacao).replace('.', ',') : ''; };
window.rvPropTexto = async id => {
  const p = S.prop.find(x => x.id === id), a = S.aj, mods = MODULOS.filter(m => (p.modulos || {})[m.id]).map(m => '• ' + m.nome);
  const t = 'Olá' + (p.contato_nome ? ' ' + p.contato_nome.split(' ')[0] : '') + '! Segue a proposta do sistema para o ' + p.nome + ':\n\n'
    + '✅ Cardápio digital com pedidos pelo celular\n✅ Caixa, pedidos, cozinha e entregas\n✅ Clientes, fidelidade e cupons\n✅ Estoque, custos e relatórios\n✅ App da equipe e avisos no celular\n✅ Backup automático e suporte\n'
    + (mods.length ? '\nMódulos incluídos:\n' + mods.join('\n') + '\n' : '') + (p.plano ? '\nPlano: ' + p.plano : '') + (p.valor_mensal ? '\nMensalidade: ' + BRL(p.valor_mensal) : '') + (p.taxa_implantacao ? '\nImplantação (uma vez): ' + BRL(p.taxa_implantacao) : '')
    + '\n\nO sistema fica com o nome, as cores e a logo do restaurante.' + (a.whatsapp ? '\nQualquer dúvida: ' + a.whatsapp : '');
  if(await copiarTxt(t)) aviso('Proposta copiada. Cole no WhatsApp do cliente.', 'ok');
};
window.rvPropFechar = id => { const p = S.prop.find(x => x.id === id); rvNovo(p); };

/* ---------- USUÁRIOS DO PAINEL (conector: usr_*) ---------- */
async function vUsuarios(){
  T('<h1>Usuários do painel</h1><div class="card"><small class="mudo">Carregando…</small></div>');
  let a; try{ a = await chamarConector({ acao:'usr_listar' }); if(!a.ok) throw new Error(a.erro || 'Não consegui carregar.'); }catch(e){ return T('<h1>Usuários do painel</h1><div class="card">' + conLinha(false, esc(e.message)) + '</div>'); }
  const dt = x => x ? new Date(x).toLocaleDateString('pt-BR') : '—';
  T('<h1>Usuários do painel</h1><div class="card"><h2>🙋 Meus dados</h2><p class="mudo pequeno">Seu nome e telefone (aparecem na lista de usuários) ou o seu e-mail e a sua senha de acesso.</p><p class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvUsrPerfil()">✏️ Meu nome e telefone</button> <button class="mini" onclick="rvUsrEu()">🔑 E-mail e senha</button></p><div id="usr_eu_res"></div></div>' + avErroCard_()
   + '<div class="card"><h2>👥 Quem entra no painel</h2><p class="mudo pequeno">' + (a.souDono ? 'Você é o dono: só você cria, troca a senha e remove os outros. Cada um entra com o próprio e-mail e vê tudo.' : 'Só o dono cria e remove usuários.') + '</p>'
   + a.usuarios.map(u => '<div class="linha mapa-l"><span><b>' + esc(u.nome || u.email) + '</b> <small class="mudo">' + (u.dono ? 'dono' : 'usuário') + (u.funcao ? ' · ' + esc(u.funcao) : '') + (u.eu ? ' · você' : '') + '</small><br><small class="mudo">' + (u.nome ? esc(u.email) + ' · ' : '') + (u.telefone ? '📞 ' + esc(foneBonito_(u.telefone)) + ' · ' : '<i>sem telefone</i> · ') + 'último acesso ' + dt(u.ultimo) + '</small></span>'
      + ((a.souDono || u.eu) ? '<span><button class="mini" onclick="rvUsrPerfil(\'' + u.id + '\')">✏️ Dados</button> </span>' : '')
      + (a.souDono && !u.eu ? '<span><button class="mini" onclick="rvUsrSenha(\'' + u.id + '\')">🔑 Senha</button> <button class="mini" onclick="rvUsrRemover(\'' + u.id + '\')">🗑️ Remover</button></span>' : '') + '</div>').join('')
   + (a.souDono ? '<p class="linha" style="justify-content:flex-start"><button class="mini" onclick="rvUsrCriar()">➕ Novo usuário</button></p>' : '') + '<div id="usr_res"></div></div>');
}
const usrMsg = (id, h) => { const b = $(id); if(b) b.innerHTML = h; };
const foneBonito_ = t => { const d = String(t).replace(/\D/g, ''); return d.length === 11 ? '(' + d.slice(0, 2) + ') ' + d.slice(2, 7) + '-' + d.slice(7) : d.length === 10 ? '(' + d.slice(0, 2) + ') ' + d.slice(2, 6) + '-' + d.slice(6) : t; };
window.rvUsrPerfil = async id => {
  let a; try{ a = await chamarConector({ acao:'usr_listar' }); }catch(e){ return erro(e.message); }
  const u = a.usuarios.find(x => id ? x.id === id : x.eu); if(!u) return;
  const nome = prompt('Nome de ' + (u.eu ? 'você' : u.email) + ':', u.nome || ''); if(nome === null) return;
  const telefone = prompt('Telefone / WhatsApp com DDD (só números):', u.telefone || ''); if(telefone === null) return;
  const funcao = prompt('Função (ex.: dono, suporte, vendas) — pode deixar em branco:', u.funcao || ''); if(funcao === null) return;
  try{ const r = await chamarConector({ acao:'usr_perfil', id:u.id, nome, telefone, funcao }); if(!r.ok) throw new Error(r.erro || 'Não salvou.'); aviso('Dados salvos.', 'ok'); vUsuarios(); }catch(e){ erro(e.message); }
};
window.rvUsrCriar = async () => {
  const email = prompt('E-mail do novo usuário:'); if(!email) return; const nome = prompt('Nome dele:') || '', telefone = prompt('Telefone / WhatsApp com DDD (pode deixar em branco):') || ''; const senha = prompt('Senha para ele (mínimo 8, com letras e números):'); if(!senha) return;
  try{ const a = await chamarConector({ acao:'usr_criar', email, nome, telefone, senha }); if(!a.ok) throw new Error(a.erro || 'Não criou.'); aviso(a.message || 'Criado.', 'ok'); vUsuarios(); }catch(e){ usrMsg('usr_res', conLinha(false, esc(e.message))); }
};
window.rvUsrSenha = async id => {
  const senha = prompt('Nova senha para esse usuário (mínimo 8, com letras e números):'); if(!senha) return;
  try{ const a = await chamarConector({ acao:'usr_senha', id, senha }); if(!a.ok) throw new Error(a.erro || 'Não trocou.'); aviso(a.message || 'Senha trocada.', 'ok'); }catch(e){ usrMsg('usr_res', conLinha(false, esc(e.message))); }
};
window.rvUsrRemover = async id => {
  if(!confirm('Remover esse usuário do painel? Ele não poderá mais entrar.')) return;
  try{ const a = await chamarConector({ acao:'usr_remover', id }); if(!a.ok) throw new Error(a.erro || 'Não removeu.'); aviso('Removido.', 'ok'); vUsuarios(); }catch(e){ usrMsg('usr_res', conLinha(false, esc(e.message))); }
};
window.rvUsrEu = async () => {
  const atual = prompt('Sua senha ATUAL:'); if(!atual) return;
  const email = prompt('Novo e-mail (deixe em branco para manter o atual):') || '', senha = prompt('Nova senha (deixe em branco para manter a atual; mínimo 8, com letras e números):') || '';
  if(!email && !senha) return;
  try{ const a = await chamarConector({ acao:'usr_eu', atual, email, senha }); if(!a.ok) throw new Error(a.erro || 'Não mudou.'); aviso(a.message || 'Pronto.', 'ok'); if(a.sair) setTimeout(() => rvSair(), 1200); }catch(e){ usrMsg('usr_eu_res', conLinha(false, esc(e.message))); }
};
/* ---------- MAIS / AJUSTES / GUIA ---------- */
const rvLinkPainel = () => location.origin + location.pathname.replace(/[^\/]*$/, '');
async function rvCopiarLink(){ try{ await navigator.clipboard.writeText(rvLinkPainel()); aviso('Link copiado.'); }catch(e){ try{ const t = document.getElementById('rvLink'); const r = document.createRange(); r.selectNodeContents(t); const se = getSelection(); se.removeAllRanges(); se.addRange(r); aviso('Segure sobre o link selecionado e escolha Copiar.'); }catch(e2){ aviso('Não consegui copiar. Selecione o link e copie.'); } } }
async function rvCompartilhar(){ const u = rvLinkPainel(); try{ if(navigator.share){ await navigator.share({ title:'Painel de Revenda', text:'Painel de Revenda', url:u }); return; } }catch(e){ if(e && e.name === 'AbortError') return; } rvCopiarLink(); }
function vMais(){
  const it = [['assistente','✨','Assistente (IA)','Chaves das IAs, teste e leitura dos restaurantes'],['conectores','🔌','Conectores','Ligar o painel ao GitHub e ao Supabase de cada restaurante'],['usuarios','👤','Usuários do painel','Seus dados de acesso e quem mais pode entrar'],['vendas','🤝','Vendas e propostas','Restaurantes com quem você está conversando'],['guia','📘','Como criar um restaurante','O caminho completo, explicado do começo'],['ajustes','⚙️','Meus dados, Pix e planos','Seus dados nos termos, chave Pix, mensagem de cobrança, planos e meta']];
  T('<h1>Mais</h1>' + it.map(x => '<button class="alerta n0" onclick="rvIr(\'' + x[0] + '\')"><span class="ic">' + x[1] + '</span><span><b>' + x[2] + '</b><small>' + x[3] + '</small></span><span class="seta">›</span></button>').join('')
   + '<div class="card" id="painelSaude"><h2>🩺 Saúde do painel</h2><small class="mudo">Conferindo o uso do plano grátis…</small></div>'
   + '<div class="card"><h2>🔗 Link do painel</h2><p class="mudo pequeno">Este é o endereço do painel. Para entrar é preciso ter login, então só quem você cadastrar consegue usar.</p><p><code id="rvLink" style="word-break:break-all;">' + esc(rvLinkPainel()) + '</code></p><p><button class="principal" onclick="rvCompartilhar()">📤 Compartilhar</button> <button class="mini" onclick="rvCopiarLink()">Copiar link</button></p></div>'
   + '<div class="card"><small class="mudo">Versão do painel: ' + ((document.querySelector('script[src*="revenda.js"]') || {}).src || '').replace(/^.*[?]v=/, '') + ' · Conectado como ' + esc((S.sess && S.sess.email) || '') + '</small><p><button onclick="rvSair()">Sair do painel</button></p></div>');
  carregarSaudePainel_();
}
function vAjustes(){
  const a = S.aj, t = S.termos || {}, planos = a.planos || [], ba = a.bloqueio_auto || {}, au = a.atualizar_auto || {};
  T('<div class="topo"><button class="mini" onclick="rvIr(\'mais\')">← Mais</button></div><h1>Meus dados, Pix e planos</h1>'
   + '<div class="card"><h2>👤 Seus dados nos termos de uso</h2><p class="mudo pequeno">Aparecem no contrato que o cliente aceita (valem para todos os restaurantes).</p>'
   + '<label for="tNome">Seu nome ou razão social</label><input id="tNome" value="' + esc(t.fornecedor_nome || '') + '" maxlength="120"><label for="tDoc">Seu CPF ou CNPJ</label><input id="tDoc" value="' + esc(t.fornecedor_doc || '') + '" maxlength="30">'
   + '<label for="tForo">Cidade/UF do foro (ex.: Jaboticabal/SP)</label><input id="tForo" value="' + esc(t.foro || '') + '" maxlength="80"><label for="tCont">Seu contato (e-mail ou WhatsApp)</label><input id="tCont" value="' + esc(t.contato || '') + '" maxlength="120">'
   + '<p><button class="principal" onclick="rvSalvarTermos()">💾 Salvar</button> <button class="mini" onclick="rvVerTermos()">Ver o texto dos termos</button></p><small class="mudo">Versão dos termos: ' + esc(t.versao || '—') + '. Não substitui a revisão de um advogado.</small></div>'
   + '<div class="card"><h2>💳 Recebimento e cobrança</h2><div class="cols"><div><label for="aPix">Sua chave Pix</label><input id="aPix" value="' + esc(a.pix || '') + '"></div><div><label for="aPn">Nome que aparece no Pix</label><input id="aPn" value="' + esc(a.pix_nome || '') + '"></div></div><label for="aPc">Sua cidade (vai no Pix copia e cola)</label><input id="aPc" maxlength="40" value="' + esc(a.pix_cidade || '') + '" placeholder="Ex.: Jaboticabal"><small class="mudo">Com a chave cadastrada, cada cobrança ganha um Pix copia e cola com o valor certo (botão 📋 Pix e na mensagem do WhatsApp). Telefone como chave: escreva com DDD entre parênteses, ex.: (16) 99999-9999.</small>'
   + '<div class="cols"><div><label for="aWa">Seu WhatsApp (vai nas propostas)</label><input id="aWa" type="tel" value="' + esc(a.whatsapp || '') + '"></div><div><label for="aDv">Dia de vencimento padrão</label><input id="aDv" type="number" min="1" max="28" value="' + esc(a.dia_padrao || 10) + '"></div></div>'
   + '<label for="aMeta">Meta de recebimento por mês (R$)</label><input id="aMeta" inputmode="decimal" value="' + esc(a.meta || '') + '">'
   + '<label for="aMsg">Mensagem de cobrança (WhatsApp)</label><textarea id="aMsg" rows="5" placeholder="Deixe em branco para usar a mensagem padrão">' + esc(a.msg_cobranca || '') + '</textarea><small class="mudo">Pode usar: {contato} {restaurante} {tipo} {valor} {vencimento} {pix}</small>'
   + '<p><button class="principal" onclick="rvSalvarAj()">💾 Salvar</button></p></div>'
   + '<div class="card"><h2>🤖 Automáticos</h2><p class="mudo pequeno">O painel trabalha sozinho no servidor, com o painel fechado. Cada restaurante ainda pode ser tirado do automático na tela dele.</p>'
   + '<label for="baOn"><b>🔒 Bloqueio automático por falta de pagamento</b></label><select id="baOn"><option value="1"' + (ba.ligado !== false ? ' selected' : '') + '>Ligado</option><option value="0"' + (ba.ligado === false ? ' selected' : '') + '>Desligado (só bloqueio manual)</option></select>'
   + '<div class="cols"><div><label for="baDias">Bloquear depois de quantos dias do vencimento</label><input id="baDias" type="number" min="1" max="60" value="' + esc(ba.dias || 1) + '"></div>'
   + '<div><label for="baProm">1ª promessa de pagamento</label><select id="baProm"><option value="1"' + (ba.promessa_auto !== false ? ' selected' : '') + '>Libera na hora (1 vez por restaurante)</option><option value="0"' + (ba.promessa_auto === false ? ' selected' : '') + '>Sempre espera eu aprovar</option></select></div></div>'
   + '<label for="baPrazo">Promessa de pagamento: até quantos dias à frente o cliente pode escolher (1 a 15)</label><input id="baPrazo" type="number" min="1" max="15" value="' + esc(ba.promessa_dias || 15) + '">'
   + '<label for="baMsg">Mensagem que a equipe vê quando bloqueia sozinho (opcional)</label><textarea id="baMsg" rows="2" maxlength="200" placeholder="Acesso suspenso por mensalidade em aberto. Fale com o fornecedor do sistema.">' + esc(ba.mensagem || '') + '</textarea>'
   + '<small class="mudo">Só vale para restaurante com mensalidade preenchida e fora de implantação. Se você liberar na mão, o automático não bloqueia de novo a mesma mensalidade. Ao registrar o pagamento de uma mensalidade, o restaurante bloqueado (automático ou manual) é liberado na hora, se não restar outra mensalidade vencida.</small>'
   + '<label for="auOn" style="margin-top:12px"><b>🔄 Atualização automática (banco, funções e site)</b></label><select id="auOn"><option value="1"' + (au.ligado !== false ? ' selected' : '') + '>Ligada</option><option value="0"' + (au.ligado === false ? ' selected' : '') + '>Desligada (eu atualizo à mão)</option></select>'
   + '<small class="mudo">De 30 em 30 minutos. Nunca mexe no que é do restaurante (chaves, Google, Drive, planilhas, dados). Se algo não subir, aparece nos Alertas e chega aviso no celular.</small>'
   + '<p><button class="principal" onclick="rvSalvarAuto()">💾 Salvar</button> <button class="mini" onclick="rvAtualizarAgora()">▶ Atualizar agora</button></p></div>'
   + '<div class="card"><div class="linha"><h2>📦 Planos e preços</h2><button class="mini principal" onclick="rvPlano()">＋ Plano</button></div><p class="mudo pequeno">Escolha com um toque ao criar restaurante ou proposta.</p>'
   + (planos.length ? planos.map((p, i) => '<div class="cob"><div class="cob-i"><b>' + esc(p.nome) + '</b><small>' + MODULOS.filter(m => (p.modulos || {})[m.id]).map(m => m.nome).join(', ') + '</small></div><b class="cob-v">' + BRL(p.valor) + '</b><div class="cob-a"><button class="mini" onclick="rvPlano(' + i + ')">✏️</button><button class="mini" onclick="rvPlanoApagar(' + i + ')">🗑️</button></div></div>').join('') : '<p class="mudo">Nenhum plano ainda.</p>') + '</div>');
}

window.rvSalvarAuto = async () => {
  const dias = Math.min(60, Math.max(1, parseInt(jv('baDias'), 10) || 1));
  await salvarAjustes({ bloqueio_auto:{ ligado:jv('baOn') !== '0', dias, promessa_auto:jv('baProm') !== '0', promessa_dias:Math.min(15, Math.max(1, parseInt(jv('baPrazo'), 10) || 15)), mensagem:jv('baMsg') }, atualizar_auto:{ ligado:jv('auOn') !== '0' } }, 'Automáticos salvos.');
};
async function chamarAtualizador_(corpo){
  if(S.sess && Date.now() > S.sess.exp && !await renovar()) throw new Error('Sua sessão expirou. Entre de novo.');
  const c = new AbortController(), t = setTimeout(() => c.abort(), 140000);
  try{ const r = await fetch(URL_ + '/functions/v1/atualizador', { method:'POST', signal:c.signal, headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:JSON.stringify(corpo || {}) });
    if(r.status === 404) throw new Error('A função "atualizador" ainda não foi publicada no servidor do painel.');
    const j = await r.json().catch(() => null); if(!j || !j.ok) throw new Error((j && j.erro) || 'O atualizador não respondeu.'); return j;
  } finally { clearTimeout(t); }
}
window.rvAtualizarAgora = async () => {
  aviso('Atualizando… pode levar uns minutos.', 'ok');
  try{ const j = await chamarAtualizador_({ forcar:true }); S.atz = await tenta(() => rest('atualizador_estado?select=*'), []);
    const ruins = (j.restaurantes || []).filter(x => [x.banco, x.site, x.funcoes].some(v => v === 'erro' || v === 'revisao')).length;
    aviso(j.desligado ? 'A atualização automática está desligada.' : ruins ? ruins + ' restaurante(s) com atualização que não subiu (veja os Alertas).' : 'Tudo em dia.', ruins ? 'erro' : 'ok');
  }catch(e){ erro(e.message); }
  desenhar();
};
window.rvAtzTentar = async id => {
  const r = S.lista.find(x => x.id === id) || {};
  if(!confirm('Tentar atualizar "' + (r.nome || '') + '" de novo agora?\n\nSe continuar falhando, o motivo aparece nos Alertas e dá para fazer à mão em Conectores.')) return;
  aviso('Tentando…', 'ok');
  try{ await chamarAtualizador_({ restaurante_id:id }); S.atz = await tenta(() => rest('atualizador_estado?select=*'), []); const ainda = S.atz.filter(x => x.restaurante_id === id).length; aviso(ainda ? 'Ainda não subiu. Veja o motivo nos Alertas.' : 'Atualizado ✓', ainda ? 'erro' : 'ok'); }catch(e){ erro(e.message); }
  desenhar();
};
/* chave por restaurante: entra ou sai do bloqueio automático / da atualização automática */
window.rvTogRest = async (campo, on, id) => {
  const r = S.lista.find(z => z.id === (id || (S.rest || {}).id)); if(!r) return;
  try{ await rest('restaurantes?id=eq.' + r.id, 'PATCH', { [campo]:on }); r[campo] = on; const x = S.lista.find(z => z.id === r.id); if(x) x[campo] = on;
    await hist(r.id, (campo === 'bloqueio_auto' ? 'Bloqueio automático ' : 'Atualização automática ') + (on ? 'LIGADO' : 'DESLIGADO') + ' neste restaurante', ''); aviso(on ? 'Ligado.' : 'Desligado.', 'ok'); }catch(e){ erro(e.message); }
  desenhar();
};
const togHtml_ = (campo, titulo, r) => '<label class="check"><input type="checkbox" ' + (r[campo] !== false ? 'checked ' : '') + 'onchange="rvTogRest(\'' + campo + '\',this.checked,\'' + r.id + '\')"><span>' + titulo + '</span></label>';
/* SINCRONIA COM O SERVIDOR: leva para o banco do painel o código das atualizações numeradas e o carregador oficial, para o atualizador trabalhar sozinho com o painel fechado.
   Guarda também o hash do carregador anterior como "antigo" (é assim que o servidor sabe que pode trocá-lo sem pisar em algo personalizado). */
async function sincronizarServidor_(){
  if(typeof window.cdObter !== 'function') return;
  try{
    const ja = new Set((await rest('atualizacoes_sql?select=id') || []).map(x => x.id));
    for(const u of UPDS){ if(ja.has(u[0])) continue; try{ const sql = await window.cdObter(u[0]); await rest('atualizacoes_sql', 'POST', { id:u[0], rotulo:u[1], sql, revisada:true }, { Prefer:'resolution=merge-duplicates,return=minimal' }); }catch(e){ /* tenta na próxima abertura */ } }
    for(const n of ['index.html']){
      const x = await fetch('leve/' + n + '?t=' + Date.now(), { cache:'no-store' }); if(!x.ok) continue;
      const txt = await x.text(), hNovo = await sha256_(Array.from(new TextEncoder().encode(txt), c => String.fromCharCode(c)).join(''));
      const at = (await rest('site_modelo?caminho=eq.' + n + '&select=conteudo,antigos') || [])[0];
      let antigos = at ? (at.antigos || []).slice() : LOADER_ANTIGOS.slice();
      if(at){ const hAt = await sha256_(Array.from(new TextEncoder().encode(at.conteudo), c => String.fromCharCode(c)).join('')); if(hAt === hNovo) continue; if(!antigos.includes(hAt)) antigos.push(hAt); }
      await rest('site_modelo', 'POST', { caminho:n, conteudo:txt, antigos, atualizado_em:new Date().toISOString() }, { Prefer:'resolution=merge-duplicates,return=minimal' });
    }
  }catch(e){ /* sem a tabela ainda ou sem rede: o servidor continua com o que já tem */ }
}

/* SAÚDE DO PRÓPRIO PAINEL: uso do plano grátis do Supabase do painel + arquivamento mensal do que é antigo (vai para o Storage antes de sair do banco) */
async function carregarSaudePainel_(){
  const box = $('painelSaude'); if(!box) return;
  try{
    const d = await rpc('painel_saude'); if(!d || d.banco_bytes == null) throw new Error('sem dados');
    const pct = (a, b) => Math.round(a / b * 1000) / 10, ua = d.ultimo_arquivo;
    box.innerHTML = '<h2>🩺 Saúde do painel</h2>'
     + barraUso({ tit:'Banco do painel', uso:fmtBytes_(d.banco_bytes), lim:'500 MB', pct:pct(d.banco_bytes, d.banco_limite) })
     + barraUso({ tit:'Arquivo (Storage)', uso:fmtBytes_(d.storage_bytes), lim:'1 GB', pct:pct(d.storage_bytes, d.storage_limite) })
     + (d.cron_falhas ? conLinha(false, d.cron_falhas + ' tarefa(s) agendada(s) falharam nas últimas 24 h') : conLinha(true, 'Tarefas agendadas em dia'))
     + (d.saida_erros >= 5 ? conLinha(false, d.saida_erros + ' chamadas a outros serviços com erro nas últimas 24 h') : '')
     + '<small class="mudo">Conferido de 6 em 6 horas; chega aviso no celular acima de 70%. O que é antigo (histórico, registro do conector e erros resolvidos) vai sozinho para o Storage 1 vez por mês' + (ua ? ' · último: ' + esc(new Date(ua.em).toLocaleDateString('pt-BR')) + ' (' + esc(ua.tabela) + ', ' + ua.linhas + ' linhas)' : '') + '. Cobranças e contratos nunca são arquivados.</small>'
     + '<p><button class="mini" onclick="rvArquivarPainel()">🗄️ Arquivar agora</button></p>';
  }catch(e){ box.innerHTML = '<h2>🩺 Saúde do painel</h2>' + conLinha(false, 'Não consegui ler (' + esc(e.message) + '). Falta aplicar o código 025 no banco do painel.'); }
}
window.rvArquivarPainel = async () => {
  aviso('Arquivando…', 'ok');
  try{ if(S.sess && Date.now() > S.sess.exp && !await renovar()) throw new Error('Sua sessão expirou. Entre de novo.');
    const r = await fetch(URL_ + '/functions/v1/arquivar-painel', { method:'POST', headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:'{}' });
    const j = await r.json().catch(() => null); if(!j) throw new Error('A função "arquivar-painel" não respondeu.');
    if(!j.ok) throw new Error(j.erro || 'Não arquivou.');
    const n = (j.tabelas || []).reduce((t, x) => t + x.arquivadas, 0); aviso(n ? n + ' registro(s) antigo(s) foram para o Storage.' : 'Nada antigo para arquivar ainda.', 'ok');
  }catch(e){ erro(e.message); }
  carregarSaudePainel_();
};
window.rvSalvarTermos = async () => {
  const d = { fornecedor_nome:jv('tNome'), fornecedor_doc:jv('tDoc'), foro:jv('tForo'), contato:jv('tCont'), atualizado_em:new Date().toISOString() };
  try{ await rest('termos_uso?id=eq.true', 'PATCH', d); Object.assign(S.termos = S.termos || {}, d); aviso('Dados salvos.', 'ok'); }catch(e){ erro(e.message); }
};
window.rvSalvarAj = () => salvarAjustes({ pix:jv('aPix'), pix_nome:jv('aPn'), pix_cidade:jv('aPc'), whatsapp:jv('aWa'), dia_padrao:Math.min(28, Math.max(1, parseInt(jv('aDv'), 10) || 10)), meta:num(jv('aMeta')), msg_cobranca:jv('aMsg') });
window.rvPlano = i => {
  const p = (S.aj.planos || [])[i] || { modulos:{} }; MODULOS.forEach(m => { if(p.modulos[m.id] == null && i == null) p.modulos[m.id] = m.pad; });
  janela(i != null ? 'Editar plano' : 'Novo plano', '<label for="jN">Nome do plano</label><input id="jN" value="' + esc(p.nome || '') + '" placeholder="Ex.: Básico, Completo"><div class="cols"><div><label for="jV">Mensalidade (R$)</label><input id="jV" inputmode="decimal" value="' + (p.valor != null ? String(p.valor).replace('.', ',') : '') + '"></div><div><label for="jTx">Implantação (R$)</label><input id="jTx" inputmode="decimal" value="' + (p.implantacao != null ? String(p.implantacao).replace('.', ',') : '') + '"></div></div>'
    + '<p class="pequeno"><b>Módulos incluídos</b></p>' + MODULOS.map(m => '<label class="check"><input type="checkbox" class="jMod" value="' + m.id + '"' + (p.modulos[m.id] ? ' checked' : '') + '><span>' + esc(m.nome) + '</span></label>').join(''),
    async () => { const v = num(jv('jV')); if(!jv('jN') || v == null) throw new Error('Preencha o nome e a mensalidade.'); const mod = {}; document.querySelectorAll('.jMod').forEach(c => { mod[c.value] = c.checked; });
      const L = (S.aj.planos || []).slice(), novo = { nome:jv('jN'), valor:v, implantacao:num(jv('jTx')), modulos:mod }; if(i != null) L[i] = novo; else L.push(novo); if(await salvarAjustes({ planos:L }, 'Plano salvo.')) vAjustes(); });
};
window.rvPlanoApagar = async i => { if(!confirm('Apagar este plano?')) return; const L = (S.aj.planos || []).slice(); L.splice(i, 1); if(await salvarAjustes({ planos:L }, 'Plano apagado.')) vAjustes(); };
function vGuia(){
  const tot = ETAPAS.reduce((s, e) => s + (parseInt(e.tempo, 10) || 0), 0);
  T('<div class="topo"><button class="mini" onclick="rvIr(\'mais\')">← Mais</button></div><h1>Como criar um restaurante</h1>'
   + '<div class="card"><p>O painel te leva <b>um passo de cada vez</b>. Você só precisa ler e fazer o que está escrito. Leva umas <b>' + Math.round(tot / 60 * 10) / 10 + ' horas</b> no total, e dá para parar e continuar depois: o painel lembra onde você parou.</p>'
   + '<p class="mudo pequeno">Em cada etapa tem um botão "Prefere que o Claude faça?": copie o pedido e cole na conversa com ele. Mas dá para fazer tudo sozinho.</p></div>'
   + '<h2 class="sec-t">1. Contas que você vai criar</h2><div class="card contas">' + CONTAS.map(c => '<div><b>' + esc(c[0]) + '</b><small>' + esc(c[1]) + '</small></div>').join('') + '</div>'
   + '<h2 class="sec-t">2. O caminho</h2>' + FASES.map((f, k) => '<div class="card"><h3>' + (k + 1) + '. ' + f[0] + '</h3>' + f[1].map(id => { const e = ETAPAS.find(x => x.id === id); return '<div class="guia-e"><b>' + esc(e.titulo) + '</b> <small class="mudo">· ' + esc(e.tempo) + (e.opcional ? ' · opcional' : '') + '</small><br><small>' + esc(e.porque.replace(/\{[a-z_]+\}/g, '…')) + '</small></div>'; }).join('') + '</div>').join('')
   + '<h2 class="sec-t">3. Logos</h2><div class="card">' + LOGOS.map(L => '<div class="guia-e"><b>' + L.icone + ' ' + L.nome + '</b><br><small>' + esc(L.onde) + '</small><br><small class="mudo">' + esc(L.regras.slice(0, 3).join(' · ')) + '</small></div>').join('') + '<p class="mudo pequeno">Na etapa "Cores e logos" o painel monta o texto pronto para pedir cada uma ao ChatGPT.</p></div>'
   + '<button class="principal grande" onclick="rvNovo()">＋ Começar um restaurante agora</button>');
}

/* ---------- entrega: mensagem de boas-vindas e lista de contas ---------- */
function boasHtml(){
  const r = S.rest; if(!r.contato_telefone) return '<div class="res aviso">Cadastre o WhatsApp do dono (etapa 1) para mandar a mensagem.</div>';
  return '<label for="bvLogin">Login do dono (a senha vai em outra mensagem)</label><input id="bvLogin" autocomplete="off"><p><button class="principal" onclick="rvBoasVindas()">💬 Abrir no WhatsApp</button></p>';
}
window.rvBoasVindas = () => { const r = S.rest, login = jv('bvLogin');
  const t = 'Olá' + (r.contato_nome ? ' ' + r.contato_nome.split(' ')[0] : '') + '! O sistema do ' + r.nome + ' está pronto 🎉\n\n📱 Cardápio para os clientes (mande para eles e coloque na bio do Instagram):\n' + r.site_url
    + '\n\n👨‍🍳 Área da equipe: no fim do cardápio, toque em "Área de Funcionários".' + (login ? '\nSeu login: ' + login + ' (a senha vai na próxima mensagem; troque depois em "Trocar senha").' : '')
    + '\n\n📲 Instale no celular: dentro do sistema, toque em "Ajuda" → "App da equipe".\n❓ Dúvidas: em cada tela tem o botão "Ajuda" com o passo a passo e imagens.\n\nQualquer coisa, me chama aqui. Boas vendas!';
  window.open(waLink(r.contato_telefone, t), '_blank'); hist(r.id, 'Mensagem de boas-vindas enviada', ''); };
function listaContasHtml(){
  const r = S.rest, ref = refDe(r), gh = ghUsuario(r), L = [
    ['Supabase', 'E-mail do restaurante · senha do banco (Database password)', ref ? 'https://supabase.com/dashboard/project/' + ref : 'https://supabase.com/dashboard'],
    ['GitHub', 'Usuário ' + (gh || '…') + ' · repositório ' + r.slug, r.github_url || 'https://github.com'],
    ['Site do sistema', 'Endereço que vai para os clientes', r.site_url || ''],
    ['Google Cloud (login com Google)', 'E-mail do restaurante · observação: ID do cliente · senha: chave secreta (GOCSPX-)', 'https://console.cloud.google.com/auth/clients'],
    ['Chave de publicar funções', 'Token sbp_ do Supabase (está no GitHub → Settings → Secrets)', 'https://supabase.com/dashboard/account/tokens'],
    ['Planilha principal', 'Conta Google do restaurante · link: endereço /exec', r.api_url || ''],
    ['Planilha de contingência', 'A OUTRA conta Google · link: endereço /exec', r.contingencia_url || ''],
    ['Groq e Groq 2', 'E-mail de cada conta', 'https://console.groq.com/keys'], ['Gemini e Gemini 2', 'E-mail da conta Google', 'https://aistudio.google.com/apikey'],
    ['Cloudflare', 'E-mail · observação: Account ID', 'https://dash.cloudflare.com/'], ['NVIDIA', 'E-mail', 'https://build.nvidia.com/'],
    ['Search Console', 'E-mail do restaurante', 'https://search.google.com/search-console']];
  return '<div class="contas">' + L.map(x => '<div><b>' + esc(x[0]) + '</b><small>' + esc(x[1]) + '</small>' + (x[2] ? '<code class="quebra pequeno">' + esc(x[2]) + '</code>' : '') + '</div>').join('') + '</div>';
}
/* ---------- LEITURA DOS RESTAURANTES (chave só de leitura para o assistente) ---------- */
const temLeitura = r => !!(S.segs && S.segs['leitura_' + r.id]);
function tokenNovo(){ const u = new Uint8Array(36); crypto.getRandomValues(u); return b64url(u); }
function leituraHtml(){
  const r = S.rest, t = (S.leitTok || {})[r.id];
  return (temLeitura(r) ? '<div class="res ok">✓ Leitura ligada (chave termina em …' + esc(S.segs['leitura_' + r.id].fim) + ').</div>' : '<div class="res aviso">Leitura ainda não ligada.</div>')
   + '<button class="' + (temLeitura(r) ? 'mini' : 'principal') + '" onclick="rvGerarLeitura()">🔑 ' + (temLeitura(r) ? 'Gerar chave nova' : 'Gerar chave de leitura') + '</button>'
   + (t ? '<p class="pequeno"><b>Rode este código no SQL Editor do Supabase de ' + esc(r.nome) + '</b> (só aparece agora):</p><div class="copiar" id="leitSql">' + esc(leituraSql(r, t)) + '</div><button class="principal" onclick="rvCopiar(\'leitSql\')">📋 Copiar código</button> <button class="mini" onclick="rvTestarLeitura()">▶️ Testar a leitura</button><div id="leitRes"></div>' : '');
}
const leituraSql = (r, t) => '-- Chave de leitura do assistente do Painel de Revenda para ' + r.nome + '\ndo $$ declare v_id uuid; begin\n  select id into v_id from vault.secrets where name = \'revenda_leitura\';\n  if v_id is null then perform vault.create_secret(\'' + t + '\', \'revenda_leitura\'); else perform vault.update_secret(v_id, \'' + t + '\'); end if;\nend $$;';
window.rvGerarLeitura = async () => {
  const r = S.rest; if(temLeitura(r) && !confirm('Gerar uma chave NOVA? A antiga para de funcionar quando você rodar o código novo no restaurante.')) return;
  try{ const t = tokenNovo(), x = await rpc('revenda_segredo_salvar', { p_nome:'leitura_' + r.id, p_valor:t }); if(!x || !x.ok) throw new Error((x && x.erro) || 'não salvou');
    (S.leitTok = S.leitTok || {})[r.id] = t; S.segs = await tenta(() => rpc('revenda_segredos_status'), S.segs); await hist(r.id, 'Chave de leitura do assistente gerada', ''); aviso('Chave criada. Agora rode o código no Supabase do restaurante.', 'ok');
    S.aba === 'passo' ? abaPasso() : abaDados(); }catch(e){ erro('Não deu para gerar: ' + e.message); }
};
window.rvTestarLeitura = async () => {
  const r = S.rest, t = (S.leitTok || {})[r.id], box = $('leitRes'); if(!t || !box) return; box.innerHTML = '<div class="res aviso">⏳ Testando…</div>';
  try{ const x = await tempo(r.supabase_url + '/rest/v1/rpc/api_revenda_consulta', { method:'POST', headers:{ apikey:r.supabase_chave, Authorization:'Bearer ' + r.supabase_chave, 'Content-Type':'application/json' }, body:JSON.stringify({ p:{ token:t, tipo:'resumo' } }) });
    if(x.status === 404) return box.innerHTML = '<div class="res erro">❌ O banco ainda não tem a consulta. Rode primeiro o código da parte 1 (Consulta do assistente).</div>';
    const j = await x.json().catch(() => null);
    box.innerHTML = j && j.ok ? '<div class="res ok">✅ Funcionando! O assistente já lê os dados de ' + esc(r.nome) + ' (' + (j.dados.vendas ? j.dados.vendas.pedidos : 0) + ' pedidos nos últimos 7 dias).</div>' : '<div class="res erro">❌ ' + esc(j && j.erro === 'acesso negado' ? 'A chave não confere: rode o código acima no Supabase do restaurante e teste de novo.' : (j && j.erro) || 'erro ' + x.status) + '</div>';
  }catch(e){ box.innerHTML = '<div class="res erro">❌ Não deu para chegar no banco (' + esc(e.message) + ').</div>'; }
};

/* ---------- ASSISTENTE: chaves das IAs ---------- */
const IAS = [
  ['ia_groq','Groq','1º a responder. Crie em console.groq.com/keys (começa com gsk_).','https://console.groq.com/keys'],
  ['ia_groq_2','Groq 2','Reserva do Groq: OUTRA conta ou outro e-mail.','https://console.groq.com/keys'],
  ['ia_cloudflare_conta','Cloudflare · Account ID','O código de 32 letras e números da barra de endereço do dash.cloudflare.com.','https://dash.cloudflare.com/'],
  ['ia_cloudflare','Cloudflare · Token','Profile → API Tokens → Create Token → modelo "Workers AI" (começa com cfut_).','https://dash.cloudflare.com/profile/api-tokens'],
  ['ia_gemini','Gemini','Também faz a PESQUISA NA INTERNET. aistudio.google.com/apikey (começa com AIza ou AQ.).','https://aistudio.google.com/apikey'],
  ['ia_nvidia','NVIDIA','Reserva mais lenta. build.nvidia.com → API Keys (começa com nvapi-).','https://build.nvidia.com/settings/api-keys'],
  ['ia_gemini_2','Gemini 2','Último recurso e reserva da pesquisa: chave de OUTRO projeto do Google.','https://aistudio.google.com/apikey']
];
async function vAssistente(){
  const g = S.segs || {}, n = IAS.filter(x => g[x[0]]).length;
  T('<div class="topo"><button class="mini" onclick="rvIr(\'mais\')">← Mais</button></div><h1>✨ Assistente</h1>'
   + '<div class="card"><p>Seu sócio digital: responde sobre o seu negócio e os seus restaurantes, pesquisa na internet e <b>prepara</b> ações (cobrar, lançar despesa, criar proposta, mandar WhatsApp) que só acontecem quando você toca em <b>Confirmar</b>.</p>'
   + '<p class="mudo pequeno">Use chaves SUAS, diferentes das dos restaurantes (cada chave grátis tem cota própria). Elas ficam no cofre do banco do painel: este site nunca mostra a chave inteira.</p>'
   + '<div class="linha"><b>' + n + ' de ' + IAS.length + ' chaves cadastradas</b><button class="principal mini" onclick="rvTestarIAs()"' + (n ? '' : ' disabled') + '>▶️ Testar todas</button></div><div id="iaTeste"></div></div>'
   + '<div class="card"><h2>🔑 Chaves das IAs</h2><p class="mudo pequeno">A ordem é a ordem em que o assistente tenta: se uma falhar ou acabar a cota, ele passa para a próxima. Mínimo: Groq + Gemini.</p>'
   + IAS.map(x => '<div class="ia-item"><div class="linha"><b>' + x[1] + '</b>' + (g[x[0]] ? '<span class="selo ativo">✓ …' + esc(g[x[0]].fim) + '</span>' : '<span class="selo aviso">falta</span>') + '</div><small>' + esc(x[2]) + ' <a href="' + x[3] + '" target="_blank" rel="noopener">abrir ↗</a></small>'
      + '<div class="linha ia-campo"><input type="password" id="k_' + x[0] + '" placeholder="' + (g[x[0]] ? 'colar para trocar' : 'colar a chave aqui') + '" autocomplete="off"><button class="mini principal" onclick="rvSalvarIA(\'' + x[0] + '\')">Salvar</button>' + (g[x[0]] ? '<button class="mini" onclick="rvApagarIA(\'' + x[0] + '\')">🗑️</button>' : '') + '</div></div>').join('') + '</div>'
   + '<div class="card"><h2>🍽️ Leitura dos restaurantes</h2><p class="mudo pequeno">Para o assistente ver vendas, produtos, estoque e caixa de cada um.</p>'
   + S.lista.filter(r => r.situacao !== 'encerrado').map(r => '<div class="linha mapa-l"><span>' + (temLeitura(r) ? '✅' : '⬜') + ' ' + esc(r.nome) + '</span>' + (temLeitura(r) ? '<small class="mudo">ligada</small>' : '<button class="mini" onclick="rvAbrir(\'' + r.id + '\',\'passo\').then(()=>rvVerPasso(\'leitura\'))">Ligar ›</button>') + '</div>').join('') + '</div>'
   + '<div class="card"><h2>📒 Últimas respostas</h2><div id="iaLog"><small class="mudo">Carregando…</small></div></div>');
  try{ const L = await rest('assistente_log?select=*&order=em.desc&limit=15') || []; const b = $('iaLog'); if(b) b.innerHTML = L.length ? L.map(l => '<div class="hist"><small class="mudo">' + esc(new Date(l.em).toLocaleString('pt-BR')) + ' · ' + esc(l.provedor || '—') + (l.modelo ? ' · ' + esc(l.modelo) : '') + ' · ' + Math.round((l.ms || 0) / 100) / 10 + ' s · ' + (l.ferramentas || 0) + ' consulta(s)</small><b class="' + (l.ok ? 'txt-ok' : 'txt-erro') + '">' + (l.ok ? '✓ respondeu' : '✗ ' + esc(l.erro || 'erro')) + '</b></div>').join('') : '<small class="mudo">Ainda não foi usado.</small>'; }catch(e){}
}
window.rvSalvarIA = async (k, volta) => { const v = jv('k_' + k); if(!v) return erro('Cole a chave no campo.'); if(k === 'ia_cloudflare_conta' && !/^[0-9a-f]{32}$/.test(v)) return erro('O Account ID tem 32 letras (a-f) e números.');
  try{ const x = await rpc('revenda_segredo_salvar', { p_nome:k, p_valor:v }); if(!x || !x.ok) throw new Error((x && x.erro) || 'não salvou'); S.segs = await rpc('revenda_segredos_status'); aviso('Guardado no cofre ✓', 'ok'); volta === 'conectores' ? vConectores() : vAssistente(); }catch(e){ erro(e.message); } };
window.rvApagarIA = async (k, volta) => { if(!confirm('Apagar do cofre?')) return; try{ await rpc('revenda_segredo_salvar', { p_nome:k, p_valor:'' }); S.segs = await rpc('revenda_segredos_status'); volta === 'conectores' ? vConectores() : vAssistente(); }catch(e){ erro(e.message); } };

/* ---------- CONECTORES: cada restaurante tem os SEUS dois tokens (GitHub e Supabase) no cofre; função "conector" (SQL 015) ---------- */
const UPDS = [['upd135','135 · iFood: falso alarme'],['upd136','136 · avisos equipe × clientes'],['upd137','137 · comanda editável'],['upd138','138 · ponto: pedidos e atestados'],['upd139','139 · economia no plano grátis'],['upd140','140 · ajustes pelo painel'],['upd141','141 · aviso do Drive'],['upd142','142 · caixa profissional'],['upd143','143 · iFood sem alarme falso'],['upd144','144 · Desenvolvedores pelo painel'],['upd145','145 · completar instalação'],['upd146','146 · iFood compartilhado'],['upd147','147 · desempenho (regras duplicadas)'],['upd148','148 · igualar funções'],['upd149','149 · iFood nasce aceito'],['upd150','150 · avisos no celular do Administrador'],['upd151','151 · login de Desenvolvedor sem comando bloqueado'],['upd152','152 · tira um aviso anti-pausa duplicado']];
async function chamarConector(corpo, fn){
  if(S.sess && Date.now() > S.sess.exp && !await renovar()) throw new Error('Sua sessão expirou. Entre de novo.');
  const c = new AbortController(), t = setTimeout(() => c.abort(), 150000);
  try{ const r = await fetch(URL_ + '/functions/v1/' + (fn || 'conector'), { method:'POST', signal:c.signal, headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:JSON.stringify(corpo) });
    if(r.status === 404) throw new Error('A função "' + (fn || 'conector') + '" ainda não foi publicada no servidor do painel (veja "Preparar o painel" em Mais → Conectores).');
    const j = await r.json().catch(() => null); if(!j) throw new Error('O conector não respondeu (erro ' + r.status + ').'); return j;
  }catch(e){ throw new Error(e.name === 'AbortError' ? 'O conector demorou demais.' : e.message); } finally { clearTimeout(t); }
}
const kGh = r => 'conector_github_' + r.id, kSb = r => 'conector_supabase_' + r.id;
const temGh = r => !!(S.segs && S.segs[kGh(r)]), temSb = r => !!(S.segs && S.segs[kSb(r)]);
const conLinha = (ok, t) => '<div class="res ' + (ok ? 'ok' : 'erro') + '">' + (ok ? '✅ ' : '❌ ') + t + '</div>';
function conSel(r, k, rot, dica, link){
  const g = S.segs || {}, on = !!g[k];
  return '<div class="ia-item"><div class="linha"><b>' + rot + '</b>' + (on ? '<span class="selo ativo">✓ …' + esc(g[k].fim) + '</span>' : '<span class="selo aviso">falta</span>') + '</div><small>' + dica + ' <a href="' + link + '" target="_blank" rel="noopener">abrir ↗</a></small>'
   + '<div class="linha ia-campo"><input type="password" id="k_' + k + '" placeholder="' + (on ? 'colar para trocar' : 'colar o token aqui') + '" autocomplete="off"><button class="mini principal" onclick="rvConSalvar(\'' + r.id + '\',\'' + k + '\')">Salvar</button>' + (on ? '<button class="mini" onclick="rvConApagar(\'' + r.id + '\',\'' + k + '\')">🗑️</button>' : '') + '</div></div>';
}
/* o bloco completo de um restaurante: instruções, os 2 tokens, teste. Usado na etapa "Conectores" e na tela Mais → Conectores */
function conectorHtml(r){
  return '<details class="como"><summary>📖 Como ligar (passo a passo)</summary><ol class="pequeno">'
   + '<li><b>Supabase:</b> abra o link do token (botão abaixo), entre com a conta do <b>restaurante</b>, toque em <b>Generate new token</b>, nome <code>painel-' + esc(r.slug || 'restaurante') + '</code>, e copie o token (começa com <code>sbp_</code>; só aparece uma vez). Cole no primeiro campo e toque em Salvar.</li>'
   + '<li><b>GitHub:</b> abra o link, entre com a conta do restaurante. Nome <code>painel-' + esc(r.slug || 'restaurante') + '</code>, validade a maior possível. Em <i>Repository access</i> marque <b>Only select repositories</b> e escolha o repositório deste restaurante (crie o repositório antes, etapa "Criar o endereço do site"). Em <i>Permissions → Repository permissions</i> deixe <b>Contents: Read and write</b> e também <b>Pages: Read and write</b>. Toque em Generate token, copie e cole no segundo campo.</li>'
   + '<li>Toque em <b>Testar ligações</b>. Tem que aparecer ✅ nos dois.</li>'
   + '<li>Cada restaurante tem o <b>seu</b> par de tokens, guardados separados no cofre do painel: ligar um não mexe nos outros. Para desligar, toque na lixeira.</li>'
   + '<li>Seguro? O token nunca volta para o navegador (só os 4 últimos dígitos), e o conector só escreve no repositório e no projeto cadastrados neste restaurante. Tudo fica no Registro.</li></ol></details>'
   + conSel(r, kSb(r), '🗄️ Supabase', 'Token de acesso da conta Supabase do restaurante.', 'https://supabase.com/dashboard/account/tokens')
   + conSel(r, kGh(r), '🐙 GitHub', 'Token só deste repositório, com "Contents" e "Pages" em Read and write.', 'https://github.com/settings/personal-access-tokens/new')
   + '<div class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvConTestar(\'' + r.id + '\')">▶️ Testar ligações</button>' + '<button class="mini" onclick="rvConConferir(\'' + r.id + '\')">✅ Conferir implantação</button>' + (refDe(r) ? '<button class="mini" onclick="rvConFuncoes(\'' + r.id + '\')">⚙️ Funções</button><button class="mini" onclick="rvConPublicarFuncoes(\'' + r.id + '\')">⬆️ Publicar funções</button>' : '') + '</div><div id="con_' + r.id + '"></div>';
}
const conMsg = (id, html) => { const b = $('con_' + id); if(b) b.innerHTML = html; };
async function conRecarregar(r){ S.segs = await tenta(() => rpc('revenda_segredos_status'), S.segs); if(S.view === 'conectores') vConectores(); else if(S.view === 'rest' && S.aba === 'passo') abaPasso(); }
window.rvConSalvar = async (id, k) => {
  const v = jv('k_' + k); if(!v) return erro('Cole o token no campo.');
  if(/_supabase_/.test(k) && !/^sbp_[A-Za-z0-9]{20,}$/.test(v)) return erro('O token do Supabase começa com sbp_ e não tem espaços. Copie de novo.');
  if(/_github_/.test(k) && !/^(github_pat_|ghp_)[A-Za-z0-9_]{20,}$/.test(v)) return erro('O token do GitHub começa com github_pat_ (ou ghp_). Copie de novo.');
  try{ const x = await rpc('revenda_segredo_salvar', { p_nome:k, p_valor:v }); if(!x || !x.ok) throw new Error((x && x.erro) || 'Não salvou. Rode o arquivo 015 no banco do painel.'); aviso('Guardado no cofre ✓', 'ok'); hist(id, 'Conector: token guardado', /_github_/.test(k) ? 'GitHub' : 'Supabase'); await conRecarregar(S.lista.find(r => r.id === id)); }catch(e){ erro(e.message); }
};
window.rvConApagar = async (id, k) => { if(!confirm('Desligar este conector? O token sai do cofre.')) return; try{ await rpc('revenda_segredo_salvar', { p_nome:k, p_valor:'' }); await conRecarregar(S.lista.find(r => r.id === id)); }catch(e){ erro(e.message); } };
async function vConectores(){
  const L = S.lista.filter(r => r.situacao !== 'encerrado'); const aberto = S.conAberto || '';
  T('<div class="topo"><button class="mini" onclick="rvIr(\'mais\')">← Mais</button></div><h1>🔌 Conectores</h1>'
   + '<div class="card"><p>Ligue o painel ao <b>GitHub</b> e ao <b>Supabase</b> de cada restaurante. Com isso o painel <b>testa as ligações, monta o banco, atualiza o banco e publica o site</b> sozinho, sem você copiar e colar.</p>'
   + '<p class="mudo pequeno">Cada restaurante tem os seus próprios tokens: ligar um não tira o outro. Num restaurante novo, essa é a primeira coisa do passo a passo (etapa "Ligar o GitHub e o Supabase").</p></div>'
   + '<div class="card"><details class="como"' + (S.conPrep ? ' open' : '') + '><summary>🛠️ Preparar o painel (uma vez só)</summary><ol class="pequeno">'
   + '<li>No banco do <b>painel</b> (SQL Editor): rode o arquivo <code>015-conector.sql</code>.</li>'
   + '<li>No Supabase do <b>painel</b>: Edge Functions → Deploy a new function → nome <code>conector</code> → cole o arquivo <code>conector/index.ts</code> → desligue <b>Verify JWT</b> (igual à função assistente) → Deploy.</li>'
   + '<li>Pronto. Agora é só ligar cada restaurante abaixo. Os dois arquivos estão na pasta <i>1-PAINEL-DE-REVENDA</i> do Sistemas.zip.</li></ol></details></div>'
   + (L.some(r => temSb(r)) ? '<div class="card"><div class="linha"><b>⬆️ Atualizar todos os restaurantes</b><button class="principal mini" onclick="rvConAtualizarTodos()">Atualizar todos</button></div><small class="mudo">Aplica só o que falta das atualizações do banco (' + updFaixa() + ') em todos que têm o Supabase ligado, um por vez.</small><div id="con_todos"></div></div>' : '')
   + L.map(r => '<div class="card"><button class="alerta n0" onclick="rvConAbrir(\'' + r.id + '\')"><span class="ic">' + (temGh(r) && temSb(r) ? '✅' : (temGh(r) || temSb(r) ? '🟡' : '⬜')) + '</span><span><b>' + esc(r.nome) + '</b><small>' + (temSb(r) ? 'Supabase ✓' : 'Supabase: falta') + ' · ' + (temGh(r) ? 'GitHub ✓' : 'GitHub: falta') + '</small></span><span class="seta">' + (aberto === r.id ? '⌃' : '›') + '</span></button>'
      + (aberto === r.id ? conectorHtml(r) + '<div class="linha" style="margin-top:10px;"><button class="mini principal" onclick="rvConAtualizar(\'' + r.id + '\')"' + (temSb(r) ? '' : ' disabled') + '>⬆️ Atualizar banco (' + UPDS[0][1].slice(0, 3) + '–' + UPDS[UPDS.length - 1][1].slice(0, 3) + ')</button></div>' + togHtml_('atualizar_auto', 'Atualizar este restaurante automaticamente (banco, funções e site)', r) : '') + '</div>').join('')
   + '<div class="card"><h2>📒 Registro</h2><div id="conLog"><small class="mudo">Carregando…</small></div></div>');
  try{ const X = await rest('conector_log?select=*&order=em.desc&limit=20') || []; const b = $('conLog'); const nm = id => (S.lista.find(r => r.id === id) || {}).nome || '—';
    if(b) b.innerHTML = X.length ? X.map(l => '<div class="hist"><small class="mudo">' + esc(new Date(l.em).toLocaleString('pt-BR')) + ' · ' + esc(nm(l.restaurante_id)) + ' · ' + esc(l.alvo) + ' · ' + esc(l.acao) + '</small><b class="' + (l.ok ? 'txt-ok' : 'txt-erro') + '">' + (l.ok ? '✓ ' : '✗ ') + esc(l.ok ? (l.detalhe || 'ok') : (l.erro || 'erro')) + '</b></div>').join('') : '<small class="mudo">Nada feito ainda.</small>'; }catch(e){ const b = $('conLog'); if(b) b.innerHTML = '<small class="mudo">Rode o arquivo 015-conector.sql no banco do painel.</small>'; }
}
window.rvConAbrir = id => { S.conAberto = S.conAberto === id ? '' : id; vConectores(); };
const expiraHtml = e => { if(!e) return ''; const d = new Date(String(e).replace(' UTC', 'Z').replace(' ', 'T')); if(isNaN(d)) return ''; const dias = Math.ceil((d - Date.now()) / 864e5); return dias < 0 ? conLinha(false, 'O token do GitHub VENCEU. Crie outro e salve de novo.') : dias <= 14 ? '<div class="res" style="border-left:3px solid #f0b429;">⚠️ O token do GitHub vence em ' + dias + ' dia(s) (' + d.toLocaleDateString('pt-BR') + '). Crie outro antes disso e salve de novo.</div>' : '<div class="res"><small class="mudo">ℹ️ Token do GitHub vale até ' + d.toLocaleDateString('pt-BR') + '.</small></div>'; };
window.rvConTestar = async id => {
  conMsg(id, '<small class="mudo">Testando…</small>'); let h = '';
  try{ const a = await chamarConector({ acao:'sb_testar', restaurante_id:id }); h += conLinha(a.ok, a.ok ? 'Supabase: projeto "' + esc(a.nome || a.ref) + '" (' + esc(a.estado || '') + ')' : 'Supabase: ' + esc(a.erro)); }catch(e){ h += conLinha(false, 'Supabase: ' + esc(e.message)); }
  try{ const b = await chamarConector({ acao:'gh_testar', restaurante_id:id }); h += conLinha(b.ok, b.ok ? 'GitHub: ' + esc(b.repo) + ' (pode gravar)' : 'GitHub: ' + esc(b.erro)); if(b.ok) h += expiraHtml(b.expira); }catch(e){ h += conLinha(false, 'GitHub: ' + esc(e.message)); }
  conMsg(id, h);
};

/* CONFERIR IMPLANTAÇÃO: banco (comparado com o restaurante de referência), funções do servidor e site no GitHub */
const amarela = t => '<div class="res" style="border-left:3px solid #f0b429;">⚠️ ' + t + '</div>';
const listaCurta = (a, n = 8) => a.slice(0, n).map(esc).join(', ') + (a.length > n ? ' e mais ' + (a.length - n) : '');
window.rvConConferir = async id => {
  const r = S.lista.find(x => x.id === id); if(!r) return;
  conMsg(id, '<small class="mudo">⏳ Conferindo o banco e o GitHub de ' + esc(r.nome) + '…</small>');
  let h = '<div class="res"><b>Conferência de ' + esc(r.nome) + '</b> <small class="mudo">· ' + new Date().toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' }) + '</small></div>', precisaBanco = false, precisaFuncoes = false, precisaSite = false, precisaSync = false;
  if(!temSb(r)) h += amarela('Banco: ligue o token do Supabase deste restaurante para conferir.');
  else try{
    const a = await chamarConector({ acao:'sb_conferir', restaurante_id:id });
    if(!a.ok) h += conLinha(false, 'Banco: ' + esc(a.erro || 'não consegui conferir'));
    else if(a.referencia) h += conLinha(true, 'Este é o restaurante de referência (o mais novo): nada a comparar.');
    else {
      const t0 = a.totais || {};
      if(!a.faltamTabelas.length && !a.faltamColunas.length && !a.faltamFuncoes.length && !a.faltamCron.length) h += conLinha(true, 'Banco completo: ' + t0.tabelas + ' tabelas e ' + t0.funcoes + ' funções iguais às do modelo.');
      else { precisaBanco = true;
        h += conLinha(false, 'Banco incompleto: faltam ' + a.faltamTabelas.length + ' tabela(s), ' + a.faltamColunas.length + ' coluna(s), ' + a.faltamFuncoes.length + ' função(ões)' + (a.faltamCron.length ? ' e ' + a.faltamCron.length + ' rotina(s) automática(s)' : '') + '.'
          + (a.faltamTabelas.length ? '<br><small>Tabelas: ' + listaCurta(a.faltamTabelas) + '</small>' : '') + (a.faltamColunas.length ? '<br><small>Colunas: ' + listaCurta(a.faltamColunas) + '</small>' : '') + (a.faltamFuncoes.length ? '<br><small>Funções: ' + listaCurta(a.faltamFuncoes) + '</small>' : '') + (a.faltamCron.length ? '<br><small>Rotinas: ' + listaCurta(a.faltamCron) + '</small>' : '')); }
      if(a.diferentes && a.diferentes.length) h += amarela(a.diferentes.length + ' função(ões) do banco estão desatualizadas em relação ao modelo.' + ' Toque em "Sincronizar funções" para copiar as do modelo (a versão antiga fica guardada).' + '<br><small>' + a.diferentes.slice(0, 8).map(n => esc(n) + (a.detalhes && a.detalhes[n] ? ' — ' + esc(a.detalhes[n]) : '')).join('<br>') + (a.diferentes.length > 8 ? '<br>e mais ' + (a.diferentes.length - 8) : '') + '</small>');
      else if(a.personalizadas && a.personalizadas.length) h += conLinha(true, 'Funções do banco: todas iguais às do modelo.');
      if(a.soComentarios && a.soComentarios.length) h += '<div class="res"><small class="mudo">ℹ️ ' + a.soComentarios.length + ' função(ões) diferem só nos comentários (o código é o mesmo). Não é atraso e não precisa fazer nada.</small></div>';
      if(a.temMais && a.temMais.length) h += '<div class="res"><small class="mudo">ℹ️ ' + a.temMais.length + ' função(ões) deste banco têm algo A MAIS que o modelo. O "Sincronizar" não mexe nelas (para não apagar nada): ' + listaCurta(a.temMais, 8) + '. O desenvolvedor leva esse trecho para o modelo.</small></div>';
      if(a.personalizadas && a.personalizadas.length) h += '<div class="res"><small class="mudo">ℹ️ ' + a.personalizadas.length + ' função(ões) são diferentes DE PROPÓSITO neste restaurante (login, endereço do banco) e nunca são trocadas: ' + listaCurta(a.personalizadas, 6) + '.</small></div>';
      if(a.diferentes && a.diferentes.length) precisaSync = true;
      if(a.edgeFaltam && a.edgeFaltam.length){ precisaFuncoes = true; h += conLinha(false, 'Funções do servidor não publicadas: ' + listaCurta(a.edgeFaltam)); }
      else h += conLinha(true, 'Funções do servidor: todas publicadas.');
    }
  }catch(e){ h += conLinha(false, 'Banco: ' + esc(e.message)); }
  if(!temGh(r)) h += amarela('GitHub: ligue o token do GitHub deste restaurante para conferir.');
  else try{
    const g = await chamarConector({ acao:'gh_conferir', restaurante_id:id });
    if(!g.ok) h += conLinha(false, 'GitHub: ' + esc(g.erro || 'não consegui conferir'));
    else {
      h += expiraHtml(g.expira);
      const faltam = g.arquivos.filter(x => !x.existe).map(x => x.nome);
      h += conLinha(!faltam.length, faltam.length ? 'Site no GitHub: faltam arquivos (' + esc(faltam.join(', ')) + ').' : 'Site no GitHub: os 4 arquivos estão em ' + esc(g.repo) + '.');
      if(faltam.length){ precisaSite = true; (window._confSite = window._confSite || {})[id] = faltam; }
      if(!g.motor) { h += conLinha(false, 'Não achei o endereço do motor em config-restaurante.js (arquivo lido: ' + (g.cfgTam >= 0 ? g.cfgTam + ' letras' : 'não lido') + (g.amostra ? ' · trecho: ' + esc(g.amostra) : '') + ').'); precisaSite = true; }
      else if(!g.motorOk){ h += conLinha(false, 'O motor (' + esc(g.motor) + ') não respondeu: confira o endereço.'); precisaSite = true; }
      else h += conLinha(!g.ultima || g.versao === g.ultima, 'Motor em uso: ' + esc(g.versao) + (!g.ultima ? '' : g.versao !== g.ultima ? ' (a última é ' + esc(g.ultima) + ')' : ' (a última)'));
    }
  }catch(e){ h += conLinha(false, 'GitHub: ' + esc(e.message)); }
  (window._confEst = window._confEst || {})[id] = { banco:precisaBanco && temSb(r), funcoes:precisaFuncoes && temSb(r), site:precisaSite && temGh(r) && !!((window._confSite || {})[id] || []).length };
  const bt = []; if(window._confEst[id].banco || window._confEst[id].funcoes || window._confEst[id].site) bt.push('<button class="principal" onclick="rvConCorrigir(\'' + id + '\')">🔧 Corrigir tudo que foi encontrado</button>');
  if(precisaBanco && temSb(r)) bt.push('<button class="principal mini" onclick="rvConAtualizar(\'' + id + '\')">⬆️ Atualizar banco</button>');
  if(precisaSync && temSb(r)) bt.push('<button class="mini" onclick="rvConSincronizar(\'' + id + '\')">🔄 Sincronizar funções</button>');
  if(precisaFuncoes && temSb(r)) bt.push('<button class="mini" onclick="rvConPublicarFuncoes(\'' + id + '\')">⬆️ Publicar funções</button>');
  if(!precisaBanco && !precisaFuncoes && !precisaSite && h.indexOf('class="res erro"') < 0 && h.indexOf('⚠️') < 0) h += '<div class="res ok"><b>🎉 Tudo implantado.</b></div>';
  conMsg(id, h + (bt.length ? '<div class="linha" style="justify-content:flex-start">' + bt.join('') + '</div>' : ''));
  hist(id, 'Conferência da implantação', precisaBanco || precisaFuncoes || precisaSite ? 'faltam itens' : 'completa');
};
/* IMPLANTAR TUDO: banco, funções do servidor, logins e site, numa tela só, com uma confirmação */
window.rvLigarPages = async () => {
  const r = S.rest; if(!r) return; if(!temGh(r)) return erro('Antes, salve o token do GitHub deste restaurante e toque em Testar ligações.');
  if(!r.github_url) return erro('Preencha antes o endereço do GitHub (etapa "Criar o endereço do site").');
  conMsg('pages_' + r.id, '<small class="mudo">⏳ Ligando o GitHub Pages…</small>');
  let p; try{ p = await chamarConector({ acao:'gh_pages', restaurante_id:r.id }, 'conector-pages'); }catch(e){ p = { ok:false, erro:e.message }; }
  if(p.ok && p.url){ r.site_url = p.url; S.rest.site_url = p.url; try{ await salvar(''); }catch(e){} }
  conMsg('pages_' + r.id, conLinha(p.ok, p.ok ? 'Pages ligado. Endereço do site preenchido: ' + esc(p.url) + (p.criado ? '. Leva 1 a 2 minutos para ficar no ar.' : '') : esc(p.erro || 'erro')));
};
window.rvImplantarTudo = async () => {
  const r = S.rest; if(!r) return;
  if(!temSb(r) || !temGh(r)) return erro('Antes, salve os dois tokens (GitHub e Supabase) deste restaurante e toque em Testar ligações.');
  if(!/^[a-z0-9]{20}$/.test(refDe(r))) return erro('Preencha antes o endereço do banco (etapa "Criar o banco de dados").');
  if(!r.github_url) return erro('Preencha antes o endereço do GitHub (etapa "Criar o endereço do site"). O endereço do site o painel preenche sozinho.');
  if(r.situacao !== 'implantacao') return erro('Este restaurante não está "em implantação". Por segurança, o painel só monta o banco de restaurante novo. Se for refazer de propósito, mude a situação para "Em implantação" na aba Contrato.');
  const val = id => (($(id) || {}).value || ''), aLogin = val('tdLogin').trim(), aSenha = val('tdSenha'), dLogin = val('tdDLogin').trim(), dSenha = val('tdDSenha');
  const senhaOk = x => x.length >= 8 && /[A-Za-z]/.test(x) && /[0-9]/.test(x), loginOk = x => /^[A-Za-z0-9._-]{3,30}$/.test(x);
  if(!loginOk(aLogin) || !loginOk(dLogin)) return erro('Os logins têm de 3 a 30 letras, números, ponto, traço ou _ (sem espaço).');
  if(aLogin.toLowerCase() === dLogin.toLowerCase()) return erro('O login do dono e o seu de suporte precisam ser diferentes.');
  if(!senhaOk(aSenha) || !senhaOk(dSenha)) return erro('As senhas precisam de 8 caracteres ou mais, com letras e números.');
  if(!confirm('O painel vai montar o banco VAZIO de "' + r.nome + '", publicar as funções, criar os dois logins e gravar o site no GitHub. Leva uns 6 a 10 minutos: deixe esta tela aberta e não troque de aplicativo (o celular pausa o painel e a internet cai). Só use em restaurante NOVO. Continuar?')) return;
  const nome = prompt('Para confirmar, digite o nome do restaurante exatamente:'); if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  let _tela = null; try{ if(navigator.wakeLock) _tela = await navigator.wakeLock.request('screen'); }catch(e){}   // a tela não apaga enquanto o painel trabalha
  const caixa = 'tudo_' + r.id; let h = '', ok = true; const tela = t => conMsg(caixa, h + (t ? '<small class="mudo">⏳ ' + esc(t) + '</small>' : ''));
  const passo = async (rotulo, fn) => { if(!ok) return; tela(rotulo + '…'); let x; try{ x = await fn(); }catch(e){ x = { ok:false, erro:e.message }; } h += conLinha(x.ok, esc(rotulo) + (x.ok ? ' ✓' : ': ' + esc(x.erro || 'erro'))); if(!x.ok) ok = false; return x; };
  const q = v => String(v).replace(/'/g, "''");
  try{
    await passo('Ligando o site (GitHub Pages)', async () => { const p = await chamarConector({ acao:'gh_pages', restaurante_id:r.id }, 'conector-pages'); if(p.ok && p.url){ r.site_url = p.url; S.rest.site_url = p.url; } return { ok:!!p.ok, erro:p.erro }; });
    ctxCod(r, []);
    await passo('1/7 Estrutura do banco', () => conRodarSilencioso(r, bancoAutoItens(1), (n, t, rot) => tela('1/7 Estrutura do banco: parte ' + n + ' de ' + t + ' (' + rot + ')')));
    await passo('2/7 Cofre de chaves e dados iniciais', async () => {
      const c = await chamarConector({ acao:'sb_cofre1', restaurante_id:r.id, confirmar:r.nome }); if(!c.ok) return { ok:false, erro:'Cofre: ' + (c.erro || 'erro') };
      if(c.chave_publica && !r.supabase_chave){ r.supabase_chave = c.chave_publica; await salvar('Chave pública preenchida.'); }
      ctxCod(r, []); return conRodarSilencioso(r, bancoAutoItens(2), (n, t, rot) => tela('2/7 Dados iniciais: parte ' + n + ' de ' + t)); });
    await passo('3/7 Funções do servidor', async () => { conMsg(caixa + '_f', ''); const f = await conPublicarFuncoes(r, caixa + '_f', true); return { ok:!!f, erro:'veja abaixo e toque em Publicar funções para repetir' }; });
    await passo('4/7 Logins (dono e Desenvolvedor)', async () => {
      const ua = await conRodarSilencioso(r, UPDS.filter(u => u[0] === 'upd151'));   // a trava do Desenvolvedor que o Supabase não bloqueia (banco montado antes dessa versão)
      if(!ua.ok) return { ok:false, erro:ua.erro };
      const sql = "select public.instalar_admin_inicial('" + q(aLogin) + "', '" + q(aSenha) + "', 'Administrador');\nselect public.instalar_desenvolvedor('" + q(dLogin) + "', '" + q(dSenha) + "');";
      const a = await chamarConector({ acao:'sb_sql', restaurante_id:r.id, sql, rotulo:'Logins iniciais', confirmar:r.nome }); return { ok:!!a.ok, erro:a.erro }; });
    await passo('5/7 Endereços de login (Supabase)', async () => { const a = await chamarConector({ acao:'sb_login_urls', restaurante_id:r.id }); return { ok:!!a.ok, erro:a.erro }; });
    await passo('6/7 Site no GitHub', async () => { const a = await gravarSite_(r); return { ok:!!a.ok, erro:a.erro || 'algum arquivo falhou' }; });
    await passo('7/7 Avisos no celular (chaves)', async () => r.push_chave_publica ? { ok:true } : gerarChavesAviso_(r));   // se já tem, não gera outra (os celulares já ligados parariam de receber)
  }catch(e){ h += conLinha(false, esc(e.message)); ok = false; }
  try{ if(_tela) _tela.release(); }catch(e){}
  hist(r.id, 'Implantação automática', ok ? 'completa' : 'parou com erro');
  if(ok){
    const agora = new Date().toISOString(); ['conectar', 'banco', 'funcoes', 'admin', 'push'].forEach(id => { const e = S.rest.etapas[id]; if(!e || !e.feita) S.rest.etapas[id] = Object.assign(e || {}, { feita:true, pulada:false, em:agora }); });
    try{ await salvar('Etapas já feitas pelo painel foram marcadas.'); }catch(e){}
    setTimeout(() => { try{ rvConConferir(r.id); }catch(e){} }, 2500); }
  conMsg(caixa, h + (ok ? '<div class="res ok"><b>🎉 Pronto.</b> As chaves dos avisos também ficaram prontas e as etapas Conectar, Banco, Funções, Logins e Avisos já foram marcadas como feitas. Falta confirmar o site no ar. Falta só o que depende das suas contas: Entrar com o Google, Drive e chaves das IAs (próximas etapas). A conferência abaixo roda sozinha. Em Mais → Conectores toque em <b>Conferir implantação</b> para ver se ficou tudo.</div>' : '<div class="res erro">Parou neste passo. Nada do que já deu certo se perde: quando você resolver e tocar de novo, o painel pula o que já foi feito e continua daqui.</div>'));
};
/* ---------- AVISOS DE ERRO NO CELULAR (SQL 018 do painel + função avisar-painel): um botão por aparelho ---------- */
function avErroCard_(){
  setTimeout(avErroEstado_, 50);
  return '<div class="card"><h2>🔔 Avisos de erro neste aparelho</h2><p class="mudo pequeno">Quando um restaurante tiver um erro novo no sistema, este aparelho recebe um aviso, mesmo com o painel fechado. Restaurante em implantação não avisa.</p><div id="av_erro"><small class="mudo">Verificando…</small></div></div>';
}
const avB64_ = b => { const p = '='.repeat((4 - b.length % 4) % 4), r = atob((b + p).replace(/-/g, '+').replace(/_/g, '/')); return Uint8Array.from(r, c => c.charCodeAt(0)); };
async function avFn_(corpo){ if(S.sess && Date.now() > S.sess.exp) await renovar(); const r = await fetch(URL_ + '/functions/v1/avisar-painel', { method:'POST', headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:JSON.stringify(corpo) }); return r.json().catch(() => ({ ok:false, erro:'Sem resposta (erro ' + r.status + ').' })); }
async function avErroEstado_(){
  const box = $('av_erro'); if(!box) return;
  if(!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) { box.innerHTML = '<div class="res aviso">Este navegador não recebe avisos. No iPhone, instale o painel na tela inicial (Compartilhar → Adicionar à Tela de Início) e abra por lá.</div>'; return; }
  let sub = null; try{ const reg = await navigator.serviceWorker.ready; sub = await reg.pushManager.getSubscription(); }catch(e){}
  if(Notification.permission === 'denied') { box.innerHTML = '<div class="res erro">As notificações estão bloqueadas para este site. Libere nas configurações do navegador e volte aqui.</div>'; return; }
  box.innerHTML = sub ? '<div class="res ok">✅ Ligado neste aparelho.</div><div class="linha" style="justify-content:flex-start"><button class="mini" onclick="rvAvErroTeste()">Mandar um aviso de teste</button><button class="mini" onclick="rvAvErroDesligar()">Desligar</button></div><div id="av_erro_res"></div>'
    : '<button class="principal" onclick="rvAvErroLigar()">🔔 Ligar neste aparelho</button><div id="av_erro_res"></div>';
}
window.rvAvErroLigar = async () => {
  const res = $('av_erro_res'); const msg = t => { if(res) res.innerHTML = t; };
  try{
    msg('<small class="mudo">Pedindo permissão…</small>'); const perm = await Notification.requestPermission(); if(perm !== 'granted') return msg(conLinha(false, 'Sem permissão. Toque em Permitir quando o navegador perguntar.'));
    const k = await avFn_({ acao:'chave' }); if(!k.ok) return msg(conLinha(false, esc(k.erro || 'Não consegui a chave.')));
    const reg = await navigator.serviceWorker.ready; let sub = await reg.pushManager.getSubscription();
    if(!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly:true, applicationServerKey:avB64_(k.chave) });
    const j = sub.toJSON(), eu = (await chamarConector({ acao:'usr_listar' })).usuarios.find(u => u.eu);
    await rest('push_painel?on_conflict=endpoint', 'POST', { user_id:eu.id, endpoint:j.endpoint, p256dh:j.keys.p256dh, auth:j.keys.auth, falhas:0 }, { Prefer:'resolution=merge-duplicates' });
    const t = await avFn_({ acao:'teste' }); await avErroEstado_(); const r2 = $('av_erro_res'); if(r2) r2.innerHTML = conLinha(!!t.ok, t.ok ? 'Pronto! Mandei um aviso de teste: ele deve aparecer agora.' : esc(t.erro || 'Ligado, mas o teste não chegou.'));
  }catch(e){ msg(conLinha(false, esc(e.message))); }
};
window.rvAvErroTeste = async () => { const r = $('av_erro_res'); if(r) r.innerHTML = '<small class="mudo">Enviando…</small>'; const t = await avFn_({ acao:'teste' }); if(r) r.innerHTML = conLinha(!!t.ok, t.ok ? 'Aviso enviado.' : esc(t.erro || 'Não chegou.')); };
window.rvAvErroDesligar = async () => {
  try{ const reg = await navigator.serviceWorker.ready, sub = await reg.pushManager.getSubscription(); if(sub){ await rest('push_painel?endpoint=eq.' + encodeURIComponent(sub.endpoint), 'DELETE'); await sub.unsubscribe(); } }catch(e){ erro(e.message); }
  avErroEstado_();
};
window.rvConSincronizar = async id => {
  const r = S.lista.find(x => x.id === id); if(!r) return;
  const nome = prompt('Vai copiar para o banco de "' + r.nome + '" só as funções do modelo (Restaurante Teste) que estão ATRASADAS (as que têm algo a mais aqui e as personalizadas não são tocadas). A versão antiga de cada uma fica guardada na tabela _funcoes_backup, e se der erro nada é mudado.\n\nPara confirmar, digite o nome do restaurante exatamente:');
  if(nome === null) return; if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  conMsg(id, '<small class="mudo">⏳ Comparando e copiando as funções…</small>');
  try{ const a = await chamarConector({ acao:'sb_sincronizar', restaurante_id:id, confirmar:nome }); if(!a.ok) throw new Error(a.erro || 'Não foi possível.');
    hist(id, 'Funções sincronizadas com o modelo', (a.trocadas || 0) + ' trocadas');
    conMsg(id, conLinha(true, esc(a.message || 'Pronto.')) + ((a.ignoradas || []).length ? amarela((a.ignoradas.length) + ' função(ões) ficaram como estão por terem dados específicos do restaurante de referência.<br><small>' + listaCurta(a.ignoradas, 6) + '</small>') : '') + '<small class="mudo">⏳ Conferindo de novo…</small>');
    await rvConConferir(id);
  }catch(e){ conMsg(id, conLinha(false, esc(e.message))); }
};
window.rvConCorrigir = async id => {
  const r = S.lista.find(x => x.id === id), E = (window._confEst || {})[id]; if(!r || !E) return;
  const passos = [E.banco ? 'atualizar o banco (' + updFaixa() + ')' : '', E.funcoes ? 'publicar as funções do servidor' : '', E.site ? 'gravar no GitHub os arquivos que faltam' : ''].filter(Boolean);
  const nome = prompt('Vai corrigir "' + r.nome + '":\n• ' + passos.join('\n• ') + '\n\nTudo pode rodar de novo sem erro. Para confirmar, digite o nome do restaurante exatamente:');
  if(nome === null) return; if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  let h = '', ok = true; const mostra = t => conMsg(id, h + (t ? '<small class="mudo">⏳ ' + esc(t) + '</small>' : ''));
  try{
    if(E.banco){ mostra('Atualizando o banco…'); ctxCod(r, []); const a = await conRodarSilencioso(r, UPDS); h += conLinha(a.ok, a.ok ? 'Banco atualizado.' : 'Banco: ' + esc(a.erro)); ok = a.ok; }
    if(ok && E.funcoes){ mostra('Publicando as funções (uns 2 minutos)…'); const f = await conPublicarFuncoes(r, id); h += conLinha(!!f, f ? 'Funções do servidor publicadas.' : 'Funções: não terminou (veja acima).'); ok = !!f; }
    if(ok && E.site){ mostra('Gravando os arquivos no GitHub…'); const falt = (window._confSite || {})[id] || [], arqs = [];
      for(const n of falt){ if(n === 'config-restaurante.js') arqs.push({ caminho:n, conteudo:configTexto(r) }); else if(n === 'manifest.webmanifest') arqs.push({ caminho:n, conteudo:manifestTexto(r) });
        else { const x = await fetch('leve/' + n + '?t=' + Date.now(), { cache:'no-store' }); if(!x.ok) throw new Error('não achei ' + n); arqs.push({ caminho:n, conteudo:await x.text() }); } }
      const a = await chamarConector({ acao:'gh_publicar', restaurante_id:id, arquivos:arqs, mensagem:'Arquivos que faltavam, pelo Painel de Revenda' });
      h += (a.arquivos || []).map(f => conLinha(f.ok, esc(f.caminho) + (f.ok ? ' gravado' : ': ' + esc(f.erro)))).join(''); ok = !!a.ok; }
  }catch(e){ h += conLinha(false, esc(e.message)); ok = false; }
  hist(id, 'Correção da implantação', ok ? 'ok' : 'parou com erro'); conMsg(id, h + '<small class="mudo">⏳ Conferindo de novo…</small>');
  if(ok) await rvConConferir(id); else conMsg(id, h);
};
/* roda as atualizações sem escrever na tela; devolve {ok, erro} */
async function conRodarSilencioso(r, lista, cb){
  if(typeof window.cdObter !== 'function') return { ok:false, erro:'A tela de códigos ainda não carregou. Abra Restaurantes e volte.' };
  let n = 0; const feitas = await updsFeitas_(r); lista = lista.filter(u => !feitas.has(u[0]));
  for(const u of lista){ if(cb) cb(++n, lista.length, u[1]); try{ let sql = await window.cdObter(u[0]); const marcavel = /^((upd|est|dad)\d+|manual)$/.test(u[0]); if(marcavel) sql += MARCA_UPD(u[0]); let a = await chamarConector({ acao:'sb_sql', restaurante_id:r.id, sql, rotulo:u[1], confirmar:r.nome });
    /* restos de uma tentativa anterior que parou: o banco recusa com "já existe". Cada parte roda inteira ou nada (se algo já existe, a parte já tinha sido aplicada antes): só anota e segue. */
    if(!a.ok && /^((est|dad)\d+|manual)$/.test(u[0]) && /already exists|duplicate key|j[aá] existe/i.test(a.erro || '')){ const m = await chamarConector({ acao:'sb_sql', restaurante_id:r.id, sql:MARCA_UPD(u[0]).replace(/^\n;/, ''), rotulo:u[1] + ' (anotar)', confirmar:r.nome }); if(m.ok) a = { ok:true, jaTinha:true }; }
    if(!a.ok) return { ok:false, erro:u[1] + ': ' + (a.erro || 'falhou') }; }catch(e){ return { ok:false, erro:u[1] + ': ' + e.message }; } }
  return { ok:true };
}
window.rvConFuncoes = async id => {
  conMsg(id, '<small class="mudo">Consultando…</small>');
  try{ const a = await chamarConector({ acao:'sb_funcoes', restaurante_id:id });
    conMsg(id, a.ok ? '<div class="res ok">' + (a.funcoes.length ? a.funcoes.map(f => esc(f.slug) + ' (v' + esc(f.versao) + ')').join(' · ') : 'Nenhuma função publicada.') + '</div>' : conLinha(false, esc(a.erro || 'não consegui')));
  }catch(e){ conMsg(id, conLinha(false, esc(e.message))); }
};
/* roda uma lista de códigos [id, rótulo] em ordem no Supabase do restaurante; para no primeiro erro */
/* as atualizações numeradas já aplicadas ficam anotadas no banco do restaurante (tabela _atualizacoes): só roda o que falta */
const MARCA_UPD = id => "\n;create table if not exists public._atualizacoes (id text primary key, em timestamptz not null default now());\nalter table public._atualizacoes enable row level security;\ninsert into public._atualizacoes (id) values ('" + id + "') on conflict do nothing;";
async function updsFeitas_(r){ try{ const a = await chamarConector({ acao:'sb_atualizacoes', restaurante_id:r.id }); return a.ok ? new Set(a.feitas || []) : new Set(); }catch(e){ return new Set(); } }
async function conRodar(r, lista, onde){
  if(typeof window.cdObter !== 'function') { erro('A tela de códigos ainda não carregou. Abra Restaurantes e volte.'); return false; }
  let h = '';
  const feitas = await updsFeitas_(r), pulou = lista.filter(u => feitas.has(u[0])).length; lista = lista.filter(u => !feitas.has(u[0]));
  if(pulou) h += '<small class="mudo">⏭️ ' + pulou + ' atualizaç' + (pulou > 1 ? 'ões já estavam aplicadas' : 'ão já estava aplicada') + ' (puladas).</small>';
  if(!lista.length){ conMsg(onde, h + conLinha(true, 'Este banco já está em dia: nada para aplicar.')); return true; }
  for(const u of lista){
    conMsg(onde, h + '<small class="mudo">⏳ ' + esc(u[1]) + '…</small>');
    try{ let sql = await window.cdObter(u[0]); if(/^upd\d+$/.test(u[0])) sql += MARCA_UPD(u[0]); const a = await chamarConector({ acao:'sb_sql', restaurante_id:r.id, sql, rotulo:u[1], confirmar:r.nome });
      h += conLinha(a.ok, esc(u[1]) + (a.ok ? '' : ': ' + esc(a.erro))); if(!a.ok){ conMsg(onde, h); return false; }
    }catch(e){ h += conLinha(false, esc(u[1]) + ': ' + esc(e.message)); conMsg(onde, h); return false; }
  }
  conMsg(onde, h); return true;
}
/* publica as 33 funções do servidor direto pelo conector (sem GitHub Actions), uma por vez, mostrando o andamento */
async function conPublicarFuncoes(r, onde, soFaltam){
  conMsg(onde, '<small class="mudo">Buscando a lista de funções…</small>');
  try{ const L = await chamarConector({ acao:'sb_funcoes_publicar', restaurante_id:r.id, site:true }); if(!L.ok) { conMsg(onde, conLinha(false, esc(L.erro))); return false; }
    let fs = L.funcoes || []; const ruins = []; let n = 0, jaTinha = 0;
    if(soFaltam){ try{ const ex = await chamarConector({ acao:'sb_funcoes', restaurante_id:r.id }); if(ex.ok){ const tem = new Set((ex.funcoes || []).map(x => x.slug)); jaTinha = fs.filter(f => tem.has(f)).length; fs = fs.filter(f => !tem.has(f)); } }catch(e){ /* sem a lista: publica todas */ } }
    const total = fs.length + jaTinha, esperar = ms => new Promise(ok => setTimeout(ok, ms));
    for(const f of fs){ conMsg(onde, '<small class="mudo">⏳ ' + (++n + jaTinha) + ' de ' + total + ': ' + esc(f) + '…</small>' + (ruins.length ? conLinha(false, ruins.length + ' com erro até agora') : ''));
      let a;
      for(let t = 0; t < 4; t++){   // falha de internet (celular trocou de app, sinal caiu): espera e tenta de novo, até 4 vezes
        try{ a = await chamarConector({ acao:'sb_funcoes_publicar', restaurante_id:r.id, slug:f }); }catch(e){ a = { ok:false, erro:e.message, rede:/failed to fetch|load failed|network|demorou|abort/i.test(e.message || '') }; }
        if(a.ok || (!a.rede && t >= 1)) break; await esperar(a.rede ? 4000 : 1500); }
      if(!a.ok) ruins.push(f + ': ' + (a.erro || 'erro')); }
    conMsg(onde, ruins.length ? conLinha(false, (total - ruins.length) + ' de ' + total + ' publicadas. Toque de novo: só as que faltam serão tentadas.') + '<small class="mudo">' + ruins.map(esc).join('<br>') + '</small>' : conLinha(true, 'As ' + total + ' funções do servidor foram publicadas.'));
    hist(r.id, 'Funções do servidor publicadas pelo conector', ruins.length ? (total - ruins.length) + ' de ' + total : 'todas (' + total + ')');
    return !ruins.length;
  }catch(e){ conMsg(onde, conLinha(false, esc(e.message))); return false; }
}
window.rvConPublicarFuncoes = async (id, onde) => { const r = S.lista.find(x => x.id === id); if(!r) return; if(!r.site_url) return erro('Preencha antes o endereço do site.'); if(!confirm('Publicar (ou atualizar) as funções do servidor no Supabase de "' + r.nome + '"? Leva uns 2 minutos; deixe a tela aberta.')) return; const ok = await conPublicarFuncoes(r, onde || id); if(ok) aviso('Funções publicadas ✓', 'ok'); };
/* ATUALIZAR TODOS: roda as atualizações do banco em todos os restaurantes com o Supabase ligado, um depois do outro */
const updFaixa = () => UPDS[0][1].slice(0, 3) + ' a ' + UPDS[UPDS.length - 1][1].slice(0, 3);
window.rvConAtualizarTodos = async () => {
  const L = S.lista.filter(r => r.situacao !== 'encerrado' && temSb(r) && /^[a-z0-9]{20}$/.test(refDe(r))); if(!L.length) return erro('Nenhum restaurante com o Supabase ligado.');
  const t = prompt('Vai aplicar só as atualizações que ainda faltam (de ' + updFaixa() + ') no banco de ' + L.length + ' restaurante(s): ' + L.map(r => r.nome).join(', ') + '.\nO que já foi aplicado é pulado.\n\nPara confirmar, digite TODOS:');
  if(t === null) return; if(t.trim().toUpperCase() !== 'TODOS') return erro('Não confere. Nada foi feito.');
  const box = $('con_todos'); let h = '', ruins = 0;
  for(const r of L){ if(box) box.innerHTML = h + '<small class="mudo">⏳ ' + esc(r.nome) + '…</small><div id="con_todos_' + r.id + '"></div>';
    ctxCod(r, []); const ok = await conRodar(r, UPDS, 'todos_' + r.id); hist(r.id, 'Atualização do banco (todos)', ok ? 'ok' : 'parou com erro');
    h += conLinha(ok, esc(r.nome) + (ok ? ': atualizado' : ': parou com erro (abra o restaurante abaixo e toque em Atualizar banco para ver)')); if(!ok) ruins++; }
  h += '<div class="res ' + (ruins ? 'erro' : 'ok') + '"><b>' + (ruins ? '❌ ' + ruins + ' de ' + L.length + ' pararam com erro.' : '✅ Os ' + L.length + ' restaurante(s) estão em dia.') + '</b><br><small class="mudo">Cada atualização roda inteira ou não roda: se uma linha der erro, nada daquela atualização fica pela metade. O vigia reconfere agora.</small></div>';
  if(box) box.innerHTML = h; aviso(ruins ? 'Terminou com erro.' : 'Terminou.', ruins ? 'erro' : 'ok'); vigiaReconferir();
};
window.rvConAtualizar = async id => {
  const r = S.lista.find(x => x.id === id); if(!r) return;
  const nome = prompt('Vai aplicar só as atualizações que ainda faltam (de ' + updFaixa() + ') no banco de "' + r.nome + '". O que já foi aplicado é pulado.\n\nPara confirmar, digite o nome do restaurante exatamente:');
  if(nome === null) return; if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  ctxCod(r, []); await conRodar(r, UPDS, id); hist(id, 'Atualização do banco pelo conector', UPDS.map(u => u[0]).join(', ')); vigiaReconferir();
  vigiaReconferir();
};
/* ETAPA "Ligar o GitHub e o Supabase" */
function conectarEtapaHtml(){ const r = S.rest; return conectorHtml(r); }
/* ETAPA "Montar as tabelas": o painel aplica sozinho todos os códigos que não pedem nada seu */
function bancoAutoItens(fase){
  const C = (window.CODIGOS || {}).banco || [], k = C.findIndex(i => i.id === 'segredos1');
  const parte = fase === 2 ? C.slice(k + 1) : C.slice(0, k < 0 ? C.length : k);
  return parte.filter(i => i.arq && !i.especial && !i.opcional).map(i => [i.id, i.titulo]);
}
function bancoAutoHtml(){
  const r = S.rest; if(!temSb(r)) return '<div class="res erro">Antes, ligue o Supabase na etapa "Ligar o GitHub e o Supabase". Sem isso, use o jeito manual abaixo.</div>';
  if(!/^[a-z0-9]{20}$/.test(refDe(r))) return '<div class="res erro">Preencha antes o endereço do banco (etapa "Criar o banco de dados").</div>';
  return '<p class="pequeno"><b>Fase 1</b>: o painel roda sozinho as ' + bancoAutoItens(1).length + ' partes da estrutura, em ordem.</p><button class="principal" onclick="rvBancoAuto(1)">⚡ Montar a estrutura sozinho</button><div id="con_banco1_' + r.id + '"></div>'
   + '<p class="pequeno" style="margin-top:12px;"><b>Fase 2</b>: o painel guarda as chaves no cofre do banco sozinho (a chave secreta é lida direto no Supabase e não passa por aqui) e depois roda os dados iniciais.</p><button class="principal" onclick="rvBancoAuto(2)">⚡ Cofre de chaves e dados iniciais</button><div id="con_banco2_' + r.id + '"></div>'
   + '<p class="pequeno" style="margin-top:12px;"><b>Opcional</b>: um cardápio de exemplo (3 categorias, 9 produtos com preço, marcados "exemplo") para o dono ver como fica e testar um pedido. Só entra com o cardápio vazio.</p><button class="mini" onclick="rvBancoExemplo()">🍔 Pôr o cardápio de exemplo</button><div id="con_banco3_' + r.id + '"></div>';
}
window.rvGoogleAuto = async () => {
  const r = S.rest, cid = jv('gaId'), csec = jv('gaSec'), box = 'ga_' + r.id; if(!cid || !csec) return erro('Cole o ID do cliente e a chave secreta.');
  conMsg(box, '<small class="mudo">Ligando…</small>');
  try{ const a = await chamarConector({ acao:'sb_google', restaurante_id:r.id, cid, csec }); const ip = $('gaSec'); if(ip) ip.value = '';
    conMsg(box, a.ok ? conLinha(true, '"Entrar com o Google" ligado no Supabase.') + (a.cofre ? conLinha(true, 'Credenciais guardadas no cofre (Drive).') : conLinha(false, 'Não guardei no cofre: ' + esc(a.erro_cofre || '') + '. Use o código da etapa do Drive.')) : conLinha(false, esc(a.erro)));
    if(a.ok){ hist(r.id, 'Login com Google ligado pelo conector', ''); (window.CD_VALS = window.CD_VALS || {}).gid = cid; } }catch(e){ conMsg(box, conLinha(false, esc(e.message))); }
};
window.rvLoginUrls = async () => {
  const r = S.rest; if(!r.site_url) return erro('Preencha antes o endereço do site.'); const box = 'lu_' + r.id; conMsg(box, '<small class="mudo">Gravando…</small>');
  try{ const a = await chamarConector({ acao:'sb_login_urls', restaurante_id:r.id }); conMsg(box, conLinha(a.ok, a.ok ? 'Site URL e Redirect URL gravados: ' + esc(a.site) : esc(a.erro))); if(a.ok) hist(r.id, 'Endereços do login configurados pelo conector', a.site); }catch(e){ conMsg(box, conLinha(false, esc(e.message))); }
};
window.rvBancoExemplo = async () => {
  const r = S.rest; if(!confirm('Pôr o cardápio de exemplo em "' + r.nome + '"? Só entra se o cardápio estiver vazio.')) return;
  ctxCod(r, []); const ok = await conRodar(r, [['exemplo', 'Cardápio de exemplo']], 'banco3_' + r.id); if(ok){ hist(r.id, 'Cardápio de exemplo colocado', ''); aviso('Pronto. Abra o site para ver.', 'ok'); }
};
window.rvBancoAuto = async fase => {
  const r = S.rest; if(!confirm('O painel vai rodar no banco de "' + r.nome + '" (projeto ' + refDe(r) + '). Só use em banco NOVO e vazio. Continuar?')) return;
  const nome = prompt('Para confirmar, digite o nome do restaurante exatamente:'); if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  if(fase === 2){ conMsg('banco2_' + r.id, '<small class="mudo">⏳ Cofre de chaves (parte 1)…</small>');
    let c; try{ c = await chamarConector({ acao:'sb_cofre1', restaurante_id:r.id, confirmar:r.nome }); }catch(e){ c = { ok:false, erro:e.message }; }
    if(!c.ok){ conMsg('banco2_' + r.id, conLinha(false, 'Cofre de chaves: ' + esc(c.erro || 'erro') + '. Faça o cofre à mão (jeito manual abaixo) e toque de novo.')); return; }
    if(c.chave_publica && !r.supabase_chave){ r.supabase_chave = c.chave_publica; await salvar('Chave pública preenchida.'); } }
  ctxCod(r, []); const lista = bancoAutoItens(fase);
  const ok = await conRodar(r, lista, 'banco' + fase + '_' + r.id); hist(r.id, 'Banco montado pelo conector (fase ' + fase + ')', ok ? 'completo (' + lista.length + ' partes)' : 'parou com erro');
  if(ok) aviso(fase === 1 ? 'Estrutura pronta ✓ Agora faça o código do cofre de chaves à mão.' : 'Dados iniciais prontos ✓ Toque em Testar.', 'ok');
};
/* ETAPA "Colocar o site no ar": o painel grava os 4 arquivos no GitHub do restaurante */
function publicarAutoHtml(){
  const r = S.rest; if(!temGh(r)) return '<div class="res erro">Antes, ligue o GitHub na etapa "Ligar o GitHub e o Supabase". Sem isso, use o jeito manual abaixo.</div>';
  return '<p class="pequeno">O painel grava no repositório os 4 arquivos do site, já prontos para este restaurante.</p><button class="principal" onclick="rvPublicarAuto()">⚡ Publicar o site sozinho</button><div id="con_pub_' + r.id + '"></div>';
}
/* grava no GitHub os 4 arquivos do site (um lugar só: usado pela etapa "Colocar o site no ar" e pelo "Implantar tudo") */
/* PUBLICAÇÃO AUTOMÁTICA: quando uma mudança salva no painel altera o config-restaurante.js ou o manifest do site, o painel grava no GitHub sozinho.
   Só mexe se o arquivo no GitHub ainda for o que o painel gerou (se alguém mudou à mão, avisa e não sobrescreve) e só depois de o site já ter sido publicado. */
const semHora_ = t => String(t).replace(/gerado pelo Painel de Revenda em [^\n]*?\.\n/, '\n');
function snapSite_(r){ try{ return { cfg:semHora_(configTexto(r)), man:manifestTexto(r) }; }catch(e){ return null; } }
const utf8_ = b => { try{ return new TextDecoder().decode(Uint8Array.from(String(b), c => c.charCodeAt(0))); }catch(e){ return String(b); } };
async function autoSite_(antes){
  const r = S.rest, agora = snapSite_(r); if(!agora) return; S._snap = agora;
  if(!antes || !temGh(r) || !r.github_url || !r.site_url) return;
  const lista = [];
  if(agora.cfg !== antes.cfg) lista.push(['config-restaurante.js', configTexto(r), antes.cfg, t => semHora_(t)]);
  if(agora.man !== antes.man) lista.push(['manifest.webmanifest', manifestTexto(r), antes.man, t => t]);
  if(!lista.length) return;
  const feitos = [], parados = [];
  for(const m of lista){
    const l = await chamarConector({ acao:'gh_ler', restaurante_id:r.id, caminho:m[0] });
    if(!l.ok || !l.existe) continue;   // o site ainda não foi publicado: nada a atualizar
    if(m[3](utf8_(l.conteudo || '')).trim() !== m[2].trim()){ parados.push(m[0]); continue; }   // foi mudado fora do painel
    const a = await chamarConector({ acao:'gh_publicar', restaurante_id:r.id, arquivos:[{ caminho:m[0], conteudo:m[1] }], mensagem:'Atualização de ' + r.nome + ' pelo Painel de Revenda' });
    if(a.ok) feitos.push(m[0]); else parados.push(m[0] + ' (' + (a.erro || 'falhou') + ')');
  }
  if(feitos.length){ hist(r.id, 'Site atualizado no GitHub automaticamente', feitos.join(', ')); aviso('Salvo e já enviado ao GitHub: ' + feitos.join(', ') + '. O site atualiza em 1 a 2 minutos.', 'ok'); }
  if(parados.length) aviso('Salvo, mas NÃO enviei ao GitHub: ' + parados.join(', ') + ' (foi mudado fora do painel ou deu erro). Use "Gravar no GitHub" na etapa Colocar o site no ar.', 'erro');
}
/* CARREGADOR AUTOMÁTICO: o index.html de cada restaurante (a "porta" que abre o sistema) é o do painel (leve/index.html).
   Quando o painel muda o carregador (ex.: buscar o sistema sem cache), ele troca sozinho no GitHub de cada restaurante.
   Só troca se o arquivo lá for um carregador oficial ANTIGO (conferido pelo SHA-256); se for outro (mudado à mão), não mexe e avisa. Confere no máximo 1 vez por dia por restaurante. */
const LOADER_ANTIGOS = ['e4949dde3c168d93335ef35f49ed3b385eadc8990c11218aed086d1ade449ae9'];
async function sha256_(bin){ const b = Uint8Array.from(String(bin), c => c.charCodeAt(0) & 255); const h = await crypto.subtle.digest('SHA-256', b); return Array.from(new Uint8Array(h)).map(x => x.toString(16).padStart(2, '0')).join(''); }
async function carregadorAuto_(){
  if(!S.lista || !S.lista.length || !(window.crypto && crypto.subtle)) return;
  const x = await fetch('leve/index.html?t=' + Date.now(), { cache:'no-store' }); if(!x.ok) return;
  const novoTxt = await x.text(), novo = await sha256_(Array.from(new TextEncoder().encode(novoTxt), c => String.fromCharCode(c)).join(''));
  const hoje_ = new Date().toISOString().slice(0, 10), feitos = [], parados = [];
  for(const r of S.lista){
    if(!temGh(r) || !r.github_url || !r.site_url) continue;   // sem conector ou site ainda não publicado
    const k = 'rvLoaderOk_' + r.id; let v = null; try{ v = localStorage.getItem(k); }catch(e){}
    if(v === hoje_ + novo.slice(0, 8)) continue;
    try{
      const l = await chamarConector({ acao:'gh_ler', restaurante_id:r.id, caminho:'index.html' });
      if(!l.ok || !l.existe) continue;
      const atual = await sha256_(l.conteudo || '');
      if(atual === novo){ try{ localStorage.setItem(k, hoje_ + novo.slice(0, 8)); }catch(e){} continue; }
      if(LOADER_ANTIGOS.indexOf(atual) === -1){ parados.push(r.nome); try{ localStorage.setItem(k, hoje_ + novo.slice(0, 8)); }catch(e){} continue; }   // não é o carregador oficial: não mexe
      const a = await chamarConector({ acao:'gh_publicar', restaurante_id:r.id, arquivos:[{ caminho:'index.html', conteudo:novoTxt }], mensagem:'Carregador atualizado pelo Painel de Revenda' });
      if(a.ok){ feitos.push(r.nome); hist(r.id, 'Carregador do site atualizado no GitHub automaticamente', 'index.html'); try{ localStorage.setItem(k, hoje_ + novo.slice(0, 8)); }catch(e){} }
    }catch(e){ /* tenta de novo na próxima abertura */ }
  }
  if(feitos.length) aviso('Atualizei sozinho o carregador do site de: ' + feitos.join(', ') + '. Vale em 1 a 2 minutos.', 'ok');
  if(parados.length) aviso('O index.html de ' + parados.join(', ') + ' foi mudado fora do painel; não troquei o carregador. Se quiser o novo, use "Gravar no GitHub" na etapa Colocar o site no ar.', 'aviso');
}
async function gravarSite_(r){
  const arqs = [{ caminho:'config-restaurante.js', conteudo:configTexto(r) }, { caminho:'manifest.webmanifest', conteudo:manifestTexto(r) }];
  for(const n of ['index.html', 'sw.js']){ const x = await fetch('leve/' + n + '?t=' + Date.now(), { cache:'no-store' }); if(!x.ok) throw new Error('não achei ' + n + ' (erro ' + x.status + ')'); arqs.push({ caminho:n, conteudo:await x.text() }); }
  const a = await chamarConector({ acao:'gh_publicar', restaurante_id:r.id, arquivos:arqs, mensagem:'Site de ' + r.nome + ' publicado pelo Painel de Revenda' });
  hist(r.id, 'Site publicado pelo conector', arqs.map(x => x.caminho).join(', '));
  if(a && a.ok && S.rest && S.rest.id === r.id) S._snap = snapSite_(S.rest);   // o que está no GitHub agora é o que o painel gerou: a próxima mudança salva compara com isso
  return a;
}
/* gera as chaves dos avisos no celular (a privada vai direto ao cofre do banco) e guarda a pública no cadastro */
async function gerarChavesAviso_(r){
  const a = await chamarConector({ acao:'sb_vapid', restaurante_id:r.id }); if(!a.ok) return a;
  r.push_chave_publica = a.chave_publica; await salvar('Chaves dos avisos prontas e guardadas no cofre.'); await hist(r.id, 'Chaves de aviso geradas pelo conector', ''); return a;
}
window.rvPublicarAuto = async () => {
  const r = S.rest, caixa = 'pub_' + r.id;
  try{
    conMsg(caixa, '<small class="mudo">⏳ Gravando os arquivos no GitHub…</small>');
    const a = await gravarSite_(r);
    conMsg(caixa, (a.arquivos || []).map(f => conLinha(f.ok, esc(f.caminho) + (f.ok ? '' : ': ' + esc(f.erro)))).join('') + (a.ok ? '<div class="res ok">Pronto! Espere 1 a 2 minutos e toque em "Conferir o site".</div>' : conLinha(false, esc(a.erro || 'Alguns arquivos falharam.'))));
  }catch(e){ conMsg(caixa, conLinha(false, esc(e.message))); }
};

/* ---------- AJUSTES DO RESTAURANTE PELO PAINEL (pelo conector do Supabase; SQL 140 no restaurante) ----------
   Tudo aqui continua podendo ser mudado dentro do sistema do restaurante (Administrador). */
const IA_REST = [['groq','Groq','1º a responder (começa com gsk_).','https://console.groq.com/keys'],['groq_2','Groq 2','Reserva do Groq: outra conta.','https://console.groq.com/keys'],
  ['cloudflare_conta','Cloudflare · Account ID','32 letras e números (barra de endereço do dash.cloudflare.com).','https://dash.cloudflare.com/'],['cloudflare','Cloudflare · Token','API Tokens → modelo "Workers AI".','https://dash.cloudflare.com/profile/api-tokens'],
  ['gemini','Gemini','Também faz a pesquisa na internet (AIza… ou AQ.…).','https://aistudio.google.com/apikey'],['nvidia','NVIDIA','Reserva mais lenta (nvapi-…).','https://build.nvidia.com/settings/api-keys'],['gemini_2','Gemini 2','Último recurso: chave de outro projeto do Google.','https://aistudio.google.com/apikey']];
const DADOS_REST = [['nome','Nome que aparece no cardápio e nas impressões',60],['endereco','Endereço',200],['telefone','WhatsApp / telefone da loja',30],['horario','Horário de funcionamento',300],['redes','Redes sociais (Instagram, etc.)',300]];
async function abaAjustesRest(){
  const r = S.rest;
  if(!temSb(r)){ C('<div class="card"><h2>⚙️ Ajustes do restaurante</h2><p>Daqui você muda as <b>chaves das IAs</b>, os <b>dados do restaurante</b> (nome, endereço, WhatsApp, horário, redes) e a <b>senha de um usuário</b> (quando o dono esquece), sem entrar no sistema dele.</p>'
    + '<div class="res aviso">Para isso, ligue antes o conector do Supabase deste restaurante.</div><button class="principal" onclick="rvIr(\'conectores\')">🔌 Ligar o conector</button>'
    + '<p class="mudo pequeno">Tudo isso também pode ser mudado dentro do sistema do restaurante, em Administrador.</p></div>'); return; }
  C('<div class="card"><small class="mudo">Carregando os ajustes de ' + esc(r.nome) + '…</small></div>');
  let a; try{ a = await chamarConector({ acao:'sb_ajustes', restaurante_id:r.id, p:{ acao:'ler' } }); }catch(e){ a = { ok:false, erro:e.message }; }
  if(S.view !== 'rest' || S.aba !== 'ajustes' || S.rest.id !== r.id) return;
  if(!a || !a.ok){ C('<div class="card"><h2>⚙️ Ajustes do restaurante</h2>' + conLinha(false, esc((a && a.erro) || 'Não consegui ler.')) + '<button class="mini" onclick="rvAba(\'ajustes\')">↻ Tentar de novo</button></div>'); return; }
  const ia = {}; (a.ia || []).forEach(x => { ia[x.provedor] = x; }); const d = a.dados || {};
  C('<p class="mudo pequeno">Muda direto no sistema de ' + esc(r.nome) + ', na hora. Tudo continua podendo ser mudado lá dentro também (Administrador), e fica registrado na Auditoria dele.</p>'
   + '<div class="cols-pc"><div><div class="card"><h2>🤖 Chaves das IAs do atendente</h2><p class="mudo pequeno">A ordem é a ordem em que o atendente tenta. Use as chaves do restaurante (cada uma tem cota própria).</p>'
   + IA_REST.map(x => { const v = ia[x[0]] || {}; return '<div class="ia-item"><div class="linha"><b>' + x[1] + '</b>' + (v.tem ? '<span class="selo ativo">✓ …' + esc(v.final || '') + '</span>' : '<span class="selo aviso">falta</span>') + '</div><small>' + esc(x[2]) + ' <a href="' + x[3] + '" target="_blank" rel="noopener">abrir ↗</a></small>'
      + '<div class="linha ia-campo"><input type="password" id="aj_ia_' + x[0] + '" placeholder="' + (v.tem ? 'colar para trocar' : 'colar a chave aqui') + '" autocomplete="off"><button class="mini principal" onclick="rvAjIa(\'' + x[0] + '\')">Salvar</button>' + (v.tem && x[0] !== 'cloudflare_conta' ? '<button class="mini" onclick="rvAjIaTestar(\'' + x[0] + '\')">🧪 Testar</button>' : '') + (v.tem ? '<button class="mini" onclick="rvAjIa(\'' + x[0] + '\',true)" title="Apagar">🗑️</button>' : '') + '</div><div id="aj_ia_t_' + x[0] + '"></div></div>'; }).join('') + '<p class="linha" style="justify-content:flex-start"><button class="mini principal" onclick="rvAjIaTestar(\'todas\')">🧪 Testar todas as chaves</button></p><small class="mudo">O teste só pergunta ao provedor se a chave vale (não gasta a cota). A chave não sai do servidor.</small><div id="aj_ia_res"></div></div>' + comandaAjHtml(a.comanda || {}) + '</div>'
   + '<div><div class="card"><h2>🏪 Dados do restaurante</h2><p class="mudo pequeno">Aparecem no cardápio, nas impressões e para o atendente virtual.</p>'
   + DADOS_REST.map(x => '<label for="aj_d_' + x[0] + '">' + x[1] + '</label>' + (x[2] > 100 ? '<textarea id="aj_d_' + x[0] + '" maxlength="' + x[2] + '" rows="2">' + esc(d[x[0]] || '') + '</textarea>' : '<input id="aj_d_' + x[0] + '" maxlength="' + x[2] + '" value="' + esc(d[x[0]] || '') + '">')).join('')
   + '<p><button class="principal" onclick="rvAjDados()">💾 Salvar dados</button></p><div id="aj_d_res"></div></div>'
   + '<div class="card"><h2>👥 Usuários do sistema</h2><p class="mudo pequeno">Para quando alguém esquece a senha. Peça a ele uma senha nova (mínimo 8, com letras e números) ou crie uma e passe para ele.</p>'
   + ((a.usuarios || []).length ? (a.usuarios || []).map(u => '<div class="linha mapa-l"><span>' + (u.ativo ? '' : '⏸️ ') + '<b>' + esc(u.login) + '</b> <small class="mudo">' + esc(u.nivel) + (u.ativo ? '' : ' · desativado') + '</small></span><button class="mini" onclick="rvAjSenha(\'' + esc(u.login).replace(/'/g, '&#39;') + '\')">🔑 Trocar senha</button></div>').join('') : '<small class="mudo">Nenhum usuário ainda (etapa "Criar os logins").</small>')
   + '<div id="aj_s_res"></div></div>'
   + '<div class="card"><h2>🛠️ Logins de Desenvolvedor</h2><p class="mudo pequeno">Os seus logins de suporte neste restaurante. Dentro do sistema dele eles ficam protegidos: só você mexe aqui. Entram mesmo com o restaurante bloqueado e não veem os termos de uso.</p><div id="aj_dev"><small class="mudo">Carregando…</small></div><p class="linha" style="justify-content:flex-start"><button class="mini" onclick="rvAjDev(\'criar\')">➕ Novo Desenvolvedor</button></p><div id="aj_dev_res"></div></div>'
   + ((a.integracoes || []).length ? '<div class="card"><h2>🔗 Integrações</h2><p class="mudo pequeno">Só para ver. Ligar ou desligar é dentro do sistema dele (Administrador → Sistema → Integrações), porque cada uma tem o seu passo a passo.</p>'
      + a.integracoes.map(x => '<div class="linha mapa-l"><span>' + (x.ligado ? '🟢' : '⚪') + ' <b>' + esc({ ifood:'iFood', nfce:'Nota fiscal (NFC-e)', mercadopago:'Mercado Pago', infinitepay:'InfinitePay' }[x.provedor] || x.provedor) + '</b></span><small class="mudo">' + (x.ligado ? 'ligado' : 'desligado') + (x.modo ? ' · ' + esc(x.modo === 'producao' ? 'produção' : 'teste') : '') + '</small></div>').join('') + '</div>' : '')
   + '</div></div>');
  setTimeout(() => { if(window.rvAjDev) rvAjDev('listar'); }, 0);
}
window.rvAjDev = async (acao, login, extra) => {
  const r = S.rest; if(!r) return; const box = $('aj_dev'), res = $('aj_dev_res');
  const msg = h => { if(res) res.innerHTML = h; };
  const pe = { acao };
  if(acao === 'criar'){
    login = prompt('Login do novo Desenvolvedor (3 a 30 letras ou números):'); if(!login) return;
    const nova = prompt('Senha para "' + login + '" (mínimo 8, com letras e números):'); if(!nova) return; pe.novaSenha = nova;
  } else if(acao === 'senha'){
    const nova = prompt('Nova senha para "' + login + '" (mínimo 8, com letras e números):'); if(!nova) return; pe.novaSenha = nova;
  } else if(acao === 'ativar'){ pe.ativo = !!extra; }
  pe.login = login || '';
  let conf = '';
  if(acao !== 'listar'){ conf = prompt('Para confirmar, digite o nome do restaurante exatamente:'); if(conf !== r.nome) return erro('O nome não confere. Nada foi feito.'); msg('<small class="mudo">Aplicando…</small>'); }
  try{
    const a = await chamarConector({ acao:'sb_dev', restaurante_id:r.id, confirmar:conf, p:pe }); if(!a.ok) throw new Error(a.erro || 'Não foi possível.');
    if(acao !== 'listar'){ msg(conLinha(true, esc(a.message || 'Pronto.'))); hist(r.id, 'Desenvolvedor: ' + acao, login || ''); return rvAjDev('listar'); }
    if(box) box.innerHTML = (a.devs || []).map(u => '<div class="linha mapa-l"><span>' + (u.ativo ? '' : '⏸️ ') + '<b>' + esc(u.login) + '</b>' + (u.ativo ? '' : ' <small class="mudo">desativado</small>') + '</span><span><button class="mini" onclick="rvAjDev(\'senha\',\'' + esc(u.login).replace(/'/g, '&#39;') + '\')">🔑 Senha</button> <button class="mini" onclick="rvAjDev(\'ativar\',\'' + esc(u.login).replace(/'/g, '&#39;') + '\',' + (u.ativo ? 'false' : 'true') + ')">' + (u.ativo ? '⏸️ Desativar' : '▶️ Ativar') + '</button></span></div>').join('') || '<small class="mudo">Nenhum Desenvolvedor.</small>';
  }catch(e){ if(acao === 'listar'){ if(box) box.innerHTML = conLinha(false, esc(e.message)); } else msg(conLinha(false, esc(e.message))); }
};
/* comanda (impressão do pedido): mesma regra da tela Administrador → Sistema → Comanda do restaurante */
const CM_SIM = [['mostrarLogo','Logo no topo'],['mostrarTelefone','Telefone do cliente'],['mostrarEntregador','Nome do entregador'],['mostrarHoraImpressa','Hora da impressão'],['mostrarWhatsapp','WhatsApp da loja'],['mostrarVersiculo','Versículo'],['mostrarQr','QR Code']];
const CM_TXT = [['topo','Texto do topo',60],['whatsapp','WhatsApp da loja (com DDD)',20],['agradecimento','Agradecimento',120],['versiculo','Versículo',260],['qrTitulo','Título do QR Code',40],['qrTexto','Texto do QR Code',140]];
function comandaAjHtml(c){
  const sel = (id, ops, v) => '<select id="' + id + '">' + ops.map(o => '<option value="' + o[0] + '"' + (o[0] === v ? ' selected' : '') + '>' + o[1] + '</option>').join('') + '</select>';
  return '<div class="card"><h2>🧾 Comanda (impressão do pedido)</h2><p class="mudo pequeno">O que sai no papel. A logo em si é a da aba Marca. Vale para todos os aparelhos na próxima impressão.</p>'
   + '<div class="cols"><div><label for="aj_c_tamanho">Tamanho da letra</label>' + sel('aj_c_tamanho', [['pequena','Pequena'],['normal','Normal'],['grande','Grande']], c.tamanho || 'normal') + '</div><div><label for="aj_c_logoTamanho">Tamanho da logo</label>' + sel('aj_c_logoTamanho', [['pequeno','Pequena'],['medio','Média'],['grande','Grande']], c.logoTamanho || 'medio') + '</div></div>'
   + '<div class="chips-sim">' + CM_SIM.map(x => '<label class="chk"><input type="checkbox" id="aj_c_' + x[0] + '"' + (c[x[0]] === false ? '' : ' checked') + '> ' + x[1] + '</label>').join('') + '</div>'
   + CM_TXT.map(x => '<label for="aj_c_' + x[0] + '">' + x[1] + '</label>' + (x[2] > 100 ? '<textarea id="aj_c_' + x[0] + '" maxlength="' + x[2] + '" rows="2">' + esc(c[x[0]] || '') + '</textarea>' : '<input id="aj_c_' + x[0] + '" maxlength="' + x[2] + '"' + (x[0] === 'whatsapp' ? ' inputmode="tel"' : '') + ' value="' + esc(c[x[0]] || '') + '">')).join('')
   + '<p class="linha" style="justify-content:flex-start"><button class="principal" onclick="rvAjComanda()">💾 Salvar comanda</button><button class="mini" onclick="rvAjComanda(true)">↺ Voltar ao padrão</button></p><div id="aj_c_res"></div></div>';
}
window.rvAjComanda = async padrao => {
  const r = S.rest; if(padrao && !confirm('Voltar a comanda de ' + r.nome + ' ao padrão original?')) return;
  const c = { tamanho:jv('aj_c_tamanho'), logoTamanho:jv('aj_c_logoTamanho') }; CM_SIM.forEach(x => { c[x[0]] = !!($('aj_c_' + x[0]) || {}).checked; }); CM_TXT.forEach(x => { c[x[0]] = jv('aj_c_' + x[0]) || ''; });
  const box = $('aj_c_res'); if(box) box.innerHTML = '<small class="mudo">Salvando…</small>';
  try{ const a = await chamarConector({ acao:'sb_ajustes', restaurante_id:r.id, p:{ acao:'comanda_salvar', config:c, padrao:!!padrao } });
    if(box) box.innerHTML = conLinha(a.ok, esc(a.ok ? (a.message || 'Salvo.') : a.erro)); if(a.ok){ hist(r.id, 'Comanda ajustada pelo painel', padrao ? 'padrão' : ''); if(padrao) abaAjustesRest(); } }catch(e){ if(box) box.innerHTML = conLinha(false, esc(e.message)); }
};
window.rvAjIaTestar = async prov => {
  const r = S.rest, nomes = {}; IA_REST.forEach(x => { nomes[x[0]] = x[1]; });
  const alvo = prov === 'todas' ? $('aj_ia_res') : $('aj_ia_t_' + prov); if(alvo) alvo.innerHTML = '<small class="mudo">⏳ Testando… pode levar uns segundos</small>';
  try{ const a = await chamarConector({ acao:'sb_ia_testar', restaurante_id:r.id, provedor:prov }); if(!a.ok) throw new Error(a.erro || 'Não consegui testar.');
    const linha = y => (y.funcionando === true ? conLinha(true, '<b>' + esc(nomes[y.provedor] || y.provedor) + '</b>: funcionando' + (y.ms ? ' (' + (Math.round(y.ms / 100) / 10).toString().replace('.', ',') + ' s)' : '') + (y.motivo ? '. ' + esc(y.motivo) : ''))
      : y.funcionando === null ? amarela('<b>' + esc(nomes[y.provedor] || y.provedor) + '</b>: ' + esc(y.motivo))
      : (y.tem ? conLinha(false, '<b>' + esc(nomes[y.provedor] || y.provedor) + '</b>: ' + esc(y.motivo)) : '<div class="res"><small class="mudo">➖ <b>' + esc(nomes[y.provedor] || y.provedor) + '</b>: sem chave</small></div>'));
    if(prov === 'todas'){ const R = a.resultados || [], ok = R.filter(y => y.funcionando === true).length, ruim = R.filter(y => y.funcionando === false && y.tem).length;
      alvo.innerHTML = (R.some(y => y.tem) ? '' : '<div class="res erro">Nenhuma chave cadastrada neste restaurante.</div>') + R.map(linha).join('') + '<small class="mudo">' + ok + ' funcionando' + (ruim ? ' · ' + ruim + ' com problema' : '') + '. O mínimo para o atendente é Groq + Gemini.</small>';
    } else alvo.innerHTML = (a.resultados || []).map(linha).join('');
    hist(r.id, 'Chaves de IA testadas pelo painel', prov);
  }catch(e){ if(alvo) alvo.innerHTML = conLinha(false, esc(e.message)); }
};
window.rvAjIa = async (prov, apagar) => {
  const r = S.rest, inp = $('aj_ia_' + prov), v = apagar ? '' : jv('aj_ia_' + prov);
  if(!apagar && !v) return erro('Cole a chave no campo.');
  if(apagar && !confirm('Apagar esta chave no sistema de ' + r.nome + '?')) return;
  if(prov === 'cloudflare_conta' && v && !/^[0-9a-f]{32}$/.test(v)) return erro('O Account ID tem 32 letras (a-f) e números.');
  const box = $('aj_ia_res'); if(box) box.innerHTML = '<small class="mudo">Salvando…</small>';
  try{ const a = await chamarConector({ acao:'sb_ajustes', restaurante_id:r.id, p:{ acao:'ia_salvar', provedor:prov, chave:v } });
    if(!a.ok) throw new Error(a.erro || 'Não salvou.'); if(inp) inp.value = ''; aviso((a.message || 'Salvo.') + ' ✓', 'ok'); hist(r.id, 'Chave de IA ' + (apagar ? 'apagada' : 'trocada') + ' pelo painel', prov); abaAjustesRest();
  }catch(e){ if(box) box.innerHTML = conLinha(false, esc(e.message)); }
};
window.rvAjDados = async () => {
  const r = S.rest, p = { acao:'dados_salvar' }; DADOS_REST.forEach(x => { p[x[0]] = (($('aj_d_' + x[0]) || {}).value || '').trim(); });
  const box = $('aj_d_res'); if(box) box.innerHTML = '<small class="mudo">Salvando…</small>';
  try{ const a = await chamarConector({ acao:'sb_ajustes', restaurante_id:r.id, p }); if(!a.ok) throw new Error(a.erro || 'Não salvou.');
    if(box) box.innerHTML = conLinha(true, esc(a.message || 'Salvo.')); hist(r.id, 'Dados do restaurante mudados pelo painel', '');
  }catch(e){ if(box) box.innerHTML = conLinha(false, esc(e.message)); }
};
window.rvAjSenha = async login => {
  const r = S.rest, nova = prompt('Nova senha para "' + login + '" em ' + r.nome + ' (mínimo 8, com letras e números):'); if(!nova) return;
  const nome = prompt('Para confirmar, digite o nome do restaurante exatamente:'); if(nome !== r.nome) return erro('O nome não confere. Nada foi feito.');
  const box = $('aj_s_res'); if(box) box.innerHTML = '<small class="mudo">Trocando…</small>';
  try{ const a = await chamarConector({ acao:'sb_ajustes', restaurante_id:r.id, confirmar:nome, p:{ acao:'senha', login, novaSenha:nova } }); if(!a.ok) throw new Error(a.erro || 'Não trocou.');
    if(box) box.innerHTML = conLinha(true, esc(a.message || 'Senha trocada.') + ' Passe a nova senha para ' + esc(login) + ' por um canal seguro.'); hist(r.id, 'Senha trocada pelo painel', login);
  }catch(e){ if(box) box.innerHTML = conLinha(false, esc(e.message)); }
};
async function chamarAssistente(corpo){
  if(S.sess && Date.now() > S.sess.exp && !await renovar()) throw new Error('Sua sessão expirou. Entre de novo.');
  const c = new AbortController(), t = setTimeout(() => c.abort(), 130000);
  try{ const r = await fetch(URL_ + '/functions/v1/assistente', { method:'POST', signal:c.signal, headers:{ apikey:CHAVE_, Authorization:'Bearer ' + S.sess.access_token, 'Content-Type':'application/json' }, body:JSON.stringify(corpo) });
    const j = await r.json().catch(() => null); if(!j) throw new Error('O assistente não respondeu (erro ' + r.status + ').'); if(r.status === 404) throw new Error('A função do assistente ainda não foi publicada no servidor do painel.'); return j;
  }catch(e){ if(e.name === 'AbortError') throw new Error('Demorou demais. Tente uma pergunta mais curta.'); throw e; } finally { clearTimeout(t); }
}
window.rvTestarIAs = async () => { const b = $('iaTeste'); b.innerHTML = '<div class="res aviso">⏳ Testando cada IA…</div>';
  try{ const j = await chamarAssistente({ acao:'testar' }); if(!j.ok) throw new Error(j.erro); b.innerHTML = j.resultados.map(x => '<div class="res ' + (x.ok ? 'ok' : 'erro') + '">' + (x.ok ? '✅ ' : '❌ ') + '<b>' + esc(x.nome) + '</b>: ' + (x.ok ? 'funcionando · ' + esc(x.modelo) + ' · ' + x.ms + ' ms' : esc(x.erro)) + '</div>').join(''); }
  catch(e){ b.innerHTML = '<div class="res erro">❌ ' + esc(e.message) + '</div>'; } };

/* ---------- ASSISTENTE: conversa ---------- */
const CHAT_K = 'rv_chat_v1';
function chatLer(){ try{ return JSON.parse(localStorage.getItem(CHAT_K) || '[]'); }catch(e){ return []; } }
function chatGravar(){ try{ localStorage.setItem(CHAT_K, JSON.stringify((S.chat || []).slice(-40))); }catch(e){} }
const SUGESTOES = ['Como está o meu mês?','Quem está com mensalidade atrasada?','Algum restaurante com problema agora?','Quanto cada restaurante vendeu nesta semana?','O que falta para terminar a implantação do Teste?','Quanto cobram sistemas de cardápio digital hoje no Brasil?'];
function telaAtual(){ const v = S.view; if(v === 'rest' && S.rest) return 'restaurante ' + S.rest.nome + ', aba ' + S.aba; return { inicio:'Início', restaurantes:'lista de restaurantes', saude:'Saúde', dinheiro:'Dinheiro, mês ' + S.mes, vendas:'Vendas (propostas)', mais:'Mais', ajustes:'Ajustes', guia:'Guia', assistente:'configuração do assistente', usuarios:'usuários do painel', novo:'criar restaurante' }[v] || v; }
function md(t){ let h = esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
  return h.split('\n').map(l => /^\s*([-•*]|\d+[.)])\s+/.test(l) ? '<li>' + l.replace(/^\s*([-•*]|\d+[.)])\s+/, '') + '</li>' : (l.trim() ? '<p>' + l + '</p>' : '')).join('').replace(/(<li>.*?<\/li>)+/g, m => '<ul>' + m + '</ul>'); }
const ROT_ACAO = { gerar_cobranca:'💰 Gerar cobrança', registrar_recebimento:'💵 Registrar recebimento', criar_despesa:'🧾 Lançar despesa', criar_proposta:'🤝 Criar proposta', atualizar_proposta:'✏️ Atualizar proposta', enviar_whatsapp:'💬 Mandar WhatsApp', marcar_erros_resolvidos:'🐞 Marcar erros como resolvidos', abrir_tela:'➡️ Abrir tela' };
function detAcao(a){ const d = a.dados || {}, L = [];
  if(d.restaurante_nome) L.push('Restaurante: ' + d.restaurante_nome); if(d.nome) L.push('Nome: ' + d.nome); if(d.descricao) L.push('Descrição: ' + d.descricao);
  if(d.valor != null) L.push('Valor: ' + BRL(d.valor)); if(d.valor_mensal != null) L.push('Mensalidade: ' + BRL(d.valor_mensal)); if(d.vencimento) L.push('Vencimento: ' + dataBr(d.vencimento)); if(d.data) L.push('Data: ' + dataBr(d.data));
  if(d.forma) L.push('Forma: ' + d.forma); if(d.categoria) L.push('Categoria: ' + d.categoria); if(d.status) L.push('Situação: ' + (ST_PROP[d.status] || d.status)); if(d.proxima_acao) L.push('Retornar em: ' + dataBr(d.proxima_acao));
  if(d.texto) L.push('Mensagem: "' + String(d.texto).slice(0, 300) + '"'); if(d.tela) L.push('Tela: ' + d.tela); return L; }
window.rvChat = () => { S.chat = S.chat || chatLer(); S.chatAberto = true; desenharChat(); setTimeout(() => { const i = $('chatTxt'); if(i) i.focus(); }, 80); };
window.rvChatFechar = () => { S.chatAberto = false; const c = $('chat'); if(c) c.remove(); };
window.rvChatLimpar = () => { if(!confirm('Apagar a conversa?')) return; S.chat = []; chatGravar(); desenharChat(); };
function desenharChat(){
  let c = $('chat'); if(!c){ c = document.createElement('div'); c.id = 'chat'; c.className = 'chat'; document.body.appendChild(c); }
  const txt = ($('chatTxt') || {}).value != null ? $('chatTxt').value : (S.chatTxt || '');
  const M = S.chat || [];
  c.innerHTML = '<div class="chat-c"><div class="chat-cab"><b>✨ Assistente</b><span><button class="mini" onclick="rvChatLimpar()" title="Apagar conversa">🗑️</button> <button class="mini" onclick="rvChatFechar()">✕</button></span></div>'
   + '<div class="chat-msgs" id="chatMsgs">' + (M.length ? '' : '<div class="chat-vazio"><div style="font-size:40px">✨</div><b>Pergunte qualquer coisa sobre o seu negócio</b><p class="mudo pequeno">Eu leio os seus restaurantes, o seu dinheiro, a saúde dos sistemas e pesquiso na internet. Quando você pedir para fazer algo, eu deixo pronto para você confirmar.</p></div><div class="sugestoes">' + SUGESTOES.map(x => '<button class="chip" onclick="rvChatEnviar(' + esc(JSON.stringify(x)) + ')">' + esc(x) + '</button>').join('') + '</div>')
   + M.map((m, i) => '<div class="bolha-m ' + m.role + (m.erro ? ' erro' : '') + '">' + (m.role === 'user' ? esc(m.content).replace(/\n/g, '<br>') : md(m.content))
      + (m.acoes && m.acoes.length ? m.acoes.map((a, k) => '<div class="acao-c ' + (a.estado || 'pendente') + '"><b>' + (ROT_ACAO[a.tipo] || a.tipo) + '</b><small>' + esc(a.resumo || '') + '</small>' + detAcao(a).map(l => '<small class="mudo">' + esc(l) + '</small>').join('')
          + (a.estado === 'feita' ? '<span class="selo ativo">✓ Feito</span>' : a.estado === 'descartada' ? '<span class="selo">Descartada</span>' : '<div class="linha" style="justify-content:flex-start;margin-top:6px"><button class="mini principal" onclick="rvAcao(' + i + ',' + k + ')">✅ Confirmar</button><button class="mini" onclick="rvAcaoDesc(' + i + ',' + k + ')">Descartar</button></div>') + '</div>').join('') : '')
      + (m.fontes && m.fontes.length ? '<div class="fontes">🔎 ' + m.fontes.map(f => '<a href="' + esc(f.url) + '" target="_blank" rel="noopener">' + esc(String(f.titulo || f.url).slice(0, 40)) + '</a>').join(' · ') + '</div>' : '')
      + (m.info ? '<small class="info-m">' + esc(m.info) + '</small>' : '') + '</div>').join('')
   + (S.chatEspera ? '<div class="bolha-m assistant esperando"><span class="pontinhos"><i></i><i></i><i></i></span> <small class="mudo">' + esc(S.chatEspera) + '</small></div>' : '') + '</div>'
   + '<div class="chat-in"><textarea id="chatTxt" rows="1" placeholder="Pergunte ou peça algo…" oninput="this.style.height=\'auto\';this.style.height=Math.min(120,this.scrollHeight)+\'px\'" onkeydown="if(event.key===\'Enter\'&&!event.shiftKey){event.preventDefault();rvChatEnviar()}">' + esc(txt) + '</textarea><button class="principal" onclick="rvChatEnviar()"' + (S.chatEspera ? ' disabled' : '') + ' aria-label="Enviar">➤</button></div></div>';
  const ms = $('chatMsgs'); if(ms) ms.scrollTop = ms.scrollHeight;
}
window.rvChatEnviar = async (pronto) => {
  if(S.chatEspera) return; const i = $('chatTxt'), q = String(pronto || (i && i.value) || '').trim(); if(!q) return;
  if(!Object.keys(S.segs || {}).some(k => /^ia_/.test(k))){ erro('Cadastre as chaves das IAs primeiro (Mais → Assistente).'); return; }
  S.chat = S.chat || []; S.chat.push({ role:'user', content:q }); if(i) i.value = ''; S.chatTxt = ''; S.chatEspera = 'pensando…'; chatGravar(); desenharChat();
  const fr = ['pensando…','consultando os dados…','juntando as informações…','quase lá…'], tf = setInterval(() => { S.chatEspera = fr[(fr.indexOf(S.chatEspera) + 1) % fr.length]; const e = document.querySelector('.esperando small'); if(e) e.textContent = S.chatEspera; }, 3500);
  try{ const j = await chamarAssistente({ mensagens:S.chat.filter(m => !m.erro).slice(-12).map(m => ({ role:m.role, content:m.content })), tela:telaAtual() });
    if(!j.ok) throw new Error(j.erro || 'sem resposta');
    S.chat.push({ role:'assistant', content:j.texto, acoes:(j.acoes || []).map(a => Object.assign(a, { estado:'pendente' })), fontes:j.fontes || [], info:j.provedor + (j.ferramentas ? ' · ' + j.ferramentas + ' consulta(s)' : '') });
  }catch(e){ S.chat.push({ role:'assistant', content:'⚠️ ' + e.message, erro:true }); }
  finally{ clearInterval(tf); S.chatEspera = null; chatGravar(); if(S.chatAberto) desenharChat(); }
};
window.rvAcaoDesc = (i, k) => { S.chat[i].acoes[k].estado = 'descartada'; chatGravar(); desenharChat(); };
window.rvAcao = async (i, k) => {
  const a = S.chat[i].acoes[k], d = a.dados || {}, agora = new Date().toISOString();
  try{
    if(a.tipo === 'gerar_cobranca'){ const v = num(d.valor), venc = d.vencimento || hoje(); if(!d.restaurante_id || !v) throw new Error('Faltam o restaurante ou o valor.');
      await rest('cobrancas', 'POST', { restaurante_id:d.restaurante_id, tipo:['mensalidade','implantacao','avulsa'].includes(d.tipo) ? d.tipo : 'avulsa', valor:v, vencimento:venc, competencia:venc.slice(0, 8) + '01', descricao:d.descricao || null }); await hist(d.restaurante_id, 'Cobrança criada pelo assistente', BRL(v)); }
    else if(a.tipo === 'registrar_recebimento'){ if(!d.cobranca_id) throw new Error('Falta a cobrança.'); const c = S.cob.find(x => x.id === d.cobranca_id); if(!c) throw new Error('Cobrança não encontrada.');
      await rest('cobrancas?id=eq.' + d.cobranca_id, 'PATCH', { pago_em:d.data || hoje(), valor_pago:num(d.valor) != null ? num(d.valor) : c.valor, forma:d.forma || 'Pix' }); await hist(c.restaurante_id, 'Pagamento recebido (assistente)', BRL(num(d.valor) || c.valor)); }
    else if(a.tipo === 'criar_despesa'){ const v = num(d.valor); if(!d.descricao || v == null) throw new Error('Faltam a descrição ou o valor.');
      await rest('despesas_revenda', 'POST', { descricao:d.descricao, valor:v, data:d.data || hoje(), categoria:CAT_DESP.includes(d.categoria) ? d.categoria : 'Outros', pago:d.pago !== false, recorrente:!!d.recorrente, restaurante_id:d.restaurante_id || null }); }
    else if(a.tipo === 'criar_proposta'){ if(!d.nome) throw new Error('Falta o nome.');
      await rest('propostas', 'POST', { nome:d.nome, contato_nome:d.contato_nome || null, telefone:d.telefone || null, cidade:d.cidade || null, origem:d.origem || null, status:ST_PROP[d.status] ? d.status : 'novo', valor_mensal:num(d.valor_mensal), taxa_implantacao:num(d.taxa_implantacao), proxima_acao:d.proxima_acao || null, observacoes:d.observacoes || null }); }
    else if(a.tipo === 'atualizar_proposta'){ if(!d.proposta_id) throw new Error('Falta a proposta.'); const c = { atualizado_em:agora }; if(ST_PROP[d.status]) c.status = d.status; if(d.proxima_acao) c.proxima_acao = d.proxima_acao; if(d.observacoes) c.observacoes = d.observacoes;
      await rest('propostas?id=eq.' + d.proposta_id, 'PATCH', c); }
    else if(a.tipo === 'enviar_whatsapp'){ const l = waLink(d.telefone, d.texto); if(!l) throw new Error('Falta o telefone.'); window.open(l, '_blank'); }
    else if(a.tipo === 'marcar_erros_resolvidos'){ if(!d.restaurante_slug) throw new Error('Falta o restaurante.'); await rest('erros_app?slug=eq.' + encodeURIComponent(d.restaurante_slug) + '&resolvido=eq.false', 'PATCH', { resolvido:true, resolvido_em:agora }); }
    else if(a.tipo === 'abrir_tela'){ a.estado = 'feita'; chatGravar(); rvChatFechar(); if(d.restaurante_id) return rvAbrir(d.restaurante_id); return rvIr(['inicio','restaurantes','saude','dinheiro','vendas'].includes(d.tela) ? d.tela : 'inicio'); }
    a.estado = 'feita'; chatGravar(); aviso('Feito ✓', 'ok');
    if(a.tipo !== 'enviar_whatsapp'){ await carregar(); if(S.rest){ const x = S.lista.find(r => r.id === S.rest.id); if(x) S.rest = normalizar(JSON.parse(JSON.stringify(x))); await carregarRest(); } desenhar(); }
  }catch(e){ erro('Não deu: ' + e.message); }
  if(S.chatAberto) desenharChat();
};

S.sess = sessLer(); tela();
})();
