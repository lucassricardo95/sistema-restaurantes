// Google Drive direto: conectar contas, navegar, baixar, enviar, criar pasta. Só Admin (Desenvolvedor vale como Admin).
import { CORS, json, svcClient, autorizar, URL_, cfg } from "./auth.ts";
import { CONTAS, ESCOPO, REDIRECT, credenciais, g, acessoToken, listar, nomeDaPasta, acharOuCriarPasta, enviarArquivo } from "./drive.ts";

const MAX_BAIXAR = 25 * 1024 * 1024, MAX_ENVIAR = 20 * 1024 * 1024;
const NOMES: Record<string, string> = { principal: "Drive principal", contingencia: "Drive da contingência" };
function b64(bytes: Uint8Array) { let s = ""; const C = 0x8000; for (let i = 0; i < bytes.length; i += C) s += String.fromCharCode(...bytes.subarray(i, i + C)); return btoa(s); }
function bytesDe(base64: string) { const bin = atob(base64); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }

// Ações sensíveis (conectar, desconectar, enviar arquivo): senha do Admin conferida aqui no servidor, sempre (igual a excluir backup).
async function senhaOk(svc: any, usuarioId: string | undefined, senha: unknown): Promise<boolean> {
  if (!usuarioId || !senha) return false;
  const { data: u } = await svc.from("usuarios").select("login").eq("id", usuarioId).single();
  const email = String(u?.login || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim() + "@usuarios.restaurante.app";
  const chavePub = (await cfg("SB_PUBLISHABLE_KEY")) || Deno.env.get("SUPABASE_ANON_KEY")!;
  const rs = await fetch(`${URL_}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: chavePub, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: String(senha) }) });
  return rs.ok;
}
async function auditar(svc: any, a: any, acao: string, detalhes: string) {
  try { const { data: u } = await svc.from("usuarios").select("login").eq("id", a.usuario?.id).single();
    await svc.from("auditoria").insert({ acao, usuario_id: a.usuario?.id ?? null, usuario_login: u?.login ?? null, detalhes }); } catch { /* auditoria não derruba a ação */ }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  try {
    const b = await req.json().catch(() => ({}));
    const acao = String(b.acao || ""), svc = svcClient();
    const conta = String(b.conta || "");
    if (!["status", "prazos", "prazosSalvar"].includes(acao) && !CONTAS.includes(conta as any)) return json({ ok: false, message: "Conta inválida (use principal ou contingencia)." }, 400);

    if (acao === "status") {
      const { data } = await svc.from("drive_contas").select("conta,email,conectado_em");
      const out = [];
      for (const c of CONTAS) {
        const x = data?.find((d) => d.conta === c);
        if (!x) { out.push({ conta: c, nome: NOMES[c], conectado: false }); continue; }
        let ok = true, erro = "";
        try { await acessoToken(c); } catch (e) { ok = false; erro = (e as Error).message; }
        out.push({ conta: c, nome: NOMES[c], conectado: true, email: x.email, desde: x.conectado_em, ok, erro });
      }
      let credOk = true; try { await credenciais(); } catch { credOk = false; }
      return json({ ok: true, contas: out, credenciais: credOk });
    }

    if (["oauthUrl", "desconectar", "enviar", "prazosSalvar"].includes(acao)) {
      if (a.servico) return json({ ok: false, message: "Só o Admin logado faz isto." }, 403);
      if (!(await senhaOk(svc, a.usuario?.id, b.senhaAdmin))) return json({ ok: false, message: "Senha incorreta." }, 403);
    }

    if (acao === "prazos" || acao === "prazosSalvar") {   // Quanto tempo guardar (fotos, notas e backups)
      const PADRAO: Record<string, number> = { ponto: 90, evidencias: 90, atestados: 90, notas: 395 };
      const LIM: Record<string, [number, number]> = { ponto: [7, 730], evidencias: [7, 730], atestados: [7, 730], notas: [90, 1825], backups: [3, 365] };
      const { data: sv } = await svc.from("sistema").select("valor").eq("chave", "DRIVE_PRAZOS").maybeSingle();
      const { data: bc } = await svc.from("backup_config").select("auto_retencao_dias").eq("id", true).single();
      const atual: Record<string, number> = { ...PADRAO }; for (const k of Object.keys(PADRAO)) { const n = Number((sv?.valor as any)?.[k]); if (n >= 1) atual[k] = Math.round(n); }
      atual.backups = bc?.auto_retencao_dias ?? 30;
      if (acao === "prazosSalvar") {
        const novo: Record<string, number> = {};
        for (const k of Object.keys(LIM)) {
          const n = Math.round(Number(b.prazos?.[k] ?? atual[k]));
          if (!(n >= LIM[k][0] && n <= LIM[k][1])) return json({ ok: false, message: `Prazo inválido em "${k}": use de ${LIM[k][0]} a ${LIM[k][1]} dias. Nada foi salvo.` }, 400);
          novo[k] = n;
        }
        const { error: e1 } = await svc.from("sistema").upsert({ chave: "DRIVE_PRAZOS", valor: { ponto: novo.ponto, evidencias: novo.evidencias, atestados: novo.atestados, notas: novo.notas }, atualizado_em: new Date().toISOString() });
        if (e1) throw new Error(e1.message);
        const { error: e2 } = await svc.from("backup_config").update({ auto_retencao_dias: novo.backups }).eq("id", true);
        if (e2) throw new Error(e2.message);
        await auditar(svc, a, "Drive: prazos de guarda alterados", Object.entries(novo).map(([k, v]) => k + " " + v + " dias").join(" · "));
        return json({ ok: true, prazos: novo });
      }
      const { data: auto } = await svc.from("sistema").select("valor").eq("chave", "DRIVE_LIMPEZA_AUTO").maybeSingle();
      return json({ ok: true, prazos: atual, padroes: { ...PADRAO, backups: 30 }, limites: LIM, limpezaAuto: auto?.valor ?? null });
    }

    if (acao === "oauthUrl") {
      await auditar(svc, a, "Drive: conectar conta", NOMES[conta]);
      const retorno = String(b.retorno || ""); if (!/^https:\/\//.test(retorno)) return json({ ok: false, message: "Endereço de retorno inválido." }, 400);
      const { id } = await credenciais();
      await svc.from("drive_oauth_estados").delete().lt("criado_em", new Date(Date.now() - 3600000).toISOString());
      const estado = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
      await svc.from("drive_oauth_estados").insert({ estado, conta, retorno: retorno.split("#")[0].split("?")[0], usuario_id: a.usuario?.id ?? null });
      const u = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      u.searchParams.set("client_id", id); u.searchParams.set("redirect_uri", REDIRECT); u.searchParams.set("response_type", "code");
      u.searchParams.set("scope", ESCOPO); u.searchParams.set("access_type", "offline"); u.searchParams.set("prompt", "consent select_account");
      u.searchParams.set("include_granted_scopes", "true"); u.searchParams.set("state", estado);
      return json({ ok: true, url: u.toString() });
    }

    if (acao === "desconectar") {
      try {   // avisa o Google para revogar (se falhar, só apaga aqui)
        const { data: refresh } = await svc.rpc("drive_ler_token", { p_conta: conta });
        if (refresh) await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(refresh as string), { method: "POST" });
      } catch { /* segue */ }
      const { error } = await svc.rpc("drive_desconectar", { p_conta: conta });
      if (error) throw new Error(error.message);
      await auditar(svc, a, "Drive: desconectar conta", NOMES[conta]);
      return json({ ok: true });
    }

    if (acao === "listar") {
      const pasta = String(b.pastaId || "root");
      const l = await listar(conta, pasta, b.pageToken);
      const info = await nomeDaPasta(conta, pasta);
      return json({ ok: true, pasta: typeof info === "string" ? { nome: info, pai: null } : info, arquivos: l.files || [], proxima: l.nextPageToken || null });
    }

    if (acao === "baixar") {
      const id = String(b.fileId || ""); if (!id) return json({ ok: false, message: "Informe o arquivo." }, 400);
      const meta = await (await g(conta, `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}?fields=id,name,mimeType,size`)).json();
      const nativo = String(meta.mimeType || "").startsWith("application/vnd.google-apps.");
      if (meta.mimeType === "application/vnd.google-apps.folder") return json({ ok: false, message: "Isto é uma pasta." }, 400);
      if (!nativo && Number(meta.size || 0) > MAX_BAIXAR) return json({ ok: false, message: `Arquivo grande demais para baixar por aqui (${Math.round(Number(meta.size) / 1048576)} MB; o limite é 25 MB). Abra pelo Google Drive.` }, 413);
      const url = nativo ? `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}/export?mimeType=application/pdf` : `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(id)}?alt=media`;
      const bytes = new Uint8Array(await (await g(conta, url)).arrayBuffer());
      if (bytes.length > MAX_BAIXAR) return json({ ok: false, message: "Arquivo grande demais para baixar por aqui (limite 25 MB)." }, 413);
      return json({ ok: true, nome: nativo ? meta.name + ".pdf" : meta.name, mime: nativo ? "application/pdf" : meta.mimeType, base64: b64(bytes) });
    }

    if (acao === "enviar") {
      const { nome, mime, base64 } = b, pasta = String(b.pastaId || "root");
      if (!nome || !base64) return json({ ok: false, message: "Arquivo ausente." }, 400);
      const bytes = bytesDe(String(base64));
      if (bytes.length > MAX_ENVIAR) return json({ ok: false, message: "Arquivo grande demais (limite 20 MB por envio)." }, 413);
      const r = await enviarArquivo(conta, pasta, String(nome).slice(0, 200), String(mime || "application/octet-stream"), bytes);
      await auditar(svc, a, "Drive: arquivo enviado", `${NOMES[conta]} · ${String(nome).slice(0, 120)}`);
      return json({ ok: true, id: r.id, nome: r.name });
    }

    if (acao === "criarPasta") {
      const nome = String(b.nome || "").trim().slice(0, 100); if (!nome) return json({ ok: false, message: "Informe o nome da pasta." }, 400);
      const id = await acharOuCriarPasta(conta, nome, String(b.pastaId || "root"));
      return json({ ok: true, id });
    }
    return json({ ok: false, message: "Ação desconhecida." }, 400);
  } catch (e) { return json({ ok: false, message: (e as Error).message }, 500); }
});
