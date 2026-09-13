-- =============================================================================
-- Verificacao da 004 - agendamento (pg_cron e avisos de pagamento)
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 004.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto 4 inventa uma divida do mes passado a tres alunos e gera os avisos,
-- para ver o comportamento. E DESFEITO dentro do proprio script - nao fica
-- divida nenhuma nem notificacao nenhuma.
--
-- ATENCAO: a 011 muda o dia do avisos-atraso de 11 para 9 e junta uma quarta
-- tarefa. O esperado aqui e o de logo a seguir a 004.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) extensao pg_cron', coalesce(max(extname || ' ' || extversion), '(nao instalada)'),
       'pg_cron (versao do projeto)', count(*) = 1
FROM pg_extension WHERE extname = 'pg_cron';

WITH j AS (
  SELECT jobname || ' | ' || schedule || ' | ' || active || ' | ' || btrim(command) AS j
  FROM cron.job WHERE jobname IN ('fechar-mes', 'avisos-inicial', 'avisos-atraso'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) as tres tarefas', string_agg(j, '; ' ORDER BY j),
       'avisos-atraso | 0 8 11 * * | true | SELECT gerar_avisos_pagamento(''atraso''); '
       || 'avisos-inicial | 0 8 1 * * | true | SELECT gerar_avisos_pagamento(''inicial''); '
       || 'fechar-mes | 0 1 1 * * | true | SELECT fechar_mes_anterior();',
       string_agg(j, '; ' ORDER BY j) =
       'avisos-atraso | 0 8 11 * * | true | SELECT gerar_avisos_pagamento(''atraso''); '
       || 'avisos-inicial | 0 8 1 * * | true | SELECT gerar_avisos_pagamento(''inicial''); '
       || 'fechar-mes | 0 1 1 * * | true | SELECT fechar_mes_anterior();'
FROM j;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) gerar_avisos_pagamento e SECURITY DEFINER', coalesce(bool_or(prosecdef)::text, '(nao existe)'),
       'true', coalesce(bool_or(prosecdef), false)
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'gerar_avisos_pagamento';

-- 4) Comportamento. "segunda_vez: 0" e o guarda de repeticao a funcionar; se
--    der 3, os alunos levam o mesmo aviso cada vez que a tarefa dispara.
DO $$
DECLARE
  v_primeira int; v_segunda int; v_atraso int; v_fases text; v_erro text;
  v_mes date := (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date;
BEGIN
  BEGIN
    INSERT INTO meses_em_divida (aluno_id, ano, mes, data, total)
    SELECT a.id, EXTRACT(YEAR FROM v_mes)::int, EXTRACT(MONTH FROM v_mes)::int, v_mes, 12.50
    FROM (SELECT id FROM alunos ORDER BY id LIMIT 3) a;

    v_primeira := gerar_avisos_pagamento('inicial');
    v_segunda  := gerar_avisos_pagamento('inicial');
    v_atraso   := gerar_avisos_pagamento('atraso');

    SELECT string_agg(fase || ' ' || n, ', ' ORDER BY fase) INTO v_fases
    FROM (SELECT dados->>'fase' AS fase, count(*)::int AS n
          FROM notificacoes WHERE tipo = 'pagamento' GROUP BY 1) s;

    RAISE EXCEPTION USING ERRCODE = 'VRF01';          -- desfazer tudo
  EXCEPTION
    WHEN SQLSTATE 'VRF01' THEN NULL;
    WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
  END;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('4) avisos: primeira vez / segunda vez / fase atraso (desfeito)',
     coalesce(v_erro, v_primeira || ' / ' || v_segunda || ' / ' || v_atraso), '3 / 0 / 3',
     v_erro IS NULL AND v_primeira = 3 AND v_segunda = 0 AND v_atraso = 3),
    ('4b) notificacoes de pagamento por fase (desfeito)', coalesce(v_erro, v_fases),
     'atraso 3, inicial 3', v_erro IS NULL AND v_fases = 'atraso 3, inicial 3');
END $$;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
VALUES ('5) as tarefas disparam mesmo', 'so depois do dia 1 as 01:00 UTC',
        'SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10; -> succeeded', NULL);

-- ---------------------------------------------------------------- PASSO 4 ---
-- Nas duas primeiras NAO pode aparecer o PUBLIC (=X/postgres sozinho) nem anon
-- nem authenticated. Nas duas ultimas anon e authenticated TEM de continuar.
WITH f AS (
  SELECT proname, coalesce(proacl::text, '') AS acl
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname IN ('fechar_mes_anterior', 'gerar_avisos_pagamento', 'liquidar_mes_divida', 'reservar_refeicao'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.1) EXECUTE: ' || proname, CASE WHEN acl = '' THEN '(por omissao: PUBLIC)' ELSE acl END,
       CASE WHEN proname IN ('fechar_mes_anterior', 'gerar_avisos_pagamento')
            THEN 'so postgres e service_role'
            ELSE 'com anon=X e authenticated=X' END,
       CASE WHEN proname IN ('fechar_mes_anterior', 'gerar_avisos_pagamento')
            THEN acl <> '' AND acl NOT LIKE '%anon=%' AND acl NOT LIKE '%authenticated=%' AND acl !~ '(^\{|,)=X'
            ELSE acl LIKE '%anon=X%' AND acl LIKE '%authenticated=X%' END
FROM f;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.2) o cron (postgres) pode executar os avisos',
       has_function_privilege('postgres', 'public.gerar_avisos_pagamento(text)', 'EXECUTE')::text, 'true',
       has_function_privilege('postgres', 'public.gerar_avisos_pagamento(text)', 'EXECUTE');

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
