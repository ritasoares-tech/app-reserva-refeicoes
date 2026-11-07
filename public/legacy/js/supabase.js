// =============================================================================
//  ⚠️  A APONTAR PARA A BASE DE DADOS DE TESTES  ⚠️
// =============================================================================
//  Projeto pessoal (mtbjlagltbkuqhunayxy), com 149 alunos inventados.
//  NAO e a base de dados da escola. Ver docs/db-teste-local.md.
//
//  ISTO FICA ASSIM DURANTE TODO O RAMO `development`. E deliberado.
//  As migracoes 001 e 002 ainda nao foram aplicadas ao projeto da escola, por
//  isso este codigo ligado a escola falha de propria - pede colunas que la
//  ainda nao existem. Commits a apontar para a escola dariam a entender que o
//  ramo esta cheio de erros, quando o que falta e correr o SQL.
//
//  >>> A TROCA E O ULTIMO COMMIT ANTES DO MERGE/PR PARA `main`. <<<
//  Nao antes. Nunca depois. Depois de trocar, confirmar com:
//      git diff public/legacy/js/supabase.js
//  e recarregar a app: o aviso vermelho na consola tem de DESAPARECER.
//
//  ORIGINAL (projeto da escola) - descomentar e apagar o bloco de testes:
//    const SUPABASE_URL = "https://fghsgknistganzbuxrjt.supabase.co";
//    const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnaHNna25pc3RnYW56YnV4cmp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNDUzNjcsImV4cCI6MjA4MzgyMTM2N30.6NPsu-DeQuEpjnHptdZTgsYmtx7mQ5STs8zbwYgIoYY";
// =============================================================================

// --- TESTES (trocar no ultimo commit antes do merge) -------------------------
const SUPABASE_URL = "https://mtbjlagltbkuqhunayxy.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im10YmpsYWdsdGJrdXFodW5heXh5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3MzQwNjIsImV4cCI6MjEwMDMxMDA2Mn0.y1sV57xZBOWrpkEB7xkIzVpDiMZVbAvOXczxBg46yvE";
const _BD_ESCOLA_REF = "fghsgknistganzbuxrjt";   // para o aviso na consola
// -----------------------------------------------------------------------------

// Aguarda o supabase estar carregado e cria a instância
function initSupabase() {
  if(typeof supabase === 'undefined') {
    console.error("Supabase library not loaded");
    return;
  }
  
  const client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  window.supabaseClient = client;
  console.log("✅ Supabase inicializado com sucesso");

  // Deixar sempre visivel a que base de dados a app esta ligada. Sem isto e
  // facil passar uma hora a testar contra o projeto errado sem dar por nada.
  if (typeof _BD_ESCOLA_REF !== "undefined" && !SUPABASE_URL.includes(_BD_ESCOLA_REF)) {
    console.warn(
      "%c⚠️ BASE DE DADOS DE TESTES ⚠️",
      "background:#b30000;color:#fff;font-weight:bold;padding:2px 6px;border-radius:3px;"
    );
    console.warn("Ligado a:", SUPABASE_URL, "- dados inventados, nao e a escola.");
  }
}

// Se o supabase já estiver disponível, inicializa imediatamente
if(typeof supabase !== 'undefined') {
  initSupabase();
} else {
  // Caso contrário, aguarda até estar disponível
  const checkInterval = setInterval(() => {
    if(typeof supabase !== 'undefined') {
      clearInterval(checkInterval);
      initSupabase();
    }
  }, 50);
  
  // Timeout de 5 segundos
  setTimeout(() => {
    clearInterval(checkInterval);
    console.error("⚠️ Supabase não carregou no tempo esperado");
  }, 5000);
}
