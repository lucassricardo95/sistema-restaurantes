// ifood-sync · Analytics (API de KPIs do iFood): números históricos D-1 (até ONTEM), sempre agregados por loja e dia — nunca pedido a pedido.
// Usa um SEGUNDO aplicativo do Portal do Desenvolvedor (categoria BI) com Client ID/Secret próprios (guardados como ifood_bi_client_id/secret).
// ⚠️ Corpo/resposta seguem a documentação oficial do Analytics v1.0; o formato exato da resposta ainda NÃO foi visto com o iFood de verdade,
// por isso a leitura é tolerante (aceita "metrics" dentro do item ou direto nele). Se o iFood devolver algo diferente, o erro aparece na tela.
type Ctx = {
  http1: (metodo: string, caminho: string, token: string | null, corpo?: unknown, extra?: Record<string, string>) => Promise<any>;
  http: (metodo: string, caminho: string, token: string | null, corpo?: unknown, extra?: Record<string, string>) => Promise<any>;
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<any>;
  HttpErro: any;
};

const num = (v: unknown): number => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const arred = (v: number, c = 2) => Math.round(v * 10 ** c) / 10 ** c;

async function tokenBI(ctx: Ctx, cred: any, forcar = false): Promise<string> {
  if (!forcar) { const t: any = await ctx.rpc("ifood_bi_token_ler"); if (t && t.token) return t.token; }
  if (!cred.clientId || !cred.clientSecret) throw new ctx.HttpErro(401, "faltam o Client ID e o Client Secret do aplicativo BI");
  const r: any = await ctx.http1("POST", "/authentication/v1.0/oauth/token", null,
    new URLSearchParams({ grantType: "client_credentials", clientId: cred.clientId, clientSecret: cred.clientSecret }));
  const token = r?.accessToken || r?.access_token;
  if (!token) throw new ctx.HttpErro(401, "resposta sem token");
  await ctx.rpc("ifood_bi_token_gravar", { p_token: token, p_seg: Math.max(60, num(r?.expiresIn || r?.expires_in || 3600) - 30) });
  return token;
}

async function kpis(ctx: Ctx, cred: any, corpo: any): Promise<any[]> {
  const m = encodeURIComponent(cred.merchantId || "");
  const extra: Record<string, string> = cred.homologacao ? { "x-request-homologation": "true" } : {};
  const todos: any[] = [];
  let token = await tokenBI(ctx, cred);
  for (let pagina = 1; pagina <= 5; pagina++) {
    const body = { ...corpo, page: pagina, size: 500 };
    let r: any;
    try { r = await ctx.http("POST", `/analytics/v1.0/merchants/${m}/orders/kpis`, token, body, extra); }
    catch (e) {
      if (e instanceof ctx.HttpErro && (e as any).status === 401) { token = await tokenBI(ctx, cred, true); r = await ctx.http("POST", `/analytics/v1.0/merchants/${m}/orders/kpis`, token, body, extra); }
      else throw e;
    }
    const data: any[] = Array.isArray(r?.data) ? r.data : [];
    todos.push(...data);
    if (pagina >= num(r?.totalPages || 1)) break;
  }
  return todos;
}

// leitura tolerante de um item da resposta
const chaveDe = (it: any, campo: string) => { const k = it?.groupByKey || it?.groupBy || {}; const v = (k.value || k)[campo]; return v == null ? "" : String(v); };
const contagem = (it: any) => num((it?.groupByKey || it?.groupBy || {}).count ?? it?.count);
const met = (it: any, campo: string, fn: string) => num((it?.metrics?.[campo] ?? it?.[campo] ?? {})[fn]);

const ST_TXT: Record<string, string> = { CONCLUDED: "Concluídos", CANCELLED: "Cancelados", DELIVERED: "Entregues", DISPATCHED: "Saíram para entrega", PLACED: "Recebidos", CONFIRMED: "Confirmados" };
const DIA_TXT = ["", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado", "Domingo"];
const CANAL_TXT: Record<string, string> = { IFOOD: "App do iFood", DIGITAL_CATALOG: "Cardápio digital / link da loja" };
const ENTREGA_TXT: Record<string, string> = { IFOOD_DELIVERY: "Entregador do iFood", MERCHANT_DELIVERY: "Entrega própria da loja", TAKEOUT: "Retirada na loja" };

function agrupado(itens: any[], campo: string, rot: (k: string) => string) {
  return itens.map((it) => ({ chave: chaveDe(it, campo), nome: rot(chaveDe(it, campo)), pedidos: contagem(it), gmv: arred(met(it, "gmv", "sum")), semEntrega: arred(met(it, "gmvWithoutDelivery", "sum")) }))
    .filter((x) => x.chave !== "");
}

export async function executarAnalytics(ctx: Ctx, a: any) {
  const chave: string = a.dados?.bi; const de: string = a.dados?.de; const ate: string = a.dados?.ate;
  const falhar = async (msg: string, definitivo: boolean) => {
    try { await ctx.rpc("ifood_bi_gravar", { p_chave: chave, p_dados: null, p_erro: msg }); } catch { /* sem registro */ }
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: definitivo ? "erro" : "duvida", p_erro: msg });
  };
  try {
    const cred: any = await ctx.rpc("ifood_bi_credenciais");
    if (!cred?.clientId || !cred?.clientSecret) return await falhar("Faltam o Client ID e o Client Secret do aplicativo BI (Analytics). Digite em Integrações › iFood.", true);
    if (!cred?.merchantId) return await falhar("Falta o código da loja (Merchant ID) em Integrações › iFood.", true);
    const filtro = (extra: Record<string, unknown> = {}) => ({ referenceDate: { gte: de + " 00:00:00", lte: ate + " 23:59:59" }, ...extra });
    const avisos: string[] = [];
    const tentar = async (rot: string, corpo: any) => {
      try { return await kpis(ctx, cred, corpo); }
      catch (e) {
        if (rot === "status") throw e;   // sem o resumo principal não há o que mostrar
        avisos.push(rot + ": " + (e instanceof ctx.HttpErro ? (e as any).status + " " + String((e as any).corpo || "").slice(0, 120) : String(e)));
        return [];
      }
    };
    const M = { gmv: ["sum"], gmvWithoutDelivery: ["sum"] };
    const status = await tentar("status", { agg: { groupBy: { fields: ["orderStatus"] }, metrics: { ...M, netDeliveryFee: ["sum"] } }, filter: filtro() });
    const conc = { orderStatus: ["CONCLUDED"] };
    const canais = await tentar("canal de venda", { agg: { groupBy: { fields: ["salesChannel"] }, metrics: M }, filter: filtro(conc) });
    const entregas = await tentar("quem entrega", { agg: { groupBy: { fields: ["deliveredBy"] }, metrics: M }, filter: filtro(conc) });
    const pagtos = await tentar("forma de pagamento", { agg: { groupBy: { fields: ["paymentMethod"] }, metrics: M }, filter: filtro(conc) });
    const dias = await tentar("dia da semana", { agg: { groupBy: { fields: ["dayOfWeek"] }, metrics: M }, filter: filtro(conc) });
    const horas = await tentar("hora do pedido", { agg: { groupBy: { fields: ["orderCreationHour"] }, metrics: M }, filter: filtro(conc) });
    const novos = await tentar("clientes novos", { agg: { groupBy: { fields: ["customerFirstOrderInMerchant"] }, metrics: M }, filter: filtro(conc) });
    const canc = await tentar("motivos de cancelamento", { agg: { groupBy: { fields: ["cancellationReason"] }, metrics: { gmv: ["sum"] } }, filter: filtro({ orderStatus: ["CANCELLED"] }) });
    const tempos = await tentar("tempos", { agg: { metrics: { timeToAcceptInMin: ["avg"], preparationTimeInMin: ["avg"], timeToDeliveryInMin: ["avg"], timeDelayedInMin: ["avg"], timeToDeliveryExpectedInMin: ["avg"], distanceKm: ["avg"], refundedTotalValue: ["sum"] } }, filter: filtro(conc) });

    const st = agrupado(status, "orderStatus", (k) => ST_TXT[k] || k);
    const taxas: Record<string, number> = {}; status.forEach((it) => { taxas[chaveDe(it, "orderStatus")] = arred(met(it, "netDeliveryFee", "sum")); });
    const concl = st.find((x) => x.chave === "CONCLUDED"), cancs = st.find((x) => x.chave === "CANCELLED");
    const totalPed = st.reduce((s, x) => s + x.pedidos, 0), totalGmv = arred(st.reduce((s, x) => s + x.gmv, 0));
    const t0 = tempos[0] || {};
    const dados = {
      geradoEm: new Date().toISOString(), de, ate, homologacao: !!cred.homologacao,
      resumo: {
        pedidosTotal: totalPed, gmvTotal: totalGmv,
        concluidos: concl?.pedidos || 0, gmvConcluidos: concl?.gmv || 0, gmvSemEntregaConcluidos: concl?.semEntrega || 0,
        cancelados: cancs?.pedidos || 0, gmvCancelados: cancs?.gmv || 0,
        ticketMedio: concl && concl.pedidos ? arred(concl.gmv / concl.pedidos) : 0,
        taxaCancelamentoPct: totalPed ? arred((cancs?.pedidos || 0) * 100 / totalPed, 1) : 0,
        taxaEntregaLiquida: taxas["CONCLUDED"] || 0,
      },
      status: st,
      canais: agrupado(canais, "salesChannel", (k) => CANAL_TXT[k] || k),
      entregas: agrupado(entregas, "deliveredBy", (k) => ENTREGA_TXT[k] || k),
      pagamentos: agrupado(pagtos, "paymentMethod", (k) => k),
      dias: agrupado(dias, "dayOfWeek", (k) => DIA_TXT[num(k)] || k).sort((x, y) => num(x.chave) - num(y.chave)),
      horas: agrupado(horas, "orderCreationHour", (k) => k + "h").sort((x, y) => num(x.chave) - num(y.chave)),
      clientes: agrupado(novos, "customerFirstOrderInMerchant", (k) => (k === "true" ? "Primeiro pedido na loja" : "Cliente que já comprou")),
      cancelamentos: agrupado(canc, "cancellationReason", (k) => k).sort((x, y) => y.pedidos - x.pedidos).slice(0, 10),
      tempos: {
        aceitarMin: arred(met(t0, "timeToAcceptInMin", "avg"), 1), preparoMin: arred(met(t0, "preparationTimeInMin", "avg"), 1), entregaMin: arred(met(t0, "timeToDeliveryInMin", "avg"), 1),
        atrasoMin: arred(met(t0, "timeDelayedInMin", "avg"), 1), previstoMin: arred(met(t0, "timeToDeliveryExpectedInMin", "avg"), 1), distanciaKm: arred(met(t0, "distanceKm", "avg"), 1),
        reembolsado: arred(met(t0, "refundedTotalValue", "sum")),
      },
      avisos,
    };
    await ctx.rpc("ifood_bi_gravar", { p_chave: chave, p_dados: dados, p_erro: null });
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof ctx.HttpErro ? (er as any).status : 0;
    const c = er instanceof ctx.HttpErro ? String((er as any).corpo || "").slice(0, 200) : "";
    const msg = !(er instanceof ctx.HttpErro) ? String((er as any)?.message || er)
      : st === 401 ? "O iFood recusou o Client ID/Secret do aplicativo BI (401). Confira os dois valores."
      : st === 403 ? "O aplicativo BI não tem acesso ao Analytics para esta loja (403). Confira no Portal do Desenvolvedor se o módulo Analytics está no aplicativo e se a loja foi vinculada."
      : st === 400 ? "O iFood recusou o pedido de números (400): " + c
      : st === 429 ? "Muitas consultas ao iFood (429). Tente de novo em alguns minutos."
      : st === 0 ? "Sem resposta do iFood agora. Tente de novo." : `Erro ${st} do iFood: ${c}`;
    await falhar(msg, st >= 400 && st < 500 && st !== 429);
  }
}
