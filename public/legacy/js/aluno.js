// Funções da área do aluno (menus, reservas e ações sobre reservas)

/* ==============================
   ALUNO — MENU POR DATA E RESERVAS
============================== */
/* formatarData vive agora no app.js, com o escapeHtml. */

/* Estado do calendário de reservar refeição */
let _menusAluno = [];              // menus disponíveis (>= hoje)
let _reservasAtivasMenu = {};      // menu_id -> true (já reservado pelo aluno)
let _reservasCanceladasMenu = {};  // menu_id -> true (cancelado por si; permite "Voltar a Reservar")
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
      .select("menu_id, ativa, cancelamento_tipo")
      .eq("aluno_id", aluno.id);

    // Ativas → "Já reservado". Canceladas por si → botão "Voltar a Reservar",
    // para o aluno reconhecer que está a desfazer um cancelamento, não a marcar
    // uma refeição nova. As duas coisas passam pela mesma RPC reservar_refeicao.
    _reservasAtivasMenu = {};
    _reservasCanceladasMenu = {};
    reservas?.forEach(r => {
      if(r.ativa) _reservasAtivasMenu[r.menu_id] = true;
      else if(r.cancelamento_tipo === "user") _reservasCanceladasMenu[r.menu_id] = true;
    });

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
// PRAZO LIMITE DE UMA REFEIÇÃO (fonte única para reservar/cancelar/dieta)
//   Pequeno-almoço: 23:00 do dia anterior.
//   Almoço/Jantar:  9:00 do próprio dia da refeição.
// Devolve um Date. Usar sempre isto — nunca comparar horas à mão — para
// que reserva, cancelamento e troca de dieta não divirjam.
function _prazoLimite(tipo, iso){
  const dia = new Date(iso + "T00:00:00");
  if(tipo === "pequeno_almoco"){
    const limite = new Date(dia);
    limite.setDate(limite.getDate() - 1);
    limite.setHours(23, 0, 0, 0);
    return limite;
  }
  const limite = new Date(dia);
  limite.setHours(9, 0, 0, 0);
  return limite;
}

// ---------------------------------------------------------------
// REGRAS DE HORÁRIO PARA RESERVAR (centralizadas)
//   Pequeno-almoço: até às 23:00 do dia anterior (logo, nunca para hoje).
//   Almoço/Jantar:  até às 9:00 do próprio dia da refeição.
// O almoço é criado automaticamente pela cantina, mas quando foi cancelado
// volta a ser reservável — e só até ao mesmo prazo em que podia ser cancelado.
// Sem isto, um aluno cancelava o almoço de manhã e voltava a reservá-lo à tarde,
// depois de a cantina já ter contado as refeições.
// Devolve { pode, mensagem }.
function _regraReserva(tipo, iso){
  const agora = new Date();
  const hoje = agora.toISOString().split("T")[0];

  if(iso < hoje){
    return { pode:false, mensagem:" ⏰ (Data já passou)" };
  }

  // O prazo do pequeno-almoço para hoje já passou por definição (23:00 de ontem),
  // mas a mensagem genérica confundiria — o aluno nunca poderia reservar hoje.
  if(tipo === "pequeno_almoco" && iso === hoje){
    return { pode:false, mensagem:" ⏰ (Só é possível reservar a partir do dia seguinte)" };
  }

  const pode = agora < _prazoLimite(tipo, iso);
  const mensagem = tipo === "pequeno_almoco"
    ? " ⏰ (Prazo ultrapassado - até às 23:00 do dia anterior)"
    : " ⏰ (Prazo ultrapassado - até às 9:00 do próprio dia)";
  return { pode, mensagem: pode ? "" : mensagem };
}

// Cartões de reserva das refeições de um dia
function _cartoesReservaDia(iso){
  const menusDia = _menusAluno.filter(m => m.data === iso);
  if(!menusDia.length) return `<i>Sem menus neste dia.</i>`;

  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  menusDia.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));

  return menusDia.map(m => {
    // O almoço passa pela mesma lógica que as outras refeições: é criado
    // automaticamente pela cantina, mas pode ter sido cancelado, e nesse caso
    // esta página tem de o mostrar como reservável — não afirmar que está reservado.
    if(_reservasAtivasMenu[m.id]){
      return `
        <div class="menu">
          ${emojiTipo(m.tipo)} <b>${formatarTipoRefeicao(m.tipo)}</b>
          ${m.prato ? "— " + escapeHtml(m.prato) : ""} (${formatCurrency(m.preco)})
          <br><span style="color:#2e7d32;font-size:13px;">✅ Já reservado</span>
          ${m.tipo === "almoco" ? `
            <br><span style="color:#666;font-size:12px;">O almoço é reservado automaticamente pela cantina.</span>
          ` : ""}
        </div>
      `;
    }

    const regra = _regraReserva(m.tipo, iso);
    const podeReservar = regra.pode;
    const mensagemHorario = regra.mensagem;
    const foiCancelada = _reservasCanceladasMenu[m.id];
    const rotuloBotao = foiCancelada ? "Voltar a Reservar" : "Reservar";

    return `
      <div class="menu">
        ${emojiTipo(m.tipo)} <b>${formatarTipoRefeicao(m.tipo)}</b>
        ${m.prato ? "— " + escapeHtml(m.prato) : ""} (${formatCurrency(m.preco)})${mensagemHorario}
        <br>
        ${podeReservar ? `
          <button onclick="reservarAluno('${m.id}', '${m.data}', '${m.tipo}')">
            ${rotuloBotao}
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

async function reservarAluno(menuId, data, tipo) {
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

    // O preço, o tipo e a data vêm do menu, dentro da função. Se já existir uma
    // reserva cancelada para este aluno/dia/refeição, é reativada em vez de se
    // criar uma segunda (era isto que permitia dois pequenos-almoços no mesmo dia).
    const { error } = await supabaseClient
      .rpc("reservar_refeicao", { p_menu_id: menuId });

    if (error) {
      if (error.code === "RES01") {
        // Já existe reserva ativa: o ecrã estava dessincronizado. Recarregar em vez
        // de insistir — o botão não devia estar visível.
        await mostrarErro(
          "Reserva já existente",
          "Já tens esta refeição reservada para este dia. A lista foi atualizada."
        );
      } else if (error.code === "RES02") {
        await mostrarErro(
          "Refeição já liquidada",
          "Esta refeição já foi paga e não pode ser reservada de novo. Fala com a cantina."
        );
      } else {
        handleError(error, "Erro ao criar reserva");
        return;
      }
      showAlunoMenu();
      showAlunoReservas();
      saldo();
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

    // Os pedidos de cancelamento especial do próprio aluno. A política
    // "Aluno vê os seus pedidos" (005 PASSO 2) já limita isto a ele, por isso
    // não há filtro nenhum a acrescentar do lado do cliente.
    const { data: pedidos, error: erroPedidos } = await supabaseClient
      .from("cancelamentos_especiais")
      .select("id, reserva_id, status, criado_em")
      .order("criado_em", { ascending: false });

    // Um erro aqui não pode derrubar o ecrã das reservas: sem pedidos, os
    // cartões voltam ao comportamento anterior a este cluster.
    _pedidosAluno = erroPedidos ? [] : (pedidos || []);

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
let _pedidosAluno = [];           // cancelamentos especiais do próprio aluno
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
  // Reserva cancelada: cinzento e riscado, para se distinguir de uma ativa.
  // Teste explícito (não !_reservaAtiva) para a legenda, cujos objetos não têm
  // cancelamento_tipo, não aparecer riscada.
  if(r && (r.cancelamento_tipo === "user" || r.cancelamento_tipo === "payment")){
    return `<span style="display:inline-block;font-size:10px;font-weight:800;line-height:1;padding:2px 5px;border-radius:6px;background:#f0f0f0;color:#999;text-decoration:line-through;margin:1px;">${m.txt}</span>`;
  }
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

  // Agrupar TODAS as reservas por dia — inclusive as canceladas, para que um dia
  // só com cancelamentos continue a ser selecionável e o aluno possa lá reativar.
  const reservasPorData = {};
  _reservasAluno.forEach(r => {
    (reservasPorData[r.data] = reservasPorData[r.data] || []).push(r);
  });
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  Object.values(reservasPorData).forEach(arr =>
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
    const refeicoes = reservasPorData[iso] || [];
    const temReservas = refeicoes.length > 0;
    const temAtivas = refeicoes.some(_reservaAtiva);
    const isHoje = iso === hojeISO;
    const isSel = iso === _diaReservaSelecionado;

    const badges = refeicoes.map(_badgeRefeicao).join("");

    // Dia só com cancelamentos: selecionável na mesma (para reativar), mas
    // apresentado como "gasto" — sem o realce verde de um dia com reservas ativas.
    const fundo = isSel ? "#fff3cd" : (temAtivas ? "#ffffff" : "transparent");
    const borda = isSel ? "2px solid #ffc107"
                 : temAtivas ? "1px solid #c8e6c9"
                 : temReservas ? "1px dashed #e0b3b3"
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

// Contexto necessário para decidir se uma reserva pode ser cancelada/dieta.
// Os prazos não vivem aqui — vêm de _prazoLimite(), avaliado por cartão.
function _contextoReservas(){
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

  const pedidosPorReserva = {};
  _pedidosAluno.forEach(p => {
    (pedidosPorReserva[p.reserva_id] = pedidosPorReserva[p.reserva_id] || []).push(p);
  });

  return { cancelamentosUsuarioMesAlmoco, reservasPorMenu, pedidosPorReserva };
}

// Cartão individual de uma reserva (com ações: cancelar / dieta / reativar)
function _cartaoReserva(r, ctx){
  const { cancelamentosUsuarioMesAlmoco, reservasPorMenu, pedidosPorReserva } = ctx;
  const d = new Date(r.data);
  const keyMes = `${d.getFullYear()}-${d.getMonth()+1}`;

  // Mesmo prazo que governa a reserva — pequeno-almoço 23:00 da véspera,
  // almoço/jantar 9:00 do próprio dia.
  const dentroPrazo = new Date() < _prazoLimite(r.tipo, r.data);

  const estaAtiva = r.cancelamento_tipo === null || r.cancelamento_tipo === "reactivated";
  let podeCancelar = false;
  let podeDieta = false;

  if(estaAtiva && dentroPrazo){
    if(r.tipo === "almoco"){
      const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
      const reservasDia = (reservasPorMenu[r.data] && reservasPorMenu[r.data][r.tipo]) || [];
      const jaCancelou = reservasDia.filter(x=>x.cancelamento_tipo === "user").length;
      if(jaCancelou < 1 && cancelamentosAtuais < 2) podeCancelar = true;
      podeDieta = true;
    } else {
      podeCancelar = true;
    }
  }

  const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
  const mostrarAvisoLimite = r.tipo === "almoco" && !podeCancelar && estaAtiva && cancelamentosAtuais >= 2;

  // Pendente ganha ao rejeitado: é o estado atual. 'aprovado' não mostra nada —
  // a própria reserva já mostra o resultado (cancelada, ou com o ícone de dieta).
  const pedidos = (pedidosPorReserva && pedidosPorReserva[r.id]) || [];
  const pedido = pedidos.find(p => p.status === "pendente")
              || pedidos.find(p => p.status === "rejeitado");

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
            ${r.menus?.prato ? escapeHtml(r.menus.prato) : "-"}
            <span style="float:right; color:#007bff; font-weight:bold;">${formatCurrency(r.preco).replace("€", "")}€</span>
          </div>
          <div style="color:${statusCor}; font-size:12px; margin-top:4px; margin-left:28px;">${statusTexto}</div>
        </div>
        ${podeDieta && !r.is_dieta ? `
          <button onclick="trocarDieta('${r.id}', true)" style="padding:6px 10px; font-size:12px; background:#fff3cd; color:#333; border:1px solid #ffc107; border-radius:4px; cursor:pointer;">
            🥗 Dieta
          </button>
        ` : ""}
        ${podeDieta && r.is_dieta ? `
          <button onclick="trocarDieta('${r.id}', false)" style="padding:6px 10px; font-size:12px; background:#e2e3e5; color:#333; border:1px solid #6c757d; border-radius:4px; cursor:pointer;">
            🍽️ Normal
          </button>
        ` : ""}
      </div>
      ${podeCancelar ? `
        <button onclick="cancelarReserva('${r.id}', '${keyMes}')" style="margin-top:8px; width:100%; padding:8px; background:#dc3545; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
          Cancelar Reserva
        </button>
      ` : ""}
      ${r.cancelamento_tipo === "user" && dentroPrazo ? `
        <button onclick="reativarReserva('${r.id}')" style="margin-top:8px; width:100%; padding:8px; background:#28a745; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
          🔄 Reativar (marcar como ativa novamente)
        </button>
      ` : ""}
      ${mostrarAvisoLimite ? `
        ${pedido ? `
          <div style="margin-top:8px; padding:8px; border-radius:4px; font-size:13px; font-weight:bold; ${
            pedido.status === "pendente"
              ? "background:#e2e3e5; border:1px solid #6c757d; color:#41464b;"
              : "background:#f8d7da; border:1px solid #dc3545; color:#842029;"
          }">
            ${pedido.status === "pendente" ? "⏳ Pedido pendente" : "❌ Pedido rejeitado"}
          </div>
        ` : `
          <button onclick="pedirCancelamentoEspecial('${r.id}')" style="margin-top:8px; width:100%; padding:8px; background:#0d6efd; color:white; border:none; border-radius:4px; cursor:pointer; font-weight:bold;">
            📩 Pedir cancelamento especial
          </button>
        `}
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

// Pedido de cancelamento especial. So aparece quando o limite mensal ja foi
// gasto - o prazo das 9:00 nao tem excecao nenhuma e nao chega aqui.
async function pedirCancelamentoEspecial(reservaId) {
  const r = await showModal({
    icon: "📩",
    type: "warning",
    title: "Pedir Cancelamento Especial",
    message: "Já usaste os 2 cancelamentos deste mês. Explica a situação e a cantina decide.",
    fields: [
      { id: "motivo",           type: "textarea", label: "Motivo", required: true },
      { id: "trocaPorLanche",   type: "checkbox", label: "Prefiro trocar por um lanche" },
      { id: "lancheSubstituto", type: "text",     label: "Qual lanche?", revealedBy: "trocaPorLanche" }
    ],
    buttons: [
      { text: "Voltar",        type: "secondary", resolve: false },
      { text: "Enviar pedido", type: "primary",   resolve: true  }
    ]
  });

  if (!r) return;   // null = Voltar ou clique fora. Falha fechada.

  showLoading("⏳ A enviar pedido...");

  try {
    const { error } = await supabaseClient.rpc("solicitar_cancelamento_especial", {
      p_reserva_id: reservaId,
      p_motivo: r.motivo,
      p_troca_por_lanche: !!r.trocaPorLanche,
      p_lanche_substituto: r.trocaPorLanche ? (r.lancheSubstituto || null) : null
    });

    hideLoading();

    if (error) {
      // "Já existe um pedido pendente" quer dizer ecrã desatualizado: recarregar,
      // não insistir. Mesma forma que o RES01 do Cluster 1.
      await mostrarErro("Erro ao Enviar Pedido", error.message || "Erro inesperado");
      showAlunoReservas();
      return;
    }

    await mostrarSucesso("Pedido Enviado", "A cantina vai analisar o teu pedido.");
    showAlunoReservas();
  } catch (err) {
    await mostrarErro("Erro", err?.message || "Erro inesperado ao enviar pedido");
  } finally {
    hideLoading();
  }
}

// Troca reversível nos dois sentidos, até ao prazo do almoço (9:00 do próprio dia).
async function trocarDieta(reservaId, paraDieta) {
  if (!await confirmar(
    "Alterar Almoço",
    paraDieta ? "Mudar para Dieta?" : "Voltar a Prato Normal?"
  )) {
    return;
  }

  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ is_dieta: paraDieta })
      .eq("id", reservaId);

    if (error) {
      await mostrarErro("Erro ao Atualizar", error.message);
      return;
    }

    await mostrarSucesso(
      "Almoço Alterado",
      paraDieta ? "Almoço alterado para dieta." : "Almoço alterado para prato normal."
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
    const { data, error } = await supabaseClient
      .rpc("reativar_reserva_cancelada", { p_reserva_id: reservaId });

    if (error) {
      hideLoading();
      const mensagemErro = error?.message || "Erro ao reativar reserva";
      await mostrarErro("Erro ao Reativar Reserva", mensagemErro);
      return;
    }

    // A função devolve (success, message) em vez de lançar erro.
    const resultado = data && data[0];
    if (!resultado || !resultado.success) {
      hideLoading();
      await mostrarErro(
        "Erro ao Reativar Reserva",
        resultado?.message || "Esta reserva não pode ser reativada."
      );
      showAlunoReservas();
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


