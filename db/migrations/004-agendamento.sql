-- =============================================================================
-- 004 - Agendamento (Cluster 5)
-- =============================================================================
-- DEPENDE DA 001 (fechar_mes_anterior, meses_em_divida) e da 003 (RLS das
-- notificacoes - ver a nota 2, que e a mais importante deste ficheiro).
--
-- Fecha o I5 e a parte 1B que ficou pendente do Cluster 1: o fecho do mes deixa
-- de ser uma coisa que alguem se tem de lembrar de correr, e os alunos passam a
-- ser avisados do que devem sem ninguem ter de o fazer a mao.
--
-- Tres agendamentos, todos em pg_cron:
--   fechar-mes      dia 1  as 01:00  -> fechar_mes_anterior()
--   avisos-inicial  dia 1  as 08:00  -> gerar_avisos_pagamento('inicial')
--   avisos-atraso   dia 11 as 08:00  -> gerar_avisos_pagamento('atraso')
--
-- A ORDEM E LOAD-BEARING. gerar_avisos_pagamento le meses_em_divida, e essa
-- tabela so tem linhas depois de fechar_mes_anterior correr. Por isso o fecho e
-- as 01:00 e o aviso as 08:00, no mesmo dia 1. Nao mexer num sem o outro.
--
-- HORAS EM UTC. O pg_cron agenda em UTC, por isso "08:00" e 09:00 em Lisboa no
-- verao e 08:00 no inverno. Decidido deixar assim: o que a regra da cantina fixa
-- sao os DIAS (10 e 15), nao a hora a que o aviso aparece. As datas nao mudam -
-- 01:00 UTC no dia 1 cai sempre no dia 1 em Lisboa.
--
-- -----------------------------------------------------------------------------
-- TRES DESVIOS AO PLANO (internal-solutions.md Cluster 5), todos deliberados
-- -----------------------------------------------------------------------------
-- 1. NAO REPETIR O MESMO AVISO. A versao do plano nao tem nada que impeca uma
--    segunda insercao igual se o job disparar duas vezes, ou se alguem chamar a
--    funcao a mao - o que vai acontecer, porque um cron mensal nao se testa a
--    esperar. Numa mensagem que acaba em "segue para a Direcao", mandar o mesmo
--    aviso duas vezes nao e um detalhe. Juntou-se um NOT EXISTS por
--    tipo + fase + ano + mes, e a fase passou a ficar gravada no `dados` (a
--    versao do plano nao a guardava, por isso depois nem se distinguia qual das
--    duas mensagens tinha sido enviada).
--
-- 2. O SECURITY DEFINER AGORA E ESSENCIAL, E NAO ERA QUANDO ISTO FOI ESCRITO.
--    A 003 PASSO 5 fechou o INSERT em notificacoes a quem nao e da cantina. Um
--    job do cron nao tem auth.uid() nenhum. Ou seja: sem SECURITY DEFINER esta
--    funcao insere ZERO linhas, SEM DAR ERRO - o cron acusa sucesso, o RETURN
--    devolve 0, e os alunos simplesmente nunca sao avisados. Nao ha nada no
--    ecra que denuncie isto. Se um dia alguem "simplificar" esta funcao, e este
--    o comentario que espero que leia primeiro.
--
-- 3. VALIDACAO DA FASE. O plano mete o p_fase direto num CASE, por isso um erro
--    de escrita ('inicia') caia no ELSE e mandava a TODOS a mensagem de atraso,
--    a que fala na Direcao. Agora rebenta.
-- =============================================================================

BEGIN;

-- PASSO 1 - a extensao. Disponivel no projeto (1.6.4) e nao instalada ate aqui.
-- O pg_net NAO e preciso: a decisao de 2026-07-22 e so notificacoes na app, sem
-- email nenhum. Ver o Cluster 4.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- PASSO 3 - a funcao dos avisos, antes dos agendamentos que a chamam.
CREATE OR REPLACE FUNCTION public.gerar_avisos_pagamento(p_fase text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
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
              THEN format('Tens %s€ por pagar de %s %s. Regulariza na cantina até dia 10.',
                          to_char(md.total,'FM990D00'), v_nomes[v_mes], v_ano)
              ELSE format('Continuas com %s€ por pagar de %s %s. Se não pagares até dia 15, segue para a Direção.',
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
END; $fn$;

COMMENT ON FUNCTION public.gerar_avisos_pagamento(text) IS
  'Avisos de pagamento na app, uma vez por aluno/mes/fase. TEM de ser SECURITY '
  'DEFINER: o cron nao tem auth.uid() e a RLS da 003 so deixa a cantina inserir '
  'notificacoes - sem definer isto insere zero linhas sem dar erro.';

-- PASSO 2 e 3 - os agendamentos.
-- unschedule primeiro, para o ficheiro poder ser colado outra vez sem duplicar
-- e sem depender da semantica de upsert do cron.schedule.
SELECT cron.unschedule(jobname)
FROM   cron.job
WHERE  jobname IN ('fechar-mes','avisos-inicial','avisos-atraso');

SELECT cron.schedule('fechar-mes',     '0 1 1 * *',  $job$ SELECT fechar_mes_anterior(); $job$);
SELECT cron.schedule('avisos-inicial', '0 8 1 * *',  $job$ SELECT gerar_avisos_pagamento('inicial'); $job$);
SELECT cron.schedule('avisos-atraso',  '0 8 11 * *', $job$ SELECT gerar_avisos_pagamento('atraso'); $job$);

COMMIT;

-- =============================================================================
-- VERIFICACAO (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) A extensao esta instalada.
--
--   SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_cron';
--
--   Esperado: 1 linha, pg_cron | 1.6.4
--
-- 2) Os tres jobs existem, ativos, com os horarios certos.
--
--   SELECT jobname, schedule, active, command
--   FROM   cron.job
--   WHERE  jobname IN ('fechar-mes','avisos-inicial','avisos-atraso')
--   ORDER  BY jobname;
--
--   Esperado (3 linhas):
--     avisos-atraso   0 8 11 * *  t  SELECT gerar_avisos_pagamento('atraso');
--     avisos-inicial  0 8 1 * *   t  SELECT gerar_avisos_pagamento('inicial');
--     fechar-mes      0 1 1 * *   t  SELECT fechar_mes_anterior();
--
--   Se algum aparecer duas vezes, o unschedule nao apanhou o nome - conferir.
--
-- 3) A funcao existe E e SECURITY DEFINER. A segunda coluna e a que interessa;
--    ver a nota 2 no cabecalho para perceber porque.
--
--   SELECT proname, prosecdef
--   FROM   pg_proc
--   WHERE  pronamespace = 'public'::regnamespace
--     AND  proname = 'gerar_avisos_pagamento';
--
--   Esperado: gerar_avisos_pagamento | t
--
-- 4) PROVA DE COMPORTAMENTO, e a que vale mais. Correr o bloco todo de uma vez.
--    Inventa uma divida do mes passado, gera os avisos duas vezes, e mostra o
--    que aconteceu. O ROLLBACK no fim nao deixa rasto nenhum.
--
--   BEGIN;
--     INSERT INTO meses_em_divida (aluno_id, ano, mes, data, total)
--     SELECT a.id,
--            EXTRACT(YEAR  FROM date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::int,
--            EXTRACT(MONTH FROM date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::int,
--            (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date,
--            12.50
--     FROM alunos a LIMIT 3;
--
--     SELECT gerar_avisos_pagamento('inicial') AS primeira_vez;   -- esperado: 3
--     SELECT gerar_avisos_pagamento('inicial') AS segunda_vez;    -- esperado: 0
--     SELECT gerar_avisos_pagamento('atraso')  AS fase_diferente; -- esperado: 3
--
--     SELECT dados->>'fase' AS fase, count(*)::int
--     FROM   notificacoes WHERE tipo = 'pagamento' GROUP BY 1 ORDER BY 1;
--     -- esperado: atraso 3, inicial 3
--   ROLLBACK;
--
--   O "segunda_vez: 0" e o desvio 1 a funcionar. Se der 3, o guarda de
--   repeticao nao esta la e os alunos vao levar o mesmo aviso as vezes que o
--   job disparar.
--
-- 5) O QUE NAO SE CONSEGUE VERIFICAR HOJE: que os jobs disparam mesmo. O
--    primeiro e a 1 de setembro as 01:00 UTC. Depois disso vale a pena espreitar
--
--      SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
--
--    e confirmar status = 'succeeded'. Ate la, o que esta provado e que os jobs
--    estao registados e que a funcao faz o que deve quando e chamada.
-- =============================================================================


-- =============================================================================
-- PASSO 4 - Quem pode EXECUTAR as funcoes do agendador
-- =============================================================================
-- ESTE PASSO FOI ESCRITO DEPOIS DE OS TRES PRIMEIROS JA TEREM SIDO APLICADOS.
-- Fica numa transacao propria porque foi mesmo isso que aconteceu: o problema so
-- apareceu ao escrever os testes do PASSO 3, e o ficheiro conta a historia como
-- ela foi em vez de fingir que ja estava tudo pensado desde o inicio.
--
-- O QUE SE ENCONTROU. As funcoes SECURITY DEFINER tinham a permissao de EXECUTE
-- que o PostgreSQL da por omissao - ao PUBLIC - mais concessoes explicitas ao
-- anon e ao authenticated:
--
--   proacl: =X/postgres | postgres=X | anon=X | authenticated=X | service_role=X
--            ^^^^^^^^^^ isto e o PUBLIC
--
-- A chave anon vai no supabase.js, dentro do browser. Portanto "so o anon
-- consegue" quer dizer "qualquer pessoa com um navegador consegue". E as duas
-- funcoes abaixo nao tem verificacao nenhuma la dentro sobre quem as chama:
--
--   fechar_mes_anterior()    fecha o mes da contabilidade. Alguem de fora podia
--                            fechar o mes quando lhe apetecesse. Esta e anterior
--                            ao Cluster 1 - o que a 004 fez foi decidir de quem
--                            ela e: do agendador, de mais ninguem.
--   gerar_avisos_pagamento() manda os avisos de pagamento a escola inteira. O
--                            guarda de repeticao impede o spam, mas nao impede
--                            que um estranho faca todos os alunos receber "tens
--                            X€ por pagar" no dia que escolher.
--
-- Nenhuma das duas e chamada por codigo nenhum da aplicacao - existem para os
-- jobs do cron, que correm como postgres. Por isso tirar-lhes o acesso publico
-- nao parte nada. Confirmado com grep em public/ e src/ antes de escrever isto.
--
-- REVOGAR SO AO anon E AO authenticated NAO CHEGAVA. O `=X` do inicio do proacl
-- e uma concessao ao PUBLIC, separada das outras duas: deixa-la la mantinha a
-- porta aberta a toda a gente e os testes continuariam vermelhos, com ar de que
-- o REVOKE tinha falhado em silencio. Por isso o PUBLIC vem primeiro na lista.
--
-- O QUE NAO SE TOCA, E PORQUE:
--   liquidar_mes_divida  a cantina chama-a mesmo, e ela ja confirma la dentro
--                        que quem chama e da cantina (001, RES04). Fechar-lhe o
--                        acesso partia a liquidacao - um remedio pior do que a
--                        doenca. Ha um teste no tier C so para isso.
--   reservar_refeicao    e para ser chamada pelos alunos. E o objetivo dela.
-- =============================================================================

BEGIN;

REVOKE EXECUTE ON FUNCTION public.fechar_mes_anterior()
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.gerar_avisos_pagamento(text)
  FROM PUBLIC, anon, authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 4 (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) As duas funcoes fechadas, as outras duas intactas. Uma consulta so, para
--    se ver o antes e o depois lado a lado.
--
--   SELECT p.proname,
--          coalesce(array_to_string(p.proacl::text[], ' | '), '(por omissao: PUBLIC)') AS acl
--   FROM   pg_proc p
--   WHERE  p.pronamespace = 'public'::regnamespace
--     AND  p.proname IN ('fechar_mes_anterior','gerar_avisos_pagamento',
--                        'liquidar_mes_divida','reservar_refeicao')
--   ORDER  BY p.proname;
--
--   Esperado:
--     fechar_mes_anterior      postgres=X/postgres | service_role=X/postgres
--     gerar_avisos_pagamento   postgres=X/postgres | service_role=X/postgres
--     liquidar_mes_divida      ... | anon=X | authenticated=X | service_role=X
--     reservar_refeicao        ... | anon=X | authenticated=X | service_role=X
--
--   NAS DUAS PRIMEIRAS NAO PODE APARECER `=X/postgres` sozinho no inicio: isso
--   e o PUBLIC, e se ainda la estiver o REVOKE nao apanhou tudo.
--   NAS DUAS ULTIMAS o anon e o authenticated TEM de continuar la. Se
--   desapareceram, o REVOKE foi longe demais e a liquidacao e a reserva partem.
--
-- 2) Os jobs continuam a poder correr. O cron executa como postgres, que
--    mantem o EXECUTE por ser o dono - mas convem ve-lo, nao supo-lo:
--
--   SELECT has_function_privilege('postgres', 'public.gerar_avisos_pagamento(text)', 'EXECUTE') AS cron_pode;
--
--   Esperado: t
--
-- 3) A prova a serio e a suite. No tier C, estes quatro passam a verde:
--      an anonymous caller cannot close the accounting month
--      a student cannot close the accounting month
--      a student cannot trigger the school's payment warnings
--      an anonymous caller cannot trigger the school's payment warnings
--    e este TEM de continuar verde, senao o REVOKE foi longe demais:
--      the canteen keeps the RPCs it actually uses
--
--    No tier B, os cinco testes dos avisos de pagamento tambem tem de continuar
--    verdes: correm pela ligacao direta como postgres, que nao foi tocado.
-- =============================================================================
