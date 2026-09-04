// Funções da área da cantina (menus, reservas, histórico, saldos, relatórios)

/* formatarData e escapeHtml vivem agora no app.js. */

// Eram globais implícitas: nasciam da atribuição dentro de showCantinaReservasHoje,
// sem declaração nenhuma.
let reservasHoje = [];
let reservasHojePorTipo = {};

/* ==============================
   CANTINA — NAVEGAÇÃO BASE
============================== */


/* =============================
   CANTINA — CRIAR MENU
============================= */

// Estado do calendário de criação de menus
let _menusCantina = [];
let _mesCriarView = null;
let _diaCriarSelecionado = null;

const _NOMES_MESES_CANTINA = [
  "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
  "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
];
function _pad2c(n){ return String(n).padStart(2,"0"); }

function _badgeMenuCantina(tipo){
  const map = {
    pequeno_almoco: { txt: "P.A", bg: "#e3f2fd", cor: "#1565c0" },
    almoco:         { txt: "A",   bg: "#e8f5e9", cor: "#2e7d32" },
    jantar:         { txt: "J",   bg: "#f3e5f5", cor: "#6a1b9a" }
  };
  const m = map[tipo] || { txt: "?", bg: "#eee", cor: "#333" };
  return `<span style="display:inline-block;font-size:10px;font-weight:800;line-height:1;padding:2px 5px;border-radius:6px;background:${m.bg};color:${m.cor};margin:1px;">${m.txt}</span>`;
}

async function showCriarMenu() {
  show("cantinaMenu");

  if(!_mesCriarView) _mesCriarView = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  _diaCriarSelecionado = null;
  await carregarMenusCantina();
  renderCalendarioCriarMenu();
}

async function carregarMenusCantina(){
  if(!supabaseClient) return;
  const { data, error } = await supabaseClient
    .from("menus")
    .select("id, data, tipo, prato, preco");
  if(error){
    console.error("⚠️ Erro ao carregar menus", error);
    _menusCantina = [];
    return;
  }
  _menusCantina = data || [];
}

function mudarMesCriar(delta){
  if(!_mesCriarView) _mesCriarView = new Date();
  _mesCriarView = new Date(_mesCriarView.getFullYear(), _mesCriarView.getMonth() + delta, 1);
  _diaCriarSelecionado = null;
  renderCalendarioCriarMenu();
}

function selecionarDiaCriar(iso){
  _diaCriarSelecionado = (_diaCriarSelecionado === iso) ? null : iso;
  renderCalendarioCriarMenu();
}

function renderCalendarioCriarMenu(){
  const container = document.getElementById("calendarioCriarMenu");
  if(!container) return;

  const ano = _mesCriarView.getFullYear();
  const mes = _mesCriarView.getMonth();

  const menusPorData = {};
  _menusCantina.forEach(m => {
    (menusPorData[m.data] = menusPorData[m.data] || []).push(m);
  });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(menusPorData).forEach(arr =>
    arr.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9))
  );

  const hojeISO = new Date().toISOString().split("T")[0];
  const primeiroDia = new Date(ano, mes, 1);
  const diasNoMes = new Date(ano, mes + 1, 0).getDate();
  const offset = (primeiroDia.getDay() + 6) % 7;
  const diasSemana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"];

  let celulas = "";
  for(let i = 0; i < offset; i++) celulas += `<div></div>`;
  for(let dia = 1; dia <= diasNoMes; dia++){
    const iso = `${ano}-${_pad2c(mes+1)}-${_pad2c(dia)}`;
    const menusDia = menusPorData[iso] || [];
    const completo = menusDia.length >= 3;
    const temMenus = menusDia.length > 0;
    const passado = iso < hojeISO;
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaCriarSelecionado;
    const badges = menusDia.map(m => _badgeMenuCantina(m.tipo)).join("");

    let fundo = "transparent";
    if(isSel) fundo = "#fff3cd";
    else if(completo) fundo = "#e8f5e9";
    else if(temMenus) fundo = "#fffde7";
    else if(!passado) fundo = "#ffebee";

    const borda = isSel ? "2px solid #ffc107"
                 : completo ? "1px solid #a5d6a7"
                 : temMenus ? "1px solid #ffe082"
                 : (!passado ? "1px dashed #ef9a9a" : "1px solid transparent");

    const clicavel = !passado;

    celulas += `
      <div onclick="${clicavel ? `selecionarDiaCriar('${iso}')` : ''}"
        style="min-height:56px;padding:4px;border-radius:8px;background:${fundo};border:${borda};
               ${clicavel ? 'cursor:pointer;box-shadow:0 1px 2px rgba(0,0,0,0.06);' : 'opacity:0.5;'}
               display:flex;flex-direction:column;align-items:center;gap:2px;">
        <span style="font-size:12px;font-weight:700;color:${isHoje ? '#d32f2f' : '#333'};
              ${isHoje ? 'background:#ffe0e0;border-radius:50%;width:20px;height:20px;display:flex;align-items:center;justify-content:center;' : ''}">${dia}</span>
        <div style="display:flex;flex-wrap:wrap;justify-content:center;">${badges}</div>
      </div>
    `;
  }

  let detalhe = "";
  if(_diaCriarSelecionado){
    detalhe = `
      <div style="margin-top:16px;">
        <h3 style="color:#333;margin-bottom:10px;font-size:15px;">📅 ${formatarData(_diaCriarSelecionado)}</h3>
        ${_cartoesCriarDia(_diaCriarSelecionado)}
      </div>
    `;
  } else {
    detalhe = `
      <p style="text-align:center;color:#999;font-size:13px;margin-top:14px;">
        Toca num dia para criar os menus.<br>
        <span style="color:#c62828;">Vermelho</span> = falta criar &nbsp;·&nbsp;
        <span style="color:#f9a825;">Amarelo</span> = incompleto &nbsp;·&nbsp;
        <span style="color:#2e7d32;">Verde</span> = completo
      </p>`;
  }

  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
      <button onclick="mudarMesCriar(-1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">‹</button>
      <b style="font-size:16px;">${_NOMES_MESES_CANTINA[mes]} ${ano}</b>
      <button onclick="mudarMesCriar(1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">›</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;margin-bottom:6px;">
      ${diasSemana.map(d => `<div style="font-size:11px;font-weight:700;color:#888;">${d}</div>`).join("")}
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">
      ${celulas}
    </div>
    ${detalhe}
  `;
}

function _cartaoCriarRefeicao(iso, tipo, existente){
  const nomes = {
    pequeno_almoco: "🥐 Pequeno Almoço",
    almoco: "🍽️ Almoço",
    jantar: "🌙 Jantar"
  };
  const precos = { pequeno_almoco: 2, almoco: 4, jantar: 4 };

  let corpo = "";
  if(existente){
    corpo = `<div style="color:#2e7d32;font-size:13px;">✅ Criado${existente.prato ? ` — ${escapeHtml(existente.prato)}` : ""}</div>`;
  } else if(tipo === "pequeno_almoco"){
    corpo = `
      <div style="font-size:13px;color:#555;margin-bottom:8px;">Pão e Leite (fixo)</div>
      <button class="btn-full" style="margin:0;" onclick="criarRefeicao('${iso}','pequeno_almoco')">Criar Pequeno Almoço</button>`;
  } else if(tipo === "almoco"){
    corpo = `
      <input id="pratoAlmoco-${iso}" placeholder="Ex: Frango com arroz"
        style="width:100%;box-sizing:border-box;margin:0 0 8px 0;padding:10px 12px;border:2px solid #e0e0e0;border-radius:8px;">
      <button class="btn-full" style="margin:0;" onclick="criarRefeicao('${iso}','almoco')">Criar Almoço</button>`;
  } else {
    corpo = `
      <div style="font-size:13px;color:#555;margin-bottom:8px;">Sem prato (apenas contagem)</div>
      <button class="btn-full" style="margin:0;" onclick="criarRefeicao('${iso}','jantar')">Criar Jantar</button>`;
  }

  return `
    <div style="border:1px solid #e0e0e0;border-radius:10px;padding:12px;margin-bottom:10px;text-align:left;">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
        <b>${nomes[tipo]}</b>
        <span style="color:#888;font-size:13px;">${precos[tipo]}€</span>
      </div>
      ${corpo}
    </div>
  `;
}

function _cartoesCriarDia(iso){
  const menusDia = _menusCantina.filter(m => m.data === iso);
  const porTipo = {};
  menusDia.forEach(m => porTipo[m.tipo] = m);
  return ["pequeno_almoco","almoco","jantar"]
    .map(t => _cartaoCriarRefeicao(iso, t, porTipo[t]))
    .join("");
}

async function criarRefeicao(iso, tipo){
  let prato = "";
  if(tipo === "almoco"){
    const inp = document.getElementById(`pratoAlmoco-${iso}`);
    prato = inp ? inp.value.trim() : "";
    if(!prato){
      mostrarMensagem("warning", "⚠️ Escreve o prato do almoço");
      return;
    }
  }
  document.getElementById("dataMenu") && (document.getElementById("dataMenu").value = "");
  await addMenuDireto(iso, tipo, prato);
  await carregarMenusCantina();
  renderCalendarioCriarMenu();
}

async function addMenuDireto(dataValue, tipo, pratoEntrada) {

  if (!supabaseClient) {
    mostrarMensagem("error", "❌ Erro: Conexão não pronta. Atualiza a página.");
    console.error("❌ supabaseClient não disponível");
    return;
  }

  let prato = (pratoEntrada || "").trim();

  if (!dataValue) {
    mostrarMensagem("warning", "⚠️ Seleciona uma data");
    return;
  }

  const hoje = new Date().toISOString().split("T")[0];
  if (dataValue < hoje) {
    mostrarMensagem("warning", "⚠️ Não podes criar menus com data passada");
    return;
  }

  const configuracao = {
    pequeno_almoco: { preco: 2, prato: "Pão e Leite" },
    almoco: { preco: 4 },
    jantar: { preco: 4, prato: "" }
  };

  if (!configuracao[tipo]) {
    mostrarMensagem("error", "❌ Tipo inválido");
    return;
  }

  if (tipo === "pequeno_almoco") {
    prato = configuracao.pequeno_almoco.prato;
  }

  if (tipo === "almoco" && !prato) {
    mostrarMensagem("warning", "⚠️ Preenche o prato do almoço");
    return;
  }

  showLoading("⏳ Criando menu...");

  // 🔎 Verificar se já existe menu do mesmo tipo neste dia
  const { data: existente, error: erroCheck } = await supabaseClient
    .from("menus")
    .select("id")
    .eq("data", dataValue)
    .eq("tipo", tipo)
    .limit(1);

    if (erroCheck) {
      handleError(erroCheck, "Erro ao verificar menu existente");
      return;
    }

    if (existente && existente.length > 0) {
      mostrarMensagem("warning", "⚠️ Já existe este tipo de menu neste dia.");
      hideLoading();
      return;
    }

    try {
      
      const { data, error } = await supabaseClient
        .from("menus")
        .insert([{
          data: dataValue,
          tipo,
          prato,
          preco: configuracao[tipo].preco
        }])
        .select();

      if (error) {
        handleError(error, "Erro ao criar menu");
        return;
      }

      // O almoço é reservado automaticamente para todos os alunos pelo trigger
      // criar_reservas_automaticas_almoco, na base de dados (ver migração 001).
      // Não duplicar aqui: o trigger corre sempre, mesmo se o menu for criado por outra via.

      mostrarSucesso("Menu Criado", "Menu criado com sucesso!");
  } catch (err) {
    handleError(err, "Erro ao criar menu");
  } finally {
    hideLoading();
  }
}

/* =============================
   CANTINA — LISTAR MENUS CRIADOS (VERSÃO MELHORADA)
============================= */

function toggleDia(data) {
  const el = document.getElementById(`dia-${data}`);
  const chevron = document.querySelector(`.chevron-${data}`);

  if (!el) return;

  el.classList.toggle("hidden");

  if (chevron) {
    chevron.style.transform = el.classList.contains("hidden")
      ? "rotate(0deg)"
      : "rotate(180deg)";
  }
}

// 🔐 Proteção simples contra HTML injection
let _mesMenusView = null;
let _diaMenusSelecionado = null;

async function showMenusCriados() {
  show("cantinaMenus");
  showLoading("⏳ Carregando menus...");

  try {
    const { data: menus, error } = await supabaseClient
      .from("menus")
      .select("*")
      .order("data", { ascending: false });

    if (error) throw error;

    window.todosOsMenus = menus || [];

    if(!_mesMenusView) _mesMenusView = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    _diaMenusSelecionado = null;
    renderCalendarioMenusCriados();

  } catch (err) {
    handleError(err, "Erro ao carregar menus");
  } finally {
    hideLoading();
  }
}

function mudarMesMenus(delta){
  if(!_mesMenusView) _mesMenusView = new Date();
  _mesMenusView = new Date(_mesMenusView.getFullYear(), _mesMenusView.getMonth() + delta, 1);
  _diaMenusSelecionado = null;
  renderCalendarioMenusCriados();
}

function selecionarDiaMenus(iso){
  _diaMenusSelecionado = (_diaMenusSelecionado === iso) ? null : iso;
  renderCalendarioMenusCriados();
}

function renderCalendarioMenusCriados(){
  const container = document.getElementById("listaMenus");
  if(!container) return;

  const menus = window.todosOsMenus || [];
  const ano = _mesMenusView.getFullYear();
  const mes = _mesMenusView.getMonth();

  const menusPorData = {};
  menus.forEach(m => {
    (menusPorData[m.data] = menusPorData[m.data] || []).push(m);
  });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(menusPorData).forEach(arr =>
    arr.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9))
  );

  const hojeISO = new Date().toISOString().split("T")[0];
  const primeiroDia = new Date(ano, mes, 1);
  const diasNoMes = new Date(ano, mes + 1, 0).getDate();
  const offset = (primeiroDia.getDay() + 6) % 7;
  const diasSemana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"];

  let celulas = "";
  for(let i = 0; i < offset; i++) celulas += `<div></div>`;
  for(let dia = 1; dia <= diasNoMes; dia++){
    const iso = `${ano}-${_pad2c(mes+1)}-${_pad2c(dia)}`;
    const menusDia = menusPorData[iso] || [];
    const temMenus = menusDia.length > 0;
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaMenusSelecionado;
    const badges = menusDia.map(m => _badgeMenuCantina(m.tipo)).join("");

    const fundo = isSel ? "#fff3cd" : (temMenus ? "#ffffff" : "transparent");
    const borda = isSel ? "2px solid #ffc107"
                 : temMenus ? "1px solid #c8e6c9"
                 : "1px solid transparent";

    celulas += `
      <div onclick="${temMenus ? `selecionarDiaMenus('${iso}')` : ''}"
        style="min-height:56px;padding:4px;border-radius:8px;background:${fundo};border:${borda};
               ${temMenus ? 'cursor:pointer;box-shadow:0 1px 2px rgba(0,0,0,0.06);' : ''}
               display:flex;flex-direction:column;align-items:center;gap:2px;">
        <span style="font-size:12px;font-weight:700;color:${isHoje ? '#d32f2f' : '#333'};
              ${isHoje ? 'background:#ffe0e0;border-radius:50%;width:20px;height:20px;display:flex;align-items:center;justify-content:center;' : ''}">${dia}</span>
        <div style="display:flex;flex-wrap:wrap;justify-content:center;">${badges}</div>
      </div>
    `;
  }

  let detalhe = "";
  if(_diaMenusSelecionado){
    detalhe = `
      <div style="margin-top:16px;">
        <h3 style="color:#333;margin-bottom:10px;font-size:15px;">📅 ${formatarData(_diaMenusSelecionado)}</h3>
        ${_cartoesMenusDia(_diaMenusSelecionado)}
      </div>`;
  } else {
    detalhe = `<p style="text-align:center;color:#999;font-size:13px;margin-top:14px;">Toca num dia marcado para ver e alterar as refeições.</p>`;
  }

  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
      <button onclick="mudarMesMenus(-1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">‹</button>
      <b style="font-size:16px;">${_NOMES_MESES_CANTINA[mes]} ${ano}</b>
      <button onclick="mudarMesMenus(1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">›</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;margin-bottom:6px;">
      ${diasSemana.map(d => `<div style="font-size:11px;font-weight:700;color:#888;">${d}</div>`).join("")}
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">
      ${celulas}
    </div>
    ${detalhe}
  `;
}

function _cartoesMenusDia(iso){
  const menus = (window.todosOsMenus || []).filter(m => m.data === iso);
  if(!menus.length) return `<i>Sem menus neste dia.</i>`;

  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  menus.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));

  const nomes = {
    pequeno_almoco: "🥐 Pequeno Almoço",
    almoco: "🍽️ Almoço",
    jantar: "🌙 Jantar"
  };

  const hoje = new Date();
  const hojeStr = hoje.toISOString().split("T")[0];
  const horaAtual = hoje.getHours();

  return menus.map(m => {
    const prato = escapeHtml(m.prato || "");
    const preco = Number(m.preco || 0).toFixed(2);

    let podeEditar = false;
    if(new Date(m.data) > new Date(hojeStr)) podeEditar = true;
    if(m.data === hojeStr && horaAtual < 9) podeEditar = true;

    // Só o almoço tem prato editável
    const podeEditarPrato = podeEditar && m.tipo === "almoco";

    const acoes = podeEditar
      ? `<div style="display:flex;gap:6px;">
           ${podeEditarPrato ? `<button class="btn-edit" onclick="startEdit('${m.id}')" style="padding:6px 10px;font-size:12px;">✏️ Alterar</button>` : ""}
           <button class="btn-delete" onclick="apagarMenu('${m.id}')" style="padding:6px 10px;font-size:12px;">🗑️ Apagar</button>
         </div>`
      : `<span style="color:#999;font-size:12px;">Bloqueado</span>`;

    return `
      <div style="border:1px solid #e0e0e0;border-radius:10px;padding:12px;margin-bottom:10px;text-align:left;">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
          <b>${nomes[m.tipo] || m.tipo}</b>
          <span style="color:#007bff;font-weight:bold;">${preco}€</span>
        </div>
        ${prato ? `<div style="font-size:13px;color:#555;margin-bottom:8px;">${escapeHtml(prato)}</div>`
                : `<div style="font-size:13px;color:#999;margin-bottom:8px;">Sem prato</div>`}
        ${acoes}
      </div>
    `;
  }).join("");
}

function formatarTipoRefeicao(tipo) {

  const nomes = {
    pequeno_almoco: "Pequeno Almoço",
    almoco: "Almoço",
    dieta: "Dieta",
    jantar: "Jantar"
  };

  return nomes[tipo] || tipo;
}

/* =============================
   CANTINA — EDITAR / APAGAR MENU
============================= */

async function startEdit(id) {
  const menu = window.todosOsMenus.find(m => m.id == id);
  if (!menu) {
    mostrarErro("Erro", "Menu não encontrado.");
    return;
  }

  const novoPrato = await modalEditarPrato(menu.prato);

  if (!novoPrato) return;

  if (!validarInput(novoPrato, "Prato")) return;

  await saveEdit(id, novoPrato);
}

function cancelEdit(id) {
  const el = document.getElementById(`edit-${id}`);
  if (el) el.classList.add("hidden");
}

async function saveEdit(id, novoPrato) {
  showLoading("⏳ Atualizando prato...");

  try {
    // Buscar menu antigo para ter o prato anterior
    const menuAntigo = window.todosOsMenus.find(m => m.id === id);
    if (!menuAntigo) {
      mostrarErro("Erro", "Menu não encontrado.");
      return;
    }

    const pratosAntigo = menuAntigo.prato;

    // Atualizar menu
    const { error } = await supabaseClient
      .from("menus")
      .update({ prato: novoPrato })
      .eq("id", id);

    if (error) {
      handleError(error, "Erro ao atualizar prato");
      return;
    }

    // Notificar alunos que têm reserva neste menu
    try {

      const { data: notificacoes, error: erroNotif } = await supabaseClient
        .rpc('notificar_menu_alterado', {
          p_menu_id: id,
          p_prato_antigo: pratosAntigo,
          p_prato_novo: novoPrato,
          p_data_menu: menuAntigo.data,
          p_tipo_menu: menuAntigo.tipo
        });


      if (erroNotif) {
        console.error("❌ Erro na função RPC:", erroNotif);
      } else if (notificacoes > 0) {
      } else {
      }
    } catch (erroNotif) {
      console.error("❌ Exceção ao notificar alunos:", erroNotif);
      // Não bloqueia a operação se notificações falhar
    }

    mostrarSucesso("Prato Atualizado", "Prato atualizado com sucesso!\n✅ Os alunos com reserva veem o aviso na app.");
    showMenusCriados();
  } catch (err) {
    handleError(err, "Erro ao atualizar prato");
  } finally {
    hideLoading();
  }
}

async function apagarMenu(id) {

  if (!await confirmar("Apagar Menu", "Tens a certeza que queres apagar este menu?")) {
    return;
  }

  showLoading("⏳ Apagando menu...");

  try {
    const { error } = await supabaseClient
      .from("menus")
      .delete()
      .eq("id", id);

    if (error) {
      handleError(error, "Erro ao apagar menu");
      return;
    }

    mostrarSucesso("Sucesso", "Menu apagado com sucesso!");
    showMenusCriados();
  } catch (err) {
    handleError(err, "Erro ao apagar menu");
  } finally {
    hideLoading();
  }
}

/* =============================
   CANTINA — RESERVAS DO DIA
============================= */

async function showCantinaReservasHoje() {
  show("cantinaReservas");

  const hoje = new Date().toISOString().slice(0, 10);
  const div = document.getElementById("reservasDia");
  div.innerHTML = "A carregar reservas de hoje...";

  const { data, error } = await supabaseClient
    .from("reservas")
    .select(`
      id,
      tipo,
      is_dieta,
      alunos ( nome )
    `)
    .eq("data", hoje)
    .eq("ativa", true);

  if (error) {
    div.innerHTML = `<i>${error.message}</i>`;
    return;
  }

  reservasHoje = data || [];

  reservasHojePorTipo = {
    pequeno_almoco: [],
    almoco: [],
    dieta: [],
    jantar: []
  };

  reservasHoje.forEach(r => {

    if (r.tipo === "almoco" && r.is_dieta) {
      reservasHojePorTipo.dieta.push(r);
    }
    else if (r.tipo === "almoco") {
      reservasHojePorTipo.almoco.push(r);
    }
    else {
      reservasHojePorTipo[r.tipo]?.push(r);
    }

  });

  const cardRefeicao = (tipo, emoji, nome, qtd, cor) => `
    <div onclick="verDetalheRefeicao('${tipo}')"
      style="display:flex;align-items:center;justify-content:space-between;gap:12px;
             padding:18px 20px;margin-bottom:12px;border-radius:14px;cursor:pointer;
             background:#fff;border:2px solid ${cor};
             box-shadow:0 3px 8px rgba(0,0,0,0.08);transition:transform .1s;"
      onmousedown="this.style.transform='scale(0.98)'" onmouseup="this.style.transform='scale(1)'" onmouseleave="this.style.transform='scale(1)'">
      <span style="display:flex;align-items:center;gap:10px;font-size:17px;font-weight:700;color:#333;">
        <span style="font-size:24px;">${emoji}</span>${nome}
      </span>
      <span style="min-width:42px;text-align:center;font-size:18px;font-weight:800;color:#fff;
                   background:${cor};border-radius:20px;padding:4px 12px;">${qtd}</span>
    </div>`;

  div.innerHTML = `
    ${cardRefeicao('pequeno_almoco','🥐','Pequeno Almoço',reservasHojePorTipo.pequeno_almoco.length,'#1565c0')}
    ${cardRefeicao('almoco','🍽️','Almoço',reservasHojePorTipo.almoco.length,'#2e7d32')}
    ${cardRefeicao('dieta','🥗','Dieta',reservasHojePorTipo.dieta.length,'#f9a825')}
    ${cardRefeicao('jantar','🌙','Jantar',reservasHojePorTipo.jantar.length,'#6a1b9a')}
  `;
}

async function alunoTemDivida(alunoId) {
  try {
    // "Pagamentos em atraso" refere-se apenas a refeições de meses ANTERIORES
    // ao mês atual que ainda não foram liquidadas. Refeições reservadas no
    // mês corrente NÃO contam como dívida em atraso.
    const hoje = new Date();
    const inicioMesAtual = `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, "0")}-01`;

    const { data, error } = await supabaseClient
      .from("reservas")
      .select("id")
      .eq("aluno_id", alunoId)
      .eq("ativa", true)
      .lt("data", inicioMesAtual)
      .limit(1);

    if (error) {
      mostrarErro("Erro", "Erro ao verificar pagamentos");
      return true;
    }

    return data && data.length > 0;
  } catch (err) {
    console.error("❌ Erro ao verificar dívida:", err);
    return true;
  }
}

function verDetalheRefeicao(tipo) {

  const div = document.getElementById("reservasDia");
  const lista = reservasHojePorTipo[tipo] || [];

  if (lista.length === 0) {
    div.innerHTML = `
      <h3>${formatarTipoRefeicao(tipo)}</h3>
      <i>Sem reservas</i>
      <br><button onclick="showCantinaReservasHoje()">⬅️ Voltar às Reservas de Hoje</button>
    `;
    return;
  }

  const nomesOrdenados = [...lista].sort((a,b)=> (a.alunos?.nome||"").localeCompare(b.alunos?.nome||""));

  div.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;">
      <h3 style="margin:0;">${formatarTipoRefeicao(tipo)} — ${nomesOrdenados.length}</h3>
      <button class="btn-medium" onclick="imprimirListaRefeicao('${tipo}')">🖨️ Exportar / Imprimir</button>
    </div>
    <div style="margin-top:12px;">
      ${nomesOrdenados.map((r,i) => `
        <div style="display:flex;align-items:center;gap:8px;padding:8px 4px;border-bottom:1px solid #eee;">
          <span style="color:#999;width:22px;">${i+1}.</span> 👤 ${escapeHtml(r.alunos.nome)}
        </div>
      `).join("")}
    </div>
    <br>
    <button class="btn-back" onclick="showCantinaReservasHoje()">⬅️ Voltar às Reservas de Hoje</button>
  `;
}

// Abre uma janela imprimível com a lista de alunos da refeição selecionada
function imprimirListaRefeicao(tipo) {
  const lista = reservasHojePorTipo[tipo] || [];
  const nomes = [...lista].sort((a,b)=> (a.alunos?.nome||"").localeCompare(b.alunos?.nome||""));
  const hojeFmt = formatarData(new Date().toISOString().slice(0,10));
  const linhas = nomes.map((r,i) => `<tr><td>${i+1}</td><td>${escapeHtml(r.alunos.nome)}</td></tr>`).join("");

  const win = window.open("", "_blank");
  if(!win){
    mostrarErro("Bloqueado", "Permite pop-ups para exportar a lista.");
    return;
  }
  win.document.write(`
    <html><head><title>${formatarTipoRefeicao(tipo)} - ${hojeFmt}</title>
    <style>
      body{font-family:Arial,sans-serif;padding:24px;color:#222;}
      h1{font-size:20px;margin:0 0 4px;}
      p{color:#666;margin:0 0 16px;}
      table{width:100%;border-collapse:collapse;}
      th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #ccc;}
      th{background:#f0f0f0;}
      td:first-child,th:first-child{width:40px;text-align:center;}
      @media print{button{display:none;}}
    </style></head>
    <body>
      <h1>${formatarTipoRefeicao(tipo)}</h1>
      <p>${hojeFmt} · Total: ${nomes.length} aluno(s)</p>
      <table><thead><tr><th>#</th><th>Aluno</th></tr></thead><tbody>${linhas}</tbody></table>
      <br><button onclick="window.print()">🖨️ Imprimir</button>
    </body></html>
  `);
  win.document.close();
}

/* =============================
   CANTINA — HISTÓRICO
============================= */

let alunosHistoricoLista = [];
let alunosHistoricoFiltrados = [];
let historicoAtual = [];
let historicoFiltrado = [];
let alunoHistoricoAtual = null;
let nomeAlunoHistoricoAtual = "";

async function showCantinaHistorico() {
  show("cantinaHistorico");

  document.getElementById("alunosPesquisaBox").style.display = "block";
  document.getElementById("historico").innerHTML = "";
  document.getElementById("btnBackHistorico").style.display = "none";
  document.getElementById("btnBackMenu").style.display = "inline-block";

  const div = document.getElementById("listaAlunosHistorico");
  div.innerHTML = "⏳ A carregar alunos...";

  // A lista vem dos ALUNOS e não das reservas. Antes ia buscar todas as reservas
  // e removia os repetidos aqui, e o PostgREST corta a resposta nas 1000 linhas
  // por omissão: com 1195 reservas chegavam 1000, e nessas só havia 125 alunos
  // distintos dos 149 que têm reservas. A cantina não conseguia abrir o
  // histórico de 24 alunos, e não havia erro nenhum a dizê-lo — a lista apenas
  // vinha mais curta. Encontrado a olho, num teste manual: qualquer teste
  // automático escolhe um aluno que calha estar dentro das primeiras 1000 linhas.
  //
  // Assim a lista cresce com o número de alunos e não com o número de refeições,
  // por isso nunca mais se aproxima do limite. Passam a aparecer também os alunos
  // sem reservas nenhumas, o que para quem procura um aluno é melhor - e o ecrã
  // de detalhe já trata desse caso.
  const { data, error } = await supabaseClient
    .from("alunos")
    .select("id, nome")
    .order("nome");

  if (error) {
    div.innerHTML = `<i>❌ Erro: ${escapeHtml(error.message)}</i>`;
    return;
  }

  if (!data || data.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem alunos registados.</div>";
    document.getElementById("alunosPesquisaBox").style.display = "none";
    return;
  }

  alunosHistoricoLista = data
    .map(a => [a.id, a.nome])
    .sort((a, b) => a[1].localeCompare(b[1]));

  alunosHistoricoFiltrados = [...alunosHistoricoLista];

  document.getElementById("pesquisaAlunos").value = "";
  exibirAlunosHistorico();
}

function filtrarAlunos() {
  const pesquisa = document.getElementById("pesquisaAlunos").value.toLowerCase();
  
  alunosHistoricoFiltrados = alunosHistoricoLista.filter(([id, nome]) =>
    nome.toLowerCase().includes(pesquisa)
  );

  exibirAlunosHistorico();
}

function exibirAlunosHistorico() {
  const div = document.getElementById("listaAlunosHistorico");
  
  const totalAlunos = alunosHistoricoLista.length;
  const resultados = alunosHistoricoFiltrados.length;
  document.getElementById("alunosContagemResultados").textContent = 
    resultados === totalAlunos 
      ? `👥 ${totalAlunos} aluno${totalAlunos !== 1 ? 's' : ''}`
      : `👥 ${resultados} de ${totalAlunos} alunos`;

  if (alunosHistoricoFiltrados.length === 0) {
    div.innerHTML = "<div class='empty-state' style='width:100%;'><div class='empty-state-icon'>🔍</div>Nenhum aluno encontrado.</div>";
    return;
  }

  div.innerHTML = alunosHistoricoFiltrados.map(([id, nome]) => `
    <div class="aluno-card" onclick="showHistoricoAluno('${id}')">
      👤 ${escapeHtml(nome)}
    </div>
  `).join("");
}

// O nome deixou de viajar dentro do onclick. Estava interpolado num literal de
// string JS dentro de um atributo HTML, por isso um nome com apostrofe - O'Brien
// - partia o handler todo. Isso e um erro a serio, nao uma hipotese. Agora entra
// so o id e o nome vem do estado.
async function showHistoricoAluno(alunoId) {
  const alunoNome = (alunosHistoricoLista.find(([id]) => id === alunoId) || [])[1] || "";
  alunoHistoricoAtual = alunoId;
  nomeAlunoHistoricoAtual = alunoNome;

  document.getElementById("alunosPesquisaBox").style.display = "none";
  document.getElementById("listaAlunosHistorico").innerHTML = "";
  document.getElementById("btnBackHistorico").style.display = "inline-block";
  document.getElementById("btnBackMenu").style.display = "none";

  // O nome é escrito ANTES de ir buscar as reservas. A lista passou a incluir
  // alunos sem reserva nenhuma, e nesse caso isto saía pelo return de baixo sem
  // nunca chegar a dizer de quem era o ecrã que estava a mostrar.
  // innerText, não innerHTML: o nome não é escapado e não precisa de ser.
  document.getElementById("NomeAluno").innerText = alunoNome;

  const div = document.getElementById("historico");
  div.innerHTML = "⏳ A carregar histórico...";

  const { data: reservas, error } = await supabaseClient
    .from("reservas")
    .select(`
      id,
      tipo,
      data,
      ativa,
      cancelamento_tipo,
      preco,
      is_dieta,
      menus!inner(prato)
    `)
    .eq("aluno_id", alunoId)
    .order("data", { ascending: false });

  if (error) {
    div.innerHTML = `<i>❌ Erro: ${escapeHtml(error.message)}</i>`;
    return;
  }

  if (!reservas || reservas.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem histórico disponível para este aluno.</div>";
    return;
  }

  historicoAtual = reservas;
  historicoFiltrado = [...reservas];
  _diaHistSelecionado = null;
  const primeira = reservas[0] ? new Date(reservas[0].data) : new Date();
  _mesHistView = new Date(primeira.getFullYear(), primeira.getMonth(), 1);
  exibirHistoricoFiltrado();
}

let _mesHistView = null;
let _diaHistSelecionado = null;

function mudarMesHistorico(delta){
  if(!_mesHistView) _mesHistView = new Date();
  _mesHistView = new Date(_mesHistView.getFullYear(), _mesHistView.getMonth() + delta, 1);
  _diaHistSelecionado = null;
  exibirHistoricoFiltrado();
}

function selecionarDiaHistorico(iso){
  _diaHistSelecionado = (_diaHistSelecionado === iso) ? null : iso;
  exibirHistoricoFiltrado();
}

// Estado legível de uma reserva, derivado de cancelamento_tipo (fonte de verdade única).
// Espelha as etiquetas usadas em aluno.js › _cartaoReserva.
// `ativa` é calculada pela base de dados: NULL e 'reactivated' são ativas.
function _estadoReserva(r){
  switch(r.cancelamento_tipo){
    case "user":        return { texto: "❌ Cancelada pelo aluno", classe: "status-cancelada" };
    case "contrato":    return { texto: "🏷️ Cancelada pela cantina (mudança de contrato)", classe: "status-cancelada" };
    case "payment":     return { texto: "💳 Paga",                 classe: "status-cancelada" };
    case "reactivated": return { texto: "🔄 Reativada",            classe: "status-ativa" };
    default:            return { texto: "✅ Ativa",                classe: "status-ativa" };
  }
}

function _cartoesHistoricoDia(iso){
  const doDia = (historicoAtual || []).filter(r => r.data === iso);
  if(!doDia.length) return `<i>Sem reservas neste dia.</i>`;
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  doDia.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));

  // Acção direta só em almoços ativos de hoje em diante: um pedido por telefone
  // é sempre sobre uma refeição que ainda não foi servida. Dias passados ficam
  // como histórico, só de leitura.
  const hoje = new Date().toISOString().split("T")[0];

  return doDia.map(r => {
    const podeAlterar = r.tipo === "almoco" && r.ativa && r.data >= hoje;
    return `
    <div style="border:1px solid #e0e0e0;border-radius:10px;padding:12px;margin-bottom:10px;text-align:left;">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
        <b>${formatarTipoRefeicao(r.tipo)}${r.is_dieta ? " 🥗" : ""}</b>
        <span style="color:#007bff;font-weight:bold;">${Number(r.preco).toFixed(2)}€</span>
      </div>
      <div style="font-size:13px;color:#555;margin-bottom:6px;">${escapeHtml(r.menus?.prato || "-")}</div>
      <div class="${_estadoReserva(r).classe}" style="font-size:12px;">
        ${_estadoReserva(r).texto}
      </div>
      ${podeAlterar ? `
        <div style="display:flex;gap:6px;margin-top:8px;flex-wrap:wrap;">
          <button onclick="alterarReservaDireto('${r.id}', 'cancelar')" style="flex:1 1 auto;padding:6px 10px;font-size:12px;background:#dc3545;color:white;border:none;border-radius:4px;cursor:pointer;">Cancelar</button>
          <button onclick="alterarReservaDireto('${r.id}', 'dieta')" style="flex:1 1 auto;padding:6px 10px;font-size:12px;background:#ffc107;color:#333;border:none;border-radius:4px;cursor:pointer;">Dieta</button>
          <button onclick="alterarReservaDireto('${r.id}', 'normal')" style="flex:1 1 auto;padding:6px 10px;font-size:12px;background:#e2e3e5;color:#333;border:1px solid #6c757d;border-radius:4px;cursor:pointer;">Normal</button>
        </div>
      ` : ""}
    </div>
  `;
  }).join("");
}

function exibirHistoricoFiltrado() {
  const div = document.getElementById("historico");
  if(!div) return;

  const reservas = historicoAtual || [];
  if (reservas.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem histórico disponível.</div>";
    return;
  }

  if(!_mesHistView) _mesHistView = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  const ano = _mesHistView.getFullYear();
  const mes = _mesHistView.getMonth();

  const porData = {};
  reservas.forEach(r => { (porData[r.data] = porData[r.data] || []).push(r); });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(porData).forEach(arr => arr.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9)));

  const hojeISO = new Date().toISOString().split("T")[0];
  const primeiroDia = new Date(ano, mes, 1);
  const diasNoMes = new Date(ano, mes + 1, 0).getDate();
  const offset = (primeiroDia.getDay() + 6) % 7;
  const diasSemana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"];

  let celulas = "";
  for(let i = 0; i < offset; i++) celulas += `<div></div>`;
  for(let dia = 1; dia <= diasNoMes; dia++){
    const iso = `${ano}-${_pad2c(mes+1)}-${_pad2c(dia)}`;
    const doDia = porData[iso] || [];
    const temReservas = doDia.length > 0;
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaHistSelecionado;
    const badges = doDia.map(r => _badgeMenuCantina(r.tipo)).join("");

    const fundo = isSel ? "#fff3cd" : (temReservas ? "#ffffff" : "transparent");
    const borda = isSel ? "2px solid #ffc107" : (temReservas ? "1px solid #c8e6c9" : "1px solid transparent");

    celulas += `
      <div onclick="${temReservas ? `selecionarDiaHistorico('${iso}')` : ''}"
        style="min-height:56px;padding:4px;border-radius:8px;background:${fundo};border:${borda};
               ${temReservas ? 'cursor:pointer;box-shadow:0 1px 2px rgba(0,0,0,0.06);' : ''}
               display:flex;flex-direction:column;align-items:center;gap:2px;">
        <span style="font-size:12px;font-weight:700;color:${isHoje ? '#d32f2f' : '#333'};
              ${isHoje ? 'background:#ffe0e0;border-radius:50%;width:20px;height:20px;display:flex;align-items:center;justify-content:center;' : ''}">${dia}</span>
        <div style="display:flex;flex-wrap:wrap;justify-content:center;">${badges}</div>
      </div>`;
  }

  let detalhe = "";
  if(_diaHistSelecionado){
    detalhe = `
      <div style="margin-top:16px;">
        <h3 style="color:#333;margin-bottom:10px;font-size:15px;">📅 ${formatarData(_diaHistSelecionado)}</h3>
        ${_cartoesHistoricoDia(_diaHistSelecionado)}
      </div>`;
  } else {
    detalhe = `<p style="text-align:center;color:#999;font-size:13px;margin-top:14px;">Toca num dia marcado para ver o que reservou e escolheu.</p>`;
  }

  div.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
      <button onclick="mudarMesHistorico(-1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">‹</button>
      <b style="font-size:16px;">${_NOMES_MESES_CANTINA[mes]} ${ano}</b>
      <button onclick="mudarMesHistorico(1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">›</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;margin-bottom:6px;">
      ${diasSemana.map(d => `<div style="font-size:11px;font-weight:700;color:#888;">${d}</div>`).join("")}
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">
      ${celulas}
    </div>
    ${detalhe}
  `;
}

function resetarFiltrosHistorico() {
  document.getElementById("pesquisaHistorico").value = "";
  document.getElementById("filtroTipoHistorico").value = "";
  document.getElementById("filtroStatusHistorico").value = "";
  historicoFiltrado = [...historicoAtual];
  exibirHistoricoFiltrado();
}

function backToHistoricoList() {
  historicoAtual = [];
  historicoFiltrado = [];
  alunoHistoricoAtual = null;
  showCantinaHistorico();
}

/* =============================
   CANTINA — SALDOS
============================= */

let alunoAtual = null;

async function showCantinaSaldos() {
  show("cantinaSaldos");
  const div = document.getElementById("listaSaldos");
  div.innerHTML = "⏳ A carregar valores em dívida...";

  showLoading("⏳ Carregando valores em dívida...");

  try {
    // A soma é feita na base de dados (saldos_por_aluno, migração 007). Antes
    // este ecrã ia buscar TODAS as reservas ativas e somava aqui, e o PostgREST
    // corta a resposta nas 1000 linhas por omissão: os alunos que ficavam de
    // fora apareciam sem dívida nenhuma, e o que calhava em cima do corte
    // aparecia com parte da dívida - tudo em silêncio, e esta é a lista pela
    // qual a cantina cobra. Terceira aparição do mesmo defeito (relatório
    // mensal, histórico de aluno, e este). A função devolve exatamente o que
    // este ecrã já consumia: { id, nome, total, refeicoes }.
    const { data, error } = await supabaseClient.rpc("saldos_por_aluno");

    if (error) {
      handleError(error, "Erro ao carregar Valores em Dívida");
      div.innerHTML = "<i>❌ Erro ao carregar dados.</i>";
      return;
    }

    if (!data || data.length === 0) {
      todosSaldos = [];
      saldosFiltrados = [];
      div.innerHTML = "<i>✅ Sem dívidas.</i>";
      return;
    }

    todosSaldos = data.map(s => ({ id: s.id, nome: s.nome, total: Number(s.total) }));
    saldosFiltrados = [...todosSaldos];
    ordenarSaldos('nome');

    renderizarSaldos();

    const inputPesquisa = document.getElementById("pesquisaSaldos");
    if(inputPesquisa) inputPesquisa.value = "";

  } catch (err) {
    handleError(err, "Erro ao carregar saldos");
    div.innerHTML = "<i>❌ Erro ao processar dados.</i>";
  } finally {
    hideLoading();
  }
}

function renderizarSaldos() {
  const div = document.getElementById("listaSaldos");
  
  if(!saldosFiltrados || saldosFiltrados.length === 0) {
    div.innerHTML = "<i>❌ Nenhum aluno com valor em dívida encontrado.</i>";
    return;
  }

  const html = saldosFiltrados
    .map(s => `
      <div class="saldo-linha" onclick="showSaldoAluno('${s.id}')">
        <span class="saldo-nome">${escapeHtml(s.nome)}</span>
        <span class="saldo-valor">${Number(s.total).toFixed(2)}€</span>
      </div>
    `)
    .join("");
  
  div.innerHTML = html;
}

function filtrarSaldos() {
  const termo = document.getElementById("pesquisaSaldos").value.toLowerCase().trim();
  
  if(!termo) {
    saldosFiltrados = [...todosSaldos];
  } else {
    saldosFiltrados = todosSaldos.filter(s => 
      s.nome.toLowerCase().includes(termo)
    );
  }
  
  renderizarSaldos();
}

function ordenarSaldos(tipo) {
  ordenacaoSaldos = tipo;
  
  if(tipo === 'nome') {
    saldosFiltrados.sort((a, b) => a.nome.localeCompare(b.nome));
  } else if(tipo === 'valor') {
    saldosFiltrados.sort((a, b) => b.total - a.total);
  }
  
  renderizarSaldos();
}

function resetarFiltrosSaldos() {
  document.getElementById("pesquisaSaldos").value = "";
  saldosFiltrados = [...todosSaldos];
  ordenarSaldos('nome');
}

async function showSaldoAluno(alunoId) {
  alunoAtual = alunoId;
  show("cantinaSaldoAluno");
  
  showLoading("⏳ Carregando dados...");

  try {
    const { data: dividas, error } = await supabaseClient
      .rpc('obter_divida_por_mes', { p_aluno_id: alunoId });

    if (error) {
      handleError(error, "Erro ao carregar dívidas do aluno");
      return;
    }

    if (!dividas || dividas.length === 0) {
      document.getElementById("tituloAluno").innerText = "Sem dívidas";
      document.getElementById("valorTotal").innerText = "€0.00";
      document.getElementById("mesesDivida").innerHTML = "";
      document.getElementById("btnLiquidarTotal").style.display = "none";
      return;
    }

    // Continuar com o fluxo normal se a RPC funcionou
    await processarDividasEncontradas(alunoId, dividas);

  } catch (err) {
    console.error("Erro ao processar dados do aluno:", err);
    handleError(err, "Erro ao carregar dados do aluno");
  } finally {
    hideLoading();
  }
}

// Função auxiliar para processar dívidas encontradas
async function processarDividasEncontradas(alunoId, dividas) {
  // Obter nome do aluno
  const { data: aluno } = await supabaseClient
    .from("alunos")
    .select("nome")
    .eq("id", alunoId)
    .single();

  if (aluno && aluno.nome) {
    document.getElementById("tituloAluno").innerText = aluno.nome;
  } else {
    document.getElementById("tituloAluno").innerText = "Aluno";
  }

  // Calcular total
  const total = dividas.reduce((sum, item) => sum + Number(item.valor), 0);
  document.getElementById("valorTotal").innerText = `${total.toFixed(2)}€`;

  // Exibir meses em dívida
  const mesesDivida = document.getElementById("mesesDivida");
  mesesDivida.innerHTML = "";

  const nomesMeses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];

  dividas.forEach(item => {
    const nomeMes = nomesMeses[item.mes - 1];
    const emAtraso = item.em_atraso;


    mesesDivida.innerHTML += `
      <div class="mes-divida ${emAtraso ? 'em-atraso' : ''}">
        <span>${nomeMes} ${item.ano}</span>
        <strong>${Number(item.valor).toFixed(2)}€</strong>
        <button class="${emAtraso ? 'btn-atraso' : ''}" onclick="liquidarMes('${alunoId}', ${item.ano}, ${item.mes})">
          ${emAtraso ? '⚠️ Liquidar' : 'Liquidar mês'}
        </button>
      </div>
    `;
  });

  // Mostrar botão de liquidar total
  const btnLiquidar = document.getElementById("btnLiquidarTotal");
  btnLiquidar.classList.remove("hidden");
  btnLiquidar.style.display = "block";
}

// Função de fallback caso a nova função não exista

/* =============================
   CANTINA — AÇÕES DE LIQUIDAÇÃO
============================= */

async function liquidarDividaTotal(alunoId) {
  
  if (!alunoId) {
    mostrarErro("Erro", "Aluno inválido. Volte atrás e tente novamente.");
    return;
  }

  if (!await confirmar("Liquidar Dívida", "Tem certeza que deseja liquidar TODA a dívida deste aluno?")) {
    return;
  }

  showLoading("⏳ Liquidando dívida...");

  try {
    // Derivar TODOS os meses com valor pendente diretamente das reservas ativas
    // (a RPC de dívida por mês pode omitir meses futuros, deixando dívida por liquidar)
    const { data: reservas, error: erroReservas } = await supabaseClient
      .from("reservas")
      .select("data")
      .eq("aluno_id", alunoId)
      .eq("ativa", true);

    if (erroReservas) {
      console.error("❌ Erro ao buscar reservas:", erroReservas);
      handleError(erroReservas, "Erro ao buscar dívidas");
      return;
    }

    if (!reservas || reservas.length === 0) {
      mostrarInfo("Sem dívida", "Este aluno não tem dívidas");
      return;
    }

    // Conjunto único de {ano, mes}
    const mapMeses = {};
    reservas.forEach(r => {
      const d = new Date(r.data);
      mapMeses[`${d.getFullYear()}-${d.getMonth() + 1}`] = {
        ano: d.getFullYear(),
        mes: d.getMonth() + 1
      };
    });
    const dividas = Object.values(mapMeses);

    // Liquidar cada mês individualmente
    let totalLiquidado = 0;
    let mesesLiquidados = 0;

    for (const divida of dividas) {
      const { data: resultado, error } = await supabaseClient.rpc('liquidar_mes_divida', {
        p_aluno_id: alunoId,
        p_ano: divida.ano,
        p_mes: divida.mes
      });

      if (!error && resultado && resultado.length > 0) {
        const res = resultado[0];
        if (res.success && Number(res.valor_liquidado) > 0) {
          totalLiquidado += Number(res.valor_liquidado);
          mesesLiquidados++;
        }
      }
    }

    if (mesesLiquidados === 0) {
      mostrarInfo("Sem dívida", "Este aluno não tem dívidas para liquidar");
    } else {
      mostrarSucesso("Dívida Liquidada", 
        `Dívida liquidada com sucesso! (${mesesLiquidados} mês${mesesLiquidados !== 1 ? 'es' : ''}) - Valor: ${totalLiquidado.toFixed(2)}€`);
    }
    
    
    // Recarregar dados do aluno
    setTimeout(() => {
      showSaldoAluno(alunoId);
    }, 1500);
    
  } catch (err) {
    console.error("❌ Erro exception:", err);
    handleError(err, "Erro ao liquidar dívida");
  } finally {
    hideLoading();
  }
}

async function liquidarMes(alunoId, ano, mes) {
  const nomesMeses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];
  const nomeMes = nomesMeses[mes - 1];
  
  if (!await confirmar("Liquidar Mês", `Deseja liquidar o mês ${nomeMes} ${ano}?`)) {
    return;
  }

  showLoading("⏳ Liquidando mês...");

  try {
    // Usar a função nova que funciona corretamente
    const { data, error } = await supabaseClient.rpc('liquidar_mes_divida', {
      p_aluno_id: alunoId,
      p_ano: ano,
      p_mes: mes
    });

    if (error) {
      console.error("❌ Erro ao liquidar mês:", error);
      handleError(error, "Erro ao liquidar mês");
      return;
    }

    if (data && data.length > 0) {
      const resultado = data[0];
      
      if (!resultado.success) {
        mostrarErro("Erro", resultado.message || "Erro ao liquidar mês");
        return;
      }

      if (Number(resultado.valor_liquidado) === 0) {
        mostrarInfo("Sem dívida", `Não há dívidas para ${nomeMes} ${ano}`);
      } else {
        mostrarSucesso("Mês Liquidado", 
          `${nomeMes} ${ano} liquidado com sucesso! Valor: ${Number(resultado.valor_liquidado).toFixed(2)}€`);
      }
    }
    
    
    // Recarregar dados do aluno
    setTimeout(() => {
      showSaldoAluno(alunoId);
    }, 1500);
    
  } catch (err) {
    console.error("❌ Erro exception:", err);
    handleError(err, "Erro ao liquidar mês");
  } finally {
    hideLoading();
  }
}

/* =============================
   CANTINA — RELATÓRIO MENSAL
============================= */

function abrirRelatorioMensal() {
  esconderTodasPaginas();
  show("paginaRelatorio");
  preencherRelatorioPeriodos();
}

function esconderTodasPaginas() {
  document.querySelectorAll(".pagina, .container")
    .forEach(p => p.classList.add("hidden"));
}


// Só permite relatório do mês atual e do mês anterior (este último apenas até dia 15)
function preencherRelatorioPeriodos() {
  const mesSelect = document.getElementById("relatorioMes");
  if(!mesSelect) return;

  const nomesMeses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];

  const hoje = new Date();
  const periodos = [{ ano: hoje.getFullYear(), mes: hoje.getMonth() + 1 }];
  if (hoje.getDate() <= 15) {
    const p = new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1);
    periodos.unshift({ ano: p.getFullYear(), mes: p.getMonth() + 1 });
  }

  mesSelect.innerHTML = periodos
    .map(p => `<option value="${p.ano}-${p.mes}">${nomesMeses[p.mes - 1]} ${p.ano}</option>`)
    .join("");
  // Selecionar por defeito o mês atual (último da lista)
  mesSelect.value = `${hoje.getFullYear()}-${hoje.getMonth() + 1}`;
}

// Compatibilidade: o botão "Preparar Relatório" apenas repõe os períodos permitidos
function prepararRelatorio() {
  show("paginaRelatorio");
  preencherRelatorioPeriodos();
}

async function gerarRelatorioMensal() {
  const periodo = (getEl("relatorioMes").value || "").split("-");
  const ano = Number(periodo[0]);
  const mes = Number(periodo[1]);

  if (!ano || !mes) {
    mostrarInfo("Período inválido", "Seleciona um mês válido.");
    return;
  }

  showLoading("⏳ Gerando relatório...");

  try {
    // A soma passou para a base de dados. Antes isto ia buscar TODAS as reservas
    // ativas e somava-as aqui, e o PostgREST corta a resposta nas 1000 linhas
    // por omissão — verificado, devolvia exatamente 1000 havendo 1195 reservas.
    // O Excel já andava a perder alunos sem ninguém dar por isso, porque um
    // ficheiro com menos linhas não tem ar de estar errado. Com carga a sério um
    // mês são ~8000 reservas e o relatório apanhava um oitavo delas.
    // Uma linha por aluno nunca chega perto desse limite.
    const { data, error } = await supabaseClient
      .rpc("relatorio_mensal", { p_ano: ano, p_mes: mes });

    if (error) {
      mostrarErro("Erro", error.message || "Erro ao gerar relatório");
      console.error(error);
      return;
    }

    const resultado = data || [];

    if (!resultado || resultado.length === 0) {
      mostrarInfo("Sem Dados", "Sem dados para este mês");
      return;
    }

    exportarRelatorioExcel(resultado, ano, mes);
  } catch (err) {
    mostrarErro("Erro", "Erro ao processar relatório");
    console.error(err);
  } finally {
    hideLoading();
  }
}

function exportarRelatorioExcel(dados, ano, mes) {
  const linhas = [["Aluno", "Total Refeições", "Total (€)"]];
  dados.forEach(r => {
    linhas.push([
      r.nome,
      r.total_refeicoes,
      r.total_valor.toFixed(2)
    ]);
  });

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  XLSX.utils.book_append_sheet(wb, ws, "Relatório");

  const nomeFicheiro = `relatorio_${ano}_${String(mes).padStart(2,"0")}.xlsx`;
  XLSX.writeFile(wb, nomeFicheiro);
}

/* =============================
   EXPORTAÇÕES CANTINA
============================= */

async function exportarSaldosExcel() {
  // Mesma consulta que o ecrã, pela mesma razão: a soma no browser sobre a
  // tabela inteira parava nas 1000 linhas e o Excel saía com valores errados.
  // Ver showCantinaSaldos. A função já vem ordenada por nome e traz o número
  // de refeições, que é a coluna que este ficheiro precisa e o ecrã não.
  const { data, error } = await supabaseClient.rpc("saldos_por_aluno");

  if (error) {
    mostrarErro("Erro", "Erro ao buscar valores em dívida: " + error.message);
    console.error("❌ Erro ao buscar valores em dívida", error);
    return;
  }

  if (!data || data.length === 0) {
    mostrarInfo("Sem Débitos", "Sem débitos para exportar.");
    return;
  }

  const linhas = [["Aluno", "Refeições", "Total Dívida (€)"]];
  let totalGeral = 0;
  let refeicaoesTotal = 0;

  data.forEach(aluno => {
    const total = Number(aluno.total);
    linhas.push([
      aluno.nome,
      aluno.refeicoes,
      total.toFixed(2)
    ]);
    totalGeral += total;
    refeicaoesTotal += aluno.refeicoes;
  });

  linhas.push([]);
  linhas.push(["TOTAL", refeicaoesTotal, totalGeral.toFixed(2)]);

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  
  ws['!cols'] = [
    { wch: 25 },
    { wch: 12 },
    { wch: 15 }
  ];

  XLSX.utils.book_append_sheet(wb, ws, "Valores em dívida");

  const agora = new Date();
  const data_hora = `${agora.getDate()}-${String(agora.getMonth() + 1).padStart(2, '0')}-${agora.getFullYear()}_${String(agora.getHours()).padStart(2, '0')}h${String(agora.getMinutes()).padStart(2, '0')}`;
  const nomeFicheiro = `valores_em_divida_${data_hora}.xlsx`;
  
  XLSX.writeFile(wb, nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}

async function exportarHistoricoAluno() {
  if (!alunoAtual) {
    mostrarErro("Erro", "Nenhum aluno selecionado.");
    return;
  }


  const { data: aluno } = await supabaseClient
    .from("alunos")
    .select("nome")
    .eq("id", alunoAtual)
    .single();

  const { data: reservas, error } = await supabaseClient
    .from("reservas")
    .select("data, tipo, preco, ativa, cancelamento_tipo, is_dieta, menus(prato)")
    .eq("aluno_id", alunoAtual)
    .order("data", { ascending: false });

  if (error) {
    mostrarErro("Erro", "Erro ao buscar histórico: " + error.message);
    console.error("❌ Erro ao buscar histórico", error);
    return;
  }

  if (!reservas || reservas.length === 0) {
    mostrarInfo("Sem Histórico", "Sem histórico para este aluno.");
    return;
  }

  const linhas = [
    [`Histórico de Reservas - ${aluno.nome}`],
    [],
    ["Data", "Tipo", "Prato", "Preço (€)", "Dieta", "Status"]
  ];

  let totalAtivo = 0;

  reservas.forEach(r => {
    const tipoFormatado = r.tipo.replace("_", " ").toUpperCase();
    const dieta = r.is_dieta ? "Sim" : "Não";
    const status = _estadoReserva(r).texto;
    
    linhas.push([
      formatarData(r.data),
      tipoFormatado,
      r.menus?.prato || "",
      r.preco.toFixed(2),
      dieta,
      status
    ]);

    if (r.ativa) {
      totalAtivo += r.preco;
    }
  });

  linhas.push([]);
  linhas.push(["Total em Dívida:", "", "", totalAtivo.toFixed(2), "", ""]);

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);

  ws['!cols'] = [
    { wch: 12 },
    { wch: 18 },
    { wch: 20 },
    { wch: 10 },
    { wch: 8 },
    { wch: 12 }
  ];

  XLSX.utils.book_append_sheet(wb, ws, "Histórico");

  const agora = new Date();
  const data_hora = `${agora.getDate()}-${String(agora.getMonth() + 1).padStart(2, '0')}-${agora.getFullYear()}`;
  const nomeFicheiro = `historico_${aluno.nome.replace(/\s+/g, '_')}_${data_hora}.xlsx`;

  XLSX.writeFile(wb, nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}


/* =============================
   CANTINA — PEDIDOS DE CANCELAMENTO (Cluster 6, passo 4)
============================== */

let _pedidosPendentes = [];

async function showPedidosCancelamento(){
  show("cantinaPedidos");

  const div = document.getElementById("listaPedidos");
  div.innerHTML = "⏳ A carregar pedidos...";

  // listar_solicitacoes_pendentes NÃO é SECURITY DEFINER de própria vontade: as
  // duas políticas de SELECT da 005 fazem o âmbito sozinhas. A cantina vê tudo.
  const { data, error } = await supabaseClient.rpc("listar_solicitacoes_pendentes");

  if(error){
    div.innerHTML = `<i>❌ Erro: ${escapeHtml(error.message)}</i>`;
    return;
  }

  _pedidosPendentes = data || [];

  if(!_pedidosPendentes.length){
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem pedidos pendentes.</div>";
    return;
  }

  div.innerHTML = _pedidosPendentes.map(_cartaoPedido).join("");
}

// TUDO o que o aluno escreveu passa por escapeHtml. Isto é renderizado na sessão
// da cantina, que é a conta que aprova cancelamentos e liquida dívidas.
function _cartaoPedido(p){
  return `
    <div style="border:1px solid #e0e0e0; border-radius:10px; padding:12px; margin-bottom:10px; text-align:left;">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
        <b>👤 ${escapeHtml(p.aluno_nome)}</b>
        <span style="color:#666; font-size:13px;">${formatarTipoRefeicao(p.tipo_refeicao)} · ${p.data_reserva}</span>
      </div>
      <div style="font-size:13px; color:#555; margin-bottom:6px;">${escapeHtml(p.motivo || "-")}</div>
      ${p.troca_por_lanche ? `
        <div style="font-size:13px; color:#555; margin-bottom:6px;">
          🥪 Pede troca por lanche: ${escapeHtml(p.lanche_substituto || "não especificado")}
        </div>
      ` : ""}
      <div style="font-size:12px; color:#888; margin-bottom:8px;">
        Cancelamentos aprovados nos últimos 30 dias: ${p.cancelamentos_30_dias}
      </div>
      <!-- flex:1 1 auto, NAO flex:1. O flex:1 e flex:1 1 0%, e uma base zero
           iguala as larguras ignorando o conteudo, o que cortava o ultimo "r"
           do "Cancelar". Com base auto a largura parte do texto e o
           min-width:auto impede o botao de encolher abaixo dele. -->
      <div style="display:flex; gap:6px; flex-wrap:wrap;">
        <button onclick="decidirPedido('${p.solicitacao_id}', 'cancelar')" style="flex:1 1 auto; padding:8px 10px; background:#dc3545; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">Cancelar</button>
        <button onclick="decidirPedido('${p.solicitacao_id}', 'dieta')" style="flex:1 1 auto; padding:8px 10px; background:#ffc107; color:#333; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">Dieta</button>
        <button onclick="decidirPedido('${p.solicitacao_id}', 'outros')" style="flex:1 1 auto; padding:8px 10px; background:#0d6efd; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">Outros</button>
        <button onclick="rejeitarPedido('${p.solicitacao_id}')" style="flex:1 1 auto; padding:8px 10px; background:#6c757d; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">Rejeitar</button>
      </div>
    </div>
  `;
}

const _ROTULO_DECISAO = {
  cancelar: "cancelar a reserva",
  dieta:    "passar a reserva a dieta",
  outros:   "registar a troca por outros alimentos e manter a reserva"
};

async function decidirPedido(solicitacaoId, decisao){
  if(!await confirmar("Aprovar Pedido", `Confirmas ${_ROTULO_DECISAO[decisao]}?`)) return;

  showLoading("⏳ A aprovar...");
  try {
    const { error } = await supabaseClient.rpc("aprovar_cancelamento_especial", {
      p_solicitacao_id: solicitacaoId,
      p_decisao: decisao,
      p_observacoes: null
    });
    hideLoading();

    if(error){
      // "Pedido inexistente ou já processado" quer normalmente dizer que outra
      // pessoa da cantina já decidiu isto, ou um duplo-clique. Mostrar e
      // recarregar, para a linha desaparecer.
      await mostrarErro("Erro ao Aprovar", error.message || "Erro inesperado");
      showPedidosCancelamento();
      return;
    }

    await mostrarSucesso("Pedido Aprovado", "O pedido foi decidido.");
    showPedidosCancelamento();
  } catch (err) {
    await mostrarErro("Erro", err?.message || "Erro inesperado ao aprovar");
  } finally {
    hideLoading();
  }
}

async function rejeitarPedido(solicitacaoId){
  if(!await confirmar("Rejeitar Pedido", "Confirmas que rejeitas este pedido? A refeição mantém-se.")) return;

  showLoading("⏳ A rejeitar...");
  try {
    const { error } = await supabaseClient.rpc("rejeitar_cancelamento_especial", {
      p_solicitacao_id: solicitacaoId,
      p_observacoes: null
    });
    hideLoading();

    if(error){
      await mostrarErro("Erro ao Rejeitar", error.message || "Erro inesperado");
      showPedidosCancelamento();
      return;
    }

    await mostrarSucesso("Pedido Rejeitado", "O pedido foi rejeitado.");
    showPedidosCancelamento();
  } catch (err) {
    await mostrarErro("Erro", err?.message || "Erro inesperado ao rejeitar");
  } finally {
    hideLoading();
  }
}

const _ROTULO_DIRETO = {
  cancelar: "cancelar esta reserva",
  dieta:    "passar esta reserva a dieta",
  normal:   "voltar esta reserva a prato normal"
};

// Para quando o aluno telefona em vez de usar a app. A função da 005 deixa
// rasto em cancelamentos_especiais sozinha, já como 'aprovado'.
async function alterarReservaDireto(reservaId, decisao){
  if(!await confirmar("Alterar Reserva", `Confirmas ${_ROTULO_DIRETO[decisao]}?`)) return;

  showLoading("⏳ A alterar...");
  try {
    const { error } = await supabaseClient.rpc("cantina_alterar_reserva", {
      p_reserva_id: reservaId,
      p_decisao: decisao,
      p_nota: null
    });
    hideLoading();

    if(error){
      await mostrarErro("Erro ao Alterar", error.message || "Erro inesperado");
      return;
    }

    await mostrarSucesso("Reserva Alterada", "A reserva foi alterada.");
    showHistoricoAluno(alunoHistoricoAtual);
  } catch (err) {
    await mostrarErro("Erro", err?.message || "Erro inesperado ao alterar reserva");
  } finally {
    hideLoading();
  }
}

/* ==============================
   CANTINA — LEITOR DE CÓDIGOS
============================== */

let _leitorTipo = null;
let _leitorHistorico = [];

// A refeição escolhe-se UMA vez e fica visível em grande o tempo todo. Um turno
// esquecido depois do pequeno-almoço tem de saltar à vista aqui, e não ser
// descoberto na exportação uma semana depois.
function showLeitorCodigo(){
  show("cantinaLeitor");
  _leitorTipo = null;
  _leitorHistorico = [];
  _renderLeitor();
}

function _leitorEscolherTipo(tipo){
  _leitorTipo = tipo;
  _renderLeitor();
}

function _renderLeitor(){
  const div = document.getElementById("leitorConteudo");

  if(!_leitorTipo){
    div.innerHTML = `
      <p>Que refeição estás a servir?</p>
      <button class="btn-full" onclick="_leitorEscolherTipo('pequeno_almoco')">🥐 Pequeno Almoço</button>
      <button class="btn-full" onclick="_leitorEscolherTipo('almoco')">🍽️ Almoço</button>
      <button class="btn-full" onclick="_leitorEscolherTipo('jantar')">🌙 Jantar</button>
    `;
    return;
  }

  div.innerHTML = `
    <div style="background:#1565c0;color:#fff;padding:14px;border-radius:12px;
                font-size:22px;font-weight:800;text-align:center;">
      ${emojiTipo(_leitorTipo)} ${formatarTipoRefeicao(_leitorTipo)}
      <button class="btn-medium" style="margin-left:12px;"
              onclick="_leitorEscolherTipo(null)">Mudar</button>
    </div>

    <input id="leitorInput" autocomplete="off" inputmode="numeric"
           placeholder="Passa o código..."
           style="width:100%;box-sizing:border-box;font-size:20px;padding:12px;
                  margin-top:14px;text-align:center;">

    <div id="leitorResultado" style="margin-top:16px;"></div>

    <div style="margin-top:18px;color:#666;font-size:13px;">
      Leituras nesta sessão: <b id="leitorContagem">${_leitorHistorico.length}</b>
    </div>
    <div id="leitorHistorico" style="margin-top:8px;"></div>

    <button class="btn-medium" style="margin-top:14px;"
            onclick="exportarLeiturasExcel()">🖨️ Exportar leituras de hoje</button>
  `;

  const input = document.getElementById("leitorInput");

  // O leitor USB é um teclado: escreve os dígitos e carrega em Enter. Não há
  // API de dispositivo nenhuma aqui — é só um keydown.
  input.addEventListener("keydown", (e) => {
    if(e.key !== "Enter") return;
    e.preventDefault();
    const codigo = input.value.trim();
    input.value = "";
    if(codigo) _leitorProcessar(codigo);
  });

  // O foco tem de ser agressivo. Uma leitura para uma página sem foco perde-se
  // em silêncio, e ao balcão isso é um aluno que se vai embora sem ficar
  // registado.
  input.focus();
  document.getElementById("cantinaLeitor").onclick = () => input.focus();
}

async function _leitorProcessar(codigo){
  const div = document.getElementById("leitorResultado");
  div.innerHTML = "⏳";

  const { data, error } = await supabaseClient.rpc("registar_leitura", {
    p_codigo: codigo,
    p_tipo: _leitorTipo
  });

  if(error){
    div.innerHTML = `<div style="background:#c62828;color:#fff;padding:18px;border-radius:12px;">
      ❌ Erro: ${escapeHtml(error.message)}</div>`;
    return;
  }

  const r = (data && data[0]) || {};
  const cores = {
    servido:             { cor:"#2e7d32", icone:"✅", texto:"PODE SERVIR" },
    sem_reserva:         { cor:"#c62828", icone:"⛔", texto:"SEM RESERVA" },
    cancelada:           { cor:"#c62828", icone:"⛔", texto:"RESERVA CANCELADA" },
    repetido:            { cor:"#f9a825", icone:"⚠️", texto:"JÁ TINHA SIDO SERVIDO" },
    codigo_desconhecido: { cor:"#c62828", icone:"❓", texto:"CÓDIGO DESCONHECIDO" }
  };
  const e = cores[r.resultado] || { cor:"#666", icone:"❓", texto:escapeHtml(r.resultado || "?") };

  div.innerHTML = `
    <div style="background:${e.cor};color:#fff;padding:22px;border-radius:14px;text-align:center;">
      <div style="font-size:40px;">${e.icone}</div>
      <div style="font-size:22px;font-weight:800;margin-top:6px;">${e.texto}</div>
      <div style="font-size:20px;margin-top:10px;">${escapeHtml(r.nome || codigo)}</div>
      ${r.is_dieta ? `<div style="margin-top:10px;font-size:20px;font-weight:800;
        background:#fff;color:#f9a825;border-radius:8px;padding:6px;">🥗 DIETA</div>` : ""}
    </div>
  `;

  _leitorHistorico.unshift({ nome: r.nome || codigo, resultado: r.resultado });
  document.getElementById("leitorContagem").textContent = _leitorHistorico.length;
  document.getElementById("leitorHistorico").innerHTML = _leitorHistorico
    .slice(0, 5)
    .map(h => `<div style="padding:6px 0;border-bottom:1px solid #eee;font-size:14px;">
        ${escapeHtml(h.nome)} — ${escapeHtml(h.resultado)}</div>`)
    .join("");

  document.getElementById("leitorInput").focus();
}

// FILTRADO POR DIA, DE PROPÓSITO. Uma consulta sem limites sobre um registo que
// só cresce é exatamente o defeito das 1000 linhas do PostgREST, já encontrado
// três vezes nesta aplicação — e um registo de leituras cresce mais depressa do
// que as reservas cresceram. Um dia de leituras fica muito abaixo do corte.
async function exportarLeiturasExcel(){
  // O dia de Lisboa, não o UTC: a coluna data das leituras é escrita pelo
  // servidor como (now() AT TIME ZONE 'Europe/Lisbon')::date. Com o UTC, entre
  // a meia-noite e a uma da manhã no verão o ficheiro saía do dia errado.
  // (sv-SE formata como AAAA-MM-DD.)
  const dia = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Lisbon" });

  const { data, error } = await supabaseClient
    .from("leituras")
    .select("data, tipo, resultado, codigo_lido, criado_em, alunos(nome)")
    .eq("data", dia)
    .order("criado_em");

  if(error){
    mostrarErro("Erro", "Erro ao exportar leituras: " + error.message);
    return;
  }

  if(!data || data.length === 0){
    mostrarInfo("Sem Leituras", "Não há leituras registadas hoje.");
    return;
  }

  const linhas = [["Data", "Hora", "Refeição", "Aluno", "Código lido", "Resultado"]];

  data.forEach(l => {
    const h = new Date(l.criado_em);
    linhas.push([
      l.data,
      `${String(h.getHours()).padStart(2,"0")}:${String(h.getMinutes()).padStart(2,"0")}`,
      formatarTipoRefeicao(l.tipo),
      l.alunos ? l.alunos.nome : "(desconhecido)",
      l.codigo_lido,
      l.resultado
    ]);
  });

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  ws['!cols'] = [{wch:12},{wch:8},{wch:16},{wch:25},{wch:14},{wch:20}];
  XLSX.utils.book_append_sheet(wb, ws, "Leituras");

  const nomeFicheiro = `leituras_${dia}.xlsx`;
  XLSX.writeFile(wb, nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}

/* ==============================
   CANTINA — ALUNOS (CONTRATOS)
============================== */

let _alunosContrato = [];
let _alunosContratoFiltrados = [];

// Um ecrã próprio e não um botão na lista do Histórico: aquela lista é um
// seletor, e pôr um controlo que muda o que um aluno paga ao lado de "abrir o
// histórico deste aluno" é a receita para um clique errado no sítio errado.
async function showCantinaAlunos(){
  show("cantinaAlunos");
  const div = document.getElementById("listaAlunosContrato");
  div.innerHTML = "⏳ A carregar alunos...";

  const { data: cfg, error: errCfg } = await supabaseClient
    .from("configuracao").select("preco_almoco_sem_contrato").single();
  document.getElementById("precoSemContrato").value =
    cfg ? Number(cfg.preco_almoco_sem_contrato).toFixed(2) : "";
  // Um campo em branco sem explicação convidava a escrever um preço por cima
  // de um erro. Dizer o que se passou.
  if (errCfg) mostrarErro("Erro", "Não foi possível ler o preço do almoço sem contrato: " + errCfg.message);

  // Cresce com os alunos, não com as refeições - nunca chega perto do corte
  // das 1000 linhas.
  const { data, error } = await supabaseClient
    .from("alunos")
    .select("id, nome, tem_contrato")
    .order("nome");

  if (error) {
    div.innerHTML = `<i>❌ Erro: ${escapeHtml(error.message)}</i>`;
    return;
  }

  _alunosContrato = data || [];
  _alunosContratoFiltrados = [..._alunosContrato];
  document.getElementById("pesquisaAlunosContrato").value = "";
  _renderAlunosContrato();
}

function filtrarAlunosContrato(){
  const termo = document.getElementById("pesquisaAlunosContrato").value.toLowerCase().trim();
  _alunosContratoFiltrados = termo
    ? _alunosContrato.filter(a => a.nome.toLowerCase().includes(termo))
    : [..._alunosContrato];
  _renderAlunosContrato();
}

function _renderAlunosContrato(){
  const div = document.getElementById("listaAlunosContrato");
  const total = _alunosContrato.length;
  const sem = _alunosContrato.filter(a => !a.tem_contrato).length;
  document.getElementById("alunosContratoContagem").textContent =
    `👥 ${total} aluno${total !== 1 ? "s" : ""} · ${sem} sem contrato`;

  if(!_alunosContratoFiltrados.length){
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>🔍</div>Nenhum aluno encontrado.</div>";
    return;
  }

  div.innerHTML = _alunosContratoFiltrados.map(a => `
    <div class="aluno-contrato-linha"
         style="display:flex;align-items:center;justify-content:space-between;gap:10px;
                padding:10px 8px;border-bottom:1px solid #eee;">
      <div>
        <div style="font-weight:600;">${escapeHtml(a.nome)}</div>
        <div style="font-size:13px;color:${a.tem_contrato ? "#2e7d32" : "#c62828"};">
          ${a.tem_contrato ? "✅ Com contrato" : "🏷️ Sem contrato"}
        </div>
      </div>
      <button class="btn-medium"
              onclick="_alternarContrato('${a.id}', ${a.tem_contrato})">
        ${a.tem_contrato ? "Retirar contrato" : "Dar contrato"}
      </button>
    </div>
  `).join("");
}

// A confirmação diz QUANTOS almoços vão ser cancelados. É uma mudança do que o
// aluno é cobrado e não é obviamente reversível para quem clica.
async function _alternarContrato(alunoId, temContratoAtual){
  const aluno = _alunosContrato.find(a => a.id === alunoId);
  const nome = aluno ? aluno.nome : "este aluno";

  if(temContratoAtual){
    const { data: n } = await supabaseClient
      .rpc("contar_almocos_automaticos_futuros", { p_aluno_id: alunoId });
    const quantos = Number(n) || 0;
    const ok = await showModal({
      icon: "🏷️",
      title: "Retirar o contrato?",
      message: `<b>${escapeHtml(nome)}</b> deixa de ter almoço automático e passa a pagar o preço sem contrato.<br><br>`
             + `Vão ser cancelados <b>${quantos} almoço${quantos !== 1 ? "s" : ""}</b> já marcado${quantos !== 1 ? "s" : ""} para os próximos dias. `
             + `O de hoje e os passados não mudam. O aluno pode voltar a marcá-los.`,
      type: "warning",
      buttons: [
        { text: "Cancelar", type: "secondary", resolve: false },
        { text: "Retirar contrato", type: "danger", resolve: true }
      ]
    });
    if(!ok) return;
  }

  const { error } = await supabaseClient
    .rpc("definir_contrato_aluno", { p_aluno_id: alunoId, p_tem_contrato: !temContratoAtual });

  if(error){
    mostrarErro("Erro", "Não foi possível alterar o contrato: " + error.message);
    return;
  }

  if(aluno) aluno.tem_contrato = !temContratoAtual;
  _renderAlunosContrato();
}

async function guardarPrecoSemContrato(){
  const valor = Number(String(document.getElementById("precoSemContrato").value).replace(",", "."));
  if(!(valor > 0)){
    mostrarErro("Valor inválido", "Indica um preço maior do que zero.");
    return;
  }

  const { error } = await supabaseClient
    .from("configuracao")
    .update({ preco_almoco_sem_contrato: valor })
    .eq("id", true);

  if(error){
    mostrarErro("Erro", "Não foi possível guardar o preço: " + error.message);
    return;
  }
  mostrarSucesso("Preço guardado", `Almoço sem contrato: ${formatCurrency(valor)}`, 1800);
}
