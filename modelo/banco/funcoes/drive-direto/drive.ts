// Google Drive direto (OAuth do próprio dono). O refresh token fica no Vault (drive_ler_token).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { URL_, CHAVE_SERVICO, cfg } from "./auth.ts";

export const CONTAS = ["principal", "contingencia"] as const;
export const ESCOPO = "https://www.googleapis.com/auth/drive";
export const REDIRECT = `${URL_}/functions/v1/drive-oauth`;
const sv = () => createClient(URL_, CHAVE_SERVICO);

export async function credenciais() {
  const id = await cfg("GOOGLE_CLIENT_ID"), segredo = await cfg("GOOGLE_CLIENT_SECRET");
  if (!id || !segredo) throw new Error("Credenciais do Google não configuradas no Supabase (google_client_id / google_client_secret).");
  return { id, segredo };
}

const cache: Record<string, { token: string; ate: number }> = {};
export async function acessoToken(conta: string): Promise<string> {
  const c = cache[conta]; if (c && c.ate > Date.now() + 60000) return c.token;
  const { data: refresh } = await sv().rpc("drive_ler_token", { p_conta: conta });
  if (!refresh) throw new Error(`Drive ${conta === "principal" ? "principal" : "da contingência"} não está conectado.`);
  const { id, segredo } = await credenciais();
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: id, client_secret: segredo, refresh_token: refresh as string, grant_type: "refresh_token" }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) {
    const motivo = j.error === "invalid_grant" ? "A autorização do Google venceu ou foi retirada. Toque em Reconectar." : (j.error_description || j.error || `HTTP ${r.status}`);
    throw new Error(`Google recusou o acesso: ${motivo}`);
  }
  cache[conta] = { token: j.access_token, ate: Date.now() + (j.expires_in || 3000) * 1000 };
  return j.access_token;
}

export async function g(conta: string, url: string, init: RequestInit = {}) {
  const t = await acessoToken(conta);
  const r = await fetch(url, { ...init, headers: { ...(init.headers || {}), Authorization: `Bearer ${t}` } });
  if (!r.ok) {
    const txt = await r.text().catch(() => ""); let m = txt.slice(0, 200);
    try { const j = JSON.parse(txt); m = j.error?.message || m; } catch { /* texto puro */ }
    throw new Error(`Google Drive: ${m} (HTTP ${r.status})`);
  }
  return r;
}

const esc = (s: string) => s.replace(/\\/g, "\\\\").replace(/'/g, "\\'");

export async function listar(conta: string, pastaId: string, pageToken?: string) {
  const q = `'${esc(pastaId)}' in parents and trashed=false`;
  const u = new URL("https://www.googleapis.com/drive/v3/files");
  u.searchParams.set("q", q); u.searchParams.set("pageSize", "100");
  u.searchParams.set("orderBy", "folder,name_natural");
  u.searchParams.set("fields", "nextPageToken,files(id,name,mimeType,size,modifiedTime)");
  if (pageToken) u.searchParams.set("pageToken", pageToken);
  return await (await g(conta, u.toString())).json();
}

export async function nomeDaPasta(conta: string, id: string) {
  if (id === "root") return "Meu Drive";
  const j = await (await g(conta, `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}?fields=id,name,parents`)).json();
  return { nome: j.name as string, pai: (j.parents?.[0] as string) || "root" };
}

export async function acharOuCriarPasta(conta: string, nome: string, paiId = "root"): Promise<string> {
  const q = `name='${esc(nome)}' and '${esc(paiId)}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`;
  const u = new URL("https://www.googleapis.com/drive/v3/files"); u.searchParams.set("q", q); u.searchParams.set("fields", "files(id)");
  const j = await (await g(conta, u.toString())).json();
  if (j.files?.[0]?.id) return j.files[0].id;
  const c = await g(conta, "https://www.googleapis.com/drive/v3/files?fields=id", { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: nome, mimeType: "application/vnd.google-apps.folder", parents: [paiId] }) });
  return (await c.json()).id;
}

export async function enviarArquivo(conta: string, pastaId: string, nome: string, mime: string, bytes: Uint8Array) {
  const limite = "txbdrive" + crypto.randomUUID().replace(/-/g, "");
  const meta = JSON.stringify({ name: nome, parents: [pastaId] });
  const enc = new TextEncoder();
  const corpo = new Blob([enc.encode(`--${limite}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${limite}\r\nContent-Type: ${mime || "application/octet-stream"}\r\n\r\n`), bytes, enc.encode(`\r\n--${limite}--`)]);
  const r = await g(conta, "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size", { method: "POST", headers: { "Content-Type": `multipart/related; boundary=${limite}` }, body: corpo });
  return await r.json();
}

export async function apagarAntigos(conta: string, pastaId: string, antesDeISO: string, prefixo = "backup-") {
  const q = `'${esc(pastaId)}' in parents and trashed=false and modifiedTime < '${antesDeISO}' and name contains '${esc(prefixo)}'`;
  const u = new URL("https://www.googleapis.com/drive/v3/files"); u.searchParams.set("q", q); u.searchParams.set("fields", "files(id,name)"); u.searchParams.set("pageSize", "200");
  const j = await (await g(conta, u.toString())).json();
  for (const f of j.files || []) await g(conta, `https://www.googleapis.com/drive/v3/files/${f.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ trashed: true }) });
  return (j.files || []).length;
}

export async function contaConectada(conta: string): Promise<boolean> {
  const { data } = await sv().from("drive_contas").select("conta").eq("conta", conta).maybeSingle(); return !!data;
}

/* ---------- v1.19: caminho direto das funções que usavam o Drive pela planilha ---------- */
const API = "https://www.googleapis.com/drive/v3/files";
const JSONH = { "Content-Type": "application/json" };
export async function meta(conta: string, id: string) {
  return await (await g(conta, `${API}/${encodeURIComponent(id)}?fields=id,name,mimeType,size,trashed,parents`)).json();
}
export async function baixarBytes(conta: string, id: string): Promise<Uint8Array> {
  return new Uint8Array(await (await g(conta, `${API}/${encodeURIComponent(id)}?alt=media`)).arrayBuffer());
}
export async function paraLixeira(conta: string, id: string) {
  await g(conta, `${API}/${encodeURIComponent(id)}`, { method: "PATCH", headers: JSONH, body: JSON.stringify({ trashed: true }) });
}
export async function tornarPublico(conta: string, id: string) {
  await g(conta, `${API}/${encodeURIComponent(id)}/permissions`, { method: "POST", headers: JSONH, body: JSON.stringify({ role: "reader", type: "anyone" }) });
}
export async function arquivosDaPasta(conta: string, pastaId: string, limite = 500): Promise<{ id: string; name: string; size: string; createdTime: string; mimeType?: string }[]> {
  const out: any[] = []; let pagina: string | undefined;
  do {
    const u = new URL(API); u.searchParams.set("q", `'${esc(pastaId)}' in parents and trashed=false and mimeType != 'application/vnd.google-apps.folder'`);
    u.searchParams.set("pageSize", "200"); u.searchParams.set("fields", "nextPageToken,files(id,name,size,createdTime,mimeType)");
    if (pagina) u.searchParams.set("pageToken", pagina);
    const j = await (await g(conta, u.toString())).json(); out.push(...(j.files || [])); pagina = j.nextPageToken;
  } while (pagina && out.length < limite);
  return out.slice(0, limite);
}
export async function cota(conta: string) {
  const j = await (await g(conta, "https://www.googleapis.com/drive/v3/about?fields=storageQuota")).json();
  return { usado: Number(j.storageQuota?.usage || 0), limite: Number(j.storageQuota?.limit || 0) };
}
const pastas: Record<string, string> = {};
export async function pastaPorNome(conta: string, nome: string): Promise<string> {
  const k = conta + "|" + nome; if (pastas[k]) return pastas[k];
  return (pastas[k] = await acharOuCriarPasta(conta, nome, "root"));
}
export async function daLixeira(conta: string, id: string) {
  await g(conta, `${API}/${encodeURIComponent(id)}`, { method: "PATCH", headers: JSONH, body: JSON.stringify({ trashed: false }) });
}
