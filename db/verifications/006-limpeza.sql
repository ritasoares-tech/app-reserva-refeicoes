-- =============================================================================
-- Verificacao da 006 - limpeza
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 006.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto P3.3 corre a purga COMO A CANTINA (o script faz-se passar pela
-- primeira conta da tabela cantina, so dentro de si proprio) e DESFAZ o que ela
-- apagar. Nao fica nada apagado.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

-- ---------------------------------------------------------------- PASSO 1 ---
-- Se aparecer alguma, o DROP dessa errou os tipos e foi um no-op silencioso.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P1.1) funcoes de relatorio antigas que sobreviveram',
       coalesce(string_agg(proname || '(' || pg_get_function_identity_arguments(oid) || ')', ', '), '(nenhuma)'),
       '(nenhuma)', count(*) = 0
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('aluno_tem_divida_mes', 'gerar_relatorio_mensal', 'resumo_mensal',
                  'listar_meses_disponiveis', 'pode_gerar_relatorio', 'verificar_mes_com_dados');

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P1.2) numero de funcoes em public', count(*)::text,
       '29 no fim da 006 (34 antes, 27 depois do passo 1)', count(*) = 29
FROM pg_proc WHERE pronamespace = 'public'::regnamespace;

-- ---------------------------------------------------------------- PASSO 2 ---
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P2) politicas em meses_em_divida', string_agg(cmd || ' | ' || policyname, '; ' ORDER BY cmd, policyname),
       'so as duas de SELECT; nem DELETE nem INSERT',
       count(*) = 2 AND bool_and(cmd = 'SELECT')
FROM pg_policies WHERE schemaname = 'public' AND tablename = 'meses_em_divida';

-- ----------------------------------------------------------- PASSOS 3 e 4 ---
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P3.1) purgar_reservas_liquidadas e relatorio_mensal (prosecdef)',
       string_agg(proname || ' ' || prosecdef, ', ' ORDER BY proname),
       'purgar_reservas_liquidadas true, relatorio_mensal true',
       string_agg(proname || ' ' || prosecdef, ', ' ORDER BY proname) = 'purgar_reservas_liquidadas true, relatorio_mensal true'
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname IN ('purgar_reservas_liquidadas', 'relatorio_mensal');

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P3.2) EXECUTE: ' || proname, coalesce(proacl::text, '(por omissao: PUBLIC)'),
       'sem anon= e sem =X/postgres (o PUBLIC)',
       proacl IS NOT NULL AND proacl::text NOT LIKE '%anon=%' AND proacl::text !~ '(^\{|,)=X'
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname IN ('purgar_reservas_liquidadas', 'relatorio_mensal');

-- A purga tem de respeitar o rasto: nao pode dar erro de chave estrangeira.
DO $$
DECLARE v_cantina uuid; v_linhas int; v_apagadas text; v_erro text;
BEGIN
  SELECT id INTO v_cantina FROM cantina ORDER BY id LIMIT 1;
  IF v_cantina IS NULL THEN
    v_erro := 'sem conta na tabela cantina';
  ELSE
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_cantina::text, true);
      SELECT count(*), string_agg(p::text, ' ') INTO v_linhas, v_apagadas
      FROM purgar_reservas_liquidadas((CURRENT_DATE - INTERVAL '1 year')::date) p;
      RAISE EXCEPTION USING ERRCODE = 'VRF01';        -- desfazer a purga
    EXCEPTION
      WHEN SQLSTATE 'VRF01' THEN NULL;
      WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
    END;
    PERFORM set_config('request.jwt.claim.sub', '', true);
  END IF;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('P3.3) purga como a cantina, ha um ano (desfeita)',
     coalesce(v_erro, v_linhas || ' linha: ' || v_apagadas),
     '1 linha (apagadas, preservadas), sem erro de chave estrangeira',
     v_erro IS NULL AND v_linhas = 1);
END $$;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
