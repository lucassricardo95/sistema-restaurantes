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

// A foto é salva pelo Apps Script (dono do Drive, que já valida tipo e tamanho).
// Contas de serviço do Google não têm espaço próprio em pastas do "Meu Drive", por isso não são usadas aqui.
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
    const { produtoId, comboId, nomeBase, base64Data, mimeType, destino, marca } = await req.json();
    if (!base64Data) return json({ ok: false, message: "Imagem ausente." }, 400);

    // Logos da Aparência (Administrador → Sistema → Aparência): vão para o mesmo Drive das fotos, mas não ficam presas a produto ou combo.
    if (marca) {
      if (!["cardapio", "impressao", "icone"].includes(marca)) return json({ ok: false, message: "Tipo de logo inválido." }, 400);
      const nv = a.usuario?.nivel;
      if (!a.servico && nv !== "Admin" && nv !== "Desenvolvedor") return json({ ok: false, message: "Só o Admin troca as logos." }, 403);
      const jm = await planilha({ action: "uploadFotoSb", nomeBase: "logo-" + marca, base64Data, mimeType, copiarContingencia: true });
      if (!jm?.ok) return json({ ok: false, message: jm?.message || "Falha ao salvar a logo no Drive." }, 502);
      return json({ ok: true, id_principal: jm.fotoId, id_contingencia: jm.fotoReservaId || null });
    }
    if (!produtoId && !comboId) return json({ ok: false, message: "Informe produto ou combo." }, 400);
    if (!["principal", "contingencia", "ambos"].includes(destino)) return json({ ok: false, message: "Destino inválido." }, 400);

    const tabela = produtoId ? "produtos" : "combos", alvo = produtoId || comboId;
    const { data: antes } = await svc.from(tabela).select("foto_id_principal,foto_id_contingencia").eq("id", alvo).single();

    // "contingencia" e "ambos" fazem o mesmo: a foto sempre nasce no Drive principal e depois é copiada para a reserva
    const j = await planilha({ action: "uploadFotoSb", nomeBase: nomeBase || alvo, base64Data, mimeType, copiarContingencia: destino !== "principal" });
    if (!j?.ok) return json({ ok: false, message: j?.message || "Falha ao salvar a foto." }, 502);

    const { error } = await svc.from(tabela).update({ foto_id_principal: j.fotoId, foto_id_contingencia: j.fotoReservaId || null }).eq("id", alvo);
    if (error) throw new Error(error.message);

    // só agora a foto antiga vai para a lixeira (se o banco falhasse acima, ela continuaria intacta)
    if (antes?.foto_id_principal) await planilha({ action: "excluirFotoSb", ids: [antes.foto_id_principal] }).catch(() => {});

    const { data: conf } = await svc.from("configuracoes_fotos").select("historico_fotos_ativo").eq("id", true).single();
    if (conf?.historico_fotos_ativo !== false) await svc.from("fotos_historico").insert({
      produto_id: produtoId || null, combo_id: comboId || null,
      acao: antes?.foto_id_principal ? "substituir" : "upload",
      drive_destino: destino, foto_id_antigo: antes?.foto_id_principal || null,
      foto_id_novo: j.fotoId, usuario_id: a.usuario?.id ?? null });
    return json({ ok: true, id_principal: j.fotoId, id_contingencia: j.fotoReservaId || null });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
