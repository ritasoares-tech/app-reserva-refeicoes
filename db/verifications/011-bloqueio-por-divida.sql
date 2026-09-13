-- =============================================================================
-- Verificacao da 011 - bloqueio por divida (a VERIFICACAO FINAL da migracao)
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 011
-- (as sete seccoes). Devolve uma tabela so: verificacao | obtido | esperado | ok
-- (vazio = ler). Mesma numeracao da VERIFICACAO FINAL no fim da migracao.
--
-- Para o 10: correr o valores-referencia.sql ANTES de aplicar a 011 e comparar.
-- Os saldos sao lidos como a cantina (o script faz-se passar pela primeira
-- conta da tabela cantina so dentro de si proprio). So le.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

-- 1) Os cinco estados da reserva, e a ativa inalterada.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1a) estados da reserva (CHECK)', pg_get_constraintdef(oid),
       'user, payment, reactivated, contrato, bloqueado',
       pg_get_constraintdef(oid) LIKE '%''user''%' AND pg_get_constraintdef(oid) LIKE '%''payment''%'
       AND pg_get_constraintdef(oid) LIKE '%''reactivated''%' AND pg_get_constraintdef(oid) LIKE '%''contrato''%'
       AND pg_get_constraintdef(oid) LIKE '%''bloqueado''%'
FROM pg_constraint WHERE conname = 'reservas_cancelamento_tipo_chk';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '1b) coluna ativa inalterada', generation_expression,
       '((cancelamento_tipo IS NULL) OR (cancelamento_tipo = ''reactivated''::text))',
       regexp_replace(generation_expression, '\s+', ' ', 'g')
         = '((cancelamento_tipo IS NULL) OR (cancelamento_tipo = ''reactivated''::text))'
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'reservas' AND column_name = 'ativa';

-- 2) Os seis resultados do leitor.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '2) resultados do leitor (CHECK)', pg_get_constraintdef(oid),
       'servido, sem_reserva, cancelada, repetido, codigo_desconhecido, bloqueado',
       pg_get_constraintdef(oid) LIKE '%''servido''%' AND pg_get_constraintdef(oid) LIKE '%''sem_reserva''%'
       AND pg_get_constraintdef(oid) LIKE '%''cancelada''%' AND pg_get_constraintdef(oid) LIKE '%''repetido''%'
       AND pg_get_constraintdef(oid) LIKE '%''codigo_desconhecido''%' AND pg_get_constraintdef(oid) LIKE '%''bloqueado''%'
FROM pg_constraint WHERE conname = 'leituras_resultado_check';

-- 3) desbloqueios.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3a) desbloqueios com RLS', relrowsecurity::text, 'true', relrowsecurity
FROM pg_class WHERE oid = 'public.desbloqueios'::regclass;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3b) concessoes em desbloqueios (anon, authenticated)',
       coalesce(string_agg(grantee || ' ' || privilege_type, ', ' ORDER BY grantee, privilege_type), '(nenhuma)'),
       'authenticated SELECT', coalesce(string_agg(grantee || ' ' || privilege_type, ', '), '') = 'authenticated SELECT'
FROM information_schema.role_table_grants
WHERE table_name = 'desbloqueios' AND grantee IN ('anon', 'authenticated');

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '3c) politicas em desbloqueios', string_agg(policyname || ' | ' || cmd, '; ' ORDER BY policyname),
       'desbloqueios_aluno_le_os_seus | SELECT; desbloqueios_cantina_le_todos | SELECT',
       string_agg(policyname || ' | ' || cmd, '; ' ORDER BY policyname)
         = 'desbloqueios_aluno_le_os_seus | SELECT; desbloqueios_cantina_le_todos | SELECT'
FROM pg_policies WHERE tablename = 'desbloqueios';

-- 4) O dia do bloqueio.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '4) dia_bloqueio', count(*) || ' linha(s), dia ' || coalesce(max(dia_bloqueio)::text, '-'),
       '1 linha(s), dia 15', count(*) = 1 AND max(dia_bloqueio) = 15
FROM configuracao;

-- 5) As cinco funcoes que a app chama.
WITH esperadas(nome) AS (
  VALUES ('aluno_bloqueado'), ('alunos_bloqueados'), ('desbloqueio_ate'),
         ('conceder_desbloqueio'), ('revogar_desbloqueio'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '5) ' || e.nome,
       CASE WHEN p.oid IS NULL THEN '(nao existe)'
            ELSE 'prosecdef=' || p.prosecdef || ' ' || coalesce(p.proacl::text, '(PUBLIC)') END,
       'prosecdef=true, authenticated=X, sem anon= e sem =X/ (PUBLIC)',
       p.oid IS NOT NULL AND p.prosecdef AND p.proacl IS NOT NULL
       AND p.proacl::text LIKE '%authenticated=X%' AND p.proacl::text NOT LIKE '%anon=%'
       AND p.proacl::text !~ '(^\{|,)=X'
FROM esperadas e
LEFT JOIN pg_proc p ON p.proname = e.nome AND p.pronamespace = 'public'::regnamespace;

-- 6) As tres internas: nem authenticated. Correm do cron e das funcoes acima.
WITH esperadas(nome) AS (
  VALUES ('suspender_reservas_bloqueadas'), ('reativar_reservas_bloqueadas'), ('sincronizar_bloqueios'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '6) ' || e.nome,
       CASE WHEN p.oid IS NULL THEN '(nao existe)' ELSE coalesce(p.proacl::text, '(PUBLIC)') END,
       'sem authenticated=, sem anon=, sem =X/ (PUBLIC)',
       p.oid IS NOT NULL AND p.proacl IS NOT NULL
       AND p.proacl::text NOT LIKE '%authenticated=%' AND p.proacl::text NOT LIKE '%anon=%'
       AND p.proacl::text !~ '(^\{|,)=X'
FROM esperadas e
LEFT JOIN pg_proc p ON p.proname = e.nome AND p.pronamespace = 'public'::regnamespace;

-- 7) As quatro tarefas agendadas.
WITH j AS (
  SELECT jobname || ' ' || schedule || ' ' || active AS j
  FROM cron.job
  WHERE jobname IN ('fechar-mes', 'avisos-inicial', 'avisos-atraso', 'bloquear-devedores'))
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '7) tarefas agendadas', string_agg(j, '; ' ORDER BY j),
       'avisos-atraso 0 8 9 * * true; avisos-inicial 0 8 1 * * true; bloquear-devedores 0 2 * * * true; fechar-mes 0 1 1 * * true',
       string_agg(j, '; ' ORDER BY j) =
       'avisos-atraso 0 8 9 * * true; avisos-inicial 0 8 1 * * true; bloquear-devedores 0 2 * * * true; fechar-mes 0 1 1 * * true'
FROM j;

-- 8) OS ACENTOS dos avisos. O ok procura a dupla codificacao; LER o obtido na mesma.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '8) textos dos avisos (LER os acentos)',
       (SELECT string_agg(btrim(l), '  ||  ')
        FROM regexp_split_to_table(prosrc, '\n') l
        WHERE l ~ 'format\('),
       'Março, até dia 8, não, Direção e o € legiveis',
       prosrc NOT LIKE '%Ã%' AND prosrc NOT LIKE '%Â%' AND prosrc LIKE '%Março%' AND prosrc LIKE '%até dia 8%'
FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'gerar_avisos_pagamento';

-- 9) A lista de colunas escreviveis na alunos continua exatamente (nome, email).
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '9) colunas de alunos que o authenticated pode alterar',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '(nenhuma)'), 'email, nome',
       coalesce(string_agg(column_name, ', ' ORDER BY column_name), '') = 'email, nome'
FROM information_schema.column_privileges
WHERE table_name = 'alunos' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';

-- 10) NENHUM VALOR SE MOVEU: comparar com o valores-referencia.sql de antes.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '10a) reservas ' || coalesce(cancelamento_tipo, '(ativa)'), count(*) || ' / ' || coalesce(sum(preco), 0),
       'igual ao de antes (ate a tarefa das 02:00; nao ha bloqueado antes disso)', NULL
FROM reservas GROUP BY cancelamento_tipo;

DO $$
DECLARE v_cantina uuid; v_saldos text; v_erro text;
BEGIN
  SELECT id INTO v_cantina FROM cantina ORDER BY id LIMIT 1;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_cantina::text, true);
    SELECT count(*) || ' alunos / ' || coalesce(sum(total), 0) || ' / ' || coalesce(sum(refeicoes), 0) || ' refeicoes'
      INTO v_saldos FROM saldos_por_aluno();
  EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE || ' ' || SQLERRM;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('10b) saldos_por_aluno (como a cantina)', coalesce(v_erro, v_saldos), 'igual ao de antes', NULL);
END $$;

-- 11) Quem fica bloqueado. Aplicada junto com a 001 (que apaga as dividas) da
--     zero. Numa base que ja tenha dividas NAO e zero, e isso nao e um erro -
--     ver o ponto 11 da VERIFICACAO FINAL na migracao.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT '11) alunos bloqueados agora', count(*) || coalesce(': ' || string_agg(nome, ', ' ORDER BY nome), ''),
       '0 se aplicada junto com a 001', count(*) = 0
FROM alunos a WHERE aluno_bloqueado(a.id);

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
