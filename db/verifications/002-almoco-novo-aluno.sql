-- =============================================================================
-- Verificacao da 002 - almoco automatico para um aluno novo
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 002.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto 2 insere um aluno de teste para ver o trigger a funcionar e DESFAZ
-- tudo dentro do proprio script (a insercao corre num bloco que termina com um
-- erro de proposito). Nao fica aluno nenhum nem reserva nenhuma. Se nao houver
-- almocos futuros, cria tambem um almoco temporario no mesmo bloco, desfeito
-- da mesma maneira.
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
  v_reais    int;
  v_data_teste date;
  v_obtido   int;
  v_erro     text;
BEGIN
  SELECT count(*) INTO v_esperado FROM menus
  WHERE tipo = 'almoco' AND (data > v_hoje OR (data = v_hoje AND v_antes_9));
  v_reais := v_esperado;

  BEGIN
    -- Sem almocos futuros o teste nao prova nada. Cria-se um almoco temporario
    -- no proximo dia util sem almoco; o trigger dos menus da-o aos alunos que
    -- ja existem, e tudo - menu e essas reservas - e desfeito com o resto.
    IF v_esperado = 0 THEN
      SELECT min(d)::date INTO v_data_teste
      FROM generate_series(v_hoje + 1, v_hoje + 60, interval '1 day') AS d
      WHERE extract(isodow FROM d) < 6
        AND NOT EXISTS (SELECT 1 FROM menus m WHERE m.tipo = 'almoco' AND m.data = d::date);
      INSERT INTO menus (data, tipo, prato, preco)
      VALUES (v_data_teste, 'almoco', 'Teste verificacao 002', 0);
      SELECT count(*) INTO v_esperado FROM menus
      WHERE tipo = 'almoco' AND (data > v_hoje OR (data = v_hoje AND v_antes_9));
    END IF;

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
    ('1) almocos que um aluno novo deve receber', v_reais::text,
     'numero de almocos de amanha em diante (+ hoje, antes das 9:00)', NULL),
    ('2) reservas criadas para um aluno de teste (desfeito)',
     coalesce(v_erro, v_obtido::text)
       || CASE WHEN v_data_teste IS NOT NULL
               THEN ' (com um almoco temporario em ' || v_data_teste || ', desfeito)' ELSE '' END,
     v_esperado::text,
     v_erro IS NULL AND v_obtido = v_esperado);
END $$;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) hora que o Postgres usa (utc / lisboa)',
       now()::text || '  /  ' || (now() AT TIME ZONE 'Europe/Lisbon')::text,
       'a hora de Lisboa certa', NULL;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
