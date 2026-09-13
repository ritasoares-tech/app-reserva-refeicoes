-- =============================================================================
-- Verificacao da 003 - guardas (passos 1 a 5)
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, LOGO A SEGUIR a aplicar a 003.
-- Devolve uma tabela so: verificacao | obtido | esperado | ok (vazio = ler).
--
-- O passo 3 tenta escrever valores invalidos para provar que as restricoes
-- travam MESMO. Tem de dar erro 23514; se passasse, a escrita e desfeita na
-- mesma, dentro do proprio script. Precisa de haver pelo menos uma reserva e um
-- menu - sem eles o resultado diz "sem linhas para testar".
--
-- A suite (tests/api/guards.test.ts) e a prova a serio; isto e o que da para
-- ver pelo catalogo e por escrita direta.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp._verificacao;
CREATE TEMP TABLE _verificacao (n serial, verificacao text, obtido text, esperado text, ok boolean);

-- ---------------------------------------------------------------- PASSO 1 ---
WITH p AS (
  SELECT policyname || ' | ' || cmd AS p, cmd, with_check
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'reservas')
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P1) politicas em reservas', string_agg(p, '; ' ORDER BY p),
       '5: Aluno pode atualizar as suas reservas | UPDATE; Aluno pode criar reservas | INSERT; '
       || 'Aluno vê apenas as suas reservas | SELECT; Cantina pode modificar reservas | UPDATE; '
       || 'Cantina pode ver todas as reservas | SELECT',
       count(*) = 5
       AND count(*) FILTER (WHERE cmd = 'INSERT' AND with_check = 'true') = 0
FROM p;

-- ---------------------------------------------------------------- PASSO 2 ---
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P2.1) trigger em reservas', coalesce(string_agg(tgname || ' | ' || tgenabled::text, ', '), '(nenhum)'),
       'trg_reservas_guard | O', coalesce(string_agg(tgname || ' | ' || tgenabled::text, ', '), '') = 'trg_reservas_guard | O'
FROM pg_trigger WHERE tgrelid = 'public.reservas'::regclass AND NOT tgisinternal;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P2.2) prazo_limite e reservas_guard (prosecdef)',
       string_agg(proname || ' | ' || prosecdef, ', ' ORDER BY proname),
       'prazo_limite | false, reservas_guard | true',
       string_agg(proname || ' | ' || prosecdef, ', ' ORDER BY proname) = 'prazo_limite | false, reservas_guard | true'
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname IN ('prazo_limite', 'reservas_guard');

-- O FUSO. Se o verao e o inverno derem a mesma hora UTC, 'Europe/Lisbon' nao
-- esta a ser aplicado e os alunos ganham uma hora no verao.
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P2.3) fuso: prazos de verao e de inverno (UTC)',
       to_char(public.prazo_limite('almoco',         DATE '2026-08-10') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || ', ' ||
       to_char(public.prazo_limite('almoco',         DATE '2026-01-15') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || ', ' ||
       to_char(public.prazo_limite('pequeno_almoco', DATE '2026-08-10') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || ', ' ||
       to_char(public.prazo_limite('pequeno_almoco', DATE '2026-01-15') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI'),
       '2026-08-10 08:00, 2026-01-15 09:00, 2026-08-09 22:00, 2026-01-14 23:00',
       public.prazo_limite('almoco',         DATE '2026-08-10') = timestamptz '2026-08-10 08:00:00+00'
   AND public.prazo_limite('almoco',         DATE '2026-01-15') = timestamptz '2026-01-15 09:00:00+00'
   AND public.prazo_limite('pequeno_almoco', DATE '2026-08-10') = timestamptz '2026-08-09 22:00:00+00'
   AND public.prazo_limite('pequeno_almoco', DATE '2026-01-15') = timestamptz '2026-01-14 23:00:00+00';

-- ---------------------------------------------------------------- PASSO 3 ---
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P3.1) restricoes CHECK', coalesce(string_agg(conname, ', ' ORDER BY conname), '(nenhuma)'),
       'menus_tipo_chk, reservas_cancelamento_tipo_chk',
       coalesce(string_agg(conname, ', ' ORDER BY conname), '') = 'menus_tipo_chk, reservas_cancelamento_tipo_chk'
FROM pg_constraint WHERE conname IN ('reservas_cancelamento_tipo_chk', 'menus_tipo_chk');

DO $$
DECLARE v_res text; v_menu text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM reservas) THEN
    v_res := 'sem linhas para testar';
  ELSE
    BEGIN
      UPDATE reservas SET cancelamento_tipo = 'nonsense' WHERE id = (SELECT id FROM reservas LIMIT 1);
      v_res := 'PASSOU sem erro';
      RAISE EXCEPTION USING ERRCODE = 'VRF01';
    EXCEPTION
      WHEN SQLSTATE 'VRF01' THEN NULL;
      WHEN OTHERS THEN v_res := SQLSTATE || ' ' || SQLERRM;
    END;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM menus) THEN
    v_menu := 'sem linhas para testar';
  ELSE
    BEGIN
      UPDATE menus SET tipo = 'lanche' WHERE id = (SELECT id FROM menus LIMIT 1);
      v_menu := 'PASSOU sem erro';
      RAISE EXCEPTION USING ERRCODE = 'VRF01';
    EXCEPTION
      WHEN SQLSTATE 'VRF01' THEN NULL;
      WHEN OTHERS THEN v_menu := SQLSTATE || ' ' || SQLERRM;
    END;
  END IF;

  INSERT INTO _verificacao (verificacao, obtido, esperado, ok) VALUES
    ('P3.2) reservas.cancelamento_tipo = ''nonsense'' e recusado', v_res,
     '23514 ... reservas_cancelamento_tipo_chk', CASE WHEN v_res LIKE 'sem linhas%' THEN NULL ELSE v_res LIKE '23514%' END),
    ('P3.3) menus.tipo = ''lanche'' e recusado', v_menu,
     '23514 ... menus_tipo_chk', CASE WHEN v_menu LIKE 'sem linhas%' THEN NULL ELSE v_menu LIKE '23514%' END);
END $$;

-- ----------------------------------------------------------- PASSOS 4 e 4b ---
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.1) tabelas SEM RLS', coalesce(string_agg(relname, ', ' ORDER BY relname), '(nenhuma)'),
       '(nenhuma)', count(*) = 0
FROM pg_class
WHERE relnamespace = 'public'::regnamespace AND relkind = 'r' AND NOT relrowsecurity;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.2) anon em cantina / cancelamentos_especiais',
       coalesce(string_agg(table_name || ' ' || privilege_type, ', '), '(nada)'), '(nada)', count(*) = 0
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'anon'
  AND table_name IN ('cantina', 'cancelamentos_especiais');

WITH p AS (
  SELECT policyname || ' | ' || cmd AS p, qual
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'meses_liquidados')
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.3) politicas em meses_liquidados', string_agg(p, '; ' ORDER BY p),
       'Aluno vê seus meses liquidados | SELECT; Cantina vê todos meses liquidados | SELECT',
       count(*) = 2 AND count(*) FILTER (WHERE qual ILIKE '%auth.role()%') = 0
FROM p;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P4.4) politicas em cantina', string_agg(policyname || ' | ' || cmd || ' | ' || qual, '; '),
       'Cantina vê o seu registo | SELECT | (id = auth.uid())', count(*) = 1
FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cantina';

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
VALUES ('P4.5) o login das duas contas', 'nao se verifica por SQL',
        'entrar na app como aluno e como cantina', NULL);

-- ---------------------------------------------------------------- PASSO 5 ---
WITH p AS (
  SELECT policyname || ' | ' || cmd AS p, qual, with_check
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notificacoes')
INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
SELECT 'P5) politicas em notificacoes', string_agg(p, '; ' ORDER BY p),
       '3: Alunos podem atualizar suas notificações | UPDATE; Alunos podem ler suas notificações | SELECT; '
       || 'Cantina cria notificacoes | INSERT',
       count(*) = 3
       AND count(*) FILTER (WHERE qual = 'true' OR with_check = 'true'
                              OR qual ILIKE '%auth.role()%' OR with_check ILIKE '%auth.role()%') = 0
FROM p;

INSERT INTO _verificacao (verificacao, obtido, esperado, ok)
VALUES ('P5.2) a cantina ainda notifica ao alterar um prato', 'nao se verifica por SQL',
        'alterar um almoco como cantina e ver a notificacao como aluno', NULL);

SELECT verificacao, obtido, esperado, ok FROM _verificacao ORDER BY n;
