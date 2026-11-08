// ifood-autorizar · autorização do restaurante no aplicativo COMPARTILHADO do iFood (tipo Distribuído).
// Chamada só pelo banco (botão "Autorizar o iFood" do Administrador). verify_jwt = false: aceita só a chave de serviço.
// 1) acao "codigo": pede ao iFood um código curto (userCode) e guarda o verificador; o dono digita o código no Portal do Parceiro.
// 2) acao "concluir": troca o código de autorização que o Portal mostrou por um acesso (token) e um refresh token, guardados no banco.
// O resultado (ou o motivo da falha) vai para o banco (ifood_autorizacao_msg); a tela do Administrador lê dali. Nada disto vai ao navegador.
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
const msg = (t: string) => rpc("ifood_autorizacao_msg", { p_msg: t });

async function pedir(caminho: string, corpo: URLSearchParams, extra: Record<string, string> = {}) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 15000);
  try {
    const r = await fetch(BASE + caminho, { method: "POST", headers: { ...extra, "Content-Type": "application/x-www-form-urlencoded" }, body: corpo.toString(), signal: ctl.signal });
    const txt = await r.text(); let j: any = null; try { j = txt ? JSON.parse(txt) : null; } catch { j = null; }
    return { status: r.status, json: j, texto: txt.slice(0, 200) };
  } finally { clearTimeout(t); }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const chaveVault = await seg("service_key");
  if (!token || (token !== SVC && token !== chaveVault)) return json({ ok: false, message: "Só execução interna." }, 403);
  const b = await req.json().catch(() => ({}));
  try {
    const cred: any = await rpc("ifood_credenciais");
    if (cred?.modo !== "compartilhado") { await msg("Este restaurante não está no modo de aplicativo compartilhado."); return json({ ok: true }); }
    if (!cred?.clientId) { await msg("Falta o Client ID do aplicativo (em Chaves e códigos)."); return json({ ok: true }); }
    const extra = cred?.config?.modoHomologacao ? { "x-request-homologation": "true" } : {};

    if (b.acao === "codigo") {
      let r;
      try { r = await pedir("/authentication/v1.0/oauth/userCode", new URLSearchParams({ clientId: cred.clientId }), extra); }
      catch { await msg("Não consegui falar com o iFood agora. Tente de novo em instantes."); return json({ ok: true }); }
      const j = r.json || {};
      if (r.status < 200 || r.status >= 300 || !j.userCode || !j.authorizationCodeVerifier) {
        await msg("O iFood não deu o código (erro " + r.status + "). Confira se o Client ID é do aplicativo Distribuído. " + (r.texto || "").slice(0, 120));
        return json({ ok: true });
      }
      await rpc("ifood_autorizacao_gravar", { p_verificador: j.authorizationCodeVerifier, p_codigo: j.userCode, p_url: j.verificationUrlComplete || j.verificationUrl || "https://portal.ifood.com.br/apps/code", p_seg: Number(j.expiresIn || 600) });
      return json({ ok: true });
    }

    if (b.acao === "concluir") {
      const a: any = await rpc("ifood_autorizacao_ler");
      if (!a?.verificador) { await msg("O código venceu (vale uns 10 minutos). Toque em Autorizar o iFood de novo."); return json({ ok: true }); }
      if (!cred?.clientSecret) { await msg("Falta o Client Secret do aplicativo (em Chaves e códigos)."); return json({ ok: true }); }
      let r;
      try {
        r = await pedir("/authentication/v1.0/oauth/token", new URLSearchParams({ grantType: "authorization_code", clientId: cred.clientId, clientSecret: cred.clientSecret,
          authorizationCode: String(b.codigo || "").trim(), authorizationCodeVerifier: a.verificador }), extra);
      } catch { await msg("Não consegui falar com o iFood agora. Tente de novo em instantes."); return json({ ok: true }); }
      const j = r.json || {}; const acesso = j.accessToken || j.access_token;
      if (r.status < 200 || r.status >= 300 || !acesso) {
        await msg("O iFood recusou o código de autorização (erro " + r.status + "). Confira se copiou inteiro e se não passou de 10 minutos. " + (r.texto || "").slice(0, 120));
        return json({ ok: true });
      }
      await rpc("ifood_refresh_gravar", { p_token: acesso, p_seg: Number(j.expiresIn || j.expires_in || 3600) - 120, p_refresh: j.refreshToken || j.refresh_token || "" });
      if (!(j.refreshToken || j.refresh_token)) { await msg("⚠️ O iFood deu o acesso, mas não mandou o refresh token. A autorização não vai se renovar sozinha."); return json({ ok: true }); }
      await msg("✅ iFood autorizado. A renovação do acesso agora é automática.");
      return json({ ok: true });
    }
    return json({ ok: false }, 400);
  } catch (e) {
    try { await msg("Erro interno na autorização: " + String((e as Error).message).slice(0, 150)); } catch { /* sem registro */ }
    return json({ ok: false }, 500);
  }
});
