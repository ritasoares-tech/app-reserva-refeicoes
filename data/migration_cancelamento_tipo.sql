-- Migração: Adicionar campo para diferenciar tipo de cancelamento
-- Problema: liquidar_mes_divida marca reservas como cancelada=TRUE, perdendo contexto se foi utilizador ou pagamento

-- Adicionar coluna cancelamento_tipo
ALTER TABLE public.reservas
ADD COLUMN cancelamento_tipo TEXT DEFAULT NULL;

-- Comentário para documentação
COMMENT ON COLUMN public.reservas.cancelamento_tipo IS 'Tipo de cancelamento: NULL (ativa), user (cancelada pelo utilizador), payment (cancelada por pagamento/liquidação), reactivated (reativada após cancelamento por engano)';

-- Recriar função liquidar_mes_divida para usar cancelamento_tipo em vez de apenas cancelada
CREATE OR REPLACE FUNCTION liquidar_mes_divida(
    p_aluno_id UUID,
    p_ano INTEGER,
    p_mes INTEGER
)
RETURNS TABLE(
    success BOOLEAN,
    message TEXT,
    valor_liquidado NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_valor_divida NUMERIC := 0;
    v_registros_liquidados INTEGER := 0;
BEGIN
    -- Calcular valor total das reservas não liquidadas deste mês
    SELECT COALESCE(SUM(preco), 0)
    INTO v_valor_divida
    FROM reservas
    WHERE aluno_id = p_aluno_id
      AND EXTRACT(YEAR FROM data) = p_ano
      AND EXTRACT(MONTH FROM data) = p_mes
      AND (cancelamento_tipo IS NULL OR cancelamento_tipo = 'user');
    
    -- Verificar se existe dívida
    IF v_valor_divida IS NULL OR v_valor_divida = 0 THEN
        RETURN QUERY SELECT FALSE, 'Não há dívida para este mês'::TEXT, 0::NUMERIC;
        RETURN;
    END IF;
    
    -- Marcar as reservas do mês como liquidadas (não deletar!)
    UPDATE reservas
    SET cancelamento_tipo = 'payment'
    WHERE aluno_id = p_aluno_id
      AND EXTRACT(YEAR FROM data) = p_ano
      AND EXTRACT(MONTH FROM data) = p_mes
      AND (cancelamento_tipo IS NULL OR cancelamento_tipo = 'user');
    
    GET DIAGNOSTICS v_registros_liquidados = ROW_COUNT;
    
    -- Registrar em meses_liquidados para histórico
    BEGIN
        INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
        VALUES (p_aluno_id, p_ano, p_mes, v_valor_divida, CURRENT_TIMESTAMP);
    EXCEPTION
        WHEN undefined_table THEN
            NULL;
        WHEN unique_violation THEN
            NULL;
    END;
    
    RETURN QUERY SELECT TRUE, 
        format('%s reserva(s) liquidada(s) com sucesso', v_registros_liquidados)::TEXT, 
        v_valor_divida;
END;
$$;

-- Função para o utilizador reativar uma reserva cancelada por engano
CREATE OR REPLACE FUNCTION reativar_reserva_cancelada(
    p_reserva_id UUID
)
RETURNS TABLE(
    success BOOLEAN,
    message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_reserva_tipo TEXT;
    v_aluno_id UUID;
    v_data DATE;
BEGIN
    -- Buscar informações da reserva
    SELECT cancelamento_tipo, aluno_id, data
    INTO v_reserva_tipo, v_aluno_id, v_data
    FROM reservas
    WHERE id = p_reserva_id;
    
    IF v_aluno_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Reserva não encontrada'::TEXT;
        RETURN;
    END IF;
    
    -- Só pode reativar se foi cancelada por utilizador, não por pagamento
    IF v_reserva_tipo != 'user' THEN
        RETURN QUERY SELECT FALSE, 'Esta reserva não pode ser reativada'::TEXT;
        RETURN;
    END IF;
    
    -- Reativar a reserva
    UPDATE reservas
    SET cancelamento_tipo = 'reactivated'
    WHERE id = p_reserva_id;
    
    RETURN QUERY SELECT TRUE, 'Reserva reativada com sucesso'::TEXT;
END;
$$;

-- Função para contar cancelamentos "reais" (por utilizador) do mês
CREATE OR REPLACE FUNCTION contar_cancelamentos_usuario(
    p_aluno_id UUID,
    p_ano INTEGER,
    p_mes INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM reservas
    WHERE aluno_id = p_aluno_id
      AND EXTRACT(YEAR FROM data) = p_ano
      AND EXTRACT(MONTH FROM data) = p_mes
      AND cancelamento_tipo = 'user';
    
    RETURN COALESCE(v_count, 0);
END;
$$;
