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
function ref(){ const v = (window.CD_CTX && window.CD_CTX.ref) || ''; return v.trim().replace(/^https?:\/\//, '').replace(/\.supabase\.co.*$/, ''); }
function cod(){ return ((window.CD_CTX && window.CD_CTX.cod) || '').trim(); }
function achar(id){ for(const k in window.CODIGOS) for(const i of window.CODIGOS[k]) if(i.id === id) return i; }
async function texto(i){
  if(i.especial) return especial(i.especial);
  if(i.subRef && !ref()) throw new Error('Preencha o endereço do Supabase deste restaurante na aba Ligações (passo 2) antes de copiar.');
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
function especial(k){
  const r = ref() || 'COLE_AQUI_ref_do_projeto', c = cod() || 'COLE_AQUI_codigo_do_restaurante', pub = (window.CD_CTX && window.CD_CTX.chave) || 'COLE_AQUI_chave_publicavel_do_projeto';
  const q = s => String(s).replace(/'/g, "''");
  const V = window.CD_VALS || {}, ex = (window.CD_CTX && window.CD_CTX.exec) || '';   // valores digitados na tela (não são guardados)
  if(k === 'segredos1') return '-- Cofre de chaves do restaurante (parte 1). Troque COLE_AQUI pelo valor real e rode UMA vez.\n'
   + "select vault.create_secret('" + q(c) + "', 'restaurante_slug');\n"
   + "select vault.create_secret('https://" + q(r) + ".supabase.co', 'supabase_url');\n"
   + "select vault.create_secret('" + q(pub) + "', 'publishable_key');\n"
   + "select vault.create_secret('" + q(V.service || 'COLE_AQUI_service_role') + "', 'service_key');\n";
  if(k === 'segredos2') return '-- Cofre de chaves (parte 2: planilhas). Troque COLE_AQUI_url_exec pelo endereço /exec e rode UMA vez.\n'
   + "select vault.create_secret('" + q(ex || 'COLE_AQUI_url_exec_da_planilha_principal') + "', 'sheets_main_url');\n"
   + "select vault.create_secret('rstsb-' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'chave_servidor_planilha');\n"
   + "-- COPIE o valor abaixo para a propriedade SB_CHAVE_SERVIDOR do Apps Script:\n"
   + "select decrypted_secret as copie_para_SB_CHAVE_SERVIDOR from vault.decrypted_secrets where name = 'chave_servidor_planilha';\n";
  if(k === 'google') return "-- Credenciais do Google (Drive). Cole o ID e a chave secreta como TEXTO e rode UMA vez.\n"
   + "select vault.create_secret('" + q(V.gid || 'COLE_AQUI_ID_DO_CLIENTE') + "', 'google_client_id');\n"
   + "select vault.create_secret('" + q(V.gsec || 'COLE_AQUI_CHAVE_SECRETA') + "', 'google_client_secret');\n";
  if(k === 'admin2') return "-- Cria o primeiro Administrador. Troque os três valores.\nselect public.instalar_admin_inicial('" + q(V.alogin || 'COLE_AQUI_login') + "', '" + q(V.asenha || 'COLE_AQUI_senha_minimo_8') + "', 'Administrador');\n";
  if(k === 'dev2') return "-- Cria o SEU login de Desenvolvedor (suporte). Troque a senha (mínimo 8) e rode UMA vez.\nselect public.instalar_desenvolvedor('Lucas', '" + q(V.dsenha || 'COLE_AQUI_sua_senha_minimo_8') + "');\n";
  throw new Error('Código especial desconhecido.');
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
function linha(i, etapa, n){
  const fe = (window.CD_CTX && window.CD_CTX.feitos) || [], f = fe.includes('cd:' + i.id);
  return '<div style="border:1px solid #2a2a2a;border-radius:10px;padding:10px;margin:8px 0;overflow-wrap:anywhere' + (f ? ';opacity:.6' : '') + '"><div class="linha"><b>' + n + '. ' + esc(i.titulo) + '</b>' + (i.kb ? '<span class="selo">' + i.kb + ' KB</span>' : '') + '</div>'
   + '<p style="margin:6px 0 2px"><b>O que é:</b> ' + esc(i.desc) + '</p>'
   + '<p style="margin:2px 0"><b>Onde colar:</b> ' + esc(i.onde) + '</p>'
   + '<p style="margin:2px 0 8px" class="mudo"><b>Cuidado:</b> ' + esc(i.cuidado) + '</p>'
   + '<button class="mini principal" onclick="cdCopiar(\'' + i.id + '\')">Copiar</button> <button class="mini" onclick="cdBaixar(\'' + i.id + '\')">Baixar</button> <button class="mini" onclick="cdVer(\'' + i.id + '\')">Ver</button>'
   + '<label style="display:flex;gap:8px;align-items:center;font-weight:400;color:var(--txt);margin:8px 0 0"><input type="checkbox" ' + (f ? 'checked ' : '') + 'onchange="rvItem(\'' + etapa + '\',\'cd:' + i.id + '\',this.checked)"> Já apliquei</label>'
   + '<div id="cd-ver-' + i.id + '" style="margin-top:8px"></div></div>';
}
window.cdEtapa = (etapa, ctx) => {
  const L = (window.CODIGOS || {})[etapa]; if(!L || !L.length) return '';
  ctx.ref = /^[a-z0-9]{20}$/.test(ctx.ref || '') ? ctx.ref : ''; window.CD_CTX = ctx;
  return '<div style="margin:10px 0"><b>Códigos desta etapa, na ordem</b><p class="mudo" style="margin:4px 0 6px">Toque em Copiar, abra o editor indicado, cole e rode. Marque "Já apliquei" ao terminar cada um.</p>' + L.map((i, n) => linha(i, etapa, n + 1)).join('') + '</div>';
};
window.cdCtx = ctx => { window.CD_CTX = ctx; };
window.cdObter = async id => { const i = achar(id); if(!i) throw new Error('Código não encontrado: ' + id); return texto(i); };
})();
