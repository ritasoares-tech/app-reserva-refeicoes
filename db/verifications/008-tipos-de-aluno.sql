-- =============================================================================
-- Verificacao da 008 - tipos de aluno (contrato / sem contrato)
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 008.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto 4 tenta mudar o preco de uma reserva e DESFAZ a tentativa dentro do
-- proprio script. Sem reservas, cria um almoco temporario no mesmo bloco,
-- desfeito da mesma maneira. O ponto 5 le os saldos como a cantina; comparar com o
-- valores-referencia.sql corrido ANTES de aplicar a 008.
--
-- ATENCAO: a 010 apaga a definir_contrato_aluno e acrescenta tipos. O esperado
-- aqui e o de logo a seguir a 008.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1a) alunos com contrato / total', count(*) FILTER (WHERE tem_contrato) || ' / ' || count(*),
       'iguais', count(*) FILTER (WHERE tem_contrato) = count(*)
FROM alunos;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1b) configuracao', count(*) || ' linha(s), preco = ' || coalesce(max(preco_almoco_sem_contrato)::text, '-'),
       '1 linha, preco > 0', count(*) = 1 AND max(preco_almoco_sem_contrato) > 0
FROM configuracao;

-- A lista final partilhada com a 009 e a 010.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) colunas de alunos que o authenticated pode alterar',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '(nenhuma)'), 'email, nome',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '') = 'email, nome'
FROM information_schema.column_privileges
WHERE table_name = 'alunos' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

WITH esperadas(nome) AS (VALUES ('definir_contrato_aluno'), ('contar_almocos_automaticos_futuros'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) ' || e.nome,
       CASE WHEN p.oid IS NULL THEN '(nao existe)'
            ELSE 'prosecdef=' || p.prosecdef || ' ' || coalesce(p.proacl::text, '(PUBLIC)') END,
       'prosecdef=true, sem anon= e sem =X/postgres',
       p.oid IS NOT NULL AND p.prosecdef AND p.proacl IS NOT NULL
       AND p.proacl::text NOT LIKE '%anon=%' AND p.proacl::text !~ '(^\{|,)=X'
FROM esperadas e
LEFT JOIN pg_proc p ON p.proname = e.nome AND p.pronamespace = 'public'::regnamespace;

-- 4) O preco de uma reserva nao se muda por UPDATE.
DO $$
DECLARE v_id uuid; v_antes numeric; v_depois numeric; v_erro text; v_data_teste date;
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  IF EXISTS (SELECT 1 FROM alunos) THEN
    BEGIN
      -- Sem reservas, cria-se um almoco temporario no proximo dia util sem
      -- almoco; o trigger dos menus da-o aos alunos. Tudo desfeito no fim.
      IF NOT EXISTS (SELECT 1 FROM reservas) THEN
        SELECT min(d)::date INTO v_data_teste
        FROM generate_series(v_hoje + 1, v_hoje + 60, interval '1 day') AS d
        WHERE extract(isodow FROM d) < 6
          AND NOT EXISTS (SELECT 1 FROM menus m WHERE m.tipo = 'almoco' AND m.data = d::date);
        INSERT INTO menus (data, tipo, prato, preco)
        VALUES (v_data_teste, 'almoco', 'Teste verificacao 008', 3.50);
      END IF;

      SELECT id, preco INTO v_id, v_antes FROM reservas ORDER BY id LIMIT 1;
      UPDATE reservas SET preco = 99.99 WHERE id = v_id;
      SELECT preco INTO v_depois FROM reservas WHERE id = v_id;
      RAISE EXCEPTION USING ERRCODE = 'VRF01';        -- desfazer
    EXCEPTION
      WHEN SQLSTATE 'VRF01' THEN NULL;
      WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
    END;
  END IF;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('4) preco depois de UPDATE preco = 99.99 (desfeito)',
     CASE WHEN v_id IS NULL AND v_erro IS NULL THEN 'sem reservas para testar'
          ELSE coalesce(v_erro, v_depois::text)
               || CASE WHEN v_data_teste IS NOT NULL
                       THEN ' (com um almoco temporario em ' || v_data_teste || ', desfeito)' ELSE '' END END,
     CASE WHEN v_id IS NULL THEN '-' ELSE 'o original: ' || v_antes END,
     CASE WHEN v_id IS NULL AND v_erro IS NULL THEN NULL ELSE v_erro IS NULL AND v_depois = v_antes END);
END $$;

-- 5) Nenhum valor ja cobrado se moveu.
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
    ('5) saldos_por_aluno (como a cantina)', coalesce(v_erro, v_saldos),
     'igual ao valores-referencia.sql de antes da 008', NULL);
END $$;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
