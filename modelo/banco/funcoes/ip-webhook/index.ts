// =====================================================================
// ip-webhook · recebe o AVISO de pagamento aprovado da InfinitePay. Chamada só pela InfinitePay.
// O aviso NÃO tem assinatura (documentação pública). Por isso:
//  • o endereço leva um segredo nosso (?s=...), conferido sem vazar tempo; sem ele, 401 e nada acontece;
//  • o aviso nunca é confiado: o pagamento é CONFERIDO com a InfinitePay (payment_check) e o valor pago é comparado no banco;
//  • aviso repetido não aprova duas vezes (chave do evento = número da transação);
//  • erro nosso ou da InfinitePay responde 400 (a InfinitePay reenvia); aviso de pagamento que não é nosso responde 200.
// =====================================================================
import { svc, aplicarStatus, log } from "./mp.ts";
import { ehUuid } from "./mp-puro.ts";
import { ipCredenciais, ipConferir, ipRegistrar, igualSeguro, IpRede } from "./ip.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const limpo = (v: unknown, max = 80) => String(v || "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, max);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  try {
    const url = new URL(req.url);
    const cred: any = await ipCredenciais();
    if (!cred?.webhookSegredo || !igualSeguro(String(url.searchParams.get("s") || ""), String(cred.webhookSegredo))) {
      log("ip_webhook_segredo_invalido");
      return json({ ok: false, erro: "segredo" }, 401);
    }
    const corpo: any = await req.json().catch(() => ({}));
    const pagamentoId = String(corpo?.order_nsu || "");
    const transacao = limpo(corpo?.transaction_nsu), slug = limpo(corpo?.invoice_slug || corpo?.slug);
    if (!ehUuid(pagamentoId)) return json({ ok: true, ignorado: "pedido_desconhecido" });
    const { data: g } = await svc.from("pagamentos_online").select("id,status,mp_modo").eq("id", pagamentoId).eq("provedor", "infinitepay").maybeSingle();
    if (!g) return json({ ok: true, ignorado: "pagamento_desconhecido" });
    if (g.mp_modo !== "producao") return json({ ok: true, ignorado: "simulacao" });
    const reg: any = await ipRegistrar({ pagamentoId, slug, transacao, recibo: String(corpo?.receipt_url || ""), metodoPago: limpo(corpo?.capture_method, 30) });
    if (!reg?.ok) { log("ip_webhook_registro_recusado", { pagamentoId }); return json({ ok: true, ignorado: "transacao_repetida" }); }

    const c = await ipConferir(cred, pagamentoId, transacao, slug);
    if (!c) return json({ ok: false, erro: "nao_conferido" }, 400);   // a InfinitePay reenvia
    await ipRegistrar({ pagamentoId, conferido: true, metodoPago: c.metodo });
    if (!c.pago) { log("ip_webhook_nao_pago", { pagamentoId }); return json({ ok: true, pago: false }); }
    const res: any = await aplicarStatus({
      pagamentoId, status: "aprovado", valorPago: c.valorPago, chaveEvento: ("ip:" + (transacao || slug || pagamentoId)).slice(0, 200), assinaturaOk: true, tipoEvento: "infinitepay",
      statusMp: "paid", statusDetalhe: "InfinitePay: pago (" + (c.metodo === "pix" ? "Pix" : c.metodo === "credit_card" ? "crédito " + c.parcelas + "x" : c.metodo || "?") + ")" + (c.valorPago > 0 ? "" : " — valor pago não informado"),
      detalhe: { provedor: "infinitepay", metodo: c.metodo, parcelas: c.parcelas },
    });
    log("ip_webhook_ok", { pagamentoId, duplicado: res?.duplicado === true });
    return json({ ok: true, duplicado: res?.duplicado === true });
  } catch (e) {
    log("ip_webhook_falha", { erro: e instanceof IpRede ? "rede" : String((e as Error)?.message || e).slice(0, 200) });
    return json({ ok: false, erro: "tente_de_novo" }, 400);
  }
});
