// ifood-sync · gestão do catálogo no iFood (categorias, itens, grupos de complementos, complementos, preço/status em massa).
// ⚠️ Corpos e endereços seguem a documentação pública do Catalog v2 conforme conhecida; ainda NÃO testados com o iFood de verdade.
// Qualquer recusa do iFood aparece na tela "Cardápio no iFood" (texto do erro) e nos Logs da API do Developer Portal.
type Ctx = { chamar: (cred: any, metodo: string, caminho: string, corpo?: unknown) => Promise<any>; rpc: (fn: string, args?: Record<string, unknown>) => Promise<any>; HttpErro: any };

const numero = (v: unknown) => Number(String(v ?? 0).replace(",", "."));
const erroTexto = (ctx: Ctx, er: unknown) => {
  if (!(er instanceof ctx.HttpErro)) return String((er as any)?.message || er);
  const st = (er as any).status, c = String((er as any).corpo || "");
  const dica = st === 409 ? "Este código já está em uso em outro produto do seu cardápio no iFood (409)."
    : st === 422 ? "O iFood recusou por regra do cardápio (422): confira grupos (mínimo/máximo), complementos disponíveis e categoria."
    : st === 413 ? "A foto ou o envio é grande demais para o iFood (413). Use uma foto menor (até 5 MB)."
    : st === 404 ? "O iFood não encontrou o item ou a categoria (404). Envie primeiro a categoria e o item; confira se o código é um UUID."
    : st === 400 ? "O iFood recusou os dados (400)." : "";
  return (dica ? dica + " Resposta do iFood: " : `${st} `) + c.slice(0, 250);
};
const ERRO_VALIDACAO = "Antes de enviar: ";
function validarNome(n: string, rot: string) { if (!n || !String(n).trim()) throw new Error(ERRO_VALIDACAO + rot + " sem nome."); if (String(n).length > 100) throw new Error(ERRO_VALIDACAO + "o nome de \"" + String(n).slice(0, 30) + "…\" passa de 100 letras (limite do iFood)."); }
function validarDescricao(d: string, rot: string) { if (d && String(d).length > 500) throw new Error(ERRO_VALIDACAO + "a descrição de " + rot + " passa de 500 letras (limite do iFood)."); }
function validarPreco(v: unknown, rot: string, podeZero: boolean) { const n = numero(v); if (!Number.isFinite(n) || n < 0 || (!podeZero && n <= 0)) throw new Error(ERRO_VALIDACAO + "preço inválido em " + rot + (podeZero ? "." : " (precisa ser maior que zero).")); }
function validarFoto(dataUrl: string, rot: string) {
  const m = /^data:(image\/[a-z]+);base64,(.*)$/i.exec(dataUrl || "");
  if (!m) throw new Error(ERRO_VALIDACAO + "a foto de " + rot + " não é uma imagem válida.");
  if (!/^image\/(jpe?g|png)$/i.test(m[1])) throw new Error(ERRO_VALIDACAO + "a foto de " + rot + " precisa ser JPG ou PNG.");
  if (m[2].length * 0.75 > 5 * 1024 * 1024) throw new Error(ERRO_VALIDACAO + "a foto de " + rot + " passa de 5 MB.");
}
// tipo do grupo (obrigatório no iFood): OFFER_UNIT = escolha/adicional; INGREDIENTS = retirar/acrescentar ingrediente; SPECIFICATION = ponto da carne etc.; CUTLERY = talheres
function tipoGrupo(g: any): string {
  const t = String(g?.dados?.tipoGrupo || "").toUpperCase();
  if (["OFFER_UNIT", "INGREDIENTS", "SPECIFICATION", "CUTLERY"].includes(t)) return t;
  const n = String(g?.nome || "").toLowerCase();
  if (/retir|sem |ingredient/.test(n)) return "INGREDIENTS";
  if (/ponto|prepar|especifica/.test(n)) return "SPECIFICATION";
  if (/talher|garfo|faca|guardanapo/.test(n)) return "CUTLERY";
  return "OFFER_UNIT";
}

async function catalogoId(ctx: Ctx, cred: any, m: string): Promise<string> {
  const r: any = await ctx.chamar(cred, "GET", `/catalog/v2.0/merchants/${m}/catalogs`);
  const lista: any[] = Array.isArray(r) ? r : (r?.catalogs || []);
  const c = lista.find((x) => /DEFAULT/i.test(JSON.stringify(x.context || x.catalogContext || ""))) || lista[0];
  const id = c?.catalogId || c?.id;
  if (!id) throw new Error("o iFood não devolveu nenhum catálogo para a loja");
  return String(id);
}

async function subirFoto(ctx: Ctx, cred: any, m: string, dataUrl: string): Promise<string> {
  const r: any = await ctx.chamar(cred, "POST", `/catalog/v2.0/merchants/${m}/image/upload`, { image: dataUrl });
  const caminho = r?.imagePath || r?.path || r?.image || r?.url;
  if (!caminho) throw new Error("o iFood não devolveu o endereço da foto enviada");
  return String(caminho);
}

async function enviarCategoria(ctx: Ctx, cred: any, m: string, reg: any) {
  const d = reg.dados || {};
  validarNome(reg.nome, "uma categoria");
  const cid = await catalogoId(ctx, cred, m);
  const status = d.status === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE";
  let ifoodId = d.ifoodId as string | undefined;
  if (!ifoodId) {
    const r: any = await ctx.chamar(cred, "POST", `/catalog/v2.0/merchants/${m}/catalogs/${encodeURIComponent(cid)}/categories`, { name: reg.nome, status, template: "DEFAULT", sequence: 0 });
    ifoodId = r?.id || r?.categoryId;
    if (!ifoodId) throw new Error("o iFood não devolveu o código da categoria criada");
  } else {
    await ctx.chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/catalogs/${encodeURIComponent(cid)}/categories/${encodeURIComponent(ifoodId)}`, { name: reg.nome, status });
  }
  await ctx.rpc("ifood_cat_resultado", { p_id: reg.id, p_estado: "enviado", p_erro: null, p_patch: { ifoodId, catalogId: cid, enviado: { nome: reg.nome, status } } });
}

async function enviarItem(ctx: Ctx, cred: any, m: string, arv: any) {
  const reg = arv.registro, d = reg.dados || {};
  const cat = arv.categoria;
  if (!cat?.dados?.ifoodId) throw new Error("envie primeiro a categoria deste item ao iFood");
  const grupos: any[] = arv.grupos || [], opcoes: any[] = arv.opcoes || [];
  // C7: validar tudo antes de gastar chamadas
  validarNome(reg.nome, "um item"); validarDescricao(d.descricao, "\"" + reg.nome + "\""); validarPreco(d.preco, "\"" + reg.nome + "\"", false);
  if (d.fotoPendente) validarFoto(d.fotoPendente, "\"" + reg.nome + "\"");
  for (const g of grupos) {
    validarNome(g.nome, "um grupo");
    if (Number(g.min) > Number(g.max)) throw new Error(ERRO_VALIDACAO + "no grupo \"" + g.nome + "\" o mínimo é maior que o máximo.");
    const ops = g.dados?.opcoes || [];
    if (!ops.length) throw new Error(ERRO_VALIDACAO + "o grupo \"" + g.nome + "\" não tem complementos.");
    if (Number(g.min) > ops.length) throw new Error(ERRO_VALIDACAO + "o grupo \"" + g.nome + "\" exige mais escolhas (" + g.min + ") do que tem complementos (" + ops.length + ").");
  }
  for (const o of opcoes) { validarNome(o.nome, "um complemento"); validarDescricao(o.dados?.descricao, "\"" + o.nome + "\""); validarPreco(o.dados?.preco ?? 0, "\"" + o.nome + "\"", true); if (o.dados?.fotoPendente) validarFoto(o.dados.fotoPendente, "\"" + o.nome + "\""); }
  const combo = d.combo === true || d.combo === "true";
  if (combo && !grupos.length) throw new Error(ERRO_VALIDACAO + "um combo precisa de ao menos um grupo (o principal).");
  const productId: string = d.productId || crypto.randomUUID();
  let foto: string | undefined = d.foto;
  if (d.fotoPendente) foto = await subirFoto(ctx, cred, m, d.fotoPendente);
  const patchOpcoes: Record<string, any> = {};
  for (const o of opcoes) {
    const od = o.dados || {};
    const p: any = { productId: od.productId || crypto.randomUUID(), foto: od.foto };
    if (od.fotoPendente) p.foto = await subirFoto(ctx, cred, m, od.fotoPendente);
    patchOpcoes[o.id] = p;
  }
  const status = d.status === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE";
  const preco = numero(d.preco);
  const est = JSON.stringify({ cb: combo, tg: grupos.map((g) => tipoGrupo(g)), n: reg.nome, d: d.descricao || "", f: foto || "", c: cat.dados.ifoodId,
    g: grupos.map((g) => ({ id: g.id, n: g.nome, min: g.min, max: g.max, o: (g.dados?.opcoes || []).map((x: any) => x.id) })),
    o: opcoes.map((o) => ({ id: o.id, n: o.nome, d: o.dados?.descricao || "", f: patchOpcoes[o.id].foto || "" })) });
  const env = d.enviado || null;
  if (!env || env.est !== est) {
    const corpo = {
      // C4: o código do item e o do produto são diferentes (o iFood reaproveita o produto quando o externalCode se repete)
      // C5: combo = type COMBO_V2 com UM grupo principal (MAIN); os demais grupos do combo são OFFER_UNIT
      item: { id: reg.id, type: combo ? "COMBO_V2" : "DEFAULT", categoryId: cat.dados.ifoodId, status, price: { value: preco }, externalCode: reg.id, index: 0, productId },
      products: [
        { id: productId, name: reg.nome, description: d.descricao || "", externalCode: reg.id + "-p", image: foto, serving: "NOT_APPLICABLE",
          optionGroups: grupos.map((g, i) => combo ? ({ id: g.id, min: g.min, max: g.max, associationType: i === 0 ? "MAIN" : "OFFER_UNIT" }) : ({ id: g.id, min: g.min, max: g.max })) },
        ...opcoes.map((o) => ({ id: patchOpcoes[o.id].productId, name: o.nome, description: o.dados?.descricao || "", externalCode: o.id + "-p", image: patchOpcoes[o.id].foto, serving: "NOT_APPLICABLE" })),
      ],
      optionGroups: grupos.map((g, i) => ({ id: g.id, name: g.nome, externalCode: g.id, status: "AVAILABLE", optionGroupType: tipoGrupo(g), index: i, optionIds: (g.dados?.opcoes || []).map((x: any) => x.id) })),
      options: opcoes.map((o, i) => ({ id: o.id, status: o.dados?.status === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE", index: i, productId: patchOpcoes[o.id].productId, price: { value: numero(o.dados?.preco) }, externalCode: o.id, fixedQuantity: 1 })),
    };
    await ctx.chamar(cred, "PUT", `/catalog/v2.0/merchants/${m}/items`, corpo);
  } else {
    // só preço/pausa mudaram: o iFood exige PATCH para isso
    if (numero(env.preco) !== preco) await ctx.chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/items/price`, { itemId: reg.id, price: { value: preco } });
    if (env.status !== status) await ctx.chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/items/status`, { itemId: reg.id, status });
    for (const o of opcoes) {
      const oe = o.dados?.enviado || {}; const op = numero(o.dados?.preco); const os = o.dados?.status === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE";
      if (oe.preco !== undefined && numero(oe.preco) !== op) await ctx.chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/options/price`, { optionId: o.id, price: { value: op } });
      if (oe.status !== undefined && oe.status !== os) await ctx.chamar(cred, "PATCH", `/catalog/v2.0/merchants/${m}/options/status`, { optionId: o.id, status: os });
    }
  }
  for (const o of opcoes) {
    const od = o.dados || {};
    await ctx.rpc("ifood_cat_patch", { p_id: o.id, p_patch: { productId: patchOpcoes[o.id].productId, foto: patchOpcoes[o.id].foto || null, enviado: { preco: numero(od.preco), status: od.status === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE" } } });
  }
  await ctx.rpc("ifood_cat_resultado", { p_id: reg.id, p_estado: "enviado", p_erro: null, p_patch: { productId, foto: foto || null, ifoodId: reg.id, enviado: { est, preco, status } } });
}

// C3: lote é assíncrono: o iFood devolve um batchId e a gente acompanha GET /batch/{batchId} até COMPLETED (sem insistir: 4 consultas em ~10 s)
async function acompanharLote(ctx: Ctx, cred: any, m: string, batchId: string): Promise<{ concluido: boolean; falhas: string[]; ok: number }> {
  const falhas: string[] = []; let ok = 0;
  for (let i = 0; i < 4; i++) {
    await new Promise((r) => setTimeout(r, 1000 * (i + 1)));
    const r: any = await ctx.chamar(cred, "GET", `/catalog/v2.0/merchants/${m}/batch/${encodeURIComponent(batchId)}`);
    const st = String(r?.batchStatus || r?.status || "").toUpperCase();
    if (st === "COMPLETED" || st === "DONE" || st === "FINISHED") {
      if (Array.isArray(r?.results)) for (const x of r.results) { if (/FAIL|ERR/i.test(String(x?.result))) falhas.push(String(x?.resourceId || "") + (x?.message ? ": " + x.message : "")); else ok++; }
      else { ok = Number(r?.successCount || 0); if (Number(r?.failureCount || 0) > 0) falhas.push(r.failureCount + " item(ns) recusado(s) pelo iFood (veja o relatório no Portal do Parceiro)"); }
      return { concluido: true, falhas, ok };
    }
  }
  return { concluido: false, falhas, ok };
}
async function lote(ctx: Ctx, cred: any, m: string, a: any) {
  const itens: any[] = Array.isArray(a.dados?.itens) ? a.dados.itens : [];
  const preco = a.acao === "catalogo_lote_preco" || a.acao === "catalogo_opcao_preco";
  const opcao = a.acao.startsWith("catalogo_opcao");
  if (!itens.length) throw new Error(ERRO_VALIDACAO + "nenhum item para enviar.");
  for (const x of itens) { if (preco) validarPreco(x.valor, "um item do lote", opcao); }
  // corpo oficial do lote: [{ externalCode, price:{value} | status, resources:[ITEM|OPTION] }]; um só item usa o formato simples
  const corpo = itens.length === 1
    ? (preco ? { [opcao ? "optionId" : "itemId"]: itens[0].id, price: { value: numero(itens[0].valor) } } : { [opcao ? "optionId" : "itemId"]: itens[0].id, status: itens[0].valor === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE" })
    : itens.map((x) => preco ? { externalCode: x.id, price: { value: numero(x.valor) }, resources: [opcao ? "OPTION" : "ITEM"] } : { externalCode: x.id, status: x.valor === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE", resources: [opcao ? "OPTION" : "ITEM"] });
  const caminho = itens.length === 1 ? `/catalog/v2.0/merchants/${m}/${opcao ? "options" : "items"}/${preco ? "price" : "status"}` : `/catalog/v2.0/merchants/${m}/items/${preco ? "price" : "status"}`;
  const resp: any = await ctx.chamar(cred, "PATCH", caminho, corpo);
  const batchId = resp?.batchId || resp?.id;
  let falhas: string[] = []; let concluido = true;
  if (batchId) { const r = await acompanharLote(ctx, cred, m, String(batchId)); falhas = r.falhas; concluido = r.concluido; }
  for (const x of itens) {
    const arv: any = await ctx.rpc("ifood_cat_arvore", { p_id: x.id });
    const dd = arv?.registro?.dados || {};
    const recusado = falhas.some((f) => f.includes(String(x.id)));
    if (recusado) { await ctx.rpc("ifood_cat_resultado", { p_id: x.id, p_estado: "erro", p_erro: "O iFood recusou esta alteração em massa: " + falhas.find((f) => f.includes(String(x.id))), p_patch: {} }); continue; }
    const novo = preco ? { preco: numero(x.valor) } : { status: x.valor === "UNAVAILABLE" ? "UNAVAILABLE" : "AVAILABLE" };
    await ctx.rpc("ifood_cat_patch", { p_id: x.id, p_patch: { ...novo, enviado: { ...(dd.enviado || {}), ...novo } } });
  }
  if (falhas.length) throw new Error("O iFood recusou " + falhas.length + " alteração(ões): " + falhas.join(" | ").slice(0, 300));
  if (!concluido) await ctx.rpc("ifood_log", { p_nivel: "aviso", p_msg: "Lote do cardápio enviado, mas o iFood ainda não terminou de aplicar (batch " + batchId + "). Confira em alguns minutos." });
}

export async function executarCatalogoGestao(ctx: Ctx, cred: any, a: any) {
  const m = encodeURIComponent(cred.merchantId || "");
  const idReg: string | null = a.acao === "catalogo_modelo_enviar" ? (a.dados?.id || null) : null;
  try {
    if (a.acao === "catalogo_diagnostico") {
      // C6: por que o item não aparece no app do iFood
      const cid = await catalogoId(ctx, cred, m);
      const r: any = await ctx.chamar(cred, "GET", `/catalog/v2.0/merchants/${m}/catalogs/${encodeURIComponent(cid)}/unsellableItems`);
      await ctx.rpc("ifood_cat_diag_gravar", { p: { catalogId: cid, itens: Array.isArray(r) ? r : (r?.unsellableItems || r?.items || []) } });
    } else if (a.acao === "catalogo_modelo_enviar") {
      const arv: any = await ctx.rpc("ifood_cat_arvore", { p_id: idReg });
      if (!arv?.registro) throw new Error("registro não encontrado no sistema");
      if (arv.registro.tipo === "categoria") await enviarCategoria(ctx, cred, m, arv.registro);
      else if (arv.registro.tipo === "item") {
        // produto novo do sistema: se a categoria ainda não foi ao iFood, envia ela primeiro
        let a2 = arv;
        if (a2.categoria && !a2.categoria.dados?.ifoodId) {
          await enviarCategoria(ctx, cred, m, a2.categoria);
          a2 = await ctx.rpc("ifood_cat_arvore", { p_id: idReg });
        }
        await enviarItem(ctx, cred, m, a2);
      }
      else throw new Error("só categoria e item são enviados direto");
    } else {
      await lote(ctx, cred, m, a);
    }
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: "ok" });
  } catch (er) {
    const st = er instanceof ctx.HttpErro ? (er as any).status : 0;
    const msg = erroTexto(ctx, er);
    if (idReg) { try { await ctx.rpc("ifood_cat_resultado", { p_id: idReg, p_estado: "erro", p_erro: msg, p_patch: {} }); } catch { /* sem registro */ } }
    await ctx.rpc("ifood_acao_resultado", { p_id: a.id, p_estado: st >= 400 && st < 500 || st === 0 && !(er instanceof ctx.HttpErro) ? "erro" : "duvida", p_erro: msg });
  }
}
