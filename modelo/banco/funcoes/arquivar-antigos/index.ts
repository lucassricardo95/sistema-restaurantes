import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS, json, svcClient, autorizar, cfg, URL_ } from "./auth.ts";
const SHEETS_MAIN = await cfg("SHEETS_MAIN_URL");
const CHAVE_SERVIDOR = await cfg("PRINCIPAL_CHAVE_SERVIDOR");
const PUBLISHABLE = await cfg("SB_PUBLISHABLE_KEY");
const BUCKET = "arquivo";

// ação manual (botão do Admin): senha SEMPRE, inclusive para o Admin
async function senhaOk(req: Request, senha: unknown) {
  if (!String(senha || "").trim()) return false;   // senha vazia nunca vale
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const cli = createClient(URL_, PUBLISHABLE, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data, error } = await cli.rpc("api_verificar_senha_admin", { p: { senha: String(senha || "") } });
  return !error && !!data?.ok;
}

/* =====================================================================
   v1.15 (P-08) — caminho dos dados antigos:  banco → Storage → planilha
   - Por idade (diário) e na emergência do banco (95%): vendas e caixas encerrados vão para o STORAGE
     (arquivo .json.gz por mês e lote). Só saem do banco depois de o arquivo ser LIDO DE VOLTA e a
     contagem bater. Se o Storage falhar, usa o caminho antigo (direto para a planilha), com a mesma conferência.
   - Proteção do Storage (a cada hora): a partir de 95% do limite, o arquivo MAIS ANTIGO vai para a planilha
     (1 por rodada, no máximo 1 rodada por hora) e só sai do Storage depois de a planilha confirmar a contagem.
     Para quando cair abaixo de 80%. Avisos ao Admin em 70% e 85%.
   - Autoteste mensal com dados de TESTE (Storage e planilha, ida e volta) e cópia mensal do resumo na planilha.
   ===================================================================== */

async function planilha(corpo: any, ms = 60000) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), ms);
  try {
    const r = await fetch(SHEETS_MAIN, { method: "POST", headers: { "Content-Type": "text/plain" },
      body: JSON.stringify({ action: "arquivar", chave: CHAVE_SERVIDOR, ...corpo }), signal: ctl.signal });
    const j = await r.json();
    // a planilha informa quantas células já reserva (limite do Google: 10 milhões); o banco guarda e avisa o Admin a partir de 80%
    if (j?.celulas) { try { await svcClient().rpc("api_planilha_uso_registrar", { p_celulas: Number(j.celulas) }); } catch { /* segue */ } }
    return j;
  } finally { clearTimeout(t); }
}

/* ---------- Storage: gravar, ler de volta, apagar ---------- */
async function gz(obj: unknown): Promise<Uint8Array> {
  const s = new Blob([JSON.stringify(obj)]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
async function ungz(b: Blob): Promise<any> {
  const s = b.stream().pipeThrough(new DecompressionStream("gzip"));
  return JSON.parse(await new Response(s).text());
}
function b64(u: Uint8Array) { let s = ""; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); }
const mesSP = (iso: string) => new Date(iso).toLocaleString("sv-SE", { timeZone: "America/Sao_Paulo" }).slice(0, 7);

async function gravarConferido(svc: any, tipo: "vendas" | "caixa", mes: string, payload: any, qtd: number, chave: string) {
  const caminho = `${tipo}/${mes}/${new Date().toISOString().replace(/[:.]/g, "-")}-${crypto.randomUUID().slice(0, 8)}.json.gz`;
  const bytes = await gz({ tipo, mes, versao: 1, ...payload });
  const up = await svc.storage.from(BUCKET).upload(caminho, bytes, { contentType: "application/gzip", upsert: false });
  if (up.error) throw new Error("Storage recusou o arquivo: " + up.error.message);
  // lê de volta e confere a contagem antes de qualquer coisa sair do banco
  const dl = await svc.storage.from(BUCKET).download(caminho);
  if (dl.error || !dl.data) { await svc.storage.from(BUCKET).remove([caminho]); throw new Error("Não foi possível ler de volta o arquivo gravado."); }
  const volta = await ungz(dl.data);
  if (!Array.isArray(volta?.[chave]) || volta[chave].length !== qtd) { await svc.storage.from(BUCKET).remove([caminho]); throw new Error("Arquivo gravado com contagem diferente (descartado)."); }
  const { error } = await svc.from("arquivo_mapa").insert({ tipo, mes, local: "storage", caminho, qtd, bytes: bytes.length });
  if (error) { await svc.storage.from(BUCKET).remove([caminho]); throw new Error("Não foi possível registrar o arquivo no mapa: " + error.message); }
  return caminho;
}

// Lote de vendas → Storage (um arquivo por mês do lote). Só confirma (apaga do banco) se TODOS os meses gravaram e conferiram.
async function loteVendasStorage(svc: any, l: any) {
  const porMes: Record<string, any> = {};
  const mesDe: Record<string, string> = {};
  for (const v of l.vendas || []) { const m = mesSP(v.data_hora); mesDe[v.id] = m; (porMes[m] ||= { vendas: [], itens: [], pagamentos: [] }).vendas.push(v); }
  for (const i of l.itens || []) { const m = mesDe[i.venda_id]; if (m) porMes[m].itens.push(i); }
  for (const p of l.pagamentos || []) { const m = mesDe[p.venda_id]; if (m) porMes[m].pagamentos.push(p); }
  const feitos: string[] = [];
  try {
    for (const [m, pl] of Object.entries(porMes)) feitos.push(await gravarConferido(svc, "vendas", m, pl, (pl as any).vendas.length, "vendas"));
  } catch (e) {
    await desfazer(svc, feitos);
    throw e;
  }
  return feitos;
}
async function loteCaixaStorage(svc: any, l: any) {
  const porMes: Record<string, any> = {};
  for (const c of l.caixas || []) { const m = mesSP(c.abertura); (porMes[m] ||= { caixas: [], sangrias: [] }).caixas.push(c); }
  const caixaMes: Record<string, string> = {}; for (const c of l.caixas || []) caixaMes[c.id] = mesSP(c.abertura);
  for (const s of l.sangrias || []) { const m = caixaMes[s.sessao_id] || caixaMes[s.caixa_id] || mesSP(s.data_hora); (porMes[m] ||= { caixas: [], sangrias: [] }).sangrias.push(s); }
  const feitos: string[] = [];
  try {
    for (const [m, pl] of Object.entries(porMes)) feitos.push(await gravarConferido(svc, "caixa", m, pl, (pl as any).caixas.length, "caixas"));
  } catch (e) {
    await desfazer(svc, feitos);
    throw e;
  }
  return feitos;
}

// tira do Storage e do mapa os arquivos de um lote que NÃO saiu do banco (a remoção do banco é tudo-ou-nada: falhou = nada saiu)
async function desfazer(svc: any, caminhos: string[]) {
  if (!caminhos.length) return;
  try { await svc.storage.from(BUCKET).remove(caminhos); } catch { /* segue */ }
  try { await svc.from("arquivo_mapa").delete().in("caminho", caminhos); } catch { /* segue */ }
}
// Envia lotes e SÓ remove do Supabase o que o destino confirmou. Destino: Storage; se o Storage falhar, planilha (caminho antigo).
async function arquivarFaixa(svc: any, dias: number, minDias: number, orcamento: { vendas: number; caixas: number }, res: any) {
  for (; orcamento.vendas > 0 && !res.erro; orcamento.vendas--) {
    const { data: l } = await svc.rpc("api_arquivar_lote_vendas", { p_dias: dias, p_limite: 200, p_min_dias: minDias });
    if (!l?.ids?.length) break;
    let ok = false;
    let caminhos: string[] = [];
    try { caminhos = await loteVendasStorage(svc, l); res.arquivos += caminhos.length; res.destino = "storage"; ok = true; }
    catch (e) { res.avisoStorage = (e as Error).message; }
    if (!ok) {
      const j = await planilha({ tipo: "vendas", vendas: l.vendas, itens: l.itens, pagamentos: l.pagamentos });
      if (!j?.ok || j.recebidas !== l.ids.length) { res.erro = "Storage e planilha não confirmaram: " + (res.avisoStorage || "") + " / " + (j?.message || "contagem diferente"); break; }
      res.destino = "planilha";
    }
    const { data: r, error: re } = await svc.rpc("api_arquivar_confirmar_vendas", { p_ids: l.ids });
    if (re || !r?.ok) { await desfazer(svc, caminhos); res.erro = (re?.message || r?.message || "Falha ao remover") + " (nada saiu do banco; o arquivo deste lote foi desfeito)"; break; }
    res.vendas += r.removidos;
  }
  for (; orcamento.caixas > 0 && !res.erro; orcamento.caixas--) {
    const { data: l } = await svc.rpc("api_arquivar_lote_caixa", { p_dias: dias, p_limite: 100, p_min_dias: minDias });
    if (!l?.ids?.length) break;
    let ok = false;
    let caminhos: string[] = [];
    try { caminhos = await loteCaixaStorage(svc, l); res.arquivos += caminhos.length; res.destino = "storage"; ok = true; }
    catch (e) { res.avisoStorage = (e as Error).message; }
    if (!ok) {
      const j = await planilha({ tipo: "caixa", caixas: l.caixas, sangrias: l.sangrias });
      if (!j?.ok || j.recebidas !== l.ids.length) { res.erro = "Storage e planilha não confirmaram: " + (res.avisoStorage || "") + " / " + (j?.message || "contagem diferente"); break; }
      res.destino = "planilha";
    }
    const { data: r, error: re } = await svc.rpc("api_arquivar_confirmar_caixa", { p_ids: l.ids });
    if (re || !r?.ok) { await desfazer(svc, caminhos); res.erro = (re?.message || r?.message || "Falha ao remover") + " (nada saiu do banco; o arquivo deste lote foi desfeito)"; break; }
    res.caixas += r.removidos;
  }
}

// LGPD: apaga os dados pessoais de quem foi anonimizado — na planilha e nos arquivos do Storage.
const LIMPAR = { cliente_nome: "Cliente anonimizado", telefone_cliente: "", endereco: "", complemento: "", referencia: "", observacoes_entrega: "", cpf_nota: "", preferencias_cliente: "" };
async function anonimizarStorage(svc: any, itens: { telefone: string; clienteId: string }[]) {
  const alvos = itens.map((x) => ({ tel: String(x.telefone || "").replace(/\D/g, ""), cid: String(x.clienteId || "") }));
  const doCliente = (v: any) => alvos.some((a) => (a.tel.length >= 8 && String(v.telefone_cliente || "").replace(/\D/g, "") === a.tel) || (!!a.cid && v.cliente_id === a.cid));
  let n = 0;
  const { data: arqs, error } = await svc.from("arquivo_mapa").select("id,caminho").eq("tipo", "vendas").eq("local", "storage");
  if (error) throw new Error("mapa: " + error.message);
  for (const a of arqs || []) {   // cada arquivo é aberto UMA vez para todos os clientes da fila
    const dl = await svc.storage.from(BUCKET).download(a.caminho); if (dl.error || !dl.data) throw new Error("não leu " + a.caminho);
    const o = await ungz(dl.data); let mudou = false;
    for (const v of o.vendas || []) if (doCliente(v)) { Object.assign(v, LIMPAR); mudou = true; n++; }
    if (mudou) {
      const bytes = await gz(o);
      const up = await svc.storage.from(BUCKET).update(a.caminho, bytes, { contentType: "application/gzip", upsert: true });
      if (up.error) throw new Error("não regravou " + a.caminho);
      await svc.from("arquivo_mapa").update({ bytes: bytes.length }).eq("id", a.id);
    }
  }
  return n;
}
async function processarAnonimizacoes(svc: any) {
  const out = { feitas: 0, pendentes: 0, erro: "" as string };
  try {
    const { data: fila } = await svc.from("anonimizar_arquivo_fila").select("id,telefone,cliente_id,tentativas").is("feito_em", null).order("id").limit(25);
    const itens = (fila || []).map((it: any) => ({ telefone: it.telefone || "", clienteId: it.cliente_id || "" }));
    if (itens.length) {
      let ok = false;
      try {
        const j = await planilha({ action: "sbAnonimizarArquivo", lista: itens, telefone: itens[0].telefone, clienteId: itens[0].clienteId }, 120000);
        if (!j?.ok) throw new Error("planilha: " + (j?.message || "não confirmou"));
        await anonimizarStorage(svc, itens);
        ok = true;
      } catch (e) { out.erro = (e as Error).message; }
      for (const it of fila || []) {
        if (ok) { await svc.from("anonimizar_arquivo_fila").update({ feito_em: new Date().toISOString() }).eq("id", it.id); out.feitas++; }
        else {
          await svc.from("anonimizar_arquivo_fila").update({ tentativas: (it.tentativas || 0) + 1 }).eq("id", it.id);
          if ((it.tentativas || 0) + 1 === 5) {   // nada falha calado: avisa o Admin na 5ª tentativa sem sucesso
            try { await svc.rpc("api_push_admins_servico", { p_titulo: "LGPD: anonimização do arquivo não concluída", p_corpo: "Há cliente anonimizado cujos pedidos antigos ainda não foram limpos no arquivo (5 tentativas). Motivo: " + out.erro.slice(0, 150), p_tag: "arquivo-lgpd" }); } catch { /* segue */ }
          }
        }
      }
    }
    const { count } = await svc.from("anonimizar_arquivo_fila").select("id", { count: "exact", head: true }).is("feito_em", null);
    out.pendentes = count || 0;
  } catch (e) { out.erro = (e as Error).message; }
  return out;
}

/* ---------- Proteção do Storage: 95% → o arquivo mais antigo vai para a planilha ---------- */
async function moverMaisAntigoParaPlanilha(svc: any) {
  const { data: a } = await svc.from("arquivo_mapa").select("*").eq("local", "storage").order("mes").order("criado_em").limit(1).maybeSingle();
  if (!a) return { movido: false, motivo: "Nenhum arquivo no Storage." };
  const dl = await svc.storage.from(BUCKET).download(a.caminho);
  if (dl.error || !dl.data) throw new Error("Não foi possível ler " + a.caminho + " do Storage.");
  const bytes = new Uint8Array(await dl.data.arrayBuffer());
  const j = await planilha({ action: "sbGuardarBloco", tipo: a.tipo, mes: a.mes, caminho: a.caminho, qtd: a.qtd, gzBase64: b64(bytes) }, 120000);
  if (!j?.ok || Number(j.qtd) !== Number(a.qtd)) throw new Error("A planilha não confirmou o arquivo " + a.caminho + ": " + (j?.message || "contagem diferente") + ". Ele continua no Storage.");
  // primeiro o mapa (a partir daqui os relatórios leem da planilha); depois apaga do Storage
  const up = await svc.from("arquivo_mapa").update({ local: "planilha", movido_em: new Date().toISOString() }).eq("id", a.id);
  if (up.error) throw new Error("A planilha recebeu " + a.caminho + ", mas o mapa não foi atualizado (" + up.error.message + "). O arquivo continua no Storage; a próxima rodada não duplica na planilha.");
  const rm = await svc.storage.from(BUCKET).remove([a.caminho]);
  if (rm.error) throw new Error("O arquivo " + a.caminho + " já está na planilha, mas o Storage não o apagou (" + rm.error.message + "): o espaço não foi liberado.");
  return { movido: true, caminho: a.caminho, qtd: a.qtd, bytes: a.bytes };
}

/* ---------- Autoteste: Storage e planilha, ida e volta, com dados de TESTE (nada real é tocado) ---------- */
async function autoteste(svc: any) {
  const passos: string[] = []; let falhou = "";
  const caminho = `teste/autoteste-${Date.now()}.json.gz`;
  try {
    const dados = { vendas: [{ id: "TESTE-1", valor_total: 1.23 }, { id: "TESTE-2", valor_total: 4.56 }] };
    const bytes = await gz(dados);
    const up = await svc.storage.from(BUCKET).upload(caminho, bytes, { contentType: "application/gzip" });
    if (up.error) throw new Error("Storage não gravou: " + up.error.message);
    const dl = await svc.storage.from(BUCKET).download(caminho);
    const volta = dl.data ? await ungz(dl.data) : null;
    if (volta?.vendas?.length !== 2) throw new Error("Storage não devolveu o que gravou.");
    passos.push("✔ Storage: gravou e leu de volta");
    const j = await planilha({ action: "sbGuardarBloco", tipo: "teste", mes: "2000-01", caminho, qtd: 2, gzBase64: b64(bytes), chaveContagem: "vendas" }, 120000);
    if (!j?.ok || Number(j.qtd) !== 2) throw new Error("Planilha não confirmou o bloco de teste: " + (j?.message || "contagem diferente"));
    passos.push("✔ Planilha: recebeu e conferiu o bloco de teste");
    const ap = await planilha({ action: "sbApagarBlocoTeste", caminho });
    if (!ap?.ok) throw new Error("Planilha não apagou o bloco de teste.");
    passos.push("✔ Planilha: apagou o bloco de teste");
  } catch (e) { falhou = (e as Error).message; }
  try { await svc.storage.from(BUCKET).remove([caminho]); } catch { /* segue */ }
  if (falhou) {
    try { await svc.rpc("api_push_admins_servico", { p_titulo: "Autoteste do arquivo FALHOU", p_corpo: falhou + " Veja Administrador → Sistema → Armazenamento.", p_tag: "arquivo-autoteste" }); } catch { /* segue */ }
  }
  return { ok: !falhou, passos, erro: falhou || null };
}
async function resumoMensal(svc: any) {
  const d = new Date(); const ant = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - 1, 15));
  const mes = ant.toISOString().slice(0, 7);
  const { data: r } = await svc.rpc("api_resumo_mes_servico", { p_mes: mes });
  if (!r?.ok) return { ok: false, message: r?.message || "Resumo indisponível." };
  const j = await planilha({ action: "sbResumoMensal", mes, dias: r.dias });
  return { ok: !!j?.ok, mes, dias: (r.dias || []).length, message: j?.message };
}

async function registrar(svc: any, linha: Record<string, unknown>) { try { await svc.from("arquivo_execucoes").insert(linha); } catch { /* segue */ } }
async function dbBytes(svc: any) { try { const { data } = await svc.rpc("api_espaco_percentual_servico"); return data; } catch { return null; } }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  const t0 = Date.now();
  try {
    const svc = svcClient();
    const corpo = await req.json().catch(() => ({}));
    if (!a.servico && (corpo.manual === true || corpo.storageAgora === true || corpo.autoteste === true) && !(await senhaOk(req, corpo.senha)))
      return json({ ok: false, message: "Senha incorreta. Nada foi movido." });
    const { data: conf } = await svc.from("backup_config").select("arquivar_ativo,arquivar_dias,arquivar_emerg_ultimo").eq("id", true).single();
    const tamanho = async () => { try { const { data } = await svc.rpc("api_espaco_tamanho_servico"); return Number(data) || null; } catch { return null; } };

    // ---- AUTOTESTE MENSAL e CÓPIA MENSAL DO RESUMO ----
    if (corpo.autoteste === true || corpo.resumoMensal === true) {
      const out: any = {};
      if (corpo.autoteste === true) { out.autoteste = await autoteste(svc); await registrar(svc, { gatilho: "autoteste", origem: "teste", destino: "storage → planilha", erro: out.autoteste.erro, ms: Date.now() - t0 }); }
      if (corpo.resumoMensal === true) { out.resumo = await resumoMensal(svc); await registrar(svc, { gatilho: "resumo", origem: "banco", destino: "planilha", qtd: out.resumo.dias || 0, erro: out.resumo.ok ? null : (out.resumo.message || "falhou"), ms: Date.now() - t0 }); }
      return json({ ok: (!out.autoteste || out.autoteste.ok) && (!out.resumo || out.resumo.ok), ...out });
    }

    // ---- PROTEÇÃO DO STORAGE (a cada hora) ----
    if (corpo.storage === true || corpo.storageAgora === true) {
      try { await svc.rpc("api_storage_alerta_servico"); } catch { /* segue */ }
      const { data: pct } = await svc.rpc("api_storage_percentual_servico");
      const agora = corpo.storageAgora === true && !a.servico;   // botão "mandar o mais antigo agora" (Admin): uma rodada, mesmo abaixo de 95%
      const { data: ult } = await svc.from("arquivo_execucoes").select("em").eq("gatilho", "storage95").order("em", { ascending: false }).limit(1).maybeSingle();
      // passou de 95%: manda 1 arquivo por hora até voltar a 80% (sequência recente = rodou nas últimas 3 h)
      const emSequencia = !!ult && Date.now() - new Date(ult.em).getTime() < 3 * 3600000;
      if (!agora && Number(pct) < 95 && !(emSequencia && Number(pct) >= 80)) return json({ ok: true, message: `Storage em ${pct}%.`, pct });
      if (!agora && ult && Date.now() - new Date(ult.em).getTime() < 50 * 60000) return json({ ok: true, message: "Proteção do Storage já rodou há menos de 50 min.", pct });
      let r: any, erro: string | null = null;
      try { r = await moverMaisAntigoParaPlanilha(svc); } catch (e) { erro = (e as Error).message; }
      await registrar(svc, { gatilho: agora ? "manual" : "storage95", origem: "storage", destino: "planilha", qtd: r?.qtd || 0, arquivos: r?.movido ? 1 : 0, erro, ms: Date.now() - t0 });
      if (erro) { try { await svc.rpc("api_push_admins_servico", { p_titulo: "Arquivo: Storage cheio e a planilha não recebeu", p_corpo: erro, p_tag: "arquivo-storage-erro" }); } catch { /* segue */ } }
      return json({ ok: !erro, message: erro || (r?.movido ? `Arquivo ${r.caminho} (${r.qtd} registro(s)) foi para a planilha.` : r?.motivo), pct, ...r });
    }

    // ---- GATILHO DE EMERGÊNCIA: banco perto do limite -> arquiva do mais antigo para o mais novo, até 1 dia atrás ----
    // Só vendas ENCERRADAS (pagas e entregues, ou canceladas) e caixas FECHADOS entram; nada em andamento sai. O pedido de hoje fica.
    if (corpo.emergencia === true) {
      const { data: pct } = await svc.rpc("api_espaco_percentual_servico");
      const limite = 95;
      if (Number(pct) < limite) return json({ ok: true, message: `Uso em ${pct}%, abaixo de ${limite}%.`, pct });
      const ult = conf?.arquivar_emerg_ultimo ? new Date(conf.arquivar_emerg_ultimo).getTime() : 0;
      if (Date.now() - ult < 50 * 60000) return json({ ok: true, message: "Emergência já rodou há menos de 50 min.", pct });
      await svc.from("backup_config").update({ arquivar_emerg_ultimo: new Date().toISOString() }).eq("id", true);
      const antes = await tamanho();
      const res = { vendas: 0, caixas: 0, arquivos: 0, destino: "", pctAntes: Number(pct), limite, erro: null as string | null, avisoStorage: "" };
      const orc = { vendas: 5, caixas: 5 };   // rodadas pequenas: no máx. 1.000 vendas e 500 caixas por hora (do mais antigo para o mais novo)
      for (const dias of [30, 14, 7, 3, 1]) { if (res.erro || (orc.vendas <= 0 && orc.caixas <= 0)) break; await arquivarFaixa(svc, dias, 1, orc, res); }
      await svc.from("auditoria").insert({ usuario_login: "sistema", acao: "Arquivamento de emergência (" + limite + "%)", detalhes: JSON.stringify(res) });
      await registrar(svc, { gatilho: "banco95", origem: "banco", destino: res.destino || "storage", qtd: res.vendas + res.caixas, arquivos: res.arquivos, erro: res.erro, ms: Date.now() - t0, db_bytes_antes: antes });
      return json({ ok: !res.erro, message: res.erro || `Uso em ${pct}%: ${res.vendas} venda(s) e ${res.caixas} caixa(s) arquivados (${res.destino || "nada a mover"}). O espaço volta depois da compactação das 05:30.`, ...res });
    }

    const anon = await processarAnonimizacoes(svc);   // LGPD roda todo dia, mesmo com o arquivamento por idade desligado

    // ---- arquivamento normal (por idade) ----
    const manual = !a.servico && corpo.manual === true;
    if (!manual && !conf?.arquivar_ativo) return json({ ok: true, message: "Arquivamento desligado.", anonimizacao: anon });
    const pedido = manual ? Number(corpo.dias) : NaN;
    const dias = Math.max(30, Number.isFinite(pedido) && pedido > 0 ? pedido : (conf?.arquivar_dias ?? 90));   // trava: nunca arquiva o que tem menos de 30 dias
    const antes = await tamanho();
    const res = { vendas: 0, caixas: 0, arquivos: 0, destino: "", dias, manual, anonimizacao: anon, erro: null as string | null, avisoStorage: "" };
    await arquivarFaixa(svc, dias, 30, { vendas: 20, caixas: 20 }, res);
    await svc.from("auditoria").insert({ usuario_login: manual ? "admin (manual)" : "sistema", acao: manual ? "Arquivamento manual" : "Arquivamento automático", detalhes: JSON.stringify(res) });
    await registrar(svc, { gatilho: manual ? "manual" : "idade", origem: "banco", destino: res.destino || "storage", qtd: res.vendas + res.caixas, arquivos: res.arquivos, erro: res.erro, ms: Date.now() - t0, db_bytes_antes: antes });
    return json({ ok: !res.erro, message: res.erro || undefined, ...res });
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
