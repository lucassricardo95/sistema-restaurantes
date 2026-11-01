import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, cfg } from "./auth.ts";
const SHEETS_MAIN = await cfg("SHEETS_MAIN_URL");
const CHAVE_SERVIDOR = await cfg("PRINCIPAL_CHAVE_SERVIDOR");

// Compara as vendas confirmadas de UM dia no Supabase e na planilha principal (a reserva).
// Agendada (cron:true): confere o dia ANTERIOR, que já está completo. Manual: confere o dia de hoje, ou o dia pedido em body.dia (AAAA-MM-DD).
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const svc = svcClient();
    const corpo = await req.json().catch(() => ({}));
    const fmt = (d: Date) => new Intl.DateTimeFormat("sv-SE", { timeZone: "America/Sao_Paulo" }).format(d);
    const hojeBr = fmt(new Date());
    let dia = /^\d{4}-\d{2}-\d{2}$/.test(String(corpo?.dia || "")) ? String(corpo.dia) : hojeBr;
    if (corpo?.cron === true && !corpo?.dia) dia = fmt(new Date(new Date(`${hojeBr}T12:00:00-03:00`).getTime() - 86400000));
    const ini = new Date(`${dia}T00:00:00-03:00`);
    const fim = new Date(ini.getTime() + 86400000);
    const { count: sb } = await svc.from("vendas").select("*", { count: "exact", head: true })
      .gte("data_hora", ini.toISOString()).lt("data_hora", fim.toISOString()).eq("status", "Confirmada");
    const { count: pend } = await svc.from("fila_sync").select("*", { count: "exact", head: true }).is("principal_ok_em", null);

    const j = await (await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
      body: JSON.stringify({ action: "contarVendasHoje", chave: CHAVE_SERVIDOR, data: dia }) })).json();
    const pl = j?.total ?? 0, dif = (sb || 0) - pl;
    // vendas ainda na fila explicam parte da diferença: só é divergência o que sobra além delas
    const divergente = Math.abs(dif) > Math.max(1, pend || 0);

    await svc.from("integridade_checks").insert({ supabase_vendas: sb || 0, planilha_vendas: pl, diferenca_vendas: dif,
      status: j?.ok ? (divergente ? "divergencia" : "ok") : "erro", detalhe: { data: dia, pendentes_fila: pend } });
    if (divergente) await svc.from("auditoria").insert({ usuario_login: "sistema", acao: "ALERTA: divergência de vendas",
      detalhes: `Dia ${dia} · Supabase: ${sb} · Planilha: ${pl} · Diferença: ${dif} · Na fila: ${pend}` });
    return json({ ok: true, dia, supabase: sb, planilha: pl, dif, pendentes_fila: pend });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
