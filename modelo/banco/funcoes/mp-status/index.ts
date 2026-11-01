// =====================================================================
// mp-status · consulta ATIVA do pagamento, para a tela do cliente quando o aviso (webhook) atrasa. Chamada pelo cardápio (cliente LOGADO).
// verify_jwt = false: confere o login do cliente e que a reserva é dele.
// Entrada: { reservaId }     Saída: o mesmo que api_mp_status_pagamento (estado, valorTotal, expiraEm, pixCopiaCola, numero, ...)
// Regras:
//  • só pergunta ao Mercado Pago se o pagamento ainda está "aguardando" e não foi atualizado nos últimos 5 s (a tela pode chamar de 3 em 3 s sem sobrecarregar);
//  • o resultado entra pela MESMA porta do aviso (mp_aplicar_status), então aviso e consulta nunca se atropelam;
//  • Pix que já foi cancelado/vencido no nosso banco mas continua aberto no Mercado Pago é cancelado lá também (melhor esforço), para ninguém pagar um QR morto.
// =====================================================================
import { resp, cors, usuario, svc, credenciais, aplicarStatus, mpChamar, MpRede, comoCliente, limite, log } from "./mp.ts";
import { ehUuid, traduzirOrder } from "./mp-puro.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return resp(req, { ok: false, message: "Método não permitido." }, 405);
  try {
    const u = await usuario(req);
    if (!u) return resp(req, { ok: false, message: "Entre na sua conta." }, 401);
    if (!limite("status:" + u.id, 40, 60000)) return resp(req, { ok: false, message: "Muitas consultas seguidas. Aguarde alguns segundos." }, 429);
    const corpo = await req.json().catch(() => ({}));
    const reservaId = String(corpo?.reservaId || "");
    if (!ehUuid(reservaId)) return resp(req, { ok: false, message: "Pedido inválido." }, 400);

    const { data: rv } = await svc.from("pedidos_reserva").select("id,user_id,estado").eq("id", reservaId).maybeSingle();
    if (!rv || rv.user_id !== u.id) return resp(req, { ok: false, message: "Pedido não encontrado." });
    const { data: g } = await svc.from("pagamentos_online").select("id,status,metodo,mp_modo,mp_order_id,atualizado_em").eq("reserva_id", reservaId).order("criado_em", { ascending: false }).limit(1).maybeSingle();

    if (g?.mp_order_id) {
      const parado = Date.now() - new Date(g.atualizado_em).getTime() > 5000;
      const consultar = (g.status === "aguardando" && parado)
        || (g.metodo === "pix" && (g.status === "cancelado" || g.status === "expirado") && Date.now() - new Date(g.atualizado_em).getTime() < 2 * 3600 * 1000 && limite("cancelar:" + g.id, 1, 600000));
      if (consultar) {
        try {
          const cred: any = await credenciais(g.mp_modo);
          if (cred?.accessToken) {
            const r = await mpChamar("GET", `/v1/orders/${encodeURIComponent(g.mp_order_id)}`, String(cred.accessToken), undefined, undefined, 12000);
            if (r.status >= 200 && r.status < 300 && r.json) {
              const tr = traduzirOrder(r.json);
              if (g.status === "aguardando") {
                if (tr.status !== "aguardando") {   // mudou lá e o aviso ainda não chegou: aplica agora (o banco ignora o que já estiver aplicado)
                  await aplicarStatus({ pagamentoId: g.id, mpOrderId: tr.orderId, mpPaymentId: tr.paymentId, status: tr.status, statusDetalhe: tr.detalheMp,
                    cartaoFinal: tr.cartaoFinal, cartaoBandeira: tr.cartaoBandeira, valorReembolsado: tr.valorReembolsado, valorPago: tr.valorPago });
                }
              } else if (tr.status === "aguardando") {   // nosso lado já desistiu, o Mercado Pago ainda espera o Pix: cancela lá
                await mpChamar("POST", `/v1/orders/${encodeURIComponent(g.mp_order_id)}/cancel`, String(cred.accessToken), undefined, "cancel-" + g.id, 8000);
                log("mp_status_pix_cancelado_no_mp", { pagamentoId: g.id });
              }
            }
          }
        } catch (e) { if (!(e instanceof MpRede)) log("mp_status_consulta_falhou", { erro: String((e as Error)?.message || e).slice(0, 160) }); /* a tela volta a perguntar */ }
      }
    }

    // a resposta final vem do banco, COMO o cliente (a função confere o dono de novo)
    const cli = await comoCliente(u.token);
    const { data, error } = await cli.rpc("api_mp_status_pagamento", { p: { reservaId } });
    if (error) return resp(req, { ok: false, message: "Não foi possível consultar o pagamento agora." }, 502);
    return resp(req, data);
  } catch (e) {
    log("mp_status_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return resp(req, { ok: false, message: "Não foi possível consultar o pagamento agora." }, 500);
  }
});
