// =====================================================================
// mp-cancelar · cancela no Mercado Pago o Pix que o nosso banco já encerrou (reserva vencida ou cancelada).
// Chamada SÓ pelo cron (mp-cancelar-pix, todo minuto, e só quando há Pix a cancelar). verify_jwt = false: confere a chave de serviço (auth.ts).
// Regras:
//  • antes de cancelar, LÊ o pedido no Mercado Pago. Se já foi encerrado lá (cancelado, vencido, recusado, 404), só marca como resolvido;
//  • se ainda aguarda, manda cancelar. Se o cancelamento falhar, LÊ DE NOVO: o cliente pode ter pago no mesmo instante (corrida);
//  • se o pedido está aprovado (ou reembolsado), aplica o status real por mp_aplicar_status: o banco leva para "Pagamento a decidir"
//    (Pix pago depois de vencer) em vez de ignorar o dinheiro recebido;
//  • erro de rede ou resposta estranha: conta uma tentativa e tenta de novo no minuto seguinte (até 5, dentro de 3 h).
// Escrito a partir da documentação pública da Orders API (cancelar pedido): ainda NÃO testado contra o Mercado Pago de verdade.
// A tradução de status espelha mp-puro.ts (mapearStatus). Nada sensível vai para o log.
// =====================================================================
import { CORS, json, svcClient, autorizar } from "./auth.ts";

const MP_BASE = Deno.env.get("MP_BASE") || "https://api.mercadopago.com";
const minusc = (s: unknown) => String(s ?? "").trim().toLowerCase();
const num = (x: unknown): number => { const n = Number(String(x ?? "").replace(",", ".")); return Number.isFinite(n) ? n : 0; };
const log = (evento: string, d: Record<string, unknown> = {}) => { try { console.log(JSON.stringify({ evento, ...d })); } catch { /* nada */ } };

function mapear(statusMp: unknown, detalheMp: unknown): string {
  const s = minusc(statusMp), d = minusc(detalheMp);
  if (s === "refunded" || d === "refunded") return "reembolsado";
  if (s === "processed") return d === "partially_refunded" ? "reembolso_parcial" : "aprovado";
  if (s === "failed") return "recusado";
  if (s === "expired") return "expirado";
  if (s === "canceled" || s === "cancelled") return "cancelado";
  return "aguardando";   // qualquer valor novo: espera, nunca aprova por engano
}
function ler(o: any) {
  const pg = Array.isArray(o?.transactions?.payments) ? o.transactions.payments[0] : null;
  const statusMp = String(pg?.status || o?.status || ""), detalheMp = String(pg?.status_detail || o?.status_detail || "");
  const refunds: any[] = Array.isArray(o?.transactions?.refunds) ? o.transactions.refunds : [];
  const reemb = refunds.reduce((t, r) => t + (minusc(r?.status) === "failed" ? 0 : num(r?.amount)), 0);
  return { status: mapear(statusMp, detalheMp), detalheMp, orderId: String(o?.id || ""), paymentId: String(pg?.id || ""), valorReembolsado: Math.round(reemb * 100) / 100 };
}

async function mp(metodo: "GET" | "POST", caminho: string, token: string, idem?: string): Promise<{ status: number; json: any } | null> {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 12000);
  try {
    const h: Record<string, string> = { Authorization: "Bearer " + token, Accept: "application/json" };
    if (metodo === "POST") h["X-Idempotency-Key"] = (idem || crypto.randomUUID()).slice(0, 64);
    const r = await fetch(MP_BASE + caminho, { method: metodo, headers: h, signal: ctl.signal });
    const txt = await r.text(); let j: any = null; try { j = txt ? JSON.parse(txt) : null; } catch { j = null; }
    return { status: r.status, json: j };
  } catch { return null; } finally { clearTimeout(t); }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, null);   // só execução interna (cron)
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  const svc = svcClient(); const inicio = Date.now();
  const r = { verificados: 0, cancelados: 0, jaEncerrados: 0, aplicados: 0, falhas: 0 };
  try {
    const { data: lista, error } = await svc.rpc("mp_pendentes_cancelar");
    if (error) return json({ ok: false, message: "mp_pendentes_cancelar: " + error.message }, 500);
    for (const g of (Array.isArray(lista) ? lista : [])) {
      if (Date.now() - inicio > 90000) break;   // o resto fica para o próximo minuto
      r.verificados++;
      const marcar = (ok: boolean, erro = "") => svc.rpc("mp_cancelar_resultado", { p_id: g.id, p_ok: ok, p_erro: erro });
      try {
        const { data: cred } = await svc.rpc("mp_credenciais", { p_modo: g.modo ?? null });
        const token = String((cred as any)?.accessToken || "");
        if (!token) { await marcar(false, "sem credencial do Mercado Pago"); r.falhas++; continue; }
        const oid = encodeURIComponent(String(g.orderId));

        let lido = await mp("GET", `/v1/orders/${oid}`, token);
        if (lido && lido.status === 404) { await marcar(true); r.jaEncerrados++; continue; }   // não existe lá: nada a cancelar
        if (!lido || lido.status < 200 || lido.status >= 300 || !lido.json) { await marcar(false, "não consegui ler o pedido no Mercado Pago (HTTP " + (lido?.status ?? "rede") + ")"); r.falhas++; continue; }
        let t = ler(lido.json);

        if (t.status === "aguardando") {
          const c = await mp("POST", `/v1/orders/${oid}/cancel`, token, "cancel-" + g.id);
          if (c && c.status >= 200 && c.status < 300) { await marcar(true); r.cancelados++; log("mp_pix_cancelado", { pagamentoId: g.id }); continue; }
          // cancelamento falhou: pode ser corrida (cliente pagou agora). Lê de novo antes de desistir.
          lido = await mp("GET", `/v1/orders/${oid}`, token);
          if (!lido || lido.status < 200 || lido.status >= 300 || !lido.json) { await marcar(false, "cancelamento falhou (HTTP " + (c?.status ?? "rede") + ") e não consegui reler o pedido"); r.falhas++; continue; }
          t = ler(lido.json);
          if (t.status === "aguardando") { await marcar(false, "cancelamento recusado pelo Mercado Pago (HTTP " + (c?.status ?? "rede") + ")"); r.falhas++; continue; }
        }

        if (t.status === "aprovado" || t.status === "reembolso_parcial" || t.status === "reembolsado") {
          // dinheiro entrou (ou já foi devolvido): o banco decide o destino (Pagamento a decidir / reembolso), nunca ignora
          const { data: ap, error: e2 } = await svc.rpc("mp_aplicar_status", { p: { pagamentoId: g.id, mpOrderId: t.orderId, mpPaymentId: t.paymentId, status: t.status, statusDetalhe: t.detalheMp, valorReembolsado: t.valorReembolsado } });
          if (e2 || (ap as any)?.ok === false) { await marcar(false, "não consegui aplicar o status " + t.status); r.falhas++; continue; }
          await marcar(true); r.aplicados++; log("mp_pix_pago_na_corrida", { pagamentoId: g.id, status: t.status });
          continue;
        }
        await marcar(true); r.jaEncerrados++;   // cancelado, vencido ou recusado lá também
      } catch (e) {
        r.falhas++; log("mp_cancelar_item_falhou", { erro: String((e as Error)?.message || e).slice(0, 160) });
        try { await svc.rpc("mp_cancelar_resultado", { p_id: g.id, p_ok: false, p_erro: "erro inesperado" }); } catch { /* nada */ }
      }
    }
    return json({ ok: true, ...r });
  } catch (e) { return json({ ok: false, message: String((e as Error)?.message || e).slice(0, 200) }, 500); }
});
