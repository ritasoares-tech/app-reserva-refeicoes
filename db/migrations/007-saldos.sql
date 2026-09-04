-- =============================================================================
-- 007 - Saldos agregados na base de dados (Cluster 7, correcao pos-validacao)
-- =============================================================================
-- DEPENDE DA 001 (a coluna gerada `ativa`).
--
-- Terceira e ultima aparicao do mesmo defeito, todas encontradas no mesmo dia:
--
--   1. O relatorio mensal (corrigido pela 006, PASSO 4).
--   2. A lista do Historico de Aluno (corrigida so no JS, porque essa lista pode
--      vir da tabela alunos e passa a crescer com os alunos e nao com as
--      refeicoes).
--   3. Os Valores Pendentes - este ficheiro.
--
-- O padrao e sempre o mesmo: o ecra ia buscar a tabela reservas INTEIRA e fazia
-- a conta no browser. O PostgREST corta a resposta nas 1000 linhas por omissao.
-- Medido na copia: 1195 reservas, chegavam 1000.
--
-- ESTE E O PIOR DOS TRES, porque nao esconde apenas linhas - da NUMEROS ERRADOS.
-- Os alunos que ficavam de fora do corte apareciam sem divida nenhuma, e o aluno
-- que calhava estar em cima do corte aparecia com parte da divida dele. Tudo em
-- silencio: nao ha erro, nao ha aviso, so ha valores mais baixos do que a
-- realidade. E isto e a lista pela qual a cantina cobra.
--
-- Sao dois sitios no JS com a mesma consulta copiada: o ecra (showCantinaSaldos)
-- e o Excel (exportarSaldosExcel). Passam os dois a usar esta funcao.
--
-- -----------------------------------------------------------------------------
-- O QUE ESTA FUNCAO NAO FAZ
-- -----------------------------------------------------------------------------
-- Nao muda o significado de "divida". Reproduz exatamente a conta que o JS ja
-- fazia: soma o preco de todas as reservas ativas do aluno, de qualquer mes.
--
-- Existe uma definicao mais elaborada no obter_divida_por_mes, que le os meses
-- correntes e futuros das reservas e os meses passados do livro-razao. Trocar
-- uma pela outra mudava os valores cobrados e NAO e uma correcao de defeito - e
-- uma decisao, e nao e nossa. Isto aqui corrige o truncamento e mais nada.
--
-- So aparecem alunos COM reservas ativas, tal como antes: o mapa do JS nascia
-- das proprias reservas, por isso um aluno sem reservas nunca aparecia na lista.
--
-- O COUNT(*) leva ::int de propria vontade: bigint contra um integer declarado
-- da 42804, e so quando ha linhas para devolver. Ja partiu o
-- listar_solicitacoes_pendentes uma vez.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.saldos_por_aluno()
RETURNS TABLE(id uuid, nome text, total numeric, refeicoes integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE cantina.id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode ver os valores pendentes';
  END IF;

  RETURN QUERY
  SELECT a.id,
         a.nome,
         sum(r.preco)::numeric AS total,
         count(*)::int         AS refeicoes
  FROM reservas r
  JOIN alunos a ON a.id = r.aluno_id
  WHERE r.ativa
  GROUP BY a.id, a.nome
  ORDER BY a.nome;
END; $fn$;

-- A licao da 004, 005 e 006 aplicada a nascenca: EXECUTE para o PUBLIC e uma
-- concessao separada do anon e do authenticated.
REVOKE EXECUTE ON FUNCTION public.saldos_por_aluno() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.saldos_por_aluno() TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO
-- =============================================================================
-- 1) Existe, e corre com os direitos de quem a criou:
--
--   SELECT proname, prosecdef FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace AND proname = 'saldos_por_aluno';
--   Esperado: uma linha, prosecdef = t.
--
-- 2) O anon e o PUBLIC nao chegam la:
--
--   SELECT proname, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace AND proname = 'saldos_por_aluno';
--   Esperado: sem `anon=` e sem a entrada vazia `=X/postgres`, que e a do PUBLIC.
--
-- 3) A conta bate certo com a antiga, feita a mao sobre a tabela toda:
--
--   SELECT count(*) AS alunos, sum(total) AS soma FROM saldos_por_aluno();
--   SELECT count(DISTINCT aluno_id) AS alunos, sum(preco) AS soma
--   FROM reservas WHERE ativa;
--
--   Esperado: as duas linhas iguais. (Correr como a cantina; com o papel
--   postgres o auth.uid() e NULL e a verificacao de staff recusa - o que
--   tambem e o comportamento certo.)
--
-- Na suite: "the balances list shows what each student owes" continua verde, e
-- o teste novo confirma que a lista tem uma linha por aluno mesmo com mais de
-- 1000 reservas na tabela.
-- =============================================================================
