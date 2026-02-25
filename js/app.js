// Full app JS extracted from indexfinal.html (supabaseClient must be initialized in js/supabase.js)
let supabaseClient = null;

// Aguarda o supabaseClient estar disponível
function waitForSupabase() {
  return new Promise(resolve => {
    if(window.supabaseClient) {
      supabaseClient = window.supabaseClient;
      console.log("✅ supabaseClient disponível");
      resolve();
      return;
    }
    
    const checkInterval = setInterval(() => {
      if(window.supabaseClient) {
        supabaseClient = window.supabaseClient;
        console.log("✅ supabaseClient disponível após aguardar");
        clearInterval(checkInterval);
        resolve();
      }
    }, 50);
    
    // Timeout de 10 segundos
    setTimeout(() => {
      clearInterval(checkInterval);
      console.error("⚠️ supabaseClient não ficou disponível no tempo esperado");
      resolve();
    }, 10000);
  });
}

let currentUser = null;
let role = null;
let reservasDoDia = [];
let reservasPorTipo = {};
let relatorioAtual = [];
let todosSaldos = []; // Array com todos os saldos em dívida
let saldosFiltrados = []; // Array com saldos filtrados
let ordenacaoSaldos = 'nome'; // Tipo de ordenação atual

/* ==============================
   ELEMENTOS HTML
============================== */
const getEl = id => document.getElementById(id);

let elements = {};

// Função para recarregar elementos (após DOM estar pronto)
function loadElements() {
  console.log("🔄 Carregando elementos do DOM...");
  
  elements = {
    login: getEl("login"),
    email: getEl("email"),
    password: getEl("password"),
    btnLogin: getEl("btnLogin"),
    menuSelect: getEl("menuSelect"),
    alunoMenuSelect: getEl("alunoMenuSelect"),
    cantinaMenuSelect: getEl("cantinaMenuSelect"),
    menuTitle: getEl("menuTitle"),
    alunoMenuTitle: getEl("alunoMenuTitle"),
    cantinaMenuTitle: getEl("cantinaMenuTitle"),
    buttons: getEl("buttons"),
    alunoButtons: getEl("alunoButtons"),
    cantinButtons: getEl("cantinButtons"),
    saldoAluno: getEl("saldo"),
    dataMenu: getEl("dataMenu"),
    pratoMenu: getEl("pratoMenu"),
    tipoMenu: getEl("tipoMenu"),
    diaMenu: getEl("diaMenu"),
    listaMenus: getEl("listaMenus"),
    btnAddMenu: getEl("btnAddMenu"),
    listaAlunoMenu: getEl("listaAlunoMenu"),
    minhasReservas: getEl("minhasReservas"),
    historico: getEl("historico")
  };
  
  const elementosCarregados = Object.keys(elements).filter(k => elements[k]);
  console.log("✅ Elementos carregados:", elementosCarregados.length, "de", Object.keys(elements).length);
  if(elementosCarregados.length < Object.keys(elements).length) {
    const elementosFaltosos = Object.keys(elements).filter(k => !elements[k]);
    console.warn("⚠️ Elementos faltosos:", elementosFaltosos);
  }
  
  // Attach event listeners para botões importantes
  if (elements.btnAddMenu) {
    elements.btnAddMenu.addEventListener("click", addMenu);
    console.log("✅ Event listener do 'btnAddMenu' atribuído");
  }
}

/* ==============================
   FUNÇÕES UTILITÁRIAS
============================== */
const show = id => {
  document.querySelectorAll(".container").forEach(c => c.classList.add("hidden"));
  getEl(id) && getEl(id).classList.remove("hidden");
};

const addBack = id => {
  const container = getEl(id);
  if(container.querySelector(".btn-back")) return;
  const btn = document.createElement("button");
  btn.className = "btn-back";
  btn.textContent = "Voltar";
  btn.onclick = menu;
  container.appendChild(btn);
};

const tipoEmoji = tipo => {
  const map = {
    pequeno_almoco: '🥐',
    almoco: '🍽️',
    jantar: '🍲',
    dieta: '🥗'
  };
  return map[tipo] || '';
};

const formatCurrency = valor => `€${Number(valor).toFixed(2)}`;

/* ==============================
   FUNÇÕES DE FEEDBACK AO UTILIZADOR
============================== */

// Mostrar/Esconder mensagens padronizadas
function mostrarMensagem(tipo, texto) {
  // Remove mensagens anteriores
  document.querySelectorAll('.alert').forEach(el => el.remove());
  
  const div = document.createElement('div');
  div.className = `alert alert-${tipo}`;
  div.textContent = texto;
  document.body.insertBefore(div, document.body.firstChild);
  
  // Auto-remover após 2 segundos
  setTimeout(() => div.remove(), 2000);
}

// Indicadores de carregamento
let loadingElement = null;
function showLoading(texto = '⏳ Carregando...') {
  if (loadingElement) loadingElement.remove();
  loadingElement = document.createElement('div');
  loadingElement.style.cssText = `
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    background: white;
    padding: 30px 50px;
    border-radius: 12px;
    box-shadow: 0 8px 24px rgba(0,0,0,0.15);
    font-size: 18px;
    font-weight: 700;
    z-index: 9999;
    animation: slideUp 0.3s ease-out;
  `;
  loadingElement.textContent = texto;
  document.body.appendChild(loadingElement);
}

function hideLoading() {
  if (loadingElement) {
    loadingElement.remove();
    loadingElement = null;
  }
}

/* ====== SISTEMA DE MODAL CUSTOMIZADO ====== */

// Criar e mostrar modal genérico
function showModal(config) {
  return new Promise((resolve) => {
    // Remove modal anterior se existir
    const existingOverlay = document.querySelector('.modal-overlay');
    if (existingOverlay) existingOverlay.remove();
    
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    
    const modal = document.createElement('div');
    const modalClass = config.type === 'success' ? 'modal-success' : 
                       config.type === 'error' ? 'modal-error' :
                       config.type === 'warning' ? 'modal-warning' : '';
    modal.className = `modal-content ${modalClass}`;
    
    let html = `
      <div class="modal-header">
        <span>${config.icon || 'ℹ️'}</span>
        <div class="modal-title">${config.title}</div>
      </div>
      <div class="modal-message">${config.message}</div>
      <div class="modal-buttons">
    `;
    
    if (config.buttons && config.buttons.length) {
      config.buttons.forEach(btn => {
        const btnClass = btn.type === 'primary' ? 'modal-button-primary' :
                        btn.type === 'danger' ? 'modal-button-danger' :
                        btn.type === 'success' ? 'modal-button-success' :
                        'modal-button-secondary';
        html += `<button class="modal-button ${btnClass}" onclick="window.modalResolve('${btn.resolve}')">${btn.text}</button>`;
      });
    }
    
    html += `</div>`;
    modal.innerHTML = html;
    overlay.appendChild(modal);
    document.body.appendChild(overlay);
    
    // Resolver modal
    window.modalResolve = (result) => {
      overlay.remove();
      resolve(result);
    };
    
    // Fechar ao clicar fora
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay && config.canClose !== false) {
        overlay.remove();
        resolve(false);
      }
    });
  });
}

// Modal de Confirmação
function confirmar(titulo, mensagem, texto_sim = '✅ Sim', texto_nao = '❌ Não') {
  return showModal({
    icon: '⚠️',
    title: titulo,
    message: mensagem,
    type: 'warning',
    buttons: [
      { text: texto_nao, type: 'secondary', resolve: false },
      { text: texto_sim, type: 'primary', resolve: true }
    ],
    canClose: true
  });
}

// Modal de Sucesso
function mostrarSucesso(titulo, mensagem, timeout = 2000) {
  const promise = showModal({
    icon: '✅',
    title: titulo,
    message: mensagem,
    type: 'success',
    buttons: [
      { text: 'Fechar', type: 'success', resolve: true }
    ],
    canClose: false
  });
  
  if (timeout > 0) {
    setTimeout(() => {
      const overlay = document.querySelector('.modal-overlay');
      if (overlay) {
        overlay.remove();
      }
    }, timeout);
  }
  
  return promise;
}

// Modal de Erro
function mostrarErro(titulo, mensagem) {
  return showModal({
    icon: '❌',
    title: titulo,
    message: mensagem,
    type: 'error',
    buttons: [
      { text: 'OK', type: 'danger', resolve: false }
    ],
    canClose: true
  });
}

// Modal de Info/Alerta
function mostrarInfo(titulo, mensagem) {
  return showModal({
    icon: '📋',
    title: titulo,
    message: mensagem,
    type: 'warning',
    buttons: [
      { text: 'OK', type: 'primary', resolve: true }
    ],
    canClose: true
  });
}

// Validação de inputs
function validarInput(valor, nomeCampo, minLength = 3) {
  if (!valor || typeof valor !== 'string') {
    mostrarMensagem('error', `❌ ${nomeCampo} não pode estar vazio`);
    return false;
  }
  
  if (valor.trim().length < minLength) {
    mostrarMensagem('error', `❌ ${nomeCampo} deve ter pelo menos ${minLength} caracteres`);
    return false;
  }
  
  return true;
}

function handleError(error, mensagemFallback = 'Erro ao processar operação') {
  console.error('❌ Erro:', error);
  const mensagem = error?.message || error?.toString() || mensagemFallback;
  mostrarMensagem('error', `❌ ${mensagemFallback}`);
  hideLoading();
  return false;
}

/* ==============================
   LOGIN / LOGOUT
============================== */
async function login(){
  console.log("🔐 Iniciando login...", { supabaseClient: !!supabaseClient });
  
  if(!elements.email || !elements.password) {
    mostrarErro("Erro", "Formulário não encontrado");
    console.error("❌ Elementos não encontrados", elements);
    return;
  }
  
  const email = elements.email.value.trim().toLowerCase();
  const password = elements.password.value;
  
  if(!email || !password) {
    mostrarErro("Erro de Validação", "Preenche email e palavra-passe");
    return;
  }
  
  if(!supabaseClient) {
    mostrarErro("Erro de Conexão", "Conexão com base de dados não está pronta. Atualiza a página.");
    console.error("❌ supabaseClient não está disponível");
    return;
  }

  const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
  if(error){ 
    mostrarErro("Erro de Login", error.message); 
    console.error("❌ Erro na autenticação", error);
    return; 
  }

  currentUser = data.user;
  console.log("✅ Autenticado com sucesso", currentUser.email);

  // Verifica role
  const { data: aluno } = await supabaseClient.from("alunos").select("*").eq("email", email);
  if(aluno && aluno.length){ role = "aluno"; console.log("✅ Role: aluno"); menu(); return; }

  const { data: cantina } = await supabaseClient.from("cantina").select("*").eq("email", email);
  if(cantina && cantina.length){ role = "cantina"; console.log("✅ Role: cantina"); menu(); return; }

  mostrarErro("Acesso Negado", "Utilizador autenticado mas não existe em aluno/cantina");
  console.error("❌ Utilizador não encontrado em tabelas");
}

async function logout(){
  await supabaseClient.auth.signOut();
  location.reload();
}

// Attach login handlers after DOM is ready
if(typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', async () => {
    // Aguarda supabaseClient estar pronto
    await waitForSupabase();
    
    loadElements();
    
    if(elements.btnLogin) {
      elements.btnLogin.addEventListener("click", login);
    }
  });
  document.addEventListener("keydown", e => {
    if(e.key==="Enter" && elements.login && !elements.login.classList.contains("hidden")) login();
  });
}

/* ==============================
   MENU PRINCIPAL
============================== */
async function menu(){
  // Esconder todos os containers
  document.querySelectorAll(".container").forEach(c => c.classList.add("hidden"));
  
  if(role==="aluno"){
    // Menu do Aluno com Saldo
    elements.alunoMenuSelect.classList.remove("hidden");
    elements.alunoMenuTitle.innerText = "Área do Aluno";
    elements.alunoButtons.innerHTML = `
      <button class="btn-full" onclick="showAlunoMenu()">Reservar Menu</button>
      <button class="btn-full" onclick="showAlunoReservas()">Minhas Reservas</button>
    `;
    await saldo();
  } else {
    // Menu da Cantina (sem saldo)
    elements.cantinaMenuSelect.classList.remove("hidden");
    elements.cantinaMenuTitle.innerText = "Área da Cantina";
    elements.cantinButtons.innerHTML = `
      <button class="btn-full" onclick="showCriarMenu()">Criar Menus</button>
      <button class="btn-full" onclick="showMenusCriados()">Menus Criados</button>
      <button class="btn-full" onclick="showCantinaReservasHoje()">Reservas do Dia</button>
      <button class="btn-full" onclick="showCantinaHistorico()">Histórico</button>
      <button class="btn-full" onclick="showCantinaSaldos()">Saldos</button>
    `;
  }
}

/* ==============================
   SALDO ALUNO
============================== */
async function saldo(){
  if(role!="aluno") return;

  try {
    const { data: aluno, error: alunoError } = await supabaseClient.from("alunos").select("id").eq("email", currentUser.email).single();
    if(alunoError) {
      handleError(alunoError, "Erro ao buscar dados do aluno");
      return;
    }
    
    const { data: reservas, error: reservasError } = await supabaseClient.from("reservas").select("preco").eq("aluno_id", aluno.id).eq("cancelada", false);
    if(reservasError) {
      handleError(reservasError, "Erro ao buscar reservas");
      return;
    }

    const total = (reservas || []).reduce((sum,r) => sum + Number(r.preco), 0);
    if(elements.saldoAluno) {
      elements.saldoAluno.innerText = `Saldo: ${formatCurrency(total)}`;
    } else {
      const saldoEl = document.getElementById("saldo");
      if(saldoEl) {
        saldoEl.innerText = `Saldo: ${formatCurrency(total)}`;
      }
    }
    console.log("✅ Saldo atualizado", total);
  } catch (err) {
    handleError(err, "Erro ao calcular saldo");
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
   CANTINA — CRIAR MENU (CLEAN)
============================= */

function showCriarMenu() {
  console.log("📝 Mostrando formulário de criar menu");
  show("cantinaMenu");
}

async function addMenu() {
  console.log("📝 Adicionando menu...", { supabaseClient: !!supabaseClient });

  if (!supabaseClient) {
    mostrarMensagem("error", "❌ Erro: Conexão não pronta. Atualiza a página.");
    console.error("❌ supabaseClient não disponível");
    return;
  }

  const dataValue = document.getElementById("dataMenu").value;
  const tipo = document.getElementById("tipoMenu").value;
  let prato = document.getElementById("pratoMenu").value.trim();
  
  console.log("📋 Valores do formulário:", { dataValue, tipo, prato });

  // Validar data
  if (!dataValue) {
    mostrarMensagem("warning", "⚠️ Seleciona uma data");
    return;
  }

  // ❌ Não permitir datas passadas
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

  // Pequeno almoço é sempre fixo
  if (tipo === "pequeno_almoco") {
    prato = configuracao.pequeno_almoco.prato;
  }

  // Almoço precisa de prato - validação
  if (tipo === "almoco" && !prato) {
    mostrarMensagem("warning", "⚠️ Preenche o prato do almoço");
    return;
  }

  showLoading("⏳ Criando menu...");

  try {
    console.log("🌐 Enviando para Supabase...", { dataValue, tipo, prato, preco: configuracao[tipo].preco });
    
    const { data, error } = await supabaseClient
      .from("menus")
      .insert([{
        data: dataValue,
        tipo,
        prato,
        preco: configuracao[tipo].preco
      }]);

    if (error) {
      handleError(error, "Erro ao criar menu");
      return;
    }

    mostrarSucesso("Menu Criado", "Menu criado com sucesso!");
    console.log("✅ Menu criado com sucesso", data);

    // Reset
    document.getElementById("dataMenu").value = "";
    document.getElementById("pratoMenu").value = "";
    document.getElementById("tipoMenu").value = "pequeno_almoco";

    showMenusCriados();
  } catch (err) {
    handleError(err, "Erro ao criar menu");
  } finally {
    hideLoading();
  }
}

/* =============================
   CANTINA — LISTAR MENUS CRIADOS (CLEAN)
============================= */

function toggleDia(data) {
  const el = document.getElementById(`dia-${data}`);
  const chevron = document.querySelector(`.chevron-${data}`);
  if (el) {
    el.classList.toggle("hidden");
    if (chevron) {
      // Se está hidden, chevron ← 0deg, senão ↓ 180deg
      chevron.style.transform = el.classList.contains("hidden") ? "rotate(0deg)" : "rotate(180deg)";
    }
  }
}

async function showMenusCriados() {
  console.log("📋 Carregando menus criados...");
  show("cantinaMenus");
  
  showLoading("⏳ Carregando menus...");

  // Adicionar input de filtro com listener
  const diaMenuInput = document.getElementById("diaMenu");
  if (diaMenuInput && !diaMenuInput.hasListener) {
    diaMenuInput.addEventListener("change", renderMenusFiltrados);
    diaMenuInput.hasListener = true;
  }

  try {
    const { data: menus, error } = await supabaseClient
      .from("menus")
      .select("*")
      .order("data", { ascending: true });

    if (error) {
      handleError(error, "Erro ao carregar menus");
      return;
    }

    console.log("✅ Menus encontrados:", menus);

    if (!menus || menus.length === 0) {
      document.getElementById("listaMenus").innerHTML =
        `<div class="empty-state">
          <span class="empty-state-icon">📭</span>
          <p>Nenhum menu criado ainda</p>
        </div>`;
      return;
    }

    // Guardar menus globalmente para filtro
    window.todosOsMenus = menus;
    renderMenusFiltrados();

  } catch (err) {
    handleError(err, "Erro ao carregar menus");
  } finally {
    hideLoading();
  }
}

async function renderMenusFiltrados() {
  const diaMenuInput = document.getElementById("diaMenu");
  const dataFiltro = diaMenuInput ? diaMenuInput.value : "";
  
  let menusFiltrados = window.todosOsMenus || [];
  
  if (dataFiltro) {
    menusFiltrados = menusFiltrados.filter(m => m.data === dataFiltro);
    console.log("🔍 Filtrando por data:", dataFiltro, "Encontrados:", menusFiltrados.length);
  } else {
    console.log("📋 Mostrando todos os menus");
  }

  if (!menusFiltrados || menusFiltrados.length === 0) {
    document.getElementById("listaMenus").innerHTML =
      `<div class="empty-state">
        <span class="empty-state-icon">🔍</span>
        <p>Nenhum menu encontrado para a data selecionada</p>
      </div>`;
    return;
  }

  // Agrupar por data
  const porDia = {};
  menusFiltrados.forEach(m => {
    if (!porDia[m.data]) porDia[m.data] = [];
    porDia[m.data].push(m);
  });

  const hojeObj = new Date();
  const hojeStr = hojeObj.toISOString().split("T")[0];
  const horaAtual = hojeObj.getHours();

  document.getElementById("listaMenus").innerHTML =
    Object.entries(porDia)
      .map(([data, menusDia]) => {
        // Formatar data com dia da semana
        const dataObj = new Date(data + "T00:00:00");
        const diaSemana = dataObj.toLocaleDateString('pt-PT', { weekday: 'long' });
        const dataFormatada = dataObj.toLocaleDateString('pt-PT', { day: 'numeric', month: 'long', year: 'numeric' });
        const ehHoje = data === hojeStr;

        return `
          <div class="menu-dia">
            <h3 onclick="toggleDia('${data}')" class="menu-dia-titulo">
              <span>📅 ${diaSemana.charAt(0).toUpperCase() + diaSemana.slice(1)}, ${dataFormatada}</span>
              ${ehHoje ? '<span style="color:white;font-weight:700;font-size:11px;background:linear-gradient(135deg, var(--primary), var(--primary-dark));padding:4px 10px;border-radius:12px;text-transform:uppercase;letter-spacing:0.3px;">Hoje</span>' : ''}
              <span style="margin-left:auto;transition:transform 0.3s;display:inline-block;transform:rotate(180deg);" class="chevron-${data}">▼</span>
            </h3>

            <div id="dia-${data}">
              ${menusDia.map(m => {

                let podeEditar = false;

                // Futuro → pode editar
                if (data > hojeStr) {
                  podeEditar = true;
                }

                // Hoje → só até às 9h
                if (data === hojeStr && horaAtual < 9) {
                  podeEditar = true;
                }

                return `
                  <div class="menu-item">
                    <div>
                      <span style="font-size:22px;display:flex;align-items:center;">${tipoEmoji(m.tipo)}</span>
                      <div>
                        <b>${m.tipo.replace(/_/g, " ")}</b>
                        ${m.prato ? `<span class="prato"> — ${m.prato}</span>` : ''}
                        <span class="preco">€${Number(m.preco).toFixed(2)}</span>
                      </div>
                    </div>

                    ${podeEditar ? `
                      <div class="menu-item-actions">
                        ${m.tipo === "almoco" ? `
                          <button class="btn-edit" onclick="startEdit('${m.id}')">✏️ Editar</button>
                        ` : ``}
                        <button class="btn-delete" onclick="apagarMenu('${m.id}')">🗑️ Apagar</button>
                      </div>
                    ` : `<div class="menu-item-bloqueado">⛔ Bloqueado</div>`}
                  </div>

                  ${m.tipo === "almoco" ? `
                    <div id="edit-${m.id}" class="hidden">
                      <div class="menu-edit-form">
                        <input id="input-prato-${m.id}" value="${m.prato || ""}" placeholder="Nome do prato">
                        <button class="btn-save" onclick="saveEdit('${m.id}')">💾 Guardar</button>
                        <button class="btn-cancel" onclick="cancelEdit('${m.id}')">❌ Cancelar</button>
                      </div>
                    </div>
                  ` : ``}
                `;
              }).join("")}
            </div>
          </div>
        `;
      })
      .join("");
    console.log("✅ Menus renderizados com sucesso");
}

/* =============================
   CANTINA — EDITAR / APAGAR MENU
============================= */

function startEdit(id) {
  const el = document.getElementById(`edit-${id}`);
  if (el) el.classList.remove("hidden");
}

function cancelEdit(id) {
  const el = document.getElementById(`edit-${id}`);
  if (el) el.classList.add("hidden");
}

async function saveEdit(id) {
  console.log("💾 Salvando edição do menu:", id);

  const input = document.getElementById(`input-prato-${id}`);
  if (!input) {
    mostrarMensagem("error", "❌ Erro ao acceder ao campo de edição.");
    console.error("❌ Input não encontrado para menu:", id);
    return;
  }

  const novoPrato = input.value.trim();
  if (!validarInput(novoPrato, "prato")) {
    return;
  }

  showLoading("⏳ Atualizando prato...");

  try {
    const { error } = await supabaseClient
      .from("menus")
      .update({ prato: novoPrato })
      .eq("id", id);

    if (error) {
      handleError(error, "Erro ao atualizar prato");
      return;
    }

    mostrarSucesso("Prato Atualizado", "Prato atualizado com sucesso!");
    console.log("✅ Menu atualizado:", id);
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
   CANTINA — RESERVAS
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
    .eq("cancelada", false);

  if (error) {
    div.innerHTML = `<i>${error.message}</i>`;
    return;
  }

  reservasHoje = data || [];

  // Organizar por tipo
  reservasHojePorTipo = {
    pequeno_almoco: [],
    almoco: [],
    jantar: [],
    dieta: []
  };

  reservasHoje.forEach(r => {
    if (r.tipo === "almoco" && r.is_dieta) {
      reservasHojePorTipo.dieta.push(r);
    } else {
      reservasHojePorTipo[r.tipo]?.push(r);
    }
  });

  // Mostrar resumo por refeição
  div.innerHTML = `
    <div class="refeicao" onclick="verDetalheRefeicao('pequeno_almoco')">
      ☕ Pequeno-almoço — ${reservasHojePorTipo.pequeno_almoco.length}
    </div>
    <div class="refeicao" onclick="verDetalheRefeicao('almoco')">
      🍽️ Almoço — ${reservasHojePorTipo.almoco.length}
    </div>
    <div class="refeicao" onclick="verDetalheRefeicao('dieta')">
      🥗 Dieta — ${reservasHojePorTipo.dieta.length}
    </div>
    <div class="refeicao" onclick="verDetalheRefeicao('jantar')">
      🌙 Jantar — ${reservasHojePorTipo.jantar.length}
    </div>
  `;
}

// Verificar dívida antes de permitir reserva
async function alunoTemDivida(alunoId) {
  try {
    // Query direta na tabela reservas sem usar RPC
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("id")
      .eq("aluno_id", alunoId)
      .eq("cancelada", false)
      .limit(1);

    if (error) {
      mostrarErro("Erro", "Erro ao verificar pagamentos");
      return true;
    }

    // Se existe alguma reserva não cancelada, tem dívida
    return data && data.length > 0;
  } catch (err) {
    console.error("❌ Erro ao verificar dívida:", err);
    return true; // Por segurança, bloqueia se houver erro
  }
}

// Mostrar detalhe de reservas por refeição
function verDetalheRefeicao(tipo) {
  const div = document.getElementById("reservasDia");
  const lista = reservasHojePorTipo[tipo] || [];

  if (lista.length === 0) {
    div.innerHTML = `
      <h3>${tipo.toUpperCase()}</h3>
      <i>Sem reservas</i>
      <br><button onclick="showCantinaReservasHoje()">⬅️ Voltar as Reservas de Hoje</button>
    `;
    return;
  }

  div.innerHTML = `
    <h3>${tipo.toUpperCase()}</h3>
    ${lista.map(r => `<div>👤 ${r.alunos.nome}</div>`).join("")}
    <br>
    <button onclick="showCantinaReservasHoje()">⬅️ Voltar as Reservas de Hoje</button>
  `;
}

/* =============================
   CANTINA — HISTÓRICO
============================= */

// Variáveis globais para filtros de histórico
let alunosHistoricoLista = []; // Lista de todos os alunos
let alunosHistoricoFiltrados = []; // Alunos filtrados
let historicoAtual = []; // Todos os históricos do aluno
let historicoFiltrado = []; // Históricos filtrados
let alunoHistoricoAtual = null; // ID do aluno sendo visualizado
let nomeAlunoHistoricoAtual = ""; // Nome do aluno

async function showCantinaHistorico() {
  show("cantinaHistorico");

  // Mostrar lista de alunos, esconder filtros
  document.getElementById("alunosPesquisaBox").style.display = "block";
  document.getElementById("historicoFiltrosBox").style.display = "none";
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

  // Remove duplicados e ordena
  alunosHistoricoLista = [
    ...new Map(
      data.map(r => [r.aluno_id, r.alunos.nome])
    ).entries()
  ].sort((a, b) => a[1].localeCompare(b[1]));

  alunosHistoricoFiltrados = [...alunosHistoricoLista];

  // Limpar e mostrar pesquisa
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
  
  // Atualizar contagem
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
  // Guardar dados do aluno
  alunoHistoricoAtual = alunoId;
  nomeAlunoHistoricoAtual = alunoNome;

  // Mostrar interface com filtros
  document.getElementById("alunosPesquisaBox").style.display = "none";
  document.getElementById("listaAlunosHistorico").innerHTML = "";
  document.getElementById("historicoFiltrosBox").style.display = "block";
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

  // Guardar histórico completo
  historicoAtual = reservas;
  historicoFiltrado = [...reservas];

  // Limpar filtros
  document.getElementById("pesquisaHistorico").value = "";
  document.getElementById("filtroTipoHistorico").value = "";
  document.getElementById("filtroStatusHistorico").value = "";

  // Exibir histórico filtrado
  exibirHistoricoFiltrado();
}

function filtrarHistorico() {
  const pesquisa = document.getElementById("pesquisaHistorico").value.toLowerCase();
  const tipo = document.getElementById("filtroTipoHistorico").value;
  const status = document.getElementById("filtroStatusHistorico").value;

  historicoFiltrado = historicoAtual.filter(r => {
    // Filtro por prato (pesquisa)
    const pratoMatches = !pesquisa || (r.menus?.prato || "").toLowerCase().includes(pesquisa);
    
    // Filtro por tipo
    const tipoMatches = !tipo || r.tipo === tipo;
    
    // Filtro por status
    const statusMatches = !status || (status === "ativa" ? !r.cancelada : r.cancelada);
    
    return pratoMatches && tipoMatches && statusMatches;
  });

  exibirHistoricoFiltrado();
}

function exibirHistoricoFiltrado() {
  const div = document.getElementById("historico");

  if (historicoFiltrado.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>🔍</div>Nenhuma reserva corresponde aos filtros aplicados.</div>";
    return;
  }

  // Agrupar por data
  const grouped = {};
  historicoFiltrado.forEach(r => {
    if (!grouped[r.data]) grouped[r.data] = [];
    grouped[r.data].push(r);
  });

  // Montar HTML agrupado por data
  div.innerHTML = Object.keys(grouped)
    .sort((a, b) => b.localeCompare(a)) // Mais recente primeiro
    .map(d => {
      const items = grouped[d].map(r => `
        <div class="historico-item">
          <div>
            🍽️ <span class="tipo-refeicao tipo-${r.tipo}">
              ${r.tipo.replace(/_/g, " ")}${r.is_dieta ? " 🥗" : ""}
            </span> — ${r.menus?.prato || "-"}<br>
            💰 €${r.preco.toFixed(2)} | 📅 ${d}
          </div>
          <div class="${r.cancelada ? 'status-cancelada' : 'status-ativa'}">
            ${r.cancelada ? '❌ Cancelada' : '✅ Ativa'}
          </div>
        </div>
      `).join("");

      return `
        <div class="historico-card">
          <div class="historico-data">📅 ${d}</div>
          ${items}
        </div>
      `;
    })
    .join("");
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
  div.innerHTML = "⏳ A carregar saldos...";

  showLoading("⏳ Carregando saldos...");

  try {
    // Pega todas reservas não canceladas agrupadas por aluno
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome)")
      .eq("cancelada", false);

    if (error) {
      handleError(error, "Erro ao carregar saldos");
      div.innerHTML = "<i>❌ Erro ao carregar dados.</i>";
      return;
    }

    if (!data || data.length === 0) {
      todosSaldos = [];
      saldosFiltrados = [];
      div.innerHTML = "<i>✅ Sem dívidas.</i>";
      return;
    }

    // Agrupa por aluno em array
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

    // Converte para array e ordena
    todosSaldos = Object.values(saldsMap);
    saldosFiltrados = [...todosSaldos];
    ordenarSaldos('nome');

    // Renderizar
    renderizarSaldos();

    // Limpar input de pesquisa
    const inputPesquisa = document.getElementById("pesquisaSaldos");
    if(inputPesquisa) inputPesquisa.value = "";

  } catch (err) {
    handleError(err, "Erro ao carregar saldos");
    div.innerHTML = "<i>❌ Erro ao processar dados.</i>";
  } finally {
    hideLoading();
  }
}

// Renderizar lista de saldos
function renderizarSaldos() {
  const div = document.getElementById("listaSaldos");
  
  if(!saldosFiltrados || saldosFiltrados.length === 0) {
    div.innerHTML = "<i>❌ Nenhum saldo encontrado.</i>";
    return;
  }

  const html = saldosFiltrados
    .map(s => `
      <div class="saldo-linha" onclick="showSaldoAluno('${s.id}')">
        <span class="saldo-nome">${s.nome}</span>
        <span class="saldo-valor">€${Number(s.total).toFixed(2)}</span>
      </div>
    `)
    .join("");
  
  div.innerHTML = html;
  console.log(`📊 A mostrar ${saldosFiltrados.length} de ${todosSaldos.length} saldos`);
}

// Filtrar saldos por nome
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

// Ordenar saldos
function ordenarSaldos(tipo) {
  ordenacaoSaldos = tipo;
  
  if(tipo === 'nome') {
    saldosFiltrados.sort((a, b) => a.nome.localeCompare(b.nome));
  } else if(tipo === 'valor') {
    saldosFiltrados.sort((a, b) => b.total - a.total);
  }
  
  renderizarSaldos();
}

// Resetar filtros
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
    const { data: reservas, error } = await supabaseClient
      .from("reservas")
      .select("data, preco, alunos(nome)")
      .eq("aluno_id", alunoId)
      .eq("cancelada", false);

    if (error) {
      handleError(error, "Erro ao carregar histórico do aluno");
      return;
    }

    if (!reservas || reservas.length === 0) {
      document.getElementById("tituloAluno").innerText = "Sem registros";
      document.getElementById("valorTotal").innerText = "€0.00";
      document.getElementById("mesesDivida").innerHTML = "";
      return;
    }

    document.getElementById("tituloAluno").innerText = reservas[0].alunos.nome;

    let total = 0;
    const porMes = {};

    reservas.forEach(r => {
      total += Number(r.preco);
      const d = new Date(r.data);
      const key = `${d.getFullYear()}-${d.getMonth() + 1}`;
      porMes[key] = (porMes[key] || 0) + Number(r.preco);
    });

    document.getElementById("valorTotal").innerText = `€${total.toFixed(2)}`;

    const hoje = new Date();
    const mesesDivida = document.getElementById("mesesDivida");
    mesesDivida.innerHTML = "";

    // Mostrar TODOS os meses com dívida (não apenas os em atraso)
    const mesesOrdenados = Object.entries(porMes).sort((a, b) => {
      const [anoA, mesA] = a[0].split("-");
      const [anoB, mesB] = b[0].split("-");
      return new Date(anoB, mesB - 1) - new Date(anoA, mesA - 1); // Mais recente primeiro
    });

    mesesOrdenados.forEach(([key, valor]) => {
      const [ano, mes] = key.split("-");
      const limite = new Date(ano, mes, 15); // limite pagamento dia 15
      const emAtraso = hoje > limite;

      mesesDivida.innerHTML += `
        <div class="mes-divida ${emAtraso ? 'em-atraso' : ''}">
          <span>${mes}/${ano} ${emAtraso ? '⚠️ ATRASO' : ''}</span>
          <strong>€${valor.toFixed(2)}</strong>
          <button onclick="liquidarMes('${alunoId}', ${ano}, ${mes})">
            Liquidar mês
          </button>
        </div>
      `;
    });

    // Sempre mostrar botão de liquidar total (oferece opção de liquidar tudo de uma vez)
    const btnLiquidar = document.getElementById("btnLiquidarTotal");
    btnLiquidar.classList.remove("hidden");
    btnLiquidar.style.display = "block";
  } catch (err) {
    handleError(err, "Erro ao processar dados do aluno");
  } finally {
    hideLoading();
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
    // Chamar RPC para liquidar toda a dívida (sem restrições de período)
    const { data, error } = await supabaseClient.rpc('liquidar_divida_aluno', {
      p_aluno_id: alunoId,
      p_mes: null,
      p_ano: null
    });

    if (error) {
      console.error("❌ Erro ao liquidar dívida:", error);
      handleError(error, "Erro ao liquidar dívida");
      return;
    }

    if (data && !data.success) {
      mostrarErro("Erro", data.erro || "Erro ao liquidar dívida");
      return;
    }

    const registrosDeleted = data?.registros_deletados || 0;
    if (registrosDeleted === 0) {
      mostrarInfo("Sem dívida", "Este aluno não tem dívidas");
    } else {
      mostrarSucesso("Dívida Liquidada", `Dívida liquidada com sucesso! (${registrosDeleted} reserva${registrosDeleted !== 1 ? 's' : ''})`);
    }
    
    console.log("✅ Dívida liquidada para aluno:", alunoId);
    
    // Espera um pouco e volta aos saldos
    setTimeout(() => {
      showCantinaSaldos();
    }, 1500);
    
  } catch (err) {
    console.error("❌ Erro exception:", err);
    handleError(err, "Erro ao liquidar dívida");
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
  preencherSelectAno();
  preencherSelectMes();
}

/* =============================
   HELPERS DE NAVEGAÇÃO
============================== */
function esconderTodasPaginas() {
  document.querySelectorAll(".pagina, .container")
    .forEach(p => p.classList.add("hidden"));
}

function voltarCantina() {
  esconderTodasPaginas();
  show("paginaCantina");
}

/* =============================
   POPULAR SELECTS
============================== */
function preencherSelectAno() {
  const sel = getEl("relatorioAno");
  sel.innerHTML = "";
  const anoAtual = new Date().getFullYear();
  for (let a = anoAtual; a >= anoAtual - 3; a--) {
    sel.innerHTML += `<option value="${a}">${a}</option>`;
  }
}

function preencherSelectMes() {
  const sel = getEl("relatorioMes");
  sel.innerHTML = "";
  const meses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];
  meses.forEach((m, i) => sel.innerHTML += `<option value="${i + 1}">${m}</option>`);
}

/* =============================
   PREPARAR E GERAR RELATÓRIO
============================== */
function prepararRelatorio() {
  show("paginaRelatorio");

  const anoSelect = document.getElementById("relatorioAno");
  const mesSelect = document.getElementById("relatorioMes");

  const anoAtual = new Date().getFullYear();

  anoSelect.innerHTML = "";
  mesSelect.innerHTML = "";

  for (let i = anoAtual - 2; i <= anoAtual; i++) {
    anoSelect.innerHTML += `<option value="${i}">${i}</option>`;
  }

  const meses = [
    "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
    "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
  ];

  meses.forEach((mes, index) => {
    mesSelect.innerHTML += `<option value="${index+1}">${mes}</option>`;
  });
}

async function gerarRelatorioMensal() {
  const ano = Number(getEl("relatorioAno").value);
  const mes = Number(getEl("relatorioMes").value);

  showLoading("⏳ Gerando relatório...");

  try {
    // Query direta sem RPC
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome), data")
      .eq("cancelada", false);

    if (error) {
      mostrarErro("Erro", "Erro ao gerar relatório");
      console.error(error);
      return;
    }

    // Filtrar por mês/ano e agrupar
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

/* =============================
   EXPORTAR RELATÓRIO PARA EXCEL
============================== */
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

/* ==============================
   EXPORTAÇÕES
============================== */

async function exportarSaldosExcel() {
  console.log("📥 Iniciando exportação de saldos...");
  
  // Buscar todas as dívidas
  const { data, error } = await supabaseClient
    .from("reservas")
    .select("aluno_id, preco, alunos(nome)")
    .eq("cancelada", false);

  if (error) {
    mostrarErro("Erro", "Erro ao buscar saldos: " + error.message);
    console.error("❌ Erro ao buscar saldos", error);
    return;
  }

  if (!data || data.length === 0) {
    mostrarInfo("Sem Débitos", "Sem débitos para exportar.");
    return;
  }

  // Agrupar por aluno
  const saldos = {};
  data.forEach(r => {
    if (!saldos[r.aluno_id]) {
      saldos[r.aluno_id] = { nome: r.alunos.nome, total: 0, refeicoes: 0 };
    }
    saldos[r.aluno_id].total += Number(r.preco);
    saldos[r.aluno_id].refeicoes += 1;
  });

  // Preparar dados para exportar
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

  // Adicionar linha de total
  linhas.push([]);
  linhas.push(["TOTAL", refeicaoesTotal, totalGeral.toFixed(2)]);

  // Criar Excel
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);
  
  // Formatar colunas
  ws['!cols'] = [
    { wch: 25 },  // Aluno
    { wch: 12 },  // Refeições
    { wch: 15 }   // Total
  ];

  XLSX.utils.book_append_sheet(wb, ws, "Saldos");

  // Gerar nome do ficheiro com data
  const agora = new Date();
  const data_hora = `${agora.getDate()}-${String(agora.getMonth() + 1).padStart(2, '0')}-${agora.getFullYear()}_${String(agora.getHours()).padStart(2, '0')}h${String(agora.getMinutes()).padStart(2, '0')}`;
  const nomeFicheiro = `saldos_${data_hora}.xlsx`;
  
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

  // Buscar histórico completo do aluno
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

  // Preparar dados
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
      r.data,
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

  // Total
  linhas.push([]);
  linhas.push(["Total em Dívida:", "", "", totalAtivo.toFixed(2), "", ""]);

  // Criar Excel
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.aoa_to_sheet(linhas);

  // Formatar colunas
  ws['!cols'] = [
    { wch: 12 },  // Data
    { wch: 18 },  // Tipo
    { wch: 20 },  // Prato
    { wch: 10 },  // Preço
    { wch: 8 },   // Dieta
    { wch: 12 }   // Status
  ];

  XLSX.utils.book_append_sheet(wb, ws, "Histórico");

  // Nome do ficheiro
  const agora = new Date();
  const data_hora = `${agora.getDate()}-${String(agora.getMonth() + 1).padStart(2, '0')}-${agora.getFullYear()}`;
  const nomeFicheiro = `historico_${aluno.nome.replace(/\s+/g, '_')}_${data_hora}.xlsx`;

  XLSX.writeFile(wb, nomeFicheiro);
  console.log("✅ Ficheiro exportado:", nomeFicheiro);
  mostrarSucesso("Sucesso", `Ficheiro exportado: ${nomeFicheiro}`, 1500);
}

/* ==============================
   ALUNO — MENU POR DATA E RESERVAS
============================== */
async function showAlunoMenu() {
  show("alunoMenu");
  addBack("alunoMenu");
  
  showLoading("⏳ Carregando menus...");

  try {
    const hoje = new Date().toISOString().split("T")[0];

    // Buscar id do aluno
    const { data: aluno, error: errAluno } = await supabaseClient
      .from("alunos")
      .select("id")
      .eq("email", currentUser.email)
      .single();
    if (errAluno) { 
      handleError(errAluno, "Erro ao identificar aluno");
      return; 
    }

    // Buscar menus futuros
    const { data: menus, error: errMenus } = await supabaseClient
      .from("menus")
      .select("*")
      .gte("data", hoje)
      .order("data", { ascending: true });

    if (errMenus) {
      handleError(errMenus, "Erro ao carregar menus");
      return;
    }

    // Buscar reservas ativas
    const { data: reservas } = await supabaseClient
      .from("reservas")
      .select("menu_id")
      .eq("aluno_id", aluno.id)
      .eq("cancelada", false);

    const reservasAtivas = {};
    reservas?.forEach(r => reservasAtivas[r.menu_id] = true);

    if(!menus || menus.length === 0){
      listaAlunoMenu.innerHTML = "<i>✅ Sem menus disponíveis no momento.</i>";
      return;
    }

    // Agrupar menus por data
    const porData = {};
    menus.forEach(m => {
      if(!porData[m.data]) porData[m.data] = [];
      porData[m.data].push(m);
    });

    listaAlunoMenu.innerHTML = Object.entries(porData).map(([data, menusDia]) => `
      <div class="menu-dia">
        <h3 style="cursor:pointer" onclick="toggleDiaAluno('${data}')">📅 ${data}</h3>
        <div id="aluno-dia-${data}" class="hidden">
        ${menusDia.map(m => {
          if(reservasAtivas[m.id]) return "";

          // Almoço com opção dieta
          if(m.tipo === "almoco"){
            return `
              <div class="menu">
                🍽️ <b>Almoço</b> — ${m.prato} (${formatCurrency(m.preco)})
                <br>
                <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', false, 'almoco')">
                  Almoço normal
                </button>
                <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', true, 'almoco')">
                  🥗 Dieta
                </button>
              </div>
            `;
          }

          // Outras refeições
          return `
            <div class="menu">
              ${emojiTipo(m.tipo)} <b>${m.tipo.replace("_"," ")}</b>
              ${m.prato ? "— " + m.prato : ""}
              (${formatCurrency(m.preco)})
              <br>
              <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', false, '${m.tipo}')">
                Reservar
              </button>
            </div>
          `;
        }).join("")}
        </div>
      </div>
    `).join("");
  } catch (err) {
    handleError(err, "Erro ao carregar menus");
    listaAlunoMenu.innerHTML = "<i>❌ Erro ao processar dados.</i>";
  } finally {
    hideLoading();
  }
}

function toggleDiaAluno(data) {
  const el = document.getElementById(`aluno-dia-${data}`);
  if (el) el.classList.toggle("hidden");
}

/* ==============================
   ALUNO — RESERVAR MENU
============================== */
async function reservarAluno(menuId, preco, data, is_dieta, tipo) {
  showLoading("⏳ Processando reserva...");

  try {
    const { data: aluno, error: alunoError } = await supabaseClient
      .from("alunos")
      .select("id")
      .eq("email", currentUser.email)
      .single();

    if (alunoError) {
      handleError(alunoError, "Erro ao identificar aluno");
      return;
    }

    // Verificar dívida
    if(await alunoTemDivida(aluno.id)){
      mostrarMensagem("warning", "⚠️ Tens pagamentos em atraso. Não podes fazer reservas.");
      return;
    }

    // Inserir reserva
    const { error } = await supabaseClient
      .from("reservas")
      .insert({
        aluno_id: aluno.id,
        menu_id: menuId,
        data,
        preco,
        tipo,
        is_dieta,
        cancelada: false
      });

    if(error){
      handleError(error, "Erro ao criar reserva");
      return;
    }

    mostrarSucesso("Reserva Confirmada", "Reserva efetuada com sucesso!");
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
    const { data: aluno, error: errAluno } = await supabaseClient
      .from("alunos")
      .select("id")
      .eq("email", currentUser.email)
      .single();
    if(errAluno){ 
      handleError(errAluno, "Erro ao identificar aluno");
      return; 
    }

    const { data: reservas, error } = await supabaseClient
      .from("reservas")
      .select(`
        id,
        data,
        tipo,
        preco,
        cancelada,
        is_dieta,
        menus!inner(prato)
      `)
      .eq("aluno_id", aluno.id)
      .order("data", { ascending: true });

    if(error){ 
      handleError(error, "Erro ao carregar reservas");
      return; 
    }
    
    if(!reservas || reservas.length === 0){
      minhasReservas.innerHTML = "<i>✅ Sem reservas no momento.</i>";
      return;
    }

    const agora = new Date();
    const hoje = agora.toISOString().split("T")[0];
    const hora = agora.getHours();
    const minuto = agora.getMinutes();

    // Contar cancelamentos do mês apenas para almoço
    const cancelamentosMesAlmoco = {};
    reservas.forEach(r => {
      if(r.tipo === "almoco" && r.cancelada){
        const d = new Date(r.data);
        const key = `${d.getFullYear()}-${d.getMonth()+1}`;
        cancelamentosMesAlmoco[key] = (cancelamentosMesAlmoco[key] || 0) + 1;
      }
    });

    // Contar reservas/cancelamentos do mesmo dia
    const reservasPorMenu = {};
    reservas.forEach(r => {
      if(!reservasPorMenu[r.data]) reservasPorMenu[r.data] = {};
      reservasPorMenu[r.data][r.tipo] = reservasPorMenu[r.data][r.tipo] || [];
      reservasPorMenu[r.data][r.tipo].push(r);
    });

    minhasReservas.innerHTML = reservas.map(r => {
      const d = new Date(r.data);
      const keyMes = `${d.getFullYear()}-${d.getMonth()+1}`;

      let podeCancelar = false;
      let podeDieta = false;

      if(!r.cancelada){
        // Verifica horários e tipo de refeição
        if(r.tipo === "pequeno_almoco"){
          if(r.data > hoje || (r.data === hoje && hora < 23)) {
            podeCancelar = true; // sem limite mensal
          }
        }
        if(r.tipo === "almoco"){
          if(r.data > hoje || (r.data === hoje && hora < 9)) {
            const cancelamentosAtuais = cancelamentosMesAlmoco[keyMes] || 0;
            // Só permite 1 cancelamento por refeição/dia
            const reservasDia = reservasPorMenu[r.data][r.tipo] || [];
            const jaCancelou = reservasDia.filter(x=>x.cancelada).length;
            if(jaCancelou < 1 && cancelamentosAtuais < 2) podeCancelar = true;
            podeDieta = true; // só antes das 9h
          }
        }
        if(r.tipo === "jantar"){
          if(r.data > hoje || (r.data === hoje && hora < 12)) {
            podeCancelar = true; // sem limite mensal
          }
        }
      }

      // Mensagem 3º cancelamento apenas para almoço
      const cancelamentosAtuais = cancelamentosMesAlmoco[keyMes] || 0;
      const mostrarAvisoLimite = r.tipo === "almoco" && !podeCancelar && !r.cancelada && cancelamentosAtuais >= 2;

      return `
        <div class="menu">
          ${emojiTipo(r.tipo, r.is_dieta)}
          <b>${r.tipo === "almoco" && r.is_dieta ? "Almoço (Dieta)" : r.tipo.replace("_"," ")}</b>
          — ${r.data} ${r.menus?.prato ? "- " + r.menus.prato : ""}
          (${formatCurrency(r.preco)})
          <br>
          ${r.cancelada ? "❌ Cancelada" : ""}
          ${podeDieta && !r.is_dieta ? `<button onclick="trocarParaDieta('${r.id}', '${keyMes}')">🥗 Dieta</button>` : ""}
          ${podeCancelar ? `<button onclick="cancelarReserva('${r.id}', '${keyMes}')">Cancelar</button>` : ""}
          ${mostrarAvisoLimite ? `<small>⚠️ Limite de 2 cancelamentos/mês. Contacta a cantina: 914117705</small>` : ""}
        </div>
      `;
    }).join("");
  } catch (err) {
    handleError(err, "Erro ao processar reservas");
    minhasReservas.innerHTML = "<i>❌ Erro ao carregar dados.</i>";
  } finally {
    hideLoading();
  }
}

/* =============================
   LIQUIDAR MÊS ESPECÍFICO
============================== */
async function liquidarMes(alunoId, ano, mes) {
  if (!await confirmar("Liquidar Mês", `Deseja liquidar o mês ${mes}/${ano}?`)) {
    return;
  }

  showLoading("⏳ Liquidando mês...");

  try {
    // Chamar RPC para liquidar mês específico (sem restrições de período)
    const { data, error } = await supabaseClient.rpc('liquidar_divida_aluno', {
      p_aluno_id: alunoId,
      p_mes: mes,
      p_ano: ano
    });

    if (error) {
      console.error("❌ Erro ao liquidar mês:", error);
      handleError(error, "Erro ao liquidar mês");
      return;
    }

    if (data && !data.success) {
      mostrarErro("Erro", data.erro || "Erro ao liquidar mês");
      return;
    }

    const registrosDeleted = data?.registros_deletados || 0;
    if (registrosDeleted === 0) {
      mostrarInfo("Sem registros", `Nenhuma dívida encontrada para o mês ${mes}/${ano}`);
    } else {
      mostrarSucesso("Mês Liquidado", `Mês ${mes}/${ano} liquidado com sucesso! (${registrosDeleted} reserva${registrosDeleted !== 1 ? 's' : ''})`);
    }
    
    showSaldoAluno(alunoId);
  } catch (err) {
    console.error("❌ Erro exception:", err);
    handleError(err, "Erro ao liquidar mês");
  } finally {
    hideLoading();
  }
}

/* =============================
   CANCELAR RESERVA
============================== */
async function cancelarReserva(reservaId, keyMes) {
  if (!await confirmar("Cancelar Reserva", "Tem certeza que deseja cancelar esta reserva?")) {
    return;
  }

  showLoading("⏳ Cancelando reserva...");

  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ cancelada: true })
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

/* =============================
   TROCAR PARA DIETA
============================== */
async function trocarParaDieta(reservaId, keyMes) {
  if (!await confirmar("Mudar para Dieta", "Deseja trocar esta refeição para dieta?")) {
    return;
  }

  showLoading("⏳ Atualizando refeição...");

  try {
    const { error } = await supabaseClient
      .from("reservas")
      .update({ is_dieta: true })
      .eq("id", reservaId);

    if (error) {
      hideLoading();
      const mensagemErro = error?.message || "Erro ao atualizar para dieta";
      await mostrarErro("Erro ao Atualizar Refeição", mensagemErro);
      return;
    }

    mostrarSucesso("Refeição Alterada", "Refeição alterada para dieta!");
    showAlunoReservas();
  } catch (error) {
    hideLoading();
    const mensagemErro = error?.message || "Erro inesperado ao atualizar refeição";
    await mostrarErro("Erro", mensagemErro);
  } finally {
    hideLoading();
  }
}

/* ==============================
   HELPERS — TIPOS DE REFEIÇÃO
============================== */
function emojiTipo(tipo, is_dieta = false){
  if(tipo === "almoco" && is_dieta) return "🥗";
  if(tipo === "pequeno_almoco") return "🥐";
  if(tipo === "almoco") return "🍽️";
  if(tipo === "jantar") return "🌙";
  return "🍽️";
}

