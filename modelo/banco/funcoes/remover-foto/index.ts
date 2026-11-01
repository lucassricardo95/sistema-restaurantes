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

// Remove a foto de um produto ou combo: limpa o vínculo no banco primeiro; só depois manda o arquivo
// do Drive para a lixeira (se a planilha falhar, o vínculo já saiu e o arquivo vira órfão — nunca o contrário).
async function planilhaApps(corpo: Record<string, unknown>) {
  const r = await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
    body: JSON.stringify({ chave: CHAVE_SERVIDOR, ...corpo }) });
  return await r.json();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin", "Operador"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const svc = svcClient();
    const { produtoId, comboId } = await req.json();
    if (!produtoId && !comboId) return json({ ok: false, message: "Informe produto ou combo." }, 400);
    const tabela = produtoId ? "produtos" : "combos", alvo = produtoId || comboId;

    const { data: antes, error: e0 } = await svc.from(tabela).select("foto_id_principal,foto_id_contingencia").eq("id", alvo).single();
    if (e0 || !antes) return json({ ok: false, message: "Cadastro não encontrado." }, 404);
    if (!antes.foto_id_principal && !antes.foto_id_contingencia) return json({ ok: true, message: "Não havia foto." });

    const { error } = await svc.from(tabela).update({
      foto_id_principal: null, foto_id_contingencia: null, foto_url_principal: null, foto_url_contingencia: null }).eq("id", alvo);
    if (error) throw new Error(error.message);

    let aviso = "";
    if (antes.foto_id_principal) {
      try { const j = await planilha({ action: "excluirFotoSb", ids: [antes.foto_id_principal] }); if (!j?.ok) aviso = "A foto saiu do cadastro, mas o arquivo no Drive não foi para a lixeira."; }
      catch { aviso = "A foto saiu do cadastro, mas o arquivo no Drive não foi para a lixeira."; }
    }
    // a cópia da contingência é limpa como órfã na próxima sincronização da contingência

    const { data: conf } = await svc.from("configuracoes_fotos").select("historico_fotos_ativo").eq("id", true).single();
    if (conf?.historico_fotos_ativo !== false) await svc.from("fotos_historico").insert({
      produto_id: produtoId || null, combo_id: comboId || null, acao: "remover",
      foto_id_antigo: antes.foto_id_principal || antes.foto_id_contingencia, usuario_id: a.usuario?.id ?? null });

    return json({ ok: true, message: aviso || "Foto removida." });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
