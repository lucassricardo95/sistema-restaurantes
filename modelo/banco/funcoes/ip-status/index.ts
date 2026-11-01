// =====================================================================
// ip-status · consulta ATIVA do pagamento da InfinitePay (cliente LOGADO): chamada pela tela "aguardando pagamento",
// pelo botão "Já paguei" e quando o cliente volta do checkout (com os dados da volta: slug, transaction_nsu, receipt_url).
// verify_jwt = false: confere o login e que a reserva é do cliente.
// Entrada: { reservaId, slug?, transacao?, nsu?, recibo?, metodo? }   Saída: o mesmo de api_mp_status_pagamento + { link, provedor }
// Regras: só aprova depois da consulta payment_check com a InfinitePay (valor pago conferido no banco);
//         pergunta no máximo a cada 5 s por pagamento; o resultado entra pela MESMA porta do aviso (mp_aplicar_status).
// =====================================================================
import { resp, cors, usuario, svc, rpc, aplicarStatus, comoCliente, limite, log, bearer } from "./mp.ts";
import { ehUuid } from "./mp-puro.ts";
import { ipCredenciais, ipConferir, ipRegistrar, IpRede } from "./ip.ts";

const limpo = (v: unknown, max = 80) => String(v || "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, max);
const detalhe = (c: any) => "InfinitePay: pago (" + (c.metodo === "pix" ? "Pix" : c.metodo === "credit_card" ? "crédito " + c.parcelas + "x" : c.metodo || "?") + ")" + (c.valorPago > 0 ? "" : " — valor pago não informado");

// Modo serviço (agendador, a cada 10 min): confere na InfinitePay os pagamentos que ficaram sem resposta (o cliente pagou e fechou a página).
async function conferirPendentes() {
  const cred: any = await ipCredenciais();
  if (!cred?.ligado || cred.modo !== "producao") return { ok: true, conferidos: 0 };
  const lista: any[] = (await rpc("ip_pendentes_conferir")) || [];
  let aprovados = 0;
  for (const g of lista) {
    try {
      const c = await ipConferir(cred, g.id, g.transacao, g.slug);
      await ipRegistrar({ pagamentoId: g.id, conferido: true, metodoPago: c?.metodo || "" });
      if (c?.pago) { await aplicarStatus({ pagamentoId: g.id, status: "aprovado", statusDetalhe: detalhe(c), valorPago: c.valorPago }); aprovados++; }
    } catch (e) { if (!(e instanceof IpRede)) log("ip_conferir_pendente_falhou", { erro: String((e as Error)?.message || e).slice(0, 160) }); }
  }
  if (aprovados) log("ip_conferir_pendentes", { aprovados });
  return { ok: true, conferidos: lista.length, aprovados };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return resp(req, { ok: false, message: "Método não permitido." }, 405);
  try {
    const tok = bearer(req);
    if (tok && (tok === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || tok === String((await rpc("api_segredo", { p_nome: "service_key" }).catch(() => "")) || "-"))) {
      return resp(req, await conferirPendentes());
    }
    const u = await usuario(req);
    if (!u) return resp(req, { ok: false, message: "Entre na sua conta." }, 401);
    if (!limite("ipstatus:" + u.id, 40, 60000)) return resp(req, { ok: false, message: "Muitas consultas seguidas. Aguarde alguns segundos." }, 429);
    const corpo = await req.json().catch(() => ({}));
    const reservaId = String(corpo?.reservaId || "");
    if (!ehUuid(reservaId)) return resp(req, { ok: false, message: "Pedido inválido." }, 400);

    const { data: rv } = await svc.from("pedidos_reserva").select("id,user_id").eq("id", reservaId).maybeSingle();
    if (!rv || rv.user_id !== u.id) return resp(req, { ok: false, message: "Pedido não encontrado." });
    const { data: g } = await svc.from("pagamentos_online").select("id,status,valor,mp_modo,ip_link,ip_slug,ip_transacao,ip_conferido_em,atualizado_em")
      .eq("reserva_id", reservaId).eq("provedor", "infinitepay").order("criado_em", { ascending: false }).limit(1).maybeSingle();

    if (g && g.status === "aguardando" && g.mp_modo === "producao") {
      // dados da volta do checkout (a página manda o que veio no endereço); o order_nsu tem de ser este pagamento
      const nsu = limpo(corpo?.nsu, 64);
      // os dados da volta só valem se o número do pedido (order_nsu) for ESTE pagamento
      if ((corpo?.slug || corpo?.transacao) && nsu && nsu === g.id.replace(/[^A-Za-z0-9_-]/g, "")) {
        await ipRegistrar({ pagamentoId: g.id, slug: limpo(corpo.slug), transacao: limpo(corpo.transacao), recibo: String(corpo?.recibo || ""), metodoPago: limpo(corpo?.metodo, 30) });
      }
      const { data: g2 } = await svc.from("pagamentos_online").select("ip_slug,ip_transacao").eq("id", g.id).maybeSingle();
      const slug = g2?.ip_slug || "", transacao = g2?.ip_transacao || "";   // só o que ficou guardado (conferido) no banco
      const parado = !g.ip_conferido_em || Date.now() - new Date(g.ip_conferido_em).getTime() > 5000;
      if (slug && transacao && parado) {
        try {
          const cred: any = await ipCredenciais();
          const c = await ipConferir(cred, g.id, transacao, slug);
          await ipRegistrar({ pagamentoId: g.id, conferido: true, metodoPago: c?.metodo || "" });
          if (c?.pago) {
            await aplicarStatus({ pagamentoId: g.id, status: "aprovado", statusDetalhe: detalhe(c), valorPago: c.valorPago });
            log("ip_status_aprovado", { pagamentoId: g.id });
          }
        } catch (e) { if (!(e instanceof IpRede)) log("ip_status_consulta_falhou", { erro: String((e as Error)?.message || e).slice(0, 160) }); }
      }
    }

    const cli = await comoCliente(u.token);
    const { data, error } = await cli.rpc("api_mp_status_pagamento", { p: { reservaId } });
    if (error) return resp(req, { ok: false, message: "Não foi possível consultar o pagamento agora." }, 502);
    return resp(req, { ...(data || {}), provedor: "infinitepay", link: g?.ip_link || null, simulacao: g ? g.mp_modo !== "producao" : false });
  } catch (e) {
    log("ip_status_falha", { erro: String((e as Error)?.message || e).slice(0, 200) });
    return resp(req, { ok: false, message: "Não foi possível consultar o pagamento agora." }, 500);
  }
});
