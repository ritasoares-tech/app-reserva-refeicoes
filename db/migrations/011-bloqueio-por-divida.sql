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
--   O pagamento vence no dia 8, mas o bloqueio pelo mes anterior so entra no
--   dia 15: e uma folga de uma semana para o que possa ter corrido mal pelo
--   meio. Uma divida de ha dois meses ou mais ja teve essa folga e bloqueia
--   todos os dias. Apanha as TRES
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
  'Dia do mes a partir do qual quem tem o mes ANTERIOR por pagar fica '
  'bloqueado. Meses mais antigos bloqueiam todos os dias. O pagamento vence '
  'no dia 8; o 15 e a folga acordada.';

-- -----------------------------------------------------------------------------
-- 1.3 - A excecao manual da cantina
-- -----------------------------------------------------------------------------
-- A cantina pode levantar o bloqueio COM A DIVIDA POR PAGAR - um acordo, uma
-- explicacao. A cantina aceitou a razao do atraso, e isso vale como ter pago
-- ATE AO PROXIMO PAGAMENTO: uma excecao dada no mes M cobre ate a vespera do
-- dia_bloqueio do mes M+1 (dia 14, com o 15 de sempre). Depois caduca; se o
-- acordo se mantiver, a cantina volta a dar. Regra do Pedro, 2026-09-13.
--
-- MESMA FORMA DA meses_liquidados, de proposito: e ja a tabela que responde
-- "este mes deste aluno esta tratado", e o predicado testa-a com o mesmo
-- EXISTS. Uma coluna na alunos respondia ao mesmo com o mesmo custo e PERDIA
-- QUEM AUTORIZOU E PORQUE, que e a unica razao para deixar passar uma divida.
--
-- Nao ha coluna de validade e nao ha tarefa de limpeza: o fim de uma excecao
-- calcula-se do (ano, mes) dela e do dia_bloqueio, pelo desbloqueio_ate (1.4),
-- e passado esse dia ela simplesmente deixa de contar. As linhas antigas ficam:
-- sao o registo de quem deixou passar uma divida e porque.
--
-- Porque nao so ate ao fim do mes: no dia 1 a divida que a excecao cobria passa
-- a ter dois meses, e uma divida de dois meses bloqueia todos os dias. A
-- excecao acabava por durar menos do que o proprio mes de tolerancia.
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
  'Excecoes dadas pela cantina: levantam o bloqueio de um aluno com a divida por '
  'pagar, do mes em que sao dadas ate a vespera do dia_bloqueio do mes seguinte '
  '(ver desbloqueio_ate). Guarda quem autorizou e porque.';

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
-- Bloqueado quando nao ha excecao da cantina em vigor (desbloqueio_ate) E:
--   a) existe um mes por pagar de ha DOIS meses ou mais - todos os dias; OU
--   b) o mes ANTERIOR esta por pagar e hoje ja e o dia_bloqueio ou depois.
--
-- A semana de tolerancia (do dia 8 ao 15) e para pagar o mes anterior e so
-- esse. Uma divida mais antiga ja teve a sua: sem a condicao a), um aluno que
-- nunca paga ficava desbloqueado do dia 1 ao 14 de cada mes, a acumular mais
-- divida. Regra do Pedro, 2026-09-13, depois de o resto da 011 estar feito.
--
-- "Por pagar" e COPIADO A LETRA do CTE 'passados' do obter_divida_por_mes (001),
-- para que as duas nunca possam discordar sobre o que e uma divida. O mes
-- corrente esta deliberadamente de fora: ninguem esta em divida pelas refeicoes
-- que esta a comer este mes.
--
-- ATENCAO AOS DOIS RELOGIOS, e e de proposito. O "por pagar" e os limites dos
-- meses usam CURRENT_DATE porque e assim que esta no obter_divida_por_mes e no
-- fechar_mes_anterior, e alinhar so aqui punha as duas definicoes de "mes
-- corrente" a divergir. O dia do bloqueio e a excecao sao novos e usam a data de Lisboa, como o prazo_limite (003)
-- e o registar_leitura (009). A diferenca entre as duas e a primeira hora do
-- dia 1 no verao. NAO "corrigir" uma para a outra sem mexer nas tres funcoes.
--
-- SECURITY DEFINER porque o aluno tem de poder saber que esta bloqueado sem ter
-- SELECT na meses_em_divida.
--
-- Primeiro, ATE QUANDO vale a excecao mais recente do aluno - o ultimo dia de
-- Lisboa que ainda cobre, ou NULL sem nenhuma. Uma funcao so, usada pelo
-- predicado, pelo revogar_desbloqueio e pelos dois ecras, para que "a excecao
-- esta em vigor" tenha uma definicao e o ecra mostre a data que o predicado usa.
--
--   (1 do mes seguinte ao da excecao) + (dia_bloqueio - 2) dias
--   = a vespera do dia_bloqueio do mes seguinte. Com dia_bloqueio 1 da o ultimo
--   dia do proprio mes, que e o certo: o bloqueio seguinte entra no dia 1.
CREATE OR REPLACE FUNCTION public.desbloqueio_ate(p_aluno_id uuid)
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT max((make_date(d.ano, d.mes, 1) + INTERVAL '1 month')::date
             + ((SELECT c.dia_bloqueio FROM configuracao c) - 2))
  FROM desbloqueios d
  WHERE d.aluno_id = p_aluno_id;
$fn$;

COMMENT ON FUNCTION public.desbloqueio_ate(uuid) IS
  'Ultimo dia (Lisboa) coberto pela excecao mais recente do aluno: a vespera do '
  'dia_bloqueio do mes seguinte ao da excecao. NULL sem nenhuma.';

REVOKE EXECUTE ON FUNCTION public.desbloqueio_ate(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.desbloqueio_ate(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.aluno_bloqueado(p_aluno_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  WITH por_pagar AS (
    SELECT make_date(md.ano, md.mes, 1) AS mes
    FROM meses_em_divida md
    WHERE md.aluno_id = p_aluno_id
      AND make_date(md.ano, md.mes, 1) < date_trunc('month', CURRENT_DATE)::date
      AND NOT EXISTS (
            SELECT 1 FROM meses_liquidados ml
            WHERE ml.aluno_id = md.aluno_id
              AND ml.ano = md.ano AND ml.mes = md.mes)
  )
  SELECT (
           -- a) ha dois meses ou mais: sem tolerancia
           EXISTS (SELECT 1 FROM por_pagar
                   WHERE mes < (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date)
           -- b) o mes anterior, so a partir do dia do bloqueio
        OR (    EXISTS (SELECT 1 FROM por_pagar
                        WHERE mes = (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date)
            AND EXTRACT(DAY FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int
                  >= (SELECT c.dia_bloqueio FROM configuracao c))
         )
     AND NOT coalesce(public.desbloqueio_ate(p_aluno_id)
                        >= (now() AT TIME ZONE 'Europe/Lisbon')::date, false);
$fn$;

COMMENT ON FUNCTION public.aluno_bloqueado(uuid) IS
  'Verdadeiro quando nao ha excecao em vigor e o aluno tem por '
  'pagar um mes de ha dois meses ou mais, ou o mes anterior depois do dia_bloqueio.';

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
--    fechados por pagar, tem de dar zero. NA ESCOLA nao da
--    zero e nao e erro - ver o ponto 11 da VERIFICACAO FINAL, no fim do ficheiro:
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
-- O sentido de volta nao e um extra. Um aluno pode deixar de estar bloqueado
-- sem pagar e sem excecao - o dia_bloqueio mudado para mais tarde, um mes
-- liquidado por outro caminho que nao o liquidar_mes_divida, a divida corrigida
-- a mao - e nenhum dos dois chamadores da reposicao dispara. Sem isto voltava a
-- poder marcar com as marcacoes que ja tinha mortas. (Quando isto foi escrito o
-- caso principal era o dia 1, em que um aluno que nunca pagava deixava de estar
-- bloqueado; com a regra de 2026-09-13 uma divida de dois meses ja nao tem
-- folga e esse caso deixou de existir.)
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


-- =============================================================================
-- SECCAO 3 - a guarda, o reservar_refeicao, e o almoco automatico
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 3.1 - A guarda
-- -----------------------------------------------------------------------------
-- Corpo da 003 PASSO 2 inteiro, mais UMA condicao em cada ramo. Nada mais
-- mudou: o RES03, o RES05, o RES06 e o RES07 estao como estavam.
--
-- A condicao esta escrita sobre o ESTADO RESULTANTE - "esta linha vai ficar
-- ativa?" - e nao sobre a operacao. Assim apanha de uma so vez a reserva nova,
-- a reativacao que o reservar_refeicao faz por ON CONFLICT, e qualquer chamada
-- direta ao PostgREST. E deixa passar o cancelamento, que torna a linha MENOS
-- ativa: quem nao consegue pagar deve poder tirar refeicoes da conta.
--
-- AS ISENCOES SAO O PONTO DE ESTAR AQUI DENTRO DO IF, e nao fora:
--   sistema (auth.uid() IS NULL) - a sincronizacao e os dois triggers de
--     alastramento TEM de conseguir escrever linhas 'bloqueado';
--   cantina - quem pode levantar o bloqueio inteiro nao pode ser travado por
--     ele. (Nota: a cantina nao tem politica de INSERT na reservas, so UPDATE,
--     por isso na pratica isto vale para alterar reservas que ja existem.)
CREATE OR REPLACE FUNCTION public.reservas_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_uid      uuid    := auth.uid();
  v_sistema  boolean := v_uid IS NULL;   -- service_role, triggers, migracoes
  v_staff    boolean := NOT (v_uid IS NULL)
                        AND EXISTS (SELECT 1 FROM cantina WHERE id = v_uid);
  m          record;
  v_contrato boolean;
  v_preco_sc numeric;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- F6: preco, tipo e data vem do menu. Nunca do cliente, para ninguem.
    SELECT preco, tipo, data INTO m FROM menus WHERE id = NEW.menu_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Menu inexistente' USING ERRCODE = 'RES03';
    END IF;
    NEW.tipo := m.tipo;
    NEW.data := m.data;

    NEW.preco := public.preco_para_reserva(NEW.aluno_id, m.tipo, m.preco);

    IF NOT v_sistema AND NOT v_staff THEN
      IF NEW.aluno_id <> v_uid THEN
        RAISE EXCEPTION 'So podes reservar para ti' USING ERRCODE = 'RES05';
      END IF;
      IF now() >= public.prazo_limite(NEW.tipo, NEW.data) THEN
        RAISE EXCEPTION 'Prazo ultrapassado para esta refeicao'
          USING ERRCODE = 'RES06';
      END IF;
      IF (NEW.cancelamento_tipo IS NULL OR NEW.cancelamento_tipo = 'reactivated')
         AND public.aluno_bloqueado(NEW.aluno_id) THEN
        RAISE EXCEPTION 'Tens valores em atraso. Regulariza na cantina.'
          USING ERRCODE = 'RES11';
      END IF;
    END IF;

  ELSE  -- UPDATE
    -- Imutaveis depois de criada, para toda a gente. Uma reserva nao muda de
    -- dono, de menu, de dia, de tipo nem de preco: se for preciso outra coisa,
    -- cancela-se esta e cria-se outra.
    NEW.aluno_id   := OLD.aluno_id;
    NEW.menu_id    := OLD.menu_id;
    NEW.data       := OLD.data;
    NEW.tipo       := OLD.tipo;
    NEW.criado_em  := OLD.criado_em;
    NEW.automatico := OLD.automatico;

    IF OLD.cancelamento_tipo = 'contrato' AND NEW.cancelamento_tipo = 'reactivated' THEN
      -- A excecao da 008: marcacao nova, preco de hoje. O 'bloqueado' NAO entra
      -- aqui de proposito - uma suspensao e a mesma refeicao nas mesmas
      -- condicoes, so retida uns dias, por isso o preco fica congelado como em
      -- qualquer outra reativacao.
      SELECT preco INTO m FROM menus WHERE id = OLD.menu_id;
      NEW.preco := public.preco_para_reserva(OLD.aluno_id, OLD.tipo, m.preco);
    ELSE
      NEW.preco := OLD.preco;
    END IF;

    IF NOT v_sistema AND NOT v_staff THEN
      IF NEW.cancelamento_tipo IS DISTINCT FROM OLD.cancelamento_tipo THEN
        IF NEW.cancelamento_tipo = 'payment' THEN
          RAISE EXCEPTION 'So a cantina pode liquidar reservas'
            USING ERRCODE = 'RES07';
        END IF;
        IF now() >= public.prazo_limite(OLD.tipo, OLD.data) THEN
          RAISE EXCEPTION 'Prazo ultrapassado para esta refeicao'
            USING ERRCODE = 'RES06';
        END IF;
      END IF;

      -- A dieta segue o prazo do almoco, como no Cluster 3 (F2).
      IF NEW.is_dieta IS DISTINCT FROM OLD.is_dieta
         AND now() >= public.prazo_limite(OLD.tipo, OLD.data) THEN
        RAISE EXCEPTION 'Prazo ultrapassado para alterar a dieta'
          USING ERRCODE = 'RES06';
      END IF;

      -- O bloqueio nao vale nada se o proprio aluno o puder desfazer. Mesma
      -- forma do buraco do 'payment' que o RES07 acima fecha.
      IF (NEW.cancelamento_tipo IS NULL OR NEW.cancelamento_tipo = 'reactivated')
         AND public.aluno_bloqueado(OLD.aluno_id) THEN
        RAISE EXCEPTION 'Tens valores em atraso. Regulariza na cantina.'
          USING ERRCODE = 'RES11';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END; $function$;


COMMENT ON FUNCTION public.reservas_guard() IS
  'Guarda de escrita em reservas: deriva preco/tipo/data do menu, congela os '
  'campos imutaveis, aplica o prazo do servidor a sessoes de aluno, e recusa a '
  'um aluno bloqueado qualquer escrita que deixe a reserva ativa. '
  'Cantina e contextos de sistema (auth.uid() IS NULL) passam ao lado.';

-- -----------------------------------------------------------------------------
-- 3.2 - O reservar_refeicao
-- -----------------------------------------------------------------------------
-- A guarda ja o cobre; isto e ERGONOMIA, e mesmo assim nao e opcional. O
-- ON CONFLICT so reativa linhas em 'user' ou 'contrato', por isso uma linha
-- 'bloqueado' nao entra la e o fluxo caia no ramo do RES01 - "ja tens uma
-- reserva para esta refeicao neste dia" - que e verdade e nao serve de nada a
-- quem precisa de saber que deve dinheiro.
--
-- E NAO acrescentar 'bloqueado' aquela lista do ON CONFLICT: isso deixava um
-- aluno bloqueado reativar a reserva suspensa, que e exatamente o que nao pode
-- acontecer.
CREATE OR REPLACE FUNCTION public.reservar_refeicao(p_menu_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  m record;
  v_estado text;
BEGIN
  SELECT id, data, tipo, preco INTO m FROM menus WHERE id = p_menu_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Menu inexistente' USING ERRCODE = 'RES03';
  END IF;

  IF public.aluno_bloqueado(auth.uid()) THEN
    RAISE EXCEPTION 'Tens valores em atraso. Regulariza na cantina.'
      USING ERRCODE = 'RES11';
  END IF;

  INSERT INTO reservas (aluno_id, menu_id, data, tipo, preco, is_dieta, automatico, cancelamento_tipo)
  VALUES (auth.uid(), m.id, m.data, m.tipo, m.preco, false, false, NULL)
  ON CONFLICT (aluno_id, data, tipo) DO UPDATE
    SET cancelamento_tipo = 'reactivated',
        menu_id           = EXCLUDED.menu_id,
        preco             = EXCLUDED.preco
    WHERE reservas.cancelamento_tipo IN ('user', 'contrato');

  IF NOT FOUND THEN
    SELECT r.cancelamento_tipo INTO v_estado
    FROM reservas r
    WHERE r.aluno_id = auth.uid() AND r.data = m.data AND r.tipo = m.tipo;

    IF v_estado = 'payment' THEN
      RAISE EXCEPTION 'Esta refeicao ja foi liquidada e nao pode ser reservada de novo'
        USING ERRCODE = 'RES02';
    ELSE
      RAISE EXCEPTION 'Ja tens uma reserva para esta refeicao neste dia'
        USING ERRCODE = 'RES01';
    END IF;
  END IF;
END; $function$;

-- -----------------------------------------------------------------------------
-- 3.3 - O almoco automatico de quem esta bloqueado nasce SUSPENSO
-- -----------------------------------------------------------------------------
-- E nao "nao nasce". As duas coisas sao iguais para o aluno e para o dinheiro -
-- a linha esta inativa de qualquer maneira, nao e servida nem cobrada - mas
-- sao diferentes NO DESBLOQUEIO. Se o alastramento SALTASSE o aluno, um aluno
-- que paga no dia 20 ficava sem almoco em todos os menus criados enquanto
-- esteve bloqueado, e a reposicao nao tinha linha nenhuma para repor: era
-- preciso um enchimento a posteriori, um segundo caminho de codigo, para
-- reparar um buraco aberto pelo proprio bloqueio.
--
-- Desvio ao que foi dito ("nao criar"), aprovado pelo Pedro a 2026-09-13.
CREATE OR REPLACE FUNCTION public.criar_reservas_automaticas_almoco()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  IF NEW.tipo = 'almoco' THEN
    INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta,
                          cancelamento_tipo)
    SELECT a.id, NEW.id, NEW.tipo, NEW.data, NEW.preco, true, false,
           CASE WHEN public.aluno_bloqueado(a.id) THEN 'bloqueado' ELSE NULL END
    FROM alunos a
    WHERE a.tipo_contrato = 'completo'
    ON CONFLICT (aluno_id, data, tipo) DO NOTHING;
  END IF;
  RETURN NEW;
END; $function$;

-- Trigger AFTER INSERT: o NEW.tipo_contrato ja vem com o default aplicado.
--
-- Um aluno acabado de inscrever nao tem meses fechados, por isso na pratica
-- nunca esta bloqueado. Fica na mesma pela uniformidade - e para nao ser uma
-- surpresa se um dia alguem inserir um aluno com historico.
CREATE OR REPLACE FUNCTION public.criar_reservas_almoco_novo_aluno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_local     timestamp := now() AT TIME ZONE 'Europe/Lisbon';
  v_hoje      date      := v_local::date;
  v_hora      time      := v_local::time;
  v_bloqueado text;
BEGIN
  IF NEW.tipo_contrato <> 'completo' THEN
    RETURN NEW;
  END IF;

  v_bloqueado := CASE WHEN public.aluno_bloqueado(NEW.id) THEN 'bloqueado' END;

  INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta,
                        cancelamento_tipo)
  SELECT NEW.id, m.id, m.tipo, m.data, m.preco, true, false, v_bloqueado
  FROM menus m
  WHERE m.tipo = 'almoco'
    AND (m.data > v_hoje OR (m.data = v_hoje AND v_hora < TIME '09:00'))
  ON CONFLICT (aluno_id, data, tipo) DO NOTHING;

  RETURN NEW;
END; $$;

COMMIT;


-- =============================================================================
-- SECCAO 4 - as duas RPC da cantina
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 4.1 - Conceder
-- -----------------------------------------------------------------------------
-- A cantina pode chegar a acordo com um aluno, ou aceitar uma explicacao, e
-- levantar o bloqueio COM A DIVIDA POR PAGAR. Fica registada no mes corrente e
-- vale ate a vespera do dia_bloqueio do mes seguinte (desbloqueio_ate).
--
-- ON CONFLICT DO UPDATE, e nao DO NOTHING: dar outra vez no mesmo mes e
-- corrigir a razao, nao um erro. Guarda sempre quem autorizou.
--
-- Devolve quantas refeicoes voltaram, que e o que o ecra mostra a cantina.
CREATE OR REPLACE FUNCTION public.conceder_desbloqueio(p_aluno_id uuid, p_motivo text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode desbloquear alunos'
      USING ERRCODE = 'RES04';
  END IF;

  INSERT INTO desbloqueios (aluno_id, ano, mes, motivo, cantina_responsavel)
  VALUES (p_aluno_id,
          EXTRACT(YEAR  FROM v_hoje)::int,
          EXTRACT(MONTH FROM v_hoje)::int,
          p_motivo, auth.uid())
  ON CONFLICT (aluno_id, ano, mes) DO UPDATE
    SET motivo              = EXCLUDED.motivo,
        cantina_responsavel = EXCLUDED.cantina_responsavel,
        criado_em           = now();

  RETURN public.reativar_reservas_bloqueadas(p_aluno_id);
END; $fn$;

COMMENT ON FUNCTION public.conceder_desbloqueio(uuid, text) IS
  'A cantina levanta o bloqueio de um aluno para o mes corrente, com a divida '
  'por pagar. Repoe logo as refeicoes suspensas e devolve quantas.';

-- -----------------------------------------------------------------------------
-- 4.2 - Revogar
-- -----------------------------------------------------------------------------
-- Apaga a excecao EM VIGOR E VOLTA A SUSPENDER JA. Em vigor e o que o
-- desbloqueio_ate cobre hoje - pode ser a do mes anterior, do dia 1 ao 14. As
-- que ja nao cobrem nada ficam, como registo. Sem a segunda metade,
-- revogar nao fazia nada visivel ate a tarefa da madrugada seguinte, que nao e
-- o que a palavra quer dizer.
--
-- Devolve quantas refeicoes voltaram a ser suspensas. Zero e uma resposta
-- legitima: o aluno pode ja ter pago entretanto.
CREATE OR REPLACE FUNCTION public.revogar_desbloqueio(p_aluno_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode desbloquear alunos'
      USING ERRCODE = 'RES04';
  END IF;

  -- A mesma conta do desbloqueio_ate, linha a linha.
  DELETE FROM desbloqueios d
   WHERE d.aluno_id = p_aluno_id
     AND (make_date(d.ano, d.mes, 1) + INTERVAL '1 month')::date
           + ((SELECT c.dia_bloqueio FROM configuracao c) - 2) >= v_hoje;

  RETURN public.suspender_reservas_bloqueadas(p_aluno_id);
END; $fn$;

COMMENT ON FUNCTION public.revogar_desbloqueio(uuid) IS
  'Retira a excecao em vigor e volta a suspender as refeicoes do aluno '
  'na mesma chamada. Devolve quantas foram suspensas.';

-- A cantina entra na aplicacao como um utilizador autenticado qualquer; e a
-- verificacao la dentro que a separa, como na 005 e na 007. O anon e o PUBLIC
-- nao chegam la.
REVOKE EXECUTE ON FUNCTION public.conceder_desbloqueio(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.revogar_desbloqueio(uuid)        FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.conceder_desbloqueio(uuid, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.revogar_desbloqueio(uuid)        TO authenticated;

COMMIT;


-- =============================================================================
-- SECCAO 5 - o leitor de codigo de barras
-- =============================================================================
BEGIN;

-- O sexto resultado. Nome da restricao confirmado na base viva, nao adivinhado.
ALTER TABLE public.leituras DROP CONSTRAINT leituras_resultado_check;
ALTER TABLE public.leituras ADD  CONSTRAINT leituras_resultado_check
  CHECK (resultado IN ('servido', 'sem_reserva', 'cancelada', 'repetido',
                       'codigo_desconhecido', 'bloqueado'));

-- Corpo da 009 inteiro, mais o bloco do bloqueio. Confirmado contra o
-- pg_get_functiondef da base antes de reescrever - a licao da seccao 3.
--
-- ONDE ENTRA E QUE INTERESSA: depois de resolver o aluno pelo codigo e ANTES de
-- ir ver a reserva. Estar bloqueado vale mais do que aquilo que a reserva diga,
-- e a cantina precisa da razao mesmo quando nao ha reserva nenhuma para
-- comentar - se a verificacao viesse depois, um aluno bloqueado sem reserva
-- saia como 'sem_reserva' e ninguem ao balcao percebia que era dinheiro.
CREATE OR REPLACE FUNCTION public.registar_leitura(p_codigo text, p_tipo text)
RETURNS TABLE(resultado text, nome text, is_dieta boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_hoje      date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_aluno     record;
  v_res       record;
  v_resultado text;
  v_reserva   uuid;
  v_dieta     boolean := false;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina c WHERE c.id = v_uid) THEN
    RAISE EXCEPTION 'Apenas a cantina pode registar leituras';
  END IF;

  IF p_tipo NOT IN ('pequeno_almoco', 'almoco', 'jantar') THEN
    RAISE EXCEPTION 'Tipo de refeicao invalido: %', p_tipo USING ERRCODE = 'LEI01';
  END IF;

  SELECT a.id, a.nome INTO v_aluno FROM alunos a WHERE a.codigo = p_codigo;

  IF NOT FOUND THEN
    INSERT INTO leituras (aluno_id, codigo_lido, tipo, data, resultado, criado_por)
    VALUES (NULL, p_codigo, p_tipo, v_hoje, 'codigo_desconhecido', v_uid);

    RETURN QUERY SELECT 'codigo_desconhecido'::text, NULL::text, false;
    RETURN;
  END IF;

  -- Devolve o nome: ao balcao e preciso dizer a alguem, e nao a um codigo.
  IF public.aluno_bloqueado(v_aluno.id) THEN
    INSERT INTO leituras (aluno_id, codigo_lido, tipo, data, resultado, criado_por)
    VALUES (v_aluno.id, p_codigo, p_tipo, v_hoje, 'bloqueado', v_uid);

    RETURN QUERY SELECT 'bloqueado'::text, v_aluno.nome, false;
    RETURN;
  END IF;

  -- No maximo uma linha: reservas tem UNIQUE (aluno_id, data, tipo) desde a 001.
  SELECT r.id, r.ativa, r.is_dieta INTO v_res
  FROM reservas r
  WHERE r.aluno_id = v_aluno.id AND r.data = v_hoje AND r.tipo = p_tipo;

  IF NOT FOUND THEN
    v_resultado := 'sem_reserva';
  ELSIF NOT v_res.ativa THEN
    -- Separavel do sem_reserva unicamente porque a linha cancelada sobrevive.
    v_resultado := 'cancelada';
    v_reserva   := v_res.id;
  ELSIF EXISTS (
      SELECT 1 FROM leituras l
      WHERE l.aluno_id  = v_aluno.id
        AND l.data      = v_hoje
        AND l.tipo      = p_tipo
        AND l.resultado = 'servido'
  ) THEN
    v_resultado := 'repetido';
    v_reserva   := v_res.id;
    v_dieta     := coalesce(v_res.is_dieta, false);
  ELSE
    v_resultado := 'servido';
    v_reserva   := v_res.id;
    v_dieta     := coalesce(v_res.is_dieta, false);
  END IF;

  INSERT INTO leituras (aluno_id, codigo_lido, tipo, data, resultado, reserva_id, criado_por)
  VALUES (v_aluno.id, p_codigo, p_tipo, v_hoje, v_resultado, v_reserva, v_uid);

  RETURN QUERY SELECT v_resultado, v_aluno.nome, v_dieta;
END; $function$;

COMMIT;


-- =============================================================================
-- SECCAO 6 - os agendamentos e os textos dos avisos
-- =============================================================================
-- O pagamento passa a vencer no DIA 8 (era 10). Muda o texto dos dois avisos, o
-- dia do segundo aviso (11 -> 9), e entra a tarefa do bloqueio.
--
-- Os dois manuais em docs/ dizem dia 10 e mudam com isto.
--
-- ATENCAO A CODIFICACAO desta seccao: e a unica com acentos e com o simbolo do
-- euro, porque as mensagens sao texto que o aluno le. O ficheiro e UTF-8. Se
-- for acrescentado ou editado por uma ferramenta que leia em ANSI e escreva em
-- UTF-8 - o Get-Content/Add-Content do PowerShell 5.1 faz exatamente isso - o
-- texto fica duplamente codificado e o aluno recebe "atA(c) dia 8". Ja
-- aconteceu uma vez, a 2026-09-13, e so um teste que olha para a mensagem e que
-- apanha isso.
BEGIN;

-- Corpo da 004 inteiro, so com as duas datas nos textos. Confirmado contra o
-- pg_get_functiondef da base viva antes de reescrever.
CREATE OR REPLACE FUNCTION public.gerar_avisos_pagamento(p_fase text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  mes_ref date := date_trunc('month', CURRENT_DATE) - INTERVAL '1 month';
  v_ano   int  := EXTRACT(YEAR  FROM mes_ref);
  v_mes   int  := EXTRACT(MONTH FROM mes_ref);
  v_nomes text[] := ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
                          'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
  v_n     int;
BEGIN
  -- Desvio 3: sem isto, uma fase mal escrita manda a mensagem da Direcao a toda
  -- a gente, e em silencio.
  IF p_fase NOT IN ('inicial','atraso') THEN
    RAISE EXCEPTION 'Fase invalida: %. Usar inicial ou atraso.', p_fase;
  END IF;

  INSERT INTO notificacoes (aluno_id, tipo, titulo, mensagem, dados)
  SELECT md.aluno_id,
         'pagamento',
         CASE WHEN p_fase = 'inicial' THEN 'Pagamento em falta'
                                      ELSE 'Pagamento em atraso' END,
         CASE WHEN p_fase = 'inicial'
              THEN format('Tens %s€ por pagar de %s %s. Regulariza na cantina até dia 8.',
                          to_char(md.total,'FM990D00'), v_nomes[v_mes], v_ano)
              ELSE format('Continuas com %s€ por pagar de %s %s. Se não pagares até dia 15, segue para a Direção e ficas sem poder usar a cantina.',
                          to_char(md.total,'FM990D00'), v_nomes[v_mes], v_ano)
         END,
         jsonb_build_object('ano', v_ano, 'mes', v_mes, 'total', md.total, 'fase', p_fase)
  FROM meses_em_divida md
  WHERE md.ano = v_ano
    AND md.mes = v_mes
    -- Quem ja pagou nao leva aviso.
    AND NOT EXISTS (
      SELECT 1 FROM meses_liquidados ml
      WHERE ml.aluno_id = md.aluno_id AND ml.ano = v_ano AND ml.mes = v_mes)
    -- Desvio 1: e quem ja levou este aviso tambem nao leva outro igual.
    AND NOT EXISTS (
      SELECT 1 FROM notificacoes n
      WHERE n.aluno_id = md.aluno_id
        AND n.tipo = 'pagamento'
        AND n.dados->>'fase' = p_fase
        AND (n.dados->>'ano')::int = v_ano
        AND (n.dados->>'mes')::int = v_mes);

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $function$;

-- Tirar por nome e voltar a agendar, como na 004: sem depender da semantica de
-- upsert do cron.schedule.
--
-- A 004 fazia DELETE FROM cron.job. AQUI NAO SERVE: a 004 foi colada no editor
-- de SQL do Supabase, onde corre com um papel privilegiado, e pelo pooler o
-- DELETE direto na cron.job da "permission denied for table job". O
-- cron.unschedule e a API suportada e passa nos dois sitios - na escola, colado
-- a mao, funciona na mesma.
--
-- O IF EXISTS e preciso porque o unschedule rebenta com um nome que nao existe,
-- e o bloquear-devedores ainda nao existe da primeira vez.
DO $desagendar$
DECLARE j text;
BEGIN
  FOREACH j IN ARRAY ARRAY['fechar-mes','avisos-inicial','avisos-atraso','bloquear-devedores']
  LOOP
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = j) THEN
      PERFORM cron.unschedule(j);
    END IF;
  END LOOP;
END $desagendar$;

SELECT cron.schedule('fechar-mes',     '0 1 1 * *',  $job$ SELECT fechar_mes_anterior(); $job$);
SELECT cron.schedule('avisos-inicial', '0 8 1 * *',  $job$ SELECT gerar_avisos_pagamento('inicial'); $job$);
SELECT cron.schedule('avisos-atraso',  '0 8 9 * *',  $job$ SELECT gerar_avisos_pagamento('atraso'); $job$);

-- DIARIA, e nao no dia 15. A tarefa nao decide nada: quem decide e o
-- aluno_bloqueado, que le o dia_bloqueio da configuracao. Prende-la ao dia 15
-- era pos uma data no cron a ter de acompanhar uma definicao que pode mudar.
-- E e nos dois sentidos, por isso tem de correr todos os dias para repor as
-- refeicoes de quem deixou de estar bloqueado na viragem do mes.
--
-- 02:00 UTC = 02:00 ou 03:00 em Lisboa, sempre dentro do dia de Lisboa que esta
-- a reconciliar, que e o fuso que o aluno_bloqueado le. Correr isto mais cedo
-- parte essa correspondencia: as 23:00 UTC ja e o dia seguinte em Lisboa.
SELECT cron.schedule('bloquear-devedores', '0 2 * * *', $job$ SELECT sincronizar_bloqueios(); $job$);

COMMIT;

-- =============================================================================
-- VERIFICACAO DA SECCAO 6
-- =============================================================================
-- 1) Quatro tarefas, com os dias novos:
--
--   SELECT jobname, schedule, active FROM cron.job
--   WHERE jobname IN ('fechar-mes','avisos-inicial','avisos-atraso','bloquear-devedores')
--   ORDER BY jobname;
--   Esperado: avisos-atraso 0 8 9 * * | avisos-inicial 0 8 1 * * |
--             bloquear-devedores 0 2 * * * | fechar-mes 0 1 1 * *, todas active.
--
-- 2) OS ACENTOS. Correr isto e LER a saida - nao basta a funcao existir:
--
--   SELECT prosrc FROM pg_proc WHERE proname = 'gerar_avisos_pagamento';
--   Esperado: 'Março', 'até dia 8', 'não', 'Direção' e o simbolo do euro
--   legiveis. Se aparecer "MarA§o" ou "atA(c)" ou "a,¬", o ficheiro foi
--   gravado com dupla codificacao - nao aplicar na escola assim.
-- =============================================================================


-- =============================================================================
-- SECCAO 7 - quem esta bloqueado, para a lista de Valores Pendentes
-- =============================================================================
-- Nao estava no plano, que so dizia "a lista marca os alunos bloqueados". A
-- forma obvia de o fazer no browser era ler a meses_em_divida inteira e fazer a
-- conta la - e uma leitura de tabela inteira pelo PostgREST para nas 1000
-- linhas EM SILENCIO, o defeito ja encontrado tres vezes nesta app (a ultima e
-- a razao de existir o saldos_por_aluno da 007). A alternativa, uma chamada ao
-- aluno_bloqueado por aluno, eram ~150 pedidos cada vez que o ecra abre.
--
-- Uma funcao, e o MESMO predicado: nao ha segunda definicao de "bloqueado" a
-- poder divergir da primeira.
BEGIN;

CREATE OR REPLACE FUNCTION public.alunos_bloqueados()
RETURNS SETOF uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode ver os alunos bloqueados'
      USING ERRCODE = 'RES04';
  END IF;

  RETURN QUERY SELECT a.id FROM alunos a WHERE public.aluno_bloqueado(a.id);
END; $fn$;

COMMENT ON FUNCTION public.alunos_bloqueados() IS
  'Os ids dos alunos que o aluno_bloqueado da como bloqueados. So a cantina.';

REVOKE EXECUTE ON FUNCTION public.alunos_bloqueados() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.alunos_bloqueados() TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO DA SECCAO 7
-- =============================================================================
--   SELECT prosecdef, proacl FROM pg_proc WHERE proname = 'alunos_bloqueados';
--   Esperado: prosecdef = t, sem `anon=` e sem `=X/postgres`.
--
--   SELECT count(*) FROM alunos a WHERE aluno_bloqueado(a.id);
--   Esperado: o numero de alunos que a lista de Valores Pendentes marca.
-- =============================================================================


-- =============================================================================
-- VERIFICACAO FINAL - para colar no editor de SQL da escola depois das 7 seccoes
-- =============================================================================
-- Tudo o que as verificacoes das seccoes dizem, junto, mais o que so faz
-- sentido no fim. Correr uma a uma e comparar com o Esperado. As que leem
-- saldos_por_aluno() tem de ser corridas pela app (como a cantina) ou vistas no
-- ecra de Valores Pendentes: a funcao recusa uma ligacao sem auth.uid().
--
-- ANTES DE APLICAR, apontar os valores de referencia (ver 10):
--
--   SELECT coalesce(cancelamento_tipo, '(ativa)') AS estado, count(*), sum(preco)
--   FROM reservas GROUP BY 1 ORDER BY 1;
--
-- 1) Os cinco estados da reserva, e a ativa inalterada:
--
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conname = 'reservas_cancelamento_tipo_chk';
--   Esperado: ARRAY['user', 'payment', 'reactivated', 'contrato', 'bloqueado']
--
--   SELECT generation_expression FROM information_schema.columns
--   WHERE table_name = 'reservas' AND column_name = 'ativa';
--   Esperado: (cancelamento_tipo IS NULL) OR (cancelamento_tipo = 'reactivated'::text)
--
-- 2) Os seis resultados do leitor:
--
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--   WHERE conname = 'leituras_resultado_check';
--   Esperado: servido, sem_reserva, cancelada, repetido, codigo_desconhecido, bloqueado
--
-- 3) desbloqueios: RLS ligado, o anon sem nada, o authenticated so com SELECT,
--    e as duas politicas de leitura:
--
--   SELECT relrowsecurity FROM pg_class WHERE oid = 'public.desbloqueios'::regclass;
--   Esperado: t
--
--   SELECT grantee, privilege_type FROM information_schema.role_table_grants
--   WHERE table_name = 'desbloqueios' AND grantee IN ('anon', 'authenticated');
--   Esperado: uma linha so, authenticated | SELECT
--
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'desbloqueios' ORDER BY 1;
--   Esperado: desbloqueios_aluno_le_os_seus | SELECT e desbloqueios_cantina_le_todos | SELECT
--
-- 4) O dia do bloqueio:
--
--   SELECT dia_bloqueio FROM configuracao;
--   Esperado: uma linha, 15
--
-- 5) As funcoes que a app chama: SECURITY DEFINER, o authenticated chega-lhes,
--    o anon e o PUBLIC nao:
--
--   SELECT proname, prosecdef, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('aluno_bloqueado', 'alunos_bloqueados', 'desbloqueio_ate',
--                     'conceder_desbloqueio', 'revogar_desbloqueio')
--   ORDER BY 1;
--   Esperado: cinco linhas, prosecdef = t, `authenticated=X` no proacl, e
--   NEM `anon=` NEM uma entrada a comecar por `=X/` (o PUBLIC).
--
-- 6) As tres funcoes internas: ninguem de fora lhes chega, nem o authenticated.
--    Correm do cron e de dentro das funcoes acima:
--
--   SELECT proname, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('suspender_reservas_bloqueadas', 'reativar_reservas_bloqueadas',
--                     'sincronizar_bloqueios')
--   ORDER BY 1;
--   Esperado: tres linhas, e no proacl NEM `authenticated=` NEM `anon=` NEM `=X/`.
--
-- 7) As quatro tarefas agendadas:
--
--   SELECT jobname, schedule, active FROM cron.job
--   WHERE jobname IN ('fechar-mes', 'avisos-inicial', 'avisos-atraso', 'bloquear-devedores')
--   ORDER BY jobname;
--   Esperado: avisos-atraso 0 8 9 * * | avisos-inicial 0 8 1 * * |
--             bloquear-devedores 0 2 * * * | fechar-mes 0 1 1 * *, todas active.
--
-- 8) OS ACENTOS dos avisos. LER a saida:
--
--   SELECT prosrc FROM pg_proc WHERE proname = 'gerar_avisos_pagamento';
--   Esperado: 'Março', 'até dia 8', 'não', 'Direção' legiveis. "MarA§o" ou
--   "atA(c)" = ficheiro com dupla codificacao; desfazer e nao usar assim.
--
-- 9) A lista de colunas escreviveis na alunos continua exatamente (nome, email).
--    A 011 nao lhe toca; a 008, a 009 e a 010 estreitaram-na:
--
--   SELECT string_agg(column_name, ', ' ORDER BY column_name)
--   FROM information_schema.column_privileges
--   WHERE table_name = 'alunos' AND grantee = 'authenticated' AND privilege_type = 'UPDATE';
--   Esperado: email, nome
--
-- 10) NENHUM VALOR SE MOVEU. A consulta de antes, outra vez:
--
--   SELECT coalesce(cancelamento_tipo, '(ativa)') AS estado, count(*), sum(preco)
--   FROM reservas GROUP BY 1 ORDER BY 1;
--   Esperado: identico ao de antes de aplicar, ate a tarefa das 02:00 correr -
--   nao ha 'bloqueado' nenhum antes disso. Depois, ver 11.
--
-- 11) QUEM FICA BLOQUEADO, e isto NAO e um erro a corrigir:
--
--   SELECT a.nome FROM alunos a WHERE aluno_bloqueado(a.id) ORDER BY 1;
--
--   Na copia de testes da zero. NA ESCOLA, SE AS MIGRACOES FOREM APLICADAS
--   JUNTAS (001 a 011) TAMBEM DA ZERO: a 001 faz TRUNCATE a reservas,
--   meses_em_divida e meses_liquidados, e sem meses em divida ninguem fica
--   bloqueado. So nao da zero se a 011 for aplicada numa base que ja tenha
--   dividas registadas - e ai, em QUALQUER DIA do mes, todo o
--   aluno com um mes por pagar de ha dois meses ou mais fica bloqueado no
--   momento em que a 011 e aplicada; e a partir do dia 15 juntam-se os que so
--   devem o mes anterior. Ficam logo sem poder reservar; as refeicoes deles sao
--   suspensas na tarefa das 02:00 UTC seguinte, e a partir dai o 10 deixa de dar
--   identico - pelas refeicoes futuras deles, que passam a 'bloqueado'. A
--   cantina tem de saber, ANTES de aplicar, quem vai ficar bloqueado. Com a 011
--   ainda por aplicar, a lista sai daqui (o mes anterior so conta a partir do
--   dia 15; os mais antigos contam sempre):
--
--   SELECT a.nome, md.ano, md.mes, md.total
--   FROM meses_em_divida md JOIN alunos a ON a.id = md.aluno_id
--   WHERE make_date(md.ano, md.mes, 1) < date_trunc('month', CURRENT_DATE)::date
--     AND NOT EXISTS (SELECT 1 FROM meses_liquidados ml
--                     WHERE ml.aluno_id = md.aluno_id AND ml.ano = md.ano AND ml.mes = md.mes)
--   ORDER BY a.nome, md.ano, md.mes;
-- =============================================================================
