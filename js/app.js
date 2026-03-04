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
let todosSaldos = [];
let saldosFiltrados = [];
let ordenacaoSaldos = 'nome';

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

function emojiTipo(tipo, is_dieta = false){
  if(tipo === "almoco" && is_dieta) return "🥗";
  if(tipo === "pequeno_almoco") return "🥐";
  if(tipo === "almoco") return "🍽️";
  if(tipo === "jantar") return "🌙";
  return "🍽️";
}

async function getAlunoAtual() {
  if (!currentUser || !currentUser.email) {
    throw new Error("Utilizador não identificado");
  }

  const { data, error } = await supabaseClient
    .from("alunos")
    .select("id, nome, email")
    .eq("email", currentUser.email)
    .single();

  if (error || !data) {
    throw error || new Error("Aluno não encontrado");
  }

  return data;
}

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
  loadingElement.className = 'loading-modal';
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
                        'modal-button-secondary';html += `<button class="modal-button ${btnClass}" data-resolve="${btn.resolve}">${btn.text}</button>`;
        
      });
    }
    
    html += `</div>`;
    modal.innerHTML = html;
    overlay.appendChild(modal);
    document.body.appendChild(overlay);
    
    // Resolver modal
    modal.querySelectorAll('.modal-button').forEach(button => {
    button.addEventListener('click', () => {
    const value = button.dataset.resolve === 'true';
    overlay.remove();
    resolve(value);
    });
  });
    
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
  return new Promise((resolve) => {

    let resolvido = false;

    showModal({
      icon: '✅',
      title: titulo,
      message: mensagem,
      type: 'success',
      buttons: [
        { text: 'Fechar', type: 'success', resolve: true }
      ],
      canClose: false
    }).then((value) => {
      if (!resolvido) {
        resolvido = true;
        resolve(value);
      }
    });

    if (timeout > 0) {
      setTimeout(() => {
        const overlay = document.querySelector('.modal-overlay');
        if (overlay) overlay.remove();

        if (!resolvido) {
          resolvido = true;
          resolve(true); // 🔥 resolve quando fecha automaticamente
        }
      }, timeout);
    }

  });
}

function modalEditarPrato(pratoAtual) {
  return new Promise((resolve) => {
    const existingOverlay = document.querySelector('.modal-overlay');
    if (existingOverlay) existingOverlay.remove();

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';

    const modal = document.createElement('div');
    modal.className = 'modal-content modal-warning';

    modal.innerHTML = `
      <div class="modal-header">
        <span>✏️</span>
        <div class="modal-title">Editar Prato</div>
      </div>

      <div class="modal-message">
        <input 
          type="text" 
          id="modalInputPrato" 
          value="${pratoAtual || ""}"
          style="width:100%;padding:10px;border-radius:8px;border:1px solid #ccc;margin-top:10px;"
        />
      </div>

      <div class="modal-buttons">
        <button class="modal-button modal-button-secondary" data-action="cancel">
          Cancelar
        </button>
        <button class="modal-button modal-button-primary" data-action="save">
          Guardar
        </button>
      </div>
    `;

    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    const input = modal.querySelector("#modalInputPrato");
    input.focus();

    modal.querySelectorAll(".modal-button").forEach(btn => {
      btn.addEventListener("click", () => {
        const action = btn.dataset.action;

        if (action === "cancel") {
          overlay.remove();
          resolve(null);
        }

        if (action === "save") {
          const valor = input.value.trim();
          overlay.remove();
          resolve(valor);
        }
      });
    });

    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) {
        overlay.remove();
        resolve(null);
      }
    });
  });
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
    // Menu da Cantina
    elements.cantinaMenuSelect.classList.remove("hidden");
    elements.cantinaMenuTitle.innerText = "Área da Cantina";
    elements.cantinButtons.innerHTML = `
      <button class="btn-full" onclick="showCriarMenu()">Criar Menus</button>
      <button class="btn-full" onclick="showMenusCriados()">Menus Criados</button>
      <button class="btn-full" onclick="showCantinaReservasHoje()">Reservas do Dia</button>
      <button class="btn-full" onclick="showCantinaHistorico()">Histórico</button>
      <button class="btn-full" onclick="showCantinaSaldos()">Saldos em Dívida</button>
    `;
  }
}

/* ==============================
   SALDO ALUNO
============================== */
async function saldo(){
  if(role !== "aluno") return;

  try {
    const aluno = await getAlunoAtual();

    const { data: reservas, error } = await supabaseClient
      .from("reservas")
      .select("preco, data")
      .eq("aluno_id", aluno.id)
      .eq("cancelada", false);

    if(error){
      handleError(error, "Erro ao buscar reservas");
      return;
    }

    if(!reservas || reservas.length === 0){
      elements.saldoAluno.innerHTML = "Sem valores em dívida.";
      return;
    }

    let total = 0;
    const porMes = {};

    reservas.forEach(r => {
      total += Number(r.preco);

      const d = new Date(r.data);
      const key = `${d.getFullYear()}-${d.getMonth()+1}`;
      porMes[key] = (porMes[key] || 0) + Number(r.preco);
    });

    const nomesMeses = [
      "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
      "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"
    ];

    const hoje = new Date();
    const anoAtual = hoje.getFullYear();
    const mesAtual = hoje.getMonth();

    const mesesOrdenados = Object.entries(porMes).sort((a,b)=>{
      const [anoA, mesA] = a[0].split("-");
      const [anoB, mesB] = b[0].split("-");
      return new Date(anoB, mesB-1) - new Date(anoA, mesA-1);
    });

    let html = "";

    mesesOrdenados.forEach(([key, valor]) => {
      const [ano, mes] = key.split("-");
      const anoNum = Number(ano);
      const mesNum = Number(mes) - 1;

      const nomeMes = nomesMeses[mesNum];

      const mesCorrente = anoNum === anoAtual && mesNum === mesAtual;
      const mesAnterior = new Date(anoNum, mesNum) < new Date(anoAtual, mesAtual);

      let etiqueta = "";
      if(mesCorrente) etiqueta = " (Mês Atual)";
      else if(mesAnterior) etiqueta = "⚠️ (Em Dívida)";
      else etiqueta = "📅";

      html += `
        <div style="margin-bottom:6px;">
          <b>${nomeMes} ${ano}</b> ${etiqueta}
          <span style="float:right">${formatCurrency(valor)}</span>
        </div>
      `;
    });

    html += `
      <hr style="margin:8px 0;">
      <div>
        <b>Total em Dívida:</b>
        <span style="float:right">${formatCurrency(total)}</span>
      </div>
    `;

    elements.saldoAluno.innerHTML = html;

  } catch (err) {
    handleError(err, "Erro ao calcular saldo");
  }
}
