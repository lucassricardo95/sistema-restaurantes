// =====================================================================
// mp-webhook · recebe os AVISOS do Mercado Pago (evento "Order (Mercado Pago)"). Chamada só pelo Mercado Pago.
// verify_jwt = false: a prova de que o aviso é do Mercado Pago é a assinatura (header x-signature, HMAC-SHA256 com a chave secreta do webhook).
// Regras:
//  • aviso com assinatura inválida: só é registrado e nada mais acontece (resposta 401);
//  • o aviso nunca é confiado: o status vem de uma CONSULTA ao pedido no Mercado Pago (GET /v1/orders/{id}) com o Access Token do modo certo;
//  • aviso repetido é ignorado no banco (chave do evento); responder 200 em poucos segundos (o Mercado Pago espera até 22 s e reenvia a cada 15 min);
//  • erro nosso (banco ou Mercado Pago fora do ar) responde 500 para o Mercado Pago tentar de novo; pedido que não é nosso responde 200 (não adianta reenviar);
//  • o clique em "Simular" do painel do Mercado Pago (número de pedido falso) responde 200.
// =====================================================================
import { svc, credenciais, aplicarStatus, mpChamar, MpRede, limite, log } from "./mp.ts";
import { ehUuid, traduzirOrder, validarAssinatura } from "./mp-puro.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const ID_ORDER = /^[A-Za-z0-9_-]{8,64}$/;

// consulta o pedido no Mercado Pago; sem saber o modo, tenta o provável e depois o outro (aviso de teste x produção)
async function consultarPedido(orderId: string, modos: string[]): Promise<{ pedido: any; modo: string } | null> {
  for (const modo of modos) {
    const cred: any = await credenciais(modo);
    if (!cred?.accessToken) continue;
    const r = await mpChamar("GET", `/v1/orders/${encodeURIComponent(orderId)}`, String(cred.accessToken), undefined, undefined, 15000);
    if (r.status >= 200 && r.status < 300 && r.json) return { pedido: r.json, modo };
    if (r.status >= 500 || r.status === 429) throw new MpRede();   // problema do lado deles: pedir reenvio
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, erro: "metodo" }, 405);
  try {
    const url = new URL(req.url);
    const bruto = await req.text();
    let corpo: any = {}; try { corpo = bruto ? JSON.parse(bruto) : {}; } catch { corpo = {}; }
    const dataIdQuery = String(url.searchParams.get("data.id") || ""), dataIdCorpo = String(corpo?.data?.id || "");
    const tipo = String(url.searchParams.get("type") || corpo?.type || "");
    const requestId = req.headers.get("x-request-id");
    const orderId = dataIdQuery || dataIdCorpo;

    // 1) assinatura: sem chave cadastrada ou assinatura errada = não é confiável
    const cred0: any = await credenciais(null);
    const segredo = String(cred0?.webhookSecret || "");
    if (!segredo) { log("mp_webhook_sem_chave"); return json({ ok: false, erro: "chave_do_aviso_nao_cadastrada" }, 401); }
    const assinaturaOk = await validarAssinatura({ segredo, assinatura: req.headers.get("x-signature"), requestId, ids: [dataIdQuery, dataIdCorpo] });
    if (!assinaturaOk) {
      if (limite("assinatura_invalida", 30, 60000)) await aplicarStatus({ chaveEvento: "x", assinaturaOk: false, tipoEvento: tipo, statusMp: "", detalhe: { action: String(corpo?.action || ""), motivo: "assinatura inválida" } });
      log("mp_webhook_assinatura_invalida", { tipo });
      return json({ ok: false, erro: "assinatura" }, 401);
    }

    // 2) só o tópico "order" interessa; o resto recebe 200 para o Mercado Pago não reenviar
    if (tipo && tipo !== "order") return json({ ok: true, ignorado: "tipo" });
    if (!ID_ORDER.test(orderId)) return json({ ok: true, ignorado: "sem_id" });

    // 3) descobre o modo (teste/produção) e consulta o pedido de verdade
    const { data: g } = await svc.from("pagamentos_online").select("id,mp_modo").eq("mp_order_id", orderId).maybeSingle();
    const provavel = g?.mp_modo || (corpo?.live_mode === true ? "producao" : "homologacao");
    const modos = g ? [provavel] : [provavel, provavel === "producao" ? "homologacao" : "producao"];
    const achado = await consultarPedido(orderId, modos);
    if (!achado) { log("mp_webhook_pedido_nao_encontrado"); return json({ ok: true, ignorado: "pedido_inexistente" }); }   // inclui o "Simular" do painel
    const tr = traduzirOrder(achado.pedido);

    // 4) o pagamento é nosso? (external_reference = id do pagamento no banco; ou pelo número do pedido já gravado)
    const pagamentoId = ehUuid(tr.externalReference) ? tr.externalReference : (g?.id || null);
    if (!pagamentoId && !g) { log("mp_webhook_pagamento_desconhecido"); return json({ ok: true, ignorado: "pagamento_desconhecido" }); }

    // 5) entrega ao banco: a chave do evento impede processar o mesmo aviso duas vezes
    const chaveEvento = `order:${orderId}:${String(corpo?.action || "")}:${String(corpo?.date_created || requestId || "")}`.slice(0, 200);
    const res: any = await aplicarStatus({
      pagamentoId, mpOrderId: tr.orderId || orderId, mpPaymentId: tr.paymentId, status: tr.status, statusDetalhe: tr.detalheMp,
      pixCopiaCola: tr.pix?.copiaCola || "", pixQrBase64: tr.pix?.qrBase64 || "", pixExpiraEm: tr.pix?.expiraEm || "",
      cartaoFinal: tr.cartaoFinal, cartaoBandeira: tr.cartaoBandeira, valorReembolsado: tr.valorReembolsado, valorPago: tr.valorPago,
      chaveEvento, assinaturaOk: true, tipoEvento: tipo || "order", statusMp: tr.statusMp, detalhe: { action: String(corpo?.action || ""), status: tr.statusMp, status_detail: tr.detalheMp, modo: achado.modo },
    });
    log("mp_webhook_ok", { status: tr.status, duplicado: res?.duplicado === true, ignorado: res?.ignorado || null });
    return json({ ok: true, duplicado: res?.duplicado === true });
  } catch (e) {
    log("mp_webhook_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return json({ ok: false, erro: "tente_de_novo" }, 500);   // o Mercado Pago reenvia
  }
});
