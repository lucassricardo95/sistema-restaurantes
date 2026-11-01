// =====================================================================
// ifood-sync · FASE 1 (iFood). Roda 1x por minuto (pg_cron → chamar_edge), SÓ quando a integração iFood está LIGADA.
// Faz 1 consulta por chamada; o agendamento chama a cada 30 s: pede os eventos ao iFood, guarda (sem duplicar), confirma o recebimento,
// busca o pedido completo e cria a venda; depois envia ao iFood as ações pendentes (confirmar, preparo, pronto, despachar, cancelar).
// verify_jwt = false: aceita só a chave de serviço (a mesma do pg_cron). Segredos do iFood vêm do banco (integracoes_segredos).
// Regras: um único leitor por vez (trava no banco); ações que mudam algo NÃO são repetidas sozinhas em caso de dúvida;
// o estado do pedido só avança por EVENTO oficial do iFood.
// ⚠️ Escrito a partir de documentação de terceiros e da oficial (parcial): ainda NÃO testado com o iFood de verdade.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import { executarCatalogoGestao } from "./catalogo.ts";
import { processarFinanceiro } from "./financeiro.ts";
import { executarShipping } from "./shipping.ts";
import { executarAnalytics } from "./analytics.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const svc = createClient(URL_, SVC, { auth: { persistSession: false } });
const BASE = Deno.env.get("IFOOD_BASE_URL") || "https://merchant-api.ifood.com.br";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));
const seg = async (nome: string) => { try { const { data } = await svc.rpc("api_segredo", { p_nome: nome }); return (data as string) || ""; } catch { return ""; } };
const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
  const { data, error } = await svc.rpc(fn, args);
  if (error) throw new Error(fn + ": " + error.message);
  return data;
};

class HttpErro extends Error { esperaMs = 0; constructor(public status: number, public corpo: string) { super("http_" + status); } }
const textoErro = (er: unknown) => er instanceof HttpErro
  ? (er.status === 401 ? "401 (credenciais recusadas)" : er.status === 403 ? "403 (módulo não liberado para este app)" : er.status === 429 ? "429 (limite de chamadas)" : `${er.status} ${er.corpo}`)
  : String(er);

// v1.15 (homologação) — estado de cada módulo nesta rodada (D-01): vai para o banco uma vez no fim
const MODULOS: Record<string, { ok: boolean; status?: number; msg?: string }> = {};
function moduloDe(caminho: string) {
  const m = caminho.match(/^\/(authentication|merchant|order|events|catalog|review|financial|shipping|logistics|analytics)\b/);
  return m ? m[1] : "outro";
}
function marcarModulo(caminho: string, ok: boolean, status?: number, msg?: string) {
  const mod = moduloDe(caminho);
  if (ok) { if (!MODULOS[mod] || MODULOS[mod].ok) MODULOS[mod] = { ok: true }; }   // um erro na rodada prevalece sobre o sucesso
  else MODULOS[mod] = { ok: false, status, msg: String(msg || "").slice(0, 250) };
}

// 429 (limite de chamadas): espera e tenta de novo, no máximo 3 vezes (1 s, 2 s, 4 s ou o Retry-After do iFood, até 10 s).
async function http(metodo: string, caminho: string, token: string | null, corpo?: unknown, extra: Record<string, string> = {}) {
  for (let tentativa = 0; ; tentativa++) {
    try { const r = await http1(metodo, caminho, token, corpo, extra); marcarModulo(caminho, true); return r; }
    catch (e) {
      const st = e instanceof HttpErro ? e.status : 0;
      if (st === 429 && tentativa < 3) { await dormir(Math.min(10000, ((e as HttpErro).esperaMs || 1000 * 2 ** tentativa))); continue; }
      const normal404 = st === 404 && /\/tracking(\?|$)/.test(caminho);   // doc: 404 no rastreio = entregador ainda não disponível (normal)
      marcarModulo(caminho, normal404, st, e instanceof HttpErro ? e.corpo : String(e));
      throw e;
    }
  }
}
async function http1(metodo: string, caminho: string, token: string | null, corpo?: unknown, extra: Record<string, string> = {}) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 15000);
  try {
    const h: Record<string, string> = { ...extra };
    if (token) h["Authorization"] = "Bearer " + token;
    let body: string | undefined;
    if (corpo !== undefined) {
      if (corpo instanceof URLSearchParams) { body = corpo.toString(); h["Content-Type"] = "application/x-www-form-urlencoded"; }
      else { body = JSON.stringify(corpo); h["Content-Type"] = "application/json"; }
    }
    const r = await fetch(BASE + caminho, { method: metodo, headers: h, body, signal: ctl.signal });
    const txt = await r.text();
    if (!r.ok) { const er = new HttpErro(r.status, txt.slice(0, 300)); const ra = Number(r.headers.get("retry-after")); if (ra > 0) er.esperaMs = ra * 1000; throw er; }
    if (!txt) return null;
    try { return JSON.parse(txt); } catch { return txt; }
  } catch (e) {
    if (e instanceof HttpErro) throw e;
    throw new HttpErro(0, "rede_ou_timeout");
  } finally { clearTimeout(t); }
}

// ---------- acesso (token OAuth guardado no banco; renova antes de vencer) ----------
async function pegarToken(cred: any, forcar = false): Promise<string> {
  if (!forcar) { const t: any = await rpc("ifood_token_ler"); if (t && t.token) return t.token; }
  if (!cred.clientId || !cred.clientSecret) throw new HttpErro(401, "faltam Client ID / Client Secret");
  const r: any = await http("POST", "/authentication/v1.0/oauth/token", null,
    new URLSearchParams({ grantType: "client_credentials", clientId: cred.clientId, clientSecret: cred.clientSecret }));
  const token = r?.accessToken || r?.access_token;
  if (!token) throw new HttpErro(401, "resposta sem token");
  await rpc("ifood_token_gravar", { p_token: token, p_seg: Math.max(60, Number(r?.expiresIn || r?.expires_in || 3600) - 30) });   // doc: renovar só ao expirar; 30 s é só margem de relógio (e o 401 renova sozinho)
  return token;
}

// chama o iFood; se o token estiver vencido (401) renova uma vez e repete
// Modo homologação (ajuste "modoHomologacao", desligado): o iFood pede o cabeçalho x-request-homologation nas chamadas feitas durante os testes de homologação.
async function chamar(cred: any, metodo: string, caminho: string, corpo?: unknown, extra0: Record<string, string> = {}) {
  const extra = cred?.config?.modoHomologacao ? { ...extra0, "x-request-homologation": "true" } : extra0;
  let token = await pegarToken(cred);
  try { return await http(metodo, caminho, token, corpo, extra); }
  catch (e) {
    if (e instanceof HttpErro && e.status === 401) { token = await pegarToken(cred, true); return await http(metodo, caminho, token, corpo, extra); }
    throw e;
  }
}

// ---------- eventos ----------
const CURTO: Record<string, string> = { PLACED: "PLC", CONFIRMED: "CFM", READY_TO_PICKUP: "RTP", DISPATCHED: "DSP", CONCLUDED: "CON", CANCELLED: "CAN",
  CANCELLATION_REQUESTED: "CR", CANCELLATION_REQUEST_FAILED: "CARF", CONSUMER_CANCELLATION_REQUESTED: "CCR", CONSUMER_CANCELLATION_ACCEPTED: "CCA", CONSUMER_CANCELLATION_DENIED: "CCD",
  ASSIGN_DRIVER: "ADR", GOING_TO_ORIGIN: "GTO", ARRIVED_AT_ORIGIN: "AAO", COLLECTED: "CLT", ARRIVED_AT_DESTINATION: "AAD", DELIVERY_DROP_CODE_REQUESTED: "DDCR" };
const curto = (c: string) => CURTO[String(c || "").toUpperCase()] || String(c || "").toUpperCase();

async function tratarEvento(cred: any, e: any): Promise<{ final: boolean; erro?: string }> {
  const cod = curto(e.codigo); const pedido = e.pedido as string;
  if (!pedido) return { final: true, erro: "evento sem pedido" };
  // O iFood considera uso indevido consultar o mesmo pedido mais de 10 vezes: eventos que consultam o pedido só tentam de novo com espera crescente
  // (cada rodada soma 1 em "tentativas"; com rodadas de 30 s isto dá consultas em 0, 0,5, 1, 2, 4, 8 e 12 min).
  if ((cod === "PLC" || cod.includes("PATCH") || cod.includes("MODIF")) && (e.tentativas || 0) > 0 && ![1, 2, 4, 8, 16, 24].includes(e.tentativas || 0)) {
    const idadeEsp = Date.now() - new Date(e.bruto?.createdAt || Date.now()).getTime();
    return idadeEsp < 10 * 60000 || cod !== "PLC" ? { final: false, erro: "aguardando a próxima tentativa" } : { final: true, erro: "pedido não encontrado após 10 min" };
  }
  // Entregador do iFood (Shipping): eventos REQUEST_DRIVER_* / DELIVERY_* dos pedidos que a loja pediu entregador (ou criou como Sob Demanda)
  if (/^(REQUEST_DRIVER_|DELIVERY_|CONCLUDED$|CANCELLED$|CANCELLATION_REQUEST)/.test(String(e.codigo || "").toUpperCase())) {
    const sh: any = await rpc("ifood_ship_evento", { p_codigo: String(e.codigo), p_pedido: pedido, p_meta: e.bruto?.metadata || {} });
    if (sh?.achou && sh?.avisou) return { final: true };
  }
  if (cod === "PLC") {
    let ordem: any;
    try { ordem = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(pedido)}`); }
    catch (er) {
      if (er instanceof HttpErro && er.status === 404) {
        const idade = Date.now() - new Date(e.bruto?.createdAt || Date.now()).getTime();
        return idade < 10 * 60000 ? { final: false, erro: "pedido ainda não disponível (404); vamos tentar de novo" } : { final: true, erro: "pedido não encontrado após 10 min" };
      }
      throw er;
    }
    const r: any = await rpc("ifood_criar_pedido", { p_order: ordem, p_simulado: false });
    if (r && r.ok === false) return { final: true, erro: r.message || "falha ao criar" };
    if (r && !r.duplicado && cred.config?.confirmacaoAutomatica !== false) await rpc("ifood_enfileirar", { p_pedido: pedido, p_acao: "confirmar" });
    return { final: true };
  }
  if (cod.includes("PATCH") || cod.includes("MODIF")) {
    const ordem: any = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(pedido)}`);
    await rpc("ifood_atualizar_pedido", { p_order: ordem });
    await avisar(pedido, "pedido_alterado", "✏️ Cliente alterou o pedido", resumoAlteracao(e.bruto?.metadata), e.bruto?.metadata);
    return { final: true };
  }
  const full = String(e.codigo || "").toUpperCase(); const md = e.bruto?.metadata || {};
  if (full === "CANCELLATION_REQUEST_FAILED" || cod === "CARF") {
    await avisar(pedido, "cancelamento_recusado", "❌ O iFood recusou o cancelamento", textoCarf(md), md);
    return { final: true };
  }
  if (full === "DELIVERY_ADDRESS_CHANGE_REQUESTED" || cod === "DAR") {
    try { const ordem: any = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(pedido)}`); await rpc("ifood_endereco_atualizar", { p_order: ordem }); } catch { /* o aviso abaixo basta */ }
    const a = md.address || {};
    await avisar(pedido, "endereco", "📍 Cliente mudou o endereço de entrega", [a.streetName, a.streetNumber, a.neighborhood, a.city, a.complement].filter(Boolean).join(", ") + ". Avise o entregador.", md);
    return { final: true };
  }
  if (full === "DELIVERY_RETURN_CODE_REQUESTED" || cod === "DRCR") {
    await avisar(pedido, "devolucao_codigo", "🔑 Código de devolução do pedido", "Passe este código ao entregador na devolução: " + (md.HANDSHAKE_CODE || "(sem código)"), md);
    return { final: true };
  }
  if (full === "DELIVERY_RETURNING_TO_ORIGIN" || cod === "DRGO") { await avisar(pedido, "devolvendo", "↩️ Pedido voltando para a loja", "O entregador está trazendo o pedido de volta.", md); return { final: true }; }
  if (full === "DELIVERY_RETURNED_TO_ORIGIN" || cod === "DRDO") { await avisar(pedido, "devolvido", "📦 Pedido voltou para a loja", "Confira o pedido devolvido.", md); return { final: true }; }
  if (full === "RECOMMENDED_PREPARATION_START" || cod === "RPS") {
    const h = horaBr(md.expectedPreparationStartTimestamp);
    await avisar(pedido, "preparo", "⏱ Hora ideal para começar o preparo", h ? "Comece o preparo às " + h + " (Preparo Inteligente do iFood)." : "O iFood recomenda começar agora.", md);
    return { final: true };
  }
  if (full === "PICKUP_AREA_ASSIGNED") {
    const vaga = md.pickupAreaCode || md.pickupArea || md.areaCode || Object.values(md).find((v) => typeof v === "string" && v.length < 12);
    await avisar(pedido, "vaga", "🅿️ Vaga de retirada definida", "O cliente vai retirar na vaga/área: " + (vaga || "(veja o pedido)"), md);
    return { final: true };
  }
  if (["CFM", "RTP", "DSP", "CON", "CAN"].includes(cod)) {
    const motivo = cod === "CAN" ? motivoCancelamento(e.bruto?.metadata) : (e.bruto?.metadata?.cancelReason || e.bruto?.metadata?.cancellationReason || e.bruto?.metadata?.reason || null);
    const ap: any = await rpc("ifood_aplicar_evento", { p_codigo: cod, p_pedido: pedido, p_motivo: motivo });
    if (ap && ap.desconhecido) {
      // o evento chegou antes de a venda existir (o PLC ainda está tentando): não pode sumir, senão um cancelamento se perde
      const idade = Date.now() - new Date(e.bruto?.createdAt || Date.now()).getTime();
      return idade < 10 * 60000 ? { final: false, erro: "pedido ainda não existe no sistema; vamos tentar de novo" } : { final: true, erro: "pedido não existe no sistema após 10 min" };
    }
    return { final: true };
  }
  // negociação de cancelamento (handshake): cliente pede cancelar/reembolsar; a equipe responde no painel
  if (/^HS[DS]?$|HANDSHAKE/i.test(String(e.codigo || "")) || /^HS[DS]?$/.test(cod)) {
    const fim = /SETTLEMENT/i.test(String(e.codigo || "")) || cod === "HSS";
    const imgs: string[] = [];
    if (!fim) {
      const ev = e.bruto?.metadata?.evidences;
      for (const x of (Array.isArray(ev) ? ev : []).slice(0, 4)) { const u = typeof x === "string" ? x : x?.url; if (u) { const im = await baixarEvidencia(cred, String(u)); if (im) imgs.push(im); } }
    }
    await rpc(fim ? "ifood_negociacao_fim" : "ifood_negociacao_registrar", { p_evento: fim ? e.bruto : { ...e.bruto, _imagens: imgs }, p_pedido: pedido });
    return { final: true };
  }
  return { final: true };   // demais eventos: só ficam registrados
}

// ---------- avisos do iFood (aparecem no painel e no celular da equipe) ----------
async function avisar(pedido: string, tipo: string, titulo: string, msg: string, dados?: unknown) {
  try { await rpc("ifood_aviso_registrar", { p_pedido: pedido, p_tipo: tipo, p_titulo: titulo, p_msg: msg, p_dados: dados || {} }); } catch { /* o evento já foi guardado; o aviso é reforço */ }
}
function horaBr(iso: unknown): string {
  try { const d = new Date(String(iso)); if (isNaN(d.getTime())) return ""; return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" }); } catch { return ""; }
}
const MOTIVO_CARF: Record<string, string> = {
  ACCOUNT_BLOCKED: "a conta está bloqueada", ORDER_ALREADY_CANCELLED: "o pedido já estava cancelado", ORDER_ALREADY_CONCLUDED: "o pedido já foi concluído",
  CANCELLATION_DEADLINE_EXCEEDED: "o prazo para cancelar passou", INVALID_CANCEL_CODE: "o motivo do cancelamento não vale para este pedido",
};
function textoCarf(md: any): string {
  const r = String(md?.CANCELLATION_REQUEST_FAILED_REASON || md?.reason || "");
  const trad = MOTIVO_CARF[r.toUpperCase()];
  return "O iFood não aceitou o cancelamento" + (trad ? ": " + trad : r ? ": " + r : "") + ". O pedido continua valendo no iFood. Se for um problema passageiro, tente de novo; se persistir, fale com o suporte do iFood. (Também chega quando a confirmação do pedido falha.)";
}
function resumoAlteracao(md: any): string {
  const mudancas: string[] = [];
  for (const c of (Array.isArray(md?.changes) ? md.changes : [])) {
    const t = String(c?.changeType || c?.type || "").toUpperCase();
    mudancas.push(t === "DELETE_ITEMS" ? "item removido" : t === "ADD_ITEMS" ? "item adicionado" : t === "EDIT_ITEMS" ? "item alterado" : t === "ADD_OPTIONS" ? "complemento adicionado" : t === "DELETE_OPTIONS" ? "complemento removido" : t === "EDIT_OPTIONS" ? "complemento alterado" : t ? t : "alteração");
  }
  const de = md?.total?.subtotal?.from, para = md?.total?.subtotal?.to;
  const r = (n: number) => "R$ " + Number(n).toFixed(2).replace(".", ",");
  return (mudancas.length ? Array.from(new Set(mudancas)).join(", ") + ". " : "") + (de != null && para != null ? "Subtotal: " + r(de) + " → " + r(para) + ". " : "") + "O pedido e o estoque já foram atualizados no sistema: avise a cozinha e reimprima a comanda.";
}
const ORIGEM_CANCEL: Record<string, string> = { CONSUMER: "o cliente", CUSTOMER: "o cliente", MERCHANT: "a loja", RESTAURANT: "a loja", SCHEDULER: "o iFood (prazo esgotado)", IFOOD: "o iFood", CALL_CENTER: "a central do iFood", SYSTEM: "o sistema do iFood" };
const CODIGO_CANCEL: Record<string, string> = { "901": "o pedido não chegou à loja a tempo (901)", "902": "o pedido não foi confirmado em 8 minutos (902)" };
function motivoCancelamento(md: any): string | null {
  if (!md) return null;
  const r = String(md.CANCEL_REASON || md.cancelReason || md.cancellationReason || md.reason || "").trim();
  const o = String(md.CANCEL_ORIGIN || "").toUpperCase(); const c = String(md.CANCEL_CODE || "");
  const quem = o ? (ORIGEM_CANCEL[o] || o) : "";
  const partes = [quem ? "por " + quem : "", CODIGO_CANCEL[c] || (c ? "código " + c : ""), r].filter(Boolean);
  return partes.length ? partes.join(" · ").slice(0, 190) : null;
}

// ---------- motivos de cancelamento (doc oficial: GET .../cancellationReasons → {"reasons":[{"code","description"}]}; 204 = o iFood não permite cancelar por API) ----------
function listaMotivos(r: any): any[] {
  const l = Array.isArray(r) ? r : (Array.isArray(r?.reasons) ? r.reasons : []);
  return l.map((m: any) => ({ ...m, code: String(m.code ?? m.cancelCodeId ?? m.id ?? "") })).filter((m: any) => m.code);
}
// mensagens claras para os erros 400 do cancelamento (doc "Cancelamento de pedidos")
function textoCancelamento(er: unknown): string {
  const t = er instanceof HttpErro ? er.corpo : String(er);
  if (/OrderExceededCancellationDeadline/i.test(t)) return "O prazo para cancelar este pedido no iFood já passou.";
  if (/OrderHasACancellationInProgress|cancellation.*in progress/i.test(t)) return "Já existe um cancelamento em andamento para este pedido no iFood.";
  if (/already.*cancel|OrderAlreadyCancelled/i.test(t)) return "Este pedido já está cancelado no iFood.";
  if (/INVALID_CANCEL|invalid.*reason|reason.*invalid/i.test(t)) return "O iFood não aceitou o motivo escolhido. Escolha outro motivo da lista.";
  return t;
}

// ---------- ações que vão para o iFood ----------
const CAMINHO: Record<string, string> = { confirmar: "confirm", iniciar_preparo: "startPreparation", pronto: "readyToPickup", despachar: "dispatch", cancelar: "requestCancellation" };

// ---------- loja (aberta / fechada / pausada) e negociações ----------
// ⚠️ Endereços de "interruptions" e "disputes" vêm de fontes de terceiros: ainda não testado com o iFood de verdade.
async function executarLoja(cred: any, a: any) {
  const m = encodeURIComponent(cred.merchantId || "");
  try {
    if (a.acao === "loja_horario_enviar" || a.acao === "loja_horario_ler") {
      // ⚠️ Horário de funcionamento (Merchant API): formato conforme a documentação pública; ainda não testado com o iFood de verdade.
      if (a.acao === "loja_horario_enviar") {
        const turnos: any[] = [];
        const h = a.dados?.horario || {};
        // turno que passa da meia-noite (ex.: 18:00 às 02:00) vira dois: até 23:59 no dia e de 00:00 no dia seguinte (C-04)
        const DIAS = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];
        for (const dia of Object.keys(h)) for (const t of (Array.isArray(h[dia]) ? h[dia] : [])) {
          const [hi, mi] = String(t.inicio).split(":").map(Number); const [hf, mf] = String(t.fim).split(":").map(Number);
          const ini = hi * 60 + mi, fim = hf * 60 + mf;
          if (!(Number.isFinite(ini) && Number.isFinite(fim)) || ini === fim) continue;
          if (fim > ini) { turnos.push({ dayOfWeek: dia, start: `${String(t.inicio).padStart(5, "0")}:00`, duration: fim - ini }); continue; }
          turnos.push({ dayOfWeek: dia, start: `${String(t.inicio).padStart(5, "0")}:00`, duration: 24 * 60 - ini - 1 });
          const prox = DIAS[(DIAS.indexOf(String(dia).toUpperCase()) + 1) % 7] || dia;
          if (fim > 0) turnos.push({ dayOfWeek: prox, start: "00:00:00", duration: fim });
        }
        // documentação oficial (Merchant): o corpo leva storeId + shifts; dias que não vão na lista ficam FECHADOS (substitui tudo)
        if (!turnos.length) throw new HttpErro(400, "nenhum turno válido: o iFood fecharia a loja todos os dias");
        await chamar(cred, "PUT", `/merchant/v1.0/merchants/${m}/opening-hours`, { storeId: String(cred.merchantId || ""), shifts: turnos });
      }
      const lido: any = await chamar(cred, "GET", `/merchant/v1.0/merchants/${m}/opening-hours`);
      await rpc("ifood_horario_gravar", { p_turnos: Array.isArray(lido?.shifts) ? lido.shifts : (Array.isArray(lido) ? lido : []) });
    } else if (a.acao === "loja_pausar" || a.acao === "loja_fechar") {
      const min = a.acao === "loja_pausar" ? Math.max(5, Number(a.dados?.minutos || 30)) : 12 * 60;
      // documentação oficial: corpo = description (até 255), start e end (ISO 8601); mínimo 1 min, máximo 7 dias; 409 = já existe pausa nesse horário
      let r: any = null;
      try {
        r = await chamar(cred, "POST", `/merchant/v1.0/merchants/${m}/interruptions`, { description: (a.acao === "loja_fechar" ? "Fechado pelo sistema" : "Pausa pelo sistema"), start: new Date().toISOString(), end: new Date(Date.now() + Math.min(min, 7 * 24 * 60) * 60000).toISOString() });
      } catch (er) {
        if (!(er instanceof HttpErro && er.status === 409)) throw er;   // sobreposição: a loja já está pausada no iFood (por nós ou pelo Portal)
        await rpc("ifood_log", { p_nivel: "info", p_msg: "Pausa no iFood não criada: já havia uma pausa ativa nesse horário (409)." });
      }
      await rpc("ifood_loja_gravar", { p_status: [{ state: a.acao === "loja_fechar" ? "FECHADA" : "PAUSADA", available: false }], p_interrupcao: r?.id ? String(r.id) : null });
    } else {
      const lista: any = await chamar(cred, "GET", `/merchant/v1.0/merchants/${m}/interruptions`);
      for (const i of (Array.isArray(lista) ? lista : [])) {
        if (/pelo sistema/i.test(String(i.description || ""))) await chamar(cred, "DELETE", `/merchant/v1.0/merchants/${m}/interruptions/${encodeURIComponent(i.id)}`);
      }
    }
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
    await atualizarLoja(cred, true);
  } catch (er) {
    const st = er instanceof HttpErro ? er.status : 0;
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 ? "erro" : "duvida", p_erro: er instanceof HttpErro ? `${st} ${er.corpo}` : String(er) });
  }
}
async function atualizarLoja(cred: any, forcar = false) {
  try {
    const l: any = await rpc("ifood_loja_estado");
    if (!forcar && l?.verificado_em && Date.now() - new Date(l.verificado_em).getTime() < 25000) return;   // C-03: a cada rodada (30 s), como pede a documentação
    const st: any = await chamar(cred, "GET", `/merchant/v1.0/merchants/${encodeURIComponent(cred.merchantId || "")}/status`);
    await rpc("ifood_loja_gravar", { p_status: Array.isArray(st) ? st : [st], p_interrupcao: null });
  } catch (er) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Estado da loja não carregou: " + textoErro(er).slice(0, 200) }); } catch { /* sem registro */ } }
}
// C-02: lojas do app (1x por dia e quando ligar): confere se o merchantId configurado pertence ao app
async function conferirLojas(cred: any) {
  try {
    const r: any = await chamar(cred, "GET", "/merchant/v1.0/merchants");
    await rpc("ifood_lojas_gravar", { p_lista: Array.isArray(r) ? r : (r?.merchants || []), p_merchant: String(cred.merchantId || "") });
  } catch (er) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Lista de lojas do iFood não carregou: " + textoErro(er).slice(0, 200) }); } catch { /* sem registro */ } }
}
// Negociação (doc oficial "Plataforma de negociação"): accept {reason, detailReason} (o motivo é exigido na negociação por ATRASO),
// reject {reason: negotiationReasons}, alternative (singular) {type, metadata}. REFUND: valor em centavos, texto ("5000" = R$ 50,00).
function textoNegociacao(er: unknown): string {
  const t = er instanceof HttpErro ? er.corpo : String(er);
  if (/DISPUTE_ALREADY_ANSWERED/i.test(t)) return "Esta negociação já foi respondida (talvez pelo Portal do Parceiro ou pela resposta automática do iFood).";
  if (/DISPUTE_NOT_FOUND/i.test(t)) return "O iFood não encontrou esta negociação (já encerrada ou expirada).";
  if (/INVALID_REASON/i.test(t)) return "O iFood não aceitou o motivo escolhido. Escolha outro motivo da lista.";
  if (/INVALID_AMOUNT/i.test(t)) return "O valor do reembolso está fora do permitido pelo iFood (acima do máximo da proposta).";
  return t;
}
// baixa a foto de evidência do cliente (a URL exige o acesso do iFood) e devolve como imagem pequena para a tela
async function baixarEvidencia(cred: any, url: string): Promise<string | null> {
  try {
    const u = /^https?:/i.test(url) ? new URL(url) : new URL(BASE + (url.startsWith("/") ? url : "/" + url));
    if (!/(^|\.)ifood\.com\.br$/i.test(u.hostname) && !/(^|\.)ifood\.com$/i.test(u.hostname) && u.origin !== new URL(BASE).origin) return null;
    const token = await pegarToken(cred);
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 12000);
    try {
      const r = await fetch(u.toString(), { headers: { Authorization: "Bearer " + token }, signal: ctl.signal });
      if (!r.ok) return null;
      const tipo = (r.headers.get("content-type") || "image/jpeg").split(";")[0];
      if (!/^image\//i.test(tipo)) return null;
      const buf = new Uint8Array(await r.arrayBuffer());
      if (buf.length > 900000) return null;
      let bin = ""; for (let i = 0; i < buf.length; i += 8192) bin += String.fromCharCode(...buf.subarray(i, i + 8192));
      return `data:${tipo};base64,${btoa(bin)}`;
    } finally { clearTimeout(t); }
  } catch { return null; }
}
async function executarNegociacao(cred: any, a: any) {
  const id = encodeURIComponent(a.dados?.disputa || "");
  const d = a.dados || {};
  try {
    if (a.acao === "negociacao_aceitar") {
      const corpo: any = {};
      if (d.motivo) corpo.reason = String(d.motivo);
      if (d.detalhe) corpo.detailReason = String(d.detalhe).slice(0, 250);
      await chamar(cred, "POST", `/order/v1.0/disputes/${id}/accept`, Object.keys(corpo).length ? corpo : undefined);
    } else if (a.acao === "negociacao_recusar") {
      await chamar(cred, "POST", `/order/v1.0/disputes/${id}/reject`, { reason: String(d.motivo || "CUSTOMER_SATISFACTION") });
    } else {
      const tipo = String(d.tipo || "").toUpperCase();
      let corpo: any;
      if (tipo === "REFUND" || tipo === "BENEFIT") {
        const c = Math.round(Number(d.valorCentavos));
        if (!(c > 0)) throw new HttpErro(400, "informe o valor do reembolso");
        corpo = { type: tipo, metadata: { amount: { value: String(c), currency: "BRL" } } };
      } else if (tipo === "ADDITIONAL_TIME") {
        const min = Math.round(Number(d.minutos));
        if (!(min > 0)) throw new HttpErro(400, "informe quantos minutos a mais");
        corpo = { type: tipo, metadata: { additionalTimeInMinutes: min, reason: String(d.motivo || "HIGH_STORE_DEMAND") } };
      } else throw new HttpErro(400, "escolha uma contraproposta");
      await chamar(cred, "POST", `/order/v1.0/disputes/${id}/alternative`, corpo);
    }
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof HttpErro ? er.status : 0;
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 ? "erro" : "duvida", p_erro: er instanceof HttpErro ? `${st} ${textoNegociacao(er)}` : String(er) });
    if (st >= 400 && st < 500) { try { await rpc("ifood_negociacao_erro", { p_id: String(d.disputa || ""), p_erro: textoNegociacao(er).slice(0, 300) }); } catch { /* sem registro */ } }
  }
}

// ---------- catálogo (preço, pausa), financeiro e avaliações ----------
// ⚠️ Endereços do catálogo/financeiro/avaliações vêm de fontes de terceiros: ainda não testado com o iFood de verdade.
function achatarCatalogo(cats: any): any[] {
  const out: any[] = [];
  for (const c of (Array.isArray(cats) ? cats : [])) {
    for (const it of (c.items || c.products || [])) {
      out.push({ id: it.id || it.itemId, name: it.name || it.description, externalCode: it.externalCode, price: it.price?.value ?? it.price, category: c.name, status: it.status });
    }
  }
  return out;
}
async function executarCatalogo(cred: any, a: any) {
  if (/^catalogo_(modelo|lote|opcao|diagnostico)/.test(String(a.acao))) return await executarCatalogoGestao({ chamar, rpc, HttpErro }, cred, a);
  const m = encodeURIComponent(cred.merchantId || "");
  try {
    if (a.acao === "catalogo_importar") {
      const cats: any = await chamar(cred, "GET", `/catalog/v2.0/merchants/${m}/catalogs`);
      const todos: any[] = [];
      for (const c of (Array.isArray(cats) ? cats : [])) {
        const id = c.catalogId || c.id; if (!id) continue;
        const itens: any = await chamar(cred, "GET", `/catalog/v2.0/merchants/${m}/catalogs/${encodeURIComponent(id)}/categories?include_items=true`);
        todos.push(...achatarCatalogo(itens));
      }
      await rpc("ifood_catalogo_gravar", { p_itens: todos });
    } else if (a.acao === "catalogo_preco") {
      try {
        await chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/items/price`, { itemId: a.dados.itemId, price: { value: Number(a.dados.preco) } });
        if (a.dados.hist) await rpc("ifood_preco_confirmar", { p_id: a.dados.hist, p_ok: true });
      } catch (er) { if (a.dados.hist) await rpc("ifood_preco_confirmar", { p_id: a.dados.hist, p_ok: false, p_erro: String(er instanceof HttpErro ? `${er.status} ${er.corpo}` : er).slice(0, 250) }); throw er; }
    } else if (a.acao === "catalogo_pausar" || a.acao === "catalogo_retomar") {
      await chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/items/status`, { itemId: a.dados.itemId, status: a.acao === "catalogo_pausar" ? "UNAVAILABLE" : "AVAILABLE" });
    } else if (a.acao === "avaliacao_responder") {
      await chamar(cred, "POST", `/review/v2.0/merchants/${m}/reviews/${encodeURIComponent(a.dados.avaliacao)}/answers`, { text: a.dados.texto });
      await rpc("ifood_aval_resposta_resultado", { p_id: String(a.dados.avaliacao), p_http: 201 });   // 201 = recebida; o iFood ainda valida (a tela mostra "enviando")
    }
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof HttpErro ? er.status : 0;
    // H4: o iFood recusou (400 tamanho, 409 já respondida/fora do prazo, 422 conteúdo): a tela volta a "sem resposta" e a equipe é avisada
    if (a.acao === "avaliacao_responder" && st >= 400 && st < 500) { try { await rpc("ifood_aval_resposta_resultado", { p_id: String(a.dados?.avaliacao || ""), p_http: st, p_corpo: er instanceof HttpErro ? er.corpo : "" }); } catch { /* sem registro */ } }
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 ? "erro" : "duvida", p_erro: er instanceof HttpErro ? `${st} ${er.corpo}` : String(er) });
  }
}
// v1.15: o financeiro completo (vendas, lançamentos, repasses, antecipações e arquivo mensal) fica em financeiro.ts, por fila.
// A cada 6 h só agenda as buscas automáticas; as tarefas são feitas aos poucos em cada rodada (processarFinanceiro).
async function sincronizarFinanceiro(_cred: any) {
  try { await rpc("ifood_fin_agendar_auto"); } catch (er) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Financeiro do iFood: não foi possível agendar as buscas: " + String(er).slice(0, 200) }); } catch { /* sem registro */ } }
}
async function sincronizarAvaliacoes(cred: any) {
  const m = encodeURIComponent(cred.merchantId || "");
  // H6: pageSize 50 (máximo; acima disso o iFood dá 400), todas as páginas, últimos 10 dias (o prazo de resposta é de 5 dias; o padrão do iFood seria só 7 dias)
  try {
    const ate = new Date(); const de = new Date(Date.now() - 10 * 86400000);
    const todas: any[] = []; let pagina = 1, total = 1;
    while (pagina <= total && pagina <= 10) {
      const r: any = await chamar(cred, "GET", `/review/v2.0/merchants/${m}/reviews?page=${pagina}&pageSize=50&dateFrom=${encodeURIComponent(de.toISOString())}&dateTo=${encodeURIComponent(ate.toISOString())}`);
      const lista = Array.isArray(r) ? r : (r?.reviews || r?.items || r?.data || []);
      todas.push(...lista);
      total = Number(r?.pageCount ?? r?.totalPages ?? 1) || 1; pagina++;
      if (!lista.length) break;
    }
    await rpc("ifood_avaliacoes_gravar", { p_lista: todas });   // a listagem v2 vai inteira: order.id / order.shortId, replies (MERCHANT/CUSTOMER), status, visibility...
  } catch (er) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Avaliações do iFood não carregaram: " + textoErro(er).slice(0, 200) }); } catch { /* sem registro */ } }   // C-01: nunca mais calado
  // H8: nota oficial (média dos últimos 3 meses); 404/400 em loja de teste é normal
  try {
    const sm: any = await chamar(cred, "GET", `/review/v2.0/merchants/${m}/summary`);
    if (sm && typeof sm === "object") await rpc("ifood_aval_resumo_gravar", { p: sm });
  } catch (er) { if (!(er instanceof HttpErro && (er.status === 404 || er.status === 400))) { try { await rpc("ifood_log", { p_nivel: "aviso", p_msg: "Nota oficial do iFood não carregou: " + textoErro(er).slice(0, 200) }); } catch { /* sem registro */ } } }
  // H7: detalhe (nome do cliente e questionário) das avaliações novas, no máximo 5 por rodada
  try {
    const ids = ((await rpc("ifood_aval_detalhe_pendentes")) as string[]) || [];
    for (const id of ids) {
      try { const d: any = await chamar(cred, "GET", `/review/v2.0/merchants/${m}/reviews/${encodeURIComponent(id)}`); await rpc("ifood_aval_detalhe_gravar", { p_id: id, p: d || {} }); }
      catch (er) { if (er instanceof HttpErro && er.status === 404) await rpc("ifood_aval_detalhe_gravar", { p_id: id, p: {} }); }   // 404: sem detalhe; não insiste
    }
  } catch { /* só enfeite */ }
}

async function executarAcao(cred: any, a: any) {
  if (a.acao === "analytics_buscar") return await executarAnalytics({ http, http1, rpc, HttpErro }, a);
  if (String(a.acao).startsWith("ship_")) return await executarShipping({ chamar, rpc, HttpErro }, cred, a);
  if (/^(catalogo_|avaliacao_)/.test(String(a.acao))) return await executarCatalogo(cred, a);
  if (String(a.acao).startsWith("loja_")) return await executarLoja(cred, a);
  if (String(a.acao).startsWith("negociacao_")) return await executarNegociacao(cred, a);
  const info: any = await rpc("ifood_pedido_dados", { p_pedido: a.pedido });
  if (!info || info.simulado) { await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "pulada", p_erro: "pedido simulado/desconhecido" }); return; }
  if (a.acao === "motivos") {   // C-06: motivos oficiais para a equipe escolher antes de cancelar
    try {
      const lista: any = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(a.pedido)}/cancellationReasons`);
      await rpc("ifood_motivos_gravar", { p_pedido: a.pedido, p_lista: listaMotivos(lista).map((m: any) => ({ ...m, cancelCodeId: m.code })) });
      await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
    } catch (er) { await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "erro", p_erro: textoErro(er).slice(0, 250) }); }
    return;
  }
  if (a.acao === "codigo_coleta" || a.acao === "codigo_entrega") {   // C-07
    const tipo = a.acao === "codigo_coleta" ? "coleta" : "entrega";
    try {
      const resp: any = await chamar(cred, "POST", `/order/v1.0/orders/${encodeURIComponent(a.pedido)}/${tipo === "coleta" ? "validatePickupCode" : "verifyDeliveryCode"}`, { code: String(a.dados?.codigo || "") });
      // doc oficial: a resposta é 200 {"valid": true|false}; só "valid: true" confirma (código errado também volta 200)
      if (resp && typeof resp === "object" && resp.valid === false) throw new HttpErro(400, "invalid_code");
      await rpc("ifood_codigo_resultado", { p_pedido: a.pedido, p_tipo: tipo, p_ok: true });
      await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
    } catch (er) {
      const st = er instanceof HttpErro ? er.status : 0;
      const msg = st === 400 || st === 422 ? "código não confere: confira os números com o entregador/cliente" : st === 404 || st === 412 ? "este pedido não exige código agora ou não está no estado certo" : textoErro(er);
      await rpc("ifood_codigo_resultado", { p_pedido: a.pedido, p_tipo: tipo, p_ok: false, p_erro: msg });
      await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 ? "erro" : "duvida", p_erro: msg.slice(0, 250) });
    }
    return;
  }
  const cam = CAMINHO[a.acao]; if (!cam) { await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "erro", p_erro: "ação desconhecida" }); return; }
  try {
    let corpo: unknown = undefined;
    if (a.acao === "cancelar") {
      // doc oficial: os motivos vêm de GET cancellationReasons ({"reasons":[{code,description}]}; 204 = sem política) e o corpo do POST é só {"reason":"<código>"}
      const motivos: any = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(a.pedido)}/cancellationReasons`);
      const lista = listaMotivos(motivos);
      if (!lista.length) throw new HttpErro(409, "o iFood não permite cancelar este pedido pelo sistema (sem motivos disponíveis). Cancele pelo Portal do Parceiro ou fale com o iFood.");
      const texto = String(a.dados?.motivo || "").toLowerCase();
      const escolhido = (a.dados?.codigo && lista.find((m: any) => m.code === String(a.dados.codigo)))
        || lista.find((m: any) => texto && String(m.description || "").toLowerCase().includes(texto.slice(0, 8))) || lista[0];
      corpo = { reason: String(escolhido.code) };
      try { await rpc("ifood_log", { p_nivel: "info", p_msg: `Cancelamento do pedido ${a.pedido} enviado ao iFood com o motivo ${escolhido.code} (${String(escolhido.description || "").slice(0, 80)})` }); } catch { /* só registro */ }
    }
    // doc oficial: ao despachar (entrega própria) o corpo é {"deliveredBy":"MERCHANT"}; o "pronto" já foi enviado antes (a fila respeita a ordem)
    if (a.acao === "despachar") corpo = { deliveredBy: "MERCHANT" };
    await chamar(cred, "POST", `/order/v1.0/orders/${encodeURIComponent(a.pedido)}/${cam}`, corpo);
    // HTTP 202 = aceito, NÃO = concluído: o estado oficial vem pelos eventos
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof HttpErro ? er.status : 0;
    const msg = a.acao === "cancelar" ? textoCancelamento(er) : (er instanceof HttpErro ? `${st} ${er.corpo}` : String(er));
    // 429 (limite de chamadas, já esperou 3 vezes): o iFood NÃO recebeu; volta para a fila e tenta na próxima rodada (até 5 vezes).
    // Outro 4xx = o iFood recusou (erro definitivo). Timeout/5xx = não sabemos se foi: fica "dúvida" e NÃO repete sozinho.
    if (st === 429 && (a.tentativas || 0) < 5) { await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "pendente", p_erro: "429: tenta de novo na próxima rodada" }); return; }
    await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 ? "erro" : "duvida", p_erro: msg });
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const chaveVault = await seg("service_key");
  if (!token || (token !== SVC && token !== chaveVault)) return json({ ok: false, message: "Só execução interna." }, 403);
  try {
    const cred: any = await rpc("ifood_credenciais");
    if (!cred || !cred.ligado) return json({ ok: true, ligado: false });
    // documentação oficial (Authentication): não repetir sem parar quando o iFood recusa o acesso (401/403): espera 5 min
    try { if ((await rpc("ifood_pode_consultar")) === false) return json({ ok: true, aguardando: "acesso recusado: nova tentativa em até 5 min" }); } catch { /* sem a função: segue */ }
    const dono = crypto.randomUUID();
    if (!(await rpc("ifood_trava_pegar", { p_dono: dono, p_seg: 100 }))) return json({ ok: true, ocupado: true });
    try {
      for (let volta = 0; volta < 1; volta++) {   // 1 rodada por chamada: o agendamento (pg_cron) chama a cada 30 s, que é o ritmo que o iFood pede
        if (volta > 0 && !(await rpc("ifood_trava_pegar", { p_dono: dono, p_seg: 100 }))) break;   // renova a trava a cada volta (mesmo dono); se perdeu, para
        await consultar(cred);
        await processar(cred);
        await agir(cred);
        await acompanharEntregas(cred);
        try { await rpc("ifood_escalar"); await rpc("ifood_loja_verificar"); await atualizarLoja(cred);
          if (volta === 0 && await rpc("ifood_precisa", { p_tarefa: "avaliacoes", p_minutos: 30 })) await sincronizarAvaliacoes(cred);
          if (volta === 0 && await rpc("ifood_precisa", { p_tarefa: "financeiro", p_minutos: 360 })) await sincronizarFinanceiro(cred);
          if (volta === 0 && await rpc("ifood_precisa", { p_tarefa: "lojas", p_minutos: 1440 })) await conferirLojas(cred); } catch { /* reforços: não podem derrubar o ciclo */ }
        try { await processarFinanceiro({ rpc, pegarToken, marcarModulo, BASE }, cred); } catch { /* financeiro: nunca derruba o ciclo */ }
      }
    } finally {
      await rpc("ifood_trava_soltar", { p_dono: dono });
      if (Object.keys(MODULOS).length) { try { await rpc("ifood_modulos_registrar", { p: MODULOS }); } catch { /* só painel */ } for (const k of Object.keys(MODULOS)) delete MODULOS[k]; }
    }
    return json({ ok: true });
  } catch (e) {
    try { await rpc("ifood_marcar_consulta", { p_ok: false, p_erro: "Erro interno: " + String(e).slice(0, 200) }); } catch { /* sem registro */ }
    return json({ ok: false, message: String(e).slice(0, 200) }, 500);
  }
});

// confirma o recebimento em lotes de até 2000 (limite do Order); se o iFood responder 413 (lote grande demais), divide ao meio
async function confirmarEventos(cred: any, ids: string[]) {
  for (let i = 0; i < ids.length; i += 2000) {
    const lote = ids.slice(i, i + 2000).map((id) => ({ id }));
    try { await chamar(cred, "POST", "/events/v1.0/events/acknowledgment", lote); }
    catch (er) {
      if (er instanceof HttpErro && er.status === 413 && lote.length > 1) {
        const meio = Math.ceil(lote.length / 2);
        await chamar(cred, "POST", "/events/v1.0/events/acknowledgment", lote.slice(0, meio));
        await chamar(cred, "POST", "/events/v1.0/events/acknowledgment", lote.slice(meio));
      } else throw er;
    }
  }
}

// 1) pergunta ao iFood o que há de novo, guarda e confirma o recebimento
async function consultar(cred: any) {
  try {
    const eventos: any = await chamar(cred, "GET", "/events/v1.0/events:polling", undefined, cred.merchantId ? { "x-polling-merchants": cred.merchantId } : {});
    const lista: any[] = Array.isArray(eventos) ? eventos : [];
    const guardados: any[] = []; let falhas = 0;
    for (const ev of lista) { try { await rpc("ifood_evento_guardar", { p: ev }); guardados.push(ev); } catch { falhas++; } }   // guarda ANTES de confirmar: nunca perde evento; um que falhe não trava os outros
    if (falhas) { try { await rpc("ifood_log", { p_nivel: "erro", p_msg: `${falhas} evento(s) do iFood não puderam ser guardados nesta rodada (o iFood entrega de novo).` }); } catch { /* sem registro */ } }
    if (guardados.length) await confirmarEventos(cred, guardados.map((ev) => ev.id));
    await rpc("ifood_marcar_consulta", { p_ok: true, p_token_ok: true });
  } catch (e) {
    const st = e instanceof HttpErro ? e.status : 0;
    const recusado = st === 401 || st === 403 || (e instanceof HttpErro && /faltam Client/.test(e.corpo));
    const naoAutorizada = st === 403 && e instanceof HttpErro && /unauthorizedMerchants/i.test(e.corpo);
    await rpc("ifood_marcar_consulta", { p_ok: false, p_erro: naoAutorizada ? "O iFood diz que a loja ainda NÃO autorizou este app (pode levar até 10 minutos depois de autorizar no Portal do Parceiro). O sistema tenta de novo sozinho." : recusado ? "Acesso recusado pelo iFood (confira Client ID e Client Secret)" : "Falha ao consultar o iFood: " + (e instanceof HttpErro ? `${e.status} ${e.corpo}` : String(e)).slice(0, 200), p_token_ok: recusado ? false : null });
  }
}

// 2) trata os eventos guardados (criar venda, estado oficial...)
async function processar(cred: any) {
  let pend: any[] = [];
  try { await rpc("ifood_eventos_vencidos_fechar"); } catch { /* só limpeza: não pode travar o ciclo */ }
  try { pend = (await rpc("ifood_eventos_pendentes")) as any[]; } catch { return; }
  for (const e of pend || []) {
    try {
      const r = await tratarEvento(cred, e);
      await rpc("ifood_evento_resultado", { p_id: e.id, p_final: r.final || (e.tentativas || 0) >= 30, p_erro: r.erro || null });
    } catch (er) {
      await rpc("ifood_evento_resultado", { p_id: e.id, p_final: (e.tentativas || 0) >= 30, p_erro: String(er).slice(0, 250) });
    }
  }
}

// 2b) rastreio do entregador (doc: só entrega do iFood, depois do entregador escalado, no máximo 1x a cada 30 s por pedido; 404 antes disso é normal)
async function acompanharEntregas(cred: any) {
  let ids: string[] = [];
  try { ids = ((await rpc("ifood_rastreio_pendentes")) as string[]) || []; } catch { return; }
  for (const id of ids.slice(0, 3)) {
    try {
      const r: any = await chamar(cred, "GET", `/order/v1.0/orders/${encodeURIComponent(id)}/tracking`);
      await rpc("ifood_rastreio_gravar", { p_pedido: id, p_dados: r || {} });
    } catch (er) {
      if (er instanceof HttpErro && er.status === 404) { try { await rpc("ifood_rastreio_gravar", { p_pedido: id, p_dados: { aguardando: true } }); } catch { /* sem registro */ } }
    }
  }
}

// 3) manda ao iFood o que a equipe fez no sistema (confirmar, preparo, pronto, despachar, cancelar)
async function agir(cred: any) {
  let acoes: any[] = [];
  try { acoes = (await rpc("ifood_acoes_pendentes")) as any[]; } catch { return; }
  for (const a of acoes || []) { try { await executarAcao(cred, a); } catch (er) { await rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "duvida", p_erro: String(er).slice(0, 250) }); } }
}
