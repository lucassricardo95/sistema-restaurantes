// Volta do Google depois de você autorizar o Drive. Troca o código pelo refresh token, guarda no Vault e devolve você para o sistema.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { URL_, CHAVE_SERVICO } from "./auth.ts";
import { credenciais, REDIRECT } from "./drive.ts";

const volta = (retorno: string, ok: boolean, conta: string, msg = "") => {
  const u = new URL(retorno); u.searchParams.set("drive", ok ? "ok" : "erro"); u.searchParams.set("conta", conta); if (msg) u.searchParams.set("msg", msg.slice(0, 300));
  return new Response(null, { status: 302, headers: { Location: u.toString() } });
};
Deno.serve(async (req) => {
  const url = new URL(req.url), state = url.searchParams.get("state") || "", code = url.searchParams.get("code") || "", erroG = url.searchParams.get("error");
  const svc = createClient(URL_, CHAVE_SERVICO);
  const { data: est } = await svc.from("drive_oauth_estados").select("*").eq("estado", state).maybeSingle();
  if (!est) return new Response("Link expirado ou inválido. Volte ao sistema e toque em Conectar de novo.", { status: 400, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  await svc.from("drive_oauth_estados").delete().eq("estado", state);   // uso único
  if (Date.now() - new Date(est.criado_em).getTime() > 15 * 60000) return volta(est.retorno, false, est.conta, "O link venceu (mais de 15 minutos). Toque em Conectar de novo.");
  if (erroG || !code) return volta(est.retorno, false, est.conta, erroG === "access_denied" ? "Você não autorizou o acesso. Se a tela do Google bloqueou, confira se esta conta está em Usuários de teste no Google Cloud." : `Google: ${erroG || "sem código"}`);
  try {
    const { id, segredo } = await credenciais();
    const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ code, client_id: id, client_secret: segredo, redirect_uri: REDIRECT, grant_type: "authorization_code" }) });
    const j = await r.json();
    if (!r.ok || !j.access_token) return volta(est.retorno, false, est.conta, `Google recusou: ${j.error_description || j.error || r.status}`);
    if (!j.refresh_token) return volta(est.retorno, false, est.conta, "O Google não devolveu a autorização permanente. Remova o acesso do Drive em myaccount.google.com/permissions e conecte de novo.");
    const sobre = await (await fetch("https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)", { headers: { Authorization: `Bearer ${j.access_token}` } })).json().catch(() => ({}));
    const { error } = await svc.rpc("drive_guardar_token", { p_conta: est.conta, p_email: sobre?.user?.emailAddress || null, p_token: j.refresh_token, p_por: est.usuario_id });
    if (error) return volta(est.retorno, false, est.conta, `Não consegui guardar a autorização: ${error.message}`);
    return volta(est.retorno, true, est.conta);
  } catch (e) { return volta(est.retorno, false, est.conta, (e as Error).message); }
});
