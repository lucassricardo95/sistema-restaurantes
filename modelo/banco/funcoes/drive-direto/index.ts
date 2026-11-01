// Executa no Google Drive (OAuth direto) o que antes passava pela planilha. Só execução interna (chave de serviço):
// as outras funções chamam esta primeiro e, se ela devolver usado:false, seguem pela planilha (Apps Script).
import { CORS, json, autorizar } from "./auth.ts";
import { tentarDireto } from "./drive-acoes.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, null);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const corpo = await req.json();
    if (corpo?.action === "limpezaDiaria") {   // rotina do cron: responde já e termina em segundo plano
      const p = tentarDireto(corpo), rt = (globalThis as any).EdgeRuntime;
      if (rt?.waitUntil) { rt.waitUntil(p); return json({ ok: true, usado: true, r: { ok: true, iniciado: true } }); }
      return json({ ok: true, usado: true, r: await p });
    }
    const r = await tentarDireto(corpo);
    return json(r === null ? { ok: true, usado: false } : { ok: true, usado: true, r });
  } catch (e) { return json({ ok: true, usado: false, erro: (e as Error).message }); }
});
