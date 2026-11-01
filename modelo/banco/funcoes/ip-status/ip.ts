// =====================================================================
// INFINITEPAY · apoio das 3 Edge Functions (ip-criar, ip-status, ip-webhook). Copiado igual para dentro de cada pasta.
// Usa o "Checkout Integrado" público: POST https://api.checkout.infinitepay.io/links e /payment_check (documentação da InfinitePay).
// O aviso (webhook) da InfinitePay NÃO é assinado: nada é aprovado sem a consulta payment_check e a conferência do valor.
// ⚠️ Escrito pela documentação pública, sem conta real para testar: a primeira ligação real pode pedir ajuste.
// =====================================================================
import { rpc, log } from "./mp.ts";

export const IP_BASE = Deno.env.get("IP_BASE") || "https://api.checkout.infinitepay.io";
export class IpRede extends Error { constructor() { super("rede_ou_timeout"); } }

export const ipCredenciais = async () => await rpc("ip_credenciais");   // {ligado, modo, config, handle, chave, webhookSegredo}
export const ipRegistrar = async (p: Record<string, unknown>) => await rpc("ip_registrar", { p });

export async function ipPost(caminho: string, corpo: unknown, chave?: string | null, ms = 20000): Promise<{ status: number; json: any }> {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), ms);
  try {
    const h: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json" };
    if (chave) h["Authorization"] = "Bearer " + chave;   // só se a conta tiver a chave do Checkout (inchk_…); a versão pública usa só a InfiniteTag
    const r = await fetch(IP_BASE + caminho, { method: "POST", headers: h, body: JSON.stringify(corpo), signal: ctl.signal });
    const txt = await r.text(); let json: any = null; try { json = txt ? JSON.parse(txt) : null; } catch { json = { message: txt.slice(0, 200) }; }
    return { status: r.status, json };
  } catch { throw new IpRede(); } finally { clearTimeout(t); }
}

export const centavos = (v: number) => Math.round(Number(v) * 100);

// Confere com a InfinitePay se o pagamento foi feito. Devolve null se não deu para perguntar (faltam dados ou rede).
export async function ipConferir(cred: any, pagamentoId: string, transacao: string, slug: string): Promise<{ pago: boolean; valorPago: number; metodo: string; parcelas: number } | null> {
  if (!cred?.handle || !transacao || !slug) return null;
  const r = await ipPost("/payment_check", { handle: String(cred.handle), order_nsu: pagamentoId, transaction_nsu: transacao, slug }, cred.chave, 15000);
  if (r.status < 200 || r.status >= 300 || !r.json) { log("ip_conferir_http", { http: r.status }); return null; }
  const j = r.json;
  const pago = j.paid === true || (j.paid === undefined && j.success === true && Number(j.paid_amount) > 0);
  // só vale o valor PAGO informado pela InfinitePay (nunca o valor do pedido). Sem ele, 0: o banco manda para "decidir" em vez de aprovar.
  const pagoCent = Number(j.paid_amount);
  return { pago, valorPago: Number.isFinite(pagoCent) && pagoCent > 0 ? pagoCent / 100 : 0,
           metodo: String(j.capture_method || ""), parcelas: Number(j.installments || 1) };
}

// segredo comparado sem vazar o tempo (o segredo vai no endereço do aviso)
export function igualSeguro(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
