-- Políticas RLS para a tabela notificacoes

-- Habilitar RLS na tabela (se ainda não estiver)
ALTER TABLE public.notificacoes ENABLE ROW LEVEL SECURITY;

-- Política para permitir inserção de notificações pela função RPC (service role)
-- Esta política permite que a função notificar_menu_alterado crie notificações
CREATE POLICY "Permitir inserção via função RPC"
ON public.notificacoes
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Política para permitir que alunos leiam suas próprias notificações
CREATE POLICY "Alunos podem ler suas notificações"
ON public.notificacoes
FOR SELECT
TO authenticated
USING (aluno_id = auth.uid());

-- Política para permitir que alunos marquem suas notificações como lidas
CREATE POLICY "Alunos podem atualizar suas notificações"
ON public.notificacoes
FOR UPDATE
TO authenticated
USING (aluno_id = auth.uid())
WITH CHECK (aluno_id = auth.uid());

-- Política para permitir que a função RPC atualize notificações (marcar como lida)
CREATE POLICY "Permitir atualização via função RPC"
ON public.notificacoes
FOR UPDATE
TO authenticated
WITH CHECK (true);
