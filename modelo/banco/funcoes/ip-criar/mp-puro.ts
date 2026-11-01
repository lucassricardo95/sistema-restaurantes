// =====================================================================
// MERCADO PAGO · funções PURAS (sem rede, sem banco, sem Deno): tradução de status, assinatura do aviso, CPF, textos.
// Este arquivo é copiado igual para dentro de mp-criar, mp-webhook, mp-status e mp-reembolsar.
// Escrito a partir da documentação pública do Mercado Pago (Orders API, 13/10/2026): ainda NÃO testado contra o Mercado Pago de verdade.
// =====================================================================

export type StatusBanco = "aguardando" | "aprovado" | "recusado" | "expirado" | "cancelado" | "reembolso_parcial" | "reembolsado" | "erro";

export const num = (x: unknown): number => { const n = Number(String(x ?? "").replace(",", ".")); return Number.isFinite(n) ? n : 0; };
export const dinheiro = (n: number): string => (Math.round(n * 100) / 100).toFixed(2);   // o Mercado Pago quer texto "00.00"
export const centavos = (n: number): number => Math.round(n * 100);
export const apenasDigitos = (s: unknown): string => String(s ?? "").replace(/\D+/g, "");
export const minusc = (s: unknown): string => String(s ?? "").trim().toLowerCase();
export const ehUuid = (s: unknown): boolean => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(s ?? ""));

// CPF com os dois dígitos verificadores (recusa 111.111.111-11 e parecidos)
export function cpfValido(valor: unknown): boolean {
  const c = apenasDigitos(valor);
  if (c.length !== 11 || /^(\d)\1{10}$/.test(c)) return false;
  for (let t = 9; t < 11; t++) {
    let soma = 0;
    for (let i = 0; i < t; i++) soma += Number(c[i]) * (t + 1 - i);
    const dv = ((soma * 10) % 11) % 10;
    if (dv !== Number(c[t])) return false;
  }
  return true;
}

// Duração ISO 8601 do vencimento do Pix. O Mercado Pago aceita no mínimo 30 minutos (e no máximo 30 dias).
export function duracaoPix(minutos: number): string { return "PT" + Math.max(30, Math.min(43200, Math.ceil(minutos))) + "M"; }

// ---------- status do Mercado Pago → status do banco ----------
// Pedido (order) e transação (payment) usam: created, processing, action_required (waiting_payment/waiting_transfer/pending_challenge),
// processed (accredited | partially_refunded), failed, expired, canceled, refunded.
export function mapearStatus(statusMp: unknown, detalheMp: unknown): StatusBanco {
  const s = minusc(statusMp), d = minusc(detalheMp);
  if (s === "refunded" || d === "refunded") return "reembolsado";
  if (s === "processed") return d === "partially_refunded" ? "reembolso_parcial" : "aprovado";
  if (s === "failed") return "recusado";
  if (s === "expired") return "expirado";
  if (s === "canceled" || s === "cancelled") return "cancelado";
  return "aguardando";   // created, processing, action_required, at_terminal e qualquer valor novo: espera, nunca aprova por engano
}

export interface Traducao {
  status: StatusBanco; statusMp: string; detalheMp: string; orderId: string; paymentId: string; externalReference: string;
  valorPago: number; valorReembolsado: number;
  pix: { copiaCola: string; qrBase64: string; ticketUrl: string; expiraEm: string } | null;
  cartaoFinal: string; cartaoBandeira: string;
  desafio: { url: string } | null;   // autenticação 3DS pedida pelo banco do cartão (se vier)
}

// Lê a resposta de POST/GET /v1/orders e devolve só o que o banco precisa. Prefere o status da transação; sem ela, usa o do pedido.
export function traduzirOrder(o: any): Traducao {
  const pg = Array.isArray(o?.transactions?.payments) ? o.transactions.payments[0] : null;
  const pm = pg?.payment_method || {};
  const statusMp = String(pg?.status || o?.status || ""), detalheMp = String(pg?.status_detail || o?.status_detail || "");
  const refunds: any[] = Array.isArray(o?.transactions?.refunds) ? o.transactions.refunds : [];
  const reemb = refunds.reduce((t, r) => t + (minusc(r?.status) === "failed" ? 0 : num(r?.amount)), 0);
  const final4 = [pm.last_four_digits, pm.card?.last_four_digits, pm.card_last_four_digits].map(apenasDigitos).find((x) => /^\d{4}$/.test(x)) || "";
  const url3ds = String(pm?.transaction_security?.url || "");
  const eh = String(pm.type || "") === "bank_transfer" || String(pm.id || "") === "pix";
  return {
    status: mapearStatus(statusMp, detalheMp), statusMp, detalheMp,
    orderId: String(o?.id || ""), paymentId: String(pg?.id || ""), externalReference: String(o?.external_reference || ""),
    valorPago: num(pg?.paid_amount ?? o?.total_paid_amount), valorReembolsado: Math.round(reemb * 100) / 100,
    pix: eh && (pm.qr_code || pm.qr_code_base64) ? { copiaCola: String(pm.qr_code || ""), qrBase64: String(pm.qr_code_base64 || ""), ticketUrl: String(pm.ticket_url || ""), expiraEm: String(pg?.date_of_expiration || "") } : null,
    cartaoFinal: final4, cartaoBandeira: String(pm.type === "credit_card" || pm.type === "debit_card" ? (pm.id || "") : "").slice(0, 30),
    desafio: /^https:\/\//i.test(url3ds) ? { url: url3ds } : null,
  };
}

// Texto para o cliente quando o cartão não passa (nunca mostra o código bruto do Mercado Pago)
export function mensagemRecusa(detalhe: unknown): string {
  const d = minusc(detalhe);
  if (d === "insufficient_amount") return "O cartão não tem limite suficiente. Tente outro cartão ou pague na entrega.";
  if (d === "card_disabled") return "Esse cartão está desativado. Tente outro cartão ou pague na entrega.";
  if (d === "amount_limit_exceeded") return "O valor passou do limite do cartão. Tente outro cartão ou pague na entrega.";
  if (d === "high_risk") return "O pagamento foi recusado por segurança. Tente outro cartão ou pague na entrega.";
  if (d === "invalid_card_token" || d === "bad_filled_card_data") return "Confira os dados do cartão e tente de novo.";
  if (d === "invalid_installments") return "Esse cartão não aceita pagamento à vista neste pedido. Tente outro cartão.";
  return "O pagamento não foi aprovado. Tente outro cartão ou pague na entrega.";
}

// Código do erro do Mercado Pago (só para o log, sem dados do cliente)
export function codigoErroMp(j: any): string {
  const e = Array.isArray(j?.errors) ? j.errors[0] : null;
  return String(e?.code || j?.error || j?.code || j?.message || "").slice(0, 80);
}

// ---------- assinatura do aviso (webhook) ----------
export function lerAssinatura(h: string | null | undefined): { ts: string; v1: string } {
  let ts = "", v1 = "";
  for (const parte of String(h || "").split(",")) {
    const i = parte.indexOf("="); if (i < 0) continue;
    const k = parte.slice(0, i).trim(), v = parte.slice(i + 1).trim();
    if (k === "ts") ts = v; else if (k === "v1") v1 = v;
  }
  return { ts, v1 };
}
export async function hmacHex(segredo: string, texto: string): Promise<string> {
  const enc = new TextEncoder();
  const chave = await crypto.subtle.importKey("raw", enc.encode(segredo), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const ass = await crypto.subtle.sign("HMAC", chave, enc.encode(texto));
  return Array.from(new Uint8Array(ass)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function iguaisSeguro(a: string, b: string): boolean {   // compara sem parar no primeiro caractere diferente
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
// Texto assinado: "id:<data.id>;request-id:<x-request-id>;ts:<ts>;" (parte ausente sai do texto). O id é aceito como veio e em minúsculas.
export async function validarAssinatura(o: { segredo: string; assinatura: string | null; requestId: string | null; ids: string[] }): Promise<boolean> {
  const { ts, v1 } = lerAssinatura(o.assinatura);
  if (!o.segredo || !ts || !v1) return false;
  const candidatos = Array.from(new Set(o.ids.filter(Boolean).flatMap((x) => [x, x.toLowerCase()])));
  if (!candidatos.length) candidatos.push("");
  for (const id of candidatos) {
    const manifesto = (id ? `id:${id};` : "") + (o.requestId ? `request-id:${o.requestId};` : "") + `ts:${ts};`;
    if (iguaisSeguro(await hmacHex(o.segredo, manifesto), v1.toLowerCase())) return true;
  }
  return false;
}
