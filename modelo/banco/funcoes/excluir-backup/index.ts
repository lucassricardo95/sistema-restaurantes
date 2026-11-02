import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, URL_, cfg } from "./auth.ts";
import { apagarBackupDrive } from "./drive.ts";

// Exclui UM backup (arquivo no Drive ou, nos de segurança, no Storage + linha da tabela). Só Admin logado, com a senha do Admin conferida aqui no servidor.
// Nunca apaga backup em andamento nem o último backup com sucesso. No Drive o arquivo vai para a lixeira (recuperável por 30 dias).
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok || a.servico) return json({ ok: false, message: a.ok ? "Só o Admin logado exclui backups." : a.message }, a.ok ? 403 : a.status);
  const svc = svcClient();
  try {
    const { backupId, senhaAdmin } = await req.json();
    if (!backupId || !senhaAdmin) return json({ ok: false, message: "Dados incompletos." }, 400);

    const { data: u } = await svc.from("usuarios").select("login").eq("id", a.usuario.id).single();
    const email = String(u?.login || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim() + "@usuarios.restaurante.app";
    const chavePub = (await cfg("SB_PUBLISHABLE_KEY")) || Deno.env.get("SUPABASE_ANON_KEY")!;
    const rs = await fetch(`${URL_}/auth/v1/token?grant_type=password`, { method: "POST",
      headers: { apikey: chavePub, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: senhaAdmin }) });
    if (!rs.ok) return json({ ok: false, message: "Senha incorreta." }, 403);

    const { data: bk } = await svc.from("backups").select("id,arquivo,status,tipo,data_hora,armazenado_em").eq("id", backupId).maybeSingle();
    if (!bk) return json({ ok: false, message: "Backup não encontrado." }, 404);
    if (bk.status === "Em andamento") return json({ ok: false, message: "Este backup ainda está em andamento." }, 409);
    if (bk.status === "Sucesso") {
      const { count } = await svc.from("backups").select("*", { count: "exact", head: true }).eq("status", "Sucesso").neq("id", backupId);
      if (!count) return json({ ok: false, message: "Este é o único backup com sucesso. Faça outro antes de excluir." }, 409);
    }
    if (bk.arquivo) {
      if (bk.armazenado_em === "drive") {
        // O arquivo mora no Drive: vai para a lixeira do Drive (dá para recuperar por 30 dias).
        const r = await apagarBackupDrive(bk.arquivo);
        if (r.erros.length && !r.apagados) return json({ ok: false, message: "Não consegui apagar o arquivo no Drive: " + r.erros.join(" | ").slice(0, 200) }, 500);
      } else {
        const { error: er } = await svc.storage.from("backups").remove([bk.arquivo]);
        if (er) return json({ ok: false, message: "Não consegui apagar o arquivo: " + er.message }, 500);
      }
    }
    const { error: ed } = await svc.from("backups").delete().eq("id", backupId);
    if (ed) return json({ ok: false, message: "Arquivo apagado, mas não consegui tirar da lista: " + ed.message }, 500);
    await svc.from("auditoria").insert({ acao: "Backup excluído", usuario_id: a.usuario.id, usuario_login: u?.login ?? null, detalhes: `Backup ${backupId} · ${bk.tipo} · ${bk.data_hora}` });
    return json({ ok: true, message: "Backup excluído." });
  } catch (e) {
    return json({ ok: false, message: (e as Error).message }, 500);
  }
});
