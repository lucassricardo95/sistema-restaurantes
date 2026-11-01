// ifood-sync · FINANCEIRO do iFood (v1.15, 25/10/2026) — feito pela documentação oficial do módulo Financial (PDFs do portal):
//   API Sales (vendas), API Financial Events (lançamentos), API Settlement (repasses), API Anticipation (antecipações) e
//   API Reconciliation On-Demand (arquivo mensal .csv.gz).
// Funciona por uma FILA no banco (ifood_fin_tarefas): a cada rodada do ifood-sync (30 s) faz no máximo algumas chamadas,
// por no máximo ~20 s — bem abaixo do limite de 1000 chamadas/min do iFood. Uma página por chamada; a próxima página vai
// para a rodada seguinte. Token: renova sozinho (401 → token novo e repete 1 vez). 429: espera o Retry-After (ou 2, 4, 8 s)
// e, se continuar, volta para a fila com espera crescente. Homologação: o cabeçalho x-request-homologation vai junto quando
// o "Modo homologação" do iFood está marcado.
// ⚠️ O endereço exato de cada API (a documentação mostra só "/v3/sales" etc.) é confirmado no primeiro teste: tentamos o formato
// já usado pelo iFood (/financial/v3.0/merchants/{id}/...) e, se o iFood responder 404, o formato alternativo; o que funcionar fica guardado.

type Dep = {
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<any>;
  pegarToken: (cred: any, forcar?: boolean) => Promise<string>;
  marcarModulo: (caminho: string, ok: boolean, status?: number, msg?: string) => void;
  BASE: string;
};
type Resp = { status: number; corpo: any; texto: string; retryAfter: number };

const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));
const q = (o: Record<string, unknown>) => Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== "").map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`).join("&");
const junta = (base: string, qs: string) => qs ? base + (base.includes("?") ? "&" : "?") + qs : base;

// Endereços possíveis de cada API (o primeiro que responder algo diferente de 404 fica guardado em ifood_estado.fin_rotas)
const ROTAS: Record<string, ((m: string) => string)[]> = {
  vendas: [(m) => `/financial/v3.0/merchants/${m}/sales`, (m) => `/financial/v3/sales?merchantId=${m}`],
  eventos: [(m) => `/financial/v3.0/merchants/${m}/financial-events`, (m) => `/financial/v3/financial-events?merchantId=${m}`],
  repasses: [(m) => `/financial/v3.0/merchants/${m}/settlements`, (m) => `/financial/v3/settlements?merchantId=${m}`],
  antecipacoes: [(m) => `/financial/v3.0/merchants/${m}/anticipations`, (m) => `/financial/v3/anticipations?merchantId=${m}`],
  conciliacao: [(m) => `/financial/v3.0/merchants/${m}/reconciliation/on-demand`, (m) => `/financial/v3.0/merchants/${m}/reconciliation-on-demand`,
                (m) => `/financial/v3/reconciliation-on-demand?merchantId=${m}`],
};

export function textoFin(status: number, texto: string): string {
  if (status === 400) return "O iFood recusou os parâmetros (400): " + texto.slice(0, 160);
  if (status === 401) return "Credenciais recusadas pelo iFood (401). Confira Client ID e Client Secret.";
  if (status === 403) return "Módulo Financeiro ainda não liberado para este app (403): ele é liberado na homologação do Financeiro.";
  if (status === 404) return "Nada encontrado para o período (404).";
  if (status === 409) return "Pedido repetido (409): o iFood já está gerando este arquivo.";
  if (status === 429) return "Limite de chamadas do iFood (429): tentando de novo daqui a pouco.";
  if (status === 0) return "O iFood não respondeu (sem internet ou demorou demais).";
  if (status >= 500) return `O iFood está com problema (${status}). Tentamos de novo mais tarde.`;
  return `${status} ${texto.slice(0, 160)}`;
}

async function req(d: Dep, cred: any, metodo: string, caminho: string, corpo?: unknown): Promise<Resp> {
  const extra: Record<string, string> = cred?.config?.modoHomologacao ? { "x-request-homologation": "true" } : {};
  let token = await d.pegarToken(cred);
  let renovou = false;
  for (let tentativa = 0; ; tentativa++) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 20000);
    let r: Response | null = null; let texto = "";
    try {
      const h: Record<string, string> = { ...extra, Authorization: "Bearer " + token, Accept: "application/json" };
      if (corpo !== undefined) h["Content-Type"] = "application/json";
      r = await fetch(d.BASE + caminho, { method: metodo, headers: h, body: corpo !== undefined ? JSON.stringify(corpo) : undefined, signal: ctl.signal });
      texto = await r.text();
    } catch { r = null; } finally { clearTimeout(t); }
    if (!r) { d.marcarModulo(caminho, false, 0, "rede_ou_timeout"); return { status: 0, corpo: null, texto: "rede_ou_timeout", retryAfter: 0 }; }
    if (r.status === 401 && !renovou) { renovou = true; token = await d.pegarToken(cred, true); continue; }
    const ra = Number(r.headers.get("retry-after")) || 0;
    if (r.status === 429 && tentativa < 3) { await dormir(Math.min(8000, ra > 0 ? ra * 1000 : 2000 * 2 ** tentativa)); continue; }
    let parsed: any = null; try { parsed = texto ? JSON.parse(texto) : null; } catch { parsed = null; }
    const ok = (r.status >= 200 && r.status < 300) || r.status === 404 || r.status === 409;
    d.marcarModulo(caminho, ok, r.status, ok ? undefined : texto.slice(0, 250));
    return { status: r.status, corpo: parsed, texto, retryAfter: ra };
  }
}

// tenta os endereços na ordem (o guardado primeiro); 404 → tenta o próximo; qualquer outra resposta encerra.
async function comRota(d: Dep, cred: any, rotas: Record<string, string>, api: string, metodo: string, sufixo: string, qs: string, corpo?: unknown): Promise<Resp> {
  const m = encodeURIComponent(cred.merchantId || "");
  const lista = ROTAS[api].map((f, i) => ({ i, f }));
  const pref = Number(rotas?.[api]);
  if (Number.isInteger(pref) && pref > 0 && pref < lista.length) lista.unshift(lista.splice(pref, 1)[0]);
  let ultimo: Resp | null = null;
  for (const { i, f } of lista) {
    const base = f(m);
    const [cam, qbase] = base.split("?");
    const r = await req(d, cred, metodo, junta(cam + sufixo + (qbase ? "?" + qbase : ""), qs), corpo);
    if (r.status === 404 && lista.length > 1 && !(r.corpo && typeof r.corpo === "object" && JSON.stringify(r.corpo).match(/liquida|settlement|antecipa|anticipation|plan|request/i))) { ultimo = r; continue; }
    if ((r.status >= 200 && r.status < 300) || r.status === 409 || r.status === 400) {   // endereço confirmado (404 não confirma nada)
      if (String(rotas?.[api] ?? "0") !== String(i)) { try { await d.rpc("ifood_fin_rota", { p_api: api, p_rota: String(i) }); rotas[api] = String(i); } catch { /* só memória */ } }
    }
    return r;
  }
  return ultimo || { status: 404, corpo: null, texto: "", retryAfter: 0 };
}

// primeiro array da resposta (o nome do campo varia conforme a API: sales, financialEvents, events, data, items...)
function lista(corpo: any, nomes: string[]): any[] {
  if (Array.isArray(corpo)) return corpo;
  if (!corpo || typeof corpo !== "object") return [];
  for (const n of nomes) if (Array.isArray(corpo[n])) return corpo[n];
  for (const v of Object.values(corpo)) if (Array.isArray(v) && v.length && typeof v[0] === "object") return v as any[];
  return [];
}
function temMais(corpo: any, pagina: number, base: number, qtd: number, tamanho: number): boolean {
  if (corpo && typeof corpo === "object") {
    if (typeof corpo.hasNextPage === "boolean") return corpo.hasNextPage;
    const pc = Number(corpo.pageCount ?? corpo.totalPages);
    if (Number.isFinite(pc) && pc > 0) return pagina + (base === 0 ? 1 : 0) < pc;
  }
  return qtd >= tamanho;   // sem informação: página cheia = pode haver mais
}

// resultado de erro: 429/5xx/sem resposta voltam para a fila com espera crescente (até 6 vezes); 400/401/403 são definitivos
async function falhou(d: Dep, t: any, api: string, r: Resp) {
  const msg = textoFin(r.status, r.texto);
  const temporario = r.status === 0 || r.status === 429 || r.status >= 500;
  await d.rpc("ifood_fin_consulta", { p_api: api, p_ok: false, p_status: r.status, p_msg: msg, p_ini: t.ini, p_fim: t.fim });
  if (temporario && (t.tentativas || 0) < 6) {
    const espera = Math.max(r.retryAfter || 0, Math.min(1800, 60 * 2 ** (t.tentativas || 0)));
    await d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "pendente", p_status: r.status, p_erro: msg, p_espera_seg: espera });
  } else await d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_status: r.status, p_erro: msg });
}

async function vendas(d: Dep, cred: any, rotas: any, t: any) {
  const pagina = Number(t.pagina || 0);   // API Sales: página começa em 0; tamanho fixo (100)
  const r = await comRota(d, cred, rotas, "vendas", "GET", "", q({ beginSalesDate: t.ini, endSalesDate: t.fim, page: pagina }));
  if (r.status === 404) { await d.rpc("ifood_fin_consulta", { p_api: "vendas", p_ok: true, p_status: 404, p_msg: "Sem vendas no período.", p_qtd: 0, p_ini: t.ini, p_fim: t.fim }); return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "sem_dados", p_status: 404 }); }
  if (r.status !== 200) return falhou(d, t, "vendas", r);
  const l = lista(r.corpo, ["sales"]);
  await d.rpc("ifood_fin_vendas_gravar", { p_lista: l });
  await d.rpc("ifood_fin_consulta", { p_api: "vendas", p_ok: true, p_status: 200, p_qtd: Number(r.corpo?.total ?? l.length), p_ini: t.ini, p_fim: t.fim });
  const mais = l.length > 0 && temMais(r.corpo, pagina, 0, l.length, 100);
  return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: mais ? "pagina" : "ok", p_status: 200 });
}

async function eventos(d: Dep, cred: any, rotas: any, t: any) {
  const pagina = Math.max(1, Number(t.pagina || 1));   // Financial Events: página começa em 1; até 500 por página (usamos 100)
  const r = await comRota(d, cred, rotas, "eventos", "GET", "", q({ beginDate: t.ini, endDate: t.fim, page: pagina, size: 100 }));
  if (r.status === 404) { await d.rpc("ifood_fin_eventos_gravar", { p_ini: t.ini, p_fim: t.fim, p_primeira: pagina === 1, p_lista: [] }); return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "sem_dados", p_status: 404 }); }
  if (r.status !== 200) return falhou(d, t, "eventos", r);
  const l = lista(r.corpo, ["financialEvents", "events", "data", "items", "content"]);
  await d.rpc("ifood_fin_eventos_gravar", { p_ini: t.ini, p_fim: t.fim, p_primeira: pagina === 1, p_lista: l });
  await d.rpc("ifood_fin_consulta", { p_api: "eventos", p_ok: true, p_status: 200, p_qtd: l.length, p_ini: t.ini, p_fim: t.fim });
  const mais = l.length > 0 && temMais(r.corpo, pagina, 1, l.length, 100);
  return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: mais ? "pagina" : "ok", p_status: 200 });
}

async function repasses(d: Dep, cred: any, rotas: any, t: any) {
  const r = await comRota(d, cred, rotas, "repasses", "GET", "", q({ beginDate: t.ini, endDate: t.fim }));
  if (r.status === 404) { await d.rpc("ifood_fin_consulta", { p_api: "repasses", p_ok: true, p_status: 404, p_msg: "Nenhum repasse (liquidação) no período.", p_qtd: 0, p_ini: t.ini, p_fim: t.fim }); return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "sem_dados", p_status: 404 }); }
  if (r.status !== 200) return falhou(d, t, "repasses", r);
  const n = await d.rpc("ifood_fin_liquidacoes_gravar", { p_resp: r.corpo || {} });
  await d.rpc("ifood_fin_consulta", { p_api: "repasses", p_ok: true, p_status: 200, p_saldo: Number(r.corpo?.balance ?? 0), p_qtd: Number(n) || 0, p_ini: t.ini, p_fim: t.fim });
  return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "ok", p_status: 200 });
}

async function antecipacoes(d: Dep, cred: any, rotas: any, t: any) {
  const pagina = Math.max(1, Number(t.pagina || 1));
  const r = await comRota(d, cred, rotas, "antecipacoes", "GET", "", q({ beginCalculationDate: t.ini, endCalculationDate: t.fim, page: pagina, size: 100 }));
  if (r.status === 404) {   // 404 = a loja não tem plano de antecipação (D+1/D+7) contratado: não é erro
    await d.rpc("ifood_fin_consulta", { p_api: "antecipacoes", p_ok: true, p_status: 404, p_msg: "A loja não tem plano de antecipação (D+1 ou D+7) contratado.", p_qtd: 0, p_ini: t.ini, p_fim: t.fim });
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "sem_dados", p_status: 404 });
  }
  if (r.status !== 200) return falhou(d, t, "antecipacoes", r);
  const n = Number(await d.rpc("ifood_fin_antecipacoes_gravar", { p_resp: r.corpo || {} })) || 0;
  await d.rpc("ifood_fin_consulta", { p_api: "antecipacoes", p_ok: true, p_status: 200, p_saldo: Number(r.corpo?.balance ?? 0), p_qtd: n, p_ini: t.ini, p_fim: t.fim });
  const mais = n > 0 && temMais(r.corpo, pagina, 1, n, 100);
  return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: mais ? "pagina" : "ok", p_status: 200 });
}

// ---------- arquivo mensal (Reconciliation On-Demand) ----------
async function conciliacaoPedir(d: Dep, cred: any, rotas: any, t: any) {
  const comp = String(t.competencia);
  const r = await comRota(d, cred, rotas, "conciliacao", "POST", "", "", { competencia: comp, competence: comp });
  const reqId = r.corpo?.requestId || r.corpo?.lastRequestId || r.corpo?.id;
  if ((r.status >= 200 && r.status < 300) || r.status === 409) {
    if (!reqId) {
      await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "O iFood aceitou o pedido mas não devolveu o número (requestId). Tente de novo." });
      return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_status: r.status, p_erro: "sem requestId" });
    }
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "processando", p_request_id: String(reqId) });
    await d.rpc("ifood_fin_consulta", { p_api: "conciliacao", p_ok: true, p_status: r.status, p_msg: r.status === 409 ? "Já havia um pedido recente: reaproveitado." : null });
    await d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "ok", p_status: r.status, p_dados: { requestId: String(reqId) } });
    return d.rpc("_ifood_fin_enfileirar", { p_api: "conciliacao_status", p_ini: null, p_fim: null, p_comp: comp, p_origem: "manual", p_lote: null });
  }
  if (r.status === 0 || r.status === 429 || r.status >= 500) return falhou(d, t, "conciliacao", r);
  await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: textoFin(r.status, r.texto) });
  return falhou(d, t, "conciliacao", r);
}

const numBR = (s: string): number => {
  let x = String(s ?? "").trim().replace(/^"|"$/g, "").replace(/\s/g, "").replace(/^R\$/, "");
  if (x === "") return NaN;
  if (x.includes(",")) x = x.replace(/\./g, "").replace(",", ".");
  return Number(x);
};
function linhasCsv(texto: string): string[][] {
  const out: string[][] = []; let campo = ""; let linha: string[] = []; let aspas = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (aspas) { if (c === '"') { if (texto[i + 1] === '"') { campo += '"'; i++; } else aspas = false; } else campo += c; continue; }
    if (c === '"') aspas = true;
    else if (c === ";") { linha.push(campo); campo = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && texto[i + 1] === "\n") i++; linha.push(campo); campo = ""; if (linha.some((x) => x !== "")) out.push(linha); linha = []; }
    else campo += c;
  }
  linha.push(campo); if (linha.some((x) => x !== "")) out.push(linha);
  return out;
}
// Resumo do arquivo: só os lançamentos COM impacto no repasse (impacto_no_repasse = SIM) compõem o valor a receber (regra do iFood).
export function resumirCsv(texto: string) {
  const L = linhasCsv(texto.replace(/^﻿/, ""));
  const cab = (L.shift() || []).map((h) => h.trim().toLowerCase());
  const col = (n: string) => cab.indexOf(n);
  const iImp = col("impacto_no_repasse"), iVal = col("valor"), iTipo = col("tipo_lancamento"), iFato = col("fato_gerador"),
        iData = col("data_repasse_esperada"), iPed = col("pedido_associado_ifood"), iTrans = col("valor_transacao");
  let com = 0, sem = 0, qCom = 0, qSem = 0, ileg = 0, abertos = 0;
  const porTipo: Record<string, number> = {}, porFato: Record<string, number> = {}, porData: Record<string, number> = {}; const pedidos = new Set<string>();
  for (const r of L) {
    const v = numBR(r[iVal] ?? "");
    if (!Number.isFinite(v)) { ileg++; continue; }
    const imp = /^(SIM|S|TRUE)$/i.test(String(r[iImp] ?? "").trim());
    if (imp) {
      com += v; qCom++;
      const tp = String(r[iTipo] ?? "(sem tipo)").trim() || "(sem tipo)"; porTipo[tp] = (porTipo[tp] || 0) + v;
      const ft = String(r[iFato] ?? "(sem fato)").trim() || "(sem fato)"; porFato[ft] = (porFato[ft] || 0) + v;
      const dt = String(r[iData] ?? "").trim().slice(0, 10); if (dt) porData[dt] = (porData[dt] || 0) + v;
    } else { sem += v; qSem++; }
    if (iPed >= 0 && r[iPed]) pedidos.add(String(r[iPed]).trim());
    if (iTrans >= 0 && /aberto/i.test(String(r[iTrans] ?? ""))) abertos++;
  }
  const r2 = (x: number) => Math.round(x * 100) / 100;
  const ord = (o: Record<string, number>) => Object.entries(o).map(([k, v]) => ({ nome: k, valor: r2(v) })).sort((a, b) => Math.abs(b.valor) - Math.abs(a.valor)).slice(0, 25);
  return {
    linhas: L.length, comImpacto: r2(com), semImpacto: r2(sem), qtdComImpacto: qCom, qtdSemImpacto: qSem, ilegiveis: ileg,
    pedidos: pedidos.size, periodoAberto: abertos, porTipo: ord(porTipo), porFato: ord(porFato),
    porDataRepasse: Object.entries(porData).map(([data, v]) => ({ data, valor: r2(v) })).sort((a, b) => a.data.localeCompare(b.data)),
    colunas: cab.slice(0, 60), faltando: ["impacto_no_repasse", "valor"].filter((c) => col(c) < 0),
  };
}
async function gz(bytes: Uint8Array, comprimir: boolean): Promise<Uint8Array> {
  const s = new Blob([bytes as BlobPart]).stream().pipeThrough(comprimir ? new CompressionStream("gzip") : new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
function b64(u: Uint8Array): string { let s = ""; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); }

async function conciliacaoStatus(d: Dep, cred: any, rotas: any, t: any) {
  const comp = String(t.competencia);
  const reqId = t.requestId || t.dados?.requestId;
  if (!reqId) { await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "Pedido sem número (requestId). Peça de novo." }); return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_erro: "sem requestId" }); }
  const r = await comRota(d, cred, rotas, "conciliacao", "GET", "/" + encodeURIComponent(reqId), "");
  const idadeMin = (Date.now() - new Date(t.pedidoEm || Date.now()).getTime()) / 60000;
  const url = r.corpo?.downloadUrl || r.corpo?.url || r.corpo?.link || r.corpo?.fileUrl || r.corpo?.download?.url;
  if (r.status === 202 || (r.status === 200 && !url)) {
    if (idadeMin > 30) {
      await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "O iFood não terminou o arquivo em 30 minutos. Tente de novo mais tarde (o mesmo pedido é reaproveitado por 6 h)." });
      return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_status: r.status, p_erro: "demorou mais de 30 min" });
    }
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "processando" });
    // espera progressiva, como pede o iFood: 30 s nas 5 primeiras vezes, depois 60 s
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "pendente", p_status: r.status, p_erro: "processando no iFood", p_espera_seg: (t.tentativas || 0) < 5 ? 30 : 60 });
  }
  if (r.status === 404) {
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_request_id: "", p_erro: "O pedido expirou no iFood (vale 24 h). Peça o arquivo de novo." });
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_status: 404, p_erro: "requestId expirado" });
  }
  if (r.status !== 200) {
    if (!(r.status === 0 || r.status === 429 || r.status >= 500) || (t.tentativas || 0) >= 6) await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: textoFin(r.status, r.texto) });
    return falhou(d, t, "conciliacao", r);
  }
  // pronto: baixa (o link do iFood vence), confere, resume e guarda comprimido
  let bruto: Uint8Array;
  try {
    const ctl = new AbortController(); const tm = setTimeout(() => ctl.abort(), 30000);
    const a = await fetch(String(url), { signal: ctl.signal }); clearTimeout(tm);
    if (!a.ok) throw new Error("download " + a.status);
    bruto = new Uint8Array(await a.arrayBuffer());
  } catch (e) {
    if ((t.tentativas || 0) < 4) return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "pendente", p_erro: "falha ao baixar o arquivo: " + String(e).slice(0, 120), p_espera_seg: 60 });
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "Não foi possível baixar o arquivo do iFood: " + String(e).slice(0, 150) });
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_erro: String(e).slice(0, 200) });
  }
  const ehGz = bruto.length > 2 && bruto[0] === 0x1f && bruto[1] === 0x8b;
  let texto: string; let guardar: Uint8Array;
  try {
    const csv = ehGz ? await gz(bruto, false) : bruto;
    texto = new TextDecoder("utf-8").decode(csv);
    guardar = ehGz ? bruto : await gz(bruto, true);
  } catch (e) {
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "Arquivo do iFood corrompido (não abriu): " + String(e).slice(0, 120) });
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_erro: "arquivo corrompido" });
  }
  if (guardar.length > 8 * 1024 * 1024) {
    await d.rpc("ifood_fin_conciliacao_estado", { p_competencia: comp, p_estado: "erro", p_erro: "Arquivo grande demais para guardar (" + Math.round(guardar.length / 1048576) + " MB). Baixe pelo Portal do Parceiro." });
    return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_erro: "arquivo grande demais" });
  }
  const resumo = resumirCsv(texto);
  await d.rpc("ifood_fin_conciliacao_pronta", { p_competencia: comp, p_b64: b64(guardar), p_linhas: resumo.linhas, p_resumo: resumo });
  await d.rpc("ifood_fin_consulta", { p_api: "conciliacao", p_ok: true, p_status: 200, p_qtd: resumo.linhas });
  return d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "ok", p_status: 200 });
}

// Chamado a cada rodada do ifood-sync. Nunca derruba o ciclo (cada tarefa tem o próprio try).
export async function processarFinanceiro(d: Dep, cred: any, limite = 6, prazoMs = 20000) {
  const ini = Date.now();
  let pacote: any;
  try { pacote = await d.rpc("ifood_fin_proximas", { p_limite: limite }); } catch { return; }
  const tarefas: any[] = Array.isArray(pacote?.tarefas) ? pacote.tarefas : [];
  if (!tarefas.length) return;
  const rotas: Record<string, string> = { ...(pacote?.rotas || {}) };
  let conferir = false;
  for (const t of tarefas) {
    if (Date.now() - ini > prazoMs) break;
    try {
      if (t.api === "vendas") await vendas(d, cred, rotas, t);
      else if (t.api === "eventos") { await eventos(d, cred, rotas, t); conferir = true; }
      else if (t.api === "repasses") { await repasses(d, cred, rotas, t); conferir = true; }
      else if (t.api === "antecipacoes") await antecipacoes(d, cred, rotas, t);
      else if (t.api === "conciliacao_pedir") await conciliacaoPedir(d, cred, rotas, t);
      else if (t.api === "conciliacao_status") await conciliacaoStatus(d, cred, rotas, t);
      else await d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: "erro", p_erro: "tarefa desconhecida" });
    } catch (e) {
      try { await d.rpc("ifood_fin_tarefa_fim", { p_id: t.id, p_estado: (t.tentativas || 0) < 6 ? "pendente" : "erro", p_erro: "Erro interno: " + String(e).slice(0, 200), p_espera_seg: 120 }); } catch { /* sem registro */ }
    }
  }
  if (conferir) { try { await d.rpc("ifood_fin_alertar_semanas"); } catch { /* só aviso */ } }
}
