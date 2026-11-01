// ifood-teste · "Testar conexão" do iFood. Chamada só pelo banco (botão do Administrador). Funciona MESMO com a integração desligada.
// Pede um acesso (token) ao iFood com o Client ID e o Client Secret digitados e confere se o iFood acha a loja. Não consulta nem confirma pedidos.
// verify_jwt = false: aceita só a chave de serviço. O resultado vai para o banco (ifood_marcar_consulta); o painel lê dali.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const svc = createClient(URL_, SVC, { auth: { persistSession: false } });
const BASE = Deno.env.get("IFOOD_BASE_URL") || "https://merchant-api.ifood.com.br";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const seg = async (nome: string) => { try { const { data } = await svc.rpc("api_segredo", { p_nome: nome }); return (data as string) || ""; } catch { return ""; } };
const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
  const { data, error } = await svc.rpc(fn, args);
  if (error) throw new Error(fn + ": " + error.message);
  return data;
};
const falhou = (msg: string, tokenOk: boolean | null = false) => rpc("ifood_marcar_consulta", { p_ok: false, p_erro: msg, p_token_ok: tokenOk });

async function pedir(metodo: string, caminho: string, token: string | null, corpo?: URLSearchParams, extra: Record<string, string> = {}) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 15000);
  try {
    const h: Record<string, string> = { ...extra };
    if (token) h["Authorization"] = "Bearer " + token;
    if (corpo) h["Content-Type"] = "application/x-www-form-urlencoded";
    const r = await fetch(BASE + caminho, { method: metodo, headers: h, body: corpo ? corpo.toString() : undefined, signal: ctl.signal });
    const txt = await r.text(); let j: any = null; try { j = txt ? JSON.parse(txt) : null; } catch { j = null; }
    return { status: r.status, json: j };
  } finally { clearTimeout(t); }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const chaveVault = await seg("service_key");
  if (!token || (token !== SVC && token !== chaveVault)) return json({ ok: false, message: "Só execução interna." }, 403);
  try {
    const cred: any = await rpc("ifood_credenciais");
    if (!cred?.clientId || !cred?.clientSecret || !cred?.merchantId) { await falhou("Faltam o Client ID, o Client Secret ou o código da loja."); return json({ ok: true }); }
    const extra = cred?.config?.modoHomologacao ? { "x-request-homologation": "true" } : {};
    let r;
    try { r = await pedir("POST", "/authentication/v1.0/oauth/token", null, new URLSearchParams({ grantType: "client_credentials", clientId: cred.clientId, clientSecret: cred.clientSecret }), extra); }
    catch { await falhou("Não consegui falar com o iFood agora. Tente de novo em instantes.", null); return json({ ok: true }); }
    const acesso = r.json?.accessToken || r.json?.access_token;
    if (r.status < 200 || r.status >= 300 || !acesso) {
      await falhou(r.status === 401 || r.status === 400 || r.status === 403 ? "O iFood recusou o Client ID / Client Secret. Confira se copiou certo, sem espaço, do aplicativo Centralizado." : "O iFood não deu o acesso (erro " + r.status + "). Tente de novo.", r.status >= 500 ? null : false);
      return json({ ok: true });
    }
    await rpc("ifood_token_gravar", { p_token: acesso, p_seg: Number(r.json?.expiresIn || r.json?.expires_in || 3600) - 120 });
    // a loja: só reprova se o iFood disser que ela não existe (404); outros avisos não bloqueiam (o aplicativo de teste pode não ter esse módulo)
    try {
      const l = await pedir("GET", `/merchant/v1.0/merchants/${encodeURIComponent(cred.merchantId)}/status`, acesso, undefined, extra);
      if (l.status === 404) { await falhou("As chaves foram aceitas, mas o iFood não achou a loja. Confira o código da loja (use o Merchant UUID, o código comprido)."); return json({ ok: true }); }
      // documentação oficial (Authentication): 403 "user is forbidden to access merchant" = a loja ainda não autorizou o app (ou o módulo Merchant não foi liberado)
      if (l.status === 403) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Teste do iFood: chaves aceitas, mas o iFood negou acesso à loja (403). A loja precisa autorizar o aplicativo no Portal do Parceiro, ou o módulo Merchant ainda não foi liberado. Depois de autorizar, pode levar até 10 minutos." }); } catch { /* só registro */ } }
    } catch { /* sem resposta da loja: não bloqueia */ }
    await rpc("ifood_marcar_consulta", { p_ok: true, p_token_ok: true });
    return json({ ok: true });
  } catch (e) {
    try { await falhou("Erro interno no teste: " + String((e as Error).message).slice(0, 150), null); } catch { /* sem registro */ }
    return json({ ok: false }, 500);
  }
});
