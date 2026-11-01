import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { CORS, json, svcClient } from "./auth.ts";
// Público de propósito (UptimeRobot): só devolve se o banco respondeu. Uma consulta leve a cada chamada
// evita que o projeto gratuito seja pausado por inatividade. Nenhum dado é exposto.
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { error } = await svcClient().from("sistema").select("chave").limit(1);
    if (error) return json({ ok: false }, 503);
    return json({ ok: true, em: new Date().toISOString() });
  } catch { return json({ ok: false }, 503); }
});
