// Funções da área do aluno (menus, reservas e ações sobre reservas)

/* ==============================
   ALUNO — MENU POR DATA E RESERVAS
============================== */

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

    const filtroTipoSelect = document.getElementById("filtroTipoAluno");
    const tipoFiltro = filtroTipoSelect ? filtroTipoSelect.value : "";

    let menus = menusRaw || [];
    if (tipoFiltro) {
      if (tipoFiltro === "dieta") {
        menus = menus.filter(m => m.tipo === "almoco");
      } else {
        menus = menus.filter(m => m.tipo === tipoFiltro);
      }
    }

    const { data: reservas } = await supabaseClient
      .from("reservas")
      .select("menu_id")
      .eq("aluno_id", aluno.id)
      .eq("cancelada", false);

    const reservasAtivas = {};
    reservas?.forEach(r => reservasAtivas[r.menu_id] = true);

    const listaAlunoMenuEl = document.getElementById("listaAlunoMenu");

    if(!menus || menus.length === 0){
      listaAlunoMenuEl.innerHTML = "<i>✅ Sem menus disponíveis no momento.</i>";
      return;
    }

    const porData = {};
    menus.forEach(m => {
      if(!porData[m.data]) porData[m.data] = [];
      porData[m.data].push(m);
    });

    listaAlunoMenuEl.innerHTML = Object.entries(porData).map(([data, menusDia]) => `
      <div class="menu-dia">
        <h3 style="cursor:pointer" onclick="toggleDiaAluno('${data}')">📅 ${data}</h3>
        <div id="aluno-dia-${data}" class="hidden">
        ${menusDia.map(m => {
          if(reservasAtivas[m.id]) return "";

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
        cancelada: false
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

    const cancelamentosMesAlmoco = {};
    reservas.forEach(r => {
      if(r.tipo === "almoco" && r.cancelada){
        const d = new Date(r.data);
        const key = `${d.getFullYear()}-${d.getMonth()+1}`;
        cancelamentosMesAlmoco[key] = (cancelamentosMesAlmoco[key] || 0) + 1;
      }
    });

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
        if(r.tipo === "pequeno_almoco"){
          if(r.data > hoje || (r.data === hoje && hora < 23)) {
            podeCancelar = true;
          }
        }
        if(r.tipo === "almoco"){
          if(r.data > hoje || (r.data === hoje && hora < 9)) {
            const cancelamentosAtuais = cancelamentosMesAlmoco[keyMes] || 0;
            const reservasDia = reservasPorMenu[r.data][r.tipo] || [];
            const jaCancelou = reservasDia.filter(x=>x.cancelada).length;
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
          ${mostrarAvisoLimite ? `<button class="btn-medium danger" style="margin-top:8px;" onclick="mostrarLimiteCancelamentos()">⚠️ Já atingiste o limite de cancelamentos</button>` : ""}
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

function mostrarLimiteCancelamentos() {
  mostrarErro(
    "Limite de Cancelamentos",
    "Já atingiste o limite de 2 cancelamentos de almoço neste mês. Para situações excecionais, fala com a cantina (914117705)."
  );
}

