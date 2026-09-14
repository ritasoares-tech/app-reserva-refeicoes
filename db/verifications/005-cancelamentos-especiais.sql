-- =============================================================================
-- Verificacao da 005 - cancelamentos especiais
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 005.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O passo 4 cria um pedido pendente para chamar a listar_solicitacoes_pendentes
-- COM LINHAS la dentro, e DESFAZ-O dentro do proprio script. Precisa de uma
-- reserva de almoco ativa; sem nenhuma cria um almoco temporario no mesmo
-- bloco, desfeito da mesma maneira.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

WITH f AS (
  SELECT proname || ' ' || prosecdef AS f
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname IN ('solicitar_cancelamento_especial', 'aprovar_cancelamento_especial',
                    'rejeitar_cancelamento_especial', 'cantina_alterar_reserva',
                    'listar_solicitacoes_pendentes'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) prosecdef das cinco funcoes', string_agg(f, ', ' ORDER BY f),
       'aprovar_ true, cantina_alterar_reserva true, listar_ FALSE, rejeitar_ true, solicitar_ true',
       string_agg(f, ', ' ORDER BY f) =
       'aprovar_cancelamento_especial true, cantina_alterar_reserva true, listar_solicitacoes_pendentes false, '
       || 'rejeitar_cancelamento_especial true, solicitar_cancelamento_especial true'
FROM f;

-- Se acusar alguma coisa, ver PRIMEIRO se a linha e um comentario no corpo.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) funcoes de cancelamento que ainda falam em cancelada',
       coalesce(string_agg(proname, ', '), '(nenhuma)'), '(nenhuma)', count(*) = 0
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND prosrc ~ '\mcancelada\M' AND proname LIKE '%cancelamento%';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) politicas em cancelamentos_especiais', string_agg(policyname || ' | ' || cmd, '; ' ORDER BY policyname),
       'Aluno vê os seus pedidos | SELECT; Cantina vê todos os pedidos | SELECT',
       count(*) = 2 AND bool_and(cmd = 'SELECT')
FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cancelamentos_especiais';

WITH f AS (
  SELECT p.proname,
         has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('solicitar_cancelamento_especial', 'aprovar_cancelamento_especial',
                      'rejeitar_cancelamento_especial', 'cantina_alterar_reserva'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '4) EXECUTE: ' || proname, 'anon=' || anon || ' authenticated=' || auth,
       'anon=false authenticated=true', NOT anon AND auth
FROM f;

-- ---------------------------------------------------------------- PASSO 4 ---
-- Antes deste passo isto dava 42804 em vez de devolver a linha.
DO $$
DECLARE v_linhas int; v_c30 int; v_erro text; v_sem boolean; v_data_teste date;
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  v_sem := NOT EXISTS (SELECT 1 FROM alunos);
  IF NOT v_sem THEN
    BEGIN
      -- Sem reserva de almoco ativa, cria-se um almoco temporario no proximo dia
      -- util sem almoco; o trigger dos menus da-o aos alunos. Menu, reservas e
      -- pedido sao desfeitos juntos, no fim do bloco.
      IF NOT EXISTS (SELECT 1 FROM reservas WHERE tipo = 'almoco' AND ativa) THEN
        SELECT min(d)::date INTO v_data_teste
        FROM generate_series(v_hoje + 1, v_hoje + 60, interval '1 day') AS d
        WHERE extract(isodow FROM d) < 6
          AND NOT EXISTS (SELECT 1 FROM menus m WHERE m.tipo = 'almoco' AND m.data = d::date);
        INSERT INTO menus (data, tipo, prato, preco)
        VALUES (v_data_teste, 'almoco', 'Teste verificacao 005', 0);
      END IF;

      INSERT INTO cancelamentos_especiais (aluno_id, reserva_id, motivo, status)
      SELECT r.aluno_id, r.id, 'Teste do cast', 'pendente'
      FROM reservas r WHERE r.tipo = 'almoco' AND r.ativa LIMIT 1;

      SELECT count(*), max(cancelamentos_30_dias) INTO v_linhas, v_c30
      FROM listar_solicitacoes_pendentes();

      RAISE EXCEPTION USING ERRCODE = 'VRF01';        -- desfazer o pedido
    EXCEPTION
      WHEN SQLSTATE 'VRF01' THEN NULL;
      WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
    END;
  END IF;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('P4) listar_solicitacoes_pendentes com um pedido (desfeito)',
     CASE WHEN v_sem THEN 'sem alunos para testar'
          ELSE coalesce(v_erro, v_linhas || ' linha(s), cancelamentos_30_dias = ' || v_c30)
               || CASE WHEN v_data_teste IS NOT NULL
                       THEN ' (com um almoco temporario em ' || v_data_teste || ', desfeito)' ELSE '' END END,
     '1 linha(s), cancelamentos_30_dias = 0',
     CASE WHEN v_sem THEN NULL ELSE v_erro IS NULL AND v_linhas = 1 AND v_c30 = 0 END);
END $$;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
