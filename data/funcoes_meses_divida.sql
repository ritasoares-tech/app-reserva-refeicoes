-- Função para gerar meses em dívida (executada mensalmente)
CREATE OR REPLACE FUNCTION gerar_meses_em_divida(p_ano INTEGER DEFAULT NULL, p_mes INTEGER DEFAULT NULL)
RETURNS TABLE(
    total_alunos INTEGER,
    total_meses_gerados INTEGER,
    total_valor NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_ano INTEGER := COALESCE(p_ano, EXTRACT(YEAR FROM CURRENT_DATE));
    v_mes INTEGER := COALESCE(p_mes, EXTRACT(MONTH FROM CURRENT_DATE) - 1);
    v_total_alunos INTEGER := 0;
    v_total_meses INTEGER := 0;
    v_total_valor NUMERIC := 0;
BEGIN
    -- Validar mês (se for janeiro, usar dezembro do ano anterior)
    IF v_mes < 1 THEN
        v_mes := 12;
        v_ano := v_ano - 1;
    END IF;
    
    -- Gerar meses em dívida para todos os alunos com reservas não pagas
    INSERT INTO meses_em_divida (aluno_id, ano, mes, data, total)
    SELECT 
        r.aluno_id,
        v_ano,
        v_mes,
        MAKE_DATE(v_ano, v_mes, 1),
        COALESCE(SUM(r.preco), 0)
    FROM reservas r
    WHERE r.cancelada = FALSE
      AND EXTRACT(YEAR FROM r.data) = v_ano
      AND EXTRACT(MONTH FROM r.data) = v_mes
      AND NOT EXISTS (
          SELECT 1 FROM meses_em_divida md 
          WHERE md.aluno_id = r.aluno_id 
            AND md.ano = v_ano 
            AND md.mes = v_mes
      )
    GROUP BY r.aluno_id
    HAVING COALESCE(SUM(r.preco), 0) > 0;
    
    GET DIAGNOSTICS v_total_meses = ROW_COUNT;
    
    -- Calcular totais
    SELECT 
        COUNT(DISTINCT aluno_id),
        COALESCE(SUM(total), 0)
    INTO v_total_alunos, v_total_valor
    FROM meses_em_divida
    WHERE ano = v_ano AND mes = v_mes;
    
    RETURN QUERY SELECT v_total_alunos, v_total_meses, v_total_valor;
END;
$$;

-- Função para obter meses em dívida de um aluno
CREATE OR REPLACE FUNCTION obter_meses_divida_aluno(p_aluno_id UUID)
RETURNS TABLE(
    ano INTEGER,
    mes INTEGER,
    valor_total NUMERIC,
    em_atraso BOOLEAN,
    dias_atraso INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        md.ano,
        md.mes,
        md.total,
        (CURRENT_DATE > (MAKE_DATE(md.ano, md.mes, 15) + INTERVAL '15 days'))::BOOLEAN,
        GREATEST(0, EXTRACT(DAYS FROM CURRENT_DATE - (MAKE_DATE(md.ano, md.mes, 15) + INTERVAL '15 days')))::INTEGER
    FROM meses_em_divida md
    WHERE md.aluno_id = p_aluno_id
      AND NOT EXISTS (
          SELECT 1 FROM meses_liquidados ml 
          WHERE ml.aluno_id = md.aluno_id 
            AND ml.ano = md.ano 
            AND ml.mes = md.mes
      )
    ORDER BY md.ano DESC, md.mes DESC;
END;
$$;

-- Função para liquidar mês em dívida (trabalha diretamente com reservas)
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
    -- Calcular valor total das reservas não canceladas deste mês
    SELECT COALESCE(SUM(preco), 0)
    INTO v_valor_divida
    FROM reservas
    WHERE aluno_id = p_aluno_id
      AND EXTRACT(YEAR FROM data) = p_ano
      AND EXTRACT(MONTH FROM data) = p_mes
      AND cancelada = FALSE;
    
    -- Verificar se existe dívida
    IF v_valor_divida IS NULL OR v_valor_divida = 0 THEN
        RETURN QUERY SELECT FALSE, 'Não há dívida para este mês'::TEXT, 0::NUMERIC;
        RETURN;
    END IF;
    
    -- Cancelar as reservas do mês
    UPDATE reservas
    SET cancelada = TRUE
    WHERE aluno_id = p_aluno_id
      AND EXTRACT(YEAR FROM data) = p_ano
      AND EXTRACT(MONTH FROM data) = p_mes
      AND cancelada = FALSE;
    
    GET DIAGNOSTICS v_registros_liquidados = ROW_COUNT;
    
    -- Registrar em meses_liquidados para histórico (se a tabela existir)
    BEGIN
        INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
        VALUES (p_aluno_id, p_ano, p_mes, v_valor_divida, CURRENT_TIMESTAMP);
    EXCEPTION
        WHEN undefined_table THEN
            -- Tabela não existe, ignorar
            NULL;
        WHEN unique_violation THEN
            -- Registro já existe, ignorar
            NULL;
    END;
    
    RETURN QUERY SELECT TRUE, 
        format('%s reserva(s) liquidada(s) com sucesso', v_registros_liquidados)::TEXT, 
        v_valor_divida;
END;
$$;

-- Função para limpar meses em dívida antigos (opcional)
CREATE OR REPLACE FUNCTION limpar_meses_divida_antigos(p_meses INTEGER DEFAULT 24)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_registros_removidos INTEGER := 0;
BEGIN
    DELETE FROM meses_em_divida
    WHERE criado_em < CURRENT_TIMESTAMP - INTERVAL '1 month' * p_meses
      AND EXISTS (
          SELECT 1 FROM meses_liquidados ml 
          WHERE ml.aluno_id = meses_em_divida.aluno_id 
            AND ml.ano = meses_em_divida.ano 
            AND ml.mes = meses_em_divida.mes
      );
    
    GET DIAGNOSTICS v_registros_removidos = ROW_COUNT;
    RETURN v_registros_removidos;
END;
$$;
