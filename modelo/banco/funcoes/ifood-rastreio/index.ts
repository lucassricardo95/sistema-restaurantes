// ifood-rastreio · DESATIVADA. O "Acompanhar entrega" agora usa os eventos oficiais de entrega recebidos pela consulta do ifood-sync.
Deno.serve(() => new Response(JSON.stringify({ ok: true, desativada: true }), { headers: { "Content-Type": "application/json" } }));
