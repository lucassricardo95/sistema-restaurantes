import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
export const URL_ = Deno.env.get("SUPABASE_URL")!;
export const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Configurações: primeiro a variável de ambiente (secrets), senão o Vault do banco (api_segredo, só service_role).
const VAULT: Record<string, string> = { SHEETS_MAIN_URL: "sheets_main_url", PRINCIPAL_CHAVE_SERVIDOR: "chave_servidor_planilha",
  SB_PUBLISHABLE_KEY: "publishable_key", SB_SECRET_KEY: "service_key",
  GOOGLE_CLIENT_ID: "google_client_id", GOOGLE_CLIENT_SECRET: "google_client_secret" };
export async function cfg(nome: string): Promise<string> {
  const e = Deno.env.get(nome); if (e) return e;
  try { const { data } = await createClient(URL_, SVC).rpc("api_segredo", { p_nome: VAULT[nome] }); return (data as string) || ""; } catch { return ""; }
}
// Chave nova (sb_secret_…), a que o Vault entrega aos crons. Aceita as duas.
export const SB_SECRET = await cfg("SB_SECRET_KEY");
export const CHAVE_SERVICO = SB_SECRET || SVC;
export const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey" };
export const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
export const svcClient = () => createClient(URL_, CHAVE_SERVICO);

// Quem chama? "servico" = cron/outra função (chave de serviço). Senão confere o login e o nível.
// Assume usuarios.id = auth.users.id. Desenvolvedor vale como Admin (igual ao auth_nivel() do banco).
export async function autorizar(req: Request, niveis: string[] | null) {
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return { ok: false as const, status: 401, message: "Sem autenticação." };
  if (token === SVC || (SB_SECRET && token === SB_SECRET)) return { ok: true as const, servico: true, usuario: null as any };
  if (!niveis) return { ok: false as const, status: 403, message: "Só execução interna." };
  const svc = svcClient();
  const { data: u } = await svc.auth.getUser(token);
  if (!u?.user) return { ok: false as const, status: 401, message: "Sessão inválida." };
  const { data: usr } = await svc.from("usuarios").select("id,nivel,ativo").eq("id", u.user.id).single();
  const nivelEf = usr?.nivel === "Desenvolvedor" ? "Admin" : usr?.nivel;
  if (!usr || usr.ativo === false || !niveis.includes(nivelEf))
    return { ok: false as const, status: 403, message: "Sem permissão." };
  return { ok: true as const, servico: false, usuario: usr };
}
