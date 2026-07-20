// Funções da área da cantina (menus, reservas, histórico, saldos, relatórios)

function formatarData(dataISO) {
  if (!dataISO) return "";
  const [ano, mes, dia] = dataISO.split("-");
  return `${dia}/${mes}/${ano}`;
}

// Função para enviar email de notificação via Edge Function
async function enviarEmailNotificacao(email, assunto, mensagem, nomeAluno) {
  try {
    const SUPABASE_URL = "https://fghsgknistganzbuxrjt.supabase.co";
    const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnaHNna25pc3RnYW56YnV4cmp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNDUzNjcsImV4cCI6MjA4MzgyMTM2N30.6NPsu-DeQuEpjnHptdZTgsYmtx7mQ5STs8zbwYgIoYY";
    
    const response = await fetch(`${SUPABASE_URL}/functions/v1/send-notification-email`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ANON_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email,
        subject: assunto,
        message: mensagem,
        studentName: nomeAluno
      })
    });

    if (!response.ok) {
      console.warn('⚠️ Erro ao enviar email:', await response.text());
      return false;
    }

    console.log('✅ Email enviado para:', email);
    return true;
  } catch (error) {
    console.warn('⚠️ Exceção ao enviar email:', error);
    return false;
  }
}

/* ==============================
   CANTINA — NAVEGAÇÃO BASE
============================== */

function showCantinaDashboard() {
  esconderTodasPaginas();

  const pagina = document.getElementById("cantinaDashboard");
  if (pagina) {
    pagina.classList.remove("hidden");
  }
}

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
  console.log("📝 Mostrando calendário de criar menu");
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
  console.log("📝 Adicionando menu...", { supabaseClient: !!supabaseClient });

  if (!supabaseClient) {
    mostrarMensagem("error", "❌ Erro: Conexão não pronta. Atualiza a página.");
    console.error("❌ supabaseClient não disponível");
    return;
  }

  let prato = (pratoEntrada || "").trim();
  console.log("📋 Valores do formulário:", { dataValue, tipo, prato });

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
      console.log("🌐 Enviando para Supabase...", { dataValue, tipo, prato, preco: configuracao[tipo].preco });
      
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

      // 🍽️ O almoço é reservado automaticamente para todos os alunos assim que criado
      if (tipo === "almoco" && data && data.length) {
        const menuCriado = data[0];
        const { data: alunos, error: erroAlunos } = await supabaseClient
          .from("alunos")
          .select("id");

        if (!erroAlunos && alunos && alunos.length) {
          // Evitar duplicados: verificar que alunos já têm reserva de almoço neste dia
          const { data: jaReservados } = await supabaseClient
            .from("reservas")
            .select("aluno_id")
            .eq("data", dataValue)
            .eq("tipo", "almoco");

          const idsComReserva = new Set((jaReservados || []).map(r => r.aluno_id));

          const reservasAuto = alunos
            .filter(a => !idsComReserva.has(a.id))
            .map(a => ({
              aluno_id: a.id,
              menu_id: menuCriado.id,
              data: dataValue,
              preco: menuCriado.preco,
              tipo: "almoco",
              is_dieta: false,
              cancelamento_tipo: null
            }));

          if (reservasAuto.length) {
            const { error: erroReservas } = await supabaseClient
              .from("reservas")
              .insert(reservasAuto);
            if (erroReservas) console.error("⚠️ Erro ao reservar almoço automaticamente", erroReservas);
          }
        }
      }

      mostrarSucesso("Menu Criado", "Menu criado com sucesso!");
      console.log("✅ Menu criado com sucesso", data);
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
function escapeHtml(text) {
  if (!text) return "";
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

let _mesMenusView = null;
let _diaMenusSelecionado = null;

async function showMenusCriados() {
  console.log("📋 Carregando menus criados...");
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
        ${prato ? `<div style="font-size:13px;color:#555;margin-bottom:8px;">${prato}</div>`
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

function renderMenusFiltrados() {
  const container = document.getElementById("listaMenus");
  if (!container) return;

  let menusFiltrados = window.todosOsMenus || [];

  if (!menusFiltrados.length) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="empty-state-icon">🔍</span>
        <p>Nenhum menu encontrado para a data selecionada</p>
      </div>`;
    return;
  }

  const hoje = new Date();
  const hojeStr = hoje.toISOString().split("T")[0];
  const horaAtual = hoje.getHours();

  // Renderizar lista simples sem agrupamento hierárquico
  const menusHtml = menusFiltrados.map(m => {
    const tipo = escapeHtml(m.tipo || "");
    const prato = escapeHtml(m.prato || "");
    const preco = Number(m.preco || 0).toFixed(2);
    const data = m.data;

    const dataObj = new Date(data);
    const dataFormatada = dataObj.toLocaleDateString('pt-PT', {
      day: 'numeric',
      month: 'long',
      year: 'numeric'
    });

    const dataMenu = new Date(data);
    let podeEditar = false;

    if (dataMenu > new Date(hojeStr)) podeEditar = true;
    if (data === hojeStr && horaAtual < 9) podeEditar = true;

    return `
      <div class="menu-item" style="margin-bottom:12px;padding:12px;background:#f9f9f9;border-radius:6px;display:flex;justify-content:space-between;align-items:center;">
        <div style="flex:1;">
          <div style="font-size:14px;color:#666;margin-bottom:4px;">${dataFormatada}</div>
          <div style="display:flex;align-items:center;gap:8px;">
            <span style="font-size:20px;">${tipoEmoji(tipo)}</span>
            <div>
              <b>${formatarTipoRefeicao(tipo)}</b>
              ${prato ? `<span style="color:#666;"> — ${prato}</span>` : ""}
            </div>
            <span style="color:#007bff;font-weight:bold;margin-left:auto;">${preco}€</span>
          </div>
        </div>
        <div style="display:flex;gap:6px;margin-left:12px;">
          ${
            podeEditar
              ? `
              <button class="btn-edit" onclick="startEdit('${m.id}')" style="padding:6px 10px;font-size:12px;">
                ✏️
              </button>
              <button class="btn-delete" onclick="apagarMenu('${m.id}')" style="padding:6px 10px;font-size:12px;">
                🗑️
              </button>
            `
              : `<span style="color:#999;font-size:12px;">Bloqueado</span>`
          }
        </div>
      </div>
    `;
  }).join("");

  container.innerHTML = `<div style="margin-top:12px;">${menusHtml}</div>`;
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
      console.log("🔔 Iniciando envio de notificações...");
      console.log("📋 Dados da notificação:", {
        menu_id: id,
        prato_antigo: pratosAntigo,
        prato_novo: novoPrato,
        data_menu: menuAntigo.data,
        tipo_menu: menuAntigo.tipo
      });

      const { data: notificacoes, error: erroNotif } = await supabaseClient
        .rpc('notificar_menu_alterado', {
          p_menu_id: id,
          p_prato_antigo: pratosAntigo,
          p_prato_novo: novoPrato,
          p_data_menu: menuAntigo.data,
          p_tipo_menu: menuAntigo.tipo
        });

      console.log("📊 Resposta da RPC:", { notificacoes, erroNotif });

      if (erroNotif) {
        console.error("❌ Erro na função RPC:", erroNotif);
      } else if (notificacoes > 0) {
        console.log(`✅ Notificações enviadas para ${notificacoes} aluno(s)`);

        // Enviar emails para os alunos
        const { data: alunosComReserva, error: erroAlunos } = await supabaseClient
          .from('reservas')
          .select('alunos(email, nome)')
          .eq('menu_id', id)
          .is('cancelamento_tipo', null);

        if (!erroAlunos && alunosComReserva) {
          const nomesMeses = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
          const dataObj = new Date(menuAntigo.data);
          const dia = dataObj.getDate();
          const mes = nomesMeses[dataObj.getMonth()];
          const tipoNome = menuAntigo.tipo === 'almoco' ? 'Almoço' : 
                          menuAntigo.tipo === 'pequeno_almoco' ? 'Pequeno Almoço' : 
                          menuAntigo.tipo === 'jantar' ? 'Jantar' : menuAntigo.tipo;

          const assunto = `Menu Alterado - ${tipoNome}, ${dia} de ${mes}`;
          const mensagem = `A cantina alterou o menu que reservaste para <strong>${dia} de ${mes}</strong>.<br><br><strong>Prato anterior:</strong> ${pratosAntigo}<br><strong>Prato novo:</strong> ${novoPrato}`;

          // Enviar emails (paralelo)
          const emailsEnviados = await Promise.allSettled(
            alunosComReserva.map(r => 
              enviarEmailNotificacao(r.alunos.email, assunto, mensagem, r.alunos.nome)
            )
          );

          const sucesso = emailsEnviados.filter(e => e.status === 'fulfilled' && e.value === true).length;
          console.log(`📧 Emails enviados: ${sucesso}/${alunosComReserva.length}`);
        }
      } else {
        console.log("⚠️ Nenhuma notificação enviada (provavelmente não há reservas ativas neste menu)");
      }
    } catch (erroNotif) {
      console.error("❌ Exceção ao notificar alunos:", erroNotif);
      // Não bloqueia a operação se notificações falhar
    }

    mostrarSucesso("Prato Atualizado", "Prato atualizado com sucesso!\n✅ Alunos foram notificados da alteração.");
    showMenusCriados();
  } catch (err) {
    handleError(err, "Erro ao atualizar prato");
  } finally {
    hideLoading();
  }
}

async function apagarMenu(id) {
  console.log("🗑️ Apagando menu:", id);

  if (!await confirmar("Apagar Menu", "Tens a certeza que queres apagar este menu?")) {
    console.log("❌ Operação cancelada pelo utilizador");
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
    console.log("✅ Menu apagado:", id);
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
    .is("cancelamento_tipo", null);

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
      .is("cancelamento_tipo", null)
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

  const { data, error } = await supabaseClient
    .from("reservas")
    .select("aluno_id, alunos(nome)")
    .order("aluno_id");

  if (error) {
    div.innerHTML = `<i>❌ Erro: ${error.message}</i>`;
    return;
  }

  if (!data || data.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem reservas registadas.</div>";
    document.getElementById("alunosPesquisaBox").style.display = "none";
    return;
  }

  alunosHistoricoLista = [
    ...new Map(
      data.map(r => [r.aluno_id, r.alunos.nome])
    ).entries()
  ].sort((a, b) => a[1].localeCompare(b[1]));

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
    <div class="aluno-card" onclick="showHistoricoAluno('${id}', '${nome}')">
      👤 ${nome}
    </div>
  `).join("");
}

async function showHistoricoAluno(alunoId, alunoNome) {
  alunoHistoricoAtual = alunoId;
  nomeAlunoHistoricoAtual = alunoNome;

  document.getElementById("alunosPesquisaBox").style.display = "none";
  document.getElementById("listaAlunosHistorico").innerHTML = "";
  document.getElementById("btnBackHistorico").style.display = "inline-block";
  document.getElementById("btnBackMenu").style.display = "none";

  const div = document.getElementById("historico");
  div.innerHTML = "⏳ A carregar histórico...";

  const { data: reservas, error } = await supabaseClient
    .from("reservas")
    .select(`
      id,
      tipo,
      data,
      cancelada,
      preco,
      is_dieta,
      menus!inner(prato)
    `)
    .eq("aluno_id", alunoId)
    .order("data", { ascending: false });

  if (error) {
    div.innerHTML = `<i>❌ Erro: ${error.message}</i>`;
    return;
  }

  if (!reservas || reservas.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>📭</div>Sem histórico disponível para este aluno.</div>";
    return;
  }
  
  document.getElementById("NomeAluno").innerText = alunoNome;
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

function _cartoesHistoricoDia(iso){
  const doDia = (historicoAtual || []).filter(r => r.data === iso);
  if(!doDia.length) return `<i>Sem reservas neste dia.</i>`;
  const ordemTipo = { pequeno_almoco: 0, almoco: 1, jantar: 2 };
  doDia.sort((a,b)=> (ordemTipo[a.tipo]??9) - (ordemTipo[b.tipo]??9));
  return doDia.map(r => `
    <div style="border:1px solid #e0e0e0;border-radius:10px;padding:12px;margin-bottom:10px;text-align:left;">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
        <b>${formatarTipoRefeicao(r.tipo)}${r.is_dieta ? " 🥗" : ""}</b>
        <span style="color:#007bff;font-weight:bold;">${Number(r.preco).toFixed(2)}€</span>
      </div>
      <div style="font-size:13px;color:#555;margin-bottom:6px;">${escapeHtml(r.menus?.prato || "-")}</div>
      <div class="${r.cancelada ? 'status-cancelada' : 'status-ativa'}" style="font-size:12px;">
        ${r.cancelada ? '❌ Cancelada' : '✅ Ativa'}
      </div>
    </div>
  `).join("");
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
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome)")
      .is("cancelamento_tipo", null);

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

    const saldsMap = {};
    data.forEach(r => {
      if (!saldsMap[r.aluno_id]) {
        saldsMap[r.aluno_id] = { 
          id: r.aluno_id, 
          nome: r.alunos.nome, 
          total: 0 
        };
      }
      saldsMap[r.aluno_id].total += Number(r.preco);
    });

    todosSaldos = Object.values(saldsMap);
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
        <span class="saldo-nome">${s.nome}</span>
        <span class="saldo-valor">${Number(s.total).toFixed(2)}€</span>
      </div>
    `)
    .join("");
  
  div.innerHTML = html;
  console.log(`📊 A mostrar ${saldosFiltrados.length} de ${todosSaldos.length} saldos`);
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
    // Primeiro, verificar diretamente as reservas do aluno para debug
    console.log('🔍 DEBUG: Verificando reservas do aluno ID:', alunoId);
    const { data: todasReservas, error: erroReservas } = await supabaseClient
      .from("reservas")
      .select("data, preco, cancelada, tipo, id")
      .eq("aluno_id", alunoId)
      .order("data", { ascending: false });

    console.log('🔍 DEBUG: Todas as reservas do aluno:', todasReservas);
    console.log('🔍 DEBUG: Erro reservas:', erroReservas);
    console.log('🔍 DEBUG: Total de reservas encontradas:', todasReservas?.length || 0);

    // Verificar reservas não canceladas
    const reservasNaoCanceladas = todasReservas?.filter(r => !r.cancelada) || [];
    console.log('🔍 DEBUG: Reservas não canceladas:', reservasNaoCanceladas);
    console.log('🔍 DEBUG: Total de reservas não canceladas:', reservasNaoCanceladas.length);

    // Calcular total manualmente para verificação
    const totalManual = reservasNaoCanceladas.reduce((sum, r) => sum + Number(r.preco), 0);
    console.log('🔍 DEBUG: Total manual calculado:', totalManual);

    // Se não há reservas não canceladas, mostrar detalhes
    if (reservasNaoCanceladas.length === 0 && todasReservas && todasReservas.length > 0) {
      console.log('🔍 DEBUG: Todas as reservas estão canceladas!');
      console.log('🔍 DEBUG: Detalhes das reservas canceladas:', 
        todasReservas.map(r => ({ data: r.data, preco: r.preco, cancelada: r.cancelada })));
    }

    // Usar função original que funciona com as reservas
    console.log('🔍 Buscando dívida por mês com RPC...');
    const { data: dividas, error } = await supabaseClient
      .rpc('obter_divida_por_mes', { p_aluno_id: alunoId });

    console.log('🔍 DEBUG: Erro RPC:', error);
    console.log('🔍 DEBUG: Resultado RPC:', dividas);

    if (error) {
      console.error("Erro ao buscar dívida por mês:", error);
      handleError(error, "Erro ao carregar dívidas do aluno");
      return;
    }

    console.log('🔍 Dívidas encontradas pela RPC:', dividas);

    if (!dividas || dividas.length === 0) {
      console.log('📋 Nenhuma dívida encontrada pela função RPC');
      
      // Se há reservas não canceladas mas RPC não retorna, há problema na função
      if (reservasNaoCanceladas.length > 0) {
        console.log('⚠️ ALERTA: Há reservas não canceladas mas a RPC não retornou dívidas!');
        console.log('⚠️ Verificando se a função RPC está correta...');
        
        // Tentar calcular dívida manualmente e mostrar
        const porMes = {};
        reservasNaoCanceladas.forEach(r => {
          const data = new Date(r.data);
          const chave = `${data.getFullYear()}-${data.getMonth() + 1}`;
          if (!porMes[chave]) {
            porMes[chave] = { ano: data.getFullYear(), mes: data.getMonth() + 1, valor: 0 };
          }
          porMes[chave].valor += Number(r.preco);
        });
        
        console.log('🔍 DEBUG: Dívida calculada manualmente por mês:', porMes);
        
        // Mostrar dívida manualmente calculada
        const dividasManuais = Object.values(porMes);
        if (dividasManuais.length > 0) {
          console.log('🔄 Usando dívida calculada manualmente...');
          await mostrarDividaManual(alunoId, dividasManuais);
          return;
        }
      }
      
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

// Função auxiliar para mostrar dívida calculada manualmente
async function mostrarDividaManual(alunoId, dividas) {
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
    const emAtraso = new Date() > new Date(item.ano, item.mes, 15);

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

// Função auxiliar para processar dívidas encontradas
async function processarDividasEncontradas(alunoId, dividas) {
  // Obter nome do aluno
  console.log('🔍 Buscando nome do aluno...');
  const { data: aluno } = await supabaseClient
    .from("alunos")
    .select("nome")
    .eq("id", alunoId)
    .single();

  console.log('👤 Aluno encontrado:', aluno);
  if (aluno && aluno.nome) {
    document.getElementById("tituloAluno").innerText = aluno.nome;
    console.log('✅ Nome do aluno definido no título:', aluno.nome);
  } else {
    document.getElementById("tituloAluno").innerText = "Aluno";
    console.log('⚠️ Nome do aluno não encontrado, usando padrão');
  }

  // Calcular total
  const total = dividas.reduce((sum, item) => sum + Number(item.valor), 0);
  console.log('💰 Total calculado:', total);
  document.getElementById("valorTotal").innerText = `${total.toFixed(2)}€`;

  // Exibir meses em dívida
  const mesesDivida = document.getElementById("mesesDivida");
  mesesDivida.innerHTML = "";

  const nomesMeses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];

  console.log('📅 Processando meses em dívida...');
  dividas.forEach(item => {
    const nomeMes = nomesMeses[item.mes - 1];
    const emAtraso = item.em_atraso;

    console.log(`📊 Mês: ${nomeMes} ${item.ano}, Valor: ${item.valor}€, Atraso: ${emAtraso}`);

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
async function carregarSaldoAlunoFallback(alunoId) {
  try {
    const { data: reservas, error } = await supabaseClient
      .from("reservas")
      .select("data, preco, alunos(nome)")
      .eq("aluno_id", alunoId)
      .is("cancelamento_tipo", null);

    if (error) {
      handleError(error, "Erro ao carregar histórico do aluno");
      return;
    }

    if (!reservas || reservas.length === 0) {
      document.getElementById("tituloAluno").innerText = "Sem registros";
      document.getElementById("valorTotal").innerText = "€0.00";
      document.getElementById("mesesDivida").innerHTML = "";
      document.getElementById("btnLiquidarTotal").style.display = "none";
      return;
    }

    document.getElementById("tituloAluno").innerText = reservas[0].alunos.nome;

    let total = 0;
    const porMes = {};

    reservas.forEach(r => {
      total += Number(r.preco);
      const d = new Date(r.data);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      porMes[key] = (porMes[key] || 0) + Number(r.preco);
    });

    document.getElementById("valorTotal").innerText = `${total.toFixed(2)}€`;

    const hoje = new Date();
    const mesesDivida = document.getElementById("mesesDivida");
    mesesDivida.innerHTML = "";

    const mesesOrdenados = Object.entries(porMes).sort((a, b) => {
      const [anoA, mesA] = a[0].split("-");
      const [anoB, mesB] = b[0].split("-");
      return new Date(anoB, mesB - 1) - new Date(anoA, mesA - 1);
    });

    const nomesMeses = [
      "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
      "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
    ];

    mesesOrdenados.forEach(([key, valor]) => {
      const [ano, mes] = key.split("-");
      const limite = new Date(parseInt(ano), parseInt(mes) - 1, 15);
      const emAtraso = hoje > limite;
      const nomeMes = nomesMeses[parseInt(mes) - 1];

      mesesDivida.innerHTML += `
        <div class="mes-divida ${emAtraso ? 'em-atraso' : ''}">
          <span>${nomeMes} ${ano}</span>
          <strong>${valor.toFixed(2)}€</strong>
          <button class="${emAtraso ? 'btn-atraso' : ''}" onclick="liquidarMes('${alunoId}', ${ano}, ${parseInt(mes)})">
            ${emAtraso ? '⚠️ Liquidar' : 'Liquidar mês'}
          </button>
        </div>
      `;
    });

    const btnLiquidar = document.getElementById("btnLiquidarTotal");
    btnLiquidar.classList.remove("hidden");
    btnLiquidar.style.display = "block";

  } catch (err) {
    handleError(err, "Erro ao processar dados do aluno");
  }
}

/* =============================
   CANTINA — AÇÕES DE LIQUIDAÇÃO
============================= */

async function liquidarDividaTotal(alunoId) {
  console.log("💰 Liquidando dívida total do aluno:", alunoId);
  
  if (!alunoId) {
    mostrarErro("Erro", "Aluno inválido. Volte atrás e tente novamente.");
    return;
  }

  if (!await confirmar("Liquidar Dívida", "Tem certeza que deseja liquidar TODA a dívida deste aluno?")) {
    console.log("❌ Operação cancelada pelo utilizador");
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
      .is("cancelamento_tipo", null);

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
    
    console.log("✅ Dívida liquidada para aluno:", alunoId);
    
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
      console.log('🔍 Resultado da liquidação:', resultado);
      
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
    
    console.log(`✅ Mês ${mes}/${ano} liquidado para aluno:`, alunoId);
    
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

function voltarCantina() {
  esconderTodasPaginas();
  show("paginaCantina");
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
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome), data")
      .is("cancelamento_tipo", null);

    if (error) {
      mostrarErro("Erro", "Erro ao gerar relatório");
      console.error(error);
      return;
    }

    const reportData = {};
    data.forEach(r => {
      const d = new Date(r.data);
      if (d.getFullYear() === ano && (d.getMonth() + 1) === mes) {
        if (!reportData[r.aluno_id]) {
          reportData[r.aluno_id] = {
            nome: r.alunos.nome,
            total_refeicoes: 0,
            total_valor: 0
          };
        }
        reportData[r.aluno_id].total_refeicoes += 1;
        reportData[r.aluno_id].total_valor += Number(r.preco);
      }
    });

    const resultado = Object.values(reportData);

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
  console.log("📥 Iniciando exportação de valores em dívidas...");
  
  const { data, error } = await supabaseClient
    .from("reservas")
    .select("aluno_id, preco, alunos(nome)")
    .is("cancelamento_tipo", null);

  if (error) {
    mostrarErro("Erro", "Erro ao buscar valores em dívida: " + error.message);
    console.error("❌ Erro ao buscar valores em dívida", error);
    return;
  }

  if (!data || data.length === 0) {
    mostrarInfo("Sem Débitos", "Sem débitos para exportar.");
    return;
  }

  const saldos = {};
  data.forEach(r => {
    if (!saldos[r.aluno_id]) {
      saldos[r.aluno_id] = { nome: r.alunos.nome, total: 0, refeicoes: 0 };
    }
    saldos[r.aluno_id].total += Number(r.preco);
    saldos[r.aluno_id].refeicoes += 1;
  });

  const linhas = [["Aluno", "Refeições", "Total Dívida (€)"]];
  let totalGeral = 0;
  let refeicaoesTotal = 0;

  Object.entries(saldos)
    .sort((a, b) => a[1].nome.localeCompare(b[1].nome))
    .forEach(([id, aluno]) => {
      linhas.push([
        aluno.nome,
        aluno.refeicoes,
        aluno.total.toFixed(2)
      ]);
      totalGeral += aluno.total;
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
  console.log("✅ Ficheiro exportado:", nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}

async function exportarHistoricoAluno() {
  if (!alunoAtual) {
    mostrarErro("Erro", "Nenhum aluno selecionado.");
    return;
  }

  console.log("📥 Iniciando exportação de histórico do aluno:", alunoAtual);

  const { data: aluno } = await supabaseClient
    .from("alunos")
    .select("nome")
    .eq("id", alunoAtual)
    .single();

  const { data: reservas, error } = await supabaseClient
    .from("reservas")
    .select("data, tipo, preco, cancelada, is_dieta, menus(prato)")
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
    const status = r.cancelada ? "Cancelada" : "Ativa";
    
    linhas.push([
      formatarData(r.data),
      tipoFormatado,
      r.menus?.prato || "",
      r.preco.toFixed(2),
      dieta,
      status
    ]);

    if (!r.cancelada) {
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
  console.log("✅ Ficheiro exportado:", nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}

