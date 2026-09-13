-- =============================================================================
-- Verificacao da 007 - saldos_por_aluno
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 007.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O ponto 3 chama a saldos_por_aluno COMO A CANTINA - no editor de SQL nao ha
-- auth.uid() e a funcao recusa. O script faz-se passar pela primeira conta da
-- tabela cantina so dentro de si proprio. So le.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) saldos_por_aluno e SECURITY DEFINER', coalesce(bool_or(prosecdef)::text, '(nao existe)'), 'true',
       coalesce(bool_or(prosecdef), false)
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'saldos_por_aluno';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) EXECUTE: saldos_por_aluno', coalesce(proacl::text, '(por omissao: PUBLIC)'),
       'sem anon= e sem =X/postgres (o PUBLIC)',
       proacl IS NOT NULL AND proacl::text NOT LIKE '%anon=%' AND proacl::text !~ '(^\{|,)=X'
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'saldos_por_aluno';

-- 3) A conta da funcao bate certo com a conta feita a mao sobre a tabela toda.
DO $$
DECLARE v_cantina uuid; v_funcao text; v_mao text; v_erro text;
BEGIN
  SELECT count(DISTINCT aluno_id) || ' alunos / ' || coalesce(sum(preco), 0) INTO v_mao
  FROM reservas WHERE ativa;

  SELECT id INTO v_cantina FROM cantina ORDER BY id LIMIT 1;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_cantina::text, true);
    SELECT count(*) || ' alunos / ' || coalesce(sum(total), 0) INTO v_funcao FROM saldos_por_aluno();
  EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('3) saldos_por_aluno (como a cantina) = soma das reservas ativas',
     coalesce(v_erro, v_funcao), v_mao, v_erro IS NULL AND v_funcao = v_mao);
END $$;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
