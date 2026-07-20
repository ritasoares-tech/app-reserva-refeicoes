// Funções da área do aluno (menus, reservas e ações sobre reservas)

/* ==============================
   ALUNO — MENU POR DATA E RESERVAS
============================== */
function formatarData(dataISO) {
  if (!dataISO) return "";
  const [ano, mes, dia] = dataISO.split("-");
  return `${dia}/${mes}/${ano}`;
}
/* Estado do calendário de reservar refeição */
let _menusAluno = [];              // menus disponíveis (>= hoje)
let _reservasAtivasMenu = {};      // menu_id -> true (já reservado pelo aluno)
let _mesMenuView = null;           // primeiro dia do mês em visualização
let _diaMenuSelecionado = null;    // data ISO do dia selecionado

async function showAlunoMenu() {
  show("alunoMenu");
  addBack("alunoMenu");

  showLoading("⏳ Carregando menus...");

  try {
    const hoje = new Date().toISOString().split("T")[0];
    const aluno = await getAlunoAtual();

    const { data: menusRaw, error: errMenus } = await supabaseClient
      .from("menus")
      .select("*")
      .gte("data", hoje)
      .order("data", { ascending: true });

    if (errMenus) {
      handleError(errMenus, "Erro ao carregar menus");
      return;
    }

    _menusAluno = menusRaw || [];

    const { data: reservas } = await supabaseClient
      .from("reservas")
      .select("menu_id")
      .eq("aluno_id", aluno.id)
      .is("cancelamento_tipo", null);

    _reservasAtivasMenu = {};
    reservas?.forEach(r => _reservasAtivasMenu[r.menu_id] = true);

    // Mês inicial: o do primeiro menu disponível, senão o atual
    if(!_mesMenuView){
      const base = _menusAluno.length ? new Date(_menusAluno[0].data) : new Date();
      _mesMenuView = new Date(base.getFullYear(), base.getMonth(), 1);
    }
    _diaMenuSelecionado = null;
    renderCalendarioMenu();
  } catch (err) {
    handleError(err, "Erro ao carregar menus");
    const el = document.getElementById("listaAlunoMenu");
    if (el) el.innerHTML = "<i>❌ Erro ao processar dados.</i>";
  } finally {
    hideLoading();
  }
}

function mudarMesMenu(delta){
  if(!_mesMenuView) _mesMenuView = new Date();
  _mesMenuView = new Date(_mesMenuView.getFullYear(), _mesMenuView.getMonth() + delta, 1);
  _diaMenuSelecionado = null;
  renderCalendarioMenu();
}

function selecionarDiaMenu(iso){
  _diaMenuSelecionado = (_diaMenuSelecionado === iso) ? null : iso;
  renderCalendarioMenu();
}

// Etiqueta do tipo de menu no calendário
function _badgeMenu(tipo){
  const map = {
    pequeno_almoco: { txt: "P.A", bg: "#e3f2fd", cor: "#1565c0" },
    almoco:         { txt: "A",   bg: "#e8f5e9", cor: "#2e7d32" },
    jantar:         { txt: "J",   bg: "#f3e5f5", cor: "#6a1b9a" }
  };
  const m = map[tipo] || { txt: "?", bg: "#eee", cor: "#333" };
  return `<span style="display:inline-block;font-size:10px;font-weight:800;line-height:1;padding:2px 5px;border-radius:6px;background:${m.bg};color:${m.cor};margin:1px;">${m.txt}</span>`;
}

function renderCalendarioMenu(){
  const container = document.getElementById("listaAlunoMenu");
  if(!container) return;

  const ano = _mesMenuView.getFullYear();
  const mes = _mesMenuView.getMonth();

  // Agrupar menus por dia
  const menusPorData = {};
  _menusAluno.forEach(m => {
    (menusPorData[m.data] = menusPorData[m.data] || []).push(m);
  });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(menusPorData).forEach(arr =>
    arr.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9))
  );

  const hojeISO = new Date().toISOString().split("T")[0];
  const primeiroDia = new Date(ano, mes, 1);
  const diasNoMes = new Date(ano, mes + 1, 0).getDate();
  const offset = (primeiroDia.getDay() + 6) % 7; // semana começa à Segunda
  const diasSemana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"];

  let celulas = "";
  for(let i = 0; i < offset; i++) celulas += `<div></div>`;
  for(let dia = 1; dia <= diasNoMes; dia++){
    const iso = `${ano}-${_pad2(mes+1)}-${_pad2(dia)}`;
    const menusDia = menusPorData[iso] || [];
    const temMenus = menusDia.length > 0;
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaMenuSelecionado;
    const badges = menusDia.map(m => _badgeMenu(m.tipo)).join("");

    const fundo = isSel ? "#fff3cd" : (temMenus ? "#ffffff" : "transparent");
    const borda = isSel ? "2px solid #ffc107"
                 : temMenus ? "1px solid #c8e6c9"
                 : "1px solid transparent";

    celulas += `
      <div onclick="${temMenus ? `selecionarDiaMenu('${iso}')` : ''}"
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
  if(_diaMenuSelecionado){
    detalhe = `
      <div style="margin-top:16px;">
        <h3 style="color:#333;margin-bottom:10px;font-size:15px;">📅 ${formatarData(_diaMenuSelecionado)}</h3>
        ${_cartoesReservaDia(_diaMenuSelecionado)}
      </div>
    `;
  } else {
    detalhe = `<p style="text-align:center;color:#999;font-size:13px;margin-top:14px;">Toca num dia marcado para ver as refeições disponíveis.</p>`;
  }

  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
      <button onclick="mudarMesMenu(-1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">‹</button>
      <b style="font-size:16px;">${_NOMES_MESES[mes]} ${ano}</b>
      <button onclick="mudarMesMenu(1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">›</button>
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

// ---------------------------------------------------------------
// REGRAS DE HORÁRIO PARA RESERVAR (centralizadas)
//   Pequeno-almoço: nunca para hoje/passado; para dias futuros até
//                   às 23:00 do dia anterior (logo, amanhã = 23:00 de hoje).
//   Jantar:         hoje até às 9:00; amanhã até às 9:00 de hoje;
//                   dias seguintes até às 9:00 do dia anterior.
//   Almoço:         reservado automaticamente pela cantina.
// Devolve { pode, mensagem }.
function _regraReserva(tipo, iso){
  const agora = new Date();
  const hoje = agora.toISOString().split("T")[0];

  if(iso < hoje){
    return { pode:false, mensagem:" ⏰ (Data já passou)" };
  }

  const diaMeal = new Date(iso + "T00:00:00");
  const hojeD   = new Date(hoje + "T00:00:00");

  if(tipo === "pequeno_almoco"){
    // limite: 23:00 do dia anterior à refeição
    const limite = new Date(diaMeal);
    limite.setDate(limite.getDate() - 1);
    limite.setHours(23, 0, 0, 0);
    if(iso === hoje) return { pode:false, mensagem:" ⏰ (Só é possível reservar a partir do dia seguinte)" };
    return { pode: agora < limite, mensagem: agora < limite ? "" : " ⏰ (Prazo ultrapassado - até às 23:00 do dia anterior)" };
  }

  if(tipo === "jantar"){
    // limite: 9:00 do dia anterior, mas nunca antes de hoje 9:00
    const anterior = new Date(diaMeal);
    anterior.setDate(anterior.getDate() - 1);
    const base = anterior < hojeD ? hojeD : anterior;
    base.setHours(9, 0, 0, 0);
    return { pode: agora < base, mensagem: agora < base ? "" : " ⏰ (Prazo ultrapassado - até às 9:00)" };
  }

  // almoço (automático) ou outros
  return { pode:true, mensagem:"" };
}

// Cartões de reserva das refeições de um dia
function _cartoesReservaDia(iso){
  const menusDia = _menusAluno.filter(m => m.data === iso);
  if(!menusDia.length) return `<i>Sem menus neste dia.</i>`;

  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  menusDia.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));

  return menusDia.map(m => {
    // Almoço é reservado automaticamente quando o menu é criado
    if(m.tipo === "almoco"){
      return `
        <div class="menu">
          🍽️ <b>Almoço</b> — ${m.prato} (${formatCurrency(m.preco)})
          <br><span style="color:#2e7d32;font-size:13px;">✅ Reservado automaticamente</span>
        </div>
      `;
    }

    if(_reservasAtivasMenu[m.id]){
      return `
        <div class="menu">
          ${emojiTipo(m.tipo)} <b>${formatarTipoRefeicao(m.tipo)}</b>
          ${m.prato ? "— " + m.prato : ""} (${formatCurrency(m.preco)})
          <br><span style="color:#2e7d32;font-size:13px;">✅ Já reservado</span>
        </div>
      `;
    }

    const regra = _regraReserva(m.tipo, iso);
    const podeReservar = regra.pode;
    const mensagemHorario = regra.mensagem;

    return `
      <div class="menu">
        ${emojiTipo(m.tipo)} <b>${formatarTipoRefeicao(m.tipo)}</b>
        ${m.prato ? "— " + m.prato : ""} (${formatCurrency(m.preco)})${mensagemHorario}
        <br>
        ${podeReservar ? `
          <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', false, '${m.tipo}')">
            Reservar
          </button>
        ` : `
          <button style="opacity:0.5; cursor:not-allowed;" disabled>❌ Prazo expirado</button>
        `}
      </div>
    `;
  }).join("");
}

/* ==============================
   ALUNO — RESERVAR MENU
============================== */

async function reservarAluno(menuId, preco, data, is_dieta, tipo) {
  try {
    // Verificar regra de horário para fazer reserva (mesma lógica da UI)
    const regra = _regraReserva(tipo, data);
    if (!regra.pode) {
      const nomesTipo = {
        "pequeno_almoco": "Pequeno-almoço",
        "almoco": "Almoço",
        "jantar": "Jantar"
      };
      const nomeTipo = nomesTipo[tipo] || tipo;
      mostrarErro(
        "Fora do Prazo",
        `Já não é possível reservar ${nomeTipo} para esta data.`
      );
      return;
    }

    const aluno = await getAlunoAtual();

    const temDivida = await alunoTemDivida(aluno.id);

    if (temDivida) {
      const continuar = await showModal({
        icon: "💳",
        title: "Pagamentos em Atraso",
        message: "Tens pagamentos em atraso. Pretendes continuar com a reserva mesmo assim?",
        type: "warning",
        buttons: [
          { text: "Cancelar", type: "secondary", resolve: false },
          { text: "Continuar", type: "danger", resolve: true }
        ]
      });

      if (!continuar) {
        return; // sai sem mostrar loading
      }
    }

    //showLoading("⏳ Processando reserva...");

    const { error } = await supabaseClient
      .from("reservas")
      .insert({
        aluno_id: aluno.id,
        menu_id: menuId,
        data,
        preco,
        tipo,
        is_dieta,
        cancelamento_tipo: null
      });

    if (error) {
      handleError(error, "Erro ao criar reserva");
      return;
    }

    await mostrarSucesso("Reserva Confirmada", "Reserva efetuada com sucesso!");

    showAlunoMenu();
    showAlunoReservas();
    saldo();

  } catch (err) {
    handleError(err, "Erro inesperado ao fazer reserva");
  } finally {
    hideLoading();
  }
}

/* ==============================
   ALUNO — MINHAS RESERVAS
============================== */

async function showAlunoReservas(){
  show("alunoReservas");
  addBack("alunoReservas");

  showLoading("⏳ Carregando reservas...");

  try {
    const aluno = await getAlunoAtual();

    const { data: reservas, error } = await supabaseClient
      .from("reservas")
      .select(`
        id,
        data,
        tipo,
        preco,
        cancelamento_tipo,
        is_dieta,
        menus!inner(prato)
      `)
      .eq("aluno_id", aluno.id)
      .order("data", { ascending: true });

    if(error){
      handleError(error, "Erro ao carregar reservas");
      return;
    }

    _reservasAluno = reservas || [];

    if(!_mesReservasView){
      const h = new Date();
      _mesReservasView = new Date(h.getFullYear(), h.getMonth(), 1);
    }

    renderMinhasReservas();
  } catch (err) {
    handleError(err, "Erro ao processar reservas");
    const c = document.getElementById("minhasReservas");
    if(c) c.innerHTML = "<i>❌ Erro ao carregar dados.</i>";
  } finally {
    hideLoading();
  }
}

/* Estado do calendário de reservas do aluno */
let _reservasAluno = [];
let _mesReservasView = null;      // primeiro dia do mês em visualização
let _diaReservaSelecionado = null; // data ISO do dia selecionado

const _NOMES_MESES = [
  "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
  "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
];

function _pad2(n){ return String(n).padStart(2,"0"); }

// Só contam como "reservado" as reservas ativas (não canceladas / reativadas)
function _reservaAtiva(r){
  return r.cancelamento_tipo === null || r.cancelamento_tipo === "reactivated";
}

// Etiqueta bonita de cada refeição: P.A / A / J (com 🥗 se dieta)
function _badgeRefeicao(r){
  const map = {
    pequeno_almoco: { txt: "P.A", bg: "#e3f2fd", cor: "#1565c0" },
    almoco:         { txt: r.is_dieta ? "A 🥗" : "A", bg: "#e8f5e9", cor: "#2e7d32" },
    jantar:         { txt: "J", bg: "#f3e5f5", cor: "#6a1b9a" }
  };
  const m = map[r.tipo] || { txt: "?", bg: "#eee", cor: "#333" };
  return `<span style="display:inline-block;font-size:10px;font-weight:800;line-height:1;padding:2px 5px;border-radius:6px;background:${m.bg};color:${m.cor};margin:1px;">${m.txt}</span>`;
}

function mudarMesReservas(delta){
  if(!_mesReservasView) _mesReservasView = new Date();
  _mesReservasView = new Date(_mesReservasView.getFullYear(), _mesReservasView.getMonth() + delta, 1);
  _diaReservaSelecionado = null;
  renderMinhasReservas();
}

function selecionarDiaReserva(iso){
  _diaReservaSelecionado = (_diaReservaSelecionado === iso) ? null : iso;
  renderMinhasReservas();
}

function renderMinhasReservas(){
  const container = document.getElementById("minhasReservas");
  if(!container) return;

  const ano = _mesReservasView.getFullYear();
  const mes = _mesReservasView.getMonth();

  // Agrupar refeições ativas por dia
  const ativasPorData = {};
  _reservasAluno.forEach(r => {
    if(!_reservaAtiva(r)) return;
    (ativasPorData[r.data] = ativasPorData[r.data] || []).push(r);
  });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(ativasPorData).forEach(arr =>
    arr.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9))
  );

  const hojeISO = new Date().toISOString().split("T")[0];
  const primeiroDia = new Date(ano, mes, 1);
  const diasNoMes = new Date(ano, mes + 1, 0).getDate();
  const offset = (primeiroDia.getDay() + 6) % 7; // semana começa à Segunda

  const diasSemana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"];

  let celulas = "";
  for(let i = 0; i < offset; i++){
    celulas += `<div></div>`;
  }
  for(let dia = 1; dia <= diasNoMes; dia++){
    const iso = `${ano}-${_pad2(mes+1)}-${_pad2(dia)}`;
    const refeicoes = ativasPorData[iso] || [];
    const temReservas = refeicoes.length > 0;
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaReservaSelecionado;

    const badges = refeicoes.map(_badgeRefeicao).join("");

    const fundo = isSel ? "#fff3cd" : (temReservas ? "#ffffff" : "transparent");
    const borda = isSel ? "2px solid #ffc107"
                 : temReservas ? "1px solid #c8e6c9"
                 : "1px solid transparent";

    celulas += `
      <div onclick="${temReservas ? `selecionarDiaReserva('${iso}')` : ''}"
        style="min-height:56px;padding:4px;border-radius:8px;background:${fundo};border:${borda};
               ${temReservas ? 'cursor:pointer;box-shadow:0 1px 2px rgba(0,0,0,0.06);' : ''}
               display:flex;flex-direction:column;align-items:center;gap:2px;">
        <span style="font-size:12px;font-weight:700;color:${isHoje ? '#d32f2f' : '#333'};
              ${isHoje ? 'background:#ffe0e0;border-radius:50%;width:20px;height:20px;display:flex;align-items:center;justify-content:center;' : ''}">${dia}</span>
        <div style="display:flex;flex-wrap:wrap;justify-content:center;">${badges}</div>
      </div>
    `;
  }

  let detalhe = "";
  if(_diaReservaSelecionado){
    const ctx = _contextoReservas();
    const doDia = _reservasAluno
      .filter(r => r.data === _diaReservaSelecionado)
      .sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));
    detalhe = `
      <div style="margin-top:16px;">
        <h3 style="color:#333;margin-bottom:10px;font-size:15px;">📅 ${formatarData(_diaReservaSelecionado)}</h3>
        ${doDia.map(r => _cartaoReserva(r, ctx)).join("")}
      </div>
    `;
  } else {
    detalhe = `<p style="text-align:center;color:#999;font-size:13px;margin-top:14px;">Toca num dia marcado para ver e gerir as reservas.</p>`;
  }

  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;">
      <button onclick="mudarMesReservas(-1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">‹</button>
      <b style="font-size:16px;">${_NOMES_MESES[mes]} ${ano}</b>
      <button onclick="mudarMesReservas(1)" style="border:none;background:#f0f0f0;border-radius:8px;width:36px;height:36px;font-size:18px;cursor:pointer;">›</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;margin-bottom:6px;">
      ${diasSemana.map(d => `<div style="font-size:11px;font-weight:700;color:#888;">${d}</div>`).join("")}
    </div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">
      ${celulas}
    </div>
    <div style="display:flex;gap:12px;flex-wrap:wrap;justify-content:center;margin-top:12px;font-size:11px;color:#666;">
      <span>${_badgeRefeicao({tipo:'pequeno_almoco'})} Pequeno Almoço</span>
      <span>${_badgeRefeicao({tipo:'almoco'})} Almoço</span>
      <span>${_badgeRefeicao({tipo:'jantar'})} Jantar</span>
    </div>
    ${detalhe}
  `;
}

// Contexto necessário para decidir se uma reserva pode ser cancelada/dieta
function _contextoReservas(){
  const agora = new Date();
  const hoje = agora.toISOString().split("T")[0];
  const hora = agora.getHours();

  const cancelamentosUsuarioMesAlmoco = {};
  _reservasAluno.forEach(r => {
    if(r.tipo === "almoco" && r.cancelamento_tipo === "user"){
      const d = new Date(r.data);
      const key = `${d.getFullYear()}-${d.getMonth()+1}`;
      cancelamentosUsuarioMesAlmoco[key] = (cancelamentosUsuarioMesAlmoco[key] || 0) + 1;
    }
  });

  const reservasPorMenu = {};
  _reservasAluno.forEach(r => {
    if(!reservasPorMenu[r.data]) reservasPorMenu[r.data] = {};
    reservasPorMenu[r.data][r.tipo] = reservasPorMenu[r.data][r.tipo] || [];
    reservasPorMenu[r.data][r.tipo].push(r);
  });

  return { hoje, hora, cancelamentosUsuarioMesAlmoco, reservasPorMenu };
}

// Cartão individual de uma reserva (com ações: cancelar / dieta / reativar)
function _cartaoReserva(r, ctx){
  const { hoje, hora, cancelamentosUsuarioMesAlmoco, reservasPorMenu } = ctx;
  const d = new Date(r.data);
  const keyMes = `${d.getFullYear()}-${d.getMonth()+1}`;

  const estaAtiva = r.cancelamento_tipo === null || r.cancelamento_tipo === "reactivated";
  let podeCancelar = false;
  let podeDieta = false;

  if(estaAtiva){
    if(r.tipo === "pequeno_almoco"){
      // ontem: não; hoje: até 9:00; amanhã e futuro: sim
      if(r.data > hoje || (r.data === hoje && hora < 9)) podeCancelar = true;
    }
    if(r.tipo === "almoco"){
      if(r.data > hoje || (r.data === hoje && hora < 9)){
        const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
        const reservasDia = (reservasPorMenu[r.data] && reservasPorMenu[r.data][r.tipo]) || [];
        const jaCancelou = reservasDia.filter(x=>x.cancelamento_tipo === "user").length;
        if(jaCancelou < 1 && cancelamentosAtuais < 2) podeCancelar = true;
        podeDieta = true;
      }
    }
    if(r.tipo === "jantar"){
      // ontem: não; hoje: até 9:00; amanhã e futuro: sim
      if(r.data > hoje || (r.data === hoje && hora < 9)) podeCancelar = true;
    }
  }

  const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
  const mostrarAvisoLimite = r.tipo === "almoco" && !podeCancelar && estaAtiva && cancelamentosAtuais >= 2;

  let statusBg = "#f8f9fa", statusBorda = "#007bff", statusTexto = "✅ Ativa", statusCor = "#28a745";
  if(r.cancelamento_tipo === "user"){
    statusBg = "#f8d7da"; statusBorda = "#dc3545"; statusTexto = "❌ Cancelada por si"; statusCor = "#dc3545";
  } else if(r.cancelamento_tipo === "payment"){
    statusBg = "#e7d4f5"; statusBorda = "#6f42c1"; statusTexto = "💳 Paga (liquidação do mês)"; statusCor = "#6f42c1";
  } else if(r.cancelamento_tipo === "reactivated"){
    statusBg = "#d1ecf1"; statusBorda = "#0c5460"; statusTexto = "🔄 Reativada"; statusCor = "#0c5460";
  }

  return `
    <div style="background:${statusBg}; padding:12px; margin-bottom:10px; border-radius:6px; border-left:4px solid ${statusBorda};">
      <div style="display:flex; justify-content:space-between; align-items:start; gap:12px;">
        <div style="flex:1;">
          <div style="display:flex; align-items:center; gap:8px; margin-bottom:4px;">
            <span style="font-size:20px;">${emojiTipo(r.tipo, r.is_dieta)}</span>
            <span style="font-weight:bold; color:#333;">${r.tipo === "almoco" && r.is_dieta ? "Almoço (Dieta)" : formatarTipoRefeicao(r.tipo)}</span>
          </div>
          <div style="color:#666; font-size:13px; margin-left:28px;">
            ${r.menus?.prato ? `${r.menus.prato}` : "-"}
            <span style="float:right; color:#007bff; font-weight:bold;">${formatCurrency(r.preco).replace("€", "")}€</span>
          </div>
          <div style="color:${statusCor}; font-size:12px; margin-top:4px; margin-left:28px;">${statusTexto}</div>
        </div>
        ${podeDieta && !r.is_dieta ? `
          <button onclick="trocarParaDieta('${r.id}')" style="padding:6px 10px; font-size:12px; background:#fff3cd; border:1px solid #ffc107; border-radius:4px; cursor:pointer;">
            🥗 Dieta
          </button>
        ` : ""}
      </div>
      ${podeCancelar ? `
        <button onclick="cancelarReserva('${r.id}', '${keyMes}')" style="margin-top:8px; width:100%; padding:8px; background:#dc3545; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
          Cancelar Reserva
        </button>
      ` : ""}
      ${r.cancelamento_tipo === "user" && r.data > hoje ? `
        <button onclick="reativarReserva('${r.id}')" style="margin-top:8px; width:100%; padding:8px; background:#28a745; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
          🔄 Reativar (marcar como ativa novamente)
        </button>
      ` : ""}
      ${mostrarAvisoLimite ? `
        <div style="margin-top:8px; padding:8px; background-color:#fff3cd; border:1px solid #ffc107; border-radius:4px; color:#856404; font-size:13px;">
          ⚠️ Para conseguires cancelar liga à cantina - 914117705
        </div>
      ` : ""}
    </div>
  `;
}

/* =============================
   ALUNO — AÇÕES EM RESERVAS
============================== */

async function cancelarReserva(reservaId, keyMes) {
  if (!await confirmar("Cancelar Reserva", "Tem certeza que deseja cancelar esta reserva?")) {
    return;
  }

  showLoading("⏳ Cancelando reserva...");

  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ cancelamento_tipo: 'user' })
      .eq("id", reservaId);

    if (error) {
      hideLoading();
      const mensagemErro = error?.message || "Erro ao cancelar reserva";
      await mostrarErro("Erro ao Cancelar Reserva", mensagemErro);
      return;
    }

    mostrarSucesso("Reserva Cancelada", "Reserva cancelada com sucesso!");
    showAlunoReservas();
    saldo();
  } catch (error) {
    hideLoading();
    const mensagemErro = error?.message || "Erro inesperado ao cancelar reserva";
    await mostrarErro("Erro", mensagemErro);
  } finally {
    hideLoading();
  }
}

async function trocarParaDieta(reservaId) {
  if (!await confirmar(
    "Alterar para Dieta",
    "Depois de escolher dieta não poderá voltar a alterar. Deseja continuar?"
  )) {
    return;
  }


  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ is_dieta: true })
      .eq("id", reservaId);

    if (error) {
      await mostrarErro("Erro ao Atualizar", error.message);
      return;
    }

    await mostrarSucesso(
      "Refeição Alterada",
      "Almoço alterado para dieta com sucesso!"
    );

    showAlunoReservas();
    saldo();

  } catch (error) {
    await mostrarErro("Erro", error.message || "Erro inesperado");
  } finally {
    hideLoading();
  }
}

function mostrarLimiteCancelamentos() {
  mostrarErro(
    "Limite de Cancelamentos",
    "Já atingiste o limite de 2 cancelamentos de almoço neste mês. Para situações excecionais, fala com a cantina (914117705)."
  );
}

/* =============================
   ALUNO — REATIVAR RESERVA
============================== */

async function reativarReserva(reservaId) {
  if (!await confirmar("Reativar Reserva", "Deseja reativar esta reserva? Este cancelamento não contará para seu limite de cancelamentos.")) {
    return;
  }

  showLoading("⏳ Reativando reserva...");

  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ cancelamento_tipo: 'reactivated' })
      .eq("id", reservaId);

    if (error) {
      hideLoading();
      const mensagemErro = error?.message || "Erro ao reativar reserva";
      await mostrarErro("Erro ao Reativar Reserva", mensagemErro);
      return;
    }

    mostrarSucesso("Reserva Reativada", "Reserva reativada com sucesso! Este cancelamento não contará para seu limite.");
    showAlunoReservas();
    saldo();
  } catch (error) {
    hideLoading();
    const mensagemErro = error?.message || "Erro inesperado ao reativar reserva";
    await mostrarErro("Erro", mensagemErro);
  } finally {
    hideLoading();
  }
}

/* =============================
   ALUNO — NOTIFICAÇÕES
============================= */

let contadorNotificacoesNaoLidas = 0;

/* Notificações mostradas diretamente na página inicial do aluno.
   Mostra apenas as notificações que ainda NÃO aconteceram, ou seja,
   cuja data do menu (dados.data) é hoje ou no futuro. Quando o dia
   passa, a notificação deixa de aparecer automaticamente. */
async function carregarNotificacoesInline() {
  const container = document.getElementById("notificacoesInline");
  if (!container) return;

  try {
    const aluno = await getAlunoAtual();

    const { data: notificacoes, error } = await supabaseClient
      .from("notificacoes")
      .select("*")
      .eq("aluno_id", aluno.id)
      .eq("lida", false)
      .order("criada_em", { ascending: false });

    if (error) {
      console.warn("Erro ao carregar notificações:", error);
      container.innerHTML = "";
      return;
    }

    const hoje = new Date().toISOString().split("T")[0];

    // Manter apenas as que ainda não aconteceram (data do menu >= hoje).
    // Notificações sem data associada são sempre mostradas.
    const ativas = (notificacoes || []).filter(n => {
      const dataMenu = n.dados && n.dados.data ? String(n.dados.data).split("T")[0] : null;
      if (!dataMenu) return true;
      return dataMenu >= hoje;
    });

    if (ativas.length === 0) {
      container.innerHTML = "";
      return;
    }

    container.innerHTML = ativas.map(notif => {
      const icone = notif.tipo === "menu_alterado" ? "🍽️" : "🔔";
      return `
        <div style="padding:12px;margin-bottom:8px;border-left:4px solid #ff9800;background:#fffbf0;border-radius:6px;text-align:left;">
          <div style="display:flex;justify-content:space-between;align-items:start;gap:8px;">
            <div style="flex:1;">
              <p style="margin:0 0 4px 0;font-weight:600;font-size:14px;">${icone} ${notif.titulo}</p>
              <p style="margin:0;font-size:13px;color:#666;">${notif.mensagem}</p>
            </div>
            <button class="btn-small" onclick="marcarNotificacaoInlineLida('${notif.id}')" style="font-size:11px;padding:4px 8px;white-space:nowrap;">✓ Ler</button>
          </div>
        </div>
      `;
    }).join("");
  } catch (err) {
    console.warn("Erro ao carregar notificações:", err);
    container.innerHTML = "";
  }
}

async function marcarNotificacaoInlineLida(notificacaoId) {
  try {
    await supabaseClient.rpc("marcar_notificacao_lida", { p_notificacao_id: notificacaoId });
  } catch (err) {
    console.warn("Erro ao marcar notificação como lida:", err);
  }
  carregarNotificacoesInline();
}

async function carregarNotificacoes() {
  try {
    const aluno = await getAlunoAtual();
    
    const { data: notificacoes, error } = await supabaseClient
      .from("notificacoes")
      .select("*")
      .eq("aluno_id", aluno.id)
      .eq("lida", false)
      .order("criada_em", { ascending: false });
    
    if (error) {
      console.warn("Erro ao carregar notificações:", error);
      return 0;
    }
    
    contadorNotificacoesNaoLidas = notificacoes?.length || 0;
    atualizarBadgeNotificacoes();
    
    return contadorNotificacoesNaoLidas;
  } catch (err) {
    console.warn("Erro ao carregar notificações:", err);
    return 0;
  }
}

function atualizarBadgeNotificacoes() {
  const badge = document.getElementById("notificacoesBadge");
  if (badge) {
    if (contadorNotificacoesNaoLidas > 0) {
      badge.textContent = contadorNotificacoesNaoLidas;
      badge.classList.remove("hidden");
    } else {
      badge.classList.add("hidden");
    }
  }
}

async function showNotificacoes() {
  show("notificacoesAluno");
  addBack("notificacoesAluno");
  
  showLoading("⏳ Carregando notificações...");
  
  try {
    const aluno = await getAlunoAtual();
    
    const { data: notificacoes, error } = await supabaseClient
      .from("notificacoes")
      .select("*")
      .eq("aluno_id", aluno.id)
      .order("criada_em", { ascending: false })
      .limit(50);
    
    if (error) {
      handleError(error, "Erro ao carregar notificações");
      return;
    }
    
    const container = document.getElementById("listaNotificacoes");
    
    if (!notificacoes || notificacoes.length === 0) {
      container.innerHTML = '<p style="text-align:center;color:#888;">Nenhuma notificação</p>';
      hideLoading();
      return;
    }
    
    let html = '';
    
    notificacoes.forEach(notif => {
      const dataFormatada = new Date(notif.criada_em).toLocaleDateString('pt-PT', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
      
      const classe = notif.lida ? 'notificacao-lida' : 'notificacao-nao-lida';
      const icone = notif.tipo === 'menu_alterado' ? '🍽️' : '🔔';
      
      html += `
        <div class="card ${classe}" style="padding:12px;margin-bottom:8px;border-left:4px solid ${notif.lida ? '#ddd' : '#ff9800'};background:${notif.lida ? '#f9f9f9' : '#fffbf0'};">
          <div style="display:flex;justify-content:space-between;align-items:start;gap:8px;">
            <div style="flex:1;">
              <p style="margin:0 0 4px 0;font-weight:600;font-size:14px;">${icone} ${notif.titulo}</p>
              <p style="margin:0 0 6px 0;font-size:13px;color:#666;">${notif.mensagem}</p>
              <p style="margin:0;font-size:11px;color:#999;">${dataFormatada}</p>
            </div>
            ${!notif.lida ? `<button class="btn-small" onclick="marcarNotificacaoLida('${notif.id}')" style="font-size:11px;padding:4px 8px;white-space:nowrap;">✓ Ler</button>` : ''}
          </div>
        </div>
      `;
    });
    
    container.innerHTML = html;
  } catch (err) {
    handleError(err, "Erro ao carregar notificações");
  } finally {
    hideLoading();
  }
}

async function marcarNotificacaoLida(notificacaoId) {
  try {
    const { error } = await supabaseClient
      .rpc('marcar_notificacao_lida', {
        p_notificacao_id: notificacaoId
      });
    
    if (!error) {
      contadorNotificacoesNaoLidas = Math.max(0, contadorNotificacoesNaoLidas - 1);
      atualizarBadgeNotificacoes();
      showNotificacoes(); // Recarregar lista
    }
  } catch (err) {
    console.warn("Erro ao marcar notificação como lida:", err);
  }
}

async function marcarTodasNotificacoesLidas() {
  try {
    const aluno = await getAlunoAtual();
    
    const { error } = await supabaseClient
      .rpc('marcar_todas_notificacoes_lidas', {
        p_aluno_id: aluno.id
      });
    
    if (!error) {
      contadorNotificacoesNaoLidas = 0;
      atualizarBadgeNotificacoes();
      showNotificacoes();
    }
  } catch (err) {
    console.warn("Erro ao marcar notificações como lidas:", err);
  }
}


