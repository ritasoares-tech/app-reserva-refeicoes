// Substitui com os teus dados do Supabase
const SUPABASE_URL = "https://fghsgknistganzbuxrjt.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnaHNna25pc3RnYW56YnV4cmp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNDUzNjcsImV4cCI6MjA4MzgyMTM2N30.6NPsu-DeQuEpjnHptdZTgsYmtx7mQ5STs8zbwYgIoYY";

// Aguarda o supabase estar carregado e cria a instância
function initSupabase() {
  if(typeof supabase === 'undefined') {
    console.error("Supabase library not loaded");
    return;
  }
  
  const client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  window.supabaseClient = client;
  window.supabase = client;
  console.log("✅ Supabase inicializado com sucesso");
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
