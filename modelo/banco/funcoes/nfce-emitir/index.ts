// =====================================================================
// nfce-emitir · FASE 5 (Nota fiscal do consumidor, NFC-e, pela Focus NFe). Roda 1x por minuto (pg_cron → chamar_edge)
// e também na hora, quando alguém pede "Reemitir"/"Emitir agora". SÓ faz algo se a integração "nfce" estiver LIGADA.
// verify_jwt = false: aceita só a chave de serviço (a mesma do pg_cron). Token da Focus vem do banco (integracoes_segredos).
// Regras de segurança:
//  • a referência (ref) da Focus é o id da venda → a Focus recusa nota duplicada;
//  • rede/timeout/erro 5xx NÃO reenvia às cegas: a nota vira "dúvida" e, na próxima rodada, CONSULTA a Focus antes de qualquer reenvio;
//  • item sem perfil fiscal ou dados da empresa incompletos → a nota fica parada ("pendência"), nunca vai errada;
//  • cancelamento (só dentro de 30 min) consulta antes de cancelar; fora do prazo vira pendência para o contador;
//  • nota de TREINO (ambiente "simulado") nunca fala com a Focus: o servidor inventa uma autorização.
// ⚠️ Escrito a partir da documentação pública da Focus NFe: ainda NÃO testado com a Focus de verdade.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const svc = createClient(URL_, SVC, { auth: { persistSession: false } });
const BASE_HOM = Deno.env.get("FOCUS_BASE_HOMOLOGACAO") || "https://homologacao.focusnfe.com.br";
const BASE_PRD = Deno.env.get("FOCUS_BASE_PRODUCAO") || "https://api.focusnfe.com.br";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const seg = async (nome: string) => { try { const { data } = await svc.rpc("api_segredo", { p_nome: nome }); return (data as string) || ""; } catch { return ""; } };
const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
  const { data, error } = await svc.rpc(fn, args);
  if (error) throw new Error(fn + ": " + error.message);
  return data;
};

class HttpErro extends Error { constructor(public status: number, public corpo: any) { super("http_" + status); } }

async function focus(metodo: string, base: string, caminho: string, token: string, corpo?: unknown) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 25000);
  try {
    const h: Record<string, string> = { Authorization: "Basic " + btoa(token + ":") };
    let body: string | undefined;
    if (corpo !== undefined) { body = JSON.stringify(corpo); h["Content-Type"] = "application/json"; }
    const r = await fetch(base + caminho, { method: metodo, headers: h, body, signal: ctl.signal });
    const txt = await r.text(); let j: any = null; try { j = txt ? JSON.parse(txt) : null; } catch { j = { mensagem: txt.slice(0, 300) }; }
    if (!r.ok) throw new HttpErro(r.status, j);
    return j;
  } catch (e) {
    if (e instanceof HttpErro) throw e;
    throw new HttpErro(0, { mensagem: "rede_ou_timeout" });
  } finally { clearTimeout(t); }
}

const agoraSP = () => new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 19) + "-03:00";   // horário de Brasília (sem horário de verão)
const abs = (base: string, c?: string) => !c ? "" : /^https?:/i.test(c) ? c : base + c;

// transforma a resposta da Focus no que o banco entende
function interpretar(base: string, r: any): any {
  const st = String(r?.status || "").toLowerCase();
  const msg = [r?.mensagem_sefaz, r?.mensagem].filter(Boolean).join(" · ");
  const comum = { statusSefaz: String(r?.status_sefaz || ""), mensagem: msg };
  if (st === "autorizado") {
    return { resultado: "autorizada", ...comum, numero: r?.numero, serie: r?.serie, chave: r?.chave_nfe, protocolo: r?.protocolo,
      urlDanfe: abs(base, r?.caminho_danfe), urlXml: abs(base, r?.caminho_xml_nota_fiscal), urlConsulta: r?.url_consulta_nf || r?.qrcode_url || "" };
  }
  if (st === "erro_autorizacao" || st === "denegado") return { resultado: "rejeitada", ...comum };
  if (/conting/i.test(msg) && st !== "autorizado") return { resultado: "contingencia", ...comum, numero: r?.numero, serie: r?.serie, chave: r?.chave_nfe };
  return { resultado: "duvida", ...comum, mensagem: msg || ("situação: " + (st || "desconhecida")) };   // processando_autorizacao etc.
}

const log = async (nivel: string, texto: string) => { try { await rpc("nfce_log", { p_nivel: nivel, p_msg: texto }); } catch { /* sem log não derruba */ } };

async function tratar(nota: any) {
  const id = nota.id as number;
  const dar = (res: any) => rpc("nfce_resultado", { p_id: id, p_res: res });

  // ---- treino (sem Focus) ----
  if (nota.ambiente === "simulado") {
    const m: any = await rpc("nfce_montar", { p_id: id });
    if (!m?.ok) return dar({ resultado: m?.dispensar ? "dispensada" : "pendencia", motivo: m?.motivo || "Não foi possível montar a nota." });
    const n = 900000 + id;
    return dar({ resultado: "autorizada", numero: String(n), serie: "1", chave: ("35" + String(Date.now()) + String(id).padStart(30, "0")).slice(0, 44),
      protocolo: "TREINO", statusSefaz: "100", mensagem: "NOTA DE TREINO — sem valor fiscal", urlDanfe: "", urlXml: "", urlConsulta: "" });
  }

  const cred: any = await rpc("nfce_credenciais", { p_ambiente: nota.ambiente });
  if (!cred?.ligado) return;                                                   // desligada no meio do caminho: deixa como está
  if (!cred.token) return dar({ resultado: "pendencia", motivo: "Falta o token da Focus (" + (nota.ambiente === "producao" ? "produção" : "teste") + ") em Chaves." });
  const base = nota.ambiente === "producao" ? BASE_PRD : BASE_HOM;
  const ref = encodeURIComponent(nota.ref);

  // ---- cancelamento (só dentro dos 30 min; consulta antes para não cancelar duas vezes) ----
  if (nota.estado === "cancelando") {
    try {
      try { const g = await focus("GET", base, "/v2/nfce/" + ref, cred.token); if (String(g?.status || "").toLowerCase() === "cancelado") return await dar({ resultado: "cancelada", mensagem: g?.mensagem_sefaz || "cancelada" }); }
      catch (e) { if (!(e instanceof HttpErro) || e.status !== 404) throw e; }
      const r = await focus("DELETE", base, "/v2/nfce/" + ref, cred.token, { justificativa: nota.cancelamento_motivo || "Venda cancelada no sistema" });
      const st = String(r?.status || "").toLowerCase();
      if (st === "cancelado") return await dar({ resultado: "cancelada", mensagem: r?.mensagem_sefaz || "cancelada" });
      if (st === "erro_cancelamento") return await dar({ resultado: "cancelamento_recusado", mensagem: r?.mensagem_sefaz || r?.mensagem || "recusado" });
      return await dar({ resultado: "duvida", mensagem: "cancelamento: situação " + (st || "desconhecida") });
    } catch (e) {
      if (e instanceof HttpErro && e.status >= 400 && e.status < 500 && e.status !== 401 && e.status !== 403 && e.status !== 404) {
        const c = e.corpo || {}; return await dar({ resultado: "cancelamento_recusado", mensagem: [c.codigo, c.mensagem].filter(Boolean).join(": ") || ("erro " + e.status) });
      }
      return await dar({ resultado: "duvida", mensagem: e instanceof HttpErro ? ("erro " + e.status + " " + JSON.stringify(e.corpo || {}).slice(0, 150)) : String((e as Error).message) });
    }
  }

  try {
    // dúvida/contingência: consulta ANTES de qualquer reenvio
    if (nota.estado === "duvida" || nota.estado === "contingencia") {
      try { return await dar(interpretar(base, await focus("GET", base, "/v2/nfce/" + ref, cred.token))); }
      catch (e) {
        if (!(e instanceof HttpErro) || e.status !== 404) throw e;           // 404 = a Focus nunca recebeu: aí sim pode enviar
      }
    }
    const m: any = await rpc("nfce_montar", { p_id: id });
    if (!m?.ok) return dar({ resultado: m?.dispensar ? "dispensada" : "pendencia", motivo: m?.motivo || "Não foi possível montar a nota." });
    const corpo = { ...m.payload, data_emissao: agoraSP() };
    const r = await focus("POST", base, "/v2/nfce?ref=" + ref, cred.token, corpo);
    return await dar(interpretar(base, r));
  } catch (e) {
    if (e instanceof HttpErro) {
      const c = e.corpo || {}; const msg = [c.codigo, c.mensagem].filter(Boolean).join(": ");
      if (e.status === 401 || e.status === 403) return dar({ resultado: "pendencia", motivo: "A Focus recusou o token (" + (nota.ambiente === "producao" ? "produção" : "teste") + "). Confira em Chaves." });
      // a Focus diz que a nota já existe/autorizada: consulta para pegar os dados (nunca gera outra)
      if (/autorizad|duplic|ja_existe|já existe/i.test(String(c.codigo || "") + " " + String(c.mensagem || ""))) {
        try { return await dar(interpretar(base, await focus("GET", base, "/v2/nfce/" + ref, cred.token))); } catch { return dar({ resultado: "duvida", mensagem: msg }); }
      }
      if (e.status >= 400 && e.status < 500) return dar({ resultado: "rejeitada", mensagem: msg || ("erro " + e.status), statusSefaz: String(c.status_sefaz || e.status) });
      return dar({ resultado: "duvida", mensagem: msg || ("erro " + e.status) });                 // 5xx / rede
    }
    throw e;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const chaveVault = await seg("service_key");
  if (!token || (token !== SVC && token !== chaveVault)) return json({ ok: false, message: "Só execução interna." }, 403);
  try {
    const notas: any[] = (await rpc("nfce_pegar_pendentes", { p_limite: 5 })) || [];
    let feitas = 0;
    for (const n of notas) {
      try { await tratar(n); feitas++; }
      catch (e) { try { await rpc("nfce_resultado", { p_id: n.id, p_res: { resultado: "duvida", mensagem: "falha interna: " + String((e as Error).message).slice(0, 200) } }); } catch { /* */ } }
    }
    // inutilização de numeração (pedida pelo Administrador)
    const inu: any[] = (await rpc("nfce_inutilizacoes_pendentes")) || [];
    for (const i of inu) {
      const dar = (estado: string, msg: string) => rpc("nfce_inutilizacao_resultado", { p_id: i.id, p_estado: estado, p_msg: msg });
      try {
        const cred: any = await rpc("nfce_credenciais", { p_ambiente: i.ambiente });
        if (!cred?.ligado || !cred?.token) { await dar("duvida", "sem token da Focus"); continue; }
        const base = i.ambiente === "producao" ? BASE_PRD : BASE_HOM;
        const r = await focus("POST", base, "/v2/nfce/inutilizacao", cred.token, { cnpj: cred.cnpj, serie: i.serie, numero_inicial: i.numero_ini, numero_final: i.numero_fim, justificativa: i.justificativa });
        const st = String(r?.status || "").toLowerCase();
        await dar(st === "autorizado" ? "feita" : st === "erro_autorizacao" ? "recusada" : "duvida", r?.mensagem_sefaz || r?.mensagem || st);
      } catch (e) {
        if (e instanceof HttpErro && e.status >= 400 && e.status < 500) await dar("recusada", [e.corpo?.codigo, e.corpo?.mensagem].filter(Boolean).join(": ") || ("erro " + e.status));
        else await dar("duvida", e instanceof HttpErro ? "rede/erro do servidor" : String((e as Error).message));
      }
    }
    return json({ ok: true, notas: notas.length, feitas, inutilizacoes: inu.length });
  } catch (e) {
    await log("erro", "falha geral: " + String((e as Error).message).slice(0, 200));
    return json({ ok: false, message: String((e as Error).message) }, 500);
  }
});
