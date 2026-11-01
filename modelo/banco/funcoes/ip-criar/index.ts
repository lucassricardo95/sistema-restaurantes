// =====================================================================
// ip-criar · cria o link de pagamento da InfinitePay para uma reserva do cardápio (cliente LOGADO).
// verify_jwt = false: confere o login do cliente (auth.getUser) e o dono da reserva (ip_preparar_pagamento).
// Entrada: { reservaId, retorno }   retorno = endereço do cardápio para onde o cliente volta depois de pagar
// Saída:   { ok, estado: aguardando | erro, pagamentoId, metodo, link?, simulacao?, expiraEm, mensagem? }
// Regras: o valor vem SEMPRE do banco; order_nsu = id do pagamento (imprevisível); o endereço do aviso leva um segredo próprio;
//         SIMULAÇÃO não fala com a InfinitePay (o pagamento é decidido pelos botões Pagar / Recusar / Expirar).
// =====================================================================
import { resp, cors, usuario, rpc, aplicarStatus, limite, log, URL_ } from "./mp.ts";
import { ehUuid } from "./mp-puro.ts";
import { ipCredenciais, ipPost, ipRegistrar, IpRede, centavos } from "./ip.ts";

const RETORNOS = [(Deno.env.get("SITE_URL") || "").replace(/\/?$/, "/"), "http://localhost:8080/", "http://127.0.0.1:8080/", "http://localhost:5500/", "http://127.0.0.1:5500/"].filter((x) => x.length > 1);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return resp(req, { ok: false, message: "Método não permitido." }, 405);
  try {
    const u = await usuario(req);
    if (!u) return resp(req, { ok: false, message: "Entre na sua conta para pagar pelo site." }, 401);
    if (!limite("ipcriar:" + u.id, 12, 60000)) return resp(req, { ok: false, message: "Muitas tentativas seguidas. Aguarde um minuto e tente de novo." }, 429);
    const corpo = await req.json().catch(() => ({}));
    const reservaId = String(corpo?.reservaId || "");
    if (!ehUuid(reservaId)) return resp(req, { ok: false, message: "Pedido inválido. Volte ao carrinho e tente de novo." }, 400);
    let retorno = String(corpo?.retorno || "").split("#")[0].split("?")[0];
    if (!RETORNOS.some((r) => retorno.startsWith(r))) retorno = RETORNOS[0];

    const prep: any = await rpc("ip_preparar_pagamento", { p: { reservaId, userId: u.id } });
    if (!prep?.ok) return resp(req, { ok: false, message: prep?.message || "Não foi possível iniciar o pagamento." });
    const pagamentoId = String(prep.pagamentoId);
    const base = { ok: true, pagamentoId, metodo: prep.metodo, valor: Number(prep.valor), expiraEm: prep.expiraEm, provedor: "infinitepay" };
    if (prep.reaproveitar) return resp(req, { ...base, estado: "aguardando", reaproveitado: true, link: prep.link || null, simulacao: !!prep.simulacao });
    if (prep.simulacao) { log("ip_criar_simulacao", { pagamentoId }); return resp(req, { ...base, estado: "aguardando", simulacao: true }); }

    const falhar = async (mensagem: string, detalhe: string) => {   // não deu para criar: solta a reserva (estoque, cupom e brinde voltam)
      await aplicarStatus({ pagamentoId, status: "erro", statusDetalhe: detalhe, erro: detalhe });
      return resp(req, { ...base, estado: "erro", mensagem });
    };
    const cred: any = await ipCredenciais();
    if (!cred?.handle) return await falhar("O pagamento pela InfinitePay não está disponível agora. Escolha pagar na entrega.", "sem InfiniteTag");
    if (!cred?.webhookSegredo) log("ip_criar_sem_segredo_aviso", { pagamentoId });   // segue: a volta do checkout e o "Já paguei" confirmam pela consulta

    const qtd = Math.max(1, Number(prep.quantidade) || 1);
    const pedido: Record<string, unknown> = {
      handle: String(cred.handle),
      items: [{ quantity: 1, price: centavos(Number(prep.valor)), description: `Pedido Restaurante (${qtd} ${qtd === 1 ? "item" : "itens"})` }],
      order_nsu: pagamentoId,
      redirect_url: retorno + "?ipRetorno=" + encodeURIComponent(reservaId),
      customer: { name: String(prep.nome || "").slice(0, 80), email: String(prep.email || u.email || ""), phone_number: "+55" + String(prep.telefone || "").replace(/\D/g, "") },
    };
    if (cred.webhookSegredo) pedido.webhook_url = `${URL_}/functions/v1/ip-webhook?s=${encodeURIComponent(String(cred.webhookSegredo))}`;
    if (!/^\+55\d{10,11}$/.test(String((pedido.customer as any).phone_number))) delete (pedido.customer as any).phone_number;

    let r: { status: number; json: any };
    try { r = await ipPost("/links", pedido, cred.chave); }
    catch (e) { if (e instanceof IpRede) { log("ip_criar_rede", { pagamentoId }); return await falhar("Não conseguimos falar com a InfinitePay agora. Escolha pagar na entrega.", "rede ou timeout"); } throw e; }
    const link = String(r.json?.url || r.json?.link || r.json?.checkout_url || r.json?.data?.url || "");
    if (r.status < 200 || r.status >= 300 || !/^https:\/\//.test(link)) {
      log("ip_criar_http", { pagamentoId, http: r.status });
      return await falhar("O pagamento pela InfinitePay não está disponível agora. Escolha pagar na entrega.", "http " + r.status + (link ? "" : " sem link"));
    }
    const reg: any = await ipRegistrar({ pagamentoId, link }).catch(() => null);
    if (!reg?.ok) return await falhar("Não foi possível guardar o pagamento agora. Escolha pagar na entrega ou tente de novo.", "link não guardado");
    log("ip_criar_ok", { pagamentoId, metodo: prep.metodo });
    return resp(req, { ...base, estado: "aguardando", link });
  } catch (e) {
    log("ip_criar_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return resp(req, { ok: false, message: "Não foi possível processar o pagamento agora. Tente de novo em instantes." }, 500);
  }
});
