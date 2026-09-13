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
