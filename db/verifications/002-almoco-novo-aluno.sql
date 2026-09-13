-- =============================================================================
-- Verificacao da 002 - almoco automatico para um aluno novo
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 002.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto 2 insere um aluno de teste para ver o trigger a funcionar e DESFAZ
-- tudo dentro do proprio script (a insercao corre num bloco que termina com um
-- erro de proposito). Nao fica aluno nenhum nem reserva nenhuma.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

-- O esperado conta os almocos de amanha em diante, mais o de hoje SO antes das
-- 9:00 em Lisboa - e a regra da 002. (O comentario da migracao contava o de
-- hoje sempre, o que da uma diferenca de 1 depois das 9:00.)
DO $$
DECLARE
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_antes_9  boolean := (now() AT TIME ZONE 'Europe/Lisbon')::time < time '09:00';
  v_esperado int;
  v_obtido   int;
  v_erro     text;
BEGIN
  SELECT count(*) INTO v_esperado FROM menus
  WHERE tipo = 'almoco' AND (data > v_hoje OR (data = v_hoje AND v_antes_9));

  BEGIN
    INSERT INTO alunos (id, nome, email)
    VALUES (gen_random_uuid(), 'Teste Trigger', 'teste-trigger@example.org');
    SELECT count(*) INTO v_obtido
    FROM reservas r JOIN alunos a ON a.id = r.aluno_id
    WHERE a.email = 'teste-trigger@example.org';
    RAISE EXCEPTION USING ERRCODE = 'VRF01';          -- desfazer o aluno de teste
  EXCEPTION
    WHEN SQLSTATE 'VRF01' THEN NULL;
    WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
  END;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('1) almocos que um aluno novo deve receber', v_esperado::text,
     'numero de almocos de amanha em diante (+ hoje, antes das 9:00)', NULL),
    ('2) reservas criadas para um aluno de teste (desfeito)',
     CASE WHEN v_esperado = 0 AND v_erro IS NULL
          THEN 'sem almocos futuros: criar um menu de almoco e correr outra vez'
          ELSE coalesce(v_erro, v_obtido::text) END,
     v_esperado::text,
     CASE WHEN v_esperado = 0 AND v_erro IS NULL THEN NULL
          ELSE v_erro IS NULL AND v_obtido = v_esperado END);
END $$;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) hora que o Postgres usa (utc / lisboa)',
       now()::text || '  /  ' || (now() AT TIME ZONE 'Europe/Lisbon')::text,
       'a hora de Lisboa certa', NULL;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
