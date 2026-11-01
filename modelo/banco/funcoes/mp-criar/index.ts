// =====================================================================
// mp-criar · cria o pagamento (Pix ou cartão de crédito) no Mercado Pago, pela Orders API. Chamada pelo cardápio (cliente LOGADO).
// verify_jwt = false: a função confere o login do cliente ela mesma (auth.getUser) e o dono da reserva (mp_preparar_pagamento).
// Entrada: { reservaId, token?, paymentMethodId?, paymentTypeId?, payerCpf? }   (os campos de cartão só vêm no cartão)
// Saída:   { ok, estado: aguardando | aprovado | conferindo | recusado | erro, pagamentoId, metodo, pix?, numero?, mensagem? }
// Regras:
//  • o valor vem SEMPRE do banco (reserva já validada): o navegador nunca diz quanto cobrar;
//  • idempotência: a chave do Mercado Pago é o id do pagamento no banco, então repetir a chamada nunca cobra duas vezes;
//  • rede/timeout/5xx: repete UMA vez com a mesma chave; se ainda falhar, solta a reserva e a página oferece "pagar na entrega";
//  • cartão recusado mantém a reserva para outra tentativa; Pix ainda valendo é reaproveitado (decidido no banco);
//  • CPF só vai ao Mercado Pago (cartão) e nada de cartão/CPF é gravado nem escrito no log.
// =====================================================================
import { resp, cors, usuario, svc, rpc, credenciais, aplicarStatus, mpChamar, mpPostComRetentativa, MpRede, limite, log } from "./mp.ts";
import { apenasDigitos, cpfValido, dinheiro, duracaoPix, ehUuid, mensagemRecusa, minusc, traduzirOrder, codigoErroMp } from "./mp-puro.ts";

// Pix antigo da mesma reserva trocado por um novo: cancela no Mercado Pago para ninguém pagar o QR velho (melhor esforço)
async function cancelarSubstituidos(reservaId: string, novoId: string, accessToken: string) {
  try {
    const { data } = await svc.from("pagamentos_online").select("id,mp_order_id").eq("reserva_id", reservaId).eq("metodo", "pix").eq("status", "cancelado")
      .eq("status_detalhe", "substituído por nova tentativa").not("mp_order_id", "is", null).neq("id", novoId).limit(5);
    for (const g of data || []) {
      try {
        await mpChamar("POST", `/v1/orders/${encodeURIComponent(g.mp_order_id)}/cancel`, accessToken, undefined, "cancel-" + g.id, 8000);
        await svc.from("pagamentos_online").update({ status_detalhe: "substituído (cancelado no Mercado Pago)" }).eq("id", g.id);
      } catch { /* melhor esforço */ }
    }
  } catch { /* melhor esforço */ }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return resp(req, { ok: false, message: "Método não permitido." }, 405);
  try {
    const u = await usuario(req);
    if (!u) return resp(req, { ok: false, message: "Entre na sua conta para pagar pelo site." }, 401);
    if (!limite("criar:" + u.id, 12, 60000)) return resp(req, { ok: false, message: "Muitas tentativas seguidas. Aguarde um minuto e tente de novo." }, 429);
    const corpo = await req.json().catch(() => ({}));
    const reservaId = String(corpo?.reservaId || "");
    if (!ehUuid(reservaId)) return resp(req, { ok: false, message: "Pedido inválido. Volte ao carrinho e tente de novo." }, 400);

    // 1) descobre o método da reserva ANTES de gastar uma tentativa (assim dado de cartão faltando não conta como tentativa)
    const { data: rv } = await svc.from("pedidos_reserva").select("user_id,forma_pagamento_id").eq("id", reservaId).maybeSingle();
    if (!rv || rv.user_id !== u.id) return resp(req, { ok: false, message: "Pedido não encontrado." });
    const { data: fp } = await svc.from("formas_pagamento").select("tipo_online").eq("id", rv.forma_pagamento_id).maybeSingle();
    const metodoPedido = fp?.tipo_online === "credito" ? "credito" : fp?.tipo_online === "debito" ? "debito" : fp?.tipo_online === "pix" ? "pix" : "";
    if (!metodoPedido) return resp(req, { ok: false, message: "Esta forma de pagamento não é aceita pelo site." });

    let cartao: { token: string; bandeira: string; cpf: string } | null = null;
    if (metodoPedido === "credito" || metodoPedido === "debito") {
      const tipoMp = metodoPedido === "debito" ? "debit_card" : "credit_card";
      const token = String(corpo?.token || ""), bandeira = minusc(corpo?.paymentMethodId), cpf = apenasDigitos(corpo?.payerCpf);
      if (minusc(corpo?.paymentTypeId || tipoMp) !== tipoMp) return resp(req, { ok: false, message: metodoPedido === "debito" ? "Esta forma aceita só cartão de débito." : "Esta forma aceita só cartão de crédito." });
      if (!/^[A-Za-z0-9_-]{10,80}$/.test(token) || !/^[a-z0-9_]{2,25}$/.test(bandeira)) return resp(req, { ok: false, message: "Os dados do cartão não chegaram. Digite de novo." });
      if (!cpfValido(cpf)) return resp(req, { ok: false, message: "CPF inválido. Confira os números." });
      cartao = { token, bandeira, cpf };
    }

    // 2) o banco confere dono, tempo, ligado e tentativas, e cria a linha do pagamento (ou devolve o Pix que ainda vale)
    const prep: any = await rpc("mp_preparar_pagamento", { p: { reservaId, userId: u.id } });
    if (!prep?.ok) return resp(req, { ok: false, message: prep?.message || "Não foi possível iniciar o pagamento." });
    if (prep.reaproveitar) {
      return resp(req, { ok: true, estado: "aguardando", reaproveitado: true, metodo: "pix", pagamentoId: prep.pagamentoId, valor: prep.valor,
        pix: { copiaCola: prep.pixCopiaCola || "", qrBase64: prep.pixQrBase64 || "", expiraEm: prep.pixExpiraEm || "" } });
    }
    const pagamentoId = String(prep.pagamentoId);
    const falhar = async (mensagem: string, detalhe: string) => {   // não deu nem para criar: solta a reserva (o banco devolve estoque, cupom e brinde)
      await aplicarStatus({ pagamentoId, status: "erro", statusDetalhe: detalhe, erro: detalhe });
      return resp(req, { ok: true, estado: "erro", pagamentoId, metodo: prep.metodo, mensagem });
    };

    // 3) credenciais do modo em que o pagamento nasceu (teste ou produção)
    const cred: any = await credenciais(prep.modo);
    if (!cred?.accessToken) { log("mp_criar_sem_token", { modo: prep.modo }); return await falhar("O pagamento pelo site não está disponível agora. Escolha pagar na entrega.", "sem credencial"); }
    const email = String(prep.email || u.email || "").trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return await falhar("Sua conta está sem e-mail válido. Escolha pagar na entrega.", "sem e-mail");

    // 4) monta o pedido no Mercado Pago (campos mínimos da documentação; valor sempre em texto "00.00")
    const valor = dinheiro(Number(prep.valor));
    const pedidoMp: any = { type: "online", processing_mode: "automatic", total_amount: valor, external_reference: pagamentoId, payer: { email }, transactions: { payments: [] as any[] } };
    if (prep.metodo === "pix") {
      const minutos = Math.max(0, Math.ceil((new Date(prep.expiraEm).getTime() - Date.now()) / 60000));
      pedidoMp.transactions.payments.push({ amount: valor, payment_method: { id: "pix", type: "bank_transfer" }, expiration_time: duracaoPix(minutos) });   // o Mercado Pago só aceita a partir de 30 min
    } else {
      if (!cartao) return await falhar("Os dados do cartão não chegaram. Tente de novo.", "sem dados do cartão");
      pedidoMp.payer.identification = { type: "CPF", number: cartao.cpf };
      pedidoMp.transactions.payments.push({ amount: valor, payment_method: { id: cartao.bandeira, type: prep.metodo === "debito" ? "debit_card" : "credit_card", token: cartao.token, installments: 1 } });   // só à vista (1x)
    }

    // 5) cria no Mercado Pago
    let r: { status: number; json: any };
    try { r = await mpPostComRetentativa("/v1/orders", String(cred.accessToken), pedidoMp, pagamentoId); }
    catch (e) {
      if (e instanceof MpRede) { log("mp_criar_rede", { pagamentoId }); return await falhar("Não conseguimos falar com o Mercado Pago agora. Escolha pagar na entrega.", "rede ou timeout"); }
      throw e;
    }
    if (r.status < 200 || r.status >= 300) {
      log("mp_criar_http", { pagamentoId, http: r.status, codigo: codigoErroMp(r.json), metodo: prep.metodo });
      if ((r.status === 400 || r.status === 422) && (prep.metodo === "credito" || prep.metodo === "debito")) {   // dado do cartão não aceito: cliente pode tentar de novo
        await aplicarStatus({ pagamentoId, status: "recusado", statusDetalhe: "dados rejeitados (" + r.status + ")" });
        return resp(req, { ok: true, estado: "recusado", pagamentoId, metodo: prep.metodo, mensagem: "Os dados do cartão não foram aceitos. Confira e tente de novo, ou pague na entrega." });
      }
      return await falhar("O pagamento pelo site não está disponível agora. Escolha pagar na entrega.", "http " + r.status + " " + codigoErroMp(r.json));
    }

    // 6) entrega o resultado ao banco (única porta) e responde à página
    const tr = traduzirOrder(r.json);
    const ap: any = await aplicarStatus({
      pagamentoId, mpOrderId: tr.orderId, mpPaymentId: tr.paymentId, status: tr.status, statusDetalhe: tr.detalheMp,
      pixCopiaCola: tr.pix?.copiaCola || "", pixQrBase64: tr.pix?.qrBase64 || "", pixExpiraEm: tr.pix?.expiraEm || "",
      cartaoFinal: tr.cartaoFinal, cartaoBandeira: tr.cartaoBandeira, valorReembolsado: tr.valorReembolsado, valorPago: tr.valorPago,
    });
    log("mp_criar_ok", { pagamentoId, metodo: prep.metodo, statusMp: tr.statusMp, detalheMp: tr.detalheMp, status: tr.status });
    if (prep.metodo === "pix") await cancelarSubstituidos(reservaId, pagamentoId, String(cred.accessToken));
    const base = { ok: true, pagamentoId, metodo: prep.metodo, valor: Number(prep.valor), reservaExpiraEm: prep.expiraEm };

    if (tr.status === "aprovado") {
      const res = ap?.resultado || {};
      if (res.vendaId) return resp(req, { ...base, estado: "aprovado", vendaId: res.vendaId, numero: res.numero });
      return resp(req, { ...base, estado: "conferindo", mensagem: "Seu pagamento foi aprovado e estamos conferindo o pedido com o restaurante." });   // caiu em "Pagamento a decidir"
    }
    if (tr.status === "recusado") return resp(req, { ...base, estado: "recusado", mensagem: mensagemRecusa(tr.detalheMp) });
    if (tr.status === "aguardando") return resp(req, { ...base, estado: "aguardando", pix: tr.pix ? { copiaCola: tr.pix.copiaCola, qrBase64: tr.pix.qrBase64, expiraEm: tr.pix.expiraEm } : null, desafio: tr.desafio });
    return resp(req, { ...base, estado: "erro", mensagem: "O pagamento não pôde ser concluído. Tente de novo ou pague na entrega." });   // expirado/cancelado na criação
  } catch (e) {
    log("mp_criar_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return resp(req, { ok: false, message: "Não foi possível processar o pagamento agora. Tente de novo em instantes." }, 500);
  }
});
