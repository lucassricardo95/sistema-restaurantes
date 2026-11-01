// Caminho DIRETO ao Google Drive (OAuth) para o que antes passava pela planilha (Apps Script).
// tentarDireto(corpo) devolve o MESMO formato de resposta do Apps Script, ou null quando não dá para fazer por aqui
// (ação não suportada, Drive não conectado ou erro do Google). Quem chama usa a planilha como segundo caminho.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { URL_, CHAVE_SERVICO } from "./auth.ts";
import { contaConectada, enviarArquivo, meta, baixarBytes, paraLixeira, daLixeira, tornarPublico, arquivosDaPasta, cota, pastaPorNome } from "./drive.ts";

const sv = () => createClient(URL_, CHAVE_SERVICO);
const P = "principal", C = "contingencia";
const PASTAS = {
  fotos:  { [P]: "Restaurante - Fotos",          [C]: "Restaurante - Fotos (cópia)" },
  notas:  { [P]: "Restaurante - Notas de compra", [C]: "Restaurante - Notas de compra (cópia)" },
  ponto:  { [P]: "Fotos do ponto",  [C]: "Fotos do ponto (cópia)" },
  backups:{ [P]: "Restaurante - Backups",         [C]: "Restaurante - Backups (cópia)" },
} as const;
const PASTA_BACKUP_DIRETO = "Backups (Drive direto)";
const PASTA_BACKUP_SUPABASE = "Restaurante - Backups do Supabase";   // onde a planilha (Apps Script) guarda a cópia do backup

function decodificar(b64: string): Uint8Array { const l = b64.indexOf(",") >= 0 ? b64.split(",").pop()! : b64; const bin = atob(l); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }
function codificar(bytes: Uint8Array): string { let s = ""; const C2 = 0x8000; for (let i = 0; i < bytes.length; i += C2) s += String.fromCharCode(...bytes.subarray(i, i + C2)); return btoa(s); }
function nomeSeguro(n: unknown) { const b = String(n || "item").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-zA-Z0-9\-_ ]/g, "").trim().replace(/\s+/g, "-").toLowerCase(); return b || "item"; }
const uuid8 = () => crypto.randomUUID().slice(0, 8);
function tipoImagem(b: Uint8Array) {
  if (b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) return { tipo: "image/jpeg", ext: ".jpg" };
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) return { tipo: "image/png", ext: ".png" };
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return { tipo: "image/webp", ext: ".webp" };
  return null;
}
function tipoNota(b: Uint8Array) { const i = tipoImagem(b); if (i) return i; if (b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46) return { tipo: "application/pdf", ext: ".pdf" }; return null; }

async function exigir(...contas: string[]) { for (const c of contas) if (!(await contaConectada(c))) throw new Error(`Drive ${c} não conectado`); }

/* ---- fotos do cardápio ---- */
async function uploadFotoSb(b: any) {
  await exigir(P);
  const dados = String(b.base64Data || ""); if (!dados) return { ok: false, message: "Nenhuma imagem recebida." };
  const bytes = decodificar(dados);
  if (bytes.length > 5 * 1024 * 1024) return { ok: false, message: "Imagem grande demais (máximo 5 MB)." };
  const t = tipoImagem(bytes); if (!t) return { ok: false, message: "Arquivo não é uma imagem válida (use JPG, PNG ou WEBP)." };
  const pasta = await pastaPorNome(P, PASTAS.fotos[P]);
  const r = await enviarArquivo(P, pasta, nomeSeguro(b.nomeBase) + "-" + uuid8() + t.ext, t.tipo, bytes);
  await tornarPublico(P, r.id);
  let reserva = "";
  if (b.copiarContingencia && (await contaConectada(C))) {
    try {
      const pc = await pastaPorNome(C, PASTAS.fotos[C]);
      const rc = await enviarArquivo(C, pc, r.id + t.ext, t.tipo, bytes); await tornarPublico(C, rc.id); reserva = rc.id;
    } catch { /* a principal já está salva; a reserva é copiada depois pelo botão de sincronizar */ }
  }
  return { ok: true, fotoId: r.id, fotoReservaId: reserva };
}
async function excluirFotoSb(b: any) {
  await exigir(P);
  for (const id of (Array.isArray(b.ids) ? b.ids : [])) { try { await paraLixeira(P, String(id)); } catch { /* já não existe */ } }
  return { ok: true };
}
async function replicarFotos(b: any) {
  await exigir(P, C);
  const ini = Date.now(), resultados: any[] = [], falhas: string[] = [];
  const pc = await pastaPorNome(C, PASTAS.fotos[C]);
  for (const p of (b.itens || [])) {
    if (Date.now() - ini > 100000 || !p.foto_id_principal) continue;
    try {
      const bytes = await baixarBytes(P, p.foto_id_principal);
      if (bytes.length > 5 * 1024 * 1024) { falhas.push(p.id + ": maior que 5 MB"); continue; }
      const t = tipoImagem(bytes); if (!t) { falhas.push(p.id + ": não é imagem válida"); continue; }
      const rc = await enviarArquivo(C, pc, p.foto_id_principal + t.ext, t.tipo, bytes); await tornarPublico(C, rc.id);
      resultados.push({ tipo: p.tipo, id: p.id, foto_id_contingencia: rc.id });
    } catch (e) { falhas.push(p.id + ": " + (e as Error).message); }
  }
  return { ok: true, resultados, falhas, message: falhas.length ? falhas.length + " foto(s) não copiadas." : "" };
}

/* ---- notas de compra e fotos do ponto (privadas) ---- */
function guardarPrivado(chavePasta: "notas" | "ponto", max: number, msgGrande: string, validar: (b: Uint8Array) => { tipo: string; ext: string } | null, msgTipo: string, padrao: string) {
  return async (b: any) => {
    const destino = String(b.destino || "ambos");
    if (!["principal", "contingencia", "ambos"].includes(destino)) return { ok: false, message: "Destino inválido." };
    const dados = String(b.base64Data || ""); if (!dados) return { ok: false, message: chavePasta === "notas" ? "Nenhum arquivo recebido." : "Nenhuma foto recebida." };
    const bytes = decodificar(dados);
    if (bytes.length > max) return { ok: false, message: msgGrande };
    const t = validar(bytes); if (!t) return { ok: false, message: msgTipo };
    await exigir(...(destino === "principal" ? [P] : destino === "contingencia" ? [C] : [P, C]));
    const nome = nomeSeguro(b.nomeBase || padrao) + "-" + uuid8() + t.ext;
    let id = "", reserva = "", avisoReserva = "";
    if (destino !== "contingencia") id = (await enviarArquivo(P, await pastaPorNome(P, PASTAS[chavePasta][P]), nome, t.tipo, bytes)).id;
    if (destino !== "principal") {
      try { reserva = (await enviarArquivo(C, await pastaPorNome(C, PASTAS[chavePasta][C]), nome, t.tipo, bytes)).id; }
      catch (e) { avisoReserva = String((e as Error).message || e).slice(0, 200); }
      if (!reserva && !id) return { ok: false, message: "Não consegui salvar no Drive da contingência: " + avisoReserva };
    }
    return chavePasta === "notas" ? { ok: true, id, idReserva: reserva, tipo: t.tipo, avisoReserva } : { ok: true, id, idReserva: reserva, avisoReserva };
  };
}
const guardarNota = guardarPrivado("notas", 3 * 1024 * 1024, "Arquivo grande demais (máximo 3 MB).", tipoNota, "Use foto (JPG, PNG, WEBP) ou PDF.", "nota");
const guardarPonto = guardarPrivado("ponto", 1536 * 1024, "Foto grande demais (máximo 1,5 MB).", (b) => (b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF ? { tipo: "image/jpeg", ext: ".jpg" } : null), "A foto precisa ser JPEG.", "ponto");

function lerPrivado(chavePasta: "notas" | "ponto") {
  return async (b: any) => {
    const id = String(b.id || ""); if (!/^[\w-]{10,80}$/.test(id)) return { ok: false, message: "Arquivo inválido." };
    const conta = b.onde === "contingencia" ? C : P;
    await exigir(conta);
    const pasta = await pastaPorNome(conta, PASTAS[chavePasta][conta]);
    const m = await meta(conta, id);
    if (m.trashed || !(m.parents || []).includes(pasta)) throw new Error("fora da pasta esperada");   // deixa a planilha decidir
    const bytes = await baixarBytes(conta, id);
    return { ok: true, tipo: m.mimeType, nome: m.name, base64: codificar(bytes) };
  };
}
function excluirPrivado(chavePasta: "notas" | "ponto") {
  return async (b: any) => {
    const ids = Array.isArray(b.ids) ? b.ids : [], idsR = Array.isArray(b.idsReserva) ? b.idsReserva : [];
    await exigir(...(idsR.length ? [P, C] : [P]));
    let n = 0;
    for (const [conta, lista] of [[P, ids], [C, idsR]] as [string, string[]][]) {
      if (!lista.length) continue;
      const pasta = await pastaPorNome(conta, PASTAS[chavePasta][conta]);
      for (const id of lista) { try { const m = await meta(conta, String(id)); if ((m.parents || []).includes(pasta) && !m.trashed) { await paraLixeira(conta, String(id)); if (conta === P) n++; } } catch { /* já não existe */ } }
    }
    return chavePasta === "ponto" ? { ok: true, apagadas: n } : { ok: true };
  };
}

/* ---- espaço do Drive (leitura rápida) ---- */
function nivelEspaco(pct: number | null) { return pct === null ? "Indisponível" : pct > 90 ? "Crítico" : pct >= 70 ? "Atenção" : "Normal"; }
async function resumoCota(conta: string) {
  const { usado, limite } = await cota(conta);
  const pct = limite > 0 ? Math.round(usado / limite * 1000) / 10 : null;
  return { usado, limite, livre: limite > 0 ? Math.max(0, limite - usado) : null, percentual: pct, nivel: nivelEspaco(pct) };
}
// A composição (o que ocupa o espaço) exige listar as pastas; fica guardada por 30 min para a tela abrir rápido. A cota (usado/livre) é sempre atual.
const COMP_TTL = 30 * 60000;
async function compCache(chave: string, calc: () => Promise<any>) {
  const v = await lerSistema(chave);
  if (v?.em && v?.dados && Date.now() - new Date(v.em).getTime() < COMP_TTL) return v.dados;
  const dados = await calc(); await guardarSistema(chave, { em: new Date().toISOString(), dados });
  return dados;
}
const limparCacheComp = async () => { try { await sv().from("sistema").delete().in("chave", ["ARMAZ_COMP_P", "ARMAZ_COMP_C"]); } catch { /* o prazo de 30 min resolve */ } };
async function armazenamento() {
  await exigir(P);
  const [dr, comp] = await Promise.all([resumoCota(P), compCache("ARMAZ_COMP_P", compPrincipal)]);
  return { ok: true, drive: dr, ...comp, viaDireto: true };
}
async function compPrincipal() {
  const svc = sv();
  const [pr, cb] = await Promise.all([svc.from("produtos").select("foto_id_principal").not("foto_id_principal", "is", null), svc.from("combos").select("foto_id_principal").not("foto_id_principal", "is", null)]);
  if (pr.error || cb.error) throw new Error("não consegui ler as fotos em uso");
  const fp = new Set((pr.data || []).map((x: any) => x.foto_id_principal)), fc = new Set((cb.data || []).map((x: any) => x.foto_id_principal));
  const cats: Record<string, { qtd: number; bytes: number }> = { "Imagens de produtos": { qtd: 0, bytes: 0 }, "Imagens de combos": { qtd: 0, bytes: 0 }, "Outras imagens": { qtd: 0, bytes: 0 }, "Notas de compra": { qtd: 0, bytes: 0 }, "Arquivos de backup": { qtd: 0, bytes: 0 }, "Arquivos do sistema": { qtd: 1, bytes: 0 } };
  const arquivos: any[] = [];
  const add = (f: any, c: string) => { const b = Number(f.size || 0); cats[c].qtd++; cats[c].bytes += b; arquivos.push({ nome: f.name, categoria: c, tamanho: b, criadoEm: f.createdTime }); };
  try { for (const f of await arquivosDaPasta(P, await pastaPorNome(P, PASTAS.fotos[P]), 500)) add(f, fp.has(f.id) ? "Imagens de produtos" : fc.has(f.id) ? "Imagens de combos" : "Outras imagens"); } catch { /* segue */ }
  try { for (const f of await arquivosDaPasta(P, await pastaPorNome(P, PASTAS.notas[P]), 500)) add(f, "Notas de compra"); } catch { /* segue */ }
  for (const nome of [PASTAS.backups[P], PASTA_BACKUP_SUPABASE, PASTA_BACKUP_DIRETO]) { try { for (const f of await arquivosDaPasta(P, await pastaPorNome(P, nome), 200)) add(f, "Arquivos de backup"); } catch { /* segue */ } }
  // tamanho da planilha: só o Apps Script sabe medir; usa o último valor conhecido (atualizado em segundo plano pela função planilha-admin)
  const { data: cache } = await svc.from("sistema").select("valor").eq("chave", "ARMAZ_ARQ_SISTEMA").maybeSingle();
  const v: any = cache?.valor;
  if (v && Number(v.bytes) > 0) { cats["Arquivos do sistema"].bytes = Number(v.bytes); arquivos.push({ nome: (v.nome || "Planilha principal") + " (planilha principal)", categoria: "Arquivos do sistema", tamanho: Number(v.bytes), criadoEm: v.criadoEm || null }); }
  arquivos.sort((a, b) => b.tamanho - a.tamanho);
  return { categorias: cats, arquivos: arquivos.slice(0, 30), totalArquivos: arquivos.length, arquivosDoSistemaEm: v?.em || null };
}
async function armazenamentoContingencia() {
  await exigir(C);
  const [dr, comp] = await Promise.all([resumoCota(C), compCache("ARMAZ_COMP_C", compContingencia)]);
  return { ok: true, drive: dr, ...comp, viaDireto: true };
}
async function compContingencia() {
  const cats: Record<string, { qtd: number; bytes: number }> = { "Cópias de backup": { qtd: 0, bytes: 0 }, "Fotos (cópia)": { qtd: 0, bytes: 0 }, "Fotos do ponto, perdas e atestados": { qtd: 0, bytes: 0 } };
  const backups: any[] = [];
  for (const nome of [PASTAS.backups[C], PASTA_BACKUP_DIRETO]) {
    try { for (const f of await arquivosDaPasta(C, await pastaPorNome(C, nome), 200)) { const b = Number(f.size || 0); cats["Cópias de backup"].qtd++; cats["Cópias de backup"].bytes += b; backups.push({ nome: f.name, tamanho: b, criadoEm: f.createdTime }); } } catch { /* segue */ }
  }
  try { for (const f of await arquivosDaPasta(C, await pastaPorNome(C, PASTAS.fotos[C]), 1000)) { cats["Fotos (cópia)"].qtd++; cats["Fotos (cópia)"].bytes += Number(f.size || 0); } } catch { /* segue */ }
  try { for (const f of await arquivosDaPasta(C, await pastaPorNome(C, PASTAS.ponto[C]), 3000)) { cats["Fotos do ponto, perdas e atestados"].qtd++; cats["Fotos do ponto, perdas e atestados"].bytes += Number(f.size || 0); } } catch { /* segue */ }
  backups.sort((a, b) => (a.criadoEm < b.criadoEm ? 1 : -1));
  return { categorias: cats, backups: backups.slice(0, 10) };
}


/* ---- v1.21: fotos sem uso (direto), prazos e limpeza automática ---- */
export const PRAZOS_PADRAO: Record<string, number> = { ponto: 90, evidencias: 90, atestados: 90, notas: 395 };
export async function prazos(): Promise<Record<string, number>> {
  const { data } = await sv().from("sistema").select("valor").eq("chave", "DRIVE_PRAZOS").maybeSingle();
  const v: any = data?.valor || {}, o: Record<string, number> = { ...PRAZOS_PADRAO };
  for (const k of Object.keys(o)) { const n = Number(v[k]); if (n >= 1 && n <= 3650) o[k] = Math.round(n); }
  return o;
}
const guardarSistema = (chave: string, valor: unknown) => sv().from("sistema").upsert({ chave, valor, atualizado_em: new Date().toISOString() });
const lerSistema = async (chave: string): Promise<any> => (await sv().from("sistema").select("valor").eq("chave", chave).maybeSingle()).data?.valor ?? null;
const baseFoto = (nome: string) => String(nome || "").replace(/\.[a-z0-9]+$/i, "").replace(/-[0-9a-f]{8}$/i, "");

/* TRAVA (só foto do cardápio): a limpeza só pode mandar para a lixeira um arquivo que seja IMAGEM (JPG/PNG/WEBP) e tenha o nome
   que o próprio sistema dá às fotos: principal "nome-do-item-1a2b3c4d.jpg"; cópia da contingência "<id da foto>.jpg".
   Qualquer outro arquivo colocado nessas pastas (PDF, planilha, foto com outro nome...) nunca é apagado. */
const MIME_FOTO = new Set(["image/jpeg", "image/png", "image/webp"]);
const ehFotoDoSistemaP = (f: any) => MIME_FOTO.has(String(f.mimeType || "")) && /^[a-z0-9_-]+-[0-9a-f]{8}\.(jpg|png|webp)$/.test(String(f.name || ""));
const ehCopiaDoSistemaC = (f: any) => MIME_FOTO.has(String(f.mimeType || "")) && /^[\w-]{10,80}\.(jpg|png|webp)$/.test(String(f.name || ""));

async function analisarFotos(emUso: string[], emUsoCont: string[]) {
  const uso = new Set(emUso.map(String)), usoRes = new Set(emUsoCont.map(String)), limite = Date.now() - 7 * 86400000;
  // Drive principal: pasta de fotos do cardápio
  const arqP = await arquivosDaPasta(P, await pastaPorNome(P, PASTAS.fotos[P]), 3000);
  const usadas = new Set<string>(), soltas: typeof arqP = []; let recP = 0, outrosP = 0;
  for (const f of arqP) {
    if (uso.has(f.id)) { usadas.add(baseFoto(f.name) + "|" + f.size); continue; }
    if (!ehFotoDoSistemaP(f)) { outrosP++; continue; }   // não é foto do cardápio: nunca entra
    if (new Date(f.createdTime).getTime() > limite) { recP++; continue; }
    soltas.push(f);
  }
  const semUsoP = soltas.map((f) => ({ id: f.id, nome: f.name, tamanho: Number(f.size || 0), criadoEm: f.createdTime, motivo: usadas.has(baseFoto(f.name) + "|" + f.size) ? "duplicada de uma foto em uso" : "não é foto de nenhum produto ou combo" }));
  const principal = { total: arqP.length, qtdSemUso: semUsoP.length, bytesSemUso: semUsoP.reduce((t, x) => t + x.tamanho, 0), recentesIgnoradas: recP, outrosIgnorados: outrosP, semUso: semUsoP.slice(0, 500) };
  // Drive da contingência: cópias (o nome do arquivo começa pelo id da foto do principal)
  let contingencia: any;
  try {
    await exigir(C);
    const arqC = await arquivosDaPasta(C, await pastaPorNome(C, PASTAS.fotos[C]), 3000);
    const semUsoC: any[] = []; let recC = 0, outrosC = 0;
    for (const f of arqC) {
      const orig = String(f.name || "").replace(/\.[a-z0-9]+$/i, "");
      if (usoRes.has(f.id) || uso.has(orig)) continue;
      if (!ehCopiaDoSistemaC(f)) { outrosC++; continue; }   // não é cópia de foto do cardápio: nunca entra
      if (new Date(f.createdTime).getTime() > limite) { recC++; continue; }
      semUsoC.push({ id: f.id, nome: f.name, tamanho: Number(f.size || 0), criadoEm: f.createdTime, motivo: "cópia de uma foto que o sistema não usa mais" });
    }
    contingencia = { ok: true, total: arqC.length, qtdSemUso: semUsoC.length, bytesSemUso: semUsoC.reduce((t, x) => t + x.tamanho, 0), recentesIgnoradas: recC, outrosIgnorados: outrosC, semUso: semUsoC.slice(0, 500) };
  } catch (e) { contingencia = { ok: false, message: "A contingência não respondeu: " + (e as Error).message }; }
  return { ok: true, principal, contingencia };
}
async function sbFotosAnalisar(b: any) {
  const emUso = Array.isArray(b.emUso) ? b.emUso.filter(Boolean) : [];
  if (!emUso.length) return { ok: false, message: "A lista de fotos em uso veio vazia: análise cancelada (proteção, nada foi apagado)." };
  await exigir(P);
  return await analisarFotos(emUso, Array.isArray(b.emUsoCont) ? b.emUsoCont : []);
}
async function lixeiraDeFotos(a: any, idsP: string[], idsC: string[]) {
  const res: any = { ok: true, principal: { removidas: 0, bytes: 0 }, contingencia: { removidas: 0, bytes: 0 } }, itens: { conta: string; id: string }[] = [];
  const podeP = new Map<string, any>((a.principal.semUso || []).map((x: any) => [x.id, x]));
  for (const id of idsP.slice(0, 200)) { const x = podeP.get(String(id)); if (!x) continue; try { await paraLixeira(P, x.id); res.principal.removidas++; res.principal.bytes += x.tamanho; itens.push({ conta: P, id: x.id }); } catch { /* segue */ } }
  if (idsC.length) {
    if (!a.contingencia?.ok) res.contingencia.erro = a.contingencia?.message || "A contingência recusou.";
    else {
      const podeC = new Map<string, any>((a.contingencia.semUso || []).map((x: any) => [x.id, x]));
      for (const id of idsC.slice(0, 200)) { const x = podeC.get(String(id)); if (!x) continue; try { await paraLixeira(C, x.id); res.contingencia.removidas++; res.contingencia.bytes += x.tamanho; itens.push({ conta: C, id: x.id }); } catch { /* segue */ } }
    }
  }
  if (itens.length) { await guardarSistema("FOTOS_LIMPEZA_ULTIMA", { em: new Date().toISOString(), itens, restaurada: false }); await limparCacheComp(); }
  return res;
}
async function sbFotosLimpar(b: any) {
  const emUso = Array.isArray(b.emUso) ? b.emUso.filter(Boolean) : [];
  if (!emUso.length) return { ok: false, message: "A lista de fotos em uso veio vazia: nada foi apagado (proteção)." };
  await exigir(P);
  const a = await analisarFotos(emUso, Array.isArray(b.emUsoCont) ? b.emUsoCont : []);   // confere de novo na hora de apagar
  return await lixeiraDeFotos(a, Array.isArray(b.ids) ? b.ids.map(String) : [], Array.isArray(b.idsCont) ? b.idsCont.map(String) : []);
}
async function sbFotosRestaurar() {
  const v = await lerSistema("FOTOS_LIMPEZA_ULTIMA");
  if (!v) return null;   // nenhuma limpeza feita por aqui: a planilha confere a dela
  if (v.restaurada || !(v.itens || []).length) return { ok: true, restauradas: 0, message: "Não há limpeza para restaurar." };
  await exigir(P);
  let n = 0;
  for (const it of v.itens as { conta: string; id: string }[]) {
    try {
      const pasta = await pastaPorNome(it.conta, PASTAS.fotos[it.conta as typeof P]);
      const m = await meta(it.conta, it.id);
      if (m.trashed && (m.parents || []).includes(pasta)) { await daLixeira(it.conta, it.id); n++; }
    } catch { /* arquivo já apagado de vez */ }
  }
  await guardarSistema("FOTOS_LIMPEZA_ULTIMA", { ...v, restaurada: true, restauradaEm: new Date().toISOString() }); await limparCacheComp();
  return { ok: true, restauradas: n, message: n + " foto(s) tirada(s) da lixeira do Drive." };
}

/* Lê a tabela INTEIRA em páginas de 1000 (o Supabase corta em 1000 linhas por consulta: sem isto, uma tabela grande deixaria
   fotos em uso fora da lista e elas seriam tratadas como "sem uso"). Qualquer falha para tudo. */
async function lerTudo(tabela: string, colunas: string): Promise<{ data: any[]; error: any }> {
  const svc = sv(), out: any[] = [], PAG = 1000;
  for (let ini = 0; ; ini += PAG) {
    const { data, error } = await svc.from(tabela).select(colunas).order("id").range(ini, ini + PAG - 1);
    if (error) return { data: [], error };
    out.push(...(data || []));
    if ((data || []).length < PAG) return { data: out, error: null };
    if (ini > 200000) return { data: [], error: new Error("tabela grande demais") };   // trava: não conclui com lista possivelmente incompleta
  }
}
async function fotosEmUso() {
  const svc = sv();
  const [p1, p2, p3] = await Promise.all([lerTudo("produtos", "foto_id_principal,foto_id_contingencia"), lerTudo("combos", "foto_id_principal,foto_id_contingencia"), lerTudo("fotos_historico", "foto_id_antigo,foto_id_novo")]);
  if (p1.error || p2.error || p3.error) throw new Error("não consegui ler as fotos em uso no banco");
  const emUso = new Set<string>(), emUsoCont = new Set<string>();
  for (const x of [...(p1.data || []), ...(p2.data || [])]) { if (x.foto_id_principal) emUso.add(x.foto_id_principal); if (x.foto_id_contingencia) emUsoCont.add(x.foto_id_contingencia); }
  for (const x of (p3.data || [])) { if (x.foto_id_antigo) emUso.add(x.foto_id_antigo); if (x.foto_id_novo) emUso.add(x.foto_id_novo); }
  return { emUso: [...emUso], emUsoCont: [...emUsoCont] };
}
const partesDe = (path: string) => Object.fromEntries(String(path || "").split("|").map((x) => x.split(":")).filter((x) => x.length === 2));

// Rotina diária (cron): comprovantes de nota vencidos; e, uma vez por mês, copia as fotos que faltam na contingência e manda as fotos sem uso para a lixeira.
async function limpezaDiaria() {
  const svc = sv(), out: any = { notas: 0, falhas: 0 }, ini = Date.now();
  const pr = await prazos();
  try {
    const corte = new Date(Date.now() - pr.notas * 86400000).toISOString();
    const { data } = await svc.from("compras").select("id,anexo_path").not("anexo_path", "is", null).like("anexo_path", "%drive:%").lt("criado_em", corte).limit(100);
    for (const c of data || []) {
      const p = partesDe(c.anexo_path as string);
      try { const r: any = await excluirPrivado("notas")({ ids: p.drive ? [p.drive] : [], idsReserva: p.cont ? [p.cont] : [] }); if (!r?.ok) { out.falhas++; continue; } await svc.from("compras").update({ anexo_path: null, anexo_nome: null }).eq("id", c.id); out.notas++; }
      catch { out.falhas++; }
    }
  } catch (e) { out.erroNotas = (e as Error).message; }

  const mes = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit" }).format(new Date());
  const ult = await lerSistema("DRIVE_LIMPEZA_AUTO");
  if (ult?.mes === mes) { out.mensal = "já feita neste mês"; return out; }
  const reg: any = { mes, em: new Date().toISOString(), replicadas: 0, principal: { removidas: 0, bytes: 0 }, contingencia: { removidas: 0, bytes: 0 } };
  try {
    await exigir(P, C);
    // 1) fotos do cardápio que ainda não têm cópia na contingência
    for (const tipo of ["produtos", "combos"] as const) {
      if (Date.now() - ini > 70000) break;
      const { data } = await svc.from(tipo).select("id,nome,foto_id_principal").not("foto_id_principal", "is", null).is("foto_id_contingencia", null).limit(25);
      if (!(data || []).length) continue;
      const r: any = await replicarFotos({ itens: (data || []).map((x: any) => ({ tipo, ...x })) });
      for (const x of r.resultados || []) { await svc.from(tipo).update({ foto_id_contingencia: x.foto_id_contingencia }).eq("id", x.id); reg.replicadas++; }
      if ((r.falhas || []).length) reg.avisoCopia = r.falhas.slice(0, 3).join(" · ");
    }
    // 2) fotos sem uso -> lixeira (com trava de segurança)
    const { data: bk } = await svc.from("backups").select("id").eq("status", "Em andamento").gte("data_hora", new Date(Date.now() - 3600000).toISOString()).limit(1);
    if (bk?.length) { out.mensal = "adiada: backup em andamento"; return out; }
    const u = await fotosEmUso();
    if (!u.emUso.length) throw new Error("nenhuma foto em uso encontrada no banco; por segurança nada foi limpo");
    const a: any = await analisarFotos(u.emUso, u.emUsoCont);
    const nP = a.principal.qtdSemUso, nC = a.contingencia?.ok ? a.contingencia.qtdSemUso : 0;
    const trava = (n: number, total: number) => n > Math.max(20, Math.floor(total * 0.4));
    if (trava(nP, a.principal.total) || (a.contingencia?.ok && trava(nC, a.contingencia.total))) {
      reg.erro = `Limpeza automática cancelada por segurança: ${nP} foto(s) sem uso no principal e ${nC} na contingência é muito mais que o normal. Confira em Fotos sem uso.`;
    } else {
      const r = await lixeiraDeFotos(a, (a.principal.semUso || []).map((x: any) => x.id), a.contingencia?.ok ? (a.contingencia.semUso || []).map((x: any) => x.id) : []);
      reg.principal = r.principal; reg.contingencia = r.contingencia;
      if (!a.contingencia?.ok) reg.erro = a.contingencia?.message;
    }
  } catch (e) { reg.erro = "Limpeza mensal não concluída: " + (e as Error).message; }
  await guardarSistema("DRIVE_LIMPEZA_AUTO", reg); await limparCacheComp();
  try { await svc.from("auditoria").insert({ acao: "Limpeza automática mensal de fotos (Drive)", detalhes: reg.erro ? reg.erro.slice(0, 300) : `principal: ${reg.principal.removidas} foto(s); contingência: ${reg.contingencia.removidas} foto(s); copiadas para a contingência: ${reg.replicadas}` }); } catch { /* auditoria não derruba */ }
  out.mensal = reg;
  return out;
}

const ACOES: Record<string, (b: any) => Promise<any>> = {
  uploadFotoSb, excluirFotoSb, replicarFotos,
  sbGuardarNota: guardarNota, sbLerNota: lerPrivado("notas"), sbExcluirNota: excluirPrivado("notas"),
  sbGuardarPonto: guardarPonto, sbLerPonto: lerPrivado("ponto"), sbExcluirPonto: excluirPrivado("ponto"),
  sbArmazenamento: armazenamento, sbArmazenamentoContingencia: armazenamentoContingencia,
  sbFotosAnalisar, sbFotosLimpar, sbFotosRestaurar, limpezaDiaria,
};
export async function tentarDireto(corpo: Record<string, any>): Promise<any | null> {
  const h = ACOES[String(corpo?.action || "")]; if (!h) return null;
  try { return await h(corpo); }
  catch (e) { console.error("[drive-direto]", corpo.action, "→ usando a planilha:", (e as Error).message); return null; }
}
export const acoesDiretas = Object.keys(ACOES);
