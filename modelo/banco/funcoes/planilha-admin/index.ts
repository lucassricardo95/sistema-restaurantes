import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS, json, autorizar, cfg, svcClient, URL_ } from "./auth.ts";
import * as AUTH_ from "./auth.ts";
// Primeiro o Drive direto (função drive-direto, OAuth); se ela não puder, devolve null e segue a planilha (Apps Script).
async function tentarDireto(corpo: Record<string, unknown>): Promise<any | null> {
  try {
    const r = await fetch(`${AUTH_.URL_}/functions/v1/drive-direto`, { method: "POST", headers: { Authorization: `Bearer ${AUTH_.CHAVE_SERVICO}`, "Content-Type": "application/json" }, body: JSON.stringify(corpo), signal: AbortSignal.timeout(125000) });
    const j = await r.json(); return j?.usado ? j.r : null;
  } catch { return null; }
}
// Primeiro o Drive direto (OAuth, rápido); se não der, a planilha (Apps Script) como segundo caminho.
// "Arquivos do sistema" (tamanho da planilha) só o Apps Script sabe medir: o último valor fica guardado em sistema.ARMAZ_ARQ_SISTEMA e é renovado em segundo plano (a cada 12 h).
async function guardarArqSistema(r: any) {
  try {
    const b = Number(r?.categorias?.["Arquivos do sistema"]?.bytes || 0); if (!(b > 0)) return;
    const f = (r.arquivos || []).find((x: any) => x.categoria === "Arquivos do sistema");
    await svcClient().from("sistema").upsert({ chave: "ARMAZ_ARQ_SISTEMA", valor: { bytes: b, nome: String(f?.nome || "Planilha principal").replace(/ \(planilha principal\)$/, ""), criadoEm: f?.criadoEm || null, em: new Date().toISOString() }, atualizado_em: new Date().toISOString() });
  } catch { /* cache é só um atalho */ }
}
async function planilha(corpo: Record<string, unknown>, ms?: number) {
  if (corpo.action === "sbArmazenamento") {
    const { data: c } = await svcClient().from("sistema").select("valor").eq("chave", "ARMAZ_ARQ_SISTEMA").maybeSingle();
    const em = (c?.valor as any)?.em ? new Date((c!.valor as any).em).getTime() : 0;
    if (em) {
      const d = await tentarDireto(corpo);
      if (d) {
        if (Date.now() - em > 12 * 3600000) { try { (globalThis as any).EdgeRuntime?.waitUntil((async () => { guardarArqSistema(await planilhaApps(corpo, 60000)); })()); } catch { /* ok */ } }
        return d;
      }
    }
    const r = await planilhaApps(corpo, ms); guardarArqSistema(r); return r;
  }
  const d = await tentarDireto(corpo);
  return d ?? await planilhaApps(corpo, ms);
}
const SHEETS_MAIN = await cfg("SHEETS_MAIN_URL");
const CHAVE_SERVIDOR = await cfg("PRINCIPAL_CHAVE_SERVIDOR");
const PUBLISHABLE = await cfg("SB_PUBLISHABLE_KEY");

// Ponte entre o app (usuário logado) e o Apps Script da planilha principal: espaço do Drive, espelho,
// vendas da contingência, meses arquivados e chave de leitura da reserva. As chaves da contingência ficam no Apps Script.
async function planilhaApps(corpo: Record<string, unknown>, ms = 30000) {
  const ctl = new AbortController(); const timer = setTimeout(() => ctl.abort(), ms);
  try {
    const r = await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
      body: JSON.stringify({ chave: CHAVE_SERVIDOR, ...corpo }), signal: ctl.signal });
    const raw = await r.text(); let j: any;
    try { j = JSON.parse(raw); } catch { throw new Error(`Planilha respondeu conteúdo inválido (HTTP ${r.status}).`); }
    if (!r.ok) throw new Error(`Planilha respondeu HTTP ${r.status}.`);
    return j;
  } catch (e) {
    if ((e as Error)?.name === "AbortError") throw new Error(`Tempo esgotado aguardando a planilha (${Math.round(ms / 1000)} s); tente novamente. Nada foi marcado como concluído.`);
    throw e;
  } finally { clearTimeout(timer); }
}

/* v1.15 (P-08): meses antigos agora podem estar em 3 lugares — abas Arquivo_* e blocos da planilha (a planilha junta os dois)
   e arquivos .json.gz no Storage do Supabase (bucket "arquivo"). Aqui junta o Storage, sem repetir id. */
async function ungz(b: Blob): Promise<any> {
  const s = b.stream().pipeThrough(new DecompressionStream("gzip"));
  return JSON.parse(await new Response(s).text());
}
async function arquivosStorage(tipo: "vendas" | "caixa", mes?: string) {
  const svc = svcClient();
  let q = svc.from("arquivo_mapa").select("caminho").eq("local", "storage").eq("tipo", tipo);
  if (mes) q = q.eq("mes", mes);
  // todas as páginas do mapa (antes parava em 500 e o histórico do cliente ficava incompleto sem avisar)
  const data: any[] = [];
  for (let de = 0; ; de += 1000) {
    const { data: pag, error } = await q.order("criado_em").range(de, de + 999);
    if (error) throw new Error("Não foi possível ler o mapa do arquivo no Storage: " + error.message);
    data.push(...(pag || []));
    if (!pag || pag.length < 1000) break;
  }
  const out: any[] = [];
  for (const a of data) {
    const dl = await svc.storage.from("arquivo").download(a.caminho);
    if (dl.error || !dl.data) throw new Error("Não foi possível abrir " + a.caminho + " do Storage. O relatório ficaria incompleto; tente de novo.");
    out.push(await ungz(dl.data));
  }
  return out;
}
const arr = (x: any) => (Array.isArray(x) ? x : []);
function juntarVendas(r: any, arqs: any[], filtro?: (v: any) => boolean) {
  r.vendas = arr(r.vendas); r.itens = arr(r.itens); r.pagamentos = arr(r.pagamentos);
  const vistos = new Set(r.vendas.map((v: any) => String(v.id)));
  for (const o of arqs) {
    const novos = new Set<string>();
    for (const v of arr(o.vendas)) { const id = String(v.id); if (vistos.has(id) || (filtro && !filtro(v))) continue; vistos.add(id); novos.add(id); r.vendas.push(v); }
    for (const i of arr(o.itens)) if (novos.has(String(i.venda_id))) r.itens.push({ ...i, adicionais_ids: Array.isArray(i.adicionais_ids) ? i.adicionais_ids : [] });
    for (const p of arr(o.pagamentos)) if (novos.has(String(p.venda_id))) r.pagamentos.push(p);
  }
  return r;
}
function juntarCaixa(r: any, arqs: any[]) {
  r.caixas = arr(r.caixas); r.sangrias = arr(r.sangrias);
  const vc = new Set(r.caixas.map((c: any) => String(c.id))), vs = new Set(r.sangrias.map((x: any) => String(x.id)));
  for (const o of arqs) {
    for (const c of arr(o.caixas)) if (!vc.has(String(c.id))) { vc.add(String(c.id)); r.caixas.push(c); }
    for (const x of arr(o.sangrias)) if (!vs.has(String(x.id))) { vs.add(String(x.id)); r.sangrias.push(x); }
  }
  return r;
}

const TODOS = ["Admin", "Operador", "Garçom", "Cozinha", "Entregador"];
const ACOES: Record<string, { niveis: string[]; action: string }> = {
  armazenamento:            { niveis: ["Admin"], action: "sbArmazenamento" },
  armazenamentoContingencia:{ niveis: ["Admin"], action: "sbArmazenamentoContingencia" },
  sincronizarContingencia:  { niveis: ["Admin"], action: "sbSincronizarContingencia" },
  chaveContingencia:        { niveis: ["Admin", "Operador"], action: "sbChaveContingencia" },
  arquivoVendas:            { niveis: ["Admin", "Operador"], action: "sbLerArquivo" },
  arquivoCaixa:             { niveis: ["Admin", "Operador"], action: "sbLerArquivoCaixa" },
  arquivoCliente:           { niveis: ["Admin", "Operador"], action: "sbLerArquivoCliente" },   // todas as vendas arquivadas de um cliente (telefone e/ou id)   // D17: caixas fechados e sangrias arquivados
  arquivoContagem:          { niveis: ["Admin", "Operador"], action: "sbContarArquivo" },   // Fase 3.3: quantos pedidos há na planilha (conferência)
  chaveLeitura:             { niveis: TODOS, action: "sbChaveLeitura" },
  celulasArquivos:          { niveis: ["Admin"], action: "sbCelulasArquivos" },   // v1.15: células da principal e de cada arquivo anual (tela Armazenamento)   // chave só de consulta da reserva (não enfileira venda)
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const corpo = await req.json().catch(() => ({}));
    const acao = String(corpo.acao || "");
    const simples = ACOES[acao];
    const FOTOS = ["fotosAnalisar", "fotosLimpar", "fotosRestaurar"];
    const niveis = simples ? simples.niveis : ((acao === "reconciliarContingencia" || FOTOS.includes(acao)) ? ["Admin"] : null);
    if (!niveis) return json({ ok: false, message: "Ação desconhecida." }, 400);
    const a = await autorizar(req, niveis);
    if (!a.ok) return json({ ok: false, message: a.message }, a.status);

    if (simples) {
      const usaMes = acao === "arquivoVendas" || acao === "arquivoCaixa";
      const mes = usaMes ? String(corpo.mes || "") : undefined;
      if (usaMes && !/^\d{4}-(0[1-9]|1[0-2])$/.test(mes!)) return json({ ok: false, message: "Mês inválido." }, 400);
      const extra = acao === "arquivoCliente" ? { telefone: String(corpo.telefone || "").replace(/\D/g, ""), clienteId: String(corpo.clienteId || "") } : {};
      // o arquivo guarda só os ids de quem registrou/entregou/abriu o caixa: devolve os logins para o app montar o relatório.
      // A lista de logins é pedida AO MESMO TEMPO que a planilha responde (antes esperava uma e depois a outra).
      const precisaLogins = acao === "arquivoVendas" || acao === "arquivoCliente" || acao === "arquivoCaixa";
      const loginsP: any = precisaLogins ? svcClient().from("usuarios").select("id,login") : null;
      let r: any, us: any;
      try { [r, us] = await Promise.all([planilha({ action: simples.action, mes, rapido: corpo.rapido === true, renovar: corpo.renovar === true, ...extra }, acao === "celulasArquivos" ? 85000 : 30000), loginsP]); }
      catch (e) { if (acao === "celulasArquivos") return json({ ok: false, message: "A planilha não respondeu a contagem de células: " + (e as Error).message }); throw e; }
      if (r?.ok) {
        if (acao === "arquivoVendas") juntarVendas(r, await arquivosStorage("vendas", mes));
        else if (acao === "arquivoCaixa") juntarCaixa(r, await arquivosStorage("caixa", mes));
        else if (acao === "arquivoCliente") {
          const tel = String(extra.telefone || ""), cid = String(extra.clienteId || "");
          juntarVendas(r, await arquivosStorage("vendas"), (v) => (tel.length >= 8 && String(v.telefone_cliente || "").replace(/\D/g, "") === tel) || (!!cid && v.cliente_id === cid));
        } else if (acao === "arquivoContagem") {
          const { data: m, error: me } = await svcClient().from("arquivo_mapa").select("qtd").eq("local", "storage").eq("tipo", "vendas");
          if (me) return json({ ok: false, message: "Não foi possível contar o arquivo do Storage: " + me.message });
          const noStorage = (m || []).reduce((t: number, x: any) => t + (Number(x.qtd) || 0), 0);
          r.pedidosPlanilha = r.pedidos; r.pedidosStorage = noStorage; r.pedidos = (Number(r.pedidos) || 0) + noStorage;
        }
      }
      if (precisaLogins && r?.ok) r.logins = Object.fromEntries(((us?.data) || []).map((u: any) => [u.id, u.login]));
      return json(r);
    }

    if (a.servico) return json({ ok: false, message: "Use o app logado como Admin." }, 403);
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const cli = createClient(URL_, PUBLISHABLE, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });

    // ---- P-12 (v1.15): fotos sem uso no Drive principal e no da contingência ----
    if (FOTOS.includes(acao)) {
      const svc = svcClient();
      if (acao !== "fotosAnalisar") {
        // ação sensível: senha sempre, inclusive para o Admin
        if (!String(corpo.senha || "").trim()) return json({ ok: false, message: "Digite a sua senha. Nada foi apagado." });
        const { data: sv, error: se } = await cli.rpc("api_verificar_senha_admin", { p: { senha: String(corpo.senha || "") } });
        if (se || !sv?.ok) return json({ ok: false, message: "Senha incorreta. Nada foi apagado." });
        const { data: bk } = await svc.from("backups").select("id").eq("status", "Em andamento").gte("data_hora", new Date(Date.now() - 3600000).toISOString()).limit(1);
        if (bk?.length) return json({ ok: false, message: "Há um backup em andamento. Tente a limpeza daqui a alguns minutos (nada foi apagado)." });
      }
      if (acao === "fotosRestaurar") {
        const r = await planilha({ action: "sbFotosRestaurar" }, 120000);
        if (r?.ok) await svc.from("auditoria").insert({ usuario_id: a.usuario?.id, perfil: a.usuario?.nivel, acao: "Fotos restauradas da lixeira do Drive", detalhes: String(r.restauradas ?? 0) + " foto(s)" });
        return json(r);
      }
      // lista COMPLETA das fotos em uso: produtos, combos e histórico de fotos. Se qualquer leitura falhar, para tudo.
      // lê as tabelas INTEIRAS em páginas de 1000 (o Supabase corta em 1000 linhas por consulta)
      const lerTudo = async (tabela: string, colunas: string): Promise<{ data: any[]; error: any }> => {
        const out: any[] = [];
        for (let ini = 0; ; ini += 1000) {
          const { data, error } = await svc.from(tabela).select(colunas).order("id").range(ini, ini + 999);
          if (error) return { data: [], error };
          out.push(...(data || []));
          if ((data || []).length < 1000) return { data: out, error: null };
          if (ini > 200000) return { data: [], error: new Error("tabela grande demais") };
        }
      };
      const [p1, p2, p3] = await Promise.all([
        lerTudo("produtos", "foto_id_principal,foto_id_contingencia"),
        lerTudo("combos", "foto_id_principal,foto_id_contingencia"),
        lerTudo("fotos_historico", "foto_id_antigo,foto_id_novo"),
      ]);
      if (p1.error || p2.error || p3.error) return json({ ok: false, message: "Não foi possível ler as fotos em uso no banco. Nada foi analisado nem apagado." });
      const emUso = new Set<string>(), emUsoCont = new Set<string>();
      for (const x of [...(p1.data || []), ...(p2.data || [])]) { if (x.foto_id_principal) emUso.add(x.foto_id_principal); if (x.foto_id_contingencia) emUsoCont.add(x.foto_id_contingencia); }
      for (const x of (p3.data || [])) { if (x.foto_id_antigo) emUso.add(x.foto_id_antigo); if (x.foto_id_novo) emUso.add(x.foto_id_novo); }
      if (!emUso.size) return json({ ok: false, message: "Nenhuma foto em uso foi encontrada no banco: por segurança, nada foi feito." });
      if (acao === "fotosAnalisar") return json(await planilha({ action: "sbFotosAnalisar", emUso: [...emUso], emUsoCont: [...emUsoCont] }, 140000));
      const ids = Array.isArray(corpo.ids) ? corpo.ids.map(String).slice(0, 200) : [];
      const idsCont = Array.isArray(corpo.idsCont) ? corpo.idsCont.map(String).slice(0, 200) : [];
      if (!ids.length && !idsCont.length) return json({ ok: false, message: "Nenhuma foto escolhida." });
      const r = await planilha({ action: "sbFotosLimpar", emUso: [...emUso], emUsoCont: [...emUsoCont], ids, idsCont }, 140000);
      if (r?.ok) await svc.from("auditoria").insert({ usuario_id: a.usuario?.id, perfil: a.usuario?.nivel, acao: "Limpeza de fotos sem uso (Drive)",
        detalhes: `principal: ${r.principal?.removidas ?? 0} foto(s); contingência: ${r.contingencia?.removidas ?? 0} foto(s)${r.contingencia?.erro ? " (erro: " + r.contingencia.erro + ")" : ""}` });
      return json(r);
    }

    // ---- reconciliarContingencia: busca a fila na contingência e lança cada venda no Supabase, como o Admin logado ----
    const lista = await planilha({ action: "sbListarPendentesContingencia" });
    if (!lista?.ok) return json({ ok: false, message: lista?.message || "Não foi possível ler a fila da contingência." });
    const pendentes: any[] = lista.pendentes || [];
    const res = { reaplicadas: 0, jaEstavam: 0, falhas: [] as string[], restantes: 0 };
    const paraMarcar: string[] = [];
    for (const item of pendentes.slice(0, 30)) {
      const id = String(item?.id || "");
      if (!id) continue;
      if (item.tipo !== "venda") { res.falhas.push(`${id}: tipo desconhecido (${item.tipo})`); continue; }
      if (item.corrompido || !item.dados || !item.dados.itens) { res.falhas.push(`${id}: dados ilegíveis na fila`); continue; }
      const { data, error } = await cli.rpc("api_reconciliar_venda_contingencia", { p: { idFila: id, dados: item.dados } });
      if (error) { res.falhas.push(`${id}: ${error.message}`); continue; }
      if (data?.ok) { paraMarcar.push(id); if (data.jaFeita || data.duplicado) res.jaEstavam++; else res.reaplicadas++; }
      else res.falhas.push(`${id}: ${data?.message || "recusada"}`);
    }
    res.restantes = Math.max(0, pendentes.length - 30);
    if (paraMarcar.length) {
      const m = await planilha({ action: "sbMarcarSincronizadoContingencia", ids: paraMarcar });
      if (m?.falhas?.length) res.falhas.push(`${m.falhas.length} venda(s) lançada(s) mas não marcadas na contingência (não duplicam se repetir)`);
    }
    const partes = [`${res.reaplicadas} venda(s) lançada(s)`, `${res.jaEstavam} já estavam no sistema`];
    if (res.falhas.length) partes.push(`${res.falhas.length} com problema`);
    if (res.restantes) partes.push(`${res.restantes} ainda na fila (rode de novo)`);
    return json({ ok: true, message: partes.join(" · ") + ".", ...res });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
