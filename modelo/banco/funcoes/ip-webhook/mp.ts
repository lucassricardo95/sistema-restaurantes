// =====================================================================
// MERCADO PAGO · apoio das 4 Edge Functions (rede, banco, login). Copiado igual para dentro de cada pasta.
// verify_jwt = false em todas: cada função confere sozinha quem chamou (cliente logado, equipe ou assinatura do Mercado Pago).
// Segredos NUNCA ficam aqui: o Access Token e a chave do aviso vêm do banco (mp_credenciais, só chave de serviço).
// Nada sensível vai para o log: nem token do cartão, nem CPF, nem corpo da requisição.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import { ehUuid } from "./mp-puro.ts";

export const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
export const svc = createClient(URL_, SVC, { auth: { persistSession: false } });
export const MP_BASE = Deno.env.get("MP_BASE") || "https://api.mercadopago.com";

// ---------- CORS (o cardápio e o app falam com estas funções pelo navegador) ----------
const ORIGENS = [(Deno.env.get("SITE_ORIGEM") || "").replace(/\/$/, ""), "http://localhost:8080", "http://127.0.0.1:8080", "http://localhost:5500", "http://127.0.0.1:5500"].filter(Boolean);
export const cors = (req: Request) => {
  const o = req.headers.get("origin") || "";
  return { "Access-Control-Allow-Origin": ORIGENS.includes(o) ? o : ORIGENS[0], "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
};
export const resp = (req: Request, corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...cors(req), "Content-Type": "application/json; charset=utf-8" } });

// ---------- log sem dados sensíveis ----------
export const log = (evento: string, detalhe: Record<string, unknown> = {}) => { try { console.log(JSON.stringify({ evento, ...detalhe })); } catch { /* nada */ } };

// ---------- limite simples por instância (freio de abuso; o limite de verdade está no banco) ----------
const _lim = new Map<string, number[]>();
export function limite(chave: string, max: number, janelaMs: number): boolean {
  const agora = Date.now(); const l = (_lim.get(chave) || []).filter((t) => agora - t < janelaMs);
  if (l.length >= max) { _lim.set(chave, l); return false; }
  l.push(agora); _lim.set(chave, l);
  if (_lim.size > 5000) for (const k of _lim.keys()) { _lim.delete(k); if (_lim.size < 2500) break; }
  return true;
}

// ---------- quem chamou ----------
export const bearer = (req: Request) => (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
export async function usuario(req: Request): Promise<{ id: string; email: string; token: string } | null> {
  const token = bearer(req); if (!token) return null;
  const { data } = await svc.auth.getUser(token);
  return data?.user ? { id: data.user.id, email: data.user.email || "", token } : null;
}
// Equipe (Admin, Operador; o Desenvolvedor vale como Admin, igual a auth_nivel() no banco). Devolve null se não puder.
export async function equipe(req: Request, niveis: string[]): Promise<{ id: string; nivel: string } | null> {
  const u = await usuario(req); if (!u) return null;
  const { data: usr } = await svc.from("usuarios").select("id,nivel,ativo").eq("id", u.id).maybeSingle();
  if (!usr || usr.ativo === false || !niveis.includes(usr.nivel)) return null;
  return { id: usr.id, nivel: usr.nivel };
}

// ---------- banco ----------
export async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<any> {
  const { data, error } = await svc.rpc(fn, args);
  if (error) throw new Error(fn + ": " + error.message);
  return data;
}
export const credenciais = async (modo?: string | null) => await rpc("mp_credenciais", { p_modo: modo ?? null });   // {ligado, modoAtual, modo, config, publicKey, accessToken, webhookSecret}
export const aplicarStatus = async (p: Record<string, unknown>) => await rpc("mp_aplicar_status", { p });

// Chave pública do projeto (para chamar funções do banco COMO o cliente logado, ex.: api_mp_status_pagamento)
let _pk = "";
export async function chavePublica(): Promise<string> {
  if (_pk) return _pk;
  _pk = Deno.env.get("SB_PUBLISHABLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (!_pk) { try { const { data } = await svc.rpc("api_segredo", { p_nome: "publishable_key" }); _pk = (data as string) || ""; } catch { /* nada */ } }
  return _pk;
}
export async function comoCliente(token: string) {
  return createClient(URL_, await chavePublica(), { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
}

// ---------- Mercado Pago ----------
export class MpRede extends Error { constructor() { super("rede_ou_timeout"); } }
export async function mpChamar(metodo: "GET" | "POST", caminho: string, accessToken: string, corpo?: unknown, chaveIdem?: string, ms = 25000): Promise<{ status: number; json: any }> {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), ms);
  try {
    const h: Record<string, string> = { Authorization: "Bearer " + accessToken, Accept: "application/json" };
    let body: string | undefined;
    if (corpo !== undefined) { body = JSON.stringify(corpo); h["Content-Type"] = "application/json"; }
    if (metodo === "POST") h["X-Idempotency-Key"] = (chaveIdem || crypto.randomUUID()).slice(0, 64);   // 1 a 64 caracteres
    const r = await fetch(MP_BASE + caminho, { method: metodo, headers: h, body, signal: ctl.signal });
    const txt = await r.text(); let json: any = null; try { json = txt ? JSON.parse(txt) : null; } catch { json = { message: txt.slice(0, 200) }; }
    return { status: r.status, json };
  } catch { throw new MpRede(); } finally { clearTimeout(t); }
}
// POST que repete UMA vez, com a MESMA chave de idempotência, se a rede cair ou o Mercado Pago responder 429/5xx (a chave impede cobrança dupla)
export async function mpPostComRetentativa(caminho: string, accessToken: string, corpo: unknown, chaveIdem: string): Promise<{ status: number; json: any }> {
  let ultimo: { status: number; json: any } | null = null;
  for (let i = 0; i < 2; i++) {
    try {
      const r = await mpChamar("POST", caminho, accessToken, corpo, chaveIdem);
      if (r.status !== 429 && r.status < 500) return r;
      ultimo = r;
    } catch (e) { if (!(e instanceof MpRede)) throw e; ultimo = null; }
    if (i === 0) await new Promise((ok) => setTimeout(ok, 1500));
  }
  if (ultimo) return ultimo;
  throw new MpRede();
}
export { ehUuid };
