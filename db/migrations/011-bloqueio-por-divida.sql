-- =============================================================================
-- 011 - Bloqueio de alunos com valores em atraso
-- =============================================================================
-- DEPENDE DA 001 (a coluna gerada ativa, a restricao unica, o
-- obter_divida_por_mes e o liquidar_mes_divida), DA 003 (reservas_guard), DA
-- 004 (pg_cron e os avisos) e DA 009 (leituras, registar_leitura).
-- Correr depois da 010.
--
-- O QUE RESOLVE
--   Das propostas da cantina para 2026/2027, a unica regra que a aplicacao nao
--   tinha: "o aluno com valores em atraso nao pode usar a cantina ate
--   regularizar". Tudo o resto ou ja estava feito ou ficou de fora - ver
--   docs/propostas-cantina-2026-27.md.
--
--   O pagamento vence no dia 8, mas o bloqueio so entra no dia 15: e uma folga
--   de uma semana para o que possa ter corrido mal pelo meio. Apanha as TRES
--   refeicoes, dos dois lados - o aluno nao marca e o leitor recusa, dizendo
--   que e a divida e nao a falta de reserva.
--
-- O QUE NAO MUDA
--   Nenhum valor ja cobrado. A coluna ativa nao se toca, o preco continua
--   congelado, e a definicao de divida e a do obter_divida_por_mes tal como
--   esta.
--
-- Ver docs/superpowers/specs/2026-09-13-bloqueio-por-divida-design.md
-- =============================================================================


-- =============================================================================
-- SECCAO 1 - o estado, a definicao, a tabela de excecoes e o predicado
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 1.1 - O quinto estado da reserva
-- -----------------------------------------------------------------------------
-- A coluna ativa e uma LISTA BRANCA dos estados ativos:
--   GENERATED ALWAYS AS (cancelamento_tipo IS NULL OR = 'reactivated')
-- por isso um valor novo nasce INATIVO sem se lhe tocar. E o mesmo movimento da
-- 008 seccao 7 para o 'contrato'.
--
-- E daqui vem de graca o que interessa: o saldos_por_aluno (007), o
-- fechar_mes_anterior, o liquidar_mes_divida (001) e o relatorio_mensal filtram
-- todos por ativa. Uma refeicao suspensa nao e somada, nao fecha no mes e nao e
-- liquidada - INCLUINDO UMA JA PASSADA. A regra "os dias em que esteve
-- bloqueado nao se cobram" nao precisa de uma unica conta escrita.
ALTER TABLE public.reservas DROP CONSTRAINT reservas_cancelamento_tipo_chk;
ALTER TABLE public.reservas ADD  CONSTRAINT reservas_cancelamento_tipo_chk
  CHECK (cancelamento_tipo IS NULL
         OR cancelamento_tipo = ANY (ARRAY['user'::text, 'payment'::text,
                                           'reactivated'::text, 'contrato'::text,
                                           'bloqueado'::text]));

COMMENT ON COLUMN public.reservas.cancelamento_tipo IS
  'Estado da reserva: NULL = ativa | reactivated = cancelada e reposta | '
  'user = cancelada pelo aluno | payment = servida e liquidada | '
  'contrato = cancelada por mudanca de contrato | '
  'bloqueado = suspensa por valores em atraso, nunca cobrada';

-- -----------------------------------------------------------------------------
-- 1.2 - O dia a partir do qual o bloqueio entra
-- -----------------------------------------------------------------------------
-- Vive na configuracao e nao escrito no codigo, e a razao principal e de TESTE.
-- Das tres condicoes do predicado, duas sao dados (ha divida, ha excecao) e a
-- terceira e o dia do mes - a unica que um teste nao consegue conduzir, porque
-- o harness existe precisamente para mover os dados e nunca o relogio
-- (tests/lib/dates.ts). Com o 15 escrito no SQL, metade dos testes de bloqueio
-- so afirmava alguma coisa em 14 dias do mes e desistia nos outros 17 - que e a
-- armadilha ja documentada no e2e-testes.md, "Where the two clocks disagree", e
-- que ja custou uma sessao a este projeto.
--
-- O maximo e 28 para a definicao valer em fevereiro como em qualquer outro mes.
ALTER TABLE public.configuracao
  ADD COLUMN dia_bloqueio integer NOT NULL DEFAULT 15
  CHECK (dia_bloqueio BETWEEN 1 AND 28);

COMMENT ON COLUMN public.configuracao.dia_bloqueio IS
  'Dia do mes a partir do qual quem tem meses fechados por pagar fica '
  'bloqueado. O pagamento vence no dia 8; o 15 e a folga acordada.';

-- -----------------------------------------------------------------------------
-- 1.3 - A excecao manual da cantina
-- -----------------------------------------------------------------------------
-- A cantina pode levantar o bloqueio COM A DIVIDA POR PAGAR - um acordo, uma
-- explicacao. Vale UM MES DE CALENDARIO e depois caduca; se o acordo se
-- mantiver, a cantina volta a dar no mes seguinte.
--
-- MESMA FORMA DA meses_liquidados, de proposito: e ja a tabela que responde
-- "este mes deste aluno esta tratado", e o predicado testa-a com o mesmo
-- EXISTS. Uma coluna na alunos respondia ao mesmo com o mesmo custo e PERDIA
-- QUEM AUTORIZOU E PORQUE, que e a unica razao para deixar passar uma divida.
--
-- Nao ha coluna de validade e nao ha tarefa de limpeza: como o bloqueio so
-- morde a partir do dia_bloqueio, a caducidade trata-se sozinha. No dia 1
-- ninguem esta bloqueado, e ate ao dia 15 a cantina renova se quiser.
CREATE TABLE public.desbloqueios (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aluno_id            uuid NOT NULL REFERENCES public.alunos(id)  ON DELETE CASCADE,
  ano                 integer NOT NULL,
  mes                 integer NOT NULL CHECK (mes BETWEEN 1 AND 12),
  motivo              text    NOT NULL CHECK (btrim(motivo) <> ''),
  cantina_responsavel uuid NOT NULL REFERENCES public.cantina(id),
  criado_em           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (aluno_id, ano, mes)
);

COMMENT ON TABLE public.desbloqueios IS
  'Excecoes dadas pela cantina: levantam o bloqueio de um aluno durante um mes '
  'de calendario, com a divida por pagar. Guarda quem autorizou e porque.';

-- O UNIQUE ja cria o indice por (aluno_id, ano, mes), que e exatamente a
-- consulta do predicado. Nao ha segundo indice a criar.

-- Um projeto novo do Supabase da tudo ao anon e ao authenticated em cada tabela
-- nova (db-teste-local.md, 2b). Revogar primeiro, conceder depois, sempre.
ALTER TABLE public.desbloqueios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.desbloqueios FROM anon, authenticated;

-- O aluno le as SUAS, para o ecra lhe poder dizer "a cantina levantou o
-- bloqueio ate ao fim do mes" em vez de o deixar sem perceber porque voltou a
-- conseguir marcar. Escrita nenhuma para ninguem: so as duas RPC da seccao 4,
-- que sao SECURITY DEFINER e nao precisam da concessao.
GRANT SELECT ON public.desbloqueios TO authenticated;

CREATE POLICY desbloqueios_aluno_le_os_seus ON public.desbloqueios
  FOR SELECT TO authenticated
  USING (aluno_id = auth.uid());

CREATE POLICY desbloqueios_cantina_le_todos ON public.desbloqueios
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.cantina c WHERE c.id = auth.uid()));

-- -----------------------------------------------------------------------------
-- 1.4 - O predicado
-- -----------------------------------------------------------------------------
-- Tres condicoes:
--   1. existe um mes FECHADO por pagar;
--   2. hoje ja e o dia_bloqueio ou depois;
--   3. a cantina nao deu excecao este mes.
--
-- A primeira e COPIADA A LETRA do CTE 'passados' do obter_divida_por_mes (001),
-- para que as duas nunca possam discordar sobre o que e uma divida. O mes
-- corrente esta deliberadamente de fora: ninguem esta em divida pelas refeicoes
-- que esta a comer este mes.
--
-- ATENCAO AOS DOIS RELOGIOS, e e de proposito. A condicao 1 usa CURRENT_DATE
-- porque e assim que esta no obter_divida_por_mes e no fechar_mes_anterior, e
-- alinhar so aqui punha as duas definicoes de "mes corrente" a divergir. As
-- condicoes 2 e 3 sao novas e usam a data de Lisboa, como o prazo_limite (003)
-- e o registar_leitura (009). A diferenca entre as duas e a primeira hora do
-- dia 1 no verao. NAO "corrigir" uma para a outra sem mexer nas tres funcoes.
--
-- SECURITY DEFINER porque o aluno tem de poder saber que esta bloqueado sem ter
-- SELECT na meses_em_divida.
CREATE OR REPLACE FUNCTION public.aluno_bloqueado(p_aluno_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
           SELECT 1
           FROM meses_em_divida md
           WHERE md.aluno_id = p_aluno_id
             AND make_date(md.ano, md.mes, 1) < date_trunc('month', CURRENT_DATE)::date
             AND NOT EXISTS (
                   SELECT 1 FROM meses_liquidados ml
                   WHERE ml.aluno_id = md.aluno_id
                     AND ml.ano = md.ano AND ml.mes = md.mes)
         )
     AND EXTRACT(DAY FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int
           >= (SELECT c.dia_bloqueio FROM configuracao c)
     AND NOT EXISTS (
           SELECT 1
           FROM desbloqueios d
           WHERE d.aluno_id = p_aluno_id
             AND d.ano = EXTRACT(YEAR  FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int
             AND d.mes = EXTRACT(MONTH FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int
         );
$fn$;

COMMENT ON FUNCTION public.aluno_bloqueado(uuid) IS
  'Verdadeiro quando o aluno tem um mes fechado por pagar, ja passou o '
  'dia_bloqueio, e a cantina nao lhe deu excecao este mes.';

-- A licao da 004, 005 e 006 aplicada a nascenca, como na 007.
REVOKE EXECUTE ON FUNCTION public.aluno_bloqueado(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.aluno_bloqueado(uuid) TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO DA SECCAO 1
-- =============================================================================
-- 1) O estado novo esta no CHECK, e os quatro antigos continuam la:
--
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conname = 'reservas_cancelamento_tipo_chk';
--   Esperado: ... ARRAY['user', 'payment', 'reactivated', 'contrato', 'bloqueado']
--
-- 2) A coluna ativa NAO mudou - continua a ser a lista branca de dois valores:
--
--   SELECT generation_expression FROM information_schema.columns
--   WHERE table_name = 'reservas' AND column_name = 'ativa';
--   Esperado: (cancelamento_tipo IS NULL) OR (cancelamento_tipo = 'reactivated'::text)
--
-- 3) O dia do bloqueio nasce a 15, uma linha so:
--
--   SELECT id, preco_almoco_sem_contrato, dia_bloqueio FROM configuracao;
--   Esperado: uma linha, t | <o preco> | 15
--
-- 4) A tabela nova tem RLS ligado e o anon nao lhe chega:
--
--   SELECT relrowsecurity FROM pg_class WHERE oid = 'public.desbloqueios'::regclass;
--   Esperado: t
--
--   SELECT grantee, privilege_type FROM information_schema.role_table_grants
--   WHERE table_name = 'desbloqueios' ORDER BY grantee, privilege_type;
--   Esperado: SO o postgres/owner e `authenticated | SELECT`. NENHUMA linha do
--   anon, e NENHUM INSERT/UPDATE/DELETE do authenticated.
--
-- 5) O predicado existe, corre com os direitos do dono, e o anon nao o chama:
--
--   SELECT proname, prosecdef, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace AND proname = 'aluno_bloqueado';
--   Esperado: uma linha, prosecdef = t, e no proacl NEM =X/ (o PUBLIC) NEM anon.
--
-- 6) Ninguem esta bloqueado so por isto ter sido aplicado. Numa base sem meses
--    fechados por pagar, tem de dar zero:
--
--   SELECT count(*) FROM alunos WHERE aluno_bloqueado(id);
--
-- 7) A lista de colunas escreviveis pelo authenticated na alunos continua a ser
--    exatamente (nome, email). A 011 nao lhe toca, mas a 008, a 009 e a 010
--    estreitaram-na e a verificacao pertence a todas as que vierem a seguir:
--
--   SELECT string_agg(column_name, ', ' ORDER BY column_name)
--   FROM information_schema.column_privileges
--   WHERE table_name = 'alunos' AND grantee = 'authenticated'
--     AND privilege_type = 'UPDATE';
--   Esperado: email, nome
-- =============================================================================


-- =============================================================================
-- SECCAO 2 - suspender, repor, e o gancho na liquidacao
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 2.1 - Suspender
-- -----------------------------------------------------------------------------
-- data >= HOJE, e nao data > HOJE. E DIFERENTE da 008/010, onde a mudanca de
-- contrato so mexe no estritamente futuro para nao arrancar a meio do dia um
-- almoco com que o aluno ja contava. Aqui a regra e "nao usa a cantina a partir
-- do dia X" e a tarefa corre de madrugada, antes de qualquer refeicao. E
-- deliberado: nao alinhar com a 008 sem ler isto.
--
-- O parametro opcional serve o revogar_desbloqueio (seccao 4), que precisa de
-- suspender um aluno so. NULL = todos.
CREATE OR REPLACE FUNCTION public.suspender_reservas_bloqueadas(p_aluno_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_n integer;
BEGIN
  UPDATE reservas r
     SET cancelamento_tipo = 'bloqueado'
   WHERE r.ativa
     AND r.data >= (now() AT TIME ZONE 'Europe/Lisbon')::date
     AND (p_aluno_id IS NULL OR r.aluno_id = p_aluno_id)
     AND public.aluno_bloqueado(r.aluno_id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $fn$;

COMMENT ON FUNCTION public.suspender_reservas_bloqueadas(uuid) IS
  'Suspende as refeicoes ativas de hoje em diante de quem esta bloqueado. '
  'Sem argumento, de todos.';

-- -----------------------------------------------------------------------------
-- 2.2 - Repor
-- -----------------------------------------------------------------------------
-- A ASSIMETRIA E A FUNCAO TODA. Voltam o futuro e o proprio dia; o passado FICA
-- suspenso para sempre, porque essas refeicoes nao chegaram a ser servidas e
-- nao podem ser cobradas. Um unico >= separa o correto de faturar comida
-- recusada.
--
-- O preco nao se toca. O reservas_guard congela o preco em UPDATE para toda a
-- gente e a UNICA excecao e a da 008 ('contrato' -> 'reactivated', porque uma
-- mudanca de contrato e mesmo um preco novo). Uma suspensao nao e um contrato
-- novo, por isso NAO entra na excecao - nao ha nada a escrever aqui, mas ha um
-- teste, porque a excecao do lado faz a resposta errada parecer plausivel.
CREATE OR REPLACE FUNCTION public.reativar_reservas_bloqueadas(p_aluno_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_n integer;
BEGIN
  UPDATE reservas r
     SET cancelamento_tipo = NULL
   WHERE r.aluno_id = p_aluno_id
     AND r.cancelamento_tipo = 'bloqueado'
     AND r.data >= (now() AT TIME ZONE 'Europe/Lisbon')::date;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $fn$;

COMMENT ON FUNCTION public.reativar_reservas_bloqueadas(uuid) IS
  'Repoe as refeicoes suspensas de hoje em diante. As passadas ficam suspensas '
  'para sempre: nao foram servidas e nao se cobram.';

-- -----------------------------------------------------------------------------
-- 2.3 - A reconciliacao diaria, NOS DOIS SENTIDOS
-- -----------------------------------------------------------------------------
-- O sentido de volta nao e um extra. Sem ele fica um buraco real: um aluno que
-- nunca paga DEIXA DE ESTAR BLOQUEADO no dia 1 - o dia e menor que o
-- dia_bloqueio - e ninguem lhe repoe as refeicoes suspensas, porque nao pagou e
-- nao teve excecao, e nenhum dos dois chamadores da reposicao dispara. Voltava
-- a poder marcar com as marcacoes que ja tinha mortas.
--
-- Diaria, e nao no dia 15: assim nao ha um dia no cron para manter alinhado com
-- o dia_bloqueio, que e uma definicao e pode mudar. Idempotente - quem ja esta
-- no estado certo nao da linhas.
CREATE OR REPLACE FUNCTION public.sincronizar_bloqueios()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_suspensas integer; v_repostas integer;
BEGIN
  v_suspensas := public.suspender_reservas_bloqueadas();

  -- Em conjunto, e nao aluno a aluno: e a mesma condicao da reposicao, so que
  -- sem fixar o aluno.
  UPDATE reservas r
     SET cancelamento_tipo = NULL
   WHERE r.cancelamento_tipo = 'bloqueado'
     AND r.data >= (now() AT TIME ZONE 'Europe/Lisbon')::date
     AND NOT public.aluno_bloqueado(r.aluno_id);
  GET DIAGNOSTICS v_repostas = ROW_COUNT;

  RETURN v_suspensas + v_repostas;
END; $fn$;

COMMENT ON FUNCTION public.sincronizar_bloqueios() IS
  'Tarefa diaria: suspende as refeicoes de quem passou a estar bloqueado e '
  'repoe as de quem deixou de estar. Idempotente.';

-- Estas tres sao chamadas pelo cron e pelas duas RPC da seccao 4, que sao elas
-- proprias SECURITY DEFINER e nao precisam da concessao. NENHUM papel da
-- aplicacao lhes chega.
--
-- Nao e enfeite: e a quarta vez neste projeto que uma funcao SECURITY DEFINER
-- ficou ao alcance de qualquer um - o fechar_mes_anterior e o
-- gerar_avisos_pagamento na 004, o rejeitar_cancelamento_especial na 005 e as
-- politicas do livro-razao na 006. O REVOKE ao PUBLIC e uma concessao separada
-- das dos dois papeis e sem ele o buraco ficava aberto na mesma.
REVOKE EXECUTE ON FUNCTION public.suspender_reservas_bloqueadas(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reativar_reservas_bloqueadas(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sincronizar_bloqueios()            FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2.4 - O gancho na liquidacao
-- -----------------------------------------------------------------------------
-- Corpo da 001 inteiro, mais o bloco do fim. Nada mais mudou: a verificacao do
-- RES04, o SECURITY DEFINER e as contas sao as mesmas.
CREATE OR REPLACE FUNCTION public.liquidar_mes_divida(p_aluno_id uuid, p_ano integer, p_mes integer)
RETURNS TABLE(success boolean, message text, valor_liquidado numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_valor numeric := 0;
  v_linhas integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode liquidar dividas'
      USING ERRCODE = 'RES04';
  END IF;

  SELECT COALESCE(SUM(preco), 0) INTO v_valor
  FROM reservas
  WHERE aluno_id = p_aluno_id
    AND EXTRACT(YEAR  FROM data) = p_ano
    AND EXTRACT(MONTH FROM data) = p_mes
    AND ativa;

  IF v_valor = 0 THEN
    RETURN QUERY SELECT false, 'Nao ha divida para este mes'::text, 0::numeric;
    RETURN;
  END IF;

  UPDATE reservas
  SET cancelamento_tipo = 'payment'
  WHERE aluno_id = p_aluno_id
    AND EXTRACT(YEAR  FROM data) = p_ano
    AND EXTRACT(MONTH FROM data) = p_mes
    AND ativa;

  GET DIAGNOSTICS v_linhas = ROW_COUNT;

  INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
  VALUES (p_aluno_id, p_ano, p_mes, v_valor, now());

  -- Pagou o ultimo mes em atraso? Entao as refeicoes futuras suspensas voltam
  -- ja. Pagamento parcial nao desbloqueia: havendo outro mes fechado por pagar,
  -- o aluno_bloqueado continua verdadeiro e isto nao faz nada.
  --
  -- A ORDEM IMPORTA: liquidar primeiro, repor depois. Ao contrario, as
  -- refeicoes repostas entravam na soma do mes que se esta a liquidar.
  IF NOT public.aluno_bloqueado(p_aluno_id) THEN
    PERFORM public.reativar_reservas_bloqueadas(p_aluno_id);
  END IF;

  RETURN QUERY SELECT true,
    format('%s reserva(s) liquidada(s) com sucesso', v_linhas)::text,
    v_valor;
END; $$;

COMMIT;
