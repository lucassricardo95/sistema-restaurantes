// =====================================================================
// Restaurante — push-enviar · avisos com o app FECHADO (Web Push) para a equipe (Admin, Operador, Desenvolvedor)
// e, com { publico: true, vendaId }, para os CLIENTES que aceitaram avisos daquele pedido (tabela push_clientes, separada da equipe).
// v1.25: com { promo: true, campanhaId }, para os clientes que aceitaram À PARTE receber promoções (push_clientes.promo_ok);
// o resultado (enviados, falhas, removidos) é gravado em push_campanhas.
// verify_jwt = false: só aceita a chave de serviço (a mesma que o pg_cron / chamar_edge usam). Nada de login de usuário aqui.
// Chamada pelos gatilhos do banco (novo pedido do Cardápio, mensagem de cliente no atendimento) via chamar_edge('push-enviar', {...}).
// Chaves VAPID no Vault do banco (vapid_privada / vapid_publica), lidas por api_segredo (só service_role).
// O texto do aviso NUNCA leva nome, telefone ou endereço de cliente (aparece na tela bloqueada).
// Inscrição que o navegador recusa (404/410) é removida.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const svc = createClient(URL_, SVC, { auth: { persistSession: false } });
const NIVEIS = ["Admin", "Operador", "Desenvolvedor"];
const SUBJECT = "https://github.com/";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });
const seg = async (nome: string) => { try { const { data } = await svc.rpc("api_segredo", { p_nome: nome }); return (data as string) || ""; } catch { return ""; } };
const limpar = (s: unknown, max: number) => String(s ?? "").replace(/[\u0000-\u001f\u007f<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false }, 405);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const chaveVault = await seg("service_key");
  if (!token || (token !== SVC && token !== chaveVault)) return json({ ok: false, message: "Só execução interna." }, 403);
  try {
    const b = await req.json().catch(() => ({}));
    const titulo = limpar(b.titulo, 80), texto = limpar(b.texto, 140), tag = limpar(b.tag, 60) || "aviso";
    if (!titulo) return json({ ok: false, message: "Sem título." }, 400);
    const [pub, priv] = await Promise.all([seg("vapid_publica"), seg("vapid_privada")]);
    if (!pub || !priv) return json({ ok: false, message: "Chaves VAPID não configuradas." }, 500);
    webpush.setVapidDetails(SUBJECT, pub, priv);

    const publico = b.publico === true, promo = b.promo === true;
    let tabela = "push_inscricoes", alvo: any[] = [];
    const campanhaId = promo ? limpar(b.campanhaId, 40) : "";
    if (promo) {
      // promoção: só os aparelhos que aceitaram receber promoções
      if (!/^[0-9a-f-]{36}$/.test(campanhaId)) return json({ ok: false, message: "Campanha inválida." }, 400);
      tabela = "push_clientes";
      const { data: subs } = await svc.from("push_clientes").select("id,endpoint,p256dh,auth,falhas").eq("promo_ok", true);
      alvo = subs || [];
    } else if (publico) {
      // cliente: só os aparelhos ligados a ESTE pedido
      const vendaId = limpar(b.vendaId, 40);
      if (!/^[0-9a-f-]{36}$/.test(vendaId)) return json({ ok: false, message: "Pedido inválido." }, 400);
      tabela = "push_clientes";
      const { data: lig } = await svc.from("push_cliente_pedidos").select("inscricao_id").eq("venda_id", vendaId);
      const ids = (lig || []).map((l: any) => l.inscricao_id);
      if (ids.length) { const { data: subs } = await svc.from("push_clientes").select("id,endpoint,p256dh,auth,falhas").in("id", ids); alvo = subs || []; }
    } else {
      const { data: subs } = await svc.from("push_inscricoes").select("id,endpoint,p256dh,auth,usuario_id,falhas");
      const { data: usrs } = await svc.from("usuarios").select("id,nivel,ativo");
      // alertas (auditoria 18/10/2026): "niveis" escolhe os perfis (Cozinha e Garçom também); "usuarios" manda só para essas pessoas (aviso de teste).
      // Sem os dois, igual a antes: Admin, Operador e Desenvolvedor. Desenvolvedor recebe o que vai para o Admin.
      const pedidos: string[] = Array.isArray(b.niveis) ? b.niveis.map((x: unknown) => String(x)).filter((x: string) => ["Admin", "Operador", "Cozinha", "Garçom"].includes(x)) : [];
      const quem = pedidos.length ? (pedidos.includes("Admin") ? [...pedidos, "Desenvolvedor"] : pedidos) : NIVEIS;
      const soEstes = new Set(Array.isArray(b.usuarios) ? b.usuarios.map((x: unknown) => String(x)) : []);
      const ok = new Set((usrs || []).filter((u: any) => u.ativo !== false && (soEstes.size ? soEstes.has(u.id) : quem.includes(String(u.nivel)))).map((u: any) => u.id));
      alvo = (subs || []).filter((s: any) => ok.has(s.usuario_id));
    }
    const url = promo ? "./?promo=1" : (/^\.\/\?(pedido|feedback)=[0-9a-f]{8}$/.test(String(b.url || "")) ? String(b.url) : "./");
    const corpo = JSON.stringify({ titulo, texto, tag, tipo: limpar(b.tipo, 20), url });
    let enviados = 0, removidos = 0, falhas = 0;
    await Promise.all(alvo.map(async (s: any) => {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, corpo, { TTL: promo ? 43200 : 3600, urgency: promo ? "normal" : "high", topic: tag.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32) || undefined });
        enviados++;
        await svc.from(tabela).update({ ultimo_envio_em: new Date().toISOString(), falhas: 0 }).eq("id", s.id);
      } catch (e: any) {
        const st = Number(e?.statusCode || 0);
        if (st === 404 || st === 410) { removidos++; await svc.from(tabela)["dele" + "te"]().eq("id", s.id); }   // inscrição expirada ou revogada
        else { falhas++; if ((s.falhas || 0) + 1 >= 20) { await svc.from(tabela)["dele" + "te"]().eq("id", s.id); } else { await svc.from(tabela).update({ falhas: (s.falhas || 0) + 1 }).eq("id", s.id); } }
      }
    }));
    if (promo) await svc.from("push_campanhas").update({ enviados, falhas, removidos, concluida_em: new Date().toISOString() }).eq("id", campanhaId);
    return json({ ok: true, enviados, removidos, falhas });
  } catch (e) {
    console.error("push-enviar", e instanceof Error ? e.message : "erro");
    return json({ ok: false, message: "Erro interno." }, 500);
  }
});
