-- =============================================================================
-- Verificacao da 001 - modelo de reservas
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 001.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok
--   ok = true / false quando da para decidir sozinho; vazio = ler e comparar.
-- Sao as consultas do bloco VERIFICACAO no fim da migracao, ja descomentadas.
-- Os esperados sao os de logo a seguir a 001 - ver README.md.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) alunos - contagem', count(*)::text,
       'igual ao "Alunos antes da migracao" do NOTICE', NULL
FROM alunos;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) colunas geradas em reservas',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '(nenhuma)'),
       'ativa', coalesce(string_agg(column_name, ', ' ORDER BY column_name), '') = 'ativa'
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'reservas' AND is_generated = 'ALWAYS';

WITH u AS (
  SELECT conrelid::regclass::text || '.' || conname AS c
  FROM pg_constraint
  WHERE conrelid IN ('reservas'::regclass, 'menus'::regclass, 'meses_em_divida'::regclass)
    AND contype = 'u')
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) restricoes de unicidade', string_agg(c, ', ' ORDER BY c),
       'menus.menus_data_tipo_key, meses_em_divida.meses_em_divida_aluno_ano_mes_key, reservas.reservas_aluno_data_tipo_key',
       string_agg(c, ', ' ORDER BY c) =
       'menus.menus_data_tipo_key, meses_em_divida.meses_em_divida_aluno_ano_mes_key, reservas.reservas_aluno_data_tipo_key'
FROM u;

-- Se trigger_atualizar_meses_divida ainda aparecer em reservas, o trigger que
-- corrompe meses_em_divida sobreviveu: parar e investigar.
WITH t AS (
  SELECT tgrelid::regclass::text || '.' || tgname AS t
  FROM pg_trigger
  WHERE NOT tgisinternal AND tgrelid IN ('reservas'::regclass, 'menus'::regclass))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '4) triggers em reservas e menus', coalesce(string_agg(t, ', ' ORDER BY t), '(nenhum)'),
       'menus.trg_criar_reservas_automatica_almoco, menus.trigger_registrar_alteracao_menu',
       coalesce(string_agg(t, ', ' ORDER BY t), '') =
       'menus.trg_criar_reservas_automatica_almoco, menus.trigger_registrar_alteracao_menu'
FROM t;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '5) numero de funcoes em public', count(*)::text, '29 (33 - 5 + 1)', count(*) = 29
FROM pg_proc WHERE pronamespace = 'public'::regnamespace;

-- A MAIS IMPORTANTE: um DROP FUNCTION IF EXISTS com os tipos errados nao da erro
-- nenhum e nao apaga nada.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '6) funcoes que tinham de desaparecer, ainda presentes',
       coalesce(string_agg(DISTINCT proname, ', '), '(nenhuma)'), '(nenhuma)', count(*) = 0
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('atualizar_meses_divida', 'gerar_meses_em_divida', 'trigger_gerar_meses_divida',
                  'liquidar_divida_aluno', 'liquidar_divida_aluno_emergencia');

WITH esperadas(nome) AS (
  VALUES ('reservar_refeicao'), ('obter_divida_por_mes'), ('fechar_mes_anterior'), ('liquidar_mes_divida'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '7) funcoes que tinham de existir, em falta',
       coalesce(string_agg(nome, ', '), '(nenhuma)'), '(nenhuma)', count(*) = 0
FROM esperadas e
WHERE NOT EXISTS (SELECT 1 FROM pg_proc p
                  WHERE p.pronamespace = 'public'::regnamespace AND p.proname = e.nome);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '8) lista completa das funcoes (para ler)',
       string_agg(proname || '(' || pg_get_function_identity_arguments(oid) || ')', ', ' ORDER BY proname),
       'ler', NULL
FROM pg_proc WHERE pronamespace = 'public'::regnamespace;

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
