-- =============================================================================
-- Valores de referencia - correr ANTES e DEPOIS de uma migracao que diz
-- "nenhum valor ja cobrado se moveu" (008, 010, 011) e comparar as duas tabelas.
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL. Devolve uma tabela so:
-- verificacao | obtido. So le.
--
-- Os saldos sao lidos como a cantina (o script faz-se passar pela primeira
-- conta da tabela cantina so dentro de si proprio). Antes da 007 a funcao
-- saldos_por_aluno ainda nao existe, e a linha diz isso.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido)
SELECT 'alunos', count(*)::text FROM alunos;

INSERT INTO _verificacao (verificacao, obtido)
SELECT 'reservas ' || coalesce(cancelamento_tipo, '(ativa)') || ' - linhas / soma',
       count(*) || ' / ' || coalesce(sum(preco), 0)
FROM reservas GROUP BY cancelamento_tipo ORDER BY cancelamento_tipo NULLS FIRST;

DO $$
DECLARE v_cantina uuid; v_saldos text;
BEGIN
  IF to_regprocedure('public.saldos_por_aluno()') IS NULL THEN
    v_saldos := '(saldos_por_aluno ainda nao existe - antes da 007)';
  ELSE
    SELECT id INTO v_cantina FROM cantina ORDER BY id LIMIT 1;
    BEGIN
      PERFORM set_config('request.jwt.claim.sub', v_cantina::text, true);
      EXECUTE 'SELECT count(*) || '' alunos / '' || coalesce(sum(total), 0) || '' / '' || coalesce(sum(refeicoes), 0) || '' refeicoes'' FROM saldos_por_aluno()'
        INTO v_saldos;
    EXCEPTION WHEN OTHERS THEN v_saldos := SQLSTATE || ' ' || SQLERRM;
    END;
    PERFORM set_config('request.jwt.claim.sub', '', true);
  END IF;
  INSERT INTO _verificacao (verificacao, obtido) VALUES ('saldos_por_aluno (como a cantina)', v_saldos);
END $$;

SELECT verificacao, obtido FROM _verificacao ORDER BY n;
