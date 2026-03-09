// Funções da área da cantina (menus, reservas, histórico, saldos, relatórios)

function formatarData(dataISO) {
  if (!dataISO) return "";
  const [ano, mes, dia] = dataISO.split("-");
  return `${dia}/${mes}/${ano}`;
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
        }]);

      if (error) {
        handleError(error, "Erro ao criar menu");
        return;
      }

      mostrarSucesso("Menu Criado", "Menu criado com sucesso!");
      console.log("✅ Menu criado com sucesso", data);

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

    if (!menus?.length) {
      document.getElementById("listaMenus").innerHTML = `
        <div class="empty-state">
          <span class="empty-state-icon">📭</span>
          <p>Nenhum menu criado ainda</p>
        </div>`;
      return;
    }

    window.todosOsMenus = menus;
    renderMenusFiltrados();

  } catch (err) {
    handleError(err, "Erro ao carregar menus");
  } finally {
    hideLoading();
  }
}

function formatarTipoRefeicao(tipo) {

  const nomes = {
    pequeno_almoco: "Pequeno-almoço",
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

  // Agrupar por data
  const porDia = menusFiltrados.reduce((acc, m) => {
    if (!acc[m.data]) acc[m.data] = [];
    acc[m.data].push(m);
    return acc;
  }, {});

  const hoje = new Date();
  const hojeStr = hoje.toISOString().split("T")[0];
  const horaAtual = hoje.getHours();

  const diasEditaveis = [];
  const diasBloqueados = [];

  Object.entries(porDia)
    .sort(([a], [b]) => b.localeCompare(a))
    .forEach(([data, menusDia]) => {

      const dataObj = new Date(data);
      const diaSemana = dataObj.toLocaleDateString('pt-PT', { weekday: 'long' });
      const dataFormatada = dataObj.toLocaleDateString('pt-PT', {
        day: 'numeric',
        month: 'long',
        year: 'numeric'
      });

      const ehHoje = data === hojeStr;
      let diaTemEditaveis = false;

      // Ordenar por tipo: pequeno_almoco → almoco → jantar
        const ordemTipos = {
          pequeno_almoco: 1,
          almoco: 2,
          jantar: 3
        };

        menusDia.sort((a, b) => {
          return ordemTipos[a.tipo] - ordemTipos[b.tipo];
        });

      const menusHtml = menusDia.map(m => {

        const tipo = escapeHtml(m.tipo || "");
        const prato = escapeHtml(m.prato || "");
        const preco = Number(m.preco || 0).toFixed(2);

        const dataMenu = new Date(data);
        let podeEditar = false;

        if (dataMenu > new Date(hojeStr)) podeEditar = true;
        if (data === hojeStr && horaAtual < 9) podeEditar = true;

        if (podeEditar) diaTemEditaveis = true;

        return `
          <div class="menu-item">
            <div>
              <span style="font-size:22px;display:flex;align-items:center;">
                ${tipoEmoji(tipo)}
              </span>
              <div>
                <b>${formatarTipoRefeicao(tipo)}</b>
                ${prato ? `<span class="prato"> — ${prato}</span>` : ""}
                <span class="preco">€${preco}</span>
              </div>
            </div>

            ${
              podeEditar
                ? `
                <div class="menu-item-actions">
                  <button class="btn-edit" onclick="startEdit('${m.id}')">
                    ✏️ Editar
                  </button>
                  <button class="btn-delete" onclick="apagarMenu('${m.id}')">
                    🗑️ Apagar
                  </button>
                </div>
              `
                : `<div class="menu-item-bloqueado">⛔ Bloqueado</div>`
            }
          </div>
        `;
      }).join("");

      const diaHtml = `
        <div class="menu-dia">
          <h3 onclick="toggleDia('${data}')" class="menu-dia-titulo">
            <span>📅 ${diaSemana.charAt(0).toUpperCase() + diaSemana.slice(1)}, ${dataFormatada}</span>
            ${ehHoje ? `<span class="badge-hoje">Hoje</span>` : ""}
            <span class="chevron-${data}" style="margin-left:auto;transition:transform 0.3s;display:inline-block;transform:rotate(180deg);">▼</span>
          </h3>

          <div id="dia-${data}" class=hidden>
            ${menusHtml}
          </div>
        </div>
      `;

      if (diaTemEditaveis) {
        diasEditaveis.push(diaHtml);
      } else {
        diasBloqueados.push(diaHtml);
      }
    });

  container.innerHTML = `
    ${diasEditaveis.length ? `
      <div class="section">
        <div class="section-title">✏️ Menus que ainda podes alterar</div>
        ${diasEditaveis.join("")}
      </div>
    ` : ""}

    ${diasBloqueados.length ? `
      <div class="section">
        <div class="section-title">⛔ Menus já bloqueados</div>
        ${diasBloqueados.join("")}
      </div>
    ` : ""}
  `;
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
    const { error } = await supabaseClient
      .from("menus")
      .update({ prato: novoPrato })
      .eq("id", id);

    if (error) {
      handleError(error, "Erro ao atualizar prato");
      return;
    }

    mostrarSucesso("Prato Atualizado", "Prato atualizado com sucesso!");
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
    .eq("cancelada", false);

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

  div.innerHTML = `
    <div class="refeicao" onclick="verDetalheRefeicao('pequeno_almoco')">
      Pequeno-almoço — ${reservasHojePorTipo.pequeno_almoco.length}
    </div>

    <div class="refeicao" onclick="verDetalheRefeicao('almoco')">
      Almoço — ${reservasHojePorTipo.almoco.length}
    </div>

    <div class="refeicao" onclick="verDetalheRefeicao('dieta')">
      Dieta — ${reservasHojePorTipo.dieta.length}
    </div>

    <div class="refeicao" onclick="verDetalheRefeicao('jantar')">
      Jantar — ${reservasHojePorTipo.jantar.length}
    </div>
  `;
}

async function alunoTemDivida(alunoId) {
  try {
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

  div.innerHTML = `
    <h3>${formatarTipoRefeicao(tipo)}</h3>
    ${lista.map(r => `
      <div>
        👤 ${r.alunos.nome}
      </div>
    `).join("")}
    <br>
    <button onclick="showCantinaReservasHoje()">⬅️ Voltar às Reservas de Hoje</button>
  `;
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
  exibirHistoricoFiltrado()
}


function exibirHistoricoFiltrado() {
  const div = document.getElementById("historico");

  if (historicoFiltrado.length === 0) {
    div.innerHTML = "<div class='empty-state'><div class='empty-state-icon'>🔍</div>Nenhuma reserva corresponde aos filtros aplicados.</div>";
    return;
  }

  const grouped = {};
  historicoFiltrado.forEach(r => {
    if (!grouped[r.data]) grouped[r.data] = [];
    grouped[r.data].push(r);
  });

  div.innerHTML = Object.keys(grouped)
    .sort((a, b) => b.localeCompare(a))
    .map(d => {
      const items = grouped[d].map(r => `
        <div class="historico-item">
          <div>
            🍽️ <span class="tipo-refeicao tipo-${r.tipo}">
              ${r.tipo.replace(/_/g, " ")}${r.is_dieta ? " 🥗" : ""}
            </span> — ${r.menus?.prato || "-"}<br>
            💰 €${r.preco.toFixed(2)} | 📅 ${formatarData(d)}
          </div>
          <div class="${r.cancelada ? 'status-cancelada' : 'status-ativa'}">
            ${r.cancelada ? '❌ Cancelada' : '✅ Ativa'}
          </div>
        </div>
      `).join("");

      return `
        <div class="historico-card">
          <div class="historico-data">📅 ${formatarData(d)}</div>
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
  div.innerHTML = "⏳ A carregar valores em dívida...";

  showLoading("⏳ Carregando valores em dívida...");

  try {
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome)")
      .eq("cancelada", false);

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
        <span class="saldo-valor">€${Number(s.total).toFixed(2)}</span>
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
  document.getElementById("valorTotal").innerText = `€${total.toFixed(2)}`;

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
        <span>${nomeMes} ${item.ano} ${emAtraso ? '⚠️ ATRASO' : ''}</span>
        <strong>€${Number(item.valor).toFixed(2)}</strong>
        <button onclick="liquidarMes('${alunoId}', ${item.ano}, ${item.mes})">
          Liquidar mês
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
  document.getElementById("valorTotal").innerText = `€${total.toFixed(2)}`;

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

    console.log(`📊 Mês: ${nomeMes} ${item.ano}, Valor: €${item.valor}, Atraso: ${emAtraso}`);

    mesesDivida.innerHTML += `
      <div class="mes-divida ${emAtraso ? 'em-atraso' : ''}">
        <span>${nomeMes} ${item.ano} ${emAtraso ? '⚠️ ATRASO' : ''}</span>
        <strong>€${Number(item.valor).toFixed(2)}</strong>
        <button onclick="liquidarMes('${alunoId}', ${item.ano}, ${item.mes})">
          Liquidar mês
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
      .eq("cancelada", false);

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

    document.getElementById("valorTotal").innerText = `€${total.toFixed(2)}`;

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
          <span>${nomeMes} ${ano} ${emAtraso ? '⚠️ ATRASO' : ''}</span>
          <strong>€${valor.toFixed(2)}</strong>
          <button onclick="liquidarMes('${alunoId}', ${ano}, ${parseInt(mes)})">
            Liquidar mês
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
    // Para liquidar tudo, precisamos primeiro buscar todos os meses em dívida
    const { data: dividas, error: erroDividas } = await supabaseClient
      .rpc('obter_divida_por_mes', { p_aluno_id: alunoId });

    if (erroDividas) {
      console.error("❌ Erro ao buscar dívidas:", erroDividas);
      handleError(erroDividas, "Erro ao buscar dívidas");
      return;
    }

    if (!dividas || dividas.length === 0) {
      mostrarInfo("Sem dívida", "Este aluno não tem dívidas");
      return;
    }

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
        `Dívida liquidada com sucesso! (${mesesLiquidados} mês${mesesLiquidados !== 1 ? 'es' : ''}) - Valor: €${totalLiquidado.toFixed(2)}`);
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
          `${nomeMes} ${ano} liquidado com sucesso! Valor: €${Number(resultado.valor_liquidado).toFixed(2)}`);
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
  preencherSelectAno();
  preencherSelectMes();
}

function esconderTodasPaginas() {
  document.querySelectorAll(".pagina, .container")
    .forEach(p => p.classList.add("hidden"));
}

function voltarCantina() {
  esconderTodasPaginas();
  show("paginaCantina");
}

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
    const { data, error } = await supabaseClient
      .from("reservas")
      .select("aluno_id, preco, alunos(nome), data")
      .eq("cancelada", false);

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
    .eq("cancelada", false);

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

