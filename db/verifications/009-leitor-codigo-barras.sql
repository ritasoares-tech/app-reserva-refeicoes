-- =============================================================================
-- Verificacao da 009 - leitor de codigo de barras
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 009.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
-- So le.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1) codigos: total / com codigo / distintos / mal formados',
       count(*) || ' / ' || count(codigo) || ' / ' || count(DISTINCT codigo) || ' / '
       || count(*) FILTER (WHERE codigo !~ '^[0-9]{6}$'),
       'os tres primeiros iguais, mal formados = 0',
       count(*) = count(codigo) AND count(codigo) = count(DISTINCT codigo)
       AND count(*) FILTER (WHERE codigo !~ '^[0-9]{6}$') = 0
FROM alunos;

-- A que apanha o conflito com a 008. Correr SEMPRE.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) colunas de alunos que o authenticated pode alterar',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '(nenhuma)'), 'email, nome',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '') = 'email, nome'
FROM information_schema.column_privileges
WHERE table_name = 'alunos' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3) registar_leitura',
       coalesce(max('prosecdef=' || prosecdef || ' ' || coalesce(proacl::text, '(PUBLIC)')), '(nao existe)'),
       'prosecdef=true, sem anon= e sem =X/postgres',
       coalesce(bool_and(prosecdef AND proacl IS NOT NULL AND proacl::text NOT LIKE '%anon=%'
                         AND proacl::text !~ '(^\{|,)=X'), false)
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'registar_leitura';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '4) UPDATE/DELETE em leituras para anon ou authenticated',
       coalesce(string_agg(grantee || ' ' || privilege_type, ', '), '(nenhum)'), '(nenhum)', count(*) = 0
FROM information_schema.role_table_grants
WHERE table_name = 'leituras' AND grantee IN ('anon', 'authenticated')
  AND privilege_type IN ('UPDATE', 'DELETE');

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
