const userId = localStorage.getItem("user_id");

async function carregarMenus() {
    const { data: menus } = await supabase.from("menus").select("*").order("data");

    const container = document.getElementById("menus");
    container.innerHTML = "";

    menus.forEach(menu => {
        const div = document.createElement("div");
        div.innerHTML = `
            <strong>${menu.data} - ${menu.prato}</strong> | €${menu.preco.toFixed(2)}
            <button onclick="reservar(${menu.id}, ${menu.preco})">Reservar</button>
        `;
        container.appendChild(div);
    });
}

async function reservar(menuId, preco) {
    await supabase.from("reservas").insert([{ aluno_id: userId, menu_id: menuId }]);
    alert("Reserva feita com sucesso!");
    carregarSaldo();
}

async function cancelar(menuId) {
    await supabase.from("reservas")
        .delete()
        .eq("aluno_id", userId)
        .eq("menu_id", menuId);
    alert("Reserva cancelada!");
    carregarSaldo();
}

async function carregarSaldo() {
    const { data: reservas } = await supabase.from("reservas").select("menu_id, menus(preco)").eq("aluno_id", userId);
    let total = 0;
    reservas.forEach(r => { total += r.menus.preco; });
    document.getElementById("saldo").innerText = "Saldo: €" + total.toFixed(2);
}

// Chamar ao carregar a página
window.onload = function() {
    carregarMenus();
    carregarSaldo();
}
