const cantinaId = localStorage.getItem("user_id");

async function carregarMenus() {
    const { data: menus } = await supabase.from("menus").select("*").order("data");

    const container = document.getElementById("menus");
    container.innerHTML = "";

    menus.forEach(menu => {
        const div = document.createElement("div");
        div.innerHTML = `
            <input type="date" value="${menu.data}" onchange="atualizarMenu(${menu.id}, this.value)">
            <input type="text" value="${menu.prato}" onchange="atualizarMenu(${menu.id}, null, this.value)">
            <input type="number" value="${menu.preco}" step="0.01" onchange="atualizarMenu(${menu.id}, null, null, this.value)">
        `;
        container.appendChild(div);
    });
}

async function atualizarMenu(id, data, prato, preco) {
    const updates = {};
    if (data) updates.data = data;
    if (prato) updates.prato = prato;
    if (preco) updates.preco = parseFloat(preco);

    await supabase.from("menus").update(updates).eq("id", id);
}

async function adicionarMenu() {
    await supabase.from("menus").insert([{ data: new Date().toISOString().slice(0,10), prato: "Novo prato", preco: 0 }]);
    carregarMenus();
}

async function verReservas() {
    const { data: reservas } = await supabase.from("reservas").select("aluno_id, menus(data, prato, preco), alunos(nome)").join("menus", "menu_id", "id").join("alunos", "aluno_id", "id");
    const container = document.getElementById("reservas");
    container.innerHTML = "";
    reservas.forEach(r => {
        const div = document.createElement("div");
        div.innerText = `${r.alunos.nome} reservou ${r.menus.prato} em ${r.menus.data} (€${r.menus.preco})`;
        container.appendChild(div);
    });
}

window.onload = function() {
    carregarMenus();
    verReservas();
}
