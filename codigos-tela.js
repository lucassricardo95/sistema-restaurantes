/* Tela "Códigos" do Painel de Revenda: SQL e Apps Script para copiar/baixar, com explicação. */
(function(){
'use strict';
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const $ = id => document.getElementById(id);
const PLACEHOLDER = 'abcdefghijklmnopqrst';
let aberto = {}, cache = {};
function msg(t, erro){ const a = $('aviso'); if(!a) return; a.textContent = (erro ? '⚠️ ' : '') + t; a.className = 'aviso ' + (erro ? 'erro' : 'ok'); a.hidden = false; setTimeout(() => { a.hidden = true; }, 3500); }
function ler(k){ try{ return localStorage.getItem(k) || ''; }catch(e){ return ''; } }
function gravar(k, v){ try{ localStorage.setItem(k, v); }catch(e){} }
function ref(){ const v = ($('cd-ref') || {}).value || ler('cd_ref'); return v.trim().replace(/^https?:\/\//, '').replace(/\.supabase\.co.*$/, ''); }
function cod(){ return (($('cd-cod') || {}).value || ler('cd_cod')).trim(); }
function achar(id){ for(const g of window.CODIGOS) for(const i of g.itens) if(i.id === id) return i; }
async function texto(i){
  if(i.especial === 'segredos') return segredos();
  if(cache[i.arq]) return pronto(i, cache[i.arq]);
  const r = await fetch('codigos/' + i.arq + '.enc?t=' + Date.now(), { cache:'no-store' });
  if(!r.ok) throw new Error('Não consegui carregar ' + i.arq + ' (erro ' + r.status + ').');
  cache[i.arq] = await abrir(await r.text()); return pronto(i, cache[i.arq]);
}
let chaveCr = null;
async function token(){
  let s = null; try{ s = JSON.parse(localStorage.getItem('rv_sess') || 'null'); }catch(e){}
  if(!s) throw new Error('Entre no painel de novo para abrir os códigos.');
  if(Date.now() > s.exp){
    const r = await fetch(window.REVENDA_URL + '/auth/v1/token?grant_type=refresh_token', { method:'POST', headers:{ apikey:window.REVENDA_CHAVE, 'Content-Type':'application/json' }, body:JSON.stringify({ refresh_token:s.refresh_token }) });
    const j = await r.json(); if(!r.ok || !j.access_token) throw new Error('Sua sessão expirou. Saia e entre de novo.');
    s = { access_token:j.access_token, refresh_token:j.refresh_token, exp:Date.now() + (j.expires_in - 60) * 1000, email:s.email };
    try{ localStorage.setItem('rv_sess', JSON.stringify(s)); }catch(e){}
  }
  return s.access_token;
}
async function chave(){
  if(chaveCr) return chaveCr;
  const r = await fetch(window.REVENDA_URL + '/rest/v1/codigos_chave?select=chave', { headers:{ apikey:window.REVENDA_CHAVE, Authorization:'Bearer ' + await token() } });
  const j = await r.json().catch(() => null);
  if(!r.ok) throw new Error('Não consegui buscar a chave dos códigos (erro ' + r.status + '). Rode o arquivo 008 no banco do painel.');
  if(!j || !j[0]) throw new Error('A chave dos códigos ainda não foi guardada no banco do painel. Veja o arquivo 008-codigos.sql (Códigos > 3).');
  const raw = Uint8Array.from(atob(j[0].chave.trim()), c => c.charCodeAt(0));
  chaveCr = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt']); return chaveCr;
}
async function abrir(b64){
  const k = await chave(), b = Uint8Array.from(atob(b64.trim()), c => c.charCodeAt(0));
  try{ return new TextDecoder().decode(await crypto.subtle.decrypt({ name:'AES-GCM', iv:b.slice(0, 12) }, k, b.slice(12))); }
  catch(e){ throw new Error('A chave guardada no banco não abre estes arquivos. Guarde de novo a chave de codigos-chave.txt.'); }
}
function pronto(i, t){ const r = ref(); return (i.subRef && r) ? t.split(PLACEHOLDER).join(r) : t; }
function segredos(){
  const r = ref() || 'COLE_AQUI_ref_do_projeto', c = cod() || 'COLE_AQUI_codigo_do_restaurante';
  return '-- Cofre de chaves do restaurante. Troque cada COLE_AQUI pelo valor real e rode UMA vez.\n'
   + '-- Se uma chave já existir, o Supabase avisa: apague-a antes em Project Settings > Vault ou use vault.update_secret.\n'
   + "select vault.create_secret('" + c + "', 'restaurante_slug');\n"
   + "select vault.create_secret('https://" + r + ".supabase.co', 'supabase_url');\n"
   + "select vault.create_secret('COLE_AQUI_chave_publicavel_do_projeto', 'publishable_key');\n"
   + "select vault.create_secret('COLE_AQUI_service_role_do_projeto', 'service_key');\n"
   + "select vault.create_secret('COLE_AQUI_url_da_planilha_principal_(Apps_Script)', 'sheets_main_url');\n"
   + "select vault.create_secret('COLE_AQUI_chave_do_servidor_da_planilha', 'chave_servidor_planilha');\n";
}
async function copiarTxt(t){
  try{ await navigator.clipboard.writeText(t); return true; }catch(e){}
  const a = document.createElement('textarea'); a.value = t; a.style.cssText = 'position:fixed;top:0;left:0;opacity:0'; document.body.appendChild(a); a.focus(); a.select();
  let ok = false; try{ ok = document.execCommand('copy'); }catch(e){} a.remove(); return ok;
}
window.cdCopiar = async id => { const i = achar(id); try{ const t = await texto(i); if(await copiarTxt(t)) msg('Copiado: ' + i.titulo + ' (' + t.length.toLocaleString('pt-BR') + ' letras). Agora cole no editor.'); else msg('O celular não deixou copiar. Use "Ver" e copie o texto à mão.', true); }catch(e){ msg(e.message, true); } };
window.cdBaixar = async id => { const i = achar(id); try{ const t = await texto(i); const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([t], { type:'text/plain;charset=utf-8' })); a.download = (i.arq ? i.arq.split('/').pop() : 'cofre-de-chaves.sql'); document.body.appendChild(a); a.click(); a.remove(); }catch(e){ msg(e.message, true); } };
window.cdVer = async id => { const i = achar(id), box = $('cd-ver-' + id); if(box.innerHTML){ box.innerHTML = ''; return; } try{ const t = await texto(i); box.innerHTML = '<textarea readonly rows="14" style="width:100%;font:12px/1.4 monospace;background:#0b0b0b;color:#ddd;border:1px solid #2a2a2a;border-radius:8px;padding:8px" onfocus="this.select()">' + esc(t) + '</textarea>'; }catch(e){ msg(e.message, true); } };
window.cdGrupo = id => { aberto[id] = !aberto[id]; desenhar(); };
window.cdCampo = () => { gravar('cd_ref', ($('cd-ref') || {}).value || ''); gravar('cd_cod', ($('cd-cod') || {}).value || ''); };
function card(i){
  return '<div class="card" style="overflow-wrap:anywhere"><div class="linha"><b>' + esc(i.titulo) + '</b>' + (i.kb ? '<span class="selo">' + i.kb + ' KB</span>' : '') + '</div>'
   + '<p style="margin:8px 0 4px"><b>O que é:</b> ' + esc(i.desc) + '</p>'
   + '<p style="margin:4px 0"><b>Quando usar:</b> ' + esc(i.quando) + '</p>'
   + '<p style="margin:4px 0"><b>Onde colar:</b> ' + esc(i.onde) + '</p>'
   + '<p style="margin:4px 0 10px" class="mudo"><b>Cuidado:</b> ' + esc(i.cuidado) + '</p>'
   + '<button class="mini principal" onclick="cdCopiar(\'' + i.id + '\')">Copiar</button> <button class="mini" onclick="cdBaixar(\'' + i.id + '\')">Baixar</button> <button class="mini" onclick="cdVer(\'' + i.id + '\')">Ver</button>'
   + '<div id="cd-ver-' + i.id + '" style="margin-top:8px"></div></div>';
}
function desenhar(){
  const G = window.CODIGOS || [];
  $('app').innerHTML = '<div class="topo"><h1>Códigos</h1><div class="acoes"><button onclick="rvVoltar()">← Restaurantes</button></div></div>'
   + '<div class="card"><p style="margin:0 0 8px">Aqui estão todos os SQL e Apps Script do sistema para você aplicar sozinho, sem depender de mim. Cada item diz o que é, quando usar, onde colar e o que cuidar. Toque em <b>Copiar</b>, abra o editor indicado, cole e rode.</p>'
   + '<p class="mudo" style="margin:0 0 10px"><b>Atenção:</b> estes arquivos não têm senhas nem chaves. Quando faltar um valor, o texto traz um COLE_AQUI para você preencher. O usuário Desenvolvedor (com senha) não está aqui de propósito.</p>'
   + '<label style="display:block;margin:6px 0 2px"><small>Código do restaurante (ex.: texas-burger)</small></label><input id="cd-cod" value="' + esc(ler('cd_cod')) + '" oninput="cdCampo()" placeholder="codigo-do-restaurante" style="width:100%">'
   + '<label style="display:block;margin:8px 0 2px"><small>Ref do projeto Supabase (20 letras do endereço https://REF.supabase.co)</small></label><input id="cd-ref" value="' + esc(ler('cd_ref')) + '" oninput="cdCampo()" placeholder="abcdefghijklmnopqrst" style="width:100%">'
   + '<small class="mudo">Esses dois campos preenchem sozinhos o que for copiado. Ficam salvos só neste aparelho.</small></div>'
   + G.map(g => '<div class="card"><button style="width:100%;text-align:left" onclick="cdGrupo(\'' + g.id + '\')"><b>' + (aberto[g.id] ? '▾ ' : '▸ ') + esc(g.titulo) + '</b> <small class="mudo">(' + g.itens.length + ')</small></button>'
      + (aberto[g.id] ? '<p class="mudo" style="margin:10px 0">' + esc(g.intro) + '</p>' + g.itens.map(card).join('') : '') + '</div>').join('');
}
window.rvCodigos = () => { if(!window.CODIGOS){ msg('A lista de códigos não carregou. Atualize a página.', true); return; } cache = {}; desenhar(); window.scrollTo(0, 0); };
})();
