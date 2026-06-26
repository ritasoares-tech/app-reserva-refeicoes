-- Tabela para armazenar notificações aos alunos
CREATE TABLE IF NOT EXISTS public.notificacoes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  aluno_id uuid NOT NULL,
  tipo TEXT NOT NULL, -- 'menu_alterado', 'reserva_cancelada', etc
  titulo TEXT NOT NULL,
  mensagem TEXT NOT NULL,
  dados JSONB DEFAULT NULL, -- armazenar dados adicionais (menu_id, prato_antigo, prato_novo, etc)
  lida BOOLEAN DEFAULT FALSE,
  criada_em TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  lida_em TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  CONSTRAINT notificacoes_pkey PRIMARY KEY (id),
  CONSTRAINT notificacoes_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id)
);

-- Índice para queries rápidas
CREATE INDEX IF NOT EXISTS notificacoes_aluno_id_idx ON public.notificacoes(aluno_id);
CREATE INDEX IF NOT EXISTS notificacoes_lida_idx ON public.notificacoes(lida);
CREATE INDEX IF NOT EXISTS notificacoes_criada_em_idx ON public.notificacoes(criada_em DESC);

-- Função para notificar alunos quando um menu é alterado
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
BEGIN
  -- Obter nome do mês e dia
  v_dia := EXTRACT(DAY FROM p_data_menu)::INTEGER;
  v_mes_nome := v_nomesMeses[EXTRACT(MONTH FROM p_data_menu)::INTEGER];
  
  -- Inserir notificação para cada aluno com reserva neste menu
  INSERT INTO notificacoes (aluno_id, tipo, titulo, mensagem, dados)
  SELECT 
    r.aluno_id,
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
  FROM reservas r
  WHERE r.menu_id = p_menu_id
    AND r.cancelamento_tipo IS NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN v_count;
END;
$$;

-- Função para marcar notificação como lida
CREATE OR REPLACE FUNCTION marcar_notificacao_lida(p_notificacao_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE notificacoes
  SET lida = TRUE, lida_em = CURRENT_TIMESTAMP
  WHERE id = p_notificacao_id;
  
  RETURN TRUE;
END;
$$;

-- Função para marcar todas as notificações de um aluno como lidas
CREATE OR REPLACE FUNCTION marcar_todas_notificacoes_lidas(p_aluno_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE notificacoes
  SET lida = TRUE, lida_em = CURRENT_TIMESTAMP
  WHERE aluno_id = p_aluno_id AND lida = FALSE;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Função para obter notificações não lidas de um aluno
CREATE OR REPLACE FUNCTION obter_notificacoes_nao_lidas(p_aluno_id UUID)
RETURNS TABLE(
  id UUID,
  tipo TEXT,
  titulo TEXT,
  mensagem TEXT,
  dados JSONB,
  criada_em TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    n.id,
    n.tipo,
    n.titulo,
    n.mensagem,
    n.dados,
    n.criada_em
  FROM notificacoes n
  WHERE n.aluno_id = p_aluno_id
    AND n.lida = FALSE
  ORDER BY n.criada_em DESC;
END;
$$;

-- Função para obter todas as notificações de um aluno (com limite)
CREATE OR REPLACE FUNCTION obter_notificacoes_aluno(
  p_aluno_id UUID,
  p_limite INTEGER DEFAULT 20
)
RETURNS TABLE(
  id UUID,
  tipo TEXT,
  titulo TEXT,
  mensagem TEXT,
  dados JSONB,
  lida BOOLEAN,
  criada_em TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    n.id,
    n.tipo,
    n.titulo,
    n.mensagem,
    n.dados,
    n.lida,
    n.criada_em
  FROM notificacoes n
  WHERE n.aluno_id = p_aluno_id
  ORDER BY n.criada_em DESC
  LIMIT p_limite;
END;
$$;

-- Função para apagar notificações antigas (após o dia do menu passar)
-- Apaga notificações de menus que já passaram há mais de 7 dias
CREATE OR REPLACE FUNCTION apagar_notificacoes_antigas()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- Apagar notificações onde a data do menu nos dados é anterior a 7 dias atrás
  DELETE FROM notificacoes
  WHERE 
    -- Notificações de menu alterado
    (tipo = 'menu_alterado' AND dados->>'data' < CURRENT_DATE - INTERVAL '7 days')
    OR
    -- Notificações criadas há mais de 30 dias (para outros tipos)
    (criada_em < CURRENT_TIMESTAMP - INTERVAL '30 days');
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN v_count;
END;
$$;

-- Função para apagar notificações de um aluno específico (opcional)
CREATE OR REPLACE FUNCTION apagar_notificacoes_aluno(p_aluno_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  DELETE FROM notificacoes
  WHERE aluno_id = p_aluno_id;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
