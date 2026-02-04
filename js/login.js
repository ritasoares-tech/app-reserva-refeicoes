async function login() {
    const email = document.getElementById("email").value;
    const password = document.getElementById("password").value;

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
        alert("Erro no login: " + error.message);
        return;
    }

    // Verificar role no DB
    const { data: alunoData } = await supabase
        .from("alunos")
        .select("*")
        .eq("id", data.user.id);

    if (alunoData && alunoData.length > 0) {
        // É aluno
        window.location.href = "aluno.html";
        localStorage.setItem("user_id", data.user.id);
        localStorage.setItem("role", "aluno");
    } else {
        // Verificar cantina
        const { data: cantinaData } = await supabase
            .from("cantina")
            .select("*")
            .eq("id", data.user.id);

        if (cantinaData && cantinaData.length > 0) {
            // É cantina
            window.location.href = "cantina.html";
            localStorage.setItem("user_id", data.user.id);
            localStorage.setItem("role", "cantina");
        } else {
            alert("Usuário não encontrado em nenhum grupo.");
        }
    }
}
