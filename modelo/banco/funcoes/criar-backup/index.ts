import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient, autorizar, cfg } from "./auth.ts";
import { contaConectada, acharOuCriarPasta, enviarArquivo, apagarAntigos, lerBackupDrive, PASTA_BACKUP_DIRETO } from "./drive.ts";

// A lista de tabelas vem do banco (backup_tabelas): tudo do schema public, menos segredos e dados deriváveis
// (ver _backup_excluidas no SQL 2026-10-15-backup-restauracao.sql). Tabela nova entra sozinha.

async function gzip(bytes: Uint8Array): Promise<Uint8Array> {   // nativo, sem biblioteca externa
  const s = new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}
function paraBase64(bytes: Uint8Array): string {
  let s = ""; const C = 0x8000;
  for (let i = 0; i < bytes.length; i += C) s += String.fromCharCode(...bytes.subarray(i, i + C));
  return btoa(s);
}
const espera = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Segunda cópia do backup: vai para uma pasta do Google Drive pela planilha principal (Apps Script).
// Tenta até 2 vezes (no máx. ~45 s, para caber no limite da função) (a planilha pode estar ocupada ou "acordando") e grava o motivo REAL do erro.
// O backup mora no DRIVE (Storage do Supabase fica livre para dados antigos arquivados). Só se NENHUM Drive direto aceitar a cópia é que o arquivo fica no Storage como segurança;
// aí o motivo real fica em backups.copia_drive_erro, aparece na tela e o botão "Enviar ao Drive" repete depois (e tira do Storage).
async function copiarParaDrive(nome: string, gz: Uint8Array, retencaoDias: number): Promise<{ ok: boolean; erro?: string }> {
  const url = await cfg("SHEETS_MAIN_URL"), chave = await cfg("PRINCIPAL_CHAVE_SERVIDOR");
  if (!url || !chave) return { ok: false, erro: "Planilha principal não configurada." };
  const corpo = JSON.stringify({ action: "sbGuardarBackup", chave, nome, base64: paraBase64(gz), retencaoDias });
  let erro = "";
  for (let tent = 1; tent <= 2; tent++) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 20000);
    try {
      const r = await fetch(url, { method: "POST", headers: { "Content-Type": "text/plain" }, body: corpo, signal: ctl.signal, redirect: "follow" });
      const txt = await r.text();
      let j: any = null; try { j = JSON.parse(txt); } catch { /* resposta não é JSON */ }
      if (j?.ok) return { ok: true };
      erro = j ? String(j.message || j.erro || (j.manutencao ? "Planilha em manutenção." : j.ocupado ? "Planilha ocupada." : "Resposta sem mensagem: " + txt.slice(0, 120))) : `HTTP ${r.status}: ${txt.replace(/\s+/g, " ").slice(0, 160)}`;
    } catch (e) { erro = (e as Error).name === "AbortError" ? "A planilha demorou mais de 20 s para responder." : (e as Error).message; }
    finally { clearTimeout(t); }
    if (tent < 2) await espera(5000);
  }
  return { ok: false, erro: (erro + " (2 tentativas)").slice(0, 300) };
}

// Caminho direto (sem Apps Script): envia o backup pelo Drive autorizado por OAuth. Pasta própria em cada Drive conectado.
// Só os backups AUTOMÁTICOS antigos saem da pasta (manuais e pré-restauração ficam), igual ao Storage.
const PASTA_DIRETA = PASTA_BACKUP_DIRETO;
async function copiarDireto(nome: string, gz: Uint8Array, retencaoDias: number): Promise<{ principal: boolean | null; contingencia: boolean | null; erros: string[] }> {
  const r: { principal: boolean | null; contingencia: boolean | null; erros: string[] } = { principal: null, contingencia: null, erros: [] };
  for (const conta of ["principal", "contingencia"] as const) {
    try {
      if (!(await contaConectada(conta))) continue;
      const pasta = await acharOuCriarPasta(conta, PASTA_DIRETA, "root");
      await enviarArquivo(conta, pasta, nome, "application/gzip", gz);
      r[conta] = true;
      try { await apagarAntigos(conta, pasta, new Date(Date.now() - retencaoDias * 86400000).toISOString(), "-auto"); } catch { /* limpeza é opcional */ }
    } catch (e) { r[conta] = false; r.erros.push(`${conta === "principal" ? "Drive principal" : "Drive da contingência"}: ${(e as Error).message}`); }
  }
  return r;
}
// Resume as duas vias num único estado para a tabela backups
function resumoDrive(apps: { ok: boolean; erro?: string }, d: { principal: boolean | null; contingencia: boolean | null; erros: string[] }) {
  const ok = apps.ok || d.principal === true;
  const avisos: string[] = [];
  if (!apps.ok) avisos.push(`Apps Script falhou (${apps.erro || "sem motivo"})` + (d.principal ? "; a cópia foi feita pelo Drive direto." : "."));
  if (d.erros.length) avisos.push(d.erros.join(" | "));
  return { ok, erro: avisos.length ? avisos.join(" ").slice(0, 400) : null };
}

// Lê o arquivo de um backup de onde ele estiver (Drive ou, nos antigos/de segurança, Storage).
async function lerBackupArquivo(svc: any, b: { arquivo: string; armazenado_em?: string }): Promise<{ bytes?: Uint8Array; erro?: string }> {
  if (b.armazenado_em === "drive") return await lerBackupDrive(b.arquivo);
  const { data: arq, error } = await svc.storage.from("backups").download(b.arquivo);
  if (error || !arq) return { erro: "Não consegui ler o arquivo do backup no Storage." };
  return { bytes: new Uint8Array(await arq.arrayBuffer()) };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const a = await autorizar(req, ["Admin"]);
  if (!a.ok) return json({ ok: false, message: a.message }, a.status);
  const svc = svcClient();
  let bkId: string | undefined;
  try {
    const body = await req.json().catch(() => ({}));

    // Reenviar ao Drive um backup que ficou sem cópia (não cria backup novo)
    if (body.reenviarDrive) {
      const { data: b } = await svc.from("backups").select("id,arquivo,status,armazenado_em").eq("id", body.reenviarDrive).maybeSingle();
      if (!b?.arquivo || b.status !== "Sucesso") return json({ ok: false, message: "Backup não encontrado." }, 404);
      const lido = await lerBackupArquivo(svc, b);
      if (!lido.bytes) return json({ ok: false, message: lido.erro || "Não consegui ler o arquivo do backup." }, 500);
      const { data: c2 } = await svc.from("backup_config").select("auto_retencao_dias").eq("id", true).single();
      const bytesArq = lido.bytes;
      const d = await copiarParaDrive(b.arquivo, bytesArq, c2?.auto_retencao_dias ?? 7);
      const dir = await copiarDireto(b.arquivo, bytesArq, c2?.auto_retencao_dias ?? 7);
      const res = resumoDrive(d, dir);
      const noDrive = dir.principal === true || dir.contingencia === true;
      if (noDrive && b.armazenado_em === "storage") { await svc.storage.from("backups").remove([b.arquivo]); await svc.from("backups").update({ armazenado_em: "drive" }).eq("id", b.id); }
      await svc.from("backups").update(res.ok ? { copia_drive_em: new Date().toISOString(), copia_drive_erro: res.erro } : { copia_drive_erro: res.erro }).eq("id", b.id);
      return json({ ok: res.ok, drive: res.ok, message: res.ok ? (res.erro ? "Cópia enviada ao Drive. Aviso: " + res.erro : "Cópia enviada ao Drive.") : (res.erro || "Falhou.") });
    }

    // Move para o Drive os backups que ainda estão no Storage (uso único; depois de confirmar a cópia no Drive, apaga do Storage)
    if (body.moverParaDrive) {
      const { data: lista } = await svc.from("backups").select("id,arquivo,armazenado_em").eq("status", "Sucesso").eq("armazenado_em", "storage");
      const { data: c3 } = await svc.from("backup_config").select("auto_retencao_dias").eq("id", true).single();
      let movidos = 0; const falhas: string[] = [];
      for (const x of lista || []) {
        if (!x.arquivo) continue;
        const { data: arq } = await svc.storage.from("backups").download(x.arquivo);
        if (!arq) { falhas.push(x.arquivo + ": não li do Storage"); continue; }
        const bytes = new Uint8Array(await arq.arrayBuffer());
        const dir = await copiarDireto(x.arquivo, bytes, 3650);
        if (dir.principal === true || dir.contingencia === true) {
          const conf = await lerBackupDrive(x.arquivo);   // só apaga do Storage depois de reler do Drive
          if (conf.bytes && conf.bytes.length === bytes.length) { await svc.storage.from("backups").remove([x.arquivo]); await svc.from("backups").update({ armazenado_em: "drive", copia_drive_em: new Date().toISOString(), copia_drive_erro: null }).eq("id", x.id); movidos++; }
          else falhas.push(x.arquivo + ": não conferiu no Drive");
        } else falhas.push(x.arquivo + ": " + (dir.erros.join(" | ") || "nenhum Drive conectado"));
      }
      return json({ ok: falhas.length === 0, movidos, falhas, message: `${movidos} backup(s) movido(s) para o Drive.` + (falhas.length ? " Falhas: " + falhas.join("; ") : "") });
    }

    const tipo = ["Manual", "Automático", "Pré-restauração"].includes(body.tipo) ? body.tipo : "Manual";
    const usuarioId = a.usuario?.id ?? body.usuarioId ?? null;

    if (tipo === "Automático") {
      // liga/desliga e hora ficam nas chaves já existentes da tabela sistema (as mesmas da tela de Backup)
      const { data: cfgs } = await svc.from("sistema").select("chave,valor").in("chave", ["BACKUP_AUTO_ATIVO", "BACKUP_HORA"]);
      const v = (k: string) => cfgs?.find((c) => c.chave === k)?.valor;
      if (v("BACKUP_AUTO_ATIVO") !== true) return json({ ok: true, message: "Backup automático desligado." });
      if (body.cron) {   // chamada de hora em hora pelo cron: só roda na hora escolhida (Brasília) e uma vez por dia
        const hora = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "America/Sao_Paulo", hour: "2-digit", hour12: false }).format(new Date()));
        if (hora !== Number(v("BACKUP_HORA") ?? 4)) return json({ ok: true, message: "Fora do horário." });
        const { count } = await svc.from("backups").select("*", { count: "exact", head: true })
          .eq("tipo", "Automático").eq("status", "Sucesso").gte("data_hora", new Date(Date.now() - 20 * 3600000).toISOString());
        if ((count || 0) > 0) return json({ ok: true, message: "Já feito hoje." });
      }
    }

    const { data: bk } = await svc.from("backups").insert({ tipo, usuario_id: usuarioId, status: "Em andamento" }).select("id").single();
    bkId = bk?.id;

    const { data: lista, error: eLista } = await svc.rpc("backup_tabelas");
    if (eLista || !Array.isArray(lista) || !lista.length) throw new Error("Lista de tabelas do backup: " + (eLista?.message || "vazia (rode o SQL 2026-10-15-backup-restauracao.sql)"));

    const dados: Record<string, unknown> = { gerado_em: new Date().toISOString(), versao: 2 };
    for (const { tabela: t, chaves } of lista as { tabela: string; chaves: string[] }[]) {
      let todos: any[] = [], de = 0; const TAM = 1000;
      for (;;) {
        let q = svc.from(t).select("*");
        for (const c of chaves) q = q.order(c);   // ordem estável pela chave primária (inclusive composta)
        const r = await q.range(de, de + TAM - 1);
        if (r.error) throw new Error(`Leitura de ${t}: ${r.error.message}`);
        if (!r.data?.length) break;
        todos = todos.concat(r.data);
        if (r.data.length < TAM) break;
        de += TAM;
      }
      dados[t] = todos;
    }

    const gz = await gzip(new TextEncoder().encode(JSON.stringify(dados)));
    const nome = `backup-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")}-${tipo === "Pré-restauração" ? "pre" : tipo === "Automático" ? "auto" : "manual"}.json.gz`;
    const { data: cfg2 } = await svc.from("backup_config").select("auto_retencao_dias").eq("id", true).single();
    const retDias = cfg2?.auto_retencao_dias ?? 7;

    // 1) Copia para o Drive (direto = o que dá para ler de volta e restaurar; Apps Script = segunda via). Nada disso derruba o backup.
    const direto = await copiarDireto(nome, gz, retDias);
    const apps = await copiarParaDrive(nome, gz, retDias);
    const res = resumoDrive(apps, direto);
    const noDrive = direto.principal === true || direto.contingencia === true;

    // 2) Só se NENHUM Drive direto aceitou a cópia, o arquivo fica no Storage (segurança); senão o Storage não é usado.
    if (!noDrive) {
      const { error: up } = await svc.storage.from("backups").upload(nome, gz, { contentType: "application/gzip", upsert: false });
      if (up) throw new Error("Sem cópia no Drive e o Storage também recusou: " + up.message + (res.erro ? " | " + res.erro : ""));
    }
    await svc.from("backups").update({ status: "Sucesso", arquivo: nome, tamanho_bytes: gz.length, armazenado_em: noDrive ? "drive" : "storage" }).eq("id", bkId);
    const drive = { ok: res.ok, erro: res.erro || undefined };
    await svc.from("backups").update(res.ok ? { copia_drive_em: new Date().toISOString(), copia_drive_erro: res.erro } : { copia_drive_erro: (res.erro || "Nenhum Drive conectado") + (noDrive ? "" : " O backup ficou guardado no Storage do Supabase até o Drive voltar.") }).eq("id", bkId);

    // Retenção: só apaga backups AUTOMÁTICOS antigos (manuais e pré-restauração ficam)
    const corte = new Date(Date.now() - retDias * 86400000).toISOString();
    const { data: antigos } = await svc.from("backups").select("id,arquivo,armazenado_em").eq("tipo", "Automático").lt("data_hora", corte);
    for (const x of antigos || []) {
      if (x.arquivo && x.armazenado_em === "storage") await svc.storage.from("backups").remove([x.arquivo]);
      await svc.from("backups").delete().eq("id", x.id);
    }
    return json({ ok: true, arquivo: nome, tamanho: gz.length, drive: drive.ok, driveErro: drive.erro, guardadoEm: noDrive ? "drive" : "storage" });
  } catch (e) {
    if (bkId) await svc.from("backups").update({ status: "Erro", erro: (e as Error).message.slice(0, 500) }).eq("id", bkId);
    return json({ ok: false, message: (e as Error).message }, 500);
  }
});
