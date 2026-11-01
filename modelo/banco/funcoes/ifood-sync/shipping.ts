// ifood-sync · Entregador do iFood (módulo Shipping / Sob Demanda).
// Modo A: pedido que veio do iFood com entrega própria → cotar (deliveryAvailabilities), chamar (requestDriver), cancelar (cancelRequestDriver).
// Modo B: pedido de fora do iFood → cotar pelo endereço (merchants/{id}/deliveryAvailabilities), criar (merchants/{id}/orders), cancelar (cancel) com motivos do iFood.
// ⚠️ Corpos e endereços seguem a documentação oficial do Shipping v1.0; ainda NÃO testados com o iFood de verdade (precisa do serviço Sob Demanda contratado).
// O resultado de cada passo volta por eventos (REQUEST_DRIVER_*, DELIVERY_*), tratados em ifood_ship_evento.
type Ctx = { chamar: (cred: any, metodo: string, caminho: string, corpo?: unknown) => Promise<any>; rpc: (fn: string, args?: Record<string, unknown>) => Promise<any>; HttpErro: any };

const CODIGOS = ["DeliveryDistanceTooHigh", "ServiceAreaMismatch", "OffOpeningHours", "HighDemand", "MerchantEasyDeliveryDisabled", "MerchantStatusAvailability", "InvalidPaymentMethods",
  "SaturatedOfflinePayment", "NRELimitExceeded", "UnavailableFleet", "OriginNotFound", "BadRequestMerchant", "BadRequestCustomer", "BadRequest"];

async function erroTexto(ctx: Ctx, er: unknown): Promise<string> {
  if (!(er instanceof ctx.HttpErro)) return String((er as any)?.message || er);
  const st = (er as any).status, c = String((er as any).corpo || "");
  const cod = CODIGOS.find((x) => c.includes(x));
  let t: string | null = null;
  if (cod) { try { t = (await ctx.rpc("_ifood_ship_erro_txt", { p_codigo: cod })) as string | null; } catch { /* usa o texto genérico */ } }
  if (!t) {
    t = st === 401 || st === 403 ? "O iFood não autorizou (" + st + "): confira se o serviço Sob Demanda está contratado e liberado para este aplicativo."
      : st === 404 ? "O iFood não encontrou o pedido ou a loja (404). A cotação pode ter vencido: peça outra."
      : st === 429 ? "Muitas consultas ao iFood (429). Espere um minuto e tente de novo."
      : st === 400 || st === 422 ? "O iFood recusou os dados (" + st + ")." : "Erro " + st + " do iFood.";
  }
  return (cod ? t + " (" + cod + ")" : t + " Resposta do iFood: " + c.slice(0, 200));
}

const numero = (v: unknown) => { const n = Number(String(v ?? "").replace(",", ".")); return Number.isFinite(n) ? n : null; };

export async function executarShipping(ctx: Ctx, cred: any, a: any) {
  const m = encodeURIComponent(cred.merchantId || "");
  const id: string = a.dados?.ship;
  const resultado = (estado: string, patch: Record<string, unknown> = {}, erro: string | null = null) => ctx.rpc("ifood_ship_resultado", { p_id: id, p_estado: estado, p_patch: patch, p_erro: erro });
  const info: any = id ? await ctx.rpc("ifood_ship_dados", { p_id: id }) : null;
  if (!info) { await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "pulada", p_erro: "entrega não encontrada" }); return; }
  const shipId: string = info.shipId || "";
  try {
    if (a.acao === "ship_cotar") {
      let r: any;
      if (info.modo === "A") r = await ctx.chamar(cred, "GET", `/shipping/v1.0/orders/${encodeURIComponent(info.pedidoIfood)}/deliveryAvailabilities`);
      else {
        const e = info.endereco || {};
        r = await ctx.chamar(cred, "GET", `/shipping/v1.0/merchants/${m}/deliveryAvailabilities?latitude=${encodeURIComponent(String(e.lat))}&longitude=${encodeURIComponent(String(e.lng))}`);
      }
      if (!r?.id) throw new Error("o iFood não devolveu a cotação (sem entregador disponível agora?)");
      const q = r.quote || {};
      const valor = numero(q.netValue ?? q.grossValue ?? r.netValue ?? r.grossValue);
      await resultado("cotada", { quoteId: r.id, valor, expiraEm: r.expirationAt || null,
        quote: { deliveryTime: r.deliveryTime || q.deliveryTime || null, distance: r.distance ?? null, paymentMethods: r.paymentMethods || [], grossValue: q.grossValue ?? null, discount: q.discount ?? null, raise: q.raise ?? null, netValue: q.netValue ?? null } });
    } else if (a.acao === "ship_chamar") {
      if (!info.ligado) throw new Error("o entregador do iFood foi desligado antes do envio");
      if (info.modo === "A") {
        await ctx.chamar(cred, "POST", `/shipping/v1.0/orders/${encodeURIComponent(info.pedidoIfood)}/requestDriver`, { quoteId: info.quoteId });
        await resultado("solicitando");
      } else {
        const corpo: any = await ctx.rpc("ifood_ship_payload_b", { p_id: id });
        if (corpo?.erro) throw new Error(String(corpo.erro));
        delete corpo.telefoneTipo;
        const r: any = await ctx.chamar(cred, "POST", `/shipping/v1.0/merchants/${m}/orders`, corpo);
        if (!r?.id) throw new Error("o iFood não devolveu o código do pedido de entrega");
        await resultado("solicitando", { shipId: r.id, trackingUrl: r.trackingUrl || null });
      }
    } else if (a.acao === "ship_motivos") {
      const r: any = await ctx.chamar(cred, "GET", `/shipping/v1.0/orders/${encodeURIComponent(shipId)}/cancellationReasons`);
      const lista = Array.isArray(r) ? r : [];
      await resultado("", { motivos: lista.map((x: any) => ({ cancelCodeId: String(x.cancelCodeId ?? x.code ?? ""), description: String(x.description ?? x.reason ?? "") })) });
      if (!lista.length) await resultado("", {}, "O iFood não permite cancelar esta entrega agora (já entregue ou cancelada).");
    } else if (a.acao === "ship_cancelar") {
      if (info.modo === "A") await ctx.chamar(cred, "POST", `/shipping/v1.0/orders/${encodeURIComponent(info.pedidoIfood)}/cancelRequestDriver`);
      else await ctx.chamar(cred, "POST", `/shipping/v1.0/orders/${encodeURIComponent(shipId)}/cancel`, { reason: String(a.dados?.motivo || "Cancelado pela loja").slice(0, 200), cancellationCode: Number(a.dados?.codigo) });
      await resultado("cancelando");   // o evento de cancelamento fecha o estado
    } else if (a.acao === "ship_endereco") {
      const rota = a.dados?.acao === "aceitar" ? "acceptDeliveryAddressChange" : a.dados?.acao === "negar" ? "denyDeliveryAddressChange" : "userConfirmAddress";
      await ctx.chamar(cred, "POST", `/shipping/v1.0/orders/${encodeURIComponent(shipId)}/${rota}`);
      await resultado("", { limparEndereco: true });
    } else if (a.acao === "ship_safe") {
      try {
        const r: any = await ctx.chamar(cred, "GET", `/shipping/v1.0/orders/${encodeURIComponent(shipId)}/safeDelivery`);
        await resultado("", { safeScore: r?.score || null, safeRegras: r?.rules || {} });
      } catch (er) {
        if (er instanceof ctx.HttpErro && (er as any).status === 400) await resultado("", { safeScore: "SEM_REGRAS" }, null);   // pedido antigo, sem regras de confiança
        else throw er;
      }
    }
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof ctx.HttpErro ? (er as any).status : 0;
    const msg = await erroTexto(ctx, er);
    const definitivo = (st >= 400 && st < 500 && st !== 429) || (st === 0 && !(er instanceof ctx.HttpErro));
    if (definitivo) {
      // devolve a entrega a um estado em que a equipe possa agir de novo, com o motivo em português
      const volta: Record<string, string> = { ship_cotar: "erro_cotacao", ship_chamar: "falhou", ship_cancelar: "alocada" };
      try { await resultado(volta[a.acao] || "", {}, msg); } catch { /* sem registro */ }
    }
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: definitivo ? "erro" : "duvida", p_erro: msg });
  }
}
