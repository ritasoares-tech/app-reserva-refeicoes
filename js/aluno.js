// Funções da área do aluno (menus, reservas e ações sobre reservas)

/* ==============================
   ALUNO — MENU POR DATA E RESERVAS
============================== */
function formatarData(dataISO) {
  if (!dataISO) return "";
  const [ano, mes, dia] = dataISO.split("-");
  return `${dia}/${mes}/${ano}`;
}
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

    let menus = menusRaw || [];

    const filtroDataInput = document.getElementById("filtroDataAluno");
    const dataSelecionada = filtroDataInput?.value;

    if (dataSelecionada) {
      menus = menus.filter(m => m.data === dataSelecionada);
    }

    const { data: reservas } = await supabaseClient
      .from("reservas")
      .select("menu_id")
      .eq("aluno_id", aluno.id)
      .is("cancelamento_tipo", null);

    const reservasAtivas = {};
    reservas?.forEach(r => reservasAtivas[r.menu_id] = true);

    const listaAlunoMenuEl = document.getElementById("listaAlunoMenu");

    if(!menus || menus.length === 0){
      listaAlunoMenuEl.innerHTML = "<i>✅ Sem menus disponíveis no momento.</i>";
      return;
    }

    const agora = new Date();
    const hojeAtualizado = agora.toISOString().split("T")[0];
    const hora = agora.getHours();

    const porData = {};
    menus.forEach(m => {
      if(!porData[m.data]) porData[m.data] = [];
      porData[m.data].push(m);
    });

    listaAlunoMenuEl.innerHTML = Object.entries(porData).map(([data, menusDia]) => `
      <div class="menu-dia">
        <h3 style="cursor:pointer" onclick="toggleDiaAluno('${data}')">📅 ${formatarData(data)}</h3>
        <div id="aluno-dia-${data}" class="hidden">
        ${menusDia.map(m => {
          if(reservasAtivas[m.id]) return "";

          // Verificar se passou o horário limite
          let podeReservar = true;
          let mensagemHorario = "";
          
          if (data === hojeNow) {
            if (m.tipo === "almoco" && hora >= 9) {
              podeReservar = false;
              mensagemHorario = " ⏰ (Prazo ultrapassado - até às 9:00)";
            } else if (m.tipo === "jantar" && hora >= 12) {
              podeReservar = false;
              mensagemHorario = " ⏰ (Prazo ultrapassado - até às 12:00)";
            } else if (m.tipo === "pequeno_almoco" && hora >= 23) {
              podeReservar = false;
              mensagemHorario = " ⏰ (Prazo ultrapassado - até às 23:00)";
            }
          }

          if(m.tipo === "almoco"){
            return `
              <div class="menu">
                🍽️ <b>Almoço</b> — ${m.prato} (${formatCurrency(m.preco)})${mensagemHorario}
                <br>
                ${podeReservar ? `
                  <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', false, 'almoco')">
                    Almoço normal
                  </button>
                  <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', true, 'almoco')">
                    🥗 Dieta
                  </button>
                ` : `
                  <button style="opacity:0.5; cursor:not-allowed;" disabled>
                    ❌ Prazo expirado
                  </button>
                `}
              </div>
            `;
          }

          return `
            <div class="menu">
              ${emojiTipo(m.tipo)} <b>${m.tipo.replace("_"," ")}</b>
              ${m.prato ? "— " + m.prato : ""}
              (${formatCurrency(m.preco)})${mensagemHorario}
              <br>
              ${podeReservar ? `
                <button onclick="reservarAluno('${m.id}', ${m.preco}, '${m.data}', false, '${m.tipo}')">
                  Reservar
                </button>
              ` : `
                <button style="opacity:0.5; cursor:not-allowed;" disabled>
                  ❌ Prazo expirado
                </button>
              `}
            </div>
          `;
        }).join("")}
        </div>
      </div>
    `).join("");
  } catch (err) {
    handleError(err, "Erro ao carregar menus");
    const listaAlunoMenuEl = document.getElementById("listaAlunoMenu");
    if (listaAlunoMenuEl) {
      listaAlunoMenuEl.innerHTML = "<i>❌ Erro ao processar dados.</i>";
    }
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
  try {
    // Verificar horário limite para fazer reserva
    const agora = new Date();
    const hoje = agora.toISOString().split("T")[0];
    const hora = agora.getHours();

    // Se for para hoje, verificar horário limite
    if (data === hoje) {
      let horarioLimite = 23; // padrão
      
      if (tipo === "pequeno_almoco") {
        horarioLimite = 23; // até às 23:00
      } else if (tipo === "almoco") {
        horarioLimite = 9; // até às 9:00
      } else if (tipo === "jantar") {
        horarioLimite = 12; // até às 12:00
      }

      if (hora >= horarioLimite) {
        const nomesTipo = {
          "pequeno_almoco": "Pequeno-almoço",
          "almoco": "Almoço",
          "jantar": "Jantar"
        };
        const nomeTipo = nomesTipo[tipo] || tipo;
        mostrarErro(
          "Horário Limite Atingido",
          `Não podes fazer reserva de ${nomeTipo} após as ${horarioLimite}:00. Tenta novamente amanhã.`
        );
        return;
      }
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
    
    if(!reservas || reservas.length === 0){
      minhasReservas.innerHTML = "<i>✅ Sem reservas no momento.</i>";
      return;
    }

    const agora = new Date();
    const hoje = agora.toISOString().split("T")[0];
    const hora = agora.getHours();

    const cancelamentosUsuarioMesAlmoco = {};
    reservas.forEach(r => {
      if(r.tipo === "almoco" && r.cancelamento_tipo === 'user'){
        const d = new Date(r.data);
        const key = `${d.getFullYear()}-${d.getMonth()+1}`;
        cancelamentosUsuarioMesAlmoco[key] = (cancelamentosUsuarioMesAlmoco[key] || 0) + 1;
      }
    });

    const reservasPorMenu = {};
    reservas.forEach(r => {
      if(!reservasPorMenu[r.data]) reservasPorMenu[r.data] = {};
      reservasPorMenu[r.data][r.tipo] = reservasPorMenu[r.data][r.tipo] || [];
      reservasPorMenu[r.data][r.tipo].push(r);
    });

    minhasReservas.innerHTML = `
      <div style="margin-bottom:20px;">
        <h3 style="color:#333; margin-bottom:12px;">📋 Suas Reservas</h3>
        ${reservas.map(r => {
          const d = new Date(r.data);
          const keyMes = `${d.getFullYear()}-${d.getMonth()+1}`;

          const estaAtiva = r.cancelamento_tipo === null || r.cancelamento_tipo === 'reactivated';
          let podeCancelar = false;
          let podeDieta = false;

          if(estaAtiva){
            if(r.tipo === "pequeno_almoco"){
              if(r.data > hoje || (r.data === hoje && hora < 23)) {
                podeCancelar = true;
              }
            }
            if(r.tipo === "almoco"){
              if(r.data > hoje || (r.data === hoje && hora < 9)) {
                const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
                const reservasDia = reservasPorMenu[r.data][r.tipo] || [];
                const jaCancelou = reservasDia.filter(x=>x.cancelamento_tipo === 'user').length;
                if(jaCancelou < 1 && cancelamentosAtuais < 2) podeCancelar = true;
                podeDieta = true;
              }
            }
            if(r.tipo === "jantar"){
              if(r.data > hoje || (r.data === hoje && hora < 12)) {
                podeCancelar = true;
              }
            }
          }

          const cancelamentosAtuais = cancelamentosUsuarioMesAlmoco[keyMes] || 0;
          const mostrarAvisoLimite = r.tipo === "almoco" && !podeCancelar && estaAtiva && cancelamentosAtuais >= 2;

          let statusBg = "#f8f9fa";
          let statusBorda = "#007bff";
          let statusTexto = "✅ Ativa";
          let statusCor = "#28a745";

          if(r.cancelamento_tipo === 'user'){
            statusBg = "#f8d7da";
            statusBorda = "#dc3545";
            statusTexto = "❌ Cancelada por si";
            statusCor = "#dc3545";
          } else if(r.cancelamento_tipo === 'payment'){
            statusBg = "#e7d4f5";
            statusBorda = "#6f42c1";
            statusTexto = "💳 Paga (liquidação do mês)";
            statusCor = "#6f42c1";
          } else if(r.cancelamento_tipo === 'reactivated'){
            statusBg = "#d1ecf1";
            statusBorda = "#0c5460";
            statusTexto = "🔄 Reativada";
            statusCor = "#0c5460";
          }

          return `
            <div style="background:${statusBg}; padding:12px; margin-bottom:10px; border-radius:6px; border-left:4px solid ${statusBorda};">
              <div style="display:flex; justify-content:space-between; align-items:start; gap:12px;">
                <div style="flex:1;">
                  <div style="display:flex; align-items:center; gap:8px; margin-bottom:4px;">
                    <span style="font-size:20px;">${emojiTipo(r.tipo, r.is_dieta)}</span>
                    <span style="font-weight:bold; color:#333;">${r.tipo === "almoco" && r.is_dieta ? "Almoço (Dieta)" : r.tipo.replace("_"," ")}</span>
                    <span style="color:#666; font-size:13px;">${formatarData(r.data)}</span>
                  </div>
                  <div style="color:#666; font-size:13px; margin-left:28px;">
                    ${r.menus?.prato ? `${r.menus.prato}` : "-"}
                    <span style="float:right; color:#007bff; font-weight:bold;">€${formatCurrency(r.preco).replace("€", "")}</span>
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
              ${r.cancelamento_tipo === 'user' && r.data > hoje ? `
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
        }).join("")}
      </div>
    `;
  } catch (err) {
    handleError(err, "Erro ao processar reservas");
    minhasReservas.innerHTML = "<i>❌ Erro ao carregar dados.</i>";
  } finally {
    hideLoading();
  }
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


