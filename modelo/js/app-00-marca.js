/* =====================================================================
   MARCA DO RESTAURANTE — nome, cores, logos e ícone do app, vindos de config-restaurante.js
   e, depois, da tela Administrador → Sistema → Aparência (guardada neste aparelho para abrir já com a marca certa).
   Carregado ANTES de tudo, para a página nunca "piscar" com outra cor.
   ===================================================================== */
(function(){
  'use strict';
  const R = window.RESTAURANTE = window.RESTAURANTE || {};
  /* logo e ícone padrão moram no motor (todo restaurante tem), não no site do restaurante: assim nunca apontam para um arquivo que não existe */
  const MOTOR = typeof window.MOTOR_URL_ === 'string' ? window.MOTOR_URL_ : '';
  const BASE = { slogan:'', assistente:'Assistente', tema:'classico', cores:{ destaque:'#d9a21b', botao:'#8c1c13', fundo:'#14100c' }, logos:{ cardapio:MOTOR + 'img/logo.png', impressao:'', icone:MOTOR + 'img/icon-512.png' } };
  /* logo vazio vindo do painel ou do cache ("sem logo escolhida") não apaga a logo/ícone padrão; só a de impressão pode ficar vazia */
  const comValor = l => { const o = Object.assign({}, l || {}); ['cardapio', 'icone'].forEach(k => { if(!o[k]) delete o[k]; }); return o; };
  const CHAVE_CACHE = 'marcaRestaurante_v1';
  const HEX = /^#[0-9a-fA-F]{6}$/;

  function lerCache(){ try{ const j = JSON.parse(localStorage.getItem(CHAVE_CACHE) || 'null'); return j && typeof j === 'object' ? j : null; }catch(e){ return null; } }
  function mesclar(){
    const c = lerCache() || {}, a = R.marca || {};
    const cores = Object.assign({}, BASE.cores, a.cores || {}, c.cores || {});
    ['destaque','botao','fundo'].forEach(k => { if(!HEX.test(cores[k])) cores[k] = BASE.cores[k]; });
    return { nome: c.nome || R.nome || 'Meu Restaurante', slogan: c.slogan != null ? c.slogan : (a.slogan || ''), assistente: c.assistente || a.assistente || BASE.assistente,
      tema: c.tema || a.tema || BASE.tema, cores, logos: Object.assign({}, BASE.logos, comValor(a.logos), comValor(c.logos)) };
  }
  /* ---------- cores ---------- */
  const h2r = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const r2h = a => '#' + a.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
  const mix = (a, b, t) => { const x = h2r(a), y = h2r(b); return r2h(x.map((v, i) => v + (y[i] - v) * t)); };
  const lum = h => { const [r, g, b] = h2r(h).map(v => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }); return .2126 * r + .7152 * g + .0722 * b; };
  const tinta = h => (lum(h) > .35 ? '#1a1410' : '#ffffff');
  function paleta(c){
    const d = c.destaque, b = c.botao, f = c.fundo, claro = '#ffffff', escuro = '#000000';
    const modoClaro = lum(f) > .4;   /* fundo claro: a "tinta" do texto fica escura e os painéis escurecem em vez de clarear */
    const lado = modoClaro ? escuro : claro;                 /* direção em que painéis e linhas se afastam do fundo */
    const cream = modoClaro ? mix(escuro, d, .10) : mix(claro, d, .10);   /* cor do texto */
    const eqB = modoClaro ? mix(f, escuro, .04) : mix(f, escuro, .12), eqC = modoClaro ? mix(escuro, d, .06) : mix(claro, d, .05);
    return {
      '--bg-campo': modoClaro ? mix(f, claro, .7) : '#100c09', '--bg-hero': modoClaro ? mix(f, escuro, .05) : escuro, '--bg-barra': modoClaro ? mix(f, claro, .06) : mix(f, escuro, .03), '--bg': f, '--panel': mix(f, lado, modoClaro ? .04 : .05), '--panel-2': mix(f, lado, modoClaro ? .08 : .09), '--line': mix(f, modoClaro ? escuro : d, modoClaro ? .16 : .22), '--line-forte': mix(f, modoClaro ? escuro : d, modoClaro ? .30 : .38),
      '--gold': d, '--gold-rgb': h2r(d).join(','), '--gold-hi': mix(d, claro, .22), '--gold-lo': mix(d, escuro, .28), '--gold-dim': mix(d, escuro, .22),
      '--red': b, '--red-rgb': h2r(b).join(','), '--red-hi': mix(b, claro, .18), '--red-dim': mix(b, escuro, .32),
      '--on-gold': tinta(d), '--cream': cream, '--muted': mix(cream, f, modoClaro ? .45 : .40),
      '--eq-bg': eqB, '--eq-panel': mix(eqB, lado, modoClaro ? .05 : .06), '--eq-panel-2': mix(eqB, lado, modoClaro ? .09 : .10), '--eq-panel-3': mix(eqB, lado, modoClaro ? .13 : .14),
      '--eq-line': modoClaro ? 'rgba(0,0,0,.12)' : 'rgba(255,236,200,.09)', '--eq-line-forte': modoClaro ? 'rgba(0,0,0,.22)' : 'rgba(255,236,200,.16)', '--eq-cream': eqC, '--eq-muted': mix(eqC, eqB, .42), 'color-scheme': modoClaro ? 'light' : 'dark'
    };
  }
  function pintar(m){
    let st = document.getElementById('marcaCss');
    if(!st){ st = document.createElement('style'); st.id = 'marcaCss'; (document.head || document.documentElement).appendChild(st); }
    /* Tema original "Brasa" (dourado/vermelho/marrom-escuro): usa as cores escritas à mão no CSS, sem recalcular, para ficar idêntico ao visual aprovado. */
    const c0 = m.cores || {};
    if(String(c0.destaque).toLowerCase() === '#e0b53a' && String(c0.botao).toLowerCase() === '#d20807' && String(c0.fundo).toLowerCase() === '#0b0705'){ st.textContent = ''; document.documentElement.setAttribute('data-modo', 'escuro'); return; }
    const p = paleta(m.cores);
    document.documentElement.setAttribute('data-modo', lum(m.cores.fundo) > .4 ? 'claro' : 'escuro');
    st.textContent = 'html:root{' + Object.keys(p).map(k => k + ':' + p[k] + ';').join('') + '}';
  }
  /* ---------- manifesto do app (nome, cor e ícone do restaurante) ---------- */
  function absoluta(u){ try{ return new URL(u, location.href).href; }catch(e){ return u; } }
  function manifesto(m){
    try{
      const ic = absoluta(m.logos.icone || BASE.logos.icone), base = location.href.split('?')[0].replace(/[^/]*$/, '');
      const j = { id:base, name:m.nome, short_name:m.nome.length > 14 ? m.nome.slice(0, 14) : m.nome, description:'Cardápio digital e pedidos de ' + m.nome, lang:'pt-BR', start_url:base, scope:base, display:'standalone', orientation:'any',
        background_color:m.cores.fundo, theme_color:m.cores.fundo, icons:[{ src:ic, sizes:'512x512', type:'image/png', purpose:'any' }, { src:ic, sizes:'512x512', type:'image/png', purpose:'maskable' }] };
      const url = URL.createObjectURL(new Blob([JSON.stringify(j)], { type:'application/manifest+json' }));
      let l = document.querySelector('link[rel="manifest"]'); if(!l){ l = document.createElement('link'); l.rel = 'manifest'; document.head.appendChild(l); }
      l.href = url;
    }catch(e){}
  }
  function textos(m){
    document.title = m.nome;
    const t = document.querySelector('meta[name="theme-color"]'); if(t) t.content = m.cores.fundo;
    const a = document.querySelector('meta[name="apple-mobile-web-app-title"]'); if(a) a.content = m.nome;
    const ic = document.querySelector('link[rel="icon"]'); if(ic && m.logos.icone) ic.href = m.logos.icone;
    const ap = document.querySelector('link[rel="apple-touch-icon"]'); if(ap && m.logos.icone) ap.href = m.logos.icone;
    document.querySelectorAll('[data-marca-logo]').forEach(i => { const u = m.logos[i.getAttribute('data-marca-logo')] || m.logos.cardapio; if(u && i.getAttribute('src') !== u) i.setAttribute('src', u); i.setAttribute('alt', m.nome); });
    document.querySelectorAll('[data-marca-nome]').forEach(e => { e.textContent = m.nome; });
    document.querySelectorAll('[data-marca-icone]').forEach(i => { if(m.logos.icone) i.setAttribute('src', m.logos.icone); });
    const sp = document.getElementById('txbSplashCss'); if(sp) sp.textContent = 'html.txb-equipe::before{content:"";position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483000;background:' + m.cores.fundo + ' url(' + (m.logos.cardapio || '') + ') center center/min(52vw,210px) auto no-repeat;}';
  }
  function aplicar(){ const m = window.MARCA = mesclar(); window.NOME_RESTAURANTE_ = m.nome; window.ASSISTENTE_ = m.assistente || 'Assistente'; pintar(m); textos(m); manifesto(m); return m; }
  window.marcaAplicar_ = aplicar;
  /* Guarda a marca vinda do banco (Aparência) e aplica na hora */
  window.marcaGuardar_ = function(parcial){ try{ const c = Object.assign(lerCache() || {}, parcial || {}); localStorage.setItem(CHAVE_CACHE, JSON.stringify(c)); }catch(e){} return aplicar(); };
  const escH_ = t => String(t == null ? '' : t).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  window.ASSISTENTE_H_ = () => escH_(window.ASSISTENTE_);
  window.NOME_UP_ = () => String(window.NOME_RESTAURANTE_ || '').toUpperCase();
  window.NOME_H_ = () => escH_(window.NOME_RESTAURANTE_);
  window.NOME_UP_H_ = () => escH_(window.NOME_UP_());
  window.marcaLimpar_ = function(){ try{ localStorage.removeItem(CHAVE_CACHE); }catch(e){} return aplicar(); };
  window.marcaPaleta_ = paleta;
  window.kickerPadrao_ = function(){ const m = window.MARCA || {}; return m.slogan ? 'DELIVERY · ' + String(m.slogan).toUpperCase() : 'DELIVERY'; };
  aplicar();
  document.addEventListener('DOMContentLoaded', function(){ textos(window.MARCA);
    if(!R.supabaseUrl){
      const d = document.createElement('div');
      d.style.cssText = 'position:fixed;inset:0;z-index:2147483001;background:#14100c;color:#fff;display:flex;align-items:center;justify-content:center;padding:24px;text-align:center;font-family:sans-serif';
      d.innerHTML = '<div style="max-width:420px"><h2 style="margin:0 0 10px">Sistema ainda não configurado</h2><p style="line-height:1.5;opacity:.85">Este restaurante ainda não recebeu as ligações com o banco de dados. Peça a quem implantou o sistema para gerar o arquivo <b>config-restaurante.js</b> no Painel de Revenda.</p></div>';
      document.body.appendChild(d);
    } });
})();

/* =====================================================================
   ACESSO SUSPENSO — o fornecedor do sistema pode bloquear o restaurante (botão "Bloquear acesso" no Painel de Revenda).
   Nunca é automático. A verificação é feita pelo endereço do banco do restaurante (não dá para escapar trocando o nome).
   Sem internet ou se o painel não responder: o sistema continua abrindo (só vale o último bloqueio já visto neste aparelho).
   ===================================================================== */
(function(){
  'use strict';
  var PAINEL = 'https://ufoivqszbpznwwkpbvil.supabase.co', CHAVE = 'sb_publishable_u9l2Jz3-aMrnU1JKrQwEUw_46OKJ2m9', FLAG = 'rvAcessoSuspenso_v1';
  var R = window.RESTAURANTE || {}, FETCH = window.fetch.bind(window);
  if(!R.supabaseUrl && !R.slug) return;
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]; }); }
  function ler(){ try{ return JSON.parse(localStorage.getItem(FLAG) || 'null'); }catch(e){ return null; } }
  function gravar(v){ try{ if(v) localStorage.setItem(FLAG, JSON.stringify(v)); else localStorage.removeItem(FLAG); }catch(e){} }
  var estado = { msg:'', prom:null }, ativo = false, repintar = function(){}, enviando = false;
  function dataBr(d){ return String(d || '').split('-').reverse().join('/'); }
  function corpoPromessa(){
    var p = estado.prom;
    if(p && p.estado === 'pendente') return '<div style="background:#1d1d1d;border:1px solid #3a3a3a;border-radius:12px;padding:12px;margin:0 0 16px"><b>⏳ Promessa de pagamento enviada</b><br><span style="color:#cfc4c4;font-size:14px">Pagamento prometido para ' + esc(dataBr(p.data)) + '. Aguarde a aprovação do fornecedor: esta tela libera sozinha quando for aprovado.</span></div>';
    var rec = (p && p.estado === 'recusada') ? '<div style="color:#ff8a8a;font-size:14px;margin:0 0 10px">O último pedido não foi aprovado. Fale com o fornecedor do sistema.</div>' : '';
    var hj = new Date(), mx = new Date(Date.now() + 15 * 86400000);
    function iso(d){ return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
    return rec + '<div id="rvPromBox" style="margin:0 0 16px"><button onclick="document.getElementById(\'rvPromForm\').style.display=\'block\';this.style.display=\'none\'" style="font:inherit;padding:11px 20px;border:1px solid #d4262c;border-radius:12px;background:transparent;color:#f3ecec;font-weight:700">🤝 Prometer pagamento</button>'
      + '<div id="rvPromForm" style="display:none;text-align:left;background:#1d1d1d;border:1px solid #3a3a3a;border-radius:12px;padding:12px;margin-top:8px"><label style="font-size:14px;color:#cfc4c4">Em que dia você vai pagar?</label>'
      + '<input id="rvPromData" type="date" min="' + iso(hj) + '" max="' + iso(mx) + '" style="width:100%;box-sizing:border-box;margin:6px 0 10px;padding:10px;border-radius:10px;border:1px solid #444;background:#0a0a0a;color:#fff;font:inherit">'
      + '<label style="font-size:14px;color:#cfc4c4">Seu nome ou WhatsApp (para o fornecedor te responder)</label>'
      + '<input id="rvPromContato" maxlength="120" style="width:100%;box-sizing:border-box;margin:6px 0 10px;padding:10px;border-radius:10px;border:1px solid #444;background:#0a0a0a;color:#fff;font:inherit">'
      + '<div id="rvPromMsg" style="color:#ff8a8a;font-size:14px;min-height:18px"></div>'
      + '<button onclick="window.__rvPedirPromessa()" style="font:inherit;padding:11px 20px;border:0;border-radius:12px;background:#d4262c;color:#fff;font-weight:700;width:100%">Enviar pedido</button>'
      + '<div style="color:#9a8f8f;font-size:12px;margin-top:8px">O pedido só vale depois que o fornecedor aprovar.</div></div></div>';
  }
  window.__rvPedirPromessa = function(){
    if(enviando) return;
    var d = (document.getElementById('rvPromData') || {}).value, c = (document.getElementById('rvPromContato') || {}).value, m = document.getElementById('rvPromMsg');
    if(!d){ if(m) m.textContent = 'Escolha o dia do pagamento.'; return; }
    if(!c || !c.trim()){ if(m) m.textContent = 'Informe seu nome ou WhatsApp.'; return; }
    enviando = true; if(m) m.textContent = 'Enviando…';
    FETCH(PAINEL + '/rest/v1/rpc/pedir_promessa', { method:'POST', headers:{ apikey:CHAVE, 'Content-Type':'application/json' },
      body: JSON.stringify({ p_slug: R.slug || '', p_url: R.supabaseUrl || '', p_data: d, p_contato: c.trim() }) })
      .then(function(r){ return r.ok ? r.json() : { ok:false, erro:'Não foi possível enviar agora. Tente de novo em instantes.' }; })
      .then(function(j){ enviando = false;
        if(j && j.ok){ estado.prom = { estado:'pendente', data:d }; gravar({ bloqueado:true, mensagem:estado.msg, promessa:estado.prom }); repintar(); }
        else if(m) m.textContent = (j && j.erro) || 'Não foi possível enviar.'; })
      .catch(function(){ enviando = false; if(m) m.textContent = 'Sem conexão. Tente de novo.'; });
  };
  function bloquear(msg, prom){
    estado.msg = msg; estado.prom = prom || null;
    if(ativo){ repintar(); return; }
    ativo = true;
    /* O bloqueio vale SÓ para a área de funcionários (tela de login e sistema aberto). O cardápio digital do cliente continua funcionando. */
    function equipeAtiva(){
      var l = document.getElementById('lockScreen'), m = document.getElementById('mainWrap');
      return !!((l && !l.classList.contains('hidden')) || (m && m.classList.contains('unlocked')));
    }
    var fetchReal = window.fetch;
    try{ window.fetch = function(){ if(equipeAtiva()) return Promise.reject(new Error('Acesso suspenso')); return fetchReal.apply(this, arguments); }; }catch(e){}
    function conteudo(){
      return '<div style="max-width:420px;width:100%"><div style="font-size:54px">⛔</div><h1 style="margin:10px 0 8px;font-size:24px">Acesso suspenso</h1>'
        + '<p style="color:#cfc4c4;margin:0 0 20px">' + esc(estado.msg || 'O acesso a este sistema está suspenso. Fale com o fornecedor do sistema.') + '</p>'
        + corpoPromessa()
        + '<button onclick="location.reload()" style="font:inherit;padding:12px 22px;border:0;border-radius:12px;background:#d4262c;color:#fff;font-weight:700">Verificar de novo</button></div>';
    }
    function pintar(forcar){
      if(!document.body) return;
      var d = document.getElementById('rvBloqueio');
      if(!d){ d = document.createElement('div'); d.id = 'rvBloqueio'; d.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:none;align-items:center;justify-content:center;overflow:auto;background:#0a0a0a;color:#f3ecec;font:16px/1.5 system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box'; document.body.appendChild(d); forcar = true; }
      if(forcar){ d.innerHTML = conteudo(); }
      d.style.display = equipeAtiva() ? 'flex' : 'none';
    }
    repintar = function(){ pintar(true); };
    if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function(){ pintar(true); }); else pintar(true);
    setInterval(function(){ pintar(false); }, 400);
    // enquanto bloqueado, pergunta ao painel a cada minuto; liberou (ou promessa aprovada) = recarrega sozinho
    setInterval(function(){
      FETCH(PAINEL + '/rest/v1/rpc/verificar_restaurante', { method:'POST', headers:{ apikey:CHAVE, 'Content-Type':'application/json' }, body: JSON.stringify({ p_slug: R.slug || '', p_url: R.supabaseUrl || '', p_host: location.hostname || '' }) })
        .then(function(r){ return r.ok ? r.json() : null; })
        .then(function(j){ if(!j || typeof j.bloqueado !== 'boolean') return;
          if(!j.bloqueado){ gravar(null); setTimeout(function(){ location.reload(); }, 1500); return; }
          var novo = JSON.stringify(j.promessa || null); if(novo !== JSON.stringify(estado.prom || null) && !((document.getElementById('rvPromData') || {}).value)){ estado.prom = j.promessa || null; gravar({ bloqueado:true, mensagem:estado.msg, promessa:estado.prom }); repintar(); } })
        .catch(function(){});
    }, 60000);
  }
  /* AVISO DE VENCIMENTO / PROMESSA — aparece uma vez por dia, só para administradores (Admin e Desenvolvedor). */
  function avisarDia(av){
    try{
      if(!av) return;
      var hoje = new Date(), dia = hoje.getFullYear() + '-' + (hoje.getMonth() + 1) + '-' + hoje.getDate();
      if(localStorage.getItem('rvAvisoDia_v1') === dia) return;
      var txt = av.tipo === 'promessa'
        ? 'O acesso está liberado por promessa de pagamento até <b>' + esc(dataBr(av.ate)) + '</b>. Depois dessa data o acesso é suspenso de novo se o pagamento não for confirmado.'
        : 'A mensalidade do sistema vence ' + (av.dias <= 0 ? '<b>hoje</b>' : av.dias === 1 ? '<b>amanhã</b>' : 'em <b>' + av.dias + ' dias</b>') + ' (' + esc(dataBr(av.vencimento)) + '). Pague em dia para não ter o acesso suspenso.';
      var tent = 0, t = setInterval(function(){
        tent++; if(tent > 600){ clearInterval(t); return; }
        var u; try{ u = (typeof currentUser !== 'undefined') ? currentUser : null; }catch(e){ u = null; }
        if(!u || (u.nivel !== 'Admin' && u.nivel !== 'Desenvolvedor') || !document.body) return;
        clearInterval(t);
        try{ localStorage.setItem('rvAvisoDia_v1', dia); }catch(e){}
        var d = document.createElement('div');
        d.style.cssText = 'position:fixed;inset:0;z-index:2147483000;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;padding:24px;font-family:system-ui,sans-serif';
        d.innerHTML = '<div style="max-width:380px;background:#1a1a1a;color:#f3ecec;border:1px solid #d4262c;border-radius:16px;padding:20px;text-align:center;line-height:1.5"><div style="font-size:40px">' + (av.tipo === 'promessa' ? '🤝' : '🔔') + '</div><h3 style="margin:6px 0 8px">Aviso do sistema</h3><p style="margin:0 0 16px;color:#cfc4c4">' + txt + '</p><button style="font:inherit;padding:11px 24px;border:0;border-radius:12px;background:#d4262c;color:#fff;font-weight:700">Entendi</button></div>';
        d.querySelector('button').onclick = function(){ d.remove(); };
        document.body.appendChild(d);
      }, 1000);
    }catch(e){}
  }
  /* TERMOS DE USO — depois que o fornecedor marca o restaurante como entregue, o Admin lê, aceita, manda a foto do rosto e assina.
     Só o Admin vê (a equipe e o cardápio não são afetados). O aceite fica guardado com o fornecedor. */
  var termosPedidos = false;
  function pedirTermos(){
    if(termosPedidos) return; termosPedidos = true;
    var T = null, ov = null, enviado = false, fotoURL = '', sig = { tracos:0, comprimento:0 };
    function elx(id){ return document.getElementById(id); }
    function usuario(){ try{ return (typeof currentUser !== 'undefined') ? currentUser : null; }catch(e){ return null; } }
    function html(txt){ return String(txt).split('\n').map(function(l){ return /^## /.test(l) ? '<h4 style="margin:16px 0 6px;color:#fff">' + esc(l.slice(3)) + '</h4>' : (l.trim() ? '<p style="margin:0 0 8px">' + esc(l) + '</p>' : ''); }).join(''); }
    function carregarTexto(cb){
      FETCH(PAINEL + '/rest/v1/rpc/termos_texto', { method:'POST', headers:{ apikey:CHAVE, 'Content-Type':'application/json' }, body: JSON.stringify({ p_slug: R.slug || '', p_url: R.supabaseUrl || '', p_host: location.hostname || '' }) })
        .then(function(r){ return r.ok ? r.json() : null; }).then(function(j){ if(j && j.ok) { T = j; cb(); } else termosPedidos = false; }).catch(function(){ termosPedidos = false; });
    }
    function montar(){
      ov = document.createElement('div'); ov.id = 'rvTermos';
      ov.style.cssText = 'position:fixed;inset:0;z-index:2147483200;background:#0a0a0a;color:#e9e1e1;overflow:auto;-webkit-overflow-scrolling:touch;font:15px/1.5 system-ui,sans-serif';
      var inp = 'width:100%;box-sizing:border-box;margin:4px 0 10px;padding:11px;border-radius:10px;border:1px solid #444;background:#151515;color:#fff;font:inherit';
      ov.innerHTML = '<div style="max-width:640px;margin:0 auto;padding:18px 16px 40px">'
        + '<h2 style="margin:0 0 4px">📄 Termos de uso do sistema</h2><p style="margin:0 0 12px;color:#bdb2b2">Para continuar no painel administrativo, leia os termos, confirme seus dados, tire uma foto do rosto e assine. A equipe e o cardápio continuam funcionando normalmente.</p>'
        + '<div id="tmTexto" style="height:42vh;overflow:auto;background:#151515;border:1px solid #3a3a3a;border-radius:12px;padding:12px;color:#d6cccc;font-size:14px">' + html(T.texto) + '</div>'
        + '<div id="tmDica" style="color:#f0a500;font-size:13px;margin:6px 0 10px">Role o texto até o final para liberar o aceite.</div>'
        + '<div id="tmCaixas" style="opacity:.45;pointer-events:none">'
        + '<label style="display:flex;gap:10px;margin:8px 0"><input type="checkbox" id="tmLeu" style="width:22px;height:22px;flex:none"><span>Li e concordo com todos os termos acima.</span></label>'
        + '<label style="display:flex;gap:10px;margin:8px 0"><input type="checkbox" id="tmDados" style="width:22px;height:22px;flex:none"><span>Autorizo o uso do meu nome, documento, foto do rosto, assinatura, IP e aparelho para comprovar este aceite (cláusula 6).</span></label>'
        + '<label style="display:flex;gap:10px;margin:8px 0"><input type="checkbox" id="tmCustos" style="width:22px;height:22px;flex:none"><span>Estou ciente de que, se for necessário, haverá custo de planos pagos da infraestrutura, como o plano Pro do Supabase (cláusula 8).</span></label>'
        + '<label style="display:flex;gap:10px;margin:8px 0"><input type="checkbox" id="tmPoderes" style="width:22px;height:22px;flex:none"><span>Sou o(a) responsável pelo estabelecimento ou tenho poderes para assinar por ele.</span></label>'
        + '<h4 style="margin:16px 0 4px">Seus dados</h4>'
        + '<label>Nome completo</label><input id="tmNome" autocomplete="name" maxlength="120" style="' + inp + '">'
        + '<label>CPF ou CNPJ</label><input id="tmDoc" inputmode="numeric" maxlength="20" style="' + inp + '">'
        + '<label>Cargo</label><input id="tmCargo" maxlength="80" placeholder="Ex.: Proprietário" style="' + inp + '">'
        + '<label>E-mail</label><input id="tmEmail" type="email" maxlength="120" style="' + inp + '">'
        + '<label>Telefone / WhatsApp</label><input id="tmTel" inputmode="tel" maxlength="40" style="' + inp + '">'
        + '<h4 style="margin:16px 0 4px">Foto do rosto</h4><div id="tmFotoBox" style="text-align:center"><p style="margin:0 0 8px;color:#bdb2b2;font-size:13px">Rosto de frente, sem óculos escuros nem boné, em local claro.</p><button id="tmCam" style="font:inherit;padding:11px 20px;border:1px solid #d4262c;border-radius:12px;background:transparent;color:#fff;font-weight:700">📷 Tirar foto</button> <label style="display:inline-block;color:#bdb2b2;font-size:13px;margin-left:6px;text-decoration:underline">escolher da galeria<input id="tmArq" type="file" accept="image/*" capture="user" style="display:none"></label></div>'
        + '<h4 style="margin:16px 0 4px">Assinatura <button id="tmLimpa" style="font:inherit;font-size:12px;margin-left:8px;padding:3px 10px;border:1px solid #555;border-radius:8px;background:transparent;color:#ccc">limpar</button></h4>'
        + '<canvas id="tmSig" width="640" height="220" style="width:100%;height:150px;background:#fff;border-radius:12px;touch-action:none"></canvas>'
        + '<div id="tmErro" style="color:#ff8a8a;min-height:22px;margin:10px 0 4px"></div>'
        + '<button id="tmEnviar" style="font:inherit;width:100%;padding:14px;border:0;border-radius:12px;background:#d4262c;color:#fff;font-weight:700">Aceitar e assinar</button></div></div>';
      document.body.appendChild(ov);
      var box = elx('tmTexto');
      function fim(){ if(box.scrollTop + box.clientHeight >= box.scrollHeight - 8){ elx('tmCaixas').style.opacity = 1; elx('tmCaixas').style.pointerEvents = 'auto'; elx('tmDica').style.display = 'none'; } }
      box.addEventListener('scroll', fim); fim();
      // assinatura
      var cv = elx('tmSig'), cx = cv.getContext('2d'), desenhando = false, ult = null;
      cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height); cx.strokeStyle = '#111'; cx.lineWidth = 3.2; cx.lineCap = 'round'; cx.lineJoin = 'round';
      function pos(e){ var r = cv.getBoundingClientRect(); return { x:(e.clientX - r.left) * cv.width / r.width, y:(e.clientY - r.top) * cv.height / r.height }; }
      cv.addEventListener('pointerdown', function(e){ e.preventDefault(); desenhando = true; ult = pos(e); sig.tracos++; try{ cv.setPointerCapture(e.pointerId); }catch(x){} });
      cv.addEventListener('pointermove', function(e){ if(!desenhando) return; e.preventDefault(); var p = pos(e); cx.beginPath(); cx.moveTo(ult.x, ult.y); cx.lineTo(p.x, p.y); cx.stroke(); sig.comprimento += Math.abs(p.x - ult.x) + Math.abs(p.y - ult.y); ult = p; });
      function solta(){ desenhando = false; } cv.addEventListener('pointerup', solta); cv.addEventListener('pointercancel', solta);
      elx('tmLimpa').onclick = function(){ cx.fillStyle = '#fff'; cx.fillRect(0, 0, cv.width, cv.height); sig = { tracos:0, comprimento:0 }; };
      // foto
      function mostrarFoto(url){ fotoURL = url; elx('tmFotoBox').innerHTML = '<img src="' + url + '" style="width:170px;height:170px;object-fit:cover;border-radius:14px;border:2px solid #2f9e44"><div style="margin-top:8px"><button id="tmRefaz" style="font:inherit;padding:8px 16px;border:1px solid #555;border-radius:10px;background:transparent;color:#ddd">Tirar outra</button></div>'; elx('tmRefaz').onclick = function(){ fotoURL = ''; abrirCamera(); }; }
      function reduzir(img){ var m = 480, e = Math.min(1, m / Math.max(img.width || img.videoWidth, img.height || img.videoHeight)), w = Math.round((img.width || img.videoWidth) * e), h = Math.round((img.height || img.videoHeight) * e), c = document.createElement('canvas'); c.width = w; c.height = h; c.getContext('2d').drawImage(img, 0, 0, w, h); return c.toDataURL('image/jpeg', 0.72); }
      function abrirCamera(){
        var b = elx('tmFotoBox');
        if(!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)){ b.innerHTML = '<button id="tmCam2" style="font:inherit;padding:11px 20px;border:1px solid #d4262c;border-radius:12px;background:transparent;color:#fff;font-weight:700">📷 Tirar foto</button><input id="tmArq2" type="file" accept="image/*" capture="user" style="display:none">'; elx('tmCam2').onclick = function(){ elx('tmArq2').click(); }; elx('tmArq2').onchange = function(){ doArquivo(this.files[0]); }; return; }
        navigator.mediaDevices.getUserMedia({ video:{ facingMode:'user' }, audio:false }).then(function(st){
          b.innerHTML = '<video id="tmVid" playsinline autoplay muted style="width:100%;max-width:320px;border-radius:14px;background:#000;transform:scaleX(-1)"></video><div style="margin-top:8px"><button id="tmClick" style="font:inherit;padding:11px 24px;border:0;border-radius:12px;background:#d4262c;color:#fff;font-weight:700">Capturar</button></div>';
          var v = elx('tmVid'); v.srcObject = st;
          elx('tmClick').onclick = function(){ if(!v.videoWidth) return; var u = reduzir(v); st.getTracks().forEach(function(t){ t.stop(); }); mostrarFoto(u); };
        }).catch(function(){ elx('tmErro').textContent = 'Não consegui abrir a câmera. Libere a câmera no navegador ou escolha uma foto da galeria.'; b.innerHTML = '<label style="display:inline-block;padding:11px 20px;border:1px solid #d4262c;border-radius:12px;color:#fff;font-weight:700">📷 Escolher foto<input type="file" accept="image/*" capture="user" style="display:none" onchange="window.__tmArq(this.files[0])"></label>'; });
      }
      function doArquivo(f){ if(!f) return; var u = URL.createObjectURL(f), im = new Image(); im.onload = function(){ mostrarFoto(reduzir(im)); URL.revokeObjectURL(u); }; im.onerror = function(){ elx('tmErro').textContent = 'Não consegui ler essa imagem.'; }; im.src = u; }
      window.__tmArq = doArquivo;
      elx('tmCam').onclick = abrirCamera; elx('tmArq').onchange = function(){ doArquivo(this.files[0]); };
      // enviar
      elx('tmEnviar').onclick = function(){
        var er = elx('tmErro'), btn = elx('tmEnviar'); er.textContent = '';
        var nome = elx('tmNome').value.trim(), doc = elx('tmDoc').value.trim();
        if(!(elx('tmLeu').checked && elx('tmDados').checked && elx('tmCustos').checked && elx('tmPoderes').checked)) return er.textContent = 'Marque todas as confirmações.';
        if(nome.length < 5 || nome.indexOf(' ') < 0) return er.textContent = 'Informe o nome completo.';
        var dg = doc.replace(/\D/g, ''); if(dg.length !== 11 && dg.length !== 14) return er.textContent = 'Informe um CPF (11 números) ou CNPJ (14 números).';
        if(!fotoURL) return er.textContent = 'Tire a foto do rosto.';
        if(sig.comprimento < 250) return er.textContent = 'Faça a sua assinatura no quadro branco.';
        btn.disabled = true; btn.textContent = 'Enviando…';
        FETCH(PAINEL + '/rest/v1/rpc/aceitar_termos', { method:'POST', headers:{ apikey:CHAVE, 'Content-Type':'application/json' }, body: JSON.stringify({ p: {
          slug: R.slug || '', url: R.supabaseUrl || '', versao: T.versao, nome: nome, documento: doc, cargo: elx('tmCargo').value.trim(), email: elx('tmEmail').value.trim(), telefone: elx('tmTel').value.trim(),
          foto: fotoURL, assinatura: cv.toDataURL('image/png'), aparelho: navigator.userAgent, marcas: { leu:true, dados:true, custos:true, poderes:true } } }) })
          .then(function(r){ return r.ok ? r.json() : { ok:false, erro:'Não foi possível enviar agora. Tente de novo.' }; })
          .then(function(j){ if(j && j.ok){ enviado = true; ov.innerHTML = '<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;text-align:center;padding:24px"><div><div style="font-size:54px">✅</div><h2>Termos aceitos</h2><p style="color:#bdb2b2">Obrigado! Seu aceite foi registrado.</p></div></div>'; setTimeout(function(){ try{ ov.remove(); }catch(e){} }, 2500); }
            else { btn.disabled = false; btn.textContent = 'Aceitar e assinar'; er.textContent = (j && j.erro) || 'Não foi possível registrar o aceite.'; } })
          .catch(function(){ btn.disabled = false; btn.textContent = 'Aceitar e assinar'; er.textContent = 'Sem conexão. Tente de novo.'; });
      };
    }
    // só o Admin vê; o Desenvolvedor e a equipe seguem normalmente
    carregarTexto(function(){
      setInterval(function(){
        if(enviado || !document.body) return;
        var u = usuario(), deve = !!(u && u.nivel === 'Admin');
        if(deve && !ov){ montar(); }
        else if(!deve && ov){ try{ ov.remove(); }catch(e){} ov = null; }
      }, 1500);
    });
  }
  var antes = ler();
  if(antes && antes.bloqueado) bloquear(antes.mensagem, antes.promessa);
  var t = null;
  try{
    var c = new AbortController(); t = setTimeout(function(){ c.abort(); }, 6000);
    FETCH(PAINEL + '/rest/v1/rpc/verificar_restaurante', { method:'POST', signal:c.signal, headers:{ apikey:CHAVE, 'Content-Type':'application/json' },
      body: JSON.stringify({ p_slug: R.slug || '', p_url: R.supabaseUrl || '', p_host: location.hostname || '' }) })
      .then(function(r){ clearTimeout(t); return r.ok ? r.json() : null; })
      .then(function(j){
        if(!j || typeof j.bloqueado !== 'boolean') return;           // painel fora do ar ou sem a função: não mexe em nada
        if(j.bloqueado){ gravar({ bloqueado:true, mensagem:j.mensagem || '', promessa:j.promessa || null }); bloquear(j.mensagem, j.promessa); }
        else { gravar(null); if(antes && antes.bloqueado) location.reload(); avisarDia(j.aviso); if(j.termos && j.termos.pendente) pedirTermos(); }
      }).catch(function(){ clearTimeout(t); });
  }catch(e){}
})();

/* =====================================================================
   AVISO DE ERROS — os erros de tela do app chegam ao fornecedor (tabela erros_app do Painel de Revenda), para serem corrigidos.
   Vai só: restaurante, tela, texto do erro, arquivo/linha, versão do sistema e tipo de aparelho. Nenhum dado de cliente, venda, senha ou telefone.
   O mesmo erro repetido conta uma vez só (contador no painel). Sem internet ou se o painel não responder: nada acontece.
   ===================================================================== */
(function(){
  'use strict';
  var PAINEL = 'https://ufoivqszbpznwwkpbvil.supabase.co', CHAVE = 'sb_publishable_u9l2Jz3-aMrnU1JKrQwEUw_46OKJ2m9';
  var R = window.RESTAURANTE || {}, FETCH = window.fetch.bind(window), vistos = {}, total = 0;
  if(!R.slug) return;
  var RUIDO = /ResizeObserver|Script error\.?$|Failed to fetch|NetworkError|Load failed|AbortError|Acesso suspenso|The operation was aborted|chrome-extension|moz-extension|Non-Error promise rejection|network request failed/i;
  function aparelho(){
    var u = navigator.userAgent || '', so = (u.match(/Android [\d.]+|iPhone OS [\d_]+|iPad|Windows NT [\d.]+|Mac OS X [\d_]+|Linux/) || [''])[0].replace(/_/g, '.');
    var nav = (u.match(/(SamsungBrowser|Edg|Firefox|CriOS|Chrome|Safari)\/(\d+)/) || ['', '', ''])[0];
    return (so + ' ' + nav).trim();
  }
  function tela(){
    try{ var a = document.querySelector('[id^="tab-"].active'); if(a) return a.id.replace(/^tab-/, ''); }catch(e){}
    try{ if(document.documentElement.classList.contains('txb-equipe')) return 'equipe'; }catch(e){}
    return 'cardapio';
  }
  function versao(){ try{ return String(window.MOTOR_URL_ || '').replace(/\/+$/, '').split('/').pop(); }catch(e){ return ''; } }
  function limpa(s){ return String(s == null ? '' : s).replace(/https?:\/\/[^\s)]*?\/([^\/\s)?#]+)(\?[^\s)]*)?/g, '$1').replace(/\s+/g, ' ').trim(); }
  function enviar(msg, detalhe){
    try{
      msg = limpa(msg).slice(0, 400); if(!msg || RUIDO.test(msg)) return;
      var t = tela(), k = msg + '|' + t;
      if(vistos[k] || total >= 20) return; vistos[k] = 1; total++;
      FETCH(PAINEL + '/rest/v1/rpc/registrar_erro', { method:'POST', keepalive:true, headers:{ apikey:CHAVE, 'Content-Type':'application/json' },
        body: JSON.stringify({ p:{ slug:R.slug, tela:t, mensagem:msg, detalhe:limpa(detalhe).slice(0, 1500), versao:versao(), aparelho:aparelho() } }) }).catch(function(){});
    }catch(e){}
  }
  window.addEventListener('error', function(ev){
    if(!ev) return;
    var m = ev.message || (ev.error && ev.error.message) || '';
    var onde = ev.filename ? (limpa(ev.filename) + ':' + (ev.lineno || 0) + ':' + (ev.colno || 0)) : '';
    enviar(m, onde + ' ' + ((ev.error && ev.error.stack) || ''));
  });
  window.addEventListener('unhandledrejection', function(ev){
    var r = ev && ev.reason, m = r && (r.message || (typeof r === 'string' ? r : ''));
    enviar(m || '', (r && r.stack) || '');
  });
  window.rvRegistrarErro = enviar;   // usado pelos avisos de erro do próprio sistema
})();
