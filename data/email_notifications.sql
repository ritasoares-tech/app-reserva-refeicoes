-- Função para enviar email de notificação usando Supabase Auth
-- Nota: Requer que o Supabase Auth esteja configurado para enviar emails

CREATE OR REPLACE FUNCTION enviar_email_notificacao(
  p_email TEXT,
  p_assunto TEXT,
  p_mensagem TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  -- Esta função usa o pg_cron ou Supabase Edge Functions para enviar emails
  -- Para implementação simples, vamos usar o Supabase Auth via RPC
  
  -- Nota: Supabase não tem função nativa para enviar emails arbitrários via SQL
  -- A melhor abordagem é usar Supabase Edge Functions
  
  -- Por agora, vamos apenas registrar que o email deveria ser enviado
  -- Em produção, isso seria substituído por uma Edge Function
  
  RAISE NOTICE 'Email deveria ser enviado para: %, Assunto: %', p_email, p_assunto;
  
  RETURN TRUE;
END;
$$;

-- Função atualizada para notificar alunos quando um menu é alterado
-- Agora inclui envio de email
CREATE OR REPLACE FUNCTION notificar_menu_alterado(
  p_menu_id UUID,
  p_prato_antigo TEXT,
  p_prato_novo TEXT,
  p_data_menu DATE,
  p_tipo_menu TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER := 0;
  v_nomesMeses TEXT[] := ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
  v_mes_nome TEXT;
  v_dia INTEGER;
  v_aluno RECORD;
BEGIN
  -- Obter nome do mês e dia
  v_dia := EXTRACT(DAY FROM p_data_menu)::INTEGER;
  v_mes_nome := v_nomesMeses[EXTRACT(MONTH FROM p_data_menu)::INTEGER];
  
  -- Para cada aluno com reserva neste menu
  FOR v_aluno IN 
    SELECT DISTINCT r.aluno_id, a.email, a.nome
    FROM reservas r
    INNER JOIN alunos a ON r.aluno_id = a.id
    WHERE r.menu_id = p_menu_id
      AND r.cancelamento_tipo IS NULL
  LOOP
    -- Inserir notificação na tabela
    INSERT INTO notificacoes (aluno_id, tipo, titulo, mensagem, dados)
    VALUES (
      v_aluno.aluno_id,
      'menu_alterado',
      format('Menu Alterado - %s, %s de %s', 
        CASE WHEN p_tipo_menu = 'almoco' THEN 'Almoço'
             WHEN p_tipo_menu = 'pequeno_almoco' THEN 'Pequeno-almoço'
             WHEN p_tipo_menu = 'jantar' THEN 'Jantar'
             ELSE p_tipo_menu END,
        v_dia,
        v_mes_nome),
      format('A cantina alterou o menu que reservou. Antes: "%s". Agora: "%s"', 
        COALESCE(p_prato_antigo, '(não especificado)'),
        COALESCE(p_prato_novo, '(não especificado)')),
      jsonb_build_object(
        'menu_id', p_menu_id,
        'tipo', p_tipo_menu,
        'data', p_data_menu,
        'prato_antigo', p_prato_antigo,
        'prato_novo', p_prato_novo
      )
    );
    
    -- Enviar email (será implementado via Edge Function)
    -- Por agora, apenas registra no log
    RAISE NOTICE 'Email de notificação para: % (Menu alterado: %s -> %s)', 
      v_aluno.email, 
      COALESCE(p_prato_antigo, '(não especificado)'),
      COALESCE(p_prato_novo, '(não especificado)');
    
    v_count := v_count + 1;
  END LOOP;
  
  RETURN v_count;
END;
$$;
