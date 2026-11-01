// =====================================================================
// mp-reembolsar · devolve o dinheiro (total ou parcial) de um pagamento online, pelo Mercado Pago. Chamada só pela EQUIPE (Admin, Operador).
// verify_jwt = false: confere o login e o nível (Admin, Operador; o Desenvolvedor vale como Admin) e se existe uma DECISÃO registrada.
// Entrada: { pagamentoId, valor? }   sem "valor" = devolver tudo o que falta. Saída: { ok, estado, valorReembolsado, restante, message }
// Regras:
//  • NUNCA reembolsa sozinho: só devolve se alguém já decidiu (api_mp_decidir_pagamento = "reembolsar") OU se a venda foi cancelada e há
//    um reembolso "Pendente" na tabela reembolsos (cancelamento de pedido pago). Qualquer outro pedido de reembolso é recusado;
//  • idempotência: a chave do Mercado Pago é fixa por pagamento + valor já devolvido + valor pedido, então duplo clique não devolve duas vezes;
//  • reembolso total sem corpo (como a documentação manda); parcial com o id da transação e o valor;
//  • depois de devolvido, o resultado entra pela mesma porta do aviso (mp_aplicar_status): o banco marca "Devolvido" sozinho quando for o total.
// =====================================================================
import { resp, cors, equipe, svc, credenciais, aplicarStatus, mpChamar, MpRede, limite, log } from "./mp.ts";
import { centavos, codigoErroMp, dinheiro, ehUuid, num, traduzirOrder } from "./mp-puro.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return resp(req, { ok: false, message: "Método não permitido." }, 405);
  try {
    const eq = await equipe(req, ["Admin", "Operador", "Desenvolvedor"]);
    if (!eq) return resp(req, { ok: false, message: "Sem permissão para reembolsar." }, 403);
    if (!limite("reemb:" + eq.id, 10, 60000)) return resp(req, { ok: false, message: "Muitos pedidos seguidos. Aguarde um minuto." }, 429);
    const corpo = await req.json().catch(() => ({}));
    const pagamentoId = String(corpo?.pagamentoId || "");
    if (!ehUuid(pagamentoId)) return resp(req, { ok: false, message: "Pagamento inválido." }, 400);

    const { data: g } = await svc.from("pagamentos_online").select("id,venda_id,status,mp_modo,mp_order_id,mp_payment_id,valor,valor_reembolsado,decisao").eq("id", pagamentoId).maybeSingle();
    if (!g) return resp(req, { ok: false, message: "Pagamento não encontrado." });
    if (g.status !== "aprovado" && g.status !== "reembolso_parcial") return resp(req, { ok: false, message: g.status === "reembolsado" ? "Este pagamento já foi devolvido por inteiro." : "Só dá para devolver um pagamento aprovado." });
    if (!g.mp_order_id) return resp(req, { ok: false, message: "Este pagamento não tem número no Mercado Pago." });

    // só devolve com decisão registrada
    let autorizado = g.decisao === "reembolsar";
    if (!autorizado && g.venda_id) {
      const { data: pend } = await svc.from("reembolsos").select("id").eq("venda_id", g.venda_id).eq("status", "Pendente").limit(1);
      autorizado = !!(pend && pend.length);
    }
    if (!autorizado) return resp(req, { ok: false, message: "Antes de devolver, registre a decisão de reembolsar (ou cancele o pedido pago)." });

    // quanto devolver
    const total = Number(g.valor), jaDevolvido = Number(g.valor_reembolsado || 0), restante = Math.round((total - jaDevolvido) * 100) / 100;
    if (restante <= 0) return resp(req, { ok: false, message: "Não há nada a devolver neste pagamento." });
    const pedido = corpo?.valor === undefined || corpo?.valor === null || corpo?.valor === "" ? restante : Math.round(num(corpo.valor) * 100) / 100;
    if (!(pedido > 0)) return resp(req, { ok: false, message: "Informe um valor maior que zero." });
    if (centavos(pedido) > centavos(restante)) return resp(req, { ok: false, message: `O valor passa do que falta devolver (R$ ${dinheiro(restante).replace(".", ",")}).` });
    const total_ = jaDevolvido === 0 && centavos(pedido) === centavos(total);   // devolução total "limpa": sem corpo

    const cred: any = await credenciais(g.mp_modo);
    if (!cred?.accessToken) return resp(req, { ok: false, message: "As chaves do Mercado Pago deste modo não estão cadastradas." });
    const token = String(cred.accessToken);

    let corpoMp: unknown = undefined;
    if (!total_) {
      let idTransacao = String(g.mp_payment_id || "");
      if (!idTransacao) {   // o id da transação pode não ter sido guardado: pega no pedido
        const c = await mpChamar("GET", `/v1/orders/${encodeURIComponent(g.mp_order_id)}`, token, undefined, undefined, 15000);
        idTransacao = c.status >= 200 && c.status < 300 ? traduzirOrder(c.json).paymentId : "";
      }
      if (!idTransacao) return resp(req, { ok: false, message: "Não foi possível identificar a transação no Mercado Pago. Tente de novo." });
      corpoMp = { transactions: [{ id: idTransacao, amount: dinheiro(pedido) }] };
    }

    // chave fixa: mesmo pagamento + mesmo valor já devolvido + mesmo valor pedido = mesma devolução (repetir não devolve de novo)
    const chave = `ref-${g.id}-${centavos(jaDevolvido)}-${centavos(pedido)}`.slice(0, 64);
    let r: { status: number; json: any };
    try { r = await mpChamar("POST", `/v1/orders/${encodeURIComponent(g.mp_order_id)}/refund`, token, corpoMp, chave); }
    catch (e) {
      if (e instanceof MpRede) { log("mp_reembolso_rede", { pagamentoId }); return resp(req, { ok: false, message: "Não houve resposta do Mercado Pago. Confira no painel do Mercado Pago se a devolução saiu antes de repetir; repetir o mesmo pedido é seguro." }); }
      throw e;
    }
    if (r.status < 200 || r.status >= 300) {
      log("mp_reembolso_http", { pagamentoId, http: r.status, codigo: codigoErroMp(r.json) });
      const msg = r.status === 400 || r.status === 409 || r.status === 422
        ? "O Mercado Pago não aceitou a devolução agora (talvez já exista uma em andamento). Aguarde um minuto e confira o estado do pagamento."
        : "O Mercado Pago não conseguiu devolver agora. Tente de novo em instantes.";
      return resp(req, { ok: false, message: msg });
    }

    // deu certo: registra pela mesma porta do aviso (o banco passa o reembolso pendente para "Devolvido" quando for o total)
    const novoTotal = Math.round((jaDevolvido + pedido) * 100) / 100;
    const completo = centavos(novoTotal) >= centavos(total);
    const ap: any = await aplicarStatus({ pagamentoId: g.id, mpOrderId: g.mp_order_id, status: completo ? "reembolsado" : "reembolso_parcial", valorReembolsado: novoTotal, statusDetalhe: completo ? "refunded" : "partially_refunded" });
    log("mp_reembolso_ok", { pagamentoId, completo, valor: dinheiro(pedido) });
    return resp(req, { ok: true, estado: ap?.status || (completo ? "reembolsado" : "reembolso_parcial"), valorReembolsado: novoTotal, restante: Math.max(0, Math.round((total - novoTotal) * 100) / 100),
      message: completo ? "Devolvido por inteiro pelo Mercado Pago." : `Devolvidos R$ ${dinheiro(pedido).replace(".", ",")}. Ainda faltam R$ ${dinheiro(total - novoTotal).replace(".", ",")}.` });
  } catch (e) {
    log("mp_reembolso_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return resp(req, { ok: false, message: "Não foi possível devolver agora. Tente de novo em instantes." }, 500);
  }
});
