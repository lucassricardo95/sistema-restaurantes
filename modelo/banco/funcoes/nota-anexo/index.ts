import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, cfg } from "./auth.ts";
import * as AUTH_ from "./auth.ts";
// Primeiro o Drive direto (função drive-direto, OAuth); se ela não puder, devolve null e segue a planilha (Apps Script).
async function tentarDireto(corpo: Record<string, unknown>): Promise<any | null> {
  try {
    const r = await fetch(`${AUTH_.URL_}/functions/v1/drive-direto`, { method: "POST", headers: { Authorization: `Bearer ${AUTH_.CHAVE_SERVICO}`, "Content-Type": "application/json" }, body: JSON.stringify(corpo), signal: AbortSignal.timeout(125000) });
    const j = await r.json(); return j?.usado ? j.r : null;
  } catch { return null; }
}
// Primeiro o Drive direto (OAuth, rápido); se não der, a planilha (Apps Script) como segundo caminho.
async function planilha(corpo: Record<string, unknown>, ms?: number) {
  const d = await tentarDireto(corpo);
  return d ?? await (planilhaApps as any)(corpo, ms);
}
const SHEETS_MAIN = await cfg("SHEETS_MAIN_URL");
const CHAVE_SERVIDOR = await cfg("PRINCIPAL_CHAVE_SERVIDOR");

// Comprovante da nota de compra (foto ou PDF) no Google Drive, pelo mesmo caminho das fotos dos produtos:
// Edge Function -> planilha principal (Apps Script, dono do Drive) -> Drive principal e/ou Drive da contingência.
// Diferença das fotos: os arquivos ficam PRIVADOS (sem link público). Só o Admin vê, e o conteúdo passa por aqui.
// Trocar o comprovante não apaga o antigo do Drive (fica como histórico; conservador).
// anexo_path guardado na compra: "drive:<id>", "cont:<id>" ou "drive:<id>|cont:<id>".
async function planilhaApps(corpo: Record<string, unknown>) {
  const r = await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
    body: JSON.stringify({ chave: CHAVE_SERVIDOR, ...corpo }) });
  return await r.json();
}
const desatualizada = (m: string) => /Ação desconhecida/i.test(m || "")
  ? "A planilha principal ainda não tem a função de comprovantes: cole o código novo do Apps Script e publique uma nova versão (ver LEIA-ME)." : m;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const b = await req.json();
    if (b.acao === "enviar") {
      if (!b.base64Data || String(b.base64Data).length > 4.2 * 1024 * 1024) return json({ ok: false, message: "Arquivo ausente ou maior que 3 MB." }, 400);
      // o comprovante fica no Drive principal; se ele não responder, vai para o da contingência
      let j = await planilha({ action: "sbGuardarNota", base64Data: b.base64Data, nomeBase: String(b.nomeBase || "nota").slice(0, 60), destino: "principal" });
      if (!j?.ok) { const k = await planilha({ action: "sbGuardarNota", base64Data: b.base64Data, nomeBase: String(b.nomeBase || "nota").slice(0, 60), destino: "contingencia" }); if (k?.ok) j = k; }
      if (!j?.ok) return json({ ok: false, message: desatualizada(j?.message) || "Falha ao salvar o comprovante." }, 502);
      const partes = [j.id ? "drive:" + j.id : "", j.idReserva ? "cont:" + j.idReserva : ""].filter(Boolean);
      return json({ ok: true, path: partes.join("|"), aviso: "" });
    }
    if (b.acao === "ver") {
      const { data: c } = await svcClient().from("compras").select("anexo_path").eq("id", b.compraId).single();
      const path = String(c?.anexo_path || "");
      if (!path) return json({ ok: false, message: "Esta nota não tem comprovante." }, 404);
      const partes = Object.fromEntries(path.split("|").map((x) => x.split(":")).filter((x) => x.length === 2));
      let ultimo = "";
      for (const [onde, chave] of [["principal", "drive"], ["contingencia", "cont"]]) {
        if (!partes[chave]) continue;
        const j = await planilha({ action: "sbLerNota", id: partes[chave], onde });
        if (j?.ok && j.base64) return json({ ok: true, tipo: j.tipo, nome: j.nome, base64: j.base64, de: onde });
        ultimo = desatualizada(j?.message) || ultimo;
      }
      return json({ ok: false, message: ultimo || "Não consegui abrir o comprovante (formato antigo ou arquivo apagado)." }, 404);
    }
    return json({ ok: false, message: "Ação inválida." }, 400);
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
