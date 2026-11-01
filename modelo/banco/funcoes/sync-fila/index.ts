import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, cfg } from "./auth.ts";
const SHEETS_MAIN = await cfg("SHEETS_MAIN_URL");
const CHAVE_SERVIDOR = await cfg("PRINCIPAL_CHAVE_SERVIDOR");

// A fila vai SÓ para a planilha principal. A contingência é alimentada pela própria planilha principal
// (sincronizarContingencia no Apps Script), então não depende do Supabase para se atualizar.
async function enviar(url: string, corpo: any) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 30000);
  try {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "text/plain" }, body: JSON.stringify(corpo), signal: ctl.signal });
    const raw = await r.text();
    let j: any;
    try { j = JSON.parse(raw); } catch { throw new Error(`Planilha respondeu conteúdo inválido (HTTP ${r.status}).`); }
    if (!r.ok) throw new Error(`Planilha respondeu HTTP ${r.status}.`);
    return j;
  } catch (e) {
    if ((e as Error)?.name === "AbortError") throw new Error("Tempo esgotado aguardando a planilha (30 s). A fila permanece pendente para nova tentativa.");
    throw e;
  } finally { clearTimeout(timer); }
}

// Mantém o Apps Script "acordado": sem chamadas, ele fica parado e a primeira resposta leva vários segundos (partida a frio).
// Quando a fila está vazia, este toque leve (?ping=1, não lê planilha) roda a cada execução do cron (2 min).
async function aquecer(url: string) {
  if (!url) return false;
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 15000);
  try {
    const r = await fetch(url + (url.includes("?") ? "&" : "?") + "ping=1", { signal: ctl.signal });
    await r.text();
    return r.ok;
  } catch { return false; } finally { clearTimeout(t); }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin", "Operador"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const svc = svcClient();
    const { data: lote } = await svc.rpc("api_sync_lote", { p_limite: 100 });
    let ok = 0, er = 0, aquecida = false;
    const itens = lote?.itens || [];
    if (itens.length) {
      const ids = itens.map((i: any) => i.id);
      try {
        const j = await enviar(SHEETS_MAIN, { action: "syncLote", chave: CHAVE_SERVIDOR, itens });
        if (j?.ok) { await svc.rpc("api_sync_marcar", { p_ids: ids, p_destino: "principal", p_ok: true }); ok = ids.length; }
        else { await svc.rpc("api_sync_marcar", { p_ids: ids, p_destino: "principal", p_ok: false, p_erro: j?.message || "erro" }); er = ids.length; }
      } catch (e) {
        await svc.rpc("api_sync_marcar", { p_ids: ids, p_destino: "principal", p_ok: false, p_erro: (e as Error).message }); er = ids.length;
      }
    } else {
      aquecida = await aquecer(SHEETS_MAIN);
    }
    return json({ ok: true, principal: { enviados: ok, erros: er }, aquecida });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
