-- =============================================================================
-- Verificacao da 010 - tres tipos de aluno
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 010.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
-- So le. O ponto 4 le os saldos como a cantina; comparar com o
-- valores-referencia.sql corrido ANTES de aplicar a 010.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) tipo_contrato / tem_contrato / alunos',
       string_agg(coalesce(tipo_contrato, 'NULL') || '/' || tem_contrato || ' ' || n, ', ' ORDER BY tipo_contrato),
       'so completo/true, parcial/true, sem/false; nunca NULL',
       bool_and(   (tipo_contrato = 'completo' AND tem_contrato)
                OR (tipo_contrato = 'parcial'  AND tem_contrato)
                OR (tipo_contrato = 'sem'      AND NOT tem_contrato))
FROM (SELECT tipo_contrato, tem_contrato, count(*) AS n FROM alunos GROUP BY 1, 2) s;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) colunas de alunos que o authenticated pode alterar',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '(nenhuma)'), 'email, nome',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '') = 'email, nome'
FROM information_schema.column_privileges
WHERE table_name = 'alunos' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) definir_contrato_aluno (antiga) e definir_tipo_contrato (nova)',
       coalesce(string_agg(proname || ' prosecdef=' || prosecdef || ' ' || coalesce(proacl::text, '(PUBLIC)'), '; '
                           ORDER BY proname), '(nenhuma)'),
       'so definir_tipo_contrato, prosecdef=true, sem anon=',
       count(*) = 1 AND bool_and(proname = 'definir_tipo_contrato' AND prosecdef
                                 AND proacl IS NOT NULL AND proacl::text NOT LIKE '%anon=%')
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname IN ('definir_contrato_aluno', 'definir_tipo_contrato');

DO $$
DECLARE v_cantina uuid; v_saldos text; v_erro text;
BEGIN
  SELECT id INTO v_cantina FROM cantina ORDER BY id LIMIT 1;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_cantina::text, true);
    SELECT count(*) || ' alunos / ' || coalesce(sum(total), 0) INTO v_saldos FROM saldos_por_aluno();
  EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('4) saldos_por_aluno (como a cantina)', coalesce(v_erro, v_saldos),
     'igual ao valores-referencia.sql de antes da 010', NULL);
END $$;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
