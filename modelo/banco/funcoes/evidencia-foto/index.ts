import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS, json, svcClient, autorizar, cfg, URL_ } from "./auth.ts";
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
const PUBLISHABLE = await cfg("SB_PUBLISHABLE_KEY");

// Fotos opcionais de perda de estoque, recebimento de compra e ocorrência de pedido (18/10/2026).
// Mesmo caminho das fotos do ponto: Edge Function -> planilha principal (Apps Script) -> Drive principal e Drive da contingência,
// na mesma pasta privada "Fotos do ponto" (o nome do arquivo começa com perda-, recebimento- ou ocorrencia-).
//   enviar  (quem fez o lançamento, logo depois; o banco confere em api_evidencia_pode)
//   ver     (Admin; Admin/Operador nas ocorrências): devolve uma foto
//   limpar  (rotina diária do banco): apaga nos dois Drives e remove as linhas com mais de 45 dias

const PRAZOS_PADRAO_: Record<string, number> = { ponto: 90, evidencias: 90, atestados: 90, notas: 395 };
// Quanto tempo guardar (tela Backup e espaço → Quanto tempo guardar); se não houver valor salvo, usa o padrão.
async function prazo(chave: string): Promise<number> {
  try { const { data } = await svcClient().from("sistema").select("valor").eq("chave", "DRIVE_PRAZOS").maybeSingle(); const n = Number((data?.valor as any)?.[chave]); if (n >= 1 && n <= 3650) return Math.round(n); } catch { /* usa o padrão */ }
  return PRAZOS_PADRAO_[chave] ?? 90;
}
// A foto vai para o Drive indicado; se ele não responder, tenta o outro (nunca perde a foto por um Drive fora do ar).
async function guardarFoto(corpo: Record<string, unknown>, primeiro: "principal" | "contingencia") {
  const j = await planilha({ ...corpo, destino: primeiro });
  if (j?.ok) return j;
  const k = await planilha({ ...corpo, destino: primeiro === "principal" ? "contingencia" : "principal" });
  return k?.ok ? k : j;
}
const TODOS = ["Admin", "Operador", "Garçom", "Cozinha", "Entregador"];
const TIPOS = ["perda", "recebimento", "ocorrencia"];
async function planilhaApps(corpo: Record<string, unknown>) {
  const r = await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
    body: JSON.stringify({ chave: CHAVE_SERVIDOR, ...corpo }) });
  return await r.json();
}
const desatualizada = (m: string) => /Ação desconhecida/i.test(m || "")
  ? "A planilha principal ainda não tem a função de fotos: cole o código novo do Apps Script (das duas planilhas) e publique uma nova versão." : m;
const partesDe = (path: string) => Object.fromEntries(String(path || "").split("|").map((x) => x.split(":")).filter((x) => x.length === 2));

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const b = await req.json();
    if (b.acao === "limpar") {
      const a = await autorizar(req, null);
      if (!a.ok) return json({ ok: false, message: a.message }, a.status);
      const corte = new Date(Date.now() - (await prazo("evidencias")) * 86400000).toISOString();
      const svc = svcClient();
      const { data: regs, error } = await svc.from("evidencias_foto").select("id,path").lt("criado_em", corte).limit(150);
      if (error) return json({ ok: false, message: error.message }, 500);
      let apagados = 0, falhas = 0;
      for (const r of regs || []) {
        const p = partesDe(r.path as string);
        try {
          const j = p.drive || p.cont ? await planilha({ action: "sbExcluirPonto", ids: p.drive ? [p.drive] : [], idsReserva: p.cont ? [p.cont] : [] }) : { ok: true };
          if (!j?.ok) { falhas++; continue; }
          await svc.from("evidencias_foto").delete().eq("id", r.id);
          apagados++;
        } catch { falhas++; }
      }
      // registro das etiquetas de validade impressas: guarda 45 dias
      try { await svc.from("etiqueta_impressoes").delete().lt("criado_em", new Date(Date.now() - 45 * 86400000).toISOString()); } catch { /* ok */ }
      return json({ ok: true, apagados, falhas, restantes: (regs || []).length >= 150 });
    }

    if (b.acao === "enviar") {
      const a = await autorizar(req, TODOS);
      if (!a.ok) return json({ ok: false, message: a.message }, a.status);
      if (a.servico) return json({ ok: false, message: "Só quem fez o lançamento envia a foto." }, 403);
      const tipo = String(b.tipo || "");
      if (!TIPOS.includes(tipo)) return json({ ok: false, message: "Tipo inválido." }, 400);
      const dados = String(b.base64Data || "");
      if (!dados || dados.length > 2.1 * 1024 * 1024) return json({ ok: false, message: "Foto ausente ou maior que 1,5 MB." }, 400);
      const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      const usr = createClient(URL_, PUBLISHABLE, { global: { headers: { Authorization: "Bearer " + token } } });
      const ped = { tipo, refId: String(b.refId || "") };
      const { data: pode } = await usr.rpc("api_evidencia_pode", { p: ped });
      if (!pode?.ok) return json({ ok: false, message: pode?.message || "Não foi possível salvar a foto." }, 403);
      const j = await guardarFoto({ action: "sbGuardarPonto", base64Data: dados, nomeBase: tipo + "-" + ped.refId.slice(0, 8) }, "contingencia");
      if (!j?.ok) return json({ ok: false, message: desatualizada(j?.message) || "Falha ao salvar a foto." }, 502);
      const path = [j.id ? "drive:" + j.id : "", j.idReserva ? "cont:" + j.idReserva : ""].filter(Boolean).join("|");
      const { data: an } = await usr.rpc("api_evidencia_anexar", { p: { ...ped, path } });
      if (!an?.ok) {
        try { await planilha({ action: "sbExcluirPonto", ids: j.id ? [j.id] : [], idsReserva: j.idReserva ? [j.idReserva] : [] }); } catch { /* ok */ }
        return json({ ok: false, message: an?.message || "Não foi possível anexar a foto." }, 400);
      }
      return json({ ok: true, aviso: "" });
    }

    if (b.acao === "ver") {
      const tipo = String(b.tipo || "");
      if (!TIPOS.includes(tipo)) return json({ ok: false, message: "Tipo inválido." }, 400);
      const a = await autorizar(req, tipo === "ocorrencia" ? ["Admin", "Operador"] : ["Admin"]);
      if (!a.ok) return json({ ok: false, message: a.message }, a.status);
      const { data: fs } = await svcClient().from("evidencias_foto").select("path").eq("tipo", tipo).eq("ref_id", b.refId).order("criado_em", { ascending: true });
      const path = String(((fs || [])[Number(b.indice) || 0] || {}).path || "");
      if (!path) return json({ ok: false, message: "Sem foto (ou já passou do prazo de " + await prazo("evidencias") + " dias e foi apagada)." }, 404);
      const partes = partesDe(path);
      let ultimo = "";
      for (const [onde, chave] of [["principal", "drive"], ["contingencia", "cont"]]) {
        if (!partes[chave]) continue;
        const j = await planilha({ action: "sbLerPonto", id: partes[chave], onde });
        if (j?.ok && j.base64) return json({ ok: true, tipo: j.tipo, base64: j.base64, de: onde, total: (fs || []).length });
        ultimo = desatualizada(j?.message) || ultimo;
      }
      return json({ ok: false, message: ultimo || "Não consegui abrir a foto (arquivo apagado)." }, 404);
    }
    return json({ ok: false, message: "Ação inválida." }, 400);
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
