-- =============================================================================
-- 006 - Limpeza (Cluster 7)
-- =============================================================================
-- DEPENDE DA 001 (a coluna `cancelada` foi apagada la) e da 005 (o rasto em
-- cancelamentos_especiais, que o PASSO 3 tem de respeitar).
--
-- O passo 1 do plano acordado - largar quatro funcoes perigosas ou superadas -
-- JA ESTAVA FEITO: as quatro foram largadas na propria 001, linhas 303-306. Nao
-- sobra nada dele, e esta migracao nao repete nada.
--
-- DUAS COISAS AQUI NAO CONSTAM DO PLANO, e sao as duas mais serias do cluster:
--
--   PASSO 2 - qualquer aluno com sessao iniciada podia apagar e inventar
--             registos no livro-razao das dividas da escola inteira;
--   PASSO 4 - o relatorio mensal perde, hoje e em silencio, tudo o que passe
--             das 1000 linhas.
--
-- Nenhuma das duas e regressao deste trabalho: as duas ja la estavam. Entram
-- aqui porque a regra acordada e desviar do plano quando se encontra um erro ou
-- um risco de seguranca, e sao as duas coisas.
-- =============================================================================


-- =============================================================================
-- PASSO 1 - largar as sete assinaturas de relatorio partidas
-- =============================================================================
-- E a seccao 12 da 001, que ficou comentada de propria vontade a espera desta
-- decisao. Tres factos, medidos em 2026-08-09 contra a copia:
--
--   1. As sete leem a coluna `cancelada`, que a 001 apagou. O corpo de uma
--      funcao plpgsql so e analisado quando corre, por isso nenhuma delas deu
--      erro na migracao - dao erro na primeira chamada a serio. Ou seja: TODAS
--      estao partidas. (Verificado em pg_proc.prosrc.)
--   2. Nenhuma tem um unico chamador no JS.
--   3. Nenhuma e chamada por outra funcao. (Procurado em todos os prosrc do
--      schema public.)
--
-- E o ecra do relatorio nao precisa delas: o gerarRelatorioMensal() do
-- cantina.js consulta a tabela reservas diretamente. A funcionalidade nao perde
-- nada.
--
-- O plano dizia "senao, deixar (inofensivas)". Essa frase foi escrita a pensar
-- em funcoes que funcionam e ninguem usa. Estas nao funcionam - deixa-las e
-- guardar sete minas que rebentam a primeira vez que alguem lhes toque.
--
-- SAO SETE ASSINATURAS PARA SEIS NOMES: verificar_mes_com_dados tem duas
-- sobrecargas, integer e bigint, e as duas tem de cair.
--
-- E REPARAR NOS TIPOS: pode_gerar_relatorio recebe BIGINT. Escrito com integer,
-- o DROP nao faz nada e nao se queixa. E exatamente o erro que a 001 cometeu e
-- que so foi apanhado quando o schema real foi extraido.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.aluno_tem_divida_mes(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.gerar_relatorio_mensal(integer, integer);
DROP FUNCTION IF EXISTS public.resumo_mensal(integer, integer);
DROP FUNCTION IF EXISTS public.listar_meses_disponiveis();
DROP FUNCTION IF EXISTS public.pode_gerar_relatorio(bigint, bigint);
DROP FUNCTION IF EXISTS public.verificar_mes_com_dados(bigint, bigint);
DROP FUNCTION IF EXISTS public.verificar_mes_com_dados(integer, integer);

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 1
-- =============================================================================
-- 1) Nenhuma delas sobreviveu:
--
--   SELECT proname, pg_get_function_identity_arguments(oid)
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('aluno_tem_divida_mes','gerar_relatorio_mensal','resumo_mensal',
--                     'listar_meses_disponiveis','pode_gerar_relatorio',
--                     'verificar_mes_com_dados');
--
--   Esperado: ZERO linhas.
--   Se aparecer alguma, o DROP dessa errou os tipos e foi um no-op silencioso.
--
-- 2) A contagem bate certo:
--
--   SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace;
--
--   Esperado: 34 antes desta migracao, 27 depois deste passo, 29 no fim do
--   ficheiro (o PASSO 3 e o PASSO 4 criam uma funcao cada).
-- =============================================================================


-- =============================================================================
-- PASSO 2 - fechar o meses_em_divida   (NAO CONSTA DO PLANO - seguranca)
-- =============================================================================
-- Medido em 2026-08-09, em pg_policies:
--
--   DELETE  to authenticated  USING (true)
--   INSERT  to authenticated  WITH CHECK (true)
--
-- Ou seja: qualquer aluno com sessao iniciada podia apagar o livro-razao INTEIRO
-- da escola, ou inventar dividas a quem quisesse. Nao e a divida dele - e a de
-- toda a gente, porque o USING e literalmente `true`.
--
-- E a tabela que o fechar_mes_anterior escreve no dia 1 de cada mes e que os
-- avisos de pagamento leem. Apagada, ninguem e cobrado nesse mes, e nada parece
-- avariado: nao ha erro, nao ha ecra em branco, so nao ha divida nenhuma.
--
-- Nenhuma das duas politicas faz falta a ninguem. Os unicos escritores
-- legitimos sao o fechar_mes_anterior e o liquidar_mes_divida, os dois SECURITY
-- DEFINER, que passam ao lado da RLS por definicao. As duas politicas de SELECT
-- ("Aluno ve sua divida" e "Cantina ve todas as dividas") ficam intactas.
--
-- E o mesmo tratamento que o Cluster 2, passo 4b, deu ao meses_liquidados. Esta
-- tabela simplesmente nunca foi auditada da mesma maneira.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "permitir apagar meses em divida"  ON public.meses_em_divida;
DROP POLICY IF EXISTS "permitir inserir meses em divida" ON public.meses_em_divida;

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 2
-- =============================================================================
--   SELECT cmd, policyname, qual, with_check
--   FROM pg_policies
--   WHERE schemaname = 'public' AND tablename = 'meses_em_divida'
--   ORDER BY cmd;
--
--   Esperado: SO as duas de SELECT. Nem DELETE nem INSERT.
--
-- Na suite, e isto que da significado ao passo: os testes
--   "a student cannot delete the debt ledger"
--   "a student cannot invent debt"
-- falhavam OS DOIS antes desta migracao - o primeiro devolvia 0 linhas restantes
-- e o segundo 1 linha inventada - e passam os dois depois. Foram escritos e
-- vistos a falhar contra a base de dados como estava, que e a unica maneira de
-- um guarda provar alguma coisa.
-- =============================================================================


-- =============================================================================
-- PASSO 3 - purga manual das reservas liquidadas
-- =============================================================================
-- A decisao 1 (apagar reservas na liquidacao, ou manter o 'payment') continua
-- com o dono da escola, sem resposta. Por isso esta migracao NAO MUDA
-- COMPORTAMENTO NENHUM: nada e apagado, nao ha job agendado, nao ha botao. Isto
-- e so a ferramenta, para a opcao existir se ele a quiser.
--
-- E a decisao deixou de assentar em palpites. Medido em 2026-08-09 com o
-- protocolo da suite - snapshot, semear, medir, repor (tests/medir-espaco.ts,
-- registado em docs/medicao-espaco.md):
--
--   200 alunos (a escola tem 149), os 365 dias de 2025 (a escola tem ~180 dias
--   letivos), tres refeicoes por aluno por dia, zero cancelamentos, tudo
--   liquidado = 219.000 reservas e 89,4 MB. Sao 426 bytes por reserva, indices
--   incluidos. No free tier de 500 MB da para uns cinco anos e meio.
--
--   A escola a serio: ~34 MB por ano, uns catorze anos.
--
-- Conclusao para levar ao dono: purgar e uma preferencia, nao uma necessidade.
--
-- -----------------------------------------------------------------------------
-- TEM DE SALTAR AS RESERVAS COM RASTO, e isto nao e um detalhe
-- -----------------------------------------------------------------------------
-- cancelamentos_especiais.reserva_id referencia reservas SEM ON DELETE nenhum.
-- Apagar uma reserva que tenha registo rebenta com violacao de chave
-- estrangeira e leva a purga inteira atras dela.
--
-- E alcancavel, nao e teorico: uma decisao 'outros' ou 'dieta' deixa a refeicao
-- ativa e servida, logo e liquidada mais tarde continuando a ter registo - tal
-- como qualquer cantina_alterar_reserva, que deixa rasto sempre.
--
-- Apagar em cascata, ou apagar primeiro as linhas dependentes, destruia o rasto
-- que o Cluster 6 existe para criar - e destruia-o precisamente nas refeicoes
-- sobre as quais alguem teve de decidir alguma coisa, que sao as unicas que
-- interessam a alguem mais tarde.
--
-- Por isso a funcao apaga o que pode e DEVOLVE AS DUAS CONTAS, em vez de um
-- numero sozinho que esconderia o que se recusou a tocar.
--
-- Recebe uma DATA e nao "ha mais de N meses", para quem chama ter de dizer
-- exatamente o que desaparece.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.purgar_reservas_liquidadas(p_antes_de date)
RETURNS TABLE(apagadas integer, preservadas integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_apagadas    integer := 0;
  v_preservadas integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode purgar reservas';
  END IF;

  SELECT count(*)::int INTO v_preservadas
  FROM reservas r
  WHERE r.cancelamento_tipo = 'payment'
    AND r.data < p_antes_de
    AND EXISTS (SELECT 1 FROM cancelamentos_especiais ce WHERE ce.reserva_id = r.id);

  DELETE FROM reservas r
  WHERE r.cancelamento_tipo = 'payment'
    AND r.data < p_antes_de
    AND NOT EXISTS (SELECT 1 FROM cancelamentos_especiais ce WHERE ce.reserva_id = r.id);

  GET DIAGNOSTICS v_apagadas = ROW_COUNT;

  RETURN QUERY SELECT v_apagadas, v_preservadas;
END; $fn$;

-- A licao da 004 e da 005 aplicada a nascenca: uma funcao nova nasce com EXECUTE
-- para o PUBLIC, que e uma concessao SEPARADA do anon e do authenticated.
-- Revogar so aos dois papeis deixava o buraco aberto na mesma.
REVOKE EXECUTE ON FUNCTION public.purgar_reservas_liquidadas(date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.purgar_reservas_liquidadas(date) TO authenticated;

COMMIT;


-- =============================================================================
-- PASSO 4 - relatorio mensal que nao trunca
-- =============================================================================
-- O gerarRelatorioMensal() do cantina.js vai buscar TODAS as reservas ativas e
-- soma-as no browser. O PostgREST corta a resposta nas 1000 linhas por omissao.
--
-- VERIFICADO em 2026-08-09, nao suspeitado: a consulta do relatorio devolveu
-- exatamente 1000 linhas, havendo 1195 reservas. O Excel ja anda a perder alunos
-- e ninguem deu por isso, porque um ficheiro com menos linhas nao tem ar de
-- estar errado. Com carga a serio um mes sao ~8000 reservas, e o relatorio
-- apanhava um oitavo delas.
--
-- A correcao e pedir a soma a base de dados: uma linha por aluno, no maximo
-- umas duas centenas, e o limite deixa de poder chegar la.
--
-- O COUNT(*) leva ::int de propria vontade. O COUNT devolve bigint, e um
-- RETURNS TABLE que declare integer da erro 42804 - mas SO quando ha linhas para
-- devolver. Foi exatamente isto que partiu o listar_solicitacoes_pendentes e que
-- so apareceu quando um teste criou linhas primeiro. Nao repetir.
--
-- Nome novo, e nao o gerar_relatorio_mensal que o PASSO 1 largou: um nome novo
-- nao pode colidir com uma sobrecarga esquecida, que foi a armadilha da 005.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.relatorio_mensal(p_ano integer, p_mes integer)
RETURNS TABLE(nome text, total_refeicoes integer, total_valor numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode gerar relatorios';
  END IF;

  RETURN QUERY
  SELECT a.nome,
         count(*)::int         AS total_refeicoes,
         sum(r.preco)::numeric AS total_valor
  FROM reservas r
  JOIN alunos a ON a.id = r.aluno_id
  WHERE r.ativa
    AND EXTRACT(YEAR  FROM r.data)::int = p_ano
    AND EXTRACT(MONTH FROM r.data)::int = p_mes
  GROUP BY a.nome
  ORDER BY a.nome;
END; $fn$;

REVOKE EXECUTE ON FUNCTION public.relatorio_mensal(integer, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.relatorio_mensal(integer, integer) TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO DOS PASSOS 3 E 4
-- =============================================================================
-- 1) As duas existem e correm com os direitos de quem as criou:
--
--   SELECT proname, prosecdef, pg_get_function_identity_arguments(oid)
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('purgar_reservas_liquidadas','relatorio_mensal');
--
--   Esperado: duas linhas, prosecdef = t nas duas.
--
-- 2) O anon e o PUBLIC nao chegam la:
--
--   SELECT proname, proacl
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('purgar_reservas_liquidadas','relatorio_mensal');
--
--   Esperado: sem `anon=` e SEM a entrada vazia `=X/postgres`, que e a do PUBLIC
--   e e a que se esquece.
--
-- 3) A purga respeita o rasto (o teste do tier B faz isto, mas a mao):
--
--   BEGIN;
--     SELECT * FROM purgar_reservas_liquidadas(CURRENT_DATE - INTERVAL '1 year');
--   ROLLBACK;
--
--   Esperado: uma linha com apagadas e preservadas. Nao pode dar erro de chave
--   estrangeira - se der, o NOT EXISTS do DELETE nao esta a funcionar.
--   (Correr como a cantina; em SQL editor com o papel postgres o auth.uid() e
--   NULL e a verificacao de staff recusa, o que tambem e o comportamento certo.)
-- =============================================================================
