
-- Função para liquidar dívida de um aluno (total ou mensal)
CREATE OR REPLACE FUNCTION liquidar_divida_aluno(
    p_aluno_id UUID,
    p_mes INTEGER DEFAULT NULL,
    p_ano INTEGER DEFAULT NULL
)
RETURNS TABLE(
    success BOOLEAN,
    message TEXT,
    registros_deletados INTEGER,
    valor_liquidado NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_registros_deletados INTEGER := 0;
    v_valor_liquidado NUMERIC := 0;
    v_mensagem TEXT := 'Operação realizada com sucesso';
    v_registros_antes INTEGER := 0;
BEGIN
    -- Validar parâmetros
    IF p_aluno_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Aluno não informado'::TEXT, 0::INTEGER, 0::NUMERIC;
        RETURN;
    END IF;
    
    -- Liquidar dívida total (todos os meses)
    IF p_mes IS NULL OR p_ano IS NULL THEN
        -- Calcular valor total E contagem antes de deletar
        SELECT 
            COALESCE(SUM(preco), 0),
            COALESCE(COUNT(*), 0)
        INTO v_valor_liquidado, v_registros_deletados
        FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE;
        
        -- Deletar todas as reservas não canceladas do aluno
        DELETE FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE;
        
        -- Registrar liquidação total
        IF v_registros_deletados > 0 THEN
            INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
            SELECT 
                p_aluno_id,
                EXTRACT(YEAR FROM CURRENT_DATE),
                EXTRACT(MONTH FROM CURRENT_DATE),
                v_valor_liquidado,
                CURRENT_TIMESTAMP;
        END IF;
        
        v_mensagem := 'Dívida total liquidada com sucesso';
    
    -- Liquidar dívida de um mês específico
    ELSE
        -- Validar mês e ano
        IF p_mes < 1 OR p_mes > 12 THEN
            RETURN QUERY SELECT FALSE, 'Mês inválido'::TEXT, 0::INTEGER, 0::NUMERIC;
            RETURN;
        END IF;
        
        IF p_ano < 2000 OR p_ano > EXTRACT(YEAR FROM CURRENT_DATE) + 1 THEN
            RETURN QUERY SELECT FALSE, 'Ano inválido'::TEXT, 0::INTEGER, 0::NUMERIC;
            RETURN;
        END IF;
        
        -- DEBUG: Contar todas as reservas do aluno antes
        SELECT COUNT(*) INTO v_registros_antes
        FROM reservas
        WHERE aluno_id = p_aluno_id AND cancelada = FALSE;
        
        -- Calcular valor E contagem do mês antes de deletar
        SELECT 
            COALESCE(SUM(preco), 0),
            COALESCE(COUNT(*), 0)
        INTO v_valor_liquidado, v_registros_deletados
        FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE
          AND EXTRACT(YEAR FROM data) = p_ano
          AND EXTRACT(MONTH FROM data) = p_mes;
        
        -- DEBUG: Log para debug (via RAISE NOTICE)
        RAISE NOTICE 'DEBUG: Aluno %, Mês %/%, Registros antes: %, Registros mês: %, Valor: %', 
            p_aluno_id, p_mes, p_ano, v_registros_antes, v_registros_deletados, v_valor_liquidado;
        
        -- Deletar reservas do mês específico
        DELETE FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE
          AND EXTRACT(YEAR FROM data) = p_ano
          AND EXTRACT(MONTH FROM data) = p_mes;
        
        -- Registrar liquidação mensal
        IF v_registros_deletados > 0 THEN
            INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
            VALUES (p_aluno_id, p_ano, p_mes, v_valor_liquidado, CURRENT_TIMESTAMP);
        END IF;
        
        v_mensagem := format('Dívida do mês %s/%s liquidada com sucesso', p_mes, p_ano);
    END IF;
    
    -- Correção: success deve ser TRUE quando registros foram deletados OU valor_liquidado > 0
    DECLARE
        v_success BOOLEAN := (v_registros_deletados > 0 OR v_valor_liquidado > 0);
    BEGIN
        -- Retornar resultado
        RETURN QUERY SELECT 
            v_success AS success,
            v_mensagem::TEXT,
            v_registros_deletados::INTEGER,
            v_valor_liquidado::NUMERIC;
    END;
END;
$$;

-- Função para obter dívida agrupada por mês
CREATE OR REPLACE FUNCTION obter_divida_por_mes(p_aluno_id UUID)
RETURNS TABLE(
    ano INTEGER,
    mes INTEGER,
    valor NUMERIC,
    em_atraso BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        EXTRACT(YEAR FROM r.data)::INTEGER,
        EXTRACT(MONTH FROM r.data)::INTEGER,
        SUM(r.preco)::NUMERIC,
        (CURRENT_DATE > MAKE_DATE(EXTRACT(YEAR FROM r.data)::INTEGER, EXTRACT(MONTH FROM r.data)::INTEGER, 15))::BOOLEAN
    FROM reservas r
    WHERE r.aluno_id = p_aluno_id
      AND r.cancelada = FALSE
    GROUP BY EXTRACT(YEAR FROM r.data), EXTRACT(MONTH FROM r.data)
    ORDER BY EXTRACT(YEAR FROM r.data) DESC, EXTRACT(MONTH FROM r.data) DESC;
END;
$$;

-- Função para verificar se aluno tem dívida em determinado mês
CREATE OR REPLACE FUNCTION aluno_tem_divida_mes(p_aluno_id UUID, p_ano INTEGER, p_mes INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE
          AND EXTRACT(YEAR FROM data) = p_ano
          AND EXTRACT(MONTH FROM data) = p_mes
    );
END;
$$;

-- Trigger para atualizar meses_em_divida quando há alterações nas reservas
CREATE OR REPLACE FUNCTION atualizar_meses_divida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Se for uma nova reserva ou atualização para não cancelada
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NOT NEW.cancelada) THEN
        -- Inserir ou atualizar registro na tabela meses_em_divida
        BEGIN
            INSERT INTO meses_em_divida (aluno_id, ano, mes, data, total)
            VALUES (
                NEW.aluno_id,
                EXTRACT(YEAR FROM NEW.data)::INTEGER,
                EXTRACT(MONTH FROM NEW.data)::INTEGER,
                NEW.data,
                NEW.preco
            );
        EXCEPTION
            WHEN unique_violation THEN
                -- Registro já existe, atualizar
                UPDATE meses_em_divida 
                SET total = meses_em_divida.total + NEW.preco,
                    data = NEW.data
                WHERE aluno_id = NEW.aluno_id
                  AND ano = EXTRACT(YEAR FROM NEW.data)::INTEGER
                  AND mes = EXTRACT(MONTH FROM NEW.data)::INTEGER;
        END;
    
    -- Se for cancelamento de reserva
    ELSIF TG_OP = 'UPDATE' AND NEW.cancelada AND NOT OLD.cancelada THEN
        -- Atualizar total na tabela meses_em_divida
        UPDATE meses_em_divida 
        SET total = total - NEW.preco
        WHERE aluno_id = NEW.aluno_id
          AND ano = EXTRACT(YEAR FROM NEW.data)::INTEGER
          AND mes = EXTRACT(MONTH FROM NEW.data)::INTEGER;
          
        -- Remover registro se total ficar zero ou negativo
        DELETE FROM meses_em_divida 
        WHERE aluno_id = NEW.aluno_id
          AND ano = EXTRACT(YEAR FROM NEW.data)::INTEGER
          AND mes = EXTRACT(MONTH FROM NEW.data)::INTEGER
          AND total <= 0;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Função de EMERGÊNCIA para liquidar dívida (usa UPDATE em vez de DELETE)
CREATE OR REPLACE FUNCTION liquidar_divida_aluno_emergencia(
    p_aluno_id UUID,
    p_mes INTEGER DEFAULT NULL,
    p_ano INTEGER DEFAULT NULL
)
RETURNS TABLE(
    success BOOLEAN,
    message TEXT,
    registros_atualizados INTEGER,
    valor_liquidado NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_registros_atualizados INTEGER := 0;
    v_valor_liquidado NUMERIC := 0;
    v_mensagem TEXT := 'Operação realizada com sucesso';
BEGIN
    -- Validar parâmetros
    IF p_aluno_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Aluno não informado'::TEXT, 0::INTEGER, 0::NUMERIC;
        RETURN;
    END IF;
    
    -- Liquidar dívida total (todos os meses)
    IF p_mes IS NULL OR p_ano IS NULL THEN
        -- Calcular valor total E contagem antes de atualizar
        SELECT 
            COALESCE(SUM(preco), 0),
            COALESCE(COUNT(*), 0)
        INTO v_valor_liquidado, v_registros_atualizados
        FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE;
        
        -- ATUALIZAR (não deletar) todas as reservas não canceladas do aluno
        UPDATE reservas
        SET cancelada = TRUE, 
            data_cancelamento = CURRENT_TIMESTAMP
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE;
        
        -- Registrar liquidação total
        IF v_registros_atualizados > 0 THEN
            INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
            SELECT 
                p_aluno_id,
                EXTRACT(YEAR FROM CURRENT_DATE),
                EXTRACT(MONTH FROM CURRENT_DATE),
                v_valor_liquidado,
                CURRENT_TIMESTAMP;
        END IF;
        
        v_mensagem := 'Dívida total liquidada com sucesso (emergência)';
    
    -- Liquidar dívida de um mês específico
    ELSE
        -- Validar mês e ano
        IF p_mes < 1 OR p_mes > 12 THEN
            RETURN QUERY SELECT FALSE, 'Mês inválido'::TEXT, 0::INTEGER, 0::NUMERIC;
            RETURN;
        END IF;
        
        IF p_ano < 2000 OR p_ano > EXTRACT(YEAR FROM CURRENT_DATE) + 1 THEN
            RETURN QUERY SELECT FALSE, 'Ano inválido'::TEXT, 0::INTEGER, 0::NUMERIC;
            RETURN;
        END IF;
        
        -- Calcular valor E contagem do mês antes de atualizar
        SELECT 
            COALESCE(SUM(preco), 0),
            COALESCE(COUNT(*), 0)
        INTO v_valor_liquidado, v_registros_atualizados
        FROM reservas
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE
          AND EXTRACT(YEAR FROM data) = p_ano
          AND EXTRACT(MONTH FROM data) = p_mes;
        
        -- ATUALIZAR (não deletar) reservas do mês específico
        UPDATE reservas
        SET cancelada = TRUE, 
            data_cancelamento = CURRENT_TIMESTAMP
        WHERE aluno_id = p_aluno_id
          AND cancelada = FALSE
          AND EXTRACT(YEAR FROM data) = p_ano
          AND EXTRACT(MONTH FROM data) = p_mes;
        
        -- Registrar liquidação mensal
        IF v_registros_atualizados > 0 THEN
            INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
            VALUES (p_aluno_id, p_ano, p_mes, v_valor_liquidado, CURRENT_TIMESTAMP);
        END IF;
        
        v_mensagem := format('Dívida do mês %s/%s liquidada com sucesso (emergência)', p_mes, p_ano);
    END IF;
    
    -- Retornar resultado
    RETURN QUERY SELECT 
        (v_registros_atualizados > 0 OR v_valor_liquidado > 0) AS success,
        v_mensagem::TEXT,
        v_registros_atualizados::INTEGER,
        v_valor_liquidado::NUMERIC;
END;
$$;
