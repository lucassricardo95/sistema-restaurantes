import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, URL_, CHAVE_SERVICO, cfg } from "./auth.ts";
import { lerBackupDrive } from "./drive.ts";

async function gunzip(bytes: Uint8Array): Promise<string> {
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return await new Response(s).text();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);   // quem manda é o login, não o usuarioId do corpo
  if (!a.ok || a.servico) return json({ ok: false, message: a.ok ? "Só o Admin logado restaura." : a.message }, a.ok ? 403 : a.status);
  const svc = svcClient();
  let manutencao = false;
  try {
    const { backupId, senhaAdmin } = await req.json();
    if (!backupId || !senhaAdmin) return json({ ok: false, message: "Dados incompletos." }, 400);

    // Confere a senha do Admin no servidor, do mesmo jeito que o login do app (e-mail montado a partir do login).
    const { data: u } = await svc.from("usuarios").select("login").eq("id", a.usuario.id).single();
    const email = String(u?.login || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim() + "@usuarios.restaurante.app";
    const chavePub = (await cfg("SB_PUBLISHABLE_KEY")) || Deno.env.get("SUPABASE_ANON_KEY")!;
    const rs = await fetch(`${URL_}/auth/v1/token?grant_type=password`, { method: "POST",
      headers: { apikey: chavePub, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: senhaAdmin }) });
    if (!rs.ok) return json({ ok: false, message: "Senha incorreta." }, 403);

    const { data: bk } = await svc.from("backups").select("arquivo,armazenado_em").eq("id", backupId).eq("status", "Sucesso").single();
    if (!bk?.arquivo) return json({ ok: false, message: "Backup não encontrado." }, 404);

    // O backup mora no Drive (ou, nos de segurança/antigos, no Storage). Lê ANTES de mexer em qualquer coisa.
    let bytes: Uint8Array | undefined; let erroLeitura = "";
    if (bk.armazenado_em === "drive") { const l = await lerBackupDrive(bk.arquivo); bytes = l.bytes; erroLeitura = l.erro || ""; }
    else { const { data: arq } = await svc.storage.from("backups").download(bk.arquivo); if (arq) bytes = new Uint8Array(await arq.arrayBuffer()); else erroLeitura = "Arquivo não está no Storage."; }
    if (!bytes) return json({ ok: false, message: "Não consegui ler o arquivo deste backup (" + erroLeitura + "). Confira se o Drive está conectado. Nada foi alterado." }, 500);
    const dados = JSON.parse(await gunzip(bytes));

    // Backup de segurança antes de mexer em qualquer coisa — se falhar, aborta
    const pre = await fetch(`${URL_}/functions/v1/criar-backup`, { method: "POST",
      headers: { Authorization: `Bearer ${CHAVE_SERVICO}`, "Content-Type": "application/json" },
      body: JSON.stringify({ tipo: "Pré-restauração", usuarioId: a.usuario.id }) });
    const preJ = await pre.json().catch(() => ({}));
    if (!preJ.ok) return json({ ok: false, message: "Não foi possível criar o backup de segurança. Nada foi alterado." }, 500);


    await svc.from("sistema").upsert({ chave: "MANUTENCAO", valor: { mensagem: "Restaurando os dados — aguarde alguns minutos.", desde: new Date().toISOString() } }, { onConflict: "chave" });
    manutencao = true;

    // Tudo numa única transação no banco (restaurar_backup_dados): grava por cima, remove só o que não estava no
    // backup, confere a contagem de cada tabela e, se qualquer passo falhar, desfaz tudo (nada fica pela metade).
    const { data: res, error: eRest } = await svc.rpc("restaurar_backup_dados", { p_dados: dados });
    if (eRest) throw new Error(eRest.message);
    const nTab = Number(res?.tabelas ?? 0);
    await svc.from("sistema").upsert({ chave: "MANUTENCAO", valor: false }, { onConflict: "chave" });   // a linha existe e o app só liga o aviso se o valor for verdadeiro
    await svc.from("auditoria").insert({ acao: "Backup restaurado", usuario_id: a.usuario.id, usuario_login: u?.login ?? null, detalhes: `Backup ${backupId} · ${nTab} tabelas` });
    return json({ ok: true, message: `Restaurado. ${nTab} tabelas.` });
  } catch (e) {
    if (manutencao) await svc.from("sistema").upsert({ chave: "MANUTENCAO", valor: false }, { onConflict: "chave" });
    return json({ ok: false, message: (e as Error).message + ". O banco continua como estava (a restauração é tudo ou nada)." }, 500);
  }
});
